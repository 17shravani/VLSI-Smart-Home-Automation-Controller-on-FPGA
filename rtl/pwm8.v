// file: rtl/pwm8.v
// 8-bit PWM Controller for Dimmers (Lights) and Fan Speed Controllers
// Increment counter on 1 kHz clock enable tick to produce PWM output.

`timescale 1ns/1ps

module pwm8 (
    input  wire       clk,      // System Clock
    input  wire       rst_n,    // Active-Low Reset
    input  wire       tick_1k,  // 1 kHz clock enable tick
    input  wire [7:0] duty,     // Duty Cycle value (0-255)
    output reg        out       // PWM output signal
);

    reg [7:0] cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt <= 8'd0;
            out <= 1'b0;
        end else if (tick_1k) begin
            cnt <= cnt + 8'd1;
            // High duty cycle comparison: if cnt < duty, output is high.
            // When duty = 0, out is always 0.
            // When duty = 255, out is high for 255 cycles and low for 1 cycle.
            // (To get 100% duty, standard design uses cnt < duty logic, out is 1'b1 for duty=255)
            out <= (cnt < duty);
        end
    end

endmodule
