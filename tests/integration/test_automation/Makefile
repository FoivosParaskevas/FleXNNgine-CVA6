# Copyright 2022 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51


ROOT_DIR := $(shell dirname $(abspath $(lastword $(MAKEFILE_LIST))))
include ../../../common.mk
include ../../../rtl.mk

SYS_DIR = ../../sw/sys
LIB_DIR = ../../libs
INC_DIR = ../../sw/include
INCLUDES = $(foreach d, $(INC_DIR), -I$d)
INCLUDES += $(foreach d, $(SYS_DIR), -I$d)

TEST_SRCS += $(shell find . -name "*.c" -exec basename {} \;)

CVA6_DIR = ../../../../modules/cva6
ASCON_DIR = ../../../../modules/ascon

SIMJTAG_SW_DIR = $(CVA6_DIR)/corev_apu/tb/dpi
SIMJTAG_SRCS =  $(SIMJTAG_SW_DIR)/SimJTAG.cc \
				$(SIMJTAG_SW_DIR)/remote_bitbang.cc \
				$(SIMJTAG_SW_DIR)/remote_bitbang.h
SIMJTAG_OUT_DIR = ../../tb

SV_LIBS = -sv_lib $(SIMJTAG_OUT_DIR)/SimJTAG

CFLAGS := \
	-Werror -g \
	$(INCLUDES)	\
	-L$(LIB_DIR)	\
	-DPREALLOCATE=1 \
	-mcmodel=medany \
	-static -std=gnu99 \
	-O3 -g -ffast-math \
	-fno-common \
	-fno-builtin-printf \
	$(SYS_DIR)/syscalls.c \
	-static -nostdlib \
	$(SYS_DIR)/crt.S \
	-nostartfiles \
	-lm -lgcc \
	-T $(SYS_DIR)/linker.ld \
	-march=rv64imafdc_zifencei \
	-lintegr -Xlinker \
	-Map=main.map \
	-fno-tree-loop-distribute-patterns \
	-fvisibility=hidden \
	-fno-zero-initialized-in-bss \
	-funroll-all-loops \
	-ffunction-sections -fdata-sections \
	-Wl,-gc-sections \
	-falign-jumps=32 -falign-functions=32 


## copied COREMARK flags from CVA6 repo - https://github.com/openhwgroup/cva6/blob/master/verif/regress/coremark.sh @ 70972da
COREMARK_ITERATIONS ?= 1
COREMARK_MULTICORE ?= 1 
COREMARK_CFLAGS := \
        -DCOMPILER_FLAGS='"$(CFLAGS)"' \
        -DITERATIONS=$(COREMARK_ITERATIONS) \
        -DPERFORMANCE_RUN   \
        -DSKIP_TIME_CHECK   \
        -DNOPRINT			\
		-DC_MULTICORE=$(COREMARK_MULTICORE)	\
		# -DCORE_DEBUG

# Rebuild RTL
build_rtl:
	@$(MAKE) -C ../../ rtl

# build objs and libs files for SW
objs_libs:
	@$(MAKE) -C ../../ clean_sw libs/libintegr.a nb_cores

# simJTAG SRC geneartion
simJTAG.so:
	@rm -rf $(SIMJTAG_OUT_DIR)/SimJTAG.so
	@g++ -m64 -shared -o $(SIMJTAG_OUT_DIR)/SimJTAG.so $(SIMJTAG_SRCS) -fPIC

# elf file generation
main.riscv : objs_libs $(TEST_SRCS) $(LIB_DIR)/libintegr.a $(SYS_DIR)/crt.S $(SYS_DIR)/syscalls.c $(SYS_DIR)/linker.ld
	$(RV_GCC) $(CFLAGS) -o main.riscv $(TEST_SRCS)  $(COREMARK_CFLAGS)

main.dis : main.riscv
	$(RV_OBJDUMP) -d main.riscv > main.dis

dis : main.dis

main.hex : main.riscv dis
	$(RV_OBJCOPY) -O verilog main.riscv main.vh
	python3 ../../test_automation/vh2hex.py -m main.vh -o main.hex -b 0x80000000 -d 0x80000000 -i 0x80100000
	rm main.vh
	@if [ "$(ENCRYPTION)" = "1" ]; then \
		rm -f ascon.hex; \
		python3 $(ASCON_DIR)/ascon.py; \
		rm -f main_encrypt.hex; \
	fi

