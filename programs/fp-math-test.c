/* **************************************************************************
 *     RISC-V Emulator - Comprehensive FPU test for the RISC-V emulator
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

// fp-math-test.c -- Comprehensive FPU test for the RISC-V emulator.
//
// Covers single- and double-precision floating-point:
//   1. Basic arithmetic (add, sub, mul, div) with exact results
//   2. Integer <-> float/double conversions (fcvt.s.w, fcvt.w.s, etc.)
//   3. Comparisons  (feq.s, flt.s, fle.s and double variants)
//   4. Special values: +/-Inf, NaN, -0.0
//   5. Float <-> double promotion (fcvt.d.s, fcvt.s.d)
//   6. Cycle-count profiling for mul and div
//
// Build: cd programs && make run-fp-math-test
// By Ulrik Hørlyk Hjort 2026

#include "log.h"
#include <stdint.h>

void putchar(char c);

static void uart_puts(const char *s) {
    while (*s) { if (*s == '\n') putchar('\r'); putchar(*s++); }
}

static int g_pass = 0, g_fail = 0;

// --- Bit-level helpers -------------------------------------------------------

static inline uint32_t f32_bits(float f) {
    uint32_t u; __builtin_memcpy(&u, &f, 4); return u;
}
static inline uint64_t f64_bits(double d) {
    uint64_t u; __builtin_memcpy(&u, &d, 8); return u;
}
static inline float bits_f32(uint32_t u) {
    float f; __builtin_memcpy(&f, &u, 4); return f;
}
static inline double bits_f64(uint64_t u) {
    double d; __builtin_memcpy(&d, &u, 8); return d;
}

// --- Checkers ----------------------------------------------------------------

static void check_f32(const char *label, float got, float expected) {
    if (f32_bits(got) == f32_bits(expected)) {
        log_write(NONE, "  PASS  %s\n", label); g_pass++;
    } else {
        log_write(NONE, "  FAIL  %s: got %x  exp %x\n",
                  label, f32_bits(got), f32_bits(expected)); g_fail++;
    }
}

static void check_f64(const char *label, double got, double expected) {
    if (f64_bits(got) == f64_bits(expected)) {
        log_write(NONE, "  PASS  %s\n", label); g_pass++;
    } else {
        uint32_t g_hi = (uint32_t)(f64_bits(got) >> 32);
        uint32_t g_lo = (uint32_t)(f64_bits(got));
        uint32_t e_hi = (uint32_t)(f64_bits(expected) >> 32);
        uint32_t e_lo = (uint32_t)(f64_bits(expected));
        log_write(NONE, "  FAIL  %s: got %x%x  exp %x%x\n",
                  label, g_hi, g_lo, e_hi, e_lo); g_fail++;
    }
}

static void check_i32(const char *label, int32_t got, int32_t expected) {
    if (got == expected) {
        log_write(NONE, "  PASS  %s\n", label); g_pass++;
    } else {
        log_write(NONE, "  FAIL  %s: got %d  exp %d\n", label, got, expected); g_fail++;
    }
}

static void check_bool(const char *label, int got, int expected) {
    check_i32(label, got, expected);
}

// --- 1. Single-precision arithmetic ------------------------------------------

static void test_f32_arith(void) {
    log_write(NONE, "\n=== float arithmetic (fadd/fsub/fmul/fdiv) ===\n");

    check_f32("1.0f + 2.0f = 3.0f",        1.0f + 2.0f,   3.0f);
    check_f32("5.0f - 3.0f = 2.0f",        5.0f - 3.0f,   2.0f);
    check_f32("4.0f * 0.5f = 2.0f",        4.0f * 0.5f,   2.0f);
    check_f32("6.0f / 2.0f = 3.0f",        6.0f / 2.0f,   3.0f);
    check_f32("-1.5f + 3.5f = 2.0f",      -1.5f + 3.5f,   2.0f);
    check_f32("0.25f * 8.0f = 2.0f",      0.25f * 8.0f,   2.0f);
    check_f32("1.0f / 4.0f = 0.25f",      1.0f / 4.0f,    0.25f);
    check_f32("-3.0f * -2.0f = 6.0f",    -3.0f * -2.0f,   6.0f);
    check_f32("1.0f - 1.0f = 0.0f",       1.0f - 1.0f,    0.0f);
    check_f32("0.5f + 0.5f = 1.0f",       0.5f + 0.5f,    1.0f);
    check_f32("1.5f * 4.0f = 6.0f",       1.5f * 4.0f,    6.0f);
    check_f32("7.0f / 0.5f = 14.0f",      7.0f / 0.5f,   14.0f);
}

// --- 2. Single-precision conversions -----------------------------------------

static void test_f32_conv(void) {
    log_write(NONE, "\n=== float<->int conversions (fcvt.s.w / fcvt.w.s) ===\n");

    // int -> float  (fcvt.s.w)
    check_f32("(float)0   = 0.0f",            (float)0,        0.0f);
    check_f32("(float)1   = 1.0f",            (float)1,        1.0f);
    check_f32("(float)-1  = -1.0f",           (float)(-1),    -1.0f);
    check_f32("(float)100 = 100.0f",          (float)100,     100.0f);
    check_f32("(float)1024 = 1024.0f",        (float)1024,   1024.0f);
    check_f32("(float)-32768 = -32768.0f",    (float)(-32768), -32768.0f);

    // float -> int  (fcvt.w.s, truncation toward zero)
    check_i32("(int)3.9f   =  3",  (int)3.9f,    3);
    check_i32("(int)3.1f   =  3",  (int)3.1f,    3);
    check_i32("(int)-3.9f  = -3",  (int)(-3.9f), -3);
    check_i32("(int)-3.1f  = -3",  (int)(-3.1f), -3);
    check_i32("(int)0.5f   =  0",  (int)0.5f,    0);
    check_i32("(int)-0.5f  =  0",  (int)(-0.5f), 0);
    check_i32("(int)1024.0f = 1024", (int)1024.0f, 1024);
}

// --- 3. Single-precision comparisons -----------------------------------------

static void test_f32_cmp(void) {
    log_write(NONE, "\n=== float comparisons (feq/flt/fle) ===\n");

    check_bool("1.0f == 1.0f  -> 1",  (1.0f == 1.0f), 1);
    check_bool("1.0f == 2.0f  -> 0",  (1.0f == 2.0f), 0);
    check_bool("1.0f  < 2.0f  -> 1",  (1.0f  < 2.0f), 1);
    check_bool("2.0f  < 1.0f  -> 0",  (2.0f  < 1.0f), 0);
    check_bool("2.0f  > 1.0f  -> 1",  (2.0f  > 1.0f), 1);
    check_bool("1.0f <= 1.0f  -> 1",  (1.0f <= 1.0f), 1);
    check_bool("1.5f >= 1.5f  -> 1",  (1.5f >= 1.5f), 1);
    check_bool("-1.0f < 0.0f  -> 1", (-1.0f  < 0.0f), 1);
    check_bool("0.0f <= 0.0f  -> 1",  (0.0f <= 0.0f), 1);
}

// --- 4. Special values -------------------------------------------------------

static void test_f32_special(void) {
    log_write(NONE, "\n=== float special values (Inf, NaN, -0) ===\n");

    // Bit-construct special values to avoid UB
    volatile float pos_inf  = bits_f32(0x7f800000U);  // +Inf
    volatile float neg_inf  = bits_f32(0xff800000U);  // -Inf
    volatile float nan_val  = bits_f32(0x7fc00000U);  // quiet NaN
    volatile float neg_zero = bits_f32(0x80000000U);  // -0.0

    // Inf arithmetic
    check_f32("+Inf + 1.0f = +Inf",  pos_inf + 1.0f,  pos_inf);
    check_f32("-Inf - 1.0f = -Inf",  neg_inf - 1.0f,  neg_inf);
    check_f32("+Inf * 2.0f = +Inf",  pos_inf * 2.0f,  pos_inf);

    // NaN propagation: result of any op with NaN is NaN (i.e. != itself)
    volatile float nan_add = nan_val + 1.0f;
    volatile float nan_mul = nan_val * 2.0f;
    check_bool("NaN + 1.0f -> NaN",   (nan_add != nan_add), 1);
    check_bool("NaN * 2.0f -> NaN",   (nan_mul != nan_mul), 1);

    // Ordered comparisons with NaN are all false
    check_bool("NaN == NaN -> 0",  (nan_val == nan_val), 0);
    check_bool("NaN  < 1.0f -> 0", (nan_val  < 1.0f),   0);
    check_bool("NaN  > 1.0f -> 0", (nan_val  > 1.0f),   0);
    check_bool("NaN <= 1.0f -> 0", (nan_val <= 1.0f),   0);

    // -0.0 == +0.0 per IEEE 754, but bits differ
    check_bool("-0.0f == 0.0f -> 1",        (neg_zero == 0.0f), 1);
    check_bool("-0.0f bits != 0.0f bits -> 1",
               (f32_bits(neg_zero) != f32_bits(0.0f)), 1);
}

// --- 5. Double-precision arithmetic ------------------------------------------

static void test_f64_arith(void) {
    log_write(NONE, "\n=== double arithmetic (fadd.d/fsub.d/fmul.d/fdiv.d) ===\n");

    check_f64("1.0 + 2.0 = 3.0",      1.0 + 2.0,   3.0);
    check_f64("5.0 - 3.0 = 2.0",      5.0 - 3.0,   2.0);
    check_f64("4.0 * 0.5 = 2.0",      4.0 * 0.5,   2.0);
    check_f64("6.0 / 2.0 = 3.0",      6.0 / 2.0,   3.0);
    check_f64("-1.5 + 3.5 = 2.0",    -1.5 + 3.5,   2.0);
    check_f64("0.25 * 8.0 = 2.0",    0.25 * 8.0,   2.0);
    check_f64("1.0 / 8.0 = 0.125",   1.0 / 8.0,    0.125);
    check_f64("1.0 - 1.0 = 0.0",     1.0 - 1.0,    0.0);
    check_f64("0.5 + 0.5 = 1.0",     0.5 + 0.5,    1.0);
}

// --- 6. Double-precision conversions -----------------------------------------

static void test_f64_conv(void) {
    log_write(NONE, "\n=== double<->int conversions (fcvt.d.w / fcvt.w.d) ===\n");

    check_f64("(double)1      = 1.0",   (double)1,      1.0);
    check_f64("(double)-42    = -42.0", (double)(-42), -42.0);
    check_f64("(double)65536  = 65536.0", (double)65536, 65536.0);
    check_f64("(double)0      = 0.0",   (double)0,      0.0);

    check_i32("(int)3.9  =  3", (int)3.9,   3);
    check_i32("(int)-3.9 = -3", (int)(-3.9), -3);
    check_i32("(int)1.0  =  1", (int)1.0,   1);
}

// --- 7. Float <-> double promotion -------------------------------------------

static void test_f32_f64_promo(void) {
    log_write(NONE, "\n=== float<->double promotion (fcvt.d.s / fcvt.s.d) ===\n");

    float  f1 = 1.5f;
    double d1 = (double)f1;
    check_f64("(double)1.5f = 1.5",  d1, 1.5);

    double d2 = 2.75;
    float  f2 = (float)d2;
    check_f32("(float)2.75 = 2.75f", f2, 2.75f);

    float  f3 = 1048576.0f;   // 2^20 -- exact in both
    double d3 = (double)f3;
    check_f64("(double)2^20f = 2^20", d3, 1048576.0);

    double d4 = 0.5;
    float  f4 = (float)d4;
    check_f32("(float)0.5 = 0.5f", f4, 0.5f);

    double d5 = -3.0;
    float  f5 = (float)d5;
    check_f32("(float)-3.0 = -3.0f", f5, -3.0f);

    // The conversions above all fold at compile time, so they never execute a
    // real fcvt.d.s / fcvt.s.d. Route these through volatile storage so the
    // compiler must emit the instruction and the emulator actually runs it.
    // Regression: both instructions once read an unassigned source operand and
    // silently returned NaN, because the format bit in funct7 names the
    // destination width, not the source width.
    {
        static volatile float  vf = 0.535617f;   // 0x3F091E32
        static volatile double vd = 0.535617;    // 0x3FE123C64345CFEE

        double p = (double)vf;                   // fcvt.d.s at run time
        check_f64("(double)vf -> 0x3FE123C640000000",
                  p, bits_f64(0x3FE123C640000000ULL));

        float q = (float)vd;                     // fcvt.s.d at run time
        check_f32("(float)vd -> 0x3F091E32", q, bits_f32(0x3F091E32U));

        // Round trip must land back on the original single.
        check_f32("(float)(double)vf = vf", (float)(double)vf, vf);
    }
}

// --- 8. Double special values -------------------------------------------------

static void test_f64_special(void) {
    log_write(NONE, "\n=== double special values ===\n");

    volatile double pos_inf = bits_f64(0x7ff0000000000000ULL);
    volatile double nan_val = bits_f64(0x7ff8000000000000ULL);

    check_f64("+Inf + 1.0 = +Inf", pos_inf + 1.0, pos_inf);

    volatile double nan_add = nan_val + 1.0;
    check_bool("NaN + 1.0 -> NaN",  (nan_add != nan_add), 1);
    check_bool("NaN == NaN -> 0",   (nan_val == nan_val), 0);
}

// --- 9. Cycle profiling -------------------------------------------------------

static void test_cycles(void) {
    log_write(NONE, "\n=== Cycle profiling ===\n");

    volatile float fa = 1.23456789f, fb = 9.87654321f, fr;
    log_write(CYCLES, "100x float mul\n");
    for (int i = 0; i < 100; i++) fr = fa * fb;
    log_write(CYCLES, "100x float mul done\n");

    log_write(CYCLES, "100x float div\n");
    for (int i = 0; i < 100; i++) fr = fa / fb;
    log_write(CYCLES, "100x float div done\n");

    volatile double da = 1.23456789, db = 9.87654321, dr;
    log_write(CYCLES, "100x double mul\n");
    for (int i = 0; i < 100; i++) dr = da * db;
    log_write(CYCLES, "100x double mul done\n");

    log_write(CYCLES, "100x double div\n");
    for (int i = 0; i < 100; i++) dr = da / db;
    log_write(CYCLES, "100x double div done\n");

    (void)fr; (void)dr;
}

// --- Main ---------------------------------------------------------------------

int main(void) {
    uart_puts("=== FP Math Test ===\n");
    if (log_init("fp-math-test.log") != 0) {
        uart_puts("ERROR: log_init failed\n");
        return 1;
    }

    log_write(NONE, "=== FP Math Test (RV32IMFD) ===\n");

    test_f32_arith();
    test_f32_conv();
    test_f32_cmp();
    test_f32_special();
    test_f64_arith();
    test_f64_conv();
    test_f32_f64_promo();
    test_f64_special();
    test_cycles();

    log_write(NONE, "\n=== Summary ===\n");
    log_write(NONE, "  PASS: %d\n", g_pass);
    log_write(NONE, "  FAIL: %d\n", g_fail);
    log_write(NONE, "  %s\n", g_fail == 0 ? "ALL TESTS PASSED" : "SOME TESTS FAILED");

    log_close();
    uart_puts(g_fail == 0 ? "ALL PASSED\n" : "SOME FAILED\n");
    return g_fail;
}
