"""Tests for the exp, reciprocal and rsqrt lookup tables."""

import math
from collections.abc import Iterator

import luts


def raw_values() -> Iterator[list[float]]:
    """Unrounded values of each table.

    Returns:
        One list of 256 floats per table.
    """
    yield [32767 * math.exp(-j / 16) for j in range(256)]
    yield [32768 / (1 + (j + 0.5) / 256) for j in range(256)]
    yield [32768 / math.sqrt((1 + (t + 0.5) / 128) * 2 ** p)
           for p in range(2) for t in range(128)]


def test_no_rounding_ties() -> None:
    """No entry is within 1e-6 of a .5 tie, so rounding mode is moot."""
    for values in raw_values():
        assert all(abs(v - math.floor(v) - 0.5) > 1e-6 for v in values)


def test_tables_fit_16_bits_and_endpoints() -> None:
    """Every table has 256 unsigned 16-bit entries; E[0] = 32767."""
    for table in luts.TABLES.values():
        values = table()
        assert len(values) == 256
        assert all(0 <= v < 1 << 16 for v in values)
    assert luts.exp_table()[0] == 32767


def test_tables_monotonic() -> None:
    """Each table, and each rsqrt half, is non-increasing."""
    assert luts.exp_table() == sorted(luts.exp_table(), reverse=True)
    assert luts.recip_table() == sorted(luts.recip_table(), reverse=True)
    rs = luts.rsqrt_table()
    assert rs[:128] == sorted(rs[:128], reverse=True)
    assert rs[128:] == sorted(rs[128:], reverse=True)
