/* **************************************************************************
 *      RISC-V Emulator - Radix-2 DIT FFT (N=8) in Q16.16 fixed-point
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

// fft-test.c -- Radix-2 DIT FFT (N=8) in Q16.16 fixed-point
//
// Algorithm: Cooley-Tukey DIT with bit-reversal permutation.
// All twiddle factors W_8^k = cos(-2pik/8) + j*sin(-2pik/8), k=0..3.
//
// Q16.16 representation: 1.0 = 65536.
//   W8[0] = { 65536,      0}   (1 + 0j)
//   W8[1] = { 46341, -46341}   (~  0.7071 - 0.7071j)
//   W8[2] = {     0, -65536}   (0 - j)
//   W8[3] = {-46341, -46341}   (~ -0.7071 - 0.7071j)
//
// Tests:
//   Impulse  -> flat spectrum (all bins = 1.0, exact)
//   DC       -> spike at bin 0 (X[0]=8, rest~0, exact)
//   Nyquist  -> spike at bin 4 (alternating +/-1 input)
//   Cosine   -> symmetric pair at bins 1 and 7 (~4.0 each, +/-2 tol)
//   Parseval -> energy conservation for impulse and DC
//   Linearity-> FFT(a+b) == FFT(a) + FFT(b)
//
// Build: cd programs && make run-fft-test
// By Ulrik Hørlyk Hjort 2026

#include <stdint.h>
#include "log.h"

static int g_pass = 0, g_fail = 0;

/* -- Q16.16 complex arithmetic ---------------------------------------------- */

typedef struct { int32_t re, im; } cx_t;

static inline int32_t q16_mul(int32_t a, int32_t b)
{
    return (int32_t)(((int64_t)a * (int64_t)b) >> 16);
}

static inline cx_t cx_mul(cx_t a, cx_t b)
{
    return (cx_t){
        q16_mul(a.re, b.re) - q16_mul(a.im, b.im),
        q16_mul(a.re, b.im) + q16_mul(a.im, b.re)
    };
}

static inline cx_t cx_add(cx_t a, cx_t b) { return (cx_t){a.re+b.re, a.im+b.im}; }
static inline cx_t cx_sub(cx_t a, cx_t b) { return (cx_t){a.re-b.re, a.im-b.im}; }

/* -- N=8 Radix-2 DIT FFT --------------------------------------------------- */

/* Twiddle factors W_8^k for k = 0..3 */
static const cx_t W8[4] = {
    { 65536,      0},   /* W8^0 =  1       */
    { 46341, -46341},   /* W8^1 ~  0.7071 - 0.7071j */
    {     0, -65536},   /* W8^2 = -j       */
    {-46341, -46341}    /* W8^3 ~ -0.7071 - 0.7071j */
};

/* Bit-reversal table for N=8 */
static const int BR8[8] = {0, 4, 2, 6, 1, 5, 3, 7};

static void fft8(cx_t x[8])
{
    /* Bit-reversal permutation */
    cx_t tmp[8];
    for (int i = 0; i < 8; i++) tmp[i] = x[BR8[i]];
    for (int i = 0; i < 8; i++) x[i]   = tmp[i];

    /* Stage 1: butterfly size 2 (twiddle W_2^0 = 1, W_2^1 = -1) */
    for (int i = 0; i < 8; i += 2) {
        cx_t u = x[i], v = x[i+1];
        x[i]   = cx_add(u, v);
        x[i+1] = cx_sub(u, v);
    }

    /* Stage 2: butterfly size 4 (twiddles W_4^0=1, W_4^1=-j) */
    for (int i = 0; i < 8; i += 4) {
        cx_t u0 = x[i+0], u1 = x[i+1];
        cx_t v0 = x[i+2], v1 = x[i+3];
        cx_t t0 = v0;                          /* W_4^0 = 1 */
        cx_t t1 = (cx_t){v1.im, -v1.re};      /* W_4^1 = -j: (a+jb)*(-j) = b - ja */
        x[i+0] = cx_add(u0, t0);
        x[i+1] = cx_add(u1, t1);
        x[i+2] = cx_sub(u0, t0);
        x[i+3] = cx_sub(u1, t1);
    }

    /* Stage 3: butterfly size 8 (twiddles W_8^0..W_8^3) */
    for (int k = 0; k < 4; k++) {
        cx_t u = x[k];
        cx_t v = cx_mul(W8[k], x[k+4]);
        x[k]   = cx_add(u, v);
        x[k+4] = cx_sub(u, v);
    }
}

