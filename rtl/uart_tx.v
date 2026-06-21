// file: rtl/uart_tx.v
// UART Transmitter (115200-N-8-1)
// Parameterized for system clock frequency and target baud rate.

`timescale 1ns/1ps

module uart_tx #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer BAUD   = 115200
) (
    input  wire       clk,      // System Clock
    input  wire       rst_n,    // Active-Low Reset
    input  wire       tx_start, // Start transmission pulse
    input  wire [7:0] tx_data,  // Byte to transmit
    output reg        tx,       // TX serial line output
    output reg        tx_ready  // High when idle and ready for new data
);

    // Divisor for baud rate clock
    localparam integer BIT_DIV = CLK_HZ / BAUD;

    // Bit timer
    reg [$clog2(BIT_DIV)-1:0] timer;
    wire bit_tick = (timer == BIT_DIV - 1);

    // Transmitter FSM
    localparam [1:0] S_IDLE  = 2'b00,
                     S_START = 2'b01,
                     S_DATA  = 2'b10,
                     S_STOP  = 2'b11;

    reg [1:0] state;
    reg [2:0] bit_cnt;   // Data bit counter
    reg [7:0] tx_shift;  // Shift register

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= S_IDLE;
            timer    <= 0;
            bit_cnt  <= 0;
            tx_shift <= 8'd0;
            tx       <= 1'b1; // Idle high
            tx_ready <= 1'b1;
        end else begin
            // Increment timer in active states
            if (state != S_IDLE) begin
                if (timer == BIT_DIV - 1)
                    timer <= 0;
                else
                    timer <= timer + 1'b1;
            end else begin
                timer <= 0;
            end

            case (state)
                S_IDLE: begin
                    tx       <= 1'b1;
                    tx_ready <= 1'b1;
                    if (tx_start) begin
                        tx_shift <= tx_data;
                        tx       <= 1'b0; // Start bit (low)
                        tx_ready <= 1'b0;
                        state    <= S_START;
                    end
                end

                S_START: begin
                    tx <= 1'b0;
                    if (bit_tick) begin
                        tx       <= tx_shift[0];
                        bit_cnt  <= 3'd0;
                        state    <= S_DATA;
                    end
                end

                S_DATA: begin
                    tx <= tx_shift[0];
                    if (bit_tick) begin
                        if (bit_cnt == 3'd7) begin
                            tx    <= 1'b1; // Stop bit (high)
                            state <= S_STOP;
                        end else begin
                            tx_shift <= {1'b0, tx_shift[7:1]};
                            bit_cnt  <= bit_cnt + 3'd1;
                        end
                    end
                end

                S_STOP: begin
                    tx <= 1'b1;
                    if (bit_tick) begin
                        tx_ready <= 1'b1;
                        state    <= S_IDLE;
                    end
                end
            endcase
        end
    end

endmodule
