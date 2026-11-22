// bringup.c
// Hardware bring-up test: writes and verifies the model weights over SPI,
// runs the output-layer MATVEC for BOS at position 0 from the vector
// registers preloaded in the bring-up bitstream, compares the 27 scores
// with the Python integer model, and shows the results on the VGA screen
// and over printf.

#include <assert.h>
#include <math.h>
#include <stdarg.h>
#include <stdio.h>

#include "bringup.h"
#include "bringup_data.h"
#include "fpga.h"
#include "model_load.h"
#include "timing.h"

#define COLS          40
#define ROWS          15
#define N_SCORES      27
#define N_TOP         6
#define TOP_PER_LINE  4
#define DONE_WAIT_US  1000
#define WHITE         0
#define GREEN         1

static const char *failed;

static void screen_line(int row, int color, const char *fmt, ...) {
    char text[COLS + 1];
    uint8_t cells[COLS];
    va_list args;

    va_start(args, fmt);
    int n = vsnprintf(text, sizeof text, fmt, args);
    va_end(args);
    assert(n >= 0 && n <= COLS);

    for (int i = 0; i < COLS; i++) {
        uint8_t ch = (i < n) ? (uint8_t) text[i] : (uint8_t) ' ';
        cells[i] = (uint8_t) ((ch & 0x7F) | (color ? 0x80 : 0x00));
    }
    fpga_write_chars((uint16_t) (row * COLS), cells, COLS);
    printf("%s\n", text);
}

static void fail(const char *check) {
    if (failed == 0) {
        failed = check;
    }
}

static void show_word(int row, const char *label, uint16_t addr) {
    uint8_t got[8];
    const uint8_t *expected = model_word(addr);
    int equal = 1;

    fpga_read_spram(addr, got, 1);
    for (int k = 0; k < 8; k++) {
        equal &= (got[k] == expected[k]);
    }
    if (!equal) {
        fail("word readback");
    }
    screen_line(row, equal ? GREEN : WHITE,
                "%-10s%02x %02x %02x %02x %02x %02x %02x %02x", label,
                got[0], got[1], got[2], got[3], got[4], got[5], got[6],
                got[7]);
}

static char token_char(int token) {
    return (token < 26) ? (char) ('a' + token) : '.';
}

static void show_top(int row, const int16_t scores[N_SCORES]) {
    float prob[N_SCORES];
    float total = 0.0f;
    float scale = 1.0f / (float) (1L << model_logit_frac());
    int16_t max_score = scores[0];
    int used[N_SCORES] = {0};
    int top[N_TOP];
    char line[COLS + 1];
    int len = 0;

    for (int i = 1; i < N_SCORES; i++) {
        if (scores[i] > max_score) {
            max_score = scores[i];
        }
    }
    for (int i = 0; i < N_SCORES; i++) {
        prob[i] = expf((float) ((int32_t) scores[i] - max_score) * scale);
        total += prob[i];
    }
    for (int t = 0; t < N_TOP; t++) {
        int best = -1;
        for (int i = 0; i < N_SCORES; i++) {
            if (!used[i] && (best < 0 || prob[i] > prob[best])) {
                best = i;
            }
        }
        used[best] = 1;
        top[t] = best;
    }

    for (int t = 0; t < N_TOP; t++) {
        len += snprintf(line + len, sizeof line - len, "%s%c %.1f%%",
                        (t % TOP_PER_LINE) ? "  " : "", token_char(top[t]),
                        100.0f * prob[top[t]] / total);
        if (t % TOP_PER_LINE == TOP_PER_LINE - 1 || t == N_TOP - 1) {
            screen_line(row++, WHITE, "%s", line);
            len = 0;
        }
    }
}

void bringup_run(void) {
    static uint8_t blank[COLS * ROWS];
    int16_t scores[N_SCORES];
    uint32_t start, mismatches, elapsed;
    int matches, done;

    failed = 0;
    timing_init();
    for (int i = 0; i < COLS * ROWS; i++) {
        blank[i] = ' ';
    }
    fpga_write_chars(0, blank, COLS * ROWS);
    fpga_scroll(0);
    screen_line(0, WHITE, "E155 transformer bring-up");

    start = timing_cycles();
    model_write_weights();
    elapsed = timing_elapsed_us(start);
    screen_line(1, WHITE, "weights   %u words written   %lu ms",
                (unsigned) model_nwords(),
                (unsigned long) (elapsed / 1000));

    mismatches = model_verify_weights();
    if (mismatches != 0) {
        fail("weight readback");
    }
    screen_line(2, mismatches ? WHITE : GREEN,
                "readback %lu bytes %lu errors %s",
                (unsigned long) (8 * model_nwords()),
                (unsigned long) mismatches, mismatches ? "FAIL" : "PASS");

    show_word(3, "tok 'a'", 0x0000);
    show_word(4, "Wq0[0]", 0x0180);
    show_word(5, "Wout[0]", 0x3180);

    fpga_write_prog(0, bringup_prog, BRINGUP_NINSTR);
    fpga_run(BRINGUP_LETTER, BRINGUP_POS);
    start = timing_cycles();
    done = fpga_wait_done(DONE_WAIT_US);
    elapsed = timing_elapsed_us(start);
    if (done) {
        screen_line(6, GREEN, "run       BOS at 0, done in %lu us",
                    (unsigned long) elapsed);
    } else {
        fail("DONE timeout");
        screen_line(6, WHITE, "run       BOS at 0, no DONE in %d us",
                    DONE_WAIT_US);
    }

    fpga_read_scores(scores);
    matches = 0;
    for (int i = 0; i < N_SCORES; i++) {
        matches += (scores[i] == bringup_scores[i]);
    }
    if (matches != N_SCORES) {
        fail("scores");
    }
    screen_line(7, (matches == N_SCORES) ? GREEN : WHITE,
                "scores    %d/%d match Python      %s", matches, N_SCORES,
                (matches == N_SCORES) ? "PASS" : "FAIL");

    screen_line(8, WHITE, "next letter after BOS:");
    show_top(9, scores);
    screen_line(11, WHITE, "pixel clock 12 MHz osc, PLL 25.125 MHz");

    if (failed == 0) {
        screen_line(12, GREEN, "ALL CHECKS PASSED");
    } else {
        screen_line(12, WHITE, "FAIL: %s", failed);
    }
}
