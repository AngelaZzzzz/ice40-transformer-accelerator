////////////////////////////////////////////////////////////////////////////////
// score_buf
//   32 x 16-bit output score buffer, 1 EBR
////////////////////////////////////////////////////////////////////////////////

module score_buf(input  logic        clk,
                 input  logic        rst,
                 input  logic        we,
                 input  logic [4:0]  waddr,
                 input  logic [15:0] wdata,
                 input  logic [4:0]  raddr,
                 output logic [15:0] rdata);

    logic [15:0] mem [0:31];

    always_ff @(posedge clk) begin
        if (we) mem[waddr] <= wdata;
        rdata <= mem[raddr];
    end

endmodule
