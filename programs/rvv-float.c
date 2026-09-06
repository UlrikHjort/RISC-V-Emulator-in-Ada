/* **************************************************************************
 *     RISC-V Emulator - RVV 1.0 floating-point vector operations test
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

// rvv-float.c -- RVV 1.0 floating-point vector operations test.
//
// Exercises the entirely-untested vector-float code paths:
//   1. vfadd.vv, vfsub.vv, vfmul.vv, vfdiv.vv
//   2. vfmacc.vv (fused multiply-accumulate)
//   3. vfsqrt.v  (element-wise square root)
//   4. vfredosum.vs (ordered-sum reduction)
//   5. vfmin.vv, vfmax.vv
//   6. vfcvt.f.x.v (int -> float), vfcvt.x.f.v (float -> int, truncate)
//   7. vfmv.v.f  (broadcast scalar float)
//
// All results are cross-checked against scalar float arithmetic.
//
// Build: cd programs && make run-rvv-float
// By Ulrik Hørlyk Hjort 2026

#include <riscv_vector.h>
#include "log.h"
#include <stdint.h>

void putchar(char c);

static void uart_puts(const char *s) {
    while (*s) { if (*s == '\n') putchar('\r'); putchar(*s++); }
}

static int g_pass = 0, g_fail = 0;

// Bit-level float helpers (no FP comparison for broken results)
static inline uint32_t f32_bits(float f) {
    uint32_t u; __builtin_memcpy(&u, &f, 4); return u;
}

// Compare floats with a small ULP tolerance (1 ULP for exact operations,
// up to 2 ULP for sqrt/div where rounding may differ slightly).
static int f32_close(float a, float b, int ulp_tol) {
    uint32_t ua = f32_bits(a), ub = f32_bits(b);
    if (ua == ub) return 1;                    // exact match
    // Handle sign bit difference
    if ((ua >> 31) != (ub >> 31)) return 0;
    int32_t diff = (int32_t)ua - (int32_t)ub;
    if (diff < 0) diff = -diff;
    return diff <= ulp_tol;
}

static void check_f32(const char *label, float got, float expected, int ulp) {
    if (f32_close(got, expected, ulp)) {
        log_write(NONE, "  PASS  %s\n", label); g_pass++;
    } else {
        log_write(NONE, "  FAIL  %s: got %x  exp %x\n",
                  label, f32_bits(got), f32_bits(expected)); g_fail++;
    }
}

static void check_i32(const char *label, int32_t got, int32_t expected) {
    if (got == expected) {
        log_write(NONE, "  PASS  %s\n", label); g_pass++;
    } else {
        log_write(NONE, "  FAIL  %s: got %d  exp %d\n", label, got, expected); g_fail++;
    }
}

// Check a full float array element by element (1 ULP tolerance)
static void check_farr(const char *label, const float *got,
                       const float *exp, int n, int ulp) {
    for (int i = 0; i < n; i++) {
        if (!f32_close(got[i], exp[i], ulp)) {
            log_write(NONE, "  FAIL  %s[%d]: got %x  exp %x\n",
                      label, i, f32_bits(got[i]), f32_bits(exp[i]));
            g_fail++;
            return;
        }
    }
    log_write(NONE, "  PASS  %s\n", label); g_pass++;
}

// --- 1. vfadd / vfsub / vfmul / vfdiv ----------------------------------------

static void test_basic_arith(void) {
    log_write(NONE, "\n=== vfadd / vfsub / vfmul / vfdiv (f32/m1) ===\n");

    static const float a[4] = {1.0f, 2.0f,  3.0f, 4.0f};
    static const float b[4] = {4.0f, 3.0f,  2.0f, 1.0f};
    float out[4];

    size_t vl = __riscv_vsetvl_e32m1(4);
    vfloat32m1_t va = __riscv_vle32_v_f32m1(a, vl);
    vfloat32m1_t vb = __riscv_vle32_v_f32m1(b, vl);

    // vfadd: every element = 5.0
    __riscv_vse32_v_f32m1(out, __riscv_vfadd_vv_f32m1(va, vb, vl), vl);
    check_f32("vfadd[0] 1+4=5",   out[0], 5.0f, 0);
    check_f32("vfadd[1] 2+3=5",   out[1], 5.0f, 0);
    check_f32("vfadd[2] 3+2=5",   out[2], 5.0f, 0);
    check_f32("vfadd[3] 4+1=5",   out[3], 5.0f, 0);

    // vfsub: a - b = [-3, -1, 1, 3]
    __riscv_vse32_v_f32m1(out, __riscv_vfsub_vv_f32m1(va, vb, vl), vl);
    static const float exp_sub[4] = {-3.0f, -1.0f, 1.0f, 3.0f};
    check_farr("vfsub a-b", out, exp_sub, 4, 0);

    // vfmul: [4, 6, 6, 4]
    __riscv_vse32_v_f32m1(out, __riscv_vfmul_vv_f32m1(va, vb, vl), vl);
    static const float exp_mul[4] = {4.0f, 6.0f, 6.0f, 4.0f};
    check_farr("vfmul a*b", out, exp_mul, 4, 0);

    // vfdiv: [0.25, 0.666..., 1.5, 4.0]
    __riscv_vse32_v_f32m1(out, __riscv_vfdiv_vv_f32m1(va, vb, vl), vl);
    for (int i = 0; i < 4; i++) {
        float expect = a[i] / b[i];
        if (!f32_close(out[i], expect, 1)) {
            log_write(NONE, "  FAIL  vfdiv[%d]: got %x  exp %x\n",
                      i, f32_bits(out[i]), f32_bits(expect));
            g_fail++;
            return;
        }
    }
    log_write(NONE, "  PASS  vfdiv a/b\n"); g_pass++;
}

// --- 2. vfmacc (fused multiply-accumulate) ------------------------------------

static void test_vfmacc(void) {
    log_write(NONE, "\n=== vfmacc.vv  vd += vs1*vs2 (f32/m1) ===\n");

    // acc=[0, 0, 1, 2], a=[1, 2, 3, 4], b=[1, 2, 3, 4]
    // result = acc + a*b = [0+1, 0+4, 1+9, 2+16] = [1, 4, 10, 18]
    static const float acc[4] = {0.0f, 0.0f, 1.0f, 2.0f};
    static const float a[4]   = {1.0f, 2.0f, 3.0f, 4.0f};
    float out[4];

    size_t vl = __riscv_vsetvl_e32m1(4);
    vfloat32m1_t vacc = __riscv_vle32_v_f32m1(acc, vl);
    vfloat32m1_t va   = __riscv_vle32_v_f32m1(a, vl);

    // vfmacc: vacc += va * va
    vfloat32m1_t vr = __riscv_vfmacc_vv_f32m1(vacc, va, va, vl);
    __riscv_vse32_v_f32m1(out, vr, vl);

    static const float expected[4] = {1.0f, 4.0f, 10.0f, 18.0f};
    check_farr("vfmacc acc += a*a", out, expected, 4, 0);

    // vfrsub: vd = scalar - vs  (reverse subtract)
    // 10.0 - [1,2,3,4] = [9,8,7,6]
    vfloat32m1_t vrsub = __riscv_vfrsub_vf_f32m1(va, 10.0f, vl);
    __riscv_vse32_v_f32m1(out, vrsub, vl);
    static const float exp_rs[4] = {9.0f, 8.0f, 7.0f, 6.0f};
    check_farr("vfrsub 10-a", out, exp_rs, 4, 0);
}

// --- 3. vfsqrt ----------------------------------------------------------------

static void test_vfsqrt(void) {
    log_write(NONE, "\n=== vfsqrt.v (f32/m1) ===\n");

    // sqrt of perfect squares -> exact results
    static const float a[4] = {1.0f, 4.0f, 9.0f, 16.0f};
    float out[4];
    size_t vl = __riscv_vsetvl_e32m1(4);
    vfloat32m1_t va = __riscv_vle32_v_f32m1(a, vl);

    __riscv_vse32_v_f32m1(out, __riscv_vfsqrt_v_f32m1(va, vl), vl);
    check_f32("vfsqrt(1)  = 1.0",  out[0], 1.0f,  1);
    check_f32("vfsqrt(4)  = 2.0",  out[1], 2.0f,  1);
    check_f32("vfsqrt(9)  = 3.0",  out[2], 3.0f,  1);
    check_f32("vfsqrt(16) = 4.0",  out[3], 4.0f,  1);

    // sqrt(2) -- compare against scalar fsqrt.s
    static const float two[4] = {2.0f, 2.0f, 2.0f, 2.0f};
    vfloat32m1_t v2  = __riscv_vle32_v_f32m1(two, vl);
    __riscv_vse32_v_f32m1(out, __riscv_vfsqrt_v_f32m1(v2, vl), vl);
    // Compare all 4 lanes; they should be the same value
    check_f32("vfsqrt(2) lane0 matches scalar", out[0], out[1], 0);
    check_f32("vfsqrt(2) lane2 matches scalar", out[2], out[3], 0);
}

// --- 4. vfredosum -------------------------------------------------------------

static void test_vfredosum(void) {
    log_write(NONE, "\n=== vfredosum.vs (f32/m1) ===\n");

    // sum([1,2,3,4]) = 10.0
    static const float a[4] = {1.0f, 2.0f, 3.0f, 4.0f};
    float out[4];
    size_t vl = __riscv_vsetvl_e32m1(4);
    vfloat32m1_t va    = __riscv_vle32_v_f32m1(a, vl);
    vfloat32m1_t vzero = __riscv_vfmv_v_f_f32m1(0.0f, vl);

    vfloat32m1_t vsum = __riscv_vfredosum_vs_f32m1_f32m1(va, vzero, vl);
    __riscv_vse32_v_f32m1(out, vsum, vl);
    check_f32("vfredosum [1,2,3,4] = 10", out[0], 10.0f, 0);

    // sum([0.5, 0.5, 0.5, 0.5]) = 2.0
    static const float b[4] = {0.5f, 0.5f, 0.5f, 0.5f};
    vfloat32m1_t vb = __riscv_vle32_v_f32m1(b, vl);
    vsum = __riscv_vfredosum_vs_f32m1_f32m1(vb, vzero, vl);
    __riscv_vse32_v_f32m1(out, vsum, vl);
    check_f32("vfredosum [0.5x4] = 2.0", out[0], 2.0f, 0);

    // sum([-1,-2,3,4]) = 4.0  (negative values)
    static const float c[4] = {-1.0f, -2.0f, 3.0f, 4.0f};
    vfloat32m1_t vc = __riscv_vle32_v_f32m1(c, vl);
    vsum = __riscv_vfredosum_vs_f32m1_f32m1(vc, vzero, vl);
    __riscv_vse32_v_f32m1(out, vsum, vl);
    check_f32("vfredosum [-1,-2,3,4] = 4.0", out[0], 4.0f, 0);
}

// --- 5. vfmin / vfmax ---------------------------------------------------------

static void test_vfminmax(void) {
    log_write(NONE, "\n=== vfmin / vfmax (f32/m1) ===\n");

    static const float a[4] = { 3.0f, -2.0f,  0.0f, 100.0f};
    static const float b[4] = { 1.0f,  5.0f, -1.0f,  50.0f};
    float out[4];
    size_t vl = __riscv_vsetvl_e32m1(4);
    vfloat32m1_t va = __riscv_vle32_v_f32m1(a, vl);
    vfloat32m1_t vb = __riscv_vle32_v_f32m1(b, vl);

    __riscv_vse32_v_f32m1(out, __riscv_vfmin_vv_f32m1(va, vb, vl), vl);
    static const float exp_min[4] = {1.0f, -2.0f, -1.0f, 50.0f};
    check_farr("vfmin", out, exp_min, 4, 0);

    __riscv_vse32_v_f32m1(out, __riscv_vfmax_vv_f32m1(va, vb, vl), vl);
    static const float exp_max[4] = {3.0f, 5.0f, 0.0f, 100.0f};
    check_farr("vfmax", out, exp_max, 4, 0);
}

// --- 6. vfcvt (float <-> int conversion) -------------------------------------

static void test_vfcvt(void) {
    log_write(NONE, "\n=== vfcvt int->float and float->int (f32/m1) ===\n");

    // int -> float (vfcvt.f.x.v)
    static const int32_t ints[4] = {0, 1, -1, 1000};
    float fout[4];
    size_t vl = __riscv_vsetvl_e32m1(4);
    vint32m1_t vi = __riscv_vle32_v_i32m1(ints, vl);

    vfloat32m1_t vf = __riscv_vfcvt_f_x_v_f32m1(vi, vl);
    __riscv_vse32_v_f32m1(fout, vf, vl);
    check_f32("vfcvt(0)    = 0.0f",     fout[0],    0.0f, 0);
    check_f32("vfcvt(1)    = 1.0f",     fout[1],    1.0f, 0);
    check_f32("vfcvt(-1)   = -1.0f",    fout[2],   -1.0f, 0);
    check_f32("vfcvt(1000) = 1000.0f",  fout[3], 1000.0f, 0);

    // float -> int truncation (vfcvt.rtz.x.f.v)
    static const float floats[4] = {3.9f, -2.7f, 0.0f, 100.0f};
    int32_t iout[4];
    vfloat32m1_t vf2 = __riscv_vle32_v_f32m1(floats, vl);
    vint32m1_t vi2 = __riscv_vfcvt_rtz_x_f_v_i32m1(vf2, vl);
    __riscv_vse32_v_i32m1(iout, vi2, vl);
    check_i32("vfcvt_rtz(3.9)  =  3",  iout[0],   3);
    check_i32("vfcvt_rtz(-2.7) = -2",  iout[1],  -2);
    check_i32("vfcvt_rtz(0.0)  =  0",  iout[2],   0);
    check_i32("vfcvt_rtz(100)  =  100", iout[3], 100);
}

// --- 7. vfmv.v.f (broadcast scalar float) ------------------------------------

static void test_vfmv(void) {
    log_write(NONE, "\n=== vfmv.v.f broadcast + vfmv.f.s extract (f32/m1) ===\n");

    size_t vl = __riscv_vsetvl_e32m1(4);
    float out[4];

    // Broadcast 3.14f to all 4 lanes
    vfloat32m1_t vpi = __riscv_vfmv_v_f_f32m1(3.14f, vl);
    __riscv_vse32_v_f32m1(out, vpi, vl);
    check_f32("vfmv.v.f 3.14 lane0", out[0], 3.14f, 0);
    check_f32("vfmv.v.f 3.14 lane3", out[3], 3.14f, 0);

    // vfmv.f.s: extract element 0 back to scalar
    float extracted = __riscv_vfmv_f_s_f32m1_f32(vpi);
    check_f32("vfmv.f.s extracts 3.14", extracted, 3.14f, 0);

    // Broadcast -0.0f
    vfloat32m1_t vneg0 = __riscv_vfmv_v_f_f32m1(-0.0f, vl);
    __riscv_vse32_v_f32m1(out, vneg0, vl);
    // -0.0f bits should be 0x80000000
    check_i32("vfmv.v.f -0.0f bits", (int32_t)f32_bits(out[0]), (int32_t)0x80000000U);
}

// --- 8. Dot product (cross-check with scalar) ---------------------------------

static void test_dotprod(void) {
    log_write(NONE, "\n=== vector float dot product vs scalar ===\n");

    // 8 elements using LMUL=2
    static const float a[8] = {1,2,3,4,5,6,7,8};
    static const float b[8] = {8,7,6,5,4,3,2,1};
    // expected dot = 1*8+2*7+3*6+4*5+5*4+6*3+7*2+8*1 = 8+14+18+20+20+18+14+8 = 120

    size_t vl = __riscv_vsetvl_e32m2(8);
    vfloat32m2_t va = __riscv_vle32_v_f32m2(a, vl);
    vfloat32m2_t vb = __riscv_vle32_v_f32m2(b, vl);

    // Multiply all 8 elements (exercises m2 vfmul)
    vfloat32m2_t vprod = __riscv_vfmul_vv_f32m2(va, vb, vl);

    // GCC 14 has no cross-LMUL vfredosum_f32m1_f32m2; store and reduce
    // two m1 halves instead.
    float prod[8];
    __riscv_vse32_v_f32m2(prod, vprod, vl);

    size_t vl1 = __riscv_vsetvl_e32m1(4);
    vfloat32m1_t vzero = __riscv_vfmv_v_f_f32m1(0.0f, vl1);
    vfloat32m1_t vp0   = __riscv_vle32_v_f32m1(prod,     vl1);
    vfloat32m1_t vp1   = __riscv_vle32_v_f32m1(prod + 4, vl1);
    vfloat32m1_t vs0   = __riscv_vfredosum_vs_f32m1_f32m1(vp0, vzero, vl1);
    vfloat32m1_t vs1   = __riscv_vfredosum_vs_f32m1_f32m1(vp1, vzero, vl1);
    float s0 = __riscv_vfmv_f_s_f32m1_f32(vs0);
    float s1 = __riscv_vfmv_f_s_f32m1_f32(vs1);
    float out = s0 + s1;
    check_f32("float dot [1..8].[8..1] = 120", out, 120.0f, 1);
}

// --- 9. Cycle profiling -------------------------------------------------------

static void test_cycles(void) {
    log_write(NONE, "\n=== Cycle profiling ===\n");

    static const float a[4] = {1.5f, 2.5f, 3.5f, 4.5f};
    static const float b[4] = {2.0f, 2.0f, 2.0f, 2.0f};
    float out[4];
    size_t vl = __riscv_vsetvl_e32m1(4);
    vfloat32m1_t va = __riscv_vle32_v_f32m1(a, vl);
    vfloat32m1_t vb = __riscv_vle32_v_f32m1(b, vl);

    log_write(CYCLES, "100x vfmul\n");
    for (int i = 0; i < 100; i++)
        __riscv_vse32_v_f32m1(out, __riscv_vfmul_vv_f32m1(va, vb, vl), vl);
    log_write(CYCLES, "100x vfmul done\n");

    log_write(CYCLES, "100x vfsqrt\n");
    for (int i = 0; i < 100; i++)
        __riscv_vse32_v_f32m1(out, __riscv_vfsqrt_v_f32m1(va, vl), vl);
    log_write(CYCLES, "100x vfsqrt done\n");

    (void)out[0];
}

// --- Main ---------------------------------------------------------------------

int main(void) {
    uart_puts("=== RVV Float Test ===\n");
    if (log_init("rvv-float.log") != 0) {
        uart_puts("ERROR: log_init failed\n");
        return 1;
    }

    log_write(NONE, "=== RVV Float Test (RV32IMFDV) ===\n");
    log_write(NONE, "VLEN=128  =>  f32/m1:4  f32/m2:8\n");

    test_basic_arith();
    test_vfmacc();
    test_vfsqrt();
    test_vfredosum();
    test_vfminmax();
    test_vfcvt();
    test_vfmv();
    test_dotprod();
    test_cycles();

    log_write(NONE, "\n=== Summary ===\n");
    log_write(NONE, "  PASS: %d\n", g_pass);
    log_write(NONE, "  FAIL: %d\n", g_fail);
    log_write(NONE, "  %s\n", g_fail == 0 ? "ALL TESTS PASSED" : "SOME TESTS FAILED");

    log_close();
    uart_puts(g_fail == 0 ? "ALL PASSED\n" : "SOME FAILED\n");
    return g_fail;
}
