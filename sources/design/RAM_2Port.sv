`timescale 1ns / 1ps
/*
According to the memory specs document, every memory bank will have the same structure.
*/

module RAM_2Port #(
    parameter int WIDTH = 8,         //size of each element stored in the RAM
    parameter int DEPTH = 16,        //amount of elements to be stored in the RAM, for this trial, picked 16. 
                                     //This will changed based on what bank we are designing
    parameter int ADDR_W = 16,       // address width. should be at least clog2(DEPTH)
    parameter string INIT_FILE = ""  // file used to populate RAM instance
    )(
    input logic clk,    //clock signal
    
    //write port
    input logic wr_dv,                    //write data valid, data written only if value is 1
    input logic [ADDR_W-1:0] wr_addr,     //address of data to be written
    input logic [WIDTH-1:0] wr_data,      //data to be written
    
    //read port
    output logic rd_dv,                     //read data valid, value is 1 if data read is valid
    input logic rd_en,  	                //read enabled, here to set rd_dv high
    input logic [ADDR_W-1:0] rd_addr,       //address of data being read
    output logic [WIDTH-1:0] rd_data        //data being read
    );

    logic [WIDTH-1:0] mem [0:DEPTH-1];      //This is the memory array itself
    
    initial begin
        if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, mem);      // if the user passes an init file, the RAM is populated with values according to the contents of the file.
        end
        else begin              
            for (int i = 0; i < DEPTH; i++) begin
                mem[i] = '0;               // if no init file is passed, RAM is populated with 0s. 
            end
        end
    end

    //write logic
    always_ff @(posedge clk) begin
        if (wr_dv) begin
            mem[wr_addr] <= wr_data;
        end
    end
    
    //read logic
    always_ff @(posedge clk) begin
        rd_data <= mem[rd_addr];    //Continuous reads
	    rd_dv <= rd_en;             //Tells the control unit if the value read is valid
    end    
    
endmodule
