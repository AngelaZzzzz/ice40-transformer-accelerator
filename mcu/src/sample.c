// sample.c
// Softmax sampling of the next token from int16 scores with logit_frac
// fractional bits. Hardware-independent; the random source is in
// sample_rng.c.

#include <math.h>

#include "sample.h"

#define N_TOKENS 27

uint8_t sample_index(const int16_t scores[27], float u, float temperature,
                     int logit_frac) {
    float weight[N_TOKENS];
    float scale = 1.0f / ((float) (1L << logit_frac) * temperature);
    float total = 0.0f;
    float cumulative = 0.0f;
    int16_t max_score = scores[0];
    uint8_t last_nonzero = 0;

    for (int i = 1; i < N_TOKENS; i++) {
        if (scores[i] > max_score) {
            max_score = scores[i];
        }
    }
    for (int i = 0; i < N_TOKENS; i++) {
        weight[i] = expf((float) ((int32_t) scores[i] - max_score) * scale);
        total += weight[i];
        if (weight[i] > 0.0f) {
            last_nonzero = (uint8_t) i;
        }
    }

    float target = u * total;
    for (int i = 0; i < N_TOKENS; i++) {
        cumulative += weight[i];
        if (cumulative > target) {
            return (uint8_t) i;
        }
    }
    return last_nonzero;
}
