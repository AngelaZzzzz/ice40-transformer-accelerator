////////////////////////////////////////////////////////////////////////////////
// vga_demo_top
//   Standalone VGA bring-up: fixed text screen or color-bar test pattern
////////////////////////////////////////////////////////////////////////////////

// The VGA path of gpt_top on its own, with no MCU, SPI or accelerator:
// 12 MHz oscillator (clk_12m, pin 35) -> vga_pll (25.125 MHz) ->
// vga_timing -> text_renderer, with text_buffer loaded at power-up from
// demo_text.mem (written by tools/make_demo_text.py) and font_rom from
// font.mem. Clocks and resets are built the same way as in gpt_top. There
// is no reset pin: the design resets once after configuration
// (reset_gen).
//
// PATTERN selects the output:
//   0  text screen (the final design's renderer)
//   1  test pattern: 64-pixel-wide vertical bars cycling through the 8
//      colors, with a 1-pixel white border around the 640 x 480 area.
//      It needs only the PLL, vga_timing and the wiring, so it separates
//      a monitor or wiring problem from a renderer problem.
// In both modes every output pin comes straight from a flip-flop, and the
// syncs pass through the same number of registers as the colors.
//
// Pins (interface spec section 8): HS 44, VS 45, R 46, G 47, B 48; R, G
// and B through 270 ohm.

module vga_demo_top #(
    parameter bit PATTERN = 1'b0
) (
    input  logic clk_12m,

    output logic vga_hs,
    output logic vga_vs,
    output logic vga_r,
    output logic vga_g,
    output logic vga_b
);

    localparam int V_ACTIVE = 480;

    logic        clk, rst;
    logic        pix_clk, pix_rst, pll_lock, pix_run;

    logic [9:0]  hcount, vcount, tb_raddr;
    logic        hsync, vsync, blank, vblank;
    logic [3:0]  scroll;
    logic [7:0]  tb_rdata, font_data;
    logic [10:0] font_addr;

    // Clocks and resets, as in gpt_top
    HSOSC #(.CLKHF_DIV("0b00")) hf_osc(
        .CLKHFPU(1'b1),
        .CLKHFEN(1'b1),
        .CLKHF(clk)
    );

    reset_gen reset(
        .clk(clk),
        .rst_n_async(1'b1),
        .rst(rst)
    );

    vga_pll pll(
        .ref_clk(clk_12m),
        .rst_n(~rst),
        .pix_clk(pix_clk),
        .lock(pll_lock)
    );

    synchronizer #(.WIDTH(1)) pix_rst_sync(
        .clk(pix_clk),
        .rst(1'b0),
        .d(pll_lock & ~rst),
        .q(pix_run)
    );

    assign pix_rst = ~pix_run;

    // Timing
    assign vblank = (vcount >= 10'(V_ACTIVE));

    vga_timing timing(
        .pix_clk(pix_clk),
        .pix_rst(pix_rst),
        .hcount(hcount),
        .vcount(vcount),
        .hsync(hsync),
        .vsync(vsync),
        .blank(blank)
    );

    generate
        if (PATTERN) begin : g_pattern
            // Bars and border, one register to the pins
            logic [2:0] bar;
            logic       edge_px;

            assign bar     = hcount[8:6];
            assign edge_px = (hcount == 10'd0) || (hcount == 10'd639) ||
                             (vcount == 10'd0) || (vcount == 10'd479);

            always_ff @(posedge pix_clk) begin
                if (pix_rst) begin
                    vga_hs <= 1'b1;
                    vga_vs <= 1'b1;
                    {vga_r, vga_g, vga_b} <= 3'b000;
                end else begin
                    vga_hs <= hsync;
                    vga_vs <= vsync;
                    if (blank)        {vga_r, vga_g, vga_b} <= 3'b000;
                    else if (edge_px) {vga_r, vga_g, vga_b} <= 3'b111;
                    else              {vga_r, vga_g, vga_b} <= bar;
                end
            end

            assign tb_raddr  = '0;
            assign font_addr = '0;
            assign scroll    = '0;
            assign tb_rdata  = '0;
            assign font_data = '0;
        end else begin : g_text
            // Text screen: the final design's VGA path, with no writes
            text_buffer #(.INIT_FILE("demo_text.mem")) tbuf(
                .wclk(clk),
                .we(1'b0),
                .waddr(10'd0),
                .wdata(8'd0),
                .rclk(pix_clk),
                .raddr(tb_raddr),
                .rdata(tb_rdata)
            );

            font_rom #(.INIT_FILE("font.mem")) font(
                .pix_clk(pix_clk),
                .addr(font_addr),
                .data(font_data)
            );

            scroll_cdc scroll_sync(
                .clk(clk),
                .rst(rst),
                .we(1'b0),
                .d(4'd0),
                .pix_clk(pix_clk),
                .pix_rst(pix_rst),
                .vblank(vblank),
                .q(scroll)
            );

            text_renderer renderer(
                .pix_clk(pix_clk),
                .pix_rst(pix_rst),
                .hcount(hcount),
                .vcount(vcount),
                .hsync(hsync),
                .vsync(vsync),
                .blank(blank),
                .scroll(scroll),
                .tb_rdata(tb_rdata),
                .font_data(font_data),
                .tb_raddr(tb_raddr),
                .font_addr(font_addr),
                .vga_hs(vga_hs),
                .vga_vs(vga_vs),
                .vga_r(vga_r),
                .vga_g(vga_g),
                .vga_b(vga_b)
            );
        end
    endgenerate

endmodule
