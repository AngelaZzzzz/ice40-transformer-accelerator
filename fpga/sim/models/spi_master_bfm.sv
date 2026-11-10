`timescale 1ns/1ps

////////////////////////////////////////////////////////////////////////////////
// spi_master_bfm
//   Simulation-only SPI mode 0 master, MSB first. transfer(n) frames
//   tx_buf[0..n-1] with CS and records MISO, sampled on each SCK rising
//   edge, into rx_buf. abort(n, nbits) sends n bytes and nbits more bits,
//   then raises CS. Up to jitter_ns of random delay precedes each byte.
////////////////////////////////////////////////////////////////////////////////

module spi_master_bfm #(
    parameter real HALF_NS = 100.0
) (
    input  logic miso,

    output logic sck,
    output logic mosi,
    output logic cs_n
);

    logic [7:0] tx_buf [0:4095];
    logic [7:0] rx_buf [0:4095];
    int         jitter_ns;

    initial begin
        sck = 1'b0;
        mosi = 1'b0;
        cs_n = 1'b1;
        jitter_ns = 0;
    end

    task automatic send_bits(input logic [7:0] tx, input int nbits,
                             output logic [7:0] rx);
        rx = 8'h00;
        for (int i = 7; i > 7 - nbits; i--) begin
            mosi = tx[i];
            #(HALF_NS);
            sck = 1'b1;
            rx[i] = miso;
            #(HALF_NS);
            sck = 1'b0;
        end
    endtask

    task automatic frame(input int n, input int nbits);
        logic [7:0] rx;
        cs_n = 1'b0;
        #(HALF_NS);
        for (int b = 0; b < n; b++) begin
            if (jitter_ns > 0) begin
                #($urandom_range(jitter_ns, 0));
            end
            send_bits(tx_buf[b], 8, rx);
            rx_buf[b] = rx;
        end
        if (nbits > 0) begin
            send_bits(tx_buf[n], nbits, rx);
        end
        #(HALF_NS);
        cs_n = 1'b1;
        #(4 * HALF_NS);
    endtask

    task automatic transfer(input int n);
        frame(n, 0);
    endtask

    task automatic abort(input int n, input int nbits);
        frame(n, nbits);
    endtask

endmodule
