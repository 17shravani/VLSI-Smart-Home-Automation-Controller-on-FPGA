// file: rtl/ctrl_fsm.v
// Priority Finite State Machine for Smart Home Controller
// Resolves conflicts and drives actuators based on the following priorities:
// 1. ALARM (Safety first - overcurrent / security breach)
// 2. MANUAL (User overrides auto logic)
// 3. SENSOR_AUTO (Sensor driven automation)
// 4. SCHEDULE (Time-of-day automatic presets)
// 5. DEFAULT / IDLE (All off)

`timescale 1ns/1ps

module ctrl_fsm (
    input  wire        clk,                      // System Clock
    input  wire        rst_n,                    // Active-Low Reset
    input  wire        tick_10,                  // 10 Hz clock enable tick (100ms timebase)

    // Sensor Inputs
    input  wire        pir,                      // Motion sensor (1 = motion)
    input  wire        dark,                     // LDR sensor threshold (1 = dark, 0 = bright)
    input  wire        overcur,                  // Safety over-current alert (1 = fault)
    input  wire        door,                     // Door magnetic sensor (1 = open, 0 = closed)
    input  wire        security_mode,            // Security armed flag (1 = armed)
    input  wire        temp_high,                // Temperature threshold (1 = hot)

    // Manual Local Switch/Button Pulses
    input  wire [3:0]  btn_pulse,                // L0..L3 toggle button pulses
    input  wire [1:0]  btn_fan_pulse,            // F0..F1 toggle button pulses
    input  wire [3:0]  btn_relay_pulse,          // R0..R3 toggle button pulses
    input  wire        manual_evt,               // Combined manual push-button event

    // UART Remote Commands
    input  wire        cmd_set_duty_pulse,
    input  wire [2:0]  cmd_duty_ch,
    input  wire [7:0]  cmd_duty_val,
    input  wire        cmd_set_relay_pulse,
    input  wire [3:0]  cmd_relay_mask,
    input  wire        cmd_load_scene_pulse,
    input  wire [2:0]  cmd_scene_idx,
    input  wire        cmd_set_night_mode_pulse,
    input  wire        cmd_night_mode_val,

    // Scheduler Presets
    input  wire        sched_set_scene,
    input  wire [2:0]  sched_scene_idx,

    // Preset scene data from scenes lookup table
    input  wire [7:0]  scene_L0, scene_L1, scene_L2, scene_L3,
    input  wire [7:0]  scene_F0, scene_F1,
    input  wire [3:0]  scene_R,
    output reg  [2:0]  sel_scene_idx,            // Selected scene read index

    // Actuator Duty Cycles and States
    output reg  [7:0]  duty_L0, duty_L1, duty_L2, duty_L3,
    output reg  [7:0]  duty_F0, duty_F1,
    output reg  [3:0]  relays,
    output reg         alarm_active,
    output reg         energy_saving,
    output reg  [1:0]  fsm_state_out             // Current state output (for debug/telemetry)
);

    // FSM States
    localparam [1:0] S_IDLE   = 2'b00,
                     S_MANUAL = 2'b01,
                     S_AUTO   = 2'b10,
                     S_ALARM  = 2'b11;

    reg [1:0] state, next_state;

    // Registers to store manual overrides
    reg [7:0] man_L0, man_L1, man_L2, man_L3;
    reg [7:0] man_F0, man_F1;
    reg [3:0] man_R;

    // Registers to store scheduled configurations
    reg [7:0] sched_L0, sched_L1, sched_L2, sched_L3;
    reg [7:0] sched_F0, sched_F1;
    reg [3:0] sched_R;

    // Night Mode configuration
    reg night_mode;

    // Inactivity timers for MANUAL mode (returns to auto after 15s of idle)
    // 15 seconds * 10 Hz = 150 ticks
    reg [7:0] manual_idle_cnt;
    wire      manual_timeout = (manual_idle_cnt >= 8'd150);

    // Inactivity timers for AUTO mode (dims appliances after 10s of no motion, turns off after 20s)
    reg [7:0] auto_idle_cnt;
    wire      auto_eco_active   = (auto_idle_cnt >= 8'd100); // 10s no motion
    wire      auto_timeout_off  = (auto_idle_cnt >= 8'd200); // 20s no motion

    // ==========================================
    // FSM State Transition Logic
    // ==========================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
        end else begin
            state <= next_state;
        end
    end

    // Combinational Next State Decoder
    always @(*) begin
        next_state = state;
        
        // Priority 1: ALARM
        if (overcur || (security_mode && door)) begin
            next_state = S_ALARM;
        end else begin
            case (state)
                S_IDLE: begin
                    if (manual_evt || cmd_set_duty_pulse || cmd_set_relay_pulse || cmd_load_scene_pulse) begin
                        next_state = S_MANUAL;
                    end else if (pir && dark) begin
                        next_state = S_AUTO;
                    end
                end

                S_MANUAL: begin
                    // Exit manual mode on timeout back to AUTO (if motion) or IDLE
                    if (manual_timeout) begin
                        if (pir && dark) begin
                            next_state = S_AUTO;
                        end else begin
                            next_state = S_IDLE;
                        end
                    end
                end

                S_AUTO: begin
                    if (manual_evt || cmd_set_duty_pulse || cmd_set_relay_pulse || cmd_load_scene_pulse) begin
                        next_state = S_MANUAL;
                    end else if (auto_timeout_off) begin
                        next_state = S_IDLE;
                    end
                end

                S_ALARM: begin
                    // Recover from alarm state only when safety condition cleared AND security armed is low
                    if (!overcur && !security_mode) begin
                        next_state = S_IDLE;
                    end
                end

                default: next_state = S_IDLE;
            endcase
        end
    end


    // ==========================================
    // Sequential Control Logic
    // ==========================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Manual overrides reset
            man_L0         <= 8'd0;
            man_L1         <= 8'd0;
            man_L2         <= 8'd0;
            man_L3         <= 8'd0;
            man_F0         <= 8'd0;
            man_F1         <= 8'd0;
            man_R          <= 4'b0000;

            // Scheduled values reset
            sched_L0       <= 8'd0;
            sched_L1       <= 8'd0;
            sched_L2       <= 8'd0;
            sched_L3       <= 8'd0;
            sched_F0       <= 8'd0;
            sched_F1       <= 8'd0;
            sched_R        <= 4'b0000;

            sel_scene_idx  <= 3'd0;
            night_mode     <= 1'b0;

            manual_idle_cnt <= 8'd0;
            auto_idle_cnt   <= 8'd0;
            
            duty_L0        <= 8'd0;
            duty_L1        <= 8'd0;
            duty_L2        <= 8'd0;
            duty_L3        <= 8'd0;
            duty_F0        <= 8'd0;
            duty_F1        <= 8'd0;
            relays         <= 4'b0000;
            alarm_active   <= 1'b0;
            energy_saving  <= 1'b0;
            fsm_state_out  <= S_IDLE;
        end else begin
            fsm_state_out <= state;

            // 1. Process Night Mode Override
            if (cmd_set_night_mode_pulse) begin
                night_mode <= cmd_night_mode_val;
            end

            // 2. Track Inactivity Timers
            if (tick_10) begin
                // Manual Idle Counter (increment if no activity, reset if there is activity)
                if (state == S_MANUAL) begin
                    if (manual_evt || cmd_set_duty_pulse || cmd_set_relay_pulse || cmd_load_scene_pulse || pir) begin
                        manual_idle_cnt <= 8'd0;
                    end else begin
                        manual_idle_cnt <= manual_idle_cnt + 1'b1;
                    end
                end else begin
                    manual_idle_cnt <= 8'd0;
                end

                // Auto Idle Counter (increment if no motion detected)
                if (state == S_AUTO) begin
                    if (pir) begin
                        auto_idle_cnt <= 8'd0;
                    end else begin
                        auto_idle_cnt <= auto_idle_cnt + 1'b1;
                    end
                end else begin
                    auto_idle_cnt <= 8'd0;
                end
            end

            // 3. Process Scene preset loads (from UART remote commands)
            if (cmd_load_scene_pulse) begin
                sel_scene_idx <= cmd_scene_idx;
                // Load preset data into manual override registers
                man_L0 <= scene_L0;
                man_L1 <= scene_L1;
                man_L2 <= scene_L2;
                man_L3 <= scene_L3;
                man_F0 <= scene_F0;
                man_F1 <= scene_F1;
                man_R  <= scene_R;
            end

            // 4. Process Scheduler presets (driven by schedule triggers)
            if (sched_set_scene) begin
                sel_scene_idx <= sched_scene_idx;
                sched_L0      <= scene_L0;
                sched_L1      <= scene_L1;
                sched_L2      <= scene_L2;
                sched_L3      <= scene_L3;
                sched_F0      <= scene_F0;
                sched_F1      <= scene_F1;
                sched_R       <= scene_R;
            end

            // 5. Update local manual override registers on button pushes
            if (btn_pulse[0]) man_L0 <= (man_L0 > 0) ? 8'd0 : 8'd255;
            if (btn_pulse[1]) man_L1 <= (man_L1 > 0) ? 8'd0 : 8'd255;
            if (btn_pulse[2]) man_L2 <= (man_L2 > 0) ? 8'd0 : 8'd255;
            if (btn_pulse[3]) man_L3 <= (man_L3 > 0) ? 8'd0 : 8'd255;

            if (btn_fan_pulse[0]) man_F0 <= (man_F0 > 0) ? 8'd0 : 8'd128; // Toggle fan to 50%
            if (btn_fan_pulse[1]) man_F1 <= (man_F1 > 0) ? 8'd0 : 8'd128;

            if (btn_relay_pulse[0]) man_R[0] <= ~man_R[0];
            if (btn_relay_pulse[1]) man_R[1] <= ~man_R[1];
            if (btn_relay_pulse[2]) man_R[2] <= ~man_R[2];
            if (btn_relay_pulse[3]) man_R[3] <= ~man_R[3];

            // 6. Update local manual override registers on UART remote writes
            if (cmd_set_duty_pulse) begin
                case (cmd_duty_ch)
                    3'd0: man_L0 <= cmd_duty_val;
                    3'd1: man_L1 <= cmd_duty_val;
                    3'd2: man_L2 <= cmd_duty_val;
                    3'd3: man_L3 <= cmd_duty_val;
                    3'd4: man_F0 <= cmd_duty_val;
                    3'd5: man_F1 <= cmd_duty_val;
                    default: ;
                endcase
            end

            if (cmd_set_relay_pulse) begin
                man_R <= cmd_relay_mask;
            end

            // 7. Resolve outputs based on active state
            case (state)
                S_IDLE: begin
                    alarm_active  <= 1'b0;
                    energy_saving <= 1'b0;
                    duty_L0       <= sched_L0;
                    duty_L1       <= sched_L1;
                    duty_L2       <= sched_L2;
                    duty_L3       <= sched_L3;
                    duty_F0       <= sched_F0;
                    duty_F1       <= sched_F1;
                    relays        <= sched_R;
                end

                S_MANUAL: begin
                    alarm_active  <= 1'b0;
                    energy_saving <= 1'b0;
                    
                    // Apply night mode cap to lighting (if night mode enabled, cap maximum brightness to 50)
                    duty_L0 <= (night_mode && (man_L0 > 8'd50)) ? 8'd50 : man_L0;
                    duty_L1 <= (night_mode && (man_L1 > 8'd50)) ? 8'd50 : man_L1;
                    duty_L2 <= (night_mode && (man_L2 > 8'd50)) ? 8'd50 : man_L2;
                    duty_L3 <= (night_mode && (man_L3 > 8'd50)) ? 8'd50 : man_L3;
                    
                    duty_F0 <= man_F0;
                    duty_F1 <= man_F1;
                    relays  <= man_R;
                end

                S_AUTO: begin
                    alarm_active <= 1'b0;
                    
                    if (auto_eco_active) begin
                        // Inactivity Level 1: Eco / Energy Saving mode
                        energy_saving <= 1'b1;
                        duty_L0       <= 8'd15; // Dimmed lights
                        duty_L1       <= 8'd15;
                        duty_L2       <= 8'd15;
                        duty_L3       <= 8'd15;
                        duty_F0       <= 8'd40; // Quiet fans
                        duty_F1       <= 8'd40;
                        relays        <= 4'b0000;
                    end else begin
                        // Normal automation logic
                        energy_saving <= 1'b0;
                        
                        // LDR Light control (turn on room light L0 if dark)
                        if (dark) begin
                            duty_L0 <= night_mode ? 8'd50 : 8'd150;
                            duty_L1 <= night_mode ? 8'd30 : 8'd100;
                            duty_L2 <= 8'd0;
                            duty_L3 <= 8'd0;
                        end else begin
                            duty_L0 <= 8'd0;
                            duty_L1 <= 8'd0;
                            duty_L2 <= 8'd0;
                            duty_L3 <= 8'd0;
                        end
                        
                        // Temperature control (turn on fan F0 if hot)
                        if (temp_high) begin
                            duty_F0 <= 8'd200; // Fast speed
                            duty_F1 <= 8'd0;
                        end else begin
                            duty_F0 <= 8'd0;
                            duty_F1 <= 8'd0;
                        end

                        relays <= 4'b0011; // Standard relay configuration for auto mode
                    end
                end

                S_ALARM: begin
                    alarm_active  <= 1'b1;
                    energy_saving <= 1'b0;
                    
                    // Safety override: turn on all lights to full duty for evacuation
                    duty_L0 <= 8'd255;
                    duty_L1 <= 8'd255;
                    duty_L2 <= 8'd255;
                    duty_L3 <= 8'd255;
                    
                    // Turn off fans/relays to prevent feeding fresh air to fire or extending short-circuits
                    duty_F0 <= 8'd0;
                    duty_F1 <= 8'd0;
                    relays  <= 4'b0000;
                end
            endcase
        end
    end

endmodule
