# Interface specification (authoritative)

## 1. Conventions

- Core clock `clk`: HSOSC at 48 MHz (CLKHF_DIV "0b00"). Nothing may depend on the exact frequency; the fallback is 24 MHz.
- Pixel clock `pix_clk`: PLL from `clk` (section 8). Only VGA logic and the text buffer read port use it.
- Reset `rst`: active high, synchronous, from `reset_gen` (power-on hold plus the P43 button); `pix_rst` is `rst` synchronized into `pix_clk` and held until PLL lock.
- Radiant primitives: SP256K (SPRAM), MAC16 via `pmi_dsp` or the IP Catalog, PLL from the IP Catalog, HSOSC.
- Shared ports use an OR-bus: every unit drives all of its shared-port outputs (SPRAM core port, vector-register ports, score-buffer write, lane-0 borrow) to 0 whenever it is not executing, and `gpt_top` ORs them together. `done` outputs are ORed into `unit_done`.
- Shared definitions live in `gpt_pkg.sv`; import it, never duplicate constants.

## 2. Arithmetic (bit-exact)

- Weights: signed int8. Activations: signed int16. Accumulators: signed int32.
- MAC: acc = sum over c of int16 activation x int8 weight (weight sign-extended to 16 bits). Bound: 2^15 x 2^7 x 256 = 2^30 < 2^31.
- Requantize rq(acc, s, sat8): t = acc if s = 0, otherwise (acc + 2^(s-1)) >>> s; saturate to [-32768, 32767], or [-128, 127] when sat8 = 1; store as int16.
- sat16(x): clamp to [-32768, 32767].
- Scales are powers of two chosen offline; hardware sees only shift amounts.

## 3. Instruction set

48-bit instruction, MSB to LSB:

| Bits | Field | Meaning |
|---|---|---|
| 47:44 | op | opcode |
| 43:37 | src | vector-register address / 8 |
| 36:30 | dst | vector-register address / 8 |
| 29:16 | base | SPRAM word address |
| 15:11 | rows_m1 | R = 8 x (rows_m1 + 1) |
| 10:6 | cols_m1 | C = 8 x (cols_m1 + 1) |
| 5:2 | shift | shift (meaning per opcode, 0 to 15) |
| 1:0 | flags | bit 0 = SAT8, bit 1 = ALT; RMSNORM: output offset o |

The sequencer also provides `letter[4:0]` (0 to 26) and `pos[3:0]` (0 to 15). vr[i] is vector-register word i; S8(a, l) is byte lane l of SPRAM word a, sign-extended (lane l = bits 8l+7:8l).

| Op | Code | Owner | Semantics |
|---|---|---|---|
| HALT | 0 | Zach | end of program; sets DONE |
| EMBED | 1 | Angela | for i < C, k = i/8, l = i%8: vr[8dst+i] = sat16((S8(base+8letter+k, l) + S8(base+256+8pos+k, l)) <<< shift) |
| MATVEC | 2 | Angela | for g < R/8, l < 8: acc = sum over c < C of vr[8src+c] x S8(base+gC+c, l); y = rq(acc, shift, SAT8); if ALT: score[8g+l] = y, else vr[8dst+8g+l] = y |
| KVSTORE | 3 | Angela | low bytes of vr[8src+c], c < 64, into the cache at base; ALT = 0 K layout, ALT = 1 V layout (section 4) |
| VADD | 4 | Angela | for i < C: vr[8dst+i] = sat16(vr[8dst+i] + vr[8src+i]) |
| VMUL | 5 | Angela | for i < C: vr[8dst+i] = rq(vr[8dst+i] x vr[8src+i], shift, 0); unused by the current program |
| VRELU | 6 | Angela | for i < C: vr[8dst+i] = max(vr[8src+i], 0); src may equal dst |
| RMSNORM | 7 | Zach | C elements, src may equal dst; shift = pre-shift a, flags = output offset o; borrows lane 0; exact rule in model/ref_int.py |
| SOFTMAX | 8 | Zach | in place on C = 16 scores, shift = table index shift k; positions > pos become 0; borrows lane 0; exact rule in model/ref_int.py |

Program guarantees: MATVEC src and dst regions never overlap; the two operands of VADD and VMUL are in different vector-register banks.

Attention uses MATVEC. Head h: scores = MATVEC(base = K + 32h, R = 16, C = 16, src = q + 2h, dst = s + 2h); weighted values = MATVEC(base = V + 32h, R = 16, C = 16, src = s + 2h, dst = a + 2h).

Program per letter (about 54 instructions): EMBED x; RMSNORM x -> x; per layer: RMSNORM x -> xn; MATVEC Wq -> q, Wk -> k (SAT8), Wv -> v (SAT8); KVSTORE k (K layout); KVSTORE v (V layout); per head: MATVEC scores, SOFTMAX, MATVEC weighted values; MATVEC Wo a -> t; VADD x += t; RMSNORM x -> xn; MATVEC W1 xn -> h; VRELU h; MATVEC W2 h -> t; VADD x += t. Then MATVEC output layer x -> score buffer (ALT, R = 32); HALT.

