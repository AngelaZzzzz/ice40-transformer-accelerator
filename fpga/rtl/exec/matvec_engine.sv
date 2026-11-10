////////////////////////////////////////////////////////////////////////////////
// matvec_engine
//   Eight-lane matrix-vector unit; lends lane 0 to RMSNORM and SOFTMAX
////////////////////////////////////////////////////////////////////////////////

// MATVEC (interface spec section 3): for row group g < R/8 and lane l < 8,
//   acc = sum over c < C of vr[8src+c] x S8(base+gC+c, l)
//   y   = rq(acc, shift, SAT8)
//   ALT = 0: vr[8dst+8g+l] = y;  ALT = 1: score[8g+l] = y
// R = 8(rows_m1+1), C = 8(cols_m1+1). Starts on start with op = MATVEC;
// ignores every other opcode.
//
// Pipeline (cycle t issues one column):
//   t    SPRAM word base+gC+c and vector-register word 8src+c requested
//        (base+gC+c is just base plus a running count)
//   t+2  both registered (sp_q, act), so SPRAM output timing stays short
//   t+5  term in the lane accumulators (mac_lane latency 3)
//   t+6  at the end of a group, all 8 sums latched into res
//   then res drains through one requant, one row per cycle, while the
//   next group accumulates (C >= 8 cycles, so the drain always finishes in
//   time), and each result is written to the vector registers or score
//   buffer. done pulses the cycle after the last write.
// Cycles per MATVEC: (R/8) x C issue cycles plus 19 cycles of fill/drain.
//
// Lane 0 borrow (spec section 6): while l0_req = 1, lane 0 takes l0_a,
// l0_b, l0_en, l0_clr directly; l0_acc follows 3 cycles after the inputs
// (see mac_lane.sv). The program never overlaps a borrow with a MATVEC.
//
// OR-bus (spec section 1): sp_re, sp_addr, ra_addr, w_*, sb_* are 0
// whenever they are not in use.

