// STM32L432KC_EXTI.c
// Source code for EXTI functions

#include "STM32L432KC_EXTI.h"
#include "STM32L432KC_GPIO.h"

void extiEnableEdges(int gpio_pin, IRQn_Type irq) {
    // Pin n can only drive EXTI line n
    int line = gpioPinOffset(gpio_pin);

    // Lines 0-3 are in EXTICR[0], 4-7 in EXTICR[1], etc.
    int reg = line / EXTICR_LINES_PER_REG;

    // Bit position of the line's field in that register
    int shift = EXTICR_FIELD_WIDTH * (line % EXTICR_LINES_PER_REG);

    // Enable SYSCFG clock domain in RCC
    RCC->APB2ENR |= RCC_APB2ENR_SYSCFGEN;

    // Route the line to the pin's port
    // Clear the 3-bit field and then write the port code
    // GPIO_PORT_A/B/C equal 000/001/010, so PB1 writes 001 to EXTICR[0] bits 6:4.
    SYSCFG->EXTICR[reg] &= ~(EXTICR_FIELD_MASK << shift);
    SYSCFG->EXTICR[reg] |= (uint32_t)gpioPinToPort(gpio_pin) << shift;

    // Unmask the line and trigger on both edges
    EXTI->IMR1  |= 1U << line;   // Interrupt mask: 1 = enabled
    EXTI->RTSR1 |= 1U << line;   // Rising edge trigger
    EXTI->FTSR1 |= 1U << line;   // Falling edge trigger

    // Enable the line's interrupt in NVIC_ISER
    NVIC_EnableIRQ(irq);
}
