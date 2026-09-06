/* **************************************************************************
 *           RISC-V Emulator - M Extension - Multiply and Divide
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

/* M Extension - Multiply and Divide
 * Demonstrates: mul, mulh, mulhu, div, divu, rem, remu
 * Expected return value: 0 (success)
 */

volatile int result[8];

int _main(void) {
    int a = 100, b = 7;
    unsigned int ua = 100, ub = 7;

    /* Multiplication */
    result[0] = a * b;              /* 700 */
    result[1] = (-a) * b;           /* -700 */

    /* Division */
    result[2] = a / b;              /* 14 */
    result[3] = (-a) / b;           /* -14 */
    result[4] = ua / ub;            /* 14 (unsigned) */

    /* Remainder */
    result[5] = a % b;              /* 2 */
    result[6] = (-a) % b;           /* -2 */
    result[7] = ua % ub;            /* 2 (unsigned) */

    /* Verify results */
    if (result[0] != 700) return 1;
    if (result[1] != -700) return 2;
    if (result[2] != 14) return 3;
    if (result[3] != -14) return 4;
    if (result[4] != 14) return 5;
    if (result[5] != 2) return 6;
    if (result[6] != -2) return 7;
    if (result[7] != 2) return 8;

    /* Large multiplication to test mulh */
    int big = 1000000;
    long long product = (long long)big * big;
    if (product != 1000000000000LL) return 9;

    return 0;
	//return result[0];
}
