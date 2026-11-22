`timescale 1ns/1ps

////////////////////////////////////////////////////////////////////////////////
// kv_store_tb
//   Testbench for kv_store
////////////////////////////////////////////////////////////////////////////////

// Self-checking, with the real vreg_file and spram_mem (SP256K model).
// The SPRAM starts random (loaded over the SPI port), so a byte-masked
// write that touches the wrong lane shows up. Vector registers are
// random, so the high byte of each source word must be dropped.
//
// Each KVSTORE is checked against a model of interface spec section 4:
// all 16,384 SPRAM words (read through the SP256K models) must match
// after every run, done must pulse exactly once, and the number of
// writes must be 64 (K layout) or 8 (V layout). Every cycle the
// testbench checks the OR-bus rule (section 1): sp_addr, sp_wdata and
// sp_bytemask are 0 without sp_we, and every output is 0 between
// instructions.
//
// Cases: the program's sequence (K and V for both layers at every
// position, then the caches compared with the transposed layouts they
// should hold), other opcodes ignored, then random base, src, pos, ALT
// and unused fields.
//
// Prints "TEST PASSED" or "TEST FAILED" on the last line.

module kv_store_tb();

    import gpt_pkg::*;

    logic        clk, rst;
    instr_t      instr;
    logic [4:0]  letter;
    logic [3:0]  pos;
    logic        start, done;
    logic [15:0] ra_data, rb_data;
    logic [9:0]  ra_addr;
    logic        sp_we;
    logic [13:0] sp_addr;
    logic [63:0] sp_wdata, sp_rdata;
    logic [7:0]  sp_bytemask;

    logic        busy, spi_we;
    logic [13:0] spi_addr;
    logic [63:0] spi_wdata;

    kv_store dut(
        .clk(clk),
        .rst(rst),
        .instr(instr),
        .letter(letter),
        .pos(pos),
        .start(start),
        .done(done),
        .ra_data(ra_data),
        .ra_addr(ra_addr),
        .sp_we(sp_we),
        .sp_addr(sp_addr),
        .sp_wdata(sp_wdata),
        .sp_bytemask(sp_bytemask)
    );

    vreg_file vregs(
        .clk(clk),
        .rst(rst),
        .ra_addr(ra_addr),
        .rb_addr(10'd0),
        .w_en(1'b0),
        .w_addr(10'd0),
        .w_data(16'd0),
        .ra_data(ra_data),
        .rb_data(rb_data)
    );

    spram_mem spm_dut(
        .clk(clk),
        .rst(rst),
        .busy(busy),
        .core_re(1'b0),
        .core_we(sp_we),
        .core_addr(sp_addr),
        .core_wdata(sp_wdata),
        .core_bytemask(sp_bytemask),
        .spi_re(1'b0),
        .spi_we(spi_we),
        .spi_addr(spi_addr),
        .spi_wdata(spi_wdata),
        .rdata(sp_rdata)
    );

    initial clk = 1'b0;
    always #10.417 clk = ~clk;

    logic [63:0] spm [0:16383];
    int          n_err  = 0;
    int          n_runs = 0;
    int          n_done = 0;
    int          n_wr   = 0;
    bit          active = 0;

    task automatic error(input string msg);
        n_err++;
        if (n_err <= 20) $display("ERROR at %0t: %s", $time, msg);
    endtask

    always @(negedge clk)
        if (!rst) begin
            if (done)  n_done++;
            if (sp_we) n_wr++;
            if (!sp_we && (sp_addr !== '0 || sp_wdata !== '0 ||
                           sp_bytemask !== '0))
                error("SPRAM port nonzero without sp_we");
            if (!active && (sp_we !== 1'b0 || ra_addr !== '0 ||
                            done !== 1'b0))
                error("outputs not 0 between instructions");
        end

    // SPRAM contents through the SP256K models
    function automatic logic [63:0] spram_word(input int a);
        return {spm_dut.g_blk[3].spram.mem[a], spm_dut.g_blk[2].spram.mem[a],
                spm_dut.g_blk[1].spram.mem[a], spm_dut.g_blk[0].spram.mem[a]};
    endfunction

    // Reference model (spec section 4)
    task automatic model(input instr_t ins, input int p);
        int          w, l;
        logic [15:0] x;
        for (int c = 0; c < 64; c++) begin
            x = vregs.mem[8 * ins.src + c];
            if (ins.flags[F_ALT]) begin
                w = 32 * (c >> 4) + 16 * ((c >> 3) & 1) + p;
                l = c & 7;
            end else begin
                w = 32 * (c >> 4) + 16 * (p >> 3) + (c & 15);
                l = p & 7;
            end
            spm[14'(ins.base + w)][8 * l +: 8] = x[7:0];
        end
    endtask

    task automatic run(input logic [3:0] op, input logic [6:0] src,
                       input logic [13:0] base, input bit alt,
                       input int p);
        instr_t ins;
        int     cyc, n_exp;
        logic   mine;
        ins         = {$urandom, $urandom};   // unused fields random
        ins[47:44]  = op;
        ins.src     = src;
        ins.base    = base;
        ins.flags[F_ALT] = alt;
        mine  = (op == OP_KVSTORE);
        n_exp = !mine ? 0 : alt ? 8 : 64;

        @(negedge clk);
        if (mine) model(ins, p);
        instr  = ins;
        letter = 5'($urandom_range(26));
        pos    = 4'(p);
        n_done = 0;
        n_wr   = 0;
        active = 1;
        start  = 1'b1;
        @(negedge clk);
        start  = 1'b0;
        cyc    = 1;
        if (mine) begin
            while (n_done == 0 && cyc < 1000) begin
                @(negedge clk);
                cyc++;
            end
            if (n_done == 0) error($sformatf("op %0d: no done", op));
        end
        active = 0;
        repeat (20) @(negedge clk);
        n_runs++;

        if (n_done != (mine ? 1 : 0))
            error($sformatf("op %0d: %0d done pulses", op, n_done));
        if (n_wr != n_exp)
            error($sformatf("op %0d alt %0d: %0d writes, expected %0d", op,
                            alt, n_wr, n_exp));
        for (int a = 0; a < 16384; a++)
            if (spram_word(a) !== spm[a])
                error($sformatf("alt %0d pos %0d: word %h = %h exp %h", alt,
                                p, a, spram_word(a), spm[a]));
        if (n_runs <= 2)
            $display("KVSTORE alt %0d: done after %0d cycles", alt, cyc);
    endtask

    task automatic scramble_vr();
        for (int a = 0; a < 1024; a++) vregs.mem[a] = $urandom;
    endtask

    // Program sequence: K and V of both layers at every position, then
    // check the caches hold K[p][c] and V[c][p] (spec section 4 tables)
    task automatic run_program();
        logic [7:0] k_exp [2][16][64];
        logic [7:0] v_exp [2][16][64];
        logic [13:0] a_k [2];
        logic [13:0] a_v [2];
        logic [63:0] w;
        logic [7:0]  got;
        a_k[0] = A_K0; a_k[1] = A_K1;
        a_v[0] = A_V0; a_v[1] = A_V1;
        for (int p = 0; p < 16; p++) begin
            scramble_vr();
            for (int li = 0; li < 2; li++) begin
                for (int c = 0; c < 64; c++) begin
                    k_exp[li][p][c] = vregs.mem[8 * VR_K + c][7:0];
                    v_exp[li][p][c] = vregs.mem[8 * VR_V + c][7:0];
                end
                run(OP_KVSTORE, VR_K, a_k[li], 1'b0, p);
                run(OP_KVSTORE, VR_V, a_v[li], 1'b1, p);
            end
        end
        // Head h at +32h; K: 16 positions x 16 channels (matrix layout,
        // row = position), V: 16 channels x 16 positions (row = channel)
        for (int li = 0; li < 2; li++)
            for (int h = 0; h < 4; h++)
                for (int r = 0; r < 16; r++)
                    for (int cc = 0; cc < 16; cc++) begin
                        w   = spram_word(a_k[li] + 32 * h + 16 * (r / 8)
                                         + cc);
                        got = w[8 * (r % 8) +: 8];
                        if (got !== k_exp[li][r][16 * h + cc])
                            error($sformatf("K%0d h%0d p%0d ch%0d", li, h,
                                            r, cc));
                        w   = spram_word(a_v[li] + 32 * h + 16 * (r / 8)
                                         + cc);
                        got = w[8 * (r % 8) +: 8];
                        if (got !== v_exp[li][cc][16 * h + r])
                            error($sformatf("V%0d h%0d ch%0d p%0d", li, h,
                                            r, cc));
                    end
    endtask

    initial begin
        rst    = 1'b1;
        start  = 1'b0;
        busy   = 1'b0;
        spi_we = 1'b0;
        instr  = '0;
        letter = '0;
        pos    = '0;
        repeat (3) @(negedge clk);
        rst = 1'b0;

        for (int a = 0; a < 16384; a++) begin
            spm[a]    = {$urandom, $urandom};
            spi_we    = 1'b1;
            spi_addr  = a;
            spi_wdata = spm[a];
            @(negedge clk);
        end
        spi_we = 1'b0;
        busy   = 1'b1;
        scramble_vr();
        @(negedge clk);

        run_program();

        for (int op = 0; op < 16; op++)
            if (op != OP_KVSTORE)
                run(op[3:0], 7'($urandom), 14'($urandom), $urandom_range(1),
                    $urandom_range(15));

        repeat (60) begin
            if ($urandom_range(1)) scramble_vr();
            run(OP_KVSTORE, 7'($urandom_range(120)), 14'($urandom),
                $urandom_range(1), $urandom_range(15));
        end

        $display("kv_store: %0d instructions, %0d errors", n_runs, n_err);
        if (n_err == 0) $display("TEST PASSED");
        else            $display("TEST FAILED");
        $finish;
    end

endmodule
