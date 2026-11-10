////////////////////////////////////////////////////////////////////////////////
// sequencer
//   Fetches and issues instructions from program memory until HALT
////////////////////////////////////////////////////////////////////////////////

module sequencer
    import gpt_pkg::*;
    (input  logic        clk,
     input  logic        rst,
     input  logic        run,
     input  logic [4:0]  run_letter,
     input  logic [3:0]  run_pos,
     input  logic [47:0] pm_rdata,
     input  logic        unit_done,
     output logic [7:0]  pm_raddr,
     output instr_t      instr,
     output logic [4:0]  letter,
     output logic [3:0]  pos,
     output logic        start,
     output logic        busy,
     output logic        done_flag);

    // TODO(zach): implement per docs/interface_spec.md section 6

    assign pm_raddr = '0;
    assign instr = '0;
    assign letter = '0;
    assign pos = '0;
    assign start = 1'b0;
    assign busy = 1'b0;
    assign done_flag = 1'b0;

endmodule
