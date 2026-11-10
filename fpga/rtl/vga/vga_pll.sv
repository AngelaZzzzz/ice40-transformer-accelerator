////////////////////////////////////////////////////////////////////////////////
// vga_pll
//   25 MHz pixel clock PLL from the core clock
////////////////////////////////////////////////////////////////////////////////

module vga_pll(input  logic ref_clk,
               input  logic rst_n,
               output logic pix_clk,
               output logic lock);

    // TODO(angela): implement per docs/interface_spec.md section 8

    assign pix_clk = 1'b0;
    assign lock = 1'b0;

endmodule
