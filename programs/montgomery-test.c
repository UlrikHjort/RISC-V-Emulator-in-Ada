/* **************************************************************************
 *RISC-V Emulator - Montgomery modular multiplication and modular exponentiation
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

// montgomery-test.c -- Montgomery modular multiplication and modular exponentiation
//
// Montgomery form: a = a * R mod N, where R = 2^32.
// REDC(T): computes T * R^-1 mod N using only additions and shifts.
//
// Uses RV32M MULHU for the upper 32 bits of 32x32->64 products.
//
// Algorithm (Montgomery REDC):
//   Given T < R*N, compute T * R^-1 mod N:
//     m = ((T mod R) * N') mod R     where N' = -N^-1 mod R (Hensel lift)
//     u = (T + m*N) / R
//     if u >= N: return u - N else return u
//
// Montgomery multiply: mont_mul(a, b, N, N', R^2) = a*b*R^-1 mod N
//   mont_mul(mont(a), mont(b)) = a*b*R^-1 * R^-1 * R^2 = a*b mod N
//
// Modular exponentiation (left-to-right binary):
//   result = mont_exp(base, exp, N) using Montgomery form internally.
//
// Tests:
//   - MULHU spot-checks
//   - Hensel lift (compute N' for several moduli)
//   - REDC identity: REDC(a * R^2) = a mod N
//   - Montgomery multiply: a*b mod N for known values
//   - Modular exponentiation: Fermat's little theorem (a^(p-1) == 1 mod p)
//   - RSA-like: 3^e mod p, 3^d mod p round-trip
//   - Edge cases: 0, 1, N-1
//
// Build: cd programs && make run-montgomery-test
// By Ulrik Hørlyk Hjort 2026

#include <stdint.h>
#include "log.h"

static int g_pass = 0, g_fail = 0;

static void chku(const char *lbl, uint32_t got, uint32_t exp)
{
    if (got == exp) {
        log_write(NONE, "  PASS  %s\n", lbl);
        g_pass++;
    } else {
        log_write(NONE, "  FAIL  %s: got 0x%x  exp 0x%x\n", lbl,
                  (unsigned)got, (unsigned)exp);
        g_fail++;
    }
}

/* -- RV32M: upper 32 bits of 32x32 unsigned product ------------------------ */

static inline uint32_t mulhu(uint32_t a, uint32_t b)
{
    uint32_t hi;
    asm volatile("mulhu %0, %1, %2" : "=r"(hi) : "r"(a), "r"(b));
    return hi;
}


/* -- Hensel lifting: compute N' = -N^-1 mod 2^32 --------------------------- */
/* Uses the identity: if x is an inverse of N mod 2^k, then
 * x*(2 - N*x) is an inverse mod 2^(2k).  Start from x = N (odd N inverse
 * mod 2 is 1, but N itself satisfies N*N == N^2, so we use a known bootstrap).
 *
 * For odd N: N^-1 mod 2 = 1.  Five squarings reach 2^32. */
static uint32_t hensel_lift(uint32_t N)
{
    /* N must be odd */
    uint32_t x = 1u;               /* N*1 == 1 mod 2 */
    x *= 2u - N * x;               /* mod 2^2 */
    x *= 2u - N * x;               /* mod 2^4 */
    x *= 2u - N * x;               /* mod 2^8 */
    x *= 2u - N * x;               /* mod 2^16 */
    x *= 2u - N * x;               /* mod 2^32 */
    return (uint32_t)(0u - x);     /* N' = -N^-1 mod 2^32 */
}

/* -- Montgomery REDC -------------------------------------------------------- */
/* Inputs: T < R*N (R = 2^32), N < 2^31 (so N fits in 32 bits safely).
 * Output: T * R^-1 mod N.
 *
 * Step:
 *   m  = (T_lo * Np) mod R          [just T_lo * Np, take low 32 bits]
 *   u  = (T + m*N) >> 32            [T is 64-bit; we need (T + m*N) / R]
 *   if u >= N: u -= N               */
