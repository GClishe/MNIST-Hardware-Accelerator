`timescale 1ns/1ps

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
    output logic [15:0] o_wgt_idx         // address for weight memory from which we read during MAC
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

                    r_curr_state <= S_BIAS;
                end
                else begin
                    // Advance to next activation for next cycle's MAC
                    r_MAC_counter <= r_MAC_counter + 1'b1;
                    r_in_idx      <= r_in_idx + 1'b1;
                end
            end
            S_BIAS: begin
                
            end       
            S_ACTIVATE: begin
                
            end   
            S_STORE: begin
                
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

endmodule