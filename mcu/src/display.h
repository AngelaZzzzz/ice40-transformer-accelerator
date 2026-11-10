// display.h
// VGA text display control through the FPGA text buffer

#ifndef DISPLAY_H
#define DISPLAY_H

void display_init(void);
void display_putc(char c, int generated);
void display_backspace(void);
void display_newline(void);

#endif // DISPLAY_H
