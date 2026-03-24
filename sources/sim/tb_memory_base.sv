`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03/20/2026 11:30:03 PM
// Design Name: 
// Module Name: tb_memory_base
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module tb_memory_base;
// Parameters
    localparam int WIDTH      = 8;
    localparam int DEPTH      = 16;
    localparam int ADDR_WIDTH = 16;

    // DUT signals
    logic                  clk;
    logic                  wr_dv;
    logic [ADDR_WIDTH-1:0] wr_addr;
    logic [WIDTH-1:0]      wr_data;

    logic                  rd_en;
    logic [ADDR_WIDTH-1:0] rd_addr;
    logic [WIDTH-1:0]      rd_data;
    logic                  rd_dv;

    // Instantiate DUT
    RAM_2Port #(
        .WIDTH(WIDTH),
        .DEPTH(DEPTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) dut (
        .clk    (clk),
        .wr_dv  (wr_dv),
        .wr_addr(wr_addr),
        .wr_data(wr_data),
        .rd_en  (rd_en),
        .rd_addr(rd_addr),
        .rd_data(rd_data),
        .rd_dv  (rd_dv)
    );

    // Clock generation: 10 ns period
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Task: write one value
    task automatic write_mem(
        input logic [ADDR_WIDTH-1:0] addr,
        input logic [WIDTH-1:0]      data
    );
    begin
        @(negedge clk);
        wr_dv   = 1'b1;
        wr_addr = addr;
        wr_data = data;

        @(negedge clk);
        wr_dv   = 1'b0;
        wr_addr = '0;
        wr_data = '0;
    end
    endtask

    // Task: read one value and check result
    task automatic read_and_check(
        input logic [ADDR_WIDTH-1:0] addr,
        input logic [WIDTH-1:0]      expected
    );
    begin
        @(negedge clk);
        rd_en   = 1'b1;
        rd_addr = addr;

        // After the next positive edge, rd_data and rd_dv update
        @(posedge clk);
        #1;

        if (rd_dv !== 1'b1) begin
            $display("ERROR @ %0t: rd_dv is not 1 during read. addr=%0d", $time, addr);
        end

        if (rd_data !== expected) begin
            $display("ERROR @ %0t: addr=%0d expected=%0h got=%0h",
                     $time, addr, expected, rd_data);
        end
        else begin
            $display("PASS  @ %0t: addr=%0d data=%0h rd_dv=%0b",
                     $time, addr, rd_data, rd_dv);
        end

        @(negedge clk);
        rd_en = 1'b0;

        @(posedge clk);
        #1;
        if (rd_dv !== 1'b0) begin
            $display("ERROR @ %0t: rd_dv did not go low after rd_en=0", $time);
        end
    end
    endtask



    // Stimulus
    initial begin
        // Initialize inputs
        wr_dv   = 0;
        wr_addr = 0;
        wr_data = 0;
        rd_en   = 0;
        rd_addr = 0;

        // Wait a couple cycles
        repeat (2) @(posedge clk);

        $display("\n--- WRITE TESTS ---");
        write_mem(4'd0, 8'hA1);
        write_mem(4'd3, 8'hB2);
        write_mem(4'd7, 8'hC3);
        write_mem(4'd15, 8'hD4);

        $display("\n--- READ TESTS ---");
        read_and_check(4'd0,  8'hA1);
        read_and_check(4'd3,  8'hB2);
        read_and_check(4'd7,  8'hC3);
        read_and_check(4'd15, 8'hD4);

        $display("\n--- NO-WRITE TEST ---");
        // Put values on wr_addr/wr_data but keep wr_dv = 0
        @(negedge clk);
        wr_dv   = 1'b0;
        wr_addr = 4'd3; 
        wr_data = 8'hFF;

        // Read back address 3 to confirm it did not change
        read_and_check(4'd3, 8'hB2);

        $display("\n--- TEST COMPLETE ---");
        $finish;
    end
endmodule
