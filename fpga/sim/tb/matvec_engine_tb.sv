`timescale 1ns/1ps

////////////////////////////////////////////////////////////////////////////////
// matvec_engine_tb
//   Testbench for matvec_engine
////////////////////////////////////////////////////////////////////////////////

// Self-checking. Compile with gpt_pkg.sv, sim/models/SP256K.sv,
// sim/models/pmi_dsp.sv, spram_mem.sv, mac_lane.sv and requant.sv.
//
// The real spram_mem (with the SP256K model) is filled with random words
// over its SPI port. The vector-register file and score buffer are
// behavioral models here (1-cycle read latency, as spec section 5). For
// each MATVEC the testbench randomizes all 1,024 vector registers and the
// 32 scores, computes the expected result from spec section 3 (exact
// integer arithmetic and rq() from section 2), runs the instruction with
// the sequencer handshake, then compares every vector register and every
// score, so a wrong value, a wrong address or a stray write all fail.
//
// Also checked:
//   - done pulses exactly once per MATVEC, and the number of writes is R;
//   - cycles from start to done <= (R/8) x C + 25;
//   - OR-bus: every shared output is 0 whenever it is not in use, and all
//     of them stay 0 outside a MATVEC;
//   - other opcodes are ignored (no done, no writes);
//   - lane 0 borrow: random l0_* traffic while idle, l0_acc checked every
//     cycle against a model with the documented 3-cycle latency.
//
// Instructions: every MATVEC shape in the program (Wq, Wk with SAT8, W1,
// W2, attention scores and weighted values, output layer with ALT), the
// smallest (8 x 8) and largest (256 x 256) shapes, an SPRAM address that
// wraps past 0x3FFF, then random shapes, shifts and flags.
//
// Prints "TEST PASSED" or "TEST FAILED" on the last line.

module matvec_engine_tb();

    import gpt_pkg::*;

    logic        clk = 1'b0;
    logic        rst;
    instr_t      instr;
    logic [4:0]  letter;
    logic [3:0]  pos;
    logic        start;
    logic        done;
    logic [63:0] sp_rdata;
    logic [15:0] ra_data;
    logic        l0_req;
    logic [15:0] l0_a;
    logic [15:0] l0_b;
    logic        l0_clr;
    logic        l0_en;
    logic        sp_re;
    logic [13:0] sp_addr;
    logic [9:0]  ra_addr;
    logic        w_en;
    logic [9:0]  w_addr;
    logic [15:0] w_data;
    logic        sb_we;
    logic [4:0]  sb_waddr;
    logic [15:0] sb_wdata;
    logic [31:0] l0_acc;

    logic        busy;
    logic        spi_we;
    logic [13:0] spi_addr;
    logic [63:0] spi_wdata;

    matvec_engine dut(.*);

    spram_mem spram(
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

    always #10 clk = ~clk;

    // Behavioral vector registers and score buffer
    logic [15:0] vr [1024];
    logic [15:0] sb [32];

    always @(posedge clk) begin
        ra_data <= vr[ra_addr];
        if (w_en)  vr[w_addr]   <= w_data;
        if (sb_we) sb[sb_waddr] <= sb_wdata;
    end

    // Shadow copies and expected results
    logic [63:0] spm    [16384];
    logic [15:0] exp_vr [1024];
    logic [15:0] exp_sb [32];

    int n_err   = 0;
    int n_runs  = 0;
    int n_w     = 0;
    int n_sb    = 0;
    int n_done  = 0;
    logic running = 1'b0;

    task automatic error(input string msg);
        n_err++;
        if (n_err <= 30) $display("ERROR t=%0t: %s", $time, msg);
    endtask

    // Monitors: OR-bus and stray done (state is unknown until reset)
    always @(posedge clk) if (!rst) begin
        if (!sp_re && (sp_addr !== '0 || ra_addr !== '0))
            error("sp_addr/ra_addr not 0 while sp_re = 0");
        if (!w_en && (w_addr !== '0 || w_data !== '0))
            error("w_addr/w_data not 0 while w_en = 0");
        if (!sb_we && (sb_waddr !== '0 || sb_wdata !== '0))
            error("sb_waddr/sb_wdata not 0 while sb_we = 0");
        if (!running && (sp_re !== 1'b0 || w_en !== 1'b0 ||
                         sb_we !== 1'b0))
            error("shared-port activity outside a MATVEC");
        if (!running && done !== 1'b0)
            error("done outside a MATVEC");
        if (w_en === 1'b1)  n_w++;
        if (sb_we === 1'b1) n_sb++;
        if (done === 1'b1)  n_done++;
    end

    // Reference arithmetic
    function automatic int s16(input logic [15:0] v);
        return int'($signed(v));
    endfunction

    function automatic int s8w(input logic [13:0] a, input int l);
        logic [63:0] w;
        w = spm[a];
        return int'($signed(w[8*l +: 8]));
    endfunction

    function automatic logic [15:0] ref_rq(input int a,
                                           input logic [3:0] s,
                                           input logic s8);
        longint t, lo, hi;
        if (s == 4'd0) t = a;
        else           t = (longint'(a) + (64'sd1 <<< (s - 1))) >>> s;
        lo = s8 ? -128 : -32768;
        hi = s8 ?  127 :  32767;
        if (t < lo) t = lo;
        if (t > hi) t = hi;
        return t[15:0];
    endfunction

    // Runs one MATVEC and checks it
    task automatic run_mv(input logic [6:0]  src,
                          input logic [6:0]  dst,
                          input logic [13:0] base,
                          input logic [4:0]  rm1,
                          input logic [4:0]  cm1,
                          input logic [3:0]  sh,
                          input logic        s8,
                          input logic        alt);
        int R, C, acc, cyc;
        logic [15:0] y;
        logic [13:0] a;
        R = 8 * (rm1 + 1);
        C = 8 * (cm1 + 1);

        @(negedge clk);
        for (int i = 0; i < 1024; i++) begin
            vr[i]     = $urandom;
            exp_vr[i] = vr[i];
        end
        for (int i = 0; i < 32; i++) begin
            sb[i]     = $urandom;
            exp_sb[i] = sb[i];
        end

        for (int g = 0; g < R / 8; g++)
            for (int l = 0; l < 8; l++) begin
                acc = 0;
                for (int c = 0; c < C; c++) begin
                    a   = base + 14'(g * C + c);
                    acc = acc + s16(vr[(8 * src + c) % 1024]) * s8w(a, l);
                end
                y = ref_rq(acc, sh, s8);
                if (alt) exp_sb[(8 * g + l) % 32] = y;
                else     exp_vr[(8 * dst + 8 * g + l) % 1024] = y;
            end

        n_w    = 0;
        n_sb   = 0;
        n_done = 0;
        instr.op      = OP_MATVEC;
        instr.src     = src;
        instr.dst     = dst;
        instr.base    = base;
        instr.rows_m1 = rm1;
        instr.cols_m1 = cm1;
        instr.shift   = sh;
        instr.flags   = {alt, s8};
        start   = 1'b1;
        running = 1'b1;
        @(negedge clk);
        start = 1'b0;

        cyc = 1;
        while (done !== 1'b1 && cyc < (R / 8) * C + 200) begin
            @(negedge clk);
            cyc++;
        end
        if (done !== 1'b1)
            error($sformatf("MATVEC R=%0d C=%0d timed out", R, C));
        if (cyc > (R / 8) * C + 25)
            error($sformatf("MATVEC R=%0d C=%0d took %0d cycles",
                            R, C, cyc));
        @(negedge clk);
        running = 1'b0;
        repeat (5) @(negedge clk);

        if (n_done != 1)
            error($sformatf("done pulsed %0d times", n_done));
        if (alt ? (n_sb != R || n_w != 0) : (n_w != R || n_sb != 0))
            error($sformatf("R=%0d ALT=%0b: %0d vr writes, %0d sb writes",
                            R, alt, n_w, n_sb));
        for (int i = 0; i < 1024; i++)
            if (vr[i] !== exp_vr[i])
                error($sformatf("R=%0d C=%0d vr[%0d]=%0d exp %0d",
                                R, C, i, s16(vr[i]), s16(exp_vr[i])));
        for (int i = 0; i < 32; i++)
            if (sb[i] !== exp_sb[i])
                error($sformatf("R=%0d C=%0d score[%0d]=%0d exp %0d",
                                R, C, i, s16(sb[i]), s16(exp_sb[i])));
        n_runs++;
    endtask

    // Random MATVEC with non-overlapping src and dst regions
    task automatic run_random();
        logic [4:0] rm1, cm1;
        logic [6:0] src, dst;
        int R, C;
        rm1 = $urandom_range(31);
        cm1 = $urandom_range(31);
        R   = 8 * (rm1 + 1);
        C   = 8 * (cm1 + 1);
        do begin
            src = $urandom_range(128 - C / 8);
            dst = $urandom_range(128 - R / 8);
        end while (!(8 * dst >= 8 * src + C || 8 * src >= 8 * dst + R));
        run_mv(src, dst, $urandom, rm1, cm1, $urandom, $urandom,
               $urandom_range(3) == 0);
    endtask

    // Other opcodes must be ignored
    task automatic run_other(input op_t op);
        @(negedge clk);
        for (int i = 0; i < 1024; i++) exp_vr[i] = vr[i];
        n_done = 0;
        instr    = {$urandom, $urandom};
        instr.op = op;
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;
        repeat (40) @(negedge clk);
        if (n_done != 0) error($sformatf("done for opcode %0d", op));
        for (int i = 0; i < 1024; i++)
            if (vr[i] !== exp_vr[i])
                error($sformatf("opcode %0d changed vr[%0d]", op, i));
    endtask

    // Lane 0 borrow: l0_acc follows the inputs by 3 cycles
    task automatic run_borrow(input int ncyc);
        logic        h_en [4];
        logic        h_clr [4];
        int          h_p [4];
        int          exp_acc;
        logic        known;
        known = 1'b0;
        for (int i = 0; i < 4; i++) h_en[i] = 1'b0;
        for (int t = 0; t < ncyc; t++) begin
            @(negedge clk);
            // Apply the inputs that reached the accumulator this edge
            if (h_en[2]) begin
                if (h_clr[2]) known = 1'b1;
                exp_acc = (h_clr[2] ? 0 : exp_acc) + h_p[2];
            end
            if (known && $signed(l0_acc) !== exp_acc)
                error($sformatf("l0_acc=%0d exp %0d", $signed(l0_acc),
                                exp_acc));
            for (int i = 3; i > 0; i--) begin
                h_en[i]  = h_en[i - 1];
                h_clr[i] = h_clr[i - 1];
                h_p[i]   = h_p[i - 1];
            end
            l0_req = ($urandom_range(9) != 0);
            l0_en  = ($urandom_range(7) != 0);
            l0_clr = ($urandom_range(7) == 0);
            l0_a   = $urandom;
            l0_b   = $urandom;
            h_en[0]  = l0_req & l0_en;
            h_clr[0] = l0_clr;
            h_p[0]   = s16(l0_a) * s16(l0_b);
        end
        @(negedge clk);
        l0_req = 1'b0;
        l0_en  = 1'b0;
        l0_clr = 1'b0;
        repeat (4) @(negedge clk);
    endtask

    // Test sequence
    initial begin
        rst      = 1'b1;
        start    = 1'b0;
        busy     = 1'b0;
        spi_we   = 1'b0;
        letter   = '0;
        pos      = '0;
        l0_req   = 1'b0;
        l0_a     = '0;
        l0_b     = '0;
        l0_clr   = 1'b0;
        l0_en    = 1'b0;
        instr    = '0;
        repeat (3) @(negedge clk);
        rst = 1'b0;

        // Fill the SPRAM over the SPI port
        for (int a = 0; a < 16384; a++) begin
            spm[a]    = {$urandom, $urandom};
            spi_we    = 1'b1;
            spi_addr  = a;
            spi_wdata = spm[a];
            @(negedge clk);
        end
        spi_we = 1'b0;
        busy   = 1'b1;
        @(negedge clk);

        // Program shapes (layer 0 / head h as in spec section 3)
        run_mv(VR_XN, VR_Q, A_L0 + O_WQ, 5'd7, 5'd7, 4'd7, 1'b0, 1'b0);
        run_mv(VR_XN, VR_K, A_L0 + O_WK, 5'd7, 5'd7, 4'd9, 1'b1, 1'b0);
        run_mv(VR_XN, VR_H, A_L1 + O_W1, 5'd31, 5'd7, 4'd8, 1'b0, 1'b0);
        run_mv(VR_H, VR_T, A_L1 + O_W2, 5'd7, 5'd31, 4'd10, 1'b0, 1'b0);
        run_mv(VR_Q + 7'd4, VR_S + 7'd4, A_K0 + 14'd64, 5'd1, 5'd1,
               4'd6, 1'b0, 1'b0);
        run_mv(VR_S + 7'd6, VR_A + 7'd6, A_V1 + 14'd96, 5'd1, 5'd1,
               4'd12, 1'b0, 1'b0);
        run_mv(VR_X, VR_X, A_OUT, 5'd3, 5'd7, 4'd5, 1'b0, 1'b1);
        // Extremes: smallest, largest, SPRAM address wrap, shift 0
        run_mv(7'd0, 7'd1, 14'h1234, 5'd0, 5'd0, 4'd3, 1'b0, 1'b0);
        run_mv(VR_H, VR_X, 14'h0000, 5'd31, 5'd31, 4'd15, 1'b0, 1'b0);
        run_mv(VR_XN, VR_Q, 14'h3FF0, 5'd3, 5'd7, 4'd8, 1'b1, 1'b0);
        run_mv(VR_XN, VR_Q, A_L0, 5'd7, 5'd7, 4'd0, 1'b0, 1'b0);

        // Other opcodes, then lane 0 borrow, then random MATVECs
        for (int op = 0; op < 9; op++)
            if (op != OP_MATVEC) run_other(op_t'(op));
        run_borrow(3000);
        repeat (40) run_random();
        run_borrow(500);

        $display("matvec_engine: %0d MATVECs, %0d errors", n_runs, n_err);
        if (n_err == 0) $display("TEST PASSED");
        else            $display("TEST FAILED");
        $finish;
    end

endmodule
