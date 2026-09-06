/* **************************************************************************
 *        RISC-V Emulator - Ed25519 (RFC 8032 Sec.6.1) test vectors
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

/* ed25519-test.c -- Ed25519 (RFC 8032 Sec.6.1) test vectors
 *
 * Test vectors 1 and 2 from RFC 8032 Section 6.1.
 * By Ulrik Hørlyk Hjort 2026
 */

#include <stdint.h>
#include "log.h"
#include "ed25519.h"
#include "sha512.h"

static int g_pass = 0, g_fail = 0;

static void chk(const char *label, int ok)
{
    if (ok) { log_write(NONE, "PASS  %s\n", label); g_pass++; }
    else     { log_write(NONE, "FAIL  %s\n", label); g_fail++; }
}

static int bytes_eq(const uint8_t *a, const uint8_t *b, uint32_t n)
{
    uint32_t i;
    for (i = 0; i < n; i++) if (a[i] != b[i]) return 0;
    return 1;
}

static void log_hex16(const char *lbl, const uint8_t *b, uint32_t n)
{
    uint32_t i;
    log_write(NONE, "  %s: ", lbl);
    for (i = 0; i < n && i < 16; i++) log_write(NONE, "%x", (unsigned)b[i]);
    if (n > 16) log_write(NONE, "...");
    log_write(NONE, "\n");
}

/* -- RFC 8032 Sec.6.1 Test Vector 1 (empty message) -------------------------- */

static const uint8_t TV1_SEED[32] = {
    0x9d,0x61,0xb1,0x9d,0xef,0xfd,0x5a,0x60,
    0xba,0x84,0x4a,0xf4,0x92,0xec,0x2c,0x44,
    0xda,0x4d,0xa0,0x55,0x73,0xd8,0x63,0x26,
    0xa9,0x84,0x11,0x89,0x05,0x50,0xfb,0x4c
};

static const uint8_t TV1_PK[32] = {
    0xaf,0x8d,0x38,0xf6,0x13,0x17,0x8c,0x2b,
    0x62,0x2c,0x53,0x5b,0x15,0x19,0x78,0x92,
    0xf4,0x2c,0x7d,0xfd,0x63,0x97,0x31,0x0f,
    0x95,0x27,0xc4,0x6f,0xf0,0x69,0x21,0xa1
};

static const uint8_t TV1_SIG[64] = {
    0xa9,0xd8,0x4a,0x51,0x63,0xb5,0x9a,0x9e,
    0xf0,0xf9,0xb3,0x92,0xf6,0xba,0x90,0x7e,
    0xed,0xb7,0xbf,0xa7,0xd8,0x2d,0x5b,0x8c,
    0xf3,0xc7,0xd3,0x90,0xf4,0xa5,0x88,0x7a,
    0x59,0x82,0xa3,0x75,0xe7,0x7e,0x43,0xdf,
    0xe9,0xbe,0x29,0x3e,0xb9,0xb8,0x9a,0xe0,
    0x89,0xc6,0x57,0xa0,0xd0,0x32,0xac,0x59,
    0xcb,0x48,0xb6,0x74,0x59,0xb4,0x1e,0x0e
};

/* -- RFC 8032 Sec.6.1 Test Vector 2 (1-byte message: 0x72) ------------------- */

static const uint8_t TV2_SEED[32] = {
    0x4c,0xcd,0x08,0x9b,0x28,0xff,0x96,0xda,
    0x9d,0xb6,0xc3,0x46,0xec,0x11,0x4e,0x0f,
    0x5b,0x8a,0x31,0x9f,0x35,0xab,0xa6,0x24,
    0xda,0x8c,0xf6,0xed,0x4d,0x0b,0x14,0x3c
};

