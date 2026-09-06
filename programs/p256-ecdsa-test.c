/* **************************************************************************
 *    RISC-V Emulator - ECDSA sign + verify over NIST P-256 (secp256r1)
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

// p256-ecdsa-test.c -- ECDSA sign + verify over NIST P-256 (secp256r1)
//
// Implements 256-bit field arithmetic, Jacobian point operations, and full
// ECDSA sign/verify using test vectors from RFC 6979 Appendix A.2.5
// (P-256, SHA-256, message = "sample").
//
// Build: cd programs && make p256-ecdsa-test
// Run:   bin/riscv_emulator --machine qemu-virt programs/out/elf/p256-ecdsa-test.elf
// By Ulrik Hørlyk Hjort 2026

#include <stdint.h>
#include <string.h>
#include "log.h"

/* =========================================================================
 * Types and basic helpers
 * ========================================================================= */

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
 * P-256 parameters (little-endian word arrays)
 *
 * p  = FFFFFFFF 00000001 00000000 00000000 00000000 FFFFFFFF FFFFFFFF FFFFFFFF
 * a  = FFFFFFFF 00000001 00000000 00000000 00000000 FFFFFFFF FFFFFFFF FFFFFFFC
 *      (= p - 3)
 * b  = 5AC635D8 AA3A93E7 B3EBBD55 769886BC 651D06B0 CC53B0F6 3BCE3C3E 27D2604B
 * Gx = 6B17D1F2 E12C4247 F8BCE6E5 63A440F2 77037D81 2DEB33A0 F4A13945 D898C296
 * Gy = 4FE342E2 FE1A7F9B 8EE7EB4A 7C0F9E16 2BCE3357 6B315ECE CBB64068 37BF51F5
 * n  = FFFFFFFF 00000000 FFFFFFFF FFFFFFFF BCE6FAAD A7179E84 F3B9CAC2 FC632551
 * ========================================================================= */

static const fe P256_P = {{
    0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0x00000000,
    0x00000000, 0x00000000, 0x00000001, 0xFFFFFFFF
}};

static const fe P256_A = {{
    0xFFFFFFFC, 0xFFFFFFFF, 0xFFFFFFFF, 0x00000000,
    0x00000000, 0x00000000, 0x00000001, 0xFFFFFFFF
}};

static const fe P256_B = {{
    0x27D2604B, 0x3BCE3C3E, 0xCC53B0F6, 0x651D06B0,
    0x769886BC, 0xB3EBBD55, 0xAA3A93E7, 0x5AC635D8
}};

static const fe P256_GX = {{
    0xD898C296, 0xF4A13945, 0x2DEB33A0, 0x77037D81,
    0x63A440F2, 0xF8BCE6E5, 0xE12C4247, 0x6B17D1F2
}};

static const fe P256_GY = {{
    0x37BF51F5, 0xCBB64068, 0x6B315ECE, 0x2BCE3357,
    0x7C0F9E16, 0x8EE7EB4A, 0xFE1A7F9B, 0x4FE342E2
}};

/* Group order n */
static const fe P256_N = {{
    0xFC632551, 0xF3B9CAC2, 0xA7179E84, 0xBCE6FAAD,
    0xFFFFFFFF, 0xFFFFFFFF, 0x00000000, 0xFFFFFFFF
}};

/* =========================================================================
 * 256-bit integer primitives
 * ========================================================================= */

static void fe_set_u32(fe *r, u32 v)
{
    r->d[0] = v;
    r->d[1] = r->d[2] = r->d[3] = r->d[4] =
    r->d[5] = r->d[6] = r->d[7] = 0;
}

static int fe_is_zero(const fe *a)
{
    u32 acc = 0;
    int i;
    for (i = 0; i < 8; i++) acc |= a->d[i];
    return acc == 0;
}

/* Returns -1, 0, or +1 */
static int fe_cmp(const fe *a, const fe *b)
{
    int i;
    for (i = 7; i >= 0; i--) {
        if (a->d[i] < b->d[i]) return -1;
        if (a->d[i] > b->d[i]) return  1;
    }
    return 0;
}

/* r = a + b (raw, no reduction), returns carry out */
static u32 fe_add_raw(fe *r, const fe *a, const fe *b)
{
    u64 acc = 0;
    int i;
    for (i = 0; i < 8; i++) {
        acc += (u64)a->d[i] + b->d[i];
        r->d[i] = (u32)acc;
        acc >>= 32;
    }
    return (u32)acc;
}

/* r = a - b (raw, no reduction), returns borrow */
static u32 fe_sub_raw(fe *r, const fe *a, const fe *b)
{
    u64 acc = 0;
    int i;
    for (i = 0; i < 8; i++) {
        acc = (u64)a->d[i] - b->d[i] - acc;
        r->d[i] = (u32)acc;
        acc = (acc >> 32) & 1;  /* borrow */
    }
    return (u32)acc;
}

/* r = a >> 1 (logical) */
static void fe_shift_right1(fe *r, const fe *a)
{
    int i;
    for (i = 0; i < 7; i++)
        r->d[i] = (a->d[i] >> 1) | (a->d[i+1] << 31);
    r->d[7] = a->d[7] >> 1;
}

static void fe_copy(fe *r, const fe *a)
{
    memcpy(r, a, sizeof(fe));
}

/* =========================================================================
 * P-256 field arithmetic mod p
 * ========================================================================= */

