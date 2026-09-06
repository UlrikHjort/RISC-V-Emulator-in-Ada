/* **************************************************************************
 *             RISC-V Emulator - SHA-3 / Keccak-256 (FIPS 202)
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

// sha3.c -- SHA-3 / Keccak-256 (FIPS 202)
//
// Sponge construction over Keccak-f[1600] permutation.
// State: 5x5 grid of 64-bit lanes (1600 bits total).
// On RV32, each 64-bit lane is stored as two uint32_t (lo, hi).
//
// SHA3-256: rate = 1088 bits (136 bytes), output = 256 bits (32 bytes)
// SHA3 padding: append 0x06, zero-fill, set last bit 0x80 (domain separator)
//
// Tests:
//   FIPS 202 Sec.A.1: SHA3-256("") and SHA3-256("abc")
//   SHA3-256("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq")
//   Incremental update (multi-call) vs one-shot
//   Avalanche: 1-bit input flip changes output
//
// Build: cd programs && make run-sha3
// By Ulrik Hørlyk Hjort 2026

#include <stdint.h>
#include "log.h"

void putchar(char c);

static int g_pass = 0, g_fail = 0;

static void chk(const char *label, int ok) {
    if (ok) { log_write(NONE, "  PASS  %s\n", label); g_pass++; }
    else     { log_write(NONE, "  FAIL  %s\n", label); g_fail++; }
}
static void chk_bytes(const char *label, const uint8_t *got, const uint8_t *exp, int n) {
    int ok=1;
    for (int i=0;i<n;i++) if(got[i]!=exp[i]){ok=0;break;}
    if (ok) { log_write(NONE, "  PASS  %s\n", label); g_pass++; }
    else {
        log_write(NONE, "  FAIL  %s\n", label);
        log_write(NONE, "    got:"); for(int i=0;i<n&&i<16;i++) log_write(NONE," %x",got[i]);
        if(n>16) log_write(NONE,"...");
        log_write(NONE, "\n    exp:"); for(int i=0;i<n&&i<16;i++) log_write(NONE," %x",exp[i]);
        if(n>16) log_write(NONE,"...");
        log_write(NONE,"\n");
        g_fail++;
    }
}

/* -- Keccak-f[1600] constants ----------------------------------------------- */

// Round constants (24 x 64-bit, stored as lo/hi pairs)
static const uint32_t RC[24][2] = {
    {0x00000001u, 0x00000000u}, {0x00008082u, 0x00000000u},
    {0x0000808au, 0x80000000u}, {0x80008000u, 0x80000000u},
    {0x0000808bu, 0x00000000u}, {0x80000001u, 0x00000000u},
    {0x80008081u, 0x80000000u}, {0x00008009u, 0x80000000u},
    {0x0000008au, 0x00000000u}, {0x00000088u, 0x00000000u},
    {0x80008009u, 0x00000000u}, {0x8000000au, 0x00000000u},
    {0x8000808bu, 0x00000000u}, {0x0000008bu, 0x80000000u},
    {0x00008089u, 0x80000000u}, {0x00008003u, 0x80000000u},
    {0x00008002u, 0x80000000u}, {0x00000080u, 0x80000000u},
    {0x0000800au, 0x00000000u}, {0x8000000au, 0x80000000u},
    {0x80008081u, 0x80000000u}, {0x00008080u, 0x80000000u},
    {0x80000001u, 0x00000000u}, {0x80008008u, 0x80000000u},
};

// Rho rotation offsets for lane (x,y), flattened: index = 5*y + x
// Lane (0,0) has offset 0 (not in table)
static const int RHO[25] = {
     0,  1, 62, 28, 27,
    36, 44,  6, 55, 20,
     3, 10, 43, 25, 39,
    41, 45, 15, 21,  8,
    18,  2, 61, 56, 14,
};

/* -- 64-bit lane helpers on RV32 (lo/hi pair) ------------------------------ */
// State stored as uint32_t st[50]; lane (x,y) at index 2*(5*y+x)
// st[2*n] = lo, st[2*n+1] = hi

