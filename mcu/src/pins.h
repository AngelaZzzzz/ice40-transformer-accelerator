// pins.h
// MCU pin assignments. PB6 and PB7 are tied to PA6 and PA5 by Nucleo-32
// solder bridges SB16 and SB18 and must remain unconfigured.

#ifndef PINS_H
#define PINS_H

#include "STM32L432KC_GPIO.h"

#define FPGA_SCK_PIN  PA5
#define FPGA_MOSI_PIN PB5
#define FPGA_MISO_PIN PB4
#define FPGA_CS_PIN   PA11
#define FPGA_DONE_PIN PA6

#define PS2_CLK_PIN   PA8
#define PS2_DATA_PIN  PB1

#endif // PINS_H
