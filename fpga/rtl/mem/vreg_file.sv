////////////////////////////////////////////////////////////////////////////////
// vreg_file
//   1,024 x 16-bit vector register file, 4 EBR banks
////////////////////////////////////////////////////////////////////////////////

module vreg_file(input  logic        clk,
                 input  logic        rst,
                 input  logic [9:0]  ra_addr,
                 input  logic [9:0]  rb_addr,
                 input  logic        w_en,
                 input  logic [9:0]  w_addr,
                 input  logic [15:0] w_data,
                 output logic [15:0] ra_data,
                 output logic [15:0] rb_data);

    // TODO(angela): implement per docs/interface_spec.md section 5

    assign ra_data = '0;
    assign rb_data = '0;

endmodule
