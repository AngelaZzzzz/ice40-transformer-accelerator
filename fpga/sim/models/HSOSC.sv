`timescale 1ns/1ps

////////////////////////////////////////////////////////////////////////////////
// HSOSC
//   Simulation-only behavioral model of the iCE40UP high-speed oscillator;
//   Radiant supplies the primitive for synthesis
////////////////////////////////////////////////////////////////////////////////

module HSOSC #(
    parameter CLKHF_DIV = "0b00"
) (
    input  logic CLKHFPU,
    input  logic CLKHFEN,

    output logic CLKHF
);

    localparam real HALF_NS = (CLKHF_DIV == "0b00") ? 10.4167 :
                              (CLKHF_DIV == "0b01") ? 20.8333 :
                              (CLKHF_DIV == "0b10") ? 41.6667 :
                                                      83.3333;

    initial begin
        CLKHF = 1'b0;
        forever begin
            #(HALF_NS) CLKHF = (CLKHFPU && CLKHFEN) ? ~CLKHF : 1'b0;
        end
    end

endmodule