/* -- Test helpers ----------------------------------------------------------- */

static void chkq(const char *lbl, int32_t got, int32_t exp, int32_t tol)
{
    int32_t d = got - exp;
    if (d < 0) d = -d;
    if (d <= tol) {
        log_write(NONE, "  PASS  %s\n", lbl);
        g_pass++;
    } else {
        log_write(NONE, "  FAIL  %s: got %d  exp %d  tol %d\n",
                  lbl, (int)got, (int)exp, (int)tol);
        g_fail++;
    }
}

static void chk_bool(const char *lbl, int ok)
{
    if (ok) { log_write(NONE, "  PASS  %s\n", lbl); g_pass++; }
    else    { log_write(NONE, "  FAIL  %s\n", lbl); g_fail++; }
}

/* Compute sum of q16_mul(re,re)+q16_mul(im,im) over all bins */
static int32_t energy_q16(cx_t x[8])
{
    int32_t e = 0;
    for (int k = 0; k < 8; k++)
        e += q16_mul(x[k].re, x[k].re) + q16_mul(x[k].im, x[k].im);
    return e;
}

/* -- Individual tests ------------------------------------------------------- */

static void test_impulse(void)
{
    log_write(NONE, "\n-- Impulse (delta) -> flat spectrum --\n");
    /* x[0]=1, rest=0. Expected: X[k]=1 for all k (exact, no twiddle muls). */
    cx_t x[8] = {
        {65536,0},{0,0},{0,0},{0,0},{0,0},{0,0},{0,0},{0,0}
    };
    fft8(x);

    for (int k = 0; k < 8; k++) {
        chkq("impulse X[k].re = 1.0", x[k].re, 65536, 0);
        chkq("impulse X[k].im = 0.0", x[k].im, 0,     0);
    }
}

static void test_dc(void)
{
    log_write(NONE, "\n-- DC (all-ones) -> spike at bin 0 --\n");
    /* x[n]=1 for all n. Expected: X[0]=8, X[k!=0]=0 (exact). */
    cx_t x[8];
    for (int i = 0; i < 8; i++) x[i] = (cx_t){65536, 0};
    fft8(x);

    chkq("DC X[0].re = 8.0", x[0].re, 8*65536, 0);
    chkq("DC X[0].im = 0",   x[0].im, 0,       0);
    for (int k = 1; k < 8; k++) {
        chkq("DC X[k].re = 0", x[k].re, 0, 0);
        chkq("DC X[k].im = 0", x[k].im, 0, 0);
    }
}

static void test_nyquist(void)
{
    log_write(NONE, "\n-- Nyquist (alternating +-1) -> spike at bin 4 --\n");
    /* x[n] = (-1)^n. Expected: X[4]=8, X[k!=4]=0 (exact, same butterfly). */
    cx_t x[8];
    for (int i = 0; i < 8; i++)
        x[i] = (cx_t){(i & 1) ? -65536 : 65536, 0};
    fft8(x);

    for (int k = 0; k < 8; k++) {
        if (k == 4) {
            chkq("Nyquist X[4].re = 8.0", x[k].re, 8*65536, 0);
            chkq("Nyquist X[4].im = 0",   x[k].im, 0,       0);
        } else {
            chkq("Nyquist X[k!=4].re = 0", x[k].re, 0, 0);
            chkq("Nyquist X[k!=4].im = 0", x[k].im, 0, 0);
        }
    }
}