/* r = (a + b) mod p */
static void p256_add(fe *r, const fe *a, const fe *b)
{
    u32 carry = fe_add_raw(r, a, b);
    /* if carry OR r >= p, subtract p */
    if (carry || fe_cmp(r, &P256_P) >= 0)
        fe_sub_raw(r, r, &P256_P);
}

/* r = (a - b) mod p */
static void p256_sub(fe *r, const fe *a, const fe *b)
{
    u32 borrow = fe_sub_raw(r, a, b);
    if (borrow)
        fe_add_raw(r, r, &P256_P);
}

/* r = -a mod p */
static void p256_neg(fe *r, const fe *a)
{
    if (fe_is_zero(a)) {
        fe_set_u32(r, 0);
    } else {
        fe_sub_raw(r, &P256_P, a);
    }
}

/*
 * P-256 reduction mod p.
 * Given the 512-bit product T = t[0..15] (little-endian 32-bit words),
 * reduce mod p = 2^256 - 2^224 + 2^192 + 2^96 - 1.
 *
 * Method: for each high limb t[k] (k=8..15), fold it back using the identity
 *   t[k] * 2^(32k) == t[k] * R[k] (mod p)
 * where R[k] = 2^(32k) mod p is a precomputed 8-word unsigned constant.
 *
 * Carry propagation is done using a 9-word unsigned accumulator (acc[8] catches
 * overflow), then the overflow is folded in up to 2 more times until stable.
 */
static void p256_reduce(fe *r, const u32 t[16])
{
    /* R[k-8] = 2^(32*k) mod p, as 8 unsigned 32-bit words (little-endian).
     * Computed from: 2^256 mod p = 2^224 - 2^192 - 2^96 + 1, then shifted. */
    static const u32 R[8][8] = {
        /* k=8  */ {0x00000001, 0x00000000, 0x00000000, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFE, 0x00000000},
        /* k=9  */ {0x00000000, 0x00000001, 0x00000000, 0x00000000, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFE},
        /* k=10 */ {0xFFFFFFFF, 0x00000000, 0x00000001, 0x00000001, 0xFFFFFFFF, 0xFFFFFFFE, 0x00000000, 0xFFFFFFFE},
        /* k=11 */ {0xFFFFFFFE, 0xFFFFFFFF, 0x00000000, 0x00000003, 0x00000000, 0xFFFFFFFF, 0x00000000, 0xFFFFFFFE},
        /* k=12 */ {0xFFFFFFFE, 0xFFFFFFFE, 0xFFFFFFFF, 0x00000002, 0x00000002, 0x00000000, 0x00000001, 0xFFFFFFFE},
        /* k=13 */ {0xFFFFFFFE, 0xFFFFFFFE, 0xFFFFFFFE, 0x00000001, 0x00000002, 0x00000002, 0x00000002, 0xFFFFFFFE},
        /* k=14 */ {0xFFFFFFFF, 0xFFFFFFFE, 0xFFFFFFFE, 0xFFFFFFFF, 0x00000000, 0x00000002, 0x00000003, 0x00000000},
        /* k=15 */ {0x00000000, 0xFFFFFFFF, 0xFFFFFFFE, 0xFFFFFFFE, 0xFFFFFFFF, 0x00000000, 0x00000002, 0x00000003},
    };
    u32 acc[8];
    u64 prod;
    u32 carry, carry2;
    int i, j;

    /* Initialize accumulator with low 8 words */
    for (i = 0; i < 8; i++) acc[i] = t[i];

    /*
     * Fold each high word t[k] into acc[0..7].
     * After adding t[k]*R[k], the carry is at most 2^32-1 (one 32-bit word).
     * We immediately fold that carry using R[0] = 2^256 mod p.
     * That fold may produce a tiny carry (0, 1, or 2) which we fold once more.
     */
    for (i = 0; i < 8; i++) {
        u32 hi = t[i + 8];
        if (hi == 0) continue;

        /* acc += hi * R[i] */
        carry = 0;
        for (j = 0; j < 8; j++) {
            prod = (u64)acc[j] + (u64)hi * R[i][j] + carry;
            acc[j] = (u32)prod;
            carry  = (u32)(prod >> 32);
        }

        /* fold carry: acc += carry * R[0] */
        if (carry) {
            carry2 = 0;
            for (j = 0; j < 8; j++) {
                prod = (u64)acc[j] + (u64)carry * R[0][j] + carry2;
                acc[j] = (u32)prod;
                carry2 = (u32)(prod >> 32);
            }
            /* one more fold if needed */
            if (carry2) {
                carry = 0;
                for (j = 0; j < 8; j++) {
                    prod = (u64)acc[j] + (u64)carry2 * R[0][j] + carry;
                    acc[j] = (u32)prod;
                    carry  = (u32)(prod >> 32);
                }
            }
        }
    }

    for (i = 0; i < 8; i++) r->d[i] = acc[i];

    /* Final conditional subtraction: ensure result < p */
    if (fe_cmp(r, &P256_P) >= 0)
        fe_sub_raw(r, r, &P256_P);
}

/* r = (a * b) mod p using schoolbook 8x8 multiplication + Solinas reduction */
static void p256_mul(fe *r, const fe *a, const fe *b)
{
    u32 t[16];
    u64 acc;
    int i, j;

    memset(t, 0, sizeof(t));

    for (i = 0; i < 8; i++) {
        acc = 0;
        for (j = 0; j < 8; j++) {
            acc += (u64)t[i+j] + (u64)a->d[i] * b->d[j];
            t[i+j] = (u32)acc;
            acc >>= 32;
        }
        t[i+8] += (u32)acc;
    }

    p256_reduce(r, t);
}

