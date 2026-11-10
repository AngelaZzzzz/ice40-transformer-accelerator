// requant_tb.sv
// Angela Zheng, 2026-11-09
//
// Self-checking testbench for requant.sv. The reference model below
// computes rq(acc, s, sat8) from interface spec section 2 in 64-bit
// arithmetic, so it cannot overflow and shares no structure with the RTL.
//
// Stimulus, for every shift 0-15 with sat8 = 0 and 1:
//   - directed edge cases: 0, +/-1, int32 extremes, exact halves and
//     their neighbours, and values on both sides of each clamp limit;
// then random values over the full int32 range and over every magnitude.
// Random idle cycles are inserted so in_valid bubbles are also tested.
//
// Prints "TEST PASSED" or "TEST FAILED" on the last line.

`timescale 1ns/1ps

module requant_tb;

  logic               clk = 1'b0;
  logic               rst;
  logic               in_valid;
  logic signed [31:0] acc;
  logic        [3:0]  shift;
  logic               sat8;
  logic               out_valid;
  logic signed [15:0] y;

  requant dut (.*);

  always #10 clk = ~clk;

  // -------------------------------------------------------------------
  // Reference model.
  // -------------------------------------------------------------------
  function automatic logic signed [15:0] ref_rq(
    input logic signed [31:0] a,
    input logic        [3:0]  s,
    input logic               s8
  );
    longint t, lo, hi;
    if (s == 4'd0) t = a;
    else           t = (longint'(a) + (64'sd1 <<< (s - 1))) >>> s;
    lo = s8 ? -128 : -32768;
    hi = s8 ?  127 :  32767;
    if (t < lo) t = lo;
    if (t > hi) t = hi;
    return t[15:0];
  endfunction

  // -------------------------------------------------------------------
  // Scoreboard: inputs and expected outputs, in issue order.
  // -------------------------------------------------------------------
  localparam int MAXV = 1 << 16;

  logic signed [31:0] acc_q [MAXV];
  logic        [3:0]  sh_q  [MAXV];
  logic               s8_q  [MAXV];
  logic signed [15:0] exp_q [MAXV];
  int                 n_in  = 0;
  int                 n_out = 0;
  int                 n_err = 0;

  always @(posedge clk)
    if (!rst && out_valid === 1'b1) begin
      if (y !== exp_q[n_out]) begin
        n_err++;
        if (n_err <= 20)
          $display("MISMATCH #%0d: acc=%0d s=%0d sat8=%0b got=%0d exp=%0d",
                   n_out, acc_q[n_out], sh_q[n_out], s8_q[n_out],
                   y, exp_q[n_out]);
      end
      n_out++;
    end

  // -------------------------------------------------------------------
  // Drivers.
  // -------------------------------------------------------------------
  task automatic idle();
    in_valid <= 1'b0;
    @(posedge clk);
  endtask

  task automatic send(input logic signed [31:0] a,
                      input logic        [3:0]  s,
                      input logic               s8);
    acc_q[n_in] = a;
    sh_q[n_in]  = s;
    s8_q[n_in]  = s8;
    exp_q[n_in] = ref_rq(a, s, s8);
    n_in++;
    acc      <= a;
    shift    <= s;
    sat8     <= s8;
    in_valid <= 1'b1;
    @(posedge clk);
    if ($urandom_range(7) == 0) idle();
  endtask

  // Sends a 64-bit value truncated to int32, for directed cases whose
  // natural value may not fit.
  task automatic send64(input longint v,
                        input logic [3:0] s,
                        input logic       s8);
    send(v[31:0], s, s8);
  endtask

  // -------------------------------------------------------------------
  // Test sequence.
  // -------------------------------------------------------------------
  longint one, half;

  initial begin
    rst      = 1'b1;
    in_valid = 1'b0;
    acc      = '0;
    shift    = '0;
    sat8     = 1'b0;
    repeat (3) @(posedge clk);
    rst <= 1'b0;
    @(posedge clk);

    // Directed edge cases.
    for (int s = 0; s < 16; s++)
      for (int s8 = 0; s8 < 2; s8++) begin
        one  = 64'sd1 <<< s;
        half = (s == 0) ? 0 : (64'sd1 <<< (s - 1));
        send64(0,            s, s8);
        send64(1,            s, s8);
        send64(-1,           s, s8);
        send64(2147483647,   s, s8);
        send64(-2147483648,  s, s8);
        send64(half,         s, s8);
        send64(-half,        s, s8);
        send64(half - 1,     s, s8);
        send64(-half - 1,    s, s8);
        send64(half + 1,     s, s8);
        send64(-half + 1,    s, s8);
        send64(3 * half,     s, s8);
        send64(-3 * half,    s, s8);
        // 16-bit clamp limits.
        send64(32767 * one,             s, s8);
        send64(32767 * one + half - 1,  s, s8);
        send64(32767 * one + half,      s, s8);
        send64(-32768 * one,            s, s8);
        send64(-32768 * one - half,     s, s8);
        send64(-32768 * one - half - 1, s, s8);
        // 8-bit clamp limits.
        send64(127 * one,               s, s8);
        send64(127 * one + half - 1,    s, s8);
        send64(127 * one + half,        s, s8);
        send64(-128 * one,              s, s8);
        send64(-128 * one - half,       s, s8);
        send64(-128 * one - half - 1,   s, s8);
      end

    // Random values over the full int32 range.
    repeat (20000)
      send($urandom, $urandom_range(15), $urandom_range(1));

    // Random values over every magnitude, from tiny to near 2^31.
    repeat (20000)
      send($signed($urandom) >>> $urandom_range(31),
           $urandom_range(15), $urandom_range(1));

    // Drain the pipeline.
    repeat (6) idle();

    if (n_out != n_in) begin
      n_err++;
      $display("COUNT MISMATCH: sent %0d, received %0d", n_in, n_out);
    end

    $display("requant: %0d vectors, %0d errors", n_in, n_err);
    if (n_err == 0) $display("TEST PASSED");
    else            $display("TEST FAILED");
    $finish;
  end

  // Timeout guard.
  initial begin
    #50ms;
    $display("TIMEOUT");
    $display("TEST FAILED");
    $finish;
  end

endmodule
