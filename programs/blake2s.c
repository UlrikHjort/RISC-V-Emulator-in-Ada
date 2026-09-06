/* **************************************************************************
 *         RISC-V Emulator - BLAKE2s cryptographic hash (RFC 7693)
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

// blake2s.c -- BLAKE2s cryptographic hash (RFC 7693)
//
// 256-bit output, 64-byte block, 10 rounds. Optimised for 32-bit platforms.
// G function uses 32-bit word rotations (16, 12, 8, 7 bits).
// 10 round permutation constants from RFC 7693 Sec.2.1.
//
// Tests:
//   RFC 7693 Appendix A: BLAKE2s("") and BLAKE2s("abc")
//   Incremental hash (multi-call update)
//   Varying-length messages (1..64 bytes)
//   Non-zero output length (BLAKE2s-128 truncated hash)
//   Sequential / incremental consistency
//
// Build: cd programs && make run-blake2s
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
    for (int i=0;i<n;i++) if (got[i]!=exp[i]){ok=0;break;}
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

/* -- BLAKE2s constants ----------------------------------------------------- */

// Initialization vector: fractional parts of sqrt of first 8 primes
static const uint32_t IV[8] = {
    0x6A09E667u, 0xBB67AE85u, 0x3C6EF372u, 0xA54FF53Au,
    0x510E527Fu, 0x9B05688Cu, 0x1F83D9ABu, 0x5BE0CD19u,
};

// Message permutation table (RFC 7693 Sec.2.1, Table 2)
// 10 rows (rounds 0..9), 16 entries each (sigma[r][i])
static const uint8_t SIGMA[10][16] = {
    { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9,10,11,12,13,14,15},
    {14,10, 4, 8, 9,15,13, 6, 1,12, 0, 2,11, 7, 5, 3},
    {11, 8,12, 0, 5, 2,15,13,10,14, 3, 6, 7, 1, 9, 4},
    { 7, 9, 3, 1,13,12,11,14, 2, 6, 5,10, 4, 0,15, 8},
    { 9, 0, 5, 7, 2, 4,10,15,14, 1,11,12, 6, 8, 3,13},
    { 2,12, 6,10, 0,11, 8, 3, 4,13, 7, 5,15,14, 1, 9},
    {12, 5, 1,15,14,13, 4,10, 0, 7, 6, 3, 9, 2, 8,11},
    {13,11, 7,14,12, 1, 3, 9, 5, 0,15, 4, 8, 6, 2,10},
    { 6,15,14, 9,11, 3, 0, 8,12, 2,13, 7, 1, 4,10, 5},
    {10, 2, 8, 4, 7, 6, 1, 5,15,11, 9,14, 3,12,13, 0},
};

/* -- G mixing function ----------------------------------------------------- */

static inline uint32_t ror32(uint32_t v, int n) {
    return (v >> n) | (v << (32-n));
}

#define G(v,a,b,c,d,x,y) do { \
    v[a]+=v[b]+x; v[d]=ror32(v[d]^v[a],16); \
    v[c]+=v[d];   v[b]=ror32(v[b]^v[c],12); \
    v[a]+=v[b]+y; v[d]=ror32(v[d]^v[a], 8); \
    v[c]+=v[d];   v[b]=ror32(v[b]^v[c], 7); \
} while(0)

/* -- BLAKE2s compression --------------------------------------------------- */

static void blake2s_compress(uint32_t h[8], const uint8_t block[64],
                              uint32_t clo, uint32_t chi, int is_final)
{
    // Load block as 16 little-endian words
    uint32_t m[16];
    for (int i=0;i<16;i++) {
        m[i] = (uint32_t)block[i*4+0]
             | ((uint32_t)block[i*4+1]<<8)
             | ((uint32_t)block[i*4+2]<<16)
             | ((uint32_t)block[i*4+3]<<24);
    }

    // Initialize working variables
    uint32_t v[16];
    for (int i=0;i<8;i++) v[i]=h[i];
    for (int i=0;i<8;i++) v[8+i]=IV[i];
    v[12] ^= clo;               // counter low
    v[13] ^= chi;               // counter high
    if (is_final) v[14] ^= 0xFFFFFFFFu; // finalization flag

    // 10 rounds
    for (int r=0;r<10;r++) {
        const uint8_t *s = SIGMA[r];
        G(v, 0,4, 8,12, m[s[ 0]], m[s[ 1]]);
        G(v, 1,5, 9,13, m[s[ 2]], m[s[ 3]]);
        G(v, 2,6,10,14, m[s[ 4]], m[s[ 5]]);
        G(v, 3,7,11,15, m[s[ 6]], m[s[ 7]]);
        G(v, 0,5,10,15, m[s[ 8]], m[s[ 9]]);
        G(v, 1,6,11,12, m[s[10]], m[s[11]]);
        G(v, 2,7, 8,13, m[s[12]], m[s[13]]);
        G(v, 3,4, 9,14, m[s[14]], m[s[15]]);
    }

    // Finalize state
    for (int i=0;i<8;i++) h[i] ^= v[i] ^ v[i+8];
}

