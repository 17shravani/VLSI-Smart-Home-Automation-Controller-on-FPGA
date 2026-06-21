# Project Report: Smart Home Automation Controller on FPGA

---

## 1. Project Objective & Overview
This project presents the design, simulation, and implementation of a parameterizable, low-latency, and highly deterministic **Smart Home Automation Controller** on a Field Programmable Gate Array (FPGA). 

In modern building management, microcontrollers (MCUs) are commonly used for networking, while FPGAs are preferred for safety-critical, hard real-time execution. This project demonstrates an industry-standard hybrid approach:
- **FPGA**: Handles real-time sensor processing, debouncing, multi-channel PWM dimming, local presets, scheduler logic, and safety-critical overrides.
- **ESP32 (or Raspberry Pi)**: Acts as an IoT bridge, handling Wi-Fi/Bluetooth, TCP/IP, and MQTT protocols. It communicates with the FPGA via a simple, structured UART protocol.

This architecture ensures that if the wireless network drops or the cloud-based assistant freezes, local safety alarms (e.g., over-current cutoffs or security alerts) and manual wall buttons still execute instantly with zero software latency.

---

## 2. Technical & Business Value
Similar logic is used extensively in:
1. **Commercial Building Management Systems (BMS)**: Controlling HVAC, high-density lighting arrays, and safety alarms.
2. **Industrial Control Systems (PLCs)**: Replaced by FPGAs for ultra-low latency safety interlocks.
3. **Smart Grid / Energy Management**: Dynamically shedding load or dimming lights to save energy based on local occupancy.

### Technical Advantages of FPGA Over MCU:
- **True Parallelism**: Multiple PWM channels, UART transceivers, and sensor debouncers run concurrently in hardware. Adding more light channels doesn't introduce CPU jitter.
- **Hardware Determinism**: Transition from sensor detection to actuator cutoff occurs within a fixed number of system clock cycles, guaranteeing timing margins.
- **Power Efficiency**: Driven by slow clock-enable ticks (`tick_1k` and `tick_10`), saving dynamic switching power.

---

## 3. System Architecture & Pin Mapping

### Subsystem Block Diagram
1. **Clock Generator (`clk_en.v`)**: Divides the master clock (50 MHz) to create a 1 kHz tick (for 8-bit PWM) and a 10 Hz tick (for debouncers/scheduler).
2. **Input Conditioning (`debounce.v`)**: Filters raw switches/buttons using a 2-stage Flip-Flop synchronizer to prevent metastability, and an integrator counter for contact debounce.
3. **PWM Actuators (`pwm8.v`)**: Generates PWM cycles for 4 lights (`L0` to `L3`) and 2 fan speeds (`F0`, `F1`).
4. **Scenes Presets (`scenes.v`)**: ROM storing 8 preconfigured room configurations.
5. **Scheduler (`scheduler.v`)**: Timed FSM triggering scenes at specific simulated time intervals.
6. **UART Transceiver (`uart_rx.v`, `uart_tx.v`)**: Configurable 115200-N-8-1 transceiver.
7. **Protocol Parsing (`proto.v`)**: Parses frames, verifies XOR checksums, and encodes telemetry reports.
8. **FSM Controller (`ctrl_fsm.v`)**: Central priority controller.

### Input/Output Signals
| Signal Name | I/O | Destination / Pin Mapping | Description |
| :--- | :---: | :--- | :--- |
| `clk_50m` | Input | Pin E3 (Nexys A7 100MHz osc) | Master system clock |
| `rst_btn` | Input | Pin N17 (BTNC Push button) | Active-high global reset button |
| `pir_raw` | Input | Pin M13 (SW2 Slide switch) | Motion sensor simulated input |
| `ldr_dark_raw` | Input | Pin R15 (SW3 Slide switch) | Light level threshold simulated input |
| `overcur_raw` | Input | Pin R17 (SW4 Slide switch) | Simulated current overload sensor |
| `door_raw` | Input | Pin T18 (SW5 Slide switch) | Magnetic door sensor |
| `security_mode_raw` | Input | Pin J15 (SW0 Slide switch) | Security mode toggle switch |
| `temp_high_raw` | Input | Pin L16 (SW1 Slide switch) | Temperature threshold switch |
| `btn0_raw`..`btn3_raw` | Input | Pins P18, T16, R10, F15 (Buttons) | Manual push buttons to toggle lights |
| `uart_rx` | Input | Pin C4 (USB-UART RX) | Serial RX input |
| `uart_tx` | Output | Pin D4 (USB-UART TX) | Serial TX output |
| `L0_PWM`..`L3_PWM` | Output | PMOD JA Pins 1, 2, 3, 4 | PWM channels for dimming lights |
| `F0_PWM`..`F1_PWM` | Output | PMOD JA Pins 7, 8 | PWM channels for fan speed control |
| `R0`..`R3` | Output | PMOD JA Pins 9, 10 & LEDs LD0..3 | Relay socket outputs (On/Off) |
| `ALARM_LED` | Output | Pin R18 (LED LD4) | Warning LED for active alarms |
| `ENERGY_LED` | Output | Pin V17 (LED LD5) | Indicator LED for Energy Saving mode |
| `fsm_state[1:0]` | Output | Pin V12, V11 (LED LD15, LD14) | Represents FSM state (00=IDLE, 01=MAN, 10=AUTO, 11=ALARM) |

