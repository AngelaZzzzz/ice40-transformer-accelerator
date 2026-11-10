////////////////////////////////////////////////////////////////////////////////
// lut_rom
//   256 x 16-bit lookup table ROM, 1 EBR, 1-cycle read
////////////////////////////////////////////////////////////////////////////////

module lut_rom #(
    parameter INIT_FILE = ""
) (
    input  logic        clk,
    input  logic        rst,
    input  logic [7:0]  addr,

    output logic [15:0] data
);

    // TODO(zach): implement per docs/interface_spec.md section 3

    assign data = '0;

endmodule
