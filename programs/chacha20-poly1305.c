/* **************************************************************************
 *           RISC-V Emulator - ChaCha20-Poly1305 AEAD (RFC 8439)
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

// chacha20-poly1305.c -- ChaCha20-Poly1305 AEAD (RFC 8439)
//
// Authenticated encryption combining ChaCha20 stream cipher with Poly1305 MAC.
// Poly1305 uses 5x26-bit limbs with uint64_t intermediates for 130-bit arithmetic.
//
// Test vectors from RFC 8439:
//   A.3  -- Poly1305 one-time key generation
//   A.4  -- Poly1305 MAC over known data
//   2.8.2 -- Full AEAD encrypt/decrypt + tamper detection
//
// Build: cd programs && make run-chacha20-poly1305
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
    int ok = 1;
    for (int i = 0; i < n; i++) if (got[i] != exp[i]) { ok = 0; break; }
    if (ok) { log_write(NONE, "  PASS  %s\n", label); g_pass++; }
    else {
        log_write(NONE, "  FAIL  %s\n", label);
        log_write(NONE, "    got:"); for (int i=0;i<n&&i<16;i++) log_write(NONE," %x",got[i]);
        log_write(NONE, " ...\n");
        log_write(NONE, "    exp:"); for (int i=0;i<n&&i<16;i++) log_write(NONE," %x",exp[i]);
        log_write(NONE, " ...\n");
        g_fail++;
    }
}

/* -- Utility --------------------------------------------------------------- */

static inline uint32_t le32(const uint8_t *p) {
    return (uint32_t)p[0] | ((uint32_t)p[1]<<8) |
           ((uint32_t)p[2]<<16) | ((uint32_t)p[3]<<24);
}
static inline void st32(uint8_t *p, uint32_t v) {
    p[0]=(uint8_t)v; p[1]=(uint8_t)(v>>8); p[2]=(uint8_t)(v>>16); p[3]=(uint8_t)(v>>24);
}
static inline void st64(uint8_t *p, uint64_t v) {
    st32(p, (uint32_t)v); st32(p+4, (uint32_t)(v>>32));
}
static inline uint32_t rotl32(uint32_t v, int n) {
    return (v << n) | (v >> (32 - n));
}
static void xmemcpy(uint8_t *dst, const uint8_t *src, int n) {
    for (int i=0;i<n;i++) dst[i]=src[i];
}

/* -- ChaCha20 -------------------------------------------------------------- */

static inline void qr(uint32_t s[16], int a, int b, int c, int d) {
    s[a]+=s[b]; s[d]^=s[a]; s[d]=rotl32(s[d],16);
    s[c]+=s[d]; s[b]^=s[c]; s[b]=rotl32(s[b],12);
    s[a]+=s[b]; s[d]^=s[a]; s[d]=rotl32(s[d], 8);
    s[c]+=s[d]; s[b]^=s[c]; s[b]=rotl32(s[b], 7);
}

// Produce 64-byte keystream block. key is 32 raw bytes, nonce is 12 raw bytes.
static void chacha20_block(const uint8_t key[32], uint32_t counter,
                            const uint8_t nonce[12], uint8_t out[64])
{
    uint32_t k[8], n[3];
    for (int i=0;i<8;i++) k[i] = le32(key + i*4);
    for (int i=0;i<3;i++) n[i] = le32(nonce + i*4);

    uint32_t s[16] = {
        0x61707865u, 0x3320646eu, 0x79622d32u, 0x6b206574u,
        k[0],k[1],k[2],k[3], k[4],k[5],k[6],k[7],
        counter, n[0],n[1],n[2]
    };
    uint32_t w[16];
    for (int i=0;i<16;i++) w[i]=s[i];
    for (int i=0;i<10;i++) {
        qr(w,0,4,8,12); qr(w,1,5,9,13); qr(w,2,6,10,14); qr(w,3,7,11,15);
        qr(w,0,5,10,15); qr(w,1,6,11,12); qr(w,2,7,8,13); qr(w,3,4,9,14);
    }
    for (int i=0;i<16;i++) w[i]+=s[i];
    for (int i=0;i<16;i++) st32(out+i*4, w[i]);
}

