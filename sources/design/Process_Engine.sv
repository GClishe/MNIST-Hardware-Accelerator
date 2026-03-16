`timescale 1ns/1ps

/*
The specifications sheet has the following information for the MAC module: 

- Process Engine Array:
        * Performs the core arithmetic. Contains MAC logic and activation function (TBD) logic 
        * Executes instructions with SIMD process flow. All PEs receive the same control signals from the control bus simultaneously
        * Expected ports: Clock, reset, ACT_IN (activation input), WGT_IN (weight input), MAC_EN (enable accumulation), APPLY_ACT (trigger the activation function), RESULT_OUT


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
    input  logic                        clk,
    input  logic                        rst,
    input  logic [ACT_W-1 : 0]          ACT_IN,        // input activation (unsigned, since RELU annihilates sign even if MAC output is negative)
    input  logic signed [WGT_W-1 : 0]   WGT_IN,        // input weight. Signed
    input  logic signed [BIAS_W-1: 0]   BIAS_IN,
    input  logic                        clear_acc,     // signal that clears accumulator 
    input  logic                        MAC_EN,        // enables MAC operation. must stay high for every clock cycle in which MAC is desired
    input  logic                        BIAS_EN,       // enables bias
    input  logic                        APPLY_ACT,     // enables activation function (RELU)
    output logic [ACT_W-1 : 0]          RESULT_OUT,    // the activation that was computed and applied to activation. Unsigned. Needs the same signed-ness as ACT_IN
    output logic                        OUT_VALID      // flag that is raised when the output can and should be read
);


localparam int MULT_W = ACT_W + WGT_W + 1;                // the width of the multiplier. Adding a 1 because casting unsigned ACT_IN to signed ACT_IN requires an additional bit. 
localparam int ACC_W = MULT_W + $clog2(NUM_MACS);         // width of the accumulator. Depends on the width of the multiplication products and the number of such products being accumulated.
localparam logic [ACT_W-1:0] MAX_ACT = {ACT_W{1'b1}};     // the maximum possible magnitude of an ACT_W-sized unsigned integer. {N{val}} concatenates val with itself N times
       
logic signed [ACC_W-1: 0] acc;                // accumulator 
logic signed [ACC_W-1:0] max_act_resized;     // same magnitude as MAX_ACT, but it needs to be resized to the size of the accumulator for safe comparisons later on
logic signed [MULT_W-1:0] mult_val;           // value from the multiplier
logic signed [ACC_W-1:0]  mult_val_resized;   // same as above, but resized for safe accumulations

assign max_act_resized = $signed({{(ACC_W-ACT_W){1'b0}}, MAX_ACT});         // create a set of 0s ACC_W - ACT_W bits wide. Then prepend that to the MAX_ACT value, and cast it to a signed format.
assign mult_val     = $signed({1'b0, ACT_IN}) * WGT_IN;                     // prepend 0 to ACT_IN, then cast to a signed integer. Both operands must be signed in order for the result to also be signed. Needs the additional bit to preserve magnitude
assign mult_val_resized = {{(ACC_W-MULT_W){mult_val[MULT_W-1]}}, mult_val}; // Sign-extend mult_val by prepending the sign bit ACC_W - MULT_W times, until mult_val has the same size as acc.

always_ff @(posedge clk) begin
    // handle reset logic
    if (rst) begin 
        acc <= '0;                              // fills the accumulator with 0s
        RESULT_OUT <= '0;     
        OUT_VALID <= 0;                   
    end

    else begin
        // if we want to start a new dot product, we need to clear the accumulator, which we want to control with a separate signal from the global reset
        if (clear_acc) begin
            acc <= '0;  // fill the accumulator with 0s    
            RESULT_OUT <= '0;
            OUT_VALID <= 0;     
        end

        // if we want a MAC operation to take place, we need the MAC_EN signal to be high
        else if (MAC_EN) begin
            acc <= acc + mult_val_resized;
            OUT_VALID <= 0;
        end

        // when the MAC is done with a dot product, the accumulator needs to add a bias 
        else if (BIAS_EN) begin
            // acc, BIAS_IN are of unequal widths. BIAS_IN is narrower, so I extend it to the size of ACC_W. I do this by prepending the sign of BIAS_IN ACC_W - BIAS_W times. 
            acc <= acc + {{(ACC_W-BIAS_W){BIAS_IN[BIAS_W-1]}}, BIAS_IN};   
            OUT_VALID <= 0;
        end
        
        // after bias is applied, the RELU will be activated, and positive numbers above 8 bits will be clamped to 8'b11111111
        else if (APPLY_ACT) begin
            if (acc < 0) begin
                RESULT_OUT <= '0;
                OUT_VALID <= 1;
            end
            else begin
                if (acc > max_act_resized) begin
                    RESULT_OUT <= MAX_ACT;
                    OUT_VALID <= 1;
                end
                else begin
                    RESULT_OUT <= acc[ACT_W-1:0]; // take the least significant bits of acc, since we know the full value can fit into that many bits.  
                    OUT_VALID <= 1;
                end
            end
        end
    end
end


endmodule 
