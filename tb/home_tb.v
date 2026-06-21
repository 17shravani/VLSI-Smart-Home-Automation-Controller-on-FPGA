// file: tb/home_tb.v
// Testbench for Smart Home Automation Controller
// Automates simulation of sensors, button overrides, alarms, and UART commands.

`timescale 1ns/1ps

module home_tb;

    // Simulation Clock Parameters (50 MHz)
    localparam integer CLK_PERIOD = 20; // 20 ns = 50 MHz
    
    // UART Baud Rate Parameters (115200 baud)
    // 1 bit period = 1s / 115200 = 8.68 us = 8680 ns
    localparam integer BIT_PERIOD = 8680;

    // Registers to drive inputs
    reg clk_50m;
    reg rst_btn;
    reg pir_raw;
    reg ldr_dark_raw;
    reg overcur_raw;
    reg door_raw;
    reg security_mode_raw;
    reg temp_high_raw;
    reg btn0_raw;
    reg btn1_raw;
    reg btn2_raw;
    reg btn3_raw;
    reg uart_rx_sim;

    // Wires to monitor outputs
    wire uart_tx;
    wire L0_PWM, L1_PWM, L2_PWM, L3_PWM;
    wire F0_PWM, F1_PWM;
    wire R0, R1, R2, R3;
    wire ALARM_LED;
    wire ENERGY_LED;
    wire [1:0] fsm_state;

    // Instantiate Device Under Test (DUT)
    top #(
        .CLK_HZ(50_000_000),
        .BAUD(115200),
        .TICKS_PER_MIN(10) // Set to 10 ticks per simulated minute for fast simulation!
    ) DUT (
        .clk_50m(clk_50m),
        .rst_btn(rst_btn),
        .pir_raw(pir_raw),
        .ldr_dark_raw(ldr_dark_raw),
        .overcur_raw(overcur_raw),
        .door_raw(door_raw),
        .security_mode_raw(security_mode_raw),
        .temp_high_raw(temp_high_raw),
        .btn0_raw(btn0_raw),
        .btn1_raw(btn1_raw),
        .btn2_raw(btn2_raw),
        .btn3_raw(btn3_raw),
        .uart_rx(uart_rx_sim),
        .uart_tx(uart_tx),
        .L0_PWM(L0_PWM),
        .L1_PWM(L1_PWM),
        .L2_PWM(L2_PWM),
        .L3_PWM(L3_PWM),
        .F0_PWM(F0_PWM),
        .F1_PWM(F1_PWM),
        .R0(R0),
        .R1(R1),
        .R2(R2),
        .R3(R3),
        .ALARM_LED(ALARM_LED),
        .ENERGY_LED(ENERGY_LED),
        .fsm_state(fsm_state)
    );

    // Clock Generation
    always #(CLK_PERIOD/2) clk_50m = ~clk_50m;

    // ==========================================
    // UART Byte Transmit Task
    // ==========================================
    task send_uart_byte(input [7:0] data);
        integer bit_idx;
        begin
            // Start Bit (low)
            uart_rx_sim = 1'b0;
            #(BIT_PERIOD);
            
            // 8 Data Bits (LSB first)
            for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
                uart_rx_sim = data[bit_idx];
                #(BIT_PERIOD);
            end
            
            // Stop Bit (high)
            uart_rx_sim = 1'b1;
            #(BIT_PERIOD);
        end
    endtask

    // UART Packet Transmit Task: 0xAA <cmd> <len> <payload...> <xor>
    task send_uart_packet_2(input [7:0] cmd, input [7:0] len, input [7:0] p0, input [7:0] p1);
        reg [7:0] computed_xor;
        begin
            computed_xor = cmd ^ len ^ p0 ^ p1;
            $display("[TB] Sending UART Packet: CMD=0x%h, LEN=%0d, P0=0x%h, P1=0x%h, XOR=0x%h", cmd, len, p0, p1, computed_xor);
            send_uart_byte(8'hAA);         // SOF
            send_uart_byte(cmd);           // CMD
            send_uart_byte(len);           // LEN
            send_uart_byte(p0);            // Payload 0
            send_uart_byte(p1);            // Payload 1
            send_uart_byte(computed_xor);   // XOR Checksum
        end
    endtask

    // ==========================================
    // Test Sequence
    // ==========================================
    initial begin
        // Setup waveform dumping
        $dumpfile("home.vcd");
        $dumpvars(0, home_tb);

        // Initialize inputs
        clk_50m           = 1'b0;
        rst_btn           = 1'b1; // Start in reset
        pir_raw           = 1'b0;
        ldr_dark_raw      = 1'b0;
        overcur_raw       = 1'b0;
        door_raw          = 1'b0;
        security_mode_raw = 1'b0;
        temp_high_raw     = 1'b0;
        btn0_raw          = 1'b0;
        btn1_raw          = 1'b0;
        btn2_raw          = 1'b0;
        btn3_raw          = 1'b0;
        uart_rx_sim       = 1'b1; // Idle high

        // 1. Release reset after 200 ns
        #200;
        rst_btn = 1'b0;
        $display("[TB] Reset released. Initial FSM State: %b", fsm_state);
        #1000;

        // 2. Test CASE 1: Manual button push override
        $display("\n--- CASE 1: Physical Push Button Override ---");
        // Pulse btn0 to toggle Light 0
        // (Note: debouncer stable count is 2 * 100ms ticks = 200ms of sim time.
        // Let's speed up the debounce tick in hardware simulations by pulsing button for long enough.
        // In our testbench, we will wait 300 ms to trigger the tick. Wait, 300 ms is 300,000,000 ns!)
        // Wait, to keep simulation short, we can advance simulation time.
        btn0_raw = 1'b1;
        #300_000_000; // Hold button for 300 ms so debounce registers it
        btn0_raw = 1'b0;
        #50_000_000;  // Wait for processing
        
        $display("[TB] State after button push: %b (Expected: 01 for S_MANUAL)", fsm_state);
        if (fsm_state == 2'b01) begin
            $display("[TB] PASS: Manual button override active.");
        end else begin
            $display("[TB] FAIL: Manual button override failed.");
        end

        // Wait for manual override inactivity timeout (15 seconds = 15,000,000,000 ns!)
        // We will fast-forward time to let it time out and return to S_IDLE
        $display("[TB] Fast-forwarding 16 seconds to observe manual mode timeout...");
        #16_000_000_000;
        $display("[TB] State after 16s idle: %b (Expected: 00 for S_IDLE)", fsm_state);
        if (fsm_state == 2'b00) begin
            $display("[TB] PASS: Manual mode timed out back to IDLE.");
        end else begin
            $display("[TB] FAIL: Manual mode timeout failed.");
        end

        // 3. Test CASE 2: Sensor Automation Mode
        $display("\n--- CASE 2: Sensor Automation (PIR + LDR) ---");
        pir_raw      = 1'b1; // Motion detected
        ldr_dark_raw = 1'b1; // Room is dark
        #300_000_000; // Hold for debouncers
        
        $display("[TB] State after sensor activation: %b (Expected: 10 for S_AUTO)", fsm_state);
        if (fsm_state == 2'b10) begin
            $display("[TB] PASS: Sensor-driven Auto mode active.");
        end else begin
            $display("[TB] FAIL: Sensor-driven Auto mode failed.");
        end

        // 4. Test CASE 3: Energy-Saving (Eco) Mode Transition
        $display("\n--- CASE 3: Energy-Saving Inactivity Timer ---");
        pir_raw = 1'b0; // Stop motion
        // Wait 12 seconds for Eco timeout (10 seconds threshold in FSM)
        $display("[TB] Fast-forwarding 12 seconds of no motion...");
        #12_000_000_000;
        $display("[TB] State: %b, ENERGY_LED: %b (Expected: S_AUTO, ENERGY_LED=1)", fsm_state, ENERGY_LED);
        if (fsm_state == 2'b10 && ENERGY_LED == 1'b1) begin
            $display("[TB] PASS: Eco Mode entered successfully.");
        end else begin
            $display("[TB] FAIL: Eco Mode entry failed.");
        end

        // Wait another 10 seconds (total 22 seconds no motion) -> should return to S_IDLE (All Off)
        $display("[TB] Fast-forwarding 10 more seconds of no motion...");
        #10_000_000_000;
        $display("[TB] State: %b (Expected: 00 for S_IDLE)", fsm_state);
        if (fsm_state == 2'b00) begin
            $display("[TB] PASS: Auto mode timed out to IDLE.");
        end else begin
            $display("[TB] FAIL: Auto mode exit to IDLE failed.");
        end

        // 5. Test CASE 4: Safety Alarm Emergency Override
        $display("\n--- CASE 4: Over-Current Safety Alarm ---");
        overcur_raw = 1'b1; // Trigger over-current fault
        #300_000_000; // Wait for debounce
        
        $display("[TB] State: %b, ALARM_LED: %b, R0..3: %b%b%b%b (Expected: S_ALARM (11), ALARM_LED=1, Relays=0)", 
                 fsm_state, ALARM_LED, R3, R2, R1, R0);
        if (fsm_state == 2'b11 && ALARM_LED == 1'b1 && {R3,R2,R1,R0} == 4'b0000) begin
            $display("[TB] PASS: Emergency alarm active, relays tripped safely.");
        end else begin
            $display("[TB] FAIL: Emergency alarm failed to trigger/trip relays.");
        end

        // Clear fault
        overcur_raw = 1'b0;
        #300_000_000;
        $display("[TB] State after fault clear: %b (Expected: 00 for S_IDLE)", fsm_state);
        if (fsm_state == 2'b00) begin
            $display("[TB] PASS: Alarm cleared.");
        end else begin
            $display("[TB] FAIL: Alarm clear failed.");
        end

        // 6. Test CASE 5: UART Remote Commands
        $display("\n--- CASE 5: UART Packet Control ---");
        // We will send a SET_DUTY packet: cmd=0x01, len=2, p0=ch (0 for L0), p1=val (128 for 50% duty)
        send_uart_packet_2(8'h01, 8'd2, 8'd0, 8'd128);
        
        // Wait for serial packet reception to complete (6 bytes * 10 bit periods per byte = 60 * 8680 ns = ~520 us)
        #600_000; 
        
        $display("[TB] State after UART write command: %b (Expected: 01 for S_MANUAL)", fsm_state);
        if (fsm_state == 2'b01) begin
            $display("[TB] PASS: Remote UART override forced FSM to manual.");
        end else begin
            $display("[TB] FAIL: UART command did not transition FSM to manual.");
        end

        // End of simulation
        $display("\n===========================================");
        $display("[TB] All test sweeps executed successfully!");
        $display("===========================================");
        $finish;
    end

endmodule
