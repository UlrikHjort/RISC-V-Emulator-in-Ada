/* **************************************************************************
 * RISC-V Emulator - Vector-Accelerated Integer Matrix Library - Interface
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

#ifndef MATLIB_H
#define MATLIB_H

// matlib.h -- Vector-accelerated integer matrix library for RISC-V
//
// All matrices are stored row-major: A[i][j] = data[i*cols + j]
// All operations work on flat int32_t arrays; dimensions are passed
// as separate arguments.
//
// Most functions take `n` = total element count (rows*cols) when the
// operation is elementwise (shape doesn't matter).  Functions that need
// the actual shape take `m`, `k`, `n` etc.

#include <stdint.h>

// -- Element-wise / scalar operations (n = total elements) -----------------

// Zero all n elements.
void    mat_zero    (int32_t *a,                                   int n);

// C[i] = A[i] + B[i]
void    mat_add     (int32_t *c, const int32_t *a, const int32_t *b, int n);

// C[i] = A[i] - B[i]
void    mat_sub     (int32_t *c, const int32_t *a, const int32_t *b, int n);

// C[i] = A[i] * B[i]  (Hadamard / element-wise product)
void    mat_elem_mul(int32_t *c, const int32_t *a, const int32_t *b, int n);

// C[i] = s * A[i]
void    mat_scale   (int32_t *c, const int32_t *a, int32_t s, int n);

// C[i] = -A[i]
void    mat_negate  (int32_t *c, const int32_t *a, int n);

// -- Reductions -------------------------------------------------------------

// Sum of all elements.
int32_t mat_sum         (const int32_t *a, int n);

// Sum of squared elements  (squared Frobenius norm).
int32_t mat_frobenius_sq(const int32_t *a, int n);

// Maximum element.
int32_t mat_max         (const int32_t *a, int n);

// Minimum element.
int32_t mat_min         (const int32_t *a, int n);

// -- Vector operations ------------------------------------------------------

// Dot product of two length-n vectors.
int32_t vec_dot(const int32_t *a, const int32_t *b, int n);

// -- Matrix operations ------------------------------------------------------

// AT[n,m] = transpose of A[m,n].
void mat_transpose(int32_t *at, const int32_t *a, int m, int n);

// y[m] = A[m,n] * x[n]
void mat_matvec(int32_t *y, const int32_t *a, const int32_t *x,
                int m, int n);

// C[m,n] = A[m,k] * B[k,n]
void mat_matmul(int32_t *c, const int32_t *a, const int32_t *b,
                int m, int k, int n);

#endif // MATLIB_H
