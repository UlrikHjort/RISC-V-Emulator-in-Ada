/* **************************************************************************
 *          RISC-V Emulator - RFC 1952 gzip compress / decompress
 *
 *           Copyright (C) 2026 By Ulrik Hørlyk Hjort
 *
 * Permission is hereby granted, free of charge, to any person obtaining
 * a copy of this software and associated documentation files (the
 * "Software"), to deal in the Software without restriction, including
 * without limitation the rights to use, copy, modify, merge, publish,
 * distribute, sublicense, and/or sell copies of the Software, and to
 * permit persons to whom the Software is furnished to do so, subject to
 * the following conditions:
 *
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 * NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
 * LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
 * OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
 * WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 * **************************************************************************/

/* gzip.c -- RFC 1952 gzip compress / decompress
 * By Ulrik Hørlyk Hjort 2026
 *
 * gzip_compress  : wraps raw deflate stored-block stream in a gzip envelope.
 * gzip_decompress: strips the gzip envelope and calls deflate_decompress().
 *
 * CRC-32 uses the reflected polynomial 0xEDB88320, init=0xFFFFFFFF,
 * final XOR 0xFFFFFFFF -- the same variant used in gzip, Ethernet, ZIP, PNG.
 */

#include "gzip.h"
#include "deflate.h"   /* deflate_decompress() */
#include <stddef.h>

/* -------------------------------------------------------------------------
 * CRC-32 (poly 0xEDB88320, reflected)
 * We build the 256-entry table on first use via a static flag.
 * -------------------------------------------------------------------------*/

static uint32_t crc32_table[256];
static int      crc32_table_ready = 0;

static void crc32_build_table(void)
{
    uint32_t i, c, j;
    for (i = 0; i < 256; i++) {
        c = i;
        for (j = 0; j < 8; j++)
            c = (c & 1u) ? ((c >> 1) ^ 0xEDB88320u) : (c >> 1);
        crc32_table[i] = c;
    }
    crc32_table_ready = 1;
}

/* Compute CRC-32 of data[0..len-1]. */
static uint32_t crc32_compute(const uint8_t *data, uint32_t len)
{
    uint32_t c = 0xFFFFFFFFu;
    if (!crc32_table_ready)
        crc32_build_table();
    while (len--)
        c = (c >> 8) ^ crc32_table[(c ^ *data++) & 0xFFu];
    return c ^ 0xFFFFFFFFu;
}

/* -------------------------------------------------------------------------
 * Helpers to write little-endian 16-bit and 32-bit values
 * -------------------------------------------------------------------------*/

static void put_le16(uint8_t *p, uint16_t v)
{
    p[0] = (uint8_t)(v & 0xFFu);
    p[1] = (uint8_t)((v >> 8) & 0xFFu);
}

static void put_le32(uint8_t *p, uint32_t v)
{
    p[0] = (uint8_t)(v & 0xFFu);
    p[1] = (uint8_t)((v >> 8) & 0xFFu);
    p[2] = (uint8_t)((v >> 16) & 0xFFu);
    p[3] = (uint8_t)((v >> 24) & 0xFFu);
}

static uint32_t get_le32(const uint8_t *p)
{
    return (uint32_t)p[0]
         | ((uint32_t)p[1] << 8)
         | ((uint32_t)p[2] << 16)
         | ((uint32_t)p[3] << 24);
}

/* -------------------------------------------------------------------------
 * gzip_compress
 *
 * Gzip format (RFC 1952):
 *   [0]  ID1 = 0x1F
 *   [1]  ID2 = 0x8B
 *   [2]  CM  = 8  (deflate)
 *   [3]  FLG = 0  (no extra fields)
 *   [4..7]  MTIME = 0
 *   [8]  XFL = 0
 *   [9]  OS  = 0xFF (unknown)
 *   [10..] deflate stream
 *   [n..n+3] CRC32  (little-endian)
 *   [n+4..n+7] ISIZE = original size mod 2^32 (little-endian)
 *
 * The deflate stream is composed of stored blocks (BTYPE=00, RFC 1951 Sec.3.2.4).
 * Each stored block can hold at most 65535 bytes.
 * Block format:
 *   1 byte:  BFINAL (1 bit, 0 or 1) | BTYPE (2 bits = 00) | padding (5 bits = 0)
 *   2 bytes: LEN  (16-bit little-endian)
 *   2 bytes: NLEN = one's complement of LEN (16-bit little-endian)
 *   LEN bytes: raw data
 * -------------------------------------------------------------------------*/

#define STORED_BLOCK_MAX 65535u

