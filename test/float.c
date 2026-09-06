/* **************************************************************************
 *      RISC-V Emulator - Test floating-point operations (F extension)
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

// Test floating-point operations (F extension)
// Returns 1 if all tests pass, 0 otherwise

int _main(void) {
    float a = 3.0f;
    float b = 2.0f;
    float result;
    int pass = 1;

    // Test addition: 3.0 + 2.0 = 5.0
    result = a + b;
    if (result != 5.0f) pass = 0;

    // Test subtraction: 3.0 - 2.0 = 1.0
    result = a - b;
    if (result != 1.0f) pass = 0;

    // Test multiplication: 3.0 * 2.0 = 6.0
    result = a * b;
    if (result != 6.0f) pass = 0;

    // Test division: 3.0 / 2.0 = 1.5
    result = a / b;
    if (result != 1.5f) pass = 0;

    // Test conversion from int to float and back
    int i = 42;
    float f = (float)i;
    int j = (int)f;
    if (j != 42) pass = 0;

    // Test comparison
    if (a <= b) pass = 0;  // 3.0 > 2.0
    if (!(a > b)) pass = 0;

    return pass;
}
