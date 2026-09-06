/* **************************************************************************
 *       RISC-V Emulator - CRC32 (ISO 3309 / ITU-T V.42) test program
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

// crc32-test.c -- CRC32 (ISO 3309 / ITU-T V.42) test program
//
// Uses the reflected polynomial 0xEDB88320 with:
//   initial value : 0xFFFFFFFF
//   final XOR     : 0xFFFFFFFF
//
// This is the same CRC32 used in Ethernet, gzip, ZIP, and PNG.
//
// Known test vector (check value): CRC32("123456789") = 0xCBF43926
//
// Build: cd programs && make run-crc32-test
// By Ulrik Hørlyk Hjort 2026

#include "log.h"
#include <stdint.h>

void putchar(char c);

static void uart_puts(const char *s) {
    while (*s) { if (*s == '\n') putchar('\r'); putchar(*s++); }
}

// -- CRC32 implementation ----------------------------------------------------

static uint32_t crc32_table[256];

static void crc32_init(void) {
    for (uint32_t i = 0; i < 256; i++) {
        uint32_t c = i;
        for (int j = 0; j < 8; j++)
            c = (c & 1) ? (c >> 1) ^ 0xEDB88320u : c >> 1;
        crc32_table[i] = c;
    }
}

static uint32_t crc32(const uint8_t *data, uint32_t len) {
    uint32_t c = 0xFFFFFFFFu;
    while (len--)
        c = (c >> 8) ^ crc32_table[(c ^ *data++) & 0xFF];
    return c ^ 0xFFFFFFFFu;
}

// Incremental version: call with c=0xFFFFFFFF to start, finalize with ^0xFFFFFFFF.
static uint32_t crc32_feed(uint32_t c, const uint8_t *data, uint32_t len) {
    while (len--)
        c = (c >> 8) ^ crc32_table[(c ^ *data++) & 0xFF];
    return c;
}

// -- Test infrastructure -----------------------------------------------------

static int g_pass = 0, g_fail = 0;

static void check(const char *label, uint32_t got, uint32_t expected) {
    if (got == expected) {
        log_write(NONE, "  PASS  %s  (0x%x)\n", label, got);
        g_pass++;
    } else {
        log_write(NONE, "  FAIL  %s: got 0x%x  expected 0x%x\n",
                  label, got, expected);
        g_fail++;
    }
}

static int slen(const char *s) {
    int n = 0;
    while (s[n]) n++;
    return n;
}

// -- Tests -------------------------------------------------------------------

static void test_known_vectors(void) {
    log_write(NONE, "\n=== Known test vectors ===\n");

    // THE canonical CRC32 check value
    check("CRC32(\"123456789\")",
          crc32((const uint8_t *)"123456789", 9),
          0xCBF43926u);

    // Empty string: initial ^ final = 0xFFFFFFFF ^ 0xFFFFFFFF = 0
    check("CRC32(\"\")",
          crc32((const uint8_t *)"", 0),
          0x00000000u);

    // Well-known pangram
    const char *fox = "The quick brown fox jumps over the lazy dog";
    log_write(NONE, "  INFO  CRC32(pangram) = 0x%x\n",
              crc32((const uint8_t *)fox, slen(fox)));

    // Single byte 0xFF
    uint8_t b = 0xFF;
    log_write(NONE, "  INFO  CRC32(0xFF)    = 0x%x\n", crc32(&b, 1));

    // All-zero block (32 bytes)
    uint8_t zeros[32];
    for (int i = 0; i < 32; i++) zeros[i] = 0;
    log_write(NONE, "  INFO  CRC32(32*0x00) = 0x%x\n", crc32(zeros, 32));
}

static void test_incremental(void) {
    log_write(NONE, "\n=== Incremental (split-input) test ===\n");

    // CRC32("123456789") must equal CRC32("1234" || "56789")
    uint32_t full = crc32((const uint8_t *)"123456789", 9);
    uint32_t part = crc32_feed(0xFFFFFFFFu, (const uint8_t *)"1234", 4);
    part          = crc32_feed(part,         (const uint8_t *)"56789", 5);
    part         ^= 0xFFFFFFFFu;
    check("CRC32(\"1234\"||\"56789\") == CRC32(\"123456789\")", part, full);

    // Three-way split: "12" || "345" || "6789"
    uint32_t p2 = crc32_feed(0xFFFFFFFFu, (const uint8_t *)"12",   2);
    p2          = crc32_feed(p2,           (const uint8_t *)"345",  3);
    p2          = crc32_feed(p2,           (const uint8_t *)"6789", 4);
    p2         ^= 0xFFFFFFFFu;
    check("Three-way split matches full", p2, full);
}

static void test_properties(void) {
    log_write(NONE, "\n=== Properties ===\n");

    // Idempotency: computing twice gives the same result
    uint32_t a = crc32((const uint8_t *)"hello", 5);
    uint32_t b = crc32((const uint8_t *)"hello", 5);
    check("Idempotent (same input -> same CRC)", a, b);

    // Byte-wise vs block: process "abc" one byte at a time
    uint32_t block  = crc32((const uint8_t *)"abc", 3);
    uint32_t stream = 0xFFFFFFFFu;
    stream = crc32_feed(stream, (const uint8_t *)"a", 1);
    stream = crc32_feed(stream, (const uint8_t *)"b", 1);
    stream = crc32_feed(stream, (const uint8_t *)"c", 1);
    stream ^= 0xFFFFFFFFu;
    check("Byte-at-a-time == block for \"abc\"", stream, block);

    // Different data gives different CRC (simple collision check)
    uint32_t c1 = crc32((const uint8_t *)"abc", 3);
    uint32_t c2 = crc32((const uint8_t *)"abd", 3);
    if (c1 != c2) {
        log_write(NONE, "  PASS  \"abc\" and \"abd\" have different CRCs\n");
        g_pass++;
    } else {
        log_write(NONE, "  FAIL  \"abc\" and \"abd\" have same CRC (collision!)\n");
        g_fail++;
    }

    // Appending a zero byte changes the CRC
    uint32_t c3 = crc32((const uint8_t *)"abc",  3);
    uint32_t c4 = crc32((const uint8_t *)"abc\0", 4);
    if (c3 != c4) {
        log_write(NONE, "  PASS  Appending 0x00 changes CRC\n");
        g_pass++;
    } else {
        log_write(NONE, "  FAIL  Appending 0x00 did not change CRC\n");
        g_fail++;
    }
}

static void test_bulk(void) {
    log_write(NONE, "\n=== Bulk data ===\n");

    // Ascending bytes 0x00..0xFF (256-byte block)
    uint8_t buf[256];
    for (int i = 0; i < 256; i++) buf[i] = (uint8_t)i;
    uint32_t c = crc32(buf, 256);
    log_write(NONE, "  INFO  CRC32(0x00..0xFF) = 0x%x\n", c);

    // Same but split into 16-byte chunks
    uint32_t inc = 0xFFFFFFFFu;
    for (int i = 0; i < 256; i += 16)
        inc = crc32_feed(inc, buf + i, 16);
    inc ^= 0xFFFFFFFFu;
    check("256-byte bulk == 16-chunk incremental", inc, c);

    // Cycle cost
    log_write(CYCLES, "CRC32(256 bytes) start\n");
    crc32(buf, 256);
    log_write(CYCLES, "CRC32(256 bytes) done\n");

    log_write(CYCLES, "CRC32(\"123456789\") start\n");
    crc32((const uint8_t *)"123456789", 9);
    log_write(CYCLES, "CRC32(\"123456789\") done\n");
}

int main(void) {
    uart_puts("=== CRC32 Test ===\n");

    if (log_init("crc32-test.log") != 0) {
        uart_puts("ERROR: log_init failed\n");
        return 1;
    }

    log_write(NONE, "=== CRC32 Test (poly=0xEDB88320, init=0xFFFFFFFF) ===\n\n");

    crc32_init();
    log_write(NONE, "Table computed. table[0]=0x%x  table[1]=0x%x\n",
              crc32_table[0], crc32_table[1]);

    test_known_vectors();
    test_incremental();
    test_properties();
    test_bulk();

    log_write(NONE, "\n=== Summary ===\n");
    log_write(NONE, "  PASS: %d\n", g_pass);
    log_write(NONE, "  FAIL: %d\n", g_fail);
    log_write(NONE, "  %s\n", g_fail == 0 ? "ALL TESTS PASSED" : "SOME TESTS FAILED");

    log_close();
    uart_puts(g_fail == 0 ? "ALL PASSED\n" : "SOME FAILED\n");
    return g_fail;
}
