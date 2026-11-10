////////////////////////////////////////////////////////////////////////////////
// synchronizer
//   Two-flop synchronizer for a WIDTH-bit asynchronous input
////////////////////////////////////////////////////////////////////////////////

module synchronizer #(
    parameter int WIDTH = 1
) (
    input  logic             clk,
    input  logic             rst,
    input  logic [WIDTH-1:0] d,

    output logic [WIDTH-1:0] q
);

    // TODO(zach): implement per docs/interface_spec.md section 1

    assign q = '0;

endmodule
