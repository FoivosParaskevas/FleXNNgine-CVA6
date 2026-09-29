`include "register_interface/assign.svh"
`include "register_interface/typedef.svh"

// Xilinx Peripherals
module flexnngine_wrap #(
    parameter int AxiAddrWidth = -1,
    parameter int AxiDataWidth = -1,
    parameter int AxiIdWidth   = -1,
    parameter int AxiUserWidth = 1,
    parameter bit AxiAccCDC    = 1
) (
    input  logic       clk_axi_i   , // AXI bus clock
    input  logic       clk_array_i , // PE array clock
    input  logic       clk_spad_i  , // scratchpad interface clock
    input  logic       rst_ni      , // Asynchronous reset active low
    AXI_BUS.Slave      regs        ,
    AXI_BUS.Slave      spad        ,
    output logic       irq_o
);

    assign irq_o = 0; // not implemented yet

    logic en;
    logic [AxiDataWidth/8-1:0] write_en;
    logic [16:0] addr;
    logic [AxiDataWidth-1:0] din;
    logic [AxiDataWidth-1:0] dout;

    // acc_axi_regs is AXI4-Lite: no ID or r_last ports. Echo AR/AW IDs back
    // as RID/BID for AXI4 crossbar response routing, and drive r_last=1
    // since the register slave is always single-beat (no bursts).
    logic [AxiIdWidth-1:0] ar_id_q, aw_id_q;
    always_ff @(posedge clk_axi_i or negedge rst_ni) begin
        if (!rst_ni) begin
            ar_id_q <= '0;
            aw_id_q <= '0;
        end else begin
            if (regs.ar_valid && regs.ar_ready) ar_id_q <= regs.ar_id;
            if (regs.aw_valid && regs.aw_ready) aw_id_q <= regs.aw_id;
        end
    end
    assign regs.r_id   = ar_id_q;
    assign regs.b_id   = aw_id_q;
    assign regs.r_last = 1'b1;
    assign regs.b_user = 'b0;
    assign regs.r_user = 'b0;

    // acc_axi_regs is a 32-bit AXI4-Lite slave on a 64-bit AXI4 master bus.
    // Byte-lane bridge: replicate 32-bit RDATA into both halves so the CPU
    // extracts the correct word regardless of address bit[2]. For writes,
    // select the active 32-bit lane from the 64-bit WDATA based on WSTRB.
    logic [31:0] regs_rdata32;
    logic [31:0] regs_wdata32;
    logic  [3:0] regs_wstrb32;
    assign regs.r_data  = {regs_rdata32, regs_rdata32};
    assign regs_wdata32 = |regs.w_strb[7:4] ? regs.w_data[63:32] : regs.w_data[31:0];
    assign regs_wstrb32 = |regs.w_strb[7:4] ? regs.w_strb[7:4]   : regs.w_strb[3:0];

    acc_axi_top #(
        .C_S00_AXI_ADDR_WIDTH ( 32            ), // register space fits in 32-bit address
        .C_S00_AXI_DATA_WIDTH ( 32            ), // acc_axi_regs uses 32-bit registers
        .mem_data_width       ( AxiDataWidth  ),
        .mem_word_count       ( AxiDataWidth / 8 ),
        .mem_addr_width_bytes ( 17 ), // 128 KB physical scratchpad (matches Lesniak 2024)
        .size_x ( 7 ),
        .size_y ( 10 ),
        .axi_acc_cdc (AxiAccCDC)
    ) i_acc_axi_top (
        .clk             (clk_array_i),
        .clk_sp          (clk_spad_i),
        .i_dummy_rst     (1'b0),
        .i_en            (en),
        .i_write_en      (write_en),
        .i_addr          (addr),
        .i_din           (din),
        .o_dout          (dout),
        .s00_axi_aclk    (clk_axi_i),
        .s00_axi_aresetn (rst_ni),
        .s00_axi_awaddr  (regs.aw_addr[31:0]),
        .s00_axi_awprot  (regs.aw_prot),
        .s00_axi_awvalid (regs.aw_valid),
        .s00_axi_awready (regs.aw_ready),
        .s00_axi_wdata   (regs_wdata32),
        .s00_axi_wstrb   (regs_wstrb32),
        .s00_axi_wvalid  (regs.w_valid),
        .s00_axi_wready  (regs.w_ready),
        .s00_axi_bresp   (regs.b_resp),
        .s00_axi_bvalid  (regs.b_valid),
        .s00_axi_bready  (regs.b_ready),
        .s00_axi_araddr  (regs.ar_addr[31:0]),
        .s00_axi_arprot  (regs.ar_prot),
        .s00_axi_arvalid (regs.ar_valid),
        .s00_axi_arready (regs.ar_ready),
        .s00_axi_rdata   (regs_rdata32),
        .s00_axi_rresp   (regs.r_resp),
        .s00_axi_rvalid  (regs.r_valid),
        .s00_axi_rready  (regs.r_ready)
    );

    // BRAM controller runs on the scratchpad clock (clk_spad_i). The SoC-side
    // AXI bus is clock-converted externally (xlnx_axi_clock_converter_spad
    // in cva6_flexnngine_xilinx.sv), so `spad` on this port is already in the
    // clk_spad_i domain. acc_axi_top's scratchpad interface (i_en/i_addr/...)
    // is also tagged as belonging to clk_sp — matching here keeps the whole
    // spad data path in a single clock domain.
    xlnx_axi_bram_ctrl_flexnngine (
        .s_axi_aclk     (clk_spad_i),
        .s_axi_aresetn  (rst_ni),
        .s_axi_awid     (spad.aw_id),
        .s_axi_awaddr   (spad.aw_addr[31:0]),
        .s_axi_awlen    (spad.aw_len),
        .s_axi_awsize   (spad.aw_size),
        .s_axi_awburst  (spad.aw_burst),
        .s_axi_awlock   (spad.aw_lock),
        .s_axi_awcache  (spad.aw_cache),
        .s_axi_awprot   (spad.aw_prot),
        .s_axi_awvalid  (spad.aw_valid),
        .s_axi_awready  (spad.aw_ready),
        .s_axi_wdata    (spad.w_data),
        .s_axi_wstrb    (spad.w_strb),
        .s_axi_wlast    (spad.w_last),
        .s_axi_wvalid   (spad.w_valid),
        .s_axi_wready   (spad.w_ready),
        .s_axi_bid      (spad.b_id),
        .s_axi_bresp    (spad.b_resp),
        .s_axi_bvalid   (spad.b_valid),
        .s_axi_bready   (spad.b_ready),
        .s_axi_arid     (spad.ar_id),
        .s_axi_araddr   (spad.ar_addr[31:0]),
        .s_axi_arlen    (spad.ar_len),
        .s_axi_arsize   (spad.ar_size),
        .s_axi_arburst  (spad.ar_burst),
        .s_axi_arlock   (spad.ar_lock),
        .s_axi_arcache  (spad.ar_cache),
        .s_axi_arprot   (spad.ar_prot),
        .s_axi_arvalid  (spad.ar_valid),
        .s_axi_arready  (spad.ar_ready),
        .s_axi_rid      (spad.r_id),
        .s_axi_rdata    (spad.r_data),
        .s_axi_rresp    (spad.r_resp),
        .s_axi_rlast    (spad.r_last),
        .s_axi_rvalid   (spad.r_valid),
        .s_axi_rready   (spad.r_ready),
        .bram_rst_a     (),
        .bram_clk_a     (),
        .bram_en_a      (en),
        .bram_we_a      (write_en),
        .bram_addr_a    (addr),
        .bram_wrdata_a  (din),
        .bram_rddata_a  (dout)
    );

endmodule