static uint32_t redc(uint64_t T, uint32_t N, uint32_t Np)
{
    uint32_t T_lo = (uint32_t)T;
    uint32_t m    = T_lo * Np;               /* mod 2^32 implicitly */
    uint64_t u64  = T + (uint64_t)m * N;
    uint32_t u    = (uint32_t)(u64 >> 32);
    if (u >= N) u -= N;
    return u;
}

/* -- Montgomery multiply --------------------------------------------------- */
/* mont_mul(a_mont, b_mont, N, Np) = a*b*R^-1 mod N
 * where a_mont = a*R mod N, b_mont = b*R mod N.
 * To get a*b mod N: first bring both operands to Montgomery form,
 * then multiply, then convert back via one more REDC.               */
static uint32_t mont_mul(uint32_t a, uint32_t b, uint32_t N, uint32_t Np)
{
    uint64_t T = (uint64_t)a * b;
    return redc(T, N, Np);
}

/* Reduce a 64-bit value mod a 32-bit N without any division.
 * Binary long division: O(64) iterations.                            */
static uint32_t mod64_32(uint64_t a, uint32_t N)
{
    uint64_t r = 0;
    for (int i = 63; i >= 0; i--) {
        r = (r << 1) | ((a >> i) & 1ULL);
        if (r >= (uint64_t)N) r -= (uint64_t)N;
    }
    return (uint32_t)r;
}

/* R mod N = 2^32 mod N via 32 doublings (no division).              */
static uint32_t r_mod_n(uint32_t N)
{
    uint64_t r = 1u;
    for (int i = 0; i < 32; i++) {
        r <<= 1;
        if (r >= (uint64_t)N) r -= (uint64_t)N;
    }
    return (uint32_t)r;
}

/* R^2 mod N = (R mod N)^2 mod N                                      */
static uint32_t r2_mod_n(uint32_t N)
{
    uint32_t r = r_mod_n(N);
    return mod64_32((uint64_t)r * r, N);
}

/* Convert a to Montgomery form: a_mont = a*R mod N = REDC(a * R^2) */
static uint32_t to_mont(uint32_t a, uint32_t N, uint32_t Np, uint32_t R2)
{
    return mont_mul(a, R2, N, Np);
}

/* Convert from Montgomery form: a = REDC(a_mont) */
static uint32_t from_mont(uint32_t a_mont, uint32_t N, uint32_t Np)
{
    return redc((uint64_t)a_mont, N, Np);
}

/* -- Modular exponentiation via Montgomery form ----------------------------- */
/* Computes base^exp mod N using left-to-right binary method.         */
static uint32_t mont_exp(uint32_t base, uint32_t exp, uint32_t N)
{
    if (N == 1u) return 0u;
    uint32_t Np = hensel_lift(N);
    uint32_t R2 = r2_mod_n(N);

    /* result = 1 in Montgomery form = R mod N */
    uint32_t result = to_mont(1u, N, Np, R2);
    uint32_t b      = to_mont(base % N, N, Np, R2);

    while (exp) {
        if (exp & 1u)
            result = mont_mul(result, b, N, Np);
        b   = mont_mul(b, b, N, Np);
        exp >>= 1;
    }
    return from_mont(result, N, Np);
}

/* -- Tests ------------------------------------------------------------------ */

static void test_mulhu(void)
{
    log_write(NONE, "\n-- MULHU (upper 32 bits of 32x32) --\n");
    /* 0xFFFFFFFF * 0xFFFFFFFF = 0xFFFFFFFE_00000001 */
    chku("mulhu(0xFFFFFFFF,0xFFFFFFFF)=0xFFFFFFFE",
         mulhu(0xFFFFFFFFu, 0xFFFFFFFFu), 0xFFFFFFFEu);
    chku("mulhu(0x00010000,0x00010000)=0x00000001",
         mulhu(0x00010000u, 0x00010000u), 0x00000001u);
    chku("mulhu(0x80000000,0x00000002)=0x00000001",
         mulhu(0x80000000u, 0x00000002u), 0x00000001u);
    chku("mulhu(0x12345678,0x00000001)=0",
         mulhu(0x12345678u, 0x00000001u), 0u);
}

