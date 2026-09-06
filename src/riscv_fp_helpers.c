/****************************************************************************
--             RISC-V Emulator - RISC-V FPU Helpers
--
--           Copyright (C) 2026 By Ulrik Hørlyk Hjort
--
-- Permission is hereby granted, free of charge, to any person obtaining
-- a copy of this software and associated documentation files (the
-- "Software"), to deal in the Software without restriction, including
-- without limitation the rights to use, copy, modify, merge, publish,
-- distribute, sublicense, and/or sell copies of the Software, and to
-- permit persons to whom the Software is furnished to do so, subject to
-- the following conditions:
--
-- The above copyright notice and this permission notice shall be
-- included in all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
-- EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
-- MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
-- NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
-- LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
-- OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
-- WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
-- ***************************************************************************/
/*
 * RISC-V FPU Helpers - C wrappers for IEEE 754 operations
 * with proper rounding mode control and exception flag reporting.
 */

#include <fenv.h>
#include <math.h>
#include <stdint.h>
#include <string.h>

#pragma STDC FENV_ACCESS ON

/* RISC-V rounding modes */
#define RM_RNE 0
#define RM_RTZ 1
#define RM_RDN 2
#define RM_RUP 3
#define RM_RMM 4

static int rm_to_c[] = {
    FE_TONEAREST,   /* RNE = 0 */
    FE_TOWARDZERO,  /* RTZ = 1 */
    FE_DOWNWARD,    /* RDN = 2 */
    FE_UPWARD,      /* RUP = 3 */
    FE_TONEAREST    /* RMM = 4 - handled specially */
};

static uint32_t get_riscv_flags(void) {
    uint32_t flags = 0;
    if (fetestexcept(FE_INEXACT))   flags |= 1;
    if (fetestexcept(FE_UNDERFLOW)) flags |= 2;
    if (fetestexcept(FE_OVERFLOW))  flags |= 4;
    if (fetestexcept(FE_DIVBYZERO)) flags |= 8;
    if (fetestexcept(FE_INVALID))   flags |= 16;
    return flags;
}

static inline float u32_to_f(uint32_t x) {
    float f; memcpy(&f, &x, 4); return f;
}

static inline uint32_t f_to_u32(float f) {
    uint32_t x; memcpy(&x, &f, 4); return x;
}

static inline double u64_to_d(uint64_t x) {
    double d; memcpy(&d, &x, 8); return d;
}

static inline uint64_t d_to_u64(double d) {
    uint64_t x; memcpy(&x, &d, 8); return x;
}

static void setup_rm(int rm) {
    feclearexcept(FE_ALL_EXCEPT);
    /* The Ada side passes Rounding_Mode'Pos, where DYN is 5 and would index
       past the table.  Write_FCSR/Write_FRM currently prevent that, but keep
       the lookup in bounds so a future change cannot turn it into UB. */
    if (rm < 0 || rm >= (int)(sizeof(rm_to_c) / sizeof(rm_to_c[0])))
        rm = RM_RNE;
    fesetround(rm_to_c[rm]);
}

/*
 * RMM (Round to Nearest, ties to Max Magnitude) adjustment.
 *
 * RMM is the same as RNE (Round to Nearest, ties to Even) for all non-tie
 * cases. They differ ONLY at exact tie points (midpoint between two adjacent
 * representable floats):
 *   - RNE picks the one with even mantissa LSB
 *   - RMM picks the one with larger absolute magnitude
 *
 * Strategy: compute with RNE first (correct for non-ties). Then use double
 * precision to detect ties and adjust if needed.
 */
