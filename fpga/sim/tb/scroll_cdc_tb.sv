`timescale 1ns/1ps

////////////////////////////////////////////////////////////////////////////////
// scroll_cdc_tb
//   Testbench for scroll_cdc
////////////////////////////////////////////////////////////////////////////////

// Self-checking. clk runs at 48 MHz and pix_clk at about 25 MHz with a
// slowly drifting phase. vblank is a shortened frame: 300 pix_clk cycles,
// the last 45 of them blanking. Every pix_clk cycle checks:
//   1. q changes only on an edge where vblank was high;
//   2. q is always a value that was held in clk at some time (never a
//      mixture of an old and a new value);
//   3. after the last write of a burst, q equals it by the end of the
//      second following vblank.
// Writes come at random gaps of 10 to 2,000 clk cycles, with some bursts
// of several writes before a vblank (only the last must appear), plus a
// reset of each domain with q returning to 0.
//
// Prints "TEST PASSED" or "TEST FAILED" on the last line.

module scroll_cdc_tb();

    logic       clk     = 1'b0;
    logic       pix_clk = 1'b0;
    logic       rst     = 1'b1;
    logic       pix_rst = 1'b1;
    logic       we      = 1'b0;
    logic [3:0] d       = '0;
    logic       vblank  = 1'b0;
    logic [3:0] q;

    realtime pix_half = 20.0;

    always #10.4167 clk = ~clk;
    always #(pix_half) pix_clk = ~pix_clk;

    scroll_cdc dut(.*);

    int   n_err = 0;
    int   n_chk = 0;
    bit   seen [16];          // values held in clk so far
    logic [3:0] last_wr = '0;
    int   vb_since_wr = 0;    // vblank periods ended since the last write

    task automatic err(input string msg);
        n_err++;
        if (n_err <= 20) $display("ERROR at %0t: %s", $time, msg);
    endtask

    // Frame generator and checker, in pix_clk
    int         pcyc = 0;
    logic [3:0] q_prev;
    logic       vb_prev;

    always @(posedge pix_clk) begin
        q_prev  = q;
        vb_prev = vblank;
        #1;
        if (!pix_rst) begin
            n_chk++;
            if (q !== q_prev && !vb_prev)
                err($sformatf("q changed %h -> %h outside vblank", q_prev,
                              q));
            if (!seen[q])
                err($sformatf("q = %h was never written", q));
            if (vb_since_wr >= 2 && q !== last_wr)
                err($sformatf("q = %h, expected %h after two vblanks", q,
                              last_wr));
        end
        // Next cycle's vblank
        pcyc = (pcyc + 1) % 300;
        if (vblank && pcyc < 255) vb_since_wr++;
        vblank = (pcyc >= 255);
        // Slow phase drift between the clocks
        pix_half = 20.0 + 0.3 * $sin(0.001 * $realtime);
    end

    task automatic write(input logic [3:0] v);
        @(negedge clk);
        we = 1'b1;
        d  = v;
        @(negedge clk);
        we = 1'b0;
        d  = $urandom;   // d is ignored without we
        seen[v]     = 1'b1;
        last_wr     = v;
        vb_since_wr = 0;
    endtask

    initial begin
        seen[0] = 1'b1;
        repeat (10) @(posedge clk);
        rst     = 1'b0;
        pix_rst = 1'b0;

        repeat (3000) begin
            if ($urandom_range(4) == 0)
                repeat ($urandom_range(5, 2)) begin
                    write($urandom);
                    repeat ($urandom_range(40, 10)) @(posedge clk);
                end
            else
                write($urandom);
            repeat ($urandom_range(2000, 10)) @(posedge clk);
        end

        // Wait two frames, then reset each domain
        repeat (1300) @(posedge clk);
        @(negedge pix_clk);
        pix_rst     = 1'b1;
        vb_since_wr = 0;   // q reloads the held value after the reset
        @(negedge pix_clk);
        @(negedge pix_clk);
        if (q !== 4'h0) err("q not cleared by pix_rst");
        pix_rst = 1'b0;
        @(negedge clk);
        rst = 1'b1;
        @(negedge clk);
        rst = 1'b0;
        last_wr     = 4'h0;
        vb_since_wr = 0;
        repeat (1300 * 2) @(posedge clk);
        if (q !== 4'h0) err("q not 0 after rst");

        $display("scroll_cdc: %0d cycles checked, %0d errors", n_chk, n_err);
        if (n_err == 0) $display("TEST PASSED");
        else            $display("TEST FAILED");
        $finish;
    end

endmodule
