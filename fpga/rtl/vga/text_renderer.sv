////////////////////////////////////////////////////////////////////////////////
// text_renderer
//   Character-cell renderer from text buffer and font ROM to VGA
////////////////////////////////////////////////////////////////////////////////

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

    // TODO(angela): implement per docs/interface_spec.md section 8

    assign tb_raddr = '0;
    assign font_addr = '0;
    assign vga_hs = 1'b0;
    assign vga_vs = 1'b0;
    assign vga_r = 1'b0;
    assign vga_g = 1'b0;
    assign vga_b = 1'b0;

endmodule
