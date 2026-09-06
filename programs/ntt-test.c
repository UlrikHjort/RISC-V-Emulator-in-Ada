/* **************************************************************************
 *          RISC-V Emulator - Number Theoretic Transform over Z_p
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

// ntt-test.c -- Number Theoretic Transform over Z_p
//
// p = 12289 = 3 * 2^12 + 1  (NTT-friendly prime; supports N up to 4096)
// Primitive root: g = 11
//
// Key property: max product a*b < p^2 = 12288^2 = 150,994,944 < 2^32.
// So all arithmetic stays in uint32_t -- no 64-bit ops needed.
// Modular division (`%`) uses the hardware `remu` instruction (M extension).
//
// Algorithm: Cooley-Tukey DIT (Decimation-in-Time) iterative NTT, N=8.
//   Forward: X[k] = sum_{n=0}^{N-1} x[n] * omega^(n*k) mod p
//   Inverse: x[n] = (1/N) * sum_{k=0}^{N-1} X[k] * omega^(-n*k) mod p
//
// Tests:
//   - Fermat's little theorem: g^(p-1) = 1
//   - Root of unity: omega^8 = 1, omega^k != 1 for 0 < k < 8
//   - NTT of impulse: all bins = 1
//   - NTT of constant (DC): X[0]=N, X[k!=0]=0
//   - NTT of Nyquist (alternating): X[N/2]=N, others 0
//   - INTT(NTT(x)) = x (roundtrip for several inputs)
//   - Cyclic polynomial multiplication via NTT
//   - Linearity: NTT(a+b) = NTT(a) + NTT(b)
//   - Plancherel: sum X[k]*X[N-k mod N] = N * sum x[n]^2 (mod p)
//
// Build: cd programs && make run-ntt-test
// By Ulrik Hørlyk Hjort 2026

#include <stdint.h>
#include "log.h"

#define P   12289u      /* prime */
#define G   11u         /* primitive root mod P */
#define N   8           /* transform size */

static int g_pass = 0, g_fail = 0;

/* -- modular arithmetic (all results in [0, P) ----------------------------- */

static uint32_t addmod(uint32_t a, uint32_t b)
{
    a += b;
    if (a >= P) a -= P;
    return a;
}

static uint32_t submod(uint32_t a, uint32_t b)
{
    return addmod(a, P - b % P);
}

static uint32_t mulmod(uint32_t a, uint32_t b)
{
    /* a, b < P: a*b < 12288^2 = 150,994,944 < 2^32 -- no overflow */
    return (a * b) % P;
}

/* Fast modular exponentiation: base^exp mod P */
static uint32_t pow_mod(uint32_t base, uint32_t exp)
{
    uint32_t result = 1u;
    base %= P;
    while (exp > 0u) {
        if (exp & 1u) result = mulmod(result, base);
        base = mulmod(base, base);
        exp >>= 1;
    }
    return result;
}

/* Modular inverse: a^(-1) mod P via Fermat's little theorem (P is prime) */
static uint32_t modinv(uint32_t a)
{
    return pow_mod(a, P - 2u);
}

/* -- NTT core --------------------------------------------------------------- */

/* In-place NTT/INTT of a[0..n-1] over Z_P.
 * omega: primitive n-th root of unity for forward; its inverse for INTT.
 * Caller passes the correct omega. */
static void ntt_impl(uint32_t *a, int n, uint32_t omega)
{
    /* Bit-reversal permutation (iterative) */
    int j = 0;
    for (int i = 1; i < n; i++) {
        int bit = n >> 1;
        for (; j & bit; bit >>= 1) j ^= bit;
        j ^= bit;
        if (i < j) { uint32_t t = a[i]; a[i] = a[j]; a[j] = t; }
    }

    /* Butterfly stages */
    for (int len = 2; len <= n; len <<= 1) {
        /* primitive (len)-th root = omega^(n/len) */
        uint32_t w_len = pow_mod(omega, (uint32_t)n / (uint32_t)len);
        for (int i = 0; i < n; i += len) {
            uint32_t w = 1u;
            for (int k = 0; k < len / 2; k++) {
                uint32_t u = a[i + k];
                uint32_t v = mulmod(a[i + k + len / 2], w);
                a[i + k]            = addmod(u, v);
                a[i + k + len / 2]  = submod(u, v);
                w = mulmod(w, w_len);
            }
        }
    }
}

static void ntt_forward(uint32_t a[N])
{
    /* omega_N = G^((P-1)/N) */
    uint32_t omega = pow_mod(G, (P - 1u) / (uint32_t)N);
    ntt_impl(a, N, omega);
}

