////////////////////////////////////////////////////////////////////////////////
// kv_store
//   KVSTORE unit writing keys and values into the SPRAM cache
////////////////////////////////////////////////////////////////////////////////

module kv_store
    import gpt_pkg::*;
    (input  logic        clk,
     input  logic        rst,
     input  instr_t      instr,
     input  logic [4:0]  letter,
     input  logic [3:0]  pos,
     input  logic        start,
     output logic        done,
     input  logic [15:0] ra_data,
     output logic [9:0]  ra_addr,
     output logic        sp_we,
     output logic [13:0] sp_addr,
     output logic [63:0] sp_wdata,
     output logic [7:0]  sp_bytemask);

    // TODO(angela): implement per docs/interface_spec.md section 4

    assign done = 1'b0;
    assign ra_addr = '0;
    assign sp_we = 1'b0;
    assign sp_addr = '0;
    assign sp_wdata = '0;
    assign sp_bytemask = '0;

endmodule
