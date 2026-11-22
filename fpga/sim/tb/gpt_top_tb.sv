`timescale 1ns/1ps

////////////////////////////////////////////////////////////////////////////////
// gpt_top_tb
//   Runs the bring-up sequence over SPI against gpt_top with the bring-up
//   vector registers and text screen: PLL lock on the LED, write and read
//   back the output-layer weights from spram.mem, load the two-instruction
//   program, RUN BOS at position 0 with DONE timing, compare the 27 scores
//   with pos0_scores.mem, WRITE_CHAR into the text buffer, and check the
//   hsync period. Run vvp from fpga/mem.
////////////////////////////////////////////////////////////////////////////////

module gpt_top_tb();
    logic        rst_n;
    logic        clk_12m;
    logic        sck;
    logic        mosi;
    logic        cs_n;
    logic        miso;
    logic        done;
    logic        vga_hs;
    logic        vga_vs;
    logic        vga_r;
    logic        vga_g;
    logic        vga_b;
    logic        led;
    logic [63:0] spram_words [0:13439];
    logic [47:0] prog_words [0:1];
    logic [15:0] exp_scores [0:26];
    realtime     t_run;
    realtime     t_done;
    realtime     t_fall;
    int          errors;

    localparam int OUT_BASE = 'h3180;
    localparam int OUT_WORDS = 256;

    gpt_top #(
        .VREG_INIT("bringup_vreg.mem"),
        .TEXT_INIT("bringup_text.mem")
    ) dut(
        .rst_n(rst_n),
        .clk_12m(clk_12m),
        .sck(sck),
        .mosi(mosi),
        .cs_n(cs_n),
        .miso(miso),
        .done(done),
        .vga_hs(vga_hs),
        .vga_vs(vga_vs),
        .vga_r(vga_r),
        .vga_g(vga_g),
        .vga_b(vga_b),
        .led(led)
    );

    spi_master_bfm bfm(
        .miso(miso),
        .sck(sck),
        .mosi(mosi),
        .cs_n(cs_n)
    );

    initial begin
        clk_12m = 1'b0;
        forever #41.6665 clk_12m = ~clk_12m;
    end

    // iCE40 flip-flops power up at 0. The pixel-reset synchronizer only
    // sees pix_clk edges after lock, and the SPRAM controls are sampled at
    // the first clk edge, before reset has cleared them, so these start at
    // 0 here too
    initial begin
        dut.pix_rst_sync.meta = 1'b0;
        dut.pix_rst_sync.q = 1'b0;
        dut.seq.busy = 1'b0;
        dut.decoder.spi_we = 1'b0;
        dut.decoder.spi_re = 1'b0;
        dut.matvec.issuing = 1'b0;
    end

    // Times of the run pulse and of DONE rising
    always @(posedge dut.clk) begin
        if (dut.run) t_run = $realtime;
    end

    always @(posedge done) t_done = $realtime;

    always @(negedge done) t_fall = $realtime;

    task automatic check_lock;
        int waited;
        waited = 0;
        while ((dut.rst || led !== 1'b1) && waited < 50000) begin
            #10;
            waited++;
        end
        assert (dut.rst === 1'b0 && led === 1'b1) else begin
            errors++;
            $error("expected reset released and led=1, got rst=%b led=%b",
                   dut.rst, led);
        end
    endtask

    task automatic check_spram;
        int mismatches;
        logic [63:0] word;
        bfm.tx_buf[0] = 8'h01;
        bfm.tx_buf[1] = 8'(OUT_BASE >> 8);
        bfm.tx_buf[2] = 8'(OUT_BASE);
        for (int w = 0; w < OUT_WORDS; w++) begin
            word = spram_words[OUT_BASE + w];
            for (int k = 0; k < 8; k++) begin
                bfm.tx_buf[3 + 8 * w + k] = word[8 * k +: 8];
            end
        end
        bfm.transfer(3 + 8 * OUT_WORDS);

        bfm.tx_buf[0] = 8'h02;
        for (int i = 3; i < 4 + 8 * OUT_WORDS; i++) begin
            bfm.tx_buf[i] = 8'h00;
        end
        bfm.transfer(4 + 8 * OUT_WORDS);

        mismatches = 0;
        for (int w = 0; w < OUT_WORDS; w++) begin
            word = spram_words[OUT_BASE + w];
            for (int k = 0; k < 8; k++) begin
                if (bfm.rx_buf[4 + 8 * w + k] !== word[8 * k +: 8]) begin
                    mismatches++;
                end
            end
        end
        assert (mismatches == 0) else begin
            errors++;
            $error("SPRAM readback: expected 0 mismatched bytes, got %0d",
                   mismatches);
        end
    endtask

    task automatic write_prog;
        bfm.tx_buf[0] = 8'h03;
        bfm.tx_buf[1] = 8'h00;
        for (int i = 0; i < 2; i++) begin
            for (int k = 0; k < 6; k++) begin
                bfm.tx_buf[2 + 6 * i + k] = prog_words[i][8 * (5 - k) +: 8];
            end
        end
        bfm.transfer(14);
    endtask

    task automatic check_run;
        logic was_done;
        was_done = done;
        t_run = 0;
        t_done = 0;
        t_fall = 0;
        bfm.tx_buf[0] = 8'h04;
        bfm.tx_buf[1] = 8'd26;
        bfm.tx_buf[2] = 8'd0;
        bfm.transfer(3);
        if (was_done) begin
            assert (t_run > 0 && t_fall == t_run) else begin
                errors++;
                $error("expected DONE to fall at the RUN pulse (%0t), got %0t",
                       t_run, t_fall);
            end
        end
        #20000;
        assert (done === 1'b1 && t_done > t_run &&
                t_done - t_run <= 20000) else begin
            errors++;
            $error("expected DONE within 20 us of RUN, got done=%b after %0t",
                   done, t_done - t_run);
        end
        $display("DONE %0.0f ns after the RUN pulse", t_done - t_run);
    endtask

    task automatic check_scores;
        logic [15:0] score;
        bfm.tx_buf[0] = 8'h05;
        for (int i = 1; i < 56; i++) begin
            bfm.tx_buf[i] = 8'h00;
        end
        bfm.transfer(56);
        for (int i = 0; i < 27; i++) begin
            score = {bfm.rx_buf[2 + 2 * i], bfm.rx_buf[3 + 2 * i]};
            assert (score === exp_scores[i]) else begin
                errors++;
                $error("score %0d: expected %h, got %h", i, exp_scores[i],
                       score);
            end
        end
    endtask

    task automatic check_write_char;
        bfm.tx_buf[0] = 8'h06;
        bfm.tx_buf[1] = 8'h00;
        bfm.tx_buf[2] = 8'd41;
        bfm.tx_buf[3] = 8'h4F;
        bfm.tx_buf[4] = 8'hCB;
        bfm.transfer(5);
        assert (dut.tbuf.mem[41] === 8'h4F && dut.tbuf.mem[42] === 8'hCB)
        else begin
            errors++;
            $error("text cells 41, 42: expected 4f cb, got %h %h",
                   dut.tbuf.mem[41], dut.tbuf.mem[42]);
        end
    endtask

    task automatic check_hsync;
        realtime t0, period;
        @(negedge vga_hs);
        t0 = $realtime;
        @(negedge vga_hs);
        period = $realtime - t0;
        assert (period > 31808.0 && period < 31872.0) else begin
            errors++;
            $error("expected hsync period 31840 ns, got %0.1f ns", period);
        end
    endtask

    initial begin
        errors = 0;
        rst_n = 1'b1;
        $readmemh("spram.mem", spram_words);
        $readmemh("bringup_prog.mem", prog_words);
        $readmemh("../sim/vectors/prefix_empty/pos0_scores.mem", exp_scores);

        // Verify reset release and PLL lock on the LED
        check_lock();

        // Verify output-layer weights write and read back
        check_spram();

        // Verify the program runs, DONE timing and the scores against the
        // Python integer model; the second run starts with DONE high
        write_prog();
        check_run();
        check_scores();
        check_run();
        check_scores();

        // Verify WRITE_CHAR reaches the text buffer
        check_write_char();

        // Verify the hsync period
        check_hsync();

        if (errors == 0) $display("PASSED");
        else             $display("FAILED: %0d errors", errors);
        $stop();
    end

endmodule
