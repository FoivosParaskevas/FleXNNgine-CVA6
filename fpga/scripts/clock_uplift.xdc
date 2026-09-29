# Clock uplift (50/50/250, matching Lesniak 2024 Table 2): MMCM clk_out1
# (50 MHz — CVA6 + AXI + PE array) and clk_out5 (250 MHz — FleXNNgine
# scratchpad) are genuinely asynchronous relative to each other. All data
# crossings are handled by xlnx_axi_clock_converter_spad (for the BRAM AXI
# path) and acc_axi_top's bit_sync stages (for the start/done/reset control
# signals when AxiAccCDC=1). Declare the two clock domains as async so STA
# doesn't try to meet cross-domain setup.
set_clock_groups -name clk_uplift_system_spad_async -asynchronous \
    -group [get_clocks -include_generated_clocks clk_out1_xlnx_clk_gen] \
    -group [get_clocks -include_generated_clocks clk_out5_xlnx_clk_gen]
