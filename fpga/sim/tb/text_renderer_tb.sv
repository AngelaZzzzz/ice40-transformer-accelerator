`timescale 1ns/1ps

////////////////////////////////////////////////////////////////////////////////
// text_renderer_tb
//   Testbench for text_renderer
////////////////////////////////////////////////////////////////////////////////

// Self-checking. Runs text_renderer with the real vga_timing, text_buffer
// and font_rom (font.mem; run vvp from fpga/mem). The buffer is written
// through its write port in a separate 48 MHz clock: rows 0 to 9 of memory
// hold readable text in both colors, rows 10 to 14 every byte value
// (including 0x00, 0x20, control codes and color 1).
//
// A model computes each pixel from the interface spec section 8 rules,
// using the testbench's own copies of the buffer and the font, and every
// output (vga_r, vga_g, vga_b, vga_hs, vga_vs) is compared every cycle with
// the model for the counters three cycles earlier. Frames are rendered
// with scroll = 0, 1, 7, 14 and 15 (15 must equal 0 mod 15), and scroll
// also changes mid-frame once (allowed for this unit; scroll_cdc only
// changes it in vblank). pix_rst must hold the colors at 0 and the syncs
// high.
//
// The first frame (scroll = 0) is also written to text_renderer_tb.ppm
// for viewing.
//
// Prints "TEST PASSED" or "TEST FAILED" on the last line.

module text_renderer_tb();

    logic pix_clk = 1'b0;
    logic wclk    = 1'b0;
    logic pix_rst = 1'b1;

    always #20.0    pix_clk = ~pix_clk;
    always #10.4167 wclk    = ~wclk;

    logic [9:0]  hcount, vcount, tb_raddr;
    logic        hsync, vsync, blank;
    logic [3:0]  scroll = '0;
    logic [7:0]  tb_rdata, font_data;
    logic [10:0] font_addr;
    logic        vga_hs, vga_vs, vga_r, vga_g, vga_b;

    logic        we = 1'b0;
    logic [9:0]  waddr;
    logic [7:0]  wdata;

    vga_timing timing(.*);

    text_buffer tbuf(
        .wclk(wclk),
        .we(we),
        .waddr(waddr),
        .wdata(wdata),
        .rclk(pix_clk),
        .raddr(tb_raddr),
        .rdata(tb_rdata)
    );

    font_rom font(.pix_clk(pix_clk), .addr(font_addr), .data(font_data));

    text_renderer dut(.*);

    // Testbench copies of the buffer and the font
    logic [7:0] buf_m  [0:1023];
    logic [7:0] font_m [0:2047];

    // Expected outputs for counters (h, v) with scroll s
    function automatic logic [4:0] expect_out(input int h, input int v,
                                              input int s, input logic hs,
                                              input logic vs,
                                              input logic bl);
        int         mr;
        logic [7:0] ch, fr;
        logic       lit;
        mr  = ((v / 32) + s) % 15;
        ch  = buf_m[mr * 40 + h / 16];
        fr  = font_m[{ch[6:0], 4'((v / 2) % 16)}];
        lit = !bl && fr[7 - (h / 2) % 8] &&
              ch[6:0] != 7'h00 && ch[6:0] != 7'h20;
        // {hs, vs, r, g, b}
        return {hs, vs, lit && !ch[7], lit, lit && !ch[7]};
    endfunction

    // History of the expected outputs. At a clock edge, e_now is the model
    // for the counters of the cycle just ending; the outputs after that
    // edge belong to the counters two cycles before it (three edges
    // after their own cycle), which is exp_q[1].
    logic [4:0] exp_q [2];
    int         n_err  = 0;
    int         n_chk  = 0;
    int         n_lit  = 0;
    int         warm   = 0;   // cycles since pix_rst released

    task automatic err(input string msg);
        n_err++;
        if (n_err <= 20) $display("ERROR at %0t: %s", $time, msg);
    endtask

    // Image of the first frame
    int  fd;
    bit  dumping = 1'b0;
    int  hcount_q, vcount_q;
    int  ix [2];
    int  iy [2];

    always @(posedge pix_clk) begin
        logic [4:0] e_now;
        logic [4:0] got;
        // Expected value for the counters as they are before this edge
        e_now    = expect_out(hcount, vcount, scroll, hsync, vsync, blank);
        hcount_q = hcount;
        vcount_q = vcount;
        #1;
        got = {vga_hs, vga_vs, vga_r, vga_g, vga_b};
        if (pix_rst) begin
            if (got !== 5'b11000) err($sformatf("reset outputs %b", got));
            warm = 0;
        end else begin
            warm++;
            if (warm > 3) begin
                n_chk++;
                if (got[2:0] != 0) n_lit++;
                if (got !== exp_q[1])
                    err($sformatf("hs vs r g b %b, expected %b", got,
                                  exp_q[1]));
                if (dumping && ix[1] < 640 && iy[1] < 480)
                    $fdisplay(fd, "%0d %0d %0d", got[2] * 255,
                              got[1] * 255, got[0] * 255);
            end
        end
        exp_q[1] = exp_q[0];
        exp_q[0] = e_now;
        ix[1] = ix[0];
        ix[0] = hcount_q;
        iy[1] = iy[0];
        iy[0] = vcount_q;
    end

    // Fill the buffer through its write port
    task automatic write(input int a, input logic [7:0] d);
        @(negedge wclk);
        we    = 1'b1;
        waddr = 10'(a);
        wdata = d;
        @(negedge wclk);
        we = 1'b0;
        buf_m[a] = d;
    endtask

    task automatic text(input int r, input string s, input logic color);
        for (int c = 0; c < 40; c++)
            write(r * 40 + c, {color, (c < s.len()) ? 7'(s[c]) : 7'h20});
    endtask

    // Wait for the start of the next frame (counters at 0, 0)
    task automatic frame_start();
        do @(negedge pix_clk); while (!(hcount == 0 && vcount == 0));
    endtask

    initial begin
        $readmemh("font.mem", font_m);

        // Buffer contents (pix_rst held)
        text(0, "ice40 transformer accelerator", 1'b0);
        text(1, "E155 final project", 1'b0);
        text(2, "> em", 1'b0);
        text(3, "emily", 1'b1);
        text(4, "> ja", 1'b0);
        text(5, "jaxon", 1'b1);
        text(6, "ABCDEFGHIJKLMNOPQRSTUVWXYZ 0123456789", 1'b0);
        text(7, "abcdefghijklmnopqrstuvwxyz !?.,:;()[]{}", 1'b1);
        text(8, "row 8: the last column is here ------->|", 1'b0);
        text(9, "", 1'b0);
        for (int i = 400; i < 1024; i++) write(i, 8'(i - 400));
        // Overwrite the bytes that are not glyphs with visible variety
        write(400, 8'h00);
        write(401, 8'h20);
        write(402, 8'ha0);

        repeat (5) @(negedge pix_clk);
        pix_rst = 1'b0;

        // Frame with scroll = 0, dumped to an image
        frame_start();
        fd = $fopen("text_renderer_tb.ppm", "w");
        $fdisplay(fd, "P3\n640 480\n255");
        dumping = 1'b1;
        frame_start();
        dumping = 1'b0;
        $fclose(fd);

        // Other scroll values
        scroll = 4'd1;
        frame_start();
        scroll = 4'd7;
        frame_start();
        scroll = 4'd14;
        frame_start();
        scroll = 4'd15;
        frame_start();

        // Mid-frame change and a reset in the middle of a line
        repeat (200_000) @(negedge pix_clk);
        scroll = 4'd3;
        repeat (100_333) @(negedge pix_clk);
        pix_rst = 1'b1;
        repeat (4) @(negedge pix_clk);
        pix_rst = 1'b0;
        frame_start();
        frame_start();

        $display("text_renderer: %0d cycles checked, %0d lit, %0d errors",
                 n_chk, n_lit, n_err);
        if (n_lit == 0) begin
            n_err++;
            $display("no lit pixels");
        end
        if (n_err == 0) $display("TEST PASSED");
        else            $display("TEST FAILED");
        $finish;
    end

endmodule
