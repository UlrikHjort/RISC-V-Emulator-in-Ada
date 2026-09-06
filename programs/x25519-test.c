/* **************************************************************************
 *    RISC-V Emulator - X25519 (Curve25519) Diffie-Hellman key exchange
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

// x25519-test.c -- X25519 (Curve25519) Diffie-Hellman key exchange
//
// Implements field arithmetic over GF(2^255-19) and the RFC 7748
// Montgomery ladder scalar multiplication.
//
// Test vectors: RFC 7748 Section 6.1
// By Ulrik Hørlyk Hjort 2026

#include <stdint.h>
#include <string.h>
#include "log.h"

typedef unsigned int       u32;
typedef unsigned long long u64;

/* 256-bit value: 8 x 32-bit limbs, little-endian (d[0] = least significant) */
typedef struct { u32 d[8]; } fe;

static int g_pass = 0, g_fail = 0;
static void chk(const char *label, int ok)
{
    if (ok) { log_write(NONE, "PASS %s\n", label); g_pass++; }
    else     { log_write(NONE, "FAIL %s\n", label); g_fail++; }
}

/* =========================================================================
 * Curve25519 parameters
 *
 * p   = 2^255 - 19
 * a24 = 121665  (= (486662-2)/4, used in the Montgomery ladder)
 * G   = 9       (base point u-coordinate)
 * ========================================================================= */

static const fe C25519_P = {{
    0xFFFFFFED, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF,
    0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0x7FFFFFFF
}};

/* =========================================================================
 * 256-bit integer primitives (generic, reused for P and N arithmetic)
 * ========================================================================= */

static void fe_copy(fe *r, const fe *a) { memcpy(r, a, sizeof(fe)); }

static void fe_set_u32(fe *r, u32 v)
{
    r->d[0] = v;
    r->d[1] = r->d[2] = r->d[3] = r->d[4] =
    r->d[5] = r->d[6] = r->d[7] = 0;
}

static int fe_cmp(const fe *a, const fe *b)
{
    int i;
    for (i = 7; i >= 0; i--) {
        if (a->d[i] < b->d[i]) return -1;
        if (a->d[i] > b->d[i]) return  1;
    }
    return 0;
}

static int fe_eq(const fe *a, const fe *b) { return fe_cmp(a, b) == 0; }

static u32 fe_add_raw(fe *r, const fe *a, const fe *b)
{
    u64 acc = 0; int i;
    for (i = 0; i < 8; i++) {
        acc += (u64)a->d[i] + b->d[i];
        r->d[i] = (u32)acc; acc >>= 32;
    }
    return (u32)acc;
}

static u32 fe_sub_raw(fe *r, const fe *a, const fe *b)
{
    u64 acc = 0; int i;
    for (i = 0; i < 8; i++) {
        acc = (u64)a->d[i] - b->d[i] - acc;
        r->d[i] = (u32)acc; acc = (acc >> 32) & 1;
    }
    return (u32)acc;
}

/* =========================================================================
 * GF(2^255-19) field arithmetic
 * ========================================================================= */

static void fe_add(fe *r, const fe *a, const fe *b)
{
    u32 carry = fe_add_raw(r, a, b);
    if (carry || fe_cmp(r, &C25519_P) >= 0)
        fe_sub_raw(r, r, &C25519_P);
}

static void fe_sub(fe *r, const fe *a, const fe *b)
{
    u32 borrow = fe_sub_raw(r, a, b);
    if (borrow) fe_add_raw(r, r, &C25519_P);
}

/*
 * Reduce a 16-limb product (t[0..15], each < 2^32) modulo p = 2^255-19.
 * Uses 2^256 == 38 (mod p) to fold the high 8 limbs into the low 8.
 * Two fold passes suffice; a final conditional subtraction gives [0, p).
 */
static void c25519_reduce(fe *r, const u32 t[16])
{
    u64 a[8];
    u64 c;
    int i;

    /* First fold: acc[i] = t[i] + 38*t[i+8] */
    for (i = 0; i < 8; i++) a[i] = (u64)t[i] + (u64)38 * t[i+8];

    /* Carry propagation */
    c = 0;
    for (i = 0; i < 8; i++) {
        a[i] += c; r->d[i] = (u32)a[i]; c = a[i] >> 32;
    }

    /* Second fold: remaining carry c * 2^256 == c*38 (mod p); c <= 10 */
    c = (u64)r->d[0] + c * 38;
    r->d[0] = (u32)c; c >>= 32;
    for (i = 1; i < 8 && c; i++) {
        c += r->d[i]; r->d[i] = (u32)c; c >>= 32;
    }
    /* Third fold: c is 0 or 1 */
    r->d[0] += (u32)(c * 38);

    /* Final conditional subtraction -> canonical [0, p) */
    if (fe_cmp(r, &C25519_P) >= 0)
        fe_sub_raw(r, r, &C25519_P);
}