static void test_hensel(void)
{
    log_write(NONE, "\n-- Hensel lift: N * N' == -1 mod 2^32 --\n");
    /* Verify N * Np = -1 mod 2^32 == 0xFFFFFFFF... actually:
     * N * Np == -1 mod R  ->  N * Np + 1 == 0 mod R  ->  (N*Np+1) = 0 in uint32 */
    uint32_t primes[] = {3u, 7u, 13u, 17u, 97u, 65537u, 998244353u};
    const char *names[] = {"N=3","N=7","N=13","N=17","N=97","N=65537","N=998244353"};
    for (int i = 0; i < 7; i++) {
        uint32_t N  = primes[i];
        uint32_t Np = hensel_lift(N);
        uint32_t check = N * Np + 1u;     /* should be 0 mod 2^32 */
        chku(names[i], check, 0u);
    }
}

static void test_redc_identity(void)
{
    log_write(NONE, "\n-- REDC identity: REDC(a * R^2) / R = a mod N --\n");
    /* to_mont(a) = a*R mod N; from_mont(to_mont(a)) = a mod N */
    uint32_t N  = 97u;
    uint32_t Np = hensel_lift(N);
    uint32_t R2 = r2_mod_n(N);

    uint32_t vals[] = {0u, 1u, 2u, 48u, 96u};
    const char *names[] = {"a=0","a=1","a=2","a=48","a=96"};
    for (int i = 0; i < 5; i++) {
        uint32_t a = vals[i];
        uint32_t m = to_mont(a, N, Np, R2);
        uint32_t r = from_mont(m, N, Np);
        chku(names[i], r, a);
    }
}

static void test_mont_mul(void)
{
    log_write(NONE, "\n-- Montgomery multiply: a*b mod N --\n");
    /* Use N=97 (prime). */
    uint32_t N  = 97u;
    uint32_t Np = hensel_lift(N);
    uint32_t R2 = r2_mod_n(N);

    /* 2 * 3 mod 97 = 6 */
    uint32_t a = to_mont(2u,  N, Np, R2);
    uint32_t b = to_mont(3u,  N, Np, R2);
    uint32_t c = from_mont(mont_mul(a, b, N, Np), N, Np);
    chku("2*3 mod 97 = 6", c, 6u);

    /* 50 * 50 mod 97 = 2500 mod 97. 2500 = 25*97 + 75 -> 75 */
    a = to_mont(50u, N, Np, R2);
    b = to_mont(50u, N, Np, R2);
    c = from_mont(mont_mul(a, b, N, Np), N, Np);
    chku("50*50 mod 97 = 75", c, 75u);

    /* 96 * 96 mod 97 = (-1)*(-1) = 1 */
    a = to_mont(96u, N, Np, R2);
    b = to_mont(96u, N, Np, R2);
    c = from_mont(mont_mul(a, b, N, Np), N, Np);
    chku("96*96 mod 97 = 1", c, 1u);

    /* 0 * anything = 0 */
    a = to_mont(0u,  N, Np, R2);
    b = to_mont(42u, N, Np, R2);
    c = from_mont(mont_mul(a, b, N, Np), N, Np);
    chku("0*42 mod 97 = 0", c, 0u);

    /* Commutativity */
    a = to_mont(17u, N, Np, R2);
    b = to_mont(23u, N, Np, R2);
    uint32_t ab = from_mont(mont_mul(a, b, N, Np), N, Np);
    uint32_t ba = from_mont(mont_mul(b, a, N, Np), N, Np);
    chku("17*23 mod 97 == 23*17 mod 97", ab, ba);
    chku("17*23 mod 97 = 391 mod 97 = 3", ab, 3u); /* 391 = 4*97+3 */
}

