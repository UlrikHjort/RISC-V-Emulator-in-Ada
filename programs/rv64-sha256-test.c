/* **************************************************************************
 *               RISC-V Emulator - RV64 SHA-256 Test
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
 * **************************************************************************
 * SHA-256 (FIPS 180-4) compiled for and running on RV64.
 * SHA-256 operates on 32-bit words, but on RV64 all pointer arithmetic,
 * loop counters, and the message-length accumulator are 64-bit natively.
 *
 * Test vectors (FIPS 180-4 / NIST):
 *   SHA-256("")    = e3b0c442 98fc1c14 9afbf4c8 996fb924
 *                    27ae41e4 649b934c a495991b 7852b855
 *   SHA-256("abc") = ba7816bf 8f01cfea 414140de 5dae2223
 *                    b00361a3 96177a9c b410ff61 f20015ad
 *   SHA-256("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq")
 *                  = 248d6a61 d20638b8 e5c02693 0c3e6039
 *                    a33ce459 64ff2167 f6ecedd4 19db06c1
 */

#include <stdint.h>
#include "log.h"

/* ---- SHA-256 constants (FIPS 180-4 Sec.4.2.2) -------------------------------- */

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

/* ---- Bit operations ------------------------------------------------------- */

#define ROTR(x,n)  (((x) >> (n)) | ((x) << (32-(n))))
#define CH(x,y,z)  (((x) & (y)) ^ (~(x) & (z)))
#define MAJ(x,y,z) (((x) & (y)) ^ ((x) & (z)) ^ ((y) & (z)))
#define SIG0(x)    (ROTR(x, 2) ^ ROTR(x,13) ^ ROTR(x,22))
#define SIG1(x)    (ROTR(x, 6) ^ ROTR(x,11) ^ ROTR(x,25))
#define sig0(x)    (ROTR(x, 7) ^ ROTR(x,18) ^ ((x) >>  3))
#define sig1(x)    (ROTR(x,17) ^ ROTR(x,19) ^ ((x) >> 10))

/* ---- Single 512-bit block compression ------------------------------------- */

static void sha256_block(uint32_t h[8], const uint8_t blk[64])
{
    uint32_t W[64];
    uint64_t i;   /* 64-bit loop index -- natural on RV64 */

    for (i = 0; i < 16; i++)
        W[i] = ((uint32_t)blk[i*4  ] << 24) | ((uint32_t)blk[i*4+1] << 16)
             | ((uint32_t)blk[i*4+2] <<  8) |  (uint32_t)blk[i*4+3];
    for (i = 16; i < 64; i++)
        W[i] = sig1(W[i-2]) + W[i-7] + sig0(W[i-15]) + W[i-16];

    uint32_t a=h[0], b=h[1], c=h[2], d=h[3];
    uint32_t e=h[4], f=h[5], g=h[6], hh=h[7];

    for (i = 0; i < 64; i++) {
        uint32_t T1 = hh + SIG1(e) + CH(e,f,g) + K[i] + W[i];
        uint32_t T2 = SIG0(a) + MAJ(a,b,c);
        hh=g; g=f; f=e; e=d+T1;
        d=c;  c=b; b=a; a=T1+T2;
    }

    h[0]+=a; h[1]+=b; h[2]+=c; h[3]+=d;
    h[4]+=e; h[5]+=f; h[6]+=g; h[7]+=hh;
}

/* ---- Full SHA-256 --------------------------------------------------------- */
/* len is uint64_t: on RV64 this is handled natively in a single register.    */

static void sha256(const uint8_t *msg, uint64_t len, uint32_t out[8])
{
    out[0] = 0x6a09e667u; out[1] = 0xbb67ae85u;
    out[2] = 0x3c6ef372u; out[3] = 0xa54ff53au;
    out[4] = 0x510e527fu; out[5] = 0x9b05688cu;
    out[6] = 0x1f83d9abu; out[7] = 0x5be0cd19u;

    uint8_t blk[64];
    uint64_t pos = 0;

    while (pos + 64 <= len) {
        sha256_block(out, msg + pos);
        pos += 64;
    }

    uint64_t rem = len - pos;
    for (uint64_t i = 0; i < rem; i++) blk[i] = msg[pos + i];

    blk[rem++] = 0x80u;

    if (rem > 56) {
        while (rem < 64) blk[rem++] = 0;
        sha256_block(out, blk);
        rem = 0;
    }

    while (rem < 56) blk[rem++] = 0;

    /* 64-bit big-endian bit-length -- on RV64 a single SD would suffice,
     * but we keep byte-by-byte for portability with the algorithm spec. */
    uint64_t bits = len * 8;
    blk[56] = (uint8_t)(bits >> 56); blk[57] = (uint8_t)(bits >> 48);
    blk[58] = (uint8_t)(bits >> 40); blk[59] = (uint8_t)(bits >> 32);
    blk[60] = (uint8_t)(bits >> 24); blk[61] = (uint8_t)(bits >> 16);
    blk[62] = (uint8_t)(bits >>  8); blk[63] = (uint8_t)(bits);
    sha256_block(out, blk);
}

