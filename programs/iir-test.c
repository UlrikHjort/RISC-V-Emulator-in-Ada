/* **************************************************************************
 *     RISC-V Emulator - IIR biquad filter tests in Q16.16 fixed-point
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

// iir-test.c -- IIR biquad filter tests in Q16.16 fixed-point
//
// Structure: Direct Form II biquad
//   w[n] = x[n] - a1*w[n-1] - a2*w[n-2]
//   y[n] = b0*w[n] + b1*w[n-1] + b2*w[n-2]
//
// Filters under test:
//   LP1 -- single-pole lowpass:  y[n] = 0.5*x[n] + 0.5*y[n-1]
//          b0=0.5, b1=0, b2=0,  a1=-0.5, a2=0
//          DC gain = 1; impulse -> geometric decay 0.5^n; step -> 1.
//
//   HP1 -- single-pole highpass: y[n] = 0.5*(x[n]-x[n-1]) + 0.5*y[n-1]
//          b0=0.5, b1=-0.5, b2=0,  a1=-0.5, a2=0
//          DC gain = 0; impulse -> alternating decay; step -> 0.
//
//   LP2 -- two-pole lowpass: poles at +/-j*0.5 (double conjugate imaginary poles)
//          b0=0.75, b1=0, b2=0,  a1=0, a2=-0.25
//          Denominator = 1 - 0.25*z^-2 -> DC gain = 0.75/(1-0.25) = 1.
//
// All coefficients are exact powers of two -> no rounding in Q16 arithmetic.
//
// Build: cd programs && make run-iir-test
// By Ulrik Hørlyk Hjort 2026

#include <stdint.h>
#include "log.h"

static int g_pass = 0, g_fail = 0;

/* -- Q16.16 helpers --------------------------------------------------------- */

#define Q16_ONE   ((int32_t)0x00010000)  /* 1.0  */
#define Q16_HALF  ((int32_t)0x00008000)  /* 0.5  */
#define Q16_NHALF ((int32_t)0xFFFF8000)  /* -0.5 */
#define Q16_3QTR  ((int32_t)0x0000C000)  /* 0.75 */
#define Q16_QTR   ((int32_t)0x00004000)  /* 0.25 */
#define Q16_NQTR  ((int32_t)0xFFFFC000)  /* -0.25*/

static inline int32_t q16_mul(int32_t a, int32_t b)
{
    return (int32_t)(((int64_t)a * (int64_t)b) >> 16);
}

/* -- Biquad state ----------------------------------------------------------- */

typedef struct {
    int32_t b0, b1, b2;   /* numerator   (Q16.16) */
    int32_t a1, a2;        /* denominator (Q16.16), a0 = 1 implicit */
    int32_t w1, w2;        /* delay elements w[n-1], w[n-2] */
} bq_t;

static void bq_init(bq_t *f,
                    int32_t b0, int32_t b1, int32_t b2,
                    int32_t a1, int32_t a2)
{
    f->b0 = b0; f->b1 = b1; f->b2 = b2;
    f->a1 = a1; f->a2 = a2;
    f->w1 = f->w2 = 0;
}

static int32_t bq_process(bq_t *f, int32_t x)
{
    int32_t w = x - q16_mul(f->a1, f->w1) - q16_mul(f->a2, f->w2);
    int32_t y = q16_mul(f->b0, w) + q16_mul(f->b1, f->w1) + q16_mul(f->b2, f->w2);
    f->w2 = f->w1;
    f->w1 = w;
    return y;
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
        log_write(NONE, "  FAIL  %s: got 0x%x  exp 0x%x  tol %d\n",
                  lbl, (uint32_t)got, (uint32_t)exp, (int)tol);
        g_fail++;
    }
}

static void chk_bool(const char *lbl, int ok)
{
    if (ok) { log_write(NONE, "  PASS  %s\n", lbl); g_pass++; }
    else    { log_write(NONE, "  FAIL  %s\n", lbl); g_fail++; }
}

/* -- Tests ------------------------------------------------------------------ */