static void chacha20_xor(const uint8_t key[32], uint32_t counter,
                          const uint8_t nonce[12],
                          const uint8_t *in, uint8_t *out, int len)
{
    uint8_t block[64];
    for (int pos=0; pos<len; ) {
        chacha20_block(key, counter++, nonce, block);
        int chunk = len-pos; if (chunk>64) chunk=64;
        for (int i=0;i<chunk;i++) out[pos+i] = in[pos+i] ^ block[i];
        pos += chunk;
    }
}

/* -- Poly1305 (5x26-bit limb representation) ------------------------------ */

typedef struct {
    uint64_t h[5];    // accumulator (130-bit, 5x26-bit limbs, with carry headroom)
    uint64_t r[5];    // r (26-bit each)
    uint64_t rr[4];   // r[1..4] * 5  (for mod-2^130-5 reduction)
    uint32_t s[4];    // addend (pad), LE words
    uint8_t  buf[16]; // partial block
    int      buflen;
} poly1305_ctx;

static void poly1305_init(poly1305_ctx *ctx, const uint8_t key[32]) {
    // Clamp r = key[0..15]
    uint32_t t0 = le32(key+0) & 0x0fffffffu;
    uint32_t t1 = le32(key+4) & 0x0ffffffcu;
    uint32_t t2 = le32(key+8) & 0x0ffffffcu;
    uint32_t t3 = le32(key+12)& 0x0ffffffcu;

    // Load into 5x26-bit limbs
    ctx->r[0] = (t0)                          & 0x3ffffffu;
    ctx->r[1] = ((t0>>26) | ((uint64_t)t1<<6))& 0x3ffffffu;
    ctx->r[2] = ((t1>>20) | ((uint64_t)t2<<12))&0x3ffffffu;
    ctx->r[3] = ((t2>>14) | ((uint64_t)t3<<18))&0x3ffffffu;
    ctx->r[4] = (t3>>8)                       & 0x3ffffffu;

    // Precompute s[k] = r[k+1]*5 (reduction: 2^130 == 5 mod 2^130-5)
    ctx->rr[0] = ctx->r[1]*5;
    ctx->rr[1] = ctx->r[2]*5;
    ctx->rr[2] = ctx->r[3]*5;
    ctx->rr[3] = ctx->r[4]*5;

    ctx->s[0] = le32(key+16);
    ctx->s[1] = le32(key+20);
    ctx->s[2] = le32(key+24);
    ctx->s[3] = le32(key+28);

    ctx->h[0]=ctx->h[1]=ctx->h[2]=ctx->h[3]=ctx->h[4]=0;
    ctx->buflen = 0;
}

// Process one 16-byte block. hibit=1 for full blocks (appends 2^128), 0 for final partial.
static void poly1305_block(poly1305_ctx *ctx, const uint8_t m[16], int hibit) {
    uint64_t h0=ctx->h[0], h1=ctx->h[1], h2=ctx->h[2], h3=ctx->h[3], h4=ctx->h[4];
    uint64_t r0=ctx->r[0], r1=ctx->r[1], r2=ctx->r[2], r3=ctx->r[3], r4=ctx->r[4];
    uint64_t s1=ctx->rr[0],s2=ctx->rr[1],s3=ctx->rr[2],s4=ctx->rr[3];

    // Load message block into 5x26-bit limbs + high bit
    uint64_t u0=le32(m+0), u1=le32(m+4), u2=le32(m+8), u3=le32(m+12);
    uint64_t m0 =  u0                          & 0x3ffffffu;
    uint64_t m1 = ((u0>>26)|(u1<<6))           & 0x3ffffffu;
    uint64_t m2 = ((u1>>20)|(u2<<12))          & 0x3ffffffu;
    uint64_t m3 = ((u2>>14)|(u3<<18))          & 0x3ffffffu;
    uint64_t m4 = (u3>>8)  | ((uint64_t)hibit << 24);

    // h += m
    h0+=m0; h1+=m1; h2+=m2; h3+=m3; h4+=m4;

    // h = h * r mod (2^130-5)
    // d[k] = sum_{i+j=k} h[i]*r[j]  + sum_{i+j=k+5} h[i]*r[j]*5
    uint64_t d0 = h0*r0 + h1*s4 + h2*s3 + h3*s2 + h4*s1;
    uint64_t d1 = h0*r1 + h1*r0 + h2*s4 + h3*s3 + h4*s2;
    uint64_t d2 = h0*r2 + h1*r1 + h2*r0 + h3*s4 + h4*s3;
    uint64_t d3 = h0*r3 + h1*r2 + h2*r1 + h3*r0 + h4*s4;
    uint64_t d4 = h0*r4 + h1*r3 + h2*r2 + h3*r1 + h4*r0;

    // Carry propagation (keep 26 bits per limb)
    uint64_t c;
    c=d0>>26; h0=d0&0x3ffffffu; d1+=c;
    c=d1>>26; h1=d1&0x3ffffffu; d2+=c;
    c=d2>>26; h2=d2&0x3ffffffu; d3+=c;
    c=d3>>26; h3=d3&0x3ffffffu; d4+=c;
    c=d4>>26; h4=d4&0x3ffffffu; h0+=c*5;
    c=h0>>26; h0&=0x3ffffffu;   h1+=c;

    ctx->h[0]=h0; ctx->h[1]=h1; ctx->h[2]=h2; ctx->h[3]=h3; ctx->h[4]=h4;
}

