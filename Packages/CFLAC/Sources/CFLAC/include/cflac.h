/*
 * API C minima sopra libFLAC, pensata per essere chiamata da Swift.
 *
 * libFLAC lavora a "push" (consegna un blocco alla volta in una callback);
 * il lettore audio ha invece bisogno di chiedere N campioni quando servono.
 * Questo strato converte il modello e nasconde tutti i tipi di libFLAC.
 */
#ifndef CFLAC_H
#define CFLAC_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define CFLAC_OK 0
#define CFLAC_ERR_OPEN (-1)            /* file assente o illeggibile */
#define CFLAC_ERR_NOT_FLAC (-2)        /* non è uno stream FLAC valido */
#define CFLAC_ERR_MEMORY (-3)
#define CFLAC_ERR_DECODE (-4)          /* errore non recuperabile durante la decodifica */
#define CFLAC_ERR_CHANNELS (-5)        /* solo mono e stereo sono riproducibili */
#define CFLAC_ERR_SEEK (-6)
#define CFLAC_ERR_MD5 (-7)             /* audio decodificato diverso dalla firma MD5 */

typedef struct {
    uint32_t sample_rate;
    uint32_t channels;
    uint32_t bits_per_sample;
    uint64_t total_frames;             /* 0 se il file non lo dichiara */
} cflac_info;

typedef struct cflac_stream cflac_stream;

/* Apre un file e legge l'intestazione. Restituisce NULL e valorizza *status in caso di errore. */
cflac_stream *cflac_stream_open(const char *utf8_path, cflac_info *info_out, int32_t *status);

/*
 * Decodifica fino a `frames` frame in `channels_out` (un puntatore per canale,
 * float32 in [-1, 1)). Restituisce i frame scritti: 0 significa fine del file,
 * un valore negativo è un codice CFLAC_ERR_*.
 * I blocchi danneggiati non interrompono la lettura: libFLAC cerca il blocco
 * valido successivo e l'evento viene contato in cflac_stream_error_count().
 */
int64_t cflac_stream_read(cflac_stream *stream, float *const *channels_out, uint32_t frames);

/* Posiziona la lettura sul frame indicato. Restituisce CFLAC_OK o CFLAC_ERR_SEEK. */
int32_t cflac_stream_seek(cflac_stream *stream, uint64_t frame);

/* Numero di errori di stream segnalati da libFLAC dall'apertura. */
uint32_t cflac_stream_error_count(const cflac_stream *stream);

void cflac_stream_close(cflac_stream *stream);

typedef struct {
    cflac_info info;
    uint32_t comment_count;
    char **comments;                   /* stringhe UTF-8 "CHIAVE=valore" */
    uint8_t *picture_data;             /* copertina: preferisce il tipo "front cover" */
    size_t picture_size;
    char *picture_mime;
} cflac_metadata;

/* Legge intestazione, tag e copertina senza decodificare l'audio. */
int32_t cflac_metadata_read(const char *utf8_path, cflac_metadata *out);
void cflac_metadata_free(cflac_metadata *metadata);

/*
 * Decodifica l'intero file e confronta l'audio con la firma MD5 di STREAMINFO.
 * Se il file non contiene una firma, verifica solo che sia decodificabile.
 * *frames_out riceve i frame decodificati. Può richiedere qualche secondo.
 */
int32_t cflac_verify_file(const char *utf8_path, uint64_t *frames_out);

#ifdef __cplusplus
}
#endif

#endif
