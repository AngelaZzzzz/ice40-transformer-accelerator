`timescale 1ns/1ps

////////////////////////////////////////////////////////////////////////////////
// vga_pll_tb
//   Testbench for vga_pll
////////////////////////////////////////////////////////////////////////////////

// Self-checking, with sim/models/PLL_B.sv. Checks that:
//   1. lock and pix_clk stay low while rst_n is low;
//   2. lock rises after rst_n, and pix_clk then runs at 25.000 MHz from a
//      48 MHz reference (period 40.000 ns, within 0.1%);
//   3. pulling rst_n low drops lock and stops pix_clk, and the PLL locks
//      again afterwards;
//   4. with the reference 10% slow (43.2 MHz, the HSOSC tolerance),
//      pix_clk scales with it to 22.5 MHz.
//
// Prints "TEST PASSED" or "TEST FAILED" on the last line.

module vga_pll_tb();

    logic    ref_clk = 1'b0;
    logic    rst_n   = 1'b0;
    logic    pix_clk;
    logic    lock;
    realtime half    = 10.4167;   // 48 MHz

    int n_err = 0;

    vga_pll dut(.*);

    always #(half) ref_clk = ~ref_clk;

    task automatic fail(input string msg);
        n_err++;
        $display("ERROR at %0t: %s", $time, msg);
    endtask

    // Average pix_clk period over n cycles
    task automatic measure(input int n, input real expect_ns);
        realtime t0, t1;
        real     p;
        @(posedge pix_clk);
        t0 = $realtime;
        repeat (n) @(posedge pix_clk);
        t1 = $realtime;
        p  = (t1 - t0) / n;
        $display("pix_clk period %.3f ns (expected %.3f)", p, expect_ns);
        if (p < 0.999 * expect_ns || p > 1.001 * expect_ns)
            fail($sformatf("period %.3f ns, expected %.3f", p, expect_ns));
    endtask

    // Count pix_clk edges, to check that it does not toggle
    int n_tog = 0;

    always @(pix_clk) n_tog++;

    // pix_clk must not toggle for this long
    task automatic quiet(input realtime t);
        int c = n_tog;
        #(t);
        if (n_tog != c) fail("pix_clk toggled while not locked");
    endtask

    // Wait for lock with a timeout of 20 us
    task automatic wait_lock();
        for (int i = 0; i < 20_000 && lock !== 1'b1; i++) #(1);
        if (lock !== 1'b1) fail("no lock within 20 us");
    endtask

    initial begin
        // 1. Held in reset
        #(5);
        if (lock !== 1'b0) fail("lock not low in reset");
        quiet(2_000);
        if (lock !== 1'b0) fail("lock rose in reset");

        // 2. Lock and frequency
        rst_n = 1'b1;
        wait_lock();
        measure(1000, 40.0);

        // 3. Reset again
        rst_n = 1'b0;
        #(1);
        if (lock !== 1'b0) fail("lock did not drop on reset");
        quiet(2_000);
        rst_n = 1'b1;
        wait_lock();
        measure(1000, 40.0);

        // 4. Reference 10% slow
        rst_n = 1'b0;
        half  = 10.4167 / 0.9;
        #(1_000);
        rst_n = 1'b1;
        wait_lock();
        repeat (10) @(posedge pix_clk);
        measure(1000, 40.0 / 0.9);

        $display("vga_pll: %0d errors", n_err);
        if (n_err == 0) $display("TEST PASSED");
        else            $display("TEST FAILED");
        $finish;
    end

endmodule
