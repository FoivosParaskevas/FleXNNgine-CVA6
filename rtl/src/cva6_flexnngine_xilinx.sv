// Copyright 2018 ETH Zurich and University of Bologna.
// Copyright 2022 PlanV GmbH
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.

// Description: Single CVA6 + FleXNNgine — VCU118 FPGA top-level.
// A single CVA6 core connects directly to the AXI crossbar (no coherence unit).

`include "vcu118.svh"
`include "axi/assign.svh"
`include "axi/typedef.svh"
`include "register_interface/typedef.svh"

module cva6_flexnngine_xilinx
  import soc_pkg::*;
(
  input  wire          c0_sys_clk_p    ,  // 250 MHz Clock for DDR4
  input  wire          c0_sys_clk_n    ,  // 250 MHz Clock for DDR4
  input  logic         cpu_reset       ,  // CPU subsystem reset (active-high)
  output wire [16:0]   c0_ddr4_adr     ,
  output wire [1:0]    c0_ddr4_ba      ,
  output wire [0:0]    c0_ddr4_cke     ,
  output wire [0:0]    c0_ddr4_cs_n    ,
  inout  wire [7:0]    c0_ddr4_dm_dbi_n,
  inout  wire [63:0]   c0_ddr4_dq      ,
  inout  wire [7:0]    c0_ddr4_dqs_c   ,
  inout  wire [7:0]    c0_ddr4_dqs_t   ,
  output wire [0:0]    c0_ddr4_odt     ,
  output wire [0:0]    c0_ddr4_bg      ,
  output wire          c0_ddr4_reset_n ,
  output wire          c0_ddr4_act_n   ,
  output wire [0:0]    c0_ddr4_ck_c    ,
  output wire [0:0]    c0_ddr4_ck_t    ,
  // JTAG power rails (drive to 1/0 to power target via level-shifter)
  output logic         jtag_vdd_o      ,
  output logic         jtag_gnd_o      ,
  // JTAG
  input  logic         tck             ,
  input  logic         tms             ,
  input  logic         tdi             ,
  output wire          tdo             ,
  // UART
  input  logic         rx              ,
  output logic         tx
);

// ---------------------------------------------------------------------------
// Local parameters (copy package constants to work around Vivado limitations)
// ---------------------------------------------------------------------------
localparam bit HasLLC = 1'b1;

localparam int unsigned NB_CORES_LP        = soc_pkg::NB_CORES;
localparam int unsigned NrMasters_LP       = soc_pkg::NrMasters;
localparam int unsigned IdWidth_LP         = soc_pkg::IdWidth;
localparam int unsigned IdWidthToXbar_LP   = soc_pkg::IdWidthToXbar;
localparam int unsigned IdWidthSlave_LP    = soc_pkg::IdWidthSlave;
localparam int unsigned NB_PERIPHERALS_LP  = soc_pkg::NB_PERIPHERALS;
localparam int unsigned NumTargets_LP      = soc_pkg::NumTargets;

localparam int unsigned AxiAddrWidth  = 64;
localparam int unsigned AxiDataWidth  = 64;
localparam int unsigned AxiUserWidth  = ariane_pkg::AXI_USER_WIDTH;
localparam int unsigned AxiIdWidthSlaves = IdWidthSlave_LP;
// LLC adds 1 bit to the DRAM-side ID width
localparam int unsigned AxiIdWidthDram = HasLLC ? AxiIdWidthSlaves + 1 : AxiIdWidthSlaves;
localparam int unsigned AxiStrbWidth   = AxiDataWidth / 8;

localparam ariane_pkg::ariane_cfg_t ArianeCfg = soc_pkg::ArianeFpgaSocCfg;