static uint32_t rmm_adjust(float rne, double exact) {
    uint32_t rne_bits = f_to_u32(rne);

    /* Odd mantissa LSB means RNE didn't pick "even" - can't be a tie */
    if (rne_bits & 1) return rne_bits;

    /* Even mantissa - might be a tie resolved to even.
     * Check if the exact result is at the midpoint between rne and
     * the adjacent float. */
    float other;
    if (exact > (double)rne) {
        other = nextafterf(rne, INFINITY);
    } else if (exact < (double)rne) {
        other = nextafterf(rne, -INFINITY);
    } else {
        /* exact == (double)rne: result is exact at double precision,
         * so it's not a float tie point */
        return rne_bits;
    }

    double mid = ((double)rne + (double)other) / 2.0;
    if (exact == mid && fabsf(other) > fabsf(rne)) {
        return f_to_u32(other);
    }
    return rne_bits;
}

/* ========== RMM helpers for each operation ========== */
/* These use __attribute__((noinline)) to prevent inlining issues */

static uint32_t __attribute__((noinline))
rmm_add(uint32_t a, uint32_t b, uint32_t *flags) {
    float fa = u32_to_f(a), fb = u32_to_f(b);
    fesetround(FE_TONEAREST); feclearexcept(FE_ALL_EXCEPT);
    volatile float rne = fa + fb;
    *flags = get_riscv_flags();
    if (!(*flags & 1) || isnanf(rne) || isinff(rne)) return f_to_u32(rne);
    double exact = (double)fa + (double)fb;
    return rmm_adjust(rne, exact);
}

static uint32_t __attribute__((noinline))
rmm_sub(uint32_t a, uint32_t b, uint32_t *flags) {
    float fa = u32_to_f(a), fb = u32_to_f(b);
    fesetround(FE_TONEAREST); feclearexcept(FE_ALL_EXCEPT);
    volatile float rne = fa - fb;
    *flags = get_riscv_flags();
    if (!(*flags & 1) || isnanf(rne) || isinff(rne)) return f_to_u32(rne);
    double exact = (double)fa - (double)fb;
    return rmm_adjust(rne, exact);
}

static uint32_t __attribute__((noinline))
rmm_mul(uint32_t a, uint32_t b, uint32_t *flags) {
    float fa = u32_to_f(a), fb = u32_to_f(b);
    fesetround(FE_TONEAREST); feclearexcept(FE_ALL_EXCEPT);
    volatile float rne = fa * fb;
    *flags = get_riscv_flags();
    if (!(*flags & 1) || isnanf(rne) || isinff(rne)) return f_to_u32(rne);
    double exact = (double)fa * (double)fb;
    return rmm_adjust(rne, exact);
}

static uint32_t __attribute__((noinline))
rmm_div(uint32_t a, uint32_t b, uint32_t *flags) {
    float fa = u32_to_f(a), fb = u32_to_f(b);
    fesetround(FE_TONEAREST); feclearexcept(FE_ALL_EXCEPT);
    volatile float rne = fa / fb;
    *flags = get_riscv_flags();
    if (!(*flags & 1) || isnanf(rne) || isinff(rne)) return f_to_u32(rne);
    /* For div, (double)fa / (double)fb gives sufficient precision
     * for tie detection (53-bit mantissa vs 25-bit need) */
    double exact = (double)fa / (double)fb;
    return rmm_adjust(rne, exact);
}

static uint32_t __attribute__((noinline))
rmm_sqrt(uint32_t a, uint32_t *flags) {
    float fa = u32_to_f(a);
    fesetround(FE_TONEAREST); feclearexcept(FE_ALL_EXCEPT);
    volatile float rne = sqrtf(fa);
    *flags = get_riscv_flags();
    if (!(*flags & 1) || isnanf(rne) || isinff(rne)) return f_to_u32(rne);
    double exact = sqrt((double)fa);
    return rmm_adjust(rne, exact);
}

