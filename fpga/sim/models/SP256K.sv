`timescale 1ns/1ps

////////////////////////////////////////////////////////////////////////////////
// SP256K
//   Simulation-only behavioral model of the iCE40UP 16K x 16 SPRAM;
//   Radiant supplies the primitive for synthesis
////////////////////////////////////////////////////////////////////////////////

// Port names and behavior follow the Radiant primitive:
//   - CS = 1, WE = 1 on a rising CK edge: write DI to AD, one enable bit
//     per nibble (MASKWE[n] = 1 writes DI[4n+3:4n]);
//   - CS = 1, WE = 0: read; DO shows mem[AD] after the edge (1-cycle
//     latency);
//   - CS = 0: no access; DO holds its last value.
// Cross-checked against Radiant's own model in Icarus: reads, nibble masks
// and hold behavior agree.
//
// Pessimistic where the hardware is unspecified, so a design that depends
// on it fails in simulation instead of on the board:
//   - memory contents start as X (SPRAM is not initialized at power-up);
//   - DO becomes X after a write (Radiant's model holds it instead);
//   - X on CS, WE or a written address is reported and corrupts data.
// STDBY, SLEEP and PWROFF_N must stay at 0, 0, 1; the low-power modes are
// not modeled and anything else is reported as an error.

module SP256K(input  logic [13:0] AD,
              input  logic [15:0] DI,
              input  logic [3:0]  MASKWE,
              input  logic        WE,
              input  logic        CS,
              input  logic        CK,
              input  logic        STDBY,
              input  logic        SLEEP,
              input  logic        PWROFF_N,
              output logic [15:0] DO);

    logic [15:0] mem [16384];
    logic [15:0] bitmask;

    initial begin
        for (int i = 0; i < 16384; i++) mem[i] = 'x;
        DO = 'x;
    end

    assign bitmask = {{4{MASKWE[3]}}, {4{MASKWE[2]}},
                      {4{MASKWE[1]}}, {4{MASKWE[0]}}};

    always @(posedge CK) begin
        if (STDBY !== 1'b0 || SLEEP !== 1'b0 || PWROFF_N !== 1'b1)
            $error("SP256K: low-power inputs not at 0/0/1 (not modeled)");

        if (CS === 1'b1 && WE === 1'b1) begin
            if ($isunknown(AD))
                $error("SP256K: write with unknown address");
            else
                mem[AD] <= (mem[AD] & ~bitmask) | (DI & bitmask);
            DO <= 'x;
        end else if (CS === 1'b1 && WE === 1'b0) begin
            DO <= $isunknown(AD) ? 16'hxxxx : mem[AD];
        end else if (CS !== 1'b0) begin
            // CS = 1 with WE unknown, or CS unknown: outcome undefined
            $error("SP256K: unknown CS or WE on a clock edge");
            DO <= 'x;
        end
    end

endmodule