static void test_lp1_impulse(void)
{
    log_write(NONE, "\n-- LP1: single-pole lowpass, impulse response --\n");
    /* b0=0.5, a1=-0.5: w[n]=x[n]+0.5*w[n-1], y[n]=0.5*w[n]
     * impulse: y[k] = 0.5^(k+1)  (all exact in Q16) */
    bq_t f;
    bq_init(&f, Q16_HALF, 0, 0, Q16_NHALF, 0);

    int32_t y0 = bq_process(&f, Q16_ONE);   /* x[0]=1 */
    int32_t y1 = bq_process(&f, 0);
    int32_t y2 = bq_process(&f, 0);
    int32_t y3 = bq_process(&f, 0);

    chkq("LP1 impulse y[0] = 0.5",      y0, 0x8000,  0);
    chkq("LP1 impulse y[1] = 0.25",     y1, 0x4000,  0);
    chkq("LP1 impulse y[2] = 0.125",    y2, 0x2000,  0);
    chkq("LP1 impulse y[3] = 0.0625",   y3, 0x1000,  0);
}

static void test_lp1_step(void)
{
    log_write(NONE, "\n-- LP1: single-pole lowpass, step response --\n");
    /* step: y[n] = 1 - 0.5^(n+1) -> converges to 1 (Q16=65536).
     * Exact Q16 values: y[k] = 65536 - 65536>>(k+1)               */
    bq_t f;
    bq_init(&f, Q16_HALF, 0, 0, Q16_NHALF, 0);

    int32_t y0 = bq_process(&f, Q16_ONE);
    int32_t y1 = bq_process(&f, Q16_ONE);
    int32_t y2 = bq_process(&f, Q16_ONE);
    int32_t y3 = bq_process(&f, Q16_ONE);

    chkq("LP1 step y[0] = 0.5",    y0, 0x8000,  0);  /* 32768  */
    chkq("LP1 step y[1] = 0.75",   y1, 0xC000,  0);  /* 49152  */
    chkq("LP1 step y[2] = 0.875",  y2, 0xE000,  0);  /* 57344  */
    chkq("LP1 step y[3] = 0.9375", y3, 0xF000,  0);  /* 61440  */

    /* After 16 steps, gap halves each step: 65536 - 65536>>16 = 65535 */
    for (int i = 4; i < 16; i++) bq_process(&f, Q16_ONE);
    int32_t y15 = bq_process(&f, Q16_ONE);
    chkq("LP1 step y[16] converges to ~1.0", y15, 65535, 0);
}

static void test_hp1_impulse(void)
{
    log_write(NONE, "\n-- HP1: single-pole highpass, impulse response --\n");
    /* b0=0.5, b1=-0.5, a1=-0.5: highpass.
     * w[n] = x[n] + 0.5*w[n-1]
     * y[n] = 0.5*w[n] - 0.5*w[n-1]
     * impulse: y[0]=0.5, y[1]=-0.25, y[2]=-0.125, y[3]=-0.0625  */
    bq_t f;
    bq_init(&f, Q16_HALF, Q16_NHALF, 0, Q16_NHALF, 0);

    int32_t y0 = bq_process(&f, Q16_ONE);
    int32_t y1 = bq_process(&f, 0);
    int32_t y2 = bq_process(&f, 0);
    int32_t y3 = bq_process(&f, 0);

    chkq("HP1 impulse y[0] =  0.5",    y0,  0x8000, 0);
    chkq("HP1 impulse y[1] = -0.25",   y1, (int32_t)0xFFFFC000, 0);
    chkq("HP1 impulse y[2] = -0.125",  y2, (int32_t)0xFFFFE000, 0);
    chkq("HP1 impulse y[3] = -0.0625", y3, (int32_t)0xFFFFF000, 0);
}

