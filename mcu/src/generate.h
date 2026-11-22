// generate.h
// Word completion: runs a prefix through the FPGA and samples the rest

#ifndef GENERATE_H
#define GENERATE_H

#define GENERATE_MAX_LETTERS 15
#define GENERATE_TIMEOUT     (-1)
#define GENERATE_INVALID     (-2)

int generate(const char *prefix, char *out, int max_out);

#endif // GENERATE_H