static void ntt_inverse(uint32_t a[N])
{
    /* omega_inv = G^((P-1) - (P-1)/N) = omega^(P-2) */
    uint32_t omega     = pow_mod(G, (P - 1u) / (uint32_t)N);
    uint32_t omega_inv = modinv(omega);
    ntt_impl(a, N, omega_inv);
    /* Normalize by N^(-1) mod P */
    uint32_t n_inv = modinv((uint32_t)N);
    for (int i = 0; i < N; i++) a[i] = mulmod(a[i], n_inv);
}

/* -- helpers ---------------------------------------------------------------- */

static void chk(const char *lbl, uint32_t got, uint32_t exp)
{
    if (got == exp) {
        log_write(NONE, "  PASS  %s\n", lbl);
        g_pass++;
    } else {
        log_write(NONE, "  FAIL  %s: got %d  exp %d\n", lbl, (int)got, (int)exp);
        g_fail++;
    }
}

static void chk_bool(const char *lbl, int ok)
{
    if (ok) { log_write(NONE, "  PASS  %s\n", lbl); g_pass++; }
    else    { log_write(NONE, "  FAIL  %s\n", lbl); g_fail++; }
}

/* Copy array */
static void copy8(uint32_t dst[N], const uint32_t src[N])
{
    for (int i = 0; i < N; i++) dst[i] = src[i];
}

/* Pointwise multiply two arrays mod P */
static void pointwise_mul(const uint32_t a[N], const uint32_t b[N], uint32_t c[N])
{
    for (int i = 0; i < N; i++) c[i] = mulmod(a[i], b[i]);
}

/* -- tests ------------------------------------------------------------------ */

static void test_fermat(void)
{
    log_write(NONE, "\n-- Fermat's little theorem: G^(P-1) = 1 --\n");
    chk("G^(P-1) = 1", pow_mod(G, P - 1u), 1u);
    chk("2^(P-1) = 1", pow_mod(2u, P - 1u), 1u);
    chk("3^(P-1) = 1", pow_mod(3u, P - 1u), 1u);
    chk("pow_mod(1,anything)=1", pow_mod(1u, 99u), 1u);
    chk("pow_mod(x,0)=1",       pow_mod(42u, 0u), 1u);
}

static void test_root_of_unity(void)
{
    log_write(NONE, "\n-- Root of unity: omega^N = 1, omega^k != 1 for 0<k<N --\n");
    uint32_t omega = pow_mod(G, (P - 1u) / (uint32_t)N);

    chk("omega^8 = 1", pow_mod(omega, (uint32_t)N), 1u);
    chk("omega^4 = P-1 (= -1)", pow_mod(omega, 4u), P - 1u);

    /* omega^k != 1 for k = 1..7 */
    int all_ne = 1;
    for (int k = 1; k < N; k++) {
        if (pow_mod(omega, (uint32_t)k) == 1u) { all_ne = 0; break; }
    }
    chk_bool("omega^k != 1 for 0<k<N", all_ne);

    /* Check inverse: omega * omega_inv = 1 */
    uint32_t omega_inv = modinv(omega);
    chk("omega * omega_inv = 1", mulmod(omega, omega_inv), 1u);
}

static void test_impulse(void)
{
    log_write(NONE, "\n-- NTT of impulse: all bins = 1 --\n");
    uint32_t x[N] = {1, 0, 0, 0, 0, 0, 0, 0};
    ntt_forward(x);
    int ok = 1;
    for (int k = 0; k < N; k++)
        if (x[k] != 1u) ok = 0;
    chk_bool("NTT([1,0,...,0]): all bins = 1", ok);
}

static void test_dc(void)
{
    log_write(NONE, "\n-- NTT of DC: X[0]=N, X[k!=0]=0 --\n");
    uint32_t x[N];
    for (int i = 0; i < N; i++) x[i] = 1u;
    ntt_forward(x);
    chk("DC X[0] = N", x[0], (uint32_t)N);
    int rest_ok = 1;
    for (int k = 1; k < N; k++)
        if (x[k] != 0u) rest_ok = 0;
    chk_bool("DC X[k!=0] = 0", rest_ok);
}

static void test_nyquist(void)
{
    log_write(NONE, "\n-- NTT of Nyquist (alternating +1/-1): X[N/2]=N, others 0 --\n");
    uint32_t x[N];
    for (int i = 0; i < N; i++)
        x[i] = (i & 1) ? P - 1u : 1u;  /* +1 or -1 mod P */
    ntt_forward(x);
    chk("Nyquist X[N/2] = N", x[N / 2], (uint32_t)N);
    int rest_ok = 1;
    for (int k = 0; k < N; k++) {
        if (k == N / 2) continue;
        if (x[k] != 0u) rest_ok = 0;
    }
    chk_bool("Nyquist X[k!=N/2] = 0", rest_ok);
}