static void poly1305_update(poly1305_ctx *ctx, const uint8_t *data, int len) {
    if (ctx->buflen) {
        int fill = 16 - ctx->buflen;
        if (len < fill) {
            xmemcpy(ctx->buf + ctx->buflen, data, len);
            ctx->buflen += len;
            return;
        }
        xmemcpy(ctx->buf + ctx->buflen, data, fill);
        poly1305_block(ctx, ctx->buf, 1);
        ctx->buflen = 0;
        data += fill; len -= fill;
    }
    while (len >= 16) {
        poly1305_block(ctx, data, 1);
        data += 16; len -= 16;
    }
    if (len) {
        xmemcpy(ctx->buf, data, len);
        ctx->buflen = len;
    }
}

static void poly1305_final(poly1305_ctx *ctx, uint8_t tag[16]) {
    // Flush partial block if any
    if (ctx->buflen) {
        ctx->buf[ctx->buflen] = 1;
        for (int i = ctx->buflen+1; i < 16; i++) ctx->buf[i] = 0;
        poly1305_block(ctx, ctx->buf, 0);
    }

    // Fully reduce h mod 2^130-5
    uint64_t h0=ctx->h[0], h1=ctx->h[1], h2=ctx->h[2], h3=ctx->h[3], h4=ctx->h[4];
    uint64_t c;
    c=h1>>26; h1&=0x3ffffffu; h2+=c;
    c=h2>>26; h2&=0x3ffffffu; h3+=c;
    c=h3>>26; h3&=0x3ffffffu; h4+=c;
    c=h4>>26; h4&=0x3ffffffu; h0+=c*5;
    c=h0>>26; h0&=0x3ffffffu; h1+=c;

    // Compute g = h + 5; if g >= 2^130, use g (h >= 2^130-5)
    uint64_t g0=h0+5; c=g0>>26; g0&=0x3ffffffu;
    uint64_t g1=h1+c; c=g1>>26; g1&=0x3ffffffu;
    uint64_t g2=h2+c; c=g2>>26; g2&=0x3ffffffu;
    uint64_t g3=h3+c; c=g3>>26; g3&=0x3ffffffu;
    uint64_t g4=h4+c;

    // mask = all-ones if h >= 2^130-5, else all-zeros
    uint64_t mask = (uint64_t)(-(int64_t)((g4>>26)&1));
    uint64_t nmask = ~mask;
    h0 = (h0&nmask)|(g0&mask);
    h1 = (h1&nmask)|(g1&mask);
    h2 = (h2&nmask)|(g2&mask);
    h3 = (h3&nmask)|(g3&mask);
    h4 = (h4&nmask)|(g4&mask);

    // Assemble 128-bit h from 5x26-bit limbs into 4x32-bit words.
    // Each limb only contributes its own bits to avoid double-counting:
    //   w0: bits  0-31 = h0[0..25] | h1[0..5]<<26
    //   w1: bits 32-63 = h1[6..25] | h2[0..11]<<20
    //   w2: bits 64-95 = h2[12..25] | h3[0..17]<<14
    //   w3: bits 96-127 = h3[18..25] | h4[0..23]<<8
    uint32_t w0 = (uint32_t)(h0      | ((h1 & 0x3fu)    << 26));
    uint32_t w1 = (uint32_t)(h1>>6   | ((h2 & 0xfffu)   << 20));
    uint32_t w2 = (uint32_t)(h2>>12  | ((h3 & 0x3ffffu) << 14));
    uint32_t w3 = (uint32_t)(h3>>18  | (h4 << 8));

    // Add s (128-bit pad) with carry chain
    uint64_t f0 = (uint64_t)w0 + (uint64_t)ctx->s[0];
    uint64_t f1 = (uint64_t)w1 + (uint64_t)ctx->s[1] + (f0>>32);
    uint64_t f2 = (uint64_t)w2 + (uint64_t)ctx->s[2] + (f1>>32);
    uint64_t f3 = (uint64_t)w3 + (uint64_t)ctx->s[3] + (f2>>32);

    st32(tag+0,  (uint32_t)f0);
    st32(tag+4,  (uint32_t)f1);
    st32(tag+8,  (uint32_t)f2);
    st32(tag+12, (uint32_t)f3);
}

