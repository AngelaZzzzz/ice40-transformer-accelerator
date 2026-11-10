# Generated memory files and test vectors

Every file below is written by `python model/export.py` (run from `model/`) and must not be edited by hand. All files are `$readmemh` text: one value per line, lowercase hex, two's complement for signed values, no `0x` prefix. Lines of different widths in one file can all be read into a memory at least as wide as the widest line.

Regenerate after retraining with `python train.py` then `python export.py`. `python check.py` prints the losses, the format and shift table, and the ref_int versus isa_sim agreement.

## Memory images (`fpga/mem/`)

| File | Lines | Contents |
|---|---|---|
| `spram.mem` | 13,440 | SPRAM words 0x0000 to 0x347F, 16 hex digits each; lane l (signed byte) at bits 8l+7:8l; the KV region (0x3280 and up) is zero. Gitignored. |
| `prog.mem` | 54 | One 48-bit instruction per line, 12 hex digits, MSB first. Gitignored. |
| `exp_lut.mem`, `recip_lut.mem`, `rsqrt_lut.mem` | 256 each | 16-bit table entries, 4 hex digits. |

`mcu/src/model_weights.h` holds the same data for the MCU: `model_spram[]` is SPRAM words 0 to 12,927 (8 bytes per word, byte k = lane k), `model_prog[]` is 6 bytes per instruction MSB first, plus `MODEL_NWORDS`, `MODEL_NINSTR` and `MODEL_LOGIT_FRAC` (fractional bits of the int16 scores). `model/out/program.lst` is a readable listing of the program.

## Whole-program vectors (`fpga/sim/vectors/prefix_<name>/`)

Prefixes: `empty` (""), `a`, `em`, `ja`, `kri`, `mar`, `zoe`. Each is fed as BOS at position 0, then its letters at positions 1 to n, starting from an all-zero KV cache. For each position p:

| File | Lines | Contents |
|---|---|---|
| `pos<p>_vreg.mem` | 53 x 1,024 | The vector register file (1,024 words, 4 hex digits) after each of the 53 instructions before HALT, in program order, concatenated. 53 x 1,024 = 54,272 lines. |
| `pos<p>_kv.mem` | 512 | SPRAM words 0x3280 to 0x347F (K and V caches of both layers) after the letter, 16 hex digits. |
| `pos<p>_scores.mem` | 27 | Score buffer entries 0 to 26 after HALT, 4 hex digits (int16). |

## Unit vectors (`fpga/sim/vectors/unit/`)

Each file is a sequence of fixed-length cases. Header words pack small fields into 4 hex digits as shown.

| File | Cases | Lines per case |
|---|---|---|
| `requant.mem` | 1,024 | 1 line of 14 hex digits: acc (8), shift (1), sat8 (1), y (4) |
| `rmsnorm.mem` | 64 | header `{a[7:4], o[3:0]}`, 64 inputs, 64 outputs (case 0 is all zero) |
| `softmax.mem` | 64 | header `{pos[11:8], k[3:0]}`, 16 scores, 16 outputs |
| `matvec.mem` | 64 | instruction (12 hex digits, R = C = 16, src 16, dst 48, base 0x0100, random shift and flags), 16 inputs vr[128..143], 32 SPRAM words 0x0100 to 0x011F, 16 outputs (vr[384..399], or score[0..15] when ALT) |
| `embed.mem` | 64 | header `{letter[12:8], pos[7:4], shift[3:0]}` (C = 64, base 0), 8 letter-table words, 8 position-table words, 64 outputs vr[0..63] |
| `kvstore.mem` | 64 | header `{pos[7:4], alt[0]}` (src 24, base 0x3280), 64 inputs vr[192..255], 128 SPRAM words 0x3280 to 0x32FF after the store (those words are all zero before the store) |
| `vadd.mem` | 64 | 64 dst inputs vr[0..63], 64 src inputs vr[448..511], 64 outputs vr[0..63] |
| `vrelu.mem` | 64 | 64 inputs vr[448..511], 64 outputs vr[0..63] |

Unit inputs are random, with the int16 edge values -32768, -32767, -1, 0, 1, 32766 and 32767 at the start of each input vector, scaled by a random right shift so that every magnitude range occurs.

## Running the testbenches

All testbenches use Icarus Verilog and print `PASSED` or `FAILED: n errors` on their last line. Run from `fpga/` (`lut_rom_tb` runs `vvp` from `fpga/mem` so that `exp_lut.mem` is found):

```
iverilog -g2012 -o spi_slave_tb.vvp sim/tb/spi_slave_tb.sv sim/models/spi_master_bfm.sv rtl/ctrl/spi_slave.sv rtl/ctrl/synchronizer.sv
vvp -n spi_slave_tb.vvp

iverilog -g2012 -o cmd_decoder_tb.vvp sim/tb/cmd_decoder_tb.sv sim/models/spi_master_bfm.sv rtl/ctrl/spi_slave.sv rtl/ctrl/cmd_decoder.sv rtl/ctrl/synchronizer.sv
vvp -n cmd_decoder_tb.vvp

iverilog -g2012 -o spi_test_top_tb.vvp sim/tb/spi_test_top_tb.sv sim/models/spi_master_bfm.sv sim/models/HSOSC.sv rtl/spi_test_top.sv rtl/ctrl/reset_gen.sv rtl/ctrl/synchronizer.sv rtl/ctrl/spi_slave.sv rtl/ctrl/cmd_decoder.sv
vvp -n spi_test_top_tb.vvp

iverilog -g2012 -o lut_rom_tb.vvp sim/tb/lut_rom_tb.sv rtl/ctrl/lut_rom.sv
cd mem && vvp -n ../lut_rom_tb.vvp
```

`sim/models/` holds simulation-only models (`HSOSC`, `SP256K`, and the SPI master bus-functional model `spi_master_bfm`); they are never added to a synthesis project.

The PS/2 decoder has a host-side C test, run from the repository root:

```
gcc -std=c99 -Wall -Wextra -I mcu/src mcu/test/ps2_decode_test.c mcu/src/ps2_decode.c -o ps2_decode_test
./ps2_decode_test
```
