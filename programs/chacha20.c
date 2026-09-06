/* **************************************************************************
 *         RISC-V Emulator - ChaCha20 Stream Cipher (RFC 7539) Test
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

// chacha20.c -- ChaCha20 stream cipher (RFC 7539) test for the RISC-V emulator.
//
// Self-contained implementation; no external crypto library needed.
// Tests against official RFC 7539 test vectors:
//   1. Quarter-round function (section 2.1.1)
//   2. Block function -- 20 rounds (section 2.3.2)
//   3. Full encrypt/decrypt round-trip
//   4. Counter increment across two blocks
//
// The algorithm exercises 32-bit add, XOR, and rotate -- a good stress-test
// for ALU instruction coverage.
//
// Build: cd programs && make run-chacha20
// By Ulrik Hørlyk Hjort 2026

#include "log.h"
#include <stdint.h>

void putchar(char c);

static void uart_puts(const char *s) {
    while (*s) { if (*s == '\n') putchar('\r'); putchar(*s++); }
}

static int g_pass = 0, g_fail = 0;

// --- Helpers ------------------------------------------------------------------

static inline uint32_t rotl32(uint32_t v, int n) {
    return (v << n) | (v >> (32 - n));
}

static void check_u32(const char *label, uint32_t got, uint32_t expected) {
    if (got == expected) {
        log_write(NONE, "  PASS  %s\n", label); g_pass++;
    } else {
        log_write(NONE, "  FAIL  %s: got %x  exp %x\n", label, got, expected); g_fail++;
    }
}

static void check_i(const char *label, int got, int expected) {
    if (got == expected) {
        log_write(NONE, "  PASS  %s\n", label); g_pass++;
    } else {
        log_write(NONE, "  FAIL  %s: got %d  exp %d\n", label, got, expected); g_fail++;
    }
}

// --- ChaCha20 core ------------------------------------------------------------

// Quarter round in-place on the state array
static inline void qr(uint32_t s[16], int a, int b, int c, int d) {
    s[a] += s[b]; s[d] ^= s[a]; s[d] = rotl32(s[d], 16);
    s[c] += s[d]; s[b] ^= s[c]; s[b] = rotl32(s[b], 12);
    s[a] += s[b]; s[d] ^= s[a]; s[d] = rotl32(s[d],  8);
    s[c] += s[d]; s[b] ^= s[c]; s[b] = rotl32(s[b],  7);
}

// Produce one 64-byte keystream block.
// key:     8 x uint32  (256-bit)
// counter: 32-bit block counter
// nonce:   3 x uint32  (96-bit)
// out:     64-byte output
static void chacha20_block(const uint32_t key[8],
                            uint32_t       counter,
                            const uint32_t nonce[3],
                            uint8_t        out[64])
{
    // Initial state
    uint32_t s[16] = {
        0x61707865, 0x3320646e, 0x79622d32, 0x6b206574,  // "expand 32-byte k"
        key[0],  key[1],  key[2],  key[3],
        key[4],  key[5],  key[6],  key[7],
        counter,
        nonce[0], nonce[1], nonce[2]
    };

    uint32_t w[16];
    for (int i = 0; i < 16; i++) w[i] = s[i];

    // 20 rounds (10 double-rounds)
    for (int i = 0; i < 10; i++) {
        // Column rounds
        qr(w, 0, 4,  8, 12);
        qr(w, 1, 5,  9, 13);
        qr(w, 2, 6, 10, 14);
        qr(w, 3, 7, 11, 15);
        // Diagonal rounds
        qr(w, 0, 5, 10, 15);
        qr(w, 1, 6, 11, 12);
        qr(w, 2, 7,  8, 13);
        qr(w, 3, 4,  9, 14);
    }

    // Add initial state
    for (int i = 0; i < 16; i++) w[i] += s[i];

    // Serialize little-endian
    for (int i = 0; i < 16; i++) {
        out[i*4+0] = (uint8_t)(w[i]       & 0xFF);
        out[i*4+1] = (uint8_t)((w[i]>> 8) & 0xFF);
        out[i*4+2] = (uint8_t)((w[i]>>16) & 0xFF);
        out[i*4+3] = (uint8_t)((w[i]>>24) & 0xFF);
    }
}

// Encrypt / decrypt (XOR with keystream, in-place if src==dst is ok)
static void chacha20_encrypt(const uint32_t key[8],
                              uint32_t       initial_counter,
                              const uint32_t nonce[3],
                              const uint8_t *in, uint8_t *out, int len)
{
    uint8_t block[64];
    uint32_t counter = initial_counter;
    int pos = 0;
    while (pos < len) {
        chacha20_block(key, counter++, nonce, block);
        int chunk = len - pos;
        if (chunk > 64) chunk = 64;
        for (int i = 0; i < chunk; i++)
            out[pos + i] = in[pos + i] ^ block[i];
        pos += chunk;
    }
}

// --- 1. Quarter-round test (RFC 7539 Sec.2.1.1) ---------------------------------

static void test_quarter_round(void) {
    log_write(NONE, "\n=== Quarter-round (RFC 7539 section 2.1.1) ===\n");

    uint32_t s[16] = {0};
    s[0] = 0x11111111;
    s[4] = 0x01020304;
    s[8] = 0x9b8d6f43;
    s[12] = 0x01234567;

    qr(s, 0, 4, 8, 12);

    check_u32("s[0]  = ea2a92f4", s[0],  0xea2a92f4);
    check_u32("s[4]  = cb1cf8ce", s[4],  0xcb1cf8ce);
    check_u32("s[8]  = 4581472e", s[8],  0x4581472e);
    check_u32("s[12] = 5881c4bb", s[12], 0x5881c4bb);
}

// --- 2. Block function (RFC 7539 Sec.2.3.2) -------------------------------------

static void test_block(void) {
    log_write(NONE, "\n=== Block function (RFC 7539 section 2.3.2) ===\n");

    // Key: 00 01 02 03 ... 1f  (32 bytes)
    static const uint32_t key[8] = {
        0x03020100, 0x07060504, 0x0b0a0908, 0x0f0e0d0c,
        0x13121110, 0x17161514, 0x1b1a1918, 0x1f1e1d1c
    };
    // Nonce: 00 00 00 09 00 00 00 4a 00 00 00 00
    static const uint32_t nonce[3] = {0x09000000, 0x4a000000, 0x00000000};
    uint32_t counter = 1;

    uint8_t out[64];
    chacha20_block(key, counter, nonce, out);

    // Expected output (RFC 7539 Sec.2.3.2, serialised as bytes, first 16 bytes)
    static const uint8_t expected[64] = {
        0x10, 0xf1, 0xe7, 0xe4, 0xd1, 0x3b, 0x59, 0x15,
        0x50, 0x0f, 0xdd, 0x1f, 0xa3, 0x20, 0x71, 0xc4,
        0xc7, 0xd1, 0xf4, 0xc7, 0x33, 0xc0, 0x68, 0x03,
        0x04, 0x22, 0xaa, 0x9a, 0xc3, 0xd4, 0x6c, 0x4e,
        0xd2, 0x82, 0x64, 0x46, 0x07, 0x9f, 0xaa, 0x09,
        0x14, 0xc2, 0xd7, 0x05, 0xd9, 0x8b, 0x02, 0xa2,
        0xb5, 0x12, 0x9c, 0xd1, 0xde, 0x16, 0x4e, 0xb9,
        0xcb, 0xd0, 0x83, 0xe8, 0xa2, 0x50, 0x3c, 0x4e
    };

    int ok = 1;
    for (int i = 0; i < 64; i++) {
        if (out[i] != expected[i]) { ok = 0; break; }
    }
    check_i("block output matches RFC 7539 Sec.2.3.2", ok, 1);
    if (!ok) {
        log_write(NONE, "  first 8 bytes: %x %x %x %x %x %x %x %x\n",
                  out[0],out[1],out[2],out[3],out[4],out[5],out[6],out[7]);
        log_write(NONE, "  expected:       %x %x %x %x %x %x %x %x\n",
                  expected[0],expected[1],expected[2],expected[3],
                  expected[4],expected[5],expected[6],expected[7]);
    }
}

// --- 3. Full encryption (RFC 7539 Sec.2.4.2) ------------------------------------

static void test_encrypt(void) {
    log_write(NONE, "\n=== Encrypt (RFC 7539 section 2.4.2) ===\n");

    static const uint32_t key[8] = {
        0x03020100, 0x07060504, 0x0b0a0908, 0x0f0e0d0c,
        0x13121110, 0x17161514, 0x1b1a1918, 0x1f1e1d1c
    };
    static const uint32_t nonce[3] = {0x00000000, 0x4a000000, 0x00000000};

    // Plaintext: "Ladies and Gentlemen of the class of '99: ..."
    static const uint8_t plaintext[114] = {
        0x4c,0x61,0x64,0x69,0x65,0x73,0x20,0x61,0x6e,0x64,0x20,0x47,0x65,0x6e,
        0x74,0x6c,0x65,0x6d,0x65,0x6e,0x20,0x6f,0x66,0x20,0x74,0x68,0x65,0x20,
        0x63,0x6c,0x61,0x73,0x73,0x20,0x6f,0x66,0x20,0x27,0x39,0x39,0x3a,0x20,
        0x49,0x66,0x20,0x49,0x20,0x63,0x6f,0x75,0x6c,0x64,0x20,0x6f,0x66,0x66,
        0x65,0x72,0x20,0x79,0x6f,0x75,0x20,0x6f,0x6e,0x6c,0x79,0x20,0x6f,0x6e,
        0x65,0x20,0x74,0x69,0x70,0x20,0x66,0x6f,0x72,0x20,0x74,0x68,0x65,0x20,
        0x66,0x75,0x74,0x75,0x72,0x65,0x2c,0x20,0x73,0x75,0x6e,0x73,0x63,0x72,
        0x65,0x65,0x6e,0x20,0x77,0x6f,0x75,0x6c,0x64,0x20,0x62,0x65,0x20,0x69,
        0x74,0x2e
    };

    // Expected ciphertext (RFC 7539 Sec.2.4.2)
    static const uint8_t expected_ct[114] = {
        0x6e,0x2e,0x35,0x9a,0x25,0x68,0xf9,0x80,0x41,0xba,0x07,0x28,0xdd,0x0d,
        0x69,0x81,0xe9,0x7e,0x7a,0xec,0x1d,0x43,0x60,0xc2,0x0a,0x27,0xaf,0xcc,
        0xfd,0x9f,0xae,0x0b,0xf9,0x1b,0x65,0xc5,0x52,0x47,0x33,0xab,0x8f,0x59,
        0x3d,0xab,0xcd,0x62,0xb3,0x57,0x16,0x39,0xd6,0x24,0xe6,0x51,0x52,0xab,
        0x8f,0x53,0x0c,0x35,0x9f,0x08,0x61,0xd8,0x07,0xca,0x0d,0xbf,0x50,0x0d,
        0x6a,0x61,0x56,0xa3,0x8e,0x08,0x8a,0x22,0xb6,0x5e,0x52,0xbc,0x51,0x4d,
        0x16,0xcc,0xf8,0x06,0x81,0x8c,0xe9,0x1a,0xb7,0x79,0x37,0x36,0x5a,0xf9,
        0x0b,0xbf,0x74,0xa3,0x5b,0xe6,0xb4,0x0b,0x8e,0xed,0xf2,0x78,0x5e,0x42,
        0x87,0x4d
    };

    uint8_t ct[114];
    chacha20_encrypt(key, 1, nonce, plaintext, ct, 114);

    int ok = 1;
    for (int i = 0; i < 114; i++) {
        if (ct[i] != expected_ct[i]) { ok = 0; break; }
    }
    check_i("encrypt matches RFC 7539 Sec.2.4.2", ok, 1);

    // Decrypt: XOR again must recover plaintext
    uint8_t pt2[114];
    chacha20_encrypt(key, 1, nonce, ct, pt2, 114);
    int ok2 = 1;
    for (int i = 0; i < 114; i++) {
        if (pt2[i] != plaintext[i]) { ok2 = 0; break; }
    }
    check_i("decrypt recovers plaintext", ok2, 1);
}

// --- 4. Counter increment -----------------------------------------------------

static void test_counter(void) {
    log_write(NONE, "\n=== Counter increment across two blocks ===\n");

    static const uint32_t key[8]   = {1,2,3,4,5,6,7,8};
    static const uint32_t nonce[3] = {0,0,0};

    uint8_t ks0[64], ks1[64];
    chacha20_block(key, 0, nonce, ks0);
    chacha20_block(key, 1, nonce, ks1);

    // Two consecutive blocks must be different (counter changes the state)
    int differ = 0;
    for (int i = 0; i < 64; i++) if (ks0[i] != ks1[i]) { differ = 1; break; }
    check_i("counter 0 vs 1: blocks differ", differ, 1);

    // Encrypt 128 bytes as one call; must equal two separate block XORs
    uint8_t plain[128];
    for (int i = 0; i < 128; i++) plain[i] = (uint8_t)i;

    uint8_t ct_combined[128];
    chacha20_encrypt(key, 0, nonce, plain, ct_combined, 128);

    // Verify first block
    int ok0 = 1;
    for (int i = 0; i < 64; i++) {
        if (ct_combined[i] != (uint8_t)(plain[i] ^ ks0[i])) { ok0 = 0; break; }
    }
    check_i("encrypt block 0 matches keystream 0", ok0, 1);

    // Verify second block
    int ok1 = 1;
    for (int i = 0; i < 64; i++) {
        if (ct_combined[64+i] != (uint8_t)(plain[64+i] ^ ks1[i])) { ok1 = 0; break; }
    }
    check_i("encrypt block 1 matches keystream 1", ok1, 1);
}

// --- 5. Cycle profiling -------------------------------------------------------

static void test_cycles(void) {
    log_write(NONE, "\n=== Cycle profiling ===\n");

    static const uint32_t key[8]   = {0xdeadbeef,0xcafebabe,1,2,3,4,5,6};
    static const uint32_t nonce[3] = {0x1234,0x5678,0};
    uint8_t out[64];

    log_write(CYCLES, "100x chacha20_block\n");
    for (int i = 0; i < 100; i++)
        chacha20_block(key, (uint32_t)i, nonce, out);
    log_write(CYCLES, "100x chacha20_block done\n");
    (void)out[0];
}

// --- Main ---------------------------------------------------------------------

int main(void) {
    uart_puts("=== ChaCha20 Test ===\n");
    if (log_init("chacha20.log") != 0) {
        uart_puts("ERROR: log_init failed\n");
        return 1;
    }

    log_write(NONE, "=== ChaCha20 Test (RFC 7539) ===\n");

    test_quarter_round();
    test_block();
    test_encrypt();
    test_counter();
    test_cycles();

    log_write(NONE, "\n=== Summary ===\n");
    log_write(NONE, "  PASS: %d\n", g_pass);
    log_write(NONE, "  FAIL: %d\n", g_fail);
    log_write(NONE, "  %s\n", g_fail == 0 ? "ALL TESTS PASSED" : "SOME TESTS FAILED");

    log_close();
    uart_puts(g_fail == 0 ? "ALL PASSED\n" : "SOME FAILED\n");
    return g_fail;
}
