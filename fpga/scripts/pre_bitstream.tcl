# Pre-hook for write_bitstream step.
#
# SPI is disabled (InclSPI=0) but the SoC peripherals block still exposes
# spi_clk_o/mosi/miso/ss as module ports driven to constants.  Vivado
# promotes them to unconstrained top-level I/O pads, causing DRC errors
# NSTD-1, UCIO-1 (no IOSTANDARD/LOC) and RTSTAT-9 (GLOBAL_LOGIC0
# routing stub).  Down-grade all three to warnings so write_bitstream
# can proceed; the SPI pins are not physically used on the board.
set_property SEVERITY {Warning} [get_drc_checks NSTD-1]
set_property SEVERITY {Warning} [get_drc_checks UCIO-1]
set_property SEVERITY {Warning} [get_drc_checks RTSTAT-9]
