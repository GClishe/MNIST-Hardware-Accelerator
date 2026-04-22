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

localparam string INPUT_ACTIVATIONS = "testImage_7_b.mem";

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
logic [ACT_W-1:0] act_ram0_probe [0:INPUT_LAYER_SIZE-1];             // probe for memory addresses for input activations
logic [ACT_W-1:0] act_ram1_probe [0:LAYER1_SIZE-1];
logic [ACT_W-1:0] act_ram2_probe [0:LAYER2_SIZE-1];
logic [ACT_W-1:0] act_ram3_probe [0:OUTPUT_LAYER_SIZE-1];
logic [WGT_W-1:0] wgt_ram1_probe [0:WGT_RAM_DEPTH-1];

// PE1 probes
logic signed [WGT_W-1:0] probe_pe0_wgt_in;
logic signed [BIAS_W-1:0] probe_pe0_bias_in;
logic signed [dut.g_pe[0].u_pe.ACC_W-1:0]  probe_pe0_acc;
logic [ACT_W-1:0] probe_pe0_result;
logic             probe_pe0_out_valid;

// PE2 probes
logic signed [WGT_W-1:0] probe_pe1_wgt_in;
logic signed [BIAS_W-1:0] probe_pe1_bias_in;
logic signed [dut.g_pe[0].u_pe.ACC_W-1:0]  probe_pe1_acc;
logic [ACT_W-1:0] probe_pe1_result;
logic             probe_pe1_out_valid;

// PE3 Probes
logic signed [WGT_W-1:0] probe_pe2_wgt_in;
logic signed [BIAS_W-1:0] probe_pe2_bias_in;
logic signed [dut.g_pe[0].u_pe.ACC_W-1:0]  probe_pe2_acc;
logic [ACT_W-1:0] probe_pe2_result;
logic             probe_pe2_out_valid;

// PE4 probes
logic signed [WGT_W-1:0] probe_pe3_wgt_in;
logic signed [BIAS_W-1:0] probe_pe3_bias_in;
logic signed [dut.g_pe[0].u_pe.ACC_W-1:0]  probe_pe3_acc;
logic [ACT_W-1:0] probe_pe3_result;
logic             probe_pe3_out_valid;

// PE5 Probes
logic signed [WGT_W-1:0] probe_pe4_wgt_in;
logic signed [BIAS_W-1:0] probe_pe4_bias_in;
logic signed [dut.g_pe[0].u_pe.ACC_W-1:0]  probe_pe4_acc;
logic [ACT_W-1:0] probe_pe4_result;
logic             probe_pe4_out_valid;

// RAM probes
logic [ACT_W-1:0] probe_act_rd_data0;
logic             probe_act_rd_dv0;

logic [WGT_W-1:0] probe_wgt0_rd_data;
logic             probe_wgt0_rd_dv;

logic [BIAS_W-1:0] probe_bias0_rd_data;
logic              probe_bias0_rd_dv;

logic [15:0] probe_act0_rd_addr;        // looking at read addresses to see if the address is the problem
logic [15:0] probe_wgt0_rd_addr;
logic [15:0] probe_bias0_rd_addr;

logic [ACT_W-1:0] probe_act0_mem0;      // looking at memory locations to see if improper memory storing is the problem
logic [ACT_W-1:0] probe_act0_mem1;

logic [WGT_W-1:0] probe_wgt0_mem0;
logic [WGT_W-1:0] probe_wgt0_mem1;

logic [BIAS_W-1:0] probe_bias0_mem0;
logic [BIAS_W-1:0] probe_bias0_mem1;

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

// CU probe assignments
assign cu_current_state = dut.cu_current_state;

logic [ACT_W-1:0] probe_pe_act_in;

// PE1 probe assignments
assign probe_pe_act_in       = dut.pe_act_in;
assign probe_pe0_wgt_in      = dut.pe_wgt_in[0];
assign probe_pe0_bias_in     = dut.pe_bias_in[0];

assign probe_pe0_acc         = dut.g_pe[0].u_pe.r_acc;

assign probe_pe0_result      = dut.pe_result[0];
assign probe_pe0_out_valid   = dut.pe_out_valid_vec[0];

// PE2 probe assignments
assign probe_pe1_wgt_in      = dut.pe_wgt_in[1];
assign probe_pe1_bias_in     = dut.pe_bias_in[1];

assign probe_pe1_acc         = dut.g_pe[1].u_pe.r_acc;

assign probe_pe1_result      = dut.pe_result[1];
assign probe_pe1_out_valid   = dut.pe_out_valid_vec[1];

// PE3 probe assignments
assign probe_pe2_wgt_in      = dut.pe_wgt_in[2];
assign probe_pe2_bias_in     = dut.pe_bias_in[2];