`gpt_pkg.sv`:

```systemverilog
package gpt_pkg;

  // ---------------------------------------------------------------------
  // Model shape
  // ---------------------------------------------------------------------
  localparam int D     = 64;
  localparam int HEADS = 4;
  localparam int HD    = 16;
  localparam int T     = 16;
  localparam int V     = 27;
  localparam int BOS   = 26;
  localparam int LANES = 8;

  // ---------------------------------------------------------------------
  // Instructions
  // ---------------------------------------------------------------------
  typedef enum logic [3:0] {
    OP_HALT    = 4'h0,
    OP_EMBED   = 4'h1,
    OP_MATVEC  = 4'h2,
    OP_KVSTORE = 4'h3,
    OP_VADD    = 4'h4,
    OP_VMUL    = 4'h5,
    OP_VRELU   = 4'h6,
    OP_RMSNORM = 4'h7,
    OP_SOFTMAX = 4'h8
  } op_t;

  typedef struct packed {
    op_t         op;
    logic [6:0]  src;
    logic [6:0]  dst;
    logic [13:0] base;
    logic [4:0]  rows_m1;
    logic [4:0]  cols_m1;
    logic [3:0]  shift;
    logic [1:0]  flags;
  } instr_t;

  localparam int F_SAT8 = 0;
  localparam int F_ALT  = 1;

  // ---------------------------------------------------------------------
  // SPRAM map (64-bit word addresses)
  // ---------------------------------------------------------------------
  localparam logic [13:0] A_TOK  = 14'h0000;
  localparam logic [13:0] A_POS  = 14'h0100;
  localparam logic [13:0] A_L0   = 14'h0180;
  localparam logic [13:0] A_L1   = 14'h1980;
  localparam logic [13:0] A_OUT  = 14'h3180;
  localparam logic [13:0] A_K0   = 14'h3280;
  localparam logic [13:0] A_V0   = 14'h3300;
  localparam logic [13:0] A_K1   = 14'h3380;
  localparam logic [13:0] A_V1   = 14'h3400;

  localparam logic [13:0] O_WQ   = 14'h0000;
  localparam logic [13:0] O_WK   = 14'h0200;
  localparam logic [13:0] O_WV   = 14'h0400;
  localparam logic [13:0] O_WO   = 14'h0600;
  localparam logic [13:0] O_W1   = 14'h0800;
  localparam logic [13:0] O_W2   = 14'h1000;

  // ---------------------------------------------------------------------
  // Vector-register map (units of 8 words)
  // ---------------------------------------------------------------------
  localparam logic [6:0] VR_X  = 7'd0;
  localparam logic [6:0] VR_XN = 7'd8;
  localparam logic [6:0] VR_Q  = 7'd16;
  localparam logic [6:0] VR_K  = 7'd24;
  localparam logic [6:0] VR_V  = 7'd32;
  localparam logic [6:0] VR_A  = 7'd40;
  localparam logic [6:0] VR_S  = 7'd48;
  localparam logic [6:0] VR_T  = 7'd56;
  localparam logic [6:0] VR_H  = 7'd64;

endpackage
```

## 4. SPRAM

Four SP256K blocks share a 14-bit address and form one 64-bit word. Block b holds word bits 16b+15:16b, so lane l is in block l/2, low byte (MASKWE[1:0]) when l is even, high byte (MASKWE[3:2]) when l is odd. MASKWE = 1 enables a nibble. Read latency 1 cycle; no read and write in the same cycle.

Matrix layout (weight matrices, K cache, transposed V cache): matrix M (R rows, C columns) at `base` stores row group g, column c at word base + gC + c, lane l = M[8g+l][c]. Rows past the real row count are zero.

Vector layout (embedding tables only): row r at base + 8r + k, lane l = E[r][8k+l]. The letter table is padded to 32 rows (256 words).

| Region | Start | Words | Shape |
|---|---|---|---|
| letter embedding | 0x0000 | 256 | 32 x 64, vector layout |
| position embedding | 0x0100 | 128 | 16 x 64, vector layout |
| layer 0 | 0x0180 | 6,144 | Wq, Wk, Wv, Wo at +0x000, +0x200, +0x400, +0x600 (64 x 64); W1 at +0x800 (256 x 64); W2 at +0x1000 (64 x 256) |
| layer 1 | 0x1980 | 6,144 | same offsets |
| output layer | 0x3180 | 256 | 32 x 64 (27 real rows) |
| K cache L0, L1 | 0x3280, 0x3380 | 128 each | head h at +32h: 16 positions x 16 channels |
| V cache L0, L1 | 0x3300, 0x3400 | 128 each | head h at +32h: 16 channels x 16 positions |
| free | 0x3480 | 2,944 | |

