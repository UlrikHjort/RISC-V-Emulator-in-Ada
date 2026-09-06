/* **************************************************************************
 *               RISC-V Emulator - RV64 FPU Test (F + D extensions)
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
 * **************************************************************************
 * Tests floating-point instructions in the RV64 context, including the
 * RV64-only conversions: FCVT.L.D, FCVT.LU.D, FCVT.D.L, FCVT.D.LU,
 * FMV.X.D, and FMV.D.X.
 */

#include <stdint.h>
#include "log.h"

static int g_pass = 0, g_fail = 0;

static void chk(const char *label, int ok) {
    if (ok) { log_write(NONE, "PASS %s\n", label); g_pass++; }
    else     { log_write(NONE, "FAIL %s\n", label); g_fail++; }
}

/* Bit-cast double <-> uint64_t without triggering UB */
static uint64_t d_to_u64(double d) {
    uint64_t v;
    __builtin_memcpy(&v, &d, 8);
    return v;
}
static double u64_to_d(uint64_t v) {
    double d;
    __builtin_memcpy(&d, &v, 8);
    return d;
}
static uint32_t f_to_u32(float f) {
    uint32_t v;
    __builtin_memcpy(&v, &f, 4);
    return v;
}

/* Hardware FP helpers (avoid libm dependency) */
static double hw_sqrt(double x) {
    double r;
    asm volatile ("fsqrt.d %0,%1" : "=f"(r) : "f"(x));
    return r;
}
static double hw_fma(double a, double b, double c) {
    double r;
    asm volatile ("fmadd.d %0,%1,%2,%3" : "=f"(r) : "f"(a), "f"(b), "f"(c));
    return r;
}
static double hw_copysign(double x, double y) {
    double r;
    asm volatile ("fsgnj.d  %0,%1,%2" : "=f"(r) : "f"(x), "f"(y));
    return r;
}
static double hw_ncopysign(double x, double y) {   /* FSGNJN: negate sign of y */
    double r;
    asm volatile ("fsgnjn.d %0,%1,%2" : "=f"(r) : "f"(x), "f"(y));
    return r;
}
static double hw_xcopysign(double x, double y) {   /* FSGNJX: XOR signs */
    double r;
    asm volatile ("fsgnjx.d %0,%1,%2" : "=f"(r) : "f"(x), "f"(y));
    return r;
}

/* Simple approximate equality for double */
static int deq(double a, double b, double tol) {
    double diff = a - b;
    if (diff < 0.0) diff = -diff;
    double ref  = b < 0.0 ? -b : b;
    if (ref < 1e-300) return diff < tol;
    return diff / ref < tol;
}

