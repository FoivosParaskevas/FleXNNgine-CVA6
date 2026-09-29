# source the enviroment (loads openocd module)
source scripts/setup-debug-env.sh

# Test directories
TEST_DIR=../../tests
INTEGR_DIR=$TEST_DIR/integration
TESTLIST_DIR=$INTEGR_DIR/testlist

#echo "test directory is $TEST_DIR"
#echo "integration test directory is $INTEGR_DIR"

#echo -e "test directory is $INTEGR_DIR/$1 \n\n"
#echo -e "test binary file is $INTEGR_DIR/$1/main.riscv \n\n"

if [ $# -eq 1 ]; then
	echo -e "Running test '$1' \n\n"

	#gnome-terminal -- bash -c "openocd -f vcu118.cfg; exec bash" &
	xterm -e openocd -f vcu118.cfg &

	sleep 2

	riscv64-unknown-elf-gdb $TESTLIST_DIR/$1/main.riscv -d $TESTLIST_DIR/$1/ -x GDB-init.cmd
elif [ $# -gt 1 ]; then
	echo -e "\nToo many arguments! Pass only the test name!\n\n  Example:   ./scripts/run-debug.sh 'your_test_name'"
elif [ $# -lt 1 ]; then
	echo -e "\nNo arguments passed! Pass the test test name!\n\n Example:   ./scripts/run-debug.sh 'your_test_name'"
fi


echo -e "\n\ndebugging finished\n\n"
