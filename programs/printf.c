/* **************************************************************************
 *   RISC-V Emulator - printf / sprintf / snprintf for Bare-Metal RISC-V
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

// Simple printf/sprintf/snprintf implementation for bare-metal RISC-V
// Supports: %d %u %x %X %s %c %% %f %e %g  (+width, zero-pad, precision)
// By Ulrik Hørlyk Hjort 2026

#include <stdarg.h>

// External functions
void putchar(char c);
extern void put_string(const char *s);  // From syscalls.c
extern void put_int(int val);            // From syscalls.c

// Floating-point conversion functions from ftoa.c
extern void ftoa_fixed(double val, char *buf, int precision);
extern void ftoa_exp(double val, char *buf, int precision);
extern void ftoa_general(double val, char *buf, int precision);

// Print unsigned integer
static void put_uint(unsigned int val) {
    char buf[12];
    int i = 0;

    do {
        buf[i++] = '0' + (val % 10);
        val /= 10;
    } while (val > 0);

    while (i > 0) {
        putchar(buf[--i]);
    }
}

// Print hexadecimal
static void put_hex(unsigned int val) {
    char buf[9];
    int i = 0;
    const char *hex = "0123456789abcdef";

    do {
        buf[i++] = hex[val & 0xF];
        val >>= 4;
    } while (val > 0);

    while (i > 0) {
        putchar(buf[--i]);
    }
}

// Helper: parse precision from format string (e.g., %.2f returns 2)
static int parse_precision(const char **fmt_ptr) {
    const char *fmt = *fmt_ptr;
    int precision = -1;  // -1 means no precision specified

    if (*fmt == '.') {
        fmt++;
        precision = 0;
        while (*fmt >= '0' && *fmt <= '9') {
            precision = precision * 10 + (*fmt - '0');
            fmt++;
        }
    }

    *fmt_ptr = fmt;
    return precision;
}

// Simple printf implementation
int printf(const char *fmt, ...) {
    va_list args;
    va_start(args, fmt);

    while (*fmt) {
        if (*fmt == '%') {
            fmt++;

            // Parse flags (zero-padding)
            int zero_pad = 0;
            if (*fmt == '0') {
                zero_pad = 1;
                fmt++;
            }

            // Parse width
            int width = 0;
            while (*fmt >= '0' && *fmt <= '9') {
                width = width * 10 + (*fmt - '0');
                fmt++;
            }

            // Parse precision if present (e.g., %.2f)
            int precision = parse_precision(&fmt);

            // Suppress unused variable warnings
            (void)zero_pad;
            (void)width;

            switch (*fmt) {
                case 'd': {  // Signed decimal
                    int val = va_arg(args, int);
                    put_int(val);
                    break;
                }
                case 'u': {  // Unsigned decimal
                    unsigned int val = va_arg(args, unsigned int);
                    put_uint(val);
                    break;
                }
                case 'x':  // Hexadecimal (lowercase)
                case 'X': {  // Hexadecimal (uppercase) - TODO: implement uppercase
                    unsigned int val = va_arg(args, unsigned int);
                    put_hex(val);
                    break;
                }
                case 's': {  // String
                    const char *s = va_arg(args, const char *);
                    put_string(s ? s : "(null)");
                    break;
                }
                case 'c': {  // Character
                    char c = (char)va_arg(args, int);
                    putchar(c);
                    break;
                }
                case '%': {  // Literal %
                    putchar('%');
                    break;
                }
                case 'f': {  // Floating-point (fixed)
                    double val = va_arg(args, double);
                    char buf[64];
                    if (precision < 0) precision = 6;  // Default precision for %f
                    ftoa_fixed(val, buf, precision);
                    put_string(buf);
                    break;
                }
                case 'e': {  // Floating-point (exponential)
                    double val = va_arg(args, double);
                    char buf[64];
                    if (precision < 0) precision = 6;  // Default precision for %e
                    ftoa_exp(val, buf, precision);
                    put_string(buf);
                    break;
                }
                case 'g': {  // Floating-point (general)
                    double val = va_arg(args, double);
                    char buf[64];
                    if (precision < 0) precision = 6;  // Default precision for %g
                    ftoa_general(val, buf, precision);
                    put_string(buf);
                    break;
                }
                default:
                    putchar('%');
                    putchar(*fmt);
                    break;
            }
            fmt++;
        } else {
            putchar(*fmt++);
        }
    }

    va_end(args);
    return 0;
}

/* -- vsnprintf / snprintf / sprintf ---------------------------------------- */

/* Emit one character to buffer; always increments pos for return-value counting */
static inline int snp_emit(char *buf, int size, int pos, char c) {
    if (pos < size - 1) buf[pos] = c;
    return pos + 1;
}

