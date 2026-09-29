echo "Setup for $(lsb_release -is)$(lsb_release -rs)"
MODULE_PATH=/nas/sec/tools/modulefiles/cva6_toolchain/$(lsb_release -is)$(lsb_release -rs)
MODULE_PATH_EI=/nas/ei/share/sec/tools/modulefiles/cva6_toolchain/$(lsb_release -is)$(lsb_release -rs)
TOOLS_PATH=/nas/ei/share/sec/tools/cva6_toolchain/$(lsb_release -is)$(lsb_release -rs)

module use ${MODULE_PATH}
module use ${MODULE_PATH_EI}

module load riscv-gnu-tools
module load riscv-openocd