/* -- AEAD ------------------------------------------------------------------ */

static void aead_mac_input(poly1305_ctx *mac,
                            const uint8_t *aad, int aad_len,
                            const uint8_t *ct,  int ct_len)
{
    static const uint8_t zeros[16] = {0};
    int aad_pad = (16 - aad_len%16) % 16;
    int ct_pad  = (16 - ct_len %16) % 16;
    uint8_t lens[16];

    poly1305_update(mac, aad, aad_len);
    if (aad_pad) poly1305_update(mac, zeros, aad_pad);
    poly1305_update(mac, ct, ct_len);
    if (ct_pad)  poly1305_update(mac, zeros, ct_pad);
    st64(lens+0, (uint64_t)aad_len);
    st64(lens+8, (uint64_t)ct_len);
    poly1305_update(mac, lens, 16);
}

// AEAD seal: ct and tag are output. ct must be >= pt_len bytes.
static void aead_seal(const uint8_t key[32], const uint8_t nonce[12],
                       const uint8_t *aad, int aad_len,
                       const uint8_t *pt,  int pt_len,
                       uint8_t *ct, uint8_t tag[16])
{
    uint8_t otk[64];
    chacha20_block(key, 0, nonce, otk);          // OTK = first 32 bytes
    chacha20_xor(key, 1, nonce, pt, ct, pt_len); // Encrypt
    poly1305_ctx mac;
    poly1305_init(&mac, otk);
    aead_mac_input(&mac, aad, aad_len, ct, pt_len);
    poly1305_final(&mac, tag);
}

// AEAD open: returns 1 if tag matches, 0 otherwise
static int aead_open(const uint8_t key[32], const uint8_t nonce[12],
                      const uint8_t *aad, int aad_len,
                      const uint8_t *ct, int ct_len,
                      const uint8_t *expected_tag,
                      uint8_t *pt)
{
    uint8_t otk[64];
    chacha20_block(key, 0, nonce, otk);
    poly1305_ctx mac;
    poly1305_init(&mac, otk);
    aead_mac_input(&mac, aad, aad_len, ct, ct_len);
    uint8_t computed_tag[16];
    poly1305_final(&mac, computed_tag);
    // Constant-time compare
    int diff = 0;
    for (int i=0;i<16;i++) diff |= (computed_tag[i] ^ expected_tag[i]);
    if (diff) return 0;
    chacha20_xor(key, 1, nonce, ct, pt, ct_len);
    return 1;
}

/* ========================================================================== */
/*                               T E S T S                                   */
/* ========================================================================== */

