// =============================================================================
// pcs_10g_top.v — IEEE 802.3 Clause 49 10GBASE-R PCS Top Level
// =============================================================================
// Ultra-low latency 10G Ethernet PCS for Xilinx UltraScale+ FPGA
//
// Architecture:
//   TX Path: XGMII → 64B/66B Encode → Scramble → TX Gearbox → SERDES TX
//   RX Path: SERDES RX → RX Gearbox → Block Sync → Descramble → 64B/66B Decode → XGMII
//
// TX Latency:  3-4 clock cycles (encoder:1 + scrambler:1 + gearbox:1-2)
// RX Latency:  6-7 clock cycles (gearbox:4-5 + descrambler:1 + decoder:1)
// Total:       ~10 clock cycles @ 644 MHz = ~15.5 ns (PCS core only)
//
// Clock: Single 644 MHz clock domain
//        16-bit SERDES data width → 16 × 644 MHz ≈ 10.3 Gbps line rate
//
// Interface to SERDES/GTH:
//   - 16-bit data width for 644 MHz operation
//   - Separate sync header for GTH 64B/66B gearbox bypass
//   - Compatible with GTH raw mode (no GTH internal encoder/decoder)
//
// Parameters:
//   INIT_IDLE_DISPATCH - Send idle on reset (recommended: 1)
// =============================================================================

