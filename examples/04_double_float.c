/* **************************************************************************
 *     RISC-V Emulator - D Extension - Double-Precision Floating Point
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

/* D Extension - Double-Precision Floating Point
 * Demonstrates: fadd.d, fsub.d, fmul.d, fdiv.d, fsqrt.d, conversions
 * Expected return value: 0 (success)
 */

int _main(void) {
    double a = 10.0, b = 3.0;
    double result;

    /* Addition: 10.0 + 3.0 = 13.0 */
    result = a + b;
    if (result != 13.0) return 1;

    /* Subtraction: 10.0 - 3.0 = 7.0 */
    result = a - b;
    if (result != 7.0) return 2;

    /* Multiplication: 10.0 * 3.0 = 30.0 */
    result = a * b;
    if (result != 30.0) return 3;

    /* Division: 10.0 / 4.0 = 2.5 */
    result = a / 4.0;
    if (result != 2.5) return 4;

    /* Square root: sqrt(16.0) = 4.0 */
    result = __builtin_sqrt(16.0);
    if (result != 4.0) return 5;

    /* Comparisons */
    if (!(a > b)) return 6;
    if (!(a >= b)) return 7;
    if (a < b) return 8;
    if (a == b) return 9;

    /* Float to double conversion */
    float f = 2.5f;
    result = (double)f;
    if (result != 2.5) return 10;

    /* Double to float conversion */
    double d = 3.5;
    f = (float)d;
    if (f != 3.5f) return 11;

    /* Int to double conversion */
    int i = 100;
    result = (double)i;
    if (result != 100.0) return 12;

    /* Double to int conversion */
    int j = (int)result;
    if (j != 100) return 13;

    return 0;
}
