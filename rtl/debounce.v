// file: rtl/debounce.v
// Input Conditioning: Synchronizer + Integrator Debouncer + Edge Detector
// Prevents metastability and filters contact bounce / noise.

`timescale 1ns/1ps

module debounce #(
    parameter integer CNT = 5  // Stability count (CNT * 100ms when driven by 10Hz tick)
) (
    input  wire clk,        // System Clock
    input  wire rst_n,      // Active-Low Reset
    input  wire tick,       // Slow clock enable tick (e.g. 10 Hz)
    input  wire async_in,   // Raw asynchronous noisy input
    output reg  level,      // Clean debounced level
    output reg  rise_pulse  // High for 1 system clock cycle on 0->1 transition
);

    // 2-FF Synchronizer for metastability avoidance
    reg sync0, sync1;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync0 <= 1'b0;
            sync1 <= 1'b0;
        end else begin
            sync0 <= async_in;
            sync1 <= sync0;
        end
    end

    // Debouncing Counter Logic
    reg [$clog2(CNT+1)-1:0] debounce_cnt;
    reg stable_val;
    reg prev_level;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            debounce_cnt <= 0;
            stable_val   <= 1'b0;
            level        <= 1'b0;
            prev_level   <= 1'b0;
            rise_pulse   <= 1'b0;
        end else begin
            // Pulse logic
            rise_pulse <= 1'b0;

            if (tick) begin
                if (sync1 != stable_val) begin
                    if (debounce_cnt == CNT - 1) begin
                        stable_val   <= sync1;
                        debounce_cnt <= 0;
                    end else begin
                        debounce_cnt <= debounce_cnt + 1'b1;
                    end
                end else begin
                    debounce_cnt <= 0;
                end

                // Level update
                level <= stable_val;
            end

            // Rising edge detection relative to sys clock
            prev_level <= level;
            if (level && !prev_level) begin
                rise_pulse <= 1'b1;
            end
        end
    end

endmodule
