"""Exp, reciprocal and rsqrt lookup tables for the SOFTMAX and RMSNORM
units. No table value falls exactly on a rounding tie, so Python round()
gives the same result as any rounding mode.
"""

import math
from pathlib import Path

from config import MEM_DIR


def exp_table() -> list[int]:
    """E[j] = round(32767 exp(-j / 16)), j = 0..255.

    Returns:
        256 table entries.
    """
    return [round(32767 * math.exp(-j / 16)) for j in range(256)]


def recip_table() -> list[int]:
    """R[j] = round(32768 / (1 + (j + 0.5) / 256)), j = 0..255.

    Returns:
        256 table entries.
    """
    return [round(32768 / (1 + (j + 0.5) / 256)) for j in range(256)]


def rsqrt_table() -> list[int]:
    """RS[128p + t] = round(32768 / sqrt((1 + (t + 0.5) / 128) 2^p)).

    Returns:
        256 table entries.
    """
    return [round(32768 / math.sqrt((1 + (t + 0.5) / 128) * 2 ** p))
            for p in range(2) for t in range(128)]


TABLES = {"exp_lut.mem": exp_table,
          "recip_lut.mem": recip_table,
          "rsqrt_lut.mem": rsqrt_table}


def write_mem(path: Path, values: list[int], digits: int) -> None:
    """Write values as a $readmemh file, one per line.

    Args:
        path: Output file.
        values: Unsigned values.
        digits: Hex digits per line.
    """
    path.write_text("".join(f"{v:0{digits}x}\n" for v in values))


def main() -> None:
    """Write all three tables to fpga/mem."""
    for name, table in TABLES.items():
        write_mem(MEM_DIR / name, table(), 4)


if __name__ == "__main__":
    main()
