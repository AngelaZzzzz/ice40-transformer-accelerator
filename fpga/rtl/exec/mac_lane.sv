////////////////////////////////////////////////////////////////////////////////
// mac_lane
//   Signed 16 x 16 multiply-accumulate lane on one sysDSP block
////////////////////////////////////////////////////////////////////////////////

// Behavior (interface spec section 6), with a, b, en, clr sampled together:
//   en = 1, clr = 1: acc = a x b
//   en = 1, clr = 0: acc = acc + a x b
//   en = 0:          acc holds (clr is ignored)
// rst clears acc to 0.
//
// Latency: inputs applied before clock edge k appear in acc after edge
// k + 3. A new a, b pair is accepted every cycle.
//   edge k+1: a, b registered          (MAC16 input registers)
//   edge k+2: product registered       (MAC16 pipeline register)
//   edge k+3: accumulator updated      (fabric, 32-bit carry chain)
//
// The multiplier and its two register stages are written so synthesis maps
// them onto one MAC16. The accumulator is in fabric because the MAC16
// accumulator cannot start a new sum from the product in one cycle: its
// load input replaces the adder output with the C input instead of adding
// to it. A fabric accumulator keeps clr & en = "acc = a x b" exact at a
// cost of about 32 logic cells per lane.
//
// The 32-bit sum does not overflow for the program's operands: at most 256
// terms of int16 x int8, bounded by 2^30 (interface spec section 2).
//
// The en/clr pipeline registers carry syn_preserve so synthesis keeps one
// copy per lane. The eight lanes' copies are identical, and when they were
// merged in the feasibility build, one flip-flop drove all 256 accumulator
// bits and its routing made this the second-slowest path (44.5 MHz).

module mac_lane(input  logic               clk,
                input  logic               rst,
                input  logic               en,
                input  logic               clr,
                input  logic signed [15:0] a,
                input  logic signed [15:0] b,
                output logic signed [31:0] acc);

    logic signed [15:0] a_r, b_r;
    logic signed [31:0] prod;

    (* syn_preserve = 1 *) logic en1;
    (* syn_preserve = 1 *) logic clr1;
    (* syn_preserve = 1 *) logic en2;
    (* syn_preserve = 1 *) logic clr2;

    // Stage 1: input registers
    always_ff @(posedge clk) begin
        a_r <= a;
        b_r <= b;
    end

    // Stage 2: product register
    always_ff @(posedge clk)
        prod <= a_r * b_r;

    // Control pipeline, aligned with the data
    always_ff @(posedge clk)
        if (rst) {en1, clr1, en2, clr2} <= 4'b0000;
        else     {en1, clr1, en2, clr2} <= {en, clr, en1, clr1};

    // Stage 3: accumulator
    always_ff @(posedge clk)
        if (rst)       acc <= '0;
        else if (en2)  acc <= (clr2 ? 32'sd0 : acc) + prod;

endmodule