/* r = a^2 mod p */
static void p256_sqr(fe *r, const fe *a)
{
    p256_mul(r, a, a);
}

/* r = a^{e} mod p using square-and-multiply, e given as fe */
static void p256_pow(fe *r, const fe *a, const fe *e)
{
    fe base, result;
    int i, bit;

    fe_copy(&base, a);
    fe_set_u32(&result, 1);

    for (i = 0; i < 8; i++) {
        for (bit = 0; bit < 32; bit++) {
            if ((e->d[i] >> bit) & 1)
                p256_mul(&result, &result, &base);
            p256_sqr(&base, &base);
        }
    }
    fe_copy(r, &result);
}

/* r = a^{-1} mod p = a^{p-2} mod p (Fermat) */
static void p256_inv(fe *r, const fe *a)
{
    /* p - 2 = FFFFFFFF00000001000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFD */
    fe pm2 = {{
        0xFFFFFFFD, 0xFFFFFFFF, 0xFFFFFFFF, 0x00000000,
        0x00000000, 0x00000000, 0x00000001, 0xFFFFFFFF
    }};
    p256_pow(r, a, &pm2);
}

/* =========================================================================
 * Modular arithmetic mod n (group order)
 * Uses the same fe type; reduction is by trial subtraction (n is 256-bit).
 * ========================================================================= */

/* r = (a + b) mod n */
static void n_add(fe *r, const fe *a, const fe *b)
{
    u32 carry = fe_add_raw(r, a, b);
    if (carry || fe_cmp(r, &P256_N) >= 0)
        fe_sub_raw(r, r, &P256_N);
}

/*
 * n_reduce: reduce 16-word product mod n using precomputed R[k] = 2^(32*k) mod n.
 * Same algorithm as p256_reduce but with group order n.
 */
static void n_reduce(fe *r, const u32 t[16])
{
    /* R[k-8] = 2^(32*k) mod n, as 8 unsigned 32-bit words (little-endian) */
    static const u32 Rn[8][8] = {
        /* k=8  */ {0x039CDAAF, 0x0C46353D, 0x58E8617B, 0x43190552, 0x00000000, 0x00000000, 0xFFFFFFFF, 0x00000000},
        /* k=9  */ {0x00000000, 0x039CDAAF, 0x0C46353D, 0x58E8617B, 0x43190552, 0x00000000, 0x00000000, 0xFFFFFFFF},
        /* k=10 */ {0xFC632551, 0xF756A571, 0xB6FAAE70, 0x22159165, 0x9C0166CD, 0x43190552, 0x00000001, 0xFFFFFFFE},
        /* k=11 */ {0xF8C64AA2, 0xE7739585, 0x51CC17B8, 0x89B10547, 0x652E96B7, 0x9C0166CD, 0x43190554, 0xFFFFFFFE},
        /* k=12 */ {0xFC632551, 0xF01CF013, 0x9AD16947, 0x679B73E1, 0xCCCA0A99, 0x652E96B7, 0x9C0166CE, 0x43190552},
        /* k=13 */ {0x609A770E, 0x74D1CB7B, 0xADAE2385, 0xA83F3999, 0x79318F1C, 0xCCCA0A99, 0x22159165, 0xDF1A6C20},
        /* k=14 */ {0x4A40048F, 0x227511DE, 0x0A16AD07, 0x27F60529, 0xE2B8F21E, 0x79318F1C, 0xEDAF9E78, 0x012FFD85},
        /* k=15 */ {0xB9BD8FEB, 0x108E407A, 0x5C29D906, 0xECD00DB8, 0x2845B238, 0xE2B8F21E, 0x78019197, 0xEEDF9BFD},
    };
    u32 acc[8];
    u64 prod;
    u32 carry, carry2;
    int i, j;

    for (i = 0; i < 8; i++) acc[i] = t[i];

    for (i = 0; i < 8; i++) {
        u32 hi = t[i + 8];
        if (hi == 0) continue;

        carry = 0;
        for (j = 0; j < 8; j++) {
            prod = (u64)acc[j] + (u64)hi * Rn[i][j] + carry;
            acc[j] = (u32)prod;
            carry  = (u32)(prod >> 32);
        }

        if (carry) {
            carry2 = 0;
            for (j = 0; j < 8; j++) {
                prod = (u64)acc[j] + (u64)carry * Rn[0][j] + carry2;
                acc[j] = (u32)prod;
                carry2 = (u32)(prod >> 32);
            }
            if (carry2) {
                carry = 0;
                for (j = 0; j < 8; j++) {
                    prod = (u64)acc[j] + (u64)carry2 * Rn[0][j] + carry;
                    acc[j] = (u32)prod;
                    carry  = (u32)(prod >> 32);
                }
            }
        }
    }

    for (i = 0; i < 8; i++) r->d[i] = acc[i];

    if (fe_cmp(r, &P256_N) >= 0)
        fe_sub_raw(r, r, &P256_N);
}

/* r = (a * b) mod n */
static void n_mul(fe *r, const fe *a, const fe *b)
{
    u32 t[16];
    int i, j;
    u64 acc;

    memset(t, 0, sizeof(t));
    for (i = 0; i < 8; i++) {
        acc = 0;
        for (j = 0; j < 8; j++) {
            acc += (u64)t[i+j] + (u64)a->d[i] * b->d[j];
            t[i+j] = (u32)acc;
            acc >>= 32;
        }
        t[i+8] += (u32)acc;
    }

    n_reduce(r, t);
}

