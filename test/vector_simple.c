/* **************************************************************************
 *              RISC-V Emulator - Simple Vector Extension Test
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
 * Simple Vector Extension Test
 * Tests just vsetvli and basic load/store
 * Expected return value: 0 (success)
 */

int _main(void) {
    int vl;
    volatile int arr[4];
    volatile int out[4];

    /* Initialize */
    arr[0] = 10;
    arr[1] = 20;
    arr[2] = 30;
    arr[3] = 40;
    out[0] = 0;
    out[1] = 0;
    out[2] = 0;
    out[3] = 0;

    /* Configure for 4 x 32-bit elements */
    asm volatile (
        "vsetvli %0, %1, e32, m1, ta, ma"
        : "=r"(vl)
        : "r"(4)
    );

    /* Check VL */
    if (vl != 4) return 1;

    /* Vector load */
    asm volatile (
        "vle32.v v1, (%0)"
        :
        : "r"(arr)
        : "memory"
    );

    /* Vector store */
    asm volatile (
        "vse32.v v1, (%0)"
        :
        : "r"(out)
        : "memory"
    );

    /* Verify */
    if (out[0] != 10) return 2;
    if (out[1] != 20) return 3;
    if (out[2] != 30) return 4;
    if (out[3] != 40) return 5;

    return 0;  /* Success */
}
