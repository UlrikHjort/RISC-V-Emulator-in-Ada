/* **************************************************************************
 *             RISC-V Emulator - Fibonacci sequence calculator
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

// Fibonacci sequence calculator
// Tests: recursion, stack, loops, integer math
// By Ulrik Hørlyk Hjort 2026

int printf(const char *fmt, ...);

// Recursive fibonacci (slow but tests stack depth)
int fib_recursive(int n) {
    if (n <= 1) return n;
    return fib_recursive(n - 1) + fib_recursive(n - 2);
}

// Iterative fibonacci (fast)
int fib_iterative(int n) {
    if (n <= 1) return n;

    int a = 0, b = 1;
    for (int i = 2; i <= n; i++) {
        int temp = a + b;
        a = b;
        b = temp;
    }
    return b;
}

int main(void) {
    printf("=== Fibonacci Sequence ===\n\n");

    printf("Iterative method (fast):\n");
    for (int i = 0; i < 20; i++) {
        printf("fib(%d) = %d\n", i, fib_iterative(i));
    }

    printf("\nRecursive method (slow, tests stack):\n");
    for (int i = 0; i < 15; i++) {  // Only to 15, gets slow!
        printf("fib(%d) = %d\n", i, fib_recursive(i));
    }

    printf("\nDone!\n");
    while (1);
    return 0;
}
