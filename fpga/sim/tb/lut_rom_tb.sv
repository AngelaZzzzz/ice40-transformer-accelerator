`timescale 1ns/1ps

////////////////////////////////////////////////////////////////////////////////
// lut_rom_tb
//   Self-checking testbench for lut_rom with exp_lut.mem: fixed values of
//   E[j] = round(32767 exp(-j / 16)), every address against the file, and
//   the 1-cycle read latency. Run vvp from fpga/mem so exp_lut.mem is found.
////////////////////////////////////////////////////////////////////////////////

module lut_rom_tb();
    logic        clk;
    logic        rst;
    logic [7:0]  addr;
    logic [15:0] data;
    logic [15:0] expected;
    logic [15:0] table_vals [0:255];
    int          errors;

    lut_rom #(.INIT_FILE("exp_lut.mem")) dut(
        .clk(clk),
        .rst(rst),
        .addr(addr),
        .data(data)
    );

    initial begin
        clk = 0;
        forever begin
            #5 clk = ~clk;
        end
    end

    task automatic check(input logic [7:0]  addr_val,
                         input logic [15:0] expected_val);
        @(negedge clk);
        addr = addr_val;
        expected = expected_val;
        @(posedge clk);
        #1;
        assert (data === expected) else begin
            errors++;
            $error("addr=%0d: expected data=%h, got data=%h",
                   addr, expected, data);
        end
    endtask

    initial begin
        errors = 0;
        rst = 1'b0;
        $readmemh("exp_lut.mem", table_vals);

        // Verify values computed from the table definition
        check(8'd0, 16'h7FFF);
        check(8'd16, 16'h2F16);
        check(8'd255, 16'h0000);

        // Verify every address against exp_lut.mem
        for (int i = 0; i < 256; i++) begin
            check(8'(i), table_vals[i]);
        end

        // Verify data holds until the clock edge after an address change
        @(negedge clk);
        addr = 8'd0;
        #1;
        assert (data === table_vals[255]) else begin
            errors++;
            $error("expected data=%h before the clock edge, got data=%h",
                   table_vals[255], data);
        end

        if (errors == 0) $display("PASSED");
        else             $display("FAILED: %0d errors", errors);
        $stop();
    end

endmodule
