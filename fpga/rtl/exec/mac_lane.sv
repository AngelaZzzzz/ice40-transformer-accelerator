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
//   edge k+1: a, b registered          (MAC16 A and B input registers)
//   edge k+2: product registered       (MAC16 16 x 16 output register)
//   edge k+3: accumulator updated      (fabric, 32-bit carry chain)
//
// The multiplier is one MAC16, instantiated through Radiant's pmi_dsp
// wrapper with its input and product registers enabled, so the whole
// multiply path stays inside the DSP block. When the same registers were
// written in plain RTL, synthesis left them in fabric and merged the
// shared activation register across lanes, and the routing to and from
// the DSP blocks limited the feasibility build to 46.8 MHz.
//
// The accumulator is in fabric because the MAC16 accumulator cannot start
// a new sum from the product in one cycle: its load input replaces the
// adder output with the C input instead of adding to it. A fabric
// accumulator keeps clr & en = "acc = a x b" exact at a cost of about 32
// logic cells per lane.
//
// The 32-bit sum does not overflow for the program's operands: at most 256
// terms of int16 x int8, bounded by 2^30 (interface spec section 2).
//
// The en/clr pipeline registers carry syn_preserve so synthesis keeps one
// copy per lane. The eight lanes' copies are identical, and when they were
// merged, one flip-flop drove all 256 accumulator bits and its routing was
// a critical path.
//
// Simulation: compile with sim/models/pmi_dsp.sv.

module mac_lane(input  logic               clk,
                input  logic               rst,
                input  logic               en,
                input  logic               clr,
                input  logic signed [15:0] a,
                input  logic signed [15:0] b,
                output logic signed [31:0] acc);

    logic [31:0] prod;

    (* syn_preserve = 1 *) logic en1;
    (* syn_preserve = 1 *) logic clr1;
    (* syn_preserve = 1 *) logic en2;
    (* syn_preserve = 1 *) logic clr2;

    // Stages 1 and 2: registered signed 16 x 16 multiply in the MAC16
    pmi_dsp #(
        .A_REG("0b1"),
        .B_REG("0b1"),
        .PIPELINE_16x16_MULT_REG2("0b1"),
        .TOPOUTPUT_SELECT("0b11"),
        .BOTOUTPUT_SELECT("0b11"),
        .A_SIGNED("0b1"),
        .B_SIGNED("0b1")
    ) mult(
        .CLK(clk),
        .CE(1'b1),
        .C(16'h0000),
        .A(a),
        .B(b),
        .D(16'h0000),
        .AHOLD(1'b0),
        .BHOLD(1'b0),
        .CHOLD(1'b0),
        .DHOLD(1'b0),
        .IRSTTOP(1'b0),
        .IRSTBOT(1'b0),
        .ORSTTOP(1'b0),
        .ORSTBOT(1'b0),
        .OLOADTOP(1'b0),
        .OLOADBOT(1'b0),
        .ADDSUBTOP(1'b0),
        .ADDSUBBOT(1'b0),
        .OHOLDTOP(1'b0),
        .OHOLDBOT(1'b0),
        .CI(1'b0),
        .ACCUMCI(1'b0),
        .SIGNEXTIN(1'b0),
        .O(prod),
        .CO(),
        .ACCUMCO(),
        .SIGNEXTOUT()
    );

    // Control pipeline, aligned with the data
    always_ff @(posedge clk)
        if (rst) {en1, clr1, en2, clr2} <= 4'b0000;
        else     {en1, clr1, en2, clr2} <= {en, clr, en1, clr1};

    // Stage 3: accumulator
    always_ff @(posedge clk)
        if (rst)      acc <= '0;
        else if (en2) acc <= (clr2 ? 32'sd0 : acc) + $signed(prod);

endmodule
