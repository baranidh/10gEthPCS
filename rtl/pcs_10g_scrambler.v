// =============================================================================
// pcs_10g_scrambler.v — IEEE 802.3 Clause 49.2.6 Self-Synchronizing Scrambler
// =============================================================================
// TX-path scrambler: G(x) = 1 + x^39 + x^58
// Operates on 64-bit payload of 66-bit block (sync header bypasses scrambler)
// Self-synchronizing: no initialization sequence needed
//
// Per IEEE 802.3 Clause 49.2.6:
//   - Sync header bits are NOT scrambled
//   - Payload bits [63:0] are scrambled using LFSR polynomial
//   - Scrambler processes all 64 bits combinationally in one cycle
//
// Latency: 1 clock cycle (registered output)
// =============================================================================

`timescale 1ns / 1ps

module pcs_10g_scrambler (
    input  wire        clk,
    input  wire        rst_n,

    // Input 66-bit block
    input  wire [65:0] tx_block_in,
    input  wire        tx_block_valid,

    // Output scrambled 66-bit block
    output reg  [65:0] tx_block_out,
    output reg         tx_block_out_valid
);

// ---- Scrambler State (58-bit LFSR) ----
// Polynomial: G(x) = 1 + x^39 + x^58
// Output: scrambled_bit = data_bit XOR state[38] XOR state[57]
// Then shift state, feeding scrambled_bit into state[0]

reg [57:0] lfsr;

// ---- Combinational scramble of 64 payload bits ----
reg [63:0] scrambled_data;
reg [57:0] lfsr_next;

integer i;

always @(*) begin
    lfsr_next = lfsr;
    scrambled_data = 64'd0;

    // Process bit 0 (LSB) first through bit 63 (MSB)
    // This matches the serial bit ordering of the scrambler
    for (i = 0; i < 64; i = i + 1) begin
        scrambled_data[i] = tx_block_in[i] ^ lfsr_next[38] ^ lfsr_next[57];
        lfsr_next = {lfsr_next[56:0], scrambled_data[i]};
    end
end

// ---- Registered output ----
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        lfsr               <= 58'h3FF_FFFF_FFFF_FFFF; // All-ones init
        tx_block_out       <= 66'd0;
        tx_block_out_valid <= 1'b0;
    end else if (tx_block_valid) begin
        lfsr               <= lfsr_next;
        // Sync header passes through unscrambled
        tx_block_out       <= {tx_block_in[65:64], scrambled_data};
        tx_block_out_valid <= 1'b1;
    end else begin
        tx_block_out_valid <= 1'b0;
    end
end

endmodule
