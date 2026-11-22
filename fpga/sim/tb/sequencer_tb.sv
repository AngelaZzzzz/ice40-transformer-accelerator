`timescale 1ns/1ps

////////////////////////////////////////////////////////////////////////////////
// sequencer_tb
//   Runs programs through prog_mem and sequencer against a fake execution
//   unit that answers each start with unit_done after a per-opcode delay.
//   Checks instruction order, a one-cycle start with stable fields until
//   unit_done, busy and done_flag timing, run ignored while busy, an
//   immediate HALT, the 54-instruction program from prog.mem (run vvp from
//   fpga/mem) and the end of a run after the instruction at pc = 255
////////////////////////////////////////////////////////////////////////////////

module sequencer_tb();
    import gpt_pkg::*;

    logic        clk;
    logic        rst;
    logic        we;
    logic [7:0]  waddr;
    logic [47:0] wdata;
    logic [7:0]  pm_raddr;
    logic [47:0] pm_rdata;
    logic        run;
    logic [4:0]  run_letter;
    logic [3:0]  run_pos;
    logic        unit_done;
    instr_t      instr;
    logic [4:0]  letter;
    logic [3:0]  pos;
    logic        start;
    logic        busy;
    logic        done_flag;

    logic [47:0] prog [0:255];
    logic [47:0] file_prog [0:255];
    instr_t      log_instr [0:511];
    logic [4:0]  log_letter [0:511];
    logic [3:0]  log_pos [0:511];
    int          n_log;
    instr_t      held_instr;
    logic [4:0]  held_letter;
    logic [3:0]  held_pos;
    int          remaining;
    logic        active;
    logic        start_prev;
    logic        started;
    int          errors;

    prog_mem pmem(
        .clk(clk),
        .rst(rst),
        .we(we),
        .waddr(waddr),
        .wdata(wdata),
        .raddr(pm_raddr),
        .rdata(pm_rdata)
    );

    sequencer dut(
        .clk(clk),
        .rst(rst),
        .run(run),
        .run_letter(run_letter),
        .run_pos(run_pos),
        .pm_rdata(pm_rdata),
        .unit_done(unit_done),
        .pm_raddr(pm_raddr),
        .instr(instr),
        .letter(letter),
        .pos(pos),
        .start(start),
        .busy(busy),
        .done_flag(done_flag)
    );

    initial begin
        clk = 1'b0;
        forever #10 clk = ~clk;
    end

    // Fake execution unit: unit_done 1 + 2 x op cycles after start
    always @(posedge clk) begin
        unit_done <= 1'b0;
        if (start) begin
            log_instr[n_log] = instr;
            log_letter[n_log] = letter;
            log_pos[n_log] = pos;
            n_log++;
            held_instr = instr;
            held_letter = letter;
            held_pos = pos;
            remaining = 1 + 2 * int'(instr.op);
            active = 1'b1;
        end else if (active) begin
            remaining--;
            if (remaining == 0) begin
                unit_done <= 1'b1;
                active = 1'b0;
            end
        end
    end

    // Monitors: one-cycle start, stable fields, done_flag = ~busy after
    // the first run
    always @(negedge clk) begin
        if (!rst) begin
            assert (!(start && start_prev)) else begin
                errors++;
                $error("expected a one-cycle start, got start high twice");
            end
            assert (!start || busy) else begin
                errors++;
                $error("expected busy=1 with start, got busy=0");
            end
            if (active || unit_done) begin
                assert (instr === held_instr && letter === held_letter &&
                        pos === held_pos) else begin
                    errors++;
                    $error("expected fields %h %0d %0d stable, got %h %0d %0d",
                           held_instr, held_letter, held_pos, instr, letter,
                           pos);
                end
            end
            if (started) begin
                assert (done_flag === ~busy) else begin
                    errors++;
                    $error("expected done_flag=~busy, got busy=%b done=%b",
                           busy, done_flag);
                end
            end
            start_prev = start;
        end
    end

    task automatic load_prog(input int n);
        for (int i = 0; i < n; i++) begin
            we = 1'b1;
            waddr = i;
            wdata = prog[i];
            @(negedge clk);
        end
        we = 1'b0;
    endtask

    task automatic pulse_run(input logic [4:0] l, input logic [3:0] p);
        run = 1'b1;
        run_letter = l;
        run_pos = p;
        @(negedge clk);
        run = 1'b0;
        run_letter = 5'd0;
        run_pos = 4'd0;
    endtask

    // Runs the loaded program and compares the issued instructions with
    // prog[0 .. n_expected - 1]
    task automatic check_run(input logic [4:0] l, input logic [3:0] p,
                             input int n_expected, input string name);
        int cycles;
        n_log = 0;
        pulse_run(l, p);
        started = 1'b1;
        assert (busy === 1'b1 && done_flag === 1'b0) else begin
            errors++;
            $error("%s: expected busy=1 done=0 after run, got %b %b", name,
                   busy, done_flag);
        end
        cycles = 0;
        while (done_flag !== 1'b1 && cycles < 20000) begin
            @(negedge clk);
            cycles++;
        end
        assert (done_flag === 1'b1 && busy === 1'b0) else begin
            errors++;
            $error("%s: expected done=1 busy=0, got %b %b", name, done_flag,
                   busy);
        end
        assert (n_log == n_expected) else begin
            errors++;
            $error("%s: expected %0d starts, got %0d", name, n_expected,
                   n_log);
        end
        for (int i = 0; i < n_log && i < n_expected; i++) begin
            assert (log_instr[i] === prog[i] && log_letter[i] === l &&
                    log_pos[i] === p) else begin
                errors++;
                $error("%s: instr %0d expected %h %0d %0d, got %h %0d %0d",
                       name, i, prog[i], l, p, log_instr[i], log_letter[i],
                       log_pos[i]);
            end
        end
    endtask

    // Random non-HALT instruction
    function automatic logic [47:0] random_instr();
        logic [47:0] word;
        word = {$urandom, $urandom};
        word[47:44] = 4'($urandom_range(8, 1));
        return word;
    endfunction

    initial begin
        errors = 0;
        n_log = 0;
        active = 1'b0;
        start_prev = 1'b0;
        started = 1'b0;
        rst = 1'b1;
        we = 1'b0;
        waddr = 8'd0;
        wdata = 48'd0;
        run = 1'b0;
        run_letter = 5'd0;
        run_pos = 4'd0;
        unit_done = 1'b0;
        repeat (3) @(negedge clk);
        rst = 1'b0;
        @(negedge clk);

        // Verify idle after reset
        assert (busy === 1'b0 && done_flag === 1'b0 && start === 1'b0)
        else begin
            errors++;
            $error("expected idle after reset, got busy=%b done=%b start=%b",
                   busy, done_flag, start);
        end

        // Verify order, fields and timing on every opcode, then HALT
        for (int i = 0; i < 8; i++) prog[i] = random_instr();
        for (int i = 0; i < 8; i++) prog[i][47:44] = 4'(i + 1);
        prog[8] = 48'h0;
        load_prog(9);
        check_run(5'd7, 4'd3, 8, "opcodes");

        // Verify run while busy is ignored
        n_log = 0;
        pulse_run(5'd2, 4'd9);
        started = 1'b1;
        for (int i = 0; i < 20000 && busy === 1'b1; i++) begin
            run = 1'b1;
            run_letter = 5'($urandom);
            run_pos = 4'($urandom);
            @(negedge clk);
        end
        run = 1'b0;
        run_letter = 5'd0;
        run_pos = 4'd0;
        @(negedge clk);
        assert (n_log == 8) else begin
            errors++;
            $error("run while busy: expected 8 starts, got %0d", n_log);
        end
        for (int i = 0; i < n_log; i++) begin
            assert (log_letter[i] === 5'd2 && log_pos[i] === 4'd9) else begin
                errors++;
                $error("run while busy: instr %0d expected 2 9, got %0d %0d",
                       i, log_letter[i], log_pos[i]);
            end
        end
        repeat (5) @(negedge clk);

        // Verify an immediate HALT
        prog[0] = 48'h0;
        load_prog(1);
        check_run(5'd26, 4'd0, 0, "immediate HALT");

        // Verify the model program
        $readmemh("prog.mem", file_prog, 0, 53);
        for (int i = 0; i < 54; i++) prog[i] = file_prog[i];
        load_prog(54);
        check_run(5'd26, 4'd0, 53, "prog.mem");

        // Verify the run ends after the instruction at pc = 255
        for (int i = 0; i < 256; i++) prog[i] = random_instr();
        load_prog(256);
        check_run(5'd1, 4'd15, 256, "pc 255");

        if (errors == 0) $display("PASSED");
        else             $display("FAILED: %0d errors", errors);
        $stop();
    end

endmodule
