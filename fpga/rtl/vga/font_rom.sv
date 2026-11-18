////////////////////////////////////////////////////////////////////////////////
// font_rom
//   128-glyph 8 x 16 font ROM, 4 EBRs
////////////////////////////////////////////////////////////////////////////////

// 2,048 x 8 bits loaded from INIT_FILE (fpga/mem/font.mem, written by
// tools/make_font.py; interface spec section 8). addr = {char[6:0],
// row[3:0]}; data bit 7 is the leftmost pixel of that glyph row. One-cycle
// registered read, which maps to the EBR read register.

module font_rom #(
    parameter INIT_FILE = "font.mem"
) (
    input  logic        pix_clk,
    input  logic [10:0] addr,

    output logic [7:0]  data
);

    logic [7:0] rom [0:2047];

    initial $readmemh(INIT_FILE, rom);

    always_ff @(posedge pix_clk) begin
        data <= rom[addr];
    end

endmodule
