/* **************************************************************************
 *        RISC-V Emulator - Demonstration of the host logging module
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

// log-test.c - Demonstration of the host logging module.
//
// Tests all three log_write() modes: NONE, TIME_STAMP, CYCLES.
//
// Build and run:
//   cd programs && make run-log-test
//
// After the emulator exits, inspect the log:
//   cat log-test.log
// By Ulrik Hørlyk Hjort 2026

#include "log.h"

void putchar(char c);

static void uart_puts(const char *s) {
    while (*s) {
        if (*s == '\n') putchar('\r');
        putchar(*s++);
    }
}

int main(void) {
    uart_puts("=== Host Logging Test ===\n");

    if (log_init("log-test.log") != 0) {
        uart_puts("ERROR: log_init failed\n");
        return 1;
    }

    // ---- NONE: plain output (no prefix) ----
    log_write(NONE, "=== Mode: NONE (no prefix) ===\n");
    log_write(NONE, "Integer:  %d\n", 42);
    log_write(NONE, "Negative: %d\n", -100);
    log_write(NONE, "Unsigned: %u\n", 3000000000u);
    log_write(NONE, "Hex:      0x%x\n", 0xdeadbeef);
    log_write(NONE, "String:   %s\n", "hello from RISC-V");
    log_write(NONE, "Char:     %c\n", 'Z');
    log_write(NONE, "\n");

    // ---- TIME_STAMP: wall-clock prefix ----
    log_write(NONE,       "=== Mode: TIME_STAMP (host wall-clock) ===\n");
    log_write(TIME_STAMP, "First message\n");
    log_write(TIME_STAMP, "Second message\n");
    log_write(TIME_STAMP, "Value: %d, status: %s\n", 99, "ok");

    // Burn some cycles so the timestamps differ visibly.
    volatile int x = 0;
    for (int i = 0; i < 50000; i++) x += i;

    log_write(TIME_STAMP, "After busy loop (x=%d)\n", x);
    log_write(NONE, "\n");

    // ---- CYCLES: CPU instruction count prefix ----
    log_write(NONE,   "=== Mode: CYCLES (CPU instret counter) ===\n");
    log_write(CYCLES, "Start\n");
    log_write(CYCLES, "Step A: %d\n", 1);
    log_write(CYCLES, "Step B: %d\n", 2);
    log_write(CYCLES, "Step C: %d\n", 3);
    log_write(NONE,   "\n");

    // ---- Register dump ----
    log_write(NONE, "=== Register dump ===\n");
    log_regs();

    log_close();

    uart_puts("Log written to log-test.log\n");
    uart_puts("Done!\n");
    return 0;
}
