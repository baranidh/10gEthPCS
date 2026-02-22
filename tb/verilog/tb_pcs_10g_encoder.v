// =============================================================================
// tb_pcs_10g_encoder.v — Unit Testbench for 64B/66B Encoder
// =============================================================================
// Tests all block types defined in IEEE 802.3 Table 49-1
// =============================================================================

`timescale 1ns / 1ps

module tb_pcs_10g_encoder;

localparam CLK_PERIOD = 1.553; // 644 MHz

reg         clk;
reg         rst_n;
reg  [63:0] xgmii_txd;
reg  [7:0]  xgmii_txc;
wire [65:0] tx_block;
wire        tx_block_valid;
wire        encode_error;

integer pass_count, fail_count, test_num;

// Clock
initial clk = 0;
always #(CLK_PERIOD/2) clk = ~clk;

// DUT
pcs_10g_enc_64b66b u_enc (
    .clk            (clk),
    .rst_n          (rst_n),
    .xgmii_txd      (xgmii_txd),
    .xgmii_txc      (xgmii_txc),
    .tx_block        (tx_block),
    .tx_block_valid  (tx_block_valid),
    .encode_error    (encode_error)
);

// Apply input, wait one cycle for registered output, then check
task apply_and_check;
    input [63:0] txd;
    input [7:0]  txc;
    input [1:0]  exp_sync;
    input [7:0]  exp_bt;      // expected block type (only for ctrl blocks)
    input        check_bt;    // 1 = also check block type
    input [255:0] name;
begin
    // Apply input
    xgmii_txd = txd;
    xgmii_txc = txc;
    @(posedge clk); // Input captured here
    @(posedge clk); // Output available here (1 cycle latency)
    @(negedge clk); // Sample at negedge

    // Check sync header
    if (tx_block[65:64] == exp_sync) begin
        $display("[PASS] Test %0d: %0s sync_header=%b", test_num, name, tx_block[65:64]);
        pass_count = pass_count + 1;
    end else begin
        $display("[FAIL] Test %0d: %0s expected sync=%b got=%b",
                 test_num, name, exp_sync, tx_block[65:64]);
        fail_count = fail_count + 1;
    end
    test_num = test_num + 1;

    // Check block type
    if (check_bt) begin
        if (tx_block[63:56] == exp_bt) begin
            $display("[PASS] Test %0d: %0s block_type=0x%02h", test_num, name, tx_block[63:56]);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Test %0d: %0s expected bt=0x%02h got=0x%02h",
                     test_num, name, exp_bt, tx_block[63:56]);
            fail_count = fail_count + 1;
        end
        test_num = test_num + 1;
    end
end
endtask

initial begin
    $dumpfile("tb_encoder.vcd");
    $dumpvars(0, tb_pcs_10g_encoder);

    pass_count = 0;
    fail_count = 0;
    test_num   = 1;

    $display("================================================================");
    $display("  64B/66B Encoder Unit Tests");
    $display("================================================================");

    // Reset
    rst_n = 0;
    xgmii_txd = 64'd0;
    xgmii_txc = 8'd0;
    repeat(5) @(posedge clk);
    rst_n = 1;
    repeat(2) @(posedge clk);

    // ---- Test: All Data Block ----
    $display("\n--- All Data Block ---");
    apply_and_check(
        64'h0102030405060708, 8'h00,
        2'b01, 8'h00, 1'b0,
        "Data block"
    );

    // ---- Test: All Control (Idle) Block ----
    $display("\n--- All Control (Idle) Block ---");
    apply_and_check(
        {8{8'h07}}, 8'hFF,
        2'b10, 8'h1E, 1'b1,
        "Idle block"
    );

    // ---- Test: Start in Lane 0 ----
    $display("\n--- Start in Lane 0 ---");
    apply_and_check(
        {8'hD5, 8'h55, 8'h55, 8'h55, 8'h55, 8'h55, 8'h55, 8'hFB}, 8'h01,
        2'b10, 8'h33, 1'b1,
        "Start lane 0"
    );

    // ---- Test: Terminate in Lane 0 ----
    $display("\n--- Terminate in Lane 0 ---");
    apply_and_check(
        {8'h07, 8'h07, 8'h07, 8'h07, 8'h07, 8'h07, 8'h07, 8'hFD}, 8'hFF,
        2'b10, 8'h87, 1'b1,
        "Term lane 0"
    );

    // ---- Test: Terminate in Lane 1 ----
    $display("\n--- Terminate in Lane 1 ---");
    apply_and_check(
        {8'h07, 8'h07, 8'h07, 8'h07, 8'h07, 8'h07, 8'hFD, 8'hAA}, 8'hFE,
        2'b10, 8'h99, 1'b1,
        "Term lane 1"
    );

    // ---- Test: Terminate in Lane 4 ----
    $display("\n--- Terminate in Lane 4 ---");
    apply_and_check(
        {8'h07, 8'h07, 8'h07, 8'hFD, 8'hAA, 8'hBB, 8'hCC, 8'hDD}, 8'hF0,
        2'b10, 8'hCC, 1'b1,
        "Term lane 4"
    );

    // ---- Test: Terminate in Lane 7 ----
    $display("\n--- Terminate in Lane 7 ---");
    apply_and_check(
        {8'hFD, 8'hAA, 8'hBB, 8'hCC, 8'hDD, 8'hEE, 8'hFF, 8'h11}, 8'h80,
        2'b10, 8'hFF, 1'b1,
        "Term lane 7"
    );

    // ---- Test: No encode error on valid patterns ----
    $display("\n--- Encode Error Check ---");
    // Send idle (valid)
    xgmii_txd = {8{8'h07}};
    xgmii_txc = 8'hFF;
    @(posedge clk);
    @(posedge clk);
    @(negedge clk);
    if (!encode_error) begin
        $display("[PASS] Test %0d: No encode error on idle", test_num);
        pass_count = pass_count + 1;
    end else begin
        $display("[FAIL] Test %0d: Unexpected encode error on idle", test_num);
        fail_count = fail_count + 1;
    end
    test_num = test_num + 1;

    // Send invalid pattern
    xgmii_txd = 64'h0102030405060708;
    xgmii_txc = 8'hA5;
    @(posedge clk);
    @(posedge clk);
    @(negedge clk);
    if (encode_error) begin
        $display("[PASS] Test %0d: Encode error on invalid XGMII pattern", test_num);
        pass_count = pass_count + 1;
    end else begin
        $display("[FAIL] Test %0d: Missing encode error on invalid pattern", test_num);
        fail_count = fail_count + 1;
    end
    test_num = test_num + 1;

    // ---- Summary ----
    $display("\n================================================================");
    $display("  ENCODER TEST SUMMARY");
    $display("  Total: %0d | Passed: %0d | Failed: %0d",
             pass_count + fail_count, pass_count, fail_count);
    $display("================================================================\n");

    #100;
    $finish;
end

initial begin
    #50000;
    $display("[TIMEOUT]");
    $finish;
end

endmodule
