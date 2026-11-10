`timescale 1ns/1ps

////////////////////////////////////////////////////////////////////////////////
// spi_slave_tb
//   Self-checking testbench for spi_slave: 48 MHz core clock and 5 MHz SCK
//   with random byte spacing, so the SCK phase relative to clk varies. Each
//   frame checks every received byte and every MISO bit sampled on SCK
//   rising edges against the tx_byte value loaded for that byte.
////////////////////////////////////////////////////////////////////////////////

module spi_slave_tb();
    logic       clk;
    logic       rst;
    logic       sck;
    logic       mosi;
    logic       cs_n;
    logic       miso;
    logic       cs_active;
    logic       cs_start;
    logic       rx_valid;
    logic [7:0] tx_byte;
    logic [7:0] rx_byte;
    logic [7:0] expected;
    logic [7:0] got [0:65535];
    logic [7:0] loaded [0:65535];
    int         n_rx;
    int         n_frames;
    int         n_starts;
    int         errors;

    spi_slave dut(
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

    spi_master_bfm bfm(
        .miso(miso),
        .sck(sck),
        .mosi(mosi),
        .cs_n(cs_n)
    );

    initial begin
        clk = 0;
        forever begin
            #10.4167 clk = ~clk;
        end
    end

    // Record each received byte and the tx_byte loaded with it
    always @(posedge clk) begin
        if (rx_valid) begin
            got[n_rx] = rx_byte;
            loaded[n_rx] = tx_byte;
            n_rx = n_rx + 1;
            tx_byte <= $urandom;
        end
        if (cs_start) n_starts = n_starts + 1;
        if (!rst) begin
            assert (cs_active || !miso) else begin
                errors++;
                $error("expected miso=0 while CS is inactive, got miso=1");
            end
        end
    end

    task automatic check_frame(input int n, input int jitter_ns);
        int base;
        base = n_rx;
        n_frames++;
        bfm.jitter_ns = jitter_ns;
        for (int b = 0; b < n; b++) begin
            bfm.tx_buf[b] = $urandom;
        end
        bfm.transfer(n);

        assert (n_rx == base + n) else begin
            errors++;
            $error("frame %0d: expected %0d bytes, got %0d", n_frames, n,
                   n_rx - base);
        end
        for (int b = 0; b < n; b++) begin
            assert (got[base + b] === bfm.tx_buf[b]) else begin
                errors++;
                $error("frame %0d byte %0d: expected rx_byte=%h, got %h",
                       n_frames, b, bfm.tx_buf[b], got[base + b]);
            end
            expected = (b == 0) ? 8'h00 : loaded[base + b - 1];
            assert (bfm.rx_buf[b] === expected) else begin
                errors++;
                $error("frame %0d byte %0d: expected miso=%h, got %h",
                       n_frames, b, expected, bfm.rx_buf[b]);
            end
        end
    endtask

    initial begin
        errors = 0;
        n_rx = 0;
        n_frames = 0;
        n_starts = 0;
        tx_byte = 8'h5A;
        rst = 1'b1;
        #200;
        @(negedge clk);
        rst = 1'b0;
        #500;

        // Verify single-byte frames send 0x00
        repeat (5) check_frame(1, 0);

        // Verify random frames with random byte spacing
        for (int f = 0; f < 300; f++) begin
            #($urandom_range(300, 0));
            check_frame($urandom_range(20, 1), $urandom_range(60, 0));
        end

        // Verify one cs_start pulse per frame
        assert (n_starts == n_frames) else begin
            errors++;
            $error("expected %0d cs_start pulses, got %0d", n_frames,
                   n_starts);
        end

        if (errors == 0) $display("PASSED");
        else             $display("FAILED: %0d errors", errors);
        $stop();
    end

endmodule
