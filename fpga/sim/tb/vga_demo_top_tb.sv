`timescale 1ns/1ps

////////////////////////////////////////////////////////////////////////////////
// vga_demo_top_tb
//   Testbench for vga_demo_top
////////////////////////////////////////////////////////////////////////////////

// Self-checking, end to end, with the HSOSC and PLL_B models and a 12 MHz
// clk_12m. Run vvp from fpga/mem (demo_text.mem and font.mem). Both builds
// of the demo run side by side: PATTERN = 0 (text) and PATTERN = 1 (bars).
//
// Each is watched only through its five pins, the way a monitor sees it
// (vga_monitor below): the monitor locks onto the falling edges of hsync
// and vsync, rebuilds the pixel position from them, and checks
//   - the hsync period (800 / 25.125 MHz = 31.840 us, within 0.1%), the
//     hsync width (96 pixels),
//     the vsync period (525 lines) and width (2 lines), and that vsync
//     falls at the start of a line;
//   - every visible pixel of two full frames against the image expected
//     from the spec: the text screen from demo_text.mem and font.mem, or
//     the bar pattern.
// The first text frame is also written to vga_demo_top_tb.ppm.
//
// Prints "TEST PASSED" or "TEST FAILED" on the last line.

module vga_demo_top_tb();

    logic clk_12m = 1'b0;
    logic t_hs, t_vs, t_r, t_g, t_b;
    logic p_hs, p_vs, p_r, p_g, p_b;

    always #(41.6665) clk_12m = ~clk_12m;

    vga_demo_top #(.PATTERN(1'b0)) text_dut(
        .clk_12m(clk_12m),
        .vga_hs(t_hs),
        .vga_vs(t_vs),
        .vga_r(t_r),
        .vga_g(t_g),
        .vga_b(t_b)
    );

    vga_demo_top #(.PATTERN(1'b1)) bars_dut(
        .clk_12m(clk_12m),
        .vga_hs(p_hs),
        .vga_vs(p_vs),
        .vga_r(p_r),
        .vga_g(p_g),
        .vga_b(p_b)
    );

    vga_monitor #(.PATTERN(1'b0), .DUMP("vga_demo_top_tb.ppm")) text_mon(
        .pix_clk(text_dut.pix_clk),
        .hs(t_hs),
        .vs(t_vs),
        .rgb({t_r, t_g, t_b})
    );

    vga_monitor #(.PATTERN(1'b1), .DUMP("")) bars_mon(
        .pix_clk(bars_dut.pix_clk),
        .hs(p_hs),
        .vs(p_vs),
        .rgb({p_r, p_g, p_b})
    );

    // iCE40 flip-flops power up at 0 (reset_gen relies on this too). The
    // pixel-reset synchronizer only gets pix_clk edges once the PLL has
    // locked, so in simulation it must start at 0 as in hardware, or
    // pix_rst would go from X straight to 0 and never reset the counters.
    initial begin
        text_dut.pix_rst_sync.meta = 1'b0;
        text_dut.pix_rst_sync.q    = 1'b0;
        bars_dut.pix_rst_sync.meta = 1'b0;
        bars_dut.pix_rst_sync.q    = 1'b0;
    end

    initial begin
        wait (text_mon.n_frames >= 2 && bars_mon.n_frames >= 2);
        #1000;
        $display("text: %0d pixels checked, %0d lit, %0d errors",
                 text_mon.n_chk, text_mon.n_lit, text_mon.n_err);
        $display("bars: %0d pixels checked, %0d lit, %0d errors",
                 bars_mon.n_chk, bars_mon.n_lit, bars_mon.n_err);
        if (text_mon.n_err == 0 && bars_mon.n_err == 0 &&
            text_mon.n_lit > 0 && bars_mon.n_lit > 0)
            $display("TEST PASSED");
        else
            $display("TEST FAILED");
        $finish;
    end

    initial begin
        #(60_000_000);
        $display("timeout: frames text %0d, bars %0d", text_mon.n_frames,
                 bars_mon.n_frames);
        $display("TEST FAILED");
        $finish;
    end

endmodule

// Monitor model: recovers the pixel position from the sync pins and
// checks each visible pixel against the expected image.
module vga_monitor #(
    parameter bit PATTERN = 1'b0,
    parameter     DUMP    = ""
) (
    input  logic       pix_clk,
    input  logic       hs,
    input  logic       vs,
    input  logic [2:0] rgb
);

    logic [7:0] buf_m  [0:1023];
    logic [7:0] font_m [0:2047];

    initial begin
        $readmemh("demo_text.mem", buf_m);
        $readmemh("font.mem", font_m);
    end

    function automatic logic [2:0] expect_rgb(input int x, input int y);
        logic [7:0] ch, fr;
        logic       lit;
        if (PATTERN) begin
            if (x == 0 || x == 639 || y == 0 || y == 479) return 3'b111;
            return 3'((x / 64) % 8);
        end
        ch  = buf_m[(y / 32) * 40 + x / 16];
        fr  = font_m[{ch[6:0], 4'((y / 2) % 16)}];
        lit = fr[7 - (x / 2) % 8] && ch[6:0] != 7'h00 && ch[6:0] != 7'h20;
        return {lit && !ch[7], lit, lit && !ch[7]};
    endfunction

    int      n_err    = 0;
    int      n_chk    = 0;
    int      n_lit    = 0;
    int      n_frames = 0;    // full frames compared
    int      hc       = 0;
    int      vc       = 0;
    bit      h_lock   = 0;
    bit      v_lock   = 0;
    bit      in_frame = 0;    // comparing since the start of a frame
    logic    hs_q     = 1'b1;
    logic    vs_q     = 1'b1;
    realtime t_hfall  = 0;
    int      hs_low   = 0;
    int      vs_low   = 0;
    int      fd;
    int      dump     = 0;    // 0 not yet, 1 writing, 2 done

    task automatic err(input string msg);
        n_err++;
        if (n_err <= 20) $display("%m ERROR at %0t: %s", $time, msg);
    endtask

    always @(posedge pix_clk) begin
        #1;
        // Horizontal position
        if (hs_q && !hs) begin
            if (h_lock && hc != 655)
                err($sformatf("hsync after %0d pixels", hc + 1 - 656));
            if (h_lock && ($realtime - t_hfall < 31_808 ||
                           $realtime - t_hfall > 31_872))
                err($sformatf("hsync period %.1f ns",
                              $realtime - t_hfall));
            t_hfall = $realtime;
            hc      = 656;
            h_lock  = 1;
        end else begin
            hc = (hc + 1) % 800;
            if (hc == 0) vc = (vc + 1) % 525;
        end
        if (!hs) hs_low++;
        if (!hs_q && hs) begin
            if (hs_low != 96) err($sformatf("hsync width %0d", hs_low));
            hs_low = 0;
        end

        // Vertical position
        if (vs_q && !vs) begin
            if (h_lock && hc != 0)
                err($sformatf("vsync fell at pixel %0d of a line", hc));
            if (v_lock && vc != 490)
                err($sformatf("vsync after %0d lines", vc - 490 + 525));
            vc     = 490;
            v_lock = h_lock;
        end
        if (!vs) vs_low++;
        if (!vs_q && vs) begin
            if (vs_low != 1600) err($sformatf("vsync width %0d", vs_low));
            vs_low = 0;
        end
        hs_q = hs;
        vs_q = vs;

        // Pixels, from the first full frame after lock
        if (v_lock && hc == 0 && vc == 0) begin
            if (in_frame) n_frames++;
            in_frame = 1;
            if (DUMP != "" && dump == 0) begin
                fd   = $fopen(DUMP, "w");
                dump = 1;
                $fdisplay(fd, "P3\n640 480\n255");
            end else if (dump == 1) begin
                $fclose(fd);
                dump = 2;
            end
        end
        if (in_frame && hc < 640 && vc < 480) begin
            n_chk++;
            if (rgb != 0) n_lit++;
            if (rgb !== expect_rgb(hc, vc))
                err($sformatf("pixel (%0d,%0d) rgb %b, expected %b", hc,
                              vc, rgb, expect_rgb(hc, vc)));
            if (dump == 1)
                $fdisplay(fd, "%0d %0d %0d", rgb[2] * 255, rgb[1] * 255,
                          rgb[0] * 255);
        end
    end

endmodule
