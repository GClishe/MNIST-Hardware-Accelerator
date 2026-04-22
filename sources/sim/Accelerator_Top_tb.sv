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
logic [ACT_W-1:0] act_ram0_probe [0:INPUT_LAYER_SIZE-1];             // probe for memory addresses for input activations
logic [ACT_W-1:0] act_ram1_probe [0:LAYER1_SIZE-1];
logic [ACT_W-1:0] act_ram2_probe [0:LAYER2_SIZE-1];
logic [ACT_W-1:0] act_ram3_probe [0:OUTPUT_LAYER_SIZE-1];

// PE1 probes
logic [ACT_W-1:0] probe_pe_act_in;
logic signed [WGT_W-1:0] probe_pe0_wgt_in;
logic signed [BIAS_W-1:0] probe_pe0_bias_in;
logic signed [dut.g_pe[0].u_pe.ACC_W-1:0]  probe_pe0_acc;
logic [ACT_W-1:0] probe_pe0_result;
logic             probe_pe0_out_valid;

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
// PE probe assignments
assign probe_pe_act_in       = dut.pe_act_in;
assign probe_pe0_wgt_in      = dut.pe_wgt_in[0];
assign probe_pe0_bias_in     = dut.pe_bias_in[0];

assign probe_pe0_acc         = dut.g_pe[0].u_pe.r_acc;

assign probe_pe0_result      = dut.pe_result[0];
assign probe_pe0_out_valid   = dut.pe_out_valid_vec[0];

// assigning elements in activation memory probe to corresponding locations in activation RAMs.
genvar a0, a1, a2, a3;
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