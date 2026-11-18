`timescale 1ns/1ps

////////////////////////////////////////////////////////////////////////////////
// font_rom_tb
//   Testbench for font_rom
////////////////////////////////////////////////////////////////////////////////

// Self-checking with fpga/mem/font.mem; run vvp from fpga/mem so that the
// file is found. Checks:
//   1. fixed rows of known glyphs ('A', 'g', space and a control code);
//   2. every address against the file, in order and in random order;
//   3. the one-cycle read latency (data changes only after the edge that
//      samples a new address).
//
// Prints "TEST PASSED" or "TEST FAILED" on the last line.

module font_rom_tb();

    logic        pix_clk = 1'b0;
    logic [10:0] addr;
    logic [7:0]  data;
    logic [7:0]  ref_rom [0:2047];
    int          n_err   = 0;

    font_rom dut(.*);

    always #20 pix_clk = ~pix_clk;

    task automatic check(input logic [10:0] a, input logic [7:0] expected);
        logic [7:0] prev;
        @(negedge pix_clk);
        addr   = a;
        prev   = data;
        #1;
        if (data !== prev) begin
            n_err++;
            $display("addr %h: data changed before the clock edge", a);
        end
        @(posedge pix_clk);
        #1;
        if (data !== expected) begin
            n_err++;
            if (n_err <= 20)
                $display("addr %h: data %h, expected %h", a, data, expected);
        end
    endtask

    int a;

    initial begin
        $readmemh("font.mem", ref_rom);

        // 1. Known glyph rows
        check({7'h41, 4'd2}, 8'h18);    // 'A' top of the apex
        check({7'h41, 4'd7}, 8'h7e);    // 'A' crossbar
        check({7'h41, 4'd0}, 8'h00);
        check({7'h67, 4'd15}, 8'h7c);   // 'g' descender
        for (int r = 0; r < 16; r++) begin
            check({7'h20, 4'(r)}, 8'h00);   // space
            check({7'h00, 4'(r)}, 8'h00);   // control code
        end

        // 2. Every address, in order and at random
        for (int i = 0; i < 2048; i++) check(11'(i), ref_rom[i]);
        repeat (4096) begin
            a = $urandom_range(2047);
            check(11'(a), ref_rom[a]);
        end

        $display("font_rom: %0d errors", n_err);
        if (n_err == 0) $display("TEST PASSED");
        else            $display("TEST FAILED");
        $finish;
    end

endmodule