/* r = a^{-1} mod n using extended Euclidean algorithm (binary method) */
static void n_inv(fe *r, const fe *a)
{
    /* Use Fermat: a^{n-2} mod n */
    /* n - 2 */
    fe nm2 = {{
        0xFC63254F, 0xF3B9CAC2, 0xA7179E84, 0xBCE6FAAD,
        0xFFFFFFFF, 0xFFFFFFFF, 0x00000000, 0xFFFFFFFF
    }};
    fe base, result;
    int i, bit;

    fe_copy(&base, a);
    fe_set_u32(&result, 1);

    for (i = 0; i < 8; i++) {
        for (bit = 0; bit < 32; bit++) {
            if ((nm2.d[i] >> bit) & 1)
                n_mul(&result, &result, &base);
            n_mul(&base, &base, &base);  /* square */
        }
    }
    fe_copy(r, &result);
}

/* =========================================================================
 * Jacobian point arithmetic
 * Affine (x,y) maps to Jacobian (X:Y:Z) with x = X/Z^2, y = Y/Z^3.
 * ========================================================================= */

typedef struct {
    fe X, Y, Z;
    int infinity;
} jpoint;

static void jpoint_set_infinity(jpoint *r)
{
    fe_set_u32(&r->X, 0);
    fe_set_u32(&r->Y, 1);
    fe_set_u32(&r->Z, 0);
    r->infinity = 1;
}

static void jpoint_from_affine(jpoint *r, const fe *x, const fe *y)
{
    fe_copy(&r->X, x);
    fe_copy(&r->Y, y);
    fe_set_u32(&r->Z, 1);
    r->infinity = 0;
}

/* Convert Jacobian to affine: ax = X*Z^{-2}, ay = Y*Z^{-3} */
static void point_to_affine(fe *ax, fe *ay, const jpoint *jp)
{
    fe zinv, zinv2, zinv3;
    if (jp->infinity) {
        fe_set_u32(ax, 0);
        fe_set_u32(ay, 0);
        return;
    }
    p256_inv(&zinv, &jp->Z);
    p256_mul(&zinv2, &zinv, &zinv);
    p256_mul(&zinv3, &zinv2, &zinv);
    p256_mul(ax, &jp->X, &zinv2);
    p256_mul(ay, &jp->Y, &zinv3);
}

/*
 * Jacobian point doubling: R = 2*P
 * Using the a=-3 optimization (P-256 has a = p-3 == -3 mod p).
 *
 * Algorithm (from NIST FIPS 186-4 / Hankerson et al.):
 *   T1 = Z1^2
 *   T2 = X1 - T1  (using a=-3: 3*X1^2 + a*Z1^4 = 3*(X1-Z1^2)*(X1+Z1^2))
 *   T3 = X1 + T1
 *   T2 = T2 * T3
 *   T2 = 3 * T2   (= M)
 *   Z3 = 2 * Y1 * Z1
 *   T3 = Y1^2
 *   T4 = T3 * X1  (= S = X1 * Y1^2)
 *   T4 = 4 * T4
 *   X3 = T2^2 - 2*T4
 *   T3 = T3^2 * 8  (= 8*Y1^4)
 *   Y3 = T2*(T4 - X3) - T3
 */
static void point_double(jpoint *r, const jpoint *p256pt)
{
    fe T1, T2, T3, T4;
    fe tmp;

    if (p256pt->infinity) {
        jpoint_set_infinity(r);
        return;
    }

    /* T1 = Z^2 */
    p256_sqr(&T1, &p256pt->Z);

    /* T2 = X - T1, T3 = X + T1 */
    p256_sub(&T2, &p256pt->X, &T1);
    p256_add(&T3, &p256pt->X, &T1);

    /* T2 = T2 * T3 */
    p256_mul(&T2, &T2, &T3);

    /* T2 = 3 * T2  (M = 3*(X-Z^2)*(X+Z^2)) */
    fe_copy(&tmp, &T2);
    p256_add(&T2, &T2, &tmp);   /* 2*T2 */
    p256_add(&T2, &T2, &tmp);   /* 3*T2 */

    /* Z3 = 2 * Y * Z */
    p256_mul(&r->Z, &p256pt->Y, &p256pt->Z);
    p256_add(&r->Z, &r->Z, &r->Z);

    /* T3 = Y^2 */
    p256_sqr(&T3, &p256pt->Y);

    /* T4 = 4 * X * Y^2 (S) */
    p256_mul(&T4, &p256pt->X, &T3);
    p256_add(&T4, &T4, &T4);  /* 2 */
    p256_add(&T4, &T4, &T4);  /* 4 */

    /* X3 = T2^2 - 2*T4 */
    p256_sqr(&r->X, &T2);
    p256_sub(&r->X, &r->X, &T4);
    p256_sub(&r->X, &r->X, &T4);

    /* T3 = 8 * Y^4 */
    p256_sqr(&T3, &T3);
    p256_add(&T3, &T3, &T3);
    p256_add(&T3, &T3, &T3);
    p256_add(&T3, &T3, &T3);

    /* Y3 = T2*(T4 - X3) - T3 */
    p256_sub(&T4, &T4, &r->X);
    p256_mul(&r->Y, &T2, &T4);
    p256_sub(&r->Y, &r->Y, &T3);

    r->infinity = 0;
}

