// ps2.c
// PS/2 keyboard receiver: EXTI line 8 interrupts on falling edges of the
// PS/2 clock (PA8), sampling data (PB1) and timestamping each edge with
// TIM2 free-running at 1 MHz. Decoded keys go into a ring buffer.

#include "ps2.h"
#include "ps2_decode.h"
#include "STM32L432KC.h"
#include "pins.h"

#define RING_SIZE 32

static volatile char ring[RING_SIZE];
static volatile uint8_t head;
static volatile uint8_t tail;
static ps2_frame_t frame;
static ps2_keys_t keys;

void ps2_init(void) {
    ps2_frame_init(&frame);
    ps2_keys_init(&keys);
    head = 0;
    tail = 0;

    gpioEnable(GPIO_PORT_A);
    gpioEnable(GPIO_PORT_B);
    pinMode(PS2_CLK_PIN, GPIO_INPUT);
    pinMode(PS2_DATA_PIN, GPIO_INPUT);
    GPIOA->PUPDR &= ~GPIO_PUPDR_PUPD8;
    GPIOB->PUPDR &= ~GPIO_PUPDR_PUPD1;

    RCC->APB1ENR1 |= RCC_APB1ENR1_TIM2EN;
    TIM2->PSC = SystemCoreClock / 1000000 - 1;
    TIM2->ARR = 0xFFFFFFFF;
    TIM2->EGR = TIM_EGR_UG;
    TIM2->CR1 |= TIM_CR1_CEN;

    extiEnableEdges(PS2_CLK_PIN, EXTI9_5_IRQn);
    EXTI->RTSR1 &= ~(1U << gpioPinOffset(PS2_CLK_PIN));
    __enable_irq();
}

int ps2_get(char *key) {
    if (head == tail) {
        return 0;
    }
    *key = ring[tail];
    tail = (uint8_t) ((tail + 1) % RING_SIZE);
    return 1;
}

uint32_t ps2_dropped(void) {
    return frame.dropped;
}

void EXTI9_5_IRQHandler(void) {
    if (EXTI->PR1 & EXTI_PR1_PIF8) {
        EXTI->PR1 = EXTI_PR1_PIF8;

        int byte = ps2_frame_bit(&frame, digitalRead(PS2_DATA_PIN),
                                 TIM2->CNT);
        if (byte >= 0) {
            char key = ps2_keys_code(&keys, (uint8_t) byte);
            uint8_t next = (uint8_t) ((head + 1) % RING_SIZE);
            if (key != 0 && next != tail) {
                ring[head] = key;
                head = next;
            }
        }
    }
}
