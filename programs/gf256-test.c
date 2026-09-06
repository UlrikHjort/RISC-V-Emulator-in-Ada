/* **************************************************************************
 *         RISC-V Emulator - GF(2^8) finite field arithmetic tests
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

// gf256-test.c -- GF(2^8) finite field arithmetic tests.
//
// The AES field GF(2^8) with irreducible polynomial:
//   p(x) = x^8 + x^4 + x^3 + x + 1  (0x11B)
//
// Implements and tests:
//   gf_add  -- XOR (no carry in characteristic-2 field)
//   gf_mul  -- classical shift-and-XOR method (reference)
//   gf_mul_clmul -- CLMUL + polynomial reduction (fast hardware path)
//   gf_inv  -- multiplicative inverse (extended Euclidean)
//   xtime   -- multiply by x (for MixColumns)
//   AES MixColumns column operation
//   GF(2^8) exponentiation and discrete log properties
//
// Build: cd programs && make run-gf256-test
// By Ulrik Hørlyk Hjort 2026

#include <stdint.h>
#include <stddef.h>
#include "log.h"

void putchar(char c);
static void uart_puts(const char *s) {
    while (*s) { if (*s == '\n') putchar('\r'); putchar(*s++); }
}

static int g_pass = 0, g_fail = 0;

static void chk8(const char *lbl, uint8_t got, uint8_t exp) {
    if (got == exp) {
        log_write(NONE, "  PASS  %s\n", lbl);
        g_pass++;
    } else {
        log_write(NONE, "  FAIL  %s: got 0x%x  exp 0x%x\n", lbl, (unsigned)got, (unsigned)exp);
        g_fail++;
    }
}

/* -- GF(2^8) primitives ---------------------------------------------------- */

/* Addition = XOR (no carry in GF(2)) */
static inline uint8_t gf_add(uint8_t a, uint8_t b) {
    return a ^ b;
}

/* Multiply by x = shift left, reduce if bit 7 was set.
 * Reduction: x^8 = x^4 + x^3 + x + 1 -> XOR 0x1B */
static inline uint8_t xtime(uint8_t a) {
    return (uint8_t)(((a << 1) ^ (uint8_t)(((a >> 7) & 1) * 0x1Bu)));
}

/* Reference multiply: shift-and-XOR (no hardware intrinsics) */
static uint8_t gf_mul(uint8_t a, uint8_t b) {
    uint8_t p = 0;
    for (int i = 0; i < 8; i++) {
        if (b & 1)
            p ^= a;
        a = xtime(a);
        b >>= 1;
    }
    return p;
}

/* CLMUL-based multiply (hardware carry-less multiply + reduction)
 * For 8-bit inputs the carry-less product fits in 15 bits.
 * Reduce by processing bits 14 down to 8, XORing 0x11B shifted appropriately. */
static uint8_t gf_mul_clmul(uint8_t a, uint8_t b) {
    uint32_t p;
    asm volatile("clmul %0, %1, %2"
                 : "=r"(p) : "r"((uint32_t)a), "r"((uint32_t)b));
    /* p has degree <= 14 (two degree-7 polys). Reduce mod 0x11B. */
    /* Process from bit 14 down to bit 8 */
    if (p & (1u << 14)) p ^= (0x11Bu << 6);
    if (p & (1u << 13)) p ^= (0x11Bu << 5);
    if (p & (1u << 12)) p ^= (0x11Bu << 4);
    if (p & (1u << 11)) p ^= (0x11Bu << 3);
    if (p & (1u << 10)) p ^= (0x11Bu << 2);
    if (p & (1u <<  9)) p ^= (0x11Bu << 1);
    if (p & (1u <<  8)) p ^= (0x11Bu << 0);
    return (uint8_t)(p & 0xFF);
}