static uint32_t __attribute__((noinline))
rmm_fmadd(uint32_t a, uint32_t b, uint32_t c, uint32_t *flags) {
    float fa = u32_to_f(a), fb = u32_to_f(b), fc = u32_to_f(c);
    fesetround(FE_TONEAREST); feclearexcept(FE_ALL_EXCEPT);
    volatile float rne = fmaf(fa, fb, fc);
    *flags = get_riscv_flags();
    if (!(*flags & 1) || isnanf(rne) || isinff(rne)) return f_to_u32(rne);
    /* Use double FMA for tie detection. The exact product of two floats
     * fits in double (48 bits < 53 bits), and the single-rounded double
     * FMA result has enough precision for tie detection. */
    double exact = fma((double)fa, (double)fb, (double)fc);
    return rmm_adjust(rne, exact);
}

static uint32_t __attribute__((noinline))
rmm_i2f(int32_t a, uint32_t *flags) {
    fesetround(FE_TONEAREST); feclearexcept(FE_ALL_EXCEPT);
    volatile float rne = (float)a;
    *flags = get_riscv_flags();
    if (!(*flags & 1)) return f_to_u32(rne);
    /* int32 to float: the exact value is the integer itself */
    double exact = (double)a;
    return rmm_adjust(rne, exact);
}

static uint32_t __attribute__((noinline))
rmm_u2f(uint32_t a, uint32_t *flags) {
    fesetround(FE_TONEAREST); feclearexcept(FE_ALL_EXCEPT);
    volatile float rne = (float)a;
    *flags = get_riscv_flags();
    if (!(*flags & 1)) return f_to_u32(rne);
    double exact = (double)a;
    return rmm_adjust(rne, exact);
}

/* ========== Single-precision arithmetic ========== */

uint32_t riscv_fp_add_s(uint32_t a, uint32_t b, int rm, uint32_t *flags) {
    if (rm == RM_RMM) {
        return rmm_add(a, b, flags);
    }
    float fa = u32_to_f(a), fb = u32_to_f(b);
    setup_rm(rm);
    volatile float fr = fa + fb;
    *flags = get_riscv_flags();
    fesetround(FE_TONEAREST);
    return f_to_u32(fr);
}

uint32_t riscv_fp_sub_s(uint32_t a, uint32_t b, int rm, uint32_t *flags) {
    if (rm == RM_RMM) {
        return rmm_sub(a, b, flags);
    }
    float fa = u32_to_f(a), fb = u32_to_f(b);
    setup_rm(rm);
    volatile float fr = fa - fb;
    *flags = get_riscv_flags();
    fesetround(FE_TONEAREST);
    return f_to_u32(fr);
}

uint32_t riscv_fp_mul_s(uint32_t a, uint32_t b, int rm, uint32_t *flags) {
    if (rm == RM_RMM) {
        return rmm_mul(a, b, flags);
    }
    float fa = u32_to_f(a), fb = u32_to_f(b);
    setup_rm(rm);
    volatile float fr = fa * fb;
    *flags = get_riscv_flags();
    fesetround(FE_TONEAREST);
    return f_to_u32(fr);
}

uint32_t riscv_fp_div_s(uint32_t a, uint32_t b, int rm, uint32_t *flags) {
    if (rm == RM_RMM) {
        return rmm_div(a, b, flags);
    }
    float fa = u32_to_f(a), fb = u32_to_f(b);
    setup_rm(rm);
    volatile float fr = fa / fb;
    *flags = get_riscv_flags();
    fesetround(FE_TONEAREST);
    return f_to_u32(fr);
}

uint32_t riscv_fp_sqrt_s(uint32_t a, int rm, uint32_t *flags) {
    if (rm == RM_RMM) {
        return rmm_sqrt(a, flags);
    }
    float fa = u32_to_f(a);
    setup_rm(rm);
    volatile float fr = sqrtf(fa);
    *flags = get_riscv_flags();
    fesetround(FE_TONEAREST);
    return f_to_u32(fr);
}

uint32_t riscv_fp_fmadd_s(uint32_t a, uint32_t b, uint32_t c,
                           int rm, uint32_t *flags) {
    if (rm == RM_RMM) {
        return rmm_fmadd(a, b, c, flags);
    }
    float fa = u32_to_f(a), fb = u32_to_f(b), fc = u32_to_f(c);
    setup_rm(rm);
    volatile float fr = fmaf(fa, fb, fc);
    *flags = get_riscv_flags();
    fesetround(FE_TONEAREST);
    return f_to_u32(fr);
}