static void test_roundtrip(void)
{
    log_write(NONE, "\n-- INTT(NTT(x)) = x (roundtrip) --\n");

    /* Test 1: arbitrary data */
    uint32_t orig[N] = {1, 5, 3, 9, 2, 7, 4, 8};
    uint32_t x[N];
    copy8(x, orig);
    ntt_forward(x);
    ntt_inverse(x);
    int ok1 = 1;
    for (int i = 0; i < N; i++) if (x[i] != orig[i]) ok1 = 0;
    chk_bool("roundtrip [1,5,3,9,2,7,4,8]", ok1);

    /* Test 2: all-ones */
    uint32_t ones[N] = {1, 1, 1, 1, 1, 1, 1, 1};
    copy8(x, ones);
    ntt_forward(x);
    ntt_inverse(x);
    int ok2 = 1;
    for (int i = 0; i < N; i++) if (x[i] != 1u) ok2 = 0;
    chk_bool("roundtrip [1,1,1,1,1,1,1,1]", ok2);

    /* Test 3: impulse */
    uint32_t imp[N] = {1, 0, 0, 0, 0, 0, 0, 0};
    copy8(x, imp);
    ntt_forward(x);
    ntt_inverse(x);
    chk_bool("roundtrip impulse", x[0] == 1u && x[1] == 0u);

    /* Test 4: arbitrary near-P values */
    uint32_t hi[N] = {P-1, P-2, P-3, P-4, P-5, P-6, P-7, P-8};
    copy8(x, hi);
    ntt_forward(x);
    ntt_inverse(x);
    int ok4 = 1;
    for (int i = 0; i < N; i++) if (x[i] != hi[i]) ok4 = 0;
    chk_bool("roundtrip [P-1..P-8]", ok4);
}

static void test_poly_mul(void)
{
    log_write(NONE, "\n-- Cyclic polynomial multiplication via NTT --\n");

    /* (1 + x)^2 = 1 + 2x + x^2 */
    uint32_t a[N] = {1, 1, 0, 0, 0, 0, 0, 0};
    uint32_t b[N] = {1, 1, 0, 0, 0, 0, 0, 0};
    uint32_t ta[N], tb[N], c[N];
    copy8(ta, a); ntt_forward(ta);
    copy8(tb, b); ntt_forward(tb);
    pointwise_mul(ta, tb, c);
    ntt_inverse(c);
    /* Expected: 1 + 2x + x^2 */
    chk("(1+x)^2 c[0]=1", c[0], 1u);
    chk("(1+x)^2 c[1]=2", c[1], 2u);
    chk("(1+x)^2 c[2]=1", c[2], 1u);
    int zero_ok = 1;
    for (int i = 3; i < N; i++) if (c[i] != 0u) zero_ok = 0;
    chk_bool("(1+x)^2 c[3..7]=0", zero_ok);

    /* (1 + 2x + 3x^2 + 4x^3) * (5 + 6x) = 5 + 16x + 27x^2 + 38x^3 + 24x^4 */
    uint32_t p1[N] = {1, 2, 3, 4, 0, 0, 0, 0};
    uint32_t p2[N] = {5, 6, 0, 0, 0, 0, 0, 0};
    uint32_t tp1[N], tp2[N];
    copy8(tp1, p1); ntt_forward(tp1);
    copy8(tp2, p2); ntt_forward(tp2);
    pointwise_mul(tp1, tp2, c);
    ntt_inverse(c);
    chk("poly mul c[0]=5",  c[0], 5u);
    chk("poly mul c[1]=16", c[1], 16u);
    chk("poly mul c[2]=27", c[2], 27u);
    chk("poly mul c[3]=38", c[3], 38u);
    chk("poly mul c[4]=24", c[4], 24u);
    chk("poly mul c[5]=0",  c[5], 0u);
    chk("poly mul c[6]=0",  c[6], 0u);
    chk("poly mul c[7]=0",  c[7], 0u);

    /* Delta convolution: a * delta = a */
    uint32_t delta[N] = {1, 0, 0, 0, 0, 0, 0, 0};
    uint32_t sig[N]   = {3, 1, 4, 1, 5, 9, 2, 6};
    uint32_t ts[N], td[N];
    copy8(ts, sig);   ntt_forward(ts);
    copy8(td, delta); ntt_forward(td);
    pointwise_mul(ts, td, c);
    ntt_inverse(c);
    int delta_ok = 1;
    for (int i = 0; i < N; i++) if (c[i] != sig[i]) delta_ok = 0;
    chk_bool("a * delta = a (cyclic conv identity)", delta_ok);
}

