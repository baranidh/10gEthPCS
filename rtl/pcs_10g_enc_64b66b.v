// =============================================================================
// pcs_10g_enc_64b66b.v — IEEE 802.3 Clause 49.2.4 64B/66B Encode
// =============================================================================
// TX-path encoder: XGMII 64-bit + 8-bit control → 66-bit block
// Ultra-low latency: purely combinational encoding, registered output
// Conforms to IEEE 802.3-2022 Tables 49-1 through 49-4
//
// Latency: 1 clock cycle (registered output)
// =============================================================================

`timescale 1ns / 1ps

module pcs_10g_enc_64b66b (
    input  wire        clk,
    input  wire        rst_n,

    // XGMII TX interface (internal 64-bit SDR)
    input  wire [63:0] xgmii_txd,   // 8 lanes × 8 bits
    input  wire [7:0]  xgmii_txc,   // 8 lanes × 1 bit control

    // Encoded 66-bit block output
    output reg  [65:0] tx_block,     // [65:64]=sync, [63:0]=payload
    output reg         tx_block_valid,

    // Status
    output reg         encode_error  // Invalid XGMII pattern detected
);

`include "pcs_10g_defs.vh"

// ---- Combinational encode logic ----
reg [65:0] block_next;
reg        error_next;

// Extract individual lanes
wire [7:0] d0 = xgmii_txd[ 7: 0];
wire [7:0] d1 = xgmii_txd[15: 8];
wire [7:0] d2 = xgmii_txd[23:16];
wire [7:0] d3 = xgmii_txd[31:24];
wire [7:0] d4 = xgmii_txd[39:32];
wire [7:0] d5 = xgmii_txd[47:40];
wire [7:0] d6 = xgmii_txd[55:48];
wire [7:0] d7 = xgmii_txd[63:56];

wire c0 = xgmii_txc[0];
wire c1 = xgmii_txc[1];
wire c2 = xgmii_txc[2];
wire c3 = xgmii_txc[3];
wire c4 = xgmii_txc[4];
wire c5 = xgmii_txc[5];
wire c6 = xgmii_txc[6];
wire c7 = xgmii_txc[7];

// ---- Map XGMII control character to 7-bit encoding ----
function [6:0] ctrl_encode;
    input [7:0] xgmii_char;
    begin
        case (xgmii_char)
            `XGMII_IDLE:   ctrl_encode = `CTRL_IDLE;
            `XGMII_ERROR:  ctrl_encode = `CTRL_ERROR;
            default:       ctrl_encode = `CTRL_ERROR; // Map unknown to error
        endcase
    end
endfunction

// ---- Map XGMII ordered set to 4-bit O-code ----
function [3:0] ocode_encode;
    input [7:0] xgmii_char;
    begin
        case (xgmii_char)
            `XGMII_SEQ_OS: ocode_encode = `OCODE_SEQ;
            `XGMII_SIG_OS: ocode_encode = `OCODE_SIG;
            default:       ocode_encode = `OCODE_SEQ;
        endcase
    end
endfunction

