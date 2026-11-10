// sample.h
// Next-letter sampling from FPGA scores

#ifndef SAMPLE_H
#define SAMPLE_H

#include <stdint.h>

void sample_init(void);
uint8_t sample_next(const int16_t scores[27]);

#endif // SAMPLE_H
