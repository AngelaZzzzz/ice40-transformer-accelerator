////////////////////////////////////////////////////////////////////////////////
// vga_timing
//   640 x 480 VGA horizontal and vertical timing generator
////////////////////////////////////////////////////////////////////////////////

// Default timing (interface spec section 8): 800 x 525 pixel clocks,
//   H: 640 active + 16 front porch + 96 sync + 48 back porch
//   V: 480 active + 10 front porch +  2 sync + 33 back porch
// with both syncs active low. At 25.000 MHz this is a 31.25 kHz line and a
// 59.5 Hz frame.
//
// hcount and vcount are the position of the current pixel clock, counting
// from the first active pixel. hsync, vsync and blank describe that same
// position (they are decoded from the counters, so all five outputs change
// together on each pix_clk edge). text_renderer registers them, so the
// decode never reaches a pin directly.
//
// The porch and sync widths are parameters so that the horizontal total can
// be adjusted if the monitor will not lock (spec section 8: keep the sync
// widths and change the total so that pix_clk / H_TOTAL = 31.47 kHz).
//
// pix_rst holds both counters at 0 (the first active pixel).

module vga_timing #(
    parameter int H_ACTIVE = 640,
    parameter int H_FP     = 16,
    parameter int H_SYNC   = 96,
    parameter int H_BP     = 48,
    parameter int V_ACTIVE = 480,
    parameter int V_FP     = 10,
    parameter int V_SYNC   = 2,
    parameter int V_BP     = 33
) (
    input  logic       pix_clk,
    input  logic       pix_rst,

    output logic [9:0] hcount,
    output logic [9:0] vcount,
    output logic       hsync,
    output logic       vsync,
    output logic       blank
);

    localparam int H_TOTAL = H_ACTIVE + H_FP + H_SYNC + H_BP;
    localparam int V_TOTAL = V_ACTIVE + V_FP + V_SYNC + V_BP;

    // Pixel and line counters
    always_ff @(posedge pix_clk) begin
        if (pix_rst) begin
            hcount <= '0;
            vcount <= '0;
        end else if (hcount == 10'(H_TOTAL - 1)) begin
            hcount <= '0;
            if (vcount == 10'(V_TOTAL - 1)) vcount <= '0;
            else                            vcount <= vcount + 10'd1;
        end else begin
            hcount <= hcount + 10'd1;
        end
    end

    // Syncs (active low) and blanking for the current position
    assign hsync = ~((hcount >= 10'(H_ACTIVE + H_FP)) &&
                     (hcount <  10'(H_ACTIVE + H_FP + H_SYNC)));
    assign vsync = ~((vcount >= 10'(V_ACTIVE + V_FP)) &&
                     (vcount <  10'(V_ACTIVE + V_FP + V_SYNC)));
    assign blank = (hcount >= 10'(H_ACTIVE)) || (vcount >= 10'(V_ACTIVE));

endmodule
