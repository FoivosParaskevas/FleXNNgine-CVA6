# Copyright 2022 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51

# include an additional script, which implements testcase-specific functions
set sim_extensions "sim_ext.tcl"
if { [file exists $sim_extensions] == 1} {
    source $sim_extensions
}

# Single-core CVA6 + FleXNNgine TB hierarchy.
add wave /cva6_flexnngine_tb/i_dut/*
add wave /cva6_flexnngine_tb/i_dut/i_ariane/i_cva6/commit_stage_i/*
add wave /cva6_flexnngine_tb/i_dut/i_ariane/i_cva6/WB/i_cache_subsystem/i_nbdcache/*
add wave /cva6_flexnngine_tb/i_dut/i_ariane/i_cva6/WB/i_cache_subsystem/i_nbdcache/i_miss_handler/*
add wave /cva6_flexnngine_tb/i_dut/i_ariane/i_cva6/WB/i_cache_subsystem/i_nbdcache/master_ports[1]/i_cache_ctrl/*
add wave /cva6_flexnngine_tb/i_dut/i_ariane/i_cva6/WB/i_cache_subsystem/i_nbdcache/master_ports[2]/i_cache_ctrl/*
add wave /cva6_flexnngine_tb/i_dut/i_ariane/i_cva6/issue_stage_i/i_issue_read_operands/gen_asic_regfile/i_ariane_regfile/mem
