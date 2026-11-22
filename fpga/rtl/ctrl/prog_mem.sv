////////////////////////////////////////////////////////////////////////////////
// prog_mem
//   256 x 48-bit program memory, 3 EBRs, 1-cycle read
////////////////////////////////////////////////////////////////////////////////

module prog_mem(input  logic        clk,
                input  logic        rst,
                input  logic        we,
                input  logic [7:0]  waddr,
                input  logic [47:0] wdata,
                input  logic [7:0]  raddr,
                output logic [47:0] rdata);

    logic [47:0] mem [0:255];

    always_ff @(posedge clk) begin
        if (we) mem[waddr] <= wdata;
        rdata <= mem[raddr];
    end

endmodule
