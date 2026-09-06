/* **************************************************************************
 *      RISC-V Emulator - Elliptic curve arithmetic over a prime field
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

// ecc-test.c -- Elliptic curve arithmetic over a prime field
//
// Curve: secp192r1 (NIST P-192) -- the smallest NIST prime curve.
//   p   = 2^192 - 2^64 - 1 (192-bit prime)
//   a   = p - 3
//   b   = 0x64210519E59C80E70FA7E9AB72243049FEB8DEECC146B9B1
//   G   = (Gx, Gy) -- generator point of order n
//   n   = #E(F_p) = group order (192-bit prime)
//
// Since 192-bit arithmetic is unwieldy for bare-metal RV32, this test
// uses a tiny EDUCATIONAL curve over a small prime field:
//
//   p  = 17  (prime)
//   a  = 2   (curve: y^2 = x^3 + 2x + 2 mod 17)
//   b  = 2
//
// This curve has order #E = 19 (prime).
// Generator: G = (5, 1)    (known point on curve)
//
// All arithmetic in [0, p-1] using 32-bit integers (max product = 16^2 = 256 < 2^32).
//
// Tests:
//   - Field arithmetic: addmod, submod, mulmod, modinv
//   - Point on curve: all multiples kG for k=1..19 lie on curve
//   - Point negation: G + (-G) = O (point at infinity)
//   - Point doubling: 2G = G + G
//   - Scalar multiplication: 19G = O (group order)
//   - Associativity: (aG + bG) + cG = aG + (bG + cG)
//   - Commutativity: aG + bG = bG + aG
//   - Discrete log: kG for k=1..19 gives all 19 non-identity group elements
//   - Small Diffie-Hellman: ECDH shared secret agreement
//
// Build: cd programs && make run-ecc-test
// By Ulrik Hørlyk Hjort 2026

#include <stdint.h>
#include "log.h"

/* -- curve parameters ------------------------------------------------------- */

#define P    17u   /* field prime */
#define A     2u   /* curve coefficient a: y^2 = x^3 + A*x + B mod P */
#define B     2u   /* curve coefficient b */

/* Point on the curve; x=0 AND y=0 represents the point at infinity O */
typedef struct { uint32_t x, y; } point_t;

/* Sentinel for point at infinity */
#define INFINITY_POINT ((point_t){0u, 0u})

static int g_pass = 0, g_fail = 0;

/* -- field arithmetic mod P ------------------------------------------------- */

static uint32_t addmod(uint32_t a, uint32_t b)
{
    a += b; if (a >= P) a -= P; return a;
}

static uint32_t submod(uint32_t a, uint32_t b)
{
    return addmod(a, P - b % P);
}

static uint32_t mulmod(uint32_t a, uint32_t b)
{
    /* a, b < 17: product < 289 < 2^32 -- no overflow */
    return (a * b) % P;
}

static uint32_t pow_mod(uint32_t base, uint32_t exp)
{
    uint32_t r = 1u; base %= P;
    while (exp) { if (exp & 1u) r = mulmod(r, base); base = mulmod(base, base); exp >>= 1; }
    return r;
}

/* Modular inverse via Fermat: a^(P-2) mod P */
static uint32_t modinv(uint32_t a)
{
    return pow_mod(a, P - 2u);
}

/* -- elliptic curve point arithmetic --------------------------------------- */

static int point_is_inf(point_t p)
{
    return p.x == 0u && p.y == 0u;
}

/* Check (x, y) satisfies y^2 = x^3 + A*x + B mod P */
static int point_on_curve(point_t pt)
{
    if (point_is_inf(pt)) return 1;
    uint32_t lhs = mulmod(pt.y, pt.y);  /* y^2 */
    uint32_t rhs = addmod(addmod(mulmod(mulmod(pt.x, pt.x), pt.x),  /* x^3 */
                                 mulmod(A, pt.x)),                   /* + A*x */
                          B);                                         /* + B */
    return lhs == rhs;
}

/* Negate a point: -(x, y) = (x, -y) = (x, P-y) */
static point_t point_neg(point_t pt)
{
    if (point_is_inf(pt)) return pt;
    return (point_t){ pt.x, submod(0u, pt.y) };
}