/*
 * Jacobian + affine point addition: R = P + Q  (Q in affine, Z_Q = 1)
 *
 * Algorithm (standard Jacobian + affine, a.k.a. "mixed addition"):
 *   U1 = X1, U2 = X2*Z1^2
 *   S1 = Y1, S2 = Y2*Z1^3
 *   H = U2 - U1
 *   Rv = S2 - S1
 *   if H == 0: if Rv == 0: double, else infinity
 *   X3 = Rv^2 - H^3 - 2*U1*H^2
 *   Y3 = Rv*(U1*H^2 - X3) - S1*H^3
 *   Z3 = H*Z1
 */
static void point_add_mixed(jpoint *r, const jpoint *p256pt, const fe *qx, const fe *qy)
{
    fe Z1sq, U2, S2, H, Rv, H2, H3, U1H2, tmp;

    if (p256pt->infinity) {
        jpoint_from_affine(r, qx, qy);
        return;
    }

    p256_sqr(&Z1sq, &p256pt->Z);
    p256_mul(&U2, qx, &Z1sq);
    p256_mul(&S2, qy, &Z1sq);
    p256_mul(&S2, &S2, &p256pt->Z);

    p256_sub(&H, &U2, &p256pt->X);
    p256_sub(&Rv, &S2, &p256pt->Y);

    if (fe_is_zero(&H)) {
        if (fe_is_zero(&Rv))
            point_double(r, p256pt);
        else
            jpoint_set_infinity(r);
        return;
    }

    p256_sqr(&H2, &H);
    p256_mul(&H3, &H2, &H);
    p256_mul(&U1H2, &p256pt->X, &H2);
    p256_mul(&r->Z, &p256pt->Z, &H);

    p256_sqr(&r->X, &Rv);
    p256_sub(&r->X, &r->X, &H3);
    p256_sub(&r->X, &r->X, &U1H2);
    p256_sub(&r->X, &r->X, &U1H2);

    p256_sub(&tmp, &U1H2, &r->X);
    p256_mul(&r->Y, &Rv, &tmp);
    p256_mul(&tmp, &p256pt->Y, &H3);
    p256_sub(&r->Y, &r->Y, &tmp);

    r->infinity = 0;
}

/*
 * Full Jacobian + Jacobian point addition: R = P1 + P2
 *
 * Algorithm (general Jacobian add):
 *   U1 = X1*Z2^2,  U2 = X2*Z1^2
 *   S1 = Y1*Z2^3,  S2 = Y2*Z1^3
 *   H = U2 - U1,   Rv = S2 - S1
 *   if H == 0: if Rv == 0: double, else infinity
 *   X3 = Rv^2 - H^3 - 2*U1*H^2
 *   Y3 = Rv*(U1*H^2 - X3) - S1*H^3
 *   Z3 = H*Z1*Z2
 */
static void point_add(jpoint *r, const jpoint *p1, const jpoint *p2)
{
    fe Z1sq, Z2sq, U1, U2, S1, S2, H, Rv, H2, H3, U1H2, tmp;

    if (p1->infinity) { *r = *p2; return; }
    if (p2->infinity) { *r = *p1; return; }

    p256_sqr(&Z1sq, &p1->Z);
    p256_sqr(&Z2sq, &p2->Z);

    /* U1 = X1*Z2^2, U2 = X2*Z1^2 */
    p256_mul(&U1, &p1->X, &Z2sq);
    p256_mul(&U2, &p2->X, &Z1sq);

    /* S1 = Y1*Z2^3, S2 = Y2*Z1^3 */
    p256_mul(&S1, &p1->Y, &Z2sq);
    p256_mul(&S1, &S1, &p2->Z);
    p256_mul(&S2, &p2->Y, &Z1sq);
    p256_mul(&S2, &S2, &p1->Z);

    p256_sub(&H, &U2, &U1);
    p256_sub(&Rv, &S2, &S1);

    if (fe_is_zero(&H)) {
        if (fe_is_zero(&Rv))
            point_double(r, p1);
        else
            jpoint_set_infinity(r);
        return;
    }

    p256_sqr(&H2, &H);
    p256_mul(&H3, &H2, &H);
    p256_mul(&U1H2, &U1, &H2);

    /* Z3 = H * Z1 * Z2 */
    p256_mul(&r->Z, &H, &p1->Z);
    p256_mul(&r->Z, &r->Z, &p2->Z);

    /* X3 = Rv^2 - H^3 - 2*U1H2 */
    p256_sqr(&r->X, &Rv);
    p256_sub(&r->X, &r->X, &H3);
    p256_sub(&r->X, &r->X, &U1H2);
    p256_sub(&r->X, &r->X, &U1H2);

    /* Y3 = Rv*(U1H2 - X3) - S1*H3 */
    p256_sub(&tmp, &U1H2, &r->X);
    p256_mul(&r->Y, &Rv, &tmp);
    p256_mul(&tmp, &S1, &H3);
    p256_sub(&r->Y, &r->Y, &tmp);

    r->infinity = 0;
}

/* R = k * P  (double-and-add, MSB first, 256-bit scalar) */
static void scalar_mult(jpoint *r, const fe *k, const jpoint *p256pt)
{
    jpoint Q;
    int i, bit;

    jpoint_set_infinity(&Q);

    for (i = 7; i >= 0; i--) {
        for (bit = 31; bit >= 0; bit--) {
            point_double(&Q, &Q);
            if ((k->d[i] >> bit) & 1)
                point_add(&Q, &Q, p256pt);
        }
    }
    *r = Q;
}

/* R = k * G  (base point scalar multiplication) */
static void scalar_mult_base(jpoint *r, const fe *k)
{
    jpoint G;
    jpoint_from_affine(&G, &P256_GX, &P256_GY);
    scalar_mult(r, k, &G);
}

