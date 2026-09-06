/* **************************************************************************
 * RISC-V Emulator - HMAC-SHA256 implementation with RFC 4231 test vectors
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

// hmac-sha256-test.c -- HMAC-SHA256 implementation with RFC 4231 test vectors
//
// Contains a self-contained SHA-256 implementation (FIPS 180-4) and builds
// HMAC-SHA256 on top of it per RFC 2104.
//
// Tests:
//   RFC 4231 Test Case 1: key=20x0x0b, data="Hi There"
//     HMAC = b0344c61 d8db3853 5ca8afce af0bf12b
//            881dc200 c9833da7 26e9376c 2e32cff7
//
//   RFC 4231 Test Case 2: key="Jefe", data="what do ya want for nothing?"
//     HMAC = 5bdcc146 bf60754e 6a042426 089575c7
//            5a003f08 9d273983 9dec58b9 64ec3843
//
//   RFC 4231 Test Case 3: key=20x0xaa, data=50x0xdd
//     HMAC = 773ea91e 36800e46 854db8eb d09181a7
//            2959098b 3ef8c122 d9635514 ced565fe
//
//   RFC 4231 Test Case 4: key={0x01..0x19}, data=50x0xcd
//     HMAC = 82558a38 9a443c0e a4cc8198 99f2083a
//            85f0faa3 e578f807 7a2e3ff4 6729665b
//
//   Determinism: HMAC("abc","abc") called twice gives same result
//   Length sensitivity: HMAC("key","msg") != HMAC("key","msg2")
//
// Build: cd programs && make run-hmac-sha256-test
// By Ulrik Hørlyk Hjort 2026

#include "log.h"
#include <stdint.h>

// -- SHA-256 constants (FIPS 180-4 Sec.4.2.2) -----------------------------------

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
    for (int i = 0; i < 16; i++)
        W[i] = ((uint32_t)blk[i*4  ] << 24) | ((uint32_t)blk[i*4+1] << 16)
             | ((uint32_t)blk[i*4+2] <<  8) |  (uint32_t)blk[i*4+3];
    for (int i = 16; i < 64; i++)
        W[i] = sig1(W[i-2]) + W[i-7] + sig0(W[i-15]) + W[i-16];

    uint32_t a=h[0], b=h[1], c=h[2], d=h[3];
    uint32_t e=h[4], f=h[5], g=h[6], hh=h[7];

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
    out[0] = 0x6a09e667u; out[1] = 0xbb67ae85u;
    out[2] = 0x3c6ef372u; out[3] = 0xa54ff53au;
    out[4] = 0x510e527fu; out[5] = 0x9b05688cu;
    out[6] = 0x1f83d9abu; out[7] = 0x5be0cd19u;

    uint8_t blk[64];
    uint32_t pos = 0;

    while (pos + 64 <= len) {
        sha256_block(out, msg + pos);
        pos += 64;
    }

    uint32_t rem = len - pos;
    for (uint32_t i = 0; i < rem; i++) blk[i] = msg[pos + i];

    blk[rem++] = 0x80u;

    if (rem > 56) {
        while (rem < 64) blk[rem++] = 0;
        sha256_block(out, blk);
        rem = 0;
    }

    while (rem < 56) blk[rem++] = 0;
    uint64_t bits = (uint64_t)len * 8;
    blk[56] = (uint8_t)(bits >> 56); blk[57] = (uint8_t)(bits >> 48);
    blk[58] = (uint8_t)(bits >> 40); blk[59] = (uint8_t)(bits >> 32);
    blk[60] = (uint8_t)(bits >> 24); blk[61] = (uint8_t)(bits >> 16);
    blk[62] = (uint8_t)(bits >>  8); blk[63] = (uint8_t)(bits);
    sha256_block(out, blk);
}

// -- HMAC-SHA256 (RFC 2104) ---------------------------------------------------
//
// If klen > 64: k_0 = SHA256(key) padded with zeros to 64 bytes
// Else:         k_0 = key padded with zeros to 64 bytes
// inner = SHA256( (k_0 XOR ipad) || msg )    ipad = 0x36 repeated 64 times
// outer = SHA256( (k_0 XOR opad) || inner )  opad = 0x5c repeated 64 times
// out = outer as 32 bytes (big-endian)
//
// Uses a stack buffer buf[320]:
//   bytes   0.. 63 = k_0 XOR ipad  (64)
//   bytes  64..319 = msg            (up to 256 bytes)
// Second pass:
//   bytes   0.. 63 = k_0 XOR opad  (64)
//   bytes  64.. 95 = inner digest  (32)

static void hmac_sha256(const uint8_t *key, uint32_t klen,
                        const uint8_t *msg, uint32_t mlen,
                        uint8_t out[32])
{
    uint8_t k0[64];
    uint32_t i;

    // Derive k0
    if (klen > 64u) {
        uint32_t h[8];
        sha256(key, klen, h);
        for (i = 0; i < 8u; i++) {
            k0[i*4+0] = (uint8_t)(h[i] >> 24);
            k0[i*4+1] = (uint8_t)(h[i] >> 16);
            k0[i*4+2] = (uint8_t)(h[i] >>  8);
            k0[i*4+3] = (uint8_t)(h[i]      );
        }
        for (i = 32u; i < 64u; i++) k0[i] = 0;
    } else {
        for (i = 0; i < klen; i++) k0[i] = key[i];
        for (i = klen; i < 64u; i++) k0[i] = 0;
    }

    // Inner hash: SHA256( (k0 XOR ipad) || msg )
    // buf[0..63] = k0 XOR ipad, buf[64..64+mlen-1] = msg
    uint8_t buf[320];
    for (i = 0; i < 64u; i++) buf[i] = k0[i] ^ 0x36u;
    for (i = 0; i < mlen; i++) buf[64u + i] = msg[i];

    uint32_t inner_h[8];
    sha256(buf, 64u + mlen, inner_h);

    // Outer hash: SHA256( (k0 XOR opad) || inner_bytes )
    // buf[0..63] = k0 XOR opad, buf[64..95] = inner digest bytes
    for (i = 0; i < 64u; i++) buf[i] = k0[i] ^ 0x5cu;
    for (i = 0; i < 8u; i++) {
        buf[64u + i*4+0] = (uint8_t)(inner_h[i] >> 24);
        buf[64u + i*4+1] = (uint8_t)(inner_h[i] >> 16);
        buf[64u + i*4+2] = (uint8_t)(inner_h[i] >>  8);
        buf[64u + i*4+3] = (uint8_t)(inner_h[i]      );
    }

    uint32_t outer_h[8];
    sha256(buf, 64u + 32u, outer_h);

    // Serialise result as big-endian bytes
    for (i = 0; i < 8u; i++) {
        out[i*4+0] = (uint8_t)(outer_h[i] >> 24);
        out[i*4+1] = (uint8_t)(outer_h[i] >> 16);
        out[i*4+2] = (uint8_t)(outer_h[i] >>  8);
        out[i*4+3] = (uint8_t)(outer_h[i]      );
    }
}

// -- Test infrastructure ------------------------------------------------------

static int g_pass = 0, g_fail = 0;

/* Print 32 bytes as hex, 4 bytes per %x word (no leading-zero padding needed
   for diagnostics -- we just need to see the values).  log_write only supports
   %x without width, so we print each of the 8 words separately. */
