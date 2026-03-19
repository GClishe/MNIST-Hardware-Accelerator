`timescale 1ns/1ps

/*
This module seeks to implement a parallel -> series converter with a simple shift register.

It will take the activations computed from process engines as an input and will output only one of them at a time.
The top module will then direct the outputs to a particular activation RAM 
*/

module Parallel_Series_Converter (
    parameter NUM_PE,
    parameter ACT_W
) (
    input logic i_clk,
    input logic i_rst,
    input logic [ACT_W-1:0] i_activations [0:NUM_PE-1],       // input array for activations with width ACT_W and depth NUM_PE, since that is the amount of activations computed at a time
    input logic [NUM_PE-1:0] i_PE_valid,                    // the o_out_valid signals from each process engine
    input logic i_shifting_valid,                           // high when the machine should be shifting out
    output logic [ACT_W-1:0] o_activation,                    // output activation. Not an array because outputs are passed serially. 
    output logic o_activation_valid                         // indicating the output value is valid and should be read. liekly connected to write enable on the 2-port RAM

);

logic [ACT_W-1:0] r_main [0: NUM_PE-1]; 
logic [$clog2(NUM_PE+1)-1:0] count;         // counter to avoid shifting when there is nothing in the register

always_ff @(posedge i_clk) begin
    if (i_rst) begin
        o_activation <= '0;
        o_activation_valid <= 1'b0;
        count <= '0;
        for (int i = 0; i < NUM_PE; i++) begin
            r_main[i] <= '0;
        end
    end
    else if (&i_PE_valid) begin  // checking if all bits in i_PE_valid are 1. in which case, we are writing to the register. note that this will cause data overwriting if these signals are high for more than 1 cycle
        r_main <= i_activations;       // load the register
        count <= NUM_PE;
        o_activation_valid  <= 1'b0;
    end
    else if (i_shifting_valid && (count > 0)) begin
        count <= count - 1;
        o_activation <= r_main[0];
        o_activation_valid <= 1'b1;
        for (int i = 0; i < NUM_PE-1; i++) begin
            r_main[i] <= r_main[i+1];               // shifting data toward lower indices
        end
        r_main[NUM_PE-1] <= '0;;
    end
    else begin
        o_activation_valid <= 1'b0;
    end

end
endmodule 