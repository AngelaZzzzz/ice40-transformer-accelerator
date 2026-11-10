// fpga.c
// SPI command interface to the FPGA accelerator

#include "fpga.h"

// TODO(zach): implement per docs/interface_spec.md section 7

void fpga_init(void) {}

void fpga_write_spram(uint16_t addr, const uint8_t *bytes, uint32_t nwords) {}

void fpga_read_spram(uint16_t addr, uint8_t *bytes, uint32_t nwords) {}

void fpga_write_prog(uint8_t addr, const uint8_t *bytes, uint32_t ninstr) {}

void fpga_run(uint8_t letter, uint8_t pos) {}

int fpga_done(void) { return 0; }

void fpga_read_scores(int16_t scores[27]) {}

void fpga_write_chars(uint16_t cell, const uint8_t *bytes, int n) {}

void fpga_scroll(uint8_t offset) {}
