////////////////////////////////////////////////////////////////////////////////
// reset_gen
//   Power-on and button reset, active high, synchronous to clk
////////////////////////////////////////////////////////////////////////////////

module reset_gen(input  logic clk,
                 input  logic rst_n_async,
                 output logic rst);

    // TODO(zach): implement per docs/interface_spec.md section 1

    assign rst = 1'b0;

endmodule
