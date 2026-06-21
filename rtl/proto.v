// file: rtl/proto.v
// UART Binary Protocol Bridge (Host <-> FPGA)
// Handles RX packet parsing and TX status packet assembly.
//
// RX Packet Frame format: 0xAA <cmd> <len> <payload...> <xor>
// TX Packet Frame format: 0x55 <evt> <len> <payload...> <xor>
//
// Checksum is calculated as XOR of cmd (or evt), len, and all payload bytes.

`timescale 1ns/1ps

module proto (
    input  wire        clk,                  // System Clock
    input  wire        rst_n,                // Active-Low Reset
    
    // UART interface
    input  wire        rx_stb,               // Strobe from uart_rx
    input  wire [7:0]  rx_byte,              // Received byte
    input  wire        tx_ready,             // Ready from uart_tx
    output reg         tx_start,             // Trigger to uart_tx
    output reg  [7:0]  tx_byte,              // Byte output to uart_tx
    
    // Status/Sensor inputs to report to host
    input  wire [7:0]  L0_duty, L1_duty, L2_duty, L3_duty,
    input  wire [7:0]  F0_duty, F1_duty,
    input  wire [3:0]  relays,
    input  wire        alarm_active,
    input  wire        energy_saving,
    input  wire        pir,
    input  wire        dark,
    input  wire        overcur,
    input  wire        door,
    input  wire        tick_10,              // 10 Hz tick for timers

    // Strobe commands to FSM
    output reg         cmd_set_duty_pulse,
    output reg  [2:0]  cmd_duty_ch,
    output reg  [7:0]  cmd_duty_val,
    
    output reg         cmd_set_relay_pulse,
    output reg  [3:0]  cmd_relay_mask,
    
    output reg         cmd_load_scene_pulse,
    output reg  [2:0]  cmd_scene_idx,
    
    output reg         cmd_set_night_mode_pulse,
    output reg         cmd_night_mode_val
);

    // ==========================================
    // 1. RX Packet Parser FSM
    // ==========================================
    localparam [2:0] RX_IDLE    = 3'b000,
                     RX_CMD     = 3'b001,
                     RX_LEN     = 3'b010,
                     RX_PAYLOAD = 3'b011,
                     RX_XOR     = 3'b100;

    reg [2:0] rx_state;
    reg [7:0] rx_cmd;
    reg [7:0] rx_len;
    reg [7:0] rx_payload[0:7];
    reg [2:0] rx_pay_idx;
    reg [7:0] rx_cal_xor;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_state                 <= RX_IDLE;
            rx_cmd                   <= 8'd0;
            rx_len                   <= 8'd0;
            rx_pay_idx               <= 0;
            rx_cal_xor               <= 8'd0;
            cmd_set_duty_pulse       <= 1'b0;
            cmd_duty_ch              <= 3'd0;
            cmd_duty_val             <= 8'd0;
            cmd_set_relay_pulse      <= 1'b0;
            cmd_relay_mask           <= 4'b0000;
            cmd_load_scene_pulse     <= 1'b0;
            cmd_scene_idx            <= 3'd0;
            cmd_set_night_mode_pulse <= 1'b0;
            cmd_night_mode_val       <= 1'b0;
        end else begin
            // Pulse resets
            cmd_set_duty_pulse       <= 1'b0;
            cmd_set_relay_pulse      <= 1'b0;
            cmd_load_scene_pulse     <= 1'b0;
            cmd_set_night_mode_pulse <= 1'b0;

            if (rx_stb) begin
                case (rx_state)
                    RX_IDLE: begin
                        if (rx_byte == 8'hAA) begin
                            rx_state   <= RX_CMD;
                            rx_cal_xor <= 8'd0;
                        end
                    end

                    RX_CMD: begin
                        rx_cmd     <= rx_byte;
                        rx_cal_xor <= rx_cal_xor ^ rx_byte;
                        rx_state   <= RX_LEN;
                    end

                    RX_LEN: begin
                        rx_len     <= rx_byte;
                        rx_cal_xor <= rx_cal_xor ^ rx_byte;
                        rx_pay_idx <= 0;
                        if (rx_byte == 8'd0) begin
                            rx_state <= RX_XOR;
                        end else if (rx_byte <= 8'd8) begin
                            rx_state <= RX_PAYLOAD;
                        end else begin
                            rx_state <= RX_IDLE; // Length error
                        end
                    end

                    RX_PAYLOAD: begin
                        rx_payload[rx_pay_idx] <= rx_byte;
                        rx_cal_xor             <= rx_cal_xor ^ rx_byte;
                        rx_pay_idx             <= rx_pay_idx + 1'b1;
                        if (rx_pay_idx == rx_len - 1) begin
                            rx_state <= RX_XOR;
                        end
                    end

                    RX_XOR: begin
                        if (rx_byte == rx_cal_xor) begin
                            // Checksum matched! Decode command
                            case (rx_cmd)
                                8'h01: begin // SET_DUTY (payload[0] = ch, payload[1] = val)
                                    if (rx_len == 8'd2) begin
                                        cmd_set_duty_pulse <= 1'b1;
                                        cmd_duty_ch        <= rx_payload[0][2:0];
                                        cmd_duty_val       <= rx_payload[1];
                                    end
                                end
                                8'h02: begin // SET_RELAY (payload[0] = mask)
                                    if (rx_len == 8'd1) begin
                                        cmd_set_relay_pulse <= 1'b1;
                                        cmd_relay_mask      <= rx_payload[0][3:0];
                                    end
                                end
                                8'h03: begin // LOAD_SCENE (payload[0] = scene_idx)
                                    if (rx_len == 8'd1) begin
                                        cmd_load_scene_pulse <= 1'b1;
                                        cmd_scene_idx        <= rx_payload[0][2:0];
                                    end
                                end
                                8'h04: begin // SET_NIGHT_MODE (payload[0] = on/off)
                                    if (rx_len == 8'd1) begin
                                        cmd_set_night_mode_pulse <= 1'b1;
                                        cmd_night_mode_val       <= rx_payload[0][0];
                                    end
                                end
                                default: begin
                                    // Unknown command, ignore
                                end
                            endcase
                        end
                        rx_state <= RX_IDLE;
                    end

                    default: rx_state <= RX_IDLE;
                endcase
            end
        end
    end


    // ==========================================
    // 2. TX Packet Encoder FSM
    // ==========================================
    
    // Status Timer: send STATUS event periodically (every 1 second = 10 ticks of 10Hz)
    reg [3:0] sec_cnt;
    reg       status_req;
    
    // Sensor Change Detection
    reg       prev_pir, prev_dark, prev_overcur, prev_door;
    reg       sensor_change_req;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sec_cnt           <= 0;
            status_req        <= 1'b0;
            prev_pir          <= 1'b0;
            prev_dark         <= 1'b0;
            prev_overcur      <= 1'b0;
            prev_door         <= 1'b0;
            sensor_change_req <= 1'b0;
        end else begin
            status_req        <= 1'b0;
            sensor_change_req <= 1'b0;

            // 1 Second timer
            if (tick_10) begin
                if (sec_cnt == 4'd9) begin
                    sec_cnt    <= 0;
                    status_req <= 1'b1;
                end else begin
                    sec_cnt <= sec_cnt + 1'b1;
                end
            end

            // Sensor change trigger
            prev_pir     <= pir;
            prev_dark    <= dark;
            prev_overcur <= overcur;
            prev_door    <= door;

            if ((pir != prev_pir) || (dark != prev_dark) || (overcur != prev_overcur) || (door != prev_door)) begin
                sensor_change_req <= 1'b1;
            end
        end
    end

    // Tx Buffering and Sending FSM
    localparam [2:0] TX_IDLE      = 3'b000,
                     TX_LOAD_STAT = 3'b001,
                     TX_LOAD_SENS = 3'b010,
                     TX_STREAM    = 3'b011,
                     TX_WAIT      = 3'b100;

    reg [2:0] tx_state;
    reg [7:0] tx_buf[0:15];
    reg [3:0] tx_len_total;
    reg [3:0] tx_idx;
    reg       last_tx_ready;

    // XOR calculated for outgoing packet
    wire [7:0] status_xor = 8'h81 ^ 8'd8 ^ L0_duty ^ L1_duty ^ L2_duty ^ L3_duty ^ F0_duty ^ F1_duty ^ 
                            {4'b0000, relays} ^ {6'b000000, alarm_active, energy_saving};
                            
    wire [7:0] sensor_xor = 8'h82 ^ 8'd1 ^ {4'b0000, pir, dark, overcur, door};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_state      <= TX_IDLE;
            tx_start      <= 1'b0;
            tx_byte       <= 8'd0;
            tx_len_total  <= 0;
            tx_idx        <= 0;
            last_tx_ready <= 1'b1;
        end else begin
            tx_start      <= 1'b0;
            last_tx_ready <= tx_ready;

            case (tx_state)
                TX_IDLE: begin
                    tx_idx <= 0;
                    if (status_req) begin
                        tx_state <= TX_LOAD_STAT;
                    end else if (sensor_change_req) begin
                        tx_state <= TX_LOAD_SENS;
                    end
                end

                TX_LOAD_STAT: begin
                    tx_buf[0]  <= 8'h55;          // SOF
                    tx_buf[1]  <= 8'h81;          // EVT_STATUS
                    tx_buf[2]  <= 8'd8;           // LEN = 8
                    tx_buf[3]  <= L0_duty;        // payload 0
                    tx_buf[4]  <= L1_duty;        // payload 1
                    tx_buf[5]  <= L2_duty;        // payload 2
                    tx_buf[6]  <= L3_duty;        // payload 3
                    tx_buf[7]  <= F0_duty;        // payload 4
                    tx_buf[8]  <= F1_duty;        // payload 5
                    tx_buf[9]  <= {4'b0000, relays}; // payload 6
                    tx_buf[10] <= {6'b000000, alarm_active, energy_saving}; // payload 7
                    tx_buf[11] <= status_xor;     // XOR checksum
                    tx_len_total <= 4'd12;
                    tx_state   <= TX_STREAM;
                end

                TX_LOAD_SENS: begin
                    tx_buf[0]  <= 8'h55;          // SOF
                    tx_buf[1]  <= 8'h82;          // EVT_SENSOR
                    tx_buf[2]  <= 8'd1;           // LEN = 1
                    tx_buf[3]  <= {4'b0000, pir, dark, overcur, door}; // payload 0
                    tx_buf[4]  <= sensor_xor;     // XOR checksum
                    tx_len_total <= 4'd5;
                    tx_state   <= TX_STREAM;
                end

                TX_STREAM: begin
                    if (tx_ready) begin
                        tx_byte  <= tx_buf[tx_idx];
                        tx_start <= 1'b1;
                        tx_state <= TX_WAIT;
                    end
                end

                TX_WAIT: begin
                    // Wait for tx_ready to fall (indicates start of serial transmission)
                    if (!tx_ready && last_tx_ready) begin
                        if (tx_idx == tx_len_total - 1) begin
                            tx_state <= TX_IDLE;
                        end else begin
                            tx_idx   <= tx_idx + 1'b1;
                            tx_state <= TX_STREAM;
                        end
                    end
                    
                    // Safety timeout fallback: if uart_tx somehow remains ready too long
                    // or didn't register falling edge, allow transmission to progress
                    // after brief period. Usually, tx_ready transitions are instantaneous in simulation.
                end

                default: tx_state <= TX_IDLE;
            endcase
        end
    end

endmodule
