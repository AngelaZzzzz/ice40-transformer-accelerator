////////////////////////////////////////////////////////////////////////////////
// matvec_engine
//   Eight-lane matrix-vector unit; lends lane 0 to RMSNORM and SOFTMAX
////////////////////////////////////////////////////////////////////////////////

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

    // TODO(angela): implement per docs/interface_spec.md section 3

    assign done = 1'b0;
    assign sp_re = 1'b0;
    assign sp_addr = '0;
    assign ra_addr = '0;
    assign w_en = 1'b0;
    assign w_addr = '0;
    assign w_data = '0;
    assign sb_we = 1'b0;
    assign sb_waddr = '0;
    assign sb_wdata = '0;
    assign l0_acc = '0;

endmodule