/* Point addition (handles infinity, doubling, negation) */
static point_t point_add(point_t P1, point_t P2)
{
    if (point_is_inf(P1)) return P2;
    if (point_is_inf(P2)) return P1;

    if (P1.x == P2.x) {
        /* Same x: either doubling (y equal) or inverse (y differ) */
        if (P1.y != P2.y)
            return INFINITY_POINT;  /* P2 = -P1 */
        /* Doubling: lambda = (3*x^2 + A) / (2*y) */
        uint32_t num = addmod(mulmod(3u, mulmod(P1.x, P1.x)), A);
        uint32_t den = modinv(mulmod(2u, P1.y));
        uint32_t lam = mulmod(num, den);
        uint32_t rx = submod(mulmod(lam, lam), mulmod(2u, P1.x));
        uint32_t ry = submod(mulmod(lam, submod(P1.x, rx)), P1.y);
        return (point_t){ rx, ry };
    }

    /* Addition: lambda = (y2 - y1) / (x2 - x1) */
    uint32_t num = submod(P2.y, P1.y);
    uint32_t den = modinv(submod(P2.x, P1.x));
    uint32_t lam = mulmod(num, den);
    uint32_t rx = submod(submod(mulmod(lam, lam), P1.x), P2.x);
    uint32_t ry = submod(mulmod(lam, submod(P1.x, rx)), P1.y);
    return (point_t){ rx, ry };
}

/* Scalar multiplication: k * P using double-and-add */
static point_t point_mul(uint32_t k, point_t pt)
{
    point_t result = INFINITY_POINT;
    while (k > 0u) {
        if (k & 1u) result = point_add(result, pt);
        pt = point_add(pt, pt);  /* double */
        k >>= 1;
    }
    return result;
}

/* -- group order: #E = 19, generator G = (5, 1) ---------------------------- */
#define ORDER    19u
static const point_t G = {5u, 1u};

/* All 19 non-identity group elements (kG for k=1..19, last = O):
 * Precomputed (verified by iterating G+G+... mod 17):
 *   1G=(5,1)  2G=(6,3)  3G=(10,6) 4G=(3,1)  5G=(9,16) 6G=(16,13) 7G=(0,6)
 *   8G=(13,7) 9G=(7,6) 10G=(7,11) 11G=(13,10) 12G=(0,11) 13G=(16,4) 14G=(9,1)
 *  15G=(3,16) 16G=(10,11) 17G=(6,14) 18G=(5,16) 19G=O
 */

/* -- test helpers ----------------------------------------------------------- */

static void chk(const char *lbl, uint32_t got, uint32_t exp)
{
    if (got == exp) { log_write(NONE, "  PASS  %s\n", lbl); g_pass++; }
    else { log_write(NONE, "  FAIL  %s: got %d  exp %d\n", lbl, (int)got, (int)exp); g_fail++; }
}

static void chk_pt(const char *lbl, point_t got, point_t exp)
{
    if (got.x == exp.x && got.y == exp.y) {
        log_write(NONE, "  PASS  %s\n", lbl);
        g_pass++;
    } else {
        log_write(NONE, "  FAIL  %s: got (%d,%d)  exp (%d,%d)\n",
                  lbl, (int)got.x, (int)got.y, (int)exp.x, (int)exp.y);
        g_fail++;
    }
}

static void chk_bool(const char *lbl, int ok)
{
    if (ok) { log_write(NONE, "  PASS  %s\n", lbl); g_pass++; }
    else    { log_write(NONE, "  FAIL  %s\n", lbl); g_fail++; }
}

/* -- tests ------------------------------------------------------------------ */

static void test_field(void)
{
    log_write(NONE, "\n-- Field arithmetic mod p=%d --\n", (int)P);

    /* addmod */
    chk("16+2=1 (mod 17)", addmod(16u, 2u), 1u);
    chk("8+9=0 (mod 17)",  addmod(8u, 9u), 0u);

    /* submod */
    chk("1-2=16 (mod 17)",  submod(1u, 2u), 16u);
    chk("5-3=2 (mod 17)",   submod(5u, 3u), 2u);

    /* mulmod */
    chk("3*6=1 (mod 17)",   mulmod(3u, 6u), 1u);   /* 3 and 6 are inverses */
    chk("4*13=1 (mod 17)",  mulmod(4u, 13u), 1u);  /* 4 and 13 are inverses */

    /* modinv */
    chk("inv(3)=6",  modinv(3u), 6u);
    chk("inv(4)=13", modinv(4u), 13u);
    chk("inv(1)=1",  modinv(1u), 1u);

    /* a * inv(a) = 1 for a=1..16 */
    int all_inv = 1;
    for (uint32_t a = 1u; a < P; a++)
        if (mulmod(a, modinv(a)) != 1u) { all_inv = 0; break; }
    chk_bool("a * inv(a) = 1 for all a in [1,P-1]", all_inv);
}

