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
    parameter int NUM_MACS = 784,                        // number of MAC operations in the dot product. Used to determine ACC_W 

    // fixed point format parameters
    // all non-sign bits are fractional:
    // activations: unsigned Q0.8
    // weights/biases: signed Q1.7
    parameter int ACT_FRAC = 8,
    parameter int WGT_FRAC = 7,
    parameter int BIAS_FRAC = 7
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

// i_act_in has ACT_FRAC fractional bits
// i_wgt_in has WGT_FRAC fractional bits
// therefore, the raw product has PROD_FRAC fractional bits
localparam int PROD_FRAC = ACT_FRAC + WGT_FRAC;

// output has same fractional format as activations
localparam int OUT_FRAC = ACT_FRAC;

// to convert accumulator/product scale back into activation scale, we shift right by RESCALE_SHIFT bits
localparam int RESCALE_SHIFT = PROD_FRAC - OUT_FRAC;

// bias must also be aligned to accumulator/product scale before additional
localparam int BIAS_ALIGN_SHIFT = PROD_FRAC - BIAS_FRAC;

localparam int MULT_W = ACT_W + WGT_W + 1;                // width of multiplier. adding 1 because casting unsigned i_act_in to signed requires additional bit
localparam int W1 = MULT_W + $clog2(NUM_MACS);            // potential width of the accumulator 
localparam int W2 = BIAS_W + ((BIAS_ALIGN_SHIFT > 0) ? BIAS_ALIGN_SHIFT : 0);
localparam int ACC_W = ((W1 > W2) ? W1 : W2) + 1;         // Accumulator width depends on how large the bias width is relative to the rest. If bias width dominates, it determines the accumulator width. 


localparam logic [ACT_W-1:0] MAX_ACT = {ACT_W{1'b1}};     // the maximum possible magnitude of an ACT_W-sized unsigned integer. {N{val}} concatenates val with itself N times
       
logic signed [ACC_W-1: 0] r_acc;                 // accumulator 
logic signed [MULT_W-1:0] r_mult_val;            // value from the multiplier
logic signed [ACC_W-1:0]  r_mult_val_resized;    // same as above, but resized for safe accumulations
logic signed [ACC_W-1:0]  r_bias_resized;        // sign-extended bias before scaling
logic signed [ACC_W-1:0]  r_bias_aligned;        // bias aligned to accumulator/product fractional scale
logic signed [ACC_W-1:0]  r_acc_rescaled;        // accumulator converted back to activation scale for RELU/clamp

assign r_mult_val     = $signed({1'b0, i_act_in}) * i_wgt_in;                     // prepend 0 to i_act_in, then cast to a signed integer. Both operands must be signed in order for the result to also be signed. Needs the additional bit to preserve magnitude
assign r_mult_val_resized = {{ (ACC_W-MULT_W){r_mult_val[MULT_W-1]}}, r_mult_val}; // Sign-extend r_mult_val by prepending the sign bit ACC_W - MULT_W times, until r_mult_val has the same size as acc.
assign r_bias_resized = {{(ACC_W-BIAS_W){i_bias_in[BIAS_W-1]}}, i_bias_in};        // sign-extend bias to ACC_W

generate    // generate allows me to perform conditional assignments outside of any kind of combinational or sequential block
    // left or right shift the bias value depending on sign of BIAS_ALIGN_SHIFT
    if (BIAS_ALIGN_SHIFT >= 0) begin : GEN_BIAS_LEFT_SHIFT
        assign r_bias_aligned = (r_bias_resized <<< BIAS_ALIGN_SHIFT);    
    end
    else begin : GEN_BIAS_RIGHT_SHIFT
        assign r_bias_aligned = (r_bias_resized >>> (-BIAS_ALIGN_SHIFT));
    end
endgenerate

generate
    if (RESCALE_SHIFT >= 0) begin : GEN_RESCALE_RIGHT_SHIFT
        // Convert accumulator/product scale back to activation scale.
        assign r_acc_rescaled = (r_acc >>> RESCALE_SHIFT);
    end
    else begin : GEN_RESCALE_LEFT_SHIFT
        assign r_acc_rescaled = (r_acc <<< (-RESCALE_SHIFT));
    end
endgenerate

always_ff @(posedge i_clk) begin
    // handle reset logic
    if (i_rst) begin 
        r_acc <= '0;                              // fills the accumulator with 0s
        o_result <= '0;     
        o_out_valid <= 0;                   
    end

    else begin
        o_out_valid <= 1'b0;    // default state of out_valid. Will be overwritten if necessary

        // if we want to start a new dot product, we need to clear the accumulator, which we want to control with a separate signal from the global reset
        if (i_clear_acc) begin
            r_acc <= '0;  // fill the accumulator with 0s    
            o_result <= '0;
            o_out_valid <= 0;     
        end

        // if we want a MAC operation to take place, we need the i_mac_en signal to be high
        else if (i_mac_en) begin
            r_acc <= r_acc + r_mult_val_resized;
        end

        // when the MAC is done with a dot product, the accumulator needs to add a bias 
        else if (i_bias_en) begin
            // bias must be aligned to same fractional scale as accumulator before addition
            r_acc <= r_acc + r_bias_aligned;  
        end
        
        // after bias is applied, the RELU will be activated, and positive numbers above 8 bits will be clamped to 8'b11111111
        else if (i_apply_act) begin
            // r_acc is still in the grown fixed point format from the MAC. It must be converted back to activation scale before RELU/clamping/writeback
            if (r_acc_rescaled < 0) begin
                o_result <= '0;
            end
            else begin
                if (r_acc_rescaled > $signed({1'b0, MAX_ACT})) begin
                    o_result <= MAX_ACT;
                end
                else begin
                    o_result <= r_acc_rescaled[ACT_W-1:0]; // take the least significant ACT_W bits after rescaling, since we know the full value can fit into that many bits.   
                end
            end
            o_out_valid <= 1'b1;
        end
    end
end


endmodule 
