/* **************************************************************************
 *                 RISC-V Emulator - Vector Extension Test
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

/*
 * Vector Extension Test
 * Tests basic RVV 1.0 functionality
 * Expected return value: 0 (all tests pass)
 */

int _main(void) {
    int errors = 0;
    int vl;
    int scalar_result;

    /* Use stack arrays to avoid gp-relative addressing issues */
    volatile int arr_a[4];
    volatile int arr_b[4];
    volatile int arr_c[4];

    /* Initialize arrays */
    arr_a[0] = 1; arr_a[1] = 2; arr_a[2] = 3; arr_a[3] = 4;
    arr_b[0] = 10; arr_b[1] = 20; arr_b[2] = 30; arr_b[3] = 40;
    arr_c[0] = 0; arr_c[1] = 0; arr_c[2] = 0; arr_c[3] = 0;

    /* Test 1: vsetvli - Configure vector unit for 32-bit elements */
    asm volatile (
        "vsetvli %0, %1, e32, m1, ta, ma"
        : "=r"(vl)
        : "r"(4)
    );
    if (vl != 4) errors++;

    /* Test 2: Vector load and store (unit stride) */
    asm volatile (
        "vle32.v v1, (%0)"
        :
        : "r"(arr_a)
        : "memory"
    );
    asm volatile (
        "vse32.v v1, (%0)"
        :
        : "r"(arr_c)
        : "memory"
    );
    /* Verify copy */
    if (arr_c[0] != 1 || arr_c[1] != 2 || arr_c[2] != 3 || arr_c[3] != 4) {
        errors++;
    }

    /* Test 3: Vector add (vadd.vv) */
    asm volatile (
        "vle32.v v1, (%0)\n\t"
        "vle32.v v2, (%1)\n\t"
        "vadd.vv v3, v1, v2\n\t"
        "vse32.v v3, (%2)"
        :
        : "r"(arr_a), "r"(arr_b), "r"(arr_c)
        : "memory"
    );
    /* Expected: {11, 22, 33, 44} */
    if (arr_c[0] != 11 || arr_c[1] != 22 || arr_c[2] != 33 || arr_c[3] != 44) {
        errors++;
    }

    /* Test 4: Vector add immediate (vadd.vi) */
    asm volatile (
        "vle32.v v1, (%0)\n\t"
        "vadd.vi v2, v1, 5\n\t"
        "vse32.v v2, (%1)"
        :
        : "r"(arr_a), "r"(arr_c)
        : "memory"
    );
    /* Expected: {6, 7, 8, 9} */
    if (arr_c[0] != 6 || arr_c[1] != 7 || arr_c[2] != 8 || arr_c[3] != 9) {
        errors++;
    }

    /* Test 5: Vector subtract (vsub.vv) */
    asm volatile (
        "vle32.v v1, (%0)\n\t"
        "vle32.v v2, (%1)\n\t"
        "vsub.vv v3, v2, v1\n\t"
        "vse32.v v3, (%2)"
        :
        : "r"(arr_a), "r"(arr_b), "r"(arr_c)
        : "memory"
    );
    /* Expected: {9, 18, 27, 36} */
    if (arr_c[0] != 9 || arr_c[1] != 18 || arr_c[2] != 27 || arr_c[3] != 36) {
        errors++;
    }

    /* Test 6: Vector AND (vand.vv) */
    volatile int and_a[4];
    volatile int and_b[4];
    and_a[0] = 0xFF; and_a[1] = 0xF0; and_a[2] = 0x0F; and_a[3] = 0x55;
    and_b[0] = 0x0F; and_b[1] = 0x0F; and_b[2] = 0x0F; and_b[3] = 0xAA;

    asm volatile (
        "vle32.v v1, (%0)\n\t"
        "vle32.v v2, (%1)\n\t"
        "vand.vv v3, v1, v2\n\t"
        "vse32.v v3, (%2)"
        :
        : "r"(and_a), "r"(and_b), "r"(arr_c)
        : "memory"
    );
    /* Expected: {0x0F, 0x00, 0x0F, 0x00} */
    if (arr_c[0] != 0x0F || arr_c[1] != 0x00 || arr_c[2] != 0x0F || arr_c[3] != 0x00) {
        errors++;
    }

    /* Test 7: Vector OR (vor.vv) */
    asm volatile (
        "vle32.v v1, (%0)\n\t"
        "vle32.v v2, (%1)\n\t"
        "vor.vv v3, v1, v2\n\t"
        "vse32.v v3, (%2)"
        :
        : "r"(and_a), "r"(and_b), "r"(arr_c)
        : "memory"
    );
    /* Expected: {0xFF, 0xFF, 0x0F, 0xFF} */
    if (arr_c[0] != 0xFF || arr_c[1] != 0xFF || arr_c[2] != 0x0F || arr_c[3] != 0xFF) {
        errors++;
    }

    /* Test 8: Vector shift left (vsll.vi) */
    asm volatile (
        "vle32.v v1, (%0)\n\t"
        "vsll.vi v2, v1, 2\n\t"
        "vse32.v v2, (%1)"
        :
        : "r"(arr_a), "r"(arr_c)
        : "memory"
    );
    /* Expected: {4, 8, 12, 16} */
    if (arr_c[0] != 4 || arr_c[1] != 8 || arr_c[2] != 12 || arr_c[3] != 16) {
        errors++;
    }

    /* Test 9: Vector move scalar to x register (vmv.x.s) */
    asm volatile (
        "vle32.v v1, (%1)\n\t"
        "vmv.x.s %0, v1"
        : "=r"(scalar_result)
        : "r"(arr_a)
        : "memory"
    );
    /* Expected: first element = 1 */
    if (scalar_result != 1) errors++;

    /* Test 10: Vector reduction sum (vredsum.vs) */
    volatile int sum_init[4];
    sum_init[0] = 0; sum_init[1] = 0; sum_init[2] = 0; sum_init[3] = 0;
    asm volatile (
        "vle32.v v1, (%1)\n\t"  /* Load arr_a: {1,2,3,4} */
        "vle32.v v2, (%2)\n\t"  /* Load initial value: 0 */
        "vredsum.vs v3, v1, v2\n\t"
        "vmv.x.s %0, v3"
        : "=r"(scalar_result)
        : "r"(arr_a), "r"(sum_init)
        : "memory"
    );
    /* Expected: 1+2+3+4 = 10 */
    if (scalar_result != 10) errors++;

    /* Test 11: Vector multiply (vmul.vv) */
    volatile int mul_a[4];
    volatile int mul_b[4];
    mul_a[0] = 2; mul_a[1] = 3; mul_a[2] = 4; mul_a[3] = 5;
    mul_b[0] = 3; mul_b[1] = 4; mul_b[2] = 5; mul_b[3] = 6;

    asm volatile (
        "vle32.v v1, (%0)\n\t"
        "vle32.v v2, (%1)\n\t"
        "vmul.vv v3, v1, v2\n\t"
        "vse32.v v3, (%2)"
        :
        : "r"(mul_a), "r"(mul_b), "r"(arr_c)
        : "memory"
    );
    /* Expected: {6, 12, 20, 30} */
    if (arr_c[0] != 6 || arr_c[1] != 12 || arr_c[2] != 20 || arr_c[3] != 30) {
        errors++;
    }

    /* Test 12: vmv.v.x - Splat scalar to vector */
    asm volatile (
        "vmv.v.x v1, %1\n\t"
        "vse32.v v1, (%0)"
        :
        : "r"(arr_c), "r"(42)
        : "memory"
    );
    /* Expected: {42, 42, 42, 42} */
    if (arr_c[0] != 42 || arr_c[1] != 42 || arr_c[2] != 42 || arr_c[3] != 42) {
        errors++;
    }

    /* Test 13: vmv.v.i - Splat immediate to vector */
    asm volatile (
        "vmv.v.i v1, 7\n\t"
        "vse32.v v1, (%0)"
        :
        : "r"(arr_c)
        : "memory"
    );
    /* Expected: {7, 7, 7, 7} */
    if (arr_c[0] != 7 || arr_c[1] != 7 || arr_c[2] != 7 || arr_c[3] != 7) {
        errors++;
    }

    /* Test 14: vid.v - Vector element index */
    asm volatile (
        "vid.v v1\n\t"
        "vse32.v v1, (%0)"
        :
        : "r"(arr_c)
        : "memory"
    );
    /* Expected: {0, 1, 2, 3} */
    if (arr_c[0] != 0 || arr_c[1] != 1 || arr_c[2] != 2 || arr_c[3] != 3) {
        errors++;
    }

    return errors;
}
