// file: rtl/scenes.v
// Scene Lookup Table (ROM)
// Contains 8 preset configurations for lighting, fans, and socket relays.

`timescale 1ns/1ps

module scenes (
    input  wire [2:0] idx,   // Scene index selection (0 to 7)
    output reg  [7:0] L0,    // Light 0 preset duty
    output reg  [7:0] L1,    // Light 1 preset duty
    output reg  [7:0] L2,    // Light 2 preset duty
    output reg  [7:0] L3,    // Light 3 preset duty
    output reg  [7:0] F0,    // Fan 0 preset speed
    output reg  [7:0] F1,    // Fan 1 preset speed
    output reg  [3:0] R      // Relay status (R3, R2, R1, R0)
);

    always @(*) begin
        case (idx)
            3'd0: begin // ALL OFF
                L0 = 8'd0;   L1 = 8'd0;   L2 = 8'd0;   L3 = 8'd0;
                F0 = 8'd0;   F1 = 8'd0;
                R  = 4'b0000;
            end
            3'd1: begin // EVENING MOOD (Dimmed ambient, relay 0 on)
                L0 = 8'd40;  L1 = 8'd20;  L2 = 8'd10;  L3 = 8'd0;
                F0 = 8'd0;   F1 = 8'd0;
                R  = 4'b0001;
            end
            3'd2: begin // WORK/STUDY (Bright task lights, fan 0 moderate)
                L0 = 8'd200; L1 = 8'd180; L2 = 8'd0;   L3 = 8'd0;
                F0 = 8'd80;  F1 = 8'd0;
                R  = 4'b0010;
            end
            3'd3: begin // NIGHT MODE (Low safety light, relays off)
                L0 = 8'd10;  L1 = 8'd0;   L2 = 8'd0;   L3 = 8'd10;
                F0 = 8'd0;   F1 = 8'd0;
                R  = 4'b0000;
            end
            3'd4: begin // READING MODE (Focused warm light, quiet fan)
                L0 = 8'd120; L1 = 8'd120; L2 = 8'd0;   L3 = 8'd0;
                F0 = 8'd40;  F1 = 8'd0;
                R  = 4'b0011;
            end
            3'd5: begin // PARTY MODE (Vibrant full lighting, high fans)
                L0 = 8'd255; L1 = 8'd50;  L2 = 8'd255; L3 = 8'd50;
                F0 = 8'd180; F1 = 8'd180;
                R  = 4'b1100;
            end
            3'd6: begin // ECO MODE (Energy efficient minimums)
                L0 = 8'd25;  L1 = 8'd25;  L2 = 8'd25;  L3 = 8'd25;
                F0 = 8'd50;  F1 = 8'd50;
                R  = 4'b0000;
            end
            3'd7: begin // EMERGENCY/EVACUATION (All lights 100% on, relays active)
                L0 = 8'd255; L1 = 8'd255; L2 = 8'd255; L3 = 8'd255;
                F0 = 8'd0;   F1 = 8'd0;
                R  = 4'b1111;
            end
            default: begin
                L0 = 8'd0;   L1 = 8'd0;   L2 = 8'd0;   L3 = 8'd0;
                F0 = 8'd0;   F1 = 8'd0;
                R  = 4'b0000;
            end
        endcase
    end

endmodule
