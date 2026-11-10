`timescale 1ns/1ps

////////////////////////////////////////////////////////////////////////////////
// pmi_dsp
//   Simulation-only behavioral model of Radiant's pmi_dsp (MAC16) wrapper,
//   multiplier configurations only; Radiant supplies the module for synthesis
////////////////////////////////////////////////////////////////////////////////

// Same parameters and ports as Radiant's ip/pmi/pmi_dsp.v. Models only the
// 16 x 16 multiplier path used by mac_lane:
//   A_REG, B_REG              "0b0" or "0b1": register A, B (CE, AHOLD,
//                             BHOLD honored)
//   PIPELINE_16x16_MULT_REG2  "0b0" or "0b1": register the 32-bit product
//   A_SIGNED, B_SIGNED        "0b0" or "0b1"
//   TOPOUTPUT_SELECT and BOTOUTPUT_SELECT must be "0b11" (O = product).
// Any other configuration, and any use of the reset, load, carry or
// accumulator inputs, is reported as an error.
//
// Cross-checked in Icarus against Radiant's own pmi_dsp/MAC16 model with
// mac_lane's configuration (A_REG, B_REG, REG2, both signed): identical O
// on random and extreme inputs, latency 2.

module pmi_dsp #(
    parameter NEG_TRIGGER              = "0b0",
    parameter A_REG                    = "0b0",
    parameter B_REG                    = "0b0",
    parameter C_REG                    = "0b0",
    parameter D_REG                    = "0b0",
    parameter TOP_8x8_MULT_REG         = "0b0",
    parameter BOT_8x8_MULT_REG         = "0b0",
    parameter PIPELINE_16x16_MULT_REG1 = "0b0",
    parameter PIPELINE_16x16_MULT_REG2 = "0b0",
    parameter TOPOUTPUT_SELECT         = "0b00",
    parameter TOPADDSUB_LOWERINPUT     = "0b00",
    parameter TOPADDSUB_UPPERINPUT     = "0b0",
    parameter TOPADDSUB_CARRYSELECT    = "0b00",
    parameter BOTOUTPUT_SELECT         = "0b00",
    parameter BOTADDSUB_LOWERINPUT     = "0b00",
    parameter BOTADDSUB_UPPERINPUT     = "0b0",
    parameter BOTADDSUB_CARRYSELECT    = "0b00",
    parameter MODE_8x8                 = "0b0",
    parameter A_SIGNED                 = "0b0",
    parameter B_SIGNED                 = "0b0"
) (
    input  logic        CLK,
    input  logic        CE,
    input  logic [15:0] C,
    input  logic [15:0] A,
    input  logic [15:0] B,
    input  logic [15:0] D,
    input  logic        AHOLD,
    input  logic        BHOLD,
    input  logic        CHOLD,
    input  logic        DHOLD,
    input  logic        IRSTTOP,
    input  logic        IRSTBOT,
    input  logic        ORSTTOP,
    input  logic        ORSTBOT,
    input  logic        OLOADTOP,
    input  logic        OLOADBOT,
    input  logic        ADDSUBTOP,
    input  logic        ADDSUBBOT,
    input  logic        OHOLDTOP,
    input  logic        OHOLDBOT,
    input  logic        CI,
    input  logic        ACCUMCI,
    input  logic        SIGNEXTIN,

    output logic [31:0] O,
    output logic        CO,
    output logic        ACCUMCO,
    output logic        SIGNEXTOUT
);

    localparam bit AREG = (A_REG == "0b1");
    localparam bit BREG = (B_REG == "0b1");
    localparam bit PREG = (PIPELINE_16x16_MULT_REG2 == "0b1");
    localparam bit ASGN = (A_SIGNED == "0b1");
    localparam bit BSGN = (B_SIGNED == "0b1");

    logic [15:0] a_r, b_r, a_m, b_m;
    logic [31:0] p, p_r;

    initial
        if (TOPOUTPUT_SELECT != "0b11" || BOTOUTPUT_SELECT != "0b11" ||
            PIPELINE_16x16_MULT_REG1 != "0b0" || MODE_8x8 != "0b0" ||
            NEG_TRIGGER != "0b0")
            $error("pmi_dsp model: only the 16 x 16 multiplier is modeled");

    always_ff @(posedge CLK)
        if (CE) begin
            if (!AHOLD) a_r <= A;
            if (!BHOLD) b_r <= B;
            p_r <= p;
        end

    assign a_m = AREG ? a_r : A;
    assign b_m = BREG ? b_r : B;

    // Sign- or zero-extend each operand to 32 bits, then multiply
    assign p = {{16{ASGN & a_m[15]}}, a_m} * {{16{BSGN & b_m[15]}}, b_m};

    assign O          = PREG ? p_r : p;
    assign CO         = 1'b0;
    assign ACCUMCO    = 1'b0;
    assign SIGNEXTOUT = 1'b0;

    always @(posedge CLK)
        if (IRSTTOP || IRSTBOT || ORSTTOP || ORSTBOT || OLOADTOP ||
            OLOADBOT || OHOLDTOP || OHOLDBOT || CI || ACCUMCI)
            $error("pmi_dsp model: reset/load/hold/carry inputs not modeled");

endmodule
