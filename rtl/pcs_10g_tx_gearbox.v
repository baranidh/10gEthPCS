// =============================================================================
// pcs_10g_tx_gearbox.v — TX Gearbox: 66-bit to 16-bit width conversion
// =============================================================================
// Converts 66-bit scrambled blocks into 16-bit words for SERDES TX interface
// Designed for 644 MHz operation with 16-bit data path (16 × 644 = 10.3 Gbps)
//
// 66 and 16 share GCD=2, so the pattern repeats every 33 blocks = 132 words
// We use a shift-register approach for minimum latency
//
// Interface to SERDES/GTH:
//   - tx_data[15:0]: 16-bit data to SERDES
//   - tx_header[1:0]: sync header (used with GTH 64B/66B gearbox bypass)
//
// Latency: 1-4 clock cycles depending on fill level
// =============================================================================

`timescale 1ns / 1ps

module pcs_10g_tx_gearbox (
    input  wire        clk,        // 644 MHz
    input  wire        rst_n,

    // 66-bit block input
    input  wire [65:0] tx_block,
    input  wire        tx_block_valid,

    // 16-bit output to SERDES/GTH
    output reg  [15:0] tx_data,
    output reg  [1:0]  tx_header,
    output reg         tx_data_valid,

    // Flow control
    output wire        tx_ready,    // Can accept new 66-bit block
    input  wire        tx_sequence_done // Pulse when SERDES has consumed data
);

// ---- Shift register buffer ----
// Maximum occupancy: 64 bits (one payload) + residual
// We need at most 64+16 = 80 bits buffered
reg [79:0]  shift_reg;
reg [6:0]   bit_count;     // Number of valid bits in shift register (0..80)

// Ready when we have room for another 64-bit payload
assign tx_ready = (bit_count <= 7'd16);

// ---- Header extraction ----
// The sync header is always the first 2 bits of each 66-bit block
// We pass it separately via tx_header for SERDES configurations that use
// the separate header port (TXHEADER)

reg [1:0] stored_header;
reg       header_valid;

// ---- Load and shift logic ----
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        shift_reg    <= 80'd0;
        bit_count    <= 7'd0;
        tx_data      <= 16'd0;
        tx_header    <= 2'b00;
        tx_data_valid <= 1'b0;
        stored_header <= 2'b00;
        header_valid  <= 1'b0;
    end else begin
        // Default
        tx_data_valid <= 1'b0;

        // Load new 66-bit block into shift register
        if (tx_block_valid && tx_ready) begin
            // Store header separately
            stored_header <= tx_block[65:64];
            header_valid  <= 1'b1;

            // Append 64-bit payload (without sync header for separate header mode)
            shift_reg <= shift_reg | ({16'd0, tx_block[63:0]} << bit_count);
            bit_count <= bit_count + 7'd64;
        end

        // Output 16 bits when available
        if (bit_count >= 7'd16 || (tx_block_valid && tx_ready && (bit_count + 7'd64) >= 7'd16)) begin
            if (bit_count >= 7'd16) begin
                tx_data       <= shift_reg[15:0];
                tx_header     <= header_valid ? stored_header : 2'b01;
                tx_data_valid <= 1'b1;
                header_valid  <= 1'b0;

                // Shift out consumed bits
                shift_reg <= shift_reg >> 16;
                bit_count <= bit_count - 7'd16;
            end
        end
    end
end

endmodule
