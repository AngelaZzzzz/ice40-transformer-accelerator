////////////////////////////////////////////////////////////////////////////////
// spi_test_top
//   SPI bring-up top: decoder, test memory and fake sequencer
////////////////////////////////////////////////////////////////////////////////

module spi_test_top(input  logic rst_n,
                    input  logic sck,
                    input  logic mosi,
                    input  logic cs_n,
                    output logic miso,
                    output logic done,
                    output logic led);

    // TODO(zach): implement per docs/interface_spec.md section 7

    assign miso = 1'b0;
    assign done = 1'b0;
    assign led = 1'b0;

endmodule