static void test_hp1_step(void)
{
    log_write(NONE, "\n-- HP1: single-pole highpass, step response --\n");
    /* step converges to 0 (DC blocked by highpass).
     * y[0]=0.5, y[1]=0.25, y[2]=0.125, y[3]=0.0625               */
    bq_t f;
    bq_init(&f, Q16_HALF, Q16_NHALF, 0, Q16_NHALF, 0);

    int32_t y0 = bq_process(&f, Q16_ONE);
    int32_t y1 = bq_process(&f, Q16_ONE);
    int32_t y2 = bq_process(&f, Q16_ONE);
    int32_t y3 = bq_process(&f, Q16_ONE);

    chkq("HP1 step y[0] = 0.5",    y0, 0x8000, 0);
    chkq("HP1 step y[1] = 0.25",   y1, 0x4000, 0);
    chkq("HP1 step y[2] = 0.125",  y2, 0x2000, 0);
    chkq("HP1 step y[3] = 0.0625", y3, 0x1000, 0);

    /* Run 12 more steps; output should be < 1 LSB (converged to 0) */
    for (int i = 4; i < 16; i++) bq_process(&f, Q16_ONE);
    int32_t y16 = bq_process(&f, Q16_ONE);
    chk_bool("HP1 step converges to 0", y16 == 0 || y16 == 1);
}

static void test_lp1_hp1_sum(void)
{
    log_write(NONE, "\n-- LP1 + HP1 complementary sum --\n");
    /* For an all-pole section where HP = 1 - LP, the impulse responses
     * should sum to a unit impulse: sum[0]=1, sum[k>0]=0.
     * Our LP1 and HP1 have the same pole but different zeros, so they
     * are NOT complementary by design; verify they have opposite DC gain. */
    bq_t lp, hp;
    bq_init(&lp, Q16_HALF, 0,        0, Q16_NHALF, 0);
    bq_init(&hp, Q16_HALF, Q16_NHALF, 0, Q16_NHALF, 0);

    /* Impulse: LP y[0]=0.5, HP y[0]=0.5 -> sum=1.0 */
    int32_t lp0 = bq_process(&lp, Q16_ONE);
    int32_t hp0 = bq_process(&hp, Q16_ONE);
    chkq("LP1+HP1 impulse sum[0] = 1.0", lp0 + hp0, Q16_ONE, 0);

    /* Step, DC: LP converges to 1.0, HP converges to 0 */
    bq_init(&lp, Q16_HALF, 0,        0, Q16_NHALF, 0);
    bq_init(&hp, Q16_HALF, Q16_NHALF, 0, Q16_NHALF, 0);
    int32_t lp_dc = 0, hp_dc = 0;
    for (int i = 0; i < 24; i++) {
        lp_dc = bq_process(&lp, Q16_ONE);
        hp_dc = bq_process(&hp, Q16_ONE);
    }
    chk_bool("LP1 DC gain -> 1 (> 0.999)", lp_dc >= 65530);
    chk_bool("HP1 DC gain -> 0",            hp_dc == 0 || hp_dc == 1);
}

static void test_lp2_impulse(void)
{
    log_write(NONE, "\n-- LP2: two-pole lowpass, impulse response --\n");
    /* b0=0.75, a2=-0.25  ->  y[n] = 0.75*x[n] + 0.25*y[n-2]
     * Poles at +/-j*0.5 (conjugate imaginary), stable.
     * DC gain = 0.75 / (1 - 0.25) = 1.0
     *
     * Impulse: (w[n] = x[n] + 0.25*w[n-2])
     *   w[0]=1,       y[0]=0.75
     *   w[1]=0,       y[1]=0
     *   w[2]=0.25,    y[2]=0.1875
     *   w[3]=0,       y[3]=0
     *   w[4]=0.0625,  y[4]=0.046875
     *   w[5]=0,       y[5]=0           */
    bq_t f;
    bq_init(&f, Q16_3QTR, 0, 0, 0, Q16_NQTR);

    int32_t y0 = bq_process(&f, Q16_ONE);
    int32_t y1 = bq_process(&f, 0);
    int32_t y2 = bq_process(&f, 0);
    int32_t y3 = bq_process(&f, 0);
    int32_t y4 = bq_process(&f, 0);
    int32_t y5 = bq_process(&f, 0);

    chkq("LP2 impulse y[0] = 0.75",      y0, 0xC000, 0);
    chkq("LP2 impulse y[1] = 0",         y1, 0,      0);
    chkq("LP2 impulse y[2] = 0.1875",    y2, 0x3000, 0); /* 0.75*0.25=0.1875 */
    chkq("LP2 impulse y[3] = 0",         y3, 0,      0);
    chkq("LP2 impulse y[4] = 0.046875",  y4, 0x0C00, 0); /* 0.75*0.0625 */
    chkq("LP2 impulse y[5] = 0",         y5, 0,      0);
}

