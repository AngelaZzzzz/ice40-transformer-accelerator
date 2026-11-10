"""Direct bit-exact integer implementation of the network, vectorized
over a batch of words, following docs/interface_spec.md section 2 and the
RMSNORM and SOFTMAX rules below.
"""

import numpy as np

from config import BLOCK_SIZE, HEAD_DIM, N_HEAD, N_LAYER
from luts import exp_table, recip_table, rsqrt_table
from quantize import PRE_SHIFT, QModel

E = np.array(exp_table(), dtype=np.int64)
R = np.array(recip_table(), dtype=np.int64)
RS = np.array(rsqrt_table(), dtype=np.int64)

# ------------------------------------------------------------------------------
# Arithmetic primitives (docs/interface_spec.md section 2)
# ------------------------------------------------------------------------------


def sat16(x: np.ndarray) -> np.ndarray:
    """Clamp to [-32768, 32767].

    Args:
        x: Integer values.

    Returns:
        Saturated values.
    """
    return np.clip(x, -32768, 32767)


def rq(acc: np.ndarray, shift: int, sat8: bool = False) -> np.ndarray:
    """Requantize: rounding arithmetic right shift, then saturate.

    Args:
        acc: Signed 32-bit accumulator values.
        shift: Right shift, 0 to 15.
        sat8: Saturate to int8 instead of int16.

    Returns:
        Requantized values.
    """
    assert np.all(np.abs(acc) < 1 << 31)
    t = acc if shift == 0 else (acc + (1 << (shift - 1))) >> shift
    return np.clip(t, -128, 127) if sat8 else sat16(t)


def matvec(w: np.ndarray, x: np.ndarray, shift: int,
           sat8: bool = False) -> np.ndarray:
    """Integer matrix-vector product followed by rq.

    Args:
        w: Int8 weights (rows, cols).
        x: Int16 activations (..., cols).
        shift: Requantize shift.
        sat8: Saturate to int8.

    Returns:
        Outputs (..., rows).
    """
    return rq(x @ w.T, shift, sat8)


def floor_log2(v: np.ndarray) -> np.ndarray:
    """floor(log2(v)) for positive integers below 2^53.

    Args:
        v: Positive integers.

    Returns:
        Exponents.
    """
    return np.frexp(v.astype(np.float64))[1] - 1


# ------------------------------------------------------------------------------
# RMSNORM and SOFTMAX units
# ------------------------------------------------------------------------------


def rmsnorm(x: np.ndarray, a: int, o: int) -> np.ndarray:
    """RMSNORM unit over 64 elements; output format Q(12 - o).

    Args:
        x: Int16 inputs (..., 64).
        a: Pre-shift applied before squaring.
        o: Output offset, 0 to 3.

    Returns:
        Normalized int16 outputs.
    """
    ms = np.maximum(((x >> a) ** 2).sum(-1, keepdims=True) >> 6, 1)
    b = floor_log2(ms)
    p = b & 1
    e = (b - p) // 2
    t = np.where(b >= 7, ms >> np.maximum(b - 7, 0),
                 ms << np.maximum(7 - b, 0)) & 127
    r = RS[128 * p + t]
    sh = 3 + e + a + o
    return sat16((x * r + (1 << (sh - 1))) >> sh)


def softmax(s: np.ndarray, pos: int, k: int) -> np.ndarray:
    """SOFTMAX unit over 16 scores; positions after pos become 0.

    Args:
        s: Int16 scores (..., 16).
        pos: Current position; positions 0..pos are valid.
        k: Table index shift.

    Returns:
        Probabilities in Q0.15.
    """
    valid = np.arange(s.shape[-1]) <= pos
    m = np.where(valid, s, -(1 << 20)).max(-1, keepdims=True)
    d = m - s
    idx = d if k == 0 else (d + (1 << (k - 1))) >> k
    e = np.where(valid, E[np.clip(idx, 0, 255)], 0)
    total = e.sum(-1, keepdims=True)
    b = floor_log2(total)
    r = R[(total >> (b - 8)) & 255]
    p = np.minimum((e * r + (1 << (b - 1))) >> b, 32767)
    return np.where(valid, p, 0)


# ------------------------------------------------------------------------------
# Network
# ------------------------------------------------------------------------------


def forward(qm: QModel, inputs: np.ndarray | list[list[int]]) -> np.ndarray:
    """Integer forward pass, one position at a time with a KV cache.

    Args:
        qm: Quantized model.
        inputs: Token ids (batch, steps).

    Returns:
        Integer logits (batch, steps, 27) with f["logit"] fractional
        bits.
    """
    w, s = qm["w"], qm["s"]
    inputs = np.asarray(inputs, dtype=np.int64)
    batch, steps = inputs.shape
    k_cache = np.zeros((N_LAYER, batch, BLOCK_SIZE, N_HEAD, HEAD_DIM),
                       dtype=np.int64)
    v_cache = np.zeros_like(k_cache)
    logits = np.zeros((batch, steps, w["out"].shape[0]), dtype=np.int64)

    for pos in range(steps):
        x = sat16((w["wte"][inputs[:, pos]] + w["wpe"][pos]) << s["embed"])
        x = rmsnorm(x, PRE_SHIFT, s["o_x"])
        for li in range(N_LAYER):
            xn = rmsnorm(x, PRE_SHIFT, 0)
            q = matvec(w[f"q{li}"], xn, s[f"q{li}"])
            k_cache[li, :, pos] = matvec(w[f"k{li}"], xn, s[f"k{li}"],
                                         True).reshape(batch, N_HEAD, -1)
            v_cache[li, :, pos] = matvec(w[f"v{li}"], xn, s[f"v{li}"],
                                         True).reshape(batch, N_HEAD, -1)
            q = q.reshape(batch, N_HEAD, 1, HEAD_DIM)
            keys = k_cache[li].transpose(0, 2, 3, 1)
            scores = rq((q @ keys)[:, :, 0], s[f"s{li}"])
            probs = softmax(scores, pos, s[f"sm{li}"])
            values = v_cache[li].transpose(0, 2, 1, 3)
            a = rq(probs[:, :, None] @ values, s[f"a{li}"])
            a = a.reshape(batch, -1)
            x = sat16(x + matvec(w[f"o{li}"], a, s[f"o{li}"]))
            xn = rmsnorm(x, PRE_SHIFT, 0)
            h = np.maximum(matvec(w[f"1{li}"], xn, s[f"h{li}"]), 0)
            x = sat16(x + matvec(w[f"2{li}"], h, s[f"2{li}"]))
        logits[:, pos] = matvec(w["out"], x, s["out"])
    return logits
