# Override default goal before including CVA6 Makefile, whose first target
# (vcs_build) would otherwise become the default for 'make -C fpga'.
.DEFAULT_GOAL := all

#BOARD          ?= genesys2
BOARD          ?= vcu118
VIVADO ?= vivado

HOSTNAME := $(shell hostname)
ifneq (,$(findstring lis,$(HOSTNAME)))
    MODULEFILE_FLAG := -source scripts/add_modulefiles.tcl
endif

VIVADOFLAGS = -nojournal -mode batch $(MODULEFILE_FLAG) -source scripts/prologue.tcl

NB_CORES = 1

target = cv64a6_imafdch_sv39_wb
include ../modules/cva6/Makefile

CVA6_DIR = $(root-dir)
LLC_DIR = ../modules/axi_llc


# Compile the RTL

work-dir := work-fpga
bit := $(work-dir)/cva6_flexnngine_xilinx.bit
ip-dir := xilinx
ips := xlnx_axi_clock_converter.xci  \
       xlnx_axi_dwidth_converter.xci \
       xlnx_axi_dwidth_converter_dm_master.xci \
       xlnx_axi_dwidth_converter_dm_slave.xci \
       xlnx_axi_bram_ctrl_flexnngine.xci \
       float32_mac.xci               \
       xlnx_clk_gen.xci              \
       xlnx_mig_ddr4.xci	     \
       xlnx_axi_dwidth_converter_512_64.xci
       #xlnx_mig_7_ddr3.xci


#ips_standard := xlnx_axi_clock_converter.xci  \
       xlnx_axi_dwidth_converter.xci \
       xlnx_axi_quad_spi.xci         \
       xlnx_axi_gpio.xci             \
       xlnx_clk_gen.xci

#ips_ddr3 := xlnx_mig_7_ddr3.xci

#ips_ddr4 := xlnx_mig_ddr4.xci	     \
       		xlnx_axi_dwidth_converter_512_64.xci

ips := $(addprefix $(work-dir)/, $(ips))
ips-target := $(join $(addsuffix /ip/, $(addprefix $(ip-dir)/, $(basename $(ips)))), $(ips))

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

SOC_DIR := ../rtl
SOC_PKG := $(SOC_DIR)/include/soc_pkg.sv

# ACE/AXI packages must be read first (ace_pkg still needed by axi_adapter internals)
SOC_SRC += $(CVA6_DIR)/vendor/pulp-platform/common_cells/src/cf_math_pkg.sv
SOC_SRC += $(CVA6_DIR)/vendor/pulp-platform/axi/src/axi_pkg.sv
SOC_SRC += $(CVA6_DIR)/vendor/planv/ace/src/ace_pkg.sv
SOC_SRC += $(CVA6_DIR)/vendor/planv/ace/src/snoop_pkg.sv
# ACE interface definitions (used by CVA6 axi_adapter internally)
SOC_SRC += $(CVA6_DIR)/vendor/planv/ace/src/ace_intf.sv
SOC_SRC += $(CVA6_DIR)/vendor/planv/ace/src/snoop_intf.sv
# SoC sources
SOC_SRC += $(SOC_DIR)/src/soc_peripherals.sv
SOC_SRC += $(SOC_DIR)/src/cva6_flexnngine_xilinx.sv
SOC_SRC += $(SOC_DIR)/src/flexnngine_wrap.sv

# CVA6 core source files (from core/Flist.cva6)
CVA6_CORE_SRC := $(shell find $(CVA6_DIR)/core -name "*.sv" -not -path "*/mmu_sv32/*" -not -name "std_no_dcache.sv" | sort)
CVA6_CORE_SRC += $(shell find $(CVA6_DIR)/core/mmu_sv39 -name "*.sv" 2>/dev/null | sort)
CVA6_CORE_SRC += $(shell find $(CVA6_DIR)/core/mmu_sv39x4 -name "*.sv" 2>/dev/null | sort)
CVA6_CORE_SRC += $(shell find $(CVA6_DIR)/common/local/util -name "*.sv" 2>/dev/null | sort)
CVA6_CORE_SRC += $(shell find $(CVA6_DIR)/vendor/pulp-platform/common_cells/src -name "*.sv" -not -path "*/deprecated/*" 2>/dev/null | sort)
CVA6_CORE_SRC += $(shell find $(CVA6_DIR)/vendor/pulp-platform/axi/src -name "*.sv" 2>/dev/null | sort)
CVA6_CORE_SRC += $(shell find $(CVA6_DIR)/corev_apu/axi_mem_if/src -name "*.sv" -not -path "*/deprecated/*" 2>/dev/null | sort)
CVA6_CORE_SRC += $(shell find $(CVA6_DIR)/vendor/openhwgroup/cvfpu -name "*.sv" | sort)
CVA6_CORE_SRC += $(shell find $(CVA6_DIR)/vendor/openhwgroup/cv_fpu -name "*.sv" 2>/dev/null | sort)
CVA6_CORE_SRC += $(shell find $(CVA6_DIR)/vendor/pulp-platform/fpga-support/rtl -name "*.sv" | sort)
CVA6_CORE_SRC += $(shell find $(CVA6_DIR)/vendor/pulp-platform/tech_cells_generic/src -name "*.sv" | sort)

