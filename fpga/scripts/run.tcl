# Copyright 2018 ETH Zurich and University of Bologna.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Author: Florian Zaruba <zarubaf@iis.ee.ethz.ch>

# Added VCU118 compatibility

# load board files from this repo, without the need to install anything globally
# set_param board.repoPaths [list "scripts/board_files"]

if {$::env(BOARD) eq "genesys2"} {
    add_files -fileset constrs_1 -norecurse constraints/genesys-2.xdc
} elseif {$::env(BOARD) eq "kc705"} {
      add_files -fileset constrs_1 -norecurse constraints/kc705.xdc
} elseif {$::env(BOARD) eq "vc707"} {
      add_files -fileset constrs_1 -norecurse constraints/vc707.xdc
} elseif {$::env(BOARD) eq "vcu118"} {
      add_files -fileset constrs_1 -norecurse constraints/vcu118.xdc
} else {
      exit 1
}
# "xilinx/xlnx_mig_7_ddr3/xlnx_mig_7_ddr3.srcs/sources_1/ip/xlnx_mig_7_ddr3/xlnx_mig_7_ddr3.xci" \
#read_ip xilinx/xlnx_axi_dwidth_converter/xlnx_axi_dwidth_converter.srcs/sources_1/ip/xlnx_axi_dwidth_converter/xlnx_axi_dwidth_converter.xci

read_ip { \
      "xilinx/xlnx_axi_clock_converter/xlnx_axi_clock_converter.srcs/sources_1/ip/xlnx_axi_clock_converter/xlnx_axi_clock_converter.xci" \
      "xilinx/xlnx_axi_dwidth_converter/xlnx_axi_dwidth_converter.srcs/sources_1/ip/xlnx_axi_dwidth_converter/xlnx_axi_dwidth_converter.xci" \
      "xilinx/xlnx_axi_dwidth_converter_dm_slave/xlnx_axi_dwidth_converter_dm_slave.srcs/sources_1/ip/xlnx_axi_dwidth_converter_dm_slave/xlnx_axi_dwidth_converter_dm_slave.xci" \
      "xilinx/xlnx_axi_dwidth_converter_dm_master/xlnx_axi_dwidth_converter_dm_master.srcs/sources_1/ip/xlnx_axi_dwidth_converter_dm_master/xlnx_axi_dwidth_converter_dm_master.xci" \
      "xilinx/xlnx_axi_gpio/xlnx_axi_gpio.srcs/sources_1/ip/xlnx_axi_gpio/xlnx_axi_gpio.xci" \
      "xilinx/xlnx_axi_bram_ctrl_flexnngine/xlnx_axi_bram_ctrl_flexnngine.srcs/sources_1/ip/xlnx_axi_bram_ctrl_flexnngine/xlnx_axi_bram_ctrl_flexnngine.xci" \
      "xilinx/float32_mac/float32_mac.srcs/sources_1/ip/float32_mac/float32_mac.xci" \
      "xilinx/xlnx_axi_quad_spi/xlnx_axi_quad_spi.srcs/sources_1/ip/xlnx_axi_quad_spi/xlnx_axi_quad_spi.xci" \
      "xilinx/xlnx_clk_gen/xlnx_clk_gen.srcs/sources_1/ip/xlnx_clk_gen/xlnx_clk_gen.xci" \
      "xilinx/xlnx_ila/xlnx_ila.srcs/sources_1/ip/xlnx_ila/xlnx_ila.xci" \
      "xilinx/xlnx_axi_dwidth_converter_512_64/xlnx_axi_dwidth_converter_512_64.srcs/sources_1/ip/xlnx_axi_dwidth_converter_512_64/xlnx_axi_dwidth_converter_512_64.xci" \
      "xilinx/xlnx_mig_ddr4/xlnx_mig_ddr4.srcs/sources_1/ip/xlnx_mig_ddr4/xlnx_mig_ddr4.xci" \
}

set_property include_dirs { \
      "../modules/cva6/vendor/pulp-platform/common_cells/include" \
      "../modules/cva6/vendor/pulp-platform/axi/include" \
      "../modules/cva6/vendor/planv/ace/include" \
      "../modules/axi_llc/include" \
      "../modules/cva6/corev_apu/register_interface/include" \
} [current_fileset]

source scripts/add_sources.tcl

set_property top ${project}_xilinx [current_fileset]

