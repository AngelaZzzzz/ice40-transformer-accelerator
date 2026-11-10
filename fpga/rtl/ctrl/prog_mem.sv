////////////////////////////////////////////////////////////////////////////////
// prog_mem
//   256 x 48-bit program memory, 3 EBRs, 1-cycle read
////////////////////////////////////////////////////////////////////////////////

module prog_mem(input  logic        clk,
                input  logic        rst,
                input  logic        we,
                input  logic [7:0]  waddr,
                input  logic [47:0] wdata,
                input  logic [7:0]  raddr,
                output logic [47:0] rdata);

    // TODO(zach): implement per docs/interface_spec.md section 3

    assign rdata = '0;

endmodule
