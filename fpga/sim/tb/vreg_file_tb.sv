`timescale 1ns/1ps

////////////////////////////////////////////////////////////////////////////////
// vreg_file_tb
//   Checks vreg_file against a behavioral model: INIT_FILE contents
//   (bringup_vreg.mem, run vvp from fpga/mem), 1-cycle read latency on both
//   ports, random writes with simultaneous reads of any two addresses
//   (same address, same 256-word range, idle address 0), and that a write
//   is visible on both ports
////////////////////////////////////////////////////////////////////////////////

module vreg_file_tb();
    logic        clk;
    logic        rst;
    logic [9:0]  ra_addr;
    logic [9:0]  rb_addr;
    logic        w_en;
    logic [9:0]  w_addr;
    logic [15:0] w_data;
    logic [15:0] ra_data;
    logic [15:0] rb_data;
    logic [15:0] model [0:1023];
    int          errors;

    vreg_file #(.INIT_FILE("bringup_vreg.mem")) dut(
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

    initial begin
        clk = 1'b0;
        forever #10 clk = ~clk;
    end

    // Applies one cycle of reads (and an optional write to another
    // address), then checks both ports against the model
    task automatic check_cycle(input logic [9:0] a, input logic [9:0] b,
                               input logic we, input logic [9:0] wa,
                               input logic [15:0] wd);
        logic [15:0] exp_a, exp_b;
        exp_a = model[a];
        exp_b = model[b];
        ra_addr = a;
        rb_addr = b;
        w_en = we;
        w_addr = wa;
        w_data = wd;
        @(negedge clk);
        if (we) model[wa] = wd;
        w_en = 1'b0;
        assert (ra_data === exp_a && rb_data === exp_b) else begin
            errors++;
            $error("read %0d, %0d: expected %h %h, got %h %h", a, b, exp_a,
                   exp_b, ra_data, rb_data);
        end
    endtask

    task automatic check_init;
        for (int i = 0; i < 1024; i++) begin
            check_cycle(i, 1023 - i, 1'b0, 10'd0, 16'd0);
        end
    endtask

    task automatic check_random(input int n);
        logic [9:0] a, b, wa;
        for (int i = 0; i < n; i++) begin
            a = $urandom;
            case ($urandom_range(3))
                0: b = a;
                1: b = {a[9:8], 8'($urandom)};
                2: b = 10'd0;
                default: b = $urandom;
            endcase
            do wa = $urandom; while (wa == a || wa == b);
            check_cycle(a, b, $urandom_range(1), wa, 16'($urandom));
        end
    endtask

    task automatic check_write_both;
        for (int i = 0; i < 64; i++) begin
            logic [9:0] wa;
            wa = $urandom;
            check_cycle(10'd0, 10'd0, 1'b1, (wa == 10'd0) ? 10'd1 : wa,
                        16'($urandom));
            wa = (wa == 10'd0) ? 10'd1 : wa;
            check_cycle(wa, wa, 1'b0, 10'd0, 16'd0);
        end
    endtask

    initial begin
        errors = 0;
        rst = 1'b0;
        ra_addr = 10'd0;
        rb_addr = 10'd0;
        w_en = 1'b0;
        w_addr = 10'd0;
        w_data = 16'd0;
        $readmemh("bringup_vreg.mem", model);
        @(negedge clk);

        // Verify the INIT_FILE contents on both ports
        check_init();

        // Verify random writes and reads of any two addresses
        check_random(20000);

        // Verify a write is visible on both ports
        check_write_both();

        if (errors == 0) $display("PASSED");
        else             $display("FAILED: %0d errors", errors);
        $stop();
    end

endmodule
