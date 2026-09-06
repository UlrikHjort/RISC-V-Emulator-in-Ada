/* **************************************************************************
 *RISC-V Emulator - LZSS compression/decompression with round-trip verification
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

// lz77.c -- LZSS compression/decompression with round-trip verification.
//
// Implements a classic LZSS variant:
//   - Flag-byte groups of 8 bits  (1 = literal, 0 = back-reference)
//   - Back-reference token: 2 bytes
//       bits [15:4]  = offset  (1-4095; offset 0 means offset 4096 from cursor)
//       bits  [3:0]  = length-3 encoded (0 = copy 3, 15 = copy 18)
//   - Minimum match length: 3 bytes
//   - Maximum match length: 18 bytes (3 + 15)
//   - Search window: 4096 bytes
//
// Tests:
//   1. All-same bytes (should compress ~8:1)
//   2. Repeating ASCII pattern  (should compress well)
//   3. Random-ish data (generated from LCG -- may grow slightly)
//   4. Alternating 2-byte pattern
//   5. Empty input
//   6. Single-byte input
//   7. Long run of zeros (should compress maximally)
//
// Every test does compress -> decompress -> compare to verify round-trip.
//
// Build: cd programs && make run-lz77
// By Ulrik Hørlyk Hjort 2026

#include <stdint.h>
#include <stddef.h>
#include "log.h"

void putchar(char c);
void *malloc(size_t);
void free(void *);

static void uart_puts(const char *s) {
    while (*s) { if (*s == '\n') putchar('\r'); putchar(*s++); }
}

static int g_pass = 0, g_fail = 0;

// --- LZSS Constants -------------------------------------------------------

#define WIN_BITS   12          // 4096-byte window
#define WIN_SIZE   (1 << WIN_BITS)
#define WIN_MASK   (WIN_SIZE - 1)
#define MIN_MATCH  3
#define MAX_MATCH  18          // 3 + 15 (4-bit length field)

// --- Compression ---------------------------------------------------------
//
// Returns number of bytes written to 'out', or -1 if out_cap exceeded.
// Worst case: every byte is a literal -> output is 9/8 * input + overhead.

static int lzss_compress(const uint8_t *in, int in_len,
                          uint8_t *out, int out_cap)
{
    int op   = 0;       // output position
    int ip   = 0;       // input position

    while (ip < in_len) {
        // Reserve one byte for the flag word
        int flag_pos = op++;
        if (op > out_cap) return -1;
        uint8_t flags = 0;

        for (int bit = 7; bit >= 0 && ip < in_len; bit--) {
            // Try to find the longest match in the sliding window
            int best_len = MIN_MATCH - 1;
            int best_off = 0;

            int win_start = ip - WIN_SIZE;
            if (win_start < 0) win_start = 0;

            for (int j = win_start; j < ip; j++) {
                int l = 0;
                while (l < MAX_MATCH && ip + l < in_len &&
                       in[j + l] == in[ip + l]) {
                    l++;
                }
                if (l > best_len) {
                    best_len = l;
                    best_off = ip - j;   // 1-based distance back
                    if (best_len == MAX_MATCH) break;
                }
            }

            if (best_len >= MIN_MATCH) {
                // Encode as back-reference
                // offset stored as (best_off - 1) in 12 bits so 1->0, 4096->4095
                int enc_off = best_off - 1;
                int enc_len = best_len - MIN_MATCH;   // 0-15 in 4 bits
                if (op + 2 > out_cap) return -1;
                out[op++] = (uint8_t)(enc_off >> 4);
                out[op++] = (uint8_t)((enc_off & 0xF) << 4) | (enc_len & 0xF);
                // flag bit = 0 (already 0)
                ip += best_len;
            } else {
                // Emit literal
                if (op + 1 > out_cap) return -1;
                out[op++] = in[ip++];
                flags |= (1u << bit);
            }
        }
        out[flag_pos] = flags;
    }
    return op;
}

// --- Decompression -------------------------------------------------------
//
// Returns number of bytes written to 'out', or -1 on error.

static int lzss_decompress(const uint8_t *in, int in_len,
                             uint8_t *out, int out_cap)
{
    int ip = 0;
    int op = 0;

    while (ip < in_len) {
        uint8_t flags = in[ip++];

        for (int bit = 7; bit >= 0 && ip < in_len; bit--) {
            if (flags & (1u << bit)) {
                // Literal
                if (op >= out_cap) return -1;
                out[op++] = in[ip++];
            } else {
                // Back-reference: 2 bytes
                if (ip + 1 >= in_len) return -1;   // need 2 bytes
                int b0 = in[ip++];
                int b1 = in[ip++];
                int enc_off = (b0 << 4) | (b1 >> 4);
                int enc_len = b1 & 0xF;
                int offset  = enc_off + 1;             // 1-based
                int length  = enc_len + MIN_MATCH;
                if (op < offset) return -1;            // invalid back-ref
                if (op + length > out_cap) return -1;
                // Copy byte-by-byte (handles overlap correctly)
                int src = op - offset;
                for (int k = 0; k < length; k++) {
                    out[op++] = out[src++];
                }
            }
        }
    }
    return op;
}

// --- Test helpers ---------------------------------------------------------

static int memequal(const uint8_t *a, const uint8_t *b, int n) {
    for (int i = 0; i < n; i++) if (a[i] != b[i]) return 0;
    return 1;
}

static void run_test(const char *name, const uint8_t *data, int len) {
    // We need a compression buffer (worst case: 9/8 * len + 9)
    int cmp_cap = len * 2 + 64;
    if (cmp_cap < 64) cmp_cap = 64;
    uint8_t *cmp_buf  = (uint8_t *)malloc(cmp_cap);
    uint8_t *dec_buf  = (uint8_t *)malloc(len + 64);

    if (!cmp_buf || !dec_buf) {
        log_write(NONE, "  FAIL  %s: malloc failed\n", name); g_fail++;
        if (cmp_buf) free(cmp_buf);
        if (dec_buf) free(dec_buf);
        return;
    }

    int cmp_len = lzss_compress(data, len, cmp_buf, cmp_cap);
    if (cmp_len < 0) {
        log_write(NONE, "  FAIL  %s: compress overflow\n", name); g_fail++;
        free(cmp_buf); free(dec_buf);
        return;
    }

    int dec_len = lzss_decompress(cmp_buf, cmp_len, dec_buf, len + 64);
    if (dec_len != len) {
        log_write(NONE, "  FAIL  %s: decomp len %d != orig %d\n",
                  name, dec_len, len); g_fail++;
        free(cmp_buf); free(dec_buf);
        return;
    }

    if (!memequal(data, dec_buf, len)) {
        log_write(NONE, "  FAIL  %s: data mismatch after round-trip\n", name);
        g_fail++;
        free(cmp_buf); free(dec_buf);
        return;
    }

    // Calculate compression ratio (integer %)
    // ratio = cmp_len * 100 / len  (lower is better)
    int ratio = (len > 0) ? (cmp_len * 100 / len) : 100;
    log_write(NONE, "  PASS  %s: %d -> %d bytes (%d%%)\n",
              name, len, cmp_len, ratio);
    g_pass++;

    free(cmp_buf);
    free(dec_buf);
}

// --- Test Data ------------------------------------------------------------

static void test_all_same(void) {
    log_write(NONE, "\n=== All-same bytes ===\n");
    static uint8_t buf[256];
    for (int i = 0; i < 256; i++) buf[i] = 0xAB;
    run_test("256x 0xAB", buf, 256);
    // Should compress well
}

static void test_repeating_pattern(void) {
    log_write(NONE, "\n=== Repeating ASCII pattern ===\n");
    static uint8_t buf[256];
    const char *pat = "ABCDE";
    int plen = 5;
    for (int i = 0; i < 256; i++) buf[i] = (uint8_t)pat[i % plen];
    run_test("256x \"ABCDE\"", buf, 256);
}

static void test_random_ish(void) {
    log_write(NONE, "\n=== Random-ish data (LCG) ===\n");
    static uint8_t buf[256];
    uint32_t x = 0xDEADBEEF;
    for (int i = 0; i < 256; i++) {
        x = x * 1664525u + 1013904223u;
        buf[i] = (uint8_t)(x >> 24);
    }
    run_test("256 LCG bytes", buf, 256);
}

static void test_alternating(void) {
    log_write(NONE, "\n=== Alternating 2-byte pattern ===\n");
    static uint8_t buf[128];
    for (int i = 0; i < 128; i++) buf[i] = (uint8_t)(i & 1 ? 0xFF : 0x00);
    run_test("128x 0x00/0xFF", buf, 128);
}

static void test_empty(void) {
    log_write(NONE, "\n=== Empty input ===\n");
    uint8_t dummy = 0;
    // We call compress on 0-length; expect 0 compressed bytes
    int n = lzss_compress(&dummy, 0, &dummy, 1);
    int d = lzss_decompress(&dummy, 0, &dummy, 1);
    if (n == 0 && d == 0) {
        log_write(NONE, "  PASS  empty: compress=0 decomp=0\n"); g_pass++;
    } else {
        log_write(NONE, "  FAIL  empty: compress=%d decomp=%d\n", n, d); g_fail++;
    }
}

static void test_single_byte(void) {
    log_write(NONE, "\n=== Single byte ===\n");
    uint8_t src = 0x42;
    run_test("1 byte", &src, 1);
}

static void test_long_zeros(void) {
    log_write(NONE, "\n=== Long run of zeros (512 bytes) ===\n");
    static uint8_t buf[512];
    // Already zero-initialized as static
    run_test("512 zeros", buf, 512);
}

static void test_max_window(void) {
    log_write(NONE, "\n=== Pattern spanning window boundary (5000 bytes) ===\n");
    // Use malloc to avoid stack overflow
    uint8_t *buf = (uint8_t *)malloc(5000);
    if (!buf) {
        log_write(NONE, "  SKIP  malloc failed\n");
        return;
    }
    const char *pat = "Hello, World! ";
    int plen = 14;
    for (int i = 0; i < 5000; i++) buf[i] = (uint8_t)pat[i % plen];
    run_test("5000x pattern", buf, 5000);
    free(buf);
}

// --- Main -----------------------------------------------------------------

int main(void) {
    uart_puts("=== LZ77/LZSS Test ===\n");
    if (log_init("lz77.log") != 0) {
        uart_puts("ERROR: log_init failed\n");
        return 1;
    }

    log_write(NONE, "=== LZ77/LZSS Compression Test ===\n");
    log_write(NONE, "Window=4096  MinMatch=3  MaxMatch=18\n");

    test_all_same();
    test_repeating_pattern();
    test_alternating();
    test_random_ish();
    test_empty();
    test_single_byte();
    test_long_zeros();
    test_max_window();

    log_write(NONE, "\n=== Summary ===\n");
    log_write(NONE, "  PASS: %d\n", g_pass);
    log_write(NONE, "  FAIL: %d\n", g_fail);
    log_write(NONE, "  %s\n", g_fail == 0 ? "ALL TESTS PASSED" : "SOME TESTS FAILED");

    log_close();
    uart_puts(g_fail == 0 ? "ALL PASSED\n" : "SOME FAILED\n");
    return g_fail;
}
