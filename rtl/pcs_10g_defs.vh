// =============================================================================
// pcs_10g_defs.vh — IEEE 802.3 Clause 49 10GBASE-R PCS Defines
// =============================================================================
// Uses `define macros for compatibility with Icarus Verilog functions

`ifndef PCS_10G_DEFS_VH
`define PCS_10G_DEFS_VH

// ---- XGMII Control Characters (IEEE 802.3 Table 46-3) ----
`define XGMII_IDLE   8'h07
`define XGMII_START  8'hFB
`define XGMII_TERM   8'hFD
`define XGMII_ERROR  8'hFE
`define XGMII_SEQ_OS 8'h9C
`define XGMII_SIG_OS 8'h5C

// ---- 66-bit Block Sync Headers (IEEE 802.3 Clause 49.2.4) ----
`define SYNC_DATA    2'b01
`define SYNC_CTRL    2'b10

// ---- Block Type Fields (IEEE 802.3 Table 49-1) ----
`define BT_CTRL_ALL  8'h1E
`define BT_OS_START  8'h2D
`define BT_START_0   8'h33
`define BT_OS4_START 8'h66
`define BT_START_4   8'h78
`define BT_TERM_0    8'h87
`define BT_TERM_1    8'h99
`define BT_TERM_2    8'hAA
`define BT_TERM_3    8'hB4
`define BT_TERM_4    8'hCC
`define BT_TERM_5    8'hD2
`define BT_TERM_6    8'hE1
`define BT_TERM_7    8'hFF

// ---- 7-bit Control Character Encodings (IEEE 802.3 Table 49-1) ----
`define CTRL_IDLE    7'h00
`define CTRL_LPI     7'h06
`define CTRL_ERROR   7'h1E
`define CTRL_RES_0   7'h2D
`define CTRL_RES_1   7'h33
`define CTRL_RES_2   7'h4B
`define CTRL_RES_3   7'h55
`define CTRL_RES_4   7'h66

// ---- Ordered Set O-codes (4-bit, IEEE 802.3 Table 49-1) ----
`define OCODE_SEQ    4'h0
`define OCODE_SIG    4'hF

// ---- Block Lock Parameters (IEEE 802.3 Clause 49.2.9) ----
`define BLOCK_LOCK_SH_CNT_N   64
`define BLOCK_LOCK_SH_INVALID 1
`define BER_TEST_SH_PERIOD    13'd8191
`define BER_BAD_SH_THRESHOLD  6'd16

`endif
