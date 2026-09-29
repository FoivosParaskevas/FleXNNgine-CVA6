// Copyright 2018 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.
//
// Single CVA6 core + FleXNNgine accelerator SoC — simulation top-level.
// A single CVA6 core connects directly to the AXI crossbar (no coherence unit).

`include "axi/assign.svh"
`include "axi/typedef.svh"
`include "register_interface/typedef.svh"

module cva6_flexnngine_top #(
  parameter int unsigned AXI_USER_WIDTH    = ariane_pkg::AXI_USER_WIDTH,
  parameter int unsigned AXI_USER_EN       = ariane_pkg::AXI_USER_EN,
  parameter int unsigned AXI_ADDRESS_WIDTH = 64,
  parameter int unsigned AXI_DATA_WIDTH    = 64,
  parameter ariane_pkg::ariane_cfg_t ArianeCfg = soc_pkg::ArianeSocCfg,
  parameter bit          InclSimDTM        = 1'b0,
  parameter int unsigned NUM_WORDS         = 2**25,         // memory size
  parameter bit          StallRandomOutput = 1'b0,
  parameter bit          StallRandomInput  = 1'b0,
  parameter int unsigned FixedDelayInput   = 0,
  parameter int unsigned FixedDelayOutput  = 0,
  parameter bit          HasLLC            = 1'b1,
  parameter logic [63:0] BootAddress       = 64'h8010_0000
) (
  input  logic        clk_i,
  input  logic        rtc_i,
  input  logic        rst_ni,
  output logic [31:0] exit_o
);

  // LLC adds 1 bit to the DRAM-side ID width
  localparam int unsigned AXI_ID_WIDTH_DRAM =
      HasLLC ? soc_pkg::IdWidthSlave + 1 : soc_pkg::IdWidthSlave;

  logic test_en;
  logic ndmreset;
  logic ndmreset_n;
  logic debug_req_core;

  int   jtag_enable;
  logic init_done;
  logic [31:0] jtag_exit, dmi_exit;

  logic jtag_TCK, jtag_TMS, jtag_TDI, jtag_TRSTn;
  logic jtag_TDO_data, jtag_TDO_driven;

  logic debug_req_valid, debug_req_ready;
  logic debug_resp_valid, debug_resp_ready;
  logic jtag_req_valid, jtag_resp_ready, jtag_resp_valid;
  logic [6:0]  jtag_req_bits_addr;
  logic [1:0]  jtag_req_bits_op;
  logic [31:0] jtag_req_bits_data;
  logic dmi_req_valid, dmi_resp_ready, dmi_resp_valid;

  dm::dmi_req_t  jtag_dmi_req, dmi_req, debug_req;
  dm::dmi_resp_t debug_resp;

  assign test_en   = 1'b0;
  assign init_done = rst_ni;

  // ------------------------------------------------------------------
  // AXI bus interfaces
  // ------------------------------------------------------------------
  // to_xbar[0] = CVA6 master,  to_xbar[1] = debug master
  AXI_BUS #(
    .AXI_ADDR_WIDTH ( AXI_ADDRESS_WIDTH       ),
    .AXI_DATA_WIDTH ( AXI_DATA_WIDTH          ),
    .AXI_ID_WIDTH   ( soc_pkg::IdWidthToXbar  ),
    .AXI_USER_WIDTH ( AXI_USER_WIDTH          )
  ) to_xbar[1:0]();

  // master[] = peripheral slave ports from xbar
  AXI_BUS #(
    .AXI_ADDR_WIDTH ( AXI_ADDRESS_WIDTH      ),
    .AXI_DATA_WIDTH ( AXI_DATA_WIDTH         ),
    .AXI_ID_WIDTH   ( soc_pkg::IdWidthSlave  ),
    .AXI_USER_WIDTH ( AXI_USER_WIDTH         )
  ) master[soc_pkg::NB_PERIPHERALS-1:0]();

  // Dummy ethernet AXI bus (InclEthernet=0; ariane_peripherals drives error responses internally)
  AXI_BUS #(
    .AXI_ADDR_WIDTH ( AXI_ADDRESS_WIDTH      ),
    .AXI_DATA_WIDTH ( AXI_DATA_WIDTH         ),
    .AXI_ID_WIDTH   ( soc_pkg::IdWidthSlave  ),
    .AXI_USER_WIDTH ( AXI_USER_WIDTH         )
  ) ethernet_dummy();

  // ------------------------------------------------------------------
  // Reset synchroniser
  // ------------------------------------------------------------------
  rstgen i_rstgen_main (
    .clk_i       ( clk_i                ),
    .rst_ni      ( rst_ni & (~ndmreset) ),
    .test_mode_i ( test_en              ),
    .rst_no      ( ndmreset_n           ),
    .init_no     (                      )
  );

  // ------------------------------------------------------------------
  // Debug
  // ------------------------------------------------------------------
  initial begin
    if (!$value$plusargs("jtag_rbb_enable=%b", jtag_enable)) jtag_enable = 'h0;
  end

  logic debug_enable;
  initial begin
    if ($test$plusargs("debug_disable")) debug_enable = 'h0;
    else                                 debug_enable = 'h1;
  end

  assign debug_req_valid  = (jtag_enable[0]) ? jtag_req_valid  : dmi_req_valid;
  assign debug_resp_ready = (jtag_enable[0]) ? jtag_resp_ready : dmi_resp_ready;
  assign debug_req        = (jtag_enable[0]) ? jtag_dmi_req    : dmi_req;
  assign jtag_resp_valid  = (jtag_enable[0]) ? debug_resp_valid : 1'b0;
  assign dmi_resp_valid   = (jtag_enable[0]) ? 1'b0            : debug_resp_valid;
  // exit_o is driven by the memory-mapped tohost mechanism (gen_llc/gen_no_llc below)

  dmi_jtag i_dmi_jtag (
    .clk_i            ( clk_i           ),
    .rst_ni           ( rst_ni          ),
    .testmode_i       ( test_en         ),
    .dmi_req_o        ( jtag_dmi_req    ),
    .dmi_req_valid_o  ( jtag_req_valid  ),
    .dmi_req_ready_i  ( debug_req_ready ),
    .dmi_resp_i       ( debug_resp      ),
    .dmi_resp_ready_o ( jtag_resp_ready ),
    .dmi_resp_valid_i ( jtag_resp_valid ),
    .dmi_rst_no       (                 ),
    .tck_i            ( jtag_TCK        ),
    .tms_i            ( jtag_TMS        ),
    .trst_ni          ( jtag_TRSTn      ),
    .td_i             ( jtag_TDI        ),
    .td_o             ( jtag_TDO_data   ),
    .tdo_oe_o         ( jtag_TDO_driven )
  );

  logic [1:0] debug_req_bits_op;
  assign dmi_req.op = dm::dtm_op_e'(debug_req_bits_op);

  if (InclSimDTM) begin : gen_simdtm
    SimDTM i_SimDTM (
      .clk                  ( clk_i                 ),
      .reset                ( ~rst_ni               ),
      .debug_req_valid      ( dmi_req_valid         ),
      .debug_req_ready      ( debug_req_ready       ),
      .debug_req_bits_addr  ( dmi_req.addr          ),
      .debug_req_bits_op    ( debug_req_bits_op     ),
      .debug_req_bits_data  ( dmi_req.data          ),
      .debug_resp_valid     ( dmi_resp_valid        ),
      .debug_resp_ready     ( dmi_resp_ready        ),
      .debug_resp_bits_resp ( debug_resp.resp       ),
      .debug_resp_bits_data ( debug_resp.data       ),
      .exit                 ( dmi_exit              )
    );
  end else begin : gen_nodtm
    assign dmi_req_valid     = '0;
    assign debug_req_bits_op = '0;
    assign dmi_exit          = 1'b0;
  end

  // Gate debug requests for DmiDelCycles after reset
  localparam int unsigned DmiDelCycles = 500;
  logic debug_req_core_ungtd;
  int   dmi_del_cnt_d, dmi_del_cnt_q;

  assign dmi_del_cnt_d  = (dmi_del_cnt_q) ? dmi_del_cnt_q - 1 : 0;
  assign debug_req_core = (dmi_del_cnt_q) ? 1'b0 :
                          (!debug_enable)  ? 1'b0 : debug_req_core_ungtd;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) dmi_del_cnt_q <= DmiDelCycles;
    else         dmi_del_cnt_q <= dmi_del_cnt_d;
  end

  // ------------------------------------------------------------------
  // Debug module (dm_top)
  // ------------------------------------------------------------------
  ariane_axi::req_t  dm_axi_m_req;
  ariane_axi::resp_t dm_axi_m_resp;
  ariane_axi::req_t  cva6_axi_req;
  ariane_axi::resp_t cva6_axi_resp;

  logic        dm_slave_req, dm_slave_we;
  logic [63:0] dm_slave_addr, dm_slave_wdata, dm_slave_rdata;
  logic [7:0]  dm_slave_be;

  logic        dm_master_req, dm_master_we, dm_master_gnt, dm_master_r_valid;
  logic [63:0] dm_master_add, dm_master_wdata, dm_master_r_rdata;
  logic [7:0]  dm_master_be;

  dm_top #(
    .NrHarts     ( soc_pkg::NB_CORES                              ),
    .BusWidth    ( AXI_DATA_WIDTH                                 ),
    .SelectableHarts ( {soc_pkg::NB_CORES{1'b1}}                 )
  ) i_dm_top (
    .clk_i            ( clk_i                                     ),
    .rst_ni           ( rst_ni                                    ),
    .testmode_i       ( test_en                                   ),
    .ndmreset_o       ( ndmreset                                  ),
    .dmactive_o       (                                           ),
    .debug_req_o      ( debug_req_core_ungtd                      ),
    .unavailable_i    ( '0                                        ),
    .hartinfo_i       ( {soc_pkg::NB_CORES{ariane_pkg::DebugHartInfo}} ),
    .slave_req_i      ( dm_slave_req                              ),
    .slave_we_i       ( dm_slave_we                               ),
    .slave_addr_i     ( dm_slave_addr                             ),
    .slave_be_i       ( dm_slave_be                               ),
    .slave_wdata_i    ( dm_slave_wdata                            ),
    .slave_rdata_o    ( dm_slave_rdata                            ),
    .master_req_o     ( dm_master_req                             ),
    .master_add_o     ( dm_master_add                             ),
    .master_we_o      ( dm_master_we                              ),
    .master_wdata_o   ( dm_master_wdata                           ),
    .master_be_o      ( dm_master_be                              ),
    .master_gnt_i     ( dm_master_gnt                             ),
    .master_r_valid_i ( dm_master_r_valid                         ),
    .master_r_rdata_i ( dm_master_r_rdata                         ),
    .dmi_rst_ni       ( rst_ni                                    ),
    .dmi_req_valid_i  ( debug_req_valid                           ),
    .dmi_req_ready_o  ( debug_req_ready                           ),
    .dmi_req_i        ( debug_req                                 ),
    .dmi_resp_valid_o ( debug_resp_valid                          ),
    .dmi_resp_ready_i ( debug_resp_ready                          ),
    .dmi_resp_o       ( debug_resp                                )
  );

  // Debug slave port: AXI → simple memory interface
  axi2mem #(
    .AXI_ID_WIDTH   ( soc_pkg::IdWidthSlave ),
    .AXI_ADDR_WIDTH ( AXI_ADDRESS_WIDTH     ),
    .AXI_DATA_WIDTH ( AXI_DATA_WIDTH        ),
    .AXI_USER_WIDTH ( AXI_USER_WIDTH        )
  ) i_dm_axi2mem (
    .clk_i  ( clk_i                       ),
    .rst_ni ( rst_ni                      ),
    .slave  ( master[soc_pkg::Debug]      ),
    .req_o  ( dm_slave_req                ),
    .we_o   ( dm_slave_we                 ),
    .addr_o ( dm_slave_addr               ),
    .be_o   ( dm_slave_be                 ),
    .user_o (                             ),
    .data_o ( dm_slave_wdata              ),
    .user_i ( '0                          ),
    .data_i ( dm_slave_rdata              )
  );

  // Debug master port: simple memory interface → AXI
  `AXI_ASSIGN_FROM_REQ(to_xbar[1], dm_axi_m_req)
  `AXI_ASSIGN_TO_RESP(dm_axi_m_resp, to_xbar[1])

  axi_adapter #(
    .DATA_WIDTH            ( AXI_DATA_WIDTH          ),
    .AXI_ADDR_WIDTH        ( AXI_ADDRESS_WIDTH        ),
    .AXI_DATA_WIDTH        ( AXI_DATA_WIDTH           ),
    .AXI_ID_WIDTH          ( soc_pkg::IdWidth         ),
    .axi_req_t             ( ariane_axi::req_t        ),
    .axi_rsp_t             ( ariane_axi::resp_t       )
  ) i_dm_axi_master (
    .clk_i                 ( clk_i                    ),
    .rst_ni                ( rst_ni                   ),
    .busy_o                (                          ),
    .req_i                 ( dm_master_req            ),
    .type_i                ( ariane_axi::SINGLE_REQ   ),
    .trans_type_i          ( ace_pkg::READ_NO_SNOOP   ),
    .amo_i                 ( ariane_pkg::AMO_NONE     ),
    .gnt_o                 ( dm_master_gnt            ),
    .addr_i                ( dm_master_add            ),
    .we_i                  ( dm_master_we             ),
    .wdata_i               ( dm_master_wdata          ),
    .be_i                  ( dm_master_be             ),
    .size_i                ( 2'b11                    ),
    .id_i                  ( '0                       ),
    .valid_o               ( dm_master_r_valid        ),
    .dirty_o               (                          ),
    .shared_o              (                          ),
    .rdata_o               ( dm_master_r_rdata        ),
    .id_o                  (                          ),
    .critical_word_o       (                          ),
    .critical_word_valid_o (                          ),
    .axi_req_o             ( dm_axi_m_req             ),
    .axi_resp_i            ( dm_axi_m_resp            )
  );

  // ------------------------------------------------------------------
  // Boot ROM
  // ------------------------------------------------------------------
  logic                         rom_req;
  logic [AXI_ADDRESS_WIDTH-1:0] rom_addr;
  logic [AXI_DATA_WIDTH-1:0]    rom_rdata;

  axi2mem #(
    .AXI_ID_WIDTH   ( soc_pkg::IdWidthSlave ),
    .AXI_ADDR_WIDTH ( AXI_ADDRESS_WIDTH     ),
    .AXI_DATA_WIDTH ( AXI_DATA_WIDTH        ),
    .AXI_USER_WIDTH ( AXI_USER_WIDTH        )
  ) i_axi2rom (
    .clk_i  ( clk_i                   ),
    .rst_ni ( ndmreset_n              ),
    .slave  ( master[soc_pkg::ROM]    ),
    .req_o  ( rom_req                 ),
    .we_o   (                         ),
    .addr_o ( rom_addr                ),
    .be_o   (                         ),
    .user_o (                         ),
    .data_o (                         ),
    .user_i ( '0                      ),
    .data_i ( rom_rdata               )
  );

  bootrom i_bootrom (
    .clk_i   ( clk_i     ),
    .req_i   ( rom_req   ),
    .addr_i  ( rom_addr  ),
    .rdata_o ( rom_rdata )
  );

  // ------------------------------------------------------------------
  // DRAM path: atomics wrapper → LLC (optional) → SRAM
  // ------------------------------------------------------------------
  AXI_BUS #(
    .AXI_ADDR_WIDTH ( AXI_ADDRESS_WIDTH  ),
    .AXI_DATA_WIDTH ( AXI_DATA_WIDTH     ),
    .AXI_ID_WIDTH   ( AXI_ID_WIDTH_DRAM  ),
    .AXI_USER_WIDTH ( AXI_USER_WIDTH     )
  ) dram();

  AXI_BUS #(
    .AXI_ADDR_WIDTH ( AXI_ADDRESS_WIDTH  ),
    .AXI_DATA_WIDTH ( AXI_DATA_WIDTH     ),
    .AXI_ID_WIDTH   ( AXI_ID_WIDTH_DRAM  ),
    .AXI_USER_WIDTH ( AXI_USER_WIDTH     )
  ) dram_delayed();

  AXI_BUS #(
    .AXI_ADDR_WIDTH ( AXI_ADDRESS_WIDTH      ),
    .AXI_DATA_WIDTH ( AXI_DATA_WIDTH         ),
    .AXI_ID_WIDTH   ( soc_pkg::IdWidthSlave  ),
    .AXI_USER_WIDTH ( AXI_USER_WIDTH         )
  ) to_llc();

  logic                         req, we;
  logic [AXI_ADDRESS_WIDTH-1:0] addr;
  logic [AXI_DATA_WIDTH/8-1:0]  be;
  logic [AXI_DATA_WIDTH-1:0]    wdata, rdata;
  logic [AXI_USER_WIDTH-1:0]    wuser, ruser;

  axi_riscv_atomics_wrap #(
    .AXI_ADDR_WIDTH     ( AXI_ADDRESS_WIDTH                        ),
    .AXI_DATA_WIDTH     ( AXI_DATA_WIDTH                           ),
    .AXI_ADDR_LSB       ( $clog2(ariane_pkg::DCACHE_LINE_WIDTH/8)  ),
    .AXI_ID_WIDTH       ( soc_pkg::IdWidthSlave                    ),
    .AXI_USER_WIDTH     ( AXI_USER_WIDTH                           ),
    .AXI_USER_AS_ID     ( 1'b1                                     ),
    .AXI_USER_ID_LSB    ( 0                                        ),
    .AXI_USER_ID_MSB    ( 0                                        ), // single core → 1 bit
    .AXI_MAX_READ_TXNS  ( 1                                        ),
    .AXI_MAX_WRITE_TXNS ( 1                                        ),
    .RISCV_WORD_WIDTH   ( riscv::XLEN                              )
  ) i_axi_riscv_atomics (
    .clk_i,
    .rst_ni ( ndmreset_n              ),
    .slv    ( master[soc_pkg::DRAM]   ),
    .mst    ( to_llc                  )
  );

  if (HasLLC) begin : gen_llc

    localparam int unsigned AxiStrbWidth = AXI_DATA_WIDTH / 8;

    typedef logic [soc_pkg::IdWidthSlave-1:0] axi_slv_id_t;
    typedef logic [AXI_ID_WIDTH_DRAM-1:0]     axi_mst_id_t;
    typedef logic [AXI_ADDRESS_WIDTH-1:0]     axi_addr_t;
    typedef logic [AXI_DATA_WIDTH-1:0]        axi_data_t;
    typedef logic [AxiStrbWidth-1:0]          axi_strb_t;
    typedef logic [AXI_USER_WIDTH-1:0]        axi_user_t;

    `AXI_TYPEDEF_AW_CHAN_T(axi_slv_aw_t, axi_addr_t, axi_slv_id_t, axi_user_t)
    `AXI_TYPEDEF_AW_CHAN_T(axi_mst_aw_t, axi_addr_t, axi_mst_id_t, axi_user_t)
    `AXI_TYPEDEF_W_CHAN_T(axi_w_t, axi_data_t, axi_strb_t, axi_user_t)
    `AXI_TYPEDEF_B_CHAN_T(axi_slv_b_t, axi_slv_id_t, axi_user_t)
    `AXI_TYPEDEF_B_CHAN_T(axi_mst_b_t, axi_mst_id_t, axi_user_t)
    `AXI_TYPEDEF_AR_CHAN_T(axi_slv_ar_t, axi_addr_t, axi_slv_id_t, axi_user_t)
    `AXI_TYPEDEF_AR_CHAN_T(axi_mst_ar_t, axi_addr_t, axi_mst_id_t, axi_user_t)
    `AXI_TYPEDEF_R_CHAN_T(axi_slv_r_t, axi_data_t, axi_slv_id_t, axi_user_t)
    `AXI_TYPEDEF_R_CHAN_T(axi_mst_r_t, axi_data_t, axi_mst_id_t, axi_user_t)

    `AXI_TYPEDEF_REQ_T(axi_slv_req_t, axi_slv_aw_t, axi_w_t, axi_slv_ar_t)
    `AXI_TYPEDEF_RESP_T(axi_slv_resp_t, axi_slv_b_t, axi_slv_r_t)
    `AXI_TYPEDEF_REQ_T(axi_mst_req_t, axi_mst_aw_t, axi_w_t, axi_mst_ar_t)
    `AXI_TYPEDEF_RESP_T(axi_mst_resp_t, axi_mst_b_t, axi_mst_r_t)

    `REG_BUS_TYPEDEF_ALL(conf, logic [31:0], logic [31:0], logic [3:0])

    typedef struct packed {
      int unsigned idx;
      axi_addr_t   start_addr;
      axi_addr_t   end_addr;
    } rule_full_t;

    axi_llc_pkg::events_t llc_events;
    axi_slv_req_t         axi_cpu_req;
    axi_slv_resp_t        axi_cpu_res;
    axi_mst_req_t         axi_mem_req;
    axi_mst_resp_t        axi_mem_res;
    conf_req_t            reg_cfg_req;
    conf_rsp_t            reg_cfg_rsp;

    assign reg_cfg_req = '0;

    localparam axi_addr_t SpmRegionStart       = axi_addr_t'(0);
    localparam axi_addr_t SpmRegionLength      = 0;
    localparam axi_addr_t L2CachedRegionStart  = axi_addr_t'(soc_pkg::DRAMBase);
    localparam axi_addr_t L2CachedRegionLength = axi_addr_t'(soc_pkg::DRAMLength);

    `AXI_ASSIGN_TO_REQ(axi_cpu_req, to_llc)
    `AXI_ASSIGN_FROM_RESP(to_llc, axi_cpu_res)
    `AXI_ASSIGN_FROM_REQ(dram, axi_mem_req)
    `AXI_ASSIGN_TO_RESP(axi_mem_res, dram)

    axi_llc_reg_wrap #(
      .SetAssociativity ( 32'd8                      ),
      .NumLines         ( 32'd256                    ),
      .NumBlocks        ( 32'd8                      ),
      .AxiIdWidth       ( soc_pkg::IdWidthSlave      ),
      .AxiAddrWidth     ( AXI_ADDRESS_WIDTH          ),
      .AxiDataWidth     ( AXI_DATA_WIDTH             ),
      .AxiUserWidth     ( AXI_USER_WIDTH             ),
      .slv_req_t        ( axi_slv_req_t              ),
      .slv_resp_t       ( axi_slv_resp_t             ),
      .mst_req_t        ( axi_mst_req_t              ),
      .mst_resp_t       ( axi_mst_resp_t             ),
      .reg_req_t        ( conf_req_t                 ),
      .reg_resp_t       ( conf_rsp_t                 ),
      .rule_full_t      ( rule_full_t                )
    ) i_axi_llc (
      .clk_i               ( clk_i                                         ),
      .rst_ni              ( ndmreset_n                                    ),
      .test_i              ( 1'b0                                          ),
      .slv_req_i           ( axi_cpu_req                                   ),
      .slv_resp_o          ( axi_cpu_res                                   ),
      .mst_req_o           ( axi_mem_req                                   ),
      .mst_resp_i          ( axi_mem_res                                   ),
      .conf_req_i          ( reg_cfg_req                                   ),
      .conf_resp_o         ( reg_cfg_rsp                                   ),
      .cached_start_addr_i ( L2CachedRegionStart                           ),
      .cached_end_addr_i   ( L2CachedRegionStart + L2CachedRegionLength    ),
      .spm_start_addr_i    ( SpmRegionStart                                ),
      .axi_llc_events_o    ( llc_events                                    )
    );

    // Tap exit address on the LLC input (writes to DRAM base)
    AXI_BUS #(
      .AXI_ADDR_WIDTH ( AXI_ADDRESS_WIDTH      ),
      .AXI_DATA_WIDTH ( AXI_DATA_WIDTH         ),
      .AXI_ID_WIDTH   ( soc_pkg::IdWidthSlave  ),
      .AXI_USER_WIDTH ( AXI_USER_WIDTH         )
    ) to_llc_exit();

    logic                         exit_req, exit_we;
    logic [AXI_ADDRESS_WIDTH-1:0] exit_addr;
    logic [AXI_DATA_WIDTH-1:0]    exit_wdata;

    axi_slv_req_t llc_exit_req, llc_exit_req_aw_only;

    `AXI_ASSIGN_TO_REQ(llc_exit_req, to_llc)
    always_comb begin
      llc_exit_req_aw_only          = llc_exit_req;
      llc_exit_req_aw_only.ar_valid = 0;
    end
    `AXI_ASSIGN_FROM_REQ(to_llc_exit, llc_exit_req_aw_only)

    axi2mem #(
      .AXI_ID_WIDTH   ( soc_pkg::IdWidthSlave ),
      .AXI_ADDR_WIDTH ( AXI_ADDRESS_WIDTH     ),
      .AXI_DATA_WIDTH ( AXI_DATA_WIDTH        ),
      .AXI_USER_WIDTH ( AXI_USER_WIDTH        )
    ) i_axi2exit (
      .clk_i  ( clk_i       ),
      .rst_ni ( ndmreset_n  ),
      .slave  ( to_llc_exit ),
      .req_o  ( exit_req    ),
      .we_o   ( exit_we     ),
      .addr_o ( exit_addr   ),
      .be_o   (             ),
      .user_o (             ),
      .data_o ( exit_wdata  ),
      .user_i ( '0          ),
      .data_i ( '0          )
    );

    assign exit_o = (exit_req & exit_we & exit_addr == soc_pkg::exitAddr) ? exit_wdata : '0;

  end else begin : gen_no_llc

    `AXI_ASSIGN(dram, to_llc)
    assign exit_o = (req & we & addr == soc_pkg::exitAddr) ? wdata : '0;

  end

  // AXI delayer (optional stall injection for testing)
  axi_delayer_intf #(
    .AXI_ID_WIDTH        ( AXI_ID_WIDTH_DRAM    ),
    .AXI_ADDR_WIDTH      ( AXI_ADDRESS_WIDTH    ),
    .AXI_DATA_WIDTH      ( AXI_DATA_WIDTH       ),
    .AXI_USER_WIDTH      ( AXI_USER_WIDTH       ),
    .STALL_RANDOM_INPUT  ( StallRandomInput     ),
    .STALL_RANDOM_OUTPUT ( StallRandomOutput    ),
    .FIXED_DELAY_INPUT   ( FixedDelayInput      ),
    .FIXED_DELAY_OUTPUT  ( FixedDelayOutput     )
  ) i_axi_delayer (
    .clk_i  ( clk_i        ),
    .rst_ni ( ndmreset_n   ),
    .slv    ( dram         ),
    .mst    ( dram_delayed )
  );

  // SRAM backing the DRAM address space
  axi2mem #(
    .AXI_ID_WIDTH   ( AXI_ID_WIDTH_DRAM ),
    .AXI_ADDR_WIDTH ( AXI_ADDRESS_WIDTH ),
    .AXI_DATA_WIDTH ( AXI_DATA_WIDTH    ),
    .AXI_USER_WIDTH ( AXI_USER_WIDTH    )
  ) i_axi2mem (
    .clk_i  ( clk_i        ),
    .rst_ni ( ndmreset_n   ),
    .slave  ( dram_delayed ),
    .req_o  ( req          ),
    .we_o   ( we           ),
    .addr_o ( addr         ),
    .be_o   ( be           ),
    .user_o ( wuser        ),
    .data_o ( wdata        ),
    .user_i ( ruser        ),
    .data_i ( rdata        )
  );

  sram #(
    .DATA_WIDTH ( AXI_DATA_WIDTH ),
    .USER_WIDTH ( AXI_USER_WIDTH ),
    .USER_EN    ( AXI_USER_EN    ),
