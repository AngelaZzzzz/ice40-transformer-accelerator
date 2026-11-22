`timescale 1ns/1ps

////////////////////////////////////////////////////////////////////////////////
// vecop_tb
//   Testbench for vecop
////////////////////////////////////////////////////////////////////////////////

// Self-checking, with the real vreg_file and spram_mem (SP256K model).
// The SPRAM is filled over the SPI port with random bytes, a quarter of
// them -128 or 127 so that EMBED saturates; vector registers get random
// values with the same bias toward -32768, 32767 and 0.
//
// Each instruction is checked against a model written from interface
// spec section 3: the whole 1,024-word register file must match after
// every run (so no stray writes), done must pulse exactly once, after
// exactly C writes. Every cycle the testbench also checks the OR-bus
// rule (section 1): sp_addr is 0 without sp_re, w_addr and w_data are 0
// without w_en, and every output is 0 between instructions.
//
// Cases: the program's EMBED, VADD and VRELU shapes; EMBED over every
// letter (with BOS) and position and every shift; VMUL extremes
// (-32768 x -32768); other opcodes ignored; then random instructions.
// Operand placement follows the program guarantees: VADD and VMUL
// operands in different banks, VRELU src equal to dst or not overlapping.
//
// Prints "TEST PASSED" or "TEST FAILED" on the last line.

module vecop_tb();

    import gpt_pkg::*;

    logic        clk, rst;
    instr_t      instr;
    logic [4:0]  letter;
    logic [3:0]  pos;
    logic        start, done;
    logic [63:0] sp_rdata;
    logic [15:0] ra_data, rb_data;
    logic        sp_re;
    logic [13:0] sp_addr;
    logic [9:0]  ra_addr, rb_addr;
    logic        w_en;
    logic [9:0]  w_addr;
    logic [15:0] w_data;

    logic        busy, spi_we;
    logic [13:0] spi_addr;
    logic [63:0] spi_wdata;

    vecop dut(
        .clk(clk),
        .rst(rst),
        .instr(instr),
        .letter(letter),
        .pos(pos),
        .start(start),
        .done(done),
        .sp_rdata(sp_rdata),
        .ra_data(ra_data),
        .rb_data(rb_data),
        .sp_re(sp_re),
        .sp_addr(sp_addr),
        .ra_addr(ra_addr),
        .rb_addr(rb_addr),
        .w_en(w_en),
        .w_addr(w_addr),
        .w_data(w_data)
    );

    vreg_file vregs(
        .clk(clk),
        .rst(rst),
        .ra_addr(ra_addr),
        .rb_addr(rb_addr),
        .w_en(w_en),
        .w_addr(w_addr),
        .w_data(w_data),
        .ra_data(ra_data),
        .rb_data(rb_data)
    );

    spram_mem spm_dut(
        .clk(clk),
        .rst(rst),
        .busy(busy),
        .core_re(sp_re),
        .core_we(1'b0),
        .core_addr(sp_addr),
        .core_wdata(64'h0),
        .core_bytemask(8'h00),
        .spi_re(1'b0),
        .spi_we(spi_we),
        .spi_addr(spi_addr),
        .spi_wdata(spi_wdata),
        .rdata(sp_rdata)
    );

    initial clk = 1'b0;
    always #10.417 clk = ~clk;

    logic [63:0] spm [0:16383];
    logic [15:0] exp_vr [0:1023];
    int          n_err  = 0;
    int          n_runs = 0;
    int          n_done = 0;
    int          n_wr   = 0;
    bit          active = 0;

    task automatic error(input string msg);
        n_err++;
        if (n_err <= 20) $display("ERROR at %0t: %s", $time, msg);
    endtask

    // Port checks and counters, sampled away from the clock edge
    always @(negedge clk)
        if (!rst) begin
            if (done)  n_done++;
            if (w_en)  n_wr++;
            if (!sp_re && sp_addr !== '0)
                error($sformatf("sp_addr %h without sp_re", sp_addr));
            if (!w_en && (w_addr !== '0 || w_data !== '0))
                error("w_addr or w_data nonzero without w_en");
            if (!active && (sp_re !== 1'b0 || w_en !== 1'b0 ||
                            ra_addr !== '0 || rb_addr !== '0 ||
                            done !== 1'b0))
                error("outputs not 0 between instructions");
        end

    // ---------------------------------------------------------------------
    // Reference model (spec section 3)
    // ---------------------------------------------------------------------

    function automatic logic [15:0] sat16(input longint x);
        if (x > 32767)  return 16'h7FFF;
        if (x < -32768) return 16'h8000;
        return 16'(x);
    endfunction

    function automatic longint s8(input logic [13:0] a, input int l);
        logic [63:0] w;
        w = spm[a];
        return longint'($signed(w[8 * l +: 8]));
    endfunction

    function automatic longint s16(input logic [15:0] x);
        return longint'($signed(x));
    endfunction

    function automatic longint rq(input longint acc, input int s);
        if (s == 0) return acc;
        return (acc + (longint'(1) << (s - 1))) >>> s;
    endfunction

    task automatic model(input instr_t ins, input int ltr, input int p);
        int          c, d, s;
        logic [15:0] cur [0:1023];
        c = 8 * (ins.cols_m1 + 1);
        d = 8 * ins.dst;
        s = 8 * ins.src;
        for (int a = 0; a < 1024; a++) cur[a] = vregs.mem[a];
        for (int a = 0; a < 1024; a++) exp_vr[a] = cur[a];
        for (int i = 0; i < c; i++)
            case (ins.op)
                OP_EMBED:
                    exp_vr[d + i] = sat16(
                        (s8(14'(ins.base + 8 * ltr + i / 8), i % 8) +
                         s8(14'(ins.base + 256 + 8 * p + i / 8), i % 8))
                        * (longint'(1) << ins.shift));
                OP_VADD:
                    exp_vr[d + i] = sat16(s16(cur[d + i]) + s16(cur[s + i]));
                OP_VMUL:
                    exp_vr[d + i] = sat16(rq(s16(cur[d + i]) *
                                             s16(cur[s + i]), ins.shift));
                OP_VRELU:
                    exp_vr[d + i] = cur[s + i][15] ? 16'h0 : cur[s + i];
                default: ;
            endcase
    endtask

    // ---------------------------------------------------------------------
    // Running one instruction
    // ---------------------------------------------------------------------

    function automatic logic [15:0] rand16();
        case ($urandom_range(7))
            0:       return 16'h8000;
            1:       return 16'h7FFF;
            2:       return 16'h0000;
            3:       return 16'($signed(16'($urandom_range(255))) - 128);
            default: return 16'($urandom);
        endcase
    endfunction

    task automatic scramble_vr();
        for (int a = 0; a < 1024; a++) vregs.mem[a] = rand16();
    endtask

    task automatic run(input logic [3:0] op, input logic [6:0] src,
                       input logic [6:0] dst, input logic [13:0] base,
                       input logic [4:0] cm1, input logic [3:0] shift,
                       input int ltr, input int p);
        instr_t ins;
        int     cyc, c;
        logic   mine;
        ins         = {$urandom, $urandom};   // unused fields random
        ins[47:44]  = op;
        ins.src     = src;
        ins.dst     = dst;
        ins.base    = base;
        ins.cols_m1 = cm1;
        ins.shift   = shift;
        mine = (op == OP_EMBED || op == OP_VADD || op == OP_VMUL ||
                op == OP_VRELU);
        c    = mine ? 8 * (cm1 + 1) : 0;

        @(negedge clk);
        model(ins, ltr, p);
        instr  = ins;
        letter = 5'(ltr);
        pos    = 4'(p);
        n_done = 0;
        n_wr   = 0;
        active = 1;
        start  = 1'b1;
        @(negedge clk);
        start  = 1'b0;
        cyc    = 1;
        if (mine) begin
            while (n_done == 0 && cyc < 30000) begin
                @(negedge clk);
                cyc++;
            end
            if (n_done == 0) error($sformatf("op %0d: no done", op));
        end
        active = 0;
        repeat (40) @(negedge clk);   // no late writes or done pulses
        n_runs++;

        if (n_done != (mine ? 1 : 0))
            error($sformatf("op %0d: %0d done pulses", op, n_done));
        if (n_wr != c)
            error($sformatf("op %0d: %0d writes, expected %0d", op, n_wr,
                            c));
        for (int a = 0; a < 1024; a++)
            if (vregs.mem[a] !== exp_vr[a])
                error($sformatf("op %0d C=%0d sh=%0d: vr[%0d]=%h exp %h",
                                op, c, shift, a, vregs.mem[a], exp_vr[a]));
        if (n_runs <= 8 && mine)
            $display("op %0d, C = %0d: done after %0d cycles", op, c, cyc);
    endtask

    // Random operand placement within the program guarantees
    task automatic run_random();
        logic [3:0] op;
        int         c, d, s;
        logic [4:0] cm1;
        case ($urandom_range(3))
            0: op = OP_EMBED;
            1: op = OP_VADD;
            2: op = OP_VMUL;
            default: op = OP_VRELU;
        endcase
        cm1 = (op == OP_VMUL) ? $urandom_range(7) : $urandom_range(31);
        c   = 8 * (cm1 + 1);
        d   = $urandom_range(128 - c / 8);
        s   = $urandom_range(128 - c / 8);
        if (op == OP_VADD || op == OP_VMUL) begin
            // Different banks of 256 words, so C at most 256 and both
            // regions inside their own bank
            d = 32 * $urandom_range(3) + $urandom_range(32 - c / 8);
            s = 32 * (((d / 32) + $urandom_range(1, 3)) % 4)
                + $urandom_range(32 - c / 8);
        end else if (op == OP_VRELU && $urandom_range(1)) begin
            s = d;
        end else if (op == OP_VRELU) begin
            while (!(8 * d >= 8 * s + c || 8 * s >= 8 * d + c))
                s = $urandom_range(128 - c / 8);
        end
        if ($urandom_range(3) == 0) scramble_vr();
        run(op, 7'(s), 7'(d), 14'($urandom), cm1, 4'($urandom),
            $urandom_range(26), $urandom_range(15));
    endtask

    // ---------------------------------------------------------------------
    // Test sequence
    // ---------------------------------------------------------------------

    logic [7:0] b;

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

        // SPRAM over the SPI port, bytes biased to -128 and 127
        for (int a = 0; a < 16384; a++) begin
            for (int l = 0; l < 8; l++) begin
                case ($urandom_range(7))
                    0:       b = 8'h80;
                    1:       b = 8'h7F;
                    default: b = 8'($urandom);
                endcase
                spm[a][8 * l +: 8] = b;
            end
            spi_we    = 1'b1;
            spi_addr  = a;
            spi_wdata = spm[a];
            @(negedge clk);
        end
        spi_we = 1'b0;
        busy   = 1'b1;
        scramble_vr();
        @(negedge clk);

        // Program shapes (model/assembler.py)
        run(OP_EMBED, 7'd0, VR_X, A_TOK, 5'd7, 4'd6, 3, 0);
        run(OP_EMBED, 7'd0, VR_X, A_TOK, 5'd7, 4'd6, BOS, 15);
        run(OP_VADD, VR_T, VR_X, 14'h0, 5'd7, 4'd0, 0, 0);
        run(OP_VRELU, VR_H, VR_H, 14'h0, 5'd31, 4'd0, 0, 0);
        run(OP_VMUL, VR_V, VR_X, 14'h0, 5'd7, 4'd7, 0, 0);

        // EMBED: every letter, position and shift
        for (int l = 0; l <= 26; l++)
            run(OP_EMBED, 7'd0, VR_X, A_TOK, 5'd7, 4'($urandom), l,
                $urandom_range(15));
        for (int p = 0; p < 16; p++)
            run(OP_EMBED, 7'd0, VR_XN, A_TOK, 5'd7, 4'(p),
                $urandom_range(26), p);
        // Base near the top of SPRAM: addresses wrap
        run(OP_EMBED, 7'd0, VR_Q, 14'h3F80, 5'd7, 4'd15, 26, 15);

        // VMUL extremes: -32768 x -32768 = 2^30, and rounding at -0.5
        for (int i = 0; i < 64; i++) begin
            vregs.mem[i]       = (i < 32) ? 16'h8000 : 16'hFFFF;
            vregs.mem[256 + i] = (i < 32) ? 16'h8000 : 16'h0001;
        end
        run(OP_VMUL, 7'd32, 7'd0, 14'h0, 5'd7, 4'd0, 0, 0);
        for (int i = 0; i < 64; i++) begin
            vregs.mem[i]       = (i < 32) ? 16'h8000 : 16'hFFFF;
            vregs.mem[256 + i] = (i < 32) ? 16'h8000 : 16'h0001;
        end
        run(OP_VMUL, 7'd32, 7'd0, 14'h0, 5'd7, 4'd1, 0, 0);
        run(OP_VMUL, 7'd32, 7'd0, 14'h0, 5'd7, 4'd15, 0, 0);

        // Other opcodes must be ignored
        for (int op = 0; op < 16; op++)
            if (op != OP_EMBED && op != OP_VADD && op != OP_VMUL &&
                op != OP_VRELU)
                run(op[3:0], 7'($urandom), 7'($urandom), 14'($urandom),
                    5'($urandom), 4'($urandom), 0, 0);

        // Random instructions
        repeat (150) run_random();

        $display("vecop: %0d instructions, %0d errors", n_runs, n_err);
        if (n_err == 0) $display("TEST PASSED");
        else            $display("TEST FAILED");
        $finish;
    end

endmodule