static const uint8_t TV2_PK[32] = {
    0xb9,0x5a,0x22,0x8a,0xc2,0x0a,0x7c,0x78,
    0xbd,0xae,0x5e,0x1c,0x2c,0x99,0xe6,0x78,
    0xbf,0x32,0x68,0x3a,0xc2,0xe2,0xa6,0x3f,
    0x76,0x4c,0x5c,0xb6,0x04,0x29,0x26,0xb6
};

static const uint8_t TV2_MSG[1] = { 0x72 };

static const uint8_t TV2_SIG[64] = {
    0xff,0x77,0x3d,0xf2,0x6c,0x14,0x5a,0xef,
    0x28,0x41,0xb5,0x07,0xc6,0xe8,0x98,0x24,
    0x82,0x7b,0xd0,0x58,0xaf,0xd7,0xa3,0x6e,
    0xf0,0x1d,0x1d,0x24,0x40,0xff,0x1b,0x19,
    0x82,0x79,0x07,0x97,0x8d,0xe2,0xb3,0x62,
    0xa6,0x3a,0x04,0xee,0xaa,0x68,0x0e,0x1b,
    0x0c,0x3c,0x53,0xbd,0x96,0x74,0x2e,0x12,
    0x5e,0xdc,0xdc,0x80,0xba,0xf1,0x7a,0x01
};

/* -- Tests -----------------------------------------------------------------*/

/* SHA-512 sanity: SHA-512("abc") */
static void test_sha512_abc(void)
{
    /* SHA-512("abc") per NIST:
     * ddaf35a193617aba cc417349ae204131 12e6fa4e89a97ea2 0a9eeee64b55d39a
     * 2192992a274fc1a8 36ba3c23a3feebbd 454d4423643ce80e 2a9ac94fa54ca49f */
    static const uint8_t exp[64] = {
        0xdd,0xaf,0x35,0xa1,0x93,0x61,0x7a,0xba,
        0xcc,0x41,0x73,0x49,0xae,0x20,0x41,0x31,
        0x12,0xe6,0xfa,0x4e,0x89,0xa9,0x7e,0xa2,
        0x0a,0x9e,0xee,0xe6,0x4b,0x55,0xd3,0x9a,
        0x21,0x92,0x99,0x2a,0x27,0x4f,0xc1,0xa8,
        0x36,0xba,0x3c,0x23,0xa3,0xfe,0xeb,0xbd,
        0x45,0x4d,0x44,0x23,0x64,0x3c,0xe8,0x0e,
        0x2a,0x9a,0xc9,0x4f,0xa5,0x4c,0xa4,0x9f
    };
    uint8_t got[64];
    sha512((const uint8_t *)"abc", 3, got);
    log_hex16("sha512(abc) got", got, 64);
    log_hex16("sha512(abc) exp", exp, 64);
    chk("SHA-512(abc) matches NIST", bytes_eq(got, exp, 64));
}

/* Test 1: keypair from known seed matches known public key */
static void test_keypair_tv1(void)
{
    uint8_t pk[32], sk[64];
    ed25519_keypair(pk, sk, TV1_SEED);
    log_hex16("pk got", pk, 32);
    log_hex16("pk exp", TV1_PK, 32);
    chk("TV1 keypair: public key matches RFC 8032", bytes_eq(pk, TV1_PK, 32));
}

/* Test 2: sign empty message matches known signature */
static void test_sign_tv1(void)
{
    uint8_t pk[32], sk[64], sig[64];
    ed25519_keypair(pk, sk, TV1_SEED);
    ed25519_sign(sig, (const uint8_t *)"", 0, sk);
    log_hex16("sig got", sig, 64);
    log_hex16("sig exp", TV1_SIG, 64);
    chk("TV1 sign empty msg: sig matches RFC 8032", bytes_eq(sig, TV1_SIG, 64));
}

/* Test 3: verify known-good signature returns 1 */
static void test_verify_tv1(void)
{
    int r = ed25519_verify(TV1_SIG, (const uint8_t *)"", 0, TV1_PK);
    chk("TV1 verify known-good sig returns 1", r == 1);
}

