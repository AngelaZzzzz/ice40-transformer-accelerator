////////////////////////////////////////////////////////////////////////////////
// vga_pll
//   25 MHz pixel clock PLL from the core clock
////////////////////////////////////////////////////////////////////////////////

// One iCE40UP PLL_B (the primitive that Radiant's IP Catalog PLL wraps),
// simple feedback, reference from the 48 MHz HSOSC core clock (interface
// spec section 8):
//   phase detector  48 MHz / (DIVR + 1)    = 48 / 3  = 16 MHz
//   VCO             16 MHz x (DIVF + 1)    = 16 x 50 = 800 MHz
//   pix_clk         800 MHz / 2^DIVQ       = 800 / 32 = 25.000 MHz
// FILTER_RANGE = 1 is the loop-filter setting Radiant's PLL generator uses
// for a phase-detector frequency of 16 MHz or less. The VCO (533 to 1,066
// MHz) and output (16 to 275 MHz) are within Radiant's limits.
//
// pix_clk follows the HSOSC, so its +/-10% tolerance carries through.
// Radiant's generator accepts DIVF up to 127, so 25.125 MHz (closer to the
// 25.175 MHz standard) is also possible: DIVR = 3, DIVF = 66, DIVQ = 5,
// FILTER_RANGE = 1.
//
// pix_clk drives a global clock net (OUTGLOBAL). lock rises once the PLL
// has locked; gpt_top holds the pixel-clock logic in reset until then.
//
// Simulation: compile with sim/models/PLL_B.sv.

module vga_pll(input  logic ref_clk,
               input  logic rst_n,
               output logic pix_clk,
               output logic lock);

    PLL_B #(
        .FEEDBACK_PATH("SIMPLE"),
        .PLLOUT_SELECT_PORTA("GENCLK"),
        .PLLOUT_SELECT_PORTB("GENCLK"),
        .DIVR("2"),
        .DIVF("49"),
        .DIVQ("5"),
        .FILTER_RANGE("1")
    ) pll(
        .REFERENCECLK(ref_clk),
        .FEEDBACK(1'b0),
        .DYNAMICDELAY7(1'b0),
        .DYNAMICDELAY6(1'b0),
        .DYNAMICDELAY5(1'b0),
        .DYNAMICDELAY4(1'b0),
        .DYNAMICDELAY3(1'b0),
        .DYNAMICDELAY2(1'b0),
        .DYNAMICDELAY1(1'b0),
        .DYNAMICDELAY0(1'b0),
        .BYPASS(1'b0),
        .RESET_N(rst_n),
        .SCLK(1'b0),
        .SDI(1'b0),
        .LATCH(1'b0),
        .INTFBOUT(),
        .OUTCORE(),
        .OUTGLOBAL(pix_clk),
        .OUTCOREB(),
        .OUTGLOBALB(),
        .SDO(),
        .LOCK(lock)
    );

endmodule