static void log_hmac_bytes(const char *prefix, const uint8_t b[32])
{
    uint32_t w[8];
    for (int i = 0; i < 8; i++)
        w[i] = ((uint32_t)b[i*4+0] << 24) | ((uint32_t)b[i*4+1] << 16)
             | ((uint32_t)b[i*4+2] <<  8) |  (uint32_t)b[i*4+3];
    log_write(NONE, "  %s: %x %x %x %x\n",
              prefix, w[0], w[1], w[2], w[3]);
    log_write(NONE, "         %x %x %x %x\n",
              w[4], w[5], w[6], w[7]);
}

static void check_hmac(const char *label,
                       const uint8_t got[32], const uint8_t exp[32])
{
    int ok = 1;
    for (int i = 0; i < 32; i++) if (got[i] != exp[i]) { ok = 0; break; }
    if (ok) {
        log_write(NONE, "PASS %s\n", label);
        g_pass++;
    } else {
        log_write(NONE, "FAIL %s\n", label);
        log_hmac_bytes("got ", got);
        log_hmac_bytes("want", exp);
        g_fail++;
    }
}

// -- RFC 4231 Test Cases ------------------------------------------------------

static void test_rfc4231_tc1(void)
{
    // Key: 20 bytes of 0x0b
    // Data: "Hi There" (8 bytes)
    // Expected HMAC: b0344c61 d8db3853 5ca8afce af0bf12b
    //                881dc200 c9833da7 26e9376c 2e32cff7
    uint8_t key[20];
    for (int i = 0; i < 20; i++) key[i] = 0x0bu;

    static const uint8_t data[8] = {
        'H','i',' ','T','h','e','r','e'
    };

    static const uint8_t expected[32] = {
        0xb0u,0x34u,0x4cu,0x61u, 0xd8u,0xdbu,0x38u,0x53u,
        0x5cu,0xa8u,0xafu,0xceu, 0xafu,0x0bu,0xf1u,0x2bu,
        0x88u,0x1du,0xc2u,0x00u, 0xc9u,0x83u,0x3du,0xa7u,
        0x26u,0xe9u,0x37u,0x6cu, 0x2eu,0x32u,0xcfu,0xf7u
    };

    uint8_t got[32];
    hmac_sha256(key, 20u, data, 8u, got);
    check_hmac("RFC4231-TC1 key=20*0x0b data=Hi-There", got, expected);
}

