// =============================================================================
// pcs_10g_params.vh — IEEE 802.3 Clause 49 10GBASE-R PCS Parameters
// =============================================================================
// All control character encodings per IEEE 802.3-2022 Table 49-1 through 49-4

`ifndef PCS_10G_PARAMS_VH
`define PCS_10G_PARAMS_VH

// ---- XGMII Control Characters (IEEE 802.3 Table 46-3) ----
localparam [7:0] XGMII_IDLE   = 8'h07;
localparam [7:0] XGMII_START  = 8'hFB;
localparam [7:0] XGMII_TERM   = 8'hFD;
localparam [7:0] XGMII_ERROR  = 8'hFE;
localparam [7:0] XGMII_SEQ_OS = 8'h9C;  // Sequence ordered set
localparam [7:0] XGMII_SIG_OS = 8'h5C;  // Signal ordered set

// ---- 66-bit Block Sync Headers (IEEE 802.3 Clause 49.2.4) ----
localparam [1:0] SYNC_DATA    = 2'b01;  // Data block
localparam [1:0] SYNC_CTRL    = 2'b10;  // Control block

// ---- Block Type Fields (IEEE 802.3 Table 49-1) ----
// Control block type encodings (bits [65:58] of 66-bit block after sync header)
localparam [7:0] BT_CTRL_ALL  = 8'h1E;  // C0 C1 C2 C3 C4 C5 C6 C7  (all control)
localparam [7:0] BT_OS_START  = 8'h2D;  // O0 D1 D2 D3 O4 D5 D6 D7  (2x ordered set with 4-bit O-codes)
localparam [7:0] BT_START_0   = 8'h33;  // S0 D1 D2 D3 D4 D5 D6 D7  (start in lane 0)
localparam [7:0] BT_OS4_START = 8'h66;  // O0 D1 D2 D3 S4 D5 D6 D7  (ordered set + start in lane 4)
localparam [7:0] BT_START_4   = 8'h78;  // D0 D1 D2 D3 S4 D5 D6 D7  (start in lane 4 — preceded by data)
localparam [7:0] BT_TERM_0    = 8'h87;  // T0 C1 C2 C3 C4 C5 C6 C7  (terminate lane 0)
localparam [7:0] BT_TERM_1    = 8'h99;  // D0 T1 C2 C3 C4 C5 C6 C7  (terminate lane 1)
localparam [7:0] BT_TERM_2    = 8'hAA;  // D0 D1 T2 C3 C4 C5 C6 C7  (terminate lane 2)
localparam [7:0] BT_TERM_3    = 8'hB4;  // D0 D1 D2 T3 C4 C5 C6 C7  (terminate lane 3)
localparam [7:0] BT_TERM_4    = 8'hCC;  // D0 D1 D2 D3 T4 C5 C6 C7  (terminate lane 4)
localparam [7:0] BT_TERM_5    = 8'hD2;  // D0 D1 D2 D3 D4 T5 C6 C7  (terminate lane 5)
localparam [7:0] BT_TERM_6    = 8'hE1;  // D0 D1 D2 D3 D4 D5 T6 C7  (terminate lane 6)
localparam [7:0] BT_TERM_7    = 8'hFF;  // D0 D1 D2 D3 D4 D5 D6 T7  (terminate lane 7)

// ---- 7-bit Control Character Encodings (IEEE 802.3 Table 49-1) ----
localparam [6:0] CTRL_IDLE    = 7'h00;
localparam [6:0] CTRL_LPI     = 7'h06;  // Low Power Idle
localparam [6:0] CTRL_ERROR   = 7'h1E;
localparam [6:0] CTRL_RES_0   = 7'h2D;  // Reserved 0
localparam [6:0] CTRL_RES_1   = 7'h33;  // Reserved 1
localparam [6:0] CTRL_RES_2   = 7'h4B;  // Reserved 2
localparam [6:0] CTRL_RES_3   = 7'h55;  // Reserved 3
localparam [6:0] CTRL_RES_4   = 7'h66;  // Reserved 4

// ---- Ordered Set O-codes (4-bit, IEEE 802.3 Table 49-1) ----
localparam [3:0] OCODE_SEQ    = 4'h0;   // Sequence ordered set
localparam [3:0] OCODE_SIG    = 4'hF;   // Signal ordered set

// ---- Scrambler Polynomial (IEEE 802.3 Clause 49.2.6) ----
// G(x) = 1 + x^39 + x^58
localparam SCRAMBLER_POLY_TAP1 = 38; // x^39 (0-indexed)
localparam SCRAMBLER_POLY_TAP2 = 57; // x^58 (0-indexed)
localparam SCRAMBLER_STATE_BITS = 58;

// ---- Block Lock State Machine Parameters (IEEE 802.3 Clause 49.2.9) ----
localparam BLOCK_LOCK_SH_CNT_N   = 64;   // sh_valid_cnt threshold
localparam BLOCK_LOCK_SH_INVALID = 1;    // sh_invalid_cnt threshold for slip
localparam BER_TEST_SH_PERIOD    = 16'd8191; // ~8192 block test window
localparam BER_BAD_SH_THRESHOLD  = 6'd16;   // BER too high if >=16 bad in window

// ---- Link Status Timers ----
localparam HI_BER_TIMER_BITS     = 22;   // For 125us timer at 644 MHz

`endif
