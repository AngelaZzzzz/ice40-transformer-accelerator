package gpt_pkg;

  // ---------------------------------------------------------------------
  // Model shape
  // ---------------------------------------------------------------------
  localparam int D     = 64;
  localparam int HEADS = 4;
  localparam int HD    = 16;
  localparam int T     = 16;
  localparam int V     = 27;
  localparam int BOS   = 26;
  localparam int LANES = 8;

  // ---------------------------------------------------------------------
  // Instructions
  // ---------------------------------------------------------------------
  typedef enum logic [3:0] {
    OP_HALT    = 4'h0,
    OP_EMBED   = 4'h1,
    OP_MATVEC  = 4'h2,
    OP_KVSTORE = 4'h3,
    OP_VADD    = 4'h4,
    OP_VMUL    = 4'h5,
    OP_VRELU   = 4'h6,
    OP_RMSNORM = 4'h7,
    OP_SOFTMAX = 4'h8
  } op_t;

  typedef struct packed {
    op_t         op;
    logic [6:0]  src;
    logic [6:0]  dst;
    logic [13:0] base;
    logic [4:0]  rows_m1;
    logic [4:0]  cols_m1;
    logic [3:0]  shift;
    logic [1:0]  flags;
  } instr_t;

  localparam int F_SAT8 = 0;
  localparam int F_ALT  = 1;

  // ---------------------------------------------------------------------
  // SPRAM map (64-bit word addresses)
  // ---------------------------------------------------------------------
  localparam logic [13:0] A_TOK  = 14'h0000;
  localparam logic [13:0] A_POS  = 14'h0100;
  localparam logic [13:0] A_L0   = 14'h0180;
  localparam logic [13:0] A_L1   = 14'h1980;
  localparam logic [13:0] A_OUT  = 14'h3180;
  localparam logic [13:0] A_K0   = 14'h3280;
  localparam logic [13:0] A_V0   = 14'h3300;
  localparam logic [13:0] A_K1   = 14'h3380;
  localparam logic [13:0] A_V1   = 14'h3400;

  localparam logic [13:0] O_WQ   = 14'h0000;
  localparam logic [13:0] O_WK   = 14'h0200;
  localparam logic [13:0] O_WV   = 14'h0400;
  localparam logic [13:0] O_WO   = 14'h0600;
  localparam logic [13:0] O_W1   = 14'h0800;
  localparam logic [13:0] O_W2   = 14'h1000;

  // ---------------------------------------------------------------------
  // Vector-register map (units of 8 words)
  // ---------------------------------------------------------------------
  localparam logic [6:0] VR_X  = 7'd0;
  localparam logic [6:0] VR_XN = 7'd8;
  localparam logic [6:0] VR_Q  = 7'd16;
  localparam logic [6:0] VR_K  = 7'd24;
  localparam logic [6:0] VR_V  = 7'd32;
  localparam logic [6:0] VR_A  = 7'd40;
  localparam logic [6:0] VR_S  = 7'd48;
  localparam logic [6:0] VR_T  = 7'd56;
  localparam logic [6:0] VR_H  = 7'd64;

endpackage