// Rotate a 64-bit value (lo,hi) left by n bits (0 <= n < 64)
static inline void rol64(uint32_t lo, uint32_t hi, int n,
                          uint32_t *rlo, uint32_t *rhi) {
    if (n == 0) { *rlo=lo; *rhi=hi; return; }
    if (n < 32) {
        *rlo = (lo << n) | (hi >> (32-n));
        *rhi = (hi << n) | (lo >> (32-n));
    } else {
        n -= 32;
        if (n == 0) { *rlo=hi; *rhi=lo; }
        else {
            *rlo = (hi << n) | (lo >> (32-n));
            *rhi = (lo << n) | (hi >> (32-n));
        }
    }
}

/* -- Keccak-f[1600] permutation -------------------------------------------- */

static void keccak_f(uint32_t st[50]) {
    uint32_t tmp[50];

    for (int round = 0; round < 24; round++) {
        // -- Theta ---------------------------------------------------------
        // C[x] = st[x,0] XOR st[x,1] XOR st[x,2] XOR st[x,3] XOR st[x,4]
        uint32_t Clo[5], Chi[5];
        for (int x=0;x<5;x++) {
            Clo[x] = st[2*x] ^ st[2*(x+5)] ^ st[2*(x+10)] ^ st[2*(x+15)] ^ st[2*(x+20)];
            Chi[x] = st[2*x+1]^st[2*(x+5)+1]^st[2*(x+10)+1]^st[2*(x+15)+1]^st[2*(x+20)+1];
        }
        // D[x] = C[x-1] XOR ROT(C[x+1], 1)
        uint32_t Dlo[5], Dhi[5];
        for (int x=0;x<5;x++) {
            int xp1 = (x+1)%5;
            // ROT64(C[x+1], 1)
            uint32_t rlo, rhi;
            rol64(Clo[xp1], Chi[xp1], 1, &rlo, &rhi);
            Dlo[x] = Clo[(x+4)%5] ^ rlo;
            Dhi[x] = Chi[(x+4)%5] ^ rhi;
        }
        for (int y=0;y<5;y++) for (int x=0;x<5;x++) {
            st[2*(5*y+x)  ] ^= Dlo[x];
            st[2*(5*y+x)+1] ^= Dhi[x];
        }

        // -- Rho + Pi ------------------------------------------------------
        // Pi: B[y, 2x+3y] = ROT(A[x,y], rho[x,y])
        for (int i=0;i<50;i++) tmp[i]=0;
        for (int y=0;y<5;y++) for (int x=0;x<5;x++) {
            int src = 5*y+x;
            int dst = 5*((2*x+3*y)%5) + y; // Pi permutation
            uint32_t rlo, rhi;
            rol64(st[2*src], st[2*src+1], RHO[src], &rlo, &rhi);
            tmp[2*dst  ] = rlo;
            tmp[2*dst+1] = rhi;
        }

        // -- Chi -----------------------------------------------------------
        // A[x,y] = B[x,y] XOR ((NOT B[x+1,y]) AND B[x+2,y])
        for (int y=0;y<5;y++) for (int x=0;x<5;x++) {
            int cur  = 5*y+x;
            int xp1  = 5*y+(x+1)%5;
            int xp2  = 5*y+(x+2)%5;
            st[2*cur  ] = tmp[2*cur  ] ^ ((~tmp[2*xp1  ]) & tmp[2*xp2  ]);
            st[2*cur+1] = tmp[2*cur+1] ^ ((~tmp[2*xp1+1]) & tmp[2*xp2+1]);
        }

        // -- Iota ----------------------------------------------------------
        st[0] ^= RC[round][0];
        st[1] ^= RC[round][1];
    }
}

/* -- SHA-3 context --------------------------------------------------------- */

#define SHA3_256_RATE 136  // (1600 - 2*256) / 8 = 136 bytes

typedef struct {
    uint32_t st[50];   // Keccak state: 25 lanes x 2 words
    uint8_t  buf[136]; // input buffer
    int      buflen;
} sha3_ctx;

static void sha3_init(sha3_ctx *ctx) {
    for (int i=0;i<50;i++) ctx->st[i]=0;
    ctx->buflen = 0;
}

