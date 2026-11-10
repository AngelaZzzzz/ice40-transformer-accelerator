"""Checks that isa.py matches fpga/rtl/gpt_pkg.sv exactly."""

import re

import config
import isa

PKG = config.GPT_PKG_PATH.read_text()


def pkg_localparams() -> dict[str, int]:
    """Parse every localparam in gpt_pkg.sv.

    Returns:
        Values keyed by parameter name.
    """
    pattern = r"localparam\s+(?:int|logic\s*\[\d+:\d+\])\s+(\w+)\s*=\s*" \
              r"(?:\d+'([hd]))?([0-9a-fA-F_]+)\s*;"
    params = {}
    for name, base, value in re.findall(pattern, PKG):
        params[name] = int(value.replace("_", ""), 16 if base == "h" else 10)
    return params


def test_opcodes_match_pkg() -> None:
    """Every op_t member has the same code in isa.OPS."""
    pkg_ops = {name: int(code, 16)
               for name, code in re.findall(r"OP_(\w+)\s*=\s*4'h(\w)", PKG)}
    assert pkg_ops == isa.OPS


def test_instruction_fields_match_pkg() -> None:
    """instr_t field order and widths give the bit positions in FIELDS."""
    body = re.search(r"struct packed \{(.*?)\} instr_t;", PKG, re.S).group(1)
    pos = 47
    fields = []
    for decl in body.strip().splitlines():
        m = re.match(r"\s*(op_t|logic\s*\[(\d+):0\])\s+(\w+);", decl)
        width = 4 if m.group(1) == "op_t" else int(m.group(2)) + 1
        fields.append((m.group(3), pos, pos - width + 1))
        pos -= width
    assert pos == -1
    assert tuple(fields) == isa.FIELDS


def test_constants_match_pkg() -> None:
    """All 33 localparams match isa.py or config.py."""
    params = pkg_localparams()
    shape = {"D": config.D_MODEL, "HEADS": config.N_HEAD,
             "HD": config.HEAD_DIM, "T": config.BLOCK_SIZE,
             "V": config.VOCAB_SIZE, "BOS": config.BOS, "LANES": 8}
    for name, value in params.items():
        expected = shape[name] if name in shape else getattr(isa, name)
        assert value == expected, name
    assert len(params) == 33


def test_encode_decode_round_trip() -> None:
    """encode and decode are inverses for a representative instruction."""
    word = isa.encode("MATVEC", src=isa.VR_XN, dst=isa.VR_Q,
                      base=isa.A_L1 + isa.O_WQ, rows=64, cols=64, shift=13,
                      flags=1 << isa.F_SAT8)
    assert word >> 48 == 0
    assert isa.decode(word) == {"op": "MATVEC", "src": 8, "dst": 16,
                                "base": 0x1980, "rows": 64, "cols": 64,
                                "shift": 13, "flags": 1}