// -- Test 1: Poly1305 one-time key generation (RFC 8439 Sec.A.3) -------------
static void test_otk_gen(void) {
    log_write(NONE, "\n=== OTK generation (RFC 8439 A.3) ===\n");
    static const uint8_t key[32] = {
        0x80,0x81,0x82,0x83, 0x84,0x85,0x86,0x87,
        0x88,0x89,0x8a,0x8b, 0x8c,0x8d,0x8e,0x8f,
        0x90,0x91,0x92,0x93, 0x94,0x95,0x96,0x97,
        0x98,0x99,0x9a,0x9b, 0x9c,0x9d,0x9e,0x9f
    };
    static const uint8_t nonce[12] = {
        0x00,0x00,0x00,0x00, 0x00,0x01,0x02,0x03,
        0x04,0x05,0x06,0x07
    };
    static const uint8_t exp_otk[32] = {
        0x8a,0xd5,0xa0,0x8b, 0x90,0x5f,0x81,0xcc,
        0x81,0x50,0x40,0x27, 0x4a,0xb2,0x94,0x71,
        0xa8,0x33,0xb6,0x37, 0xe3,0xfd,0x0d,0xa5,
        0x08,0xdb,0xb8,0xe2, 0xfd,0xd1,0xa6,0x46
    };
    uint8_t block[64];
    chacha20_block(key, 0, nonce, block);
    chk_bytes("OTK first 32 bytes match RFC 8439 A.3", block, exp_otk, 32);
}

// -- Test 2: Poly1305 MAC over known data (RFC 8439 Sec.2.5.2) ---------------
static void test_poly1305_mac(void) {
    log_write(NONE, "\n=== Poly1305 MAC (RFC 8439 Sec.2.5.2) ===\n");

    // Key from Sec.2.5.2
    static const uint8_t key[32] = {
        0x85,0xd6,0xbe,0x78, 0x57,0x55,0x6d,0x33,
        0x7f,0x44,0x52,0xfe, 0x42,0xd5,0x06,0xa8,
        0x01,0x03,0x80,0x8a, 0xfb,0x0d,0xb2,0xfd,
        0x4a,0xbf,0xf6,0xaf, 0x41,0x49,0xf5,0x1b
    };
    // Message: "Cryptographic Forum Research Group"
    static const uint8_t msg[] = {
        0x43,0x72,0x79,0x70, 0x74,0x6f,0x67,0x72,
        0x61,0x70,0x68,0x69, 0x63,0x20,0x46,0x6f,
        0x72,0x75,0x6d,0x20, 0x52,0x65,0x73,0x65,
        0x61,0x72,0x63,0x68, 0x20,0x47,0x72,0x6f,
        0x75,0x70
    };
    static const uint8_t exp_tag[16] = {
        0xa8,0x06,0x1d,0xc1, 0x30,0x51,0x36,0xc6,
        0xc2,0x2b,0x8b,0xaf, 0x0c,0x01,0x27,0xa9
    };
    poly1305_ctx ctx;
    poly1305_init(&ctx, key);
    poly1305_update(&ctx, msg, (int)sizeof(msg));
    uint8_t tag[16];
    poly1305_final(&ctx, tag);
    chk_bytes("Poly1305 tag matches RFC 8439 Sec.2.5.2", tag, exp_tag, 16);
}

