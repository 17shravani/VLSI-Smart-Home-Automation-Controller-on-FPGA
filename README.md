# Smart Home Automation Controller on FPGA

[![Verilog](https://img.shields.io/badge/Language-Verilog-brightgreen.svg)](https://en.wikipedia.org/wiki/Verilog)
[![FPGA](https://img.shields.io/badge/Platform-Xilinx%20Vivado-orange.svg)](https://www.xilinx.com/products/design-tools/vivado.html)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

An industry-oriented VLSI course project designing and verifying a parameterizable, real-time, deterministic Smart Home Automation Controller on FPGA. It features multi-channel PWM dimmers, preset scene management, scheduling timers, and a safety-critical priority state machine, bridged with an ESP32 IoT gateway via a custom UART frame protocol.

---

## 1. Project Explanation & Motivation

### What is a Smart Home Automation Controller?
A Smart Home Automation Controller is the central processing unit of a smart building. It aggregates inputs from environment sensors (temperature, motion, light levels, security sensors) and local user controls (wall switches, remote apps), then executes control algorithms to drive high-power relays, light dimmers, fans, and safety indicators.

### Problem Solved
Traditional IoT devices rely exclusively on microcontrollers (MCUs) connected to a local router and cloud servers. If the Wi-Fi router disconnects, the cloud is slow, or the MCU's software thread freezes while compiling network packets, critical safety interlocks (like cutting power on a current overload or triggering a burglary siren) will fail. 

This project solves this vulnerability by offloading all real-time sensing, debouncing, and safety-critical overrides to a dedicated FPGA. The FPGA runs parallel, deterministic hardware circuits with zero processor latency, ensuring safety operations occur within micro-seconds, while utilizing an external ESP32 only as a communication bridge.

---

## 2. Digital Design Concepts Used

| Digital Concept | Application in This Project | Educational / Industry Purpose |
| :--- | :--- | :--- |
| **Synchronizers** | Double Flip-Flop chains at the front of every asynchronous input (`debounce.v`). | Prevents metastability caused by setup/hold timing violations. |
| **Clock Enable Ticks** | Single master clock domain generating `1 kHz` and `10 Hz` pulses (`clk_en.v`). | Avoids Clock Domain Crossing (CDC) hazards and cuts dynamic power consumption. |
| **Debouncing Filters** | Time-integrator counters that filter electrical contact chatter (`debounce.v`). | Rejects noise and contact bounce from real physical switches. |
| **PWM Generators** | 8-bit counters compared with configured duty cycle levels (`pwm8.v`). | Delivers smooth analog voltage level emulation for lights and fan speeds. |
| **Finite State Machine** | 4-state priority-encoded Finite State Machine (`ctrl_fsm.v`). | Guarantees deterministic transitions and resolves actuator conflicts. |
| **Look-Up Table / ROM** | Multi-channel pre-configured scenes stored in combinational ROM arrays (`scenes.v`). | Recalls complex multi-actuator presets in a single clock cycle. |
| **Bit Timing / Oversampling** | 16x oversampling clock synchronizer on the RX UART stream (`uart_rx.v`). | Aligns serial RX line samples to bit centers, correcting phase drift. |

---

## 3. System Architecture & Block Diagram

```
                                      +---------------------------------------------+
                                      |                   TOP.V                     |
                                      |                                             |
   clk_50m +------------------------->+  +---------------+                          |
   rst_btn +------------------------->+  |  clk_en       |-- tick_1k (PWM) --------+|
                                      |  |  (1k/10Hz)    |-- tick_10 (Debounce/FSM)-++
                                      |  +---------------+                          |
                                      |                                             |
   pir_raw, ldr_raw, door_raw,        |  +---------------+                          |
   overcur_raw, manual_btns           |  |  debounce     |-- synchronized &         |
   +--------------------------------->+  |  (x8 channels)|   debounced signals -----+
                                      |  +---------------+                          |
                                      |                                             |
                                      |  +---------------+                          |
   uart_rx +------------------------->+  |  uart_rx/tx   |-- parsed bytes/          |
   uart_tx <-------------------------+  |  & proto      |   cmd/strobe ------------+
                                      |  +---------------+                          |
                                      |                                             |
                                      |  +---------------+                          |
                                      |  |  scenes (ROM) |<- scene_idx              |
                                      |  |               |-- preset duties/relays --+
                                      |  +---------------+                          |
                                      |                                             |
                                      |  +---------------+                          |
                                      |  |  scheduler    |-- sched_scene_idx -------+
                                      |  +---------------+                          |
                                      |                                             |
                                      |  +---------------+                          |
                                      |  |  ctrl_fsm     |<- FSM state logic        |
                                      |  |               |-- control outputs -------+
                                      |  +---------------+                          |
                                      |                                             |
                                      |  +---------------+                          |
                                      |  |  pwm8 (x6)    |<- duties                 |
                                      |  |               |-- L0..L3, F0..F1 PWM ----+----> L0..L3, F0..F1 PWM
                                      |  +---------------+                          |
                                      |                                             |
                                      |                                             |----> R0..R3 Relays
                                      |                                             |----> ALARM_LED, ENERGY_LED
                                      +---------------------------------------------+
```

---

## 4. Control Logic & Priority State Machine

### Priority Hierarchy
The central FSM (`ctrl_fsm.v`) implements a priority encoder resolving input conflicts:
1. **ALARM (`S_ALARM` = 2'b11)**: Activates on over-current fault or security door breach. Lights go to 100% duty, fans go off, and relays trip immediately.
2. **MANUAL (`S_MANUAL` = 2'b01)**: Triggered by user button toggles or remote UART packets. Features a 15-second inactivity timeout back to auto.
3. **SENSOR AUTO (`S_AUTO` = 2'b10)**: Triggered by PIR motion and low light. Turns on lights, sets fans based on temperature, and dims to Eco mode if motion stops for 10s.
4. **SCHEDULE / IDLE (`S_IDLE` = 2'b00)**: Default state driving presets according to scheduler time triggers.

### FSM State Encoder Table
| State Name | State Value | Condition for Entry | Outputs |
| :--- | :---: | :--- | :--- |
| **`S_IDLE`** | `2'b00` | Default state, or exit from Auto/Manual/Alarm. | Follows scheduler scene presets. |
| **`S_MANUAL`** | `2'b01` | Physical button press OR UART override command. | Follows manual registers. Cap applied if Night Mode is active. |
| **`S_AUTO`** | `2'b10` | Motion detected (`pir == 1`) AND Room is dark (`dark == 1`). | Lights and fans automatic. Eco dimming on 10s idle. |
| **`S_ALARM`** | `2'b11` | Over-current (`overcur == 1`) OR Armed intrusion (`security && door`). | Lights 100% on, Fans OFF, Relays OFF, `ALARM_LED = 1`. |

---

## 5. Folder Structure

```
Smart-Home-Automation-FPGA/
│
├── rtl/               # Register Transfer Level synthesizable code
│   ├── clk_en.v       # Divides system clock into slow execution ticks
│   ├── debounce.v     # Filters noisy physical buttons and sensors
│   ├── pwm8.v         # High-resolution 8-bit PWM driver modules
│   ├── scenes.v       # Look-up table containing preset configurations
│   ├── scheduler.v    # Minute-timer triggering scheduled scene changes
│   ├── uart_rx.v      # Asynchronous oversampling serial receiver
│   ├── uart_tx.v      # Serial transmitter driver
│   ├── proto.v        # Binary command frame parser and reporter
│   ├── ctrl_fsm.v     # Master priority control state machine
│   └── top.v          # Top-level wrapper mapping modules to ports
│
├── tb/                # Testbench simulation suite
│   └── home_tb.v      # Self-checking testbench
│
├── constraints/       # FPGA Physical constraints
│   └── nexys_a7.xdc   # Physical pin constraints for Xilinx Artix-7
│
├── scripts/           # Compilation and synthesis scripts
│   └── synth.ys       # Open-source Yosys synthesis script
│
├── reports/           # Synthesis and utilization reports
│   └── home_synth.json# Synthesized circuit JSON format
│
├── doc/               # Academic report documentation
│   └── project_report.md
│
└── README.md          # Project landing documentation
```

---

## 6. How to Simulate & Verify

### Option A: EDA Playground (Browser-Based, No Install)
If you don't have Xilinx Vivado or ModelSim installed, you can simulate this project in a web browser:
1. Open [EDA Playground](https://www.edaplayground.com).
2. Copy and paste all the files from `/rtl` and the testbench from `/tb` into the workspace.
3. Select **Icarus Verilog** (or ALDEC Active-HDL) under the "Tools & Simulators" tab.
4. Check the box **"Open EPWave after run"** to display the waveform.
5. Click **Run** in the left sidebar to execute and view the serial logs.

### Option B: Xilinx Vivado Simulation
1. Create a new project in Vivado and target your board (e.g. Nexys A7).
2. Add all files in `rtl/` as **Design Sources**.
3. Add `tb/home_tb.v` as a **Simulation Source**.
4. In the flow navigator, click **Run Simulation** -> **Run Behavioral Simulation**.
5. Add signals like `fsm_state`, `L0_PWM`, `relays`, `alarm_active`, and `uart_rx` to the Waveform view.
6. Run for at least `30` seconds (simulated time) to observe manual mode timeouts, Eco mode dimming, and UART command reactions.

### Waveform Analysis
The testbench outputs trace messages to the transcript. Observe the following in the wave window:
- **Button Pulse Trigger**: When `btn0_raw` is held high and released, `fsm_state` shifts from `00` (IDLE) to `01` (MANUAL).
- **Manual Timeout**: At 16.3s, FSM drops from `01` (MANUAL) to `00` (IDLE) because no motion or buttons were pressed.
- **Eco Mode Transition**: When `pir_raw` goes low in Auto mode, `ENERGY_LED` asserts high and the duty cycle on `L0_PWM` drops from high pulse width to micro-pulses (Eco duty 15/255).
- **Alarm Lockout**: When `overcur_raw` rises, FSM immediately enters state `11` (ALARM) within a single clock cycle, tripping relays.

---

## 7. FPGA Hardware Implementation (Xilinx Vivado)

### 1. Synthesize & Implement
- Open Vivado and click **Run Synthesis**. Check the report for latch warnings.
- Add the `constraints/nexys_a7.xdc` file.
- Click **Run Implementation**.
- Open the **Timing Summary Report** and verify that worst negative slack (WNS) is positive (Timing Met).

### 2. Generate Bitstream & Program
- Click **Generate Bitstream** to produce `top.bit`.
- Connect your FPGA board via USB-JTAG.
- Open **Hardware Manager**, click **Open Target**, select your device, and click **Program Device**.

### 3. Board Verification Checklist
- **SW0 (Security Mode)**: Arm/disarm security logic.
- **SW2 (Simulated PIR Motion)**: Turn on switch to trigger Auto occupancy.
- **SW3 (Simulated LDR darkness)**: Flip on switch to trigger night lighting in Auto.
- **BTND (Toggle L0)**: Press button to manually toggle Light 0 PWM (dimmer LED output).
- **LED LD0..LD3**: Relays R0..R3 states.
- **LED LD4 (Alarm indicator)**: Red alert light.
- **LED LD5 (Eco indicator)**: Green eco status.

---

## 8. Interview Preparation Q&A

### 1. Explain your project.
> **Answer**: In this project, I designed a synthesizable Smart Home Automation Controller on FPGA in Verilog. It processes inputs from environment sensors (PIR, LDR, Temp, Door) and manual wall buttons to drive PWM lights, PWM fans, relays, and alarms. It incorporates a priority-based Moore FSM that handles safety-critical events (like overcurrent protection and intrusion alarms) at the highest priority, local manual button presses next, and automatic sensor or scheduled configurations at lower priority. The system includes a parameterized clock-enable structure, input debouncers, and a UART protocol bridge that sends and receives structured telemetry packets to interface with an external ESP32 gateway.

### 2. Why did you use clock-enable ticks (`tick_1k`, `tick_10`) instead of dividing the clock output using a registers counter to drive submodules?
> **Answer**: Driving submodules with divided clock signals creates separate clock domains, leading to Clock Domain Crossing (CDC) hazards, clock skew, and increased routing complexity. By keeping the entire design on a single master clock domain (`clk_50m`) and using single-cycle clock-enable triggers (`tick_1k` and `tick_10`) inside `always @(posedge clk)` blocks, we maintain a synchronous design that is easy for Vivado to route, close timing on, and synthesize efficiently.

### 3. What is metastability, and how did you resolve it in your design?
> **Answer**: Metastability occurs when an asynchronous input signal transitions too close to the active edge of the system clock, violating setup or hold times of the input flip-flop. This causes the flip-flop output to hover between logic 0 and 1 before settling. To resolve this, I implemented 2-stage Flip-Flop synchronizers at the input of the debouncer module. This gives the signal an extra clock cycle to resolve to a stable state before it is sampled by the debouncer counter.

### 4. How does your debouncer work?
> **Answer**: The debouncer synchronizes the input using two flip-flops. It then compares the synchronized signal with the current stable level output. If the input differs from the stable level, it increments a counter. If the input remains in this new state continuously for a predefined number of ticks (driven by the slow `10 Hz` tick enable), the stable output is updated. If the input reverts before the counter finishes, the counter resets. This filters out high-frequency switch bounce and noise.

### 5. Explain the priority mechanism in your FSM.
> **Answer**: The FSM uses a priority-encoded next-state decoder. Safety faults (overcurrent) and armed security breaches (door open while armed) are at the highest priority level and immediately override all states to enter `S_ALARM`. Physical manual button overrides or remote UART commands have the next priority, putting the system into `S_MANUAL` and bypassing automation. Below this is `S_AUTO` (occupancy-based sensor logic), and the lowest priority is `S_IDLE` (standard time-of-day scheduler presets).

### 6. What is the role of the UART protocol parser (`proto.v`)?
> **Answer**: The protocol parser decodes incoming serial bytes into commands using a start-of-frame byte (`0xAA`), command ID, payload length, payload array, and an XOR checksum byte. It verifies the checksum to filter out noise on the serial line. It also acts as an encoder: when a sensor state transitions or a periodic 1-second timer tick is asserted, it builds an event packet with a header (`0x55`), event ID, sensor/telemetry payload, and XOR checksum, transmitting it to the host via the UART transmitter.

### 7. How did you verify the FSM inactivity timeouts in simulation?
> **Answer**: Real-world timeouts of 15 seconds would require millions of clock cycles in simulation, resulting in massive VCD files and slow runs. To optimize simulation, I parameterized the scheduler and FSM parameters. By reducing the ticks-per-minute parameter and scaling the simulated seconds, the FSM inactivity timers trigger after fewer clock cycles in simulation. This allowed me to verify the 15-second manual timeout and the 10-second Eco mode timeout in less than 20 seconds of real simulation run time.

### 8. What would happen if a case statement in your FSM or scenes module was not fully specified?
> **Answer**: If a case statement is not fully specified and lacks a `default` case, or if a register is not assigned a value under all branches, synthesis tools will infer a latch. Latches are highly discouraged in synchronous FPGA designs because they are sensitive to glitches on control paths, complicate timing analysis, and can lead to unpredictable behavior. I ensured all case statements have default assignments and all outputs are driven under every branch.

### 9. How does the PWM module control light brightness?
> **Answer**: The PWM module runs an 8-bit counter that increments on each 1 kHz clock-enable tick, counting from 0 to 255. The duty cycle input (0 to 255) is compared against this counter. If the counter is less than the duty cycle, the output is set high; otherwise, it is low. By varying the duty cycle, we change the ratio of ON time to OFF time, adjusting the average voltage delivered to the load.

### 10. How can this project be extended for a commercial product?
> **Answer**: We can extend this design by:
> 1. Interfacing a real analog-to-digital converter (ADC) via SPI to read raw voltage values from LDR and temperature sensors.
> 2. Replacing the PWM modules with zero-crossing phase-cut controllers to dim AC mains voltage using triacs.
> 3. Adding non-volatile SPI Flash memory to store and rewrite scene presets.
> 4. Integrating the ESP32 UART bridge with ESPHome or Home Assistant to provide local dashboard controls.