---

## 4. Priority FSM State Definitions
The controller contains a Moore FSM with the following priority hierarchy:
1. **ALARM (`S_ALARM` = 2'b11)**: Triggered if `overcur == 1` or `door == 1` while `security_mode == 1`.
   - *Safety Outputs*: Lights go to 100% duty, fans turn OFF (prevent fire propagation), and relays drop to `4'b0000`.
2. **MANUAL (`S_MANUAL` = 2'b01)**: Triggered by push-buttons or remote UART commands.
   - *Inactivity Timeout*: Reverts back to AUTO or IDLE if no user inputs or motion are detected for 15 seconds.
3. **SENSOR AUTO (`S_AUTO` = 2'b10)**: Triggered by occupancy (`pir == 1` and `dark == 1`).
   - *Eco Timeout*: If no motion is detected for 10 seconds, it enters Energy-Saving mode (dims lights to 6% duty, slows fans, shuts off relays). After 20 seconds, it shuts off all outputs and reverts to S_IDLE.
4. **SCHEDULE / IDLE (`S_IDLE` = 2'b00)**: Loads scene presets triggered by the scheduler time (07:00 Work, 18:00 Evening, 23:00 Night, 00:00 All Off).

---

## 5. UART Communication Protocol

### Packet Formatting
- **Host to FPGA**: `0xAA <cmd> <len> <payload...> <xor>`
- **FPGA to Host**: `0x55 <evt> <len> <payload...> <xor>`
- **Checksum**: XOR of command/event, length, and all payload bytes.

### Packet Types
- `0x01` (SET_DUTY): Sets duty cycle (0-255) for ch (0=L0, 1=L1, 2=L2, 3=L3, 4=F0, 5=F1).
- `0x02` (SET_RELAY): Sets relay mask (4-bits).
- `0x03` (LOAD_SCENE): Loads preset scene index (0-7).
- `0x04` (SET_NIGHT_MODE): Toggles night mode (L0..3 capped at 50 duty).
- `0x81` (EVT_STATUS): Transmitted every 1 second containing `[L0, L1, L2, L3, F0, F1, relays, flags]`.
- `0x82` (EVT_SENSOR): Transmitted immediately on sensor transitions containing `[pir, dark, overcur, door]`.

---

## 6. Simulation & Verification Plan

### Testbench Operations (`tb/home_tb.v`):
1. **Initial Reset**: Verifies that all outputs are cleared and FSM begins in `S_IDLE`.
2. **Manual push button**: Pulses `btn0_raw` high. Verifies transition to `S_MANUAL`.
3. **Manual Timeout**: Waits 16 seconds (simulated) and asserts FSM returned to `S_IDLE` due to user inactivity.
4. **Sensor Auto Activation**: Asserts `pir_raw = 1` and `ldr_dark_raw = 1`. Confirms transition to `S_AUTO`.
5. **Eco Mode Dimming**: Drops `pir_raw` to 0. Waits 12 seconds. Asserts `ENERGY_LED = 1` and lighting duties are reduced to Eco level.
6. **Safety Override**: Asserts `overcur_raw = 1`. Verifies that FSM goes to `S_ALARM` within a clock cycle, relays trip, and lights go to 100%.
7. **UART Parsing**: Sends serial byte stream at 115200 baud to change Light 0 duty. Verifies FSM handles the packet and changes state.

---

## 7. FPGA Synthesis & Implementation Workflow

### Step 1: Create Vivado Project
- Target Part: **XC7A100T-1CSG324C** (Nexys A7 board).
- Add all `.v` files in the `/rtl` directory.
- Add `/tb/home_tb.v` as a simulation source.
- Add `/constraints/nexys_a7.xdc` as constraints.

### Step 2: Synthesis & Constraints Check
- Run synthesis. Check the Utilization Report.
- Ensure no warnings are generated regarding **unintentional latches** (which can occur if `always @(*)` blocks lack complete `default` cases).

### Step 3: Run Implementation & Place & Route
- Verify timing constraints. The timing report should show positive Slack on the Setup and Hold paths (timing closed).

### Step 4: Bitstream Generation
- Generate `top.bit`.
- Connect the Nexys A7 board via USB-JTAG.
- Open Hardware Manager and program the device.

---

## 8. Conclusion
This course project demonstrates a complete digital IC design flow: translating requirements into modular Verilog RTL, modeling complex real-time behavior via FSMs, integrating synchronization and debouncing to handle real-world hardware hazards, and verifying using self-checking testbenches and synthesis rules. The resulting code serves as a solid proof of work for portfolio uploads.
