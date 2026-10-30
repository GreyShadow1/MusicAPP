/*
 * Configurazione statica di libFLAC 1.5.0 (solo decoder) per arm64.
 * Sostituisce il config.h che CMake/autotools genererebbero: non serve alcun
 * passaggio di configurazione sul Mac di compilazione.
 */
#ifndef CFLAC_CONFIG_H
#define CFLAC_CONFIG_H

#define CPU_IS_BIG_ENDIAN 0
#define ENABLE_64_BIT_WORDS 1

#define FLAC__HAS_OGG 0
#define FLAC__HAS_X86INTRIN 0
#define FLAC__HAS_NEONINTRIN 0
#define FLAC__HAS_A64NEONINTRIN 0

#define HAVE_BSWAP16 1
#define HAVE_BSWAP32 1
#define HAVE_FSEEKO 1
#define HAVE_INTTYPES_H 1
#define HAVE_LROUND 1
#define HAVE_STDINT_H 1
#define HAVE_STDLIB_H 1
#define HAVE_STRING_H 1
#define HAVE_SYS_PARAM_H 1
#define HAVE_SYS_STAT_H 1
#define HAVE_SYS_TYPES_H 1
#define HAVE_UNISTD_H 1

#define PACKAGE_VERSION "1.5.0"
#define SIZEOF_VOIDP 8

#endif