sw : main.hex

# Test execution
TESTNAME := $(notdir $(patsubst %/,%,$(ROOT_DIR)))

GUI ?= 0

JTAG_ENABLE ?= 0

# the CCU monitor can be disabled by setting ENABLE_CCU_MON=0
# Note: the CCU monitor currently doesn't work when CCU.LatencyMode != NO_LATENCY
ENABLE_CCU_MON ?= 0

# enable check of cache contents vs main memory (disable if LLC is present)
ENABLE_MEM_CHECK ?= 0

VSIM_LIB = ../../work
VERILATOR_LIB = ../../work_verilate

TOP_LEVEL = cva6_flexnngine_tb
SIM_TCL = sim.tcl
SIM_RUNTIME ?= 1000ms

#UVM_FLAGS = +UVM_NO_RELNOTES +UVM_VERBOSITY=LOW
VSIM_FLAGS += -t 1ns -64 -classdebug
VSIM_FLAGS += -suppress 12110
VSIM_FLAGS += +TESTNAME=$(TESTNAME)
VSIM_FLAGS += +ENABLE_CCU_MON=$(ENABLE_CCU_MON)
VSIM_FLAGS += +ENABLE_MEM_CHECK=$(ENABLE_MEM_CHECK)
VSIM_FLAGS += +jtag_rbb_enable=$(JTAG_ENABLE)

ifneq ($(COVER), 0)
    VSIM_FLAGS += -coverage
    VSIM_FLAGS += -coverstore ../../$(COVERAGE_DIR) -testname $(TESTNAME)
endif

ifeq ($(GUI), 0)
	VSIM_FLAGS += -c
	VSIM_CMD = -do "run $(SIM_RUNTIME);"
else
	ifneq ($(GUI), 1)
		$(error GUI must be 0 or 1)
	else
		GTKWAVE_CMD = gtkwave waveform.vcd
	endif
	VSIM_CMD = -do "source $(SIM_TCL); run $(SIM_RUNTIME);"
endif

ifeq ($(VERILATE), 0)
$(TEST_REPORT): main.hex simJTAG.so 
	@rm -rf $(TEST_REPORT)
	@$(VSIM) $(VSIM_FLAGS) $(SV_LIBS) $(VSIM_CMD) -lib $(VSIM_LIB) $(UVM_FLAGS) $(TOP_LEVEL)_optimized | tee sim.log > /dev/null
	@if [[ "$$PWD" =~ integration ]]; then \
		if [ -f test.yaml ]; then \
			python3 ../../test_automation/testParser.py || true; \
		fi \
	fi
	@if [ -f postproc.sh ]; then ./postproc.sh; fi
	@grep "\*\* Error" sim.log  | tee -a  $(TEST_REPORT) > /dev/null
	@grep "\*\* Fatal" sim.log  | tee -a  $(TEST_REPORT) > /dev/null
else
$(TEST_REPORT): main.riscv
	-$(VERILATOR_LIB)/Vcva6_flexnngine_top main.riscv
	$(GTKWAVE_CMD)
endif

all: $(TEST_REPORT)
	@cat $(TEST_REPORT)
	@(! grep -s -n -m 1 "Error:" $(TEST_REPORT))
	@(! grep -s -n -m 1 "Fatal:" $(TEST_REPORT))
	@(! grep -s -n -m 1 "FAIL" $(TEST_REPORT))


clean_test:
	rm -rf objs
	rm -rf main.riscv
	rm -rf main.dis
	rm -rf main.hex
	rm -rf *.log
	rm -rf *.vcd
	rm -rf *.dasm
	rm -rf $(TEST_REPORT)
	rm -rf transcript
	rm -rf main.map
	rm -rf ace_log/
	rm -rf axi_log/
	rm -rf ../../$(COVERAGE_DIR)/$(TESTNAME)*
	rm -rf main_data.hex
	rm -rf main_encrypt.hex
	rm -rf main_instr.hex
	rm -rf ascon.hex
	rm -rf uart
	rm -rf mock_uart.txt
	rm -rf $(SIMJTAG_OUT_DIR)/SimJTAG.so
	rm -rf *.wlf
	rm -rf *.vstf

.PHONY: all gui sw dis sw clean_test