KVSTORE, for c < 64, p = pos, byte = vr[8src+c][7:0]:
- K layout: word base + 32(c >> 4) + 16(p >> 3) + (c & 15), lane p & 7 (64 byte-masked writes).
- V layout: word base + 32(c >> 4) + 16((c >> 3) & 1) + p, lane c & 7 (8 full-word writes).

SPI load and readback happen only while the sequencer is idle; `spram_mem` selects its SPI port when `busy` is 0.

## 5. Vector register file and score buffer

- 1,024 x 16 bits in 4 EBRs; bank = addr[9:8]; each bank 1 read and 1 write port. Two reads in different banks may happen in one cycle; two reads of one bank in one cycle are a program error (assert in simulation).
- Map (words): x 0, xn 64, q 128, k 192 (bank 0); v 256, a 320, s 384, t 448 (bank 1); h 512 to 767 (bank 2); bank 3 free.
- Ports: read A, read B, one write; read latency 1 cycle.
- Score buffer: 32 x 16 bits, 1 EBR; written by MATVEC with ALT at 8g + l; read by the SPI decoder with 1-cycle latency.

## 6. Sequencer handshake and lane-0 sharing

- The sequencer holds `instr`, `letter`, `pos` stable, pulses `start` one cycle, and waits for `unit_done`. A unit acts only on its own opcodes and pulses `done` one cycle after its last write commits.
- MATVEC target: one column per cycle per row group, (R/8) x C cycles plus fill; write back one group's 8 results while the next group accumulates.
- RMSNORM and SOFTMAX borrow lane 0's MAC16 through `l0_req, l0_a, l0_b, l0_clr, l0_en` (inputs to `matvec_engine`) and `l0_acc` (output). With `l0_clr` and `l0_en`: acc = a x b; with `l0_en` only: acc += a x b. The latency from inputs to `l0_acc` is documented in `mac_lane.sv`.

## 7. SPI commands

Mode 0, 5 MHz, MSB first. CS low starts a command, CS high ends it. First byte is the opcode; multi-byte fields are MSB first.

| Command | Opcode | Bytes after the opcode |
|---|---|---|
| WRITE_SPRAM | 0x01 | 2-byte word address, then 8 bytes per word (byte k = lane k), auto-increment |
| READ_SPRAM | 0x02 | 2-byte address, 1 dummy byte, then 8 bytes per word, auto-increment |
| WRITE_PROG | 0x03 | 1-byte address, then 6 bytes per instruction |
| RUN | 0x04 | letter (0 to 26), position (0 to 15) |
| READ_SCORES | 0x05 | 1 dummy byte, then 27 x 2 bytes (int16, score 0 first) |
| WRITE_CHAR | 0x06 | 2-byte cell index, then 1 byte per cell, auto-increment |
| SCROLL | 0x07 | 1 byte, row offset 0 to 14 |

DONE (P27 to PA6) is cleared by the `run` pulse at the end of RUN (while CS is still low) and set by HALT.

## 8. VGA

- `pix_clk`: Radiant IP Catalog PLL from `clk`, 25.000 MHz (expected DIVR = 2, DIVF = 49, DIVQ = 5; phase detector 16 MHz, VCO 800 MHz; DIVF is limited to 0..63).
- Timing: 800 x 525 (H 640 + 16 + 96 + 48; V 480 + 10 + 2 + 33), syncs active low; 31.25 kHz line, 59.5 Hz frame. HSOSC is accurate to +/-10%; if the monitor will not lock, keep sync widths and adjust the horizontal total so that pix_clk / H_total = 31.47 kHz.
- Pins: HS P44, VS P45, R P46, G P47, B P48; R, G, B through 270 ohm.
- Text: 40 x 15 cells, 8 x 16 glyphs at 2x (16 x 32 pixels). Screen row r shows memory row (r + scroll) mod 15; cell index = memrow x 40 + col.
- Text buffer: 1,024 x 8 bits, 2 EBRs, write in `clk`, read in `pix_clk`; byte = {color, char[6:0]}, color 0 = typed (white), 1 = generated (green); 0x00 and 0x20 render blank.
- Font ROM: 128 glyphs x 16 rows x 8 bits, 4 EBRs, address {char, row}, bit 7 = leftmost pixel, from `fpga/mem/font.mem` (public-domain 8 x 16 ASCII font).
- Scroll crosses into `pix_clk` with a 2-flop synchronizer per bit and loads during vertical blanking after two successive samples agree.

## 9. MCU display (Angela)

`display.c` uses `fpga_write_chars` and `fpga_scroll`. Behavior: the user types a prefix in white on the current line; on Enter, the next line shows the prefix in white and the generated letters in green, and a new input line starts with the same prefix. When the cursor passes the last row, clear the next memory row and advance scroll modulo 15.
