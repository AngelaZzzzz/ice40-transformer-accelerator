////////////////////////////////////////////////////////////////////////////////
// spram_mem
//   16,384 x 64-bit SPRAM from four SP256K blocks, core and SPI ports
////////////////////////////////////////////////////////////////////////////////

module spram_mem(input  logic        clk,
                 input  logic        rst,
                 input  logic        busy,
                 input  logic        core_re,
                 input  logic        core_we,
                 input  logic [13:0] core_addr,
                 input  logic [63:0] core_wdata,
                 input  logic [7:0]  core_bytemask,
                 input  logic        spi_re,
                 input  logic        spi_we,
                 input  logic [13:0] spi_addr,
                 input  logic [63:0] spi_wdata,
                 output logic [63:0] rdata);

    // TODO(angela): implement per docs/interface_spec.md section 4

    assign rdata = '0;

endmodule
