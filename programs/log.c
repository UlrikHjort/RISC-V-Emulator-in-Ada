/* **************************************************************************
 *      RISC-V Emulator - Host logging module for the RISC-V emulator
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

// Host logging module for the RISC-V emulator.
// See log.h for the public API.
// By Ulrik Hørlyk Hjort 2026

#include "log.h"
#include <stdarg.h>

// ============================================================================
// Custom host syscall numbers (intercepted by the emulator before trap entry)
// ============================================================================

#define SYS_HOST_LOG_OPEN    0x500
#define SYS_HOST_LOG_WRITE   0x501
#define SYS_HOST_LOG_CLOSE   0x502
#define SYS_HOST_LOG_REGS    0x503
#define SYS_HOST_GET_TIME_MS 0x504   // returns ms since midnight as Word

// Maximum size of a single log_write() message (stack-allocated buffer).
#define LOG_BUF_SIZE 1024

// ============================================================================
// Low-level ECALL helper
// ============================================================================

// Issue an ECALL with the given syscall number and two arguments.
// The emulator reads a7, a0, a1 and returns the result in a0.
static int host_call(int syscall_num, int arg0, int arg1) {
    register int r_a7 asm("a7") = syscall_num;
    register int r_a0 asm("a0") = arg0;
    register int r_a1 asm("a1") = arg1;
    asm volatile (
        "ecall"
        : "+r"(r_a0)
        : "r"(r_a7), "r"(r_a1)
        : "memory"
    );
    return r_a0;
}

// ============================================================================
// Timestamp sources
// ============================================================================

// Read current CPU instruction-retire counter via CSR instruction.
// Returns the lower 32 bits of INSTRET -- a monotonically increasing count
// of retired instructions since reset.
static unsigned int read_cycles(void) {
    unsigned int val;
    asm volatile ("rdinstret %0" : "=r"(val));
    return val;
}

// Ask the host for the current wall-clock time as milliseconds since midnight.
// Returns a packed Word: (hours*3600 + minutes*60 + seconds)*1000 + ms.
static unsigned int host_time_ms(void) {
    return (unsigned int)host_call(SYS_HOST_GET_TIME_MS, 0, 0);
}

// ============================================================================
// Internal buffer helpers (no stdlib dependency)
// ============================================================================

static int log_strlen(const char *s) {
    int n = 0;
    while (s[n]) n++;
    return n;
}

static void buf_putc(char *buf, int *pos, int maxlen, char c) {
    if (*pos < maxlen - 1)
        buf[(*pos)++] = c;
}

static void buf_puts(char *buf, int *pos, int maxlen, const char *s) {
    if (!s) s = "(null)";
    while (*s) buf_putc(buf, pos, maxlen, *s++);
}

static void buf_puti(char *buf, int *pos, int maxlen, int val) {
    char tmp[12];
    int i = 0;
    unsigned int uval;
    if (val < 0) {
        buf_putc(buf, pos, maxlen, '-');
        uval = (unsigned int)(-(val + 1)) + 1u;
    } else {
        uval = (unsigned int)val;
    }
    do {
        tmp[i++] = '0' + (uval % 10);
        uval /= 10;
    } while (uval > 0);
    while (i > 0) buf_putc(buf, pos, maxlen, tmp[--i]);
}

static void buf_putu(char *buf, int *pos, int maxlen, unsigned int val) {
    char tmp[12];
    int i = 0;
    do {
        tmp[i++] = '0' + (val % 10);
        val /= 10;
    } while (val > 0);
    while (i > 0) buf_putc(buf, pos, maxlen, tmp[--i]);
}

static void buf_putx(char *buf, int *pos, int maxlen,
                     unsigned int val, int upper) {
    const char *hex = upper ? "0123456789ABCDEF" : "0123456789abcdef";
    char tmp[9];
    int i = 0;
    do {
        tmp[i++] = hex[val & 0xF];
        val >>= 4;
    } while (val > 0);
    while (i > 0) buf_putc(buf, pos, maxlen, tmp[--i]);
}

// Write a two-digit decimal number (zero-padded) to the buffer.
static void buf_put2d(char *buf, int *pos, int maxlen, unsigned int val) {
    buf_putc(buf, pos, maxlen, '0' + (val / 10) % 10);
    buf_putc(buf, pos, maxlen, '0' + val % 10);
}

// Write a three-digit decimal number (zero-padded) to the buffer.
static void buf_put3d(char *buf, int *pos, int maxlen, unsigned int val) {
    buf_putc(buf, pos, maxlen, '0' + (val / 100) % 10);
    buf_putc(buf, pos, maxlen, '0' + (val / 10) % 10);
    buf_putc(buf, pos, maxlen, '0' + val % 10);
}

// ============================================================================
// Timestamp prefix helpers
// ============================================================================

// Append "[HH:MM:SS.mmm] " to buf.
static void prepend_timestamp(char *buf, int *pos, int maxlen) {
    unsigned int t   = host_time_ms();
    unsigned int ms  = t % 1000;
    unsigned int sec = (t / 1000) % 60;
    unsigned int min = (t / 60000) % 60;
    unsigned int hr  = (t / 3600000) % 24;

    buf_putc(buf, pos, maxlen, '[');
    buf_put2d(buf, pos, maxlen, hr);
    buf_putc(buf, pos, maxlen, ':');
    buf_put2d(buf, pos, maxlen, min);
    buf_putc(buf, pos, maxlen, ':');
    buf_put2d(buf, pos, maxlen, sec);
    buf_putc(buf, pos, maxlen, '.');
    buf_put3d(buf, pos, maxlen, ms);
    buf_putc(buf, pos, maxlen, ']');
    buf_putc(buf, pos, maxlen, ' ');
}

// Append "[XXXXXXXX] " (8-digit hex cycle count) to buf.
static void prepend_cycles(char *buf, int *pos, int maxlen) {
    unsigned int cyc = read_cycles();
    buf_putc(buf, pos, maxlen, '[');
    // Always emit exactly 8 hex digits.
    for (int shift = 28; shift >= 0; shift -= 4)
        buf_putc(buf, pos, maxlen,
                 "0123456789abcdef"[(cyc >> shift) & 0xF]);
    buf_putc(buf, pos, maxlen, ']');
    buf_putc(buf, pos, maxlen, ' ');
}

// ============================================================================
// Public API
// ============================================================================

int log_init(const char *filename) {
    return host_call(SYS_HOST_LOG_OPEN, (int)filename, log_strlen(filename));
}

void log_close(void) {
    host_call(SYS_HOST_LOG_CLOSE, 0, 0);
}

void log_regs(void) {
    host_call(SYS_HOST_LOG_REGS, 0, 0);
}

int log_write(log_mode_t mode, const char *fmt, ...) {
    char buf[LOG_BUF_SIZE];
    int pos = 0;

    // Prepend timestamp prefix based on mode.
    if (mode == TIME_STAMP)
        prepend_timestamp(buf, &pos, LOG_BUF_SIZE);
    else if (mode == CYCLES)
        prepend_cycles(buf, &pos, LOG_BUF_SIZE);

    // Format the message into the remainder of the buffer.
    va_list args;
    va_start(args, fmt);

    while (*fmt) {
        if (*fmt == '%') {
            fmt++;
            switch (*fmt) {
                case 'd':
                    buf_puti(buf, &pos, LOG_BUF_SIZE, va_arg(args, int));
                    break;
                case 'u':
                    buf_putu(buf, &pos, LOG_BUF_SIZE, va_arg(args, unsigned int));
                    break;
                case 'x':
                    buf_putx(buf, &pos, LOG_BUF_SIZE,
                             va_arg(args, unsigned int), 0);
                    break;
                case 'X':
                    buf_putx(buf, &pos, LOG_BUF_SIZE,
                             va_arg(args, unsigned int), 1);
                    break;
                case 's':
                    buf_puts(buf, &pos, LOG_BUF_SIZE, va_arg(args, const char *));
                    break;
                case 'c':
                    buf_putc(buf, &pos, LOG_BUF_SIZE, (char)va_arg(args, int));
                    break;
                case '%':
                    buf_putc(buf, &pos, LOG_BUF_SIZE, '%');
                    break;
                case '\0':
                    goto done;
                default:
                    buf_putc(buf, &pos, LOG_BUF_SIZE, '%');
                    buf_putc(buf, &pos, LOG_BUF_SIZE, *fmt);
                    break;
            }
        } else {
            buf_putc(buf, &pos, LOG_BUF_SIZE, *fmt);
        }
        fmt++;
    }

done:
    va_end(args);
    if (pos == 0) return 0;
    return host_call(SYS_HOST_LOG_WRITE, (int)buf, pos);
}
