"""Per-letter program (docs/interface_spec.md section 3) and listing."""

from config import N_HEAD, N_LAYER, OUT_DIR
from isa import (A_K0, A_K1, A_L0, A_L1, A_OUT, A_TOK, A_V0, A_V1, F_ALT,
                 F_SAT8, O_W1, O_W2, O_WK, O_WO, O_WQ, O_WV, VR_A, VR_H, VR_K,
                 VR_Q, VR_S, VR_T, VR_V, VR_X, VR_XN, decode, encode)
from quantize import PRE_SHIFT, QModel

SAT8 = 1 << F_SAT8
ALT = 1 << F_ALT


def assemble(qm: QModel) -> list[int]:
    """Emit the program run once per letter.

    Args:
        qm: Quantized model supplying the shifts.

    Returns:
        Instruction words, ending with HALT.
    """
    s = qm["s"]
    prog = [encode("EMBED", dst=VR_X, base=A_TOK, cols=64, shift=s["embed"]),
            encode("RMSNORM", src=VR_X, dst=VR_X, cols=64, shift=PRE_SHIFT,
                   flags=s["o_x"])]
    for li, (a_l, a_k, a_v) in enumerate(((A_L0, A_K0, A_V0),
                                          (A_L1, A_K1, A_V1))[:N_LAYER]):
        prog += [
            encode("RMSNORM", src=VR_X, dst=VR_XN, cols=64, shift=PRE_SHIFT),
            encode("MATVEC", src=VR_XN, dst=VR_Q, base=a_l + O_WQ, rows=64,
                   cols=64, shift=s[f"q{li}"]),
            encode("MATVEC", src=VR_XN, dst=VR_K, base=a_l + O_WK, rows=64,
                   cols=64, shift=s[f"k{li}"], flags=SAT8),
            encode("MATVEC", src=VR_XN, dst=VR_V, base=a_l + O_WV, rows=64,
                   cols=64, shift=s[f"v{li}"], flags=SAT8),
            encode("KVSTORE", src=VR_K, base=a_k, cols=64),
            encode("KVSTORE", src=VR_V, base=a_v, cols=64, flags=ALT)]
        for h in range(N_HEAD):
            prog += [
                encode("MATVEC", src=VR_Q + 2 * h, dst=VR_S + 2 * h,
                       base=a_k + 32 * h, rows=16, cols=16,
                       shift=s[f"s{li}"]),
                encode("SOFTMAX", src=VR_S + 2 * h, dst=VR_S + 2 * h,
                       cols=16, shift=s[f"sm{li}"]),
                encode("MATVEC", src=VR_S + 2 * h, dst=VR_A + 2 * h,
                       base=a_v + 32 * h, rows=16, cols=16,
                       shift=s[f"a{li}"])]
        prog += [
            encode("MATVEC", src=VR_A, dst=VR_T, base=a_l + O_WO, rows=64,
                   cols=64, shift=s[f"o{li}"]),
            encode("VADD", src=VR_T, dst=VR_X, cols=64),
            encode("RMSNORM", src=VR_X, dst=VR_XN, cols=64, shift=PRE_SHIFT),
            encode("MATVEC", src=VR_XN, dst=VR_H, base=a_l + O_W1, rows=256,
                   cols=64, shift=s[f"h{li}"]),
            encode("VRELU", src=VR_H, dst=VR_H, cols=256),
            encode("MATVEC", src=VR_H, dst=VR_T, base=a_l + O_W2, rows=64,
                   cols=256, shift=s[f"2{li}"]),
            encode("VADD", src=VR_T, dst=VR_X, cols=64)]
    prog += [encode("MATVEC", src=VR_X, base=A_OUT, rows=32, cols=64,
                    shift=s["out"], flags=ALT),
             encode("HALT")]
    return prog


def listing(prog: list[int]) -> str:
    """Human-readable program listing.

    Args:
        prog: Instruction words.

    Returns:
        One line per instruction: address, hex word, decoded fields.
    """
    lines = []
    for addr, word in enumerate(prog):
        d = decode(word)
        lines.append(f"{addr:3d}  {word:012x}  {d['op']:<8} "
                     f"src {d['src']:3d}  dst {d['dst']:3d}  "
                     f"base {d['base']:04x}  R {d['rows']:3d}  "
                     f"C {d['cols']:3d}  shift {d['shift']:2d}  "
                     f"flags {d['flags']}")
    return "\n".join(lines)


def write_listing(prog: list[int]) -> None:
    """Write the listing to model/out/program.lst.

    Args:
        prog: Instruction words.
    """
    OUT_DIR.mkdir(exist_ok=True)
    (OUT_DIR / "program.lst").write_text(listing(prog) + "\n")
