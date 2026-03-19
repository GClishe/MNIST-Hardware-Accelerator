`timescale 1ns/1ps

/*
The key to understanding this code below absolutely requires an understanding of how the memory banks are split up, so consider the following situation: Suppose we have a source layer 
that has 10 activations, a_0 thru a_9, and a destination layer that has 13 neurons y_0 thru y_12. We have 4 process engines, one activation RAM for the source layer, 4 weight RAMs (one for 
each process engine), and 4 bias RAMs (one for each process engine). Thus, each tile has a size of 4. The final tile is padded with 0s when corresponding process engines should not be producing a result
that is read to memory (note: this will occur, since tile 0 will compute activations y0 thru y3, tile 1 will compute y4 thru y7, tile 2 will compute y8 thru y11, and tile 3 will compute y12. The other
three process engines cannot be inactive in tile 3 due to SIMD architecture, so whatever it computes will not be written to the destination layer's RAM. We want to use the same weight and bias address for
all four PEs at all times, so we need to pad the weight RAMs with 0s in locations where we would otherwise prefer to have the PEs inactive). The following vectors represent the contents of all RAMs under the
scenario outlined above: 

ACT_RAM  = [a0, a1, a2, a3, a4, a5, a6, a7, a8, a9]

WGT_RAM0 = [weights of neuron 0][weights of neuron 4][weights of neuron 8][weights of neuron 12]      <-- NOTICE no padding in last tile; PE0 will be computing y12,
WGT_RAM1 = [weights of neuron 1][weights of neuron 5][weights of neuron 9][0...0]                     <-- NOTICE the last tile is padded with 0s, since PE 1 will not be computing anything useful (there is no y13)
WGT_RAM2 = [weights of neuron 2][weights of neuron 6][weights of neuron 10][0...0]                    <-- NOTICE the last tile is padded with 0s, since PE 2 will not be computing anything useful (there is no y14)
WGT_RAM3 = [weights of neuron 3][weights of neuron 7][weights of neuron 11][0...0]                    <-- NOTICE the last tile is padded with 0s, since PE 3 will not be computing anything useful (there is no y15)

BIAS_RAM0 = [b0, b4, b8,  b12]
BIAS_RAM1 = [b1, b5, b9,  0]            <-- NOTICE biases are similarly padded with 0s
BIAS_RAM2 = [b2, b6, b10, 0]
BIAS_RAM3 = [b3, b7, b11, 0]

Note that the WGT RAMs show four separate arrays in the example above; that is erroneous. I only separated them into different sets of brackets for the sake of readability. All banks would store these values
contiguously. Also note that our example will have more layers after the y layer. The ACT_RAM for the next stage would then be the vector [y0 thru y12]. However, the WGT and BIAS RAMs would be the same! It's just
that for these RAMs, the weights for the next layer would be placed after the weights shown above. This means that we will have WGT RAMs that look something like
[weights of neuron i]...[weights of neuron j][0...0][weights of neuron k][weights of neuron l][0..0].

Notice that the 0 padding for each layer still comes before the weights of the next layer. This is necessary for us to be able to share the same RAM address for all WGT RAMs. 

In terms of how that address is determined, it is easy to see that since the activations are a different vector for each layer, the address will always start at 0 for a layer and increment until all values in ACT_RAM
have been read, at which point we know that the layer is done. Nothing special there. However, the WGT RAM is slighly more complex. Let's look at WGT_RAM0 as an example. For the first layer and first tile, (each set of square brackets represents a new tile) the base address is 0. But then when its time to compute the second tile, the base address needs to be tile_idx (1) * LAYER1_LENGTH (10). This is why the S_LOAD_MEM state 
sets a base weight address to tile_idx*LAYER_SIZE. The bias base address is a little easier, since each MAC cycle only uses one bias. In other words, there is only one bias per tile. This means we can use the tile_idx as the bias address. Notice that o_bias_idx is asynchronously tied to r_tile_idx (in other words, they are two words for the same net).

*/


module Control_Unit # (
    parameter int ACT_W = 8,      // size of the activations
    parameter int WGT_W = 8,      // size of the weights
    parameter int BIAS_W = 8,      // size of the bias
    parameter int NUM_PE = 4,      // number of process engines
    parameter int NUM_LAYERS = 4,     // number of neural network layers. Includes input, output, and hidden layers.

    // LAYER SIZES 
    parameter int INPUT_LAYER_SIZE = 784,   // number of activations in the input layer
    parameter int LAYER1_SIZE = 50,         // number of activations in the first hidden layer
    parameter int LAYER2_SIZE = 50,         // number of activations in the second hidden layer
    parameter int OUTPUT_LAYER_SIZE = 10    // number of activations in the output layer

) (
    input logic i_clk,
    input logic i_rst,                  // global reset. this triggers a reset in the CU, during which a reset is also applied to the PEs. o_rst is a local reset signal sent from the CU to the PE
    input logic i_out_valid,            // signal from PE indicating completion of MAC, bias, and RELU. PE output should be read only when OUT_VALID is high
    input logic i_activations_ready,    // signal broadcasted when input activation memory bank is full and ready to be broadcasted (causes transition from S_IDLE to S_LOAD_MEM)

    // control signals for process engines
    output logic o_rst,            // reset signal streamed from the CU to the process engines. Not same signal
    output logic o_clear_acc,     // clear accumulators
    output logic o_mac_en,        // enable MAC operation
    output logic o_bias_en,       // enables bias computation
    output logic o_apply_act,     // applies RELU and clamps accumulator output (after biasing) to 8 bits unsigned. 
    output logic [3:0] o_current_state,  // signal for top module. describes what state the machine is currently in 
    output logic [15:0] o_act_idx,        // address of activation memory (independent of which activation bank we are reading from) from which we read during MAC 
    output logic o_act_re,                // read enable for activation memory. Broadcast high during MAC state
    output logic o_wgt_re,                // read enable for weight memory
    output logic [15:0] o_wgt_idx,         // address for weight memory from which we read during MAC
    output logic o_bias_re,               // bias RAM read-enable
    output logic o_bias_idx               // bias RAM address (same for all biases)
);

typedef enum logic [3:0] {          // defines a named type `state`, encoded in 4 bits
        S_START         = 4'd0,     // start state. begin here
        S_CLEAR         = 4'd1,     // broadcasts reset signal to PEs. Also resets all counters 
        S_IDLE          = 4'd2,     // Select layer index 0 so that LOAD_MEM will load input activations. When input activations done loading in memory, advance to LOAD_MEM
        S_LOAD_MEM      = 4'd3,     // set/reset memory addresses for reading and writing
        S_BROADCAST     = 4'd4,     
        S_MAC           = 4'd5,     // MAC operation commences
        S_BIAS          = 4'd6,     // BIAS operation
        S_ACTIVATE      = 4'd7,     // actiavtion operation
        S_STORE         = 4'd8,     // activations stored to memory at layer index i+1. Parallel -> serial conversion so that activations stored in correct order
        S_ADVANCE_TILE  = 4'd9,     // if the activations stored in layer i+1 is less than the number expected, advance the tile (do NOT increment layer index) and proceed to LOAD_MEM
        S_ADVANCE_LAYER = 4'd10,     // if activations store in layer i+1 is equal to number expected, advance layer (increment layer index) and proceed to LOAD_MEM
        S_OUTPUT        = 4'd11
    } state_t;

state_t r_curr_state;                       // declaring r_state register with type state_t

logic [$clog2(NUM_LAYERS)-1:0] r_layer_idx; // signal used to determine which activation memory bank the PE will read from
logic [15:0] r_MAC_counter;                 // counts number of mac operations that have occured while in S_MAC state. Needs to be large enough to accomodate the max layer size (probably the input layer)

//TODO dynamically size the registers below. some of them depend on parameters not yet (as of 3/18) finalized, such as number of neurons in hidden layers
logic [15:0] r_tile_idx;                            
logic [15:0] r_in_idx;                              
logic [15:0] r_src_layer_sel;
logic [15:0] r_dst_layer_sel;
logic [15:0] r_num_inputs;
logic [15:0] r_num_outputs;
logic [15:0] r_store_base_idx;
logic [15:0] r_weight_base_idx;
logic [15:0] r_bias_base_idx;

always_ff @(posedge i_clk) begin

    if (i_rst == 1) begin
        r_curr_state <= S_START;
        r_layer_idx <= '0;       // this is technically not required because this value will be set anyways when we move to idle state, but it doesn't hurt either.
        r_MAC_counter <= '0;     // resetting the MAC counter to 0
        o_rst <= 1;             // when global reset is applied to control unit, the control unit will also broadcast a reset to the process engines
        o_mac_en <= 0;
    end
    else begin
        // state machine core logic goes here
        case (r_curr_state)
            S_START: begin
                r_curr_state <= S_CLEAR;
            end
            S_CLEAR: begin
                o_rst <= 1'b1;             // reset is broadcasted to all PEs
                r_curr_state <= S_IDLE;
            end
            S_IDLE: begin
                o_rst <= 1'b0;          // de-assert PE reset
                r_layer_idx <= '0;      // initializes r_layer_idx to 0 (the input activations) before moving to LOAD_MEM
                if (i_activations_ready == 1) begin
                    r_curr_state <= S_LOAD_MEM;       // moving to LOAD_MEM when the input activations have all been written into memory
                end
            end
            S_LOAD_MEM: begin
                // in this state, we prepare the next compute pass by resetting write and read addresses, selecting source/destination layers, and priming first activation read

                r_in_idx <= '0;         // reset the per-pass input counter so MAC starts at the first source activation. Remember that the same activation is sent to all PEs

                // defining source and destination layers. These values determine which RAM instance will be read from and written to, respectively
                r_src_layer_sel <= r_layer_idx;    
                r_dst_layer_sel <= r_layer_idx + 1;

                case (r_layer_idx)      
                    0: begin
                        r_num_inputs    <= INPUT_LAYER_SIZE;    // num of activations in the source layer (read by the PEs)
                        r_num_outputs   <= LAYER1_SIZE;         // number of outputs equals number of neurons in first hidden layer
                        r_weight_base_idx <= r_tile_idx * INPUT_LAYER_SIZE; // base address for the weight memories; depends on the tile
                    end

                    1: begin
                        r_num_inputs    <= LAYER1_SIZE;
                        r_num_outputs   <= LAYER2_SIZE; 
                        r_weight_base_idx <= r_tile_idx * LAYER1_SIZE;  
                    end     
                    2: begin
                        r_num_inputs    <= LAYER2_SIZE;
                        r_num_outputs   <= OUTPUT_LAYER_SIZE;   
                        r_weight_base_idx <= r_tile_idx * LAYER2_SIZE;
                    end 
                    default: begin
                        r_num_inputs  <= '0;
                        r_num_outputs <= '0;
                        r_weight_base_idx <= '0;
                    end     
                endcase
            
                /*We cannot always set the destination address (where we will write activations in S_STORE) to 0, since a single PE pass may not be enough to complete a layer. Remember
                that each layer is broken up into tiles. Suppose we have 4 PEs and we are trying to compute all 10 activations in the output layer. The first tile consists of 4 activations,
                since there are 4 PEs. For this first tile (r_tile_idx=0), we do want the base address for writing to be 0, since nothing has been written to the output layer yet. But after 
                this first pass, we still have 6 more activations to complete, so when the next batch of 4 activations is ready to store, they must not overwrite the activations we just computed.
                Thus, we need to store them such that the base address is 4 (so r_tile_idx=1 * NUM_PE=4 = 4). In other words, tile 1 will store activations at addresses 0, 1, 2, 3, then tile 2 will
                store activations at addresses 4, 5, 6, 7, then tile 3 will store activations at addresses 8, 9. The logic for disabling writing for the last two PEs on the last tile is not handled
                in this state.*/
                r_store_base_idx <= r_tile_idx * NUM_PE;    
                o_clear_acc <= 1'b1;    // clear accumulator for new dot product pass
                r_MAC_counter <= '0;    // reset MAC counter for new dot-product pass

                o_act_re <= 1'b1;   // priming activation RAM read. Since RAM is synchronous, the data for address 0 will not be available until the next clock cycle.
                o_wgt_re <= 1'b1;   // same for weight RAM read. 

                o_mac_en <= 1'b0;   // ensuring mac enable is not on yet

                r_curr_state <= S_BROADCAST; // move to broadcast state
            end 
            S_BROADCAST: begin
                // one-cycle state to prime the RAM. Address 0 was already presented during the last state and by the end of this cycle, the activation data for index 0 is available. same for the weight data
                o_clear_acc <= 1'b0;        // stop clearing accumulators now that the new pass is about to begin
                o_act_re <= 1'b1;           // keep activation read enable asserted so streaming can continue
                o_wgt_re <= 1'b1;           // same for wgt read enable
                o_mac_en <= 1'b1;       // enable MAC on next cycle so that MAC can begin as soon as we enter MAC state 
                r_curr_state <= S_MAC;  // move into the real MAC loop
            end
            S_MAC: begin
                // each cycle in this state corresponds to one multiply-accumulate
                // note that mac enable and activation read enable signals are still on from the broadcast state
            
                if (r_MAC_counter == r_num_inputs - 1'b1) begin
                    // perform the final MAC for the current dot product and move on to biasing
                    r_MAC_counter <= '0;
                    o_mac_en <= 1'b0;
                    o_act_re <= 1'b0;
                    o_wgt_re <= 1'b0;

                    o_bias_re  <= 1'b1;     // prime bias RAM for next cycle
                    r_curr_state <= S_BIAS;
                end
                else begin
                    // Advance to next activation for next cycle's MAC
                    r_MAC_counter <= r_MAC_counter + 1'b1;
                    r_in_idx      <= r_in_idx + 1'b1;
                    o_bias_re     <= 1'b0;              // keeping bias read enable low because we are not ready to prime the bias RAM yet.
                end
            end
            S_BIAS: begin
                o_mac_en    <= 1'b0;
                o_act_re    <= 1'b0;
                o_wgt_re    <= 1'b0;
                o_bias_re   <= 1'b0;  
                o_bias_en   <= 1'b1;
                r_curr_state <= S_ACTIVATE
            end       
            S_ACTIVATE: begin
                o_bias_en = 1'b0;
                o_apply_act = 1'b1;
                
                // it might be reasonable to only move states when the PE raises its o_out_valid flag, but currently this happens at the same time as o_apply_act, so I wont worry about this for now. 
                r_curr_state <= S_STORE;
            end   
            S_STORE: begin
                o_apply_act = 1'b0;
            end     
            S_ADVANCE_TILE: begin
                
            end
            S_ADVANCE_LAYER: begin
                
            end

            default: r_curr_state <= S_START;
        endcase
    end

end

assign o_current_state = r_curr_state;         // o_current_state asynchonously tied to r_curr_state
assign o_act_idx = r_in_idx;
assign o_wgt_idx = r_weight_base_idx + r_in_idx;    // address in weight memory where value is fixed depends on the weight base index (which itself depends on the tile index) and with r_in_idx
assign o_bias_idx = r_tile_idx;                     // address in bias memory

endmodule