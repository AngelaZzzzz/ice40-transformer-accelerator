`timescale 1ns/1ps

////////////////////////////////////////////////////////////////////////////////
// mac_lane_tb
//   Testbench for mac_lane
////////////////////////////////////////////////////////////////////////////////

// Self-checking. A cycle-exact model predicts acc after every clock edge
// from the input history, using the documented latency: inputs driven
// before edge k reach acc after edge k + 3, and rst at edge k clears acc
// and discards the inputs from the three cycles still in flight. acc is
// compared every cycle, so a wrong latency, a lost or doubled term, or a
// failure to hold all show up as mismatches.
//
// Phases:
//   1. reset with random inputs, which must be ignored;
//   2. one product followed by idle cycles (latency and hold);
//   3. every pair of extreme int16 values, each starting a new sum;
//   4. the worst-case MATVEC sums: 256 terms of -32768 x -128 and
//      -32768 x 127 (magnitude 2^30, spec section 2);
//   5. 300 back-to-back dot products of int16 x int8 with random lengths
//      1-256, random en gaps, and clr toggling while en is low;
//   6. lane-0 style traffic: full-range int16 x int16, random en and clr,
//      and occasional mid-run resets.
//
// Prints "TEST PASSED" or "TEST FAILED" on the last line.

module mac_lane_tb();

    logic               clk = 1'b0;
    logic               rst;
    logic               en;
    logic               clr;
    logic signed [15:0] a;
    logic signed [15:0] b;
    logic signed [31:0] acc;

    mac_lane dut(.*);

    always #10 clk = ~clk;

    // Input history, indexed by the cycle in which it was driven
    localparam int NMAX = 1 << 17;

    logic               h_rst [NMAX];
    logic               h_en  [NMAX];
    logic               h_clr [NMAX];
    logic signed [15:0] h_a   [NMAX];
    logic signed [15:0] h_b   [NMAX];

    logic signed [31:0] exp_acc = 'x;
    int                 m       = 0;   // cycle being driven
    int                 n_chk   = 0;
    int                 n_err   = 0;

    // Cycles before the start count as reset
    function automatic logic rst_at(input int i);
        return (i < 0) ? 1'b1 : h_rst[i];
    endfunction

    // One cycle: update the model for the edge that just passed, compare,
    // then drive the next inputs at the falling edge
    task automatic step(input logic               r,
                        input logic               e,
                        input logic               c,
                        input logic signed [15:0] av,
                        input logic signed [15:0] bv);
        logic signed [31:0] p;
        @(negedge clk);
        if (m >= 1) begin
            if (rst_at(m - 1))
                exp_acc = '0;
            else if (!rst_at(m - 2) && !rst_at(m - 3) && h_en[m - 3]) begin
                p       = 32'(h_a[m - 3]) * 32'(h_b[m - 3]);
                exp_acc = (h_clr[m - 3] ? 32'sd0 : exp_acc) + p;
            end
            n_chk++;
            if (acc !== exp_acc) begin
                n_err++;
                if (n_err <= 20)
                    $display("MISMATCH cycle %0d: acc=%0d exp=%0d",
                             m, acc, exp_acc);
            end
        end
        rst = r;
        en  = e;
        clr = c;
        a   = av;
        b   = bv;
        h_rst[m] = r;
        h_en[m]  = e;
        h_clr[m] = c;
        h_a[m]   = av;
        h_b[m]   = bv;
        m++;
    endtask

    task automatic idle();
        step(1'b0, 1'b0, 1'($urandom), $urandom, $urandom);
    endtask

    // A random int8 weight, sign-extended as matvec_engine will do
    function automatic logic signed [15:0] w8();
        logic signed [7:0] w;
        w = $urandom;
        return 16'(w);
    endfunction

    // Test sequence
    logic signed [15:0] ext [6];
    int len;

    initial begin
        ext[0] = -16'sd32768;
        ext[1] = -16'sd32767;
        ext[2] = -16'sd1;
        ext[3] = 16'sd0;
        ext[4] = 16'sd1;
        ext[5] = 16'sd32767;

        // 1. Reset with random inputs
        repeat (4) step(1'b1, 1'($urandom), 1'($urandom), $urandom,
                        $urandom);

        // 2. One product, then idle
        step(1'b0, 1'b1, 1'b1, 16'sd3, -16'sd5);
        repeat (6) idle();

        // 3. Every pair of extreme values, each a new sum
        for (int i = 0; i < 6; i++)
            for (int j = 0; j < 6; j++)
                step(1'b0, 1'b1, 1'b1, ext[i], ext[j]);
        repeat (4) idle();

        // 4. Worst-case MATVEC sums
        for (int t = 0; t < 256; t++)
            step(1'b0, 1'b1, t == 0, -16'sd32768, -16'sd128);
        for (int t = 0; t < 256; t++)
            step(1'b0, 1'b1, t == 0, -16'sd32768, 16'sd127);
        repeat (4) idle();

        // 5. Back-to-back dot products with en gaps
        repeat (300) begin
            len = $urandom_range(256, 1);
            for (int t = 0; t < len; t++) begin
                if ($urandom_range(9) == 0) idle();
                step(1'b0, 1'b1, t == 0, $urandom, w8());
            end
        end
        repeat (4) idle();

        // 6. Lane-0 style traffic with occasional resets
        repeat (20000)
            step($urandom_range(99) == 0, $urandom_range(7) != 0,
                 $urandom_range(7) == 0, $urandom, $urandom);

        repeat (5) idle();

        $display("mac_lane: %0d cycles checked, %0d errors", n_chk, n_err);
        if (n_err == 0) $display("TEST PASSED");
        else            $display("TEST FAILED");
        $finish;
    end

endmodule