/* r = (a * b) mod p -- schoolbook 8x8 with carry, then fold */
static void fe_mul(fe *r, const fe *a, const fe *b)
{
    u32 t[16] = {0};
    u64 acc;
    int i, j;
    for (i = 0; i < 8; i++) {
        acc = 0;
        for (j = 0; j < 8; j++) {
            acc += (u64)t[i+j] + (u64)a->d[i] * b->d[j];
            t[i+j] = (u32)acc; acc >>= 32;
        }
        t[i+8] += (u32)acc;
    }
    c25519_reduce(r, t);
}

static void fe_sqr(fe *r, const fe *a) { fe_mul(r, a, a); }

/* r = a * 121665 mod p  (a24 = (486662-2)/4, constant used in ladder) */
static void fe_mul_a24(fe *r, const fe *a)
{
    static const fe A24 = {{ 121665, 0, 0, 0, 0, 0, 0, 0 }};
    fe_mul(r, a, &A24);
}

/*
 * r = a^(p-2) mod p  (field inversion via Fermat's little theorem).
 * p-2 = 0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffeb
 * = { 0xFFFFFFEB, 0xFFFFFFFF*6, 0x7FFFFFFF }
 * Bits set in p-2 (from bit 0): 0,1,3,5,6,7, then 8-253 all 1, 254.
 * Simple square-and-multiply from bit 253 down (bit 254 = initial t=a).
 */
static void fe_inv(fe *r, const fe *a)
{
    static const u32 exp[8] = {
        0xFFFFFFEB, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF,
        0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0x7FFFFFFF
    };
    fe t;
    int i;
    fe_copy(&t, a);                   /* t = a^1  (processes bit 254) */
    for (i = 253; i >= 0; i--) {
        fe_sqr(&t, &t);
        if ((exp[i / 32] >> (i % 32)) & 1)
            fe_mul(&t, &t, a);
    }
    fe_copy(r, &t);
}

/* =========================================================================
 * Constant-time conditional swap
 * ========================================================================= */

static void fe_cswap(int swap, fe *a, fe *b)
{
    u32 mask = -(u32)(swap & 1);      /* 0x00000000 or 0xFFFFFFFF */
    int i;
    for (i = 0; i < 8; i++) {
        u32 x = mask & (a->d[i] ^ b->d[i]);
        a->d[i] ^= x; b->d[i] ^= x;
    }
}

/* =========================================================================
 * X25519 scalar multiplication -- RFC 7748 Montgomery ladder
 * ========================================================================= */

/*
 * Clamp a 255-bit scalar per RFC 7748:
 *   clear bits 0,1,2 of byte 0  -> clear bits 0,1,2 of d[0]
 *   clear bit 7 of byte 31      -> clear bit 31 of d[7]
 *   set   bit 6 of byte 31      -> set   bit 30 of d[7]
 */
static void clamp(fe *k)
{
    k->d[0] &= ~(u32)7;
    k->d[7] &= 0x7FFFFFFFU;
    k->d[7] |= 0x40000000U;
}

/*
 * result = scalar * u  on Curve25519
 * k is clamped internally; u is used as-is (high bit masked per RFC 7748).
 */
static void x25519(fe *result, const fe *scalar, const fe *u)
{
    fe k, x1, x2, z2, x3, z3, A, AA, B, BB, E, C, D, DA, CB, tmp;
    int swap = 0, i, k_t;

    fe_copy(&k, scalar);
    clamp(&k);

    /* x1 = u (with bit 255 cleared per RFC 7748 Sec.5) */
    fe_copy(&x1, u);
    x1.d[7] &= 0x7FFFFFFFU;

    fe_set_u32(&x2, 1); fe_set_u32(&z2, 0);
    fe_copy(&x3, &x1);  fe_set_u32(&z3, 1);

    for (i = 254; i >= 0; i--) {
        k_t  = (k.d[i / 32] >> (i % 32)) & 1;
        swap ^= k_t;
        fe_cswap(swap, &x2, &x3);
        fe_cswap(swap, &z2, &z3);
        swap = k_t;

        fe_add(&A,  &x2, &z2);          /* A  = x2 + z2        */
        fe_sqr(&AA, &A);                 /* AA = A^2            */
        fe_sub(&B,  &x2, &z2);          /* B  = x2 - z2        */
        fe_sqr(&BB, &B);                 /* BB = B^2            */
        fe_sub(&E,  &AA, &BB);           /* E  = AA - BB        */
        fe_add(&C,  &x3, &z3);          /* C  = x3 + z3        */
        fe_sub(&D,  &x3, &z3);          /* D  = x3 - z3        */
        fe_mul(&DA, &D,  &A);           /* DA = D*A            */
        fe_mul(&CB, &C,  &B);           /* CB = C*B            */
        fe_add(&tmp, &DA, &CB);         /* tmp = DA + CB       */
        fe_sqr(&x3,  &tmp);             /* x3 = (DA+CB)^2      */
        fe_sub(&tmp, &DA, &CB);         /* tmp = DA - CB       */
        fe_sqr(&tmp, &tmp);             /* tmp = (DA-CB)^2     */
        fe_mul(&z3,  &x1, &tmp);        /* z3 = x1*(DA-CB)^2   */
        fe_mul(&x2,  &AA, &BB);         /* x2 = AA*BB          */
        fe_mul_a24(&tmp, &E);           /* tmp = a24*E         */
        fe_add(&tmp, &AA, &tmp);        /* tmp = AA + a24*E    */
        fe_mul(&z2,  &E,  &tmp);        /* z2 = E*(AA+a24*E)   */
    }

    fe_cswap(swap, &x2, &x3);
    fe_cswap(swap, &z2, &z3);

    fe_inv(&tmp, &z2);
    fe_mul(result, &x2, &tmp);
}

