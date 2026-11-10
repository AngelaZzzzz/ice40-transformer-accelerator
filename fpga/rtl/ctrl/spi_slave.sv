////////////////////////////////////////////////////////////////////////////////
// spi_slave
//   SPI mode 0 slave, MSB first, oversampled in the clk domain
////////////////////////////////////////////////////////////////////////////////

module spi_slave(input  logic       clk,
                 input  logic       rst,
                 input  logic       sck,
                 input  logic       mosi,
                 input  logic       cs_n,
                 input  logic [7:0] tx_byte,
                 output logic       miso,
                 output logic       cs_active,
                 output logic       cs_start,
                 output logic [7:0] rx_byte,
                 output logic       rx_valid);

    // TODO(zach): implement per docs/interface_spec.md section 7

    assign miso = 1'b0;
    assign cs_active = 1'b0;
    assign cs_start = 1'b0;
    assign rx_byte = '0;
    assign rx_valid = 1'b0;

endmodule
