# Copyright 2022 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51

# NB_CORES is hardcoded to 1 in soc_pkg.sv; this target is a no-op kept for
# Makefile compatibility (integration/Makefile calls nb_cores: nb_cores_sw nb_cores_rtl).
.PHONY: nb_cores_rtl
nb_cores_rtl:

# Compile the RTL

CVA6_DIR = $(root-dir)

# LLC
LLC_DIR = ../../modules/axi_llc
LLC_PKG := src/axi_llc_pkg.sv \
           src/axi_llc_reg_pkg.sv
LLC_PKG := $(addprefix $(LLC_DIR)/, $(LLC_PKG))

LLC_SRC := src/axi_llc_burst_cutter.sv \
           src/axi_llc_data_way.sv \
           src/axi_llc_merge_unit.sv \
           src/axi_llc_read_unit.sv \
           src/axi_llc_reg_top.sv \
           src/axi_llc_write_unit.sv \
           src/eviction_refill/axi_llc_ax_master.sv \
           src/eviction_refill/axi_llc_r_master.sv \
           src/eviction_refill/axi_llc_w_master.sv \
           src/hit_miss_detect/axi_llc_evict_box.sv \
           src/hit_miss_detect/axi_llc_lock_box_bloom.sv \
           src/hit_miss_detect/axi_llc_miss_counters.sv \
           src/hit_miss_detect/axi_llc_tag_pattern_gen.sv \
           src/axi_llc_chan_splitter.sv \
           src/axi_llc_evict_unit.sv \
           src/axi_llc_refill_unit.sv \
           src/axi_llc_ways.sv \
           src/hit_miss_detect/axi_llc_tag_store.sv \
           src/axi_llc_config.sv \
           src/axi_llc_hit_miss.sv \
           src/axi_llc_top.sv \
           src/axi_llc_reg_wrap.sv
LLC_SRC := $(addprefix $(LLC_DIR)/, $(LLC_SRC))

LLC_INCDIR := $(LLC_DIR)/include
LLC_INCDIR := $(foreach dir, ${LLC_INCDIR}, +incdir+$(dir))
list_incdir += $(LLC_INCDIR)

# SoC sources
.PHONY: plic_regmap
plic_regmap: $(CVA6_DIR)/corev_apu/rv_plic/rtl/plic_regmap.sv
	cd $(CVA6_DIR)/corev_apu/rv_plic/rtl; \
	python3 gen_plic_addrmap.py -t $$(($(NB_CORES)*2)) > plic_regmap.sv

$(library) : $(CVA6_DIR)/corev_apu/rv_plic/rtl/plic_regmap.sv

