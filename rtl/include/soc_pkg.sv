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
//
// Single-core CVA6 + FleXNNgine SoC package.

package soc_pkg;

  localparam NB_CORES = 1;

  // M-Mode Hart, S-Mode Hart (2 interrupt targets per hart)
  localparam int unsigned NumTargets = 2 * NB_CORES;
  localparam int unsigned NumSources = 30;
  localparam int unsigned MaxPriority = 7;

  // AXI masters to crossbar: 1× CVA6 + 1× debug module
  localparam NrMasters = 2;

  // 4 is recommended by AXI standard; do not change
  localparam IdWidth       = 4;
  localparam IdWidthToXbar = IdWidth;                     // ID width entering xbar slave ports
  localparam IdWidthSlave  = IdWidth + $clog2(NrMasters); // = 5, at xbar master ports

  typedef enum int unsigned {
    Debug    = 0,
    ROM      = 1,
    CLINT    = 2,
    PLIC     = 3,
    UART     = 4,
    Timer    = 5,
    SPI      = 6,
    FlexRegs = 7,
    FlexSpad = 8,
    DRAM     = 9
  } axi_slaves_t;

  localparam NB_PERIPHERALS = DRAM + 1; // 10

  // -----------------------------------------------
  // Address lengths
  // -----------------------------------------------
  localparam logic [63:0] DebugLength    = 64'h1000;
  localparam logic [63:0] ROMLength      = 64'h10000;
  localparam logic [63:0] CLINTLength    = 64'hC0000;
  localparam logic [63:0] PLICLength     = 64'h3FF_FFFF;
  localparam logic [63:0] UARTLength     = 64'h1000;
  localparam logic [63:0] TimerLength    = 64'h1000;
  localparam logic [63:0] SPILength      = 64'h800000;
  localparam logic [63:0] FlexRegsLength = 64'h1000;
  localparam logic [63:0] FlexSpadLength = 64'h20000;    // 128 KiB scratchpad (must match mem_addr_width_bytes in flexnngine_wrap.sv)
  localparam logic [63:0] DRAMLength     = 64'h40000000; // 1 GiB

  localparam logic [63:0] SRAMLength     = 64'h1800000;  // 24 MiB SRAM (simulation)

  // -----------------------------------------------
  // Base addresses
  // -----------------------------------------------
  typedef enum logic [63:0] {
    DebugBase    = 64'h0000_0000,
    ROMBase      = 64'h0001_0000,
    CLINTBase    = 64'h0200_0000,
    PLICBase     = 64'h0C00_0000,
    UARTBase     = 64'h1000_0000,
    TimerBase    = 64'h1800_0000,
    SPIBase      = 64'h2000_0000,
    FlexRegsBase = 64'h4070_0000,
    FlexSpadBase = 64'h4080_0000,
    DRAMBase     = 64'h8000_0000
  } soc_bus_start_t;

  // Simulation: bottom 384 KiB of DRAM is non-cached (for inter-core/device communication)
  localparam logic [63:0] uncachedLength = 64'h60000;

  // Exit address used by FESVR: write to DRAMBase to terminate simulation
  localparam logic [63:0] exitAddr = DRAMBase;

  // -----------------------------------------------
  // AXI type definitions for slave ports (xbar outputs)
  // -----------------------------------------------
  localparam UserWidth = ariane_pkg::AXI_USER_WIDTH;
  localparam AddrWidth = 64;
  localparam DataWidth = 64;
  localparam StrbWidth = DataWidth / 8;

  typedef logic [IdWidth-1:0]      id_t;
  typedef logic [IdWidthSlave-1:0] id_slv_t;
  typedef logic [AddrWidth-1:0]    addr_t;
  typedef logic [DataWidth-1:0]    data_t;
  typedef logic [StrbWidth-1:0]    strb_t;
  typedef logic [UserWidth-1:0]    user_t;

  // AW channel – slave side
  typedef struct packed {
    id_slv_t          id;
    addr_t            addr;
    axi_pkg::len_t    len;
    axi_pkg::size_t   size;
    axi_pkg::burst_t  burst;
    logic             lock;
    axi_pkg::cache_t  cache;
    axi_pkg::prot_t   prot;
    axi_pkg::qos_t    qos;
    axi_pkg::region_t region;
    axi_pkg::atop_t   atop;
    user_t            user;
  } aw_slv_t;

  // W channel (same for master and slave)
  typedef struct packed {
    data_t            data;
    strb_t            strb;
    logic             last;
    user_t            user;
  } w_t;

  // B channel – slave side
  typedef struct packed {
    id_slv_t          id;
    axi_pkg::resp_t   resp;
    user_t            user;
  } b_slv_t;

  // AR channel – slave side
  typedef struct packed {
    id_slv_t          id;
    addr_t            addr;
    axi_pkg::len_t    len;
    axi_pkg::size_t   size;
    axi_pkg::burst_t  burst;
    logic             lock;
    axi_pkg::cache_t  cache;
    axi_pkg::prot_t   prot;
    axi_pkg::qos_t    qos;
    axi_pkg::region_t region;
    user_t            user;
  } ar_slv_t;

  // R channel – slave side
  typedef struct packed {
    id_slv_t          id;
    data_t            data;
    axi_pkg::resp_t   resp;
    logic             last;
    user_t            user;
  } r_slv_t;

  typedef struct packed {
    aw_slv_t aw;
    logic    aw_valid;
    w_t      w;
    logic    w_valid;
    logic    b_ready;
    ar_slv_t ar;
    logic    ar_valid;
    logic    r_ready;
  } req_slv_t;

  typedef struct packed {
    logic    aw_ready;
    logic    ar_ready;
    logic    w_ready;
    logic    b_valid;
    b_slv_t  b;
    logic    r_valid;
    r_slv_t  r;
  } resp_slv_t;

  // -----------------------------------------------
  // CVA6 configuration for simulation
  // -----------------------------------------------
  localparam ariane_pkg::ariane_cfg_t ArianeSocCfg = '{
    RASDepth:               2,
    BTBEntries:             32,
    BHTEntries:             128,
    // idempotent region: everything below DRAM is MMIO
    NrNonIdempotentRules:   1,
    NonIdempotentAddrBase:  {64'b0},
    NonIdempotentLength:    {DRAMBase},
    // execute regions: DRAM + ROM + Debug
    NrExecuteRegionRules:   3,
    ExecuteRegionAddrBase:  {DRAMBase,   ROMBase,   DebugBase},
    ExecuteRegionLength:    {DRAMLength, ROMLength, DebugLength},
    // cached region: DRAM above uncached boot area
    NrCachedRegionRules:    1,
    CachedRegionAddrBase:   {DRAMBase + uncachedLength},
    CachedRegionLength:     {DRAMLength - uncachedLength},
    // shared region (not used in single-core, kept for struct completeness)
    NrSharedRegionRules:    1,
    SharedRegionAddrBase:   {DRAMBase},
    SharedRegionLength:     {64'h40000},
    AxiCompliant:           1'b1,
    SwapEndianess:          1'b0,
    CLICNumInterruptSrc:    1,
    CLICIntCtlBits:         1,
    DmBaseAddress:          DebugBase,
    NrPMPEntries:           8
  };

  // -----------------------------------------------
  // CVA6 configuration for FPGA synthesis
  // -----------------------------------------------
  localparam ariane_pkg::ariane_cfg_t ArianeFpgaSocCfg = '{
    RASDepth:               2,
    BTBEntries:             32,
    BHTEntries:             128,
    NrNonIdempotentRules:   1,
    NonIdempotentAddrBase:  {64'b0},
    NonIdempotentLength:    {DRAMBase},
    NrExecuteRegionRules:   3,
    ExecuteRegionAddrBase:  {DRAMBase,   ROMBase,   DebugBase},
    ExecuteRegionLength:    {DRAMLength, ROMLength, DebugLength},
    // full DRAM is cached on FPGA (LLC handles coherence with DDR4)
    NrCachedRegionRules:    1,
    CachedRegionAddrBase:   {DRAMBase},
    CachedRegionLength:     {DRAMLength},
    NrSharedRegionRules:    1,
    SharedRegionAddrBase:   {DRAMBase},
    SharedRegionLength:     {DRAMLength},
    AxiCompliant:           1'b1,
    SwapEndianess:          1'b0,
    CLICNumInterruptSrc:    1,
    CLICIntCtlBits:         1,
    DmBaseAddress:          DebugBase,
    NrPMPEntries:           8
  };

  // used in axi_adapter.sv
  typedef enum logic { SINGLE_REQ, CACHE_LINE_REQ } ad_req_t;

  // Instantiate AXI protocol checkers (disabled by default)
  localparam bit GenProtocolChecker = 1'b0;

endpackage
