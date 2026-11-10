////////////////////////////////////////////////////////////////////////////////
// mac_lane
//   Signed 16 x 16 multiply-accumulate lane on one sysDSP block
////////////////////////////////////////////////////////////////////////////////

module mac_lane(input  logic               clk,
                input  logic               rst,
                input  logic               en,
                input  logic               clr,
                input  logic signed [15:0] a,
                input  logic signed [15:0] b,
                output logic signed [31:0] acc);

    // TODO(angela): implement per docs/interface_spec.md section 6

    assign acc = '0;

endmodule
