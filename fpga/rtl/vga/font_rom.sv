////////////////////////////////////////////////////////////////////////////////
// font_rom
//   128-glyph 8 x 16 font ROM, 4 EBRs
////////////////////////////////////////////////////////////////////////////////

module font_rom(input  logic        pix_clk,
                input  logic [10:0] addr,
                output logic [7:0]  data);

    // TODO(angela): implement per docs/interface_spec.md section 8

    assign data = '0;

endmodule
