/* Copyright 2018 ETH Zurich and University of Bologna.
 * Copyright and related rights are licensed under the Solderpad Hardware
 * License, Version 0.51 (the "License"); you may not use this file except in
 * compliance with the License.  You may obtain a copy of the License at
 * http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
 * or agreed to in writing, software, hardware and materials distributed under
 * this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
 * CONDITIONS OF ANY KIND, either express or implied. See the License for the
 * specific language governing permissions and limitations under the License.
 *
 * File: bootrom_64.sv
 *
 * Description: Minimal WFI boot ROM.
 *   CPU spins here until OpenOCD halts it via JTAG, then GDB loads the
 *   program directly.  No SPI/SD/DRAM-jump needed for debug-only flow.
 *
 *   0x10000: wfi          (0x10500073)
 *   0x10004: j _start     (0xffdff06f  -- jal x0, -4)
 */

// Auto-generated code
module bootrom_64 (
   input  logic         clk_i,
   input  logic         req_i,
   input  logic [63:0]  addr_i,
   output logic [63:0]  rdata_o
);
    localparam int RomSize = 2;

    const logic [RomSize-1:0][63:0] mem = {
        64'h00000000_00000000,  // mem[1]: padding
        64'hffdff06f_10500073   // mem[0]: wfi ; j _start
    };

    logic [$clog2(RomSize)-1:0] addr_q;

    always_ff @(posedge clk_i) begin
        if (req_i) begin
            addr_q <= addr_i[$clog2(RomSize)-1+3:3];
        end
    end

    // this prevents spurious Xes from propagating into
    // the speculative fetch stage of the core
    assign rdata_o = (addr_q < RomSize) ? mem[addr_q] : '0;
endmodule
