// STM32L432KC_EXTI.h
// Header for EXTI functions

#ifndef STM32L4_EXTI_H
#define STM32L4_EXTI_H

#include <stdint.h>
#include <stm32l432xx.h>

///////////////////////////////////////////////////////////////////////////////
// Definitions
///////////////////////////////////////////////////////////////////////////////

// SYSCFG_EXTICRx layout (RM0394 9.2.3-9.2.6)
#define EXTICR_LINES_PER_REG 4     // Each EXTICR register holds 4 lines
#define EXTICR_FIELD_WIDTH   4     // Each line gets a 4-bit slot
#define EXTICR_FIELD_MASK    0x7U  // Only the low 3 bits of a slot are used

///////////////////////////////////////////////////////////////////////////////
// Function prototypes
///////////////////////////////////////////////////////////////////////////////

void extiEnableEdges(int gpio_pin, IRQn_Type irq);

#endif
