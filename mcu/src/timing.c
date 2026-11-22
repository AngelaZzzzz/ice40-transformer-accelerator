// timing.c
// Microsecond delays and elapsed-time measurement on the DWT cycle counter,
// which counts core clock cycles (SystemCoreClock) and wraps every 2^32
// cycles (53 s at 80 MHz). Intervals are computed with unsigned
// subtraction, so they are correct across one wrap.

#include "timing.h"
#include "STM32L432KC.h"

void timing_init(void) {
    CoreDebug->DEMCR |= CoreDebug_DEMCR_TRCENA_Msk;
    DWT->CTRL |= DWT_CTRL_CYCCNTENA_Msk;
}

uint32_t timing_cycles(void) {
    return DWT->CYCCNT;
}

uint32_t timing_elapsed_us(uint32_t start_cycles) {
    return (DWT->CYCCNT - start_cycles) / (SystemCoreClock / 1000000u);
}

void delay_us(uint32_t us) {
    uint32_t start = DWT->CYCCNT;
    uint32_t wait = us * (SystemCoreClock / 1000000u);
    while (DWT->CYCCNT - start < wait) {
    }
}
