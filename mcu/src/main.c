// main.c
// Transformer text generator host: keyboard input, FPGA inference, sampling
// and display. MODE selects the SPI or PS/2 hardware test, or the
// application.

#include <stdio.h>

#include "STM32L432KC.h"
#include "display.h"
#include "fpga.h"
#include "model_load.h"
#include "pins.h"
#include "ps2.h"
#include "sample.h"

#define MODE_APP      0
#define MODE_SPI_TEST 1
#define MODE_PS2_TEST 2

#ifndef MODE
#define MODE MODE_APP
#endif

#define TEST_WORDS     256
#define TEST_BYTES     (8 * TEST_WORDS)
#define TEST_PASSES    5
#define DONE_POLLS     100000
#define N_SCORES       27
#define SCORE_PATTERN  0xA5A5

static uint8_t lcg_byte(uint32_t *seed) {
    *seed = *seed * 1664525u + 1013904223u;
    return (uint8_t) (*seed >> 24);
}

static void spi_test(void) {
    static uint8_t wbuf[TEST_BYTES];
    static uint8_t rbuf[TEST_BYTES];
    int16_t scores[N_SCORES];
    int errors = 0;

    for (int pass = 0; pass < TEST_PASSES; pass++) {
        uint32_t seed = (uint32_t) pass + 1;
        int mismatches = 0;
        for (int i = 0; i < TEST_BYTES; i++) {
            wbuf[i] = lcg_byte(&seed);
        }
        fpga_write_spram(0, wbuf, TEST_WORDS);
        fpga_read_spram(0, rbuf, TEST_WORDS);
        for (int i = 0; i < TEST_BYTES; i++) {
            mismatches += (rbuf[i] != wbuf[i]);
        }
        printf("pass %d: %d of %d bytes mismatched\n", pass, mismatches,
               TEST_BYTES);
        errors += mismatches;
    }

    fpga_run(3, 2);
    int polls = 0;
    while (!fpga_done() && polls < DONE_POLLS) {
        polls++;
    }
    if (!fpga_done()) {
        printf("DONE did not go high after RUN\n");
        errors++;
    }

    fpga_read_scores(scores);
    for (int i = 0; i < N_SCORES; i++) {
        if ((uint16_t) scores[i] != (SCORE_PATTERN ^ i)) {
            printf("score %d: got %04x\n", i, (uint16_t) scores[i]);
            errors++;
        }
    }

    printf("SPI test %s: %d errors\n", errors ? "FAILED" : "PASSED", errors);
}

static void ps2_test(void) {
    uint32_t dropped = 0;
    char key;

    printf("PS/2 test: press keys\n");
    while (1) {
        if (ps2_get(&key)) {
            if (key == '\n') {
                printf("key: Enter\n");
            } else if (key == '\b') {
                printf("key: Backspace\n");
            } else {
                printf("key: %c\n", key);
            }
        }
        if (ps2_dropped() != dropped) {
            dropped = ps2_dropped();
            printf("dropped frames: %lu\n", (unsigned long) dropped);
        }
    }
}

int main(void) {
    configureFlash();
    configureClock();
    SystemCoreClockUpdate();

    switch (MODE) {
        case MODE_SPI_TEST:
            fpga_init();
            spi_test();
            break;
        case MODE_PS2_TEST:
            ps2_init();
            ps2_test();
            break;
        default:
            // TODO(zach): implement the application main loop
            break;
    }

    while (1) {
    }
}
