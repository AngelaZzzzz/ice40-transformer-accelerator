// generate.c
// Word completion. Tokens are BOS at position 0, then the prefix letters
// at positions 1 to n; each runs the program once. After the last, letters
// are sampled and run in turn until BOS is sampled or the word has 15
// letters. The KV cache needs no clearing between words: every position up
// to the current one is rewritten, and SOFTMAX zeroes later positions.
// Returns the number of generated letters (written NUL-terminated to out,
// at most max_out - 1 of them), GENERATE_TIMEOUT if DONE does not rise, or
// GENERATE_INVALID for a prefix with characters outside a to z or more
// than 15 letters, or max_out < 1.

#include "generate.h"
#include "fpga.h"
#include "sample.h"

#define BOS             26
#define N_SCORES        27
#define DONE_TIMEOUT_US 5000

static int run_token(uint8_t token, uint8_t pos) {
    fpga_run(token, pos);
    return fpga_wait_done(DONE_TIMEOUT_US);
}

int generate(const char *prefix, char *out, int max_out) {
    int16_t scores[N_SCORES];
    int length = 0;
    int count = 0;

    if (max_out < 1) {
        return GENERATE_INVALID;
    }
    while (prefix[length] != '\0') {
        if (prefix[length] < 'a' || prefix[length] > 'z' ||
            length == GENERATE_MAX_LETTERS) {
            return GENERATE_INVALID;
        }
        length++;
    }

    if (!run_token(BOS, 0)) {
        return GENERATE_TIMEOUT;
    }
    for (int i = 0; i < length; i++) {
        if (!run_token((uint8_t) (prefix[i] - 'a'), (uint8_t) (i + 1))) {
            return GENERATE_TIMEOUT;
        }
    }

    while (length < GENERATE_MAX_LETTERS && count < max_out - 1) {
        fpga_read_scores(scores);
        uint8_t token = sample_next(scores);
        if (token == BOS) {
            break;
        }
        out[count++] = (char) ('a' + token);
        length++;
        if (length < GENERATE_MAX_LETTERS && count < max_out - 1 &&
            !run_token(token, (uint8_t) length)) {
            out[count] = '\0';
            return GENERATE_TIMEOUT;
        }
    }
    out[count] = '\0';
    return count;
}
