// ps2_decode_test.c
// Host-side test of the PS/2 frame and scan code decoder on synthetic bit
// streams. Build and run from the repository root:
//   gcc -std=c99 -Wall -Wextra -I mcu/src mcu/test/ps2_decode_test.c
//       mcu/src/ps2_decode.c -o ps2_decode_test && ./ps2_decode_test

#include <stdio.h>

#include "ps2_decode.h"

#define BIT_US 80
#define BYTE_GAP_US 500
#define KEY_GAP_US 50000

static ps2_frame_t frame;
static ps2_keys_t keys;
static uint32_t now_us;
static int errors;
static char typed[64];
static int ntyped;

static void check(int ok, const char *msg) {
    if (!ok) {
        errors++;
        printf("FAILED: %s\n", msg);
    }
}

static void clock_bit(int bit) {
    now_us += BIT_US;
    int byte = ps2_frame_bit(&frame, bit, now_us);
    if (byte >= 0) {
        char key = ps2_keys_code(&keys, (uint8_t) byte);
        if (key != 0 && ntyped < 63) {
            typed[ntyped++] = key;
            typed[ntyped] = 0;
        }
    }
}

static void send_frame(uint8_t data, int bad_start, int bad_parity,
                       int bad_stop) {
    int ones = 0;
    for (int i = 0; i < 8; i++) {
        ones += (data >> i) & 1;
    }
    clock_bit(bad_start);
    for (int i = 0; i < 8; i++) {
        clock_bit((data >> i) & 1);
    }
    clock_bit((ones % 2 == 0) ^ bad_parity);
    clock_bit(!bad_stop);
    now_us += BYTE_GAP_US;
}

static void send(uint8_t data) {
    send_frame(data, 0, 0, 0);
}

static void press(uint8_t code) {
    send(code);
    now_us += KEY_GAP_US;
}

static void release(uint8_t code) {
    send(0xF0);
    send(code);
    now_us += KEY_GAP_US;
}

static void reset(void) {
    ps2_frame_init(&frame);
    ps2_keys_init(&keys);
    ntyped = 0;
    typed[0] = 0;
}

static int typed_is(const char *s) {
    for (int i = 0; ; i++) {
        if (typed[i] != s[i]) {
            return 0;
        }
        if (s[i] == 0) {
            return 1;
        }
    }
}

int main(void) {
    static const uint8_t letters[26] = {
        0x1C, 0x32, 0x21, 0x23, 0x24, 0x2B, 0x34, 0x33, 0x43, 0x3B, 0x42,
        0x4B, 0x3A, 0x31, 0x44, 0x4D, 0x15, 0x2D, 0x1B, 0x2C, 0x3C, 0x2A,
        0x1D, 0x22, 0x35, 0x1A
    };

    reset();
    for (int i = 0; i < 26; i++) {
        press(letters[i]);
        release(letters[i]);
    }
    check(typed_is("abcdefghijklmnopqrstuvwxyz"), "all letters");
    check(frame.dropped == 0, "no drops on clean letters");

    reset();
    press(0x5A);
    release(0x5A);
    press(0x66);
    release(0x66);
    check(typed_is("\n\b"), "Enter and Backspace");

    reset();
    press(0x1C);
    press(0x1C);
    press(0x1C);
    release(0x1C);
    press(0x1C);
    release(0x1C);
    check(typed_is("aa"), "auto-repeat ignored until release");

    reset();
    send(0xE0);
    press(0x75);
    send(0xE0);
    release(0x75);
    press(0x75);
    release(0x75);
    check(typed_is(""), "E0-prefixed keys and unmapped codes ignored");
    press(0x1C);
    release(0x1C);
    check(typed_is("a"), "decoding continues after E0 keys");

    reset();
    send_frame(0x1C, 0, 1, 0);
    check(typed_is("") && frame.dropped == 1, "parity error dropped");
    send_frame(0x1C, 1, 0, 0);
    check(typed_is("") && frame.dropped == 2, "bad start bit dropped");
    send_frame(0x1C, 0, 0, 1);
    check(typed_is("") && frame.dropped == 3, "bad stop bit dropped");
    press(0x32);
    check(typed_is("b"), "clean frame after errors");

    reset();
    for (int i = 0; i < 5; i++) {
        clock_bit(1);
    }
    now_us += 3000;
    press(0x21);
    check(typed_is("c") && frame.dropped == 1,
          "timeout discards a partial frame");

    reset();
    now_us = 0xFFFFFFFFu - 400;
    press(0x23);
    check(typed_is("d") && frame.dropped == 0,
          "timestamps wrap without a false timeout");

    if (errors == 0) {
        printf("PASSED\n");
    } else {
        printf("FAILED: %d errors\n", errors);
    }
    return errors != 0;
}
