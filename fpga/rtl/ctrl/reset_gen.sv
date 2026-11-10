////////////////////////////////////////////////////////////////////////////////
// reset_gen
//   Active-high synchronous reset, held for 255 cycles after configuration
//   and after the active-low reset button is released. Relies on iCE40
//   flip-flops initializing to 0.
////////////////////////////////////////////////////////////////////////////////

module reset_gen(input  logic clk,
                 input  logic rst_n_async,
                 output logic rst);

    logic       button_pressed;
    logic [7:0] hold_count = 8'd0;

    synchronizer #(.WIDTH(1)) button_sync(
        .clk(clk),
        .rst(1'b0),
        .d(~rst_n_async),
        .q(button_pressed)
    );

    always_ff @(posedge clk) begin
        if (button_pressed) hold_count <= 8'd0;
        else if (rst) hold_count <= hold_count + 8'd1;
    end

    assign rst = (hold_count != 8'hFF);

endmodule
