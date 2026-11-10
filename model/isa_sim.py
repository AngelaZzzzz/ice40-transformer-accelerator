"""Instruction-level simulator: runs the assembled program on a
16,384-word SPRAM image and a 1,024-word vector register file exactly as
docs/interface_spec.md sections 3 to 5 define each instruction.
"""

from typing import Any

import numpy as np

from config import BOS, D_MODEL, N_LAYER
from isa import (A_K0, A_L0, A_L1, A_OUT, A_POS, A_TOK, A_V1, F_ALT, F_SAT8,
                 O_W1, O_W2, O_WK, O_WO, O_WQ, O_WV, decode)
from quantize import QModel
from ref_int import rmsnorm, rq, sat16, softmax

SPRAM_WORDS = 16_384
VREG_WORDS = 1024
SCORE_WORDS = 32
LANES = 8

Instr = dict[str, Any]

# ------------------------------------------------------------------------------
# SPRAM image (docs/interface_spec.md section 4)
# ------------------------------------------------------------------------------


def store_matrix(spram: np.ndarray, base: int, m: np.ndarray) -> None:
    """Store a matrix in matrix layout: row group g, column c at word
    base + gC + c, lane l = M[8g + l][c].

    Args:
        spram: SPRAM image (words, 8 lanes).
        base: First word.
        m: Int8 matrix; rows are zero-padded to a multiple of 8.
    """
    rows, cols = m.shape
    padded = np.zeros((-(-rows // LANES) * LANES, cols), dtype=np.int64)
    padded[:rows] = m
    for g in range(padded.shape[0] // LANES):
        spram[base + g * cols:base + (g + 1) * cols] = \
            padded[g * LANES:(g + 1) * LANES].T


def store_vectors(spram: np.ndarray, base: int, e: np.ndarray) -> None:
    """Store an embedding table in vector layout: row r at base + 8r + k,
    lane l = E[r][8k + l].

    Args:
        spram: SPRAM image.
        base: First word.
        e: Int8 table (rows, 64).
    """
    for r, row in enumerate(e):
        spram[base + 8 * r:base + 8 * r + D_MODEL // LANES] = \
            row.reshape(-1, LANES)


def spram_image(qm: QModel) -> np.ndarray:
    """Build the full SPRAM image with an all-zero KV region.

    Args:
        qm: Quantized model.

    Returns:
        Image (16,384 words, 8 lanes) of signed bytes.
    """
    w = qm["w"]
    spram = np.zeros((SPRAM_WORDS, LANES), dtype=np.int64)
    store_vectors(spram, A_TOK, w["wte"])
    store_vectors(spram, A_POS, w["wpe"])
    for li, a_l in enumerate((A_L0, A_L1)[:N_LAYER]):
        for key, off in (("q", O_WQ), ("k", O_WK), ("v", O_WV),
                         ("o", O_WO), ("1", O_W1), ("2", O_W2)):
            store_matrix(spram, a_l + off, w[f"{key}{li}"])
    store_matrix(spram, A_OUT, w["out"])
    assert not spram[A_K0:A_V1 + 128].any()
    return spram


# ------------------------------------------------------------------------------
# Instruction-level simulator
# ------------------------------------------------------------------------------


class Machine:
    """Accelerator state: SPRAM, vector registers and score buffer."""

    def __init__(self, qm: QModel, prog: list[int]) -> None:
        """Load the model image and decode the program.

        Args:
            qm: Quantized model.
            prog: Instruction words.
        """
        self.prog: list[Instr] = [decode(word) for word in prog]
        self.spram = spram_image(qm)
        self.vr = np.zeros(VREG_WORDS, dtype=np.int64)
        self.score = np.zeros(SCORE_WORDS, dtype=np.int64)

    def run(self, letter: int, pos: int,
            trace: list[np.ndarray] | None = None) -> np.ndarray:
        """Run the program for one letter at one position.

        Args:
            letter: Token id, 0 to 26.
            pos: Position, 0 to 15.
            trace: If given, receives the register file after each
                instruction.

        Returns:
            Score buffer.
        """
        for ins in self.prog:
            if ins["op"] == "HALT":
                break
            getattr(self, ins["op"].lower())(ins, letter, pos)
            if trace is not None:
                trace.append(self.vr.copy())
        return self.score.copy()

    def embed(self, ins: Instr, letter: int, pos: int) -> None:
        """EMBED: sum token and position embedding bytes, shift left.

        Args:
            ins: Decoded instruction.
            letter: Token id.
            pos: Position.
        """
        n, base, d = ins["cols"], ins["base"], 8 * ins["dst"]
        tok = self.spram[base + 8 * letter:base + 8 * letter + n // 8]
        pe = self.spram[base + 256 + 8 * pos:base + 256 + 8 * pos + n // 8]
        self.vr[d:d + n] = sat16((tok + pe).reshape(-1) << ins["shift"])

    def matvec(self, ins: Instr, letter: int, pos: int) -> None:
        """MATVEC: eight rows per group against the source vector.

        Args:
            ins: Decoded instruction.
            letter: Unused.
            pos: Unused.
        """
        rows, cols, base = ins["rows"], ins["cols"], ins["base"]
        x = self.vr[8 * ins["src"]:8 * ins["src"] + cols]
        sat8 = bool(ins["flags"] >> F_SAT8 & 1)
        for g in range(rows // 8):
            block = self.spram[base + g * cols:base + (g + 1) * cols]
            y = rq(x @ block, ins["shift"], sat8)
            if ins["flags"] >> F_ALT & 1:
                self.score[8 * g:8 * g + 8] = y
            else:
                d = 8 * ins["dst"] + 8 * g
                self.vr[d:d + 8] = y

    def kvstore(self, ins: Instr, letter: int, pos: int) -> None:
        """KVSTORE: write low bytes into the K or V cache layout.

        Args:
            ins: Decoded instruction.
            letter: Unused.
            pos: Position written.
        """
        base, src = ins["base"], 8 * ins["src"]
        for c in range(64):
            byte = (self.vr[src + c] + 128) % 256 - 128
            if ins["flags"] >> F_ALT & 1:
                word = base + 32 * (c >> 4) + 16 * ((c >> 3) & 1) + pos
                self.spram[word, c & 7] = byte
            else:
                word = base + 32 * (c >> 4) + 16 * (pos >> 3) + (c & 15)
                self.spram[word, pos & 7] = byte

    def vadd(self, ins: Instr, letter: int, pos: int) -> None:
        """VADD: dst += src with int16 saturation.

        Args:
            ins: Decoded instruction.
            letter: Unused.
            pos: Unused.
        """
        n, d, s = ins["cols"], 8 * ins["dst"], 8 * ins["src"]
        self.vr[d:d + n] = sat16(self.vr[d:d + n] + self.vr[s:s + n])

    def vmul(self, ins: Instr, letter: int, pos: int) -> None:
        """VMUL: dst = rq(dst x src, shift).

        Args:
            ins: Decoded instruction.
            letter: Unused.
            pos: Unused.
        """
        n, d, s = ins["cols"], 8 * ins["dst"], 8 * ins["src"]
        self.vr[d:d + n] = rq(self.vr[d:d + n] * self.vr[s:s + n],
                              ins["shift"])

    def vrelu(self, ins: Instr, letter: int, pos: int) -> None:
        """VRELU: dst = max(src, 0).

        Args:
            ins: Decoded instruction.
            letter: Unused.
            pos: Unused.
        """
        n, d, s = ins["cols"], 8 * ins["dst"], 8 * ins["src"]
        self.vr[d:d + n] = np.maximum(self.vr[s:s + n], 0)

    def rmsnorm(self, ins: Instr, letter: int, pos: int) -> None:
        """RMSNORM: shift = pre-shift a, flags = output offset o.

        Args:
            ins: Decoded instruction.
            letter: Unused.
            pos: Unused.
        """
        n, d, s = ins["cols"], 8 * ins["dst"], 8 * ins["src"]
        self.vr[d:d + n] = rmsnorm(self.vr[s:s + n], ins["shift"],
                                   ins["flags"])

    def softmax(self, ins: Instr, letter: int, pos: int) -> None:
        """SOFTMAX: in place on 16 scores; shift = table index shift.

        Args:
            ins: Decoded instruction.
            letter: Unused.
            pos: Last valid position.
        """
        assert ins["src"] == ins["dst"] and ins["cols"] == 16
        d = 8 * ins["dst"]
        self.vr[d:d + 16] = softmax(self.vr[d:d + 16], pos, ins["shift"])


def run_word(machine: Machine, tokens: list[int]) -> np.ndarray:
    """Run every position of one token sequence.

    Args:
        machine: Simulator; its KV cache carries across positions.
        tokens: Token ids starting with BOS.

    Returns:
        Scores (positions, 27).
    """
    return np.array([machine.run(tok, pos)[:27]
                     for pos, tok in enumerate(tokens)])


def word_tokens(word: str) -> list[int]:
    """Input tokens for a prefix: BOS then its letters.

    Args:
        word: Lowercase prefix.

    Returns:
        Token ids.
    """
    return [BOS] + [ord(c) - ord("a") for c in word]
