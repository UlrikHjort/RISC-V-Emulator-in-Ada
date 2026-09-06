/* **************************************************************************
 *        RISC-V Emulator - V Extension - Vector Operations (Basic)
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

/* V Extension - Vector Operations (Basic)
 * Demonstrates: vsetvli, vle32.v, vse32.v, vadd.vv, vmul.vv
 * Expected return value: 0 (success)
 */

#define ARRAY_SIZE 4

int _main(void) {
    volatile int a[ARRAY_SIZE] = {1, 2, 3, 4};
    volatile int b[ARRAY_SIZE] = {10, 20, 30, 40};
    volatile int sum[ARRAY_SIZE];
    volatile int prod[ARRAY_SIZE];

    /* Set vector length for 32-bit elements */
    int vl;
    asm volatile (
        "vsetvli %0, %1, e32, m1, ta, ma"
        : "=r"(vl)
        : "r"(ARRAY_SIZE)
    );

    if (vl != ARRAY_SIZE) return 1;

    /* Vector addition: sum = a + b */
    asm volatile (
        "vle32.v v1, (%0)\n\t"     /* v1 = a */
        "vle32.v v2, (%1)\n\t"     /* v2 = b */
        "vadd.vv v3, v1, v2\n\t"   /* v3 = v1 + v2 */
        "vse32.v v3, (%2)"         /* sum = v3 */
        :
        : "r"(a), "r"(b), "r"(sum)
        : "memory"
    );

    /* Verify addition: 11, 22, 33, 44 */
    if (sum[0] != 11) return 2;
    if (sum[1] != 22) return 3;
    if (sum[2] != 33) return 4;
    if (sum[3] != 44) return 5;

    /* Vector multiplication: prod = a * b */
    asm volatile (
        "vle32.v v1, (%0)\n\t"
        "vle32.v v2, (%1)\n\t"
        "vmul.vv v3, v1, v2\n\t"
        "vse32.v v3, (%2)"
        :
        : "r"(a), "r"(b), "r"(prod)
        : "memory"
    );

    /* Verify multiplication: 10, 40, 90, 160 */
    if (prod[0] != 10) return 6;
    if (prod[1] != 40) return 7;
    if (prod[2] != 90) return 8;
    if (prod[3] != 160) return 9;

    return 0;
}