/* =========================================================================
 * ECDSA sign and verify
 * ========================================================================= */

/* Sign: given private key d, hash h, nonce k -> (r, s) */
static void ecdsa_sign(fe *sig_r, fe *sig_s,
                       const fe *d, const fe *h, const fe *k)
{
    jpoint kG;
    fe r_fe, tmp, ki;

    /* r = (k*G).x mod n */
    scalar_mult_base(&kG, k);
    point_to_affine(&r_fe, &tmp, &kG);

    /* r = r_fe mod n */
    fe_copy(sig_r, &r_fe);
    if (fe_cmp(sig_r, &P256_N) >= 0)
        fe_sub_raw(sig_r, sig_r, &P256_N);

    /* s = k^{-1} * (h + r*d) mod n */
    n_mul(&tmp, sig_r, d);    /* r*d */
    n_add(&tmp, &tmp, h);     /* h + r*d */
    n_inv(&ki, k);
    n_mul(sig_s, &ki, &tmp);
}

/* Verify: given public key (Qx,Qy), hash h, signature (r,s) -> 1 or 0 */
static int ecdsa_verify(const fe *Qx, const fe *Qy,
                        const fe *h, const fe *sig_r, const fe *sig_s)
{
    fe w, u1, u2;
    jpoint R1, R2, Rsum, Q_jac;
    fe ax, ay;

    /* w = s^{-1} mod n */
    n_inv(&w, sig_s);

    /* u1 = h*w mod n, u2 = r*w mod n */
    n_mul(&u1, h, &w);
    n_mul(&u2, sig_r, &w);

    /* R = u1*G + u2*Q */
    scalar_mult_base(&R1, &u1);

    jpoint_from_affine(&Q_jac, Qx, Qy);
    scalar_mult(&R2, &u2, &Q_jac);

    point_add(&Rsum, &R1, &R2);
    if (Rsum.infinity) return 0;

    point_to_affine(&ax, &ay, &Rsum);

    /* Check ax mod n == r */
    if (fe_cmp(&ax, &P256_N) >= 0)
        fe_sub_raw(&ax, &ax, &P256_N);

    return fe_cmp(&ax, sig_r) == 0;
}

/* =========================================================================
 * Helper: print a 256-bit value as 8 hex words
 * ========================================================================= */
static void fe_print(const char *label, const fe *v)
{
    log_write(NONE, "%s: %x%x%x%x%x%x%x%x\n", label,
        v->d[7], v->d[6], v->d[5], v->d[4],
        v->d[3], v->d[2], v->d[1], v->d[0]);
}

/* =========================================================================
 * Test vectors (RFC 6979 Appendix A.2.5, P-256 SHA-256, message = "sample")
 *
 * a = FFFFFFFF00000001000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFC (= p-3)
 *
 * Private key d:
 *   C9AFA9D8 45BA7516 6B5C2157 67B1D693 4E50C3DB 36E89B12 7B8A622B 120F6721
 *
 * Public key Q = d*G:
 *   Qx = 60FED4BA 255A9D31 C961EB74 C6356D68 C049B892 3B61FA6C E669622E 60F29FB6
 *   Qy = 7903FE10 08B8BC99 A41AE9E9 5628BC64 F2F1B20C 2D7E9F51 77A3C294 D4462299
 *
 * SHA-256("sample"):
 *   AF2BDBE1 AA9B6EC1 E2ADE1D6 94F41FC7 1A831D02 68E98915 62113D8A 62ADD1BF
 *
 * RFC 6979 nonce k:
 *   A6E3C57D D01ABE90 08653839 8355DD4C 3B17AA87 3382B0F2 4D612949 3D8AAD60
 *
 * r = (k*G).x mod n:
 *   EFD48B2A ACB6A8FD 1140DD9C D45E81D6 9D2C877B 56AAF991 C34D0EA8 4EAF3716
 *
 * s = k^{-1}*(hash + r*d) mod n:
 *   F7CB1C94 2D657C41 D436C7A1 B6E29F65 F3E900DB B9AFF406 4DC4AB2F 843ACDA8
 * ========================================================================= */

static const fe TV_D = {{
    0x120F6721, 0x7B8A622B, 0x36E89B12, 0x4E50C3DB,
    0x67B1D693, 0x6B5C2157, 0x45BA7516, 0xC9AFA9D8
}};

static const fe TV_QX = {{
    0x60F29FB6, 0xE669622E, 0x3B61FA6C, 0xC049B892,
    0xC6356D68, 0xC961EB74, 0x255A9D31, 0x60FED4BA
}};

static const fe TV_QY = {{
    0xD4462299, 0x77A3C294, 0x2D7E9F51, 0xF2F1B20C,
    0x5628BC64, 0xA41AE9E9, 0x08B8BC99, 0x7903FE10
}};

/* SHA-256("sample") */
static const fe TV_HASH = {{
    0x62ADD1BF, 0x62113D8A, 0x68E98915, 0x1A831D02,
    0x94F41FC7, 0xE2ADE1D6, 0xAA9B6EC1, 0xAF2BDBE1
}};

static const fe TV_K = {{
    0x3D8AAD60, 0x4D612949, 0x3382B0F2, 0x3B17AA87,
    0x8355DD4C, 0x08653839, 0xD01ABE90, 0xA6E3C57D
}};

static const fe TV_R = {{
    0x4EAF3716, 0xC34D0EA8, 0x56AAF991, 0x9D2C877B,
    0xD45E81D6, 0x1140DD9C, 0xACB6A8FD, 0xEFD48B2A
}};

