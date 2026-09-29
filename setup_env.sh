#!/usr/bin/env bash
#
# Environment setup for building and simulating FleXNNgine-CVA6 on KIT
# infrastructure. Source this file in every new shell before invoking
# `make fpga`, `make test`, or the integration test harness:
#
#     source setup_env.sh

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")"; pwd -P)

# EDA tools available as environment modules on this machine.
module load xilinx/vivado/2022.2
module load questa/2023.4
module load synopsys/vcs/2020.12

# Local Verilator build (if present).
export PATH=${REPO_DIR}/tools/verilator/bin:${PATH}

# spike / fesvr install lands in ${REPO_DIR}/install64 (cva6-sdk's Makefile
# resolves $(PWD) relative to the directory make is invoked from, so the
# install prefix ends up here rather than under cva6-sdk/).
export PATH=${REPO_DIR}/install64/bin:${PATH}
export RISCV=${REPO_DIR}/install64

# RISC-V bare-metal GCC toolchain (riscv64-unknown-elf-* prefix required by
# CVA6). Built from https://github.com/riscv-collab/riscv-gnu-toolchain with:
#   ./configure --prefix=${HOME}/riscv-toolchain \
#               --with-arch=rv64imafdc_zifencei --with-abi=lp64d
#   make -j$(nproc)
export PATH=${HOME}/xpack-riscv-none-elf-gcc-15.2.0-1/bin:${PATH}

echo "Environment setup complete."
