"""Int8 weights, activation formats and shift amounts for the integer
model, calibrated on the validation set.
"""

import math
from typing import Any

import numpy as np
import torch

from config import N_LAYER, OUT_DIR
from model import Params, Record, encode, gpt, load_split

QModel = dict[str, Any]

PRE_SHIFT = 3
F_XN = 12
F_P = 15
EMBED_SHIFT = 7


def weight_frac(w: torch.Tensor) -> int:
    """Fractional bits for an int8 weight matrix.

    Args:
        w: Float weights.

    Returns:
        floor(log2(127 / max|w|)).
    """
    return math.floor(math.log2(127 / w.abs().max().item()))


def to_int8(w: torch.Tensor, frac: int) -> np.ndarray:
    """Round and clamp weights to int8 with frac fractional bits.

    Args:
        w: Float weights.
        frac: Fractional bits.

    Returns:
        Integer weights as int64.
    """
    return np.clip(np.rint(w.numpy() * 2.0 ** frac), -128,
                   127).astype(np.int64)


def act_frac(max_abs: float, bits: int = 16) -> int:
    """Fractional bits for an activation with 25 percent headroom.

    Args:
        max_abs: Largest magnitude observed in calibration.
        bits: Storage width.

    Returns:
        bits - 1 - ceil(log2(1.25 max_abs)).
    """
    return bits - 1 - math.ceil(math.log2(1.25 * max_abs))


def load_params() -> Params:
    """Load the trained float model.

    Returns:
        Parameters from model/out/float.pt.
    """
    return torch.load(OUT_DIR / "float.pt")


def calibrate(params: Params) -> Record:
    """Run the float model on the validation set and record maxima.

    Args:
        params: Float parameters.

    Returns:
        Maximum magnitude of each named vector.
    """
    _, val_words = load_split()
    inputs, _ = encode(val_words)
    record: Record = {}
    with torch.no_grad():
        gpt(params, inputs, record)
    return record


def quantize(params: Params) -> QModel:
    """Quantize the model as specified in the handoff, section 4.4.

    Args:
        params: Float parameters.

    Returns:
        Dict with int weights "w", formats "f", shifts "s", "notes" on
        lowered formats, and the calibration "record".
    """
    record = calibrate(params)
    w: dict[str, np.ndarray] = {}
    f: dict[str, int] = {}
    s: dict[str, int] = {}
    notes: list[str] = []

    def out_shift(f_acc: int, name: str) -> int:
        """Shift from an accumulator format to f[name], lowering
        f[name] if the shift would be negative.

        Args:
            f_acc: Fractional bits of the accumulator.
            name: Output format name.

        Returns:
            Shift amount, 0 to 15.
        """
        shift = f_acc - f[name]
        if shift < 0:
            notes.append(f"{name}: lowered f from {f[name]} to {f_acc}")
            f[name], shift = f_acc, 0
        assert shift <= 15, (name, shift)
        return shift

    def fit_weight(f_in: int, wname: str, out: str) -> None:
        """Lower a weight format so that its MATVEC shift is at most 15.

        Args:
            f_in: Fractional bits of the MATVEC input.
            wname: Weight format name in f.
            out: Output format name in f.
        """
        excess = f_in + f[wname] - f[out] - 15
        if excess > 0:
            notes.append(f"{wname}: lowered f from {f[wname]} to "
                         f"{f[wname] - excess} to keep the shift at 15")
            f[wname] -= excess

    f["e"] = min(weight_frac(params["wte"]), weight_frac(params["wpe"]))
    w["wte"] = to_int8(params["wte"], f["e"])
    w["wpe"] = to_int8(params["wpe"], f["e"])
    s["embed"] = EMBED_SHIFT

    f["x"] = act_frac(max(record["x"], record["t"]))
    assert f["x"] >= 9, f["x"]
    f["x"] = min(f["x"], 12)
    s["o_x"] = F_XN - f["x"]

    for li in range(N_LAYER):
        names = (("q", "attn_wq"), ("k", "attn_wk"), ("v", "attn_wv"),
                 ("o", "attn_wo"), ("1", "mlp_fc1"), ("2", "mlp_fc2"))
        for key, pname in names:
            f[f"w{key}{li}"] = weight_frac(params[f"layer{li}.{pname}"])

        f[f"q{li}"] = act_frac(record[f"q{li}"])
        f[f"k{li}"] = act_frac(record[f"k{li}"], 8)
        f[f"v{li}"] = act_frac(record[f"v{li}"], 8)
        f[f"s{li}"] = act_frac(record[f"s{li}"])
        f[f"a{li}"] = act_frac(record[f"a{li}"])
        f[f"h{li}"] = act_frac(record[f"h{li}"])
        for key, f_in, out in (("q", F_XN, f"q{li}"), ("k", F_XN, f"k{li}"),
                               ("v", F_XN, f"v{li}"), ("1", F_XN, f"h{li}"),
                               ("o", f[f"a{li}"], "x"),
                               ("2", f[f"h{li}"], "x")):
            fit_weight(f_in, f"w{key}{li}", out)
        for key, pname in names:
            w[f"{key}{li}"] = to_int8(params[f"layer{li}.{pname}"],
                                      f[f"w{key}{li}"])

        s[f"q{li}"] = out_shift(F_XN + f[f"wq{li}"], f"q{li}")
        s[f"k{li}"] = out_shift(F_XN + f[f"wk{li}"], f"k{li}")
        s[f"v{li}"] = out_shift(F_XN + f[f"wv{li}"], f"v{li}")
        s[f"s{li}"] = out_shift(f[f"q{li}"] + f[f"k{li}"] + 2, f"s{li}")
        assert f[f"s{li}"] >= 4, f[f"s{li}"]
        s[f"sm{li}"] = f[f"s{li}"] - 4
        s[f"a{li}"] = out_shift(F_P + f[f"v{li}"], f"a{li}")
        s[f"o{li}"] = f[f"a{li}"] + f[f"wo{li}"] - f["x"]
        s[f"h{li}"] = out_shift(F_XN + f[f"w1{li}"], f"h{li}")
        s[f"2{li}"] = f[f"h{li}"] + f[f"w2{li}"] - f["x"]
        assert 0 <= s[f"o{li}"] <= 15 and 0 <= s[f"2{li}"] <= 15

    f["wout"] = weight_frac(params["lm_head"])
    f["logit"] = act_frac(record["logits"])
    fit_weight(f["x"], "wout", "logit")
    w["out"] = to_int8(params["lm_head"], f["wout"])
    s["out"] = out_shift(f["x"] + f["wout"], "logit")
    return {"w": w, "f": f, "s": s, "notes": notes, "record": record}


def shift_table(qm: QModel) -> str:
    """Format every fractional-bit count and shift as a table.

    Args:
        qm: Quantized model.

    Returns:
        Table text.
    """
    lines = [f"{'name':<8}{'frac bits':>10}{'shift':>8}"]
    for name in sorted(set(qm["f"]) | set(qm["s"])):
        frac = qm["f"].get(name, "")
        shift = qm["s"].get(name, "")
        lines.append(f"{name:<8}{frac!s:>10}{shift!s:>8}")
    return "\n".join(lines)


if __name__ == "__main__":
    qm = quantize(load_params())
    print(shift_table(qm))
    print("\n".join(qm["notes"]) or "no formats lowered")
