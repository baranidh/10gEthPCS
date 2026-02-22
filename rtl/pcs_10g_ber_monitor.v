// =============================================================================
// pcs_10g_ber_monitor.v — IEEE 802.3 Clause 49.2.10 BER Monitor & Link Status
// =============================================================================
// Monitors link quality and generates PCS status signals:
//   - pcs_status: overall PCS link status (block_lock AND NOT hi_ber)
//   - hi_ber: high bit error rate indication
//   - link_status: latching-low status per IEEE 802.3 Clause 49.2.14.1
//
// Also provides MDIO register 3.32 (PCS status) compatible signals
//
// Latency: 0 additional pipeline stages (status monitoring)
// =============================================================================

`timescale 1ns / 1ps

module pcs_10g_ber_monitor (
    input  wire        clk,
    input  wire        rst_n,

    // Status inputs
    input  wire        block_lock,
    input  wire        hi_ber,
    input  wire [15:0] sh_invalid_cnt,

    // Decode error monitoring
    input  wire        rx_decode_error,

    // PCS status outputs
    output reg         pcs_status,       // 1 = link up
    output reg         pcs_status_ll,    // Latching-low (clear on read)
    input  wire        status_read,      // Pulse to clear latching-low

    // Error counters
    output reg  [15:0] ber_count,        // BER error count
    output reg  [7:0]  errored_block_count, // Errored blocks count (saturating)
    output reg         rx_link_up        // Debounced link status
);

// ---- PCS status per Clause 49.2.14.1 ----
// pcs_status = block_lock AND NOT hi_ber
wire pcs_status_raw = block_lock & ~hi_ber;

// ---- Debounce timer for link-up ----
// Require pcs_status to be stable for ~10ms before declaring link up
// At 644 MHz, 10ms ≈ 6,440,000 cycles ≈ 2^23
localparam LINK_TIMER_MAX = 23'd6440000;
reg [22:0] link_timer;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        pcs_status        <= 1'b0;
        pcs_status_ll     <= 1'b0;
        ber_count         <= 16'd0;
        errored_block_count <= 8'd0;
        rx_link_up        <= 1'b0;
        link_timer        <= 23'd0;
    end else begin
        // PCS status
        pcs_status <= pcs_status_raw;

        // Latching-low: goes low when pcs_status goes low, stays low until read
        if (!pcs_status_raw) begin
            pcs_status_ll <= 1'b0;
        end else if (status_read) begin
            pcs_status_ll <= pcs_status_raw;
        end else if (!pcs_status_ll && pcs_status_raw) begin
            // First time status is good after read
            pcs_status_ll <= 1'b1;
        end

        // BER counter
        if (!block_lock) begin
            ber_count <= 16'd0;
        end else if (hi_ber) begin
            if (ber_count != 16'hFFFF) // Saturating
                ber_count <= ber_count + 16'd1;
        end

        // Errored block counter (saturating 8-bit)
        if (!block_lock) begin
            errored_block_count <= 8'd0;
        end else if (rx_decode_error) begin
            if (errored_block_count != 8'hFF)
                errored_block_count <= errored_block_count + 8'd1;
        end

        // Debounced link status
        if (pcs_status_raw) begin
            if (link_timer >= LINK_TIMER_MAX) begin
                rx_link_up <= 1'b1;
            end else begin
                link_timer <= link_timer + 23'd1;
            end
        end else begin
            rx_link_up <= 1'b0;
            link_timer <= 23'd0;
        end
    end
end

endmodule
