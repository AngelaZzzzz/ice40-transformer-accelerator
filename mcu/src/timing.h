// timing.h
// Microsecond delays and elapsed-time measurement on the DWT cycle counter

#ifndef TIMING_H
#define TIMING_H

#include <stdint.h>

void timing_init(void);
uint32_t timing_cycles(void);
uint32_t timing_elapsed_us(uint32_t start_cycles);
void delay_us(uint32_t us);

#endif // TIMING_H
