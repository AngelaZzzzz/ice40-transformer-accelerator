`timescale 1ns/1ps

////////////////////////////////////////////////////////////////////////////////
// vga_timing_tb
//   Testbench for vga_timing
////////////////////////////////////////////////////////////////////////////////

// Self-checking. Two instances run side by side:
//   std: the default 800 x 525 timing (interface spec section 8);
//   alt: a shortened horizontal total (640 + 16 + 96 + 11 = 763), to
//        check that the parameters are honored.
// Each instance is checked every cycle against counters kept by the
// testbench: hcount/vcount sequence and wrap, hsync/vsync/blank decode,
// and reset holding both counters at 0. Each sync's period and low width
// are also measured from its edges, over 5.5 frames, with a reset
// in the middle of the run.
//
// Prints "TEST PASSED" or "TEST FAILED" on the last line.

module vga_timing_tb();

    logic pix_clk = 1'b0;
    logic pix_rst;

    always #20 pix_clk = ~pix_clk;   // 25 MHz

    // Default timing
    logic [9:0] s_h, s_v;
    logic       s_hs, s_vs, s_bl;

    vga_timing std(
        .pix_clk(pix_clk),
        .pix_rst(pix_rst),
        .hcount(s_h),
        .vcount(s_v),
        .hsync(s_hs),
        .vsync(s_vs),
        .blank(s_bl)
    );

    // Shortened horizontal total
    logic [9:0] a_h, a_v;
    logic       a_hs, a_vs, a_bl;

    vga_timing #(.H_BP(11)) alt(
        .pix_clk(pix_clk),
        .pix_rst(pix_rst),
        .hcount(a_h),
        .vcount(a_v),
        .hsync(a_hs),
        .vsync(a_vs),
        .blank(a_bl)
    );

    int n_err = 0;

    // Checker for one instance: expected counters plus sync measurements.
    // Called after every rising edge with that instance's outputs.
    typedef struct packed {
        int h, v;                  // expected position
        int hs_fall, vs_fall;      // cycle of last sync fall (-1 = none)
        int n_hs, n_vs;           // full sync periods measured
        logic hs_q, vs_q;          // previous sync values
    } chk_t;

    chk_t cs, ca;
    int   cyc = 0;

    task automatic err(input string name, input string msg);
        n_err++;
        if (n_err <= 20) $display("%s cycle %0d: %s", name, cyc, msg);
    endtask

    task automatic check(input string name, inout chk_t c,
                         input int h_tot, input int v_tot,
                         input logic rst_q,
                         input logic [9:0] h, input logic [9:0] v,
                         input logic hs, input logic vs, input logic bl);
        logic e_hs, e_vs, e_bl;
        // Expected position after this edge
        if (rst_q) begin
            c.h = 0;
            c.v = 0;
        end else begin
            c.h++;
            if (c.h == h_tot) begin
                c.h = 0;
                c.v = (c.v + 1) % v_tot;
            end
        end
        e_hs = !(c.h >= 656 && c.h < 752);
        e_vs = !(c.v >= 490 && c.v < 492);
        e_bl = (c.h >= 640) || (c.v >= 480);
        if (h !== 10'(c.h) || v !== 10'(c.v))
            err(name, $sformatf("pos (%0d,%0d) exp (%0d,%0d)",
                                h, v, c.h, c.v));
        if (hs !== e_hs || vs !== e_vs || bl !== e_bl)
            err(name, $sformatf("hs/vs/bl %b%b%b exp %b%b%b at (%0d,%0d)",
                                hs, vs, bl, e_hs, e_vs, e_bl, c.h, c.v));

        // Sync edge measurements (skipped across a reset)
        if (rst_q) begin
            c.hs_fall = -1;
            c.vs_fall = -1;
        end else begin
            if (c.hs_q && !hs) begin
                if (c.hs_fall != -1) begin
                    if (cyc - c.hs_fall != h_tot)
                        err(name, $sformatf("hsync period %0d exp %0d",
                                            cyc - c.hs_fall, h_tot));
                    c.n_hs++;
                end
                c.hs_fall = cyc;
            end
            if (!c.hs_q && hs && c.hs_fall != -1 && cyc - c.hs_fall != 96)
                err(name, $sformatf("hsync width %0d exp 96",
                                    cyc - c.hs_fall));
            if (c.vs_q && !vs) begin
                if (c.vs_fall != -1) begin
                    if (cyc - c.vs_fall != h_tot * v_tot)
                        err(name, $sformatf("vsync period %0d exp %0d",
                                            cyc - c.vs_fall,
                                            h_tot * v_tot));
                    c.n_vs++;
                end
                c.vs_fall = cyc;
            end
            if (!c.vs_q && vs && c.vs_fall != -1 &&
                cyc - c.vs_fall != 2 * h_tot)
                err(name, $sformatf("vsync width %0d exp %0d",
                                    cyc - c.vs_fall, 2 * h_tot));
        end
        c.hs_q = hs;
        c.vs_q = vs;
    endtask

    task automatic init(inout chk_t c);
        c.h       = 0;
        c.v       = 0;
        c.hs_fall = -1;
        c.vs_fall = -1;
        c.n_hs    = 0;
        c.n_vs    = 0;
        c.hs_q    = 1'b1;
        c.vs_q    = 1'b1;
    endtask

    // One cycle: drive reset at the falling edge, check after the rising
    // edge
    task automatic step(input logic r);
        @(negedge pix_clk);
        pix_rst = r;
        @(posedge pix_clk);
        #1;
        cyc++;
        check("std", cs, 800, 525, r, s_h, s_v, s_hs, s_vs, s_bl);
        check("alt", ca, 763, 525, r, a_h, a_v, a_hs, a_vs, a_bl);
    endtask

    initial begin
        init(cs);
        init(ca);

        // Reset
        repeat (5) step(1'b1);

        // 1.5 frames, reset in the middle of a line, then 4 more frames
        repeat (630_000) step(1'b0);
        repeat (3) step(1'b1);
        repeat (4 * 420_000) step(1'b0);

        $display("std: %0d hsync, %0d vsync periods measured",
                 cs.n_hs, cs.n_vs);
        $display("alt: %0d hsync, %0d vsync periods measured",
                 ca.n_hs, ca.n_vs);
        if (cs.n_vs < 3 || ca.n_vs < 3) begin
            n_err++;
            $display("too few sync periods measured");
        end
        $display("vga_timing: %0d cycles checked, %0d errors", cyc, n_err);
        if (n_err == 0) $display("TEST PASSED");
        else            $display("TEST FAILED");
        $finish;
    end

endmodule