always @(*) begin
    block_next = 66'd0;
    error_next = 1'b0;

    if (xgmii_txc == 8'h00) begin
        // ---- All data: D0..D7 (Table 49-1, row 1) ----
        block_next = {`SYNC_DATA, xgmii_txd};

    end else if (c0 && d0 == `XGMII_START && xgmii_txc[7:1] == 7'h00) begin
        // ---- S0 D1 D2 D3 D4 D5 D6 D7 (start in lane 0) ----
        block_next = {`SYNC_CTRL, `BT_START_0,
                      d7, d6, d5, d4, d3, d2, d1};

    end else if (c0 && d0 == `XGMII_TERM && xgmii_txc[7:1] == 7'h7F) begin
        // ---- T0 C1 C2 C3 C4 C5 C6 C7 ----
        // Payload: BT(8) + 7×C(7) = 57, pad 7 bits → 64
        block_next = {`SYNC_CTRL, `BT_TERM_0,
                      ctrl_encode(d7), ctrl_encode(d6),
                      ctrl_encode(d5), ctrl_encode(d4),
                      ctrl_encode(d3), ctrl_encode(d2),
                      ctrl_encode(d1), 7'b0};

    end else if (!c0 && c1 && d1 == `XGMII_TERM && xgmii_txc[7:2] == 6'h3F) begin
        // ---- D0 T1 C2 C3 C4 C5 C6 C7 ----
        // Payload: BT(8) + 6×C(7) + D0(8) = 58, pad 6 bits → 64
        block_next = {`SYNC_CTRL, `BT_TERM_1,
                      ctrl_encode(d7), ctrl_encode(d6),
                      ctrl_encode(d5), ctrl_encode(d4),
                      ctrl_encode(d3), ctrl_encode(d2),
                      d0, 6'b0};

    end else if (xgmii_txc[1:0] == 2'b00 && c2 && d2 == `XGMII_TERM && xgmii_txc[7:3] == 5'h1F) begin
        // ---- D0 D1 T2 C3 C4 C5 C6 C7 ----
        // Payload: BT(8) + 5×C(7) + D1,D0(16) = 59, pad 5 bits → 64
        block_next = {`SYNC_CTRL, `BT_TERM_2,
                      ctrl_encode(d7), ctrl_encode(d6),
                      ctrl_encode(d5), ctrl_encode(d4),
                      ctrl_encode(d3),
                      d1, d0, 5'b0};

    end else if (xgmii_txc[2:0] == 3'b000 && c3 && d3 == `XGMII_TERM && xgmii_txc[7:4] == 4'hF) begin
        // ---- D0 D1 D2 T3 C4 C5 C6 C7 ----
        // Payload: BT(8) + 4×C(7) + D2,D1,D0(24) = 60, pad 4 bits → 64
        block_next = {`SYNC_CTRL, `BT_TERM_3,
                      ctrl_encode(d7), ctrl_encode(d6),
                      ctrl_encode(d5), ctrl_encode(d4),
                      d2, d1, d0, 4'b0};

    end else if (xgmii_txc[3:0] == 4'h0 && c4 && d4 == `XGMII_TERM && xgmii_txc[7:5] == 3'h7) begin
        // ---- D0 D1 D2 D3 T4 C5 C6 C7 ----
        // Payload: BT(8) + 3×C(7) + D3..D0(32) = 61, pad 3 bits → 64
        block_next = {`SYNC_CTRL, `BT_TERM_4,
                      ctrl_encode(d7), ctrl_encode(d6),
                      ctrl_encode(d5),
                      d3, d2, d1, d0, 3'b0};

    end else if (xgmii_txc[4:0] == 5'h00 && c5 && d5 == `XGMII_TERM && xgmii_txc[7:6] == 2'h3) begin
        // ---- D0 D1 D2 D3 D4 T5 C6 C7 ----
        // Payload: BT(8) + 2×C(7) + D4..D0(40) = 62, pad 2 bits → 64
        block_next = {`SYNC_CTRL, `BT_TERM_5,
                      ctrl_encode(d7), ctrl_encode(d6),
                      d4, d3, d2, d1, d0, 2'b0};

    end else if (xgmii_txc[5:0] == 6'h00 && c6 && d6 == `XGMII_TERM && c7) begin
        // ---- D0 D1 D2 D3 D4 D5 T6 C7 ----
        // Payload: BT(8) + 1×C(7) + D5..D0(48) = 63, pad 1 bit → 64
        block_next = {`SYNC_CTRL, `BT_TERM_6,
                      ctrl_encode(d7),
                      d5, d4, d3, d2, d1, d0, 1'b0};

    end else if (xgmii_txc[6:0] == 7'h00 && c7 && d7 == `XGMII_TERM) begin
        // ---- D0 D1 D2 D3 D4 D5 D6 T7 ----
        // Payload: BT(8) + 0×C + D6..D0(56) = 64, no pad
        block_next = {`SYNC_CTRL, `BT_TERM_7,
                      d6, d5, d4, d3, d2, d1, d0};

    end else if (xgmii_txc == 8'hF0 && c4 && d4 == `XGMII_START) begin
        // ---- D0 D1 D2 D3 S4 D5 D6 D7 (start in lane 4) ----
        block_next = {`SYNC_CTRL, `BT_START_4,
                      d7, d6, d5, 4'h0, d3, d2, d1, d0};

    end else if (c0 && (d0 == `XGMII_SEQ_OS || d0 == `XGMII_SIG_OS) &&
                 xgmii_txc[3:1] == 3'b000 &&
                 c4 && (d4 == `XGMII_SEQ_OS || d4 == `XGMII_SIG_OS) &&
                 xgmii_txc[7:5] == 3'b000) begin
        // ---- O0 D1 D2 D3 O4 D5 D6 D7 (two ordered sets) ----
        block_next = {`SYNC_CTRL, `BT_OS_START,
                      d7, d6, d5, ocode_encode(d4),
                      d3, d2, d1, ocode_encode(d0)};

    end else if (c0 && (d0 == `XGMII_SEQ_OS || d0 == `XGMII_SIG_OS) &&
                 xgmii_txc[3:1] == 3'b000 &&
                 c4 && d4 == `XGMII_START &&
                 xgmii_txc[7:5] == 3'b000) begin
        // ---- O0 D1 D2 D3 S4 D5 D6 D7 (ordered set + start) ----
        block_next = {`SYNC_CTRL, `BT_OS4_START,
                      d7, d6, d5, 4'h0, d3, d2, d1, ocode_encode(d0)};

    end else if (xgmii_txc == 8'hFF) begin
        // ---- All control: C0..C7 (idle/error — checked after specific patterns) ----
        block_next = {`SYNC_CTRL, `BT_CTRL_ALL,
                      ctrl_encode(d7), ctrl_encode(d6),
                      ctrl_encode(d5), ctrl_encode(d4),
                      ctrl_encode(d3), ctrl_encode(d2),
                      ctrl_encode(d1), ctrl_encode(d0)};

    end else begin
        // ---- Invalid/unrecognized: encode as all-error control block ----
        block_next = {`SYNC_CTRL, `BT_CTRL_ALL,
                      `CTRL_ERROR, `CTRL_ERROR, `CTRL_ERROR, `CTRL_ERROR,
                      `CTRL_ERROR, `CTRL_ERROR, `CTRL_ERROR, `CTRL_ERROR};
        error_next = 1'b1;
    end
end

// ---- Registered output (1 cycle latency) ----
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        tx_block       <= {`SYNC_CTRL, `BT_CTRL_ALL, 56'd0}; // Idle
        tx_block_valid <= 1'b0;
        encode_error   <= 1'b0;
    end else begin
        tx_block       <= block_next;
        tx_block_valid <= 1'b1;
        encode_error   <= error_next;
    end
end

endmodule
