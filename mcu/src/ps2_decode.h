// ps2_decode.h
// Hardware-independent PS/2 frame assembly and scan code set 2 decoding

#ifndef PS2_DECODE_H
#define PS2_DECODE_H

#include <stdint.h>

#define PS2_TIMEOUT_US 2000

typedef struct {
    uint16_t frame;
    uint8_t nbits;
    uint32_t last_us;
    uint32_t dropped;
} ps2_frame_t;

typedef struct {
    uint8_t release;
    uint8_t extended;
    uint8_t held[32];
} ps2_keys_t;

void ps2_frame_init(ps2_frame_t *f);
int ps2_frame_bit(ps2_frame_t *f, int bit, uint32_t now_us);
void ps2_keys_init(ps2_keys_t *k);
char ps2_keys_code(ps2_keys_t *k, uint8_t code);

#endif // PS2_DECODE_H