assign probe_pe2_acc         = dut.g_pe[2].u_pe.r_acc;

assign probe_pe2_result      = dut.pe_result[2];
assign probe_pe2_out_valid   = dut.pe_out_valid_vec[2];

// PE4 probe assignments
assign probe_pe3_wgt_in      = dut.pe_wgt_in[3];
assign probe_pe3_bias_in     = dut.pe_bias_in[3];

assign probe_pe3_acc         = dut.g_pe[3].u_pe.r_acc;

assign probe_pe3_result      = dut.pe_result[3];
assign probe_pe3_out_valid   = dut.pe_out_valid_vec[3];

// PE5 probe assignments
assign probe_pe4_wgt_in      = dut.pe_wgt_in[4];
assign probe_pe4_bias_in     = dut.pe_bias_in[4];

assign probe_pe4_acc         = dut.g_pe[4].u_pe.r_acc;

assign probe_pe4_result      = dut.pe_result[4];
assign probe_pe4_out_valid   = dut.pe_out_valid_vec[4];

// RAM probe assignments
assign probe_act_rd_data0 = dut.act_ram_rd_data[0];
assign probe_act_rd_dv0   = dut.act_ram_rd_dv[0];

assign probe_wgt0_rd_data = dut.wgt_ram_rd_data[0];
assign probe_wgt0_rd_dv   = dut.wgt_ram_rd_dv[0];

assign probe_bias0_rd_data = dut.bias_ram_rd_data[0];
assign probe_bias0_rd_dv   = dut.bias_ram_rd_dv[0];

assign probe_act0_rd_addr  = dut.g_act_ram[0].u_act_ram.rd_addr;
assign probe_wgt0_rd_addr  = dut.g_wgt_ram[0].u_wgt_ram.rd_addr;
assign probe_bias0_rd_addr = dut.g_bias_ram[0].u_bias_ram.rd_addr;

assign probe_act0_mem0 = dut.g_act_ram[0].u_act_ram.mem[0];
assign probe_act0_mem1 = dut.g_act_ram[0].u_act_ram.mem[1];

assign probe_wgt0_mem0 = dut.g_wgt_ram[0].u_wgt_ram.mem[0];
assign probe_wgt0_mem1 = dut.g_wgt_ram[0].u_wgt_ram.mem[1];

assign probe_bias0_mem0 = dut.g_bias_ram[0].u_bias_ram.mem[0];
assign probe_bias0_mem1 = dut.g_bias_ram[0].u_bias_ram.mem[1];


// assigning elements in activation memory probe to corresponding locations in activation RAMs.
genvar a0, a1, a2, a3, w1;
generate
    //act_ram_probe[addr_p] assigned to activation RAM data at location addr_p
    // dut.g_act_ram[lyr_p] indexes the generate for loop inside the accelerator_top module that is used to instantiate the RAM_2Port module.
    // At the loop location named dut.g_act_ram[lyr], we have instantiated a corresponding RAM_2Port instance named u_act_ram (see Accelerator_Top.sv).
    // Inside the instance named u_act_ram in the lyr iteration of the for loop, there exists an internal signal called mem (see RAM_2Port.sv)
    // We want to access the value at the addr_p index of that internal `mem` signal. 
    // NOTE: THIS IS NOT READING DATA THROUGH THE RAM INTERFACE. THIS IS DIRECTLY PROBING THE INTERNAL STRUCTURE OF THE RAM_2Port INSTANCE
    for (a0 = 0; a0 < INPUT_LAYER_SIZE; a0++) begin : g_probe_ram0
        assign act_ram0_probe[a0] = dut.g_act_ram[0].u_act_ram.mem[a0];
    end
    for (a1 = 0; a1 < LAYER1_SIZE; a1++) begin : g_probe_ram1
        assign act_ram1_probe[a1] = dut.g_act_ram[1].u_act_ram.mem[a1];
    end
    for (a2 = 0; a2 < LAYER2_SIZE; a2++) begin : g_probe_ram2
        assign act_ram2_probe[a2] = dut.g_act_ram[2].u_act_ram.mem[a2];
    end
    for (a3 = 0; a3 < OUTPUT_LAYER_SIZE; a3++) begin : g_probe_ram3
        assign act_ram3_probe[a3] = dut.g_act_ram[3].u_act_ram.mem[a3];
    end
    for (w1 = 0; w1 < WGT_RAM_DEPTH; w1++) begin : g_probe_rweight0
        assign wgt_ram1_probe[w1] = dut.g_wgt_ram[0].u_wgt_ram.mem[w1];
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


repeat (8000) @(posedge i_clk);
$finish;
end


endmodule