int main(void) {
    log_init("rv64-fp-test.log");

    /* ------------------------------------------------------------------ */
    /* --- Double-precision arithmetic (D extension) --- */
    /* ------------------------------------------------------------------ */
    volatile double a = 3.14159265358979323846;
    volatile double b = 2.71828182845904523536;

    chk("dadd",  deq(a + b, 5.85987448204883847382, 1e-14));
    chk("dsub",  deq(a - b, 0.42331082513074800310, 1e-14));
    chk("dmul",  deq(a * b, 8.53973422267356706546, 1e-14));
    chk("ddiv",  deq(a / b, 1.15572734979092268399, 1e-14));

    /* sqrt(2.0) -- uses FSQRT.D hardware instruction */
    volatile double two = 2.0;
    chk("dsqrt", deq(hw_sqrt(two), 1.41421356237309504880, 1e-14));

    /* FMA: a*b + 1.0 -- uses FMADD.D hardware instruction */
    volatile double fma_r = hw_fma(a, b, 1.0);
    chk("dfma",  deq(fma_r, 9.53973422267356706546, 1e-14));

    /* ------------------------------------------------------------------ */
    /* --- Double comparisons --- */
    /* ------------------------------------------------------------------ */
    volatile double big  =  1e15;
    volatile double small= -1e15;
    chk("dcmp_lt",  small < big);
    chk("dcmp_le",  small <= small);
    chk("dcmp_eq",  big == big);
    chk("dcmp_ne",  small != big);

    /* ------------------------------------------------------------------ */
    /* --- FCVT.D.W / FCVT.W.D (int32 <-> double, works in RV32 too) --- */
    /* ------------------------------------------------------------------ */
    volatile int32_t i32 = -123456;
    volatile double  d32 = (double)i32;
    chk("fcvt_d_w",  d32 == -123456.0);
    volatile int32_t back32 = (int32_t)d32;
    chk("fcvt_w_d",  back32 == -123456);

    volatile uint32_t u32 = 3000000000U;
    volatile double   du32 = (double)u32;
    chk("fcvt_d_wu", du32 == 3000000000.0);
    volatile uint32_t bku32 = (uint32_t)du32;
    chk("fcvt_wu_d", bku32 == 3000000000U);

    /* ------------------------------------------------------------------ */
    /* --- RV64-specific: FCVT.D.L / FCVT.L.D (int64 <-> double) --- */
    /* ------------------------------------------------------------------ */
    volatile int64_t big_i64 = 9000000000000LL;     /* 9 trillion */
    volatile double  d_i64   = (double)big_i64;
    chk("fcvt_d_l",  d_i64 == 9000000000000.0);

    volatile int64_t back_i64 = (int64_t)d_i64;
    chk("fcvt_l_d",  back_i64 == 9000000000000LL);

    volatile int64_t neg_i64 = -9000000000000LL;
    volatile double  d_neg   = (double)neg_i64;
    chk("fcvt_d_l_neg", d_neg == -9000000000000.0);
    volatile int64_t back_neg = (int64_t)d_neg;
    chk("fcvt_l_d_neg", back_neg == -9000000000000LL);

    /* ------------------------------------------------------------------ */
    /* --- RV64-specific: FCVT.D.LU / FCVT.LU.D (uint64 <-> double) --- */
    /* ------------------------------------------------------------------ */
    volatile uint64_t big_u64 = 18000000000000000000ULL;  /* > 2^63 */
    volatile double   d_u64   = (double)big_u64;
    chk("fcvt_d_lu", deq(d_u64, 1.8e19, 1e-3));

    volatile uint64_t back_u64 = (uint64_t)d_u64;
    /* Allow rounding: within 1 LSB of a double near 1.8e19 */
    chk("fcvt_lu_d", back_u64 >= 17999999999999995904ULL &&
                     back_u64 <= 18000000000000004096ULL);

    /* ------------------------------------------------------------------ */
    /* --- FMV.X.D / FMV.D.X: bit-exact moves between FP and int regs --- */
    /* ------------------------------------------------------------------ */
    /* Pi bit pattern = 0x400921FB54442D18 */
    volatile double pi = 3.14159265358979323846;
    volatile uint64_t pi_bits = d_to_u64(pi);
    chk("fmv_x_d",  pi_bits == UINT64_C(0x400921FB54442D18));

    volatile double pi2 = u64_to_d(UINT64_C(0x400921FB54442D18));
    chk("fmv_d_x",  deq(pi2, 3.14159265358979323846, 1e-14));

    /* -0.0 has bit pattern 0x8000000000000000 */
    volatile uint64_t neg_zero_bits = UINT64_C(0x8000000000000000);
    volatile double   neg_zero = u64_to_d(neg_zero_bits);
    chk("fmv_neg_zero", neg_zero == 0.0 && d_to_u64(neg_zero) == neg_zero_bits);

    /* ------------------------------------------------------------------ */
    /* --- FCLASS.D --- */
    /* ------------------------------------------------------------------ */
    /* FCLASS.D bit layout: bit 6 = positive normal number */
    {
        uint64_t cls;
        asm volatile ("fclass.d %0,%1" : "=r"(cls) : "f"(pi));
        chk("fclass_d_pos_normal", (cls & (1ULL << 6)) != 0);

        volatile double inf_pos = 1.0 / 0.0;
        asm volatile ("fclass.d %0,%1" : "=r"(cls) : "f"(inf_pos));
        chk("fclass_d_pos_inf",    (cls & (1ULL << 7)) != 0);

        volatile double minus_pi = -pi;
        asm volatile ("fclass.d %0,%1" : "=r"(cls) : "f"(minus_pi));
        chk("fclass_d_neg_normal", (cls & (1ULL << 1)) != 0);
    }

    /* ------------------------------------------------------------------ */
    /* --- F extension (float32) still works in RV64 context --- */
    /* ------------------------------------------------------------------ */
    volatile float fa = 1.5f;
    volatile float fb = 2.5f;
    chk("fadd_s", fa + fb == 4.0f);
    chk("fmul_s", fa * fb == 3.75f);
    chk("fdiv_s", fb / fa == (5.0f / 3.0f));

    volatile int32_t fi = (int32_t)fb;
    chk("fcvt_w_s",  fi == 2);
    volatile float   ff = (float)fi;
    chk("fcvt_s_w",  ff == 2.0f);

    /* FMV.X.W: 1.5f = 0x3FC00000 */
    volatile uint32_t f32_bits = f_to_u32(fa);
    chk("fmv_x_w", f32_bits == 0x3FC00000U);

    /* ------------------------------------------------------------------ */
    /* --- Double precision min/max/sign injection --- */
    /* ------------------------------------------------------------------ */
    volatile double pos =  3.0;
    volatile double neg = -3.0;
    chk("fmin_d",   (pos < neg ? pos : neg) == -3.0);
    chk("fmax_d",   (pos > neg ? pos : neg) ==  3.0);

    /* FSGNJ.D: magnitude of pos, sign of neg -> -3.0 */
    chk("fsgnj_d",  hw_copysign(pos, neg) == -3.0);
    /* FSGNJN.D: magnitude of pos, negated sign of neg -> +3.0 */
    chk("fsgnjn_d", hw_ncopysign(pos, neg) == 3.0);
    /* FSGNJX.D: magnitude of pos, sign(pos) XOR sign(neg) -> -3.0 */
    chk("fsgnjx_d", hw_xcopysign(pos, neg) == -3.0);

    /* ------------------------------------------------------------------ */
    /* --- Large integer roundtrip via FCVT.D.L / FCVT.L.D --- */
    /* ------------------------------------------------------------------ */
    /* 2^53 is exactly representable as double */
    volatile int64_t exact53 = (int64_t)(1LL << 53);
    volatile double  d53     = (double)exact53;
    volatile int64_t back53  = (int64_t)d53;
    chk("fcvt_l_roundtrip_2_53", back53 == exact53);

    /* 2^53 + 1: NOT exactly representable -> rounds to 2^53 */
    volatile int64_t inexact = (int64_t)((1LL << 53) + 1);
    volatile double  dinexact = (double)inexact;
    chk("fcvt_d_l_inexact_representable",
        dinexact == (double)(1LL << 53) || dinexact == (double)inexact);

    log_write(NONE, "\n%d PASS  %d FAIL\n", g_pass, g_fail);
    log_close();
    return g_fail ? 1 : 0;
}