/* Round float to integer-valued float */
uint32_t riscv_fp_round_s(uint32_t a, int rm, uint32_t *flags) {
    float fa = u32_to_f(a);
    float rounded;
    switch (rm) {
        case RM_RNE: rounded = nearbyintf(fa); break;
        case RM_RTZ: rounded = truncf(fa); break;
        case RM_RDN: rounded = floorf(fa); break;
        case RM_RUP: rounded = ceilf(fa); break;
        case RM_RMM: rounded = roundf(fa); break;
        default: rounded = nearbyintf(fa); break;
    }
    *flags = (rounded != fa) ? 1 : 0;
    return f_to_u32(rounded);
}

/* Integer-to-float conversions */
uint32_t riscv_fp_i2f_s(int32_t a, int rm, uint32_t *flags) {
    if (rm == RM_RMM) {
        return rmm_i2f(a, flags);
    }
    setup_rm(rm);
    volatile float fr = (float)a;
    *flags = get_riscv_flags();
    fesetround(FE_TONEAREST);
    return f_to_u32(fr);
}

uint32_t riscv_fp_u2f_s(uint32_t a, int rm, uint32_t *flags) {
    if (rm == RM_RMM) {
        return rmm_u2f(a, flags);
    }
    setup_rm(rm);
    volatile float fr = (float)a;
    *flags = get_riscv_flags();
    fesetround(FE_TONEAREST);
    return f_to_u32(fr);
}

/* ========== RMM helpers for double-precision ========== */
/*
 * For doubles, we can't use a higher-precision type to detect ties.
 * Strategy: compute with both FE_UPWARD and FE_DOWNWARD. If they give the
 * same result, it's exact (no tie). If they differ, the true result lies
 * between them. Compute with FE_TONEAREST (=RNE) and check: if RNE equals
 * one bound, it's not at the midpoint, so RNE is correct. If RNE could be
 * a tie (even mantissa LSB), pick the value with larger magnitude.
 */
static uint64_t rmm_adjust_d(double rne, double lo, double hi) {
    uint64_t rne_bits = d_to_u64(rne);
    /* If lo == hi, result is exact, no tie possible */
    if (lo == hi) return rne_bits;
    /* lo != hi means rounding occurred. RNE picked one of them or
     * the midpoint. For RMM, if it's a tie, pick larger magnitude. */
    if (rne == lo || rne == hi) {
        /* RNE didn't land at the midpoint - it's not a tie */
        return rne_bits;
    }
    /* RNE result differs from both bounds - shouldn't happen for
     * well-behaved IEEE, but fall through to magnitude check */
    if (!(rne_bits & 1)) {
        /* Even mantissa LSB - might be RNE's tie-to-even.
         * Pick larger magnitude between lo and hi. */
        if (fabs(hi) > fabs(lo))
            return d_to_u64(hi);
        else
            return d_to_u64(lo);
    }
    return rne_bits;
}

static uint64_t __attribute__((noinline))
rmm_add_d(uint64_t a, uint64_t b, uint32_t *flags) {
    double fa = u64_to_d(a), fb = u64_to_d(b);
    fesetround(FE_TONEAREST); feclearexcept(FE_ALL_EXCEPT);
    volatile double rne = fa + fb;
    *flags = get_riscv_flags();
    if (!(*flags & 1) || isnan(rne) || isinf(rne)) return d_to_u64(rne);
    feclearexcept(FE_ALL_EXCEPT); fesetround(FE_DOWNWARD);
    volatile double lo = fa + fb;
    feclearexcept(FE_ALL_EXCEPT); fesetround(FE_UPWARD);
    volatile double hi = fa + fb;
    return rmm_adjust_d(rne, lo, hi);
}

