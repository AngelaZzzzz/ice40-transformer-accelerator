////////////////////////////////////////////////////////////////////////////////
// gpt_top
//   Accelerator top level: clocks, resets, SPI control, sequencer, execution
//   units with OR-bus shared ports, memories and VGA text output
////////////////////////////////////////////////////////////////////////////////

module gpt_top
    import gpt_pkg::*;
    (input  logic rst_n,
     input  logic sck,
     input  logic mosi,
     input  logic cs_n,
     output logic miso,
     output logic done,
     output logic vga_hs,
     output logic vga_vs,
     output logic vga_r,
     output logic vga_g,
     output logic vga_b);

    localparam int V_ACTIVE = 480;

    logic        clk, rst;
    logic        pix_clk, pix_rst, pll_lock, pix_run;

    logic        cs_active, cs_start, rx_valid;
    logic [7:0]  rx_byte, tx_byte;
    logic        spi_we, spi_re;
    logic [13:0] spi_addr;
    logic [63:0] spi_wdata;
    logic        pm_we;
    logic [7:0]  pm_waddr;
    logic [47:0] pm_wdata;
    logic        run;
    logic [4:0]  run_letter;
    logic [3:0]  run_pos;
    logic [4:0]  sb_raddr;
    logic [15:0] sb_rdata;
    logic        tb_we;
    logic [9:0]  tb_addr;
    logic [7:0]  tb_data;
    logic        scroll_we;
    logic [3:0]  scroll_data;

    logic [7:0]  pm_raddr;
    logic [47:0] pm_rdata;
    instr_t      instr;
    logic [4:0]  letter;
    logic [3:0]  pos;
    logic        start, busy, unit_done;

    logic [63:0] sp_rdata;
    logic [15:0] ra_data, rb_data;
    logic [31:0] l0_acc;
    logic        l0_req, l0_clr, l0_en;
    logic [15:0] l0_a, l0_b;

    logic        mv_done, mv_sp_re, mv_w_en;
    logic [13:0] mv_sp_addr;
    logic [9:0]  mv_ra_addr, mv_w_addr;
    logic [15:0] mv_w_data;
    logic        sb_we;
    logic [4:0]  sb_waddr;
    logic [15:0] sb_wdata;

    logic        vo_done, vo_sp_re, vo_w_en;
    logic [13:0] vo_sp_addr;
    logic [9:0]  vo_ra_addr, vo_rb_addr, vo_w_addr;
    logic [15:0] vo_w_data;

    logic        kv_done, kv_sp_we;
    logic [9:0]  kv_ra_addr;
    logic [13:0] kv_sp_addr;
    logic [63:0] kv_sp_wdata;
    logic [7:0]  kv_sp_bytemask;

    logic        rn_done, rn_w_en, rn_l0_req, rn_l0_clr, rn_l0_en;
    logic [9:0]  rn_ra_addr, rn_w_addr;
    logic [15:0] rn_w_data, rn_l0_a, rn_l0_b;
    logic [7:0]  rsqrt_addr;
    logic [15:0] rsqrt_data;

    logic        sm_done, sm_w_en, sm_l0_req, sm_l0_clr, sm_l0_en;
    logic [9:0]  sm_ra_addr, sm_w_addr;
    logic [15:0] sm_w_data, sm_l0_a, sm_l0_b;
    logic [7:0]  exp_addr, rcp_addr;
    logic [15:0] exp_data, rcp_data;

    logic        core_re, core_we, w_en;
    logic [13:0] core_addr;
    logic [63:0] core_wdata;
    logic [7:0]  core_bytemask;
    logic [9:0]  ra_addr, rb_addr, w_addr;
    logic [15:0] w_data;

    logic [9:0]  hcount, vcount, tb_raddr;
    logic        hsync, vsync, blank, vblank;
    logic [3:0]  scroll;
    logic [7:0]  tb_rdata, font_data;
    logic [10:0] font_addr;

    // Clocks and resets
    HSOSC #(.CLKHF_DIV("0b00")) hf_osc(
        .CLKHFPU(1'b1),
        .CLKHFEN(1'b1),
        .CLKHF(clk)
    );

    reset_gen reset(
        .clk(clk),
        .rst_n_async(rst_n),
        .rst(rst)
    );

    vga_pll pll(
        .ref_clk(clk),
        .rst_n(~rst),
        .pix_clk(pix_clk),
        .lock(pll_lock)
    );

    synchronizer #(.WIDTH(1)) pix_rst_sync(
        .clk(pix_clk),
        .rst(1'b0),
        .d(pll_lock & ~rst),
        .q(pix_run)
    );

    assign pix_rst = ~pix_run;

    // SPI slave and command decoder
    spi_slave spi(
        .clk(clk),
        .rst(rst),
        .sck(sck),
        .mosi(mosi),
        .cs_n(cs_n),
        .tx_byte(tx_byte),
        .miso(miso),
        .cs_active(cs_active),
        .cs_start(cs_start),
        .rx_byte(rx_byte),
        .rx_valid(rx_valid)
    );

    cmd_decoder decoder(
        .clk(clk),
        .rst(rst),
        .cs_active(cs_active),
        .cs_start(cs_start),
        .rx_byte(rx_byte),
        .rx_valid(rx_valid),
        .busy(busy),
        .spi_rdata(sp_rdata),
        .sb_rdata(sb_rdata),
        .tx_byte(tx_byte),
        .spi_we(spi_we),
        .spi_re(spi_re),
        .spi_addr(spi_addr),
        .spi_wdata(spi_wdata),
        .pm_we(pm_we),
        .pm_waddr(pm_waddr),
        .pm_wdata(pm_wdata),
        .run(run),
        .run_letter(run_letter),
        .run_pos(run_pos),
        .sb_raddr(sb_raddr),
        .tb_we(tb_we),
        .tb_addr(tb_addr),
        .tb_data(tb_data),
        .scroll_we(scroll_we),
        .scroll_data(scroll_data)
    );

    // Sequencer and program memory
    prog_mem pmem(
        .clk(clk),
        .rst(rst),
        .we(pm_we),
        .waddr(pm_waddr),
        .wdata(pm_wdata),
        .raddr(pm_raddr),
        .rdata(pm_rdata)
    );

    sequencer seq(
        .clk(clk),
        .rst(rst),
        .run(run),
        .run_letter(run_letter),
        .run_pos(run_pos),
        .pm_rdata(pm_rdata),
        .unit_done(unit_done),
        .pm_raddr(pm_raddr),
        .instr(instr),
        .letter(letter),
        .pos(pos),
        .start(start),
        .busy(busy),
        .done_flag(done)
    );

    // Execution units
    matvec_engine matvec(
        .clk(clk),
        .rst(rst),
        .instr(instr),
        .letter(letter),
        .pos(pos),
        .start(start),
        .done(mv_done),
        .sp_rdata(sp_rdata),
        .ra_data(ra_data),
        .l0_req(l0_req),
        .l0_a(l0_a),
        .l0_b(l0_b),
        .l0_clr(l0_clr),
        .l0_en(l0_en),
        .sp_re(mv_sp_re),
        .sp_addr(mv_sp_addr),
        .ra_addr(mv_ra_addr),
        .w_en(mv_w_en),
        .w_addr(mv_w_addr),
        .w_data(mv_w_data),
        .sb_we(sb_we),
        .sb_waddr(sb_waddr),
        .sb_wdata(sb_wdata),
        .l0_acc(l0_acc)
    );

    vecop vec(
        .clk(clk),
        .rst(rst),
        .instr(instr),
        .letter(letter),
        .pos(pos),
        .start(start),
        .done(vo_done),
        .sp_rdata(sp_rdata),
        .ra_data(ra_data),
        .rb_data(rb_data),
        .sp_re(vo_sp_re),
        .sp_addr(vo_sp_addr),
        .ra_addr(vo_ra_addr),
        .rb_addr(vo_rb_addr),
        .w_en(vo_w_en),
        .w_addr(vo_w_addr),
        .w_data(vo_w_data)
    );

    kv_store kv(
        .clk(clk),
        .rst(rst),
        .instr(instr),
        .letter(letter),
        .pos(pos),
        .start(start),
        .done(kv_done),
        .ra_data(ra_data),
        .ra_addr(kv_ra_addr),
        .sp_we(kv_sp_we),
        .sp_addr(kv_sp_addr),
        .sp_wdata(kv_sp_wdata),
        .sp_bytemask(kv_sp_bytemask)
    );

    rmsnorm_unit rmsnorm(
        .clk(clk),
        .rst(rst),
        .instr(instr),
        .letter(letter),
        .pos(pos),
        .start(start),
        .done(rn_done),
        .ra_data(ra_data),
        .l0_acc(l0_acc),
        .lut_data(rsqrt_data),
        .ra_addr(rn_ra_addr),
        .w_en(rn_w_en),
        .w_addr(rn_w_addr),
        .w_data(rn_w_data),
        .l0_req(rn_l0_req),
        .l0_a(rn_l0_a),
        .l0_b(rn_l0_b),
        .l0_clr(rn_l0_clr),
        .l0_en(rn_l0_en),
        .lut_addr(rsqrt_addr)
    );

    softmax_unit softmax(
        .clk(clk),
        .rst(rst),
        .instr(instr),
        .letter(letter),
        .pos(pos),
        .start(start),
        .done(sm_done),
        .ra_data(ra_data),
        .l0_acc(l0_acc),
        .exp_data(exp_data),
        .rcp_data(rcp_data),
        .ra_addr(sm_ra_addr),
        .w_en(sm_w_en),
        .w_addr(sm_w_addr),
        .w_data(sm_w_data),
        .l0_req(sm_l0_req),
        .l0_a(sm_l0_a),
        .l0_b(sm_l0_b),
        .l0_clr(sm_l0_clr),
        .l0_en(sm_l0_en),
        .exp_addr(exp_addr),
        .rcp_addr(rcp_addr)
    );

    lut_rom #(.INIT_FILE("../mem/rsqrt_lut.mem")) rsqrt_rom(
        .clk(clk),
        .rst(rst),
        .addr(rsqrt_addr),
        .data(rsqrt_data)
    );

    lut_rom #(.INIT_FILE("../mem/exp_lut.mem")) exp_rom(
        .clk(clk),
        .rst(rst),
        .addr(exp_addr),
        .data(exp_data)
    );

    lut_rom #(.INIT_FILE("../mem/recip_lut.mem")) rcp_rom(
        .clk(clk),
        .rst(rst),
        .addr(rcp_addr),
        .data(rcp_data)
    );

    // Shared-port OR-buses
    assign unit_done = mv_done | vo_done | kv_done | rn_done | sm_done;

    assign core_re = mv_sp_re | vo_sp_re;
    assign core_we = kv_sp_we;
    assign core_addr = mv_sp_addr | vo_sp_addr | kv_sp_addr;
    assign core_wdata = kv_sp_wdata;
    assign core_bytemask = kv_sp_bytemask;

    assign ra_addr = mv_ra_addr | vo_ra_addr | kv_ra_addr | rn_ra_addr |
                     sm_ra_addr;
    assign rb_addr = vo_rb_addr;
    assign w_en = mv_w_en | vo_w_en | rn_w_en | sm_w_en;
    assign w_addr = mv_w_addr | vo_w_addr | rn_w_addr | sm_w_addr;
    assign w_data = mv_w_data | vo_w_data | rn_w_data | sm_w_data;

    assign l0_req = rn_l0_req | sm_l0_req;
    assign l0_a = rn_l0_a | sm_l0_a;
    assign l0_b = rn_l0_b | sm_l0_b;
    assign l0_clr = rn_l0_clr | sm_l0_clr;
    assign l0_en = rn_l0_en | sm_l0_en;

    // Memories
    spram_mem spram(
        .clk(clk),
        .rst(rst),
        .busy(busy),
        .core_re(core_re),
        .core_we(core_we),
        .core_addr(core_addr),
        .core_wdata(core_wdata),
        .core_bytemask(core_bytemask),
        .spi_re(spi_re),
        .spi_we(spi_we),
        .spi_addr(spi_addr),
        .spi_wdata(spi_wdata),
        .rdata(sp_rdata)
    );

    vreg_file vregs(
        .clk(clk),
        .rst(rst),
        .ra_addr(ra_addr),
        .rb_addr(rb_addr),
        .w_en(w_en),
        .w_addr(w_addr),
        .w_data(w_data),
        .ra_data(ra_data),
        .rb_data(rb_data)
    );

    score_buf scores(
        .clk(clk),
        .rst(rst),
        .we(sb_we),
        .waddr(sb_waddr),
        .wdata(sb_wdata),
        .raddr(sb_raddr),
        .rdata(sb_rdata)
    );

    // VGA text output
    assign vblank = (vcount >= 10'(V_ACTIVE));

    vga_timing timing(
        .pix_clk(pix_clk),
        .pix_rst(pix_rst),
        .hcount(hcount),
        .vcount(vcount),
        .hsync(hsync),
        .vsync(vsync),
        .blank(blank)
    );

    text_buffer tbuf(
        .wclk(clk),
        .we(tb_we),
        .waddr(tb_addr),
        .wdata(tb_data),
        .rclk(pix_clk),
        .raddr(tb_raddr),
        .rdata(tb_rdata)
    );

    font_rom font(
        .pix_clk(pix_clk),
        .addr(font_addr),
        .data(font_data)
    );

    scroll_cdc scroll_sync(
        .clk(clk),
        .rst(rst),
        .we(scroll_we),
        .d(scroll_data),
        .pix_clk(pix_clk),
        .pix_rst(pix_rst),
        .vblank(vblank),
        .q(scroll)
    );

    text_renderer renderer(
        .pix_clk(pix_clk),
        .pix_rst(pix_rst),
        .hcount(hcount),
        .vcount(vcount),
        .hsync(hsync),
        .vsync(vsync),
        .blank(blank),
        .scroll(scroll),
        .tb_rdata(tb_rdata),
        .font_data(font_data),
        .tb_raddr(tb_raddr),
        .font_addr(font_addr),
        .vga_hs(vga_hs),
        .vga_vs(vga_vs),
        .vga_r(vga_r),
        .vga_g(vga_g),
        .vga_b(vga_b)
    );

endmodule
