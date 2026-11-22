////////////////////////////////////////////////////////////////////////////////
// sequencer
//   Fetches and issues instructions from program memory until HALT
////////////////////////////////////////////////////////////////////////////////

// Interface spec section 6. A run pulse latches letter and pos, sets busy,
// clears done_flag and starts at pc = 0. Each instruction takes FETCH
// (pm_raddr = pc), LOAD (instr <= pm_rdata) and ISSUE (HALT ends the run;
// any other opcode pulses start for one cycle), then WAIT until unit_done.
// instr, letter and pos change only in LOAD, so they stay stable from start
// through the unit's final writes. run is ignored while busy. The run also
// ends after the instruction at pc = 255. done_flag drives the DONE pin.

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

    typedef enum logic [2:0] {IDLE, FETCH, LOAD, ISSUE, WAIT} statetype;
    statetype state;

    logic [7:0] pc;

    assign pm_raddr = pc;

    always_ff @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            pc <= 8'd0;
            instr <= '0;
            letter <= 5'd0;
            pos <= 4'd0;
            start <= 1'b0;
            busy <= 1'b0;
            done_flag <= 1'b0;
        end else begin
            start <= 1'b0;
            case (state)
                IDLE: begin
                    if (run) begin
                        letter <= run_letter;
                        pos <= run_pos;
                        pc <= 8'd0;
                        busy <= 1'b1;
                        done_flag <= 1'b0;
                        state <= FETCH;
                    end
                end
                FETCH: state <= LOAD;
                LOAD: begin
                    instr <= pm_rdata;
                    state <= ISSUE;
                end
                ISSUE: begin
                    if (instr.op == OP_HALT) begin
                        busy <= 1'b0;
                        done_flag <= 1'b1;
                        state <= IDLE;
                    end else begin
                        start <= 1'b1;
                        state <= WAIT;
                    end
                end
                WAIT: begin
                    if (unit_done) begin
                        if (pc == 8'hFF) begin
                            busy <= 1'b0;
                            done_flag <= 1'b1;
                            state <= IDLE;
                        end else begin
                            pc <= pc + 8'd1;
                            state <= FETCH;
                        end
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end

endmodule