/* Inverse via square chain: a^254 = a^128*a^64*a^32*a^16*a^8*a^4*a^2 */
static uint8_t gf_inv2(uint8_t a) {
    if (a == 0) return 0;
    uint8_t x2  = gf_mul(a, a);         /* a^2   */
    uint8_t x4  = gf_mul(x2, x2);       /* a^4   */
    uint8_t x8  = gf_mul(x4, x4);       /* a^8   */
    uint8_t x16 = gf_mul(x8, x8);       /* a^16  */
    uint8_t x32 = gf_mul(x16, x16);     /* a^32  */
    uint8_t x64 = gf_mul(x32, x32);     /* a^64  */
    uint8_t x128 = gf_mul(x64, x64);    /* a^128 */
    /* a^254 = a^128 * a^64 * a^32 * a^16 * a^8 * a^4 * a^2 */
    return gf_mul(x128, gf_mul(x64, gf_mul(x32, gf_mul(x16, gf_mul(x8, gf_mul(x4, x2))))));
}

/* -- Tests ----------------------------------------------------------------- */

static void test_field_basics(void) {
    log_write(NONE, "\n=== GF(2^8) Basic Field Operations ===\n");

    /* Addition = XOR */
    chk8("add(0xFF,0xFF)=0",      gf_add(0xFF, 0xFF), 0);
    chk8("add(0x53,0xCA)=0x99",   gf_add(0x53, 0xCA), 0x99);
    chk8("add(0,x)=x",            gf_add(0, 0xAB), 0xAB);

    /* xtime: multiply by x (shift + conditional XOR 0x1B) */
    chk8("xtime(0x01)=0x02",      xtime(0x01), 0x02);
    chk8("xtime(0x02)=0x04",      xtime(0x02), 0x04);
    chk8("xtime(0x80)=0x1B",      xtime(0x80), 0x1B);  /* x^8 mod p = 0x1B */
    chk8("xtime(0xFF)=0xE5",      xtime(0xFF), 0xE5);

    /* Multiply */
    chk8("gf_mul(0,x)=0",         gf_mul(0x00, 0xAB), 0);
    chk8("gf_mul(1,x)=x",         gf_mul(0x01, 0xAB), 0xAB);
    chk8("gf_mul(2,2)=4",         gf_mul(0x02, 0x02), 0x04);
    chk8("gf_mul(3,3)=5",         gf_mul(0x03, 0x03), 0x05);
    chk8("gf_mul(2,0x80)=0x1B",   gf_mul(0x02, 0x80), 0x1B);

    /* Key AES test vector from FIPS 197:
     * 0x57 * 0x13 = 0xFE */
    chk8("gf_mul(0x57,0x13)=0xFE",gf_mul(0x57, 0x13), 0xFE);

    /* Commutativity */
    chk8("gf_mul commutative",    gf_mul(0x57, 0x83), gf_mul(0x83, 0x57));

    /* Distributivity: a*(b^c) = a*b ^ a*c */
    chk8("gf_mul distributive",   gf_mul(0x57, gf_add(0x13, 0x83)),
                                  gf_add(gf_mul(0x57, 0x13), gf_mul(0x57, 0x83)));
}

static void test_clmul_mul(void) {
    log_write(NONE, "\n=== GF(2^8) via CLMUL vs Reference ===\n");

    /* Compare CLMUL-based multiply against reference for key values */
    struct { uint8_t a, b, exp; } cases[] = {
        {0x00, 0xFF, 0x00},
        {0x01, 0xAB, 0xAB},
        {0x02, 0x02, 0x04},
        {0x02, 0x80, 0x1B},
        {0x03, 0x03, 0x05},
        {0x57, 0x13, 0xFE},
        {0xFF, 0xFF, 0x13},   /* 0xFF * 0xFF in AES field */
        {0x53, 0xCA, 0x01},   /* 0x53 and 0xCA are multiplicative inverses */
    };

    for (size_t i = 0; i < sizeof cases / sizeof cases[0]; i++) {
        uint8_t ref = gf_mul(cases[i].a, cases[i].b);
        uint8_t hw  = gf_mul_clmul(cases[i].a, cases[i].b);
        if (hw == cases[i].exp) {
            log_write(NONE, "  PASS  clmul gf_mul(0x%x,0x%x)=0x%x\n",
                      (unsigned)cases[i].a, (unsigned)cases[i].b, (unsigned)cases[i].exp);
            g_pass++;
        } else {
            log_write(NONE, "  FAIL  clmul gf_mul(0x%x,0x%x): got 0x%x exp 0x%x (ref=0x%x)\n",
                      (unsigned)cases[i].a, (unsigned)cases[i].b,
                      (unsigned)hw, (unsigned)cases[i].exp, (unsigned)ref);
            g_fail++;
        }
    }

    /* Verify ref and clmul agree for all values 0..31 x 0..31 */
    int mismatches = 0;
    for (int a = 0; a < 32; a++) {
        for (int b = 0; b < 32; b++) {
            if (gf_mul((uint8_t)a, (uint8_t)b) != gf_mul_clmul((uint8_t)a, (uint8_t)b))
                mismatches++;
        }
    }
    if (mismatches == 0) {
        log_write(NONE, "  PASS  clmul agrees with ref for all a,b in [0,31]\n");
        g_pass++;
    } else {
        log_write(NONE, "  FAIL  clmul mismatches: %d\n", mismatches);
        g_fail++;
    }
}

