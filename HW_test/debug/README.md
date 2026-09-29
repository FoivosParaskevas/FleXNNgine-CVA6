# Debugging VCU118 using FMC-Jtag
Use the following instructions to start debugging the VCU118!

## Quick start
Use the provided `run-debug.sh` script to start debugging any chosen test from the `/tests/integration/testlist/` directory:

*To avoid any __crossdependecy__ issues, do not source the `cecas_fpga` enviroment beforehand!*

```
./scripts/run-debug.sh name_of_test
```

*Ensure the script is executable using `chmod +x run-debug.sh`.*

## How to start debugging
If you wish to debug without using the script, read the following.

### Setup
Source the provided setup script to load the reqired modules:
```
$ source scripts/setup-debug-env.sh
```
*To avoid any __crossdependecy__ issues, do not source the `cecas_fpga` enviroment beforehand*
### Debugging
First, start the OpenOCD connection using the provided `vcu118.cfg` config file:
```
$ openocd -f vcu118.cfg
```
Next, <ins>open a new terminal</ins> and run gdb while also providing the .elf (.ricv) you wish to run. Use the `-d` flag to provide the directory containing the source files and the `-x` flag to run the initial gdb commands contained within `GDB-init.cmd`:
```
$ riscv64-unknown-elf-gdb /path/to/elf.elf -d /path/to/src_files -x GDB-init.cmd
```
If you do not wish to use`-x GDB-init.cmd`, connect to the target and load the program using the following commands:
```
$(gdb) target extended-remote localhost:3333
$(gdb) load   # loads the program
```


