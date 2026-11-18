`timescale 1ns/1ps

////////////////////////////////////////////////////////////////////////////////
// text_buffer_tb
//   Testbench for text_buffer
////////////////////////////////////////////////////////////////////////////////

// Self-checking. The write clock runs at 48 MHz and the read clock at
// 25 MHz, unrelated in phase, as in gpt_top. Checks:
//   1. every cell written and read back;
//   2. random writes in wclk while rclk reads random cells, compared with
//      a model of the buffer; reads of a cell written within a few cycles
//      are skipped, since the two clocks are unrelated;
//   3. the one-cycle read latency;
//   4. we = 0 leaves the buffer unchanged;
//   5. INIT_FILE: a second instance loaded from font.mem (its first
//      1,024 bytes) reads back that file. Run vvp from fpga/mem.
//
// Prints "TEST PASSED" or "TEST FAILED" on the last line.

module text_buffer_tb();

    logic       wclk = 1'b0;
    logic       rclk = 1'b0;
    logic       we   = 1'b0;
    logic [9:0] waddr, raddr;
    logic [7:0] wdata, rdata;

    always #10.4167 wclk = ~wclk;
    always #20.0    rclk = ~rclk;

    text_buffer dut(.*);

    // Instance with power-up contents
    logic [7:0] i_rdata;

    text_buffer #(.INIT_FILE("font.mem")) init_dut(
        .wclk(wclk),
        .we(1'b0),
        .waddr(10'd0),
        .wdata(8'd0),
        .rclk(rclk),
        .raddr(raddr),
        .rdata(i_rdata)
    );

    logic [7:0] model [0:1023];
    realtime    t_wr  [0:1023];   // time of the last write to each cell
    int         n_err = 0;
    int         n_chk = 0;
    logic [7:0] init_ref [0:1023];

    task automatic err(input string msg);
        n_err++;
        if (n_err <= 20) $display("ERROR at %0t: %s", $time, msg);
    endtask

    // One write in wclk
    task automatic write(input logic [9:0] a, input logic [7:0] d,
                         input logic e);
        @(negedge wclk);
        we    = e;
        waddr = a;
        wdata = d;
        @(posedge wclk);
        if (e) begin
            model[a] = d;
            t_wr[a]  = $realtime;
        end
        #1 we = 1'b0;
    endtask

    // One read in rclk, checked against the model
    task automatic read(input logic [9:0] a);
        logic [7:0] prev;
        realtime    t_s;
        @(negedge rclk);
        raddr  = a;
        prev   = rdata;
        #1;
        if (rdata !== prev) err("rdata changed before the clock edge");
        @(posedge rclk);
        t_s = $realtime;
        #1;
        // Skip a cell written within 50 ns of the read edge
        if (t_s - t_wr[a] > 50.0) begin
            n_chk++;
            if (rdata !== model[a])
                err($sformatf("cell %0d: read %h, expected %h", a, rdata,
                              model[a]));
        end
        // Power-up contents of the second instance
        if (i_rdata !== init_ref[a])
            err($sformatf("init cell %0d: read %h, expected %h", a,
                          i_rdata, init_ref[a]));
    endtask

    initial begin
        $readmemh("font.mem", init_ref, 0, 1023);
        for (int i = 0; i < 1024; i++) t_wr[i] = -1.0e9;

        // 1. Every cell
        for (int i = 0; i < 1024; i++) write(10'(i), 8'(i * 7 + 3), 1'b1);
        for (int i = 0; i < 1024; i++) read(10'(i));

        // 2, 4. Random traffic in both clocks
        fork
            begin
                repeat (20000)
                    write(10'($urandom), 8'($urandom),
                          $urandom_range(3) != 0);
            end
            begin
                repeat (10000) read(10'($urandom));
            end
        join

        // Final sweep
        #200;
        for (int i = 0; i < 1024; i++) read(10'(i));

        $display("text_buffer: %0d reads checked, %0d errors", n_chk, n_err);
        if (n_err == 0) $display("TEST PASSED");
        else            $display("TEST FAILED");
        $finish;
    end

endmodule