// ---------------------------------------------------------------------------
// AXI type macros
// ---------------------------------------------------------------------------
`AXI_TYPEDEF_ALL(axi_slave,
                 logic [    AxiAddrWidth-1:0],
                 logic [AxiIdWidthSlaves-1:0],
                 logic [    AxiDataWidth-1:0],
                 logic [   AxiStrbWidth-1:0],
                 logic [    AxiUserWidth-1:0])

// ---------------------------------------------------------------------------
// AXI bus interfaces
// ---------------------------------------------------------------------------
// to_xbar[0] = CVA6,  to_xbar[1] = debug module
AXI_BUS #(
    .AXI_ADDR_WIDTH ( AxiAddrWidth      ),
    .AXI_DATA_WIDTH ( AxiDataWidth      ),
    .AXI_ID_WIDTH   ( IdWidthToXbar_LP  ),
    .AXI_USER_WIDTH ( AxiUserWidth      )
) to_xbar[NrMasters_LP-1:0]();

// master[] = peripheral slave ports from xbar
AXI_BUS #(
    .AXI_ADDR_WIDTH ( AxiAddrWidth      ),
    .AXI_DATA_WIDTH ( AxiDataWidth      ),
    .AXI_ID_WIDTH   ( AxiIdWidthSlaves  ),
    .AXI_USER_WIDTH ( AxiUserWidth      )
) master[NB_PERIPHERALS_LP-1:0]();


// ---------------------------------------------------------------------------
// Global signals
// ---------------------------------------------------------------------------
logic test_en;
logic ndmreset;
logic ndmreset_n;
logic [NB_CORES_LP-1:0] debug_req_irq;
logic [NB_CORES_LP-1:0] ipi;
logic [NB_CORES_LP-1:0] timer_irq;

logic clk;
logic sd_clk_sys;
logic phy_tx_clk;
logic eth_clk;

// SPI removed — dummy locals absorb the soc_peripherals SPI outputs
logic spi_clk_o_nc;
logic spi_mosi_nc;
logic spi_ss_nc;

logic ddr_sync_reset;
logic ddr_clock_out;
logic ddr_clock_out_200;
logic calib_complete; // DDR4 calibration complete; gates CPU reset

logic rst_n;
logic rtc;

// VCU118 reset polarity: cpu_reset is active-high, rst_n is active-low
logic cpu_resetn;
assign cpu_resetn = ~cpu_reset;

logic pll_locked;

// ROM
logic                    rom_req;
logic [AxiAddrWidth-1:0] rom_addr;
logic [AxiDataWidth-1:0] rom_rdata;

// Debug
logic          debug_req_valid;
logic          debug_req_ready;
dm::dmi_req_t  debug_req;
logic          debug_resp_valid;
logic          debug_resp_ready;
dm::dmi_resp_t debug_resp;
logic          dmactive;

// IRQ
logic [NumTargets_LP-1:0] irq;

assign test_en    = 1'b0;
assign rst_n      = ~ddr_sync_reset;

// JTAG power rails
assign jtag_vdd_o = 1'b1;
assign jtag_gnd_o = 1'b0;

// JTAG trst_n: not brought out as a pin, tie high
logic trst_n;
assign trst_n = 1'b1;

// ---------------------------------------------------------------------------
// Reset synchroniser
// ---------------------------------------------------------------------------
rstgen i_rstgen_main (
    .clk_i        ( clk                      ),
    .rst_ni       ( pll_locked & calib_complete & (~ndmreset) ),
    .test_mode_i  ( test_en                                  ),
    .rst_no       ( ndmreset_n                               ),
    .init_no      (                                          )
);

// ---------------------------------------------------------------------------
// AXI Crossbar
// ---------------------------------------------------------------------------
axi_pkg::xbar_rule_64_t [NB_PERIPHERALS_LP-1:0] addr_map;

assign addr_map = '{
  '{ idx: soc_pkg::Debug,    start_addr: soc_pkg::DebugBase,    end_addr: soc_pkg::DebugBase    + soc_pkg::DebugLength    },
  '{ idx: soc_pkg::ROM,      start_addr: soc_pkg::ROMBase,      end_addr: soc_pkg::ROMBase      + soc_pkg::ROMLength      },
  '{ idx: soc_pkg::CLINT,    start_addr: soc_pkg::CLINTBase,    end_addr: soc_pkg::CLINTBase    + soc_pkg::CLINTLength    },
  '{ idx: soc_pkg::PLIC,     start_addr: soc_pkg::PLICBase,     end_addr: soc_pkg::PLICBase     + soc_pkg::PLICLength     },
  '{ idx: soc_pkg::UART,     start_addr: soc_pkg::UARTBase,     end_addr: soc_pkg::UARTBase     + soc_pkg::UARTLength     },
  '{ idx: soc_pkg::Timer,    start_addr: soc_pkg::TimerBase,    end_addr: soc_pkg::TimerBase    + soc_pkg::TimerLength    },
  '{ idx: soc_pkg::SPI,      start_addr: soc_pkg::SPIBase,      end_addr: soc_pkg::SPIBase      + soc_pkg::SPILength      },
  '{ idx: soc_pkg::FlexRegs, start_addr: soc_pkg::FlexRegsBase, end_addr: soc_pkg::FlexRegsBase + soc_pkg::FlexRegsLength },
  '{ idx: soc_pkg::FlexSpad, start_addr: soc_pkg::FlexSpadBase, end_addr: soc_pkg::FlexSpadBase + soc_pkg::FlexSpadLength },
  '{ idx: soc_pkg::DRAM,     start_addr: soc_pkg::DRAMBase,     end_addr: soc_pkg::DRAMBase     + soc_pkg::DRAMLength + 32'h1000 }
};

localparam axi_pkg::xbar_cfg_t AXI_XBAR_CFG = '{
  NoSlvPorts:         NrMasters_LP,
  NoMstPorts:         NB_PERIPHERALS_LP,
  MaxMstTrans:        1,
  MaxSlvTrans:        1,
  FallThrough:        1'b0,
  PipelineStages:     1,
  LatencyMode:        axi_pkg::CUT_ALL_PORTS,
  AxiIdWidthSlvPorts: IdWidthToXbar_LP,
  AxiIdUsedSlvPorts:  IdWidthToXbar_LP,
  UniqueIds:          1'b0,
  AxiAddrWidth:       AxiAddrWidth,
  AxiDataWidth:       AxiDataWidth,
  NoAddrRules:        NB_PERIPHERALS_LP
};

axi_xbar_intf #(
  .AXI_USER_WIDTH ( AxiUserWidth            ),
  .Cfg            ( AXI_XBAR_CFG            ),
  .rule_t         ( axi_pkg::xbar_rule_64_t )
) i_axi_xbar (
  .clk_i                 ( clk        ),
  .rst_ni                ( ndmreset_n ),
  .test_i                ( test_en    ),
  .slv_ports             ( to_xbar    ),
  .mst_ports             ( master     ),
  .addr_map_i            ( addr_map   ),
  .en_default_mst_port_i ( '0         ),
  .default_mst_port_i    ( '0         )
);

// ---------------------------------------------------------------------------
// JTAG / Debug Module Interface
// ---------------------------------------------------------------------------
dmi_jtag i_dmi_jtag (
    .clk_i                ( clk              ),
    .rst_ni               ( rst_n            ),
    .dmi_rst_no           (                  ),
    .testmode_i           ( test_en          ),
    .dmi_req_valid_o      ( debug_req_valid  ),
    .dmi_req_ready_i      ( debug_req_ready  ),
    .dmi_req_o            ( debug_req        ),
    .dmi_resp_valid_i     ( debug_resp_valid ),
    .dmi_resp_ready_o     ( debug_resp_ready ),
    .dmi_resp_i           ( debug_resp       ),
    .tck_i                ( tck              ),
    .tms_i                ( tms              ),
    .trst_ni              ( trst_n           ),
    .td_i                 ( tdi              ),
    .td_o                 ( tdo              ),
    .tdo_oe_o             (                  )
);

ariane_axi::req_t  dm_axi_m_req;
ariane_axi::resp_t dm_axi_m_resp;

logic                      dm_slave_req;
logic                      dm_slave_we;
logic [riscv::XLEN-1:0]    dm_slave_addr;
logic [riscv::XLEN/8-1:0]  dm_slave_be;
logic [riscv::XLEN-1:0]    dm_slave_wdata;
logic [riscv::XLEN-1:0]    dm_slave_rdata;

logic                      dm_master_req;
logic [riscv::XLEN-1:0]    dm_master_add;
logic                      dm_master_we;
logic [riscv::XLEN-1:0]    dm_master_wdata;
logic [riscv::XLEN/8-1:0]  dm_master_be;
logic                      dm_master_gnt;
logic                      dm_master_r_valid;
logic [riscv::XLEN-1:0]    dm_master_r_rdata;

dm_top #(
    .NrHarts          ( NB_CORES_LP               ),
    .BusWidth         ( riscv::XLEN               ),
    .SelectableHarts  ( {NB_CORES_LP{1'b1}}       )
) i_dm_top (
    .clk_i            ( clk                       ),
    .rst_ni           ( rst_n                     ),
    .testmode_i       ( test_en                   ),
    .ndmreset_o       ( ndmreset                  ),
    .dmactive_o       ( dmactive                  ),
    .debug_req_o      ( debug_req_irq             ),
    .unavailable_i    ( '0                        ),
    .hartinfo_i       ( {NB_CORES_LP{ariane_pkg::DebugHartInfo}} ),
    .slave_req_i      ( dm_slave_req              ),
    .slave_we_i       ( dm_slave_we               ),
    .slave_addr_i     ( dm_slave_addr             ),
    .slave_be_i       ( dm_slave_be               ),
    .slave_wdata_i    ( dm_slave_wdata            ),
    .slave_rdata_o    ( dm_slave_rdata            ),
    .master_req_o     ( dm_master_req             ),
    .master_add_o     ( dm_master_add             ),
    .master_we_o      ( dm_master_we              ),
    .master_wdata_o   ( dm_master_wdata           ),
    .master_be_o      ( dm_master_be              ),
    .master_gnt_i     ( dm_master_gnt             ),
    .master_r_valid_i ( dm_master_r_valid         ),
    .master_r_rdata_i ( dm_master_r_rdata         ),
    .dmi_rst_ni       ( rst_n                     ),
    .dmi_req_valid_i  ( debug_req_valid           ),
    .dmi_req_ready_o  ( debug_req_ready           ),
    .dmi_req_i        ( debug_req                 ),
    .dmi_resp_valid_o ( debug_resp_valid          ),
    .dmi_resp_ready_i ( debug_resp_ready          ),
    .dmi_resp_o       ( debug_resp                )
);

// Debug slave port: xbar master[Debug] → dm_top
axi2mem #(
    .AXI_ID_WIDTH   ( AxiIdWidthSlaves ),
    .AXI_ADDR_WIDTH ( riscv::XLEN      ),
    .AXI_DATA_WIDTH ( riscv::XLEN      ),
    .AXI_USER_WIDTH ( AxiUserWidth     )
) i_dm_axi2mem (
    .clk_i  ( clk                     ),
    .rst_ni ( rst_n                   ),
    .slave  ( master[soc_pkg::Debug]  ),
    .req_o  ( dm_slave_req            ),
    .we_o   ( dm_slave_we             ),
    .addr_o ( dm_slave_addr           ),
    .be_o   ( dm_slave_be             ),
    .data_o ( dm_slave_wdata          ),
    .data_i ( dm_slave_rdata          )
);


// Debug AXI master: dm_top → to_xbar[1]
logic [1:0] debug_req_bits_op;
assign debug_req.op = dm::dtm_op_e'(debug_req_bits_op);

logic [1:0] axi_adapter_size;
assign axi_adapter_size = (riscv::XLEN == 64) ? 2'b11 : 2'b10;

axi_adapter #(
    .DATA_WIDTH            ( riscv::XLEN          ),
    .AXI_ADDR_WIDTH        ( AxiAddrWidth         ),
    .AXI_DATA_WIDTH        ( AxiDataWidth         ),
    .AXI_ID_WIDTH          ( soc_pkg::IdWidth     ),
    .axi_req_t             ( ariane_axi::req_t    ),
    .axi_rsp_t             ( ariane_axi::resp_t   )
) i_dm_axi_master (
    .clk_i                 ( clk                    ),
    .rst_ni                ( rst_n                  ),
    .req_i                 ( dm_master_req          ),
    .type_i                ( ariane_axi::SINGLE_REQ ),
    .trans_type_i          ( ace_pkg::READ_NO_SNOOP ),
    .amo_i                 ( ariane_pkg::AMO_NONE   ),
    .gnt_o                 ( dm_master_gnt          ),
    .addr_i                ( dm_master_add          ),
    .we_i                  ( dm_master_we           ),
    .wdata_i               ( dm_master_wdata        ),
    .be_i                  ( dm_master_be           ),
    .size_i                ( axi_adapter_size       ),
    .id_i                  ( '0                     ),
    .valid_o               ( dm_master_r_valid      ),
    .rdata_o               ( dm_master_r_rdata      ),
    .id_o                  (                        ),
    .critical_word_o       (                        ),
    .critical_word_valid_o (                        ),
    .dirty_o               (                        ),
    .shared_o              (                        ),
    .busy_o                (                        ),
    .axi_req_o             ( dm_axi_m_req           ),
    .axi_resp_i            ( dm_axi_m_resp          )
);

`AXI_ASSIGN_FROM_REQ(to_xbar[1], dm_axi_m_req)
`AXI_ASSIGN_TO_RESP(dm_axi_m_resp, to_xbar[1])

// ---------------------------------------------------------------------------
// Single CVA6 core (plain AXI4, no ACE)
// ---------------------------------------------------------------------------
ariane_axi::req_t  axi_ariane_req;
ariane_axi::resp_t axi_ariane_resp;

ariane #(
    .ArianeCfg     ( ArianeCfg            ),
    .AxiAddrWidth  ( AxiAddrWidth         ),
    .AxiDataWidth  ( AxiDataWidth         ),
    .AxiIdWidth    ( soc_pkg::IdWidth     ),
    .axi_ar_chan_t ( ariane_axi::ar_chan_t ),
    .axi_aw_chan_t ( ariane_axi::aw_chan_t ),
    .axi_w_chan_t  ( ariane_axi::w_chan_t  ),
    .axi_req_t     ( ariane_axi::req_t     ),
    .axi_rsp_t     ( ariane_axi::resp_t    )
) i_ariane (
    .clk_i        ( clk                   ),
    .rst_ni       ( ndmreset_n            ),
    .boot_addr_i  ( soc_pkg::ROMBase      ),
    .hart_id_i    ( 64'h0                 ),
    .irq_i        ( irq[1:0]              ),
    .ipi_i        ( ipi[0]               ),
    .time_irq_i   ( timer_irq[0]         ),
    .debug_req_i  ( debug_req_irq[0]     ),
    .axi_req_o    ( axi_ariane_req        ),
    .axi_resp_i   ( axi_ariane_resp       )
);

`AXI_ASSIGN_FROM_REQ(to_xbar[0], axi_ariane_req)
`AXI_ASSIGN_TO_RESP(axi_ariane_resp, to_xbar[0])

// ---------------------------------------------------------------------------
// CLINT
// ---------------------------------------------------------------------------
// Generate RTC from clk (divide by 2)
always_ff @(posedge clk or negedge ndmreset_n) begin
  if (~ndmreset_n) begin
    rtc <= 0;
  end else begin
    rtc <= rtc ^ 1'b1;
  end
end

axi_slave_req_t  axi_clint_req;
axi_slave_resp_t axi_clint_resp;

clint #(
    .AXI_ADDR_WIDTH ( AxiAddrWidth     ),
    .AXI_DATA_WIDTH ( AxiDataWidth     ),
    .AXI_ID_WIDTH   ( AxiIdWidthSlaves ),
    .NR_CORES       ( NB_CORES_LP      ),
    .axi_req_t      ( axi_slave_req_t  ),
    .axi_resp_t     ( axi_slave_resp_t )
) i_clint (
    .clk_i       ( clk            ),
    .rst_ni      ( ndmreset_n     ),
    .testmode_i  ( test_en        ),
    .axi_req_i   ( axi_clint_req  ),
    .axi_resp_o  ( axi_clint_resp ),
    .rtc_i       ( rtc            ),
    .timer_irq_o ( timer_irq      ),
    .ipi_o       ( ipi            )
);

`AXI_ASSIGN_TO_REQ(axi_clint_req, master[soc_pkg::CLINT])
`AXI_ASSIGN_FROM_RESP(master[soc_pkg::CLINT], axi_clint_resp)

// ---------------------------------------------------------------------------
// Boot ROM
// ---------------------------------------------------------------------------
axi2mem #(
    .AXI_ID_WIDTH   ( AxiIdWidthSlaves ),
    .AXI_ADDR_WIDTH ( AxiAddrWidth     ),
    .AXI_DATA_WIDTH ( AxiDataWidth     ),
    .AXI_USER_WIDTH ( AxiUserWidth     )
) i_axi2rom (
    .clk_i  ( clk                     ),
    .rst_ni ( ndmreset_n              ),
    .slave  ( master[soc_pkg::ROM]    ),
    .req_o  ( rom_req                 ),
    .we_o   (                         ),
    .addr_o ( rom_addr                ),
    .be_o   (                         ),
    .data_o (                         ),
    .data_i ( rom_rdata               )
);

bootrom_64 i_bootrom (
    .clk_i   ( clk       ),
    .req_i   ( rom_req   ),
    .addr_i  ( rom_addr  ),
    .rdata_o ( rom_rdata )
);

// ---------------------------------------------------------------------------
// Peripherals (PLIC, UART, SPI, Timer)
// ---------------------------------------------------------------------------
// Dummy AXI bus for the unused ethernet port (InclEthernet = 0).
// soc_peripherals drives the slave side internally when not included,
// but Vivado requires a connected interface instance.
AXI_BUS #(
    .AXI_ADDR_WIDTH ( AxiAddrWidth     ),
    .AXI_DATA_WIDTH ( AxiDataWidth     ),
    .AXI_ID_WIDTH   ( AxiIdWidthSlaves ),
    .AXI_USER_WIDTH ( AxiUserWidth     )
) ethernet_dummy();

soc_peripherals #(
    .AxiAddrWidth ( AxiAddrWidth     ),
    .AxiDataWidth ( AxiDataWidth     ),
    .AxiIdWidth   ( AxiIdWidthSlaves ),
    .AxiUserWidth ( AxiUserWidth     ),
    .InclUART     ( 1'b1             ),
    .InclSPI      ( 1'b0             ),
    .InclEthernet ( 1'b0             ),
    .InclGPIO     ( 1'b0             ),
    .InclTimer    ( 1'b1             )
) i_ariane_peripherals (
    .clk_i        ( clk                     ),
    .rst_ni       ( ndmreset_n              ),
    .plic         ( master[soc_pkg::PLIC]   ),
    .uart         ( master[soc_pkg::UART]   ),
    .spi          ( master[soc_pkg::SPI]    ),
    .ethernet     ( ethernet_dummy           ), // not used (InclEthernet = 0)
    .timer        ( master[soc_pkg::Timer]  ),
    .irq_o        ( irq                     ),
    .rx_i         ( rx                      ),
    .tx_o         ( tx                      ),
    // Ethernet (not used — drive outputs, leave inputs open)
    .eth_txck     ( 1'b0         ),
    .eth_rxck     ( 1'b0         ),
    .eth_rxctl    ( 1'b0         ),
    .eth_rxd      ( 4'h0         ),
    .eth_rst_n    (              ),
    .eth_tx_en    (              ),
    .eth_txd      (              ),
    .phy_mdio     (              ),
    .eth_mdc      (              ),
    .mdio         (              ),
    .mdc          (              ),
    // SPI disabled — connect to dummy locals
    .spi_clk_o    ( spi_clk_o_nc ),
    .spi_mosi     ( spi_mosi_nc  ),
    .spi_miso     ( 1'b0         ),
    .spi_ss       ( spi_ss_nc    )
);

// ---------------------------------------------------------------------------
// DRAM path: axi_riscv_atomics → LLC → DDR4 MIG
// ---------------------------------------------------------------------------
AXI_BUS #(
    .AXI_ADDR_WIDTH ( AxiAddrWidth   ),
    .AXI_DATA_WIDTH ( AxiDataWidth   ),
    .AXI_ID_WIDTH   ( AxiIdWidthDram ),
    .AXI_USER_WIDTH ( AxiUserWidth   )
) dram();

AXI_BUS #(
    .AXI_ADDR_WIDTH ( AxiAddrWidth   ),
    .AXI_DATA_WIDTH ( AxiDataWidth   ),
    .AXI_ID_WIDTH   ( AxiIdWidthSlaves ),
    .AXI_USER_WIDTH ( AxiUserWidth   )
) to_llc();

axi_riscv_atomics_wrap #(
    .AXI_ADDR_WIDTH     ( AxiAddrWidth                                ),
    .AXI_DATA_WIDTH     ( AxiDataWidth                                ),
    .AXI_ADDR_LSB       ( $clog2(ariane_pkg::DCACHE_LINE_WIDTH/8)     ),
    .AXI_ID_WIDTH       ( AxiIdWidthSlaves                            ),
    .AXI_USER_WIDTH     ( AxiUserWidth                                ),
    .AXI_USER_AS_ID     ( 1'b1                                        ),
    .AXI_USER_ID_LSB    ( 0                                           ),
    .AXI_USER_ID_MSB    ( 0                                           ),  // Single core: 1 reservation bit
    .AXI_MAX_READ_TXNS  ( 1                                           ),
    .AXI_MAX_WRITE_TXNS ( 1                                           ),
    .RISCV_WORD_WIDTH   ( riscv::XLEN                                 )
) i_axi_riscv_atomics (
    .clk_i  ( clk                     ),
    .rst_ni ( ndmreset_n              ),
    .slv    ( master[soc_pkg::DRAM]   ),
    .mst    ( to_llc                  )
);

if (HasLLC) begin : gen_llc

  typedef logic [AxiIdWidthSlaves-1:0] axi_slv_id_t;
  typedef logic [AxiIdWidthDram-1:0]   axi_mst_id_t;
  typedef logic [AxiAddrWidth-1:0]     axi_addr_t;
  typedef logic [AxiDataWidth-1:0]     axi_data_t;
  typedef logic [AxiStrbWidth-1:0]     axi_strb_t;
  typedef logic [AxiUserWidth-1:0]     axi_user_t;

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
  axi_slv_req_t  axi_cpu_req;
  axi_slv_resp_t axi_cpu_res;
  axi_mst_req_t  axi_mem_req;
  axi_mst_resp_t axi_mem_res;
  conf_req_t     reg_cfg_req;
  conf_rsp_t     reg_cfg_rsp;

  assign reg_cfg_req = '0;

  localparam axi_addr_t L2CachedRegionStart  = axi_addr_t'(soc_pkg::DRAMBase);
  localparam axi_addr_t L2CachedRegionLength = axi_addr_t'(soc_pkg::DRAMLength);

  `AXI_ASSIGN_TO_REQ(axi_cpu_req, to_llc)
  `AXI_ASSIGN_FROM_RESP(to_llc, axi_cpu_res)
  `AXI_ASSIGN_FROM_REQ(dram, axi_mem_req)
  `AXI_ASSIGN_TO_RESP(axi_mem_res, dram)

  axi_llc_reg_wrap #(
    .SetAssociativity ( 32'd8              ),
    .NumLines         ( 32'd256            ),
    .NumBlocks        ( 32'd8             ),
    .AxiIdWidth       ( AxiIdWidthSlaves   ),
    .AxiAddrWidth     ( AxiAddrWidth       ),
    .AxiDataWidth     ( AxiDataWidth       ),
    .AxiUserWidth     ( AxiUserWidth       ),
    .slv_req_t        ( axi_slv_req_t      ),
    .slv_resp_t       ( axi_slv_resp_t     ),
    .mst_req_t        ( axi_mst_req_t      ),
    .mst_resp_t       ( axi_mst_resp_t     ),
    .reg_req_t        ( conf_req_t         ),
    .reg_resp_t       ( conf_rsp_t         ),
    .rule_full_t      ( rule_full_t        )
  ) i_axi_llc (
    .clk_i               ( clk                                         ),
    .rst_ni              ( ndmreset_n                                  ),
    .test_i              ( 1'b0                                        ),
    .slv_req_i           ( axi_cpu_req                                 ),
    .slv_resp_o          ( axi_cpu_res                                 ),
    .mst_req_o           ( axi_mem_req                                 ),
    .mst_resp_i          ( axi_mem_res                                 ),
    .conf_req_i          ( reg_cfg_req                                 ),
    .conf_resp_o         ( reg_cfg_rsp                                 ),
    .cached_start_addr_i ( L2CachedRegionStart                         ),
    .cached_end_addr_i   ( L2CachedRegionStart + L2CachedRegionLength  ),
    .spm_start_addr_i    ( '0                                          ),
    .axi_llc_events_o    ( llc_events                                  )
  );

end else begin : gen_no_llc
  `AXI_ASSIGN(dram, to_llc)
