/* **************************************************************************
 *RISC-V Emulator - RISC-V vector-accelerated matrix library (int32_t elements)
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

// matlib.c -- RISC-V vector-accelerated matrix library (int32_t elements)
//
// Uses RVV 1.0 intrinsics throughout.  With VLEN=128 and LMUL=m1 each
// vsetvl call processes up to 4 int32_t elements per iteration, so every
// function handles arbitrary lengths via the standard vsetvl strip-mining
// pattern:
//
//   for (int i = 0; i < n; ) {
//       size_t vl = __riscv_vsetvl_e32m1(n - i);
//       ... load, compute, store with vl elements ...
//       i += vl;
//   }
// By Ulrik Hørlyk Hjort 2026

#include "matlib.h"
#include <riscv_vector.h>
#include <stdint.h>

// RV32 quirk: vle32/vse32 intrinsics expect long* not int32_t*
#define VLP(p)  ((const long *)(p))
#define VSP(p)  ((long *)(p))

// -- Helpers ----------------------------------------------------------------

// Horizontal sum of a vint32m1_t accumulator that holds vlmax elements.
// Uses a separate zero vector as the vs1 (initial value) so element 0
// of acc is not double-counted.
static inline int32_t hsum(vint32m1_t acc, size_t vlmax) {
    vint32m1_t zero = __riscv_vmv_v_x_i32m1(0, vlmax);
    vint32m1_t s    = __riscv_vredsum_vs_i32m1_i32m1(acc, zero, vlmax);
    return __riscv_vmv_x_s_i32m1_i32(s);
}

// -- Element-wise / scalar operations --------------------------------------

void mat_zero(int32_t *a, int n) {
    for (int i = 0; i < n; ) {
        size_t vl = __riscv_vsetvl_e32m1(n - i);
        __riscv_vse32_v_i32m1(VSP(a + i),
                              __riscv_vmv_v_x_i32m1(0, vl), vl);
        i += vl;
    }
}

void mat_add(int32_t *c, const int32_t *a, const int32_t *b, int n) {
    for (int i = 0; i < n; ) {
        size_t vl = __riscv_vsetvl_e32m1(n - i);
        vint32m1_t va = __riscv_vle32_v_i32m1(VLP(a + i), vl);
        vint32m1_t vb = __riscv_vle32_v_i32m1(VLP(b + i), vl);
        __riscv_vse32_v_i32m1(VSP(c + i),
                              __riscv_vadd_vv_i32m1(va, vb, vl), vl);
        i += vl;
    }
}

void mat_sub(int32_t *c, const int32_t *a, const int32_t *b, int n) {
    for (int i = 0; i < n; ) {
        size_t vl = __riscv_vsetvl_e32m1(n - i);
        vint32m1_t va = __riscv_vle32_v_i32m1(VLP(a + i), vl);
        vint32m1_t vb = __riscv_vle32_v_i32m1(VLP(b + i), vl);
        __riscv_vse32_v_i32m1(VSP(c + i),
                              __riscv_vsub_vv_i32m1(va, vb, vl), vl);
        i += vl;
    }
}

void mat_elem_mul(int32_t *c, const int32_t *a, const int32_t *b, int n) {
    for (int i = 0; i < n; ) {
        size_t vl = __riscv_vsetvl_e32m1(n - i);
        vint32m1_t va = __riscv_vle32_v_i32m1(VLP(a + i), vl);
        vint32m1_t vb = __riscv_vle32_v_i32m1(VLP(b + i), vl);
        __riscv_vse32_v_i32m1(VSP(c + i),
                              __riscv_vmul_vv_i32m1(va, vb, vl), vl);
        i += vl;
    }
}

void mat_scale(int32_t *c, const int32_t *a, int32_t s, int n) {
    for (int i = 0; i < n; ) {
        size_t vl = __riscv_vsetvl_e32m1(n - i);
        vint32m1_t va = __riscv_vle32_v_i32m1(VLP(a + i), vl);
        __riscv_vse32_v_i32m1(VSP(c + i),
                              __riscv_vmul_vx_i32m1(va, s, vl), vl);
        i += vl;
    }
}

void mat_negate(int32_t *c, const int32_t *a, int n) {
    // vrsub.vi: c[i] = 0 - a[i]
    for (int i = 0; i < n; ) {
        size_t vl = __riscv_vsetvl_e32m1(n - i);
        vint32m1_t va = __riscv_vle32_v_i32m1(VLP(a + i), vl);
        __riscv_vse32_v_i32m1(VSP(c + i),
                              __riscv_vrsub_vx_i32m1(va, 0, vl), vl);
        i += vl;
    }
}

// -- Reductions -------------------------------------------------------------

int32_t mat_sum(const int32_t *a, int n) {
    size_t vlmax = __riscv_vsetvlmax_e32m1();
    vint32m1_t acc = __riscv_vmv_v_x_i32m1(0, vlmax);
    for (int i = 0; i < n; ) {
        size_t vl = __riscv_vsetvl_e32m1(n - i);
        acc = __riscv_vadd_vv_i32m1(
                  acc,
                  __riscv_vle32_v_i32m1(VLP(a + i), vl),
                  vl);
        i += vl;
    }
    return hsum(acc, vlmax);
}

int32_t mat_frobenius_sq(const int32_t *a, int n) {
    size_t vlmax = __riscv_vsetvlmax_e32m1();
    vint32m1_t acc = __riscv_vmv_v_x_i32m1(0, vlmax);
    for (int i = 0; i < n; ) {
        size_t vl = __riscv_vsetvl_e32m1(n - i);
        vint32m1_t va = __riscv_vle32_v_i32m1(VLP(a + i), vl);
        acc = __riscv_vadd_vv_i32m1(
                  acc,
                  __riscv_vmul_vv_i32m1(va, va, vl),
                  vl);
        i += vl;
    }
    return hsum(acc, vlmax);
}

int32_t mat_max(const int32_t *a, int n) {
    size_t vlmax = __riscv_vsetvlmax_e32m1();
    // Initialise all lanes to INT32_MIN so any real value beats it.
    vint32m1_t acc = __riscv_vmv_v_x_i32m1((int32_t)0x80000000u, vlmax);
    for (int i = 0; i < n; ) {
        size_t vl = __riscv_vsetvl_e32m1(n - i);
        acc = __riscv_vmax_vv_i32m1(
                  acc,
                  __riscv_vle32_v_i32m1(VLP(a + i), vl),
                  vl);
        i += vl;
    }
    // vredmax.vs: result = max(vs1[0], max(vs2[active]))
    // Since acc[0] <= max(acc), using acc as both vs1 and vs2 is fine.
    vint32m1_t res = __riscv_vredmax_vs_i32m1_i32m1(acc, acc, vlmax);
    return __riscv_vmv_x_s_i32m1_i32(res);
}

int32_t mat_min(const int32_t *a, int n) {
    size_t vlmax = __riscv_vsetvlmax_e32m1();
    vint32m1_t acc = __riscv_vmv_v_x_i32m1((int32_t)0x7fffffffu, vlmax);
    for (int i = 0; i < n; ) {
        size_t vl = __riscv_vsetvl_e32m1(n - i);
        acc = __riscv_vmin_vv_i32m1(
                  acc,
                  __riscv_vle32_v_i32m1(VLP(a + i), vl),
                  vl);
        i += vl;
    }
    vint32m1_t res = __riscv_vredmin_vs_i32m1_i32m1(acc, acc, vlmax);
    return __riscv_vmv_x_s_i32m1_i32(res);
}

// -- Vector operations ------------------------------------------------------

int32_t vec_dot(const int32_t *a, const int32_t *b, int n) {
    size_t vlmax = __riscv_vsetvlmax_e32m1();
    vint32m1_t acc = __riscv_vmv_v_x_i32m1(0, vlmax);
    for (int i = 0; i < n; ) {
        size_t vl = __riscv_vsetvl_e32m1(n - i);
        vint32m1_t va = __riscv_vle32_v_i32m1(VLP(a + i), vl);
        vint32m1_t vb = __riscv_vle32_v_i32m1(VLP(b + i), vl);
        acc = __riscv_vadd_vv_i32m1(
                  acc,
                  __riscv_vmul_vv_i32m1(va, vb, vl),
                  vl);
        i += vl;
    }
    return hsum(acc, vlmax);
}

// -- Matrix operations ------------------------------------------------------

// AT[n,m] = A[m,n]^T   -- scalar fallback (column access is strided)
void mat_transpose(int32_t *at, const int32_t *a, int m, int n) {
    for (int i = 0; i < m; i++)
        for (int j = 0; j < n; j++)
            at[j * m + i] = a[i * n + j];
}

// y[m] = A[m,n] * x[n]  -- one dot product per output row
void mat_matvec(int32_t *y, const int32_t *a, const int32_t *x,
                int m, int n) {
    for (int i = 0; i < m; i++)
        y[i] = vec_dot(a + i * n, x, n);
}

// C[m,n] = A[m,k] * B[k,n]
//
// Row-accumulation ("outer-product update") strategy:
//   zero C; for each i,p: C[i,:] += A[i,p] * B[p,:]
//
// This keeps all accesses to B sequential (good for cache / vector loads)
// and vectorises the inner n-wide add-scale over the output columns.
void mat_matmul(int32_t *c, const int32_t *a, const int32_t *b,
                int m, int k, int n) {
    mat_zero(c, m * n);
    for (int i = 0; i < m; i++) {
        for (int p = 0; p < k; p++) {
            int32_t aip = a[i * k + p];
            for (int j = 0; j < n; ) {
                size_t vl = __riscv_vsetvl_e32m1(n - j);
                vint32m1_t vc = __riscv_vle32_v_i32m1(VLP(c + i*n + j), vl);
                vint32m1_t vb = __riscv_vle32_v_i32m1(VLP(b + p*n + j), vl);
                // c[i,j..] += aip * b[p,j..]
                vc = __riscv_vadd_vv_i32m1(
                         vc,
                         __riscv_vmul_vx_i32m1(vb, aip, vl),
                         vl);
                __riscv_vse32_v_i32m1(VSP(c + i*n + j), vc, vl);
                j += vl;
            }
        }
    }
}
