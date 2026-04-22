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

// CU probes
logic [3:0] cu_current_state;                                        // probe for current state of state machine
logic [ACT_W-1:0] act_ram1_probe [0:39];                             // probe for contents of activation RAM 1
logic [ACT_W-1:0] act_ram2_probe [0:29];
logic [ACT_W-1:0] act_ram3_probe [0:9];

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

assign cu_current_state = dut.cu_current_state;

// assigning elements in activation memory probe to corresponding locations in activation RAMs.
genvar addr_p;
generate
    for (addr_p = 0; addr_p < ACT_RAM_DEPTH; addr_p++) begin : g_act_ram_probes
        //act_ram_probe[addr_p] assigned to activation RAM data at location addr_p
        // dut.g_act_ram[lyr_p] indexes the generate for loop inside the accelerator_top module that is used to instantiate the RAM_2Port module.
        // At the loop location named dut.g_act_ram[lyr], we have instantiated a corresponding RAM_2Port instance named u_act_ram (see Accelerator_Top.sv).
        // Inside the instance named u_act_ram in the lyr iteration of the for loop, there exists an internal signal called mem (see RAM_2Port.sv)
        // We want to access the value at the addr_p index of that internal `mem` signal. 
        // NOTE: THIS IS NOT READING DATA THROUGH THE RAM INTERFACE. THIS IS DIRECTLY PROBING THE INTERNAL STRUCTURE OF THE RAM_2Port INSTANCE
        assign act_ram1_probe[addr_p] = dut.g_act_ram[1].u_act_ram.mem[addr_p];
        assign act_ram2_probe[addr_p] = dut.g_act_ram[2].u_act_ram.mem[addr_p];
        assign act_ram3_probe[addr_p] = dut.g_act_ram[3].u_act_ram.mem[addr_p];
    end
endgenerate


// creating clock
initial i_clk = 0;
always #5 i_clk = ~i_clk;

initial begin
//resetting 
i_start = 1'b0;
i_rst = 1'b1;
repeat (2) @(posedge i_clk);
i_rst = 1'b0;
repeat (5) @(negedge i_clk);

// rasing start flag
i_start = 1'b1; // causing i_start transition on negedge for sake of clarity
@(negedge i_clk);
 i_start = 1'b0;


repeat (500) @(posedge i_clk);
$finish;
end


endmodule