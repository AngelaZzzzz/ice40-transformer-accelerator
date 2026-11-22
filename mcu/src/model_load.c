// model_load.c
// Loads model weights and program into the FPGA (docs/interface_spec.md
// section 7). This is the only file that includes model_weights.h, which
// defines the image arrays.

#include "model_load.h"
#include "fpga.h"
#include "model_weights.h"

#define VERIFY_CHUNK_WORDS 128

void model_write_weights(void) {
    fpga_write_spram(0, model_spram, MODEL_NWORDS);
}

void model_write_program(void) {
    fpga_write_prog(0, model_prog, MODEL_NINSTR);
}

void model_load(void) {
    model_write_weights();
    model_write_program();
}

uint32_t model_verify_weights(void) {
    static uint8_t buf[8 * VERIFY_CHUNK_WORDS];
    uint32_t mismatches = 0;

    for (uint32_t word = 0; word < MODEL_NWORDS; word += VERIFY_CHUNK_WORDS) {
        uint32_t nwords = MODEL_NWORDS - word;
        if (nwords > VERIFY_CHUNK_WORDS) {
            nwords = VERIFY_CHUNK_WORDS;
        }
        fpga_read_spram((uint16_t) word, buf, nwords);
        for (uint32_t i = 0; i < 8 * nwords; i++) {
            mismatches += (buf[i] != model_spram[8 * word + i]);
        }
    }
    return mismatches;
}

const uint8_t *model_word(uint16_t addr) {
    return &model_spram[8u * addr];
}

uint32_t model_nwords(void) {
    return MODEL_NWORDS;
}

int model_logit_frac(void) {
    return MODEL_LOGIT_FRAC;
}
