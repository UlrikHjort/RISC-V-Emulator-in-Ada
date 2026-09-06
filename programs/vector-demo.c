/* **************************************************************************
 *    RISC-V Emulator - RISC-V Vector Extension (RVV 1.0) demonstration
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

// vector-demo.c -- RISC-V Vector Extension (RVV 1.0) demonstration
//
// Shows the same operations implemented two ways:
//   Part 1: C intrinsics  (#include <riscv_vector.h>)
//   Part 2: Inline assembly (raw vsetvli / vle32.v / ... instructions)
//
// All results are written to a host log file via the semihosting log module.
//
// Build: cd programs && make run-vector-demo
//   (uses -march=rv32imv which enables the V extension)
//
// With VLEN=128, VLMAX for e32/m1 = 4 elements per register group.
// By Ulrik Hørlyk Hjort 2026

#include <riscv_vector.h>
#include <stdint.h>
#include "log.h"

void putchar(char c);

static void uart_puts(const char *s) {
    while (*s) {
        if (*s == '\n') putchar('\r');
        putchar(*s++);
    }
}

// RV32 quirk: vle32/vse32 intrinsics expect long* not int32_t*
// (both are 32-bit on RV32, but the types differ)
#define VLP(p)  ((const long *)(p))
#define VSP(p)  ((long *)(p))

// ============================================================================
// Test data (16 elements -- fills 4 vregs at VLMAX=4)
// ============================================================================

static const int32_t A[16] = { 1,  2,  3,  4,  5,  6,  7,  8,
                                9, 10, 11, 12, 13, 14, 15, 16 };
static const int32_t B[16] = { 16, 15, 14, 13, 12, 11, 10,  9,
                                 8,  7,  6,  5,  4,  3,  2,  1 };
static int32_t OUT[16];

// ============================================================================
// Helper: log an array of int32_t
// ============================================================================

static void log_array(const char *label, const int32_t *arr, int n) {
    log_write(NONE, "%s = [", label);
    for (int i = 0; i < n; i++) {
        if (i) log_write(NONE, ", ");
        log_write(NONE, "%d", arr[i]);
    }
    log_write(NONE, "]\n");
}

// ============================================================================
// Part 1: Intrinsics
// ============================================================================

// 1a. Element-wise add:  OUT[i] = A[i] + B[i]
static void intrinsic_vadd(const int32_t *a, const int32_t *b,
                            int32_t *out, int n) {
    for (int i = 0; i < n; ) {
        size_t vl = __riscv_vsetvl_e32m1(n - i);
        vint32m1_t va = __riscv_vle32_v_i32m1(VLP(a + i), vl);
        vint32m1_t vb = __riscv_vle32_v_i32m1(VLP(b + i), vl);
        vint32m1_t vc = __riscv_vadd_vv_i32m1(va, vb, vl);
        __riscv_vse32_v_i32m1(VSP(out + i), vc, vl);
        i += vl;
    }
}

// 1b. Dot product:  sum(A[i] * B[i])
static int32_t intrinsic_dot(const int32_t *a, const int32_t *b, int n) {
    size_t vlmax = __riscv_vsetvlmax_e32m1();
    vint32m1_t acc = __riscv_vmv_v_x_i32m1(0, vlmax);

    for (int i = 0; i < n; ) {
        size_t vl = __riscv_vsetvl_e32m1(n - i);
        vint32m1_t va = __riscv_vle32_v_i32m1(VLP(a + i), vl);
        vint32m1_t vb = __riscv_vle32_v_i32m1(VLP(b + i), vl);
        vint32m1_t vp = __riscv_vmul_vv_i32m1(va, vb, vl);
        acc = __riscv_vadd_vv_i32m1(acc, vp, vl);
        i += vl;
    }

    // Horizontal sum: vredsum result = vs1[0] + sum(vs2[active elements])
    // Use a separate zero vector as vs1 so element 0 is not double-counted.
    vint32m1_t zero = __riscv_vmv_v_x_i32m1(0, vlmax);
    vint32m1_t sum = __riscv_vredsum_vs_i32m1_i32m1(acc, zero, vlmax);
    return __riscv_vmv_x_s_i32m1_i32(sum);
}

// 1c. Array max:  max(A[i])
static int32_t intrinsic_vmax(const int32_t *a, int n) {
    size_t vlmax = __riscv_vsetvlmax_e32m1();
    // Initialise accumulator to the smallest possible signed value
    vint32m1_t acc = __riscv_vmv_v_x_i32m1((int32_t)0x80000000, vlmax);

    for (int i = 0; i < n; ) {
        size_t vl = __riscv_vsetvl_e32m1(n - i);
        vint32m1_t va = __riscv_vle32_v_i32m1(VLP(a + i), vl);
        acc = __riscv_vmax_vv_i32m1(acc, va, vl);
        i += vl;
    }

    vint32m1_t res = __riscv_vredmax_vs_i32m1_i32m1(acc, acc, vlmax);
    return __riscv_vmv_x_s_i32m1_i32(res);
}

// 1d. Scalar multiply:  OUT[i] = A[i] * scalar
static void intrinsic_vscale(const int32_t *a, int32_t scalar,
                              int32_t *out, int n) {
    for (int i = 0; i < n; ) {
        size_t vl = __riscv_vsetvl_e32m1(n - i);
        vint32m1_t va = __riscv_vle32_v_i32m1(VLP(a + i), vl);
        vint32m1_t vc = __riscv_vmul_vx_i32m1(va, scalar, vl);
        __riscv_vse32_v_i32m1(VSP(out + i), vc, vl);
        i += vl;
    }
}

// ============================================================================
// Part 2: Inline assembly
// ============================================================================

// 2a. Element-wise add using raw instructions
static void asm_vadd(const int32_t *a, const int32_t *b,
                     int32_t *out, int n) {
    int remaining = n;
    while (remaining > 0) {
        int vl;
        // vsetvli t0, remaining, e32, m1, ta, ma
        asm volatile (
            "vsetvli %0, %1, e32, m1, ta, ma"
            : "=r"(vl)
            : "r"(remaining)
        );
        // vle32.v v0, (a)
        asm volatile ("vle32.v v0, (%0)" : : "r"(a) : "v0");
        // vle32.v v1, (b)
        asm volatile ("vle32.v v1, (%0)" : : "r"(b) : "v1");
        // vadd.vv v2, v0, v1
        asm volatile ("vadd.vv v2, v0, v1" : : : "v2");
        // vse32.v v2, (out)
        asm volatile ("vse32.v v2, (%0)" : : "r"(out) : "memory");

        a         += vl;
        b         += vl;
        out       += vl;
        remaining -= vl;
    }
}

// 2b. Horizontal sum of an array using inline assembly
static int32_t asm_vsum(const int32_t *a, int n) {
    int remaining = n;
    int32_t result = 0;

    // Zero-initialise accumulator vector (v8) using vmv.v.x
    int vlmax;
    asm volatile (
        "vsetvli %0, zero, e32, m1, ta, ma"
        : "=r"(vlmax)
    );
    asm volatile (
        "vmv.v.x v8, zero"
        : : : "v8"
    );

    while (remaining > 0) {
        int vl;
        asm volatile (
            "vsetvli %0, %1, e32, m1, ta, ma"
            : "=r"(vl)
            : "r"(remaining)
        );
        asm volatile ("vle32.v v0, (%0)" : : "r"(a) : "v0");
        // vadd.vv v8, v8, v0  (accumulate)
        asm volatile ("vadd.vv v8, v8, v0" : : : "v8");

        a         += vl;
        remaining -= vl;
    }

    // Restore vlmax for the reduction
    asm volatile (
        "vsetvli zero, %0, e32, m1, ta, ma"
        : : "r"(vlmax)
    );
    // vredsum.vs result = vs1[0] + sum(vs2[active]).
    // Use v9 zeroed as vs1 so element 0 of v8 is not double-counted.
    asm volatile ("vmv.v.x v9, zero" : : : "v9");
    asm volatile ("vredsum.vs v9, v8, v9" : : : "v9");
    // vmv.x.s  result, v9
    asm volatile ("vmv.x.s %0, v9" : "=r"(result));

    return result;
}

// 2c. Element-wise multiply-accumulate: OUT[i] += A[i] * B[i]
//     (pure inline asm, single-pass, n must be <= VLMAX for simplicity)
static void asm_vmac(const int32_t *a, const int32_t *b,
                     int32_t *out, int n) {
    int vl;
    asm volatile (
        "vsetvli %0, %1, e32, m1, ta, ma"
        : "=r"(vl)
        : "r"(n)
    );
    asm volatile ("vle32.v v0, (%0)" : : "r"(a)   : "v0");
    asm volatile ("vle32.v v1, (%0)" : : "r"(b)   : "v1");
    asm volatile ("vle32.v v2, (%0)" : : "r"(out) : "v2");
    // vmul.vv  v3, v0, v1
    asm volatile ("vmul.vv v3, v0, v1" : : : "v3");
    // vadd.vv  v2, v2, v3
    asm volatile ("vadd.vv v2, v2, v3" : : : "v2");
    asm volatile ("vse32.v v2, (%0)" : : "r"(out) : "memory");
}

// ============================================================================
// Main
// ============================================================================

int main(void) {
    uart_puts("=== RISC-V Vector Demo ===\n");

    if (log_init("vector-demo.log") != 0) {
        uart_puts("ERROR: log_init failed\n");
        return 1;
    }

    log_write(NONE, "=== RISC-V Vector Extension (RVV 1.0) Demo ===\n");
    log_write(NONE, "VLEN=128 bits  =>  VLMAX = 4 x int32 per m1 group\n\n");

    log_write(NONE, "Input arrays (16 elements):\n");
    log_array("  A", A, 16);
    log_array("  B", B, 16);
    log_write(NONE, "\n");

    // ------------------------------------------------------------------
    // Part 1: Intrinsics
    // ------------------------------------------------------------------
    log_write(NONE, "--- Part 1: C Intrinsics (<riscv_vector.h>) ---\n\n");

    // 1a. Vector add
    log_write(CYCLES, "vadd_vv  start\n");
    intrinsic_vadd(A, B, OUT, 16);
    log_write(CYCLES, "vadd_vv  done\n");
    log_array("  OUT = A + B", OUT, 16);
    log_write(NONE, "  (every element should be 17)\n\n");

    // 1b. Dot product  A*B = sum(A[i]*B[i]) = 2*sum(k*(17-k), k=1..16)
    //   = 2*(16+30+42+52+60+66+70+72+72+70+66+60+52+42+30+16)
    //   = sum of A[i]*B[i] where A[i]+B[i]=17 always
    //   Expected: 1*16+2*15+...+16*1 = 2*(1*16+2*15+...+8*9) = 952
    log_write(CYCLES, "dot_product  start\n");
    int32_t dot = intrinsic_dot(A, B, 16);
    log_write(CYCLES, "dot_product  done\n");
    // A.B = sum(i*(17-i), i=1..16) = 17*136 - 1496 = 816
    log_write(NONE, "  A . B = %d  (expected 816)\n\n", dot);

    // 1c. Max
    log_write(CYCLES, "vmax/vredmax  start\n");
    int32_t mx = intrinsic_vmax(A, 16);
    log_write(CYCLES, "vmax/vredmax  done\n");
    log_write(NONE, "  max(A) = %d  (expected 16)\n\n", mx);

    // 1d. Scalar scale  A * 3
    log_write(CYCLES, "vmul_vx  start\n");
    intrinsic_vscale(A, 3, OUT, 16);
    log_write(CYCLES, "vmul_vx  done\n");
    log_array("  OUT = A * 3", OUT, 16);
    log_write(NONE, "\n");

    // ------------------------------------------------------------------
    // Part 2: Inline Assembly
    // ------------------------------------------------------------------
    log_write(NONE, "--- Part 2: Inline Assembly ---\n\n");

    // 2a. Vector add
    log_write(CYCLES, "asm vadd  start\n");
    asm_vadd(A, B, OUT, 16);
    log_write(CYCLES, "asm vadd  done\n");
    log_array("  OUT = A + B (asm)", OUT, 16);
    log_write(NONE, "  (every element should be 17)\n\n");

    // 2b. Horizontal sum of A:  1+2+...+16 = 136
    log_write(CYCLES, "asm vsum  start\n");
    int32_t s = asm_vsum(A, 16);
    log_write(CYCLES, "asm vsum  done\n");
    log_write(NONE, "  sum(A) = %d  (expected 136)\n\n", s);

    // 2c. MAC on first 4 elements (fits in one vop at VLMAX=4)
    //   initial OUT[0..3] = {0,0,0,0}
    //   OUT[i] += A[i]*B[i]  =>  {16, 30, 42, 52}
    for (int i = 0; i < 4; i++) OUT[i] = 0;
    log_write(CYCLES, "asm vmac  start\n");
    asm_vmac(A, B, OUT, 4);
    log_write(CYCLES, "asm vmac  done\n");
    log_array("  OUT = 0 + A[0..3]*B[0..3] (asm)", OUT, 4);
    log_write(NONE, "  (expected [16, 30, 42, 52])\n\n");

    // ------------------------------------------------------------------
    // Cycle cost summary (timestamps already logged inline above)
    // ------------------------------------------------------------------
    log_write(NONE, "--- Cycle timestamps recorded above with [XXXXXXXX] prefix ---\n");
    log_write(NONE, "Subtract consecutive values to get cost per operation.\n\n");

    log_write(NONE, "=== Done ===\n");
    log_regs();
    log_close();

    uart_puts("Log written to vector-demo.log\n");
    uart_puts("Done!\n");
    return 0;
}
