////////////////////////////////////////////////////////////////////////////////
// text_buffer
//   1,024 x 8-bit dual-clock character buffer, 2 EBRs
////////////////////////////////////////////////////////////////////////////////

module text_buffer(input  logic       wclk,
                   input  logic       we,
                   input  logic [9:0] waddr,
                   input  logic [7:0] wdata,
                   input  logic       rclk,
                   input  logic [9:0] raddr,
                   output logic [7:0] rdata);

    // TODO(angela): implement per docs/interface_spec.md section 8

    assign rdata = '0;

endmodule
