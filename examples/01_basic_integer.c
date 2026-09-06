/* **************************************************************************
 *            RISC-V Emulator - Basic Integer Operations (RV32I)
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

/* Basic Integer Operations (RV32I)
 * Demonstrates: arithmetic, logical, shifts, branches, loads/stores
 * Expected return value: 0 (success)
 */

volatile int result[8];

int _main(void) {
    int a = 10, b = 3;

    /* Arithmetic operations */
    result[0] = a + b;      /* 13 */
    result[1] = a - b;      /* 7 */

    /* Logical operations */
    result[2] = a & b;      /* 2 */
    result[3] = a | b;      /* 11 */
    result[4] = a ^ b;      /* 9 */

    /* Shift operations */
    result[5] = a << 2;     /* 40 */
    result[6] = a >> 1;     /* 5 */
    result[7] = (-8) >> 2;  /* -2 (arithmetic shift) */

    /* Verify results */
    if (result[0] != 13) return 1;
    if (result[1] != 7) return 2;
    if (result[2] != 2) return 3;
    if (result[3] != 11) return 4;
    if (result[4] != 9) return 5;
    if (result[5] != 40) return 6;
    if (result[6] != 5) return 7;
    if (result[7] != -2) return 8;

    /* Test branches and comparisons */
    int count = 0;
    for (int i = 0; i < 5; i++) {
        count += i;
    }
    if (count != 10) return 9;  /* 0+1+2+3+4 = 10 */

    return 0;
}