// -- Test 3: Full AEAD encrypt (RFC 8439 Sec.2.8.2) --------------------------
static void test_aead_encrypt(void) {
    log_write(NONE, "\n=== AEAD encrypt (RFC 8439 Sec.2.8.2) ===\n");

    static const uint8_t key[32] = {
        0x80,0x81,0x82,0x83, 0x84,0x85,0x86,0x87,
        0x88,0x89,0x8a,0x8b, 0x8c,0x8d,0x8e,0x8f,
        0x90,0x91,0x92,0x93, 0x94,0x95,0x96,0x97,
        0x98,0x99,0x9a,0x9b, 0x9c,0x9d,0x9e,0x9f
    };
    static const uint8_t nonce[12] = {
        0x07,0x00,0x00,0x00, 0x40,0x41,0x42,0x43,
        0x44,0x45,0x46,0x47
    };
    static const uint8_t aad[] = {
        0x50,0x51,0x52,0x53, 0xc0,0xc1,0xc2,0xc3,
        0xc4,0xc5,0xc6,0xc7
    };
    static const uint8_t pt[] = {
        0x4c,0x61,0x64,0x69, 0x65,0x73,0x20,0x61,
        0x6e,0x64,0x20,0x47, 0x65,0x6e,0x74,0x6c,
        0x65,0x6d,0x65,0x6e, 0x20,0x6f,0x66,0x20,
        0x74,0x68,0x65,0x20, 0x63,0x6c,0x61,0x73,
        0x73,0x20,0x6f,0x66, 0x20,0x27,0x39,0x39,
        0x3a,0x20,0x49,0x66, 0x20,0x49,0x20,0x63,
        0x6f,0x75,0x6c,0x64, 0x20,0x6f,0x66,0x66,
        0x65,0x72,0x20,0x79, 0x6f,0x75,0x20,0x6f,
        0x6e,0x6c,0x79,0x20, 0x6f,0x6e,0x65,0x20,
        0x74,0x69,0x70,0x20, 0x66,0x6f,0x72,0x20,
        0x74,0x68,0x65,0x20, 0x66,0x75,0x74,0x75,
        0x72,0x65,0x2c,0x20, 0x73,0x75,0x6e,0x73,
        0x63,0x72,0x65,0x65, 0x6e,0x20,0x77,0x6f,
        0x75,0x6c,0x64,0x20, 0x62,0x65,0x20,0x69,
        0x74,0x2e
    };
    static const uint8_t exp_ct[] = {
        0xd3,0x1a,0x8d,0x34, 0x64,0x8e,0x60,0xdb,
        0x7b,0x86,0xaf,0xbc, 0x53,0xef,0x7e,0xc2,
        0xa4,0xad,0xed,0x51, 0x29,0x6e,0x08,0xfe,
        0xa9,0xe2,0xb5,0xa7, 0x36,0xee,0x62,0xd6,
        0x3d,0xbe,0xa4,0x5e, 0x8c,0xa9,0x67,0x12,
        0x82,0xfa,0xfb,0x69, 0xda,0x92,0x72,0x8b,
        0x1a,0x71,0xde,0x0a, 0x9e,0x06,0x0b,0x29,
        0x05,0xd6,0xa5,0xb6, 0x7e,0xcd,0x3b,0x36,
        0x92,0xdd,0xbd,0x7f, 0x2d,0x77,0x8b,0x8c,
        0x98,0x03,0xae,0xe3, 0x28,0x09,0x1b,0x58,
        0xfa,0xb3,0x24,0xe4, 0xfa,0xd6,0x75,0x94,
        0x55,0x85,0x80,0x8b, 0x48,0x31,0xd7,0xbc,
        0x3f,0xf4,0xde,0xf0, 0x8e,0x4b,0x7a,0x9d,
        0xe5,0x76,0xd2,0x65, 0x86,0xce,0xc6,0x4b,
        0x61,0x16
    };
    static const uint8_t exp_tag[16] = {
        0x1a,0xe1,0x0b,0x59, 0x4f,0x09,0xe2,0x6a,
        0x7e,0x90,0x2e,0xcb, 0xd0,0x60,0x06,0x91
    };

    uint8_t ct[sizeof(pt)];
    uint8_t tag[16];
    aead_seal(key, nonce, aad, (int)sizeof(aad), pt, (int)sizeof(pt), ct, tag);

    chk_bytes("ciphertext matches RFC 8439 Sec.2.8.2", ct, exp_ct, (int)sizeof(pt));
    chk_bytes("auth tag matches RFC 8439 Sec.2.8.2",   tag, exp_tag, 16);
}

