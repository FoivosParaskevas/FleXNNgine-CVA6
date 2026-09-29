# Copyright 2022 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51

include common.mk

TEST ?= all

VERILATE ?= 0

ifeq ($(TEST), all)
	TEST_SELECT := all
else
	TEST_SELECT := all TEST=$(TEST)
endif

# Test execution

integr:
	$(MAKE) -C integration VERILATE=$(VERILATE) $(TEST_SELECT)

sanity:
	@make -C integration clean all TEST=hello_world VERILATE=$(VERILATE)
	@printf "\nsanity check \033[32mPASSED\033[0m\n\n"

regr:
	@make -C integration clean all VERILATE=$(VERILATE)
	@printf "\nregression test \033[32mPASSED\033[0m\n\n"

# it only makes sense to call the target "all" if TESTS is set to "all"
ifeq ($(TEST), all)
all: integr
else
all:
	echo "TEST must be set to \"all\""
	false
endif

.PHONY : all integr sanity regr

# Test summary generation

summary:
	@echo "Generating test summary"

# Cleanup

clean_integr:
	make -C integration clean

clean: clean_integr

.PHONY: clean clean_integr
