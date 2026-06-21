## file: constraints/nexys_a7.xdc
## Vivado Physical Constraints File for Nexys A7 (Artix-7 XC7A100T-1CSG324C)
## Smart Home Automation Controller on FPGA

# Master Clock Input (100 MHz clock on Board - divided to 50 MHz or mapped directly)
# In top.v, we call it clk_50m. We can drive it with the onboard 100 MHz oscillator
# and define its timing constraint accordingly.
set_property -dict { PACKAGE_PIN E3    IOSTANDARD LVCMOS33 } [get_ports { clk_50m }];
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports { clk_50m }];

# Reset Button (CPU Reset on Nexys A7 is Active Low, we map to user button BTNC which is Active High)
set_property -dict { PACKAGE_PIN N17   IOSTANDARD LVCMOS33 } [get_ports { rst_btn }]; # BTNC

# Sensor & Switch Inputs (Mapped to Slide Switches for manual board verification)
set_property -dict { PACKAGE_PIN J15   IOSTANDARD LVCMOS33 } [get_ports { security_mode_raw }]; # SW0
set_property -dict { PACKAGE_PIN L16   IOSTANDARD LVCMOS33 } [get_ports { temp_high_raw }];     # SW1
set_property -dict { PACKAGE_PIN M13   IOSTANDARD LVCMOS33 } [get_ports { pir_raw }];           # SW2 (Simulates PIR motion)
set_property -dict { PACKAGE_PIN R15   IOSTANDARD LVCMOS33 } [get_ports { ldr_dark_raw }];      # SW3 (Simulates LDR light sensor)
set_property -dict { PACKAGE_PIN R17   IOSTANDARD LVCMOS33 } [get_ports { overcur_raw }];       # SW4 (Simulates current fault)
set_property -dict { PACKAGE_PIN T18   IOSTANDARD LVCMOS33 } [get_ports { door_raw }];          # SW5 (Simulates door sensor)

# Push-buttons for manual control (raw)
set_property -dict { PACKAGE_PIN P18   IOSTANDARD LVCMOS33 } [get_ports { btn0_raw }]; # BTND (Toggle Light 0)
set_property -dict { PACKAGE_PIN T16   IOSTANDARD LVCMOS33 } [get_ports { btn1_raw }]; # BTNL (Toggle Light 1)
set_property -dict { PACKAGE_PIN R10   IOSTANDARD LVCMOS33 } [get_ports { btn2_raw }]; # BTNR (Toggle Light 2)
set_property -dict { PACKAGE_PIN F15   IOSTANDARD LVCMOS33 } [get_ports { btn3_raw }]; # BTNU (Toggle Light 3)

# USB-UART Interface (To bridge with ESP32 or PC Serial Terminal)
set_property -dict { PACKAGE_PIN C4    IOSTANDARD LVCMOS33 } [get_ports { uart_rx }]; # RXD
set_property -dict { PACKAGE_PIN D4    IOSTANDARD LVCMOS33 } [get_ports { uart_tx }]; # TXD

# Actuator PWM outputs (Mapped to PMOD Header JA for external hardware interfacing)
set_property -dict { PACKAGE_PIN C17   IOSTANDARD LVCMOS33 } [get_ports { L0_PWM }]; # PMOD JA Pin 1
set_property -dict { PACKAGE_PIN D18   IOSTANDARD LVCMOS33 } [get_ports { L1_PWM }]; # PMOD JA Pin 2
set_property -dict { PACKAGE_PIN E18   IOSTANDARD LVCMOS33 } [get_ports { L2_PWM }]; # PMOD JA Pin 3
set_property -dict { PACKAGE_PIN G17   IOSTANDARD LVCMOS33 } [get_ports { L3_PWM }]; # PMOD JA Pin 4
set_property -dict { PACKAGE_PIN D17   IOSTANDARD LVCMOS33 } [get_ports { F0_PWM }]; # PMOD JA Pin 7
set_property -dict { PACKAGE_PIN E17   IOSTANDARD LVCMOS33 } [get_ports { F1_PWM }]; # PMOD JA Pin 8

# Relay outputs (Mapped to Board LEDs LD0..LD3 and PMOD JA Pin 9, 10 for relay triggers)
set_property -dict { PACKAGE_PIN H17   IOSTANDARD LVCMOS33 } [get_ports { R0 }]; # LED LD0 / PMOD JA Pin 9
set_property -dict { PACKAGE_PIN K15   IOSTANDARD LVCMOS33 } [get_ports { R1 }]; # LED LD1 / PMOD JA Pin 10
set_property -dict { PACKAGE_PIN J13   IOSTANDARD LVCMOS33 } [get_ports { R2 }]; # LED LD2
set_property -dict { PACKAGE_PIN N14   IOSTANDARD LVCMOS33 } [get_ports { R3 }]; # LED LD3

# Alert & Status LEDs
set_property -dict { PACKAGE_PIN R18   IOSTANDARD LVCMOS33 } [get_ports { ALARM_LED  }]; # LED LD4
set_property -dict { PACKAGE_PIN V17   IOSTANDARD LVCMOS33 } [get_ports { ENERGY_LED }]; # LED LD5

# Current FSM State LEDs
set_property -dict { PACKAGE_PIN V11   IOSTANDARD LVCMOS33 } [get_ports { fsm_state[0] }]; # LED LD14
set_property -dict { PACKAGE_PIN V12   IOSTANDARD LVCMOS33 } [get_ports { fsm_state[1] }]; # LED LD15

# Configuration constraints for bitstream generation
set_property CFGBVS VCCO [current_design]
set_property CONFIG_MODE SPIx4 [current_design]