static uint64_t __attribute__((noinline))
rmm_sub_d(uint64_t a, uint64_t b, uint32_t *flags) {
    double fa = u64_to_d(a), fb = u64_to_d(b);
    fesetround(FE_TONEAREST); feclearexcept(FE_ALL_EXCEPT);
    volatile double rne = fa - fb;
    *flags = get_riscv_flags();
    if (!(*flags & 1) || isnan(rne) || isinf(rne)) return d_to_u64(rne);
    feclearexcept(FE_ALL_EXCEPT); fesetround(FE_DOWNWARD);
    volatile double lo = fa - fb;
    feclearexcept(FE_ALL_EXCEPT); fesetround(FE_UPWARD);
    volatile double hi = fa - fb;
    return rmm_adjust_d(rne, lo, hi);
}

static uint64_t __attribute__((noinline))
rmm_mul_d(uint64_t a, uint64_t b, uint32_t *flags) {
    double fa = u64_to_d(a), fb = u64_to_d(b);
    fesetround(FE_TONEAREST); feclearexcept(FE_ALL_EXCEPT);
    volatile double rne = fa * fb;
    *flags = get_riscv_flags();
    if (!(*flags & 1) || isnan(rne) || isinf(rne)) return d_to_u64(rne);
    feclearexcept(FE_ALL_EXCEPT); fesetround(FE_DOWNWARD);
    volatile double lo = fa * fb;
    feclearexcept(FE_ALL_EXCEPT); fesetround(FE_UPWARD);
    volatile double hi = fa * fb;
    return rmm_adjust_d(rne, lo, hi);
}

static uint64_t __attribute__((noinline))
rmm_div_d(uint64_t a, uint64_t b, uint32_t *flags) {
    double fa = u64_to_d(a), fb = u64_to_d(b);
    fesetround(FE_TONEAREST); feclearexcept(FE_ALL_EXCEPT);
    volatile double rne = fa / fb;
    *flags = get_riscv_flags();
    if (!(*flags & 1) || isnan(rne) || isinf(rne)) return d_to_u64(rne);
    feclearexcept(FE_ALL_EXCEPT); fesetround(FE_DOWNWARD);
    volatile double lo = fa / fb;
    feclearexcept(FE_ALL_EXCEPT); fesetround(FE_UPWARD);
    volatile double hi = fa / fb;
    return rmm_adjust_d(rne, lo, hi);
}

static uint64_t __attribute__((noinline))
rmm_sqrt_d(uint64_t a, uint32_t *flags) {
    double fa = u64_to_d(a);
    fesetround(FE_TONEAREST); feclearexcept(FE_ALL_EXCEPT);
    volatile double rne = sqrt(fa);
    *flags = get_riscv_flags();
    if (!(*flags & 1) || isnan(rne) || isinf(rne)) return d_to_u64(rne);
    feclearexcept(FE_ALL_EXCEPT); fesetround(FE_DOWNWARD);
    volatile double lo = sqrt(fa);
    feclearexcept(FE_ALL_EXCEPT); fesetround(FE_UPWARD);
    volatile double hi = sqrt(fa);
    return rmm_adjust_d(rne, lo, hi);
}

static uint64_t __attribute__((noinline))
rmm_fmadd_d(uint64_t a, uint64_t b, uint64_t c, uint32_t *flags) {
    double fa = u64_to_d(a), fb = u64_to_d(b), fc = u64_to_d(c);
    fesetround(FE_TONEAREST); feclearexcept(FE_ALL_EXCEPT);
    volatile double rne = fma(fa, fb, fc);
    *flags = get_riscv_flags();
    if (!(*flags & 1) || isnan(rne) || isinf(rne)) return d_to_u64(rne);
    feclearexcept(FE_ALL_EXCEPT); fesetround(FE_DOWNWARD);
    volatile double lo = fma(fa, fb, fc);
    feclearexcept(FE_ALL_EXCEPT); fesetround(FE_UPWARD);
    volatile double hi = fma(fa, fb, fc);
    return rmm_adjust_d(rne, lo, hi);
}

