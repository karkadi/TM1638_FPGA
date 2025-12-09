# Copyright (C) 2025  Altera Corporation. All rights reserved.
# Your use of Altera Corporation's design tools, logic functions 
# and other software and tools, and any partner logic 
# functions, and any output files from any of the foregoing 
# (including device programming or simulation files), and any 
# associated documentation or information are expressly subject 
# to the terms and conditions of the Altera Program License 
# Subscription Agreement, the Altera Quartus Prime License Agreement,
# the Altera IP License Agreement, or other applicable license
# agreement, including, without limitation, that your use is for
# the sole purpose of programming logic devices manufactured by
# Altera and sold by Altera or its authorized distributors.  Please
# refer to the Altera Software License Subscription Agreements 
# on the Quartus Prime software download page.

# Quartus Prime Version 25.1std.0 Build 1129 10/21/2025 SC Lite Edition
# File: C:\Quartus\TM1638_LED_KEY_DRV\PinAssigments.tcl
# Generated on: Sun Dec  7 13:47:41 2025

package require ::quartus::project

set_location_assignment PIN_105 -to TM1638_DIO
set_location_assignment PIN_104 -to TM1638_CLK
set_location_assignment PIN_103 -to TM1638_STB
set_location_assignment PIN_88 -to RST_N
set_location_assignment PIN_24 -to CLK_50MHZ
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to TM1638_STB
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to TM1638_DIO
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to TM1638_CLK