SOC_DIR := ../../rtl
SOC_PKG := $(wildcard $(SOC_DIR)/include/*_pkg.sv)

# ACE pkg is still needed by axi_adapter (ace_pkg::READ_NO_SNOOP).
SOC_SRC += $(CVA6_DIR)/vendor/pulp-platform/common_cells/src/cf_math_pkg.sv
SOC_SRC += $(CVA6_DIR)/vendor/pulp-platform/axi/src/axi_pkg.sv
SOC_SRC += $(CVA6_DIR)/vendor/planv/ace/src/ace_pkg.sv
SOC_SRC += $(CVA6_DIR)/vendor/planv/ace/src/snoop_pkg.sv
SOC_SRC += $(CVA6_DIR)/corev_apu/tb/common/mock_uart.sv
# Include all SoC RTL files except the FPGA-only top (which uses Xilinx IPs)
# and flexnngine_wrap (which requires the FleXNNgine VHDL + Xilinx IP;
# replaced by a sim stub below).
SOC_SRC += $(filter-out \
    $(SOC_DIR)/src/cva6_flexnngine_xilinx.sv \
    $(SOC_DIR)/src/flexnngine_wrap.sv, \
    $(wildcard $(SOC_DIR)/src/*.sv))
SOC_INCDIR := $(SOC_DIR)/include
SOC_INCDIR := $(foreach dir, ${SOC_INCDIR}, +incdir+$(dir))
list_incdir += $(SOC_INCDIR)

# Compile the test bench

CVA6_TEST += $(CVA6_DIR)/corev_apu/tb/common_verification/src/rand_id_queue.sv
CVA6_TEST += $(CVA6_DIR)/vendor/pulp-platform/axi/src/axi_test.sv
# ace_test, snoop_test, tb_ace_ccu_pkg: removed — coherence test packages, not used by single-core testbench
# dcache_intf, icache_intf, sram_intf, amo_intf, tb_std_cache_subsystem_pkg: removed — unit-test-only cache interfaces


TB_DIR = ./tb
TB_SRC := $(wildcard $(TB_DIR)/*.sv)

TOP_LEVEL := cva6_flexnngine_tb

VERILATOR_LIB = work_verilate
DEFINES ?=

HAS_LLC ?= 1
DEFINES += TB_HAS_LLC=$(HAS_LLC)

# use visualizer as GUI backend for Questa
USE_VISUALIZER ?= 0

ifeq ($(USE_XILINX_SRAM), 1)
	# overwrite the tc_sram definition
	SOC_SRC += $(XILINX_VIVADO)/data/ip/xpm/xpm_memory/hdl/xpm_memory.sv
	SOC_SRC += $(CVA6_DIR)/vendor/pulp-platform/tech_cells_generic/src/fpga/tc_sram_xilinx.sv
	DEFINES += USE_XILINX_SRAM=1
	# set this define to avoid warnings about initialisarion in tc_sram_xilinx
	DEFINES += TARGET_SYNTHESIS
endif

#VLOG_FLAGS += +cover=bcfst+/dut -incr -64 -nologo -quiet -suppress 13262 -suppress 2583 -permissive +define+$(defines)
#VLOG_FLAGS += -incr -64 -nologo -quiet -suppress 13262 -suppress 2583 -permissive +define+$(defines)
VLOG_FLAGS += -svinputport=compat -incr -64 -nologo -quiet -suppress 13262 -suppress 2583
VLOG_FLAGS += -suppress 2986 # (vlog-2986) The hierarchical reference 'aw_chan_i.id' is not legal in a constant expression context.
VLOG_FLAGS += -suppress 2879 # allow calling tasks in final procedure
ifneq ($(DEFINES), "")
VLOG_FLAGS += $(foreach def, $(DEFINES), +define+$(def))
endif

COVER            ?= 0
COVERAGE_MODULES ?=
ifneq ($(COVER), 0)
	ifneq ($(COVERAGE_MODULES), )
		VOPT_FLAGS += $(foreach mod, $(COVERAGE_MODULES), +cover+$(mod))
	else
		VOPT_FLAGS += +cover
	endif
	VOPT_FLAGS += -coveropt 1
endif

# add access if running GUI
ifeq ($(GUI), 1)
    ifeq ($(USE_VISUALIZER), 1)
        VOPT_FLAGS += -access=rw+/.
        VOPT_FLAGS += -cellaccess=rw+/.
        VOPT_FLAGS += -debug,cell
        VOPT_FLAGS += -designfile $(library)/design.bin
    endif
endif
# this is still needed due to coding style in stream_xbar.sv
VOPT_FLAGS += +acc

verilate_command := $(verilator) $(CVA6_DIR)/verilator_config.vlt                                                \
                    -f $(CVA6_DIR)/core/Flist.cva6                                                               \
                    $(filter-out %.vhd, $(ariane_pkg))                                                           \
                    $(filter-out $(CVA6_DIR)/core/fpu_wrap.sv, $(filter-out %.vhd, $(src)))                      \
                    +define+$(defines)$(if $(TRACE_FAST),+VM_TRACE)$(if $(TRACE_COMPACT),+VM_TRACE+VM_TRACE_FST) \
                    $(CVA6_DIR)/corev_apu/tb/common/mock_uart.sv                                                 \
                    +incdir+$(CVA6_DIR)/corev_apu/axi_node                                                       \
                    $(LLC_PKG) $(LLC_SRC)                                                                      \
                    $(SOC_PKG) $(SOC_SRC)                                                                \
                    $(if $(verilator_threads), --threads $(verilator_threads))                                   \
                    --unroll-count 256                                                                           \
                    -Wall                                                                                        \
                    -Werror-PINMISSING                                                                           \
                    -Werror-IMPLICIT                                                                             \
                    -Wno-fatal                                                                                   \
                    -Wno-PINCONNECTEMPTY                                                                         \
                    -Wno-ASSIGNDLY                                                                               \
                    -Wno-DECLFILENAME                                                                            \
                    -Wno-UNUSED                                                                                  \
                    -Wno-UNOPTFLAT                                                                               \
                    -Wno-BLKANDNBLK                                                                              \
                    -Wno-style                                                                                   \
                    $(if ($(PRELOAD)!=""), -DPRELOAD=1,)                                                         \
                    $(if $(PROFILE),--stats --stats-vars --profile-cfuncs,)                                      \
                    $(if $(DEBUG), --trace-structs,)                                                             \
                    $(if $(TRACE_COMPACT), --trace-fst $(VERILATOR_ROOT)/include/verilated_fst_c.cpp)            \
                    $(if $(TRACE_FAST), --trace $(VERILATOR_ROOT)/include/verilated_vcd_c.cpp,)                  \
                    -LDFLAGS "-L$(RISCV)/lib -L$(SPIKE_ROOT)/lib -Wl,-rpath,$(RISCV)/lib -Wl,-rpath,$(SPIKE_ROOT)/lib -lfesvr$(if $(PROFILE), -g -pg,) -lpthread $(if $(TRACE_COMPACT), -lz,)" \
                    -CFLAGS "$(CFLAGS)$(if $(PROFILE), -g -pg,) -DVL_DEBUG"                                      \
                    --cc  --vpi                                                                                  \
                    $(list_incdir) --top-module cva6_flexnngine_top                                           \
                    --threads-dpi none                                                                           \
                    --Mdir $(VERILATOR_LIB) -O3                                                                    \
                    --exe ./tb/cva6_flexnngine_tb.cpp

$(library)/.build-llc-srcs: $(library) $(LLC_PKG) $(LLC_SRC)
	$(VLOG) $(VLOG_FLAGS) -work $(library) $(LLC_PKG) $(list_incdir)
	$(VLOG) $(VLOG_FLAGS) -timescale "1ns / 1ns" -work $(library) -pedanticerrors $(LLC_SRC) $(list_incdir)
	@touch $(library)/.build-llc-srcs

$(library)/.build-soc-srcs: $(library) $(library)/.build-llc-srcs $(SOC_PKG) $(SOC_SRC)
	$(VLOG) $(VLOG_FLAGS) -work $(library) $(SOC_PKG) $(list_incdir)
	$(VLOG) $(VLOG_FLAGS) -timescale "1ns / 1ns" -work $(library) -pedanticerrors $(SOC_SRC) $(list_incdir)
	@touch $(library)/.build-soc-srcs

$(library)/.build-soc-tb: $(library)/.build-soc-srcs $(library) $(TB_SRC) $(CVA6_TEST)
	$(VLOG) $(VLOG_FLAGS) -timescale "1ns / 1ns" -work $(library) -pedanticerrors $(CVA6_TEST) $(list_incdir)
	$(VLOG) $(VLOG_FLAGS) -timescale "1ns / 1ns" -work $(library) -pedanticerrors $(TB_SRC) $(list_incdir)
	@touch $(library)/.build-soc-tb

ifeq ($(VERILATE), 0)
rtl: nb_cores_rtl $(library)/.build-srcs $(library)/.build-soc-srcs $(library)/.build-soc-tb
	$(VOPT) $(VOPT_FLAGS) -work $(library)  $(TOP_LEVEL) -o $(TOP_LEVEL)_optimized
else
VERILATOR_JOBS = 1
rtl:
	$(verilate_command)
	cd $(VERILATOR_LIB) && $(MAKE) -j${VERILATOR_JOBS} -f Vcva6_flexnngine_top.mk
endif


# Cleanup

clean_rtl: nb_cores_rtl plic_regmap
	rm -rf $(library)
	rm -rf $(VERILATOR_LIB)
	rm -rf $(COVERAGE_DIR)

# Override CVA6's ariane_dpi.so rule: cva6_flexnngine_tb uses $readmemh, not Spike DPI.
# Build an empty stub to satisfy the dependency without requiring libfesvr.
$(dpi-library)/ariane_dpi.so:
	mkdir -p $(dpi-library)
	g++ -shared -fPIC -o $@ -x c /dev/null

.PHONY: rtl clean_rtl
