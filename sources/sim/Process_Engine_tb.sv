`timescale 1ns / 1ps

module Process_Engine_tb;

    // creating copies of the DUT parameters local to this testbench
    localparam int ACT_W   = 8;
    localparam int WGT_W   = 8;
    localparam int BIAS_W  = 8;
    localparam int NUM_MACS = 4;
    
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
    // in this task, reset is asserted and all control and data signals are de-asserted.
    // Automatic keyword allows each function call to use local copy of variables, meaning that
    // successive function calls before the first one finishes will not overwrite the variables
    // in the first function call. For tasks like do_reset(), it is likely not necessary to use
    // the keyword, but I will be using it for all tasks for safety. 
    task automatic do_reset();
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
    endtask 
    
    // task that clears the accumulator; sets data/control signals to 0
    task automatic do_acc_clear();       
        clear_acc = 1;
        rst = 0;
        MAC_EN = 0;
        BIAS_EN = 0;
        APPLY_ACT = 0;
        ACT_IN = '0;
        WGT_IN = '0;
        BIAS_IN = '0;
       @(posedge clk);
       clear_acc = 0;
    endtask 
    
    task automatic do_MAC(
        // activations are unsigned ints, weights are signed. this is not a problem; see the PE module for how this situation is handled. 
        input logic [ACT_W-1:0] act_vec[0: NUM_MACS-1],
        input logic signed [WGT_W-1:0] wgt_vec[0: NUM_MACS-1]
    );
        int i;

        BIAS_EN = 0;
        APPLY_ACT = 0;
        MAC_EN = 1;         // MAC_EN should remain high as long as mac operations are desired. 
        for (i=0; i < NUM_MACS; i++) begin
            ACT_IN = act_vec[i];
            WGT_IN = wgt_vec[i];
            @(posedge clk);
        end
        @(posedge clk);
        MAC_EN = 0;         // de-asserting MAC_EN, since the MAC operations have now completed
    endtask 
    
    task automatic do_bias(input logic signed [BIAS_W-1:0] bias_val);
        rst = 0;
        clear_acc = 0;
        MAC_EN = 0;
        BIAS_EN = 1;        // enable bias
        APPLY_ACT = 0;
        ACT_IN = '0;
        WGT_IN = '0;
        BIAS_IN = bias_val;
        
        @(posedge clk);
        BIAS_EN = 0;
    endtask
    
    task automatic do_activation();
        rst = 0;
        clear_acc = 0;
        MAC_EN = 0;
        BIAS_EN = 0;       
        APPLY_ACT = 1;      // enable activation
        ACT_IN = '0;
        WGT_IN = '0;
        BIAS_IN = '0;
     
        @(posedge clk);
        APPLY_ACT = 0;    
    endtask
    
  
    // declaring weight and bias vectors for test cases
    logic        [ACT_W-1: 0] act1_vec [0:NUM_MACS-1];
    logic signed [WGT_W-1: 0] wgt1_vec [0:NUM_MACS-1];
    logic signed [BIAS_W-1: 0] bias1;
    
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
        
        do_reset();
        do_acc_clear();
        
        // ======================== TEST 1 (normal, positive inputs, no bias) ========================================================//
        // making sure MAC works right
        act1_vec = '{8'd1, 8'd2, 8'd3, 8'd4};
        wgt1_vec = '{8'sd1, 8'sd2, 8'sd3, 8'sd4};
        bias1 = '0;                                                                       
        
        do_MAC(act1_vec, wgt1_vec);
        do_bias(bias1);
        do_activation();
        do_acc_clear();
        
        // ======================== TEST 2 (normal, mixed inputs, nonzero bias, positive output) ======================================//
        // making sure negative values in weight array works right 
        act1_vec = '{8'd1, 8'd2, 8'd3, 8'd4};
        wgt1_vec = '{8'sd1, 8'sd2, -8'sd3, 8'sd4};      // MAC result: 12
        bias1 = 8'sd10;                                 // 12 + 10 = 22                 
        
        do_MAC(act1_vec, wgt1_vec);
        do_bias(bias1);
        do_activation();
        do_acc_clear();
        
        // ======================== TEST 3 (normal, mixed inputs, nonzero bias, negative output) ======================================//
        //  making sure negative bias works properl
        act1_vec = '{8'd1, 8'd2, 8'd3, 8'd4};      
        wgt1_vec = '{8'sd1, 8'sd2, -8'sd3, 8'sd4};      // MAC result: 12
        bias1 = -8'sd30;                                // 12 - 30 = 0 (after RELU)                   
        
        do_MAC(act1_vec, wgt1_vec);
        do_bias(bias1);
        do_activation();
        do_acc_clear();
        
        // ======================== TEST 4 (stress, positive inputs, no bias, max output) ======================================//
        // making sure large accumulations clamp to 255, even if one of the accumulations is negative
        // note: make sure that in the waveforms the radix for act1_vec and RESULT_OUT are unsigned decimal, else they will erroneously show -1
        act1_vec = '{8'd255, 8'd255, 8'd255, 8'd255}; 
        wgt1_vec = '{8'sd127, 8'sd127, -8'sd127, 8'sd127};
        bias1 = '0;                                     
        
        do_MAC(act1_vec, wgt1_vec);
        do_bias(bias1);
        do_activation();
        do_acc_clear();
        
        // ======================== TEST 5 (stress, positive inputs, no bias, max output) ======================================//
        // making sure that if dot product exceeds clamp, the bias can bring it back under
        act1_vec = '{8'd8,8'd8,8'd8,8'd8};
        wgt1_vec = '{8'sd10,8'sd10,8'sd10,8'sd10};   // 80 * 4 = 320
        bias1 = -8'sd80;   // 320 - 80 = 240                                                                  
        
        do_MAC(act1_vec, wgt1_vec);
        do_bias(bias1);
        do_activation();
        do_acc_clear();
        
        // ======================== TEST 6 (boundary, exact zero output) =============================================================//
        // making sure exact zero is handled properly and not treated as negative
        act1_vec = '{8'd1, 8'd2, 8'd3, 8'd4};
        wgt1_vec = '{8'sd1, 8'sd2, -8'sd3, 8'sd4};     // dot product = 12
        bias1 = -8'sd12;                               // 12 - 12 = 0
        
        do_MAC(act1_vec, wgt1_vec);
        do_bias(bias1);
        do_activation();
        do_acc_clear();
        
        // ======================== TEST 7 (boundary, exact max output without clamp overflow) =======================================//
        // making sure exact 255 passes through correctly
        act1_vec = '{8'd25, 8'd25, 8'd25, 8'd25};
        wgt1_vec = '{8'sd2, 8'sd2, 8'sd2, 8'sd2};      // 50 * 4 = 200
        bias1 = 8'sd55;                                // 200 + 55 = 255
        
        do_MAC(act1_vec, wgt1_vec);
        do_bias(bias1);
        do_activation();
        do_acc_clear();
        
        // ======================== TEST 8 (boundary, just above max output) =========================================================//
        // making sure a final value of 256 clamps to 255
        act1_vec = '{8'd25, 8'd25, 8'd25, 8'd25};
        wgt1_vec = '{8'sd2, 8'sd2, 8'sd2, 8'sd2};      // 50 * 4 = 200
        bias1 = 8'sd56;                                // 200 + 56 = 256
        
        do_MAC(act1_vec, wgt1_vec);
        do_bias(bias1);
        do_activation();
        do_acc_clear();
        
        // ======================== TEST 9 (bias-only path, zero MAC, positive bias) =================================================//
        // making sure bias path works even when MAC result is zero
        act1_vec = '{8'd0, 8'd0, 8'd0, 8'd0};
        wgt1_vec = '{8'sd5, 8'sd10, -8'sd12, 8'sd3};   // dot product = 0
        bias1 = 8'sd25;                                // final = 25
        
        do_MAC(act1_vec, wgt1_vec);
        do_bias(bias1);
        do_activation();
        do_acc_clear();
        
        // ======================== TEST 10 (bias-only path, zero MAC, negative bias) ================================================//
        // making sure negative bias drives output to zero when MAC result is zero
        act1_vec = '{8'd0, 8'd0, 8'd0, 8'd0};
        wgt1_vec = '{8'sd5, 8'sd10, -8'sd12, 8'sd3};   // dot product = 0
        bias1 = -8'sd25;                               // final = -25
        
        do_MAC(act1_vec, wgt1_vec);
        do_bias(bias1);
        do_activation();
        do_acc_clear();
        
        // ======================== TEST 11 (boundary, most-negative bias value) =====================================================//
        // making sure sign extension of the most-negative 8-bit bias works properly
        act1_vec = '{8'd5, 8'd5, 8'd5, 8'd5};
        wgt1_vec = '{8'sd10, 8'sd10, 8'sd10, 8'sd10};  // dot product = 200
        bias1 = -8'sd128;                              // 200 - 128 = 72
        
        do_MAC(act1_vec, wgt1_vec);
        do_bias(bias1);
        do_activation();
        do_acc_clear();
        
        do_reset();
        
        $finish;      
    end


endmodule
