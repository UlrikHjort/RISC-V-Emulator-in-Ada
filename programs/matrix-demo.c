/* **************************************************************************
 *      RISC-V Emulator - comprehensive test of the RVV matrix library
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

// matrix-demo.c -- comprehensive test of the RVV matrix library
//
// Runs a suite of tests covering every function in matlib.c.
// Results are logged to matrix-demo.log via the host logging module.
// PASS/FAIL is also printed to the UART.
//
// Build:  cd programs && make run-matrix-demo
//
// Expected log: matrix-demo.log in the launch directory.
// By Ulrik Hørlyk Hjort 2026

#include "matlib.h"
#include "log.h"
#include <stdint.h>

void putchar(char c);

// -- UART helpers ------------------------------------------------------------

static void uart_puts(const char *s) {
    while (*s) { if (*s == '\n') putchar('\r'); putchar(*s++); }
}

// -- Test infrastructure ------------------------------------------------------

static int g_pass = 0, g_fail = 0;

// Check a scalar result.
static void check(const char *label, int32_t got, int32_t expected) {
    if (got == expected) {
        log_write(NONE, "  PASS  %s\n", label);
        g_pass++;
    } else {
        log_write(NONE, "  FAIL  %s: got %d  expected %d\n",
                  label, got, expected);
        g_fail++;
    }
}

// Check every element of an array against a reference array.
static int check_array(const char *label,
                       const int32_t *got, const int32_t *ref, int n) {
    int ok = 1;
    for (int i = 0; i < n; i++) {
        if (got[i] != ref[i]) {
            log_write(NONE, "  FAIL  %s[%d] got %d  expected %d\n",
                      label, i, got[i], ref[i]);
            ok = 0;
        }
    }
    if (ok) {
        log_write(NONE, "  PASS  %s\n", label);
        g_pass++;
    } else {
        g_fail++;
    }
    return ok;
}

// Print a matrix to the log.
static void log_mat(const char *name, const int32_t *a, int m, int n) {
    log_write(NONE, "  %s [%dx%d]:\n", name, m, n);
    for (int i = 0; i < m; i++) {
        log_write(NONE, "    [");
        for (int j = 0; j < n; j++) {
            if (j) log_write(NONE, ", ");
            log_write(NONE, "%d", a[i*n + j]);
        }
        log_write(NONE, "]\n");
    }
}

// -- Test data ----------------------------------------------------------------

// 4x4 sequential (used in many tests)
static const int32_t A4[16] = {
     1,  2,  3,  4,
     5,  6,  7,  8,
     9, 10, 11, 12,
    13, 14, 15, 16
};

// 4x4 "reverse" (A[i][j] + B[i][j] = 17 everywhere)
static const int32_t B4[16] = {
    16, 15, 14, 13,
    12, 11, 10,  9,
     8,  7,  6,  5,
     4,  3,  2,  1
};

// 4x4 identity
static const int32_t I4[16] = {
    1, 0, 0, 0,
    0, 1, 0, 0,
    0, 0, 1, 0,
    0, 0, 0, 1
};

// 2x3 matrix
static const int32_t A23[6] = {
    1, 2, 3,
    4, 5, 6
};

// 3x2 matrix
static const int32_t B32[6] = {
    7,  8,
    9, 10,
   11, 12
};

// Scratch buffers
static int32_t C[64];   // up to 8x8 result
static int32_t T[64];   // scratch / transpose

// -- Individual test groups ----------------------------------------------------

static void test_elementwise(void) {
    log_write(NONE, "\n=== Element-wise operations ===\n");

    // mat_zero
    for (int i = 0; i < 16; i++) C[i] = 99;
    mat_zero(C, 16);
    {
        int ok = 1;
        for (int i = 0; i < 16; i++) if (C[i] != 0) { ok = 0; break; }
        if (ok) { log_write(NONE, "  PASS  mat_zero (16 elements)\n"); g_pass++; }
        else    { log_write(NONE, "  FAIL  mat_zero\n"); g_fail++; }
    }

    // mat_add: A + B = 17 everywhere
    mat_add(C, A4, B4, 16);
    {
        int ok = 1;
        for (int i = 0; i < 16; i++) if (C[i] != 17) { ok = 0; break; }
        if (ok) { log_write(NONE, "  PASS  mat_add (all elements = 17)\n"); g_pass++; }
        else    { log_write(NONE, "  FAIL  mat_add\n"); g_fail++; }
    }

    // mat_sub: A - A = 0 everywhere
    mat_sub(C, A4, A4, 16);
    {
        int ok = 1;
        for (int i = 0; i < 16; i++) if (C[i] != 0) { ok = 0; break; }
        if (ok) { log_write(NONE, "  PASS  mat_sub (A - A = 0)\n"); g_pass++; }
        else    { log_write(NONE, "  FAIL  mat_sub\n"); g_fail++; }
    }

    // mat_sub: B - A = 17 - 2*A
    // B[i] - A[i] = (17-A[i]) - A[i] = 17 - 2*A[i]
    // spot-check: B[0][0] - A[0][0] = 16-1 = 15
    mat_sub(C, B4, A4, 16);
    check("mat_sub B-A [0][0]", C[0],  15);   // 16-1
    check("mat_sub B-A [0][3]", C[3],   9);   // 13-4
    check("mat_sub B-A [3][0]", C[12], -9);   //  4-13
    check("mat_sub B-A [3][3]", C[15], -15);  //  1-16

    // mat_elem_mul: A * I4 = diagonal of A broadcast
    mat_elem_mul(C, A4, I4, 16);
    // A[i]*I[i]: only diagonal survives: positions 0,5,10,15
    check("mat_elem_mul A*I [0][0]", C[0],  1);
    check("mat_elem_mul A*I [0][1]", C[1],  0);  // 2*0
    check("mat_elem_mul A*I [1][1]", C[5],  6);  // 6*1
    check("mat_elem_mul A*I [2][2]", C[10], 11); // 11*1
    check("mat_elem_mul A*I [3][3]", C[15], 16); // 16*1

    // mat_scale: A * 3
    mat_scale(C, A4, 3, 16);
    check("mat_scale A*3 [0][0]", C[0],  3);
    check("mat_scale A*3 [1][0]", C[4],  15);
    check("mat_scale A*3 [3][3]", C[15], 48);

    // mat_negate: -A
    mat_negate(C, A4, 16);
    check("mat_negate -A [0][0]", C[0],  -1);
    check("mat_negate -A [1][2]", C[6],  -7);
    check("mat_negate -A [3][3]", C[15], -16);
}

static void test_reductions(void) {
    log_write(NONE, "\n=== Reductions ===\n");

    // sum(A4) = 1+2+...+16 = 136
    check("mat_sum A4",        mat_sum(A4, 16), 136);

    // sum(I4) = 4 (identity has 4 ones)
    check("mat_sum I4",        mat_sum(I4, 16), 4);

    // frobenius_sq(I4) = 4 (sum of 1^2 * 4)
    check("mat_frobenius_sq I4", mat_frobenius_sq(I4, 16), 4);

    // frobenius_sq(A4) = 1^2+2^2+...+16^2 = n(n+1)(2n+1)/6, n=16 = 1496
    check("mat_frobenius_sq A4", mat_frobenius_sq(A4, 16), 1496);

    // max(A4) = 16
    check("mat_max A4",        mat_max(A4, 16), 16);

    // max(B4) = 16
    check("mat_max B4",        mat_max(B4, 16), 16);

    // min(A4) = 1
    check("mat_min A4",        mat_min(A4, 16), 1);

    // min(B4) = 1
    check("mat_min B4",        mat_min(B4, 16), 1);

    // Test with negative values: negate A4 then min/max
    mat_negate(C, A4, 16);        // C = [-1,-2,...,-16]
    check("mat_max -A4",       mat_max(C, 16), -1);
    check("mat_min -A4",       mat_min(C, 16), -16);

    // sum of zeros = 0
    mat_zero(C, 8);
    check("mat_sum zeros",     mat_sum(C, 8), 0);
}

static void test_dot_product(void) {
    log_write(NONE, "\n=== vec_dot ===\n");

    // dot(A4[0], A4[0]) = 1^2+2^2+3^2+4^2 = 30
    check("dot row0 with itself",       vec_dot(A4,   A4,   4), 30);

    // dot(A4[1], A4[1]) = 5^2+6^2+7^2+8^2 = 174
    check("dot row1 with itself",       vec_dot(A4+4, A4+4, 4), 174);

    // dot(A4[0], B4[0]) = 1*16+2*15+3*14+4*13 = 16+30+42+52 = 140
    check("dot A4[0] . B4[0]",         vec_dot(A4,   B4,   4), 140);

    // dot([1,2,3,4], [4,3,2,1]) = 4+6+6+4 = 20
    static const int32_t u[4] = {1,2,3,4};
    static const int32_t v[4] = {4,3,2,1};
    check("dot [1,2,3,4].[4,3,2,1]",   vec_dot(u, v, 4), 20);

    // dot with zero vector = 0
    mat_zero(C, 4);
    check("dot with zero vector",       vec_dot(A4, C, 4), 0);

    // dot over 16 elements: A4 . B4 = sum(i*(17-i), i=1..16)
    //   = 17*136 - 1496 = 2312 - 1496 = 816
    check("dot A4 . B4 (16 elems)",     vec_dot(A4, B4, 16), 816);
}

static void test_transpose(void) {
    log_write(NONE, "\n=== mat_transpose ===\n");

    // AT of I4 = I4
    mat_transpose(C, I4, 4, 4);
    check_array("transpose I4 = I4", C, I4, 16);

    // (AT)T = A: double transpose of A4 should give A4 back
    mat_transpose(T, A4, 4, 4);   // T = A4^T  (4x4)
    mat_transpose(C, T, 4, 4);    // C = (A4^T)^T = A4
    check_array("(A4^T)^T = A4", C, A4, 16);

    // Spot-check A4^T values:
    //  A4[0][1]=2  =>  A4^T[1][0]=2   (index 1*4+0=4)
    //  A4[1][0]=5  =>  A4^T[0][1]=5   (index 0*4+1=1)
    //  A4[3][2]=15 =>  A4^T[2][3]=15  (index 2*4+3=11)
    mat_transpose(T, A4, 4, 4);
    check("A4^T [1][0] = 2",  T[1*4+0], 2);
    check("A4^T [0][1] = 5",  T[0*4+1], 5);
    check("A4^T [2][3] = 15", T[2*4+3], 15);

    // Non-square: transpose A23 (2x3) -> (3x2)
    // A23 = [1,2,3; 4,5,6]
    // A23^T = [1,4; 2,5; 3,6]
    static const int32_t A23T_ref[6] = {1,4, 2,5, 3,6};
    mat_transpose(C, A23, 2, 3);
    check_array("transpose A23 (2x3 -> 3x2)", C, A23T_ref, 6);
}

static void test_matvec(void) {
    log_write(NONE, "\n=== mat_matvec ===\n");

    // I4 * x = x
    static const int32_t x4[4]    = {1, 2, 3, 4};
    mat_matvec(C, I4, x4, 4, 4);
    check_array("I4 * [1,2,3,4] = [1,2,3,4]", C, x4, 4);

    // A4 * [1,0,0,0] = first column of A4: [1,5,9,13]
    static const int32_t e0[4]   = {1, 0, 0, 0};
    static const int32_t col0[4] = {1, 5, 9, 13};
    mat_matvec(C, A4, e0, 4, 4);
    check_array("A4 * e0 = col 0 of A4", C, col0, 4);

    // A4 * [0,0,0,1] = last column: [4,8,12,16]
    static const int32_t e3[4]   = {0, 0, 0, 1};
    static const int32_t col3[4] = {4, 8, 12, 16};
    mat_matvec(C, A4, e3, 4, 4);
    check_array("A4 * e3 = col 3 of A4", C, col3, 4);

    // A4 * [1,1,1,1] = row sums of A4: [10,26,42,58]
    static const int32_t ones4[4]    = {1, 1, 1, 1};
    static const int32_t rowsums[4]  = {10, 26, 42, 58};
    mat_matvec(C, A4, ones4, 4, 4);
    check_array("A4 * [1,1,1,1] = row sums", C, rowsums, 4);
}

static void test_matmul(void) {
    log_write(NONE, "\n=== mat_matmul ===\n");

    // A4 * I4 = A4
    mat_matmul(C, A4, I4, 4, 4, 4);
    check_array("A4 * I4 = A4", C, A4, 16);

    // I4 * A4 = A4
    mat_matmul(C, I4, A4, 4, 4, 4);
    check_array("I4 * A4 = A4", C, A4, 16);

    // A4 * B4: pre-computed expected result
    // A4[i,:] . B4[:,j]  (B4 stored row-major, so B4[:,j] = B4[j,j_col])
    // A+B = 17 everywhere, A[i][j] = 4i+j+1, B[i][j] = 17-(4i+j+1) = 16-4i-j
    //
    // C[0][0] = row0.A4 . col0.B4 = [1,2,3,4].[16,12,8,4]  = 16+24+24+16 = 80
    // C[0][1] = [1,2,3,4].[15,11,7,3]  = 15+22+21+12 = 70
    // C[0][2] = [1,2,3,4].[14,10,6,2]  = 14+20+18+8  = 60
    // C[0][3] = [1,2,3,4].[13,9,5,1]   = 13+18+15+4  = 50
    // C[1][0] = [5,6,7,8].[16,12,8,4]  = 80+72+56+32 = 240
    // C[1][1] = [5,6,7,8].[15,11,7,3]  = 75+66+49+24 = 214
    // C[1][2] = [5,6,7,8].[14,10,6,2]  = 70+60+42+16 = 188
    // C[1][3] = [5,6,7,8].[13,9,5,1]   = 65+54+35+8  = 162
    // C[2][0] = [9,10,11,12].[16,12,8,4]= 144+120+88+48= 400
    // C[2][1] = 135+110+77+36 = 358
    // C[2][2] = 126+100+66+24 = 316
    // C[2][3] = 117+90+55+12  = 274
    // C[3][0] = [13,14,15,16].[16,12,8,4]=208+168+120+64=560
    // C[3][1] = 195+154+105+48 = 502
    // C[3][2] = 182+140+90+32  = 444
    // C[3][3] = 169+126+75+16  = 386
    static const int32_t A4xB4[16] = {
         80,  70,  60,  50,
        240, 214, 188, 162,
        400, 358, 316, 274,
        560, 502, 444, 386
    };
    mat_matmul(C, A4, B4, 4, 4, 4);
    check_array("A4 * B4", C, A4xB4, 16);
    log_mat("A4 * B4", C, 4, 4);

    // Non-square: A23 (2x3) * B32 (3x2) = C22 (2x2)
    // C[0][0] = [1,2,3].[7,9,11] = 7+18+33 = 58
    // C[0][1] = [1,2,3].[8,10,12] = 8+20+36 = 64
    // C[1][0] = [4,5,6].[7,9,11] = 28+45+66 = 139
    // C[1][1] = [4,5,6].[8,10,12] = 32+50+72 = 154
    static const int32_t A23xB32[4] = {58, 64, 139, 154};
    mat_matmul(C, A23, B32, 2, 3, 2);
    check_array("A23 * B32 (2x3 @ 3x2 = 2x2)", C, A23xB32, 4);

    // Symmetry: A * A^T should equal (A * A^T)^T
    // (i.e. the result must be symmetric)
    // A4 * A4^T: S[i][j] = dot(A4[i,:], A4[j,:])
    // S[0][0] = 1+4+9+16 = 30
    // S[0][1] = 5+12+21+32 = 70        (= S[1][0])
    // S[0][2] = 9+20+33+48 = 110       (= S[2][0])
    // S[0][3] = 13+28+45+64 = 150      (= S[3][0])
    // S[1][1] = 25+36+49+64 = 174
    // S[1][2] = 45+60+77+96 = 278      (= S[2][1])
    // S[1][3] = 65+84+105+128 = 382    (= S[3][1])
    // S[2][2] = 81+100+121+144 = 446
    // S[2][3] = 117+140+165+192 = 614  (= S[3][2])
    // S[3][3] = 169+196+225+256 = 846
    static const int32_t A4xA4T[16] = {
         30,  70, 110, 150,
         70, 174, 278, 382,
        110, 278, 446, 614,
        150, 382, 614, 846
    };
    mat_transpose(T, A4, 4, 4);       // T = A4^T
    mat_matmul(C, A4, T, 4, 4, 4);   // C = A4 * A4^T
    check_array("A4 * A4^T (symmetric)", C, A4xA4T, 16);
    log_mat("A4 * A4^T", C, 4, 4);

    // Verify symmetry: C[i][j] == C[j][i] for all i,j
    {
        int sym_ok = 1;
        for (int i = 0; i < 4 && sym_ok; i++)
            for (int j = 0; j < 4 && sym_ok; j++)
                if (C[i*4+j] != C[j*4+i]) sym_ok = 0;
        if (sym_ok) { log_write(NONE, "  PASS  A4*A4^T is symmetric\n"); g_pass++; }
        else        { log_write(NONE, "  FAIL  A4*A4^T is not symmetric\n"); g_fail++; }
    }
}

static void test_combined(void) {
    log_write(NONE, "\n=== Combined / regression tests ===\n");

    // (A+B)*x = A*x + B*x   (distributivity)
    static const int32_t x4[4] = {1, -1, 2, -2};
    int32_t AB[16];
    int32_t Ax[4], Bx[4], AxpBx[4], ABx[4];

    mat_add(AB, A4, B4, 16);         // AB = A+B (all 17s)
    mat_matvec(Ax,  A4, x4, 4, 4);
    mat_matvec(Bx,  B4, x4, 4, 4);
    mat_add(AxpBx, Ax, Bx, 4);       // Ax + Bx
    mat_matvec(ABx, AB, x4, 4, 4);   // (A+B)x
    check_array("(A+B)x = Ax + Bx", ABx, AxpBx, 4);

    // (A*B)*x = A*(B*x)   (associativity)
    int32_t BC[16], ABCx[4], Ax2[4], BC_x[4];
    mat_matmul(BC, A4, B4, 4, 4, 4);  // BC = A4*B4
    mat_matvec(BC_x,  BC, x4, 4, 4);  // (A*B)*x
    mat_matvec(Ax2,   B4, x4, 4, 4);  // B*x
    mat_matvec(ABCx, A4, Ax2, 4, 4);  // A*(B*x)
    check_array("(A*B)*x = A*(B*x)", BC_x, ABCx, 4);

    // Frobenius: ||s*A||^2 = s^2 * ||A||^2
    int32_t sA[16];
    mat_scale(sA, A4, 2, 16);
    int32_t fA  = mat_frobenius_sq(A4, 16);   // 1496
    int32_t fsA = mat_frobenius_sq(sA, 16);   // 4*1496 = 5984
    check("||2*A||^2 = 4*||A||^2", fsA, 4 * fA);

    // Sum: sum(A+B) = sum(A) + sum(B)
    int32_t AB2[16];
    mat_add(AB2, A4, B4, 16);
    check("sum(A+B) = sum(A)+sum(B)",
          mat_sum(AB2, 16),
          mat_sum(A4, 16) + mat_sum(B4, 16));

    // Negate: A + (-A) = 0
    int32_t negA[16];
    mat_negate(negA, A4, 16);
    mat_add(C, A4, negA, 16);
    {
        int ok = 1;
        for (int i = 0; i < 16; i++) if (C[i] != 0) { ok = 0; break; }
        if (ok) { log_write(NONE, "  PASS  A + (-A) = 0\n"); g_pass++; }
        else    { log_write(NONE, "  FAIL  A + (-A) != 0\n"); g_fail++; }
    }

    // Hadamard with identity diagonal:
    // elem_mul(A, I) extracts the diagonal; sum should = 1+6+11+16 = 34
    int32_t diag[16];
    mat_elem_mul(diag, A4, I4, 16);
    check("sum(A * I4) = trace(A4) = 34", mat_sum(diag, 16), 34);
}

static void test_cycle_costs(void) {
    log_write(NONE, "\n=== Cycle-count profiling ===\n");
    log_write(NONE, "  (Subtract adjacent [XXXXXXXX] timestamps)\n");

    log_write(CYCLES, "mat_zero 16\n");
    mat_zero(C, 16);
    log_write(CYCLES, "mat_zero done\n");

    log_write(CYCLES, "mat_add 16\n");
    mat_add(C, A4, B4, 16);
    log_write(CYCLES, "mat_add done\n");

    log_write(CYCLES, "mat_scale 16\n");
    mat_scale(C, A4, 7, 16);
    log_write(CYCLES, "mat_scale done\n");

    log_write(CYCLES, "mat_sum 16\n");
    mat_sum(A4, 16);
    log_write(CYCLES, "mat_sum done\n");

    log_write(CYCLES, "mat_frobenius_sq 16\n");
    mat_frobenius_sq(A4, 16);
    log_write(CYCLES, "mat_frobenius_sq done\n");

    log_write(CYCLES, "vec_dot 16\n");
    vec_dot(A4, B4, 16);
    log_write(CYCLES, "vec_dot done\n");

    log_write(CYCLES, "mat_matvec 4x4\n");
    mat_matvec(C, A4, A4, 4, 4);
    log_write(CYCLES, "mat_matvec done\n");

    log_write(CYCLES, "mat_matmul 4x4x4\n");
    mat_matmul(C, A4, B4, 4, 4, 4);
    log_write(CYCLES, "mat_matmul done\n");

    log_write(CYCLES, "mat_matmul 4x4x4 (A*A^T)\n");
    mat_transpose(T, A4, 4, 4);
    mat_matmul(C, A4, T, 4, 4, 4);
    log_write(CYCLES, "mat_matmul A*A^T done\n");
}

// -- Main ----------------------------------------------------------------------

int main(void) {
    uart_puts("=== Matrix Library Test ===\n");

    if (log_init("matrix-demo.log") != 0) {
        uart_puts("ERROR: log_init failed\n");
        return 1;
    }

    log_write(NONE, "=== RVV Matrix Library Test ===\n");
    log_write(NONE, "VLEN=128  =>  VLMAX=4 x int32 per m1 group\n");

    test_elementwise();
    test_reductions();
    test_dot_product();
    test_transpose();
    test_matvec();
    test_matmul();
    test_combined();
    test_cycle_costs();

    log_write(NONE, "\n=== Summary ===\n");
    log_write(NONE, "  PASS: %d\n", g_pass);
    log_write(NONE, "  FAIL: %d\n", g_fail);
    log_write(NONE, "  %s\n", g_fail == 0 ? "ALL TESTS PASSED" : "SOME TESTS FAILED");

    log_regs();
    log_close();

    uart_puts(g_fail == 0 ? "ALL PASSED\n" : "SOME FAILED\n");
    uart_puts("Log: matrix-demo.log\n");
    return g_fail;
}
