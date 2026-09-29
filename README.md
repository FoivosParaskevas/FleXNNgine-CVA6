# FleXNNgine-CVA6 SoC

A single-core CVA6 RISC-V SoC with the FleXNNgine CNN accelerator, targeting
the Xilinx VCU118 FPGA. The accelerator is attached as a plain AXI4 peripheral;
the host runs Linux from DDR4 and drives the accelerator through a UIO
userspace driver.

## Quick start

### 1. Clone

```bash
git clone https://gitlab.itiv.kit.edu/cecas/flexnngine-cva6.git
cd flexnngine-cva6
git submodule update --init --recursive
```

If the FleXNNgine submodule fails to resolve automatically:
```bash
cd modules
git clone https://gitlab.itiv.kit.edu/cecas/flexnngine.git
cd ..
```

If `axi_mem_if` is missing:
```bash
cd modules/cva6/corev_apu
git clone https://github.com/pulp-platform/axi_mem_if.git
cd ../../..
```

### 2. RISC-V toolchain

Build the toolchain from the `cva6-sdk` submodule (30–60 min):

```bash
cd cva6-sdk
make toolchain64   # or `make gcc` if toolchain64 fails
cd ..
```

### 3. FPGA build

Set environment in every new shell:

```bash
source /tools/xilinx/Vivado/2024.2/settings64.sh
export RISCV=$PWD/cva6-sdk/install64
export PATH=$RISCV/bin:$PATH
```

Then:

```bash
make fpga
```

Runtime: ~1–2 h. Output bitstream lands at
`fpga/work-fpga/cva6_flexnngine_xilinx.bit`.

## Target configuration

- **FPGA board:** Xilinx VCU118 (Virtex UltraScale+, XCVU9P)
- **CVA6 config:** `cv64a6_imafdc_sv39_wb` — 64-bit, single hart, write-back
  L1 data cache, SV39 MMU
- **Top-level module:** [`rtl/src/cva6_flexnngine_xilinx.sv`](rtl/src/cva6_flexnngine_xilinx.sv)
- **Memory map:** FleXNNgine control registers at `0x4070_0000` (4 KiB),
  FleXNNgine scratchpad at `0x4080_0000` (128 KB)

Useful references:

- [CVA6 documentation](https://github.com/openhwgroup/cva6)
- [FleXNNgine accelerator](https://gitlab.itiv.kit.edu/cecas/flexnngine)

## Software

### SD image generation

Satisfy the dependencies listed in the
[`cva6-sdk`](https://github.com/openhwgroup/cva6-sdk) README, then from
that directory:

```bash
make sdk
```

Follow the `cva6-sdk` instructions to copy the generated image to an SD card.

### Running the accelerator from Linux

After booting the board, the accelerator is available via UIO. See
[`doc/linux-pivot.md`](doc/linux-pivot.md) for the Linux-side driver, test
suite, and benchmark harness.

## Simulation

### Sanity check

```bash
make sanity-tests
```

### Full regression

```bash
make test
```

### Running a single integration test

From `tests/integration`:

```bash
make -C testlist/<test_name> all
```

Append `GUI=1` to open Questa in GUI mode:

```bash
make GUI=1 -C testlist/<test_name> all
```

### Writing a new integration test

An integration test lives in `tests/integration/testlist/<test_name>/` and
contains:

| File              | Description |
|-------------------|-------------|
| `<test_name>.c/h` | The test itself — see neighbouring tests for examples. |
| `main.c`          | Co-ordinates execution and calls `<test_name>()`. |
| `Makefile`        | Symlink to `../../test_automation/Makefile`. |
| `sim.tcl`         | Symlink to `../../test_automation/sim.tcl`. |

The test function should be self-checking: call `exit(arg)` with `arg > 0`
on failure, or `return 0` on success.

## Licence

Solderpad v0.51 (SHL-0.51). See [LICENSE](LICENSE).