/* =========================================================================
 * RFC 7748 Sec.6.1 test vectors  (bytes loaded as little-endian u32 words)
 * ========================================================================= */

/* Alice's private key */
static const fe TV_ALICE_PRIV = {{
    0x0a6d0777, 0x7da51873, 0x72c1163c, 0x4566b251,
    0x872f4cdf, 0x2a99c0eb, 0xa5fb77b1, 0x2a2cb91d
}};

/* Alice's public key = X25519(alice_priv, 9) */
static const fe TV_ALICE_PUB = {{
    0x09f02085, 0x54a73089, 0xdc7d8b74, 0x5af73eb4,
    0x0d3abf0d, 0xf41a3826, 0x8ea9a4eb, 0x6a4e9baa
}};

/* Bob's private key */
static const fe TV_BOB_PRIV = {{
    0x7e08ab5d, 0x4b8a4a62, 0x8b7fe179, 0xe60e8083,
    0x29b13b6f, 0xfdb61826, 0x278b2f1c, 0xebe088ff
}};

/* Bob's public key = X25519(bob_priv, 9) */
static const fe TV_BOB_PUB = {{
    0x7ddb9ede, 0xb4c17d7b, 0xc2615bd3, 0x3735e4ec,
    0xc843833f, 0x4d67785b, 0x147efcad, 0x4f2b886f
}};

/* Shared secret = X25519(alice_priv, bob_pub) = X25519(bob_priv, alice_pub) */
static const fe TV_SHARED = {{
    0x5b9d5d4a, 0xe12dcea4, 0xf43b8e72, 0x250f3580,
    0xc9217ee0, 0x339ed147, 0x3c9bf076, 0x4217161e
}};

/* Base point u = 9 */
static const fe C25519_G = {{ 9, 0, 0, 0, 0, 0, 0, 0 }};

/* =========================================================================
 * Main
 * ========================================================================= */

int main(void)
{
    fe result;

    log_init("x25519-test.log");
    log_write(NONE, "=== X25519 (Curve25519) Key Exchange Test ===\n");

    /* Alice's public key */
    x25519(&result, &TV_ALICE_PRIV, &C25519_G);
    chk("alice public key matches RFC 7748", fe_eq(&result, &TV_ALICE_PUB));

    /* Bob's public key */
    x25519(&result, &TV_BOB_PRIV, &C25519_G);
    chk("bob public key matches RFC 7748",   fe_eq(&result, &TV_BOB_PUB));

    /* Shared secret, Alice's side */
    x25519(&result, &TV_ALICE_PRIV, &TV_BOB_PUB);
    chk("shared secret (alice side) correct", fe_eq(&result, &TV_SHARED));

    /* Shared secret, Bob's side */
    x25519(&result, &TV_BOB_PRIV, &TV_ALICE_PUB);
    chk("shared secret (bob side) correct",   fe_eq(&result, &TV_SHARED));

    /* Commutativity */
    {
        fe alice_shared, bob_shared;
        x25519(&alice_shared, &TV_ALICE_PRIV, &TV_BOB_PUB);
        x25519(&bob_shared,   &TV_BOB_PRIV,   &TV_ALICE_PUB);
        chk("alice shared == bob shared", fe_eq(&alice_shared, &bob_shared));
    }

    log_write(NONE, "\n%d PASS  %d FAIL\n", g_pass, g_fail);
    log_close();
    return g_fail ? 1 : 0;
}