static void test_lp2_step(void)
{
    log_write(NONE, "\n-- LP2: two-pole lowpass, step response --\n");
    /* step: y[n] = 0.75*w[n], w[n] = 1 + 0.25*w[n-2]
     *   w[0]=1,      y[0]=0.75   = 0xC000
     *   w[1]=1,      y[1]=0.75   = 0xC000
     *   w[2]=1.25,   y[2]=0.9375 = 0xF000
     *   w[3]=1.25,   y[3]=0.9375 = 0xF000
     *   w[4]=1.3125, y[4]=0.984375 = 0xFC00
     *   w[5]=1.3125, y[5]=0.984375 = 0xFC00  */
    bq_t f;
    bq_init(&f, Q16_3QTR, 0, 0, 0, Q16_NQTR);

    int32_t y[6];
    for (int i = 0; i < 6; i++) y[i] = bq_process(&f, Q16_ONE);

    chkq("LP2 step y[0] = 0.75",      y[0], 0xC000, 0);
    chkq("LP2 step y[1] = 0.75",      y[1], 0xC000, 0);
    chkq("LP2 step y[2] = 0.9375",    y[2], 0xF000, 0);
    chkq("LP2 step y[3] = 0.9375",    y[3], 0xF000, 0);
    chkq("LP2 step y[4] = 0.984375",  y[4], 0xFC00, 0);
    chkq("LP2 step y[5] = 0.984375",  y[5], 0xFC00, 0);

    /* Run to convergence (20 more steps) */
    for (int i = 6; i < 26; i++) bq_process(&f, Q16_ONE);
    int32_t y_dc = bq_process(&f, Q16_ONE);
    chk_bool("LP2 DC gain -> 1 (> 0.999)", y_dc >= 65530);
}

static void test_cascade(void)
{
    log_write(NONE, "\n-- Cascade LP1->LP2, impulse --\n");
    /* Cascade: LP2 output fed into LP1.  Impulse should still decay to 0. */
    bq_t lp2, lp1;
    bq_init(&lp2, Q16_3QTR, 0, 0, 0, Q16_NQTR);
    bq_init(&lp1, Q16_HALF,  0, 0, Q16_NHALF, 0);

    int32_t v0 = bq_process(&lp1, bq_process(&lp2, Q16_ONE));
    int32_t prev = v0;
    int32_t any_neg = 0;

    for (int i = 1; i < 16; i++) {
        int32_t v = bq_process(&lp1, bq_process(&lp2, 0));
        (void)prev;
        prev = v;
        if (v < 0) any_neg = 1;
    }
    chk_bool("cascade LP2->LP1 impulse starts positive", v0 > 0);
    chk_bool("cascade LP2->LP1 impulse non-negative",    !any_neg);
}

/* -- main ------------------------------------------------------------------- */
int main(void)
{
    log_init("iir-test.log");
    log_write(NONE, "=== IIR Biquad Filter Test (Q16.16) ===\n");

    test_lp1_impulse();
    test_lp1_step();
    test_hp1_impulse();
    test_hp1_step();
    test_lp1_hp1_sum();
    test_lp2_impulse();
    test_lp2_step();
    test_cascade();

    log_write(NONE, "\n=== Result: %d PASS  %d FAIL ===\n", g_pass, g_fail);
    log_close();
    return g_fail;
}
