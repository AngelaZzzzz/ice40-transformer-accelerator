////////////////////////////////////////////////////////////////////////////////
// text_buffer
//   1,024 x 8-bit dual-clock character buffer, 2 EBRs
////////////////////////////////////////////////////////////////////////////////

// Simple dual-port RAM (interface spec section 8): written in wclk (the
// core clock, from cmd_decoder WRITE_CHAR) and read in rclk (pix_clk, by
// text_renderer). Each byte is {color, char[6:0]}; cells 0 to 599 are the
// 40 x 15 screen and the rest are unused.
//
// The read is registered (one rclk cycle). A read of the cell being
// written in the same moment may return the old or new byte; the screen
// shows the new one on the next frame.
//
// INIT_FILE, if given, sets the power-up contents (for a fixed test
// screen). Without it the EBRs power up at 0, which renders blank; in
// simulation the cells start unknown until written.

module text_buffer #(
    parameter INIT_FILE = ""
) (
    input  logic       wclk,
    input  logic       we,
    input  logic [9:0] waddr,
    input  logic [7:0] wdata,
    input  logic       rclk,
    input  logic [9:0] raddr,

    output logic [7:0] rdata
);

    logic [7:0] mem [0:1023];

    initial if (INIT_FILE != "") $readmemh(INIT_FILE, mem);

    always_ff @(posedge wclk) begin
        if (we) mem[waddr] <= wdata;
    end

    always_ff @(posedge rclk) begin
        rdata <= mem[raddr];
    end

endmodule