/* -- BLAKE2s hash context -------------------------------------------------- */

typedef struct {
    uint32_t h[8];          // chained state
    uint8_t  buf[64];       // block buffer
    uint32_t ctr_lo, ctr_hi; // byte counter (64-bit)
    int      buflen;        // bytes in buf
    int      outlen;        // digest length (1..32)
} blake2s_ctx;

static void blake2s_init(blake2s_ctx *ctx, int outlen) {
    // Parameter block for hash mode (no key, default params)
    for (int i=0;i<8;i++) ctx->h[i] = IV[i];
    // XOR h[0] with parameter block word 0:
    //   fanout=1, depth=1, outlen=outlen, keylen=0, leaf_len=0,node_off=0,node_depth=0,inner=0
    ctx->h[0] ^= 0x01010000u | (uint32_t)outlen;
    ctx->ctr_lo = ctx->ctr_hi = 0;
    ctx->buflen = 0;
    ctx->outlen = outlen;
    for (int i=0;i<64;i++) ctx->buf[i]=0;
}

static void blake2s_update(blake2s_ctx *ctx, const uint8_t *data, int len) {
    while (len > 0) {
        int free = 64 - ctx->buflen;
        if (len > free) {
            // Fill buffer and compress (only if more data follows: not the last block)
            for (int i=0;i<free;i++) ctx->buf[ctx->buflen+i]=data[i];
            ctx->buflen = 64;
            data += free; len -= free;
            // Increment counter
            ctx->ctr_lo += 64;
            if (ctx->ctr_lo < 64) ctx->ctr_hi++;
            blake2s_compress(ctx->h, ctx->buf, ctx->ctr_lo, ctx->ctr_hi, 0);
            ctx->buflen = 0;
            for (int i=0;i<64;i++) ctx->buf[i]=0;
        } else {
            for (int i=0;i<len;i++) ctx->buf[ctx->buflen+i]=data[i];
            ctx->buflen += len;
            len = 0;
        }
    }
}

static void blake2s_final(blake2s_ctx *ctx, uint8_t *out) {
    // Increment counter for the last block
    ctx->ctr_lo += (uint32_t)ctx->buflen;
    if (ctx->ctr_lo < (uint32_t)ctx->buflen) ctx->ctr_hi++;

    // Zero-pad the rest of the buffer (already zeroed by update)
    // (buflen..63 are already 0 from the zero-fill in update)

    blake2s_compress(ctx->h, ctx->buf, ctx->ctr_lo, ctx->ctr_hi, 1);

    // Serialize output (little-endian)
    for (int i=0;i<ctx->outlen;i++) {
        out[i] = (uint8_t)(ctx->h[i/4] >> ((i%4)*8));
    }
}

// One-shot hash
static void blake2s(const uint8_t *msg, int msglen, uint8_t *out, int outlen) {
    blake2s_ctx ctx;
    blake2s_init(&ctx, outlen);
    blake2s_update(&ctx, msg, msglen);
    blake2s_final(&ctx, out);
}

/* ========================================================================== */
/*                               T E S T S                                   */
/* ========================================================================== */

