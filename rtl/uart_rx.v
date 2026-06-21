// file: rtl/uart_rx.v
// UART Receiver (115200-N-8-1)
// Uses 16x oversampling to sample bits at their center.
// Parameterized for system clock frequency and target baud rate.

`timescale 1ns/1ps

module uart_rx #(
    parameter integer CLK_HZ  = 50_000_000,
    parameter integer BAUD    = 115200
) (
    input  wire       clk,     // System Clock
    input  wire       rst_n,   // Active-Low Reset
    input  wire       rx,      // RX serial line input
    output reg        rx_stb,  // Received byte valid strobe
    output reg  [7:0] rx_data  // Received 8-bit data
);

    // Calculate divisor for 16x oversampling clock
    localparam integer OVERSAMPLE_DIV = CLK_HZ / (BAUD * 16);

    // Oversample clock generator
    reg [$clog2(OVERSAMPLE_DIV)-1:0] clk_cnt;
    wire tick_16x = (clk_cnt == OVERSAMPLE_DIV - 1);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clk_cnt <= 0;
        end else begin
            if (clk_cnt == OVERSAMPLE_DIV - 1)
                clk_cnt <= 0;
            else
                clk_cnt <= clk_cnt + 1'b1;
        end
    end

    // Double-FF synchronize RX input to avoid metastability
    reg rx_s1, rx_s2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_s1 <= 1'b1;
            rx_s2 <= 1'b1;
        end else begin
            rx_s1 <= rx;
            rx_s2 <= rx_s1;
        end
    end

    // Receiver FSM
    localparam [1:0] S_IDLE  = 2'b00,
                     S_START = 2'b01,
                     S_DATA  = 2'b10,
                     S_STOP  = 2'b11;

    reg [1:0] state;
    reg [3:0] sample_cnt; // Counts 16 ticks per bit
    reg [2:0] bit_cnt;    // Counts 8 data bits
    reg [7:0] rx_shift;   // Shift register

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= S_IDLE;
            sample_cnt <= 0;
            bit_cnt    <= 0;
            rx_shift   <= 8'd0;
            rx_stb     <= 1'b0;
            rx_data    <= 8'd0;
        end else begin
            rx_stb <= 1'b0;

            if (tick_16x) begin
                case (state)
                    S_IDLE: begin
                        // Detect start bit (falling edge)
                        if (!rx_s2) begin
                            state      <= S_START;
                            sample_cnt <= 4'd0;
                        end
                    end

                    S_START: begin
                        // Wait for middle of start bit (sample 7)
                        if (sample_cnt == 4'd7) begin
                            if (!rx_s2) begin // Still low (valid start bit)
                                sample_cnt <= 4'd0;
                                bit_cnt    <= 3'd0;
                                state      <= S_DATA;
                            end else begin
                                state      <= S_IDLE; // False start
                            end
                        end else begin
                            sample_cnt <= sample_cnt + 4'd1;
                        end
                    end

                    S_DATA: begin
                        // Wait 16 ticks for next bit center
                        if (sample_cnt == 4'd15) begin
                            sample_cnt <= 4'd0;
                            rx_shift   <= {rx_s2, rx_shift[7:1]}; // LSB first
                            
                            if (bit_cnt == 3'd7) begin
                                state <= S_STOP;
                            end else begin
                                bit_cnt <= bit_cnt + 3'd1;
                            end
                        end else begin
                            sample_cnt <= sample_cnt + 4'd1;
                        end
                    end

                    S_STOP: begin
                        // Wait for stop bit center
                        if (sample_cnt == 4'd15) begin
                            sample_cnt <= 4'd0;
                            if (rx_s2) begin // Valid stop bit (high)
                                rx_data <= rx_shift;
                                rx_stb  <= 1'b1;
                            end
                            state <= S_IDLE;
                        end else begin
                            sample_cnt <= sample_cnt + 4'd1;
                        end
                    end
                endcase
            end
        end
    end

endmodule
