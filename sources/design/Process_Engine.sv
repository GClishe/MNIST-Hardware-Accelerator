`timescale 1ns/1ps

/*
The specifications sheet has the following information for the MAC module: 

- Process Engine Array:
        * Performs the core arithmetic. Contains MAC logic and activation function (TBD) logic 
        * Executes instructions with SIMD process flow. All PEs receive the same control signals from the control bus simultaneously
        * Expected ports: Clock, reset, i_act_in (activation input), i_wgt_in (weight input), i_mac_en (enable accumulation), i_apply_act (trigger the activation function), o_result


The control unit fetches one activation (pixel) from the activation memory and broadcasts it to all PEs simulatenously. But each PE is responsible for a different output neuron, so they
all receive a different weight from the weight memory.

The math of the perceptron can be seen in the perceptron_matmul.png in this directory. 

Weights and activations are streamed into the process engine serially. The width of the accumulator depends on the number of MAC operations performed in a single dot product, but the result in the accumulator
after the RELU is clamped to the maximum value possible for a number of ACT_W bits if the accumulator value exceeds this threshold. 

Note that this module is not pipelined (for simplicity). This should be attempted if the 100MHZ clock frequency target is difficult to reach. 

*/

module Process_Engine # (
    // parameter list
    parameter int ACT_W = 8,
    parameter int WGT_W = 8,
    parameter int BIAS_W = 8,
    parameter int NUM_MACS = 784                        // number of MAC operations in the dot product. Used to determine ACC_W 
) (
    input  logic                        i_clk,
    input  logic                        i_rst,
    input  logic [ACT_W-1 : 0]          i_act_in,        // input activation (unsigned, since RELU annihilates sign even if MAC output is negative)
    input  logic signed [WGT_W-1 : 0]   i_wgt_in,        // input weight. Signed
    input  logic signed [BIAS_W-1: 0]   i_bias_in,
    input  logic                        i_clear_acc,     // signal that clears accumulator 
    input  logic                        i_mac_en,        // enables MAC operation. must stay high for every clock cycle in which MAC is desired
    input  logic                        i_bias_en,       // enables bias
    input  logic                        i_apply_act,     // enables activation function (RELU)
    output logic [ACT_W-1 : 0]          o_result,    // the activation that was computed and applied to activation. Unsigned. Needs the same signed-ness as i_act_in
    output logic                        o_out_valid      // flag that is raised when the output can and should be read
);


localparam int MULT_W = ACT_W + WGT_W + 1;                // the width of the multiplier. Adding a 1 because casting unsigned i_act_in to signed i_act_in requires an additional bit. 
localparam int ACC_W = MULT_W + $clog2(NUM_MACS);         // width of the accumulator. Depends on the width of the multiplication products and the number of such products being accumulated.
localparam logic [ACT_W-1:0] MAX_ACT = {ACT_W{1'b1}};     // the maximum possible magnitude of an ACT_W-sized unsigned integer. {N{val}} concatenates val with itself N times
       
logic signed [ACC_W-1: 0] r_acc;                // accumulator 
logic signed [ACC_W-1:0]  r_max_act_resized;     // same magnitude as MAX_ACT, but it needs to be resized to the size of the accumulator for safe comparisons later on
logic signed [MULT_W-1:0] r_mult_val;           // value from the multiplier
logic signed [ACC_W-1:0]  r_mult_val_resized;   // same as above, but resized for safe accumulations

assign r_max_act_resized = $signed({{(ACC_W-ACT_W){1'b0}}, MAX_ACT});         // create a set of 0s ACC_W - ACT_W bits wide. Then prepend that to the MAX_ACT value, and cast it to a signed format.
assign r_mult_val     = $signed({1'b0, i_act_in}) * i_wgt_in;                     // prepend 0 to i_act_in, then cast to a signed integer. Both operands must be signed in order for the result to also be signed. Needs the additional bit to preserve magnitude
assign r_mult_val_resized = {{(ACC_W-MULT_W){r_mult_val[MULT_W-1]}}, r_mult_val}; // Sign-extend r_mult_val by prepending the sign bit ACC_W - MULT_W times, until r_mult_val has the same size as acc.

always_ff @(posedge i_clk) begin
    // handle reset logic
    if (i_rst) begin 
        r_acc <= '0;                              // fills the accumulator with 0s
        o_result <= '0;     
        o_out_valid <= 0;                   
    end

    else begin
        // if we want to start a new dot product, we need to clear the accumulator, which we want to control with a separate signal from the global reset
        if (i_clear_acc) begin
            r_acc <= '0;  // fill the accumulator with 0s    
            o_result <= '0;
            o_out_valid <= 0;     
        end

        // if we want a MAC operation to take place, we need the i_mac_en signal to be high
        else if (i_mac_en) begin
            r_acc <= r_acc + r_mult_val_resized;
            o_out_valid <= 0;
        end

        // when the MAC is done with a dot product, the accumulator needs to add a bias 
        else if (i_bias_en) begin
            // acc, i_bias_in are of unequal widths. i_bias_in is narrower, so I extend it to the size of ACC_W. I do this by prepending the sign of i_bias_in ACC_W - BIAS_W times. 
            r_acc <= r_acc + {{(ACC_W-BIAS_W){i_bias_in[BIAS_W-1]}}, i_bias_in};   
            o_out_valid <= 0;
        end
        
        // after bias is applied, the RELU will be activated, and positive numbers above 8 bits will be clamped to 8'b11111111
        else if (i_apply_act) begin
            if (acc < 0) begin
                o_result <= '0;
                o_out_valid <= 1;
            end
            else begin
                if (r_acc > r_max_act_resized) begin
                    o_result <= MAX_ACT;
                    o_out_valid <= 1;
                end
                else begin
                    o_result <= r_acc[ACT_W-1:0]; // take the least significant bits of r_acc, since we know the full value can fit into that many bits.  
                    o_out_valid <= 1;
                end
            end
        end
    end
end


endmodule 
