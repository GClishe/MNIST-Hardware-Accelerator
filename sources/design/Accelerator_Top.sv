`timescale 1ns/1ps

module Accelerator_Top #(
    parameter int ACT_W             = 8,
    parameter int WGT_W             = 8,
    parameter int BIAS_W            = 8,
    parameter int NUM_PE            = 5,
    parameter int NUM_LAYERS        = 4,

    parameter int INPUT_LAYER_SIZE  = 784,
    parameter int LAYER1_SIZE       = 40,
    parameter int LAYER2_SIZE       = 30,
    parameter int OUTPUT_LAYER_SIZE = 10,
    parameter int MAX_LAYER_SIZE    = 784,

    // Memory depths
    parameter int ACT_RAM_DEPTH     = MAX_LAYER_SIZE,   // Max activation size is the max layer size
    parameter int WGT_RAM_DEPTH     = 6572,           
    parameter int BIAS_RAM_DEPTH    = 16
)(
    // Global clock and reset
    input  logic i_clk, 
    input  logic i_rst,

    // external indication that input activation memory has been filled and computation should begin
    input  logic i_start,

    // external output port for final network outputs
    output logic [ACT_W-1:0] o_out_data,    
    output logic             o_out_valid,
    output logic             o_done
);

    // num bits needed to accomondate all possible addresses
    localparam int ACT_ADDR_W   = $clog2(ACT_RAM_DEPTH);    
    localparam int WGT_ADDR_W   = $clog2(WGT_RAM_DEPTH);   
    localparam int BIAS_ADDR_W  = $clog2(BIAS_RAM_DEPTH);
    localparam int LAYER_SEL_W  = $clog2(NUM_LAYERS);
    localparam int OUT_ADDR_W   = $clog2(MAX_LAYER_SIZE);

    // defining file paths for weights, biases, and input activation
    localparam string INPUT_ACTIVATIONS = "A_random.mem";
    function automatic string get_wgt_file (int idx);
        // declaring a packed array for weight files would work, but I have never used functions in SV before, so I'd like to, even if it is overkill in this instance. 
        case (idx)
            0: return "W_PE1";
            1: return "W_PE2";
            2: return "W_PE3";
            3: return "W_PE4";
            4: return "W_PE5";
        endcase
    endfunction
    function automatic string get_bias_file (int idx);
        case (idx)
            0: return "B_PE1";
            1: return "B_PE2";
            2: return "B_PE3";
            3: return "B_PE4";
            4: return "B_PE5";
        endcase
    endfunction
    // Declaring control unit i/o interconnects
    logic [3:0] cu_current_state;   

    // ======================== CONTROL UNIT SIGNALS ============================
    logic cu_pe_rst;        // cu --> pe
    logic cu_clear_acc;     // cu --> pe
    logic cu_mac_en;        // cu --> pe
    logic cu_bias_en;       // cu --> pe
    logic cu_apply_act;     // cu --> pe

    logic cu_psc_shift_en;  // cu --> psc (parallel to serial converter)

    logic [15:0] cu_act_idx;    // cu --> activation RAM    (address from which to read activations during MAC)
    logic        cu_act_re;     // cu --> activation RAM    (read enable)
    logic        cu_act_we;     // cu --> activation RAM    (write enable)
    logic [15:0] cu_store_idx;  // cu --> activation RAM    (address to which activations are stored)

    logic        cu_wgt_re;     // cu --> weight RAM
    logic [15:0] cu_wgt_idx;    // cu --> weight RAM        (address from which to read weights during MAC)
    logic        cu_bias_re;    // cu --> bias RAM
    logic [15:0] cu_bias_idx;   // cu --> bias RAM         (address from which to read biases during MAC)

    logic [LAYER_SEL_W-1:0] cu_src_layer_sel; // cu --> TOP     (selecting which activation RAM to read from)
    logic [LAYER_SEL_W-1:0] cu_dst_layer_sel; // cu --> TOP     (selecting which activation RAM to write to)

    logic                   cu_out_re;        // cu --> activation RAM   (output read enable)
    logic [OUT_ADDR_W-1:0]  cu_out_idx;       // cu --> activation RAM   (address from which outputs are read)
    logic                   cu_out_valid;     // cu --> out

    //=================== PE AND PSC SIGNALS =================================================================
    logic [ACT_W-1:0]              pe_act_in;                   // activation RAM --> PE
    logic signed [WGT_W-1:0]       pe_wgt_in   [0:NUM_PE-1];    // weight RAM -->  PE
    logic signed [BIAS_W-1:0]      pe_bias_in  [0:NUM_PE-1];    // bias RAM --> PE

    logic [ACT_W-1:0]              pe_result   [0:NUM_PE-1];    // PE --> PSC
    logic [NUM_PE-1:0]             pe_out_valid_vec;            // PE --> PSC   (collection of all out valids from each PE. Streamed to psc)

    logic                          cu_i_out_valid;   // CU expects one valid input
    assign cu_i_out_valid = &pe_out_valid_vec;       // checks if all PEs valid simultaneously; this signal is sent to control unit

    logic [ACT_W-1:0]              psc_activation;          // psc --> activation memory
    logic                          psc_activation_valid;    // psc --> activation memory

    //========================== ACTIVATION RAM SIGNALS. ONE BANK PER LAYER================================================
    logic [ACT_W-1:0] act_ram_rd_data [0:NUM_LAYERS-1];     // activation RAM --> top   (MUXED read data from selected activation RAM)
    logic             act_ram_rd_dv   [0:NUM_LAYERS-1];     // activation RAM --> top   (data valid signal from the same)

    logic [ACT_W-1:0] selected_src_act_data;    // activation ram --> PE    (assigned to pe_act_in)

    logic [ACT_W-1:0] selected_out_data;        // activation RAM --> out   (read data for output RAM)
    logic             selected_out_dv;          // activation RAM --> out   (data valid for output RAM)

    // ======================================== WEIGHT RAM SIGNALS. ONE BANK PER PE===================================================
    logic [WGT_W-1:0] wgt_ram_rd_data [0:NUM_PE-1];       // weight RAM --> top     (cast to signed data; asynchronously tied to pe_wgt_in)
    logic             wgt_ram_rd_dv   [0:NUM_PE-1];       // weight RAM --> unused  (data valid for weight ram reads)

    // =============================================BIAS RAM SIGNALS. ONE BANK PER PE======================================================
    logic [BIAS_W-1:0] bias_ram_rd_data [0:NUM_PE-1];     // bias RAM --> top       (cast to signed integer, asynchronously tied to pe_bias_in)
    logic              bias_ram_rd_dv   [0:NUM_PE-1];     // bias RAM --> unused    (data valid for bias reads)

    // ============================== INSTANTIATING CONTROL UNIT =============================================================================
    Control_Unit #(
        .ACT_W(ACT_W),
        .WGT_W(WGT_W),
        .BIAS_W(BIAS_W),
        .NUM_PE(NUM_PE),
        .NUM_LAYERS(NUM_LAYERS),
        .INPUT_LAYER_SIZE(INPUT_LAYER_SIZE),
        .LAYER1_SIZE(LAYER1_SIZE),
        .LAYER2_SIZE(LAYER2_SIZE),
        .OUTPUT_LAYER_SIZE(OUTPUT_LAYER_SIZE),
        .MAX_LAYER_SIZE(MAX_LAYER_SIZE)
    ) u_control_unit (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_out_valid(cu_i_out_valid),
        .i_start(i_start),
        .i_psc_valid(psc_activation_valid),

        .o_current_state(cu_current_state),

        .o_rst(cu_pe_rst),
        .o_clear_acc(cu_clear_acc),
        .o_mac_en(cu_mac_en),
        .o_bias_en(cu_bias_en),
        .o_apply_act(cu_apply_act),

        .o_psc_shift_en(cu_psc_shift_en),

        .o_act_idx(cu_act_idx),
        .o_act_re(cu_act_re),
        .o_act_we(cu_act_we),
        .o_store_idx(cu_store_idx),

        .o_wgt_re(cu_wgt_re),
        .o_wgt_idx(cu_wgt_idx),
        .o_bias_re(cu_bias_re),
        .o_bias_idx(cu_bias_idx),

        .o_src_layer_sel(cu_src_layer_sel),
        .o_dst_layer_sel(cu_dst_layer_sel),

        .o_out_re(cu_out_re),
        .o_out_idx(cu_out_idx),
        .o_out_valid(cu_out_valid),
        .o_done(o_done)
    );

    // ============================== INSTANTIATING PSC =============================================================================
    Parallel_Series_Converter #(
        .NUM_PE(NUM_PE),
        .ACT_W(ACT_W)
    ) u_psc (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_activations(pe_result),
        .i_PE_valid(pe_out_valid_vec),
        .i_shifting_valid(cu_psc_shift_en),
        .o_activation(psc_activation),
        .o_activation_valid(psc_activation_valid)
    );

    // ============================== INSTANTIATING PROCESS ENGINE ARRAY==============================================================
    genvar pe;
    generate
        for (pe = 0; pe < NUM_PE; pe++) begin : g_pe   // generate statement creates array of names blocks, and g_pe is a label given to those blocks. This code would expand into g_pe[0].u_pe, g_pe[1], etc., which gives each instance its own local scope. So we could, for example, reference g_pe[3].u_pe.o_result to tap a specific signal. Also useful in the simulator
            Process_Engine #(
                .ACT_W(ACT_W),
                .WGT_W(WGT_W),
                .BIAS_W(BIAS_W),
                .NUM_MACS(INPUT_LAYER_SIZE) // MAC count depends on current layer (used for sizing accumulator). Using input layer size to size for the worst case
            ) u_pe (
                .i_clk(i_clk),
                .i_rst(cu_pe_rst),
                .i_act_in(pe_act_in),
                .i_wgt_in(pe_wgt_in[pe]),
                .i_bias_in(pe_bias_in[pe]),
                .i_clear_acc(cu_clear_acc),
                .i_mac_en(cu_mac_en),
                .i_bias_en(cu_bias_en),
                .i_apply_act(cu_apply_act),
                .o_result(pe_result[pe]),
                .o_out_valid(pe_out_valid_vec[pe])
            );
        end
    endgenerate

    // ==============================INSTANTIATING ACTIVATION RAMS===================================================================================
    genvar lyr;
    generate
        for (lyr = 0; lyr < NUM_LAYERS; lyr++) begin : g_act_ram    // create an array of activation RAMs, one per layer
            RAM_2Port #(
                .WIDTH(ACT_W),
                .DEPTH(ACT_RAM_DEPTH),
                .INIT_FILE((lyr == 0) ? INPUT_ACTIVATIONS : "")     // on lyr=0 (input layer), load INPUT_ACTIVATIONS. Else, do no loading. 
            ) u_act_ram (
                // each RAM receives same clock, address, and data, but not the same write enable.
                .i_Wr_Clk(i_clk),
                .i_Wr_Addr(cu_store_idx[ACT_ADDR_W-1:0]),
                .i_Wr_DV((cu_dst_layer_sel == lyr) && cu_act_we && psc_activation_valid),   //only write if the CU says writing is enabled and if PSC activation output is valid, and only to RAM whose layer index equals cu_dst_layer_sel
                .i_Wr_Data(psc_activation),

                .i_Rd_Clk(i_clk),

                // choose between two possible read addresses -- cu_out_idx or cu_act_idx
                .i_Rd_Addr(
                    (cu_out_re && (cu_src_layer_sel == (NUM_LAYERS-2))) // if we are in output read mode and the source layer is the second to last layer, then use cu_out_idx
                    ? cu_out_idx[ACT_ADDR_W-1:0]
                    : cu_act_idx[ACT_ADDR_W-1:0]
                ),

                // RAM lyr should perform a read if either the RAM is currently selected source layer (and CU wants to read) or if this RAM is the selected layer for output reading (and CU wants to read final outputs)
                .i_Rd_En(
                    ((cu_src_layer_sel == lyr) && cu_act_re) ||
                    ((cu_dst_layer_sel == lyr) && cu_out_re)
                ),
                .o_Rd_DV(act_ram_rd_dv[lyr]),       
                .o_Rd_Data(act_ram_rd_data[lyr]) // each RAM gets its own slot in act_ram_rd_data array
            );
        end
    endgenerate

    // ==============================INSTANTIATING WEIGHT RAMS===================================================================================
    generate
        for (pe = 0; pe < NUM_PE; pe++) begin : g_wgt_ram       // each PE has its own weight RAM, so we index weight RAMs by pe number
            RAM_2Port #(
                .WIDTH(WGT_W),
                .DEPTH(WGT_RAM_DEPTH),
                .INIT_FILE( get_wgt_file(pe) )
            ) u_wgt_ram (
                .i_Wr_Clk(i_clk),
                .i_Wr_Addr('0),         // weight RAM is read-only
                .i_Wr_DV(1'b0),         // weight RAM is read-only
                .i_Wr_Data('0),         // weight RAM is read-only

                .i_Rd_Clk(i_clk),
                .i_Rd_Addr(cu_wgt_idx[WGT_ADDR_W-1:0]),
                .i_Rd_En(cu_wgt_re),                // CU tells weight RAM when read should occur. 
                .o_Rd_DV(wgt_ram_rd_dv[pe]),        // this signal is connected to wg_ram_rd_dv, but wg_ram_rd_dv is currently unused (as of 3/24)
                .o_Rd_Data(wgt_ram_rd_data[pe])     // data read from weight RAM. Cast into signed integer and fed into respective PE
            );
        end
    endgenerate

    // ==============================INSTANTIATING BIAS RAMS===================================================================================
    // Bias ram behaves pretty much identically to the weight RAM, so see weight RAM comments for more details
    generate
        for (pe = 0; pe < NUM_PE; pe++) begin : g_bias_ram
            RAM_2Port #(
                .WIDTH(BIAS_W),
                .DEPTH(BIAS_RAM_DEPTH),
                .INIT_FILE( get_bias_file(pe) )
            ) u_bias_ram (
                .i_Wr_Clk(i_clk),
                .i_Wr_Addr('0),
                .i_Wr_DV(1'b0),
                .i_Wr_Data('0),

                .i_Rd_Clk(i_clk),
                .i_Rd_Addr(cu_bias_idx[BIAS_ADDR_W-1:0]),
                .i_Rd_En(cu_bias_re),
                .o_Rd_DV(bias_ram_rd_dv[pe]),
                .o_Rd_Data(bias_ram_rd_data[pe])
            );
        end
    endgenerate

    // logic below handles read data MUXing
    // Selected activation bank drives all PEs
    always_comb begin
        selected_src_act_data = '0;                             // selected_src_act_data is the data that comes out of the multiplexer into which all four activation RAM datas are fed

        for (int i = 0; i < NUM_LAYERS; i++) begin
            if (cu_src_layer_sel == i[LAYER_SEL_W-1:0]) begin
                selected_src_act_data = act_ram_rd_data[i];
            end
        end
    end

    assign pe_act_in = selected_src_act_data;

    // Each PE gets its own weight and bias bank
    generate
        for (pe = 0; pe < NUM_PE; pe++) begin
            assign pe_wgt_in[pe]  = signed'(wgt_ram_rd_data[pe]);
            assign pe_bias_in[pe] = signed'(bias_ram_rd_data[pe]);
        end
    endgenerate

    // Output streaming mux: read from final activation layer
    // final outputs live in activation RAM bank NUM_LAYERS-1.
    assign selected_out_data = act_ram_rd_data[NUM_LAYERS-1];
    assign selected_out_dv   = act_ram_rd_dv[NUM_LAYERS-1];

    assign o_out_data  = selected_out_data;
    assign o_out_valid = cu_out_valid & selected_out_dv;

endmodule