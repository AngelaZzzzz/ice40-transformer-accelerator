# ice40-transformer-accelerator

E155 final project: a 2-layer character-level transformer running on an iCE40UP5K, with an STM32L432KC host, PS/2 keyboard input and VGA text output.

![System block diagram](system_block_diagram.png)

## Layout

| Path | Contents | Owner |
|---|---|---|
| `docs/interface_spec.md` | interface contract between both halves (authoritative) | both |
| `fpga/rtl/gpt_pkg.sv` | shared constants, instruction format | Zach |
| `fpga/rtl/gpt_top.sv` | top-level wiring | shared |
| `fpga/rtl/spi_test_top.sv` | SPI hardware bring-up top | Zach |
| `fpga/rtl/exec/` | MAC lanes, MATVEC, requantize, vecop, KVSTORE | Angela |
| `fpga/rtl/mem/` | SPRAM wrapper, vector registers, score buffer | Angela |
| `fpga/rtl/ctrl/` | SPI slave, command decoder, sequencer, RMSNorm, softmax | Zach |
| `fpga/rtl/vga/` | VGA timing, text buffer, font ROM, renderer | Angela |
| `fpga/ip/` | Radiant IP Catalog output (PLL) | |
| `fpga/mem/` | ROM contents (font, lookup tables) | |
| `fpga/constraints/` | pin constraints (`.pdc`) | |
| `fpga/sim/tb/` | testbenches | |
| `fpga/sim/models/` | simulation-only models of Lattice primitives | |
| `fpga/syn/` | Radiant command-line build scripts | |
| `fpga/syn/feasibility/` | feasibility synthesis top | Angela |
| `model/` | training, bit-exact reference model, assembler | Zach |
| `model/golden/` | small Python models of single instructions | Angela |
| `mcu/` | MCU firmware | both |
| `tools/` | helper scripts | |

Generated files (test vectors, `spram.mem`, `prog.mem`, build output) are not committed; see `.gitignore`.
