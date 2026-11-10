// ps2_decode.c
// Hardware-independent PS/2 frame assembly and scan code set 2 decoding.
// A frame is 11 bits sampled on falling clock edges: start 0, 8 data bits
// LSB first, odd parity, stop 1. A gap of more than PS2_TIMEOUT_US between
// edges discards the partial frame. Bad and discarded frames count as
// dropped.

#include "ps2_decode.h"

#define SC_EXTENDED  0xE0
#define SC_RELEASE   0xF0
#define SC_ENTER     0x5A
#define SC_BACKSPACE 0x66

static const uint8_t letter_codes[26] = {
    0x1C, 0x32, 0x21, 0x23, 0x24, 0x2B, 0x34, 0x33, 0x43, 0x3B, 0x42, 0x4B,
    0x3A, 0x31, 0x44, 0x4D, 0x15, 0x2D, 0x1B, 0x2C, 0x3C, 0x2A, 0x1D, 0x22,
    0x35, 0x1A
};

void ps2_frame_init(ps2_frame_t *f) {
    f->frame = 0;
    f->nbits = 0;
    f->last_us = 0;
    f->dropped = 0;
}

int ps2_frame_bit(ps2_frame_t *f, int bit, uint32_t now_us) {
    if (f->nbits > 0 && now_us - f->last_us > PS2_TIMEOUT_US) {
        f->frame = 0;
        f->nbits = 0;
        f->dropped++;
    }
    f->last_us = now_us;
    f->frame |= (uint16_t) ((bit & 1) << f->nbits);
    f->nbits++;
    if (f->nbits < 11) {
        return -1;
    }

    uint16_t frame = f->frame;
    f->frame = 0;
    f->nbits = 0;

    uint8_t data = (uint8_t) (frame >> 1);
    int ones = (frame >> 9) & 1;
    for (int i = 0; i < 8; i++) {
        ones += (data >> i) & 1;
    }
    if ((frame & 1) != 0 || ((frame >> 10) & 1) != 1 || ones % 2 != 1) {
        f->dropped++;
        return -1;
    }
    return data;
}

void ps2_keys_init(ps2_keys_t *k) {
    k->release = 0;
    k->extended = 0;
    for (int i = 0; i < 32; i++) {
        k->held[i] = 0;
    }
}

char ps2_keys_code(ps2_keys_t *k, uint8_t code) {
    if (code == SC_EXTENDED) {
        k->extended = 1;
        return 0;
    }
    if (code == SC_RELEASE) {
        k->release = 1;
        return 0;
    }
    if (k->release) {
        if (!k->extended) {
            k->held[code >> 3] &= (uint8_t) ~(1 << (code & 7));
        }
        k->release = 0;
        k->extended = 0;
        return 0;
    }
    if (k->extended) {
        k->extended = 0;
        return 0;
    }
    if (k->held[code >> 3] & (1 << (code & 7))) {
        return 0;
    }
    k->held[code >> 3] |= (uint8_t) (1 << (code & 7));

    if (code == SC_ENTER) {
        return '\n';
    }
    if (code == SC_BACKSPACE) {
        return '\b';
    }
    for (int i = 0; i < 26; i++) {
        if (letter_codes[i] == code) {
            return (char) ('a' + i);
        }
    }
    return 0;
}
