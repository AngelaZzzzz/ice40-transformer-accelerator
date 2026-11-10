from pathlib import Path

MODEL_DIR = Path(__file__).resolve().parent
REPO_DIR = MODEL_DIR.parent
DATA_PATH = MODEL_DIR / "data" / "names.txt"
OUT_DIR = MODEL_DIR / "out"
MEM_DIR = REPO_DIR / "fpga" / "mem"
VECTOR_DIR = REPO_DIR / "fpga" / "sim" / "vectors"
MCU_SRC_DIR = REPO_DIR / "mcu" / "src"
GPT_PKG_PATH = REPO_DIR / "fpga" / "rtl" / "gpt_pkg.sv"

N_LAYER = 2
D_MODEL = 64
N_HEAD = 4
HEAD_DIM = 16
BLOCK_SIZE = 16
VOCAB_SIZE = 27
BOS = 26
D_MLP = 256
MAX_WORD_LEN = 15
RMS_EPS = 1e-5
N_PARAMS = 102_784
