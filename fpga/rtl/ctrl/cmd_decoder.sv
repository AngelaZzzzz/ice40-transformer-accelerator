////////////////////////////////////////////////////////////////////////////////
// cmd_decoder
//   SPI command decoder for memory, program, run and display access
////////////////////////////////////////////////////////////////////////////////

module cmd_decoder(input  logic        clk,
                   input  logic        rst,
                   input  logic        cs_active,
                   input  logic        cs_start,
                   input  logic [7:0]  rx_byte,
                   input  logic        rx_valid,
                   input  logic        busy,
                   input  logic [63:0] spi_rdata,
                   input  logic [15:0] sb_rdata,
                   output logic [7:0]  tx_byte,
                   output logic        spi_we,
                   output logic        spi_re,
                   output logic [13:0] spi_addr,
                   output logic [63:0] spi_wdata,
                   output logic        pm_we,
                   output logic [7:0]  pm_waddr,
                   output logic [47:0] pm_wdata,
                   output logic        run,
                   output logic [4:0]  run_letter,
                   output logic [3:0]  run_pos,
                   output logic [4:0]  sb_raddr,
                   output logic        tb_we,
                   output logic [9:0]  tb_addr,
                   output logic [7:0]  tb_data,
                   output logic        scroll_we,
                   output logic [3:0]  scroll_data);

    // TODO(zach): implement per docs/interface_spec.md section 7

    assign tx_byte = '0;
    assign spi_we = 1'b0;
    assign spi_re = 1'b0;
    assign spi_addr = '0;
    assign spi_wdata = '0;
    assign pm_we = 1'b0;
    assign pm_waddr = '0;
    assign pm_wdata = '0;
    assign run = 1'b0;
    assign run_letter = '0;
    assign run_pos = '0;
    assign sb_raddr = '0;
    assign tb_we = 1'b0;
    assign tb_addr = '0;
    assign tb_data = '0;
    assign scroll_we = 1'b0;
    assign scroll_data = '0;

endmodule