// RFC 7693 Appendix A: BLAKE2s known-answer tests
static void test_rfc_vectors(void) {
    log_write(NONE, "\n=== RFC 7693 known-answer tests ===\n");

    // BLAKE2s("") = 69217a30...
    static const uint8_t exp_empty[32] = {
        0x69,0x21,0x7a,0x30, 0x79,0x90,0x80,0x94,
        0xe1,0x11,0x21,0xd0, 0x42,0x35,0x4a,0x7c,
        0x1f,0x55,0xb6,0x48, 0x2c,0xa1,0xa5,0x1e,
        0x1b,0x25,0x0d,0xfd, 0x1e,0xd0,0xee,0xf9,
    };
    uint8_t out[32];
    blake2s((uint8_t*)"", 0, out, 32);
    chk_bytes("BLAKE2s(\"\") matches RFC 7693", out, exp_empty, 32);

    // BLAKE2s("abc") = 508c5e8c...
    static const uint8_t exp_abc[32] = {
        0x50,0x8c,0x5e,0x8c, 0x32,0x7c,0x14,0xe2,
        0xe1,0xa7,0x2b,0xa3, 0x4e,0xeb,0x45,0x2f,
        0x37,0x45,0x8b,0x20, 0x9e,0xd6,0x3a,0x29,
        0x4d,0x99,0x9b,0x4c, 0x86,0x67,0x59,0x82,
    };
    blake2s((uint8_t*)"abc", 3, out, 32);
    chk_bytes("BLAKE2s(\"abc\") matches RFC 7693", out, exp_abc, 32);
}

// Incremental vs one-shot consistency
static void test_incremental(void) {
    log_write(NONE, "\n=== Incremental update consistency ===\n");

    static const uint8_t msg[] =
        "The quick brown fox jumps over the lazy dog";
    int len = 43;

    uint8_t h1[32], h2[32];
    blake2s(msg, len, h1, 32);

    // Feed in 1-byte chunks
    blake2s_ctx ctx;
    blake2s_init(&ctx, 32);
    for (int i=0;i<len;i++) blake2s_update(&ctx, msg+i, 1);
    blake2s_final(&ctx, h2);
    chk_bytes("1-byte chunks == one-shot", h1, h2, 32);

    // Feed in two halves
    blake2s_init(&ctx, 32);
    blake2s_update(&ctx, msg, 20);
    blake2s_update(&ctx, msg+20, len-20);
    blake2s_final(&ctx, h2);
    chk_bytes("two-chunk update == one-shot", h1, h2, 32);

    // Feed as one 64-byte block + remainder
    static const uint8_t long_msg[128] = {
        0x00,0x01,0x02,0x03,0x04,0x05,0x06,0x07,
        0x08,0x09,0x0a,0x0b,0x0c,0x0d,0x0e,0x0f,
        0x10,0x11,0x12,0x13,0x14,0x15,0x16,0x17,
        0x18,0x19,0x1a,0x1b,0x1c,0x1d,0x1e,0x1f,
        0x20,0x21,0x22,0x23,0x24,0x25,0x26,0x27,
        0x28,0x29,0x2a,0x2b,0x2c,0x2d,0x2e,0x2f,
        0x30,0x31,0x32,0x33,0x34,0x35,0x36,0x37,
        0x38,0x39,0x3a,0x3b,0x3c,0x3d,0x3e,0x3f,
        0x40,0x41,0x42,0x43,0x44,0x45,0x46,0x47,
        0x48,0x49,0x4a,0x4b,0x4c,0x4d,0x4e,0x4f,
        0x50,0x51,0x52,0x53,0x54,0x55,0x56,0x57,
        0x58,0x59,0x5a,0x5b,0x5c,0x5d,0x5e,0x5f,
        0x60,0x61,0x62,0x63,0x64,0x65,0x66,0x67,
        0x68,0x69,0x6a,0x6b,0x6c,0x6d,0x6e,0x6f,
        0x70,0x71,0x72,0x73,0x74,0x75,0x76,0x77,
        0x78,0x79,0x7a,0x7b,0x7c,0x7d,0x7e,0x7f,
    };
    blake2s(long_msg, 128, h1, 32);

    blake2s_init(&ctx, 32);
    blake2s_update(&ctx, long_msg, 64);
    blake2s_update(&ctx, long_msg+64, 64);
    blake2s_final(&ctx, h2);
    chk_bytes("two 64-byte blocks == one-shot", h1, h2, 32);

    blake2s_init(&ctx, 32);
    blake2s_update(&ctx, long_msg, 1);
    blake2s_update(&ctx, long_msg+1, 127);
    blake2s_final(&ctx, h2);
    chk_bytes("1+127 byte split == one-shot", h1, h2, 32);
}

