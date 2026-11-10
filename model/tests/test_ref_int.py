"""Tests for the integer arithmetic primitives and units."""

import numpy as np

from ref_int import rmsnorm, rq, softmax


def test_rq_rounding_and_saturation() -> None:
    """rq rounds half up after an arithmetic shift, then saturates."""
    acc = np.array([5, -5, 6, -6, 1 << 30, -(1 << 30)])
    assert rq(acc, 1).tolist() == [3, -2, 3, -3, 32767, -32768]
    assert rq(acc, 0, sat8=True).tolist() == [5, -5, 6, -6, 127, -128]
    assert rq(np.array([255, -257]), 1, sat8=True).tolist() == [127, -128]


def test_rmsnorm_matches_float() -> None:
    """RMSNORM output is x / rms(x) in Q(12 - o) to within 0.5 percent."""
    rng = np.random.default_rng(0)
    for o in range(4):
        x = rng.integers(-20000, 20000, 64)
        y = rmsnorm(x, 3, o) / 2.0 ** (12 - o)
        ideal = x / np.sqrt(np.mean(x.astype(float) ** 2))
        assert np.max(np.abs(y - ideal)) < 0.005 * np.max(np.abs(ideal))


def test_rmsnorm_zero_input() -> None:
    """An all-zero input gives an all-zero output."""
    assert not rmsnorm(np.zeros(64, dtype=np.int64), 3, 0).any()


def test_softmax_masks_and_normalizes() -> None:
    """Positions after pos are 0; valid outputs sum to about 2^15."""
    rng = np.random.default_rng(1)
    for pos in range(16):
        for k in (0, 4, 8):
            s = rng.integers(-4000, 4000, 16)
            p = softmax(s, pos, k)
            assert not p[pos + 1:].any()
            assert abs(int(p.sum()) - 32768) < 32768 * 0.02
            assert p[np.argmax(s[:pos + 1])] == p.max()
