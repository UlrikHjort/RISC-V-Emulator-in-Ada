/* **************************************************************************
 *           RISC-V Emulator - AES-128 encryption/decryption test
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

// aes128.c -- AES-128 encryption/decryption test.
//
// Tests AES-128 in ECB mode against NIST FIPS 197 Appendix B and C vectors:
//   - Key schedule (key expansion)
//   - SubBytes, ShiftRows, MixColumns, AddRoundKey
//   - Full encrypt (10 rounds)
//   - Full decrypt (10 rounds)
//   - Multiple known plaintext/ciphertext pairs
//
// Build: cd programs && make run-aes128
// By Ulrik Hørlyk Hjort 2026

#include <stdint.h>
#include "log.h"

void putchar(char c);
static void uart_puts(const char *s) {
    while (*s) { if (*s == '\n') putchar('\r'); putchar(*s++); }
}

static int g_pass = 0, g_fail = 0;

static void check_block(const char *label, const uint8_t *got, const uint8_t *exp) {
    int ok = 1;
    for (int i = 0; i < 16; i++) {
        if (got[i] != exp[i]) { ok = 0; break; }
    }
    if (ok) {
        log_write(NONE, "  PASS  %s\n", label); g_pass++;
    } else {
        log_write(NONE, "  FAIL  %s\n", label);
        log_write(NONE, "        got: ");
        for (int i = 0; i < 16; i++) log_write(NONE, "%x ", got[i]);
        log_write(NONE, "\n        exp: ");
        for (int i = 0; i < 16; i++) log_write(NONE, "%x ", exp[i]);
        log_write(NONE, "\n");
        g_fail++;
    }
}

// -- AES-128 implementation ------------------------------------------------

// AES S-box
static const uint8_t SBOX[256] = {
    0x63,0x7c,0x77,0x7b,0xf2,0x6b,0x6f,0xc5,0x30,0x01,0x67,0x2b,0xfe,0xd7,0xab,0x76,
    0xca,0x82,0xc9,0x7d,0xfa,0x59,0x47,0xf0,0xad,0xd4,0xa2,0xaf,0x9c,0xa4,0x72,0xc0,
    0xb7,0xfd,0x93,0x26,0x36,0x3f,0xf7,0xcc,0x34,0xa5,0xe5,0xf1,0x71,0xd8,0x31,0x15,
    0x04,0xc7,0x23,0xc3,0x18,0x96,0x05,0x9a,0x07,0x12,0x80,0xe2,0xeb,0x27,0xb2,0x75,
    0x09,0x83,0x2c,0x1a,0x1b,0x6e,0x5a,0xa0,0x52,0x3b,0xd6,0xb3,0x29,0xe3,0x2f,0x84,
    0x53,0xd1,0x00,0xed,0x20,0xfc,0xb1,0x5b,0x6a,0xcb,0xbe,0x39,0x4a,0x4c,0x58,0xcf,
    0xd0,0xef,0xaa,0xfb,0x43,0x4d,0x33,0x85,0x45,0xf9,0x02,0x7f,0x50,0x3c,0x9f,0xa8,
    0x51,0xa3,0x40,0x8f,0x92,0x9d,0x38,0xf5,0xbc,0xb6,0xda,0x21,0x10,0xff,0xf3,0xd2,
    0xcd,0x0c,0x13,0xec,0x5f,0x97,0x44,0x17,0xc4,0xa7,0x7e,0x3d,0x64,0x5d,0x19,0x73,
    0x60,0x81,0x4f,0xdc,0x22,0x2a,0x90,0x88,0x46,0xee,0xb8,0x14,0xde,0x5e,0x0b,0xdb,
    0xe0,0x32,0x3a,0x0a,0x49,0x06,0x24,0x5c,0xc2,0xd3,0xac,0x62,0x91,0x95,0xe4,0x79,
    0xe7,0xc8,0x37,0x6d,0x8d,0xd5,0x4e,0xa9,0x6c,0x56,0xf4,0xea,0x65,0x7a,0xae,0x08,
    0xba,0x78,0x25,0x2e,0x1c,0xa6,0xb4,0xc6,0xe8,0xdd,0x74,0x1f,0x4b,0xbd,0x8b,0x8a,
    0x70,0x3e,0xb5,0x66,0x48,0x03,0xf6,0x0e,0x61,0x35,0x57,0xb9,0x86,0xc1,0x1d,0x9e,
    0xe1,0xf8,0x98,0x11,0x69,0xd9,0x8e,0x94,0x9b,0x1e,0x87,0xe9,0xce,0x55,0x28,0xdf,
    0x8c,0xa1,0x89,0x0d,0xbf,0xe6,0x42,0x68,0x41,0x99,0x2d,0x0f,0xb0,0x54,0xbb,0x16,
};

// AES inverse S-box
static const uint8_t INV_SBOX[256] = {
    0x52,0x09,0x6a,0xd5,0x30,0x36,0xa5,0x38,0xbf,0x40,0xa3,0x9e,0x81,0xf3,0xd7,0xfb,
    0x7c,0xe3,0x39,0x82,0x9b,0x2f,0xff,0x87,0x34,0x8e,0x43,0x44,0xc4,0xde,0xe9,0xcb,
    0x54,0x7b,0x94,0x32,0xa6,0xc2,0x23,0x3d,0xee,0x4c,0x95,0x0b,0x42,0xfa,0xc3,0x4e,
    0x08,0x2e,0xa1,0x66,0x28,0xd9,0x24,0xb2,0x76,0x5b,0xa2,0x49,0x6d,0x8b,0xd1,0x25,
    0x72,0xf8,0xf6,0x64,0x86,0x68,0x98,0x16,0xd4,0xa4,0x5c,0xcc,0x5d,0x65,0xb6,0x92,
    0x6c,0x70,0x48,0x50,0xfd,0xed,0xb9,0xda,0x5e,0x15,0x46,0x57,0xa7,0x8d,0x9d,0x84,
    0x90,0xd8,0xab,0x00,0x8c,0xbc,0xd3,0x0a,0xf7,0xe4,0x58,0x05,0xb8,0xb3,0x45,0x06,
    0xd0,0x2c,0x1e,0x8f,0xca,0x3f,0x0f,0x02,0xc1,0xaf,0xbd,0x03,0x01,0x13,0x8a,0x6b,
    0x3a,0x91,0x11,0x41,0x4f,0x67,0xdc,0xea,0x97,0xf2,0xcf,0xce,0xf0,0xb4,0xe6,0x73,
    0x96,0xac,0x74,0x22,0xe7,0xad,0x35,0x85,0xe2,0xf9,0x37,0xe8,0x1c,0x75,0xdf,0x6e,
    0x47,0xf1,0x1a,0x71,0x1d,0x29,0xc5,0x89,0x6f,0xb7,0x62,0x0e,0xaa,0x18,0xbe,0x1b,
    0xfc,0x56,0x3e,0x4b,0xc6,0xd2,0x79,0x20,0x9a,0xdb,0xc0,0xfe,0x78,0xcd,0x5a,0xf4,
    0x1f,0xdd,0xa8,0x33,0x88,0x07,0xc7,0x31,0xb1,0x12,0x10,0x59,0x27,0x80,0xec,0x5f,
    0x60,0x51,0x7f,0xa9,0x19,0xb5,0x4a,0x0d,0x2d,0xe5,0x7a,0x9f,0x93,0xc9,0x9c,0xef,
    0xa0,0xe0,0x3b,0x4d,0xae,0x2a,0xf5,0xb0,0xc8,0xeb,0xbb,0x3c,0x83,0x53,0x99,0x61,
    0x17,0x2b,0x04,0x7e,0xba,0x77,0xd6,0x26,0xe1,0x69,0x14,0x63,0x55,0x21,0x0c,0x7d,
};

// Round constants
static const uint8_t RCON[10] = {
    0x01,0x02,0x04,0x08,0x10,0x20,0x40,0x80,0x1b,0x36
};

// GF(2^8) multiplication by 2
static inline uint8_t xtime(uint8_t x) {
    return (x << 1) ^ ((x & 0x80) ? 0x1b : 0);
}

// GF(2^8) multiplication
static inline uint8_t gmul(uint8_t a, uint8_t b) {
    uint8_t r = 0;
    while (b) {
        if (b & 1) r ^= a;
        a = xtime(a);
        b >>= 1;
    }
    return r;
}

// Key schedule: expand 16-byte key to 176 bytes (11 x 16)
static void key_expand(const uint8_t key[16], uint8_t w[176]) {
    for (int i = 0; i < 16; i++) w[i] = key[i];
    for (int i = 16; i < 176; i += 4) {
        uint8_t t[4];
        t[0] = w[i-4]; t[1] = w[i-3]; t[2] = w[i-2]; t[3] = w[i-1];
        if (i % 16 == 0) {
            // RotWord + SubWord + Rcon
            uint8_t tmp = t[0];
            t[0] = SBOX[t[1]] ^ RCON[i/16 - 1];
            t[1] = SBOX[t[2]];
            t[2] = SBOX[t[3]];
            t[3] = SBOX[tmp];
        }
        w[i+0] = w[i-16] ^ t[0];
        w[i+1] = w[i-15] ^ t[1];
        w[i+2] = w[i-14] ^ t[2];
        w[i+3] = w[i-13] ^ t[3];
    }
}

// AddRoundKey: XOR state with round key
static void add_round_key(uint8_t state[16], const uint8_t *rk) {
    for (int i = 0; i < 16; i++) state[i] ^= rk[i];
}

// SubBytes
static void sub_bytes(uint8_t state[16]) {
    for (int i = 0; i < 16; i++) state[i] = SBOX[state[i]];
}
static void inv_sub_bytes(uint8_t state[16]) {
    for (int i = 0; i < 16; i++) state[i] = INV_SBOX[state[i]];
}

// ShiftRows (state is column-major: s[col*4 + row])
static void shift_rows(uint8_t s[16]) {
    uint8_t t;
    // Row 1: left-rotate 1
    t=s[1]; s[1]=s[5]; s[5]=s[9]; s[9]=s[13]; s[13]=t;
    // Row 2: left-rotate 2
    t=s[2]; s[2]=s[10]; s[10]=t;
    t=s[6]; s[6]=s[14]; s[14]=t;
    // Row 3: left-rotate 3
    t=s[3]; s[3]=s[15]; s[15]=s[11]; s[11]=s[7]; s[7]=t;
}
static void inv_shift_rows(uint8_t s[16]) {
    uint8_t t;
    // Row 1: right-rotate 1
    t=s[13]; s[13]=s[9]; s[9]=s[5]; s[5]=s[1]; s[1]=t;
    // Row 2: right-rotate 2
    t=s[2]; s[2]=s[10]; s[10]=t;
    t=s[6]; s[6]=s[14]; s[14]=t;
    // Row 3: right-rotate 3
    t=s[7]; s[7]=s[11]; s[11]=s[15]; s[15]=s[3]; s[3]=t;
}

// MixColumns
static void mix_columns(uint8_t s[16]) {
    for (int c = 0; c < 4; c++) {
        uint8_t *col = s + c*4;
        uint8_t a = col[0], b = col[1], cc = col[2], d = col[3];
        col[0] = gmul(2,a) ^ gmul(3,b) ^ cc ^ d;
        col[1] = a ^ gmul(2,b) ^ gmul(3,cc) ^ d;
        col[2] = a ^ b ^ gmul(2,cc) ^ gmul(3,d);
        col[3] = gmul(3,a) ^ b ^ cc ^ gmul(2,d);
    }
}
static void inv_mix_columns(uint8_t s[16]) {
    for (int c = 0; c < 4; c++) {
        uint8_t *col = s + c*4;
        uint8_t a = col[0], b = col[1], cc = col[2], d = col[3];
        col[0] = gmul(0x0e,a) ^ gmul(0x0b,b) ^ gmul(0x0d,cc) ^ gmul(0x09,d);
        col[1] = gmul(0x09,a) ^ gmul(0x0e,b) ^ gmul(0x0b,cc) ^ gmul(0x0d,d);
        col[2] = gmul(0x0d,a) ^ gmul(0x09,b) ^ gmul(0x0e,cc) ^ gmul(0x0b,d);
        col[3] = gmul(0x0b,a) ^ gmul(0x0d,b) ^ gmul(0x09,cc) ^ gmul(0x0e,d);
    }
}

// AES-128 encrypt one block (in-place, column-major state)
static void aes128_encrypt(uint8_t block[16], const uint8_t key[16]) {
    uint8_t w[176];
    key_expand(key, w);

    // AES bytes are column-major by spec: no transposition needed
    uint8_t state[16];
    for (int i = 0; i < 16; i++) state[i] = block[i];

    add_round_key(state, w);
    for (int round = 1; round <= 9; round++) {
        sub_bytes(state);
        shift_rows(state);
        mix_columns(state);
        add_round_key(state, w + round*16);
    }
    // Final round (no MixColumns)
    sub_bytes(state);
    shift_rows(state);
    add_round_key(state, w + 160);

    for (int i = 0; i < 16; i++) block[i] = state[i];
}

// AES-128 decrypt one block (in-place)
static void aes128_decrypt(uint8_t block[16], const uint8_t key[16]) {
    uint8_t w[176];
    key_expand(key, w);

    uint8_t state[16];
    for (int i = 0; i < 16; i++) state[i] = block[i];

    add_round_key(state, w + 160);
    for (int round = 9; round >= 1; round--) {
        inv_shift_rows(state);
        inv_sub_bytes(state);
        add_round_key(state, w + round*16);
        inv_mix_columns(state);
    }
    inv_shift_rows(state);
    inv_sub_bytes(state);
    add_round_key(state, w);

    for (int i = 0; i < 16; i++) block[i] = state[i];
}

// -- Test vectors ----------------------------------------------------------

static void test_vectors(void) {
    log_write(NONE, "\n=== NIST FIPS 197 test vectors ===\n");

    // FIPS 197 Appendix B
    static const uint8_t key_b[16] = {
        0x2b,0x7e,0x15,0x16,0x28,0xae,0xd2,0xa6,
        0xab,0xf7,0x15,0x88,0x09,0xcf,0x4f,0x3c
    };
    static const uint8_t pt_b[16] = {
        0x32,0x43,0xf6,0xa8,0x88,0x5a,0x30,0x8d,
        0x31,0x31,0x98,0xa2,0xe0,0x37,0x07,0x34
    };
    static const uint8_t ct_b[16] = {
        0x39,0x25,0x84,0x1d,0x02,0xdc,0x09,0xfb,
        0xdc,0x11,0x85,0x97,0x19,0x6a,0x0b,0x32
    };

    uint8_t block[16];
    for (int i = 0; i < 16; i++) block[i] = pt_b[i];
    aes128_encrypt(block, key_b);
    check_block("FIPS-197 App B: encrypt", block, ct_b);

    for (int i = 0; i < 16; i++) block[i] = ct_b[i];
    aes128_decrypt(block, key_b);
    check_block("FIPS-197 App B: decrypt", block, pt_b);

    // FIPS 197 Appendix C.1 (128-bit key)
    static const uint8_t key_c[16] = {
        0x00,0x01,0x02,0x03,0x04,0x05,0x06,0x07,
        0x08,0x09,0x0a,0x0b,0x0c,0x0d,0x0e,0x0f
    };
    static const uint8_t pt_c[16] = {
        0x00,0x11,0x22,0x33,0x44,0x55,0x66,0x77,
        0x88,0x99,0xaa,0xbb,0xcc,0xdd,0xee,0xff
    };
    static const uint8_t ct_c[16] = {
        0x69,0xc4,0xe0,0xd8,0x6a,0x7b,0x04,0x30,
        0xd8,0xcd,0xb7,0x80,0x70,0xb4,0xc5,0x5a
    };

    for (int i = 0; i < 16; i++) block[i] = pt_c[i];
    aes128_encrypt(block, key_c);
    check_block("FIPS-197 App C.1: encrypt", block, ct_c);

    for (int i = 0; i < 16; i++) block[i] = ct_c[i];
    aes128_decrypt(block, key_c);
    check_block("FIPS-197 App C.1: decrypt", block, pt_c);

    // NIST AESAVS Known Answer Test: all-zero key, all-zero plaintext
    static const uint8_t key_z[16] = {0};
    static const uint8_t pt_z[16]  = {0};
    static const uint8_t ct_z[16] = {
        0x66,0xe9,0x4b,0xd4,0xef,0x8a,0x2c,0x3b,
        0x88,0x4c,0xfa,0x59,0xca,0x34,0x2b,0x2e
    };

    for (int i = 0; i < 16; i++) block[i] = pt_z[i];
    aes128_encrypt(block, key_z);
    check_block("all-zero key/pt: encrypt", block, ct_z);

    for (int i = 0; i < 16; i++) block[i] = ct_z[i];
    aes128_decrypt(block, key_z);
    check_block("all-zero key/pt: decrypt", block, pt_z);

    // NIST SP 800-38A Table B.1 AES-128 ECB Block 1
    // (same key as FIPS-197 App B, different plaintext)
    static const uint8_t key_38a[16] = {
        0x2b,0x7e,0x15,0x16,0x28,0xae,0xd2,0xa6,
        0xab,0xf7,0x15,0x88,0x09,0xcf,0x4f,0x3c
    };
    static const uint8_t pt_38a[16] = {
        0x6b,0xc1,0xbe,0xe2,0x2e,0x40,0x9f,0x96,
        0xe9,0x3d,0x7e,0x11,0x73,0x93,0x17,0x2a
    };
    static const uint8_t ct_38a[16] = {
        0x3a,0xd7,0x7b,0xb4,0x0d,0x7a,0x36,0x60,
        0xa8,0x9e,0xca,0xf3,0x24,0x66,0xef,0x97
    };

    for (int i = 0; i < 16; i++) block[i] = pt_38a[i];
    aes128_encrypt(block, key_38a);
    check_block("SP 800-38A Block1: encrypt", block, ct_38a);

    for (int i = 0; i < 16; i++) block[i] = ct_38a[i];
    aes128_decrypt(block, key_38a);
    check_block("SP 800-38A Block1: decrypt", block, pt_38a);
}

static void test_roundtrip(void) {
    log_write(NONE, "\n=== Encrypt-decrypt round-trip ===\n");

    static const uint8_t key[16] = {
        0xde,0xad,0xbe,0xef,0xca,0xfe,0xba,0xbe,
        0x12,0x34,0x56,0x78,0x9a,0xbc,0xde,0xf0
    };
    static const uint8_t original[16] = {
        0x48,0x65,0x6c,0x6c,0x6f,0x2c,0x20,0x57,  // "Hello, W"
        0x6f,0x72,0x6c,0x64,0x21,0x00,0x00,0x00   // "orld!   "
    };

    uint8_t enc[16];
    for (int i = 0; i < 16; i++) enc[i] = original[i];
    aes128_encrypt(enc, key);

    // Encrypted should differ from original
    int differs = 0;
    for (int i = 0; i < 16; i++) {
        if (enc[i] != original[i]) { differs = 1; break; }
    }
    if (differs) {
        log_write(NONE, "  PASS  ciphertext differs from plaintext\n"); g_pass++;
    } else {
        log_write(NONE, "  FAIL  ciphertext same as plaintext\n"); g_fail++;
    }

    aes128_decrypt(enc, key);
    check_block("round-trip: decrypt(encrypt(pt)) = pt", enc, original);
}

// -- Main ------------------------------------------------------------------

int main(void) {
    uart_puts("=== AES-128 Test ===\n");
    if (log_init("aes128.log") != 0) {
        uart_puts("ERROR: log_init failed\n"); return 1;
    }

    log_write(NONE, "=== AES-128 ECB Test (NIST FIPS 197) ===\n");

    test_vectors();
    test_roundtrip();

    log_write(NONE, "\n=== Summary ===\n");
    log_write(NONE, "  PASS: %d\n", g_pass);
    log_write(NONE, "  FAIL: %d\n", g_fail);
    log_write(NONE, "  %s\n", g_fail == 0 ? "ALL TESTS PASSED" : "SOME TESTS FAILED");

    log_close();
    uart_puts(g_fail == 0 ? "ALL PASSED\n" : "SOME FAILED\n");
    return g_fail;
}