// BLAKE2s-16 (truncated output length 16 bytes)
static void test_short_output(void) {
    log_write(NONE, "\n=== Short output (BLAKE2s-128) ===\n");

    uint8_t h32[32], h16[16];
    // Different output lengths produce different hashes (distinct parameterizations)
    blake2s((uint8_t*)"test", 4, h32, 32);
    blake2s((uint8_t*)"test", 4, h16, 16);
    // They should be different (output length is part of the parameter block)
    int same = 1;
    for (int i=0;i<16;i++) if (h32[i]!=h16[i]) { same=0; break; }
    chk("BLAKE2s-128 differs from BLAKE2s-256 first 16 bytes", !same);

    // Consistency: two calls with outlen=16 give same result
    uint8_t h16b[16];
    blake2s((uint8_t*)"test", 4, h16b, 16);
    chk_bytes("BLAKE2s-128 deterministic", h16, h16b, 16);
}

// Empty message length boundary
static void test_length_boundary(void) {
    log_write(NONE, "\n=== Length boundary tests ===\n");

    uint8_t h1[32], h2[32];

    // 63-byte (just under one block)
    static const uint8_t m63[63] = {
        0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,
        16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,
        32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,
        48,49,50,51,52,53,54,55,56,57,58,59,60,61,62
    };
    // 64-byte (exactly one block)
    static const uint8_t m64[64] = {
        0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,
        16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,
        32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,
        48,49,50,51,52,53,54,55,56,57,58,59,60,61,62,63
    };
    // 65-byte (one block + 1 byte)
    static const uint8_t m65[65] = {
        0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,
        16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,
        32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,
        48,49,50,51,52,53,54,55,56,57,58,59,60,61,62,63,64
    };

    blake2s(m63, 63, h1, 32);
    blake2s(m64, 64, h2, 32);
    int same = 1;
    for (int i=0;i<32;i++) if (h1[i]!=h2[i]){same=0;break;}
    chk("63-byte hash differs from 64-byte hash", !same);

    blake2s(m64, 64, h1, 32);
    blake2s(m65, 65, h2, 32);
    same = 1;
    for (int i=0;i<32;i++) if (h1[i]!=h2[i]){same=0;break;}
    chk("64-byte hash differs from 65-byte hash", !same);

    // Incremental split at block boundary
    uint8_t h_split[32];
    blake2s_ctx ctx;
    blake2s_init(&ctx, 32);
    blake2s_update(&ctx, m65, 32);
    blake2s_update(&ctx, m65+32, 33);
    blake2s_final(&ctx, h_split);
    blake2s(m65, 65, h2, 32);
    chk_bytes("split-at-32 == one-shot (65 bytes)", h_split, h2, 32);
}

// Avalanche: flipping one bit changes the output substantially
static void test_avalanche(void) {
    log_write(NONE, "\n=== Avalanche effect ===\n");

    uint8_t h1[32], h2[32];
    uint8_t msg1[32] = {0}, msg2[32] = {0};
    msg2[0] = 0x01; // flip one bit

    blake2s(msg1, 32, h1, 32);
    blake2s(msg2, 32, h2, 32);

    int diff = 0;
    for (int i=0;i<32;i++) {
        uint8_t v = h1[i]^h2[i];
        while (v) { diff += v&1; v>>=1; }
    }
    // Expect roughly 128 bits different (good avalanche)
    chk("avalanche: >64 bits differ when input bit flipped", diff > 64);

    // Different message lengths must give different hashes
    blake2s(msg1, 1, h2, 32);
    int same = 1;
    for (int i=0;i<32;i++) if (h1[i]!=h2[i]){same=0;break;}
    chk("32-zero vs 1-zero: different hashes", !same);
}

int main(void) {
    log_init("blake2s.log");
    log_write(NONE, "BLAKE2s Test (RFC 7693)\n");

    test_rfc_vectors();
    test_incremental();
    test_short_output();
    test_length_boundary();
    test_avalanche();

    log_write(NONE, "\n%d PASS  %d FAIL\n", g_pass, g_fail);
    log_close();
    return g_fail ? 1 : 0;
}
