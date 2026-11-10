`timescale 1ns/1ps

////////////////////////////////////////////////////////////////////////////////
// spram_mem_tb
//   Testbench for spram_mem
////////////////////////////////////////////////////////////////////////////////

// Self-checking. Compile with the behavioral model sim/models/SP256K.sv.
//
// A 64-bit shadow memory predicts every read. Unwritten bytes are X in both
// the shadow and the model, and comparisons use !==, so a read of an
// unwritten byte must also come back X.
//
// Checked every cycle: a read on either port returns the shadow word
// exactly one cycle later, and with no access rdata holds the last value
// read.
//
// Phases:
//   1. SPI full-word writes to an address pool (including 0 and 0x3FFF);
//   2. back-to-back SPI reads of the pool;
//   3. core writes of one byte lane at a time, each read back, so a wrong
//      lane-to-nibble mapping shows up as a changed neighbour byte;
//   4. random mix of reads, writes and idle cycles on both ports, random
//      byte masks, random busy switching, and random values on every
//      field of the port that does not own the SPRAM.
//
// Prints "TEST PASSED" or "TEST FAILED" on the last line.

module spram_mem_tb();

    logic        clk = 1'b0;
    logic        rst;
    logic        busy;
    logic        core_re, core_we;
    logic [13:0] core_addr;
    logic [63:0] core_wdata;
    logic [7:0]  core_bytemask;
    logic        spi_re, spi_we;
    logic [13:0] spi_addr;
    logic [63:0] spi_wdata;
    logic [63:0] rdata;

    spram_mem dut(.*);

    always #10 clk = ~clk;

    // Shadow memory and checker state
    localparam int NPOOL = 64;

    logic [63:0] shadow [16384];
    logic [13:0] pool [NPOOL];
    logic [63:0] last_exp;          // value rdata should show
    logic        last_known = 1'b0; // 0 after a write (rdata undefined)
    int          n_chk = 0;
    int          n_err = 0;

    initial
        for (int i = 0; i < 16384; i++) shadow[i] = 'x;

    // Compares rdata with the prediction from the previous cycle. Called
    // at each falling edge, before driving the next cycle.
    task automatic check();
        if (last_known) begin
            n_chk++;
            if (rdata !== last_exp) begin
                n_err++;
                if (n_err <= 20)
                    $display("MISMATCH t=%0t: rdata=%h exp=%h",
                             $time, rdata, last_exp);
            end
        end
    endtask

    // One clock cycle. port: 1 = core (busy = 1), 0 = SPI (busy = 0). At
    // most one of w, r should be set. The port that does not own the SPRAM
    // gets random addresses and data with its enables low.
    task automatic cycle(input logic        port,
                         input logic        w,
                         input logic        r,
                         input logic [13:0] a,
                         input logic [63:0] d,
                         input logic [7:0]  m);
        logic [63:0] bm;
        @(negedge clk);
        check();

        busy          = port;
        core_we       = 1'b0;
        core_re       = 1'b0;
        spi_we        = 1'b0;
        spi_re        = 1'b0;
        core_addr     = $urandom;
        core_wdata    = {$urandom, $urandom};
        core_bytemask = $urandom;
        spi_addr      = $urandom;
        spi_wdata     = {$urandom, $urandom};

        if (port) begin
            core_we       = w;
            core_re       = r;
            core_addr     = a;
            core_wdata    = d;
            core_bytemask = m;
        end else begin
            spi_we    = w;
            spi_re    = r;
            spi_addr  = a;
            spi_wdata = d;
        end

        if (w) begin
            for (int l = 0; l < 8; l++)
                bm[8*l +: 8] = (port ? m[l] : 1'b1) ? 8'hFF : 8'h00;
            shadow[a]  = (shadow[a] & ~bm) | (d & bm);
            last_known = 1'b0;
        end else if (r) begin
            last_exp   = shadow[a];
            last_known = 1'b1;
        end
    endtask

    task automatic idle();
        cycle(1'b0, 1'b0, 1'b0, '0, '0, '0);
    endtask

    // Test sequence
    logic [13:0] a;
    int          op;

    initial begin
        rst     = 1'b1;
        busy    = 1'b0;
        core_we = 1'b0;
        core_re = 1'b0;
        spi_we  = 1'b0;
        spi_re  = 1'b0;

        pool[0] = 14'h0000;
        pool[1] = 14'h3FFF;
        for (int i = 2; i < NPOOL; i++) pool[i] = $urandom;
        repeat (2) idle();
        rst = 1'b0;

        // 1. SPI full-word writes
        for (int i = 0; i < NPOOL; i++)
            cycle(1'b0, 1'b1, 1'b0, pool[i], {$urandom, $urandom}, '0);

        // 2. Back-to-back SPI reads, then idle cycles to check hold
        for (int i = 0; i < NPOOL; i++)
            cycle(1'b0, 1'b0, 1'b1, pool[i], '0, '0);
        repeat (4) idle();

        // 3. One byte lane at a time on the core port, each read back
        for (int i = 0; i < 8; i++)
            for (int l = 0; l < 8; l++) begin
                cycle(1'b1, 1'b1, 1'b0, pool[i], {$urandom, $urandom},
                      8'(1 << l));
                cycle(1'b1, 1'b0, 1'b1, pool[i], '0, '0);
            end

        // 4. Random mix. Mostly pool addresses so reads hit written data;
        //    the rest exercise reads of unwritten (X) words.
        repeat (20000) begin
            a  = ($urandom_range(9) != 0) ? pool[$urandom_range(NPOOL - 1)]
                                          : 14'($urandom);
            op = $urandom_range(2);
            cycle($urandom_range(1), op == 0, op == 1, a,
                  {$urandom, $urandom}, $urandom);
        end

        repeat (2) idle();

        $display("spram_mem: %0d read/hold checks, %0d errors",
                 n_chk, n_err);
        if (n_chk < 10000) begin
            $display("too few checks; stimulus is broken");
            n_err++;
        end
        if (n_err == 0) $display("TEST PASSED");
        else            $display("TEST FAILED");
        $finish;
    end

endmodule