// Absorb one rate-block into the state (XOR + permute)
static void sha3_absorb(sha3_ctx *ctx, const uint8_t *blk) {
    // XOR block into state (little-endian 64-bit lanes)
    for (int i=0;i<SHA3_256_RATE/8;i++) {
        uint32_t lo = (uint32_t)blk[i*8+0] | ((uint32_t)blk[i*8+1]<<8)
                    | ((uint32_t)blk[i*8+2]<<16)| ((uint32_t)blk[i*8+3]<<24);
        uint32_t hi = (uint32_t)blk[i*8+4] | ((uint32_t)blk[i*8+5]<<8)
                    | ((uint32_t)blk[i*8+6]<<16)| ((uint32_t)blk[i*8+7]<<24);
        ctx->st[2*i  ] ^= lo;
        ctx->st[2*i+1] ^= hi;
    }
    // SHA3_256_RATE = 136 = 17*8, so we absorb exactly 17 lanes (17*8 = 136 bytes)
    keccak_f(ctx->st);
}

static void sha3_update(sha3_ctx *ctx, const uint8_t *data, int len) {
    while (len > 0) {
        int free = SHA3_256_RATE - ctx->buflen;
        int take = len < free ? len : free;
        for (int i=0;i<take;i++) ctx->buf[ctx->buflen+i]=data[i];
        ctx->buflen += take;
        data += take;
        len  -= take;
        if (ctx->buflen == SHA3_256_RATE) {
            sha3_absorb(ctx, ctx->buf);
            ctx->buflen = 0;
        }
    }
}

static void sha3_final(sha3_ctx *ctx, uint8_t out[32]) {
    // Pad with SHA3 domain separator 0x06 then 0x80 at end of rate block
    ctx->buf[ctx->buflen] = 0x06;
    for (int i=ctx->buflen+1; i<SHA3_256_RATE; i++) ctx->buf[i]=0;
    ctx->buf[SHA3_256_RATE-1] |= 0x80;
    sha3_absorb(ctx, ctx->buf);

    // Squeeze: first 32 bytes of state (little-endian lanes)
    for (int i=0;i<4;i++) {
        out[i*8+0]=(uint8_t)ctx->st[2*i];
        out[i*8+1]=(uint8_t)(ctx->st[2*i]>>8);
        out[i*8+2]=(uint8_t)(ctx->st[2*i]>>16);
        out[i*8+3]=(uint8_t)(ctx->st[2*i]>>24);
        out[i*8+4]=(uint8_t)ctx->st[2*i+1];
        out[i*8+5]=(uint8_t)(ctx->st[2*i+1]>>8);
        out[i*8+6]=(uint8_t)(ctx->st[2*i+1]>>16);
        out[i*8+7]=(uint8_t)(ctx->st[2*i+1]>>24);
    }
}

// One-shot SHA3-256
static void sha3_256(const uint8_t *msg, int len, uint8_t out[32]) {
    sha3_ctx ctx;
    sha3_init(&ctx);
    sha3_update(&ctx, msg, len);
    sha3_final(&ctx, out);
}

/* ========================================================================== */
/*                               T E S T S                                   */
/* ========================================================================== */

static void test_fips202_vectors(void) {
    log_write(NONE, "\n=== FIPS 202 known-answer tests ===\n");

    // SHA3-256("") = a7ffc6f8bf1ed76651c14756a061d662f580ff4de43b49fa82d80a4b80f8434a
    static const uint8_t exp_empty[32] = {
        0xa7,0xff,0xc6,0xf8, 0xbf,0x1e,0xd7,0x66,
        0x51,0xc1,0x47,0x56, 0xa0,0x61,0xd6,0x62,
        0xf5,0x80,0xff,0x4d, 0xe4,0x3b,0x49,0xfa,
        0x82,0xd8,0x0a,0x4b, 0x80,0xf8,0x43,0x4a,
    };
    uint8_t out[32];
    sha3_256((uint8_t*)"", 0, out);
    chk_bytes("SHA3-256(\"\") matches FIPS 202", out, exp_empty, 32);

    // SHA3-256("abc") = 3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532
    static const uint8_t exp_abc[32] = {
        0x3a,0x98,0x5d,0xa7, 0x4f,0xe2,0x25,0xb2,
        0x04,0x5c,0x17,0x2d, 0x6b,0xd3,0x90,0xbd,
        0x85,0x5f,0x08,0x6e, 0x3e,0x9d,0x52,0x5b,
        0x46,0xbf,0xe2,0x45, 0x11,0x43,0x15,0x32,
    };
    sha3_256((uint8_t*)"abc", 3, out);
    chk_bytes("SHA3-256(\"abc\") matches FIPS 202", out, exp_abc, 32);

    // SHA3-256 of the 56-byte "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"
    // = 41c0dba2a9d6240849100376a8235e2c82e1b9998a999e21db32dd97496d3376
    static const uint8_t msg56[] =
        "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq";
    static const uint8_t exp56[32] = {
        0x41,0xc0,0xdb,0xa2, 0xa9,0xd6,0x24,0x08,
        0x49,0x10,0x03,0x76, 0xa8,0x23,0x5e,0x2c,
        0x82,0xe1,0xb9,0x99, 0x8a,0x99,0x9e,0x21,
        0xdb,0x32,0xdd,0x97, 0x49,0x6d,0x33,0x76,
    };
    sha3_256(msg56, 56, out);
    chk_bytes("SHA3-256(56-byte NIST msg) matches", out, exp56, 32);
}

