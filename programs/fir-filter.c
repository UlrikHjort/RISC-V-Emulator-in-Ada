/* **************************************************************************
 * RISC-V Emulator - Integer FIR filter with scalar and RVV implementations
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

// fir-filter.c -- Integer FIR filter with scalar and RVV implementations
//
// Demonstrates a 16-tap symmetric FIR filter using:
//   1. Scalar reference implementation (straightforward double loop)
//   2. RVV-vectorized implementation (vectorised multiply-accumulate via matlib)
//
// The filter coefficients form a "tent" shape:
//   h = {1, 2, 3, 4, 5, 6, 7, 8, 8, 7, 6, 5, 4, 3, 2, 1}  (sum = 72)
//
// Convolution (causal, zero initial conditions):
//   y[n] = sum_{k=0}^{N-1} h[k] * x[n-k],   x[m] = 0 for m < 0
//
// Known expected outputs:
//   Impulse input x=[1,0,0,...]:   y = h (then zeros)
//   Step input    x=[1,1,1,...]:   y ramps up to sum(h)=72 over first 16 samples
//
// Build: cd programs && make run-fir-filter
// By Ulrik Hørlyk Hjort 2026

#include "matlib.h"   // vec_dot (RVV-accelerated)
#include "log.h"
#include <stdint.h>

void putchar(char c);
static void uart_puts(const char *s) {
    while (*s) { if (*s == '\n') putchar('\r'); putchar(*s++); }
}

// -- Filter definition --------------------------------------------------------

#define N_TAPS  16
#define N_INPUT 32

static const int32_t H[N_TAPS] = {
    1, 2, 3, 4, 5, 6, 7, 8,
    8, 7, 6, 5, 4, 3, 2, 1
};
// sum(H) = 72

// -- Scalar reference ---------------------------------------------------------
//
// y[n] = sum_{k=0}^{min(n, N_TAPS-1)} H[k] * x[n-k]

static void fir_scalar(const int32_t *x, int L, int32_t *y) {
    for (int n = 0; n < L; n++) {
        int32_t acc = 0;
        int K = (n < N_TAPS) ? n + 1 : N_TAPS;
        for (int k = 0; k < K; k++)
            acc += H[k] * x[n - k];
        y[n] = acc;
    }
}

// -- RVV-accelerated via vec_dot ----------------------------------------------
//
// For each output sample, copy the relevant x window into a local buffer
// (reversed: window[k] = x[n-k]) then call vec_dot(H, window, N_TAPS).
// The expensive multiply-accumulate is vectorised inside vec_dot.

static void fir_rvv(const int32_t *x, int L, int32_t *y) {
    int32_t window[N_TAPS];
    for (int n = 0; n < L; n++) {
        int K = (n < N_TAPS) ? n + 1 : N_TAPS;
        for (int k = 0; k < K; k++)    window[k] = x[n - k];
        for (int k = K; k < N_TAPS; k++) window[k] = 0;  // zero pad
        y[n] = vec_dot(H, window, N_TAPS);
    }
}

// -- Test infrastructure ------------------------------------------------------

static int g_pass = 0, g_fail = 0;

static void check(const char *label, int32_t got, int32_t expected) {
    if (got == expected) {
        log_write(NONE, "  PASS  %s\n", label); g_pass++;
    } else {
        log_write(NONE, "  FAIL  %s: got %d  expected %d\n",
                  label, got, expected); g_fail++;
    }
}

static void check_arrays(const char *label,
                          const int32_t *a, const int32_t *b, int n) {
    int ok = 1;
    for (int i = 0; i < n; i++) {
        if (a[i] != b[i]) {
            log_write(NONE, "  FAIL  %s[%d]: got %d  expected %d\n",
                      label, i, a[i], b[i]);
            ok = 0;
        }
    }
    if (ok) { log_write(NONE, "  PASS  %s\n", label); g_pass++; }
    else    { g_fail++; }
}

static void log_arr(const char *name, const int32_t *a, int n) {
    log_write(NONE, "  %s: [", name);
    for (int i = 0; i < n; i++) {
        if (i) log_write(NONE, ", ");
        log_write(NONE, "%d", a[i]);
    }
    log_write(NONE, "]\n");
}

// -- Tests --------------------------------------------------------------------

static void test_impulse(void) {
    log_write(NONE, "\n=== Impulse response ===\n");
    log_write(NONE, "  x = [1, 0, 0, ...]\n");
    log_write(NONE, "  Expected y[0..15] = h, y[16..31] = 0\n\n");

    int32_t x[N_INPUT];
    for (int i = 0; i < N_INPUT; i++) x[i] = 0;
    x[0] = 1;  // unit impulse
    int32_t ys[N_INPUT], yv[N_INPUT];

    fir_scalar(x, N_INPUT, ys);
    fir_rvv   (x, N_INPUT, yv);

    log_arr("scalar", ys, N_INPUT);
    log_arr("rvv   ", yv, N_INPUT);

    // Verify impulse response == H for first N_TAPS samples
    for (int i = 0; i < N_TAPS; i++) {
        char buf[32];
        // build label like "y[0]=h[0]"
        buf[0] = 'y'; buf[1] = '[';
        int tmp = i, pos = 2;
        if (tmp >= 10) buf[pos++] = '0' + tmp/10;
        buf[pos++] = '0' + tmp%10;
        buf[pos++] = ']'; buf[pos++] = '='; buf[pos++] = 'h';
        buf[pos++] = '[';
        if (tmp >= 10) buf[pos++] = '0' + tmp/10;
        buf[pos++] = '0' + tmp%10;
        buf[pos++] = ']'; buf[pos] = '\0';
        check(buf, ys[i], H[i]);
    }
    // Verify zeros after impulse
    {
        int ok = 1;
        for (int i = N_TAPS; i < N_INPUT; i++) if (ys[i] != 0) { ok = 0; break; }
        if (ok) { log_write(NONE, "  PASS  y[16..31] = 0\n"); g_pass++; }
        else    { log_write(NONE, "  FAIL  y[16..31] should be 0\n"); g_fail++; }
    }
    // Scalar == RVV
    check_arrays("scalar == rvv (impulse)", ys, yv, N_INPUT);
}

static void test_step(void) {
    log_write(NONE, "\n=== Step response ===\n");
    log_write(NONE, "  x = [1, 1, 1, ...]\n");
    log_write(NONE, "  y ramps up to sum(H)=72, then holds steady\n\n");

    int32_t x[N_INPUT];
    for (int i = 0; i < N_INPUT; i++) x[i] = 1;

    int32_t ys[N_INPUT], yv[N_INPUT];
    fir_scalar(x, N_INPUT, ys);
    fir_rvv   (x, N_INPUT, yv);

    log_arr("scalar", ys, N_INPUT);

    // Ramp-up: y[n] = cumsum(H[0..n]) for n < N_TAPS
    // Pre-computed from H = {1,2,3,4,5,6,7,8,8,7,6,5,4,3,2,1}
    static const int32_t step_expected[16] = {
         1,  3,  6, 10, 15, 21, 28, 36,
        44, 51, 57, 62, 66, 69, 71, 72
    };
    check_arrays("step ramp-up y[0..15]", ys, step_expected, 16);

    // Steady state: y[16..31] = 72
    {
        int ok = 1;
        for (int i = N_TAPS; i < N_INPUT; i++) if (ys[i] != 72) { ok = 0; break; }
        if (ok) { log_write(NONE, "  PASS  y[16..31] = 72 (steady state)\n"); g_pass++; }
        else    { log_write(NONE, "  FAIL  steady state should be 72\n"); g_fail++; }
    }

    // Scalar == RVV
    check_arrays("scalar == rvv (step)", ys, yv, N_INPUT);
}

static void test_ramp(void) {
    log_write(NONE, "\n=== Ramp input (scalar vs RVV agreement) ===\n");
    log_write(NONE, "  x[n] = n+1  (1, 2, 3, ..., 32)\n");

    int32_t x[N_INPUT];
    for (int i = 0; i < N_INPUT; i++) x[i] = i + 1;

    int32_t ys[N_INPUT], yv[N_INPUT];
    fir_scalar(x, N_INPUT, ys);
    fir_rvv   (x, N_INPUT, yv);

    log_arr("scalar", ys, N_INPUT);
    log_arr("rvv   ", yv, N_INPUT);

    check_arrays("scalar == rvv (ramp)", ys, yv, N_INPUT);
}

static void test_alternating(void) {
    log_write(NONE, "\n=== Alternating input (scalar vs RVV agreement) ===\n");
    log_write(NONE, "  x[n] = (-1)^n * (n+1)  (+1,-2,+3,-4,...)\n");

    int32_t x[N_INPUT];
    for (int i = 0; i < N_INPUT; i++)
        x[i] = (i & 1) ? -(i + 1) : (i + 1);

    int32_t ys[N_INPUT], yv[N_INPUT];
    fir_scalar(x, N_INPUT, ys);
    fir_rvv   (x, N_INPUT, yv);

    log_arr("scalar", ys, N_INPUT);
    log_arr("rvv   ", yv, N_INPUT);

    check_arrays("scalar == rvv (alternating)", ys, yv, N_INPUT);
}

static void test_linearity(void) {
    log_write(NONE, "\n=== Linearity: FIR(a+b) == FIR(a) + FIR(b) ===\n");

    int32_t xa[N_INPUT], xb[N_INPUT], xab[N_INPUT];
    for (int i = 0; i < N_INPUT; i++) {
        xa[i]  = i + 1;
        xb[i]  = (N_INPUT - i);
        xab[i] = xa[i] + xb[i];
    }

    int32_t ya[N_INPUT], yb[N_INPUT], yab[N_INPUT], ysum[N_INPUT];
    fir_scalar(xa,  N_INPUT, ya);
    fir_scalar(xb,  N_INPUT, yb);
    fir_scalar(xab, N_INPUT, yab);
    for (int i = 0; i < N_INPUT; i++) ysum[i] = ya[i] + yb[i];

    check_arrays("FIR(a+b) == FIR(a)+FIR(b) [scalar]", yab, ysum, N_INPUT);

    // Also verify RVV agrees
    fir_rvv(xab, N_INPUT, ysum);
    check_arrays("FIR(a+b) scalar == rvv",              yab, ysum, N_INPUT);
}

static void test_cycles(void) {
    log_write(NONE, "\n=== Cycle profiling ===\n");

    int32_t x[N_INPUT], y[N_INPUT];
    for (int i = 0; i < N_INPUT; i++) x[i] = i + 1;

    log_write(CYCLES, "fir_scalar start\n");
    fir_scalar(x, N_INPUT, y);
    log_write(CYCLES, "fir_scalar done\n");

    log_write(CYCLES, "fir_rvv start\n");
    fir_rvv(x, N_INPUT, y);
    log_write(CYCLES, "fir_rvv done\n");

    log_write(NONE, "  (vec_dot processes %d taps in ceil(%d/4)=4 vector iters)\n",
              N_TAPS, N_TAPS);
}

// -- Main ---------------------------------------------------------------------

int main(void) {
    uart_puts("=== FIR Filter Test ===\n");

    if (log_init("fir-filter.log") != 0) {
        uart_puts("ERROR: log_init failed\n");
        return 1;
    }

    log_write(NONE, "=== FIR Filter Test ===\n");
    log_write(NONE, "N_TAPS=%d  H={1,2,3,4,5,6,7,8,8,7,6,5,4,3,2,1}  sum=%d\n",
              N_TAPS, 72);
    log_write(NONE, "N_INPUT=%d  VLEN=128 => VLMAX=4 for e32/m1\n\n", N_INPUT);

    test_impulse();
    test_step();
    test_ramp();
    test_alternating();
    test_linearity();
    test_cycles();

    log_write(NONE, "\n=== Summary ===\n");
    log_write(NONE, "  PASS: %d\n", g_pass);
    log_write(NONE, "  FAIL: %d\n", g_fail);
    log_write(NONE, "  %s\n", g_fail == 0 ? "ALL TESTS PASSED" : "SOME TESTS FAILED");

    log_close();
    uart_puts(g_fail == 0 ? "ALL PASSED\n" : "SOME FAILED\n");
    return g_fail;
}
