// file: rtl/scheduler.v
// Minute-based Scheduler
// Tracks daily time (0 to 1439 minutes) and triggers scene indices at specific times.
// Supports fast simulation scaling through a TICKS_PER_MIN parameter.

`timescale 1ns/1ps

module scheduler #(
    parameter integer TICKS_PER_MIN = 600 // 60 seconds * 10 Hz = 600 ticks for 1 min in real-time.
                                          // Set to a small number (e.g., 5 or 10) in TB for fast sim.
) (
    input  wire       clk,             // System Clock
    input  wire       rst_n,           // Active-Low Reset
    input  wire       tick_10,         // 10 Hz clock enable tick
    output reg        sched_set_scene, // Pulse indicating a scheduler scene change
    output reg  [2:0] sched_scene_idx  // Scheduled scene index to load
);

    // Time keeping registers
    reg [$clog2(TICKS_PER_MIN+1)-1:0] tick_cnt;
    reg [10:0] current_minute; // 0 to 1439 minutes (24 hours)

    // Wire conversions for debug / internal monitoring
    wire [4:0] hour   = current_minute / 60;
    wire [5:0] minute = current_minute % 60;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tick_cnt         <= 0;
            current_minute   <= 11'd1078; // Initialize to 17:58 (17 * 60 + 58 = 1078) to quickly see the 18:00 transition in simulation!
            sched_set_scene  <= 1'b0;
            sched_scene_idx  <= 3'd0;
        end else begin
            sched_set_scene <= 1'b0;

            if (tick_10) begin
                if (tick_cnt == TICKS_PER_MIN - 1) begin
                    tick_cnt <= 0;
                    
                    // Increment minutes
                    if (current_minute == 1439) begin
                        current_minute <= 0;
                    end else begin
                        current_minute <= current_minute + 1'b1;
                    end

                    // Check schedule conditions
                    case (current_minute + 1'b1) // Check next minute to trigger at exact start of minute
                        11'd0: begin // 00:00 -> All Off
                            sched_set_scene <= 1'b1;
                            sched_scene_idx <= 3'd0;
                        end
                        11'd420: begin // 07:00 -> Work Scene
                            sched_set_scene <= 1'b1;
                            sched_scene_idx <= 3'd2;
                        end
                        11'd1080: begin // 18:00 -> Evening Scene
                            sched_set_scene <= 1'b1;
                            sched_scene_idx <= 3'd1;
                        end
                        11'd1380: begin // 23:00 -> Night Scene
                            sched_set_scene <= 1'b1;
                            sched_scene_idx <= 3'd3;
                        end
                        default: begin
                            sched_set_scene <= 1'b0;
                        end
                    endcase

                end else begin
                    tick_cnt <= tick_cnt + 1'b1;
                end
            end
        end
    end

endmodule