/* Emit a NUL-terminated string to buffer, right-justified in 'width' columns */
static int snp_str(char *buf, int size, int pos, const char *s, int width) {
    int len = 0;
    const char *p = s;
    while (*p) { len++; p++; }
    for (int i = len; i < width; i++) pos = snp_emit(buf, size, pos, ' ');
    for (int i = 0; i < len; i++)     pos = snp_emit(buf, size, pos, s[i]);
    return pos;
}

/* Emit signed decimal integer, with optional width and zero-padding */
static int snp_int(char *buf, int size, int pos, int val, int width, int zero_pad) {
    char tmp[12]; int n = 0;
    int neg = (val < 0);
    unsigned int uval = neg ? (unsigned int)(-(val + 1)) + 1u : (unsigned int)val;
    do { tmp[n++] = '0' + (int)(uval % 10); uval /= 10; } while (uval);
    int total = n + (neg ? 1 : 0);
    int pad = (width > total) ? width - total : 0;
    if (zero_pad && neg) pos = snp_emit(buf, size, pos, '-');
    for (int i = 0; i < pad; i++) pos = snp_emit(buf, size, pos, zero_pad ? '0' : ' ');
    if (!zero_pad && neg) pos = snp_emit(buf, size, pos, '-');
    while (n > 0) pos = snp_emit(buf, size, pos, tmp[--n]);
    return pos;
}

/* Emit unsigned decimal integer */
static int snp_uint(char *buf, int size, int pos, unsigned int val, int width, int zero_pad) {
    char tmp[11]; int n = 0;
    do { tmp[n++] = '0' + (int)(val % 10); val /= 10; } while (val);
    for (int i = n; i < width; i++) pos = snp_emit(buf, size, pos, zero_pad ? '0' : ' ');
    while (n > 0) pos = snp_emit(buf, size, pos, tmp[--n]);
    return pos;
}

/* Emit unsigned hex integer */
static int snp_hex(char *buf, int size, int pos, unsigned int val,
                   int width, int zero_pad, int upper) {
    const char *digits = upper ? "0123456789ABCDEF" : "0123456789abcdef";
    char tmp[9]; int n = 0;
    do { tmp[n++] = digits[val & 0xF]; val >>= 4; } while (val);
    for (int i = n; i < width; i++) pos = snp_emit(buf, size, pos, zero_pad ? '0' : ' ');
    while (n > 0) pos = snp_emit(buf, size, pos, tmp[--n]);
    return pos;
}

int vsnprintf(char *buf, int size, const char *fmt, va_list args) {
    int pos = 0;
    if (size <= 0) return 0;

    while (*fmt) {
        if (*fmt != '%') { pos = snp_emit(buf, size, pos, *fmt++); continue; }
        fmt++;

        int zero_pad = 0;
        if (*fmt == '0') { zero_pad = 1; fmt++; }

        int width = 0;
        while (*fmt >= '0' && *fmt <= '9') { width = width * 10 + (*fmt++ - '0'); }

        int precision = -1;
        if (*fmt == '.') {
            fmt++; precision = 0;
            while (*fmt >= '0' && *fmt <= '9') precision = precision * 10 + (*fmt++ - '0');
        }

        switch (*fmt) {
        case 'd': pos = snp_int(buf, size, pos, va_arg(args, int), width, zero_pad); break;
        case 'u': pos = snp_uint(buf, size, pos, va_arg(args, unsigned int), width, zero_pad); break;
        case 'x': pos = snp_hex(buf, size, pos, va_arg(args, unsigned int), width, zero_pad, 0); break;
        case 'X': pos = snp_hex(buf, size, pos, va_arg(args, unsigned int), width, zero_pad, 1); break;
        case 's': {
            const char *s = va_arg(args, const char *);
            pos = snp_str(buf, size, pos, s ? s : "(null)", width);
            break;
        }
        case 'c': pos = snp_emit(buf, size, pos, (char)va_arg(args, int)); break;
        case '%': pos = snp_emit(buf, size, pos, '%'); break;
        case 'f': case 'e': case 'g': {
            double val = va_arg(args, double);
            char tmp[64];
            if (precision < 0) precision = 6;
            if (*fmt == 'f')      ftoa_fixed(val, tmp, precision);
            else if (*fmt == 'e') ftoa_exp(val, tmp, precision);
            else                  ftoa_general(val, tmp, precision);
            pos = snp_str(buf, size, pos, tmp, width);
            break;
        }
        default: pos = snp_emit(buf, size, pos, '%'); pos = snp_emit(buf, size, pos, *fmt); break;
        }
        fmt++;
    }

    /* NUL-terminate; pos may exceed size-1 if output was truncated */
    buf[pos < size ? pos : size - 1] = '\0';
    return pos; /* total chars that would be written (C99 semantics) */
}

int snprintf(char *buf, int size, const char *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    int r = vsnprintf(buf, size, fmt, args);
    va_end(args);
    return r;
}

int sprintf(char *buf, const char *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    int r = vsnprintf(buf, 4096, fmt, args);
    va_end(args);
    return r;
}
