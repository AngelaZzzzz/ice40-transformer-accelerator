`timescale 1ns/1ps

////////////////////////////////////////////////////////////////////////////////
// spi_test_top_tb
//   Runs the MCU MODE_SPI_TEST sequence against spi_test_top: five passes
//   writing and reading back 256 words of LCG data with different seeds,
//   RUN with DONE cleared then set, READ_SCORES against 16'hA5A5 ^ index,
//   and WRITE_CHAR toggling the LED once per character
////////////////////////////////////////////////////////////////////////////////

module spi_test_top_tb();
    logic        rst_n;
    logic        sck;
    logic        mosi;
    logic        cs_n;
    logic        miso;
    logic        done;
    logic        led;
    logic [31:0] seed;
    logic [7:0]  data [0:2047];
    int          errors;

    spi_test_top dut(
        .rst_n(rst_n),
        .sck(sck),
        .mosi(mosi),
        .cs_n(cs_n),
        .miso(miso),
        .done(done),
        .led(led)
    );

    spi_master_bfm bfm(
        .miso(miso),
        .sck(sck),
        .mosi(mosi),
        .cs_n(cs_n)
    );

    task automatic check_pass(input int pass);
        int mismatches;
        seed = pass + 1;
        bfm.tx_buf[0] = 8'h01;
        bfm.tx_buf[1] = 8'h00;
        bfm.tx_buf[2] = 8'h00;
        for (int i = 0; i < 2048; i++) begin
            seed = seed * 32'd1664525 + 32'd1013904223;
            data[i] = seed[31:24];
            bfm.tx_buf[3 + i] = data[i];
        end
        bfm.transfer(2051);

        bfm.tx_buf[0] = 8'h02;
        for (int i = 3; i < 2052; i++) begin
            bfm.tx_buf[i] = 8'h00;
        end
        bfm.transfer(2052);

        mismatches = 0;
        for (int i = 0; i < 2048; i++) begin
            if (bfm.rx_buf[4 + i] !== data[i]) mismatches++;
        end
        assert (mismatches == 0) else begin
            errors++;
            $error("pass %0d: expected 0 mismatched bytes, got %0d", pass,
                   mismatches);
        end
    endtask

    task automatic check_run;
        bfm.tx_buf[0] = 8'h04;
        bfm.tx_buf[1] = 8'd3;
        bfm.tx_buf[2] = 8'd2;
        bfm.transfer(3);
        assert (done === 1'b0) else begin
            errors++;
            $error("expected done=0 after RUN, got done=%b", done);
        end
        #5000;
        assert (done === 1'b1) else begin
            errors++;
            $error("expected done=1 100 cycles after RUN, got done=%b", done);
        end
    endtask

    task automatic check_read_scores;
        logic [15:0] word;
        bfm.tx_buf[0] = 8'h05;
        bfm.transfer(56);
        for (int i = 0; i < 27; i++) begin
            word = {bfm.rx_buf[2 + 2 * i], bfm.rx_buf[3 + 2 * i]};
            assert (word === (16'hA5A5 ^ 16'(i))) else begin
                errors++;
                $error("score %0d: expected %h, got %h", i,
                       16'hA5A5 ^ 16'(i), word);
            end
        end
    endtask

    task automatic check_write_char(input int n);
        logic expected;
        expected = led ^ n[0];
        bfm.tx_buf[0] = 8'h06;
        bfm.tx_buf[1] = 8'h00;
        bfm.tx_buf[2] = 8'h00;
        bfm.transfer(3 + n);
        assert (led === expected) else begin
            errors++;
            $error("%0d chars: expected led=%b, got led=%b", n, expected,
                   led);
        end
    endtask

    initial begin
        errors = 0;
        rst_n = 1'b1;
        #10000;

        // Verify five write and read-back passes with different seeds
        for (int pass = 0; pass < 5; pass++) begin
            check_pass(pass);
        end

        // Verify RUN clears DONE and the fake sequencer sets it
        check_run();

        // Verify the score pattern
        check_read_scores();

        // Verify the LED toggles once per text-buffer write
        check_write_char(3);
        check_write_char(2);

        if (errors == 0) $display("PASSED");
        else             $display("FAILED: %0d errors", errors);
        $stop();
    end

endmodule
