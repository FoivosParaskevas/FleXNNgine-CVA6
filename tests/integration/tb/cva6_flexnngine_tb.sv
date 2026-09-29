// Copyright 2022 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Minimal testbench for the single-core CVA6 + FleXNNgine SoC.

module cva6_flexnngine_tb
    import ariane_pkg::*;
#()();

    `define WAIT_CYC(CLK, N) \
        repeat(N) @(posedge(CLK));

    localparam ariane_cfg_t ArianeCfg = soc_pkg::ArianeSocCfg;

    localparam time         CLK_PERIOD       = 10ns;
    localparam int unsigned RTC_CLOCK_PERIOD = 30517; // ~30.517 µs in ns
    localparam int unsigned NUM_WORDS        = 4**10;
    localparam bit          HAS_LLC          = 1'b1;

    // TB signals
    logic        clk;
    logic        rst_n;
    logic        rtc;
    logic [31:0] exit_val;

    //--------------------------------------------------------------------------
    // Clock & reset generation
    //--------------------------------------------------------------------------

    initial begin
        clk   = 1'b0;
        rst_n = 1'b0;

        repeat(8)
            #(CLK_PERIOD/2) clk = ~clk;

        rst_n = 1'b1;

        forever begin
            #(CLK_PERIOD/2) clk = ~clk;
        end
    end

    initial begin
        rtc = 1'b0;
        forever begin
            #(RTC_CLOCK_PERIOD/2) rtc = ~rtc;
        end
    end

    //--------------------------------------------------------------------------
    // DUT
    //--------------------------------------------------------------------------
    cva6_flexnngine_top #(
        .InclSimDTM       (1'b0),
        .NUM_WORDS        (NUM_WORDS),
        .HasLLC           (HAS_LLC),
        .BootAddress      (soc_pkg::DRAMBase + 64'h10_0000)
    ) i_dut (
        .clk_i  ( clk      ),
        .rtc_i  ( rtc      ),
        .rst_ni ( rst_n    ),
        .exit_o ( exit_val )
    );

    //--------------------------------------------------------------------------
    // Tests
    //--------------------------------------------------------------------------

    task test_header (string testname, string description="");
        $display("--------------------------------------------------------------------------");
        $display("Running test %s", testname);
        $display("%s", description);
        $display("--------------------------------------------------------------------------");
    endtask

    initial begin : TESTS
        integer file;
        static    string mem_init_file = "main.hex";
        automatic string testname      = "";

        if (!$value$plusargs("TESTNAME=%s", testname)) begin
            $error("No TESTNAME plusarg given");
        end

        test_header(testname, "");

        @(posedge rst_n);
        #2
        $readmemh(mem_init_file, i_dut.i_sram.i_tc_sram.sram);

        wait (exit_val[0]);

        file = $fopen("result.rpt", "w");
        if ((exit_val >> 1)) begin
            $error("*** FAILED *** (tohost = %0d)", (exit_val >> 1));
            $display("return code: 0x%x", (exit_val >> 1));
            $fdisplay(file, "FAIL");
            $fdisplay(file, "return code: 0x%x", (exit_val >> 1));
        end else begin
            $info("*** SUCCESS *** (tohost = %0d)", (exit_val >> 1));
            $fdisplay(file, "PASS");
        end
        $fclose(file);

        //--------------------------------------------------------------
        // end of tests
        //--------------------------------------------------------------
        `WAIT_CYC(clk, 100)
        $display("Test done");
        $finish();
    end

endmodule
