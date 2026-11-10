"""Float reference model, adapted from Andrej Karpathy's microgpt:
https://gist.github.com/karpathy/8627fe009c40f57531cb18360106ce95

The architecture is microgpt's: token plus position embedding, RMSNorm
without gain, causal multi-head attention, ReLU MLP of width 4 x n_embd,
residual connections, no biases, separate lm_head. Changes from microgpt:

- Size: n_layer 2 and n_embd 64 (microgpt: 1 and 16); n_head 4, head_dim
  16, block_size 16 and the MLP ratio are unchanged. 102,784 parameters.
- Autograd: microgpt's scalar Value class is replaced by PyTorch tensors.
  Per-element Python loops become matrix products over a batch of words
  and all positions at once, with a causal mask in place of the
  incrementally grown keys and values lists.
- Tokenizer: tokens are fixed as a = 0 ... z = 25 and BOS = 26. This is
  the mapping microgpt derives from names.txt, made explicit for hardware.
- Data: a fixed-seed 90/10 train/validation split; each word is encoded
  as BOS + letters + BOS, padded to block_size + 1, with padded targets
  excluded from the loss.
- Loss: cross-entropy averaged over all predicted tokens in a batch
  (microgpt averages over the tokens of one word).
- Initialization: the same N(0, 0.08^2) scheme, drawn from a seeded
  PyTorch generator, so values differ from microgpt's random.gauss.
- Sampling: the same temperature-0.5 sampling, recomputing the full
  prefix each step instead of using a KV cache.
- Added: gpt() optionally records the maximum magnitude of each named
  intermediate vector for quantization calibration.
"""

import random

import torch
import torch.nn.functional as F

from config import (BLOCK_SIZE, BOS, D_MLP, D_MODEL, DATA_PATH, HEAD_DIM,
                    MAX_WORD_LEN, N_HEAD, N_LAYER, N_PARAMS, RMS_EPS,
                    VOCAB_SIZE)

Params = dict[str, torch.Tensor]
Record = dict[str, float]

# ------------------------------------------------------------------------------
# Dataset and tokenizer: a = 0 ... z = 25, BOS = 26
# ------------------------------------------------------------------------------


def load_split(seed: int = 42,
               val_frac: float = 0.1) -> tuple[list[str], list[str]]:
    """Load names.txt and split it into training and validation words.

    Args:
        seed: Shuffle seed.
        val_frac: Fraction of words held out for validation.

    Returns:
        Training words and validation words.
    """
    words = DATA_PATH.read_text().split()
    assert len(words) == 32_033
    assert all(w.isascii() and w.isalpha() and w.islower() for w in words)
    assert max(len(w) for w in words) <= MAX_WORD_LEN
    random.Random(seed).shuffle(words)
    n_val = int(len(words) * val_frac)
    return words[n_val:], words[:n_val]


def encode_word(word: str) -> list[int]:
    """Tokenize one word as BOS + letters + BOS.

    Args:
        word: Lowercase word.

    Returns:
        Token ids.
    """
    return [BOS] + [ord(c) - ord("a") for c in word] + [BOS]


def decode(tokens: list[int]) -> str:
    """Convert token ids back to letters, dropping BOS.

    Args:
        tokens: Token ids.

    Returns:
        Decoded word.
    """
    return "".join(chr(t + ord("a")) for t in tokens if t != BOS)


def encode(words: list[str]) -> tuple[torch.Tensor, torch.Tensor]:
    """Encode words as padded input and target token matrices.

    Args:
        words: Lowercase words.

    Returns:
        Inputs (padding 0) and targets (padding -1), each
        (len(words), BLOCK_SIZE).
    """
    seq = torch.full((len(words), BLOCK_SIZE + 1), -1, dtype=torch.long)
    for i, word in enumerate(words):
        tokens = encode_word(word)
        seq[i, :len(tokens)] = torch.tensor(tokens)
    return seq[:, :-1].clamp(min=0), seq[:, 1:]


# ------------------------------------------------------------------------------
# Parameters
# ------------------------------------------------------------------------------


def init_params(seed: int = 42, std: float = 0.08) -> Params:
    """Create all weight matrices with microgpt's Gaussian init.

    Args:
        seed: Generator seed.
        std: Standard deviation of the initial weights.

    Returns:
        Parameter tensors keyed by microgpt's state_dict names.
    """
    gen = torch.Generator().manual_seed(seed)

    def matrix(nout: int, nin: int) -> torch.Tensor:
        """Draw one trainable weight matrix.

        Args:
            nout: Number of rows.
            nin: Number of columns.

        Returns:
            Matrix with requires_grad set.
        """
        return (torch.randn(nout, nin, generator=gen) * std).requires_grad_()

    params = {"wte": matrix(VOCAB_SIZE, D_MODEL),
              "wpe": matrix(BLOCK_SIZE, D_MODEL),
              "lm_head": matrix(VOCAB_SIZE, D_MODEL)}
    for i in range(N_LAYER):
        params[f"layer{i}.attn_wq"] = matrix(D_MODEL, D_MODEL)
        params[f"layer{i}.attn_wk"] = matrix(D_MODEL, D_MODEL)
        params[f"layer{i}.attn_wv"] = matrix(D_MODEL, D_MODEL)
        params[f"layer{i}.attn_wo"] = matrix(D_MODEL, D_MODEL)
        params[f"layer{i}.mlp_fc1"] = matrix(D_MLP, D_MODEL)
        params[f"layer{i}.mlp_fc2"] = matrix(D_MODEL, D_MLP)
    assert sum(p.numel() for p in params.values()) == N_PARAMS
    return params