/* ---- Test helpers --------------------------------------------------------- */

static int g_pass = 0, g_fail = 0;

static void chk(const char *label, int ok)
{
    if (ok) { log_write(NONE, "PASS %s\n", label); g_pass++; }
    else     { log_write(NONE, "FAIL %s\n", label); g_fail++; }
}

static int hash_eq(const uint32_t a[8], const uint32_t b[8])
{
    for (int i = 0; i < 8; i++) if (a[i] != b[i]) return 0;
    return 1;
}

static int slen(const char *s) { int n = 0; while (s[n]) n++; return n; }

/* ---- Tests ---------------------------------------------------------------- */

static void test_empty(void)
{
    static const uint32_t exp[8] = {
        0xe3b0c442u, 0x98fc1c14u, 0x9afbf4c8u, 0x996fb924u,
        0x27ae41e4u, 0x649b934cu, 0xa495991bu, 0x7852b855u
    };
    uint32_t h[8];
    sha256((const uint8_t *)"", 0, h);
    chk("SHA-256(\"\") FIPS 180-4", hash_eq(h, exp));
}

static void test_abc(void)
{
    static const uint32_t exp[8] = {
        0xba7816bfu, 0x8f01cfeau, 0x414140deu, 0x5dae2223u,
        0xb00361a3u, 0x96177a9cu, 0xb410ff61u, 0xf20015adu
    };
    uint32_t h[8];
    sha256((const uint8_t *)"abc", 3, h);
    chk("SHA-256(\"abc\") FIPS 180-4", hash_eq(h, exp));
}

static void test_two_blocks(void)
{
    /* 56-byte message -> two 512-bit blocks after padding */
    static const char msg[] =
        "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq";
    static const uint32_t exp[8] = {
        0x248d6a61u, 0xd20638b8u, 0xe5c02693u, 0x0c3e6039u,
        0xa33ce459u, 0x64ff2167u, 0xf6ecedd4u, 0x19db06c1u
    };
    uint32_t h[8];
    sha256((const uint8_t *)msg, (uint64_t)slen(msg), h);
    chk("SHA-256(56-byte NIST msg) FIPS 180-4", hash_eq(h, exp));
}

static void test_determinism(void)
{
    uint32_t h1[8], h2[8];
    sha256((const uint8_t *)"hello world", 11, h1);
    sha256((const uint8_t *)"hello world", 11, h2);
    chk("determinism: same input same hash", hash_eq(h1, h2));
}

static void test_sensitivity(void)
{
    uint32_t ha[8], hb[8];
    sha256((const uint8_t *)"abc", 3, ha);
    sha256((const uint8_t *)"abd", 3, hb);
    int diff = 0;
    for (int i = 0; i < 8; i++) if (ha[i] != hb[i]) diff++;
    chk("avalanche: all 8 words differ for abc vs abd", diff == 8);
}

/* Test that sha256 handles messages longer than 64 bytes (multi-block path)
 * using a pointer arithmetic pattern that exercises 64-bit address offsets. */
static void test_long_msg(void)
{
    /* "aaaa...a" x 128 -- three blocks */
    static uint8_t buf[128];
    for (uint64_t i = 0; i < 128; i++) buf[i] = 'a';

    /* Python: hashlib.sha256(b'a'*128).hexdigest()
     * = 6836cf13 bac400e9 105071cd 6af47084
     *   dfacad4e 5e302c94 bfed24e0 13afb73e */
    static const uint32_t exp[8] = {
        0x6836cf13u, 0xbac400e9u, 0x105071cdu, 0x6af47084u,
        0xdfacad4eu, 0x5e302c94u, 0xbfed24e0u, 0x13afb73eu
    };
    uint32_t h[8];
    sha256(buf, 128, h);
    chk("SHA-256(128*'a') multi-block", hash_eq(h, exp));
}

/* ---- Main ----------------------------------------------------------------- */

int main(void)
{
    log_init("rv64-sha256-test.log");
    log_write(NONE, "RV64 SHA-256 Test\n\n");

    test_empty();
    test_abc();
    test_two_blocks();
    test_determinism();
    test_sensitivity();
    test_long_msg();

    log_write(NONE, "\n%d PASS  %d FAIL\n", g_pass, g_fail);
    log_close();
    return g_fail;
}