// -- Test 4: AEAD decrypt -------------------------------------------------
static void test_aead_decrypt(void) {
    log_write(NONE, "\n=== AEAD decrypt ===\n");

    static const uint8_t key[32] = {
        0x80,0x81,0x82,0x83, 0x84,0x85,0x86,0x87,
        0x88,0x89,0x8a,0x8b, 0x8c,0x8d,0x8e,0x8f,
        0x90,0x91,0x92,0x93, 0x94,0x95,0x96,0x97,
        0x98,0x99,0x9a,0x9b, 0x9c,0x9d,0x9e,0x9f
    };
    static const uint8_t nonce[12] = {
        0x07,0x00,0x00,0x00, 0x40,0x41,0x42,0x43,
        0x44,0x45,0x46,0x47
    };
    static const uint8_t aad[] = {
        0x50,0x51,0x52,0x53, 0xc0,0xc1,0xc2,0xc3,
        0xc4,0xc5,0xc6,0xc7
    };
    static const uint8_t exp_pt[] = {
        0x4c,0x61,0x64,0x69, 0x65,0x73,0x20,0x61,
        0x6e,0x64,0x20,0x47, 0x65,0x6e,0x74,0x6c,
        0x65,0x6d,0x65,0x6e, 0x20,0x6f,0x66,0x20,
        0x74,0x68,0x65,0x20, 0x63,0x6c,0x61,0x73,
        0x73,0x20,0x6f,0x66, 0x20,0x27,0x39,0x39,
        0x3a,0x20,0x49,0x66, 0x20,0x49,0x20,0x63,
        0x6f,0x75,0x6c,0x64, 0x20,0x6f,0x66,0x66,
        0x65,0x72,0x20,0x79, 0x6f,0x75,0x20,0x6f,
        0x6e,0x6c,0x79,0x20, 0x6f,0x6e,0x65,0x20,
        0x74,0x69,0x70,0x20, 0x66,0x6f,0x72,0x20,
        0x74,0x68,0x65,0x20, 0x66,0x75,0x74,0x75,
        0x72,0x65,0x2c,0x20, 0x73,0x75,0x6e,0x73,
        0x63,0x72,0x65,0x65, 0x6e,0x20,0x77,0x6f,
        0x75,0x6c,0x64,0x20, 0x62,0x65,0x20,0x69,
        0x74,0x2e
    };
    static const uint8_t ct[] = {
        0xd3,0x1a,0x8d,0x34, 0x64,0x8e,0x60,0xdb,
        0x7b,0x86,0xaf,0xbc, 0x53,0xef,0x7e,0xc2,
        0xa4,0xad,0xed,0x51, 0x29,0x6e,0x08,0xfe,
        0xa9,0xe2,0xb5,0xa7, 0x36,0xee,0x62,0xd6,
        0x3d,0xbe,0xa4,0x5e, 0x8c,0xa9,0x67,0x12,
        0x82,0xfa,0xfb,0x69, 0xda,0x92,0x72,0x8b,
        0x1a,0x71,0xde,0x0a, 0x9e,0x06,0x0b,0x29,
        0x05,0xd6,0xa5,0xb6, 0x7e,0xcd,0x3b,0x36,
        0x92,0xdd,0xbd,0x7f, 0x2d,0x77,0x8b,0x8c,
        0x98,0x03,0xae,0xe3, 0x28,0x09,0x1b,0x58,
        0xfa,0xb3,0x24,0xe4, 0xfa,0xd6,0x75,0x94,
        0x55,0x85,0x80,0x8b, 0x48,0x31,0xd7,0xbc,
        0x3f,0xf4,0xde,0xf0, 0x8e,0x4b,0x7a,0x9d,
        0xe5,0x76,0xd2,0x65, 0x86,0xce,0xc6,0x4b,
        0x61,0x16
    };
    static const uint8_t tag[16] = {
        0x1a,0xe1,0x0b,0x59, 0x4f,0x09,0xe2,0x6a,
        0x7e,0x90,0x2e,0xcb, 0xd0,0x60,0x06,0x91
    };
    uint8_t pt[sizeof(ct)];
    int ok = aead_open(key, nonce, aad, (int)sizeof(aad),
                       ct, (int)sizeof(ct), tag, pt);
    chk("decrypt accepts valid tag",  ok == 1);
    chk_bytes("decrypted plaintext correct", pt, exp_pt, (int)sizeof(exp_pt));
}

