// model_load.h
// Loads model weights and program into the FPGA

#ifndef MODEL_LOAD_H
#define MODEL_LOAD_H

#include <stdint.h>

void model_write_weights(void);
void model_write_program(void);
void model_load(void);
uint32_t model_verify_weights(void);
const uint8_t *model_word(uint16_t addr);
uint32_t model_nwords(void);
int model_logit_frac(void);

#endif // MODEL_LOAD_H
