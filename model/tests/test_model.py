"""Tests for the float model and dataset."""

import torch

import model
from config import BOS, N_PARAMS


def test_parameter_count() -> None:
    """The model has exactly 102,784 parameters."""
    params = model.init_params()
    assert sum(p.numel() for p in params.values()) == N_PARAMS


def test_split_and_encoding() -> None:
    """The split is 90/10 and words encode as BOS + letters + BOS."""
    train, val = model.load_split()
    assert len(train) + len(val) == 32_033 and len(val) == 3203
    inputs, targets = model.encode(["emma"])
    assert inputs[0, :5].tolist() == [BOS, 4, 12, 12, 0]
    assert targets[0, :6].tolist() == [4, 12, 12, 0, BOS, -1]


def test_causal() -> None:
    """Logits at a position do not depend on later tokens."""
    params = model.init_params()
    a = torch.tensor([[BOS, 1, 2, 3, 4]])
    b = torch.tensor([[BOS, 1, 2, 25, 9]])
    with torch.no_grad():
        la, lb = model.gpt(params, a), model.gpt(params, b)
    assert torch.equal(la[:, :3], lb[:, :3])
    assert not torch.equal(la[:, 3:], lb[:, 3:])


def test_record_does_not_change_output() -> None:
    """Calibration recording leaves the logits bit-identical."""
    params = model.init_params()
    inputs, _ = model.encode(["zoe", "kristopher"])
    record: model.Record = {}
    with torch.no_grad():
        assert torch.equal(model.gpt(params, inputs),
                           model.gpt(params, inputs, record))
    assert {"x", "t", "logits", "q0", "s1", "h1"} <= set(record)
