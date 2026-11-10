// ps2.h
// PS/2 keyboard receiver and scan code set 2 decoder

#ifndef PS2_H
#define PS2_H

#include <stdint.h>

void ps2_init(void);
int ps2_get(char *key);
uint32_t ps2_dropped(void);

#endif // PS2_H