static const fe TV_S = {{
    0x843ACDA8, 0x4DC4AB2F, 0xB9AFF406, 0xF3E900DB,
    0xB6E29F65, 0xD436C7A1, 0x2D657C41, 0xF7CB1C94
}};

/* =========================================================================
 * Tests
 * ========================================================================= */

static void test_field_arithmetic(void)
{
    fe a, b, r, expected;

    /* --- Test 1: Gx + Gy mod p
     * Expected: BAFB14D5 DF46C1E3 87A4D22F DFB3DF08 A2D1B0D8 991C926F C05779AE 1058148B
     */
    fe_copy(&a, &P256_GX);
    fe_copy(&b, &P256_GY);
    p256_add(&r, &a, &b);
    expected = (fe){{
        0x1058148B, 0xC05779AE, 0x991C926F, 0xA2D1B0D8,
        0xDFB3DF08, 0x87A4D22F, 0xDF46C1E3, 0xBAFB14D5
    }};
    chk("field_add_GxGy", fe_cmp(&r, &expected) == 0);

    /* --- Test 2: Gx - Gy mod p */
    p256_sub(&r, &P256_GX, &P256_GY);
    /* Gx < Gy so result = Gx - Gy + p */
    /* Just verify it's < p */
    chk("field_sub_lt_p", fe_cmp(&r, &P256_P) < 0);

    /* --- Test 3: a = 1 * b = 1 => a*b = 1 */
    fe_set_u32(&a, 1);
    fe_set_u32(&b, 1);
    p256_mul(&r, &a, &b);
    fe_set_u32(&expected, 1);
    chk("field_mul_1x1", fe_cmp(&r, &expected) == 0);

    /* --- Test 4: Gx * Gy mod p
     * Expected: 823CD15F 6DD3C719 33565064 513A6B2B D183E554 C6A08622 F713EBBB FACE98BE
     */
    p256_mul(&r, &P256_GX, &P256_GY);
    expected = (fe){{
        0xFACE98BE, 0xF713EBBB, 0xC6A08622, 0xD183E554,
        0x513A6B2B, 0x33565064, 0x6DD3C719, 0x823CD15F
    }};
    chk("field_mul_GxGy", fe_cmp(&r, &expected) == 0);

    /* --- Test 5: inverse: Gx * Gx^{-1} = 1 */
    p256_inv(&b, &P256_GX);
    p256_mul(&r, &P256_GX, &b);
    fe_set_u32(&expected, 1);
    chk("field_inv_Gx", fe_cmp(&r, &expected) == 0);

    /* --- Test 6: neg: -0 = 0 */
    fe_set_u32(&a, 0);
    p256_neg(&r, &a);
    fe_set_u32(&expected, 0);
    chk("field_neg_zero", fe_cmp(&r, &expected) == 0);

    /* --- Test 7: neg: -(p-1) = 1 */
    fe_sub_raw(&a, &P256_P, &(fe){{1,0,0,0,0,0,0,0}});  /* a = p-1 */
    p256_neg(&r, &a);
    fe_set_u32(&expected, 1);
    chk("field_neg_pm1", fe_cmp(&r, &expected) == 0);
}

static void test_curve_checks(void)
{
    fe lhs, rhs, tmp, a_fe;

    /* --- Test 8: G is on curve: Gy^2 = Gx^3 + a*Gx + b mod p
     * a = p-3, use p256_mul and p256_add
     */
    /* lhs = Gy^2 */
    p256_sqr(&lhs, &P256_GY);

    /* rhs = Gx^3 */
    p256_sqr(&rhs, &P256_GX);
    p256_mul(&rhs, &rhs, &P256_GX);

    /* rhs += a*Gx  (a = p-3 = -3, so a*Gx = -3*Gx) */
    fe_copy(&a_fe, &P256_A);
    p256_mul(&tmp, &a_fe, &P256_GX);
    p256_add(&rhs, &rhs, &tmp);

    /* rhs += b */
    p256_add(&rhs, &rhs, &P256_B);

    chk("G_on_curve", fe_cmp(&lhs, &rhs) == 0);

    /* --- Test 9: Q = d*G on curve */
    fe Qx_copy, Qy_copy;
    fe_copy(&Qx_copy, &TV_QX);
    fe_copy(&Qy_copy, &TV_QY);

    p256_sqr(&lhs, &Qy_copy);
    p256_sqr(&rhs, &Qx_copy);
    p256_mul(&rhs, &rhs, &Qx_copy);
    p256_mul(&tmp, &a_fe, &Qx_copy);
    p256_add(&rhs, &rhs, &tmp);
    p256_add(&rhs, &rhs, &P256_B);
    chk("Q_on_curve", fe_cmp(&lhs, &rhs) == 0);
}

