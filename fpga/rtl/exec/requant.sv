////////////////////////////////////////////////////////////////////////////////
// requant
//   Four-stage requantizer from a 32-bit accumulator to int16
////////////////////////////////////////////////////////////////////////////////

// Implements rq(acc, s, sat8) from interface spec section 2:
//   t = acc                       if s = 0
//   t = (acc + 2^(s-1)) >>> s     otherwise
//   y = clamp(t, -32768, 32767), or clamp(t, -128, 127) when sat8 = 1,
//   stored as int16 (sign-extended when sat8 = 1).
//
// Latency 4 cycles, throughput one result per cycle:
//   0. register acc and decode the rounding constant 2^(s-1)
//   1. add the rounding constant (33 bits, so the add cannot overflow)
//   2. arithmetic shift right by s
//   3. saturate to 16 or 8 bits
// Stage 0 keeps the shift decode out of the 33-bit carry chain; in the
// feasibility build, decode plus add was the slowest path (44.5 MHz).
// Only the valid bits are reset; the data path needs no reset.

module requant(input  logic               clk,
               input  logic               rst,
               input  logic               in_valid,
               input  logic signed [31:0] acc,
               input  logic        [3:0]  shift,
               input  logic               sat8,
               output logic               out_valid,
               output logic signed [15:0] y);

    logic        [32:0] rnd, rnd0;
    logic signed [31:0] acc0;
    logic signed [32:0] sum1, t2;
    logic        [3:0]  shift0, shift1;
    logic               sat8_0, sat8_1, sat8_2;
    logic               valid0, valid1, valid2;
    logic signed [15:0] ysat;

    // Stage 0: register the input; rnd = 2^(s-1) when s > 0, else 0
    always_comb
        if (shift == 4'd0) rnd = '0;
        else               rnd = 33'd1 << (shift - 4'd1);

    always_ff @(posedge clk) begin
        acc0   <= acc;
        rnd0   <= rnd;
        shift0 <= shift;
        sat8_0 <= sat8;
    end

    // Stage 1: round
    always_ff @(posedge clk) begin
        sum1   <= {acc0[31], acc0} + rnd0;
        shift1 <= shift0;
        sat8_1 <= sat8_0;
    end

    // Stage 2: arithmetic shift right
    always_ff @(posedge clk) begin
        t2     <= sum1 >>> shift1;
        sat8_2 <= sat8_1;
    end

    // Stage 3: saturate; t fits in n bits iff bits 32 down to n-1 all
    // equal the sign bit
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

    // Valid pipeline
    always_ff @(posedge clk)
        if (rst) {valid0, valid1, valid2, out_valid} <= 4'b0000;
        else     {valid0, valid1, valid2, out_valid}
                     <= {in_valid, valid0, valid1, valid2};

endmodule
