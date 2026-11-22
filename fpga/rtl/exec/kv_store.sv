////////////////////////////////////////////////////////////////////////////////
// kv_store
//   KVSTORE unit writing keys and values into the SPRAM cache
////////////////////////////////////////////////////////////////////////////////

// Interface spec section 4. For c < 64, p = pos, byte = vr[8src+c][7:0]:
//   K layout (ALT = 0): word base + 32(c >> 4) + 16(p >> 3) + (c & 15),
//                       lane p & 7; 64 byte-masked writes
//   V layout (ALT = 1): word base + 32(c >> 4) + 16((c >> 3) & 1) + p,
//                       lane c & 7; 8 full-word writes
// cols_m1 is ignored: KVSTORE always stores 64 channels.
//
// One register read per cycle (c = 0 .. 63). In K layout every byte is
// written 2 cycles after its read, replicated into all lanes with only
// lane p & 7 enabled. In V layout 8 consecutive channels share a word:
// lanes 0 to 6 are collected and the word is written with lane 7.
// About 66 cycles. The SPRAM write port is registered, and every output
// is 0 while idle (OR-bus, spec section 1); done pulses one cycle after
// the last write.

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

    logic        go, alt;
    logic        reading;
    logic [5:0]  c;           // channel being read
    logic        v1;          // ra_data holds channel c1
    logic [5:0]  c1;
    logic [55:0] gath;        // V layout: lanes 0 to 6 of the word
    logic [7:0]  byte1;

    logic        we_q, last_q;
    logic [13:0] addr_q;
    logic [63:0] wdata_q;
    logic [7:0]  mask_q;

    assign go    = start && (instr.op == OP_KVSTORE);
    assign alt   = instr.flags[F_ALT];
    assign byte1 = ra_data[7:0];

    // Read: one channel per cycle
    always_ff @(posedge clk)
        if (rst) begin
            reading <= 1'b0;
            c       <= '0;
            v1      <= 1'b0;
        end else begin
            v1 <= reading;
            c1 <= c;
            if (go) begin
                reading <= 1'b1;
                c       <= '0;
            end else if (reading) begin
                c <= c + 6'd1;
                if (c == 6'd63) reading <= 1'b0;
            end
        end

    assign ra_addr = reading ? {instr.src, 3'b000} + {4'b0000, c} : '0;

    // Write: registered SPRAM port
    always_ff @(posedge clk)
        if (rst) begin
            we_q   <= 1'b0;
            last_q <= 1'b0;
        end else begin
            we_q   <= 1'b0;
            last_q <= 1'b0;
            if (v1) begin
                if (!alt) begin
                    we_q    <= 1'b1;
                    addr_q  <= instr.base + {7'b0, c1[5:4], 5'b00000}
                               + {9'b0, pos[3], 4'b0000}
                               + {10'b0, c1[3:0]};
                    wdata_q <= {8{byte1}};
                    mask_q  <= 8'b1 << pos[2:0];
                    last_q  <= (c1 == 6'd63);
                end else if (c1[2:0] == 3'd7) begin
                    we_q    <= 1'b1;
                    addr_q  <= instr.base + {7'b0, c1[5:4], 5'b00000}
                               + {9'b0, c1[3], 4'b0000}
                               + {10'b0, pos};
                    wdata_q <= {byte1, gath};
                    mask_q  <= 8'hFF;
                    last_q  <= (c1 == 6'd63);
                end else begin
                    gath[8 * c1[2:0] +: 8] <= byte1;
                end
            end
        end

    assign sp_we       = we_q;
    assign sp_addr     = we_q ? addr_q : '0;
    assign sp_wdata    = we_q ? wdata_q : '0;
    assign sp_bytemask = we_q ? mask_q : '0;

    always_ff @(posedge clk)
        if (rst) done <= 1'b0;
        else     done <= we_q && last_q;

endmodule