static void test_rfc4231_tc2(void)
{
    // Key: "Jefe" (4 bytes: 4a 65 66 65)
    // Data: "what do ya want for nothing?" (28 bytes)
    // Expected HMAC: 5bdcc146 bf60754e 6a042426 089575c7
    //                5a003f08 9d273983 9dec58b9 64ec3843
    static const uint8_t key[4] = { 0x4au, 0x65u, 0x66u, 0x65u };

    static const uint8_t data[28] = {
        'w','h','a','t',' ','d','o',' ',
        'y','a',' ','w','a','n','t',' ',
        'f','o','r',' ','n','o','t','h',
        'i','n','g','?'
    };

    static const uint8_t expected[32] = {
        0x5bu,0xdcu,0xc1u,0x46u, 0xbfu,0x60u,0x75u,0x4eu,
        0x6au,0x04u,0x24u,0x26u, 0x08u,0x95u,0x75u,0xc7u,
        0x5au,0x00u,0x3fu,0x08u, 0x9du,0x27u,0x39u,0x83u,
        0x9du,0xecu,0x58u,0xb9u, 0x64u,0xecu,0x38u,0x43u
    };

    uint8_t got[32];
    hmac_sha256(key, 4u, data, 28u, got);
    check_hmac("RFC4231-TC2 key=Jefe data=what-do-ya-want", got, expected);
}

static void test_rfc4231_tc3(void)
{
    // Key: 20 bytes of 0xaa
    // Data: 50 bytes of 0xdd
    // Expected HMAC: 773ea91e 36800e46 854db8eb d09181a7
    //                2959098b 3ef8c122 d9635514 ced565fe
    uint8_t key[20];
    for (int i = 0; i < 20; i++) key[i] = 0xaau;

    uint8_t data[50];
    for (int i = 0; i < 50; i++) data[i] = 0xddu;

    static const uint8_t expected[32] = {
        0x77u,0x3eu,0xa9u,0x1eu, 0x36u,0x80u,0x0eu,0x46u,
        0x85u,0x4du,0xb8u,0xebu, 0xd0u,0x91u,0x81u,0xa7u,
        0x29u,0x59u,0x09u,0x8bu, 0x3eu,0xf8u,0xc1u,0x22u,
        0xd9u,0x63u,0x55u,0x14u, 0xceu,0xd5u,0x65u,0xfeu
    };

    uint8_t got[32];
    hmac_sha256(key, 20u, data, 50u, got);
    check_hmac("RFC4231-TC3 key=20*0xaa data=50*0xdd", got, expected);
}

static void test_rfc4231_tc4(void)
{
    // Key: 25 bytes {0x01, 0x02, ..., 0x19}
    // Data: 50 bytes of 0xcd
    // Expected HMAC: 82558a38 9a443c0e a4cc8198 99f2083a
    //                85f0faa3 e578f807 7a2e3ff4 6729665b
    uint8_t key[25];
    for (int i = 0; i < 25; i++) key[i] = (uint8_t)(i + 1);

    uint8_t data[50];
    for (int i = 0; i < 50; i++) data[i] = 0xcdu;

    static const uint8_t expected[32] = {
        0x82u,0x55u,0x8au,0x38u, 0x9au,0x44u,0x3cu,0x0eu,
        0xa4u,0xccu,0x81u,0x98u, 0x99u,0xf2u,0x08u,0x3au,
        0x85u,0xf0u,0xfau,0xa3u, 0xe5u,0x78u,0xf8u,0x07u,
        0x7au,0x2eu,0x3fu,0xf4u, 0x67u,0x29u,0x66u,0x5bu
    };

    uint8_t got[32];
    hmac_sha256(key, 25u, data, 50u, got);
    check_hmac("RFC4231-TC4 key=1..25 data=50*0xcd", got, expected);
}

