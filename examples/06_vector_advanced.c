/* **************************************************************************
 *       RISC-V Emulator - V Extension - Vector Operations (Advanced)
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

/* V Extension - Vector Operations (Advanced)
 * Demonstrates: reductions, scalar ops, vid.v, strided access
 * Expected return value: 0 (success)
 */

#define ARRAY_SIZE 4

int _main(void) {
    volatile int data[ARRAY_SIZE] = {1, 2, 3, 4};
    volatile int indices[ARRAY_SIZE];
    volatile int scaled[ARRAY_SIZE];

    int vl;
    asm volatile (
        "vsetvli %0, %1, e32, m1, ta, ma"
        : "=r"(vl)
        : "r"(ARRAY_SIZE)
    );

    /* Generate index sequence using vid.v */
    asm volatile (
        "vid.v v1\n\t"             /* v1 = {0, 1, 2, 3} */
        "vse32.v v1, (%0)"
        :
        : "r"(indices)
        : "memory"
    );

    if (indices[0] != 0) return 1;
    if (indices[1] != 1) return 2;
    if (indices[2] != 2) return 3;
    if (indices[3] != 3) return 4;

    /* Scalar-vector operations: scaled = data * 5 */
    asm volatile (
        "vle32.v v1, (%0)\n\t"
        "vmul.vx v2, v1, %1\n\t"   /* multiply by scalar 5 */
        "vse32.v v2, (%2)"
        :
        : "r"(data), "r"(5), "r"(scaled)
        : "memory"
    );

    /* Verify: 5, 10, 15, 20 */
    if (scaled[0] != 5) return 5;
    if (scaled[1] != 10) return 6;
    if (scaled[2] != 15) return 7;
    if (scaled[3] != 20) return 8;

    /* Vector reduction: sum all elements */
    volatile int sum_result[1] = {0};
    asm volatile (
        "vle32.v v1, (%0)\n\t"
        "vmv.v.i v2, 0\n\t"        /* v2 = 0 (accumulator) */
        "vredsum.vs v3, v1, v2\n\t"/* v3[0] = sum(v1) + v2[0] */
        "vse32.v v3, (%1)"
        :
        : "r"(data), "r"(sum_result)
        : "memory"
    );

    /* Verify: 1+2+3+4 = 10 */
    if (sum_result[0] != 10) return 9;

    /* Min/max reductions */
    volatile int minmax[2] = {0, 0};
    volatile int test_data[ARRAY_SIZE] = {7, 2, 9, 4};

    asm volatile (
        "vle32.v v1, (%0)\n\t"
        "vmv.v.x v2, %1\n\t"       /* v2 = INT_MAX */
        "vredmin.vs v3, v1, v2\n\t"
        "vse32.v v3, (%2)"
        :
        : "r"(test_data), "r"(0x7FFFFFFF), "r"(minmax)
        : "memory"
    );

    if (minmax[0] != 2) return 10;  /* min = 2 */

    asm volatile (
        "vle32.v v1, (%0)\n\t"
        "vmv.v.x v2, %1\n\t"       /* v2 = INT_MIN */
        "vredmax.vs v3, v1, v2\n\t"
        "vse32.v v3, (%2)"
        :
        : "r"(test_data), "r"(0x80000000), "r"(minmax + 1)
        : "memory"
    );

    if (minmax[1] != 9) return 11;  /* max = 9 */

    return 0;
}
