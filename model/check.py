"""Report: float and integer validation loss, ref_int versus isa_sim
agreement, the format and shift table, and samples from both models.
"""

import sys
import time

import numpy as np
import torch
import torch.nn.functional as F

from assembler import assemble
from config import BLOCK_SIZE, BOS, VOCAB_SIZE
from isa_sim import Machine, run_word
from model import decode, encode, load_split, loss_fn, sample
from quantize import QModel, load_params, quantize, shift_table
from ref_int import forward

N_ISA_WORDS = 200
TARGET_GAP = 0.05


def int_loss(qm: QModel, inputs: torch.Tensor,
             targets: torch.Tensor) -> float:
    """Validation loss of the integer model, with integer logits
    converted to float and a float log-softmax.

    Args:
        qm: Quantized model.
        inputs: Input token ids.
        targets: Target token ids, -1 for padding.

    Returns:
        Loss in nats per predicted token.
    """
    logits = forward(qm, inputs.numpy()) / 2.0 ** qm["f"]["logit"]
    return F.cross_entropy(torch.tensor(logits).reshape(-1, VOCAB_SIZE),
                           targets.reshape(-1), ignore_index=-1).item()


def int_sample(qm: QModel, n: int = 20, temperature: float = 0.5,
               seed: int = 42) -> list[str]:
    """Sample words from the integer model as the MCU will.

    Args:
        qm: Quantized model.
        n: Number of words.
        temperature: Softmax temperature.
        seed: Sampling seed.

    Returns:
        Generated words.
    """
    gen = torch.Generator().manual_seed(seed)
    words = []
    for _ in range(n):
        tokens = [BOS]
        for _ in range(BLOCK_SIZE):
            logits = forward(qm, [tokens])[0, -1] / 2.0 ** qm["f"]["logit"]
            probs = torch.tensor(logits / temperature).softmax(-1)
            token = torch.multinomial(probs, 1, generator=gen).item()
            if token == BOS:
                break
            tokens.append(token)
        words.append(decode(tokens))
    return words


def isa_mismatches(qm: QModel, words: list[str]) -> int:
    """Count words whose isa_sim scores differ from ref_int logits.

    Args:
        qm: Quantized model.
        words: Words to run at every position.

    Returns:
        Number of words with any differing score.
    """
    machine = Machine(qm, assemble(qm))
    inputs, _ = encode(words)
    ref = forward(qm, inputs.numpy())
    mismatches = 0
    for i, word in enumerate(words):
        n = len(word) + 1
        isa = run_word(machine, inputs[i, :n].tolist())
        mismatches += not np.array_equal(isa, ref[i, :n])
    return mismatches


def main(n_isa: int = N_ISA_WORDS) -> int:
    """Print the full report.

    Args:
        n_isa: Number of validation words run through isa_sim.

    Returns:
        Number of ref_int and isa_sim mismatches.
    """
    params = load_params()
    qm = quantize(params)
    _, val_words = load_split()
    inputs, targets = encode(val_words)

    with torch.no_grad():
        float_val = loss_fn(params, inputs, targets).item()
    integer_val = int_loss(qm, inputs, targets)
    gap = integer_val - float_val
    print(f"float validation loss   {float_val:.4f}")
    print(f"integer validation loss {integer_val:.4f}")
    print(f"difference              {gap:+.4f} "
          f"({'meets' if gap < TARGET_GAP else 'MISSES'} the "
          f"{TARGET_GAP} target)")

    t0 = time.time()
    bad = isa_mismatches(qm, val_words[:n_isa])
    print(f"ref_int vs isa_sim: {n_isa - bad} / {n_isa} words bit-identical "
          f"({time.time() - t0:.0f} s)")

    print("\n" + shift_table(qm))
    print("\n".join(qm["notes"]) or "no formats lowered")
    print("\n--- float samples ---\n" + "\n".join(sample(params)))
    print("\n--- integer samples ---\n" + "\n".join(int_sample(qm)))
    return bad


if __name__ == "__main__":
    sys.exit(main(int(sys.argv[1]) if len(sys.argv) > 1 else N_ISA_WORDS)
             != 0)
