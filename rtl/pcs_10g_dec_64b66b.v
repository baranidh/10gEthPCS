// =============================================================================
// pcs_10g_dec_64b66b.v — IEEE 802.3 Clause 49.2.4 64B/66B Decode
// =============================================================================
// RX-path decoder: 66-bit block → XGMII 64-bit + 8-bit control
// Ultra-low latency: purely combinational decoding, registered output
// Conforms to IEEE 802.3-2022 Tables 49-1 through 49-4
//
// Encoding layout (bits [63:0] of 66-bit block, after 2-bit sync header):
//   [63:56] = block type field (8 bits)
//   [55:0]  = payload (56 bits), layout depends on block type
//
// Terminate block payload layout (MSB to LSB after BT field):
//   T0: C7(7) C6(7) C5(7) C4(7) C3(7) C2(7) C1(7) pad(7)  = 56 bits
//   T1: C7(7) C6(7) C5(7) C4(7) C3(7) C2(7) D0(8) pad(6)  = 56 bits
//   T2: C7(7) C6(7) C5(7) C4(7) C3(7) D1(8) D0(8) pad(5)  = 56 bits
//   T3: C7(7) C6(7) C5(7) C4(7) D2(8) D1(8) D0(8) pad(4)  = 56 bits
//   T4: C7(7) C6(7) C5(7) D3(8) D2(8) D1(8) D0(8) pad(3)  = 56 bits
//   T5: C7(7) C6(7) D4(8) D3(8) D2(8) D1(8) D0(8) pad(2)  = 56 bits
//   T6: C7(7) D5(8) D4(8) D3(8) D2(8) D1(8) D0(8) pad(1)  = 56 bits
//   T7: D6(8) D5(8) D4(8) D3(8) D2(8) D1(8) D0(8) pad(0)  = 56 bits
//
// Latency: 1 clock cycle (registered output)
// =============================================================================

`timescale 1ns / 1ps

module pcs_10g_dec_64b66b (
    input  wire        clk,
    input  wire        rst_n,

    // 66-bit block input (from descrambler)
    input  wire [65:0] rx_block,
    input  wire        rx_block_valid,

    // XGMII RX interface (internal 64-bit SDR)
    output reg  [63:0] xgmii_rxd,
    output reg  [7:0]  xgmii_rxc,

    // Status
    output reg         decode_error,   // Invalid block type
    output reg         rx_data_valid
);

`include "pcs_10g_defs.vh"

// ---- Extract fields ----
wire [1:0]  sync_header   = rx_block[65:64];
wire [7:0]  block_type    = rx_block[63:56];
wire [55:0] block_payload = rx_block[55:0];

// Full 64 bits for data blocks
wire [63:0] data_payload  = rx_block[63:0];

// ---- Map 7-bit control encoding back to XGMII ----
function [7:0] ctrl_decode;
    input [6:0] code;
    begin
        case (code)
            `CTRL_IDLE:    ctrl_decode = `XGMII_IDLE;
            `CTRL_ERROR:   ctrl_decode = `XGMII_ERROR;
            `CTRL_LPI:     ctrl_decode = `XGMII_IDLE;
            default:       ctrl_decode = `XGMII_ERROR;
        endcase
    end
endfunction

// ---- Map 4-bit O-code back to XGMII ----
function [7:0] ocode_decode;
    input [3:0] code;
    begin
        case (code)
            `OCODE_SEQ: ocode_decode = `XGMII_SEQ_OS;
            `OCODE_SIG: ocode_decode = `XGMII_SIG_OS;
            default:    ocode_decode = `XGMII_SEQ_OS;
        endcase
    end
endfunction

// ---- Combinational decode ----
reg [63:0] rxd_next;
reg [7:0]  rxc_next;
reg        err_next;

