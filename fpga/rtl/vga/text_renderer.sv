////////////////////////////////////////////////////////////////////////////////
// text_renderer
//   Character-cell renderer from text buffer and font ROM to VGA
////////////////////////////////////////////////////////////////////////////////

// Interface spec section 8: a 40 x 15 grid of 8 x 16 glyphs drawn at 2x, so
// each cell is 16 x 32 pixels. For the pixel at (hcount, vcount):
//   col     = hcount / 16                 glyph column x = (hcount / 2) % 8
//   row     = vcount / 32                 glyph row    y = (vcount / 2) % 16
//   memrow  = (row + scroll) mod 15
//   cell    = memrow x 40 + col           byte = {color, char[6:0]}
// A pixel is lit when bit 7 - x of font row {char, y} is 1, the char is not
// 0x00 or 0x20, and the position is not blanked. Color 0 (typed) is white,
// color 1 (generated) is green.
//
// Pipeline, three pix_clk cycles from the counters to the pins:
//   cycle 0: cell address from the counters (combinational) to text_buffer
//   cycle 1: text_buffer byte -> font address to font_rom
//   cycle 2: font_rom row -> pixel bit
//   cycle 3: registered vga_r/g/b
// hsync, vsync and blank go through the same three registers, so the
// picture and the syncs stay aligned and every output pin is driven by a
// flip-flop.
//
// pix_rst sets the color outputs to 0 and holds both syncs inactive (high).

module text_renderer(input  logic        pix_clk,
                     input  logic        pix_rst,
                     input  logic [9:0]  hcount,
                     input  logic [9:0]  vcount,
                     input  logic        hsync,
                     input  logic        vsync,
                     input  logic        blank,
                     input  logic [3:0]  scroll,
                     input  logic [7:0]  tb_rdata,
                     input  logic [7:0]  font_data,
                     output logic [9:0]  tb_raddr,
                     output logic [10:0] font_addr,
                     output logic        vga_hs,
                     output logic        vga_vs,
                     output logic        vga_r,
                     output logic        vga_g,
                     output logic        vga_b);

    localparam int ROWS = 15;

    // Cycle 0: cell address. row is at most 16 (vcount < 525), so one
    // conditional subtract reduces row + scroll (at most 31) mod 15 for
    // every visible row; rows in vertical blanking are never shown.
    logic [5:0] col;
    logic [4:0] row;
    logic [5:0] sum;
    logic [4:0] memrow;

    assign col    = hcount[9:4];
    assign row    = vcount[9:5];
    assign sum    = row + scroll;
    assign memrow = (sum >= 6'(ROWS)) ? 5'(sum - 6'(ROWS)) : 5'(sum);

    // memrow x 40 + col = memrow x 32 + memrow x 8 + col
    assign tb_raddr = 10'({memrow, 5'b0}) + 10'({memrow, 3'b0}) + 10'(col);

    // Cycle 1: font address from the buffer byte
    logic [3:0] gy1;
    logic [2:0] gx1;
    logic       blank1, hs1, vs1;

    always_ff @(posedge pix_clk) begin
        if (pix_rst) begin
            gy1    <= '0;
            gx1    <= '0;
            blank1 <= 1'b1;
            hs1    <= 1'b1;
            vs1    <= 1'b1;
        end else begin
            gy1    <= vcount[4:1];
            gx1    <= hcount[3:1];
            blank1 <= blank;
            hs1    <= hsync;
            vs1    <= vsync;
        end
    end

    assign font_addr = {tb_rdata[6:0], gy1};

    // Cycle 2: pixel bit from the font row
    logic [2:0] gx2;
    logic       blank2, hs2, vs2, color2, show2;

    always_ff @(posedge pix_clk) begin
        if (pix_rst) begin
            gx2    <= '0;
            blank2 <= 1'b1;
            hs2    <= 1'b1;
            vs2    <= 1'b1;
            color2 <= 1'b0;
            show2  <= 1'b0;
        end else begin
            gx2    <= gx1;
            blank2 <= blank1;
            hs2    <= hs1;
            vs2    <= vs1;
            color2 <= tb_rdata[7];
            show2  <= (tb_rdata[6:0] != 7'h00) && (tb_rdata[6:0] != 7'h20);
        end
    end

    logic lit;

    assign lit = font_data[3'd7 - gx2] && show2 && !blank2;

    // Cycle 3: registered outputs
    always_ff @(posedge pix_clk) begin
        if (pix_rst) begin
            vga_hs <= 1'b1;
            vga_vs <= 1'b1;
            vga_r  <= 1'b0;
            vga_g  <= 1'b0;
            vga_b  <= 1'b0;
        end else begin
            vga_hs <= hs2;
            vga_vs <= vs2;
            vga_r  <= lit && !color2;
            vga_g  <= lit;
            vga_b  <= lit && !color2;
        end
    end

endmodule