end

// ---------------------------------------------------------------------------
// DDR4 data-width converter (64b → 512b) + MIG
// ---------------------------------------------------------------------------
assign dram.r_user = '0;
assign dram.b_user = '0;

// AXI signals after the clock converter (ddr_clock_out domain)
logic [AxiIdWidthDram-1:0]   s_axi_awid;
logic [AxiAddrWidth-1:0]     s_axi_awaddr;
logic [7:0]                  s_axi_awlen;
logic [2:0]                  s_axi_awsize;
logic [1:0]                  s_axi_awburst;
logic [0:0]                  s_axi_awlock;
logic [3:0]                  s_axi_awcache;
logic [2:0]                  s_axi_awprot;
logic [3:0]                  s_axi_awregion;
logic [3:0]                  s_axi_awqos;
logic                        s_axi_awvalid;
logic                        s_axi_awready;
logic [AxiDataWidth-1:0]     s_axi_wdata;
logic [AxiDataWidth/8-1:0]   s_axi_wstrb;
logic                        s_axi_wlast;
logic                        s_axi_wvalid;
logic                        s_axi_wready;
logic [AxiIdWidthDram-1:0]   s_axi_bid;
logic [1:0]                  s_axi_bresp;
logic                        s_axi_bvalid;
logic                        s_axi_bready;
logic [AxiIdWidthDram-1:0]   s_axi_arid;
logic [AxiAddrWidth-1:0]     s_axi_araddr;
logic [7:0]                  s_axi_arlen;
logic [2:0]                  s_axi_arsize;
logic [1:0]                  s_axi_arburst;
logic [0:0]                  s_axi_arlock;
logic [3:0]                  s_axi_arcache;
logic [2:0]                  s_axi_arprot;
logic [3:0]                  s_axi_arregion;
logic [3:0]                  s_axi_arqos;
logic                        s_axi_arvalid;
logic                        s_axi_arready;
logic [AxiIdWidthDram-1:0]   s_axi_rid;
logic [AxiDataWidth-1:0]     s_axi_rdata;
logic [1:0]                  s_axi_rresp;
logic                        s_axi_rlast;
logic                        s_axi_rvalid;
logic                        s_axi_rready;

