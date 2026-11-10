`timescale 1ns/1ps

////////////////////////////////////////////////////////////////////////////////
// cmd_decoder_tb
//   Self-checking testbench for spi_slave and cmd_decoder against behavioral
//   memories: every command, reads across word boundaries and the 14-bit
//   address wrap, writes ignored while busy, aborted commands, an unknown
//   opcode, and back-to-back commands with random byte spacing.
////////////////////////////////////////////////////////////////////////////////

module cmd_decoder_tb();
    logic        clk;
    logic        rst;
    logic        sck;
    logic        mosi;
    logic        cs_n;
    logic        miso;
    logic        busy;
    logic        cs_active;
    logic        cs_start;
    logic        rx_valid;
    logic [7:0]  rx_byte;
    logic [7:0]  tx_byte;
    logic        spi_we;
    logic        spi_re;
    logic [13:0] spi_addr;
    logic [63:0] spi_wdata;
    logic [63:0] spi_rdata;
    logic        pm_we;
    logic [7:0]  pm_waddr;
    logic [47:0] pm_wdata;
    logic        run;
    logic [4:0]  run_letter;
    logic [3:0]  run_pos;
    logic [4:0]  sb_raddr;
    logic [15:0] sb_rdata;
    logic        tb_we;
    logic [9:0]  tb_addr;
    logic [7:0]  tb_data;
    logic        scroll_we;
    logic [3:0]  scroll_data;
    logic [63:0] spram [0:16383];
    logic [63:0] exp_spram [0:16383];
    logic [47:0] prog [0:255];
    logic [15:0] scores [0:31];
    logic [7:0]  tbuf [0:1023];
    logic [3:0]  scroll;
    logic [4:0]  last_letter;
    logic [3:0]  last_pos;
    int          n_we;
    int          n_pm;
    int          n_run;
    int          n_tb;
    int          n_scroll;
    int          n_run_late;
    int          errors;

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

    cmd_decoder dut(
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

    // Behavioral memories
    always @(posedge clk) begin
        if (spi_re) spi_rdata <= spram[spi_addr];
        if (spi_we) begin
            spram[spi_addr] <= spi_wdata;
            n_we = n_we + 1;
        end
        if (pm_we) begin
            prog[pm_waddr] <= pm_wdata;
            n_pm = n_pm + 1;
        end
        sb_rdata <= scores[sb_raddr];
        if (tb_we) begin
            tbuf[tb_addr] <= tb_data;
            n_tb = n_tb + 1;
        end
        if (scroll_we) begin
            scroll <= scroll_data;
            n_scroll = n_scroll + 1;
        end
        if (run) begin
            last_letter <= run_letter;
            last_pos <= run_pos;
            n_run = n_run + 1;
            if (cs_n) n_run_late = n_run_late + 1;
        end
    end

    task automatic set_header(input logic [7:0] opcode, input int addr);
        bfm.tx_buf[0] = opcode;
        bfm.tx_buf[1] = 8'((addr >> 8) & 8'h3F);
        bfm.tx_buf[2] = 8'(addr & 8'hFF);
    endtask

    task automatic check_write_spram(input int addr, input int nwords);
        int          n_we0;
        logic [63:0] word;
        n_we0 = n_we;
        set_header(8'h01, addr);
        for (int w = 0; w < nwords; w++) begin
            word = {$urandom, $urandom};
            for (int k = 0; k < 8; k++) begin
                bfm.tx_buf[3 + 8 * w + k] = word[8 * k +: 8];
            end
            if (!busy) exp_spram[(addr + w) & 16'h3FFF] = word;
        end
        bfm.transfer(3 + 8 * nwords);

        assert (n_we == n_we0 + (busy ? 0 : nwords)) else begin
            errors++;
            $error("write %h, busy=%b: expected %0d word writes, got %0d",
                   addr, busy, busy ? 0 : nwords, n_we - n_we0);
        end
        for (int w = 0; w < nwords; w++) begin
            assert (spram[(addr + w) & 16'h3FFF] ===
                    exp_spram[(addr + w) & 16'h3FFF]) else begin
                errors++;
                $error("SPRAM %h: expected %h, got %h", (addr + w) & 16'h3FFF,
                       exp_spram[(addr + w) & 16'h3FFF],
                       spram[(addr + w) & 16'h3FFF]);
            end
        end
    endtask

    task automatic check_read_spram(input int addr, input int nwords);
        logic [63:0] word;
        set_header(8'h02, addr);
        for (int i = 3; i < 4 + 8 * nwords; i++) begin
            bfm.tx_buf[i] = $urandom;
        end
        bfm.transfer(4 + 8 * nwords);

        for (int w = 0; w < nwords; w++) begin
            for (int k = 0; k < 8; k++) begin
                word[8 * k +: 8] = bfm.rx_buf[4 + 8 * w + k];
            end
            assert (word === exp_spram[(addr + w) & 16'h3FFF]) else begin
                errors++;
                $error("read %h: expected %h, got %h", (addr + w) & 16'h3FFF,
                       exp_spram[(addr + w) & 16'h3FFF], word);
            end
        end
    endtask

    task automatic check_aborted_write(input int nbytes, input int nbits);
        int n_we0;
        n_we0 = n_we;
        set_header(8'h01, 16'h0210);
        for (int i = 3; i < 3 + nbytes + 1; i++) begin
            bfm.tx_buf[i] = $urandom;
        end
        bfm.abort(3 + nbytes, nbits);
        assert (n_we == n_we0) else begin
            errors++;
            $error("aborted write: expected 0 word writes, got %0d",
                   n_we - n_we0);
        end
    endtask

    task automatic check_write_prog(input logic [7:0] addr, input int ninstr);
        int          n_pm0;
        logic [47:0] instr [0:15];
        n_pm0 = n_pm;
        bfm.tx_buf[0] = 8'h03;
        bfm.tx_buf[1] = addr;
        for (int j = 0; j < ninstr; j++) begin
            instr[j] = {$urandom, $urandom};
            for (int k = 0; k < 6; k++) begin
                bfm.tx_buf[2 + 6 * j + k] = instr[j][8 * (5 - k) +: 8];
            end
        end
        bfm.transfer(2 + 6 * ninstr);

        assert (n_pm == n_pm0 + ninstr) else begin
            errors++;
            $error("expected %0d instruction writes, got %0d", ninstr,
                   n_pm - n_pm0);
        end
        for (int j = 0; j < ninstr; j++) begin
            assert (prog[8'(addr + j)] === instr[j]) else begin
                errors++;
                $error("prog %0d: expected %h, got %h", 8'(addr + j),
                       instr[j], prog[8'(addr + j)]);
            end
        end
    endtask

    task automatic check_run(input logic [4:0] letter, input logic [3:0] pos);
        int n_run0;
        n_run0 = n_run;
        bfm.tx_buf[0] = 8'h04;
        bfm.tx_buf[1] = 8'(letter);
        bfm.tx_buf[2] = 8'(pos);
        bfm.transfer(3);
        assert (n_run == n_run0 + 1 && last_letter == letter &&
                last_pos == pos && n_run_late == 0) else begin
            errors++;
            $error("expected 1 run (%0d, %0d), 0 late; got %0d (%0d, %0d), %0d",
                   letter, pos, n_run - n_run0, last_letter, last_pos,
                   n_run_late);
        end
    endtask

    task automatic check_read_scores;
        logic [15:0] word;
        bfm.tx_buf[0] = 8'h05;
        for (int i = 1; i < 56; i++) begin
            bfm.tx_buf[i] = $urandom;
        end
        bfm.transfer(56);
        for (int i = 0; i < 27; i++) begin
            word = {bfm.rx_buf[2 + 2 * i], bfm.rx_buf[3 + 2 * i]};
            assert (word === scores[i]) else begin
                errors++;
                $error("score %0d: expected %h, got %h", i, scores[i], word);
            end
        end
    endtask

    task automatic check_write_char(input int cell_idx, input int n);
        int         n_tb0;
        logic [7:0] chars [0:63];
        n_tb0 = n_tb;
        set_header(8'h06, cell_idx);
        for (int i = 0; i < n; i++) begin
            chars[i] = $urandom;
            bfm.tx_buf[3 + i] = chars[i];
        end
        bfm.transfer(3 + n);

        assert (n_tb == n_tb0 + n) else begin
            errors++;
            $error("expected %0d character writes, got %0d", n, n_tb - n_tb0);
        end
        for (int i = 0; i < n; i++) begin
            assert (tbuf[(cell_idx + i) % 1024] === chars[i]) else begin
                errors++;
                $error("cell %0d: expected %h, got %h", (cell_idx + i) % 1024,
                       chars[i], tbuf[(cell_idx + i) % 1024]);
            end
        end
    endtask

    task automatic check_scroll(input logic [3:0] offset);
        int n_scroll0;
        n_scroll0 = n_scroll;
        bfm.tx_buf[0] = 8'h07;
        bfm.tx_buf[1] = 8'(offset);
        bfm.transfer(2);
        assert (n_scroll == n_scroll0 + 1 && scroll === offset) else begin
            errors++;
            $error("expected one scroll write of %0d, got %0d writes, %0d",
                   offset, n_scroll - n_scroll0, scroll);
        end
    endtask

    task automatic check_unknown_opcode(input logic [7:0] opcode);
        int n_writes0;
        n_writes0 = n_we + n_pm + n_run + n_tb + n_scroll;
        bfm.tx_buf[0] = opcode;
        for (int i = 1; i < 40; i++) begin
            bfm.tx_buf[i] = 8'(1 + i % 7);
        end
        bfm.transfer(40);
        assert (n_we + n_pm + n_run + n_tb + n_scroll == n_writes0) else begin
            errors++;
            $error("opcode %h: expected no side effects, got %0d", opcode,
                   n_we + n_pm + n_run + n_tb + n_scroll - n_writes0);
        end
    endtask

    initial begin
        errors = 0;
        n_we = 0;
        n_pm = 0;
        n_run = 0;
        n_tb = 0;
        n_scroll = 0;
        n_run_late = 0;
        busy = 1'b0;
        for (int i = 0; i < 16384; i++) begin
            spram[i] = {$urandom, $urandom};
            exp_spram[i] = spram[i];
        end
        for (int i = 0; i < 32; i++) begin
            scores[i] = $urandom;
        end
        rst = 1'b1;
        #200;
        @(negedge clk);
        rst = 1'b0;
        #500;
        bfm.jitter_ns = 50;

        // Verify SPRAM writes and reads across the 14-bit address wrap
        check_write_spram(16'h3FF5, 20);
        check_read_spram(16'h3FF5, 20);
        check_read_spram(16'h3FFF, 1);
        check_read_spram(16'h0003, 7);
        check_write_spram(16'h0123, 1);
        check_read_spram(16'h0122, 3);

        // Verify WRITE_SPRAM is ignored while busy
        busy = 1'b1;
        check_write_spram(16'h0200, 2);
        busy = 1'b0;
        check_read_spram(16'h0200, 2);

        // Verify aborted commands have no effect on later commands
        check_aborted_write(5, 3);
        set_header(8'h02, 16'h3FF5);
        bfm.abort(6, 4);
        check_read_spram(16'h3FF5, 3);

        // Verify WRITE_PROG across the 8-bit address wrap
        check_write_prog(8'hFE, 3);

        // Verify RUN pulses while CS is low
        check_run(5'd26, 4'd15);
        check_run(5'd0, 4'd3);

        // Verify READ_SCORES returns scores 0 to 26, high byte first
        check_read_scores();

        // Verify WRITE_CHAR across the 10-bit address wrap and SCROLL
        check_write_char(1010, 30);
        check_scroll(4'd14);

        // Verify an unknown opcode is ignored until CS rises
        check_unknown_opcode(8'h55);
        check_unknown_opcode(8'h00);
        check_read_spram(16'h3FF5, 20);

        if (errors == 0) $display("PASSED");
        else             $display("FAILED: %0d errors", errors);
        $stop();
    end

endmodule
