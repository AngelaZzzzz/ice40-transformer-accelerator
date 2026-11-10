////////////////////////////////////////////////////////////////////////////////
// rmsnorm_unit
//   RMSNORM execution unit using the rsqrt table and lane 0
////////////////////////////////////////////////////////////////////////////////

module rmsnorm_unit
    import gpt_pkg::*;
    (input  logic        clk,
     input  logic        rst,
     input  instr_t      instr,
     input  logic [4:0]  letter,
     input  logic [3:0]  pos,
     input  logic        start,
     output logic        done,
     input  logic [15:0] ra_data,
     input  logic [31:0] l0_acc,
     input  logic [15:0] lut_data,
     output logic [9:0]  ra_addr,
     output logic        w_en,
     output logic [9:0]  w_addr,
     output logic [15:0] w_data,
     output logic        l0_req,
     output logic [15:0] l0_a,
     output logic [15:0] l0_b,
     output logic        l0_clr,
     output logic        l0_en,
     output logic [7:0]  lut_addr);

    // TODO(zach): implement per docs/interface_spec.md section 3

    assign done = 1'b0;
    assign ra_addr = '0;
    assign w_en = 1'b0;
    assign w_addr = '0;
    assign w_data = '0;
    assign l0_req = 1'b0;
    assign l0_a = '0;
    assign l0_b = '0;
    assign l0_clr = 1'b0;
    assign l0_en = 1'b0;
    assign lut_addr = '0;

endmodule