static void test_field_axioms(void) {
    log_write(NONE, "\n=== GF(2^8) Field Axioms ===\n");

    /* 1: Additive identity */
    chk8("add identity: 0+a=a",   gf_add(0, 0x57), 0x57);

    /* 2: Additive inverse (self-inverse in char-2: a+a=0) */
    chk8("add inverse: a+a=0",    gf_add(0x57, 0x57), 0);

    /* 3: Multiplicative identity */
    chk8("mul identity: 1*a=a",   gf_mul(1, 0x57), 0x57);

    /* 4: Multiplicative inverse: a * a^-1 = 1 */
    uint8_t a = 0x53;
    uint8_t inv_a = gf_inv2(a);
    chk8("mul inverse: a*a^-1=1", gf_mul(a, inv_a), 1);

    /* 5: No zero divisors: a*b=0 only if a=0 or b=0 */
    int zero_divs = 0;
    for (int i = 1; i < 256; i++)
        for (int j = 1; j < 256; j++)
            if (gf_mul((uint8_t)i, (uint8_t)j) == 0)
                zero_divs++;
    if (zero_divs == 0) {
        log_write(NONE, "  PASS  no zero divisors in GF(2^8)\n");
        g_pass++;
    } else {
        log_write(NONE, "  FAIL  found %d zero divisors\n", zero_divs);
        g_fail++;
    }

    /* 6: Order: a^255 = 1 for all non-zero a (Fermat's theorem in GF(2^8)) */
    /* Test for a few values */
    uint8_t test_vals[] = {0x02, 0x03, 0x53, 0xAB, 0xFF};
    int order_ok = 1;
    for (size_t i = 0; i < sizeof test_vals; i++) {
        uint8_t x = test_vals[i];
        uint8_t acc = 1;
        for (int k = 0; k < 255; k++)
            acc = gf_mul(acc, x);
        if (acc != 1) { order_ok = 0; break; }
    }
    if (order_ok) {
        log_write(NONE, "  PASS  a^255=1 for all tested non-zero a\n");
        g_pass++;
    } else {
        log_write(NONE, "  FAIL  Fermat theorem a^255=1 violated\n");
        g_fail++;
    }
}

static void test_mixcol_xtime(void) {
    log_write(NONE, "\n=== AES MixColumns helper (xtime chain) ===\n");

    /* MixColumns uses: b = xtime(a), then:
     * output[0] = 2*s0 ^ 3*s1 ^ s2 ^ s3
     *           = b ^ (b^s1) ^ s1 ^ s2 ^ s3
     * (where 3 = 2^1, multiplication by 3 = xtime(a) ^ a)
     *
     * Test the column [0x87, 0x6E, 0x46, 0xA6] -> [0x47, 0x37, 0x94, 0xED]
     * From FIPS 197 Appendix B, after SubBytes but before MixColumns:
     * Actually let's test with a known pair from the spec.
     */
    /* 2 * 0x87 = xtime(0x87) */
    chk8("2*0x87=xtime(0x87)",    xtime(0x87), 0x15);
    /* 3 * 0x87 = xtime(0x87) ^ 0x87 */
    chk8("3*0x87=xtime^0x87",     (uint8_t)(xtime(0x87) ^ 0x87), 0x92);
    chk8("2*0x6E",                 xtime(0x6E), 0xDC);
    chk8("3*0x6E",                 (uint8_t)(xtime(0x6E) ^ 0x6E), 0xB2);

    /* MixColumns on column [0x87, 0x6E, 0x46, 0xA6]:
     * out[0] = 2*0x87 ^ 3*0x6E ^ 0x46 ^ 0xA6
     *        = 0x15 ^ 0xB2 ^ 0x46 ^ 0xA6 = 0x47
     */
    uint8_t s0=0x87, s1=0x6E, s2=0x46, s3=0xA6;
    uint8_t out0 = (uint8_t)(xtime(s0) ^ (xtime(s1)^s1) ^ s2 ^ s3);
    uint8_t out1 = (uint8_t)(s0 ^ xtime(s1) ^ (xtime(s2)^s2) ^ s3);
    uint8_t out2 = (uint8_t)(s0 ^ s1 ^ xtime(s2) ^ (xtime(s3)^s3));
    uint8_t out3 = (uint8_t)((xtime(s0)^s0) ^ s1 ^ s2 ^ xtime(s3));
    chk8("MixCol out[0]=0x47",    out0, 0x47);
    chk8("MixCol out[1]=0x37",    out1, 0x37);
    chk8("MixCol out[2]=0x94",    out2, 0x94);
    chk8("MixCol out[3]=0xED",    out3, 0xED);
}

