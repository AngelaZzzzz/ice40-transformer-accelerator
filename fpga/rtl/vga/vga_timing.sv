////////////////////////////////////////////////////////////////////////////////
// vga_timing
//   640 x 480 VGA horizontal and vertical timing generator
////////////////////////////////////////////////////////////////////////////////

module vga_timing(input  logic       pix_clk,
                  input  logic       pix_rst,
                  output logic [9:0] hcount,
                  output logic [9:0] vcount,
                  output logic       hsync,
                  output logic       vsync,
                  output logic       blank);

    // TODO(angela): implement per docs/interface_spec.md section 8

    assign hcount = '0;
    assign vcount = '0;
    assign hsync = 1'b0;
    assign vsync = 1'b0;
    assign blank = 1'b0;

endmodule
