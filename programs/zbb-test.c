/* **************************************************************************
 *RISC-V Emulator - RISC-V Zbb (bit manipulation) and Zbs (bit single) test
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

// zbb-test.c -- RISC-V Zbb (bit manipulation) and Zbs (bit single) test.
//
// Tests all scalar Zbb / Zbs instructions against known values:
//
//   Zbb:  clz, ctz, cpop, sext.b, sext.h, orc.b, rev8,
//         min, max, minu, maxu
//   Zbkb: rol, ror, rori, andn, orn, xnor
//   Zbs:  bset, bclr, binv, bext
//
// Build: cd programs && make run-zbb-test
// By Ulrik Hørlyk Hjort 2026

#include <stdint.h>
#include "log.h"

void putchar(char c);
static void uart_puts(const char *s) {
    while (*s) { if (*s == '\n') putchar('\r'); putchar(*s++); }
}

static int g_pass = 0, g_fail = 0;

static void chk32(const char *label, uint32_t got, uint32_t expected) {
    if (got == expected) {
        log_write(NONE, "  PASS  %s\n", label);
        g_pass++;
    } else {
        log_write(NONE, "  FAIL  %s: got 0x%x  exp 0x%x\n", label, got, expected);
        g_fail++;
    }
}

// -- CLZ / CTZ / CPOP ---------------------------------------------------------

static void test_clz(void) {
    log_write(NONE, "\n=== CLZ (count leading zeros) ===\n");
    uint32_t r;
    asm volatile("clz %0, %1" : "=r"(r) : "r"(0u));            chk32("clz(0)=32",          r, 32);
    asm volatile("clz %0, %1" : "=r"(r) : "r"(1u));            chk32("clz(1)=31",          r, 31);
    asm volatile("clz %0, %1" : "=r"(r) : "r"(0x80000000u));   chk32("clz(0x80000000)=0",  r,  0);
    asm volatile("clz %0, %1" : "=r"(r) : "r"(0xFFFFFFFFu));   chk32("clz(0xFFFFFFFF)=0",  r,  0);
    asm volatile("clz %0, %1" : "=r"(r) : "r"(0x00010000u));   chk32("clz(0x00010000)=15", r, 15);
    asm volatile("clz %0, %1" : "=r"(r) : "r"(0x0000FFFFu));   chk32("clz(0x0000FFFF)=16", r, 16);
}

static void test_ctz(void) {
    log_write(NONE, "\n=== CTZ (count trailing zeros) ===\n");
    uint32_t r;
    asm volatile("ctz %0, %1" : "=r"(r) : "r"(0u));            chk32("ctz(0)=32",          r, 32);
    asm volatile("ctz %0, %1" : "=r"(r) : "r"(1u));            chk32("ctz(1)=0",           r,  0);
    asm volatile("ctz %0, %1" : "=r"(r) : "r"(2u));            chk32("ctz(2)=1",           r,  1);
    asm volatile("ctz %0, %1" : "=r"(r) : "r"(0x80000000u));   chk32("ctz(0x80000000)=31", r, 31);
    asm volatile("ctz %0, %1" : "=r"(r) : "r"(0xFFFFFFFFu));   chk32("ctz(0xFFFFFFFF)=0",  r,  0);
    asm volatile("ctz %0, %1" : "=r"(r) : "r"(0x00100000u));   chk32("ctz(0x00100000)=20", r, 20);
}

static void test_cpop(void) {
    log_write(NONE, "\n=== CPOP (popcount) ===\n");
    uint32_t r;
    asm volatile("cpop %0, %1" : "=r"(r) : "r"(0u));           chk32("cpop(0)=0",           r,  0);
    asm volatile("cpop %0, %1" : "=r"(r) : "r"(1u));           chk32("cpop(1)=1",           r,  1);
    asm volatile("cpop %0, %1" : "=r"(r) : "r"(0xFFFFFFFFu));  chk32("cpop(0xFFFF...)=32",  r, 32);
    asm volatile("cpop %0, %1" : "=r"(r) : "r"(0x55555555u));  chk32("cpop(0x5555...)=16",  r, 16);
    asm volatile("cpop %0, %1" : "=r"(r) : "r"(0xAAAAAAAAu));  chk32("cpop(0xAAAA...)=16",  r, 16);
    asm volatile("cpop %0, %1" : "=r"(r) : "r"(0x12345678u));  chk32("cpop(0x12345678)=13", r, 13);
}

// -- SEXT.B / SEXT.H ----------------------------------------------------------

static void test_sext(void) {
    log_write(NONE, "\n=== SEXT.B / SEXT.H (sign extension) ===\n");
    uint32_t r;
    asm volatile("sext.b %0, %1" : "=r"(r) : "r"(0x7Fu));       chk32("sext.b(0x7F)=0x7F",        r, 0x7Fu);
    asm volatile("sext.b %0, %1" : "=r"(r) : "r"(0x80u));       chk32("sext.b(0x80)=0xFFFFFF80",  r, 0xFFFFFF80u);
    asm volatile("sext.b %0, %1" : "=r"(r) : "r"(0xFFu));       chk32("sext.b(0xFF)=0xFFFFFFFF",  r, 0xFFFFFFFFu);
    asm volatile("sext.b %0, %1" : "=r"(r) : "r"(0x12345600u)); chk32("sext.b(0x123456XX, X=0)=0", r, 0u);
    asm volatile("sext.b %0, %1" : "=r"(r) : "r"(0xDEADBEEFu)); chk32("sext.b(0xDEADBEEF)=EF->-17", r, 0xFFFFFFEFu);

    asm volatile("sext.h %0, %1" : "=r"(r) : "r"(0x7FFFu));     chk32("sext.h(0x7FFF)=0x7FFF",       r, 0x7FFFu);
    asm volatile("sext.h %0, %1" : "=r"(r) : "r"(0x8000u));     chk32("sext.h(0x8000)=0xFFFF8000",   r, 0xFFFF8000u);
    asm volatile("sext.h %0, %1" : "=r"(r) : "r"(0xFFFFu));     chk32("sext.h(0xFFFF)=0xFFFFFFFF",   r, 0xFFFFFFFFu);
    asm volatile("sext.h %0, %1" : "=r"(r) : "r"(0xABCD1234u)); chk32("sext.h(0xABCD1234)=0x1234",   r, 0x1234u);
    asm volatile("sext.h %0, %1" : "=r"(r) : "r"(0xABCDABCDu)); chk32("sext.h(0xABCDABCD)=FFFF ABCD", r, 0xFFFFABCDu);
}

// -- ORC.B ---------------------------------------------------------------------

static void test_orc_b(void) {
    log_write(NONE, "\n=== ORC.B (or-combine bytes) ===\n");
    uint32_t r;
    asm volatile("orc.b %0, %1" : "=r"(r) : "r"(0x00000000u));  chk32("orc.b(0)=0",              r, 0x00000000u);
    asm volatile("orc.b %0, %1" : "=r"(r) : "r"(0xFFFFFFFFu));  chk32("orc.b(0xFFFFFFFF)=same",  r, 0xFFFFFFFFu);
    asm volatile("orc.b %0, %1" : "=r"(r) : "r"(0x01000000u));  chk32("orc.b(0x01000000)=0xFF000000", r, 0xFF000000u);
    asm volatile("orc.b %0, %1" : "=r"(r) : "r"(0x00000001u));  chk32("orc.b(0x00000001)=0xFF",  r, 0xFFu);
    asm volatile("orc.b %0, %1" : "=r"(r) : "r"(0x00FF0000u));  chk32("orc.b(0x00FF0000)=0xFF0000", r, 0xFF0000u);
    asm volatile("orc.b %0, %1" : "=r"(r) : "r"(0x12345678u));  chk32("orc.b(0x12345678)=all",   r, 0xFFFFFFFFu);
    asm volatile("orc.b %0, %1" : "=r"(r) : "r"(0x01000100u));  chk32("orc.b(0x01000100)=FF00FF00", r, 0xFF00FF00u);
}

// -- REV8 (byte swap) ----------------------------------------------------------

static void test_rev8(void) {
    log_write(NONE, "\n=== REV8 (byte-reverse / endian swap) ===\n");
    uint32_t r;
    asm volatile("rev8 %0, %1" : "=r"(r) : "r"(0x12345678u)); chk32("rev8(0x12345678)=0x78563412", r, 0x78563412u);
    asm volatile("rev8 %0, %1" : "=r"(r) : "r"(0x00000001u)); chk32("rev8(0x00000001)=0x01000000", r, 0x01000000u);
    asm volatile("rev8 %0, %1" : "=r"(r) : "r"(0xAABBCCDDu)); chk32("rev8(0xAABBCCDD)=0xDDCCBBAA", r, 0xDDCCBBAAu);
    asm volatile("rev8 %0, %1" : "=r"(r) : "r"(0x00000000u)); chk32("rev8(0)=0",                   r, 0u);
}

// -- ROL / ROR / RORI ---------------------------------------------------------

static void test_rotate(void) {
    log_write(NONE, "\n=== ROL / ROR / RORI ===\n");
    uint32_t r;
    asm volatile("rol %0, %1, %2" : "=r"(r) : "r"(1u),          "r"(4u));  chk32("rol(1,4)=0x10",          r, 0x10u);
    asm volatile("rol %0, %1, %2" : "=r"(r) : "r"(0x80000000u), "r"(1u));  chk32("rol(0x80000000,1)=1",    r, 1u);
    asm volatile("rol %0, %1, %2" : "=r"(r) : "r"(0xAAAAAAAAu), "r"(1u));  chk32("rol(0xAAAAAAAA,1)=0x55555555", r, 0x55555555u);
    asm volatile("ror %0, %1, %2" : "=r"(r) : "r"(1u),          "r"(1u));  chk32("ror(1,1)=0x80000000",   r, 0x80000000u);
    asm volatile("ror %0, %1, %2" : "=r"(r) : "r"(0x12345678u), "r"(8u));  chk32("ror(0x12345678,8)=0x78123456", r, 0x78123456u);
    asm volatile("rori %0, %1, 4" : "=r"(r) : "r"(0x12345678u));            chk32("rori(0x12345678,4)=0x81234567", r, 0x81234567u);
    asm volatile("rori %0, %1, 16": "=r"(r) : "r"(0xDEADBEEFu));            chk32("rori(0xDEADBEEF,16)=0xBEEFDEAD", r, 0xBEEFDEADu);
}

// -- ANDN / ORN / XNOR --------------------------------------------------------

static void test_logical_not(void) {
    log_write(NONE, "\n=== ANDN / ORN / XNOR ===\n");
    uint32_t r;
    asm volatile("andn %0, %1, %2" : "=r"(r) : "r"(0xFFu), "r"(0x0Fu));  chk32("andn(0xFF,0x0F)=0xF0",    r, 0xF0u);
    asm volatile("andn %0, %1, %2" : "=r"(r) : "r"(0u),    "r"(0xFFu));  chk32("andn(0,0xFF)=0",          r, 0u);
    asm volatile("andn %0, %1, %2" : "=r"(r) : "r"(0xFFFFFFFFu), "r"(0u)); chk32("andn(~0,0)=0xFFFFFFFF",r, 0xFFFFFFFFu);

    asm volatile("orn  %0, %1, %2" : "=r"(r) : "r"(0u),    "r"(0xFFu));  chk32("orn(0,0xFF)=0xFFFFFF00",  r, 0xFFFFFF00u);
    asm volatile("orn  %0, %1, %2" : "=r"(r) : "r"(0xFFFFFFFFu), "r"(0xFFFFFFFFu)); chk32("orn(~0,~0)=~0", r, 0xFFFFFFFFu);

    asm volatile("xnor %0, %1, %2" : "=r"(r) : "r"(0u),    "r"(0u));     chk32("xnor(0,0)=~0",           r, 0xFFFFFFFFu);
    asm volatile("xnor %0, %1, %2" : "=r"(r) : "r"(0xFFFFFFFFu), "r"(0u)); chk32("xnor(~0,0)=0",        r, 0u);
    asm volatile("xnor %0, %1, %2" : "=r"(r) : "r"(0xAAAAAAAAu), "r"(0xAAAAAAAAu)); chk32("xnor(A,A)=~0",r, 0xFFFFFFFFu);
}

// -- MIN / MAX / MINU / MAXU ---------------------------------------------------

static void test_minmax(void) {
    log_write(NONE, "\n=== MIN / MAX / MINU / MAXU ===\n");
    uint32_t r;
    asm volatile("min  %0, %1, %2" : "=r"(r) : "r"(3u),          "r"(5u));          chk32("min(3,5)=3",        r, 3u);
    asm volatile("min  %0, %1, %2" : "=r"(r) : "r"(0xFFFFFFFFu), "r"(0u));          chk32("min(-1,0)=-1",      r, 0xFFFFFFFFu);
    asm volatile("min  %0, %1, %2" : "=r"(r) : "r"(0x80000000u), "r"(0x7FFFFFFFu)); chk32("min(INT_MIN,INT_MAX)=INT_MIN", r, 0x80000000u);
    asm volatile("max  %0, %1, %2" : "=r"(r) : "r"(3u),          "r"(5u));          chk32("max(3,5)=5",        r, 5u);
    asm volatile("max  %0, %1, %2" : "=r"(r) : "r"(0xFFFFFFFFu), "r"(0u));          chk32("max(-1,0)=0",       r, 0u);
    asm volatile("max  %0, %1, %2" : "=r"(r) : "r"(0x80000000u), "r"(0x7FFFFFFFu)); chk32("max(INT_MIN,INT_MAX)=INT_MAX", r, 0x7FFFFFFFu);
    asm volatile("minu %0, %1, %2" : "=r"(r) : "r"(3u),          "r"(5u));          chk32("minu(3,5)=3",       r, 3u);
    asm volatile("minu %0, %1, %2" : "=r"(r) : "r"(0xFFFFFFFFu), "r"(0u));          chk32("minu(0xFFFFFFFF,0)=0", r, 0u);
    asm volatile("maxu %0, %1, %2" : "=r"(r) : "r"(3u),          "r"(5u));          chk32("maxu(3,5)=5",       r, 5u);
    asm volatile("maxu %0, %1, %2" : "=r"(r) : "r"(0xFFFFFFFFu), "r"(0u));          chk32("maxu(0xFFFFFFFF,0)=0xFFFFFFFF", r, 0xFFFFFFFFu);
}

// -- BSET / BCLR / BINV / BEXT ------------------------------------------------

static void test_bit_single(void) {
    log_write(NONE, "\n=== BSET / BCLR / BINV / BEXT (Zbs) ===\n");
    uint32_t r;
    asm volatile("bset  %0, %1, %2" : "=r"(r) : "r"(0u),          "r"(3u)); chk32("bset(0,3)=8",        r, 8u);
    asm volatile("bset  %0, %1, %2" : "=r"(r) : "r"(0xFFFFFFFFu), "r"(3u)); chk32("bset(~0,3)=~0",     r, 0xFFFFFFFFu);
    asm volatile("bseti %0, %1, 31" : "=r"(r) : "r"(0u));                   chk32("bseti(0,31)=0x80000000", r, 0x80000000u);

    asm volatile("bclr  %0, %1, %2" : "=r"(r) : "r"(0xFFFFFFFFu), "r"(3u)); chk32("bclr(~0,3)=0xFFFFFFF7", r, 0xFFFFFFF7u);
    asm volatile("bclr  %0, %1, %2" : "=r"(r) : "r"(0u),          "r"(5u)); chk32("bclr(0,5)=0",        r, 0u);
    asm volatile("bclri %0, %1, 31" : "=r"(r) : "r"(0x80000000u));           chk32("bclri(0x80000000,31)=0", r, 0u);

    asm volatile("binv  %0, %1, %2" : "=r"(r) : "r"(0u),          "r"(7u)); chk32("binv(0,7)=0x80",     r, 0x80u);
    asm volatile("binv  %0, %1, %2" : "=r"(r) : "r"(0x80u),       "r"(7u)); chk32("binv(0x80,7)=0",     r, 0u);
    asm volatile("binvi %0, %1, 0"  : "=r"(r) : "r"(0xFFFFFFFFu));           chk32("binvi(~0,0)=0xFFFFFFFE", r, 0xFFFFFFFEu);

    asm volatile("bext  %0, %1, %2" : "=r"(r) : "r"(0x12345678u), "r"(4u)); chk32("bext(0x12345678,4)=1", r, 1u);
    asm volatile("bext  %0, %1, %2" : "=r"(r) : "r"(0u),          "r"(0u)); chk32("bext(0,0)=0",          r, 0u);
    asm volatile("bext  %0, %1, %2" : "=r"(r) : "r"(0x80000000u), "r"(31u));chk32("bext(0x80000000,31)=1", r, 1u);
    asm volatile("bexti %0, %1, 3"  : "=r"(r) : "r"(0xFu));                 chk32("bexti(0xF,3)=1",       r, 1u);
}

// -- Main ----------------------------------------------------------------------

int main(void) {
    uart_puts("=== Zbb/Zbs Test ===\n");
    if (log_init("zbb-test.log") != 0) {
        uart_puts("ERROR: log_init failed\n"); return 1;
    }

    log_write(NONE, "=== RISC-V Zbb/Zbs Bit-Manipulation Test ===\n");

    test_clz();
    test_ctz();
    test_cpop();
    test_sext();
    test_orc_b();
    test_rev8();
    test_rotate();
    test_logical_not();
    test_minmax();
    test_bit_single();

    log_write(NONE, "\n=== Summary ===\n");
    log_write(NONE, "  PASS: %d\n", g_pass);
    log_write(NONE, "  FAIL: %d\n", g_fail);
    log_write(NONE, "  %s\n", g_fail == 0 ? "ALL TESTS PASSED" : "SOME TESTS FAILED");

    log_close();
    uart_puts(g_fail == 0 ? "ALL PASSED\n" : "SOME FAILED\n");
    return g_fail;
}
