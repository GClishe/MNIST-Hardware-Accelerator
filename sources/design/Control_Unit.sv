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



endmodule