static uint64_t __attribute__((noinline))
rmm_i2d(int32_t a, uint32_t *flags) {
    fesetround(FE_TONEAREST); feclearexcept(FE_ALL_EXCEPT);
    volatile double rne = (double)a;
    *flags = get_riscv_flags();
    /* int32 to double is always exact (53-bit mantissa > 32-bit int) */
    return d_to_u64(rne);
}

static uint64_t __attribute__((noinline))
rmm_u2d(uint32_t a, uint32_t *flags) {
    fesetround(FE_TONEAREST); feclearexcept(FE_ALL_EXCEPT);
    volatile double rne = (double)a;
    *flags = get_riscv_flags();
    /* uint32 to double is always exact */
    return d_to_u64(rne);
}

/* ========== Double-precision arithmetic ========== */

uint64_t riscv_fp_add_d(uint64_t a, uint64_t b, int rm, uint32_t *flags) {
    if (rm == RM_RMM) {
        return rmm_add_d(a, b, flags);
    }
    double fa = u64_to_d(a), fb = u64_to_d(b);
    setup_rm(rm);
    volatile double fr = fa + fb;
    *flags = get_riscv_flags();
    fesetround(FE_TONEAREST);
    return d_to_u64(fr);
}

uint64_t riscv_fp_sub_d(uint64_t a, uint64_t b, int rm, uint32_t *flags) {
    if (rm == RM_RMM) {
        return rmm_sub_d(a, b, flags);
    }
    double fa = u64_to_d(a), fb = u64_to_d(b);
    setup_rm(rm);
    volatile double fr = fa - fb;
    *flags = get_riscv_flags();
    fesetround(FE_TONEAREST);
    return d_to_u64(fr);
}

uint64_t riscv_fp_mul_d(uint64_t a, uint64_t b, int rm, uint32_t *flags) {
    if (rm == RM_RMM) {
        return rmm_mul_d(a, b, flags);
    }
    double fa = u64_to_d(a), fb = u64_to_d(b);
    setup_rm(rm);
    volatile double fr = fa * fb;
    *flags = get_riscv_flags();
    fesetround(FE_TONEAREST);
    return d_to_u64(fr);
}

uint64_t riscv_fp_div_d(uint64_t a, uint64_t b, int rm, uint32_t *flags) {
    if (rm == RM_RMM) {
        return rmm_div_d(a, b, flags);
    }
    double fa = u64_to_d(a), fb = u64_to_d(b);
    setup_rm(rm);
    volatile double fr = fa / fb;
    *flags = get_riscv_flags();
    fesetround(FE_TONEAREST);
    return d_to_u64(fr);
}

uint64_t riscv_fp_sqrt_d(uint64_t a, int rm, uint32_t *flags) {
    if (rm == RM_RMM) {
        return rmm_sqrt_d(a, flags);
    }
    double fa = u64_to_d(a);
    setup_rm(rm);
    volatile double fr = sqrt(fa);
    *flags = get_riscv_flags();
    fesetround(FE_TONEAREST);
    return d_to_u64(fr);
}

uint64_t riscv_fp_fmadd_d(uint64_t a, uint64_t b, uint64_t c,
                           int rm, uint32_t *flags) {
    if (rm == RM_RMM) {
        return rmm_fmadd_d(a, b, c, flags);
    }
    double fa = u64_to_d(a), fb = u64_to_d(b), fc = u64_to_d(c);
    setup_rm(rm);
    volatile double fr = fma(fa, fb, fc);
    *flags = get_riscv_flags();
    fesetround(FE_TONEAREST);
    return d_to_u64(fr);
}

