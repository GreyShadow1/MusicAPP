#include "include/cflac.h"

#include <stdlib.h>
#include <string.h>

#include "FLAC/stream_decoder.h"

/* Dimensione massima di un blocco FLAC secondo RFC 9639. */
#define CFLAC_MAX_BLOCK_FRAMES 65535u
/* Limiti difensivi contro tag anomali in file danneggiati. */
#define CFLAC_MAX_COMMENTS 1024u
#define CFLAC_MAX_COMMENT_BYTES (64u * 1024u)
#define CFLAC_PICTURE_FRONT_COVER 3

struct cflac_stream {
    FLAC__StreamDecoder *decoder;
    cflac_info info;
    int has_info;
    int fatal;
    uint32_t error_count;
    float *block[2];
    uint32_t block_frames;
    uint32_t block_position;
};

/* ---- Lettura a blocchi ---- */

static FLAC__StreamDecoderWriteStatus stream_write(const FLAC__StreamDecoder *decoder,
                                                   const FLAC__Frame *frame,
                                                   const FLAC__int32 *const buffer[],
                                                   void *client_data) {
    (void)decoder;
    cflac_stream *s = (cflac_stream *)client_data;
    const uint32_t frames = frame->header.blocksize;
    const uint32_t bits = frame->header.bits_per_sample;

    if (frame->header.channels != s->info.channels || frames > CFLAC_MAX_BLOCK_FRAMES || bits == 0 || bits > 32) {
        s->fatal = 1;
        return FLAC__STREAM_DECODER_WRITE_STATUS_ABORT;
    }

    /* Divisione per 2^(bit-1): esatta in float32 fino a 24 bit. */
    const float scale = 1.0f / (float)(1ull << (bits - 1));
    for (uint32_t c = 0; c < s->info.channels; c++) {
        const FLAC__int32 *in = buffer[c];
        float *out = s->block[c];
        for (uint32_t i = 0; i < frames; i++) {
            out[i] = (float)in[i] * scale;
        }
    }
    s->block_frames = frames;
    s->block_position = 0;
    return FLAC__STREAM_DECODER_WRITE_STATUS_CONTINUE;
}

static void stream_metadata(const FLAC__StreamDecoder *decoder,
                            const FLAC__StreamMetadata *metadata,
                            void *client_data) {
    (void)decoder;
    cflac_stream *s = (cflac_stream *)client_data;
    if (metadata->type == FLAC__METADATA_TYPE_STREAMINFO) {
        s->info.sample_rate = metadata->data.stream_info.sample_rate;
        s->info.channels = metadata->data.stream_info.channels;
        s->info.bits_per_sample = metadata->data.stream_info.bits_per_sample;
        s->info.total_frames = metadata->data.stream_info.total_samples;
        s->has_info = 1;
    }
}

static void stream_error(const FLAC__StreamDecoder *decoder,
                         FLAC__StreamDecoderErrorStatus status,
                         void *client_data) {
    (void)decoder;
    (void)status;
    ((cflac_stream *)client_data)->error_count++;
}

cflac_stream *cflac_stream_open(const char *utf8_path, cflac_info *info_out, int32_t *status) {
    int32_t result = CFLAC_OK;
    cflac_stream *s = (cflac_stream *)calloc(1, sizeof(cflac_stream));
    if (s == NULL) {
        result = CFLAC_ERR_MEMORY;
        goto fail;
    }
    s->decoder = FLAC__stream_decoder_new();
    if (s->decoder == NULL) {
        result = CFLAC_ERR_MEMORY;
        goto fail;
    }

    FLAC__StreamDecoderInitStatus init = FLAC__stream_decoder_init_file(
        s->decoder, utf8_path, stream_write, stream_metadata, stream_error, s);
    if (init != FLAC__STREAM_DECODER_INIT_STATUS_OK) {
        result = init == FLAC__STREAM_DECODER_INIT_STATUS_ERROR_OPENING_FILE ? CFLAC_ERR_OPEN : CFLAC_ERR_MEMORY;
        goto fail;
    }
    if (!FLAC__stream_decoder_process_until_end_of_metadata(s->decoder) || !s->has_info ||
        s->info.sample_rate == 0 || s->info.channels == 0) {
        result = CFLAC_ERR_NOT_FLAC;
        goto fail;
    }
    if (info_out != NULL) {
        *info_out = s->info;
    }
    if (s->info.channels > 2) {
        result = CFLAC_ERR_CHANNELS;
        goto fail;
    }
    for (uint32_t c = 0; c < s->info.channels; c++) {
        s->block[c] = (float *)malloc(CFLAC_MAX_BLOCK_FRAMES * sizeof(float));
        if (s->block[c] == NULL) {
            result = CFLAC_ERR_MEMORY;
            goto fail;
        }
    }
    if (status != NULL) {
        *status = CFLAC_OK;
    }
    return s;

fail:
    cflac_stream_close(s);
    if (status != NULL) {
        *status = result;
    }
    return NULL;
}

