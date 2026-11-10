////////////////////////////////////////////////////////////////////////////////
// cmd_decoder
//   SPI command decoder (docs/interface_spec.md section 7). spi_slave sends
//   tx_byte during the byte after the one being received, so tx_byte always
//   holds the next byte to send. SPRAM and score reads have 1-cycle latency
//   and are captured into registers. CS rising aborts any command.
////////////////////////////////////////////////////////////////////////////////

module cmd_decoder(input  logic        clk,
                   input  logic        rst,
                   input  logic        cs_active,
                   input  logic        cs_start,
                   input  logic [7:0]  rx_byte,
                   input  logic        rx_valid,
                   input  logic        busy,
                   input  logic [63:0] spi_rdata,
                   input  logic [15:0] sb_rdata,
                   output logic [7:0]  tx_byte,
                   output logic        spi_we,
                   output logic        spi_re,
                   output logic [13:0] spi_addr,
                   output logic [63:0] spi_wdata,
                   output logic        pm_we,
                   output logic [7:0]  pm_waddr,
                   output logic [47:0] pm_wdata,
                   output logic        run,
                   output logic [4:0]  run_letter,
                   output logic [3:0]  run_pos,
                   output logic [4:0]  sb_raddr,
                   output logic        tb_we,
                   output logic [9:0]  tb_addr,
                   output logic [7:0]  tb_data,
                   output logic        scroll_we,
                   output logic [3:0]  scroll_data);

    localparam logic [7:0] WRITE_SPRAM = 8'h01;
    localparam logic [7:0] READ_SPRAM = 8'h02;
    localparam logic [7:0] WRITE_PROG = 8'h03;
    localparam logic [7:0] RUN = 8'h04;
    localparam logic [7:0] READ_SCORES = 8'h05;
    localparam logic [7:0] WRITE_CHAR = 8'h06;
    localparam logic [7:0] SCROLL = 8'h07;

    typedef enum logic [2:0] {OPCODE, ADDR_HI, ADDR_LO, ARG, DATA,
                              IGNORE} statetype;
    statetype state;

    logic [7:0]  opcode;
    logic [13:0] addr;
    logic [2:0]  byte_count, next_lane;
    logic [55:0] write_word;
    logic [39:0] prog_word;
    logic [63:0] read_word;
    logic [15:0] score_word;
    logic        read_pending, score_req, score_pending, first_read;

    assign next_lane = byte_count + 3'd1;

    always_ff @(posedge clk) begin
        spi_we <= 1'b0;
        spi_re <= 1'b0;
        pm_we <= 1'b0;
        run <= 1'b0;
        tb_we <= 1'b0;
        scroll_we <= 1'b0;
        score_req <= 1'b0;
        read_pending <= spi_re;
        score_pending <= score_req;

        if (rst || !cs_active || cs_start) begin
            state <= OPCODE;
            tx_byte <= 8'h00;
            byte_count <= 3'd0;
            first_read <= 1'b0;
        end else begin
            if (read_pending) begin
                read_word <= spi_rdata;
                if (first_read) begin
                    tx_byte <= spi_rdata[7:0];
                    first_read <= 1'b0;
                end
            end

            if (score_pending) begin
                score_word <= sb_rdata;
                if (first_read) begin
                    tx_byte <= sb_rdata[15:8];
                    first_read <= 1'b0;
                end
            end

            if (rx_valid) begin
                case (state)
                    OPCODE: begin
                        opcode <= rx_byte;
                        byte_count <= 3'd0;
                        case (rx_byte)
                            WRITE_SPRAM, READ_SPRAM, WRITE_CHAR: begin
                                state <= ADDR_HI;
                            end
                            WRITE_PROG: state <= ADDR_LO;
                            RUN, SCROLL: state <= ARG;
                            READ_SCORES: begin
                                sb_raddr <= 5'd0;
                                score_req <= 1'b1;
                                first_read <= 1'b1;
                                state <= DATA;
                            end
                            default: state <= IGNORE;
                        endcase
                    end

                    ADDR_HI: begin
                        addr[13:8] <= rx_byte[5:0];
                        state <= ADDR_LO;
                    end

                    ADDR_LO: begin
                        state <= DATA;
                        if (opcode == READ_SPRAM) begin
                            spi_addr <= {addr[13:8], rx_byte};
                            spi_re <= 1'b1;
                            addr <= {addr[13:8], rx_byte} + 14'd1;
                            first_read <= 1'b1;
                        end else begin
                            addr[7:0] <= rx_byte;
                        end
                    end

                    ARG: begin
                        if (opcode == SCROLL) begin
                            scroll_data <= rx_byte[3:0];
                            scroll_we <= 1'b1;
                            state <= IGNORE;
                        end else if (byte_count == 3'd0) begin
                            run_letter <= rx_byte[4:0];
                            byte_count <= 3'd1;
                        end else begin
                            run_pos <= rx_byte[3:0];
                            run <= 1'b1;
                            state <= IGNORE;
                        end
                    end

                    DATA: begin
                        case (opcode)
                            WRITE_SPRAM: begin
                                if (byte_count == 3'd7) begin
                                    spi_wdata <= {rx_byte, write_word};
                                    spi_addr <= addr;
                                    spi_we <= ~busy;
                                    addr <= addr + 14'd1;
                                end else begin
                                    write_word[8 * byte_count +: 8] <= rx_byte;
                                end
                                byte_count <= next_lane;
                            end
                            READ_SPRAM: begin
                                tx_byte <= read_word[8 * next_lane +: 8];
                                byte_count <= next_lane;
                                if (next_lane == 3'd7) begin
                                    spi_addr <= addr;
                                    spi_re <= 1'b1;
                                    addr <= addr + 14'd1;
                                end
                            end
                            WRITE_PROG: begin
                                if (byte_count == 3'd5) begin
                                    pm_wdata <= {prog_word, rx_byte};
                                    pm_waddr <= addr[7:0];
                                    pm_we <= 1'b1;
                                    addr <= addr + 14'd1;
                                    byte_count <= 3'd0;
                                end else begin
                                    prog_word <= {prog_word[31:0], rx_byte};
                                    byte_count <= byte_count + 3'd1;
                                end
                            end
                            READ_SCORES: begin
                                if (byte_count[0] == 1'b0) begin
                                    tx_byte <= score_word[7:0];
                                    sb_raddr <= sb_raddr + 5'd1;
                                    score_req <= 1'b1;
                                end else begin
                                    tx_byte <= score_word[15:8];
                                end
                                byte_count[0] <= ~byte_count[0];
                            end
                            WRITE_CHAR: begin
                                tb_we <= 1'b1;
                                tb_addr <= addr[9:0];
                                tb_data <= rx_byte;
                                addr <= addr + 14'd1;
                            end
                            default: state <= IGNORE;
                        endcase
                    end

                    default: state <= IGNORE;
                endcase
            end
        end
    end

endmodule