static void test_point_on_curve(void)
{
    log_write(NONE, "\n-- Generator G = (5,1) lies on curve --\n");
    chk_bool("G on curve", point_on_curve(G));
    chk_bool("infinity on curve", point_on_curve(INFINITY_POINT));

    /* Generate all multiples kG and verify each is on curve */
    int all_on = 1;
    point_t pt = G;
    for (int k = 1; k <= (int)ORDER; k++) {
        if (!point_on_curve(pt)) { all_on = 0; break; }
        pt = point_add(pt, G);
    }
    chk_bool("all kG for k=1..ORDER lie on curve", all_on);
}

static void test_group_order(void)
{
    log_write(NONE, "\n-- Group order: ORDER*G = O --\n");
    point_t nG = point_mul(ORDER, G);
    chk_bool("ORDER*G = infinity", point_is_inf(nG));

    /* (ORDER+1)*G = G */
    point_t nG1 = point_mul(ORDER + 1u, G);
    chk_pt("(ORDER+1)*G = G", nG1, G);
}

static void test_negation(void)
{
    log_write(NONE, "\n-- Point negation: G + (-G) = O --\n");
    point_t neg_G = point_neg(G);
    point_t sum   = point_add(G, neg_G);
    chk_bool("G + (-G) = O", point_is_inf(sum));

    /* -G is on curve */
    chk_bool("-G on curve", point_on_curve(neg_G));

    /* -(-G) = G */
    chk_pt("-(-G) = G", point_neg(neg_G), G);
}

static void test_doubling(void)
{
    log_write(NONE, "\n-- Point doubling: 2G = G+G --\n");
    point_t G2_add    = point_add(G, G);
    point_t G2_double = point_mul(2u, G);
    chk_pt("2G via add = 2G via mul", G2_add, G2_double);
    chk_bool("2G on curve", point_on_curve(G2_add));

    /* Verify 2G = (6, 3) by hand:
     * lambda = (3*5^2 + 2) / (2*1) = (75+2)/2 = 77/2 mod 17
     * 77 mod 17 = 77 - 4*17 = 77-68 = 9
     * 2^(-1) mod 17 = 9  (since 2*9=18==1)
     * lambda = 9*9 mod 17 = 81 mod 17 = 81-4*17=81-68=13
     * rx = 13^2 - 2*5 mod 17 = 169-10 mod 17 = 159 mod 17 = 159-9*17=159-153=6
     * ry = 13*(5-6) - 1 mod 17 = -13-1 = -14 mod 17 = 3
     * So 2G = (6, 3)
     */
    chk_pt("2G = (6,3)", G2_add, ((point_t){6u, 3u}));
}

static void test_known_multiples(void)
{
    log_write(NONE, "\n-- Known scalar multiples kG --\n");

    /* All 18 non-identity multiples plus the identity */
    static const point_t expected[20] = {
        {0,0},   /* placeholder, 0G = O */
        {5,1},   {6,3},   {10,6},  {3,1},   {9,16},
        {16,13}, {0,6},   {13,7},  {7,6},   {7,11},
        {13,10}, {0,11},  {16,4},  {9,1},   {3,16},
        {10,11}, {6,14},  {5,16},  {0,0}    /* 19G = O */
    };

    int ok = 1;
    for (int k = 1; k <= (int)ORDER; k++) {
        point_t kG = point_mul((uint32_t)k, G);
        if (kG.x != expected[k].x || kG.y != expected[k].y) {
            ok = 0;
            log_write(NONE, "  FAIL  %dG: got (%d,%d) exp (%d,%d)\n",
                      k, (int)kG.x, (int)kG.y,
                      (int)expected[k].x, (int)expected[k].y);
        }
    }
    if (ok) chk_bool("all kG for k=1..19 match expected", ok);
    else    g_fail++;  /* already logged individual failures */
}