/* Decodifica finché non c'è un blocco pronto. 1 = pronto, 0 = fine file, <0 = errore. */
static int32_t refill(cflac_stream *s) {
    for (;;) {
        if (s->fatal) {
            return CFLAC_ERR_DECODE;
        }
        switch (FLAC__stream_decoder_get_state(s->decoder)) {
            case FLAC__STREAM_DECODER_END_OF_STREAM:
                return 0;
            case FLAC__STREAM_DECODER_SEEK_ERROR:
            case FLAC__STREAM_DECODER_ABORTED:
            case FLAC__STREAM_DECODER_MEMORY_ALLOCATION_ERROR:
                return CFLAC_ERR_DECODE;
            default:
                break;
        }
        if (!FLAC__stream_decoder_process_single(s->decoder)) {
            return CFLAC_ERR_DECODE;
        }
        if (s->block_position < s->block_frames) {
            return 1;
        }
    }
}

int64_t cflac_stream_read(cflac_stream *stream, float *const *channels_out, uint32_t frames) {
    uint32_t done = 0;
    while (done < frames) {
        uint32_t available = stream->block_frames - stream->block_position;
        if (available == 0) {
            int32_t state = refill(stream);
            if (state < 0) {
                return done > 0 ? (int64_t)done : (int64_t)state;
            }
            if (state == 0) {
                break;
            }
            available = stream->block_frames - stream->block_position;
        }
        const uint32_t count = available < frames - done ? available : frames - done;
        for (uint32_t c = 0; c < stream->info.channels; c++) {
            memcpy(channels_out[c] + done, stream->block[c] + stream->block_position, count * sizeof(float));
        }
        stream->block_position += count;
        done += count;
    }
    return (int64_t)done;
}

int32_t cflac_stream_seek(cflac_stream *stream, uint64_t frame) {
    stream->block_frames = 0;
    stream->block_position = 0;
    if (FLAC__stream_decoder_seek_absolute(stream->decoder, frame)) {
        return CFLAC_OK;
    }
    /* Dopo un seek fallito libFLAC richiede un flush prima di poter proseguire. */
    if (FLAC__stream_decoder_get_state(stream->decoder) == FLAC__STREAM_DECODER_SEEK_ERROR) {
        FLAC__stream_decoder_flush(stream->decoder);
    }
    stream->block_frames = 0;
    stream->block_position = 0;
    return CFLAC_ERR_SEEK;
}

uint32_t cflac_stream_error_count(const cflac_stream *stream) {
    return stream->error_count;
}

void cflac_stream_close(cflac_stream *stream) {
    if (stream == NULL) {
        return;
    }
    if (stream->decoder != NULL) {
        FLAC__stream_decoder_finish(stream->decoder);
        FLAC__stream_decoder_delete(stream->decoder);
    }
    free(stream->block[0]);
    free(stream->block[1]);
    free(stream);
}

/* ---- Metadati ---- */

typedef struct {
    cflac_metadata *out;
    int has_info;
    int picture_is_front;
    int failed;
} metadata_context;

