// requant.sv
// Angela Zheng, 2026-11-09
//
// Requantizes a signed 32-bit accumulator to int16 (interface spec, sec. 2):
//   t = acc                       if s = 0
//   t = (acc + 2^(s-1)) >>> s     otherwise
//   y = clamp(t, -32768, 32767), or clamp(t, -128, 127) when sat8 = 1,
//   stored as int16 (sign-extended when sat8 = 1).
//
// Three pipeline stages, so latency is 3 cycles and throughput is one
// result per cycle:
//   1. add the rounding constant (33 bits, so the add cannot overflow)
//   2. arithmetic shift right by s
//   3. saturate to 16 or 8 bits
// Only the valid bits are reset; the data path needs no reset.

module requant (
  input  logic               clk,
  input  logic               rst,
  input  logic               in_valid,
  input  logic signed [31:0] acc,
  input  logic        [3:0]  shift,
  input  logic               sat8,
  output logic               out_valid,
  output logic signed [15:0] y
);

  // -------------------------------------------------------------------
  // Stage 1: round. rnd = 2^(s-1) when s > 0, else 0.
  // -------------------------------------------------------------------
  logic        [32:0] rnd;
  logic signed [32:0] sum1;
  logic        [3:0]  shift1;
  logic               sat8_1, valid1;

  always_comb
    if (shift == 4'd0) rnd = '0;
    else               rnd = 33'd1 << (shift - 4'd1);

  always_ff @(posedge clk) begin
    sum1   <= {acc[31], acc} + rnd;
    shift1 <= shift;
    sat8_1 <= sat8;
  end

  // -------------------------------------------------------------------
  // Stage 2: arithmetic shift right.
  // -------------------------------------------------------------------
  logic signed [32:0] t2;
  logic               sat8_2, valid2;

  always_ff @(posedge clk) begin
    t2     <= sum1 >>> shift1;
    sat8_2 <= sat8_1;
  end

  // -------------------------------------------------------------------
  // Stage 3: saturate. t fits in n bits iff bits 32 down to n-1 all
  // equal the sign bit.
  // -------------------------------------------------------------------
  logic signed [15:0] ysat;

  always_comb
    if (sat8_2) begin
      if (t2[32:7] != {26{t2[32]}})
        ysat = t2[32] ? 16'shFF80 : 16'sh007F;
      else
        ysat = {{8{t2[7]}}, t2[7:0]};
    end else begin
      if (t2[32:15] != {18{t2[32]}})
        ysat = t2[32] ? 16'sh8000 : 16'sh7FFF;
      else
        ysat = t2[15:0];
    end

  always_ff @(posedge clk)
    y <= ysat;

  // -------------------------------------------------------------------
  // Valid pipeline.
  // -------------------------------------------------------------------
  always_ff @(posedge clk)
    if (rst) {valid1, valid2, out_valid} <= 3'b000;
    else     {valid1, valid2, out_valid} <= {in_valid, valid1, valid2};

endmodule