`ifdef VERILATOR
    .SIM_INIT   ( "none"         ),
`else
    .SIM_INIT   ( "random"       ),
`endif
    .NUM_WORDS  ( NUM_WORDS      )
  ) i_sram (
    .clk_i   ( clk_i                                                                        ),
    .rst_ni  ( rst_ni                                                                       ),
    .req_i   ( req                                                                          ),
    .we_i    ( we                                                                           ),
    .addr_i  ( addr[$clog2(NUM_WORDS)-1+$clog2(AXI_DATA_WIDTH/8):$clog2(AXI_DATA_WIDTH/8)] ),
    .wuser_i ( wuser                                                                        ),
    .wdata_i ( wdata                                                                        ),
    .be_i    ( be                                                                           ),
    .ruser_o ( ruser                                                                        ),
    .rdata_o ( rdata                                                                        )
  );

  // ------------------------------------------------------------------
  // AXI Crossbar
  // ------------------------------------------------------------------
  axi_pkg::xbar_rule_64_t [soc_pkg::NB_PERIPHERALS-1:0] addr_map;

  assign addr_map = '{
    '{ idx: soc_pkg::DRAM,     start_addr: soc_pkg::DRAMBase,     end_addr: soc_pkg::DRAMBase     + soc_pkg::DRAMLength     },
    '{ idx: soc_pkg::FlexSpad, start_addr: soc_pkg::FlexSpadBase, end_addr: soc_pkg::FlexSpadBase + soc_pkg::FlexSpadLength },
    '{ idx: soc_pkg::FlexRegs, start_addr: soc_pkg::FlexRegsBase, end_addr: soc_pkg::FlexRegsBase + soc_pkg::FlexRegsLength },
    '{ idx: soc_pkg::SPI,      start_addr: soc_pkg::SPIBase,      end_addr: soc_pkg::SPIBase      + soc_pkg::SPILength      },
    '{ idx: soc_pkg::Timer,    start_addr: soc_pkg::TimerBase,    end_addr: soc_pkg::TimerBase    + soc_pkg::TimerLength    },
    '{ idx: soc_pkg::UART,     start_addr: soc_pkg::UARTBase,     end_addr: soc_pkg::UARTBase     + soc_pkg::UARTLength     },
    '{ idx: soc_pkg::PLIC,     start_addr: soc_pkg::PLICBase,     end_addr: soc_pkg::PLICBase     + soc_pkg::PLICLength     },
    '{ idx: soc_pkg::CLINT,    start_addr: soc_pkg::CLINTBase,    end_addr: soc_pkg::CLINTBase    + soc_pkg::CLINTLength    },
    '{ idx: soc_pkg::ROM,      start_addr: soc_pkg::ROMBase,      end_addr: soc_pkg::ROMBase      + soc_pkg::ROMLength      },
    '{ idx: soc_pkg::Debug,    start_addr: soc_pkg::DebugBase,    end_addr: soc_pkg::DebugBase    + soc_pkg::DebugLength    }
  };

  localparam axi_pkg::xbar_cfg_t AXI_XBAR_CFG = '{
    NoSlvPorts:          soc_pkg::NrMasters,
    NoMstPorts:          soc_pkg::NB_PERIPHERALS,
    MaxMstTrans:         2,
    MaxSlvTrans:         2,
    FallThrough:         1'b0,
    PipelineStages:      1,
    LatencyMode:         axi_pkg::CUT_ALL_PORTS,
    AxiIdWidthSlvPorts:  soc_pkg::IdWidthToXbar,
    AxiIdUsedSlvPorts:   soc_pkg::IdWidthToXbar,
    UniqueIds:           1'b0,
    AxiAddrWidth:        AXI_ADDRESS_WIDTH,
    AxiDataWidth:        AXI_DATA_WIDTH,
    NoAddrRules:         soc_pkg::NB_PERIPHERALS
  };

  axi_xbar_intf #(
    .AXI_USER_WIDTH ( AXI_USER_WIDTH          ),
    .Cfg            ( AXI_XBAR_CFG            ),
    .rule_t         ( axi_pkg::xbar_rule_64_t )
  ) i_axi_xbar (
    .clk_i                 ( clk_i      ),
    .rst_ni                ( ndmreset_n ),
    .test_i                ( test_en    ),
    .slv_ports             ( to_xbar    ),
    .mst_ports             ( master     ),
    .addr_map_i            ( addr_map   ),
    .en_default_mst_port_i ( '0         ),
    .default_mst_port_i    ( '0         )
  );

  // ------------------------------------------------------------------
  // CLINT
  // ------------------------------------------------------------------
  logic ipi, timer_irq;

  soc_pkg::req_slv_t  axi_clint_req;
  soc_pkg::resp_slv_t axi_clint_resp;

  clint #(
    .AXI_ADDR_WIDTH ( AXI_ADDRESS_WIDTH        ),
    .AXI_DATA_WIDTH ( AXI_DATA_WIDTH           ),
    .AXI_ID_WIDTH   ( soc_pkg::IdWidthSlave    ),
    .NR_CORES       ( soc_pkg::NB_CORES        ),
    .axi_req_t      ( soc_pkg::req_slv_t       ),
    .axi_resp_t     ( soc_pkg::resp_slv_t      )
  ) i_clint (
    .clk_i       ( clk_i           ),
    .rst_ni      ( ndmreset_n      ),
    .testmode_i  ( test_en         ),
    .axi_req_i   ( axi_clint_req   ),
    .axi_resp_o  ( axi_clint_resp  ),
    .rtc_i       ( rtc_i           ),
    .timer_irq_o ( timer_irq       ),
    .ipi_o       ( ipi             )
  );

  `AXI_ASSIGN_TO_REQ(axi_clint_req, master[soc_pkg::CLINT])
  `AXI_ASSIGN_FROM_RESP(master[soc_pkg::CLINT], axi_clint_resp)

  // ------------------------------------------------------------------
  // Peripherals (PLIC, UART, SPI, Timer)
  // ------------------------------------------------------------------
  logic tx, rx;
  logic [soc_pkg::NumTargets-1:0] irqs;

  soc_peripherals #(
    .AxiAddrWidth ( AXI_ADDRESS_WIDTH       ),
    .AxiDataWidth ( AXI_DATA_WIDTH          ),
    .AxiIdWidth   ( soc_pkg::IdWidthSlave   ),
    .AxiUserWidth ( AXI_USER_WIDTH          ),
    .InclUART     ( 1'b0                    ), // use mock UART in simulation
    .InclSPI      ( 1'b0                    ),
    .InclEthernet ( 1'b0                    ),
    .InclGPIO     ( 1'b0                    ),
    .InclTimer    ( 1'b1                    )
  ) i_peripherals (
    .clk_i     ( clk_i                      ),
    .rst_ni    ( ndmreset_n                 ),
    .plic      ( master[soc_pkg::PLIC]      ),
    .uart      ( master[soc_pkg::UART]      ),
    .spi       ( master[soc_pkg::SPI]       ),
    .ethernet  ( ethernet_dummy             ),
    .timer     ( master[soc_pkg::Timer]     ),
    .irq_o     ( irqs                       ),
    .rx_i      ( rx                         ),
    .tx_o      ( tx                         ),
    .eth_txck  ( ),
    .eth_rxck  ( ),
    .eth_rxctl ( ),
    .eth_rxd   ( ),
    .eth_rst_n ( ),
    .eth_tx_en ( ),
    .eth_txd   ( ),
    .phy_mdio  ( ),
    .eth_mdc   ( ),
    .mdio      ( ),
    .mdc       ( ),
    .spi_clk_o ( ),
    .spi_mosi  ( ),
    .spi_miso  ( ),
    .spi_ss    ( )
  );

  // Mock UART for simulation output
  uart_bus #(.BAUD_RATE(115200), .PARITY_EN(0)) i_uart_bus
    (.rx(tx), .tx(rx), .rx_en(1'b1));

  // ------------------------------------------------------------------
  // FleXNNgine accelerator
  // ------------------------------------------------------------------
  flexnngine_wrap #(
    .AxiAddrWidth ( AXI_ADDRESS_WIDTH      ),
    .AxiDataWidth ( AXI_DATA_WIDTH         ),
    .AxiIdWidth   ( soc_pkg::IdWidthSlave  ),
    .AxiUserWidth ( AXI_USER_WIDTH         ),
    .AxiAccCDC    ( 1'b0                   ) // no CDC needed in simulation (single clock)
  ) i_flexnngine (
    .clk_axi_i   ( clk_i                       ),
    .clk_array_i ( clk_i                       ),
    .clk_spad_i  ( clk_i                       ),
    .rst_ni      ( ndmreset_n                  ),
    .regs        ( master[soc_pkg::FlexRegs]   ),
    .spad        ( master[soc_pkg::FlexSpad]   ),
    .irq_o       (                             )
  );

  // ------------------------------------------------------------------
  // Single CVA6 core (non-coherent). ACE types are used so that the
  // cache-subsystem files type-check in both branches of their
  // if (DCACHE_COHERENT) / if (AxiAce) generate blocks; the snoop/ACE
  // channels are driven to 0 by the else-branch logic.
  // ------------------------------------------------------------------
  ariane_ace::req_t  axi_ariane_req;
  ariane_ace::resp_t axi_ariane_resp;

  ariane #(
    .ArianeCfg    ( ArianeCfg              ),
    .AxiAddrWidth ( AXI_ADDRESS_WIDTH      ),
    .AxiDataWidth ( AXI_DATA_WIDTH         ),
    .AxiIdWidth   ( soc_pkg::IdWidth       ),
    .axi_ar_chan_t( ariane_ace::ar_chan_t  ),
    .axi_aw_chan_t( ariane_ace::aw_chan_t  ),
    .axi_w_chan_t ( ariane_axi::w_chan_t   ),
    .axi_req_t    ( ariane_ace::req_t      ),
    .axi_rsp_t    ( ariane_ace::resp_t     )
  ) i_ariane (
    .clk_i        ( clk_i               ),
    .rst_ni       ( ndmreset_n          ),
    .boot_addr_i  ( BootAddress         ),
    .hart_id_i    ( 64'h0               ),
    .irq_i        ( irqs[1:0]           ),
    .ipi_i        ( ipi                 ),
    .time_irq_i   ( timer_irq           ),
    .debug_req_i  ( debug_req_core      ),
    .axi_req_o    ( axi_ariane_req      ),
    .axi_resp_i   ( axi_ariane_resp     )
  );

  `AXI_ASSIGN_FROM_REQ(to_xbar[0], axi_ariane_req)
  `AXI_ASSIGN_TO_RESP(axi_ariane_resp, to_xbar[0])

  // ------------------------------------------------------------------
  // Simulation helpers: catch AXI error responses
  // ------------------------------------------------------------------
  always_ff @(posedge clk_i) begin
    if (axi_ariane_req.r_ready  && axi_ariane_resp.r_valid &&
        axi_ariane_resp.r.resp inside {axi_pkg::RESP_DECERR, axi_pkg::RESP_SLVERR})
      $warning("R Response Errored");
    if (axi_ariane_req.b_ready  && axi_ariane_resp.b_valid &&
        axi_ariane_resp.b.resp inside {axi_pkg::RESP_DECERR, axi_pkg::RESP_SLVERR})
      $warning("B Response Errored");
  end

endmodule
