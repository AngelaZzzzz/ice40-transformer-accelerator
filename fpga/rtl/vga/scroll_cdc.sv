////////////////////////////////////////////////////////////////////////////////
// scroll_cdc
//   Scroll offset crossing from clk to pix_clk, loaded in vblank
////////////////////////////////////////////////////////////////////////////////

// Interface spec section 8. In clk, a SCROLL command (we, d) sets a held
// register. Each of its 4 bits crosses into pix_clk through a 2-flop
// synchronizer. q, the scroll value text_renderer uses, loads the
// synchronized value only during vertical blanking and only after two
// successive samples agree, so a value caught while its bits are still
// settling is never used, and the screen never changes scroll mid-frame.
//
// Latency: a new value appears in q at the first vblank cycle at least
// about 4 pix_clk cycles after the write. SCROLL commands arrive over SPI
// far apart (bytes are microseconds apart), so the held value is stable
// for many pix_clk cycles before it is loaded.
//
// Both resets clear the scroll to 0.

module scroll_cdc(input  logic       clk,
                  input  logic       rst,
                  input  logic       we,
                  input  logic [3:0] d,
                  input  logic       pix_clk,
                  input  logic       pix_rst,
                  input  logic       vblank,
                  output logic [3:0] q);

    logic [3:0] held;
    logic [3:0] sync;
    logic [3:0] prev;

    // Core clock: hold the last SCROLL value
    always_ff @(posedge clk) begin
        if (rst)     held <= '0;
        else if (we) held <= d;
    end

    // Pixel clock: synchronize, then load in vblank once stable
    synchronizer #(.WIDTH(4)) held_sync(
        .clk(pix_clk),
        .rst(pix_rst),
        .d(held),
        .q(sync)
    );

    always_ff @(posedge pix_clk) begin
        if (pix_rst) begin
            prev <= '0;
            q    <= '0;
        end else begin
            prev <= sync;
            if (vblank && sync == prev) q <= sync;
        end
    end

endmodule