/* Round double to integer-valued double */
uint64_t riscv_fp_round_d(uint64_t a, int rm, uint32_t *flags) {
    double fa = u64_to_d(a);
    double rounded;
    switch (rm) {
        case RM_RNE: rounded = nearbyint(fa); break;
        case RM_RTZ: rounded = trunc(fa); break;
        case RM_RDN: rounded = floor(fa); break;
        case RM_RUP: rounded = ceil(fa); break;
        case RM_RMM: rounded = round(fa); break;
        default: rounded = nearbyint(fa); break;
    }
    *flags = (rounded != fa) ? 1 : 0;
    return d_to_u64(rounded);
}

/* Integer-to-double conversions */
uint64_t riscv_fp_i2d(int32_t a, int rm, uint32_t *flags) {
    if (rm == RM_RMM) {
        return rmm_i2d(a, flags);
    }
    setup_rm(rm);
    volatile double fr = (double)a;
    *flags = get_riscv_flags();
    fesetround(FE_TONEAREST);
    return d_to_u64(fr);
}

/* Double-to-single conversion with rounding mode */
static uint32_t __attribute__((noinline))
rmm_d2s(uint64_t a, uint32_t *flags) {
    double fa = u64_to_d(a);
    fesetround(FE_TONEAREST); feclearexcept(FE_ALL_EXCEPT);
    volatile float rne = (float)fa;
    *flags = get_riscv_flags();
    if (!(*flags & 1) || isnanf(rne) || isinff(rne)) return f_to_u32(rne);
    /* Use double precision to detect ties for single-precision result */
    double exact = fa;
    return rmm_adjust(rne, exact);
}

uint32_t riscv_fp_d2s(uint64_t a, int rm, uint32_t *flags) {
    if (rm == RM_RMM) {
        return rmm_d2s(a, flags);
    }
    double fa = u64_to_d(a);
    setup_rm(rm);
    volatile float fr = (float)fa;
    *flags = get_riscv_flags();
    fesetround(FE_TONEAREST);
    return f_to_u32(fr);
}

uint64_t riscv_fp_u2d(uint32_t a, int rm, uint32_t *flags) {
    if (rm == RM_RMM) {
        return rmm_u2d(a, flags);
    }
    setup_rm(rm);
    volatile double fr = (double)a;
    *flags = get_riscv_flags();
    fesetround(FE_TONEAREST);
    return d_to_u64(fr);
}

/* -------------------------------------------------------------------------
 * RV64 64-bit integer <-> double conversions
 * ------------------------------------------------------------------------- */

/* int64 to double */
uint64_t riscv_fp_l2d(int64_t a, int rm, uint32_t *flags) {
    setup_rm(rm);
    volatile double fr = (double)a;
    *flags = get_riscv_flags();
    fesetround(FE_TONEAREST);
    return d_to_u64(fr);
}

/* uint64 to double */
uint64_t riscv_fp_lu2d(uint64_t a, int rm, uint32_t *flags) {
    setup_rm(rm);
    volatile double fr = (double)a;
    *flags = get_riscv_flags();
    fesetround(FE_TONEAREST);
    return d_to_u64(fr);
}

/* int64 to single */
uint32_t riscv_fp_l2s(int64_t a, int rm, uint32_t *flags) {
    setup_rm(rm);
    volatile float fr = (float)a;
    *flags = get_riscv_flags();
    fesetround(FE_TONEAREST);
    return f_to_u32(fr);
}

/* uint64 to single */
uint32_t riscv_fp_lu2s(uint64_t a, int rm, uint32_t *flags) {
    setup_rm(rm);
    volatile float fr = (float)a;
    *flags = get_riscv_flags();
    fesetround(FE_TONEAREST);
    return f_to_u32(fr);
}

