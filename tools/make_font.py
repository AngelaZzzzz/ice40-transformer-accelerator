"""Writes fpga/mem/font.mem, the VGA font ROM image, from an 8 x 16 font
in GNU Unifont .hex format.

The font is unscii-16 by viznut, which is in the public domain:
    http://viznut.fi/unscii/unscii-16.hex

Usage (from the repository root):
    python tools/make_font.py unscii-16.hex

Output (docs/interface_spec.md section 8): 128 glyphs x 16 rows = 2,048
lines of 2 hex digits, address {char[6:0], row[3:0]}, bit 7 = leftmost
pixel. Codes 0x20 to 0x7E come from the font; the control codes 0x00 to
0x1F and 0x7F are left blank.
"""

import sys
from pathlib import Path

N_GLYPHS = 128
ROWS = 16
FIRST, LAST = 0x20, 0x7E
OUT = Path(__file__).resolve().parent.parent / "fpga" / "mem" / "font.mem"


def read_hex(path: Path) -> dict[int, list[int]]:
    """Read the 8-pixel-wide glyphs of a Unifont .hex file.

    Args:
        path: The .hex file, one "codepoint:bitmap" entry per line.

    Returns:
        Map from codepoint to 16 row bytes. Double-width glyphs are skipped.
    """
    glyphs = {}
    for line in path.read_text().splitlines():
        if ":" not in line:
            continue
        code, bits = line.strip().split(":")
        if len(bits) != 2 * ROWS:
            continue
        glyphs[int(code, 16)] = [int(bits[2 * r:2 * r + 2], 16)
                                 for r in range(ROWS)]
    return glyphs


def main() -> None:
    """Convert the font given on the command line and write font.mem."""
    if len(sys.argv) != 2:
        sys.exit("usage: python tools/make_font.py <font.hex>")
    glyphs = read_hex(Path(sys.argv[1]))
    lines = []
    for c in range(N_GLYPHS):
        if FIRST <= c <= LAST:
            if c not in glyphs:
                sys.exit(f"font has no 8 x 16 glyph for 0x{c:02x}")
            rows = glyphs[c]
        else:
            rows = [0] * ROWS
        lines += [f"{b:02x}" for b in rows]
    OUT.write_text("\n".join(lines) + "\n")
    print(f"wrote {OUT} ({len(lines)} lines)")


if __name__ == "__main__":
    main()
