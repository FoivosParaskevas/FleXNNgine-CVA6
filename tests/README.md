# Integration testsuite

## Introduction

This directory holds the integration tests for the single-core CVA6 + FleXNNgine
SoC. Tests exercise the full simulation top (`cva6_flexnngine_tb`) with a C
payload that runs on the RISC-V core and optionally drives the accelerator.

The FleXNNgine Linux-userspace driver and its own test suite live in the
`tests/integration/testlist/flexnngine-driver` submodule and are covered in
[`doc/linux-pivot.md`](../doc/linux-pivot.md).

## Preconditions

- RISC-V toolchain (built via `cva6-sdk` — see repository root README)
- RTL simulator (Questa or Verilator)

## Commands

Top-level targets:

- `make all`      — run every test in the integration regression list
- `make integr`   — same as `make all`
- `make integr TEST=<testname>` — run a specific testcase
- `make sanity`   — compile + run `hello_world` as a smoke test
- `make regr`     — clean + full regression
- `make clean`    — remove build artefacts

Per-regression targets (inside `integration/`):

- `make all`      — run all tests
- `make all TEST=<testname>` — run a specific testcase
- `make rerun`    — re-run failed/unexecuted tests
- `make rtl`      — compile the RTL only
- `make sw`       — compile the C source for every test

## Adding a testcase

Each test is a subdirectory of `integration/testlist/<testname>/` containing:

| File              | Description |
|-------------------|-------------|
| `<testname>.c/h`  | Test function(s) — self-checking. |
| `main.c`          | Drives the test function(s) and returns the exit code. |
| `Makefile`        | Symlink to `../../test_automation/Makefile`. |
| `sim.tcl`         | Symlink to `../../test_automation/sim.tcl` (or custom). |

`main()` must return `0` on success and a non-zero code on failure. The return
value is translated into a write to the `to_host` location (see `syscalls.c`
and the linker script); the testbench monitors that write, ends the simulation,
and produces the result report.
