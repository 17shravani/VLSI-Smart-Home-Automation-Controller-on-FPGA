// file: rtl/clk_en.v
// Clock Enable Tick Generator
// Generates synchronous tick enables for slow processes (PWM and FSM/Scheduler)
// to avoid clock domain crossing (CDC) issues and save power.

`timescale 1ns/1ps

module clk_en #(
    parameter integer CLK_HZ  = 50_000_000, // Master clock frequency (e.g. 50 MHz)
    parameter integer TICK_1K_HZ = 1000,      // 1 kHz tick frequency
    parameter integer TICK_10_HZ = 10         // 10 Hz tick frequency
) (
    input  wire clk,      // Master Clock
    input  wire rst_n,    // Active-Low Reset
    output reg  tick_1k,  // 1 kHz clock enable output
    output reg  tick_10   // 10 Hz clock enable output
);

    // Divisors calculation
    localparam integer DIV_1K = CLK_HZ / TICK_1K_HZ;
    localparam integer DIV_10 = CLK_HZ / TICK_10_HZ;

    // Counters
    reg [$clog2(DIV_1K)-1:0] cnt_1k;
    reg [$clog2(DIV_10)-1:0] cnt_10;

    // 1 kHz Tick Generation
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt_1k  <= 0;
            tick_1k <= 1'b0;
        end else begin
            tick_1k <= 1'b0;
            if (cnt_1k == DIV_1K - 1) begin
                cnt_1k  <= 0;
                tick_1k <= 1'b1;
            end else begin
                cnt_1k  <= cnt_1k + 1'b1;
            end
        end
    end

    // 10 Hz Tick Generation
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt_10  <= 0;
            tick_10 <= 1'b0;
        end else begin
            tick_10 <= 1'b0;
            if (cnt_10 == DIV_10 - 1) begin
                cnt_10  <= 0;
                tick_10 <= 1'b1;
            end else begin
                cnt_10  <= cnt_10 + 1'b1;
            end
        end
    end

endmodule
