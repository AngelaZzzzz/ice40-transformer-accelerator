////////////////////////////////////////////////////////////////////////////////
// synchronizer
//   Two-flop synchronizer for a WIDTH-bit asynchronous input; resets to 0
////////////////////////////////////////////////////////////////////////////////

module synchronizer #(
    parameter int WIDTH = 1
) (
    input  logic             clk,
    input  logic             rst,
    input  logic [WIDTH-1:0] d,

    output logic [WIDTH-1:0] q
);

    logic [WIDTH-1:0] meta;

    always_ff @(posedge clk) begin
        if (rst) begin
            meta <= '0;
            q <= '0;
        end else begin
            meta <= d;
            q <= meta;
        end
    end

endmodule
