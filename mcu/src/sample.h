// sample.h
// Next-letter sampling from FPGA scores

#ifndef SAMPLE_H
#define SAMPLE_H

#include <stdint.h>

#define SAMPLE_TEMPERATURE 0.5f

uint8_t sample_index(const int16_t scores[27], float u, float temperature,
                     int logit_frac);
void sample_init(void);
int sample_hw_rng(void);
uint8_t sample_next(const int16_t scores[27]);

#endif // SAMPLE_H