if {$::env(BOARD) eq "genesys2"} {
    read_verilog -sv {src/genesysii.svh ../modules/cva6/vendor/pulp-platform/common_cells/include/common_cells/registers.svh}
    set file "src/genesysii.svh"
    set registers "../modules/cva6/vendor/pulp-platform/common_cells/include/common_cells/registers.svh"
} elseif {$::env(BOARD) eq "kc705"} {
      read_verilog -sv {src/kc705.svh ../modules/cva6/vendor/pulp-platform/common_cells/include/common_cells/registers.svh}
      set file "src/kc705.svh"
      set registers "../modules/cva6/vendor/pulp-platform/common_cells/include/common_cells/registers.svh"
} elseif {$::env(BOARD) eq "vc707"} {
      read_verilog -sv {src/vc707.svh ../modules/cva6/vendor/pulp-platform/common_cells/include/common_cells/registers.svh}
      set file "src/vc707.svh"
      set registers "../modules/cva6/vendor/pulp-platform/common_cells/include/common_cells/registers.svh"
} elseif {$::env(BOARD) eq "vcu118"} {
      read_verilog -sv {src/vcu118.svh ../modules/cva6/vendor/pulp-platform/common_cells/include/common_cells/registers.svh}
      set file "src/vcu118.svh"
      set registers "../modules/cva6/vendor/pulp-platform/common_cells/include/common_cells/registers.svh"
} else {
    exit 1
}

set file_obj [get_files -of_objects [get_filesets sources_1] [list "*$file" "$registers"]]
set_property -dict { file_type {Verilog Header} is_global_include 1} -objects $file_obj

update_compile_order -fileset sources_1

add_files -fileset constrs_1 -norecurse constraints/ariane.xdc

# Project-local clock-uplift constraints (task #7): declares 250 MHz
# scratchpad clock asynchronous to 50 MHz system clock. Kept separate from
# the submodule-owned vcu118.xdc so we don't have to bump modules/cva6.
add_files -fileset constrs_1 -norecurse scripts/clock_uplift.xdc

synth_design -rtl -name rtl_1

set_property STEPS.SYNTH_DESIGN.ARGS.RETIMING true [get_runs synth_1]

launch_runs synth_1
wait_on_run synth_1
open_run synth_1

exec mkdir -p reports/
exec rm -rf reports/*

check_timing -verbose                                                   -file reports/$project.check_timing.rpt
report_timing -max_paths 100 -nworst 100 -delay_type max -sort_by slack -file reports/$project.timing_WORST_100.rpt
report_timing -nworst 1 -delay_type max -sort_by group                  -file reports/$project.timing.rpt
report_utilization -hierarchical                                        -file reports/$project.utilization.rpt
report_cdc                                                              -file reports/$project.cdc.rpt
report_clock_interaction                                                -file reports/$project.clock_interaction.rpt

# set for RuntimeOptimized implementation
set_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE RuntimeOptimized    [get_runs impl_1]
set_property STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE RuntimeOptimized    [get_runs impl_1]
set_property STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE RuntimeOptimized [get_runs impl_1]
set_property STEPS.OPT_DESIGN.ARGS.DIRECTIVE RuntimeOptimized      [get_runs impl_1]

# disable power optimization
set_property STEPS.POST_PLACE_POWER_OPT_DESIGN.IS_ENABLED false    [get_runs impl_1]
set_property STEPS.POWER_OPT_DESIGN.IS_ENABLED false               [get_runs impl_1]

launch_runs impl_1
wait_on_run impl_1
set_property STEPS.WRITE_BITSTREAM.TCL.PRE \
    [file normalize scripts/pre_bitstream.tcl] [get_runs impl_1]
launch_runs impl_1 -to_step write_bitstream
wait_on_run impl_1
open_run impl_1

# output Verilog netlist + SDC for timing simulation
write_verilog -force -mode funcsim work-fpga/${project}_funcsim.v
write_verilog -force -mode timesim work-fpga/${project}_timesim.v
write_sdf     -force work-fpga/${project}_timesim.sdf

# reports
exec mkdir -p reports/
exec rm -rf reports/*
check_timing                                                              -file reports/${project}.check_timing.rpt
report_timing -max_paths 100 -nworst 100 -delay_type max -sort_by slack   -file reports/${project}.timing_WORST_100.rpt
report_timing -nworst 1 -delay_type max -sort_by group                    -file reports/${project}.timing.rpt
report_utilization -hierarchical                                          -file reports/${project}.utilization.rpt