static void test_fermat(void)
{
    log_write(NONE, "\n-- Fermat's little theorem: a^(p-1) == 1 mod p --\n");
    /* For prime p and gcd(a,p)=1: a^(p-1) == 1 mod p */
    uint32_t primes[] = {7u, 13u, 17u, 97u, 257u, 65537u};
    uint32_t bases[]  = {3u,  5u,  7u,  5u,   3u,     7u};
    const char *names[] = {"3^6 mod 7","5^12 mod 13","7^16 mod 17",
                            "5^96 mod 97","3^256 mod 257","7^65536 mod 65537"};
    for (int i = 0; i < 6; i++) {
        uint32_t p = primes[i];
        uint32_t a = bases[i];
        uint32_t r = mont_exp(a, p - 1u, p);
        chku(names[i], r, 1u);
    }
}

static void test_modexp_known(void)
{
    log_write(NONE, "\n-- Known modular exponentiation results --\n");
    /* 2^10 mod 997 = 1024 mod 997 = 27  (997 is prime, Montgomery-safe) */
    chku("2^10 mod 997 = 27",    mont_exp(2u, 10u, 997u), 27u);
    /* 3^20 mod 97: by Fermat, 3^96 == 1; 3^20 mod 97 = ? */
    /* 3^1=3, 3^2=9, 3^4=81, 3^8=81^2 mod 97=6561 mod 97
     * 6561 / 97 = 67.6... -> 67*97=6499 -> 6561-6499=62
     * 3^8 mod 97 = 62
     * 3^16 mod 97 = 62^2 mod 97 = 3844 mod 97
     * 3844 / 97 = 39.6... -> 39*97=3783 -> 3844-3783=61
     * 3^16 mod 97 = 61
     * 3^20 = 3^16 * 3^4 = 61 * 81 mod 97
     * 61*81 = 4941; 4941/97=50.9... -> 50*97=4850 -> 4941-4850=91 */
    chku("3^20 mod 97 = 91",     mont_exp(3u, 20u, 97u), 91u);
    /* 7^0 = 1 */
    chku("7^0 mod 13 = 1",       mont_exp(7u, 0u, 13u), 1u);
    /* 7^1 = 7 */
    chku("7^1 mod 13 = 7",       mont_exp(7u, 1u, 13u), 7u);
    /* 5^3 mod 13 = 125 mod 13 = 8 */
    chku("5^3 mod 13 = 8",       mont_exp(5u, 3u, 13u), 8u);
    /* 2^32 mod 641: Fermat factor. 641 | (2^32 + 1) -> 2^32 == -1 mod 641 */
    /* 2^32 mod 641 = 641 - 1 = 640 */
    chku("2^32 mod 641 = 640",   mont_exp(2u, 32u, 641u), 640u);
}

static void test_rsa_roundtrip(void)
{
    log_write(NONE, "\n-- RSA-like encrypt/decrypt round-trip --\n");
    /* Small RSA: p=13, q=17, n=221, phi=192.
     * e=5 (gcd(5,192)=1); d=77 (5*77=385=2*192+1 == 1 mod 192)
     * Encrypt: c = m^e mod n;  Decrypt: m = c^d mod n            */
    uint32_t n = 221u;   /* p*q = 13*17 */
    uint32_t e = 5u;
    uint32_t d = 77u;    /* e*d == 1 mod phi(n)=192: 5*77=385=2*192+1 */
    uint32_t msgs[] = {1u, 2u, 10u, 99u, 200u};
    const char *names[] = {"RSA m=1","RSA m=2","RSA m=10","RSA m=99","RSA m=200"};
    for (int i = 0; i < 5; i++) {
        uint32_t m = msgs[i];
        uint32_t c = mont_exp(m, e, n);   /* encrypt */
        uint32_t r = mont_exp(c, d, n);   /* decrypt */
        chku(names[i], r, m);
    }
}

/* -- main ------------------------------------------------------------------- */
int main(void)
{
    log_init("montgomery-test.log");
    log_write(NONE, "=== Montgomery Multiplication Test ===\n");

    test_mulhu();
    test_hensel();
    test_redc_identity();
    test_mont_mul();
    test_fermat();
    test_modexp_known();
    test_rsa_roundtrip();

    log_write(NONE, "\n=== Result: %d PASS  %d FAIL ===\n", g_pass, g_fail);
    log_close();
    return g_fail;
}
