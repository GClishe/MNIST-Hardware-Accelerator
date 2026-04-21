`timescale 1ns/1ps

module Accelerator_Top_tb;

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



endmodule