////////////////////////////////////////////////////////////////////////////////
// vecop
//   Element-wise unit for EMBED, VADD, VMUL and VRELU
////////////////////////////////////////////////////////////////////////////////

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

    // TODO(angela): implement per docs/interface_spec.md section 3

    assign done = 1'b0;
    assign sp_re = 1'b0;
    assign sp_addr = '0;
    assign ra_addr = '0;
    assign rb_addr = '0;
    assign w_en = 1'b0;
    assign w_addr = '0;
    assign w_data = '0;

endmodule
