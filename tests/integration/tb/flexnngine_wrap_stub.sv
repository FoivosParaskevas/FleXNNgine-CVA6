// Copyright 2025 KIT.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Simulation stub for flexnngine_wrap.
// Replaces the real implementation (which requires FleXNNgine VHDL sources +
// Xilinx AXI BRAM controller IP) for CPU-only RTL simulation tests.
// All AXI slave outputs are driven to "never-accept / never-respond" values,
// which is safe as long as the test program does not access FleXNNgine registers
// or the scratchpad.

module flexnngine_wrap #(
    parameter int AxiAddrWidth = -1,
    parameter int AxiDataWidth = -1,
    parameter int AxiIdWidth   = -1,
    parameter int AxiUserWidth = 1,
    parameter bit AxiAccCDC    = 1
) (
    input  logic       clk_axi_i,
    input  logic       clk_array_i,
    input  logic       clk_spad_i,
    input  logic       rst_ni,
    AXI_BUS.Slave      regs,
    AXI_BUS.Slave      spad,
    output logic       irq_o
);
    assign irq_o = '0;

    // regs AXI slave: never accept/respond
    assign regs.aw_ready = '0;
    assign regs.w_ready  = '0;
    assign regs.b_valid  = '0;
    assign regs.b_resp   = '0;
    assign regs.b_id     = '0;
    assign regs.b_user   = '0;
    assign regs.ar_ready = '0;
    assign regs.r_valid  = '0;
    assign regs.r_data   = '0;
    assign regs.r_resp   = '0;
    assign regs.r_id     = '0;
    assign regs.r_user   = '0;
    assign regs.r_last   = '0;

    // spad AXI slave: never accept/respond
    assign spad.aw_ready = '0;
    assign spad.w_ready  = '0;
    assign spad.b_valid  = '0;
    assign spad.b_resp   = '0;
    assign spad.b_id     = '0;
    assign spad.b_user   = '0;
    assign spad.ar_ready = '0;
    assign spad.r_valid  = '0;
    assign spad.r_data   = '0;
    assign spad.r_resp   = '0;
    assign spad.r_id     = '0;
    assign spad.r_user   = '0;
    assign spad.r_last   = '0;

endmodule
