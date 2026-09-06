/* **************************************************************************
 *                RISC-V Emulator - Semihosting Log for RV64
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

/* Semihosting log for RV64 -- uses 'long' (64-bit in LP64) for pointer args */
#include "log.h"
#include <stdarg.h>

#define SYS_HOST_LOG_OPEN    0x500
#define SYS_HOST_LOG_WRITE   0x501
#define SYS_HOST_LOG_CLOSE   0x502
#define SYS_HOST_LOG_REGS    0x503

#define LOG_BUF_SIZE 1024

static long host_call64(long syscall_num, long arg0, long arg1) {
    register long r_a7 asm("a7") = syscall_num;
    register long r_a0 asm("a0") = arg0;
    register long r_a1 asm("a1") = arg1;
    asm volatile (
        "ecall"
        : "+r"(r_a0)
        : "r"(r_a7), "r"(r_a1)
        : "memory"
    );
    return r_a0;
}

static int log_strlen(const char *s) {
    int n = 0;
    while (s[n]) n++;
    return n;
}

int log_init(const char *filename) {
    return (int)host_call64(SYS_HOST_LOG_OPEN, (long)filename, log_strlen(filename));
}

void log_close(void) {
    host_call64(SYS_HOST_LOG_CLOSE, 0, 0);
}

void log_regs(void) {
    host_call64(SYS_HOST_LOG_REGS, 0, 0);
}

/* Minimal vsnprintf for log_write (no float, no width) */
static int log_vsnprintf(char *buf, int maxlen, const char *fmt, va_list ap) {
    int pos = 0;
#define OUT(c) do { if (pos < maxlen - 1) buf[pos++] = (c); } while(0)
    while (*fmt) {
        if (*fmt != '%') { OUT(*fmt++); continue; }
        fmt++;
        if (*fmt == 'd' || *fmt == 'i') {
            long v = va_arg(ap, long);
            if (v < 0) { OUT('-'); v = -v; }
            char tmp[32]; int len = 0;
            if (v == 0) { OUT('0'); } else {
                while (v) { tmp[len++] = '0' + (int)(v % 10); v /= 10; }
                while (len--) OUT(tmp[len]);
            }
        } else if (*fmt == 'u') {
            unsigned long v = va_arg(ap, unsigned long);
            char tmp[32]; int len = 0;
            if (v == 0) { OUT('0'); } else {
                while (v) { tmp[len++] = '0' + (int)(v % 10); v /= 10; }
                while (len--) OUT(tmp[len]);
            }
        } else if (*fmt == 'x' || *fmt == 'X') {
            unsigned long v = va_arg(ap, unsigned long);
            char tmp[32]; int len = 0;
            const char *hex = (*fmt == 'x') ? "0123456789abcdef" : "0123456789ABCDEF";
            if (v == 0) { OUT('0'); } else {
                while (v) { tmp[len++] = hex[v & 0xF]; v >>= 4; }
                while (len--) OUT(tmp[len]);
            }
        } else if (*fmt == 's') {
            const char *s = va_arg(ap, const char *);
            if (!s) s = "(null)";
            while (*s) OUT(*s++);
        } else if (*fmt == 'c') {
            OUT((char)va_arg(ap, int));
        } else if (*fmt == '%') {
            OUT('%');
        }
        fmt++;
    }
#undef OUT
    buf[pos] = '\0';
    return pos;
}

int log_write(log_mode_t mode, const char *fmt, ...) {
    char buf[LOG_BUF_SIZE];
    va_list ap;
    va_start(ap, fmt);
    int len = log_vsnprintf(buf, LOG_BUF_SIZE, fmt, ap);
    va_end(ap);
    (void)mode;
    return (int)host_call64(SYS_HOST_LOG_WRITE, (long)buf, len);
}
