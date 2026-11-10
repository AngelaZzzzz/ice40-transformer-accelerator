////////////////////////////////////////////////////////////////////////////////
// scroll_cdc
//   Scroll offset crossing from clk to pix_clk, loaded in vblank
////////////////////////////////////////////////////////////////////////////////

module scroll_cdc(input  logic       clk,
                  input  logic       rst,
                  input  logic       we,
                  input  logic [3:0] d,
                  input  logic       pix_clk,
                  input  logic       pix_rst,
                  input  logic       vblank,
                  output logic [3:0] q);

    // TODO(angela): implement per docs/interface_spec.md section 8

    assign q = '0;

endmodule
