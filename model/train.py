"""Training loop, adapted from Andrej Karpathy's microgpt:
https://gist.github.com/karpathy/8627fe009c40f57531cb18360106ce95

Kept from microgpt: Adam with linear learning-rate decay to 0, beta2 0.99,
eps 1e-8, and 20 temperature-0.5 samples printed after training. Changes:

- Optimizer: PyTorch's Adam with lr 3e-3 and beta1 0.9 (microgpt: 0.01
  and 0.85), suited to the larger model and batched updates.
- Steps: 5,000 steps of 128 randomly drawn training words (microgpt:
  1,000 steps of one word each, in shuffled order). 20,000 steps
  overfit: validation loss 2.194 versus 1.975 at 5,000.
- Evaluation: train and validation loss are printed every 1,000 steps.
- Output: parameters are saved to model/out/float.pt.
"""

import sys
import time

import torch

from config import OUT_DIR
from model import encode, init_params, load_split, loss_fn, sample

STEPS = 5_000
BATCH = 128
LR = 3e-3
BETAS = (0.9, 0.99)
EVAL_EVERY = 1000
SEED = 42


def main(steps: int = STEPS) -> None:
    """Train the float model, save it, and print samples.

    Args:
        steps: Number of optimizer steps.
    """
    torch.manual_seed(SEED)
    train_words, val_words = load_split()
    x_train, y_train = encode(train_words)
    x_val, y_val = encode(val_words)
    params = init_params()
    opt = torch.optim.Adam(params.values(), lr=LR, betas=BETAS)
    sched = torch.optim.lr_scheduler.LambdaLR(opt, lambda s: 1 - s / steps)

    t0 = time.time()
    for step in range(steps):
        idx = torch.randint(len(x_train), (BATCH,))
        loss = loss_fn(params, x_train[idx], y_train[idx])
        opt.zero_grad()
        loss.backward()
        opt.step()
        sched.step()
        if (step + 1) % EVAL_EVERY == 0 or step + 1 == steps:
            with torch.no_grad():
                val = loss_fn(params, x_val, y_val).item()
            print(f"step {step + 1:5d} / {steps} | train {loss.item():.4f} "
                  f"| val {val:.4f} | {time.time() - t0:.0f} s", flush=True)

    OUT_DIR.mkdir(exist_ok=True)
    torch.save({k: v.detach() for k, v in params.items()},
               OUT_DIR / "float.pt")
    print("--- samples ---")
    for word in sample(params):
        print(word)


if __name__ == "__main__":
    main(int(sys.argv[1]) if len(sys.argv) > 1 else STEPS)
