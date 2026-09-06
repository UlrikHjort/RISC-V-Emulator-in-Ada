/* **************************************************************************
 *     RISC-V Emulator - F Extension - Single-Precision Floating Point
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

/* F Extension - Single-Precision Floating Point
 * Demonstrates: fadd.s, fsub.s, fmul.s, fdiv.s, fsqrt.s, comparisons
 * Expected return value: 0 (success)
 */

int _main(void) {
    float a = 10.0f, b = 3.0f;
    float result;

    /* Addition: 10.0 + 3.0 = 13.0 */
    result = a + b;
    if (result != 13.0f) return 1;

    /* Subtraction: 10.0 - 3.0 = 7.0 */
    result = a - b;
    if (result != 7.0f) return 2;

    /* Multiplication: 10.0 * 3.0 = 30.0 */
    result = a * b;
    if (result != 30.0f) return 3;

    /* Division: 10.0 / 4.0 = 2.5 */
    result = a / 4.0f;
    if (result != 2.5f) return 4;

    /* Square root: sqrt(16.0) = 4.0 */
    result = __builtin_sqrtf(16.0f);
    if (result != 4.0f) return 5;

    /* Comparisons */
    if (!(a > b)) return 6;
    if (!(a >= b)) return 7;
    if (a < b) return 8;
    if (a == b) return 9;

    /* Negative numbers */
    float c = -5.0f;
    result = c * c;
    if (result != 25.0f) return 10;

    result = a + c;
    if (result != 5.0f) return 11;

    /* Int to float conversion */
    int i = 42;
    result = (float)i;
    if (result != 42.0f) return 12;

    /* Float to int conversion */
    int j = (int)result;
    if (j != 42) return 13;

    return 0;
}
