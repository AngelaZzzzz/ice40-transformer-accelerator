"""Instruction encoding and constants mirroring fpga/rtl/gpt_pkg.sv."""

OPS = {"HALT": 0x0, "EMBED": 0x1, "MATVEC": 0x2, "KVSTORE": 0x3,
       "VADD": 0x4, "VMUL": 0x5, "VRELU": 0x6, "RMSNORM": 0x7,
       "SOFTMAX": 0x8}
OP_NAMES = {code: name for name, code in OPS.items()}

FIELDS = (("op", 47, 44), ("src", 43, 37), ("dst", 36, 30),
          ("base", 29, 16), ("rows_m1", 15, 11), ("cols_m1", 10, 6),
          ("shift", 5, 2), ("flags", 1, 0))

F_SAT8 = 0
F_ALT = 1

A_TOK = 0x0000
A_POS = 0x0100
A_L0 = 0x0180
A_L1 = 0x1980
A_OUT = 0x3180
A_K0 = 0x3280
A_V0 = 0x3300
A_K1 = 0x3380
A_V1 = 0x3400

O_WQ = 0x0000
O_WK = 0x0200
O_WV = 0x0400
O_WO = 0x0600
O_W1 = 0x0800
O_W2 = 0x1000

VR_X = 0
VR_XN = 8
VR_Q = 16
VR_K = 24
VR_V = 32
VR_A = 40
VR_S = 48
VR_T = 56
VR_H = 64


def encode(op: str, src: int = 0, dst: int = 0, base: int = 0,
           rows: int = 8, cols: int = 8, shift: int = 0,
           flags: int = 0) -> int:
    """Pack one 48-bit instruction (interface spec section 3).

    Args:
        op: Opcode name.
        src: Source vector-register address / 8.
        dst: Destination vector-register address / 8.
        base: SPRAM word address.
        rows: Row count R, a multiple of 8.
        cols: Column count C, a multiple of 8.
        shift: Shift field.
        flags: Flags field.

    Returns:
        Instruction word.
    """
    values = {"op": OPS[op], "src": src, "dst": dst, "base": base,
              "rows_m1": rows // 8 - 1, "cols_m1": cols // 8 - 1,
              "shift": shift, "flags": flags}
    assert rows % 8 == 0 and cols % 8 == 0
    word = 0
    for name, hi, lo in FIELDS:
        assert 0 <= values[name] < 1 << (hi - lo + 1), (name, values[name])
        word |= values[name] << lo
    return word


def decode(word: int) -> dict[str, int | str]:
    """Unpack a 48-bit instruction.

    Args:
        word: Instruction word.

    Returns:
        Fields with the opcode name and R, C in elements.
    """
    fields: dict[str, int | str] = {
        name: (word >> lo) & ((1 << (hi - lo + 1)) - 1)
        for name, hi, lo in FIELDS}
    fields["op"] = OP_NAMES[fields["op"]]
    fields["rows"] = 8 * (fields.pop("rows_m1") + 1)
    fields["cols"] = 8 * (fields.pop("cols_m1") + 1)
    return fields
