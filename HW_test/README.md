# Testing on VCU118
## Flashing the bitstream
Use the `vivado` folder to run vivado and flash the VCU118. This is simply for better organisation as vivado creates temp files in the current directory.
```
$ cd vivado/
$ source setup-vivado.sh #loads only vivado 2022.2 to avoid crossdependency issues
$ vivado #run vivado
```
## Debugging
Use the `debug` folder to run openocd and debug using GDB.
```
$ cd debug/
$ source scripts/setup-debug-env.sh # loads riscv gdb and openocd modules
```
Start debugging:
```
$ openocd -f vcu118.cfg
$ riscv64-unknown-elf-gdb /path/to/elf.elf -d /path/to/src_files -x GDB-init.cmd

```



