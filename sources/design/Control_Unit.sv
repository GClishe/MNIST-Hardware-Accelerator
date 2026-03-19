`timescale 1ns/1ps

module Control_Unit # (
    parameter int ACT_W = 8,      // size of the activations
    parameter int WGT_W = 8,      // size of the weights
    parameter int BIAS_W = 8,      // size of the bias
    parameter int NUM_PE = 4

) (
    input i_clk,
    input i_rst,
    input i_out_valid,            // signal from PE indicating completion of MAC, bias, and RELU. PE output should be read only when OUT_VALID is high

    // control signals for process engines
    output o_clear_acc,     // clear accumulators
    output o_mac_en,        // enable MAC operation
    output o_bias_en,       // enables bias computation
    output o_apply_act,     // applies RELU and clamps accumulator output (after biasing) to 8 bits unsigned. 
    output o_current_state  // signal for top module. describes what state the machine is currently in 
);

typedef enum logic [3:0] {          // defines a named type `state`, encoded in 4 bits
        S_START         = 4'd0,     // start state. begin here
        S_CLEAR         = 4'd1,     // broadcasts reset signal to PEs. Also resets all counters 
        S_IDLE          = 4'd2,     // Select layer index 0 so that LOAD_MEM will load input activations. When input activations done loading in memory, advance to LOAD_MEM
        S_LOAD_MEM      = 4'd3,     // activations from layer index are loaded to registers near process engines, and biases are loaded to the back of these registers
        S_MAC           = 4'd4,     // MAC operation commences
        S_BIAS          = 4'd5,     // BIAS operation
        S_ACTIVATE      = 4'd6,     // actiavtion operation
        S_STORE         = 4'd7,     // activations stored to memory at layer index i+1. Parallel -> serial conversion so that activations stored in correct order
        S_ADVANCE_TILE  = 4'd8,     // if the activations stored in layer i+1 is less than the number expected, advance the tile (do NOT increment layer index) and proceed to LOAD_MEM
        S_ADVANCE_LAYER = 4'd9,     // if activations store in layer i+1 is equal to number expected, advance layer (increment layer index) and proceed to LOAD_MEM
        S_BROADCAST     = 4'd10     
    } state_t;

state_t r_curr_state;  // declaring r_state register with type state_t

always_ff @(posedge i_clk) begin

    if (i_rst == 1) begin
        // Put reset logic here
    end
    else begin
        // state machine core logic goes here
        case (r_curr_state)
            S_START:
            S_CLEAR:
            S_IDLE         
            S_LOAD_MEM:     
            S_MAC:          
            S_BIAS:         
            S_ACTIVATE:     
            S_STORE:        
            S_ADVANCE_TILE: 
            S_ADVANCE_LAYER:
            S_BROADCAST:   
        endcase
    end

end

assign o_current_state <= r_curr_state;         // o_current_state asynchonously tied to r_curr_state

endmodule