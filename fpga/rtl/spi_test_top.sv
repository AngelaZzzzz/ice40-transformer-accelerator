////////////////////////////////////////////////////////////////////////////////
// spi_test_top
//   SPI bring-up top: spi_slave and cmd_decoder with a 256 x 64-bit test
//   memory (address bits 7:0) for WRITE_SPRAM and READ_SPRAM, a score source
//   returning 16'hA5A5 ^ index, a fake sequencer that sets done 100 cycles
//   after RUN, and an LED that toggles on every text-buffer write
////////////////////////////////////////////////////////////////////////////////

module spi_test_top(input  logic rst_n,
                    input  logic sck,
                    input  logic mosi,
                    input  logic cs_n,
                    output logic miso,
                    output logic done,
                    output logic led);

    logic        clk, rst;
    logic        cs_active, cs_start, rx_valid;
    logic [7:0]  rx_byte, tx_byte;
    logic        spi_we, spi_re;
    logic [13:0] spi_addr;
    logic [63:0] spi_wdata, spi_rdata;
    logic        pm_we, run, tb_we, scroll_we;
    logic [7:0]  pm_waddr, tb_data;
    logic [47:0] pm_wdata;
    logic [4:0]  run_letter, sb_raddr;
    logic [3:0]  run_pos, scroll_data;
    logic [15:0] sb_rdata;
    logic [9:0]  tb_addr;
    logic [6:0]  seq_count;
    logic        busy;
    logic [63:0] test_mem [0:255];

    HSOSC #(.CLKHF_DIV("0b00")) hf_osc(
        .CLKHFPU(1'b1),
        .CLKHFEN(1'b1),
        .CLKHF(clk)
    );

    reset_gen reset(
        .clk(clk),
        .rst_n_async(rst_n),
        .rst(rst)
    );

    spi_slave spi(
        .clk(clk),
        .rst(rst),
        .sck(sck),
        .mosi(mosi),
        .cs_n(cs_n),
        .tx_byte(tx_byte),
        .miso(miso),
        .cs_active(cs_active),
        .cs_start(cs_start),
        .rx_byte(rx_byte),
        .rx_valid(rx_valid)
    );

    cmd_decoder decoder(
        .clk(clk),
        .rst(rst),
        .cs_active(cs_active),
        .cs_start(cs_start),
        .rx_byte(rx_byte),
        .rx_valid(rx_valid),
        .busy(busy),
        .spi_rdata(spi_rdata),
        .sb_rdata(sb_rdata),
        .tx_byte(tx_byte),
        .spi_we(spi_we),
        .spi_re(spi_re),
        .spi_addr(spi_addr),
        .spi_wdata(spi_wdata),
        .pm_we(pm_we),
        .pm_waddr(pm_waddr),
        .pm_wdata(pm_wdata),
        .run(run),
        .run_letter(run_letter),
        .run_pos(run_pos),
        .sb_raddr(sb_raddr),
        .tb_we(tb_we),
        .tb_addr(tb_addr),
        .tb_data(tb_data),
        .scroll_we(scroll_we),
        .scroll_data(scroll_data)
    );

    // Test memory
    always_ff @(posedge clk) begin
        if (spi_we) test_mem[spi_addr[7:0]] <= spi_wdata;
        if (spi_re) spi_rdata <= test_mem[spi_addr[7:0]];
    end

    // Score source
    always_ff @(posedge clk) begin
        sb_rdata <= 16'hA5A5 ^ {11'b0, sb_raddr};
    end

    // Fake sequencer
    always_ff @(posedge clk) begin
        if (rst) begin
            seq_count <= 7'd0;
            done <= 1'b0;
        end else if (run) begin
            seq_count <= 7'd100;
            done <= 1'b0;
        end else if (seq_count == 7'd1) begin
            seq_count <= 7'd0;
            done <= 1'b1;
        end else if (seq_count != 7'd0) begin
            seq_count <= seq_count - 7'd1;
        end
    end

    assign busy = (seq_count != 7'd0);

    // Text-buffer write indicator
    always_ff @(posedge clk) begin
        if (rst) led <= 1'b0;
        else if (tb_we) led <= ~led;
    end

endmodule
