`timescale 1ns/1ps

module Accelerator_Top_tb;
// DUT parameters
localparam int ACT_W             = 8;
localparam int WGT_W             = 8;
localparam int BIAS_W            = 8;
localparam int NUM_PE            = 5;
localparam int NUM_LAYERS        = 4;

localparam int INPUT_LAYER_SIZE  = 784;
localparam int LAYER1_SIZE       = 40;
localparam int LAYER2_SIZE       = 30;
localparam int OUTPUT_LAYER_SIZE = 10;
localparam int MAX_LAYER_SIZE    = 784;

localparam int ACT_RAM_DEPTH     = MAX_LAYER_SIZE;
localparam int WGT_RAM_DEPTH     = 6572;
localparam int BIAS_RAM_DEPTH    = 16;

localparam string INPUT_ACTIVATIONS = "A_random.mem";

// DUT I/O signals 
// todo Presuming FPGA synthesis (and P&R) works (big IF), I expect to tie i_start to FPGA button (debounced), probably an LED to o_done, and o_out_data to 7S display (to show prediction)
logic i_clk;
logic i_rst;
logic i_start;

logic [ACT_W-1:0] o_out_data;
logic             o_out_valid;
logic             o_done;

// Instantiating DUT
Accelerator_Top #(
    .ACT_W(ACT_W),
    .WGT_W(WGT_W),
    .BIAS_W(BIAS_W),
    .NUM_PE(NUM_PE),
    .NUM_LAYERS(NUM_LAYERS),
    .INPUT_LAYER_SIZE(INPUT_LAYER_SIZE),
    .LAYER1_SIZE(LAYER1_SIZE),
    .LAYER2_SIZE(LAYER2_SIZE),
    .OUTPUT_LAYER_SIZE(OUTPUT_LAYER_SIZE),
    .MAX_LAYER_SIZE(MAX_LAYER_SIZE),
    .ACT_RAM_DEPTH(ACT_RAM_DEPTH),
    .WGT_RAM_DEPTH(WGT_RAM_DEPTH),
    .BIAS_RAM_DEPTH(BIAS_RAM_DEPTH),
    .INPUT_ACTIVATIONS(INPUT_ACTIVATIONS)
) dut (
    .i_clk(i_clk),
    .i_rst(i_rst),
    .i_start(i_start),
    .o_out_data(o_out_data),
    .o_out_valid(o_out_valid),
    .o_done(o_done)
);

// creating clock
initial i_clk = 0;
always #5 i_clk = ~i_clk;

initial begin
end


endmodule