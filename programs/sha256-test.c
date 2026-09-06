/* **************************************************************************
 *      RISC-V Emulator - SHA-256 implementation and NIST test vectors
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

// sha256-test.c -- SHA-256 implementation and NIST test vectors
//
// Full SHA-256 (FIPS 180-4) with correct K constants and initial H values.
// Tests against three authoritative test vectors:
//
//   SHA-256("")    = e3b0c442 98fc1c14 9afbf4c8 996fb924
//                    27ae41e4 649b934c a495991b 7852b855
//
//   SHA-256("abc") = ba7816bf 8f01cfea 414140de 5dae2223
//                    b00361a3 96177a9c b410ff61 f20015ad
//
//   SHA-256("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq")
//                  = 248d6a61 d20638b8 e5c02693 0c3e6039
//                    a33ce459 64ff2167 f6ecedd4 19db06c1
//
// The last test requires two 512-bit message blocks, exercising the
// multi-block code path.
//
// Build: cd programs && make run-sha256-test
// By Ulrik Hørlyk Hjort 2026

#include "log.h"
#include <stdint.h>

void putchar(char c);
static void uart_puts(const char *s) {
    while (*s) { if (*s == '\n') putchar('\r'); putchar(*s++); }
}

// -- SHA-256 constants (FIPS 180-4 Sec.4.2.2) -----------------------------------
// First 32 bits of the fractional parts of the cube roots of the first 64 primes.

static const uint32_t K[64] = {
    0x428a2f98u, 0x71374491u, 0xb5c0fbcfu, 0xe9b5dba5u,
    0x3956c25bu, 0x59f111f1u, 0x923f82a4u, 0xab1c5ed5u,
    0xd807aa98u, 0x12835b01u, 0x243185beu, 0x550c7dc3u,
    0x72be5d74u, 0x80deb1feu, 0x9bdc06a7u, 0xc19bf174u,
    0xe49b69c1u, 0xefbe4786u, 0x0fc19dc6u, 0x240ca1ccu,
    0x2de92c6fu, 0x4a7484aau, 0x5cb0a9dcu, 0x76f988dau,
    0x983e5152u, 0xa831c66du, 0xb00327c8u, 0xbf597fc7u,
    0xc6e00bf3u, 0xd5a79147u, 0x06ca6351u, 0x14292967u,
    0x27b70a85u, 0x2e1b2138u, 0x4d2c6dfcu, 0x53380d13u,
    0x650a7354u, 0x766a0abbu, 0x81c2c92eu, 0x92722c85u,
    0xa2bfe8a1u, 0xa81a664bu, 0xc24b8b70u, 0xc76c51a3u,
    0xd192e819u, 0xd6990624u, 0xf40e3585u, 0x106aa070u,
    0x19a4c116u, 0x1e376c08u, 0x2748774cu, 0x34b0bcb5u,
    0x391c0cb3u, 0x4ed8aa4au, 0x5b9cca4fu, 0x682e6ff3u,
    0x748f82eeu, 0x78a5636fu, 0x84c87814u, 0x8cc70208u,
    0x90befffau, 0xa4506cebu, 0xbef9a3f7u, 0xc67178f2u
};

// -- Bit operations -----------------------------------------------------------

#define ROTR(x,n)  (((x) >> (n)) | ((x) << (32-(n))))
#define CH(x,y,z)  (((x) & (y)) ^ (~(x) & (z)))
#define MAJ(x,y,z) (((x) & (y)) ^ ((x) & (z)) ^ ((y) & (z)))
#define SIG0(x)    (ROTR(x, 2) ^ ROTR(x,13) ^ ROTR(x,22))
#define SIG1(x)    (ROTR(x, 6) ^ ROTR(x,11) ^ ROTR(x,25))
#define sig0(x)    (ROTR(x, 7) ^ ROTR(x,18) ^ ((x) >>  3))
#define sig1(x)    (ROTR(x,17) ^ ROTR(x,19) ^ ((x) >> 10))

// -- Single 512-bit block compression ----------------------------------------

static void sha256_block(uint32_t h[8], const uint8_t blk[64]) {
    uint32_t W[64];
    // Message schedule: load 16 big-endian words, expand to 64
    for (int i = 0; i < 16; i++)
        W[i] = ((uint32_t)blk[i*4  ] << 24) | ((uint32_t)blk[i*4+1] << 16)
             | ((uint32_t)blk[i*4+2] <<  8) |  (uint32_t)blk[i*4+3];
    for (int i = 16; i < 64; i++)
        W[i] = sig1(W[i-2]) + W[i-7] + sig0(W[i-15]) + W[i-16];

    // Working variables
    uint32_t a=h[0], b=h[1], c=h[2], d=h[3];
    uint32_t e=h[4], f=h[5], g=h[6], hh=h[7];

    // 64 rounds
    for (int i = 0; i < 64; i++) {
        uint32_t T1 = hh + SIG1(e) + CH(e,f,g) + K[i] + W[i];
        uint32_t T2 = SIG0(a) + MAJ(a,b,c);
        hh=g; g=f; f=e; e=d+T1;
        d=c;  c=b; b=a; a=T1+T2;
    }

    h[0]+=a; h[1]+=b; h[2]+=c; h[3]+=d;
    h[4]+=e; h[5]+=f; h[6]+=g; h[7]+=hh;
}

// -- Full SHA-256 -------------------------------------------------------------

static void sha256(const uint8_t *msg, uint32_t len, uint32_t out[8]) {
    // Initial hash values (FIPS 180-4 Sec.5.3.3)
    // First 32 bits of the fractional parts of the square roots of first 8 primes
    out[0] = 0x6a09e667u; out[1] = 0xbb67ae85u;
    out[2] = 0x3c6ef372u; out[3] = 0xa54ff53au;
    out[4] = 0x510e527fu; out[5] = 0x9b05688cu;
    out[6] = 0x1f83d9abu; out[7] = 0x5be0cd19u;

    uint8_t blk[64];
    uint32_t pos = 0;

    // Process all complete 512-bit (64-byte) blocks
    while (pos + 64 <= len) {
        sha256_block(out, msg + pos);
        pos += 64;
    }

    // Final partial block: copy remaining bytes
    uint32_t rem = len - pos;
    for (uint32_t i = 0; i < rem; i++) blk[i] = msg[pos + i];

    // Append the mandatory 0x80 padding byte
    blk[rem++] = 0x80u;

    // If there is not enough room for the 8-byte length field in this block,
    // pad to 64 bytes and process it, then start a fresh block.
    if (rem > 56) {
        while (rem < 64) blk[rem++] = 0;
        sha256_block(out, blk);
        rem = 0;
    }

    // Pad the last block to 56 bytes, then append 64-bit big-endian bit-length
    while (rem < 56) blk[rem++] = 0;
    uint64_t bits = (uint64_t)len * 8;
    blk[56] = (uint8_t)(bits >> 56); blk[57] = (uint8_t)(bits >> 48);
    blk[58] = (uint8_t)(bits >> 40); blk[59] = (uint8_t)(bits >> 32);
    blk[60] = (uint8_t)(bits >> 24); blk[61] = (uint8_t)(bits >> 16);
    blk[62] = (uint8_t)(bits >>  8); blk[63] = (uint8_t)(bits);
    sha256_block(out, blk);
}

// -- Test infrastructure ------------------------------------------------------

static int g_pass = 0, g_fail = 0;

static void log_hash(const char *label, const uint32_t h[8]) {
    log_write(NONE, "  %s:\n    %x%x%x%x%x%x%x%x\n",
              label,
              h[0], h[1], h[2], h[3], h[4], h[5], h[6], h[7]);
}

static void check_hash(const char *label,
                        const uint32_t got[8], const uint32_t exp[8]) {
    int ok = 1;
    for (int i = 0; i < 8; i++) if (got[i] != exp[i]) { ok = 0; break; }
    if (ok) {
        log_write(NONE, "  PASS  %s\n", label);
        g_pass++;
    } else {
        log_write(NONE, "  FAIL  %s\n", label);
        log_hash("  got     ", got);
        log_hash("  expected", exp);
        g_fail++;
    }
}

static int slen(const char *s) { int n=0; while(s[n]) n++; return n; }

// -- Tests --------------------------------------------------------------------

static void test_empty(void) {
    log_write(NONE, "\n=== SHA-256(\"\") ===\n");

    static const uint32_t expected[8] = {
        0xe3b0c442u, 0x98fc1c14u, 0x9afbf4c8u, 0x996fb924u,
        0x27ae41e4u, 0x649b934cu, 0xa495991bu, 0x7852b855u
    };

    uint32_t h[8];
    log_write(CYCLES, "sha256(\"\") start\n");
    sha256((const uint8_t *)"", 0, h);
    log_write(CYCLES, "sha256(\"\") done\n");

    log_hash("computed ", h);
    log_hash("expected ", expected);
    check_hash("SHA-256(\"\") matches FIPS 180-4", h, expected);
}

static void test_abc(void) {
    log_write(NONE, "\n=== SHA-256(\"abc\") ===\n");

    // Verified with OpenSSL / Python hashlib
    static const uint32_t expected[8] = {
        0xba7816bfu, 0x8f01cfeau, 0x414140deu, 0x5dae2223u,
        0xb00361a3u, 0x96177a9cu, 0xb410ff61u, 0xf20015adu
    };

    uint32_t h[8];
    log_write(CYCLES, "sha256(\"abc\") start\n");
    sha256((const uint8_t *)"abc", 3, h);
    log_write(CYCLES, "sha256(\"abc\") done\n");

    log_hash("computed ", h);
    log_hash("expected ", expected);
    check_hash("SHA-256(\"abc\") matches FIPS 180-4", h, expected);
}

static void test_two_blocks(void) {
    // 56-byte message -> requires two 512-bit blocks after padding
    const char *msg =
        "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq";

    log_write(NONE, "\n=== SHA-256(\"%s\") ===\n", msg);
    log_write(NONE, "  (56-byte message, 2 blocks after padding)\n");

    // FIPS 180-4 Appendix B, Example 2
    static const uint32_t expected[8] = {
        0x248d6a61u, 0xd20638b8u, 0xe5c02693u, 0x0c3e6039u,
        0xa33ce459u, 0x64ff2167u, 0xf6ecedd4u, 0x19db06c1u
    };

    uint32_t h[8];
    log_write(CYCLES, "sha256(56-byte msg) start\n");
    sha256((const uint8_t *)msg, slen(msg), h);
    log_write(CYCLES, "sha256(56-byte msg) done\n");

    log_hash("computed ", h);
    log_hash("expected ", expected);
    check_hash("SHA-256(56-byte NIST msg) matches FIPS 180-4", h, expected);
}

static void test_determinism(void) {
    log_write(NONE, "\n=== Determinism: hash(X) == hash(X) ===\n");

    uint32_t h1[8], h2[8];
    sha256((const uint8_t *)"hello world", 11, h1);
    sha256((const uint8_t *)"hello world", 11, h2);

    int ok = 1;
    for (int i = 0; i < 8; i++) if (h1[i] != h2[i]) { ok = 0; break; }
    if (ok) { log_write(NONE, "  PASS  Same input -> same hash\n"); g_pass++; }
    else    { log_write(NONE, "  FAIL  Same input -> different hash!\n"); g_fail++; }

    log_hash("SHA-256(\"hello world\")", h1);
}

static void test_sensitivity(void) {
    log_write(NONE, "\n=== Sensitivity: one-bit change alters the hash ===\n");

    uint32_t ha[8], hb[8];
    sha256((const uint8_t *)"abc", 3, ha);
    sha256((const uint8_t *)"abd", 3, hb);  // differ only in last byte

    int differ = 0;
    for (int i = 0; i < 8; i++) if (ha[i] != hb[i]) { differ++; }

    // All 8 words should differ (avalanche effect)
    if (differ == 8) {
        log_write(NONE, "  PASS  All 8 words differ for \"abc\" vs \"abd\"\n");
        g_pass++;
    } else {
        log_write(NONE, "  FAIL  Only %d of 8 words differ\n", differ);
        g_fail++;
    }
}

// -- Main ---------------------------------------------------------------------

int main(void) {
    uart_puts("=== SHA-256 Test ===\n");

    if (log_init("sha256-test.log") != 0) {
        uart_puts("ERROR: log_init failed\n");
        return 1;
    }

    log_write(NONE, "=== SHA-256 (FIPS 180-4) Test ===\n\n");

    test_empty();
    test_abc();
    test_two_blocks();
    test_determinism();
    test_sensitivity();

    log_write(NONE, "\n=== Summary ===\n");
    log_write(NONE, "  PASS: %d\n", g_pass);
    log_write(NONE, "  FAIL: %d\n", g_fail);
    log_write(NONE, "  %s\n", g_fail == 0 ? "ALL TESTS PASSED" : "SOME TESTS FAILED");

    log_close();
    uart_puts(g_fail == 0 ? "ALL PASSED\n" : "SOME FAILED\n");
    return g_fail;
}