/* Test 4: verify with flipped bit in sig returns 0 */
static void test_tampered_sig(void)
{
    uint8_t sig[64];
    int i;
    for (i = 0; i < 64; i++) sig[i] = TV1_SIG[i];
    sig[0] ^= 0x01;
    int r = ed25519_verify(sig, (const uint8_t *)"", 0, TV1_PK);
    chk("TV1 tampered sig (flip bit 0 of R) returns 0", r == 0);
}

/* Test 5: verify with wrong message returns 0 */
static void test_wrong_msg(void)
{
    uint8_t msg[1] = { 0xab };
    int r = ed25519_verify(TV1_SIG, msg, 1, TV1_PK);
    chk("TV1 sig vs wrong message returns 0", r == 0);
}

/* Test 6: round-trip sign+verify */
static void test_roundtrip(void)
{
    static const uint8_t seed[32] = {
        0xde,0xad,0xbe,0xef,0xca,0xfe,0xba,0xbe,
        0x01,0x23,0x45,0x67,0x89,0xab,0xcd,0xef,
        0xfe,0xdc,0xba,0x98,0x76,0x54,0x32,0x10,
        0x11,0x22,0x33,0x44,0x55,0x66,0x77,0x88
    };
    static const uint8_t msg[] = { 'R','V','3','2','E','d','2','5','5','1','9' };
    uint8_t pk[32], sk[64], sig[64];
    ed25519_keypair(pk, sk, seed);
    ed25519_sign(sig, msg, 11, sk);
    int r = ed25519_verify(sig, msg, 11, pk);
    chk("Round-trip: sign+verify returns 1", r == 1);
}

/* Test 7: wrong public key -> verify returns 0 */
static void test_wrong_pubkey(void)
{
    /* Use TV2's public key to verify TV1's signature */
    int r = ed25519_verify(TV1_SIG, (const uint8_t *)"", 0, TV2_PK);
    chk("TV1 sig with TV2 public key returns 0", r == 0);
}

/* Test 8: keypair TV2 matches */
static void test_keypair_tv2(void)
{
    uint8_t pk[32], sk[64];
    ed25519_keypair(pk, sk, TV2_SEED);
    log_hex16("TV2 pk got", pk, 32);
    log_hex16("TV2 pk exp", TV2_PK, 32);
    chk("TV2 keypair: public key matches RFC 8032", bytes_eq(pk, TV2_PK, 32));
}

/* Test 9: sign TV2 vector and verify */
static void test_sign_verify_tv2(void)
{
    uint8_t pk[32], sk[64], sig[64];
    ed25519_keypair(pk, sk, TV2_SEED);
    ed25519_sign(sig, TV2_MSG, 1, sk);
    log_hex16("TV2 sig got", sig, 64);
    log_hex16("TV2 sig exp", TV2_SIG, 64);
    int sig_ok = bytes_eq(sig, TV2_SIG, 64);
    chk("TV2 sign 1-byte msg: sig matches RFC 8032", sig_ok);
    int verify_ok = ed25519_verify(sig, TV2_MSG, 1, pk);
    chk("TV2 verify returned 1", verify_ok == 1);
}

int main(void)
{
    if (log_init("ed25519-test.log") != 0) return 1;

    log_write(NONE, "=== Ed25519 (RFC 8032) Test ===\n\n");

    test_sha512_abc();
    test_keypair_tv1();
    test_sign_tv1();
    test_verify_tv1();
    test_tampered_sig();
    test_wrong_msg();
    test_roundtrip();
    test_wrong_pubkey();
    test_keypair_tv2();
    test_sign_verify_tv2();

    log_write(NONE, "\n=== Summary ===\n");
    log_write(NONE, "  PASS: %d\n", g_pass);
    log_write(NONE, "  FAIL: %d\n", g_fail);
    log_write(NONE, "  %s\n", g_fail == 0 ? "ALL TESTS PASSED" : "SOME TESTS FAILED");

    log_close();
    return g_fail;
}