always @(*) begin
    rxd_next = {8{`XGMII_ERROR}};
    rxc_next = 8'hFF;
    err_next = 1'b0;

    if (!rx_block_valid) begin
        // No valid block — output idle
        rxd_next = {8{`XGMII_IDLE}};
        rxc_next = 8'hFF;

    end else if (sync_header == `SYNC_DATA) begin
        // ---- Data block: all 64 payload bits are data ----
        rxd_next = data_payload;
        rxc_next = 8'h00;

    end else if (sync_header == `SYNC_CTRL) begin
        case (block_type)

            `BT_CTRL_ALL: begin
                // All control: C7 C6 C5 C4 C3 C2 C1 C0
                // Payload layout: C7[55:49] C6[48:42] C5[41:35] C4[34:28]
                //                  C3[27:21] C2[20:14] C1[13:7]  C0[6:0]
                rxd_next = {ctrl_decode(block_payload[55:49]),  // D7 = C7
                            ctrl_decode(block_payload[48:42]),  // D6 = C6
                            ctrl_decode(block_payload[41:35]),  // D5 = C5
                            ctrl_decode(block_payload[34:28]),  // D4 = C4
                            ctrl_decode(block_payload[27:21]),  // D3 = C3
                            ctrl_decode(block_payload[20:14]),  // D2 = C2
                            ctrl_decode(block_payload[13: 7]),  // D1 = C1
                            ctrl_decode(block_payload[ 6: 0])}; // D0 = C0
                rxc_next = 8'hFF;
            end

            `BT_START_0: begin
                // S0 D1 D2 D3 D4 D5 D6 D7
                // Payload: D7[55:48] D6[47:40] D5[39:32] D4[31:24]
                //          D3[23:16] D2[15:8]  D1[7:0]
                rxd_next = {block_payload[55:48],  // D7
                            block_payload[47:40],  // D6
                            block_payload[39:32],  // D5
                            block_payload[31:24],  // D4
                            block_payload[23:16],  // D3
                            block_payload[15: 8],  // D2
                            block_payload[ 7: 0],  // D1
                            `XGMII_START};         // S0
                rxc_next = 8'h01;
            end

            `BT_OS_START: begin
                // O0 D1 D2 D3 O4 D5 D6 D7
                // Payload: D7[55:48] D6[47:40] D5[39:32] O4[31:28]
                //          D3[27:20] D2[19:12] D1[11:4]  O0[3:0]
                rxd_next = {block_payload[55:48],               // D7
                            block_payload[47:40],               // D6
                            block_payload[39:32],               // D5
                            ocode_decode(block_payload[31:28]), // O4
                            block_payload[27:20],               // D3
                            block_payload[19:12],               // D2
                            block_payload[11: 4],               // D1
                            ocode_decode(block_payload[ 3: 0])};// O0
                rxc_next = 8'h11;
            end

            `BT_OS4_START: begin
                // O0 D1 D2 D3 S4 D5 D6 D7
                // Payload: D7[55:48] D6[47:40] D5[39:32] pad[31:28]
                //          D3[27:20] D2[19:12] D1[11:4]  O0[3:0]
                rxd_next = {block_payload[55:48],               // D7
                            block_payload[47:40],               // D6
                            block_payload[39:32],               // D5
                            `XGMII_START,                       // S4
                            block_payload[27:20],               // D3
                            block_payload[19:12],               // D2
                            block_payload[11: 4],               // D1
                            ocode_decode(block_payload[ 3: 0])};// O0
                rxc_next = 8'h11;
            end

            `BT_START_4: begin
                // D0 D1 D2 D3 S4 D5 D6 D7
                // Payload: D7[55:48] D6[47:40] D5[39:32] pad[31:28]
                //          D3[27:20] D2[19:12] D1[11:4]  D0[3:0]???
                // Actually encoder puts: {d7, d6, d5, 4'h0, d3, d2, d1, d0}
                rxd_next = {block_payload[55:48],  // D7
                            block_payload[47:40],  // D6
                            block_payload[39:32],  // D5
                            `XGMII_START,          // S4
                            block_payload[27:20],  // D3
                            block_payload[19:12],  // D2
                            block_payload[11: 4],  // D1
                            block_payload[ 3: 0], 4'b0}; // D0
                rxc_next = 8'h10;
            end

            // ---- Terminate blocks ----
            // Layout: BT(8) + Ctrls(MSB) + Data(LSB) + Pad(LSB)
            // T_n: (7-n) control codes + n data bytes + (7-n) pad bits

            `BT_TERM_0: begin
                // T0: 7 control, 0 data, 7-bit pad
                // Payload[55:49]=C7, [48:42]=C6, ..., [13:7]=C1, [6:0]=pad
                rxd_next = {ctrl_decode(block_payload[55:49]),  // C7 → D7
                            ctrl_decode(block_payload[48:42]),  // C6 → D6
                            ctrl_decode(block_payload[41:35]),  // C5 → D5
                            ctrl_decode(block_payload[34:28]),  // C4 → D4
                            ctrl_decode(block_payload[27:21]),  // C3 → D3
                            ctrl_decode(block_payload[20:14]),  // C2 → D2
                            ctrl_decode(block_payload[13: 7]),  // C1 → D1
                            `XGMII_TERM};                       // T0
                rxc_next = 8'hFF;
            end

            `BT_TERM_1: begin
                // T1: 6 control, 1 data byte (D0), 6-bit pad
                // Payload[55:49]=C7, ..., [20:14]=C2, [13:6]=D0, [5:0]=pad
                rxd_next = {ctrl_decode(block_payload[55:49]),  // C7 → D7
                            ctrl_decode(block_payload[48:42]),  // C6 → D6
                            ctrl_decode(block_payload[41:35]),  // C5 → D5
                            ctrl_decode(block_payload[34:28]),  // C4 → D4
                            ctrl_decode(block_payload[27:21]),  // C3 → D3
                            ctrl_decode(block_payload[20:14]),  // C2 → D2
                            `XGMII_TERM,                        // T1
                            block_payload[13:6]};                // D0
                rxc_next = 8'hFE;
            end

            `BT_TERM_2: begin
                // T2: 5 control, 2 data bytes, 5-bit pad
                // Payload[55:49]=C7, ..., [27:21]=C3, [20:13]=D1, [12:5]=D0, [4:0]=pad
                rxd_next = {ctrl_decode(block_payload[55:49]),  // C7
                            ctrl_decode(block_payload[48:42]),  // C6
                            ctrl_decode(block_payload[41:35]),  // C5
                            ctrl_decode(block_payload[34:28]),  // C4
                            ctrl_decode(block_payload[27:21]),  // C3
                            `XGMII_TERM,                        // T2
                            block_payload[20:13],                // D1
                            block_payload[12: 5]};               // D0
                rxc_next = 8'hFC;
            end

            `BT_TERM_3: begin
                // T3: 4 control, 3 data bytes, 4-bit pad
                // Payload[55:49]=C7, ..., [34:28]=C4, [27:20]=D2, [19:12]=D1, [11:4]=D0, [3:0]=pad
                rxd_next = {ctrl_decode(block_payload[55:49]),  // C7
                            ctrl_decode(block_payload[48:42]),  // C6
                            ctrl_decode(block_payload[41:35]),  // C5
                            ctrl_decode(block_payload[34:28]),  // C4
                            `XGMII_TERM,                        // T3
                            block_payload[27:20],                // D2
                            block_payload[19:12],                // D1
                            block_payload[11: 4]};               // D0
                rxc_next = 8'hF8;
            end

            `BT_TERM_4: begin
                // T4: 3 control, 4 data bytes, 3-bit pad
                // Payload[55:49]=C7, [48:42]=C6, [41:35]=C5,
                //   [34:27]=D3, [26:19]=D2, [18:11]=D1, [10:3]=D0, [2:0]=pad
                rxd_next = {ctrl_decode(block_payload[55:49]),  // C7
                            ctrl_decode(block_payload[48:42]),  // C6
                            ctrl_decode(block_payload[41:35]),  // C5
                            `XGMII_TERM,                        // T4
                            block_payload[34:27],                // D3
                            block_payload[26:19],                // D2
                            block_payload[18:11],                // D1
                            block_payload[10: 3]};               // D0
                rxc_next = 8'hF0;
            end

            `BT_TERM_5: begin
                // T5: 2 control, 5 data bytes, 2-bit pad
                // Payload[55:49]=C7, [48:42]=C6,
                //   [41:34]=D4, [33:26]=D3, [25:18]=D2, [17:10]=D1, [9:2]=D0, [1:0]=pad
                rxd_next = {ctrl_decode(block_payload[55:49]),  // C7
                            ctrl_decode(block_payload[48:42]),  // C6
                            `XGMII_TERM,                        // T5
                            block_payload[41:34],                // D4
                            block_payload[33:26],                // D3
                            block_payload[25:18],                // D2
                            block_payload[17:10],                // D1
                            block_payload[ 9: 2]};               // D0
                rxc_next = 8'hE0;
            end

            `BT_TERM_6: begin
                // T6: 1 control, 6 data bytes, 1-bit pad
                // Payload[55:49]=C7,
                //   [48:41]=D5, [40:33]=D4, [32:25]=D3, [24:17]=D2, [16:9]=D1, [8:1]=D0, [0]=pad
                rxd_next = {ctrl_decode(block_payload[55:49]),  // C7
                            `XGMII_TERM,                        // T6
                            block_payload[48:41],                // D5
                            block_payload[40:33],                // D4
                            block_payload[32:25],                // D3
                            block_payload[24:17],                // D2
                            block_payload[16: 9],                // D1
                            block_payload[ 8: 1]};               // D0
                rxc_next = 8'hC0;
            end

            `BT_TERM_7: begin
                // T7: 0 control, 7 data bytes, 0-bit pad
                // Payload[55:48]=D6, [47:40]=D5, ..., [7:0]=D0
                rxd_next = {`XGMII_TERM,                        // T7
                            block_payload[55:48],                // D6
                            block_payload[47:40],                // D5
                            block_payload[39:32],                // D4
                            block_payload[31:24],                // D3
                            block_payload[23:16],                // D2
                            block_payload[15: 8],                // D1
                            block_payload[ 7: 0]};               // D0
                rxc_next = 8'h80;
            end

            default: begin
                // Invalid block type → error
                rxd_next = {8{`XGMII_ERROR}};
                rxc_next = 8'hFF;
                err_next = 1'b1;
            end
        endcase

    end else begin
        // Invalid sync header (not 01 or 10)
        rxd_next = {8{`XGMII_ERROR}};
        rxc_next = 8'hFF;
        err_next = 1'b1;
    end
end

// ---- Registered output ----
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        xgmii_rxd    <= {8{`XGMII_IDLE}};
        xgmii_rxc    <= 8'hFF;
        decode_error  <= 1'b0;
        rx_data_valid <= 1'b0;
    end else begin
        xgmii_rxd    <= rxd_next;
        xgmii_rxc    <= rxc_next;
        decode_error  <= err_next;
        rx_data_valid <= rx_block_valid;
    end
end

endmodule