// 512b signals to DDR4 MIG
logic [63:0]  dram_dwidth_axi_awaddr;
logic [7:0]   dram_dwidth_axi_awlen;
logic [2:0]   dram_dwidth_axi_awsize;
logic [1:0]   dram_dwidth_axi_awburst;
logic [0:0]   dram_dwidth_axi_awlock;
logic [3:0]   dram_dwidth_axi_awcache;
logic [2:0]   dram_dwidth_axi_awprot;
logic [3:0]   dram_dwidth_axi_awqos;
logic         dram_dwidth_axi_awvalid;
logic         dram_dwidth_axi_awready;
logic [511:0] dram_dwidth_axi_wdata;
logic [63:0]  dram_dwidth_axi_wstrb;
logic         dram_dwidth_axi_wlast;
logic         dram_dwidth_axi_wvalid;
logic         dram_dwidth_axi_wready;
logic         dram_dwidth_axi_bready;
logic [1:0]   dram_dwidth_axi_bresp;
logic         dram_dwidth_axi_bvalid;
logic [63:0]  dram_dwidth_axi_araddr;
logic [7:0]   dram_dwidth_axi_arlen;
logic [2:0]   dram_dwidth_axi_arsize;
logic [1:0]   dram_dwidth_axi_arburst;
logic [0:0]   dram_dwidth_axi_arlock;
logic [3:0]   dram_dwidth_axi_arcache;
logic [2:0]   dram_dwidth_axi_arprot;
logic [3:0]   dram_dwidth_axi_arqos;
logic         dram_dwidth_axi_arvalid;
logic         dram_dwidth_axi_arready;
logic         dram_dwidth_axi_rready;
logic         dram_dwidth_axi_rlast;
logic         dram_dwidth_axi_rvalid;
logic [1:0]   dram_dwidth_axi_rresp;
logic [511:0] dram_dwidth_axi_rdata;