// -- Auxiliary tests ----------------------------------------------------------

static void test_determinism(void)
{
    // Same inputs must always produce the same output
    static const uint8_t key[3] = { 'a','b','c' };
    static const uint8_t msg[3] = { 'a','b','c' };

    uint8_t h1[32], h2[32];
    hmac_sha256(key, 3u, msg, 3u, h1);
    hmac_sha256(key, 3u, msg, 3u, h2);

    int ok = 1;
    for (int i = 0; i < 32; i++) if (h1[i] != h2[i]) { ok = 0; break; }
    if (ok) {
        log_write(NONE, "PASS determinism: HMAC(abc,abc) == HMAC(abc,abc)\n");
        g_pass++;
    } else {
        log_write(NONE, "FAIL determinism: two calls with same inputs differ\n");
        g_fail++;
    }
}

static void test_length_sensitivity(void)
{
    // HMAC("key","msg") must differ from HMAC("key","msg2")
    static const uint8_t key[3] = { 'k','e','y' };
    static const uint8_t msg1[3] = { 'm','s','g' };
    static const uint8_t msg2[4] = { 'm','s','g','2' };

    uint8_t h1[32], h2[32];
    hmac_sha256(key, 3u, msg1, 3u, h1);
    hmac_sha256(key, 3u, msg2, 4u, h2);

    int differ = 0;
    for (int i = 0; i < 32; i++) if (h1[i] != h2[i]) differ++;

    if (differ > 0) {
        log_write(NONE, "PASS length-sensitivity: HMAC(key,msg) != HMAC(key,msg2)\n");
        g_pass++;
    } else {
        log_write(NONE, "FAIL length-sensitivity: different messages gave same HMAC\n");
        g_fail++;
    }
}

// -- Direct SHA-256 sanity check -----------------------------------------------

static void test_sha256_abc(void)
{
    // SHA256("abc") (verified with sha256sum / Python hashlib):
    // ba7816bf 8f01cfea 414140de 5dae2223 b00361a3 96177a9c b410ff61 f20015ad
    static const uint8_t msg[3] = { 'a','b','c' };
    static const uint32_t exp[8] = {
        0xba7816bfu, 0x8f01cfeau, 0x414140deu, 0x5dae2223u,
        0xb00361a3u, 0x96177a9cu, 0xb410ff61u, 0xf20015adu
    };
    uint32_t got[8];
    sha256(msg, 3, got);
    int ok = 1;
    for (int i = 0; i < 8; i++) if (got[i] != exp[i]) { ok = 0; break; }
    if (ok) {
        log_write(NONE, "PASS sha256(abc)\n");
        g_pass++;
    } else {
        log_write(NONE, "FAIL sha256(abc)\n");
        log_write(NONE, "  got : %x %x %x %x\n", got[0], got[1], got[2], got[3]);
        log_write(NONE, "         %x %x %x %x\n", got[4], got[5], got[6], got[7]);
        log_write(NONE, "  want: %x %x %x %x\n", exp[0], exp[1], exp[2], exp[3]);
        log_write(NONE, "         %x %x %x %x\n", exp[4], exp[5], exp[6], exp[7]);
        g_fail++;
    }
}

// -- Main ---------------------------------------------------------------------

int main(void)
{
    log_init("hmac-sha256-test.log");
    log_write(NONE, "=== HMAC-SHA256 (RFC 2104 / RFC 4231) Test ===\n\n");

    test_sha256_abc();
    test_rfc4231_tc1();
    test_rfc4231_tc2();
    test_rfc4231_tc3();
    test_rfc4231_tc4();
    test_determinism();
    test_length_sensitivity();

    log_write(NONE, "\n%d PASS  %d FAIL\n", g_pass, g_fail);
    log_close();

    asm volatile("li a7, 93\necall" ::: "a7", "memory");
    return g_fail ? 1 : 0;
}
