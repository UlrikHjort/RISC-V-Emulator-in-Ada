/* **************************************************************************
 *        RISC-V Emulator - RFC 1952 gzip compress/decompress tests
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

/* gzip-test.c -- RFC 1952 gzip compress/decompress tests
 * By Ulrik Hørlyk Hjort 2026
 *
 * 8 assertions:
 *  1. Compress succeeds and output starts with gzip magic 0x1F 0x8B
 *  2. CM byte is 8 (deflate)
 *  3. Round-trip: decompress matches original string
 *  4. CRC-32 in trailer matches independently computed CRC-32
 *  5. ISIZE in trailer matches original length
 *  6. Round-trip for a longer repetitive buffer (256 bytes)
 *  7. Tampered magic causes decompress to return 0 (error)
 *  8. Tampered ID2 byte also causes decompress to return 0
 */

#include "gzip.h"
#include "log.h"
#include <stdint.h>
#include <stddef.h>
#include <string.h>

static int g_pass = 0, g_fail = 0;

static void chk(const char *label, int ok)
{
    if (ok) { log_write(NONE, "PASS %s\n", label); g_pass++; }
    else     { log_write(NONE, "FAIL %s\n", label); g_fail++; }
}

/* -------------------------------------------------------------------------
 * Minimal CRC-32 (poly 0xEDB88320) -- used independently to verify the
 * value stored in the gzip trailer without relying on gzip.c internals.
 * -------------------------------------------------------------------------*/

static uint32_t ref_crc32_table[256];
static int      ref_table_built = 0;

static void ref_crc32_init(void)
{
    uint32_t i, c, j;
    for (i = 0; i < 256u; i++) {
        c = i;
        for (j = 0; j < 8u; j++)
            c = (c & 1u) ? ((c >> 1) ^ 0xEDB88320u) : (c >> 1);
        ref_crc32_table[i] = c;
    }
    ref_table_built = 1;
}

static uint32_t ref_crc32(const uint8_t *data, uint32_t len)
{
    uint32_t c = 0xFFFFFFFFu;
    if (!ref_table_built) ref_crc32_init();
    while (len--)
        c = (c >> 8) ^ ref_crc32_table[(c ^ *data++) & 0xFFu];
    return c ^ 0xFFFFFFFFu;
}

/* Read a little-endian 32-bit value from p. */
static uint32_t read_le32(const uint8_t *p)
{
    return (uint32_t)p[0]
         | ((uint32_t)p[1] << 8)
         | ((uint32_t)p[2] << 16)
         | ((uint32_t)p[3] << 24);
}

/* -------------------------------------------------------------------------
 * Main
 * -------------------------------------------------------------------------*/

int main(void)
{
    static const char    msg[]    = "Hello, gzip world!";
    static const uint32_t msg_len = 18u;   /* strlen("Hello, gzip world!") */

    static uint8_t cbuf[256];
    static uint8_t dbuf[256];

    uint32_t clen, dlen;
    uint32_t trailer_crc, trailer_isize, expected_crc;

    log_init("gzip-test.log");
    log_write(NONE, "=== Gzip Compress/Decompress Test ===\n\n");

    /* --- Test 1: compress succeeds and magic bytes are correct --- */
    clen = gzip_compress((const uint8_t *)msg, msg_len, cbuf, sizeof(cbuf));
    log_write(NONE, "  compressed len=%u  ID1=0x%x\n",
              clen,
              clen >= 1u ? (unsigned)cbuf[0] : 0u);
    log_write(NONE, "  ID2=0x%x CM=0x%x\n",
              clen >= 2u ? (unsigned)cbuf[1] : 0u,
              clen >= 3u ? (unsigned)cbuf[2] : 0u);
    chk("compress succeeds with correct magic 0x1F 0x8B",
        clen > 0u && cbuf[0] == 0x1Fu && cbuf[1] == 0x8Bu);

    /* --- Test 2: CM byte is 8 --- */
    chk("CM byte is 8 (deflate)", clen >= 3u && cbuf[2] == 8u);

    /* --- Test 3: round-trip decompression matches original --- */
    dlen = 0u;
    if (clen > 0u)
        dlen = gzip_decompress(cbuf, clen, dbuf, sizeof(dbuf));
    log_write(NONE, "  decompressed len=%u (expect %u)\n", dlen, msg_len);
    chk("round-trip decompress matches original",
        dlen == msg_len && memcmp(dbuf, msg, msg_len) == 0);

    /* --- Test 4: CRC-32 in trailer is correct --- */
    expected_crc = ref_crc32((const uint8_t *)msg, msg_len);
    trailer_crc  = (clen >= 8u) ? read_le32(cbuf + clen - 8u) : 0u;
    log_write(NONE, "  expected CRC32=0x%x  trailer CRC32=0x%x\n",
              expected_crc, trailer_crc);
    chk("CRC-32 in trailer matches original data",
        clen >= 8u && trailer_crc == expected_crc);

    /* --- Test 5: ISIZE in trailer is correct --- */
    trailer_isize = (clen >= 4u) ? read_le32(cbuf + clen - 4u) : 0u;
    log_write(NONE, "  expected ISIZE=%u  trailer ISIZE=%u\n",
              msg_len, trailer_isize);
    chk("ISIZE in trailer matches original length",
        clen >= 4u && trailer_isize == msg_len);

    /* --- Test 6: longer repetitive buffer round-trip --- */
    {
        static uint8_t pattern[256];
        static uint8_t cbuf2[512];
        static uint8_t dbuf2[512];
        uint32_t clen2, dlen2;
        int      ok;
        uint32_t i;

        for (i = 0u; i < 256u; i++)
            pattern[i] = (uint8_t)(i & 0xFFu);

        clen2 = gzip_compress(pattern, 256u, cbuf2, sizeof(cbuf2));
        dlen2 = (clen2 > 0u)
                ? gzip_decompress(cbuf2, clen2, dbuf2, sizeof(dbuf2))
                : 0u;

        ok = (dlen2 == 256u);
        if (ok) {
            for (i = 0u; i < 256u; i++) {
                if (dbuf2[i] != (uint8_t)i) { ok = 0; break; }
            }
        }
        log_write(NONE, "  256-byte pattern: clen2=%u dlen2=%u\n", clen2, dlen2);
        chk("round-trip 256-byte pattern buffer", ok);
    }

    /* --- Test 7: tampered ID1 magic -> decompress returns 0 --- */
    {
        static uint8_t bad[256];
        uint32_t       bad_result;
        uint32_t       i;

        for (i = 0u; i < clen && i < sizeof(bad); i++)
            bad[i] = cbuf[i];
        bad[0] = 0x00u;   /* corrupt ID1 */

        bad_result = gzip_decompress(bad, clen, dbuf, sizeof(dbuf));
        chk("tampered ID1 magic causes decompress to return 0",
            bad_result == 0u);
    }

    /* --- Test 8: tampered ID2 magic -> decompress returns 0 --- */
    {
        static uint8_t bad2[256];
        uint32_t       bad_result;
        uint32_t       i;

        for (i = 0u; i < clen && i < sizeof(bad2); i++)
            bad2[i] = cbuf[i];
        bad2[1] = 0x00u;  /* corrupt ID2 */

        bad_result = gzip_decompress(bad2, clen, dbuf, sizeof(dbuf));
        chk("tampered ID2 magic causes decompress to return 0",
            bad_result == 0u);
    }

    log_write(NONE, "\n%d PASS  %d FAIL\n", g_pass, g_fail);
    log_close();
    return g_fail ? 1 : 0;
}
