/* **************************************************************************
 *       RISC-V Emulator - Verify RV64E (16-register subset) support
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

/*
 * rv64e-test.c -- Verify RV64E (16-register subset) support
 *
 * Checks MISA.E is set, MISA.I is clear, MISA.V is clear, MXL=2.
 * Uses direct semihosting ECALLs to avoid log64.c (which uses x16+ registers).
 *
 * Run with: bin/riscv_emulator --machine qemu-virt --rv64e <elf>
 *
 * By Ulrik Hørlyk Hjort 2026
 */
#include <stdint.h>

static int g_pass = 0, g_fail = 0;

/* Semihosting ECALL numbers */
#define HOST_LOG_OPEN  0x500
#define HOST_LOG_WRITE 0x501
#define HOST_LOG_CLOSE 0x502

/* Write a string via HOST_LOG_WRITE ecall */
static void puts_semi(const char *s, int len)
{
    register long a0 asm("a0") = (long)s;
    register long a1 asm("a1") = (long)len;
    register long a7 asm("a7") = HOST_LOG_WRITE;
    asm volatile("ecall" : : "r"(a0), "r"(a1), "r"(a7) : "memory");
}

static int strlen_s(const char *s)
{
    int n = 0;
    while (s[n]) n++;
    return n;
}

static void puts_log(const char *s)
{
    puts_semi(s, strlen_s(s));
}

static void log_init_semi(const char *fname)
{
    register long a0 asm("a0") = (long)fname;
    register long a1 asm("a1") = (long)strlen_s(fname);
    register long a7 asm("a7") = HOST_LOG_OPEN;
    asm volatile("ecall" : "+r"(a0) : "r"(a1), "r"(a7) : "memory");
}

static void log_close_semi(void)
{
    register long a7 asm("a7") = HOST_LOG_CLOSE;
    asm volatile("ecall" : : "r"(a7) : "memory");
}

static void chk(const char *label, int ok)
{
    if (ok) {
        puts_log("PASS ");
        g_pass++;
    } else {
        puts_log("FAIL ");
        g_fail++;
    }
    puts_log(label);
    puts_log("\n");
}

static unsigned long read_misa(void)
{
    unsigned long v;
    asm volatile("csrr %0, misa" : "=r"(v));
    return v;
}

/* Print a single digit 0-9 */
static void put_digit(int d)
{
    char c = '0' + (char)d;
    puts_semi(&c, 1);
}

int main(void)
{
    unsigned long misa;

    log_init_semi("rv64e-test.log");
    puts_log("=== RV64E Test ===\n");

    misa = read_misa();

    /* MISA.E  = bit 4 */
    chk("MISA.E set",   (int)((misa >> 4)  & 1));
    /* MISA.I  = bit 8 -- must be clear for RV64E */
    chk("MISA.I clear", (int)(!((misa >> 8) & 1)));
    /* MISA.V  = bit 21 -- vector not in E profile */
    chk("MISA.V clear", (int)(!((misa >> 21) & 1)));
    /* MXL     = bits[63:62] = 2 for RV64 */
    chk("MXL=2 (RV64)", (int)(((misa >> 62) & 3) == 2));

    /* Basic arithmetic using only low registers */
    volatile unsigned long a = 0xDEAD, b = 0xBEEF;
    chk("add a0/a1", (int)((a + b) == (0xDEADUL + 0xBEEFUL)));
    chk("xor a0/a1", (int)((a ^ b) == (0xDEADUL ^ 0xBEEFUL)));

    puts_log("\n");
    put_digit(g_pass); puts_log(" PASS  ");
    put_digit(g_fail); puts_log(" FAIL\n");
    log_close_semi();
    return g_fail ? 1 : 0;
}
