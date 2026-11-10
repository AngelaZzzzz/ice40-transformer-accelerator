// main.c
// Transformer text generator host: keyboard input, FPGA inference, sampling
// and display

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

// TODO(zach): implement test modes and application main loop

int main(void) {
    while (1) {
    }
}
