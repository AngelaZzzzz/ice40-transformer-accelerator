////////////////////////////////////////////////////////////////////////////////
// vecop
//   Element-wise unit for EMBED, VADD, VMUL and VRELU
////////////////////////////////////////////////////////////////////////////////

// Interface spec section 3, C = 8 x (cols_m1 + 1) elements:
//   EMBED  vr[8dst+i] = sat16((S8(base+8letter+k, l)
//                              + S8(base+256+8pos+k, l)) <<< shift)
//   VADD   vr[8dst+i] = sat16(vr[8dst+i] + vr[8src+i])
//   VMUL   vr[8dst+i] = rq(vr[8dst+i] x vr[8src+i], shift, 0)
//   VRELU  vr[8dst+i] = max(vr[8src+i], 0)
// with k = i / 8, l = i % 8.
//
// EMBED, per SPRAM word k (11 cycles): read the letter word, read the
// position word, then write its 8 lanes, one per cycle.
// VADD and VRELU stream one element per cycle: read on read ports A
// (dst for VADD, src for VRELU) and B (src), write 2 cycles later. Reads
// run ahead of writes, and each element reads and writes only its own
// index, so src may equal dst.
// VMUL is unused by the current program and all eight MAC16s belong to
// matvec_engine, so it uses a 16-cycle shift-add multiplier: about 21
// cycles per element, and few LUTs.
//
// Every write data path is registered, and w_en, w_data and the read
// addresses are 0 while idle (OR-bus, spec section 1). done pulses one
// cycle after the last write.

