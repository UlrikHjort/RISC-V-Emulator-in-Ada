/* **************************************************************************
 *        RISC-V Emulator - SHA-512 (FIPS 180-4) for RV32 bare-metal
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

/* sha512.c -- SHA-512 (FIPS 180-4) for RV32 bare-metal
 *
 * Uses uint64_t state directly to avoid aliasing issues.
 * GCC handles 64-bit arithmetic on RV32 via register pairs (__muldi3 etc).
 * No 64-bit division required.
 */

#include "sha512.h"
#include <stdint.h>

typedef uint64_t u64;
typedef uint32_t u32;
typedef uint8_t  u8;

/* -- Round constants K[0..79] ---------------------------------------------- */
static const u64 K[80] = {
    0x428a2f98d728ae22ULL, 0x7137449123ef65cdULL,
    0xb5c0fbcfec4d3b2fULL, 0xe9b5dba58189dbbcULL,
    0x3956c25bf348b538ULL, 0x59f111f1b605d019ULL,
    0x923f82a4af194f9bULL, 0xab1c5ed5da6d8118ULL,
    0xd807aa98a3030242ULL, 0x12835b0145706fbeULL,
    0x243185be4ee4b28cULL, 0x550c7dc3d5ffb4e2ULL,
    0x72be5d74f27b896fULL, 0x80deb1fe3b1696b1ULL,
    0x9bdc06a725c71235ULL, 0xc19bf174cf692694ULL,
    0xe49b69c19ef14ad2ULL, 0xefbe4786384f25e3ULL,
    0x0fc19dc68b8cd5b5ULL, 0x240ca1cc77ac9c65ULL,
    0x2de92c6f592b0275ULL, 0x4a7484aa6ea6e483ULL,
    0x5cb0a9dcbd41fbd4ULL, 0x76f988da831153b5ULL,
    0x983e5152ee66dfabULL, 0xa831c66d2db43210ULL,
    0xb00327c898fb213fULL, 0xbf597fc7beef0ee4ULL,
    0xc6e00bf33da88fc2ULL, 0xd5a79147930aa725ULL,
    0x06ca6351e003826fULL, 0x142929670a0e6e70ULL,
    0x27b70a8546d22ffcULL, 0x2e1b21385c26c926ULL,
    0x4d2c6dfc5ac42aedULL, 0x53380d139d95b3dfULL,
    0x650a73548baf63deULL, 0x766a0abb3c77b2a8ULL,
    0x81c2c92e47edaee6ULL, 0x92722c851482353bULL,
    0xa2bfe8a14cf10364ULL, 0xa81a664bbc423001ULL,
    0xc24b8b70d0f89791ULL, 0xc76c51a30654be30ULL,
    0xd192e819d6ef5218ULL, 0xd69906245565a910ULL,
    0xf40e35855771202aULL, 0x106aa07032bbd1b8ULL,
    0x19a4c116b8d2d0c8ULL, 0x1e376c085141ab53ULL,
    0x2748774cdf8eeb99ULL, 0x34b0bcb5e19b48a8ULL,
    0x391c0cb3c5c95a63ULL, 0x4ed8aa4ae3418acbULL,
    0x5b9cca4f7763e373ULL, 0x682e6ff3d6b2b8a3ULL,
    0x748f82ee5defb2fcULL, 0x78a5636f43172f60ULL,
    0x84c87814a1f0ab72ULL, 0x8cc702081a6439ecULL,
    0x90befffa23631e28ULL, 0xa4506cebde82bde9ULL,
    0xbef9a3f7b2c67915ULL, 0xc67178f2e372532bULL,
    0xca273eceea26619cULL, 0xd186b8c721c0c207ULL,
    0xeada7dd6cde0eb1eULL, 0xf57d4f7fee6ed178ULL,
    0x06f067aa72176fbaULL, 0x0a637dc5a2c898a6ULL,
    0x113f9804bef90daeULL, 0x1b710b35131c471bULL,
    0x28db77f523047d84ULL, 0x32caab7b40c72493ULL,
    0x3c9ebe0a15c9bebcULL, 0x431d67c49c100d4cULL,
    0x4cc5d4becb3e42b6ULL, 0x597f299cfc657e2aULL,
    0x5fcb6fab3ad6faecULL, 0x6c44198c4a475817ULL
};

/* -- Initial hash values H0..H7 -------------------------------------------- */
static const u64 H_INIT[8] = {
    0x6a09e667f3bcc908ULL, 0xbb67ae8584caa73bULL,
    0x3c6ef372fe94f82bULL, 0xa54ff53a5f1d36f1ULL,
    0x510e527fade682d1ULL, 0x9b05688c2b3e6c1fULL,
    0x1f83d9abfb41bd6bULL, 0x5be0cd19137e2179ULL
};