`timescale 1ns / 1ps

module pcs_10g_top #(
    parameter INIT_IDLE_DISPATCH = 1  // Send idle blocks during reset
) (
    // ---- Clock and Reset ----
    input  wire        clk,           // 644 MHz
    input  wire        rst_n,         // Active-low synchronous reset

    // ---- XGMII TX Interface (from MAC) ----
    input  wire [63:0] xgmii_txd,     // TX data, 8 lanes × 8 bits
    input  wire [7:0]  xgmii_txc,     // TX control, 1 bit per lane

    // ---- XGMII RX Interface (to MAC) ----
    output wire [63:0] xgmii_rxd,     // RX data, 8 lanes × 8 bits
    output wire [7:0]  xgmii_rxc,     // RX control, 1 bit per lane

    // ---- SERDES/GTH TX Interface ----
    output wire [15:0] gth_txdata,    // To SERDES/GTH TXDATA[15:0]
    output wire [1:0]  gth_txheader,  // To GTH TXHEADER[1:0]
    output wire        gth_txdata_valid,

    // ---- SERDES/GTH RX Interface ----
    input  wire [15:0] gth_rxdata,    // From SERDES/GTH RXDATA[15:0]
    input  wire [1:0]  gth_rxheader,  // From GTH RXHEADER[1:0]
    input  wire        gth_rxdata_valid,
    input  wire        gth_rxheader_valid,

    // ---- GTH Control ----
    output wire        gth_txsequence_done, // unused, tie to 1
    input  wire        gth_rxgearboxslip,   // not used when we control slip

    // ---- Status ----
    output wire        block_lock,    // RX block lock achieved
    output wire        hi_ber,        // High BER detected
    output wire        pcs_status,    // Link status (lock & !hi_ber)
    output wire        rx_link_up,    // Debounced link up
    output wire        tx_encode_err, // TX encode error
    output wire        rx_decode_err, // RX decode error
    output wire [15:0] ber_count,     // BER error counter
    output wire [7:0]  errored_blocks,// Errored block counter

    // ---- MDIO-like status read ----
    input  wire        status_read,   // Clear latching-low status
    output wire        pcs_status_ll  // Latching-low PCS status
);

// =========================================================================
// TX PATH
// =========================================================================

// ---- Stage 1: 64B/66B Encoder (1 cycle) ----
wire [65:0] enc_block;
wire        enc_valid;
wire        enc_error;

pcs_10g_enc_64b66b u_encoder (
    .clk            (clk),
    .rst_n          (rst_n),
    .xgmii_txd      (xgmii_txd),
    .xgmii_txc      (xgmii_txc),
    .tx_block        (enc_block),
    .tx_block_valid  (enc_valid),
    .encode_error    (enc_error)
);

assign tx_encode_err = enc_error;

// ---- Stage 2: Scrambler (1 cycle) ----
wire [65:0] scr_block;
wire        scr_valid;

pcs_10g_scrambler u_scrambler (
    .clk              (clk),
    .rst_n            (rst_n),
    .tx_block_in       (enc_block),
    .tx_block_valid    (enc_valid),
    .tx_block_out      (scr_block),
    .tx_block_out_valid(scr_valid)
);

// ---- Stage 3: TX Gearbox (66→16, 1-4 cycles) ----
pcs_10g_tx_gearbox u_tx_gearbox (
    .clk              (clk),
    .rst_n            (rst_n),
    .tx_block          (scr_block),
    .tx_block_valid    (scr_valid),
    .tx_data           (gth_txdata),
    .tx_header         (gth_txheader),
    .tx_data_valid     (gth_txdata_valid),
    .tx_ready          (),
    .tx_sequence_done  (1'b1)
);

assign gth_txsequence_done = 1'b1;

// =========================================================================
// RX PATH
// =========================================================================

// ---- Stage 1: RX Gearbox (16→66, 4-5 cycles) ----
wire [65:0] rgbox_block;
wire        rgbox_valid;
wire        slip_cmd;

pcs_10g_rx_gearbox u_rx_gearbox (
    .clk              (clk),
    .rst_n            (rst_n),
    .rx_data           (gth_rxdata),
    .rx_header         (gth_rxheader),
    .rx_data_valid     (gth_rxdata_valid),
    .rx_header_valid   (gth_rxheader_valid),
    .rx_block          (rgbox_block),
    .rx_block_valid    (rgbox_valid),
    .slip              (slip_cmd)
);

// ---- Block Synchronization (operates on raw sync headers) ----
wire        blk_lock;
wire        blk_hi_ber;
wire [15:0] blk_sh_valid;
wire [15:0] blk_sh_invalid;

pcs_10g_block_sync u_block_sync (
    .clk              (clk),
    .rst_n            (rst_n),
    .rx_sync_header    (rgbox_block[65:64]),
    .rx_valid          (rgbox_valid),
    .block_lock        (blk_lock),
    .slip              (slip_cmd),
    .hi_ber            (blk_hi_ber),
    .sh_valid_cnt      (blk_sh_valid),
    .sh_invalid_cnt    (blk_sh_invalid)
);

assign block_lock = blk_lock;
assign hi_ber     = blk_hi_ber;

// ---- Stage 2: Descrambler (1 cycle) ----
// Only descramble when block lock is achieved
wire [65:0] dscr_block;
wire        dscr_valid;

pcs_10g_descrambler u_descrambler (
    .clk                (clk),
    .rst_n              (rst_n),
    .rx_block_in         (rgbox_block),
    .rx_block_valid      (rgbox_valid & blk_lock),
    .rx_block_out        (dscr_block),
    .rx_block_out_valid  (dscr_valid)
);

// ---- Stage 3: 64B/66B Decoder (1 cycle) ----
wire [63:0] dec_rxd;
wire [7:0]  dec_rxc;
wire        dec_error;
wire        dec_valid;

pcs_10g_dec_64b66b u_decoder (
    .clk              (clk),
    .rst_n            (rst_n),
    .rx_block          (dscr_block),
    .rx_block_valid    (dscr_valid),
    .xgmii_rxd         (dec_rxd),
    .xgmii_rxc         (dec_rxc),
    .decode_error      (dec_error),
    .rx_data_valid     (dec_valid)
);

assign xgmii_rxd   = dec_rxd;
assign xgmii_rxc   = dec_rxc;
assign rx_decode_err = dec_error;

// =========================================================================
// BER Monitor & Link Status
// =========================================================================

pcs_10g_ber_monitor u_ber_monitor (
    .clk                 (clk),
    .rst_n               (rst_n),
    .block_lock          (blk_lock),
    .hi_ber              (blk_hi_ber),
    .sh_invalid_cnt      (blk_sh_invalid),
    .rx_decode_error     (dec_error),
    .pcs_status          (pcs_status),
    .pcs_status_ll       (pcs_status_ll),
    .status_read         (status_read),
    .ber_count           (ber_count),
    .errored_block_count (errored_blocks),
    .rx_link_up          (rx_link_up)
);

endmodule
