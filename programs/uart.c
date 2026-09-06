/* **************************************************************************
 *                      RISC-V Emulator - UART Driver
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

// By Ulrik Hørlyk Hjort 2026
#define UART_BASE 0x10000000
#define UART_RBR  (*(volatile unsigned char *)(UART_BASE + 0))
#define UART_THR  (*(volatile unsigned char *)(UART_BASE + 0))
#define UART_LSR  (*(volatile unsigned char *)(UART_BASE + 5))
#define LSR_DR    (1 << 0)
#define LSR_THRE  (1 << 5)

void putchar(char c) {
    if (c == 0x0A) {
        while ((UART_LSR & LSR_THRE) == 0);
        UART_THR = 0x0D;
    }
    while ((UART_LSR & LSR_THRE) == 0);
    UART_THR = c;
}

char getchar(void) {
    while ((UART_LSR & LSR_DR) == 0);
    return UART_RBR;
}

void puts(const char *s) {
    while (*s) {
        putchar(*s++);
    }
}
