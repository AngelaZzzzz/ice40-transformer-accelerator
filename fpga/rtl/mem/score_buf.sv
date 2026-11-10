////////////////////////////////////////////////////////////////////////////////
// score_buf
//   32 x 16-bit output score buffer, 1 EBR
////////////////////////////////////////////////////////////////////////////////

module score_buf(input  logic        clk,
                 input  logic        rst,
                 input  logic        we,
                 input  logic [4:0]  waddr,
                 input  logic [15:0] wdata,
                 input  logic [4:0]  raddr,
                 output logic [15:0] rdata);

    // TODO(angela): implement per docs/interface_spec.md section 5

    assign rdata = '0;

endmodule
