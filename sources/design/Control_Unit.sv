`timescale 1ns/1ps

module Control_Unit # (
    parameter int ACT_W = 8,      // size of the activations
    parameter int WGT_W = 8,      // size of the weights
    parameter int BIAS_W = 8      // size of the bias

) (
    input clk,
    input rst,
    input OUT_VALID,            // signal from PE indicating completion of MAC, bias, and RELU. PE output should be read only when OUT_VALID is high

    // control signals for process engines
    output clear_acc,   // clear accumulator
    output MAC_EN,      // enable MAC operation
    output BIAS_EN,     // enables bias computation
    output APPLY_ACT,   // applies RELU and clamps accumulator output (after biasing) to 8 bits unsigned. 
);

typedef enum logic [2:0] {          // defines a named type `state`, encoded in 3 bits
        S_IDLE  = 3'd0,             // waiting for start signal
        S_MAC  = 3'd1,              // Enabling PE MAC units and fetching weights and activations from memory
        S_ACTIVATE = 3'd2           // Applying activation function
        S_STORE  = 3'd3             // Writing results back to memory or outputs
    } state_t;

state_t state;  // declaring state variable with type state_t


endmodule