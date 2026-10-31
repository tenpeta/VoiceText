#ifndef VOICETEXT_NATIVE_SUPPORT_H
#define VOICETEXT_NATIVE_SUPPORT_H
#include <stddef.h>
#include <stdint.h>
// The caller owns the returned bytes and must release them with vt_free.
int vt_gzip(const uint8_t *input, size_t length, uint8_t **output, size_t *output_length);
int vt_gunzip(const uint8_t *input, size_t length, uint8_t **output, size_t *output_length);
void vt_free(void *pointer);
#endif
