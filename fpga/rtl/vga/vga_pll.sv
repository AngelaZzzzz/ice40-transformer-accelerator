////////////////////////////////////////////////////////////////////////////////
// vga_pll
//   25.125 MHz pixel clock PLL from the 12 MHz oscillator
////////////////////////////////////////////////////////////////////////////////

// One iCE40UP PLL_B (the primitive that Radiant's IP Catalog PLL wraps),
// simple feedback (interface spec section 8). The reference is the
// UPduino's 12 MHz oscillator, top-level input clk_12m on pin 35:
//   phase detector  12 MHz / (DIVR + 1)    = 12 / 1   = 12 MHz
//   VCO             12 MHz x (DIVF + 1)    = 12 x 67  = 804 MHz
//   pix_clk         804 MHz / 2^DIVQ       = 804 / 32 = 25.125 MHz
// FILTER_RANGE = 1 is the loop-filter setting Radiant's PLL generator uses
// for a phase-detector frequency of 16 MHz or less. The VCO (533 to 1,066
// MHz) and output (16 to 275 MHz) are within Radiant's limits. The
// oscillator is accurate to tens of ppm, so pix_clk is stable and within
// 0.2% of the 25.175 MHz VGA standard.
//
// pix_clk drives a global clock net (OUTGLOBAL). lock rises once the PLL
// has locked; gpt_top holds the pixel-clock logic in reset until then.
//
// Simulation: compile with sim/models/PLL_B.sv.

module vga_pll(input  logic ref_clk,
               input  logic rst_n,
               output logic pix_clk,
               output logic lock);

    logic fb;

    PLL_B #(
        .FEEDBACK_PATH("SIMPLE"),
        .PLLOUT_SELECT_PORTA("GENCLK"),
        .PLLOUT_SELECT_PORTB("GENCLK"),
        .DIVR("0"),
        .DIVF("66"),
        .DIVQ("5"),
        .FILTER_RANGE("1")
    ) pll(
        .REFERENCECLK(ref_clk),
        .FEEDBACK(fb),
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
        .INTFBOUT(fb),
        .OUTCORE(),
        .OUTGLOBAL(pix_clk),
        .OUTCOREB(),
        .OUTGLOBALB(),
        .SDO(),
        .LOCK(lock)
    );

endmodule