static void test_point_ops(void)
{
    jpoint R;
    fe ax, ay;

    /* --- Test 10: 1*G = G */
    fe one;
    fe_set_u32(&one, 1);
    scalar_mult_base(&R, &one);
    point_to_affine(&ax, &ay, &R);
    chk("scalar_1G_x", fe_cmp(&ax, &P256_GX) == 0);
    chk("scalar_1G_y", fe_cmp(&ay, &P256_GY) == 0);

    /* --- Test 12: 2*G = G+G using doubling vs addition */
    jpoint G_jac, add_result, dbl_result;
    jpoint_from_affine(&G_jac, &P256_GX, &P256_GY);
    point_double(&dbl_result, &G_jac);
    point_add(&add_result, &G_jac, &G_jac);

    fe ax2, ay2, ax3, ay3;
    point_to_affine(&ax2, &ay2, &dbl_result);
    point_to_affine(&ax3, &ay3, &add_result);
    chk("2G_double_eq_add_x", fe_cmp(&ax2, &ax3) == 0);
    chk("2G_double_eq_add_y", fe_cmp(&ay2, &ay3) == 0);

    /* --- Test 13: 2*G known coordinates
     * 2G.x = 7CF27B18 8D034F7E 8A523803 04B51AC3 C08969E2 77F21B35 A60B48FC 47669978
     * 2G.y = 07775510 DB8ED040 293D9AC6 9F7430DB BA7DADE6 3CE98229 9E04B79D 227873D1
     */
    fe twoGx = {{
        0x47669978, 0xA60B48FC, 0x77F21B35, 0xC08969E2,
        0x04B51AC3, 0x8A523803, 0x8D034F7E, 0x7CF27B18
    }};
    fe twoGy = {{
        0x227873D1, 0x9E04B79D, 0x3CE98229, 0xBA7DADE6,
        0x9F7430DB, 0x293D9AC6, 0xDB8ED040, 0x07775510
    }};
    chk("2G_x_correct", fe_cmp(&ax2, &twoGx) == 0);
    chk("2G_y_correct", fe_cmp(&ay2, &twoGy) == 0);

    /* --- Test 14: d*G = Q (public key derivation) */
    scalar_mult_base(&R, &TV_D);
    point_to_affine(&ax, &ay, &R);
    chk("pubkey_Qx", fe_cmp(&ax, &TV_QX) == 0);
    chk("pubkey_Qy", fe_cmp(&ay, &TV_QY) == 0);
}

static void test_ecdsa(void)
{
    fe sig_r, sig_s;

    /* --- Test 15/16: sign produces correct (r, s) */
    ecdsa_sign(&sig_r, &sig_s, &TV_D, &TV_HASH, &TV_K);
    chk("sign_r", fe_cmp(&sig_r, &TV_R) == 0);
    chk("sign_s", fe_cmp(&sig_s, &TV_S) == 0);

    /* --- Test 17: verify with correct inputs succeeds */
    int ok = ecdsa_verify(&TV_QX, &TV_QY, &TV_HASH, &TV_R, &TV_S);
    chk("verify_ok", ok);

    /* --- Test 18: tampered hash fails */
    fe bad_hash;
    fe_copy(&bad_hash, &TV_HASH);
    bad_hash.d[0] ^= 0x00000001;  /* flip 1 bit */
    ok = ecdsa_verify(&TV_QX, &TV_QY, &bad_hash, &TV_R, &TV_S);
    chk("verify_bad_hash_fails", !ok);

    /* --- Test 19: tampered s fails */
    fe bad_s;
    fe_copy(&bad_s, &TV_S);
    bad_s.d[0] ^= 0x00000001;
    ok = ecdsa_verify(&TV_QX, &TV_QY, &TV_HASH, &TV_R, &bad_s);
    chk("verify_bad_s_fails", !ok);

    /* --- Test 20: tampered r fails */
    fe bad_r;
    fe_copy(&bad_r, &TV_R);
    bad_r.d[0] ^= 0x00000001;
    ok = ecdsa_verify(&TV_QX, &TV_QY, &TV_HASH, &bad_r, &TV_S);
    chk("verify_bad_r_fails", !ok);

    /* --- Test 21: s=0 is rejected */
    fe zero_s;
    fe_set_u32(&zero_s, 0);
    ok = ecdsa_verify(&TV_QX, &TV_QY, &TV_HASH, &TV_R, &zero_s);
    chk("verify_zero_s_fails", !ok);
}

static void test_n_arithmetic(void)
{
    fe a, b, r, expected;

    /* n_mul: 1 * 1 = 1 mod n */
    fe_set_u32(&a, 1);
    fe_set_u32(&b, 1);
    n_mul(&r, &a, &b);
    fe_set_u32(&expected, 1);
    chk("n_mul_1x1", fe_cmp(&r, &expected) == 0);

    /* n_mul: (n-1) * (n-1) = 1 mod n */
    fe_sub_raw(&a, &P256_N, &(fe){{1,0,0,0,0,0,0,0}});
    fe_copy(&b, &a);
    n_mul(&r, &a, &b);
    fe_set_u32(&expected, 1);
    chk("n_mul_nm1_sq", fe_cmp(&r, &expected) == 0);

    /* n_inv: k * k^{-1} = 1 mod n */
    fe ki;
    n_inv(&ki, &TV_K);
    n_mul(&r, &TV_K, &ki);
    fe_set_u32(&expected, 1);
    chk("n_inv_k", fe_cmp(&r, &expected) == 0);
}

/* =========================================================================
 * main
 * ========================================================================= */

int main(void)
{
    log_init("p256-ecdsa-test.log");
    log_write(NONE, "P-256 ECDSA Test\n\n");

    log_write(NONE, "--- Field arithmetic ---\n");
    test_field_arithmetic();

    log_write(NONE, "--- Curve checks ---\n");
    test_curve_checks();

    log_write(NONE, "--- Point operations ---\n");
    test_point_ops();

    log_write(NONE, "--- n-field arithmetic ---\n");
    test_n_arithmetic();

    log_write(NONE, "--- ECDSA sign/verify ---\n");
    test_ecdsa();

    log_write(NONE, "\n%d PASS  %d FAIL\n", g_pass, g_fail);
    log_close();
    return g_fail ? 1 : 0;
}