static void test_inverse(void) {
    log_write(NONE, "\n=== GF(2^8) Multiplicative Inverse ===\n");

    /* Known inverses (from AES S-box computation): */
    /* a * inv(a) = 1 for several values */
    struct { uint8_t a, inv; } pairs[] = {
        {0x01, 0x01},   /* 1 is its own inverse */
        {0x02, 0x8D},   /* from AES tables */
        {0x03, 0xF6},
        {0x53, 0xCA},   /* 0x53 and 0xCA are inverses */
        {0xFF, 0x1C},
    };

    for (size_t i = 0; i < sizeof pairs / sizeof pairs[0]; i++) {
        uint8_t computed_inv = gf_inv2(pairs[i].a);
        uint8_t product = gf_mul(pairs[i].a, computed_inv);
        if (product == 1 && computed_inv == pairs[i].inv) {
            log_write(NONE, "  PASS  inv(0x%x)=0x%x, product=1\n",
                      (unsigned)pairs[i].a, (unsigned)computed_inv);
            g_pass++;
        } else {
            log_write(NONE, "  FAIL  inv(0x%x): got 0x%x exp 0x%x (product=0x%x)\n",
                      (unsigned)pairs[i].a, (unsigned)computed_inv,
                      (unsigned)pairs[i].inv, (unsigned)product);
            g_fail++;
        }
    }

    /* Verify inv(inv(a)) = a for several values */
    uint8_t testv[] = {0x02, 0x0F, 0x57, 0xCA, 0xFE};
    for (size_t i = 0; i < sizeof testv; i++) {
        if (gf_inv2(gf_inv2(testv[i])) == testv[i]) {
            log_write(NONE, "  PASS  inv(inv(0x%x))=0x%x\n", (unsigned)testv[i], (unsigned)testv[i]);
            g_pass++;
        } else {
            log_write(NONE, "  FAIL  inv(inv(0x%x)) != 0x%x\n", (unsigned)testv[i], (unsigned)testv[i]);
            g_fail++;
        }
    }
}

/* -- Main ------------------------------------------------------------------- */

int main(void) {
    uart_puts("=== GF(2^8) Arithmetic Test ===\n");
    if (log_init("gf256-test.log") != 0) {
        uart_puts("ERROR: log_init failed\n"); return 1;
    }
    log_write(NONE, "=== GF(2^8) Finite Field Arithmetic Test ===\n");

    test_field_basics();
    test_clmul_mul();
    test_field_axioms();
    test_mixcol_xtime();
    test_inverse();

    log_write(NONE, "\n=== Summary ===\n");
    log_write(NONE, "  PASS: %d\n", g_pass);
    log_write(NONE, "  FAIL: %d\n", g_fail);
    log_write(NONE, "  %s\n", g_fail == 0 ? "ALL TESTS PASSED" : "SOME TESTS FAILED");
    log_close();

    uart_puts(g_fail == 0 ? "ALL PASSED\n" : "SOME FAILED\n");
    return g_fail;
}
