////////////////////////////////////////////////////////////////////////////////
// spram_mem
//   16,384 x 64-bit SPRAM from four SP256K blocks, core and SPI ports
////////////////////////////////////////////////////////////////////////////////

// All four blocks share the 14-bit address; block b holds word bits
// 16b+15:16b, so byte lane l lives in block l/2, in the low byte
// (MASKWE[1:0]) when l is even and the high byte (MASKWE[3:2]) when l is
// odd (interface spec section 4).
//
// busy selects the port: 1 = core port (MATVEC, EMBED, KVSTORE), with a
// per-byte write mask so KVSTORE can write single cache bytes; 0 = SPI
// port, full-word writes only. Read latency is 1 cycle: rdata is valid the
// cycle after re. A block cannot read and write in the same cycle, so we
// takes priority and rdata is undefined after a write. Chip select is
// driven only on accesses, so rdata holds its value between reads.
// rst is unused: the SPRAM has no reset and the port select is
// combinational.

module spram_mem(input  logic        clk,
                 input  logic        rst,
                 input  logic        busy,
                 input  logic        core_re,
                 input  logic        core_we,
                 input  logic [13:0] core_addr,
                 input  logic [63:0] core_wdata,
                 input  logic [7:0]  core_bytemask,
                 input  logic        spi_re,
                 input  logic        spi_we,
                 input  logic [13:0] spi_addr,
                 input  logic [63:0] spi_wdata,
                 output logic [63:0] rdata);

    logic        we, re, cs;
    logic [13:0] addr;
    logic [63:0] wdata;
    logic [7:0]  bytemask;

    // Port select
    always_comb
        if (busy) begin
            we       = core_we;
            re       = core_re;
            addr     = core_addr;
            wdata    = core_wdata;
            bytemask = core_bytemask;
        end else begin
            we       = spi_we;
            re       = spi_re;
            addr     = spi_addr;
            wdata    = spi_wdata;
            bytemask = 8'hFF;
        end

    assign cs = we | re;

    // SPRAM blocks; MASKWE has one enable bit per nibble
    genvar b;
    generate
        for (b = 0; b < 4; b++) begin : g_blk
            SP256K spram(
                .AD(addr),
                .DI(wdata[16*b +: 16]),
                .MASKWE({{2{bytemask[2*b+1]}}, {2{bytemask[2*b]}}}),
                .WE(we),
                .CS(cs),
                .CK(clk),
                .STDBY(1'b0),
                .SLEEP(1'b0),
                .PWROFF_N(1'b1),
                .DO(rdata[16*b +: 16])
            );
        end
    endgenerate

    // Simulation checks: the program guarantees SPI access only while
    // idle, and idle units drive the core port to 0 (OR-bus)
    // synthesis translate_off
    always @(posedge clk) begin
        if (busy && (spi_we || spi_re))
            $error("spram_mem: SPI access while busy (addr %h)", spi_addr);
        if (!busy && (core_we || core_re))
            $error("spram_mem: core access while idle (addr %h)",
                   core_addr);
    end
    // synthesis translate_on

endmodule
