# Program VCU118 (xcvu9p) via Vivado Hardware Manager.
#
# For remote programming, set HW_SERVER to point at the machine physically
# connected to the board:
#
#   Option A - run this script on the remote server directly:
#     vivado -nojournal -mode batch -source scripts/program_vcu118.tcl
#
#   Option B - tunnel hw_server port and run locally:
#     (on remote) hw_server
#     (local)     ssh -L 3121:localhost:3121 user@server
#     (local)     HW_SERVER=localhost:3121 vivado -nojournal -mode batch \
#                   -source scripts/program_vcu118.tcl
#
#   Option C - connect directly to remote hw_server (no tunnel):
#     HW_SERVER=fpga-server.example.com:3121 vivado -nojournal -mode batch \
#       -source scripts/program_vcu118.tcl

set hw_server [expr {[info exists ::env(HW_SERVER)] ? $::env(HW_SERVER) : "localhost:3121"}]
set bitfile   [file normalize "work-fpga/cva6_flexnngine_xilinx.bit"]

puts "INFO: Connecting to hw_server at $hw_server"
puts "INFO: Bitstream: $bitfile"

open_hw_manager
connect_hw_server -url $hw_server -allow_non_jtag

# Open the first available target; the VCU118 presents as xcvu9p_0.
# If multiple boards are on the chain, list targets with: get_hw_targets
open_hw_target

set dev [get_hw_devices xcvu9p_0]
current_hw_device $dev
set_property PROGRAM.FILE $bitfile $dev
program_hw_devices $dev
refresh_hw_device $dev

close_hw_manager
puts "INFO: VCU118 programmed successfully."