module matvec_engine
    import gpt_pkg::*;
    (input  logic        clk,
     input  logic        rst,
     input  instr_t      instr,
     input  logic [4:0]  letter,
     input  logic [3:0]  pos,
     input  logic        start,
     output logic        done,
     input  logic [63:0] sp_rdata,
     input  logic [15:0] ra_data,
     input  logic        l0_req,
     input  logic [15:0] l0_a,
     input  logic [15:0] l0_b,
     input  logic        l0_clr,
     input  logic        l0_en,
     output logic        sp_re,
     output logic [13:0] sp_addr,
     output logic [9:0]  ra_addr,
     output logic        w_en,
     output logic [9:0]  w_addr,
     output logic [15:0] w_data,
     output logic        sb_we,
     output logic [4:0]  sb_waddr,
     output logic [15:0] sb_wdata,
     output logic [31:0] l0_acc);

    logic               go;
    logic               issuing, last_col, last_grp;
    logic [7:0]         col;
    logic [4:0]         grp;
    logic [13:0]        ptr;

    logic               v1, clr1, end1;
    logic               v2, clr2, end2;
    logic               end3, end4, end5;
    logic [63:0]        sp_q;
    logic signed [15:0] act;

    logic signed [15:0] lane_a [8];
    logic signed [15:0] lane_b [8];
    logic [7:0]         lane_en, lane_clr;
    logic signed [31:0] lane_acc [8];

    logic signed [31:0] res [8];
    logic               draining;
    logic [2:0]         k;
    logic signed [31:0] rq_in;
    logic               rq_valid;
    logic               y_valid;
    logic signed [15:0] y;
    logic [7:0]         wb_row;
    logic               alt;

    assign go  = start && (instr.op == OP_MATVEC);
    assign alt = instr.flags[F_ALT];

    // Issue: one column per cycle, groups back to back
    assign last_col = (col == {instr.cols_m1, 3'b111});
    assign last_grp = (grp == instr.rows_m1);

    always_ff @(posedge clk)
        if (rst) begin
            issuing <= 1'b0;
            col     <= '0;
            grp     <= '0;
            ptr     <= '0;
        end else if (go) begin
            issuing <= 1'b1;
            col     <= '0;
            grp     <= '0;
            ptr     <= instr.base;
        end else if (issuing) begin
            ptr <= ptr + 14'd1;
            if (last_col) begin
                col <= '0;
                grp <= grp + 5'd1;
                if (last_grp) issuing <= 1'b0;
            end else
                col <= col + 8'd1;
        end

    assign sp_re   = issuing;
    assign sp_addr = issuing ? ptr : '0;
    assign ra_addr = issuing ? ({instr.src, 3'b000} + {2'b00, col}) : '0;

    // Control pipeline, aligned with the data
    always_ff @(posedge clk)
        if (rst) begin
            {v1, clr1, end1, v2, clr2, end2} <= '0;
            {end3, end4, end5}               <= '0;
        end else begin
            v1   <= issuing;
            clr1 <= (col == 8'd0);
            end1 <= issuing & last_col;
            v2   <= v1;
            clr2 <= clr1;
            end2 <= end1;
            end3 <= end2;
            end4 <= end3;
            end5 <= end4;
        end

    // Data registers in front of the lanes
    always_ff @(posedge clk) begin
        sp_q <= sp_rdata;
        act  <= ra_data;
    end

    // Lanes: shared activation, one sign-extended weight byte each
    genvar l;
    generate
        for (l = 0; l < 8; l++) begin : g_lane
            if (l == 0) begin : g_l0
                assign lane_a[l]   = l0_req ? l0_a   : act;
                assign lane_b[l]   = l0_req ? l0_b
                                            : {{8{sp_q[7]}}, sp_q[7:0]};
                assign lane_en[l]  = l0_req ? l0_en  : v2;
                assign lane_clr[l] = l0_req ? l0_clr : clr2;
            end else begin : g_ln
                assign lane_a[l]   = act;
                assign lane_b[l]   = {{8{sp_q[8*l+7]}}, sp_q[8*l +: 8]};
                assign lane_en[l]  = v2;
                assign lane_clr[l] = clr2;
            end

            mac_lane lane(
                .clk(clk),
                .rst(rst),
                .en(lane_en[l]),
                .clr(lane_clr[l]),
                .a(lane_a[l]),
                .b(lane_b[l]),
                .acc(lane_acc[l])
            );

            // Latch the group's 8 sums when its last term has landed
            always_ff @(posedge clk)
                if (end5) res[l] <= lane_acc[l];
        end
    endgenerate

    assign l0_acc = lane_acc[0];

    // Drain the latched sums through one requantizer, one row per cycle
    always_ff @(posedge clk)
        if (rst) begin
            draining <= 1'b0;
            k        <= '0;
        end else if (end5) begin
            draining <= 1'b1;
            k        <= '0;
        end else if (draining) begin
            k <= k + 3'd1;
            if (k == 3'd7) draining <= 1'b0;
        end

    always_ff @(posedge clk) begin
        rq_in <= res[k];
        if (rst) rq_valid <= 1'b0;
        else     rq_valid <= draining;
    end

    requant rq(
        .clk(clk),
        .rst(rst),
        .in_valid(rq_valid),
        .acc(rq_in),
        .shift(instr.shift),
        .sat8(instr.flags[F_SAT8]),
        .out_valid(y_valid),
        .y(y)
    );

    // Writeback; results arrive in row order 0 .. R-1
    always_ff @(posedge clk)
        if (rst || go)    wb_row <= '0;
        else if (y_valid) wb_row <= wb_row + 8'd1;

    assign w_en     = y_valid & ~alt;
    assign w_addr   = w_en ? ({instr.dst, 3'b000} + {2'b00, wb_row}) : '0;
    assign w_data   = w_en ? y : '0;
    assign sb_we    = y_valid & alt;
    assign sb_waddr = sb_we ? wb_row[4:0] : '0;
    assign sb_wdata = sb_we ? y : '0;

    always_ff @(posedge clk)
        if (rst) done <= 1'b0;
        else     done <= y_valid && (wb_row == {instr.rows_m1, 3'b111});

endmodule
