// file: rtl/top.v
// Top-Level Integration Wrapper Module
// Wires together all sub-blocks to construct the synthesizable design.

`timescale 1ns/1ps

module top #(
    parameter integer CLK_HZ = 50_000_000, // Default 50 MHz Master Clock
    parameter integer BAUD   = 115200,      // Default 115200 Baud Rate
    parameter integer TICKS_PER_MIN = 600   // Ticks per minute in scheduler
) (
    input  wire clk_50m,           // Master System Clock
    input  wire rst_btn,           // Active-High Reset button (e.g. CPU reset button on Nexys A7)
    
    // Sensor & Switch Inputs (raw)
    input  wire pir_raw,           // Motion sensor
    input  wire ldr_dark_raw,      // Light level threshold
    input  wire overcur_raw,       // Current sensing relay fault
    input  wire door_raw,          // Door contact sensor
    input  wire security_mode_raw, // Security armed switch
    input  wire temp_high_raw,     // Temperature threshold switch
    
    // Push-buttons for manual control (raw)
    input  wire btn0_raw,          // Toggle Light 0
    input  wire btn1_raw,          // Toggle Light 1
    input  wire btn2_raw,          // Toggle Light 2
    input  wire btn3_raw,          // Toggle Light 3
    
    // UART interface to ESP32 IoT Bridge
    input  wire uart_rx,           // RX pin
    output wire uart_tx,           // TX pin
    
    // Actuator PWM and Relay Outputs
    output wire L0_PWM, L1_PWM, L2_PWM, L3_PWM, // Light PWM outputs
    output wire F0_PWM, F1_PWM,                 // Fan PWM outputs
    output wire R0, R1, R2, R3,                 // Relay outputs
    
    // Status Display LEDs
    output wire ALARM_LED,         // Safety/security alert active
    output wire ENERGY_LED,        // Energy Saving mode active
    output wire [1:0] fsm_state    // Current FSM state display
);

    // Active-Low reset derivation
    wire rst_n = ~rst_btn;

    // ==========================================
    // 1. Clock Enable Tick Generators
    // ==========================================
    wire tick_1k;
    wire tick_10;

    clk_en #(
        .CLK_HZ(CLK_HZ),
        .TICK_1K_HZ(1000),
        .TICK_10_HZ(10)
    ) u_clk_en (
        .clk(clk_50m),
        .rst_n(rst_n),
        .tick_1k(tick_1k),
        .tick_10(tick_10)
    );

    // ==========================================
    // 2. Input Conditioning (Debouncing & Sync)
    // ==========================================
    wire pir, dark, overcur, door, security_mode, temp_high;
    wire b0_pulse, b1_pulse, b2_pulse, b3_pulse;

    // Debouncers for sensor switch inputs
    debounce #(.CNT(2)) u_db_pir   (.clk(clk_50m), .rst_n(rst_n), .tick(tick_10), .async_in(pir_raw),   .level(pir),   .rise_pulse());
    debounce #(.CNT(2)) u_db_dark  (.clk(clk_50m), .rst_n(rst_n), .tick(tick_10), .async_in(ldr_dark_raw), .level(dark),  .rise_pulse());
    debounce #(.CNT(2)) u_db_oc    (.clk(clk_50m), .rst_n(rst_n), .tick(tick_10), .async_in(overcur_raw), .level(overcur),.rise_pulse());
    debounce #(.CNT(2)) u_db_door  (.clk(clk_50m), .rst_n(rst_n), .tick(tick_10), .async_in(door_raw),   .level(door),  .rise_pulse());
    debounce #(.CNT(2)) u_db_sec   (.clk(clk_50m), .rst_n(rst_n), .tick(tick_10), .async_in(security_mode_raw), .level(security_mode), .rise_pulse());
    debounce #(.CNT(2)) u_db_temp  (.clk(clk_50m), .rst_n(rst_n), .tick(tick_10), .async_in(temp_high_raw), .level(temp_high), .rise_pulse());

    // Debouncers for push buttons (Manual overrides)
    debounce #(.CNT(2)) u_db_btn0  (.clk(clk_50m), .rst_n(rst_n), .tick(tick_10), .async_in(btn0_raw),  .level(),      .rise_pulse(b0_pulse));
    debounce #(.CNT(2)) u_db_btn1  (.clk(clk_50m), .rst_n(rst_n), .tick(tick_10), .async_in(btn1_raw),  .level(),      .rise_pulse(b1_pulse));
    debounce #(.CNT(2)) u_db_btn2  (.clk(clk_50m), .rst_n(rst_n), .tick(tick_10), .async_in(btn2_raw),  .level(),      .rise_pulse(b2_pulse));
    debounce #(.CNT(2)) u_db_btn3  (.clk(clk_50m), .rst_n(rst_n), .tick(tick_10), .async_in(btn3_raw),  .level(),      .rise_pulse(b3_pulse));

    // Combine manual events for idle timer reset
    wire [3:0] btn_pulse  = {b3_pulse, b2_pulse, b1_pulse, b0_pulse};
    wire       manual_evt = |btn_pulse;

    // ==========================================
    // 3. UART Hardware Interfacing
    // ==========================================
    wire rx_stb;
    wire [7:0] rx_byte;
    wire tx_ready;
    wire tx_start;
    wire [7:0] tx_byte;

    uart_rx #(
        .CLK_HZ(CLK_HZ),
        .BAUD(BAUD)
    ) u_uart_rx (
        .clk(clk_50m),
        .rst_n(rst_n),
        .rx(uart_rx),
        .rx_stb(rx_stb),
        .rx_data(rx_byte)
    );

    uart_tx #(
        .CLK_HZ(CLK_HZ),
        .BAUD(BAUD)
    ) u_uart_tx (
        .clk(clk_50m),
        .rst_n(rst_n),
        .tx_start(tx_start),
        .tx_data(tx_byte),
        .tx(uart_tx),
        .tx_ready(tx_ready)
    );

    // ==========================================
    // 4. Protocol Parser and Encoder
    // ==========================================
    wire cmd_set_duty_pulse;
    wire [2:0] cmd_duty_ch;
    wire [7:0] cmd_duty_val;
    wire cmd_set_relay_pulse;
    wire [3:0] cmd_relay_mask;
    wire cmd_load_scene_pulse;
    wire [2:0] cmd_scene_idx;
    wire cmd_set_night_mode_pulse;
    wire cmd_night_mode_val;

    wire [7:0] dutyL0, dutyL1, dutyL2, dutyL3;
    wire [7:0] dutyF0, dutyF1;
    wire [3:0] relays;
    wire alarm_active;
    wire energy_saving;

    proto u_proto (
        .clk(clk_50m),
        .rst_n(rst_n),
        .rx_stb(rx_stb),
        .rx_byte(rx_byte),
        .tx_ready(tx_ready),
        .tx_start(tx_start),
        .tx_byte(tx_byte),
        
        .L0_duty(dutyL0),
        .L1_duty(dutyL1),
        .L2_duty(dutyL2),
        .L3_duty(dutyL3),
        .F0_duty(dutyF0),
        .F1_duty(dutyF1),
        .relays(relays),
        .alarm_active(alarm_active),
        .energy_saving(energy_saving),
        
        .pir(pir),
        .dark(dark),
        .overcur(overcur),
        .door(door),
        
        .tick_10(tick_10),
        
        .cmd_set_duty_pulse(cmd_set_duty_pulse),
        .cmd_duty_ch(cmd_duty_ch),
        .cmd_duty_val(cmd_duty_val),
        .cmd_set_relay_pulse(cmd_set_relay_pulse),
        .cmd_relay_mask(cmd_relay_mask),
        .cmd_load_scene_pulse(cmd_load_scene_pulse),
        .cmd_scene_idx(cmd_scene_idx),
        .cmd_set_night_mode_pulse(cmd_set_night_mode_pulse),
        .cmd_night_mode_val(cmd_night_mode_val)
    );

    // ==========================================
    // 5. Scheduler Timer
    // ==========================================
    wire sched_set_scene;
    wire [2:0] sched_scene_idx;

    scheduler #(
        .TICKS_PER_MIN(TICKS_PER_MIN)
    ) u_scheduler (
        .clk(clk_50m),
        .rst_n(rst_n),
        .tick_10(tick_10),
        .sched_set_scene(sched_set_scene),
        .sched_scene_idx(sched_scene_idx)
    );

    // ==========================================
    // 6. Preset Scene Lookup ROM
    // ==========================================
    wire [2:0] sel_scene_idx;
    wire [7:0] scene_L0, scene_L1, scene_L2, scene_L3;
    wire [7:0] scene_F0, scene_F1;
    wire [3:0] scene_R;

    scenes u_scenes (
        .idx(sel_scene_idx),
        .L0(scene_L0), .L1(scene_L1), .L2(scene_L2), .L3(scene_L3),
        .F0(scene_F0), .F1(scene_F1),
        .R(scene_R)
    );

    // ==========================================
    // 7. Central FSM Controller
    // ==========================================
    ctrl_fsm u_ctrl_fsm (
        .clk(clk_50m),
        .rst_n(rst_n),
        .tick_10(tick_10),
        
        .pir(pir),
        .dark(dark),
        .overcur(overcur),
        .door(door),
        .security_mode(security_mode),
        .temp_high(temp_high),
        
        .btn_pulse(btn_pulse),
        .btn_fan_pulse(2'b00),       // Physical board has buttons mapped to light toggles. Fan toggles handled via UART.
        .btn_relay_pulse(4'b0000),   // Relays toggled via UART commands.
        .manual_evt(manual_evt),
        
        .cmd_set_duty_pulse(cmd_set_duty_pulse),
        .cmd_duty_ch(cmd_duty_ch),
        .cmd_duty_val(cmd_duty_val),
        .cmd_set_relay_pulse(cmd_set_relay_pulse),
        .cmd_relay_mask(cmd_relay_mask),
        .cmd_load_scene_pulse(cmd_load_scene_pulse),
        .cmd_scene_idx(cmd_scene_idx),
        .cmd_set_night_mode_pulse(cmd_set_night_mode_pulse),
        .cmd_night_mode_val(cmd_night_mode_val),
        
        .sched_set_scene(sched_set_scene),
        .sched_scene_idx(sched_scene_idx),
        
        .scene_L0(scene_L0), .scene_L1(scene_L1), .scene_L2(scene_L2), .scene_L3(scene_L3),
        .scene_F0(scene_F0), .scene_F1(scene_F1),
        .scene_R(scene_R),
        .sel_scene_idx(sel_scene_idx),
        
        .duty_L0(dutyL0), .duty_L1(dutyL1), .duty_L2(dutyL2), .duty_L3(dutyL3),
        .duty_F0(dutyF0), .duty_F1(dutyF1),
        .relays(relays),
        .alarm_active(alarm_active),
        .energy_saving(energy_saving),
        .fsm_state_out(fsm_state)
    );

    // ==========================================
    // 8. PWM Actuator Output Drivers
    // ==========================================
    pwm8 u_pwm_L0 (.clk(clk_50m), .rst_n(rst_n), .tick_1k(tick_1k), .duty(dutyL0), .out(L0_PWM));
    pwm8 u_pwm_L1 (.clk(clk_50m), .rst_n(rst_n), .tick_1k(tick_1k), .duty(dutyL1), .out(L1_PWM));
    pwm8 u_pwm_L2 (.clk(clk_50m), .rst_n(rst_n), .tick_1k(tick_1k), .duty(dutyL2), .out(L2_PWM));
    pwm8 u_pwm_L3 (.clk(clk_50m), .rst_n(rst_n), .tick_1k(tick_1k), .duty(dutyL3), .out(L3_PWM));
    
    pwm8 u_pwm_F0 (.clk(clk_50m), .rst_n(rst_n), .tick_1k(tick_1k), .duty(dutyF0), .out(F0_PWM));
    pwm8 u_pwm_F1 (.clk(clk_50m), .rst_n(rst_n), .tick_1k(tick_1k), .duty(dutyF1), .out(F1_PWM));

    // Relay outputs
    assign {R3, R2, R1, R0} = relays;
    
    // Status outputs
    assign ALARM_LED  = alarm_active;
    assign ENERGY_LED = energy_saving;

endmodule