FLEXNNGINE_DIR := ../modules/flexnngine/hdl
FLEXNNGINE_SRC := \
    ${FLEXNNGINE_DIR}/utilities.vhd \
    ${FLEXNNGINE_DIR}/gray.vhd \
    ${FLEXNNGINE_DIR}/sync.vhd \
    ${FLEXNNGINE_DIR}/fifos.vhd \
    ${FLEXNNGINE_DIR}/acc.vhd \
    ${FLEXNNGINE_DIR}/demux.vhd \
    ${FLEXNNGINE_DIR}/mult.vhd \
    ${FLEXNNGINE_DIR}/mac.vhd \
    ${FLEXNNGINE_DIR}/mux.vhd \
    ${FLEXNNGINE_DIR}/onehot_binary.vhd \
    ${FLEXNNGINE_DIR}/ram_dp.vhd \
    ${FLEXNNGINE_DIR}/rr_arbiter.vhd \
    ${FLEXNNGINE_DIR}/line_buffer.vhd \
    ${FLEXNNGINE_DIR}/pe.vhd \
    ${FLEXNNGINE_DIR}/psum_bias.vhd \
    ${FLEXNNGINE_DIR}/psum_activation.vhd \
    ${FLEXNNGINE_DIR}/psum_requantize.vhd \
    ${FLEXNNGINE_DIR}/postproc.vhd \
    ${FLEXNNGINE_DIR}/pe_array.vhd \
    ${FLEXNNGINE_DIR}/serializer.vhd \
    ${FLEXNNGINE_DIR}/parallelizer.vhd \
    ${FLEXNNGINE_DIR}/ram_dp_bwe.vhd \
    ${FLEXNNGINE_DIR}/spad_reshape.vhd \
    ${FLEXNNGINE_DIR}/scratchpad.vhd \
    ${FLEXNNGINE_DIR}/scratchpad_interface.vhd \
    ${FLEXNNGINE_DIR}/address_generator_iact.vhd \
    ${FLEXNNGINE_DIR}/address_generator_wght.vhd \
    ${FLEXNNGINE_DIR}/address_generator_psum.vhd \
    ${FLEXNNGINE_DIR}/throttle.vhd \
    ${FLEXNNGINE_DIR}/control.vhd \
    ${FLEXNNGINE_DIR}/control_address_generator.vhd \
    ${FLEXNNGINE_DIR}/control_arch_rs.vhd \
    ${FLEXNNGINE_DIR}/control_arch_alt_rs.vhd \
    ${FLEXNNGINE_DIR}/accelerator.vhd \
    ${FLEXNNGINE_DIR}/axi/acc_axi_regs.vhd \
    ${FLEXNNGINE_DIR}/axi/acc_axi_top.vhd

TOP_LEVEL := cva6_flexnngine_xilinx

fpga_filter += $(addprefix $(CVA6_DIR), corev_apu/fpga/src/ariane_xilinx.sv)
fpga_filter += $(wildcard $(addprefix $(CVA6_DIR), corev_apu/tb/ariane_*.sv))
# Exclude fpga-support files that use the old 'CfMath' package name (now cf_math_pkg).
# Unresolved CfMath::ceil_div/log2 references cause Vivado srcscanner to hang indefinitely.
fpga_filter += $(CVA6_DIR)/vendor/pulp-platform/fpga-support/rtl/AxiBramLogger.sv
fpga_filter += $(CVA6_DIR)/vendor/pulp-platform/fpga-support/rtl/BramDwc.sv
fpga_filter += $(CVA6_DIR)/vendor/pulp-platform/fpga-support/rtl/BramLogger.sv
fpga_filter += $(CVA6_DIR)/vendor/pulp-platform/fpga-support/rtl/TdpBramArray.sv

all: $(bit)

