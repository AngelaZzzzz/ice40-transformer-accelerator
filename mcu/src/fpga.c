// fpga.c
// SPI command interface to the FPGA accelerator (docs/interface_spec.md
// section 7). SPI1 runs as master in mode 0, MSB first, 8-bit frames, at
// 80 MHz / 16 = 5 MHz, on SCK PA5, MISO PB4 and MOSI PB5, with software
// chip select on PA11. The FPGA samples CS through a two-flop synchronizer
// at 48 MHz, so CS is held low 1 us before the first byte and high 1 us
// after each command.

#include "fpga.h"
#include "STM32L432KC.h"
#include "pins.h"
#include "timing.h"

#define CMD_WRITE_SPRAM 0x01
#define CMD_READ_SPRAM  0x02
#define CMD_WRITE_PROG  0x03
#define CMD_RUN         0x04
#define CMD_READ_SCORES 0x05
#define CMD_WRITE_CHAR  0x06
#define CMD_SCROLL      0x07

// SCK = 80 MHz / 2^(FPGA_SPI_BR + 1). spi_slave requires SCK <= fclk / 8:
// if the FPGA core clock falls back to 24 MHz, use 4 (divider 32, 2.5 MHz).
#define FPGA_SPI_BR 3

#define N_SCORES       27
#define CS_SETUP_US    1
#define CS_HIGH_US     1

static void cs_low(void) {
    digitalWrite(FPGA_CS_PIN, 0);
    delay_us(CS_SETUP_US);
}

static void cs_high(void) {
    while (SPI1->SR & SPI_SR_BSY);
    digitalWrite(FPGA_CS_PIN, 1);
    delay_us(CS_HIGH_US);
}

static uint8_t xfer(uint8_t byte) {
    return (uint8_t) spiSendReceive((char) byte);
}

static void send_addr14(uint16_t addr) {
    xfer((uint8_t) (addr >> 8));
    xfer((uint8_t) addr);
}

void fpga_init(void) {
    timing_init();

    RCC->AHB2ENR |= RCC_AHB2ENR_GPIOAEN | RCC_AHB2ENR_GPIOBEN;
    RCC->APB2ENR |= RCC_APB2ENR_SPI1EN;

    GPIOA->AFR[0] = (GPIOA->AFR[0] & ~GPIO_AFRL_AFSEL5) |
                    _VAL2FLD(GPIO_AFRL_AFSEL5, 5);
    GPIOB->AFR[0] = (GPIOB->AFR[0] & ~(GPIO_AFRL_AFSEL4 | GPIO_AFRL_AFSEL5)) |
                    _VAL2FLD(GPIO_AFRL_AFSEL4, 5) |
                    _VAL2FLD(GPIO_AFRL_AFSEL5, 5);
    GPIOA->OSPEEDR |= GPIO_OSPEEDR_OSPEED5;
    pinMode(FPGA_SCK_PIN, GPIO_ALT);
    pinMode(FPGA_MISO_PIN, GPIO_ALT);
    pinMode(FPGA_MOSI_PIN, GPIO_ALT);

    digitalWrite(FPGA_CS_PIN, 1);
    pinMode(FPGA_CS_PIN, GPIO_OUTPUT);

    pinMode(FPGA_DONE_PIN, GPIO_INPUT);
    GPIOA->PUPDR = (GPIOA->PUPDR & ~GPIO_PUPDR_PUPD6) |
                   _VAL2FLD(GPIO_PUPDR_PUPD6, 2);

    SPI1->CR1 = 0;
    SPI1->CR2 = _VAL2FLD(SPI_CR2_DS, 7) | SPI_CR2_FRXTH;
    SPI1->CR1 = SPI_CR1_MSTR | _VAL2FLD(SPI_CR1_BR, FPGA_SPI_BR) |
                SPI_CR1_SSM | SPI_CR1_SSI;
    SPI1->CR1 |= SPI_CR1_SPE;
}

void fpga_write_spram(uint16_t addr, const uint8_t *bytes, uint32_t nwords) {
    cs_low();
    xfer(CMD_WRITE_SPRAM);
    send_addr14(addr);
    for (uint32_t i = 0; i < 8 * nwords; i++) {
        xfer(bytes[i]);
    }
    cs_high();
}

void fpga_read_spram(uint16_t addr, uint8_t *bytes, uint32_t nwords) {
    cs_low();
    xfer(CMD_READ_SPRAM);
    send_addr14(addr);
    xfer(0);
    for (uint32_t i = 0; i < 8 * nwords; i++) {
        bytes[i] = xfer(0);
    }
    cs_high();
}

void fpga_write_prog(uint8_t addr, const uint8_t *bytes, uint32_t ninstr) {
    cs_low();
    xfer(CMD_WRITE_PROG);
    xfer(addr);
    for (uint32_t i = 0; i < 6 * ninstr; i++) {
        xfer(bytes[i]);
    }
    cs_high();
}

void fpga_run(uint8_t letter, uint8_t pos) {
    cs_low();
    xfer(CMD_RUN);
    xfer(letter);
    xfer(pos);
    cs_high();
}

int fpga_done(void) {
    return digitalRead(FPGA_DONE_PIN);
}

int fpga_wait_done(uint32_t timeout_us) {
    uint32_t start = timing_cycles();
    while (!fpga_done()) {
        if (timing_elapsed_us(start) >= timeout_us) {
            return fpga_done();
        }
    }
    return 1;
}

void fpga_read_scores(int16_t scores[27]) {
    cs_low();
    xfer(CMD_READ_SCORES);
    xfer(0);
    for (int i = 0; i < N_SCORES; i++) {
        uint16_t hi = xfer(0);
        uint16_t lo = xfer(0);
        scores[i] = (int16_t) ((hi << 8) | lo);
    }
    cs_high();
}

void fpga_write_chars(uint16_t cell, const uint8_t *bytes, int n) {
    cs_low();
    xfer(CMD_WRITE_CHAR);
    send_addr14(cell);
    for (int i = 0; i < n; i++) {
        xfer(bytes[i]);
    }
    cs_high();
}

void fpga_scroll(uint8_t offset) {
    cs_low();
    xfer(CMD_SCROLL);
    xfer(offset);
    cs_high();
}
