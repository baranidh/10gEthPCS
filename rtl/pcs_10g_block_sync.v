// =============================================================================
// pcs_10g_block_sync.v — IEEE 802.3 Clause 49.2.9 Block Synchronization
// =============================================================================
// Implements the block lock state machine per Figure 49-14
//
// States:
//   LOCK_INIT     → Looking for valid sync headers
//   LOCK_TEST_SH  → Testing consecutive sync headers
//   LOCK_ACQUIRED → Block lock achieved, monitoring for errors
//
// Lock acquisition: 64 consecutive valid sync headers
// Lock loss: 16 invalid sync headers in any window of 8192
//
// The slip signal tells the RX gearbox to advance by one bit.
//
// Latency: 0 additional pipeline stages (operates alongside gearbox)
// =============================================================================

`timescale 1ns / 1ps

module pcs_10g_block_sync (
    input  wire        clk,
    input  wire        rst_n,

    // Sync header from received block (before descrambling)
    input  wire [1:0]  rx_sync_header,
    input  wire        rx_valid,

    // Control outputs
    output reg         block_lock,    // Block lock achieved
    output reg         slip,          // Pulse: tell gearbox to slip 1 bit

    // Status
    output reg         hi_ber,        // High BER detected
    output reg  [15:0] sh_valid_cnt,  // Valid sync header counter
    output reg  [15:0] sh_invalid_cnt // Invalid sync header counter (for BER)
);

`include "pcs_10g_defs.vh"

// ---- State machine ----
localparam [1:0] ST_LOCK_INIT = 2'd0;
localparam [1:0] ST_RESET_CNT = 2'd1;
localparam [1:0] ST_TEST_SH   = 2'd2;
localparam [1:0] ST_LOCKED    = 2'd3;

reg [1:0] state;

// Valid sync header check: must be 01 or 10 (not 00 or 11)
wire sh_valid = (rx_sync_header == 2'b01) || (rx_sync_header == 2'b10);
wire sh_invalid = !sh_valid;

// ---- BER monitoring counters ----
reg [12:0] ber_test_cnt;     // Counts blocks in test window
reg [5:0]  ber_bad_cnt;      // Counts bad sync headers in window

// ---- State machine ----
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state          <= ST_LOCK_INIT;
        block_lock     <= 1'b0;
        slip           <= 1'b0;
        hi_ber         <= 1'b1;
        sh_valid_cnt   <= 16'd0;
        sh_invalid_cnt <= 16'd0;
        ber_test_cnt   <= 13'd0;
        ber_bad_cnt    <= 6'd0;
    end else begin
        slip <= 1'b0; // Default: no slip

        if (rx_valid) begin
            case (state)
                ST_LOCK_INIT: begin
                    // Looking for first valid sync header
                    block_lock <= 1'b0;
                    hi_ber     <= 1'b1;
                    if (sh_valid) begin
                        state        <= ST_RESET_CNT;
                        sh_valid_cnt <= 16'd1;
                    end else begin
                        // Slip and try again
                        slip <= 1'b1;
                    end
                end

                ST_RESET_CNT: begin
                    // Reset counters and start testing
                    sh_valid_cnt   <= 16'd1;
                    sh_invalid_cnt <= 16'd0;
                    state          <= ST_TEST_SH;
                end

                ST_TEST_SH: begin
                    // Test for BLOCK_LOCK_SH_CNT_N consecutive valid headers
                    if (sh_valid) begin
                        sh_valid_cnt <= sh_valid_cnt + 16'd1;
                        if (sh_valid_cnt >= `BLOCK_LOCK_SH_CNT_N - 1) begin
                            // Lock acquired!
                            state      <= ST_LOCKED;
                            block_lock <= 1'b1;
                            hi_ber     <= 1'b0;
                            // Reset BER counters
                            ber_test_cnt <= 13'd0;
                            ber_bad_cnt  <= 6'd0;
                        end
                    end else begin
                        // Invalid header — slip and restart
                        slip  <= 1'b1;
                        state <= ST_LOCK_INIT;
                        sh_valid_cnt <= 16'd0;
                    end
                end

                ST_LOCKED: begin
                    // Monitor for BER
                    ber_test_cnt <= ber_test_cnt + 13'd1;

                    if (sh_invalid) begin
                        sh_invalid_cnt <= sh_invalid_cnt + 16'd1;
                        ber_bad_cnt    <= ber_bad_cnt + 6'd1;
                    end

                    // Check BER window
                    if (ber_test_cnt >= `BER_TEST_SH_PERIOD) begin
                        if (ber_bad_cnt >= `BER_BAD_SH_THRESHOLD) begin
                            // BER too high — lose lock
                            hi_ber     <= 1'b1;
                            block_lock <= 1'b0;
                            state      <= ST_LOCK_INIT;
                            sh_valid_cnt   <= 16'd0;
                            sh_invalid_cnt <= 16'd0;
                        end else begin
                            hi_ber <= 1'b0;
                        end
                        // Reset BER window
                        ber_test_cnt <= 13'd0;
                        ber_bad_cnt  <= 6'd0;
                    end
                end

                default: state <= ST_LOCK_INIT;
            endcase
        end
    end
end

endmodule
