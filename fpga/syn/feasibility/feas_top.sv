////////////////////////////////////////////////////////////////////////////////
// feas_top
//   Feasibility synthesis top for resource and timing estimates
////////////////////////////////////////////////////////////////////////////////

// Synthesis harness only, not part of the design. It builds the MATVEC
// datapath as the real matvec_engine will use it, so place-and-route gives
// representative logic-cell, DSP, SPRAM and clock-frequency numbers:
//   HSOSC 48 MHz -> spram_mem (4 x SP256K, core and SPI ports)
//     -> registered SPRAM word -> 8 x mac_lane (shared activation, one
//        sign-extended weight byte each; lane 0 with the borrow-port mux)
//     -> 8-to-1 writeback mux -> requant -> probe
// A 64-bit LFSR drives every control and data input so synthesis cannot
// constant-fold anything, and every result bit reaches the probe pin
// through an XOR reduction so nothing is removed as unused.
// FFs power up at 0, which holds rst high for 8 cycles while the LFSR is
// loaded with a non-zero seed.

module feas_top(output logic probe);

    logic        clk, rst;
    logic [3:0]  por_cnt;
    logic [63:0] lfsr;
    logic [13:0] cnt;

    logic [63:0] sp_rdata, sp_q;
    logic [15:0] act;

    logic signed [15:0] lane_a [8];
    logic signed [15:0] lane_b [8];
    logic signed [31:0] lane_acc [8];
    logic               lane_en, lane_clr;
    logic               l0_req;

    logic signed [31:0] rq_in;
    logic               rq_valid;
    logic               y_valid;
    logic signed [15:0] y;

    // Clock and power-on reset
    HSOSC #(.CLKHF_DIV("0b00")) hf_osc(
        .CLKHFPU(1'b1),
        .CLKHFEN(1'b1),
        .CLKHF(clk)
    );

    always_ff @(posedge clk)
        if (!por_cnt[3]) por_cnt <= por_cnt + 4'd1;

    assign rst = ~por_cnt[3];

    // Stimulus: Galois LFSR, taps 64, 63, 61, 60, and an address counter
    always_ff @(posedge clk)
        if (rst) begin
            lfsr <= 64'h0123_4567_89AB_CDEF;
            cnt  <= '0;
        end else begin
            lfsr <= {1'b0, lfsr[63:1]} ^
                    (lfsr[0] ? 64'hD800_0000_0000_0000 : 64'h0);
            cnt  <= cnt + 14'd1;
        end

    // SPRAM with both ports driven
    spram_mem spram(
        .clk(clk),
        .rst(rst),
        .busy(lfsr[0]),
        .core_re(lfsr[1]),
        .core_we(lfsr[2] & ~lfsr[1]),
        .core_addr(cnt),
        .core_wdata(lfsr),
        .core_bytemask(lfsr[15:8]),
        .spi_re(lfsr[3]),
        .spi_we(lfsr[4] & ~lfsr[3]),
        .spi_addr(lfsr[30:17]),
        .spi_wdata({lfsr[31:0], lfsr[63:32]}),
        .rdata(sp_rdata)
    );

    // Pipeline registers in front of the lanes, as in matvec_engine
    always_ff @(posedge clk) begin
        sp_q     <= sp_rdata;
        act      <= lfsr[47:32];
        lane_en  <= lfsr[5];
        lane_clr <= lfsr[6];
        l0_req   <= lfsr[7];
    end

    // Eight lanes; lane 0 can be borrowed by RMSNORM and SOFTMAX
    genvar l;
    generate
        for (l = 0; l < 8; l++) begin : g_lane
            if (l == 0) begin : g_l0
                assign lane_a[l] = l0_req ? lfsr[63:48] : act;
                assign lane_b[l] = l0_req ? lfsr[23:8]
                                          : {{8{sp_q[7]}}, sp_q[7:0]};
            end else begin : g_ln
                assign lane_a[l] = act;
                assign lane_b[l] = {{8{sp_q[8*l+7]}}, sp_q[8*l +: 8]};
            end

            mac_lane lane(
                .clk(clk),
                .rst(rst),
                .en(lane_en),
                .clr(lane_clr),
                .a(lane_a[l]),
                .b(lane_b[l]),
                .acc(lane_acc[l])
            );
        end
    endgenerate

    // Writeback: 8-to-1 mux into the shared requantizer
    always_ff @(posedge clk) begin
        rq_in    <= lane_acc[cnt[2:0]];
        rq_valid <= lfsr[9];
    end

    requant rq(
        .clk(clk),
        .rst(rst),
        .in_valid(rq_valid),
        .acc(rq_in),
        .shift(lfsr[13:10]),
        .sat8(lfsr[14]),
        .out_valid(y_valid),
        .y(y)
    );

    // Observe every result bit
    always_ff @(posedge clk)
        probe <= ^{y, y_valid};

endmodule