uint32_t gzip_compress(const uint8_t *src, uint32_t src_len,
                       uint8_t *dst, uint32_t dst_cap)
{
    uint32_t pos;       /* write cursor into dst */
    uint32_t remaining; /* bytes of src not yet emitted */
    uint32_t offset;    /* read cursor into src */

    if (!src || !dst)
        return 0;

    /* --- Gzip 10-byte header --- */
    if (dst_cap < 18u)  /* 10 header + at least 8 trailer */
        return 0;

    dst[0] = 0x1Fu;  /* ID1 */
    dst[1] = 0x8Bu;  /* ID2 */
    dst[2] = 8u;     /* CM = deflate */
    dst[3] = 0u;     /* FLG = 0 */
    dst[4] = 0u;     /* MTIME */
    dst[5] = 0u;
    dst[6] = 0u;
    dst[7] = 0u;
    dst[8] = 0u;     /* XFL */
    dst[9] = 0xFFu;  /* OS = unknown */
    pos = 10u;

    /* --- Deflate stored-block stream --- */
    remaining = src_len;
    offset    = 0u;

    /* Handle the empty-input edge case: emit a single empty final block. */
    if (remaining == 0u) {
        /* Need 5 bytes for the empty stored block */
        if (dst_cap - pos < 5u)
            return 0;
        dst[pos++] = 0x01u;  /* BFINAL=1, BTYPE=00, padding=0 */
        put_le16(dst + pos, 0u);          pos += 2u;
        put_le16(dst + pos, 0xFFFFu);     pos += 2u;
    } else {
        while (remaining > 0u) {
            uint16_t block_len, nlen;
            uint8_t  bfinal;
            uint32_t i;

            block_len = (remaining > STORED_BLOCK_MAX)
                        ? (uint16_t)STORED_BLOCK_MAX
                        : (uint16_t)remaining;
            bfinal    = (remaining <= STORED_BLOCK_MAX) ? 1u : 0u;
            nlen      = (uint16_t)(~(uint32_t)block_len & 0xFFFFu);

            /* Space check: 5-byte block header + block_len data bytes */
            if (dst_cap - pos < (uint32_t)block_len + 5u)
                return 0;

            dst[pos++] = bfinal;          /* BFINAL | BTYPE=00 | padding=0 */
            put_le16(dst + pos, block_len);  pos += 2u;
            put_le16(dst + pos, nlen);       pos += 2u;

            for (i = 0; i < (uint32_t)block_len; i++)
                dst[pos++] = src[offset + i];

            offset    += block_len;
            remaining -= block_len;
        }
    }

    /* --- Gzip 8-byte trailer --- */
    if (dst_cap - pos < 8u)
        return 0;

    put_le32(dst + pos, crc32_compute(src, src_len));  pos += 4u;
    put_le32(dst + pos, src_len);                      pos += 4u;

    return pos;
}

/* -------------------------------------------------------------------------
 * gzip_decompress
 *
 * Parses the gzip header (skipping any optional fields), calls
 * deflate_decompress() on the payload, then verifies CRC-32 and ISIZE.
 * Returns decompressed byte count, or 0 on any error.
 * -------------------------------------------------------------------------*/

uint32_t gzip_decompress(const uint8_t *src, uint32_t src_len,
                         uint8_t *dst, uint32_t dst_cap)
{
    uint32_t hdr_len;
    uint8_t  flg;
    uint32_t deflate_in_len;
    size_t   out_len;
    int      rc;
    uint32_t crc_stored, isize_stored, crc_actual;

    if (!src || !dst)
        return 0;

    /* Minimum gzip: 10 header + 2 (empty deflate) + 8 trailer = 20 bytes */
    if (src_len < 20u)
        return 0;

    /* Check magic and compression method */
    if (src[0] != 0x1Fu || src[1] != 0x8Bu)
        return 0;   /* wrong magic */
    if (src[2] != 8u)
        return 0;   /* unsupported CM */

    flg     = src[3];
    hdr_len = 10u;  /* fixed header size */

    /* Skip FEXTRA field if present (FLG bit 2) */
    if (flg & 0x04u) {
        uint16_t xlen;
        if (src_len < hdr_len + 2u)
            return 0;
        xlen = (uint16_t)src[hdr_len] | ((uint16_t)src[hdr_len + 1u] << 8);
        hdr_len += 2u + xlen;
        if (src_len < hdr_len)
            return 0;
    }

    /* Skip FNAME field if present (FLG bit 3): null-terminated string */
    if (flg & 0x08u) {
        while (hdr_len < src_len && src[hdr_len] != 0u)
            hdr_len++;
        hdr_len++;  /* skip the NUL terminator */
        if (hdr_len > src_len)
            return 0;
    }

    /* Skip FCOMMENT field if present (FLG bit 4): null-terminated string */
    if (flg & 0x10u) {
        while (hdr_len < src_len && src[hdr_len] != 0u)
            hdr_len++;
        hdr_len++;
        if (hdr_len > src_len)
            return 0;
    }

    /* Skip FHCRC field if present (FLG bit 1): 2-byte header CRC */
    if (flg & 0x02u) {
        hdr_len += 2u;
        if (src_len < hdr_len)
            return 0;
    }

    /* Trailer is always the last 8 bytes */
    if (src_len < hdr_len + 8u)
        return 0;
    deflate_in_len = src_len - hdr_len - 8u;

    /* Decompress the raw deflate payload */
    rc = deflate_decompress(src + hdr_len, (size_t)deflate_in_len,
                            dst, (size_t)dst_cap, &out_len);
    if (rc != DEFLATE_OK)
        return 0;

    /* Verify CRC-32 */
    crc_stored = get_le32(src + src_len - 8u);
    crc_actual = crc32_compute(dst, (uint32_t)out_len);
    if (crc_stored != crc_actual)
        return 0;

    /* Verify ISIZE (original size mod 2^32) */
    isize_stored = get_le32(src + src_len - 4u);
    if (isize_stored != (uint32_t)out_len)
        return 0;

    return (uint32_t)out_len;
}
