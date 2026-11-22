// display.c
// VGA text display control through the FPGA text buffer
//
// Interface spec sections 8 and 9. The screen is 40 x 15 cells; screen
// row r shows text-buffer row (r + scroll) mod 15, and a cell byte is
// {color, char[6:0]} with color 1 = generated (green). The cursor moves
// down one screen row per line; once it is on the last row, a new line
// clears the memory row at the top of the screen and advances scroll,
// so that row reappears, empty, at the bottom.

#include "display.h"

#include <stdint.h>

#include "fpga.h"

#define COLS 40
#define ROWS 15
#define BLANK ((uint8_t) ' ')
#define GENERATED 0x80u

static int row;         // screen row of the cursor, 0 to ROWS - 1
static int col;         // cursor column, 0 to COLS
static uint8_t scroll;  // memory row shown on screen row 0

// Text-buffer cell of screen row r (r = ROWS is the row after the last),
// column c
static uint16_t cell(int r, int c) {
    return (uint16_t) (((r + scroll) % ROWS) * COLS + c);
}

static void clear_row(int r) {
    uint8_t blanks[COLS];

    for (int i = 0; i < COLS; i++) {
        blanks[i] = BLANK;
    }
    fpga_write_chars(cell(r, 0), blanks, COLS);
}

void display_init(void) {
    scroll = 0;
    fpga_scroll(scroll);
    for (int r = 0; r < ROWS; r++) {
        clear_row(r);
    }
    row = 0;
    col = 0;
}

void display_putc(char c, int generated) {
    uint8_t b = (uint8_t) ((uint8_t) c & 0x7Fu);

    if (generated) {
        b |= GENERATED;
    }
    if (col == COLS) {
        display_newline();
    }
    fpga_write_chars(cell(row, col), &b, 1);
    col++;
}

void display_backspace(void) {
    uint8_t b = BLANK;

    if (col == 0) {
        return;
    }
    col--;
    fpga_write_chars(cell(row, col), &b, 1);
}

void display_newline(void) {
    clear_row(row + 1);
    if (row < ROWS - 1) {
        row++;
    } else {
        scroll = (uint8_t) ((scroll + 1) % ROWS);
        fpga_scroll(scroll);
    }
    col = 0;
}
