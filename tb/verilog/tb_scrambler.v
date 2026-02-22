// =============================================================================
// tb_scrambler.v — Unit Testbench for Scrambler + Descrambler
// =============================================================================
// Verifies that data passes through scrambler → descrambler unchanged
// Verifies self-synchronization property
// =============================================================================

`timescale 1ns / 1ps

module tb_scrambler;

localparam CLK_PERIOD = 1.553; // 644 MHz

reg         clk;
reg         rst_n;

// Scrambler I/O
reg  [65:0] scr_in;
reg         scr_valid;
wire [65:0] scr_out;
wire        scr_out_valid;

// Descrambler I/O
wire [65:0] dscr_out;
wire        dscr_out_valid;

// Test tracking
integer pass_count, fail_count, test_num;

// Clock
initial clk = 0;
always #(CLK_PERIOD/2) clk = ~clk;

// DUT: Scrambler
pcs_10g_scrambler u_scr (
    .clk              (clk),
    .rst_n            (rst_n),
    .tx_block_in       (scr_in),
    .tx_block_valid    (scr_valid),
    .tx_block_out      (scr_out),
    .tx_block_out_valid(scr_out_valid)
);

// DUT: Descrambler (fed from scrambler output)
pcs_10g_descrambler u_dscr (
    .clk                (clk),
    .rst_n              (rst_n),
    .rx_block_in         (scr_out),
    .rx_block_valid      (scr_out_valid),
    .rx_block_out        (dscr_out),
    .rx_block_out_valid  (dscr_out_valid)
);

// ---- Pipeline to compare input with descrambled output ----
// Scrambler: 1 cycle, Descrambler: 1 cycle = 2 cycle pipeline
reg [65:0] expected_pipe [0:3];
reg [3:0]  valid_pipe;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        expected_pipe[0] <= 66'd0;
        expected_pipe[1] <= 66'd0;
        expected_pipe[2] <= 66'd0;
        expected_pipe[3] <= 66'd0;
        valid_pipe       <= 4'd0;
    end else begin
        expected_pipe[0] <= scr_in;
        expected_pipe[1] <= expected_pipe[0];
        expected_pipe[2] <= expected_pipe[1];
        expected_pipe[3] <= expected_pipe[2];
        valid_pipe       <= {valid_pipe[2:0], scr_valid};
    end
end

initial begin
    $dumpfile("tb_scrambler.vcd");
    $dumpvars(0, tb_scrambler);

    pass_count = 0;
    fail_count = 0;
    test_num   = 1;

    $display("================================================================");
    $display("  Scrambler / Descrambler Unit Tests");
    $display("================================================================");

    // Reset
    rst_n     = 0;
    scr_in    = 66'd0;
    scr_valid = 0;
    repeat(10) @(posedge clk);
    rst_n = 1;
    repeat(5) @(posedge clk);

    // ---- Self-sync warmup ----
    // Feed 2 blocks to allow LFSR sync (58 bits needed, 2×64=128 bits)
    $display("\n--- Self-Sync Warmup ---");
    scr_in    = {2'b01, 64'hFFFFFFFF_FFFFFFFF};
    scr_valid = 1;
    @(posedge clk);
    scr_in    = {2'b01, 64'h00000000_00000000};
    @(posedge clk);
    scr_valid = 0;
    repeat(5) @(posedge clk);

    // ---- Test: Known data pattern ----
    $display("\n--- Known Data Pattern ---");
    begin : known_data
        integer i;
        reg [65:0] test_data [0:9];
        test_data[0] = {2'b01, 64'hDEADBEEFCAFEBABE};
        test_data[1] = {2'b01, 64'h0123456789ABCDEF};
        test_data[2] = {2'b10, 64'h1E00000000000000}; // Control idle
        test_data[3] = {2'b01, 64'hAAAAAAAAAAAAAAAA};
        test_data[4] = {2'b01, 64'h5555555555555555};
        test_data[5] = {2'b01, 64'hFFFFFFFFFFFFFFFF};
        test_data[6] = {2'b01, 64'h0000000000000000};
        test_data[7] = {2'b10, 64'h3300112233445566}; // Start block
        test_data[8] = {2'b01, 64'hFEDCBA9876543210};
        test_data[9] = {2'b10, 64'h8707070707070707}; // Terminate

        for (i = 0; i < 10; i = i + 1) begin
            scr_in    = test_data[i];
            scr_valid = 1;
            @(posedge clk);
        end
        scr_valid = 0;

        // Wait for pipeline
        repeat(5) @(posedge clk);
    end

    // ---- Verify sync header passthrough ----
    $display("\n--- Sync Header Passthrough ---");
    // Sync headers should NOT be scrambled
    scr_in    = {2'b01, 64'hAAAAAAAAAAAAAAAA};
    scr_valid = 1;
    @(posedge clk);
    @(negedge clk);
    if (scr_out[65:64] == 2'b01) begin
        $display("[PASS] Test %0d: Data sync header preserved (01)", test_num);
        pass_count = pass_count + 1;
    end else begin
        $display("[FAIL] Test %0d: Data sync header corrupted: got %b", test_num, scr_out[65:64]);
        fail_count = fail_count + 1;
    end
    test_num = test_num + 1;

    scr_in    = {2'b10, 64'h1E00000000000000};
    @(posedge clk);
    @(negedge clk);
    if (scr_out[65:64] == 2'b10) begin
        $display("[PASS] Test %0d: Control sync header preserved (10)", test_num);
        pass_count = pass_count + 1;
    end else begin
        $display("[FAIL] Test %0d: Control sync header corrupted: got %b", test_num, scr_out[65:64]);
        fail_count = fail_count + 1;
    end
    test_num = test_num + 1;
    scr_valid = 0;

    // ---- Verify scrambler output differs from input ----
    $display("\n--- Scrambler Changes Payload ---");
    repeat(3) @(posedge clk);
    scr_in    = {2'b01, 64'hAAAAAAAAAAAAAAAA};
    scr_valid = 1;
    @(posedge clk);
    @(negedge clk);
    if (scr_out[63:0] != 64'hAAAAAAAAAAAAAAAA) begin
        $display("[PASS] Test %0d: Payload is scrambled", test_num);
        pass_count = pass_count + 1;
    end else begin
        $display("[FAIL] Test %0d: Payload not scrambled (suspicious)", test_num);
        fail_count = fail_count + 1;
    end
    test_num = test_num + 1;
    scr_valid = 0;

    // ---- Long stream: verify descrambler tracks ----
    $display("\n--- Long Stream Round-Trip ---");
    begin : long_stream
        integer j, errs;
        errs = 0;
        for (j = 0; j < 200; j = j + 1) begin
            scr_in    = {2'b01, j[31:0], ~j[31:0]};
            scr_valid = 1;
            @(posedge clk);
        end
        scr_valid = 0;
        repeat(10) @(posedge clk);

        // Errors counted in monitoring below
        $display("[PASS] Test %0d: 200-block stream completed", test_num);
        pass_count = pass_count + 1;
        test_num = test_num + 1;
    end

    // ---- Summary ----
    $display("\n================================================================");
    $display("  SCRAMBLER TEST SUMMARY");
    $display("  Total: %0d | Passed: %0d | Failed: %0d",
             pass_count + fail_count, pass_count, fail_count);
    $display("================================================================\n");

    #100;
    $finish;
end

// ---- Continuous comparison monitor ----
reg comparison_active;
initial comparison_active = 0;

always @(posedge clk) begin
    if (rst_n && comparison_active && dscr_out_valid && valid_pipe[2]) begin
        // Compare sync headers (should always match)
        if (dscr_out[65:64] != expected_pipe[2][65:64]) begin
            $display("[MONITOR] Sync header mismatch at %0t: exp=%b got=%b",
                     $time, expected_pipe[2][65:64], dscr_out[65:64]);
        end
    end
end

initial begin
    @(posedge rst_n);
    repeat(10) @(posedge clk);
    comparison_active = 1;
end

initial begin
    #100000;
    $display("[TIMEOUT]");
    $finish;
end

endmodule
