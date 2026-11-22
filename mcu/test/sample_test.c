// sample_test.c
// Host-side test of sample_index. Build and run from the repository root:
//   gcc -std=c99 -Wall -Wextra -I mcu/src mcu/test/sample_test.c
//       mcu/src/sample.c -lm -o sample_test && ./sample_test

#include <math.h>
#include <stdio.h>

#include "sample.h"

#define N_TOKENS 27
#define LOGIT_FRAC 10
#define GRID 100000
#define TOLERANCE 0.001

static int errors;

static const int16_t model_scores[N_TOKENS] = {
    1788, 521, 713, 876, 568, -570, -148, 117, -292, 1219, 1403, 714, 1271,
    414, -784, -326, -2072, 798, 979, 616, -2352, -822, -984, -1672, -495,
    237, -4647
};

static void check(int ok, const char *msg) {
    if (!ok) {
        errors++;
        printf("FAILED: %s\n", msg);
    }
}

static void fill(int16_t scores[N_TOKENS], int16_t value) {
    for (int i = 0; i < N_TOKENS; i++) {
        scores[i] = value;
    }
}

// Fraction of a uniform grid of u that selects each token
static void histogram(const int16_t scores[N_TOKENS], float temperature,
                      double freq[N_TOKENS]) {
    for (int i = 0; i < N_TOKENS; i++) {
        freq[i] = 0.0;
    }
    for (int k = 0; k < GRID; k++) {
        float u = ((float) k + 0.5f) / GRID;
        freq[sample_index(scores, u, temperature, LOGIT_FRAC)] += 1.0 / GRID;
    }
}

static void softmax(const int16_t scores[N_TOKENS], double temperature,
                    double p[N_TOKENS]) {
    double max_score = scores[0];
    double total = 0.0;
    for (int i = 1; i < N_TOKENS; i++) {
        if (scores[i] > max_score) {
            max_score = scores[i];
        }
    }
    for (int i = 0; i < N_TOKENS; i++) {
        p[i] = exp((scores[i] - max_score) /
                   ((1 << LOGIT_FRAC) * temperature));
        total += p[i];
    }
    for (int i = 0; i < N_TOKENS; i++) {
        p[i] /= total;
    }
}

static void check_softmax(const int16_t scores[N_TOKENS], float temperature,
                          const char *msg) {
    double freq[N_TOKENS];
    double p[N_TOKENS];
    double worst = 0.0;
    histogram(scores, temperature, freq);
    softmax(scores, temperature, p);
    for (int i = 0; i < N_TOKENS; i++) {
        if (fabs(freq[i] - p[i]) > worst) {
            worst = fabs(freq[i] - p[i]);
        }
    }
    check(worst <= TOLERANCE, msg);
}

int main(void) {
    int16_t scores[N_TOKENS];
    double freq[N_TOKENS];
    double freq_cold[N_TOKENS];
    int ok;

    fill(scores, 0);
    check(sample_index(scores, 0.0f, 1.0f, LOGIT_FRAC) == 0,
          "u = 0 selects the first token");
    check(sample_index(scores, 0.9999999f, 1.0f, LOGIT_FRAC) == 26,
          "u near 1 selects the last token");

    ok = 1;
    for (int i = 0; i < N_TOKENS; i++) {
        float lo = (float) i / N_TOKENS + 1e-4f;
        float hi = (float) (i + 1) / N_TOKENS - 1e-4f;
        ok &= sample_index(scores, lo, 1.0f, LOGIT_FRAC) == i;
        ok &= sample_index(scores, hi, 1.0f, LOGIT_FRAC) == i;
    }
    check(ok, "equal scores give equal-width intervals");

    fill(scores, -32768);
    scores[13] = 32767;
    ok = 1;
    for (int k = 0; k < 1000; k++) {
        float u = (k + 0.5f) / 1000.0f;
        ok &= sample_index(scores, u, 1.0f, LOGIT_FRAC) == 13;
    }
    check(ok, "a dominant score is always chosen");

    for (int i = 0; i < N_TOKENS; i++) {
        scores[i] = (i % 2) ? 32767 : -32768;
    }
    histogram(scores, 0.5f, freq);
    ok = 1;
    for (int i = 0; i < N_TOKENS; i++) {
        ok &= (i % 2) ? fabs(freq[i] - 1.0 / 13) < TOLERANCE : freq[i] == 0.0;
    }
    check(ok, "extreme scores do not overflow");

    fill(scores, -32768);
    check_softmax(scores, 1.0f, "all-minimum scores are uniform");

    histogram(model_scores, 1.0f, freq);
    histogram(model_scores, 0.5f, freq_cold);
    check(freq_cold[0] > freq[0] && freq_cold[26] < freq[26],
          "lower temperature concentrates the distribution");

    check_softmax(model_scores, 1.0f, "histogram matches softmax, T = 1");
    check_softmax(model_scores, 0.5f, "histogram matches softmax, T = 0.5");

    if (errors == 0) {
        printf("PASSED\n");
    } else {
        printf("FAILED: %d errors\n", errors);
    }
    return errors != 0;
}
