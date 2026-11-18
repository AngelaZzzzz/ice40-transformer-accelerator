"""Writes fpga/mem/demo_text.mem, the power-up contents of the text buffer
for the standalone VGA demo (fpga/syn/vga_demo).

Usage (from the repository root):
    python tools/make_demo_text.py

Format (docs/interface_spec.md section 8): 1,024 lines of 2 hex digits,
cell = row x 40 + col, byte = {color, char[6:0]}, color 0 = white (typed),
1 = green (generated). Edit SCREEN to change the message; each row is a
list of (text, color) segments, at most 40 characters in all.
"""

from pathlib import Path

COLS, ROWS, CELLS = 40, 15, 1024
W, G = 0, 1
OUT = (Path(__file__).resolve().parent.parent / "fpga" / "mem" /
       "demo_text.mem")

SCREEN: list[list[tuple[str, int]]] = [
    [("  iCE40 Transformer Accelerator", W)],
    [("  E155 Final Project", W)],
    [],
    [("  Type a prefix, the FPGA finishes", W)],
    [("  the name:", W)],
    [],
    [("  > ", W), ("em", W), ("ily", G)],
    [("  > ", W), ("ja", W), ("xon", G)],
    [("  > ", W), ("kri", W), ("sten", G)],
    [("  > ", W), ("zoe", W), ("y", G)],
    [],
    [("  white = typed    ", W), ("green = generated", G)],
    [],
    [("  VGA test screen: sample layout,", W)],
    [("  model not yet connected", W)],
]


def main() -> None:
    """Build the 1,024 cell bytes from SCREEN and write them."""
    assert len(SCREEN) <= ROWS
    cells = [0] * CELLS
    for r, segments in enumerate(SCREEN):
        col = 0
        for text, color in segments:
            for ch in text:
                assert col < COLS, f"row {r} is longer than {COLS}"
                cells[r * COLS + col] = (color << 7) | (ord(ch) & 0x7F)
                col += 1
    OUT.write_text("".join(f"{b:02x}\n" for b in cells))
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()
