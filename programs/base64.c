/* **************************************************************************
 *          RISC-V Emulator - Base64 encode/decode round-trip test
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

// base64.c -- Base64 encode/decode round-trip test.
//
// Tests:
//   - Encode various inputs and verify against known outputs
//   - Decode known base64 strings and verify output
//   - Round-trip: encode then decode equals original
//   - Edge cases: empty, 1-byte, 2-byte, 3-byte, multi-block
//   - Padding: 0, 1, 2 padding '=' characters
//
// Build: cd programs && make run-base64
// By Ulrik Hørlyk Hjort 2026

#include <stdint.h>
#include <stddef.h>
#include "log.h"

void putchar(char c);
static void uart_puts(const char *s) {
    while (*s) { if (*s == '\n') putchar('\r'); putchar(*s++); }
}

static int g_pass = 0, g_fail = 0;

static void check_int(const char *label, int got, int expected) {
    if (got == expected) {
        log_write(NONE, "  PASS  %s\n", label); g_pass++;
    } else {
        log_write(NONE, "  FAIL  %s: got %d  exp %d\n", label, got, expected);
        g_fail++;
    }
}

static void check_str(const char *label, const char *got, const char *expected) {
    int i = 0;
    while (got[i] && expected[i] && got[i] == expected[i]) i++;
    if (got[i] == expected[i]) {  // both NUL at same position
        log_write(NONE, "  PASS  %s\n", label); g_pass++;
    } else {
        log_write(NONE, "  FAIL  %s: mismatch at byte %d ('%c' vs '%c')\n",
                  label, i, got[i] ? got[i] : '0', expected[i] ? expected[i] : '0');
        g_fail++;
    }
}

static void check_bytes(const char *label, const uint8_t *got, const uint8_t *exp, int n) {
    for (int i = 0; i < n; i++) {
        if (got[i] != exp[i]) {
            log_write(NONE, "  FAIL  %s: byte[%d] got 0x%x exp 0x%x\n",
                      label, i, got[i], exp[i]);
            g_fail++;
            return;
        }
    }
    log_write(NONE, "  PASS  %s\n", label); g_pass++;
}

// -- Base64 implementation -------------------------------------------------

static const char B64_TABLE[] =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

// Encode src[0..srclen-1] to dst (NUL-terminated).
// dst must have room for ((srclen+2)/3*4 + 1) bytes.
// Returns number of output chars (excluding NUL).
static int b64_encode(const uint8_t *src, int srclen, char *dst) {
    int i = 0, j = 0;
    while (i < srclen) {
        int rem = srclen - i;  // bytes remaining in this group (1, 2, or 3)
        uint32_t b = (uint32_t)src[i++] << 16;
        if (i < srclen) b |= (uint32_t)src[i++] << 8;
        if (i < srclen) b |= src[i++];
        dst[j++] = B64_TABLE[(b >> 18) & 0x3F];
        dst[j++] = B64_TABLE[(b >> 12) & 0x3F];
        dst[j++] = (rem < 2) ? '=' : B64_TABLE[(b >> 6) & 0x3F];
        dst[j++] = (rem < 3) ? '=' : B64_TABLE[(b >> 0) & 0x3F];
    }
    dst[j] = '\0';
    return j;
}

// Decode value of a base64 character, or -1 if invalid.
static int b64_val(char c) {
    if (c >= 'A' && c <= 'Z') return c - 'A';
    if (c >= 'a' && c <= 'z') return c - 'a' + 26;
    if (c >= '0' && c <= '9') return c - '0' + 52;
    if (c == '+') return 62;
    if (c == '/') return 63;
    return -1;
}

// Decode NUL-terminated base64 string src to dst.
// Returns number of output bytes, or -1 on error.
static int b64_decode(const char *src, uint8_t *dst) {
    int j = 0;
    int i = 0;
    int slen = 0;
    while (src[slen]) slen++;

    if (slen % 4 != 0) return -1;

    while (i < slen) {
        int v0 = b64_val(src[i]);
        int v1 = b64_val(src[i+1]);
        int v2 = (src[i+2] == '=') ? 0 : b64_val(src[i+2]);
        int v3 = (src[i+3] == '=') ? 0 : b64_val(src[i+3]);
        if (v0 < 0 || v1 < 0 || v2 < 0 || v3 < 0) return -1;

        uint32_t b = ((uint32_t)v0 << 18) | ((uint32_t)v1 << 12) |
                     ((uint32_t)v2 << 6) | v3;
        dst[j++] = (b >> 16) & 0xFF;
        if (src[i+2] != '=') dst[j++] = (b >> 8) & 0xFF;
        if (src[i+3] != '=') dst[j++] = b & 0xFF;
        i += 4;
    }
    return j;
}

// -- Test cases -------------------------------------------------------------

static void test_encode(void) {
    log_write(NONE, "\n=== Base64 Encode ===\n");
    char out[128];

    // RFC 4648 test vectors
    check_int("encode '' len=0", b64_encode((uint8_t *)"", 0, out), 0);
    check_str("encode '' str", out, "");

    b64_encode((uint8_t *)"f", 1, out);
    check_str("encode 'f'='Zg=='", out, "Zg==");

    b64_encode((uint8_t *)"fo", 2, out);
    check_str("encode 'fo'='Zm8='", out, "Zm8=");

    b64_encode((uint8_t *)"foo", 3, out);
    check_str("encode 'foo'='Zm9v'", out, "Zm9v");

    b64_encode((uint8_t *)"foob", 4, out);
    check_str("encode 'foob'='Zm9vYg=='", out, "Zm9vYg==");

    b64_encode((uint8_t *)"fooba", 5, out);
    check_str("encode 'fooba'='Zm9vYmE='", out, "Zm9vYmE=");

    b64_encode((uint8_t *)"foobar", 6, out);
    check_str("encode 'foobar'='Zm9vYmFy'", out, "Zm9vYmFy");

    // Binary data
    static const uint8_t bin[] = {0x00, 0xFF, 0x01, 0xFE};
    b64_encode(bin, 4, out);
    check_str("encode {0x00,0xFF,0x01,0xFE}='AP8B/g=='", out, "AP8B/g==");

    // All zeros
    static const uint8_t zeros[3] = {0, 0, 0};
    b64_encode(zeros, 3, out);
    check_str("encode {0,0,0}='AAAA'", out, "AAAA");

    // All 0xFF
    static const uint8_t ffs[3] = {0xFF, 0xFF, 0xFF};
    b64_encode(ffs, 3, out);
    check_str("encode {0xFF,0xFF,0xFF}='////'", out, "////");
}

static void test_decode(void) {
    log_write(NONE, "\n=== Base64 Decode ===\n");
    uint8_t out[128];
    int n;

    n = b64_decode("", out);
    check_int("decode '' -> 0 bytes", n, 0);

    n = b64_decode("Zg==", out);
    check_int("decode 'Zg==' -> 1 byte", n, 1);
    check_int("decode 'Zg==' -> 'f'", out[0], 'f');

    n = b64_decode("Zm8=", out);
    check_int("decode 'Zm8=' -> 2 bytes", n, 2);
    check_int("decode 'Zm8=' -> 'f'", out[0], 'f');
    check_int("decode 'Zm8=' -> 'o'", out[1], 'o');

    n = b64_decode("Zm9v", out);
    check_int("decode 'Zm9v' -> 3 bytes", n, 3);
    static const uint8_t foo[] = {'f', 'o', 'o'};
    check_bytes("decode 'Zm9v'='foo'", out, foo, 3);

    n = b64_decode("Zm9vYmFy", out);
    check_int("decode 'Zm9vYmFy' -> 6 bytes", n, 6);
    static const uint8_t foobar[] = {'f', 'o', 'o', 'b', 'a', 'r'};
    check_bytes("decode 'Zm9vYmFy'='foobar'", out, foobar, 6);

    n = b64_decode("AP8B/g==", out);
    check_int("decode 'AP8B/g==' -> 4 bytes", n, 4);
    static const uint8_t bin[] = {0x00, 0xFF, 0x01, 0xFE};
    check_bytes("decode bin data", out, bin, 4);

    // All zeros
    n = b64_decode("AAAA", out);
    check_int("decode 'AAAA' -> 3 bytes", n, 3);
    check_int("decode 'AAAA' byte[0]=0", out[0], 0);
    check_int("decode 'AAAA' byte[1]=0", out[1], 0);
    check_int("decode 'AAAA' byte[2]=0", out[2], 0);
}

static void test_roundtrip(void) {
    log_write(NONE, "\n=== Round-trip ===\n");
    static const char *texts[] = {
        "Hello, World!",
        "The quick brown fox jumps over the lazy dog",
        "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz",
        "\x01\x02\x03\x04\x05",
        NULL
    };

    char enc[256];
    uint8_t dec[200];

    for (int t = 0; texts[t]; t++) {
        const char *orig = texts[t];
        int olen = 0;
        while (orig[olen]) olen++;

        b64_encode((const uint8_t *)orig, olen, enc);
        int dlen = b64_decode(enc, dec);

        if (dlen != olen) {
            log_write(NONE, "  FAIL  roundtrip[%d]: length %d vs %d\n", t, dlen, olen);
            g_fail++;
            continue;
        }
        int ok = 1;
        for (int i = 0; i < olen; i++) {
            if (dec[i] != (uint8_t)orig[i]) { ok = 0; break; }
        }
        if (ok) {
            log_write(NONE, "  PASS  roundtrip[%d] len=%d\n", t, olen);
            g_pass++;
        } else {
            log_write(NONE, "  FAIL  roundtrip[%d]: content mismatch\n", t);
            g_fail++;
        }
    }
}

// -- Main ------------------------------------------------------------------

int main(void) {
    uart_puts("=== Base64 Test ===\n");
    if (log_init("base64.log") != 0) {
        uart_puts("ERROR: log_init failed\n"); return 1;
    }

    log_write(NONE, "=== Base64 Encode/Decode Test ===\n");

    test_encode();
    test_decode();
    test_roundtrip();

    log_write(NONE, "\n=== Summary ===\n");
    log_write(NONE, "  PASS: %d\n", g_pass);
    log_write(NONE, "  FAIL: %d\n", g_fail);
    log_write(NONE, "  %s\n", g_fail == 0 ? "ALL TESTS PASSED" : "SOME TESTS FAILED");

    log_close();
    uart_puts(g_fail == 0 ? "ALL PASSED\n" : "SOME FAILED\n");
    return g_fail;
}