/* -- Bit operations --------------------------------------------------------- */
#define ROTR64(x,n) (((x)>>(n))|((x)<<(64-(n))))
#define CH(x,y,z)   (((x)&(y))^(~(x)&(z)))
#define MAJ(x,y,z)  (((x)&(y))^((x)&(z))^((y)&(z)))
#define SIG0(x)  (ROTR64(x,28) ^ ROTR64(x,34) ^ ROTR64(x,39))
#define SIG1(x)  (ROTR64(x,14) ^ ROTR64(x,18) ^ ROTR64(x,41))
#define sig0(x)  (ROTR64(x, 1) ^ ROTR64(x, 8) ^ ((x)>>7))
#define sig1(x)  (ROTR64(x,19) ^ ROTR64(x,61) ^ ((x)>>6))

/* -- Load big-endian u64 from 8 bytes ------------------------------------- */
static u64 load64be(const u8 *p) {
    return ((u64)p[0]<<56)|((u64)p[1]<<48)|((u64)p[2]<<40)|((u64)p[3]<<32)
          |((u64)p[4]<<24)|((u64)p[5]<<16)|((u64)p[6]<< 8)| (u64)p[7];
}

/* -- Compress one 128-byte block ------------------------------------------- */
static void sha512_block(u64 h[8], const u8 blk[128])
{
    u64 W[80], a,b,c,d,e,f,g,hh, T1,T2;
    int i;

    for (i = 0; i < 16; i++) W[i] = load64be(blk + i*8);
    for (i = 16; i < 80; i++)
        W[i] = sig1(W[i-2]) + W[i-7] + sig0(W[i-15]) + W[i-16];

    a=h[0]; b=h[1]; c=h[2]; d=h[3];
    e=h[4]; f=h[5]; g=h[6]; hh=h[7];

    for (i = 0; i < 80; i++) {
        T1 = hh + SIG1(e) + CH(e,f,g) + K[i] + W[i];
        T2 = SIG0(a) + MAJ(a,b,c);
        hh=g; g=f; f=e; e=d+T1;
        d=c;  c=b; b=a; a=T1+T2;
    }

    h[0]+=a; h[1]+=b; h[2]+=c; h[3]+=d;
    h[4]+=e; h[5]+=f; h[6]+=g; h[7]+=hh;
}

/* -- Public API ------------------------------------------------------------- */

void sha512_init(sha512_ctx *ctx)
{
    int i;
    for (i = 0; i < 8; i++) ctx->state[i] = H_INIT[i];
    ctx->count  = 0;
    ctx->buflen = 0;
}

void sha512_update(sha512_ctx *ctx, const u8 *data, u32 len)
{
    u32 i = 0, space, take;

    ctx->count += (u64)len << 3;

    if (ctx->buflen > 0) {
        space = 128 - ctx->buflen;
        take  = (len < space) ? len : space;
        for (i = 0; i < take; i++) ctx->buf[ctx->buflen + i] = data[i];
        ctx->buflen += take;
        i = take;
        if (ctx->buflen == 128) {
            sha512_block(ctx->state, ctx->buf);
            ctx->buflen = 0;
        }
    }

    while (i + 128 <= len) {
        sha512_block(ctx->state, data + i);
        i += 128;
    }

    while (i < len) ctx->buf[ctx->buflen++] = data[i++];
}

void sha512_final(sha512_ctx *ctx, u8 digest[64])
{
    u32 i, rem = ctx->buflen;
    u64 bits  = ctx->count;

    /* Append 0x80 padding byte */
    ctx->buf[rem++] = 0x80u;

    /* If not enough room for the 16-byte length, flush and start new block */
    if (rem > 112) {
        while (rem < 128) ctx->buf[rem++] = 0;
        sha512_block(ctx->state, ctx->buf);
        rem = 0;
    }

    while (rem < 112) ctx->buf[rem++] = 0;

    /* Append 128-bit big-endian bit count (high 64 bits always 0 here) */
    ctx->buf[112] = 0; ctx->buf[113] = 0;
    ctx->buf[114] = 0; ctx->buf[115] = 0;
    ctx->buf[116] = 0; ctx->buf[117] = 0;
    ctx->buf[118] = 0; ctx->buf[119] = 0;
    ctx->buf[120] = (u8)(bits >> 56);
    ctx->buf[121] = (u8)(bits >> 48);
    ctx->buf[122] = (u8)(bits >> 40);
    ctx->buf[123] = (u8)(bits >> 32);
    ctx->buf[124] = (u8)(bits >> 24);
    ctx->buf[125] = (u8)(bits >> 16);
    ctx->buf[126] = (u8)(bits >>  8);
    ctx->buf[127] = (u8)(bits);

    sha512_block(ctx->state, ctx->buf);

    /* Serialize state as big-endian bytes */
    for (i = 0; i < 8; i++) {
        u64 w = ctx->state[i];
        digest[i*8+0] = (u8)(w>>56); digest[i*8+1] = (u8)(w>>48);
        digest[i*8+2] = (u8)(w>>40); digest[i*8+3] = (u8)(w>>32);
        digest[i*8+4] = (u8)(w>>24); digest[i*8+5] = (u8)(w>>16);
        digest[i*8+6] = (u8)(w>> 8); digest[i*8+7] = (u8)(w);
    }
}

void sha512(const u8 *data, u32 len, u8 digest[64])
{
    sha512_ctx ctx;
    sha512_init(&ctx);
    sha512_update(&ctx, data, len);
    sha512_final(&ctx, digest);
}
