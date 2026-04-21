`timescale 1ns/1ps 

module RAM_loading_tb;

localparam int WIDTH = 8;
localparam int DEPTH = 16;
localparam int ADDR_W = 4;
localparam string INIT_FILE = "B_PE1.mem";

// inputs
logic clk;
logic wr_dv;
logic rd_en;
logic [ADDR_W-1:0] wr_addr;
logic [ADDR_W-1:0] rd_addr;
logic [WIDTH-1:0] wr_data;

// outputs
logic rd_dv;
logic [WIDTH-1:0] rd_data;

RAM_2Port #(
        .WIDTH(WIDTH),
        .DEPTH(DEPTH),
        .ADDR_W(ADDR_W),
        .INIT_FILE(INIT_FILE)
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

initial clk = 0;
always #5 clk = ~clk;

// The values actually stored in the selected .mem file are these. 
// This testbench will NOT write these values to the RAM, as they should already written at t=0. 
// This testbench WILL read from the RAM and check against this dataset
logic [7:0] expected_data [0:15] = '{
    8'h6B, 8'h0A, 8'h0C, 8'hD7,
    8'h14, 8'hED, 8'h16, 8'hED,
    8'h0A, 8'h15, 8'h11, 8'h0D,
    8'h1A, 8'h0A, 8'hCD, 8'h44
};

integer i;

initial begin
    // this code is currently only meant to show whether or not the new $readmemh functionality works for the 2port ram module. So we dont need to worry about writing new data
    wr_dv = 0;
    rd_en = 0;
    wr_addr = '0;
    rd_addr = '0;
    wr_data = '0;   

    repeat (5) @(posedge clk);  

    // check all 16 values in the RAM
    for (i = 0; i < DEPTH; i++) begin
        rd_en = 1;
        rd_addr = i[ADDR_W-1:0];

        @(posedge clk);

        if (rd_data != expected_data[i]) begin
            $error("FAIL: addr=%0d, expected rd_data=0x%0h, got 0x%0h at time %0t",
                   i, expected_data[i], rd_data, $time);
        end
        else begin
            $display("PASS: addr=%0d, output=0x%0h at time %0t",
                     i, rd_data, $time);
        end
    end

    $finish;
     
end




endmodule