// -- Test 5: Tamper detection ---------------------------------------------
static void test_tamper(void) {
    log_write(NONE, "\n=== Tamper detection ===\n");

    static const uint8_t key[32] = {
        0x80,0x81,0x82,0x83, 0x84,0x85,0x86,0x87,
        0x88,0x89,0x8a,0x8b, 0x8c,0x8d,0x8e,0x8f,
        0x90,0x91,0x92,0x93, 0x94,0x95,0x96,0x97,
        0x98,0x99,0x9a,0x9b, 0x9c,0x9d,0x9e,0x9f
    };
    static const uint8_t nonce[12] = {
        0x07,0x00,0x00,0x00, 0x40,0x41,0x42,0x43,
        0x44,0x45,0x46,0x47
    };
    static const uint8_t msg[] = "Hello, authenticated world!";
    static const uint8_t aad[] = "test-aad";
    uint8_t ct[sizeof(msg)], tag[16], pt[sizeof(msg)];

    aead_seal(key, nonce, aad, (int)sizeof(aad)-1, msg, (int)sizeof(msg)-1, ct, tag);
    chk("correct tag accepted",
        aead_open(key, nonce, aad, (int)sizeof(aad)-1, ct, (int)sizeof(msg)-1, tag, pt));

    // Flip one bit in ciphertext
    ct[0] ^= 0x01;
    chk("tampered ciphertext rejected",
        !aead_open(key, nonce, aad, (int)sizeof(aad)-1, ct, (int)sizeof(msg)-1, tag, pt));
    ct[0] ^= 0x01; // restore

    // Flip one bit in tag
    tag[0] ^= 0x01;
    chk("tampered tag rejected",
        !aead_open(key, nonce, aad, (int)sizeof(aad)-1, ct, (int)sizeof(msg)-1, tag, pt));
    tag[0] ^= 0x01; // restore

    // Change AAD
    static const uint8_t bad_aad[] = "test-bad";
    chk("modified AAD rejected",
        !aead_open(key, nonce, bad_aad, (int)sizeof(bad_aad)-1,
                   ct, (int)sizeof(msg)-1, tag, pt));
}

// -- Test 6: Round-trip with multi-block message ---------------------------
static void test_roundtrip(void) {
    log_write(NONE, "\n=== Round-trip (multi-block) ===\n");

    static const uint8_t key[32] = {
        0x00,0x01,0x02,0x03, 0x04,0x05,0x06,0x07,
        0x08,0x09,0x0a,0x0b, 0x0c,0x0d,0x0e,0x0f,
        0x10,0x11,0x12,0x13, 0x14,0x15,0x16,0x17,
        0x18,0x19,0x1a,0x1b, 0x1c,0x1d,0x1e,0x1f
    };
    static const uint8_t nonce[12] = {0,0,0,0,0,0,0,0,0,0,0,1};
    static const uint8_t aad[] = "additional data";

    // 100-byte message (crosses multiple ChaCha20 blocks)
    uint8_t msg[100], ct[100], pt[100], tag[16];
    for (int i=0;i<100;i++) msg[i] = (uint8_t)(i * 7 + 3);

    aead_seal(key, nonce, aad, (int)sizeof(aad)-1, msg, 100, ct, tag);
    int ok = aead_open(key, nonce, aad, (int)sizeof(aad)-1, ct, 100, tag, pt);
    chk("round-trip accepted", ok);
    int match = 1;
    for (int i=0;i<100;i++) if (pt[i]!=msg[i]) { match=0; break; }
    chk("round-trip plaintext matches", match);

    // Empty message
    aead_seal(key, nonce, aad, 3, msg, 0, ct, tag);
    ok = aead_open(key, nonce, aad, 3, ct, 0, tag, pt);
    chk("empty-message round-trip accepted", ok);

    // No AAD
    aead_seal(key, nonce, (uint8_t*)"", 0, msg, 16, ct, tag);
    ok = aead_open(key, nonce, (uint8_t*)"", 0, ct, 16, tag, pt);
    chk("no-AAD round-trip accepted", ok);
    match = 1;
    for (int i=0;i<16;i++) if (pt[i]!=msg[i]) { match=0; break; }
    chk("no-AAD plaintext matches", match);
}

/* ========================================================================== */
int main(void) {
    log_init("chacha20-poly1305.log");
    log_write(NONE, "ChaCha20-Poly1305 AEAD Test (RFC 8439)\n");

    test_otk_gen();
    test_poly1305_mac();
    test_aead_encrypt();
    test_aead_decrypt();
    test_tamper();
    test_roundtrip();

    log_write(NONE, "\n%d PASS  %d FAIL\n", g_pass, g_fail);
    log_close();
    return g_fail ? 1 : 0;
}
