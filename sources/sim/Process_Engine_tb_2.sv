`timescale 1ns/1ps

// Note that this testbench was written with the help of AI tools, for the sake of time. 

module Process_Engine_tb;

    // =========================================================
    // Parameters
    // =========================================================
    localparam int ACT_W     = 8;
    localparam int WGT_W     = 8;
    localparam int BIAS_W    = 8;
    localparam int NUM_MACS  = 8;

    localparam int ACT_FRAC  = 8;  // unsigned Q0.8
    localparam int WGT_FRAC  = 7;  // signed   Q1.7
    localparam int BIAS_FRAC = 7;  // signed   Q1.7

    localparam int PROD_FRAC       = ACT_FRAC + WGT_FRAC;
    localparam int OUT_FRAC        = ACT_FRAC;
    localparam int RESCALE_SHIFT   = PROD_FRAC - OUT_FRAC;
    localparam int BIAS_ALIGN_SHIFT = PROD_FRAC - BIAS_FRAC;

    localparam int MULT_W = ACT_W + WGT_W + 1;
    localparam int W1     = MULT_W + $clog2(NUM_MACS);
    localparam int W2     = BIAS_W + ((BIAS_ALIGN_SHIFT > 0) ? BIAS_ALIGN_SHIFT : 0);
    localparam int ACC_W  = ((W1 > W2) ? W1 : W2) + 1;

    // =========================================================
    // DUT I/O
    // =========================================================
    logic                      i_clk;
    logic                      i_rst;
    logic [ACT_W-1:0]          i_act_in;
    logic signed [WGT_W-1:0]   i_wgt_in;
    logic signed [BIAS_W-1:0]  i_bias_in;
    logic                      i_clear_acc;
    logic                      i_mac_en;
    logic                      i_bias_en;
    logic                      i_apply_act;
    logic [ACT_W-1:0]          o_result;
    logic                      o_out_valid;

    // =========================================================
    // DUT
    // =========================================================
    Process_Engine #(
        .ACT_W(ACT_W),
        .WGT_W(WGT_W),
        .BIAS_W(BIAS_W),
        .NUM_MACS(NUM_MACS),
        .ACT_FRAC(ACT_FRAC),
        .WGT_FRAC(WGT_FRAC),
        .BIAS_FRAC(BIAS_FRAC)
    ) dut (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_act_in(i_act_in),
        .i_wgt_in(i_wgt_in),
        .i_bias_in(i_bias_in),
        .i_clear_acc(i_clear_acc),
        .i_mac_en(i_mac_en),
        .i_bias_en(i_bias_en),
        .i_apply_act(i_apply_act),
        .o_result(o_result),
        .o_out_valid(o_out_valid)
    );

    // =========================================================
    // Clock
    // =========================================================
    initial i_clk = 1'b0;
    always #5 i_clk = ~i_clk;

    // =========================================================
    // Reference model state
    // =========================================================
    logic signed [ACC_W-1:0] exp_acc;
    logic signed [ACC_W-1:0] exp_rescaled;
    logic [ACT_W-1:0]        exp_result;

    integer test_count = 0;
    integer fail_count = 0;

    // =========================================================
    // Utility / reference functions
    // =========================================================

    function automatic logic signed [ACC_W-1:0] sign_extend_wgt_mult(
        input logic [ACT_W-1:0]        act_u,
        input logic signed [WGT_W-1:0] wgt_s
    );
        logic signed [MULT_W-1:0] mult_raw;
        begin
            mult_raw = $signed({1'b0, act_u}) * wgt_s;
            sign_extend_wgt_mult = {{(ACC_W-MULT_W){mult_raw[MULT_W-1]}}, mult_raw};
        end
    endfunction

    function automatic logic signed [ACC_W-1:0] align_bias(
        input logic signed [BIAS_W-1:0] bias_s
    );
        logic signed [ACC_W-1:0] bias_ext;
        begin
            bias_ext = {{(ACC_W-BIAS_W){bias_s[BIAS_W-1]}}, bias_s};

            if (BIAS_ALIGN_SHIFT >= 0)
                align_bias = (bias_ext <<< BIAS_ALIGN_SHIFT);
            else
                align_bias = (bias_ext >>> (-BIAS_ALIGN_SHIFT));
        end
    endfunction

    function automatic logic signed [ACC_W-1:0] rescale_acc(
        input logic signed [ACC_W-1:0] acc_in
    );
        begin
            if (RESCALE_SHIFT >= 0)
                rescale_acc = (acc_in >>> RESCALE_SHIFT);
            else
                rescale_acc = (acc_in <<< (-RESCALE_SHIFT));
        end
    endfunction

    function automatic logic [ACT_W-1:0] relu_and_clip(
        input logic signed [ACC_W-1:0] scaled_in
    );
        begin
            if (scaled_in < 0)
                relu_and_clip = '0;
            else if (scaled_in > 255)
                relu_and_clip = 8'hFF;
            else
                relu_and_clip = scaled_in[ACT_W-1:0];
        end
    endfunction

    task automatic clear_inputs;
        begin
            i_act_in     = '0;
            i_wgt_in     = '0;
            i_bias_in    = '0;
            i_clear_acc  = 1'b0;
            i_mac_en     = 1'b0;
            i_bias_en    = 1'b0;
            i_apply_act  = 1'b0;
        end
    endtask

    task automatic reset_dut;
        begin
            clear_inputs();
            i_rst = 1'b1;
            exp_acc = '0;
            @(posedge i_clk);
            @(posedge i_clk);
            i_rst = 1'b0;
            @(posedge i_clk);
        end
    endtask

    task automatic do_clear_acc;
        begin
            i_clear_acc = 1'b1;
            @(posedge i_clk);
            i_clear_acc = 1'b0;
            exp_acc = '0;
            @(negedge i_clk);
        end
    endtask

    task automatic do_mac(
        input logic [ACT_W-1:0]        act_u,
        input logic signed [WGT_W-1:0] wgt_s
    );
        logic signed [ACC_W-1:0] mult_term;
        begin
            mult_term = sign_extend_wgt_mult(act_u, wgt_s);

            i_act_in = act_u;
            i_wgt_in = wgt_s;
            i_mac_en = 1'b1;
            @(posedge i_clk);
            i_mac_en = 1'b0;

            exp_acc = exp_acc + mult_term;
            @(negedge i_clk);
        end
    endtask

    task automatic do_bias(
        input logic signed [BIAS_W-1:0] bias_s
    );
        logic signed [ACC_W-1:0] bias_term;
        begin
            bias_term = align_bias(bias_s);

            i_bias_in = bias_s;
            i_bias_en = 1'b1;
            @(posedge i_clk);
            i_bias_en = 1'b0;

            exp_acc = exp_acc + bias_term;
            @(negedge i_clk);
        end
    endtask

    task automatic do_apply_and_check(
        input string test_name
    );
        begin
            exp_rescaled = rescale_acc(exp_acc);
            exp_result   = relu_and_clip(exp_rescaled);

            i_apply_act = 1'b1;
            @(posedge i_clk);
            #1;

            test_count++;

            if (o_out_valid !== 1'b1) begin
                $display("FAIL [%0s]: o_out_valid was not asserted", test_name);
                fail_count++;
            end
            else if (o_result !== exp_result) begin
                $display("FAIL [%0s]: got o_result=%0d (0x%02h), expected=%0d (0x%02h)",
                         test_name, o_result, o_result, exp_result, exp_result);
                $display("             exp_acc=%0d, exp_rescaled=%0d",
                         exp_acc, exp_rescaled);
                fail_count++;
            end
            else begin
                $display("PASS [%0s]: o_result=%0d (0x%02h), exp_acc=%0d, exp_rescaled=%0d",
                         test_name, o_result, o_result, exp_acc, exp_rescaled);
            end

            i_apply_act = 1'b0;
            @(negedge i_clk);

            // out_valid should drop back low on the next cycle
            @(posedge i_clk);
            #1;
            if (o_out_valid !== 1'b0) begin
                $display("FAIL [%0s]: o_out_valid did not deassert after apply cycle", test_name);
                fail_count++;
            end
            @(negedge i_clk);
        end
    endtask

    // =========================================================
    // Main stimulus
    // =========================================================
    initial begin
        clear_inputs();
        exp_acc = '0;

        // -------------------------
        // Reset
        // -------------------------
        reset_dut();

        // -------------------------
        // Test 1: simple positive result, no saturation
        //
        // act = 128 -> 0.5 in Q0.8
        // wgt =  64 -> 0.5 in Q1.7
        // act*wgt = 0.25
        //
        // Two MACs: 0.25 + 0.25 = 0.5
        // bias = 32 -> 0.25
        // total = 0.75
        // output in Q0.8 ~= 192
        // -------------------------
        do_clear_acc();
        do_mac(8'd128, 8'sd64);
        do_mac(8'd128, 8'sd64);
        do_bias(8'sd32);
        do_apply_and_check("positive_no_saturation");

        // -------------------------
        // Test 2: negative result -> ReLU to zero
        //
        // act = 128 -> 0.5
        // wgt = -64 -> -0.5
        // one MAC = -0.25
        // two MACs = -0.5
        // bias = 0
        // final should be < 0, so output 0
        // -------------------------
        do_clear_acc();
        do_mac(8'd128, -8'sd64);
        do_mac(8'd128, -8'sd64);
        do_bias(8'sd0);
        do_apply_and_check("negative_relu_to_zero");

        // -------------------------
        // Test 3: saturation to 255
        //
        // Use repeated strong positive MACs and positive bias
        // -------------------------
        do_clear_acc();
        do_mac(8'd255, 8'sd127);
        do_mac(8'd255, 8'sd127);
        do_mac(8'd255, 8'sd127);
        do_mac(8'd255, 8'sd127);
        do_mac(8'd255, 8'sd127);
        do_mac(8'd255, 8'sd127);
        do_mac(8'd255, 8'sd127);
        do_mac(8'd255, 8'sd127);
        do_bias(8'sd127);
        do_apply_and_check("positive_saturates_to_255");

        // -------------------------
        // Test 4: verify clear_acc actually clears old dot product
        // -------------------------
        do_clear_acc();
        do_mac(8'd255, 8'sd127);
        do_mac(8'd255, 8'sd127);

        // now clear before apply
        do_clear_acc();

        do_mac(8'd128, 8'sd64);   // should behave like a fresh new dot product
        do_bias(8'sd0);
        do_apply_and_check("clear_acc_resets_state");

        // -------------------------
        // Summary
        // -------------------------
        $display("--------------------------------------------------");
        $display("Tests run : %0d", test_count);
        $display("Failures  : %0d", fail_count);
        $display("--------------------------------------------------");

        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED");

        #20;
        $finish;
    end

endmodule