# ------------------------------------------------------------------------------
# Model
# ------------------------------------------------------------------------------


def rmsnorm(x: torch.Tensor) -> torch.Tensor:
    """RMSNorm without gain over the last dimension.

    Args:
        x: Input activations.

    Returns:
        Normalized activations.
    """
    return x * (x.pow(2).mean(-1, keepdim=True) + RMS_EPS).rsqrt()


def heads(x: torch.Tensor) -> torch.Tensor:
    """Split the channel dimension into attention heads.

    Args:
        x: Activations (batch, steps, D_MODEL).

    Returns:
        Activations (batch, N_HEAD, steps, HEAD_DIM).
    """
    batch, steps, _ = x.shape
    return x.view(batch, steps, N_HEAD, HEAD_DIM).transpose(1, 2)


def track(record: Record | None, name: str, t: torch.Tensor) -> torch.Tensor:
    """Record the running maximum magnitude of a named tensor.

    Args:
        record: Maxima keyed by name, or None to skip recording.
        name: Vector name.
        t: Tensor to measure.

    Returns:
        t, unchanged.
    """
    if record is not None:
        record[name] = max(record.get(name, 0.0), t.abs().max().item())
    return t


def gpt(params: Params, tokens: torch.Tensor,
        record: Record | None = None) -> torch.Tensor:
    """Forward pass over every position of a batch of token sequences.

    Args:
        params: Model parameters.
        tokens: Token ids (batch, steps).
        record: Optional maxima of named intermediates for calibration.

    Returns:
        Logits (batch, steps, VOCAB_SIZE).
    """
    batch, steps = tokens.shape
    x = params["wte"][tokens] + params["wpe"][:steps]
    x = track(record, "x", rmsnorm(x))
    causal = torch.ones(steps, steps, dtype=torch.bool).tril()

    for li in range(N_LAYER):
        x_residual = x
        x = rmsnorm(x)
        q = heads(track(record, f"q{li}", x @ params[f"layer{li}.attn_wq"].T))
        k = heads(track(record, f"k{li}", x @ params[f"layer{li}.attn_wk"].T))
        v = heads(track(record, f"v{li}", x @ params[f"layer{li}.attn_wv"].T))
        attn_logits = q @ k.transpose(-2, -1) / HEAD_DIM ** 0.5
        track(record, f"s{li}", attn_logits.masked_fill(~causal, 0.0))
        attn_weights = attn_logits.masked_fill(~causal, float("-inf"))
        attn_weights = attn_weights.softmax(-1)
        x_attn = (attn_weights @ v).transpose(1, 2).reshape(batch, steps, -1)
        x_attn = track(record, f"a{li}", x_attn)
        t = track(record, "t", x_attn @ params[f"layer{li}.attn_wo"].T)
        x = track(record, "x", t + x_residual)
        x_residual = x
        x = rmsnorm(x)
        x = track(record, f"h{li}", x @ params[f"layer{li}.mlp_fc1"].T).relu()
        t = track(record, "t", x @ params[f"layer{li}.mlp_fc2"].T)
        x = track(record, "x", t + x_residual)

    return track(record, "logits", x @ params["lm_head"].T)


def loss_fn(params: Params, inputs: torch.Tensor,
            targets: torch.Tensor) -> torch.Tensor:
    """Mean cross-entropy over all non-padded target tokens.

    Args:
        params: Model parameters.
        inputs: Input token ids (batch, steps).
        targets: Target token ids, -1 for padding.

    Returns:
        Scalar loss in nats per predicted token.
    """
    logits = gpt(params, inputs)
    return F.cross_entropy(logits.reshape(-1, VOCAB_SIZE), targets.reshape(-1),
                           ignore_index=-1)


@torch.no_grad()
def sample(params: Params, n: int = 20, temperature: float = 0.5,
           seed: int = 42) -> list[str]:
    """Generate words with temperature sampling, as microgpt does.

    Args:
        params: Model parameters.
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
            logits = gpt(params, torch.tensor([tokens]))[0, -1]
            probs = (logits / temperature).softmax(-1)
            token = torch.multinomial(probs, 1, generator=gen).item()
            if token == BOS:
                break
            tokens.append(token)
        words.append(decode(tokens))
    return words
