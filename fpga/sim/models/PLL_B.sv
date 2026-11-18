`timescale 1ns/1ps

////////////////////////////////////////////////////////////////////////////////
// PLL_B
//   Simulation-only behavioral model of the iCE40UP PLL primitive, simple
//   feedback path only; Radiant supplies the primitive for synthesis
////////////////////////////////////////////////////////////////////////////////

// Same ports and parameters as Radiant's PLL_B (cae_library iCE40UP). With
// FEEDBACK_PATH = "SIMPLE", the output frequency is
//   f_out = f_ref x (DIVF + 1) / ((DIVR + 1) x 2^DIVQ).
// The model measures the reference period from its rising edges, holds
// LOCK low and the outputs at 0 while RESET_N is low and for LOCK_CYCLES
// reference cycles after it rises, then sets LOCK and runs OUTGLOBAL and
// OUTCORE at f_out. It does not model phase alignment or jitter, and it
// follows a change in the reference period at the next measurement.
//
// Radiant's own model needs its tSPLL40 library cell and did not lock in
// Icarus, so this one is used instead.

module PLL_B #(
    parameter FEEDBACK_PATH                  = "SIMPLE",
    parameter DELAY_ADJUSTMENT_MODE_FEEDBACK = "FIXED",
    parameter FDA_FEEDBACK                   = "0",
    parameter DELAY_ADJUSTMENT_MODE_RELATIVE = "FIXED",
    parameter FDA_RELATIVE                   = "0",
    parameter SHIFTREG_DIV_MODE              = "0",
    parameter PLLOUT_SELECT_PORTA            = "GENCLK",
    parameter PLLOUT_SELECT_PORTB            = "GENCLK",
    parameter DIVR                           = "0",
    parameter DIVF                           = "0",
    parameter DIVQ                           = "1",
    parameter FILTER_RANGE                   = "0",
    parameter EXTERNAL_DIVIDE_FACTOR         = "NONE",
    parameter ENABLE_ICEGATE_PORTA           = "0",
    parameter ENABLE_ICEGATE_PORTB           = "0",
    parameter TEST_MODE                      = "0",
    parameter FREQUENCY_PIN_REFERENCECLK     = "NONE"
) (
    input  logic REFERENCECLK,
    input  logic FEEDBACK,
    input  logic DYNAMICDELAY7,
    input  logic DYNAMICDELAY6,
    input  logic DYNAMICDELAY5,
    input  logic DYNAMICDELAY4,
    input  logic DYNAMICDELAY3,
    input  logic DYNAMICDELAY2,
    input  logic DYNAMICDELAY1,
    input  logic DYNAMICDELAY0,
    input  logic BYPASS,
    input  logic RESET_N,
    input  logic SCLK,
    input  logic SDI,
    input  logic LATCH,

    output logic INTFBOUT,
    output logic OUTCORE,
    output logic OUTGLOBAL,
    output logic OUTCOREB,
    output logic OUTGLOBALB,
    output logic SDO,
    output logic LOCK
);

    localparam int LOCK_CYCLES = 64;

    // Decimal string parameter ("49") to integer
    function automatic int dec(input logic [8*8-1:0] s);
        int v = 0;
        for (int i = 7; i >= 0; i--)
            if (s[8*i +: 8] >= "0" && s[8*i +: 8] <= "9")
                v = 10 * v + int'(s[8*i +: 8] - "0");
        return v;
    endfunction

    localparam int R = dec(DIVR);
    localparam int F = dec(DIVF);
    localparam int Q = dec(DIVQ);

    initial
        if (FEEDBACK_PATH != "SIMPLE" || BYPASS === 1'b1)
            $error("PLL_B model: only the SIMPLE feedback path is modeled");

    // Reference period, measured over each reference cycle
    realtime t_last = 0;
    realtime t_ref  = 0;
    int      n_ref  = 0;

    initial LOCK = 1'b0;

    always @(posedge REFERENCECLK or negedge RESET_N)
        if (!RESET_N) begin
            n_ref <= 0;
            LOCK  <= 1'b0;
        end else begin
            if (t_last > 0) t_ref = $realtime - t_last;
            t_last = $realtime;
            if (n_ref < LOCK_CYCLES) n_ref <= n_ref + 1;
            else                     LOCK  <= 1'b1;
        end

    // Output clock
    logic out = 1'b0;

    always begin
        if (LOCK && t_ref > 0) begin
            #(t_ref * (R + 1) * (2.0 ** Q) / (F + 1) / 2.0) out = ~out;
        end else begin
            out = 1'b0;
            @(posedge LOCK);
        end
    end

    assign OUTGLOBAL  = out & LOCK;
    assign OUTCORE    = out & LOCK;
    assign OUTGLOBALB = out & LOCK;
    assign OUTCOREB   = out & LOCK;
    assign INTFBOUT   = 1'b0;
    assign SDO        = 1'b0;

endmodule
