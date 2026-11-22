////////////////////////////////////////////////////////////////////////////////
// vreg_file
//   1,024 x 16-bit vector register file, 8 EBRs
////////////////////////////////////////////////////////////////////////////////

// Interface spec section 5. One write port and two registered read ports
// (1-cycle latency), any two addresses per cycle. An EBR has one read
// port, so synthesis builds two identical 1,024 x 16 copies (4 EBRs each),
// both written on every write, one per read port.
//
// INIT_FILE, if given, sets the contents at configuration (1,024 lines).

module vreg_file #(
    parameter INIT_FILE = ""
) (
    input  logic        clk,
    input  logic        rst,
    input  logic [9:0]  ra_addr,
    input  logic [9:0]  rb_addr,
    input  logic        w_en,
    input  logic [9:0]  w_addr,
    input  logic [15:0] w_data,

    output logic [15:0] ra_data,
    output logic [15:0] rb_data
);

    logic [15:0] mem [0:1023];

    initial if (INIT_FILE != "") $readmemh(INIT_FILE, mem);

    always_ff @(posedge clk) begin
        if (w_en) mem[w_addr] <= w_data;
        ra_data <= mem[ra_addr];
        rb_data <= mem[rb_addr];
    end

endmodule