$(bit): $(ips) scripts/add_sources.tcl $(CVA6_DIR)/corev_apu/rv_plic/rtl/plic_regmap.sv
	@echo "[FPGA] Generate Bitstream"
	@mkdir -p $(work-dir)
	export BOARD=$(BOARD) XILINX_PART=$(XILINX_PART) XILINX_BOARD=$(XILINX_BOARD) CLK_PERIOD_NS=$(CLK_PERIOD_NS); \
	$(VIVADO) $(VIVADOFLAGS) -source scripts/run.tcl
	cp cva6_flexnngine.runs/impl_1/cva6_flexnngine_xilinx.bit ./$(work-dir)/

$(ips): %.xci :
	mkdir -p $(work-dir)
	@echo Generating $(@F)
	@cd $(ip-dir)/$(basename $(@F)) && make clean && make BOARD=$(BOARD) XILINX_PART=$(XILINX_PART) XILINX_BOARD=$(XILINX_BOARD) CLK_PERIOD_NS=$(CLK_PERIOD_NS)
	@cp $(ip-dir)/$(basename $(@F))/$(basename $(@F)).srcs/sources_1/ip/$(basename $(@F))/$(@F) $@


.PHONY: $(CVA6_DIR)/corev_apu/rv_plic/rtl/plic_regmap.sv
$(CVA6_DIR)/corev_apu/rv_plic/rtl/plic_regmap.sv:
	cd $$(dirname $@); \
	python3 gen_plic_addrmap.py -t $$(($(NB_CORES)*2)) > plic_regmap.sv

scripts/add_sources.tcl: $(ariane_pkg) $(src) $(fpga_src) $(uart_src) $(src_flist) $(LLC_PKG) $(SOC_PKG) $(LLC_SRC)  $(SOC_SRC)
	@echo "[FPGA] Generate sources"
	@echo read_vhdl        {$(uart_src)}                                          > scripts/add_sources.tcl
	@echo read_vhdl -vhdl2008 -library accel {$(FLEXNNGINE_SRC)}                 >> scripts/add_sources.tcl
	@echo read_verilog -sv {$(LLC_PKG)}                                          >> scripts/add_sources.tcl
	@echo read_verilog -sv {$(CVA6_DIR)/common/local/rvfi/rvfi_pkg.sv $(CVA6_DIR)/core/include/ariane_dm_pkg.sv $(CVA6_DIR)/core/include/riscv_pkg.sv $(CVA6_DIR)/core/include/ariane_pkg.sv $(CVA6_DIR)/core/include/ariane_axi_pkg.sv $(CVA6_DIR)/core/include/ariane_ace_pkg.sv $(CVA6_DIR)/core/include/cvxif_pkg.sv $(CVA6_DIR)/core/cvxif_example/include/cvxif_instr_pkg.sv} >> scripts/add_sources.tcl
	@echo read_verilog -sv {$(ariane_pkg)}                                       >> scripts/add_sources.tcl
	@echo read_verilog -sv {$(filter-out $(fpga_filter), $(CVA6_CORE_SRC))}     >> scripts/add_sources.tcl
	@if [ -n "$(filter-out $(fpga_filter), $(src_flist))" ]; then \
		echo read_verilog -sv {$(filter-out $(fpga_filter), $(src_flist))} >> scripts/add_sources.tcl; \
	fi
	@echo read_verilog -sv {$(CVA6_DIR)/core/cvxif_example/cvxif_example_coprocessor.sv $(CVA6_DIR)/core/cvxif_example/instr_decoder.sv} >> scripts/add_sources.tcl
	@echo read_verilog -sv {$(CVA6_DIR)/vendor/pulp-platform/common_cells/src/fifo_v3.sv $(CVA6_DIR)/vendor/pulp-platform/common_cells/src/delta_counter.sv $(CVA6_DIR)/vendor/pulp-platform/common_cells/src/counter.sv} >> scripts/add_sources.tcl
	@echo read_verilog -sv {$(filter-out $(fpga_filter), $(src))} 	              >> scripts/add_sources.tcl
	@echo read_verilog -sv {$(SOC_PKG)}                                          >> scripts/add_sources.tcl
	@echo read_verilog -sv {$(filter-out $(fpga_filter), $(fpga_src))}           >> scripts/add_sources.tcl
	@echo read_verilog -sv {$(filter-out $(fpga_filter), $(LLC_SRC))}            >> scripts/add_sources.tcl
	@echo read_verilog -sv {$(filter-out $(fpga_filter), $(SOC_SRC))} 	>> scripts/add_sources.tcl

.PHONY: clean

clean:
	rm -rf *.log *.jou *.str *.mif *.xpr $(work-dir) *.cache *.hw *.ip_user_files *.runs *.sim scripts/vivado* scripts/add_sources.tcl
