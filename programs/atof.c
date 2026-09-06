/* **************************************************************************
 *     RISC-V Emulator - Floating-point string conversion: atof, strtod
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

// Floating-point string conversion: atof, strtod
// Separated from syscalls.c to avoid pulling FPU into non-FP programs
// By Ulrik Hørlyk Hjort 2026

// strtod: convert string to double, set *endptr past consumed chars
double strtod(const char *str, char **endptr) {
    const char *s = str;
    while (*s == ' ' || *s == '\t' || *s == '\n') s++;

    int neg = 0;
    if (*s == '-') { neg = 1; s++; }
    else if (*s == '+') s++;

    double result = 0.0;
    while (*s >= '0' && *s <= '9') { result = result * 10.0 + (double)(*s++ - '0'); }

    if (*s == '.') {
        s++;
        double divisor = 10.0;
        while (*s >= '0' && *s <= '9') {
            result += (double)(*s++ - '0') / divisor;
            divisor *= 10.0;
        }
    }

    if (*s == 'e' || *s == 'E') {
        s++;
        int exp_neg = 0;
        if (*s == '-') { exp_neg = 1; s++; }
        else if (*s == '+') s++;
        int exp = 0;
        while (*s >= '0' && *s <= '9') { exp = exp * 10 + (*s++ - '0'); }
        double scale = 1.0;
        for (int i = 0; i < exp; i++) scale *= 10.0;
        if (exp_neg) result /= scale; else result *= scale;
    }

    if (endptr) *endptr = (char *)s;
    return neg ? -result : result;
}

// Convert string to double
double atof(const char *str) {
    double result = 0.0;
    double fraction = 0.0;
    double divisor = 1.0;
    int sign = 1;
    int in_fraction = 0;

    // Skip leading whitespace
    while (*str == ' ' || *str == '\t' || *str == '\n') {
        str++;
    }

    // Handle sign
    if (*str == '-') {
        sign = -1;
        str++;
    } else if (*str == '+') {
        str++;
    }

    // Convert digits before decimal point
    while (*str >= '0' && *str <= '9') {
        result = result * 10.0 + (double)(*str - '0');
        str++;
    }

    // Handle decimal point
    if (*str == '.') {
        str++;
        in_fraction = 1;
    }

    // Convert digits after decimal point
    if (in_fraction) {
        while (*str >= '0' && *str <= '9') {
            divisor *= 10.0;
            fraction = fraction * 10.0 + (double)(*str - '0');
            str++;
        }
        result += fraction / divisor;
    }

    return (double)sign * result;
}
