// =============================================================================
// pcs_10g_rx_gearbox.v — RX Gearbox: 16-bit to 66-bit width conversion
// =============================================================================
// Converts 16-bit words from SERDES RX interface into 66-bit blocks
// Designed for 644 MHz operation with 16-bit data path (16 × 644 = 10.3 Gbps)
//
// Supports both:
//   1. Separate header mode (RXHEADER + RXDATA)
//   2. Raw serial mode (66-bit blocks in 16-bit stream)
//
// Block lock/alignment is handled by the block_sync module upstream,
// which tells this module when to slip by one bit position.
//
// Latency: 4-5 clock cycles (depends on alignment)
// =============================================================================

`timescale 1ns / 1ps

module pcs_10g_rx_gearbox (
    input  wire        clk,
    input  wire        rst_n,

    // 16-bit input from SERDES/GTH
    input  wire [15:0] rx_data,
    input  wire [1:0]  rx_header,
    input  wire        rx_data_valid,
    input  wire        rx_header_valid,

    // 66-bit block output
    output reg  [65:0] rx_block,
    output reg         rx_block_valid,

    // Slip control from block sync
    input  wire        slip           // Pulse: slip by one bit position
);

// ---- Shift register for reassembly ----
reg [81:0]  shift_reg;       // 66 + 16 = 82 bits max
reg [6:0]   bit_count;
reg [6:0]   slip_offset;     // Current bit-slip offset (0..65)

// ---- Separate header tracking ----
reg [1:0]   pending_header;
reg         has_header;

// ---- Main logic ----
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        shift_reg     <= 82'd0;
        bit_count     <= 7'd0;
        rx_block      <= 66'd0;
        rx_block_valid <= 1'b0;
        slip_offset   <= 7'd0;
        pending_header <= 2'b00;
        has_header    <= 1'b0;
    end else begin
        rx_block_valid <= 1'b0;

        // Handle slip: advance by 1 bit
        if (slip) begin
            if (bit_count > 0) begin
                shift_reg <= shift_reg >> 1;
                bit_count <= bit_count - 7'd1;
            end
            // Adjust slip offset for tracking
            if (slip_offset == 7'd65)
                slip_offset <= 7'd0;
            else
                slip_offset <= slip_offset + 7'd1;
        end

        // Load new 16-bit word
        if (rx_data_valid) begin
            shift_reg <= shift_reg | ({66'd0, rx_data} << bit_count);
            bit_count <= bit_count + 7'd16;

            // Store header if provided separately
            if (rx_header_valid) begin
                pending_header <= rx_header;
                has_header     <= 1'b1;
            end
        end

        // Extract 66-bit block when we have enough bits
        if (bit_count >= 7'd66) begin
            if (has_header) begin
                // Separate header mode: construct block from header + 64 data bits
                rx_block <= {pending_header, shift_reg[63:0]};
                shift_reg <= shift_reg >> 64;
                bit_count <= bit_count - 7'd64;
                has_header <= 1'b0;
            end else begin
                // Raw mode: first 2 bits are sync header
                rx_block <= shift_reg[65:0];
                shift_reg <= shift_reg >> 66;
                bit_count <= bit_count - 7'd66;
            end
            rx_block_valid <= 1'b1;
        end
    end
end

endmodule