static void test_cosine(void)
{
    log_write(NONE, "\n-- Cosine (freq=1) -> symmetric pair at bins 1 and 7 --\n");
    /* x[n] = cos(2*pi*n/8): bins 1 and 7 each get N/2 = 4.0 (real).
     * Due to twiddle rounding (46341 vs 46340.95), tolerance = 2 LSB. */
    cx_t x[8] = {
        { 65536, 0},   /* cos(0)     =  1.0   */
        { 46341, 0},   /* cos(pi/4)  ~  0.7071 */
        {     0, 0},   /* cos(pi/2)  =  0     */
        {-46341, 0},   /* cos(3pi/4) ~ -0.7071 */
        {-65536, 0},   /* cos(pi)    = -1.0   */
        {-46341, 0},   /* cos(5pi/4) ~ -0.7071 */
        {     0, 0},   /* cos(3pi/2) =  0     */
        { 46341, 0}    /* cos(7pi/4) ~  0.7071 */
    };
    fft8(x);

    /* Bins 1 and 7 should each have re ~ 4*65536 = 262144 */
    chkq("cosine X[1].re ~ 4.0", x[1].re, 4*65536, 2);
    chkq("cosine X[1].im ~ 0",   x[1].im, 0,       2);
    chkq("cosine X[7].re ~ 4.0", x[7].re, 4*65536, 2);
    chkq("cosine X[7].im ~ 0",   x[7].im, 0,       2);

    /* All other bins should be near zero */
    int32_t tol = 4;
    chkq("cosine X[0].re ~ 0", x[0].re, 0, tol);
    chkq("cosine X[2].re ~ 0", x[2].re, 0, tol);
    chkq("cosine X[3].re ~ 0", x[3].re, 0, tol);
    chkq("cosine X[4].re ~ 0", x[4].re, 0, tol);
    chkq("cosine X[5].re ~ 0", x[5].re, 0, tol);
    chkq("cosine X[6].re ~ 0", x[6].re, 0, tol);
}

static void test_parseval(void)
{
    log_write(NONE, "\n-- Parseval energy conservation --\n");
    /* Parseval: sum|x[n]|^2 == sum|X[k]|^2 / N
     * All arithmetic in Q16.16 via q16_mul.                          */

    /* Impulse: sum_x = 1.0 (in Q16), sum_X/8 = 8*1.0/8 = 1.0        */
    cx_t xi[8] = {{65536,0},{0,0},{0,0},{0,0},{0,0},{0,0},{0,0},{0,0}};
    int32_t sx = energy_q16(xi);   /* before FFT */
    fft8(xi);
    int32_t sX = energy_q16(xi) / 8;
    chkq("Parseval impulse: sum_x^2 = sum_X^2/N", sx, sX, 0);

    /* DC: x[n]=1 for all n. sum_x = 8.0, X[0]=8.0 only -> sum_X/8 = 8.0 */
    cx_t xd[8];
    for (int i = 0; i < 8; i++) xd[i] = (cx_t){65536, 0};
    int32_t sd = energy_q16(xd);   /* = 8*q16_mul(65536,65536) = 8*65536 */
    fft8(xd);
    int32_t sXd = energy_q16(xd) / 8;
    chkq("Parseval DC:      sum_x^2 = sum_X^2/N", sd, sXd, 0);
}

static void test_linearity(void)
{
    log_write(NONE, "\n-- Linearity: FFT(a+b) == FFT(a) + FFT(b) --\n");
    /* Use impulse for 'a' and DC for 'b'.
     * a[0]=1 rest=0; b[n]=1 for all n.
     * FFT(a)[k] = 1.0, FFT(b)[0]=8 rest=0.
     * FFT(a+b)[k]: (a+b)[0]=2, (a+b)[1..7]=1.
     * X[0] should be 1+8=9, X[k>0] should be 1+0=1.  */
    cx_t xa[8] = {{65536,0},{0,0},{0,0},{0,0},{0,0},{0,0},{0,0},{0,0}};
    cx_t xb[8];
    for (int i = 0; i < 8; i++) xb[i] = (cx_t){65536, 0};
    cx_t xab[8];
    for (int i = 0; i < 8; i++) xab[i] = cx_add(xa[i], xb[i]);

    fft8(xa);
    fft8(xb);
    fft8(xab);

    /* FFT(a+b) == FFT(a) + FFT(b) for each bin */
    int ok = 1;
    for (int k = 0; k < 8; k++) {
        if (xab[k].re != xa[k].re + xb[k].re) ok = 0;
        if (xab[k].im != xa[k].im + xb[k].im) ok = 0;
    }
    chk_bool("linearity FFT(a+b) == FFT(a)+FFT(b)", ok);

    /* Spot-check: X[0] = 9.0, X[1] = 1.0 */
    chkq("linear X[0].re = 9.0", xab[0].re, 9*65536, 0);
    chkq("linear X[1].re = 1.0", xab[1].re, 65536,   0);
}

/* -- main ------------------------------------------------------------------- */
int main(void)
{
    log_init("fft-test.log");
    log_write(NONE, "=== Radix-2 DIT FFT Test (N=8, Q16.16) ===\n");

    test_impulse();
    test_dc();
    test_nyquist();
    test_cosine();
    test_parseval();
    test_linearity();

    log_write(NONE, "\n=== Result: %d PASS  %d FAIL ===\n", g_pass, g_fail);
    log_close();
    return g_fail;
}
