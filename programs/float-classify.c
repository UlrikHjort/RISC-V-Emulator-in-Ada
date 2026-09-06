/* **************************************************************************
 *         RISC-V Emulator - fclass.s and fclass.d instruction test
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

// float-classify.c -- fclass.s and fclass.d instruction test.
//
// Tests the fclass.s / fclass.d instructions and FCSR rounding modes.
//
// fclass result bits (per RISC-V spec):
//   bit 0: -infinity
//   bit 1: negative normal
//   bit 2: negative subnormal
//   bit 3: -0
//   bit 4: +0
//   bit 5: positive subnormal
//   bit 6: positive normal
//   bit 7: +infinity
//   bit 8: signaling NaN
//   bit 9: quiet NaN
//
// Rounding mode tests (frm field of fcsr):
//   0 = RNE (round to nearest, ties to even)
//   1 = RTZ (round toward zero)
//   2 = RDN (round down, toward -inf)
//   3 = RUP (round up, toward +inf)
//   4 = RMM (round to nearest, ties away from zero)
//
// Build: cd programs && make run-float-classify
// By Ulrik Hørlyk Hjort 2026

#include <stdint.h>
#include "log.h"

void putchar(char c);
static void uart_puts(const char *s) {
    while (*s) { if (*s == '\n') putchar('\r'); putchar(*s++); }
}

static int g_pass = 0, g_fail = 0;

static void check32(const char *label, uint32_t got, uint32_t expected) {
    if (got == expected) {
        log_write(NONE, "  PASS  %s\n", label); g_pass++;
    } else {
        log_write(NONE, "  FAIL  %s: got 0x%x  exp 0x%x\n",
                  label, got, expected);
        g_fail++;
    }
}

// fclass.s: classify single-precision float
static inline uint32_t fclass_s(float f) {
    uint32_t r;
    asm volatile("fclass.s %0, %1" : "=r"(r) : "f"(f));
    return r;
}

// fclass.d: classify double-precision float
static inline uint32_t fclass_d(double d) {
    uint32_t r;
    asm volatile("fclass.d %0, %1" : "=r"(r) : "f"(d));
    return r;
}

// Read/write FCSR
static inline uint32_t read_fcsr(void) {
    uint32_t v; asm volatile("csrr %0, fcsr" : "=r"(v)); return v;
}
static inline void write_frm(uint32_t mode) {
    asm volatile("csrw frm, %0" :: "r"(mode));
}
static inline uint32_t read_frm(void) {
    uint32_t v; asm volatile("csrr %0, frm" : "=r"(v)); return v;
}
static inline void write_fflags(uint32_t flags) {
    asm volatile("csrw fflags, %0" :: "r"(flags));
}
static inline uint32_t read_fflags(void) {
    uint32_t v; asm volatile("csrr %0, fflags" : "=r"(v)); return v;
}

// Build a float from its raw 32-bit representation
static inline float f32_from_bits(uint32_t bits) {
    float f;
    __builtin_memcpy(&f, &bits, 4);
    return f;
}

// Build a double from its raw 64-bit representation
static inline double f64_from_bits(uint64_t bits) {
    double d;
    __builtin_memcpy(&d, &bits, 8);
    return d;
}

// -- fclass.s -------------------------------------------------------------

static void test_fclass_s(void) {
    log_write(NONE, "\n=== fclass.s (single precision) ===\n");

    // -infinity: bit 0 = 1
    check32("fclass.s -inf",
            fclass_s(f32_from_bits(0xFF800000u)), 1u << 0);

    // Negative normal: bit 1 = 1 (e.g. -1.0)
    check32("fclass.s -1.0 (neg normal)",
            fclass_s(-1.0f), 1u << 1);

    // Negative normal: -2^126 (smallest magnitude normal with sign)
    check32("fclass.s -0x1.0p-126 (neg normal small)",
            fclass_s(f32_from_bits(0x80800000u)), 1u << 1);

    // Negative subnormal: bit 2 = 1
    // 0x80400000 = negative subnormal (exponent=0, mantissa!=0, sign=1)
    check32("fclass.s neg subnormal",
            fclass_s(f32_from_bits(0x80400000u)), 1u << 2);

    // -0: bit 3 = 1
    check32("fclass.s -0.0",
            fclass_s(f32_from_bits(0x80000000u)), 1u << 3);

    // +0: bit 4 = 1
    check32("fclass.s +0.0",
            fclass_s(0.0f), 1u << 4);

    // Positive subnormal: bit 5 = 1
    // 0x00400000 = positive subnormal
    check32("fclass.s pos subnormal",
            fclass_s(f32_from_bits(0x00400000u)), 1u << 5);

    // Positive normal: bit 6 = 1 (e.g. 1.0)
    check32("fclass.s +1.0 (pos normal)",
            fclass_s(1.0f), 1u << 6);

    // Positive normal: 3.14
    check32("fclass.s 3.14 (pos normal)",
            fclass_s(3.14f), 1u << 6);

    // +infinity: bit 7 = 1
    check32("fclass.s +inf",
            fclass_s(f32_from_bits(0x7F800000u)), 1u << 7);

    // Signaling NaN: bit 8 = 1
    // sNaN: exponent all 1s, mantissa MSB=0, rest!=0
    // 0x7F800001 = sNaN (quiet bit=0)
    check32("fclass.s sNaN",
            fclass_s(f32_from_bits(0x7F800001u)), 1u << 8);

    // Quiet NaN: bit 9 = 1
    // qNaN: exponent all 1s, mantissa MSB=1
    // 0x7FC00000 = canonical qNaN
    check32("fclass.s qNaN",
            fclass_s(f32_from_bits(0x7FC00000u)), 1u << 9);
}

// -- fclass.d -------------------------------------------------------------

static void test_fclass_d(void) {
    log_write(NONE, "\n=== fclass.d (double precision) ===\n");

    // -infinity
    check32("fclass.d -inf",
            fclass_d(f64_from_bits(0xFFF0000000000000ULL)), 1u << 0);

    // Negative normal
    check32("fclass.d -1.0",
            fclass_d(-1.0), 1u << 1);

    // Negative subnormal: 0x8008000000000000 (negative, exp=0, mant!=0)
    check32("fclass.d neg subnormal",
            fclass_d(f64_from_bits(0x8008000000000000ULL)), 1u << 2);

    // -0
    check32("fclass.d -0.0",
            fclass_d(f64_from_bits(0x8000000000000000ULL)), 1u << 3);

    // +0
    check32("fclass.d +0.0",
            fclass_d(0.0), 1u << 4);

    // Positive subnormal: 0x0008000000000000
    check32("fclass.d pos subnormal",
            fclass_d(f64_from_bits(0x0008000000000000ULL)), 1u << 5);

    // Positive normal
    check32("fclass.d +1.0",
            fclass_d(1.0), 1u << 6);

    // +infinity
    check32("fclass.d +inf",
            fclass_d(f64_from_bits(0x7FF0000000000000ULL)), 1u << 7);

    // Signaling NaN (quiet bit=0, mantissa!=0): 0x7FF0000000000001
    check32("fclass.d sNaN",
            fclass_d(f64_from_bits(0x7FF0000000000001ULL)), 1u << 8);

    // Quiet NaN: 0x7FF8000000000000
    check32("fclass.d qNaN",
            fclass_d(f64_from_bits(0x7FF8000000000000ULL)), 1u << 9);
}

// -- FCSR rounding modes ---------------------------------------------------
// We test rounding by converting a value that is exactly between two integers.

static void test_rounding_modes(void) {
    log_write(NONE, "\n=== FCSR rounding modes ===\n");

    uint32_t orig_frm = read_frm();

    // Test value: 2.5 -> should round to 2 (RNE, ties to even), 2 (RTZ),
    //             2 (RDN), 3 (RUP), 3 (RMM)
    // Test value: -2.5 -> should round to -2 (RNE), -2 (RTZ),
    //              -3 (RDN), -2 (RUP), -3 (RMM)

    int32_t result;

    // RNE (round to nearest, ties to even) -- 2.5 -> 2 (2 is even)
    write_frm(0);
    asm volatile("fcvt.w.s %0, %1, dyn" : "=r"(result) : "f"(2.5f));
    check32("RNE: 2.5 -> 2 (ties to even)", (uint32_t)result, 2);

    // 3.5 -> 4 with RNE (4 is even)
    asm volatile("fcvt.w.s %0, %1, dyn" : "=r"(result) : "f"(3.5f));
    check32("RNE: 3.5 -> 4 (ties to even)", (uint32_t)result, 4);

    // RTZ (round toward zero) -- 2.5 -> 2, -2.5 -> -2
    write_frm(1);
    asm volatile("fcvt.w.s %0, %1, dyn" : "=r"(result) : "f"(2.5f));
    check32("RTZ: 2.5 -> 2", (uint32_t)result, 2);
    asm volatile("fcvt.w.s %0, %1, dyn" : "=r"(result) : "f"(-2.5f));
    check32("RTZ: -2.5 -> -2", (uint32_t)result, (uint32_t)-2);

    // RDN (round down, toward -inf) -- 2.5 -> 2, -2.5 -> -3
    write_frm(2);
    asm volatile("fcvt.w.s %0, %1, dyn" : "=r"(result) : "f"(2.5f));
    check32("RDN: 2.5 -> 2", (uint32_t)result, 2);
    asm volatile("fcvt.w.s %0, %1, dyn" : "=r"(result) : "f"(-2.5f));
    check32("RDN: -2.5 -> -3", (uint32_t)result, (uint32_t)-3);

    // RUP (round up, toward +inf) -- 2.5 -> 3, -2.5 -> -2
    write_frm(3);
    asm volatile("fcvt.w.s %0, %1, dyn" : "=r"(result) : "f"(2.5f));
    check32("RUP: 2.5 -> 3", (uint32_t)result, 3);
    asm volatile("fcvt.w.s %0, %1, dyn" : "=r"(result) : "f"(-2.5f));
    check32("RUP: -2.5 -> -2", (uint32_t)result, (uint32_t)-2);

    // RMM (round to nearest, ties away from zero) -- 2.5 -> 3, -2.5 -> -3
    write_frm(4);
    asm volatile("fcvt.w.s %0, %1, dyn" : "=r"(result) : "f"(2.5f));
    check32("RMM: 2.5 -> 3", (uint32_t)result, 3);
    asm volatile("fcvt.w.s %0, %1, dyn" : "=r"(result) : "f"(-2.5f));
    check32("RMM: -2.5 -> -3", (uint32_t)result, (uint32_t)-3);

    // Restore frm
    write_frm(orig_frm);
}

// -- FCSR exception flags --------------------------------------------------
// fflags bits: NX(0)=inexact, UF(1)=underflow, OF(2)=overflow,
//              DZ(3)=div-by-zero, NV(4)=invalid operation

static void test_fflags(void) {
    log_write(NONE, "\n=== FCSR exception flags ===\n");

    // NX (inexact): converting 2.5 to int sets NX (fractional part lost)
    write_fflags(0);
    int32_t r;
    asm volatile("fcvt.w.s %0, %1, rtz" : "=r"(r) : "f"(2.5f));
    uint32_t flags = read_fflags();
    check32("NX flag set after 2.5->int", flags & 1, 1);  // bit 0 = NX

    // NV (invalid): sqrt(-1) -> NaN sets NV (bit 4)
    write_fflags(0);
    float nan_result;
    asm volatile("fsqrt.s %0, %1" : "=f"(nan_result) : "f"(-1.0f));
    flags = read_fflags();
    check32("NV flag set after sqrt(-1)", (flags >> 4) & 1, 1);  // bit 4 = NV

    // DZ (divide by zero): 1.0f / 0.0f -> +inf, sets DZ (bit 3)
    write_fflags(0);
    float inf_result;
    float zero = 0.0f;
    asm volatile("fdiv.s %0, %1, %2" : "=f"(inf_result) : "f"(1.0f), "f"(zero));
    flags = read_fflags();
    check32("DZ flag set after 1/0", (flags >> 3) & 1, 1);  // bit 3 = DZ

    // OF (overflow): very large float * very large float
    write_fflags(0);
    float huge = f32_from_bits(0x7F000000u);  // 2^126
    float overflow;
    asm volatile("fmul.s %0, %1, %2" : "=f"(overflow) : "f"(huge), "f"(huge));
    flags = read_fflags();
    check32("OF flag set after overflow", (flags >> 2) & 1, 1);  // bit 2 = OF

    // UF (underflow): very small subnormal * very small value
    write_fflags(0);
    float tiny = f32_from_bits(0x00800001u);  // smallest normal
    float half = 0.5f;
    float underflow;
    asm volatile("fmul.s %0, %1, %2" : "=f"(underflow) : "f"(tiny), "f"(half));
    flags = read_fflags();
    // UF is set when result is subnormal and inexact (bit 1)
    check32("UF flag set after underflow", (flags >> 1) & 1, 1);

    // Clear flags
    write_fflags(0);
    check32("fflags cleared to 0", read_fflags(), 0);
}

// -- Main ------------------------------------------------------------------

int main(void) {
    uart_puts("=== Float Classify Test ===\n");
    if (log_init("float-classify.log") != 0) {
        uart_puts("ERROR: log_init failed\n"); return 1;
    }

    log_write(NONE, "=== fclass + FCSR rounding mode test (RV32IMFD) ===\n");

    test_fclass_s();
    test_fclass_d();
    test_rounding_modes();
    test_fflags();

    log_write(NONE, "\n=== Summary ===\n");
    log_write(NONE, "  PASS: %d\n", g_pass);
    log_write(NONE, "  FAIL: %d\n", g_fail);
    log_write(NONE, "  %s\n", g_fail == 0 ? "ALL TESTS PASSED" : "SOME TESTS FAILED");

    log_close();
    uart_puts(g_fail == 0 ? "ALL PASSED\n" : "SOME FAILED\n");
    return g_fail;
}