static FLAC__StreamDecoderWriteStatus metadata_write(const FLAC__StreamDecoder *decoder,
                                                     const FLAC__Frame *frame,
                                                     const FLAC__int32 *const buffer[],
                                                     void *client_data) {
    (void)decoder;
    (void)frame;
    (void)buffer;
    (void)client_data;
    return FLAC__STREAM_DECODER_WRITE_STATUS_CONTINUE;
}

static void metadata_error(const FLAC__StreamDecoder *decoder,
                           FLAC__StreamDecoderErrorStatus status,
                           void *client_data) {
    (void)decoder;
    (void)status;
    (void)client_data;
}

static char *copy_bytes(const void *bytes, size_t length) {
    char *copy = (char *)malloc(length + 1);
    if (copy != NULL) {
        memcpy(copy, bytes, length);
        copy[length] = '\0';
    }
    return copy;
}

static void metadata_comments(metadata_context *ctx, const FLAC__StreamMetadata_VorbisComment *vc) {
    cflac_metadata *out = ctx->out;
    if (out->comments != NULL) {
        return;
    }
    const uint32_t count = vc->num_comments < CFLAC_MAX_COMMENTS ? vc->num_comments : CFLAC_MAX_COMMENTS;
    if (count == 0) {
        return;
    }
    out->comments = (char **)calloc(count, sizeof(char *));
    if (out->comments == NULL) {
        ctx->failed = 1;
        return;
    }
    for (uint32_t i = 0; i < count; i++) {
        const FLAC__StreamMetadata_VorbisComment_Entry *entry = &vc->comments[i];
        if (entry->entry == NULL || entry->length > CFLAC_MAX_COMMENT_BYTES) {
            continue;
        }
        char *text = copy_bytes(entry->entry, entry->length);
        if (text == NULL) {
            ctx->failed = 1;
            return;
        }
        out->comments[out->comment_count++] = text;
    }
}

static void metadata_picture(metadata_context *ctx, const FLAC__StreamMetadata_Picture *picture) {
    cflac_metadata *out = ctx->out;
    const int is_front = picture->type == CFLAC_PICTURE_FRONT_COVER;
    if (picture->data == NULL || picture->data_length == 0) {
        return;
    }
    if (out->picture_data != NULL && (ctx->picture_is_front || !is_front)) {
        return;
    }
    uint8_t *data = (uint8_t *)copy_bytes(picture->data, picture->data_length);
    char *mime = copy_bytes(picture->mime_type, strlen(picture->mime_type));
    if (data == NULL || mime == NULL) {
        free(data);
        free(mime);
        ctx->failed = 1;
        return;
    }
    free(out->picture_data);
    free(out->picture_mime);
    out->picture_data = data;
    out->picture_size = picture->data_length;
    out->picture_mime = mime;
    ctx->picture_is_front = is_front;
}

static void metadata_block(const FLAC__StreamDecoder *decoder,
                           const FLAC__StreamMetadata *metadata,
                           void *client_data) {
    (void)decoder;
    metadata_context *ctx = (metadata_context *)client_data;
    switch (metadata->type) {
        case FLAC__METADATA_TYPE_STREAMINFO:
            ctx->out->info.sample_rate = metadata->data.stream_info.sample_rate;
            ctx->out->info.channels = metadata->data.stream_info.channels;
            ctx->out->info.bits_per_sample = metadata->data.stream_info.bits_per_sample;
            ctx->out->info.total_frames = metadata->data.stream_info.total_samples;
            ctx->has_info = 1;
            break;
        case FLAC__METADATA_TYPE_VORBIS_COMMENT:
            metadata_comments(ctx, &metadata->data.vorbis_comment);
            break;
        case FLAC__METADATA_TYPE_PICTURE:
            metadata_picture(ctx, &metadata->data.picture);
            break;
        default:
            break;
    }
}

