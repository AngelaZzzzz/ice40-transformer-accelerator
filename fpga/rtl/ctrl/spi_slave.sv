////////////////////////////////////////////////////////////////////////////////
// spi_slave
//   SPI mode 0 slave, MSB first, oversampled in the clk domain. SCK, MOSI
//   and CS pass through the same two-flop synchronizer. tx_byte is loaded
//   on the 8th SCK rising edge of each byte and sent during the next byte;
//   the first byte after CS falls sends 0x00. MISO changes right after each
//   detected SCK rising edge and is 0 while CS is inactive.
//   Requires SCK <= fclk / 8 (5 MHz at 48 MHz).
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

    logic       sck_sync, mosi_sync, sck_prev, cs_prev, sck_rise;
    logic [2:0] bit_cnt;
    logic [6:0] rx_shift;
    logic [7:0] tx_shift;

    synchronizer #(.WIDTH(3)) in_sync(
        .clk(clk),
        .rst(rst),
        .d({sck, mosi, ~cs_n}),
        .q({sck_sync, mosi_sync, cs_active})
    );

    always_ff @(posedge clk) begin
        if (rst) begin
            sck_prev <= 1'b0;
            cs_prev <= 1'b0;
        end else begin
            sck_prev <= sck_sync;
            cs_prev <= cs_active;
        end
    end

    assign sck_rise = sck_sync & ~sck_prev;
    assign cs_start = cs_active & ~cs_prev;

    always_ff @(posedge clk) begin
        if (rst || !cs_active) begin
            bit_cnt <= 3'd0;
            tx_shift <= 8'h00;
            rx_valid <= 1'b0;
        end else begin
            rx_valid <= 1'b0;
            if (sck_rise) begin
                bit_cnt <= bit_cnt + 3'd1;
                if (bit_cnt == 3'd7) begin
                    rx_byte <= {rx_shift, mosi_sync};
                    rx_valid <= 1'b1;
                    tx_shift <= tx_byte;
                end else begin
                    rx_shift <= {rx_shift[5:0], mosi_sync};
                    tx_shift <= {tx_shift[6:0], 1'b0};
                end
            end
        end
    end

    assign miso = cs_active & tx_shift[7];

endmodule
