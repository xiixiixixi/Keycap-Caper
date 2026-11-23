#include "Vorbis.h"
#define STB_VORBIS_NO_STDIO
#define STB_VORBIS_NO_PUSHDATA_API
#define STB_VORBIS_NO_COMMENTS
#include "../ThirdParty/stb_vorbis.c"

int16_t *caper_decode_vorbis(const uint8_t *encoded, int count, int *frames, int *channels, int *sample_rate)
{
    if (!encoded || count <= 0 || count > 16 * 1024 * 1024) return NULL;
    stb_vorbis *stream = stb_vorbis_open_memory(encoded, count, NULL, NULL);
    if (!stream) return NULL;
    stb_vorbis_info info = stb_vorbis_get_info(stream);
    unsigned int length = stb_vorbis_stream_length_in_samples(stream);
    int16_t *pcm = NULL;
    if (info.channels >= 1 && info.channels <= 2 && info.sample_rate >= 8000 && info.sample_rate <= 96000
        && length > 0 && length <= info.sample_rate * 180
        && length <= (32 * 1024 * 1024) / (sizeof(*pcm) * info.channels)) {
        int samples = (int)length * info.channels;
        pcm = malloc(sizeof(*pcm) * samples);
        if (pcm) {
            *frames = stb_vorbis_get_samples_short_interleaved(stream, info.channels, pcm, samples);
            if (*frames <= 0) { free(pcm); pcm = NULL; }
            *channels = info.channels;
            *sample_rate = (int)info.sample_rate;
        }
    }
    stb_vorbis_close(stream);
    return pcm;
}