/* double to int64 (signed), saturating with NV on overflow */
uint64_t riscv_fp_d2l(uint64_t a, int rm, uint32_t *flags) {
    double fa = u64_to_d(a);
    if (isnan(fa))                    { *flags = 16; return UINT64_C(0x7FFFFFFFFFFFFFFF); }
    if (isinf(fa) && fa > 0.0)        { *flags = 16; return UINT64_C(0x7FFFFFFFFFFFFFFF); }
    if (isinf(fa) && fa < 0.0)        { *flags = 16; return UINT64_C(0x8000000000000000); }
    if (fa >= 9223372036854775808.0)   { *flags = 16; return UINT64_C(0x7FFFFFFFFFFFFFFF); }
    if (fa < -9223372036854775808.0)   { *flags = 16; return UINT64_C(0x8000000000000000); }
    setup_rm(rm);
    volatile int64_t r = (int64_t)fa;
    *flags = get_riscv_flags();
    fesetround(FE_TONEAREST);
    return (uint64_t)r;
}

/* double to uint64, saturating with NV on overflow.
 * A value in (-1,0) rounds toward zero to 0 -- in range, inexact (NX), NOT
 * invalid; only a rounded result outside [0,2^64) sets NV. Round first (per
 * the requested mode) so the negative/overflow decision is post-rounding. */
uint64_t riscv_fp_d2lu(uint64_t a, int rm, uint32_t *flags) {
    double fa = u64_to_d(a);
    if (isnan(fa))                     { *flags = 16; return UINT64_C(0xFFFFFFFFFFFFFFFF); }
    if (isinf(fa) && fa > 0.0)         { *flags = 16; return UINT64_C(0xFFFFFFFFFFFFFFFF); }
    if (isinf(fa) && fa < 0.0)         { *flags = 16; return 0; }
    setup_rm(rm);
    volatile double r = rint(fa);
    uint32_t fl = get_riscv_flags();
    fesetround(FE_TONEAREST);
    if (r < 0.0)                       { *flags = 16; return 0; }
    if (r >= 18446744073709551616.0)   { *flags = 16; return UINT64_C(0xFFFFFFFFFFFFFFFF); }
    *flags = fl;
    return (uint64_t)r;
}

/* single to int64 (signed), saturating with NV on overflow */
uint64_t riscv_fp_s2l(uint32_t a, int rm, uint32_t *flags) {
    float fa = u32_to_f(a);
    if (isnanf(fa))                    { *flags = 16; return UINT64_C(0x7FFFFFFFFFFFFFFF); }
    if (isinff(fa) && fa > 0.0f)       { *flags = 16; return UINT64_C(0x7FFFFFFFFFFFFFFF); }
    if (isinff(fa) && fa < 0.0f)       { *flags = 16; return UINT64_C(0x8000000000000000); }
    if (fa >= 9223372036854775808.0f)  { *flags = 16; return UINT64_C(0x7FFFFFFFFFFFFFFF); }
    if (fa < -9223372036854775808.0f)  { *flags = 16; return UINT64_C(0x8000000000000000); }
    setup_rm(rm);
    volatile int64_t r = (int64_t)fa;
    *flags = get_riscv_flags();
    fesetround(FE_TONEAREST);
    return (uint64_t)r;
}

/* single to uint64, saturating with NV on overflow (see riscv_fp_d2lu). */
uint64_t riscv_fp_s2lu(uint32_t a, int rm, uint32_t *flags) {
    float fa = u32_to_f(a);
    if (isnanf(fa))                    { *flags = 16; return UINT64_C(0xFFFFFFFFFFFFFFFF); }
    if (isinff(fa) && fa > 0.0f)       { *flags = 16; return UINT64_C(0xFFFFFFFFFFFFFFFF); }
    if (isinff(fa) && fa < 0.0f)       { *flags = 16; return 0; }
    setup_rm(rm);
    volatile float r = rintf(fa);
    uint32_t fl = get_riscv_flags();
    fesetround(FE_TONEAREST);
    if (r < 0.0f)                      { *flags = 16; return 0; }
    if (r >= 18446744073709551616.0f) { *flags = 16; return UINT64_C(0xFFFFFFFFFFFFFFFF); }
    *flags = fl;
    return (uint64_t)r;
}
