`timescale 1ns / 1ps

module Process_Engine_tb;

    // creating copies of the DUT parameters local to this testbench
    localparam int ACT_W   = 8;
    localparam int WGT_W   = 8;
    localparam int BIAS_W  = 8;
    localparam int NUM_MACS = 10;
    
    // same idea, creating signals that connect to the DUT 
    logic clk;
    logic rst;
    logic [ACT_W-1:0] ACT_IN;
    logic signed [WGT_W-1:0] WGT_IN;
    logic signed [BIAS_W-1:0] BIAS_IN;
    logic clear_acc;
    logic MAC_EN;
    logic BIAS_EN;
    logic APPLY_ACT;
    logic [ACT_W-1:0] RESULT_OUT;
    logic OUT_VALID;

    // instantiate the DUT by passing the above parameters and signals
    Process_Engine #(
        .ACT_W(ACT_W),
        .WGT_W(WGT_W),
        .BIAS_W(BIAS_W),
        .NUM_MACS(NUM_MACS)
    ) dut (
        .clk(clk),
        .rst(rst),
        .ACT_IN(ACT_IN),
        .WGT_IN(WGT_IN),
        .BIAS_IN(BIAS_IN),
        .clear_acc(clear_acc),
        .MAC_EN(MAC_EN),
        .BIAS_EN(BIAS_EN),
        .APPLY_ACT(APPLY_ACT),
        .RESULT_OUT(RESULT_OUT),
        .OUT_VALID(OUT_VALID)
    );
    
    
    // Now i am going to create some tasks; one for each legal operation, so this will include resetting,
    // clearing accumulator, performing MAC, adding bias, then activation function
    
    // defining a task that performs a reset
    // in this task, reset is asserted and all control and data signals are de-asserted
    task do_reset();
    begin
        // these signals are set at current sim time, so asynchronously
        rst = 1;
        clear_acc = 0;
        MAC_EN = 0;
        BIAS_EN = 0;
        APPLY_ACT = 0;
        ACT_IN = '0;
        WGT_IN = '0;
        BIAS_IN = '0;
        
        repeat (2) @(posedge clk);  // holding reset for two clock cycles
        rst = 0;                    // de-asserting reset immediately after second posedge
        @(posedge clk);             // waiting for next clock cycle
        // now DUT is reset and ready for next task
    end    
    endtask 
    
    
    
    // creating a clock; a 100MHz clock has a period of 10ns
    initial clk = 0;
    always #5 clk = ~clk;   // every 5 values of timescale (so, 5ns), invert clk. Creates a 100MHz clock.
    
    // test sequence defined here
    initial begin
        // initializing control signal and data inputs to known values 
        rst       = 0;
        ACT_IN    = '0;
        WGT_IN    = '0;
        BIAS_IN   = '0;
        clear_acc = 0;
        MAC_EN    = 0;
        BIAS_EN   = 0;
        APPLY_ACT = 0;
    
    end


endmodule
