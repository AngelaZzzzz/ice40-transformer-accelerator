"""Tests that need the trained model in model/out/float.pt."""

import numpy as np
import pytest

from assembler import assemble
from config import OUT_DIR
from isa_sim import Machine, run_word
from model import encode, load_split
from quantize import QModel, load_params, quantize
from ref_int import forward

pytestmark = pytest.mark.skipif(not (OUT_DIR / "float.pt").exists(),
                                reason="model/out/float.pt not trained")


@pytest.fixture(scope="module")
def qm() -> QModel:
    """Quantized trained model.

    Returns:
        Quantized model.
    """
    return quantize(load_params())


def test_shifts_in_range(qm: QModel) -> None:
    """Every shift fits the 4-bit field; RMSNORM offset fits 2 bits."""
    for name, shift in qm["s"].items():
        assert 0 <= shift <= (3 if name == "o_x" else 15), name


def test_program_length(qm: QModel) -> None:
    """The program is 54 instructions ending in HALT."""
    prog = assemble(qm)
    assert len(prog) == 54 and prog[-1] == 0


def test_isa_matches_ref_int(qm: QModel) -> None:
    """isa_sim scores equal ref_int logits on 30 validation words."""
    words = load_split()[1][:30]
    inputs, _ = encode(words)
    ref = forward(qm, inputs.numpy())
    machine = Machine(qm, assemble(qm))
    for i, word in enumerate(words):
        n = len(word) + 1
        assert np.array_equal(run_word(machine, inputs[i, :n].tolist()),
                              ref[i, :n]), word
