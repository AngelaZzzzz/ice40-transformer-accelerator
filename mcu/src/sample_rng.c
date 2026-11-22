// sample_rng.c
// Random source for sampling: the STM32L432 RNG clocked from HSI48, or a
// xorshift32 generator seeded from the DWT cycle counter if the RNG does
// not start or reports a seed or clock error.

#include "sample.h"
#include "STM32L432KC.h"
#include "model_load.h"
#include "timing.h"

#define START_TIMEOUT_US 1000
#define RNG_ERRORS (RNG_SR_SECS | RNG_SR_CECS | RNG_SR_SEIS | RNG_SR_CEIS)

static int hw_rng;
static uint32_t xorshift_state;

static uint32_t xorshift32(void) {
    xorshift_state ^= xorshift_state << 13;
    xorshift_state ^= xorshift_state >> 17;
    xorshift_state ^= xorshift_state << 5;
    return xorshift_state;
}

static uint32_t random32(void) {
    if (hw_rng) {
        while (!(RNG->SR & RNG_SR_DRDY)) {
            if (RNG->SR & RNG_ERRORS) {
                hw_rng = 0;
                return xorshift32();
            }
        }
        return RNG->DR;
    }
    return xorshift32();
}

void sample_init(void) {
    uint32_t start;

    timing_init();

    RCC->CRRCR |= RCC_CRRCR_HSI48ON;
    start = timing_cycles();
    while (!(RCC->CRRCR & RCC_CRRCR_HSI48RDY) &&
           timing_elapsed_us(start) < START_TIMEOUT_US) {
    }
    RCC->CCIPR &= ~RCC_CCIPR_CLK48SEL;

    RCC->AHB2ENR |= RCC_AHB2ENR_RNGEN;
    RNG->CR |= RNG_CR_RNGEN;
    start = timing_cycles();
    while (!(RNG->SR & RNG_SR_DRDY) &&
           timing_elapsed_us(start) < START_TIMEOUT_US) {
    }
    hw_rng = (RNG->SR & RNG_SR_DRDY) && !(RNG->SR & RNG_ERRORS);

    xorshift_state = timing_cycles() | 1u;
}

int sample_hw_rng(void) {
    return hw_rng;
}

uint8_t sample_next(const int16_t scores[27]) {
    float u = (float) (random32() >> 8) / 16777216.0f;
    return sample_index(scores, u, SAMPLE_TEMPERATURE, model_logit_frac());
}