static void test_linearity(void)
{
    log_write(NONE, "\n-- Linearity: NTT(a+b) = NTT(a) + NTT(b) --\n");
    uint32_t a[N] = {1, 2, 3, 4, 5, 6, 7, 8};
    uint32_t b[N] = {8, 7, 6, 5, 4, 3, 2, 1};
    uint32_t ab[N], ta[N], tb[N];

    for (int i = 0; i < N; i++) ab[i] = addmod(a[i], b[i]);
    copy8(ta, a); ntt_forward(ta);
    copy8(tb, b); ntt_forward(tb);
    ntt_forward(ab);

    int ok = 1;
    for (int k = 0; k < N; k++)
        if (ab[k] != addmod(ta[k], tb[k])) ok = 0;
    chk_bool("NTT(a+b) = NTT(a) + NTT(b)", ok);
}

static void test_parseval(void)
{
    /* Plancherel (NTT Parseval):
     *   sum_{k=0}^{N-1} X[k] * X[(N-k) mod N]  =  N * sum_{n=0}^{N-1} x[n]^2   (mod P)
     *
     * (For complex DFT the analogous identity uses X[k]*conj(X[k]) = |X[k]|^2,
     *  but for NTT over Z_p "conjugate" is X[(N-k) mod N].)
     */
    log_write(NONE, "\n-- Plancherel: sum X[k]*X[N-k] = N * sum x[n]^2 (mod P) --\n");

    uint32_t x[N] = {1, 2, 3, 4, 5, 6, 7, 8};
    uint32_t X[N];
    copy8(X, x);
    ntt_forward(X);

    /* sum_n x[n]^2 = 1+4+9+16+25+36+49+64 = 204 */
    uint32_t sum_x = 0u;
    for (int i = 0; i < N; i++) sum_x = addmod(sum_x, mulmod(x[i], x[i]));

    /* sum_k X[k] * X[(N-k) mod N] */
    uint32_t sum_X = 0u;
    for (int k = 0; k < N; k++) {
        int km = (N - k) % N;
        sum_X = addmod(sum_X, mulmod(X[k], X[km]));
    }

    uint32_t lhs = mulmod((uint32_t)N, sum_x);
    chk("Plancherel: N*sum_x^2 = sum X[k]*X[N-k]", lhs, sum_X);

    /* Impulse: X[k]=1 for all k, X[N-k]=1, sum X[k]*X[N-k] = N */
    uint32_t xi[N] = {1, 0, 0, 0, 0, 0, 0, 0};
    uint32_t Xi[N];
    copy8(Xi, xi);
    ntt_forward(Xi);
    uint32_t si = 0u;
    for (int k = 0; k < N; k++) si = addmod(si, mulmod(Xi[k], Xi[(N-k)%N]));
    /* N * sum x^2 = N*1 = 8; sum X[k]*X[N-k] = N*1*1 = N */
    chk("Plancherel impulse: N = N", mulmod((uint32_t)N, 1u), si);

    /* DC: X[0]=N, X[k>0]=0, X[N-k]=0 for k>0.  sum = N*N = N^2 mod P */
    uint32_t xd[N] = {1, 1, 1, 1, 1, 1, 1, 1};
    uint32_t Xd[N];
    copy8(Xd, xd);
    ntt_forward(Xd);
    uint32_t sd = 0u;
    for (int k = 0; k < N; k++) sd = addmod(sd, mulmod(Xd[k], Xd[(N-k)%N]));
    /* N * sum x^2 = N*N = 64; sum X[k]*X[N-k] = N^2 + 0 = 64 */
    uint32_t sum_xd = 0u;
    for (int i = 0; i < N; i++) sum_xd = addmod(sum_xd, 1u);  /* sum of 1^2 = N */
    chk("Plancherel DC: N*N = N^2", mulmod((uint32_t)N, sum_xd), sd);
}

/* -- main ------------------------------------------------------------------- */
int main(void)
{
    log_init("ntt-test.log");
    log_write(NONE, "=== NTT Test (N=8, p=12289=3*2^12+1, g=11) ===\n");

    test_fermat();
    test_root_of_unity();
    test_impulse();
    test_dc();
    test_nyquist();
    test_roundtrip();
    test_poly_mul();
    test_linearity();
    test_parseval();

    log_write(NONE, "\n=== Result: %d PASS  %d FAIL ===\n", g_pass, g_fail);
    log_close();
    return g_fail;
}