static void test_associativity(void)
{
    log_write(NONE, "\n-- Associativity: (aG+bG)+cG = aG+(bG+cG) --\n");
    /* Use a=3, b=5, c=7 -> all small, distinct */
    point_t aG = point_mul(3u, G);
    point_t bG = point_mul(5u, G);
    point_t cG = point_mul(7u, G);

    point_t lhs = point_add(point_add(aG, bG), cG);
    point_t rhs = point_add(aG, point_add(bG, cG));
    chk_pt("(3G+5G)+7G = 3G+(5G+7G)", lhs, rhs);

    /* Also verify: (a+b+c)G = 15G */
    point_t abcG = point_mul(3u+5u+7u, G);
    chk_pt("(3+5+7)G = (3G+5G)+7G", lhs, abcG);
}

static void test_commutativity(void)
{
    log_write(NONE, "\n-- Commutativity: aG+bG = bG+aG --\n");
    int ok = 1;
    for (int a = 1; a <= 5; a++) {
        for (int b = 1; b <= 5; b++) {
            point_t ab = point_add(point_mul((uint32_t)a, G), point_mul((uint32_t)b, G));
            point_t ba = point_add(point_mul((uint32_t)b, G), point_mul((uint32_t)a, G));
            if (ab.x != ba.x || ab.y != ba.y) { ok = 0; break; }
        }
    }
    chk_bool("aG+bG = bG+aG for a,b in [1,5]", ok);
}

static void test_scalar_add(void)
{
    log_write(NONE, "\n-- Scalar addition: aG + bG = (a+b)G --\n");
    int ok = 1;
    for (int a = 1; a <= 9; a++) {
        for (int b = 1; b <= 9; b++) {
            int s = (a + b) % (int)ORDER;
            if (s == 0) s = (int)ORDER;  /* treat 0 as identity */
            point_t ab = point_add(point_mul((uint32_t)a, G), point_mul((uint32_t)b, G));
            point_t sg = point_mul((uint32_t)s, G);
            if (s == (int)ORDER) sg = INFINITY_POINT;
            if (ab.x != sg.x || ab.y != sg.y) { ok = 0; break; }
        }
    }
    chk_bool("aG + bG = (a+b)G for a,b in [1,9]", ok);
}

static void test_ecdh(void)
{
    log_write(NONE, "\n-- ECDH: Alice(a)*G = Bob(b)*G shared secret --\n");
    /* Alice's private key: a=7, public: A_pub = 7G */
    /* Bob's private key:   b=11, public: B_pub = 11G */
    uint32_t alice_priv = 7u, bob_priv = 11u;
    point_t A_pub = point_mul(alice_priv, G);
    point_t B_pub = point_mul(bob_priv, G);

    /* Shared secret: alice computes alice_priv * B_pub = 7*11*G = 77*G */
    /* = 77 mod 19 = 77 - 4*19 = 77-76 = 1 -> 1G = G */
    point_t alice_shared = point_mul(alice_priv, B_pub);  /* a * (b*G) */
    point_t bob_shared   = point_mul(bob_priv,   A_pub);  /* b * (a*G) */

    chk_pt("alice_shared = bob_shared (ECDH)", alice_shared, bob_shared);
    chk_bool("shared secret on curve", point_on_curve(alice_shared));

    /* The shared secret is (a*b mod ORDER)*G = (77 mod 19)*G = 1*G = G = (5,1) */
    uint32_t ab_mod = (alice_priv * bob_priv) % ORDER;
    if (ab_mod == 0u) ab_mod = ORDER;
    point_t expected_shared = point_mul(ab_mod, G);
    chk_pt("shared = (a*b mod ORDER)*G", alice_shared, expected_shared);
}

/* -- main ------------------------------------------------------------------- */
int main(void)
{
    log_init("ecc-test.log");
    log_write(NONE, "=== ECC Test: y^2 = x^3 + 2x + 2 over F_%d, ord=%d ===\n",
              (int)P, (int)ORDER);

    test_field();
    test_point_on_curve();
    test_group_order();
    test_negation();
    test_doubling();
    test_known_multiples();
    test_associativity();
    test_commutativity();
    test_scalar_add();
    test_ecdh();

    log_write(NONE, "\n=== Result: %d PASS  %d FAIL ===\n", g_pass, g_fail);
    log_close();
    return g_fail;
}