static void test_incremental(void) {
    log_write(NONE, "\n=== Incremental update ===\n");

    // 200-byte message (crosses multiple rate blocks)
    uint8_t msg[200];
    for (int i=0;i<200;i++) msg[i]=(uint8_t)(i*3+7);

    uint8_t h1[32], h2[32];
    sha3_256(msg, 200, h1);

    // Feed byte by byte
    sha3_ctx ctx;
    sha3_init(&ctx);
    for (int i=0;i<200;i++) sha3_update(&ctx, msg+i, 1);
    sha3_final(&ctx, h2);
    chk_bytes("1-byte chunks == one-shot (200 bytes)", h1, h2, 32);

    // Feed as three pieces
    sha3_init(&ctx);
    sha3_update(&ctx, msg, 50);
    sha3_update(&ctx, msg+50, 100);
    sha3_update(&ctx, msg+150, 50);
    sha3_final(&ctx, h2);
    chk_bytes("3-chunk update == one-shot (200 bytes)", h1, h2, 32);

    // Exactly one rate block = 136 bytes
    sha3_256(msg, 136, h1);
    sha3_init(&ctx);
    sha3_update(&ctx, msg, 68);
    sha3_update(&ctx, msg+68, 68);
    sha3_final(&ctx, h2);
    chk_bytes("2x68 byte split == one-shot (136 bytes)", h1, h2, 32);

    // 137 bytes: one full block + 1 partial
    sha3_256(msg, 137, h1);
    sha3_init(&ctx);
    sha3_update(&ctx, msg, 136);
    sha3_update(&ctx, msg+136, 1);
    sha3_final(&ctx, h2);
    chk_bytes("136+1 split == one-shot (137 bytes)", h1, h2, 32);
}

static void test_avalanche(void) {
    log_write(NONE, "\n=== Avalanche effect ===\n");

    uint8_t msg1[32] = {0};
    uint8_t msg2[32] = {0};
    msg2[0] = 1; // flip 1 bit

    uint8_t h1[32], h2[32];
    sha3_256(msg1, 32, h1);
    sha3_256(msg2, 32, h2);

    int diff = 0;
    for (int i=0;i<32;i++) {
        uint8_t v = h1[i]^h2[i];
        while (v) { diff += v&1; v>>=1; }
    }
    chk("avalanche: >64 bits differ when input bit flipped", diff > 64);

    // Different lengths -> different hashes
    sha3_256(msg1, 1, h2);
    int same = 1;
    for (int i=0;i<32;i++) if (h1[i]!=h2[i]){same=0;break;}
    chk("32-zero vs 1-zero: different hashes", !same);

    // Determinism
    uint8_t h3[32];
    sha3_256(msg1, 32, h3);
    chk_bytes("SHA3-256 is deterministic", h1, h3, 32);
}

int main(void) {
    log_init("sha3.log");
    log_write(NONE, "SHA-3 / Keccak-256 Test (FIPS 202)\n");

    test_fips202_vectors();
    test_incremental();
    test_avalanche();

    log_write(NONE, "\n%d PASS  %d FAIL\n", g_pass, g_fail);
    log_close();
    return g_fail ? 1 : 0;
}