module vecop
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
     input  logic [15:0] rb_data,
     output logic        sp_re,
     output logic [13:0] sp_addr,
     output logic [9:0]  ra_addr,
     output logic [9:0]  rb_addr,
     output logic        w_en,
     output logic [9:0]  w_addr,
     output logic [15:0] w_data);

    typedef enum logic [3:0] {
        S_IDLE,
        S_E_TOK,    // EMBED: read the letter word
        S_E_POS,    // EMBED: read the position word, capture letter word
        S_E_CAP,    // EMBED: capture position word
        S_E_WR,     // EMBED: one lane per cycle
        S_STREAM,   // VADD, VRELU: one read per cycle
        S_DRAIN,    // VADD, VRELU: last writes in flight
        S_M_RD,     // VMUL: read both operands
        S_M_LD,     // VMUL: load the multiplier
        S_M_MUL,    // VMUL: 16 shift-add steps
        S_M_SGN,    // VMUL: apply the sign
        S_M_RND,    // VMUL: add the rounding constant
        S_M_SHR,    // VMUL: arithmetic shift right
        S_M_SAT     // VMUL: saturate and write
    } state_t;

    state_t      state;
    logic        go;
    logic [7:0]  i;           // element index, 0 .. C-1
    logic [7:0]  last_i;
    logic [2:0]  lane;
    logic [4:0]  k;           // EMBED word index, 0 .. C/8-1
    logic [63:0] tok_q, pos_q;
    logic [9:0]  dst_a, src_a;

    // Write port registers
    logic        wv;
    logic [9:0]  wa;
    logic [15:0] wd;
    logic        wlast;

    // Stream pipeline (VADD, VRELU)
    logic        v1, last1;
    logic [9:0]  a1;

    // VMUL datapath
    logic [15:0] mb;          // magnitude, |-32768| = 32768 fits
    logic        neg;
    logic [31:0] macc, mcand;
    logic [3:0]  step;
    logic signed [32:0] p, t;

    assign go = start && (instr.op == OP_EMBED || instr.op == OP_VADD ||
                          instr.op == OP_VMUL  || instr.op == OP_VRELU);
    assign last_i = {instr.cols_m1, 3'b111};
    assign dst_a  = {instr.dst, 3'b000};
    assign src_a  = {instr.src, 3'b000};

    // ---------------------------------------------------------------------
    // Arithmetic
    // ---------------------------------------------------------------------

    function automatic logic [15:0] sat16(input logic signed [32:0] x);
        if (x > 33'sd32767)        return 16'h7FFF;
        else if (x < -33'sd32768)  return 16'h8000;
        else                       return x[15:0];
    endfunction

    // EMBED element: sign-extended byte sum (9 bits), shifted into 24 bits
    function automatic logic [15:0] embed_elem(input logic [7:0] a,
                                               input logic [7:0] b,
                                               input logic [3:0] s);
        logic signed [8:0]  sum;
        logic signed [23:0] sh;
        sum = $signed({a[7], a}) + $signed({b[7], b});
        sh  = 24'(sum) <<< s;
        return sat16(33'(sh));
    endfunction

    function automatic logic [15:0] vadd_elem(input logic [15:0] a,
                                              input logic [15:0] b);
        return sat16(33'($signed(a)) + 33'($signed(b)));
    endfunction

    function automatic logic [15:0] relu_elem(input logic [15:0] a);
        return a[15] ? 16'h0000 : a;
    endfunction

    function automatic logic [15:0] mag(input logic [15:0] a);
        return a[15] ? 16'(-a) : a;
    endfunction

    // ---------------------------------------------------------------------
    // Control
    // ---------------------------------------------------------------------

    always_ff @(posedge clk)
        if (rst) begin
            state <= S_IDLE;
            i     <= '0;
            k     <= '0;
            lane  <= '0;
            wv    <= 1'b0;
            wlast <= 1'b0;
            v1    <= 1'b0;
            last1 <= 1'b0;
        end else begin
            wv    <= 1'b0;
            wlast <= 1'b0;
            v1    <= 1'b0;
            last1 <= 1'b0;

            // Stream write stage: data read last cycle
            if (v1) begin
                wv    <= 1'b1;
                wa    <= a1;
                wd    <= (instr.op == OP_VADD) ? vadd_elem(ra_data, rb_data)
                                               : relu_elem(ra_data);
                wlast <= last1;
            end

            case (state)
                S_IDLE:
                    if (go) begin
                        i    <= '0;
                        k    <= '0;
                        lane <= '0;
                        case (instr.op)
                            OP_EMBED: state <= S_E_TOK;
                            OP_VMUL:  state <= S_M_RD;
                            default:  state <= S_STREAM;
                        endcase
                    end

                // EMBED
                S_E_TOK: state <= S_E_POS;
                S_E_POS: begin
                    tok_q <= sp_rdata;
                    state <= S_E_CAP;
                end
                S_E_CAP: begin
                    pos_q <= sp_rdata;
                    state <= S_E_WR;
                end
                S_E_WR: begin
                    wv    <= 1'b1;
                    wa    <= dst_a + {2'b00, i};
                    wd    <= embed_elem(tok_q[8 * lane +: 8],
                                        pos_q[8 * lane +: 8], instr.shift);
                    wlast <= (i == last_i);
                    i     <= i + 8'd1;
                    lane  <= lane + 3'd1;
                    if (lane == 3'd7) begin
                        k     <= k + 5'd1;
                        state <= (i == last_i) ? S_IDLE : S_E_TOK;
                    end
                end

                // VADD, VRELU
                S_STREAM: begin
                    v1    <= 1'b1;
                    a1    <= dst_a + {2'b00, i};
                    last1 <= (i == last_i);
                    i     <= i + 8'd1;
                    if (i == last_i) state <= S_DRAIN;
                end
                S_DRAIN:
                    if (!v1) state <= S_IDLE;

                // VMUL
                S_M_RD: state <= S_M_LD;
                S_M_LD: begin
                    mcand <= {16'h0000, mag(ra_data)};
                    mb    <= mag(rb_data);
                    neg   <= ra_data[15] ^ rb_data[15];
                    macc  <= '0;
                    step  <= '0;
                    state <= S_M_MUL;
                end
                S_M_MUL: begin
                    if (mb[0]) macc <= macc + mcand;
                    mcand <= mcand << 1;
                    mb    <= mb >> 1;
                    step  <= step + 4'd1;
                    if (step == 4'd15) state <= S_M_SGN;
                end
                S_M_SGN: begin
                    p     <= neg ? -$signed({1'b0, macc})
                                 :  $signed({1'b0, macc});
                    state <= S_M_RND;
                end
                S_M_RND: begin
                    if (instr.shift != 4'd0)
                        p <= p + (33'sd1 <<< (instr.shift - 4'd1));
                    state <= S_M_SHR;
                end
                S_M_SHR: begin
                    t     <= p >>> instr.shift;
                    state <= S_M_SAT;
                end
                S_M_SAT: begin
                    wv    <= 1'b1;
                    wa    <= dst_a + {2'b00, i};
                    wd    <= sat16(t);
                    wlast <= (i == last_i);
                    i     <= i + 8'd1;
                    state <= (i == last_i) ? S_IDLE : S_M_RD;
                end

                default: state <= S_IDLE;
            endcase
        end

    always_ff @(posedge clk)
        if (rst) done <= 1'b0;
        else     done <= wv && wlast;

    // ---------------------------------------------------------------------
    // Ports (0 when unused)
    // ---------------------------------------------------------------------

    always_comb begin
        sp_re   = 1'b0;
        sp_addr = '0;
        ra_addr = '0;
        rb_addr = '0;
        case (state)
            S_E_TOK: begin
                sp_re   = 1'b1;
                sp_addr = instr.base + {6'b0, letter, 3'b000} + 14'(k);
            end
            S_E_POS: begin
                sp_re   = 1'b1;
                sp_addr = instr.base + 14'd256 + {7'b0, pos, 3'b000}
                          + 14'(k);
            end
            S_STREAM: begin
                ra_addr = ((instr.op == OP_VADD) ? dst_a : src_a)
                          + {2'b00, i};
                rb_addr = (instr.op == OP_VADD) ? src_a + {2'b00, i} : '0;
            end
            S_M_RD: begin
                ra_addr = dst_a + {2'b00, i};
                rb_addr = src_a + {2'b00, i};
            end
            default: ;
        endcase
    end

    assign w_en   = wv;
    assign w_addr = wv ? wa : '0;
    assign w_data = wv ? wd : '0;

endmodule
