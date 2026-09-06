/* **************************************************************************
 *           RISC-V Emulator - Mandelbrot set ASCII art generator
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

// Mandelbrot set ASCII art generator
// Tests: floating-point arithmetic, nested loops, conditionals
// By Ulrik Hørlyk Hjort 2026

int printf(const char *fmt, ...);
void putchar(char c);

#define WIDTH 80
#define HEIGHT 40
#define MAX_ITER 50

int mandelbrot(double cr, double ci) {
    double zr = 0.0, zi = 0.0;
    int iter = 0;

    while (iter < MAX_ITER) {
        double zr2 = zr * zr;
        double zi2 = zi * zi;

        if (zr2 + zi2 > 4.0) break;

        double new_zr = zr2 - zi2 + cr;
        double new_zi = 2.0 * zr * zi + ci;

        zr = new_zr;
        zi = new_zi;
        iter++;
    }

    return iter;
}

char get_char(int iter) {
    if (iter >= MAX_ITER) return ' ';
    const char *chars = ".:-=+*#%@";
    int idx = (iter * 9) / MAX_ITER;
    return chars[idx];
}

int main(void) {
    printf("=== Mandelbrot Set ===\n");
    printf("Size: %dx%d, Max iterations: %d\n", WIDTH, HEIGHT, MAX_ITER);

    // Mandelbrot bounds
    double x_min = -2.0, x_max = 1.0;
    double y_min = -1.0, y_max = 1.0;

    double dx = (x_max - x_min) / WIDTH;
    double dy = (y_max - y_min) / HEIGHT;

    printf("Region: x=[%.1f, %.1f], y=[%.1f, %.1f]\n", x_min, x_max, y_min, y_max);
    printf("Step: dx=%.6f, dy=%.6f\n\n", dx, dy);

    for (int y = 0; y < HEIGHT; y++) {
        for (int x = 0; x < WIDTH; x++) {
            double cr = x_min + x * dx;
            double ci = y_min + y * dy;

            int iter = mandelbrot(cr, ci);
            putchar(get_char(iter));
        }
        putchar('\n');
    }

    printf("\nDone!\n");
    while (1);
    return 0;
}
