## uart_top_constraints.xdc
## Board: Digilent Nexys A7-100T, XC7A100T-1CSG324C
## Matches uart_top.v ports:
##   CLK100MHZ, CPU_RESETN, UART_RXD_OUT, UART_TXD_IN, led[15:0]

## Clock
set_property -dict { PACKAGE_PIN E3 IOSTANDARD LVCMOS33 } [get_ports {CLK100MHZ}]
create_clock -name clk100_in -period 10.000 -waveform {0 5} [get_ports {CLK100MHZ}]

## Configuration bank voltage
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

## CPU Reset Button
set_property -dict { PACKAGE_PIN C12 IOSTANDARD LVCMOS33 } [get_ports {CPU_RESETN}]

## USB-RS232 Interface
## FPGA RX from host / USB-UART TX
set_property -dict { PACKAGE_PIN C4 IOSTANDARD LVCMOS33 } [get_ports {UART_RXD_OUT}]
## FPGA TX to host / USB-UART RX
set_property -dict { PACKAGE_PIN D4 IOSTANDARD LVCMOS33 } [get_ports {UART_TXD_IN}]

## External async / board-observable paths
set_false_path -from [get_ports {CPU_RESETN}]
set_false_path -from [get_ports {UART_RXD_OUT}]
set_false_path -to   [get_ports {UART_TXD_IN}]
set_false_path -to   [get_ports {led[*]}]

## User LEDs LD0-LD15
set_property -dict { PACKAGE_PIN H17 IOSTANDARD LVCMOS33 } [get_ports {led[0]}]
set_property -dict { PACKAGE_PIN K15 IOSTANDARD LVCMOS33 } [get_ports {led[1]}]
set_property -dict { PACKAGE_PIN J13 IOSTANDARD LVCMOS33 } [get_ports {led[2]}]
set_property -dict { PACKAGE_PIN N14 IOSTANDARD LVCMOS33 } [get_ports {led[3]}]
set_property -dict { PACKAGE_PIN R18 IOSTANDARD LVCMOS33 } [get_ports {led[4]}]
set_property -dict { PACKAGE_PIN V17 IOSTANDARD LVCMOS33 } [get_ports {led[5]}]
set_property -dict { PACKAGE_PIN U17 IOSTANDARD LVCMOS33 } [get_ports {led[6]}]
set_property -dict { PACKAGE_PIN U16 IOSTANDARD LVCMOS33 } [get_ports {led[7]}]
set_property -dict { PACKAGE_PIN V16 IOSTANDARD LVCMOS33 } [get_ports {led[8]}]
set_property -dict { PACKAGE_PIN T15 IOSTANDARD LVCMOS33 } [get_ports {led[9]}]
set_property -dict { PACKAGE_PIN U14 IOSTANDARD LVCMOS33 } [get_ports {led[10]}]
set_property -dict { PACKAGE_PIN T16 IOSTANDARD LVCMOS33 } [get_ports {led[11]}]
set_property -dict { PACKAGE_PIN V15 IOSTANDARD LVCMOS33 } [get_ports {led[12]}]
set_property -dict { PACKAGE_PIN V14 IOSTANDARD LVCMOS33 } [get_ports {led[13]}]
set_property -dict { PACKAGE_PIN V12 IOSTANDARD LVCMOS33 } [get_ports {led[14]}]
set_property -dict { PACKAGE_PIN V11 IOSTANDARD LVCMOS33 } [get_ports {led[15]}]
