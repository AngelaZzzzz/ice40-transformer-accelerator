// display_test.c
// Host-side test of display.c against a model of the FPGA text buffer.
// Build and run from the repository root:
//   gcc -std=c99 -Wall -Wextra -I mcu/src mcu/test/display_test.c
//       mcu/src/display.c -o display_test && ./display_test
//
// fpga_write_chars and fpga_scroll are replaced by a 1,024-cell buffer
// and a scroll register that behave as interface spec sections 7 and 8
// describe (auto-increment cell index, scroll 0 to 14). The screen is
// rebuilt from them the way text_renderer shows it, and compared with
// a simple terminal model: a list of lines of which the last 15 are on
// the screen, each cell's character and color (white or green).

#include <stdio.h>
#include <string.h>

#include "display.h"
#include "fpga.h"

#define COLS 40
#define ROWS 15
#define CELLS 1024
#define MAX_LINES 2000

static int errors;

// ---------------------------------------------------------------------------
// FPGA model
// ---------------------------------------------------------------------------

static uint8_t text_buf[CELLS];
static uint8_t scroll_reg;
static int n_writes;

void fpga_write_chars(uint16_t cell, const uint8_t *bytes, int n) {
    if (n < 1 || cell + n > ROWS * COLS) {
        errors++;
        printf("FAILED: write of %d cells at %u\n", n, (unsigned) cell);
        return;
    }
    memcpy(&text_buf[cell], bytes, (size_t) n);
    n_writes++;
}

void fpga_scroll(uint8_t offset) {
    if (offset >= ROWS) {
        errors++;
        printf("FAILED: scroll %u\n", (unsigned) offset);
    }
    scroll_reg = offset;
}

// ---------------------------------------------------------------------------
// Terminal model
// ---------------------------------------------------------------------------

static char line_ch[MAX_LINES][COLS];
static char line_gen[MAX_LINES][COLS];
static int n_lines;
static int cur_col;

static void model_reset(void) {
    memset(line_ch, ' ', sizeof line_ch);
    memset(line_gen, 0, sizeof line_gen);
    n_lines = 1;
    cur_col = 0;
}

static void model_newline(void) {
    n_lines++;
    cur_col = 0;
}

static void model_putc(char c, int generated) {
    if (cur_col == COLS) {
        model_newline();
    }
    line_ch[n_lines - 1][cur_col] = c;
    line_gen[n_lines - 1][cur_col] = (char) (generated != 0);
    cur_col++;
}

static void model_backspace(void) {
    if (cur_col > 0) {
        cur_col--;
        line_ch[n_lines - 1][cur_col] = ' ';
        line_gen[n_lines - 1][cur_col] = 0;
    }
}

// Both at once
static void putc_both(char c, int generated) {
    display_putc(c, generated);
    model_putc(c, generated);
}

static void puts_both(const char *s, int generated) {
    for (; *s; s++) {
        putc_both(*s, generated);
    }
}

static void newline_both(void) {
    display_newline();
    model_newline();
}

static void backspace_both(void) {
    display_backspace();
    model_backspace();
}

// ---------------------------------------------------------------------------
// Checks
// ---------------------------------------------------------------------------

// Compare the rendered screen with the last ROWS lines of the model
static void check_screen(const char *what) {
    int first = (n_lines > ROWS) ? n_lines - ROWS : 0;

    for (int r = 0; r < ROWS; r++) {
        int line = first + r;
        int memrow = (r + scroll_reg) % ROWS;
        for (int c = 0; c < COLS; c++) {
            uint8_t b = text_buf[memrow * COLS + c];
            char ch = (char) (b & 0x7F);
            int gen = (b >> 7) & 1;
            char exp_ch = ' ';
            int exp_gen = 0;
            if (line < n_lines) {
                exp_ch = line_ch[line][c];
                exp_gen = line_gen[line][c];
            }
            // 0x00 and 0x20 both render blank; a blank's color is unseen
            if (ch == 0) {
                ch = ' ';
            }
            if (ch != exp_ch || (ch != ' ' && gen != exp_gen)) {
                errors++;
                if (errors <= 20) {
                    printf("FAILED: %s: screen (%d,%d) is '%c' %s, "
                           "expected '%c' %s\n", what, r, c, ch,
                           gen ? "green" : "white", exp_ch,
                           exp_gen ? "green" : "white");
                }
                return;
            }
        }
    }
}

// The app's Enter sequence (main.c): prefix + generated word, new input
// line with the prefix again
static void enter(const char *prefix, const char *word) {
    newline_both();
    puts_both(prefix, 0);
    puts_both(word, 1);
    newline_both();
    puts_both(prefix, 0);
}

int main(void) {
    char text[COLS + 1];

    // Power-up contents are replaced by a blank screen at scroll 0
    memset(text_buf, 'x', sizeof text_buf);
    scroll_reg = 7;
    display_init();
    model_reset();
    check_screen("init");
    if (scroll_reg != 0) {
        errors++;
        printf("FAILED: scroll %u after init\n", (unsigned) scroll_reg);
    }

    // Typing and backspace
    puts_both("emx", 0);
    check_screen("typing");
    backspace_both();
    check_screen("backspace");
    backspace_both();
    backspace_both();
    backspace_both();   // at column 0: nothing happens
    check_screen("backspace at column 0");
    puts_both("em", 0);

    // Enter: "emily" with "ily" green, then a new "em" line
    enter("em", "ily");
    check_screen("enter");
    for (int i = 0; i < 2; i++) {
        backspace_both();
    }
    puts_both("ja", 0);
    enter("ja", "xon");
    enter("ja", "");            // empty generated word
    enter("", "zoey");          // empty prefix
    check_screen("enters");

    // Fill past the bottom: the screen scrolls one row per line, many
    // times round the 15-row buffer
    for (int i = 0; i < 1000; i++) {
        snprintf(text, sizeof text, "line %d", i);
        newline_both();
        puts_both(text, i & 1);
        check_screen("scrolling");
    }
    enter("kri", "sten");
    check_screen("enter after scrolling");

    // A line longer than 40 cells wraps onto the next row
    newline_both();
    for (int i = 0; i < 95; i++) {
        putc_both((char) ('a' + i % 26), i >= 50);
    }
    check_screen("wrap");
    backspace_both();
    check_screen("backspace after wrap");

    printf("display: %d SPI writes, %d lines, scroll %u\n", n_writes,
           n_lines, (unsigned) scroll_reg);
    if (errors == 0) {
        printf("TEST PASSED\n");
    } else {
        printf("TEST FAILED\n");
    }
    return errors != 0;
}