// Clock converter: clk → ddr_clock_out
xlnx_axi_clock_converter i_xlnx_axi_clock_converter_ddr (
  .s_axi_aclk     ( clk              ),
  .s_axi_aresetn  ( ndmreset_n       ),
  .s_axi_awid     ( dram.aw_id       ),
  .s_axi_awaddr   ( dram.aw_addr     ),
  .s_axi_awlen    ( dram.aw_len      ),
  .s_axi_awsize   ( dram.aw_size     ),
  .s_axi_awburst  ( dram.aw_burst    ),
  .s_axi_awlock   ( dram.aw_lock     ),
  .s_axi_awcache  ( dram.aw_cache    ),
  .s_axi_awprot   ( dram.aw_prot     ),
  .s_axi_awregion ( dram.aw_region   ),
  .s_axi_awqos    ( dram.aw_qos      ),
  .s_axi_awvalid  ( dram.aw_valid    ),
  .s_axi_awready  ( dram.aw_ready    ),
  .s_axi_wdata    ( dram.w_data      ),
  .s_axi_wstrb    ( dram.w_strb      ),
  .s_axi_wlast    ( dram.w_last      ),
  .s_axi_wvalid   ( dram.w_valid     ),
  .s_axi_wready   ( dram.w_ready     ),
  .s_axi_bid      ( dram.b_id        ),
  .s_axi_bresp    ( dram.b_resp      ),
  .s_axi_bvalid   ( dram.b_valid     ),
  .s_axi_bready   ( dram.b_ready     ),
  .s_axi_arid     ( dram.ar_id       ),
  .s_axi_araddr   ( dram.ar_addr     ),
  .s_axi_arlen    ( dram.ar_len      ),
  .s_axi_arsize   ( dram.ar_size     ),
  .s_axi_arburst  ( dram.ar_burst    ),
  .s_axi_arlock   ( dram.ar_lock     ),
  .s_axi_arcache  ( dram.ar_cache    ),
  .s_axi_arprot   ( dram.ar_prot     ),
  .s_axi_arregion ( dram.ar_region   ),
  .s_axi_arqos    ( dram.ar_qos      ),
  .s_axi_arvalid  ( dram.ar_valid    ),
  .s_axi_arready  ( dram.ar_ready    ),
  .s_axi_rid      ( dram.r_id        ),
  .s_axi_rdata    ( dram.r_data      ),
  .s_axi_rresp    ( dram.r_resp      ),
  .s_axi_rlast    ( dram.r_last      ),
  .s_axi_rvalid   ( dram.r_valid     ),
  .s_axi_rready   ( dram.r_ready     ),
  .m_axi_aclk     ( ddr_clock_out    ),
  .m_axi_aresetn  ( ndmreset_n       ),
  .m_axi_awid     ( s_axi_awid       ),
  .m_axi_awaddr   ( s_axi_awaddr     ),
  .m_axi_awlen    ( s_axi_awlen      ),
  .m_axi_awsize   ( s_axi_awsize     ),
  .m_axi_awburst  ( s_axi_awburst    ),
  .m_axi_awlock   ( s_axi_awlock     ),
  .m_axi_awcache  ( s_axi_awcache    ),
  .m_axi_awprot   ( s_axi_awprot     ),
  .m_axi_awregion ( s_axi_awregion   ),
  .m_axi_awqos    ( s_axi_awqos      ),
  .m_axi_awvalid  ( s_axi_awvalid    ),
  .m_axi_awready  ( s_axi_awready    ),
  .m_axi_wdata    ( s_axi_wdata      ),
  .m_axi_wstrb    ( s_axi_wstrb      ),
  .m_axi_wlast    ( s_axi_wlast      ),
  .m_axi_wvalid   ( s_axi_wvalid     ),
  .m_axi_wready   ( s_axi_wready     ),
  .m_axi_bid      ( s_axi_bid        ),
  .m_axi_bresp    ( s_axi_bresp      ),
  .m_axi_bvalid   ( s_axi_bvalid     ),
  .m_axi_bready   ( s_axi_bready     ),
  .m_axi_arid     ( s_axi_arid       ),
  .m_axi_araddr   ( s_axi_araddr     ),
  .m_axi_arlen    ( s_axi_arlen      ),
  .m_axi_arsize   ( s_axi_arsize     ),
  .m_axi_arburst  ( s_axi_arburst    ),
  .m_axi_arlock   ( s_axi_arlock     ),
  .m_axi_arcache  ( s_axi_arcache    ),
  .m_axi_arprot   ( s_axi_arprot     ),
  .m_axi_arregion ( s_axi_arregion   ),
  .m_axi_arqos    ( s_axi_arqos      ),
  .m_axi_arvalid  ( s_axi_arvalid    ),
  .m_axi_arready  ( s_axi_arready    ),
  .m_axi_rid      ( s_axi_rid        ),
  .m_axi_rdata    ( s_axi_rdata      ),
  .m_axi_rresp    ( s_axi_rresp      ),
  .m_axi_rlast    ( s_axi_rlast      ),
  .m_axi_rvalid   ( s_axi_rvalid     ),
  .m_axi_rready   ( s_axi_rready     )
);