int32_t cflac_metadata_read(const char *utf8_path, cflac_metadata *out) {
    memset(out, 0, sizeof(*out));
    metadata_context ctx;
    memset(&ctx, 0, sizeof(ctx));
    ctx.out = out;

    FLAC__StreamDecoder *decoder = FLAC__stream_decoder_new();
    if (decoder == NULL) {
        return CFLAC_ERR_MEMORY;
    }
    FLAC__stream_decoder_set_metadata_respond(decoder, FLAC__METADATA_TYPE_VORBIS_COMMENT);
    FLAC__stream_decoder_set_metadata_respond(decoder, FLAC__METADATA_TYPE_PICTURE);

    int32_t result = CFLAC_OK;
    FLAC__StreamDecoderInitStatus init = FLAC__stream_decoder_init_file(
        decoder, utf8_path, metadata_write, metadata_block, metadata_error, &ctx);
    if (init != FLAC__STREAM_DECODER_INIT_STATUS_OK) {
        result = init == FLAC__STREAM_DECODER_INIT_STATUS_ERROR_OPENING_FILE ? CFLAC_ERR_OPEN : CFLAC_ERR_MEMORY;
    } else if (!FLAC__stream_decoder_process_until_end_of_metadata(decoder) || !ctx.has_info) {
        result = CFLAC_ERR_NOT_FLAC;
    } else if (ctx.failed) {
        result = CFLAC_ERR_MEMORY;
    }
    FLAC__stream_decoder_finish(decoder);
    FLAC__stream_decoder_delete(decoder);

    if (result != CFLAC_OK) {
        cflac_metadata_free(out);
    }
    return result;
}

void cflac_metadata_free(cflac_metadata *metadata) {
    for (uint32_t i = 0; i < metadata->comment_count; i++) {
        free(metadata->comments[i]);
    }
    free(metadata->comments);
    free(metadata->picture_data);
    free(metadata->picture_mime);
    memset(metadata, 0, sizeof(*metadata));
}

/* ---- Verifica integrità ---- */

typedef struct {
    uint64_t frames;
    uint32_t errors;
} verify_context;

static FLAC__StreamDecoderWriteStatus verify_write(const FLAC__StreamDecoder *decoder,
                                                   const FLAC__Frame *frame,
                                                   const FLAC__int32 *const buffer[],
                                                   void *client_data) {
    (void)decoder;
    (void)buffer;
    ((verify_context *)client_data)->frames += frame->header.blocksize;
    return FLAC__STREAM_DECODER_WRITE_STATUS_CONTINUE;
}

static void verify_error(const FLAC__StreamDecoder *decoder,
                         FLAC__StreamDecoderErrorStatus status,
                         void *client_data) {
    (void)decoder;
    (void)status;
    ((verify_context *)client_data)->errors++;
}

int32_t cflac_verify_file(const char *utf8_path, uint64_t *frames_out) {
    verify_context ctx = {0, 0};
    FLAC__StreamDecoder *decoder = FLAC__stream_decoder_new();
    if (decoder == NULL) {
        return CFLAC_ERR_MEMORY;
    }
    FLAC__stream_decoder_set_md5_checking(decoder, true);

    FLAC__StreamDecoderInitStatus init = FLAC__stream_decoder_init_file(
        decoder, utf8_path, verify_write, NULL, verify_error, &ctx);
    if (init != FLAC__STREAM_DECODER_INIT_STATUS_OK) {
        FLAC__stream_decoder_delete(decoder);
        return init == FLAC__STREAM_DECODER_INIT_STATUS_ERROR_OPENING_FILE ? CFLAC_ERR_OPEN : CFLAC_ERR_MEMORY;
    }

    const FLAC__bool decoded = FLAC__stream_decoder_process_until_end_of_stream(decoder);
    const FLAC__bool md5_matches = FLAC__stream_decoder_finish(decoder);
    FLAC__stream_decoder_delete(decoder);

    if (frames_out != NULL) {
        *frames_out = ctx.frames;
    }
    if (!decoded || ctx.errors > 0) {
        return ctx.frames == 0 ? CFLAC_ERR_NOT_FLAC : CFLAC_ERR_DECODE;
    }
    return md5_matches ? CFLAC_OK : CFLAC_ERR_MD5;
}
