////////////////////////////////////////////////////////////////////////////////
// lut_rom
//   256 x 16-bit lookup table ROM loaded from INIT_FILE, 1 EBR, 1-cycle read
////////////////////////////////////////////////////////////////////////////////

module lut_rom #(
    parameter INIT_FILE = ""
) (
    input  logic        clk,
    input  logic        rst,
    input  logic [7:0]  addr,

    output logic [15:0] data
);

    logic [15:0] rom [0:255];

    initial $readmemh(INIT_FILE, rom);

    always_ff @(posedge clk) begin
        data <= rom[addr];
    end

endmodule