// Data-width converter: 64b → 512b for DDR4 MIG
xlnx_axi_dwidth_converter_512_64 i_axi_dwidth_converter_512_64 (
  .s_axi_aclk     ( ddr_clock_out            ),
  .s_axi_aresetn  ( ndmreset_n               ),
  .s_axi_awid     ( s_axi_awid               ),
  .s_axi_awaddr   ( s_axi_awaddr             ),
  .s_axi_awlen    ( s_axi_awlen              ),
  .s_axi_awsize   ( s_axi_awsize             ),
  .s_axi_awburst  ( s_axi_awburst            ),
  .s_axi_awlock   ( s_axi_awlock             ),
  .s_axi_awcache  ( s_axi_awcache            ),
  .s_axi_awprot   ( s_axi_awprot             ),
  .s_axi_awregion ( '0                       ),
  .s_axi_awqos    ( s_axi_awqos              ),
  .s_axi_awvalid  ( s_axi_awvalid            ),
  .s_axi_awready  ( s_axi_awready            ),
  .s_axi_wdata    ( s_axi_wdata              ),
  .s_axi_wstrb    ( s_axi_wstrb              ),
  .s_axi_wlast    ( s_axi_wlast              ),
  .s_axi_wvalid   ( s_axi_wvalid             ),
  .s_axi_wready   ( s_axi_wready             ),
  .s_axi_bid      ( s_axi_bid                ),
  .s_axi_bresp    ( s_axi_bresp              ),
  .s_axi_bvalid   ( s_axi_bvalid             ),
  .s_axi_bready   ( s_axi_bready             ),
  .s_axi_arid     ( s_axi_arid               ),
  .s_axi_araddr   ( s_axi_araddr             ),
  .s_axi_arlen    ( s_axi_arlen              ),
  .s_axi_arsize   ( s_axi_arsize             ),
  .s_axi_arburst  ( s_axi_arburst            ),
  .s_axi_arlock   ( s_axi_arlock             ),
  .s_axi_arcache  ( s_axi_arcache            ),
  .s_axi_arprot   ( s_axi_arprot             ),
  .s_axi_arregion ( '0                       ),
  .s_axi_arqos    ( s_axi_arqos              ),
  .s_axi_arvalid  ( s_axi_arvalid            ),
  .s_axi_arready  ( s_axi_arready            ),
  .s_axi_rid      ( s_axi_rid                ),
  .s_axi_rdata    ( s_axi_rdata              ),
  .s_axi_rresp    ( s_axi_rresp              ),
  .s_axi_rlast    ( s_axi_rlast              ),
  .s_axi_rvalid   ( s_axi_rvalid             ),
  .s_axi_rready   ( s_axi_rready             ),
  .m_axi_awaddr   ( dram_dwidth_axi_awaddr   ),
  .m_axi_awlen    ( dram_dwidth_axi_awlen    ),
  .m_axi_awsize   ( dram_dwidth_axi_awsize   ),
  .m_axi_awburst  ( dram_dwidth_axi_awburst  ),
  .m_axi_awlock   ( dram_dwidth_axi_awlock   ),
  .m_axi_awcache  ( dram_dwidth_axi_awcache  ),
  .m_axi_awprot   ( dram_dwidth_axi_awprot   ),
  .m_axi_awregion (                          ),
  .m_axi_awqos    ( dram_dwidth_axi_awqos    ),
  .m_axi_awvalid  ( dram_dwidth_axi_awvalid  ),
  .m_axi_awready  ( dram_dwidth_axi_awready  ),
  .m_axi_wdata    ( dram_dwidth_axi_wdata    ),
  .m_axi_wstrb    ( dram_dwidth_axi_wstrb    ),
  .m_axi_wlast    ( dram_dwidth_axi_wlast    ),
  .m_axi_wvalid   ( dram_dwidth_axi_wvalid   ),
  .m_axi_wready   ( dram_dwidth_axi_wready   ),
  .m_axi_bresp    ( dram_dwidth_axi_bresp    ),
  .m_axi_bvalid   ( dram_dwidth_axi_bvalid   ),
  .m_axi_bready   ( dram_dwidth_axi_bready   ),
  .m_axi_araddr   ( dram_dwidth_axi_araddr   ),
  .m_axi_arlen    ( dram_dwidth_axi_arlen    ),
  .m_axi_arsize   ( dram_dwidth_axi_arsize   ),
  .m_axi_arburst  ( dram_dwidth_axi_arburst  ),
  .m_axi_arlock   ( dram_dwidth_axi_arlock   ),
  .m_axi_arcache  ( dram_dwidth_axi_arcache  ),
  .m_axi_arprot   ( dram_dwidth_axi_arprot   ),
  .m_axi_arregion (                          ),
  .m_axi_arqos    ( dram_dwidth_axi_arqos    ),
  .m_axi_arvalid  ( dram_dwidth_axi_arvalid  ),
  .m_axi_arready  ( dram_dwidth_axi_arready  ),
  .m_axi_rdata    ( dram_dwidth_axi_rdata    ),
  .m_axi_rresp    ( dram_dwidth_axi_rresp    ),
  .m_axi_rlast    ( dram_dwidth_axi_rlast    ),
  .m_axi_rvalid   ( dram_dwidth_axi_rvalid   ),
  .m_axi_rready   ( dram_dwidth_axi_rready   )
);

// DDR4 MIG
xlnx_mig_ddr4 i_ddr (
    .c0_init_calib_complete ( calib_complete                 ),
    .dbg_clk                (                                ),
    .c0_sys_clk_p           ( c0_sys_clk_p                   ),
    .c0_sys_clk_n           ( c0_sys_clk_n                   ),
    .dbg_bus                (                                ),
    .c0_ddr4_adr            ( c0_ddr4_adr                    ),
    .c0_ddr4_ba             ( c0_ddr4_ba                     ),
    .c0_ddr4_cke            ( c0_ddr4_cke                    ),
    .c0_ddr4_cs_n           ( c0_ddr4_cs_n                   ),
    .c0_ddr4_dm_dbi_n       ( c0_ddr4_dm_dbi_n               ),
    .c0_ddr4_dq             ( c0_ddr4_dq                     ),
    .c0_ddr4_dqs_c          ( c0_ddr4_dqs_c                  ),
    .c0_ddr4_dqs_t          ( c0_ddr4_dqs_t                  ),
    .c0_ddr4_odt            ( c0_ddr4_odt                    ),
    .c0_ddr4_bg             ( c0_ddr4_bg                     ),
    .c0_ddr4_reset_n        ( c0_ddr4_reset_n                ),
    .c0_ddr4_act_n          ( c0_ddr4_act_n                  ),
    .c0_ddr4_ck_c           ( c0_ddr4_ck_c                   ),
    .c0_ddr4_ck_t           ( c0_ddr4_ck_t                   ),
    .c0_ddr4_ui_clk         ( ddr_clock_out                  ),
    .c0_ddr4_ui_clk_sync_rst( ddr_sync_reset                 ),
    .addn_ui_clkout1        ( ddr_clock_out_200              ),
    .c0_ddr4_aresetn        ( ndmreset_n                     ),
    .c0_ddr4_s_axi_awid     ( '0                             ),
    .c0_ddr4_s_axi_awaddr   ( dram_dwidth_axi_awaddr[30:0]   ),
    .c0_ddr4_s_axi_awlen    ( dram_dwidth_axi_awlen          ),
    .c0_ddr4_s_axi_awsize   ( dram_dwidth_axi_awsize         ),
    .c0_ddr4_s_axi_awburst  ( dram_dwidth_axi_awburst        ),
    .c0_ddr4_s_axi_awlock   ( dram_dwidth_axi_awlock         ),
    .c0_ddr4_s_axi_awcache  ( dram_dwidth_axi_awcache        ),
    .c0_ddr4_s_axi_awprot   ( dram_dwidth_axi_awprot         ),
    .c0_ddr4_s_axi_awqos    ( dram_dwidth_axi_awqos          ),
    .c0_ddr4_s_axi_awvalid  ( dram_dwidth_axi_awvalid        ),
    .c0_ddr4_s_axi_awready  ( dram_dwidth_axi_awready        ),
    .c0_ddr4_s_axi_wdata    ( dram_dwidth_axi_wdata          ),
    .c0_ddr4_s_axi_wstrb    ( dram_dwidth_axi_wstrb          ),
    .c0_ddr4_s_axi_wlast    ( dram_dwidth_axi_wlast          ),
    .c0_ddr4_s_axi_wvalid   ( dram_dwidth_axi_wvalid         ),
    .c0_ddr4_s_axi_wready   ( dram_dwidth_axi_wready         ),
    .c0_ddr4_s_axi_bready   ( dram_dwidth_axi_bready         ),
    .c0_ddr4_s_axi_bid      (                                ),
    .c0_ddr4_s_axi_bresp    ( dram_dwidth_axi_bresp          ),
    .c0_ddr4_s_axi_bvalid   ( dram_dwidth_axi_bvalid         ),
    .c0_ddr4_s_axi_arid     ( '0                             ),
    .c0_ddr4_s_axi_araddr   ( dram_dwidth_axi_araddr[30:0]   ),
    .c0_ddr4_s_axi_arlen    ( dram_dwidth_axi_arlen          ),
    .c0_ddr4_s_axi_arsize   ( dram_dwidth_axi_arsize         ),
    .c0_ddr4_s_axi_arburst  ( dram_dwidth_axi_arburst        ),
    .c0_ddr4_s_axi_arlock   ( dram_dwidth_axi_arlock         ),
    .c0_ddr4_s_axi_arcache  ( dram_dwidth_axi_arcache        ),
    .c0_ddr4_s_axi_arprot   ( dram_dwidth_axi_arprot         ),
    .c0_ddr4_s_axi_arqos    ( dram_dwidth_axi_arqos          ),
    .c0_ddr4_s_axi_arvalid  ( dram_dwidth_axi_arvalid        ),
    .c0_ddr4_s_axi_arready  ( dram_dwidth_axi_arready        ),
    .c0_ddr4_s_axi_rready   ( dram_dwidth_axi_rready         ),
    .c0_ddr4_s_axi_rlast    ( dram_dwidth_axi_rlast          ),
    .c0_ddr4_s_axi_rvalid   ( dram_dwidth_axi_rvalid         ),
    .c0_ddr4_s_axi_rresp    ( dram_dwidth_axi_rresp          ),
    .c0_ddr4_s_axi_rid      (                                ),
    .c0_ddr4_s_axi_rdata    ( dram_dwidth_axi_rdata          ),
    .sys_rst                ( cpu_reset                      )
);

// ---------------------------------------------------------------------------
// Clock generator (produces 50 MHz system clock from DDR 200 MHz)
// ---------------------------------------------------------------------------
logic clk_spad; // 250 MHz scratchpad clock, driven by MMCM clk_out5
xlnx_clk_gen i_xlnx_clk_gen (
  .clk_out1 ( clk               ), // 50 MHz  (CVA6 + AXI + PE array)
  .clk_out2 ( phy_tx_clk        ), // 125 MHz (RGMII, unused)
  .clk_out3 ( eth_clk           ), // 125 MHz quad-phase (unused)
  .clk_out4 ( sd_clk_sys        ), // 50 MHz SD (unused)
  .clk_out5 ( clk_spad          ), // 250 MHz (FleXNNgine scratchpad)
  .reset    ( cpu_reset         ),
  .locked   ( pll_locked        ),
  .clk_in1  ( ddr_clock_out_200 )
);

// ---------------------------------------------------------------------------
// FleXNNgine accelerator
// ---------------------------------------------------------------------------
// Clock uplift (50/50/250, matching Lesniak 2024): the spad BRAM controller
// inside flexnngine_wrap runs at clk_spad (250 MHz), so the SoC-side AXI bus
// (clk = 50 MHz) has to cross a clock boundary. A dedicated instance of the
// xlnx_axi_clock_converter IP does that conversion. Control-path CDC between
// the AXI register interface and the internal accelerator logic is handled
// by acc_axi_top's internal bit_sync when AxiAccCDC=1.
AXI_BUS #(
    .AXI_ADDR_WIDTH ( AxiAddrWidth      ),
    .AXI_DATA_WIDTH ( AxiDataWidth      ),
    .AXI_ID_WIDTH   ( AxiIdWidthSlaves  ),
    .AXI_USER_WIDTH ( AxiUserWidth      )
) spad_flex();  // post-converter bus, clocked by clk_spad

xlnx_axi_clock_converter i_xlnx_axi_clock_converter_spad (
    .s_axi_aclk     ( clk                          ),
    .s_axi_aresetn  ( ndmreset_n                   ),
    .s_axi_awid     ( master[soc_pkg::FlexSpad].aw_id    ),
    .s_axi_awaddr   ( master[soc_pkg::FlexSpad].aw_addr  ),
    .s_axi_awlen    ( master[soc_pkg::FlexSpad].aw_len   ),
    .s_axi_awsize   ( master[soc_pkg::FlexSpad].aw_size  ),
    .s_axi_awburst  ( master[soc_pkg::FlexSpad].aw_burst ),
    .s_axi_awlock   ( master[soc_pkg::FlexSpad].aw_lock  ),
    .s_axi_awcache  ( master[soc_pkg::FlexSpad].aw_cache ),
    .s_axi_awprot   ( master[soc_pkg::FlexSpad].aw_prot  ),
    .s_axi_awregion ( master[soc_pkg::FlexSpad].aw_region),
    .s_axi_awqos    ( master[soc_pkg::FlexSpad].aw_qos   ),
    .s_axi_awvalid  ( master[soc_pkg::FlexSpad].aw_valid ),
    .s_axi_awready  ( master[soc_pkg::FlexSpad].aw_ready ),
    .s_axi_wdata    ( master[soc_pkg::FlexSpad].w_data   ),
    .s_axi_wstrb    ( master[soc_pkg::FlexSpad].w_strb   ),
    .s_axi_wlast    ( master[soc_pkg::FlexSpad].w_last   ),
    .s_axi_wvalid   ( master[soc_pkg::FlexSpad].w_valid  ),
    .s_axi_wready   ( master[soc_pkg::FlexSpad].w_ready  ),
    .s_axi_bid      ( master[soc_pkg::FlexSpad].b_id     ),
    .s_axi_bresp    ( master[soc_pkg::FlexSpad].b_resp   ),
    .s_axi_bvalid   ( master[soc_pkg::FlexSpad].b_valid  ),
    .s_axi_bready   ( master[soc_pkg::FlexSpad].b_ready  ),
    .s_axi_arid     ( master[soc_pkg::FlexSpad].ar_id    ),
    .s_axi_araddr   ( master[soc_pkg::FlexSpad].ar_addr  ),
    .s_axi_arlen    ( master[soc_pkg::FlexSpad].ar_len   ),
    .s_axi_arsize   ( master[soc_pkg::FlexSpad].ar_size  ),
    .s_axi_arburst  ( master[soc_pkg::FlexSpad].ar_burst ),
    .s_axi_arlock   ( master[soc_pkg::FlexSpad].ar_lock  ),
    .s_axi_arcache  ( master[soc_pkg::FlexSpad].ar_cache ),
    .s_axi_arprot   ( master[soc_pkg::FlexSpad].ar_prot  ),
    .s_axi_arregion ( master[soc_pkg::FlexSpad].ar_region),
    .s_axi_arqos    ( master[soc_pkg::FlexSpad].ar_qos   ),
    .s_axi_arvalid  ( master[soc_pkg::FlexSpad].ar_valid ),
    .s_axi_arready  ( master[soc_pkg::FlexSpad].ar_ready ),
    .s_axi_rid      ( master[soc_pkg::FlexSpad].r_id     ),
    .s_axi_rdata    ( master[soc_pkg::FlexSpad].r_data   ),
    .s_axi_rresp    ( master[soc_pkg::FlexSpad].r_resp   ),
    .s_axi_rlast    ( master[soc_pkg::FlexSpad].r_last   ),
    .s_axi_rvalid   ( master[soc_pkg::FlexSpad].r_valid  ),
    .s_axi_rready   ( master[soc_pkg::FlexSpad].r_ready  ),
    .m_axi_aclk     ( clk_spad                     ),
    .m_axi_aresetn  ( ndmreset_n                   ),
    .m_axi_awid     ( spad_flex.aw_id              ),
    .m_axi_awaddr   ( spad_flex.aw_addr            ),
    .m_axi_awlen    ( spad_flex.aw_len             ),
    .m_axi_awsize   ( spad_flex.aw_size            ),
    .m_axi_awburst  ( spad_flex.aw_burst           ),
    .m_axi_awlock   ( spad_flex.aw_lock            ),
    .m_axi_awcache  ( spad_flex.aw_cache           ),
    .m_axi_awprot   ( spad_flex.aw_prot            ),
    .m_axi_awregion ( spad_flex.aw_region          ),
    .m_axi_awqos    ( spad_flex.aw_qos             ),
    .m_axi_awvalid  ( spad_flex.aw_valid           ),
    .m_axi_awready  ( spad_flex.aw_ready           ),
    .m_axi_wdata    ( spad_flex.w_data             ),
    .m_axi_wstrb    ( spad_flex.w_strb             ),
    .m_axi_wlast    ( spad_flex.w_last             ),
    .m_axi_wvalid   ( spad_flex.w_valid            ),
    .m_axi_wready   ( spad_flex.w_ready            ),
    .m_axi_bid      ( spad_flex.b_id               ),
    .m_axi_bresp    ( spad_flex.b_resp             ),
    .m_axi_bvalid   ( spad_flex.b_valid            ),
    .m_axi_bready   ( spad_flex.b_ready            ),
    .m_axi_arid     ( spad_flex.ar_id              ),
    .m_axi_araddr   ( spad_flex.ar_addr            ),
    .m_axi_arlen    ( spad_flex.ar_len             ),
    .m_axi_arsize   ( spad_flex.ar_size            ),
    .m_axi_arburst  ( spad_flex.ar_burst           ),
    .m_axi_arlock   ( spad_flex.ar_lock            ),
    .m_axi_arcache  ( spad_flex.ar_cache           ),
    .m_axi_arprot   ( spad_flex.ar_prot            ),
    .m_axi_arregion ( spad_flex.ar_region          ),
    .m_axi_arqos    ( spad_flex.ar_qos             ),
    .m_axi_arvalid  ( spad_flex.ar_valid           ),
    .m_axi_arready  ( spad_flex.ar_ready           ),
    .m_axi_rid      ( spad_flex.r_id               ),
    .m_axi_rdata    ( spad_flex.r_data             ),
    .m_axi_rresp    ( spad_flex.r_resp             ),
    .m_axi_rlast    ( spad_flex.r_last             ),
    .m_axi_rvalid   ( spad_flex.r_valid            ),
    .m_axi_rready   ( spad_flex.r_ready            )
);

flexnngine_wrap #(
    .AxiAddrWidth ( AxiAddrWidth     ),
    .AxiDataWidth ( AxiDataWidth     ),
    .AxiIdWidth   ( AxiIdWidthSlaves ),
    .AxiUserWidth ( AxiUserWidth     ),
    .AxiAccCDC    ( 1                )
) i_flexnngine (
    .clk_axi_i    ( clk                          ),
    .clk_array_i  ( clk                          ),
    .clk_spad_i   ( clk_spad                     ),
    .rst_ni       ( ndmreset_n                   ),
    .regs         ( master[soc_pkg::FlexRegs]    ),
    .spad         ( spad_flex                    ),
    .irq_o        (                              )
);

endmodule
