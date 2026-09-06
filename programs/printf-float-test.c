/* **************************************************************************
 *           RISC-V Emulator - Floating-point printf test program
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

// Floating-point printf test program
// Tests %f, %e, %g format specifiers with various values and precisions
// By Ulrik Hørlyk Hjort 2026

int printf(const char *fmt, ...);

int main(void) {
    printf("=== Floating-Point Printf Test ===\n\n");

    // Test %f format
    printf("--- Fixed-Point Format (%%f) ---\n");
    printf("Basic: %f\n", 3.14159);
    printf("Precision .2f: %.2f\n", 3.14159);
    printf("Precision .4f: %.4f\n", 3.14159);
    printf("Zero: %f\n", 0.0);
    printf("Negative: %f\n", -123.456);
    printf("Large: %f\n", 12345.6789);
    printf("Small: %f\n", 0.000123);
    printf("Very small: %.10f\n", 0.0000001);
    printf("\n");

    // Test %e format
    printf("--- Exponential Format (%%e) ---\n");
    printf("Basic: %e\n", 3.14159);
    printf("Precision .2e: %.2e\n", 3.14159);
    printf("Precision .4e: %.4e\n", 3.14159);
    printf("Zero: %e\n", 0.0);
    printf("Negative: %e\n", -123.456);
    printf("Large: %e\n", 12345.6789);
    printf("Small: %e\n", 0.000123);
    printf("Very large: %e\n", 1.23e10);
    printf("\n");

    // Test %g format
    printf("--- General Format (%%g) ---\n");
    printf("Pi: %g\n", 3.14159);
    printf("Large (uses e): %g\n", 1234567.89);
    printf("Small (uses e): %g\n", 0.0000001);
    printf("Medium (uses f): %g\n", 123.456);
    printf("Zero: %g\n", 0.0);
    printf("\n");

    // Test special values
    printf("--- Special Values ---\n");
    double inf = 1.0 / 0.0;
    double neg_inf = -1.0 / 0.0;
    double nan = 0.0 / 0.0;
    printf("Infinity: %f\n", inf);
    printf("Negative infinity: %f\n", neg_inf);
    printf("NaN: %f\n", nan);
    printf("\n");

    // Test rounding
    printf("--- Rounding Tests ---\n");
    printf("1.5 with .0f: %.0f\n", 1.5);
    printf("2.5 with .0f: %.0f\n", 2.5);
    printf("1.234 with .2f: %.2f\n", 1.234);
    printf("1.235 with .2f: %.2f\n", 1.235);
    printf("1.9999 with .2f: %.2f\n", 1.9999);
    printf("\n");

    // Test mixed formats
    printf("--- Mixed Format Tests ---\n");
    printf("Int: %d, Float: %f, Hex: 0x%x\n", 42, 3.14, 0xFF);
    printf("Multiple floats: %f %f %f\n", 1.1, 2.2, 3.3);
    printf("Precision mix: %.1f %.2f %.3f\n", 1.111, 2.222, 3.333);
    printf("\n");

    // Real-world examples
    printf("--- Real-World Examples ---\n");
    printf("Temperature: %.1fdegC\n", 23.7);
    printf("Distance: %.2f km\n", 42.195);
    printf("Scientific: %.3e mol/L\n", 6.022e23);
    printf("Percentage: %.2f%%\n", 98.6);
    printf("Currency: $%.2f\n", 19.99);
    printf("\n");

    // Mandelbrot example values
    printf("--- Mandelbrot Values ---\n");
    printf("x_min: %f\n", -2.0);
    printf("x_max: %f\n", 1.0);
    printf("y_min: %f\n", -1.0);
    printf("y_max: %f\n", 1.0);
    double dx = (1.0 - (-2.0)) / 80.0;
    double dy = (1.0 - (-1.0)) / 40.0;
    printf("dx: %f\n", dx);
    printf("dy: %f\n", dy);
    printf("dx (scientific): %e\n", dx);
    printf("dy (scientific): %e\n", dy);
    printf("\n");

    // Edge cases
    printf("--- Edge Cases ---\n");
    printf("Negative zero: %f\n", -0.0);
    printf("Very small positive: %e\n", 1e-10);
    printf("Very small negative: %e\n", -1e-10);
    printf("Almost 1: %.10f\n", 0.9999999999);
    printf("Just over 1: %.10f\n", 1.0000000001);
    printf("\n");

    printf("All floating-point printf tests complete!\n");
    printf("Visual inspection required for correctness.\n\n");

    while (1);
    return 0;
}
