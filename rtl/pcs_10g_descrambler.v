// =============================================================================
// pcs_10g_descrambler.v — IEEE 802.3 Clause 49.2.6 Self-Synchronizing Descrambler
// =============================================================================
// RX-path descrambler: G(x) = 1 + x^39 + x^58
// Self-synchronizing: acquires lock after 58 bits of valid data
//
// Per IEEE 802.3 Clause 49.2.6:
//   - Uses received (scrambled) bits as LFSR feedback
//   - Sync header bits are NOT descrambled
//
// Latency: 1 clock cycle (registered output)
// =============================================================================

`timescale 1ns / 1ps

module pcs_10g_descrambler (
    input  wire        clk,
    input  wire        rst_n,

    // Input 66-bit block (scrambled payload, unscrambled sync header)
    input  wire [65:0] rx_block_in,
    input  wire        rx_block_valid,

    // Output descrambled 66-bit block
    output reg  [65:0] rx_block_out,
    output reg         rx_block_out_valid
);

// ---- Descrambler State (58-bit LFSR) ----
reg [57:0] lfsr;

// ---- Combinational descramble of 64 payload bits ----
reg [63:0] descrambled_data;
reg [57:0] lfsr_next;

integer i;

always @(*) begin
    lfsr_next = lfsr;
    descrambled_data = 64'd0;

    // For descrambler: output = received_bit XOR lfsr[38] XOR lfsr[57]
    // Then shift lfsr feeding the RECEIVED (scrambled) bit into lfsr[0]
    // This is the key difference from the scrambler (which feeds back the scrambled output)
    for (i = 0; i < 64; i = i + 1) begin
        descrambled_data[i] = rx_block_in[i] ^ lfsr_next[38] ^ lfsr_next[57];
        lfsr_next = {lfsr_next[56:0], rx_block_in[i]}; // Feed received bit
    end
end

// ---- Registered output ----
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        lfsr               <= 58'h3FF_FFFF_FFFF_FFFF;
        rx_block_out       <= 66'd0;
        rx_block_out_valid <= 1'b0;
    end else if (rx_block_valid) begin
        lfsr               <= lfsr_next;
        rx_block_out       <= {rx_block_in[65:64], descrambled_data};
        rx_block_out_valid <= 1'b1;
    end else begin
        rx_block_out_valid <= 1'b0;
    end
end

endmodule
