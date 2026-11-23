#pragma once
#include <stdint.h>

// On success the caller owns the interleaved 16-bit PCM buffer.
int16_t *caper_decode_vorbis(const uint8_t *encoded, int count, int *frames, int *channels, int *sample_rate);
