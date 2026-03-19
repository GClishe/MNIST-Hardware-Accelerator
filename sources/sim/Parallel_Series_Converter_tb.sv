`timescale 1ns/1ps

module Parallel_Series_Converter_tb;

    localparam int NUM_PE = 4;
    localparam int ACT_W  = 8;

    logic i_clk;
    logic i_rst;
    logic [ACT_W-1:0] i_activations [0:NUM_PE-1];
    logic [NUM_PE-1:0] i_PE_valid;
    logic i_shifting_valid;
    logic [ACT_W-1:0] o_activation;
    logic o_activation_valid;

    // instantiating dut
    Parallel_Series_Converter #(
        .NUM_PE(NUM_PE),
        .ACT_W (ACT_W)
    ) dut (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_activations(i_activations),
        .i_PE_valid(i_PE_valid),
        .i_shifting_valid(i_shifting_valid),
        .o_activation(o_activation),
        .o_activation_valid(o_activation_valid)
    );

    // creating 100MHz clock
    initial i_clk = 1'b0;
    always #5 i_clk = ~i_clk;

    // creating some helper tasks

    task automatic clear_inputs();
        i_PE_valid        = '0;
        i_shifting_valid  = 1'b0;
        for (int i = 0; i < NUM_PE; i++) begin
            i_activations[i] = '0;
        end
    endtask

    task automatic apply_parallel_data(input logic [ACT_W-1:0] data [0:NUM_PE-1]);
        for (int i = 0; i < NUM_PE; i++) begin
            i_activations[i] = data[i];
        end
    endtask

    // pulse all-valid for exactly one cycle to load the DUT
    task automatic load_data(input logic [ACT_W-1:0] data [0:NUM_PE-1]);
        apply_parallel_data(data);
        @(negedge i_clk);
        i_PE_valid = '1;
        @(negedge i_clk);
        i_PE_valid = '0;
    endtask

    // shift one word out and check it
    task automatic shift_and_check(input logic [ACT_W-1:0] expected);
        @(negedge i_clk);
        i_shifting_valid = 1'b1;

        @(posedge i_clk);
        #1; // allow registered outputs to update

        if (o_activation_valid !== 1'b1) begin
            $error("Expected o_activation_valid=1, got %0b at time %0t",
                   o_activation_valid, $time);
        end

        if (o_activation !== expected) begin
            $error("Expected o_activation=0x%0h, got 0x%0h at time %0t",
                   expected, o_activation, $time);
        end
        else begin
            $display("PASS: output = 0x%0h at time %0t", o_activation, $time);
        end
    endtask

    task automatic stop_shifting_and_check_invalid();
        @(negedge i_clk);
        i_shifting_valid = 1'b0;

        @(posedge i_clk);
        #1;

        if (o_activation_valid !== 1'b0) begin
            $error("Expected o_activation_valid=0, got %0b at time %0t",
                   o_activation_valid, $time);
        end
    endtask


    initial begin
        logic [ACT_W-1:0] vec0 [0:NUM_PE-1];
        logic [ACT_W-1:0] vec1 [0:NUM_PE-1];

        clear_inputs();

        // Test vectors
        vec0[0] = 8'h11;
        vec0[1] = 8'h22;
        vec0[2] = 8'h33;
        vec0[3] = 8'h44;

        vec1[0] = 8'hA1;
        vec1[1] = 8'hB2;
        vec1[2] = 8'hC3;
        vec1[3] = 8'hD4;

        // Reset
        i_rst = 1'b1;
        repeat (2) @(posedge i_clk);
        #1;
        if (o_activation !== '0 || o_activation_valid !== 1'b0) begin
            $error("Reset state incorrect: o_activation=0x%0h, o_activation_valid=%0b",
                   o_activation, o_activation_valid);
        end
        i_rst = 1'b0;

        // ----------------------------
        // Test 1: Load vec0 and shift out all entries
        // Expected order: r_main[0], r_main[1], ...
        // ----------------------------
        $display("\nTEST 1: Load vec0 and shift out");
        load_data(vec0);

        shift_and_check(8'h11);
        shift_and_check(8'h22);
        shift_and_check(8'h33);
        shift_and_check(8'h44);

        // One extra shift attempt: should not be valid anymore
        @(negedge i_clk);
        i_shifting_valid = 1'b1;
        @(posedge i_clk);
        #1;
        if (o_activation_valid !== 1'b0) begin
            $error("Expected o_activation_valid=0 after all data shifted, got %0b",
                   o_activation_valid);
        end
        i_shifting_valid = 1'b0;

        // ----------------------------
        // Test 2: Load vec1, pause shifting in the middle, then resume
        // ----------------------------
        $display("\nTEST 2: Load vec1, pause, resume");
        load_data(vec1);

        shift_and_check(8'hA1);
        shift_and_check(8'hB2);

        stop_shifting_and_check_invalid();

        shift_and_check(8'hC3);
        shift_and_check(8'hD4);

        // ----------------------------
        // Test 3: Partial PE valid should NOT load
        // ----------------------------
        $display("\nTEST 3: Partial i_PE_valid should not load");
        apply_parallel_data(vec0);

        @(negedge i_clk);
        i_PE_valid = 4'b1110;  // not all 1s
        @(negedge i_clk);
        i_PE_valid = '0;

        @(negedge i_clk);
        i_shifting_valid = 1'b1;
        @(posedge i_clk);
        #1;
        if (o_activation_valid !== 1'b0) begin
            $error("Partial i_PE_valid incorrectly caused a load");
        end
        i_shifting_valid = 1'b0;

        $display("\nAll test sequences completed.");
        $finish;
    end

    // monitor
    initial begin
        $display("time    rst  PE_valid shift_valid  out_valid  out");
        forever begin
            @(posedge i_clk);
            #1;
            $display("%0t   %0b     %b        %0b          %0b      0x%0h",
                     $time, i_rst, i_PE_valid, i_shifting_valid,
                     o_activation_valid, o_activation);
        end
    end

endmodule