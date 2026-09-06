/* **************************************************************************
 *RISC-V Emulator - M extension: MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM, REMU
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

// m-ext-test.c -- M extension: MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM, REMU.
//
// Uses inline assembly so the compiler is forced to emit the exact M-extension
// instructions instead of using library calls or optimising them away.
// All 8 instructions are tested, including every RISC-V-specified edge case:
//   - DIV / DIVU by zero  -> -1 / UINT_MAX
//   - REM / REMU by zero  -> dividend unchanged
//   - INT_MIN / -1 (overflow) -> INT_MIN (div), 0 (rem)
//
// Build: cd programs && make run-m-ext-test
// By Ulrik Hørlyk Hjort 2026

#include <stdint.h>
#include "log.h"

void putchar(char c);

static void uart_puts(const char *s) {
    while (*s) { if (*s == '\n') putchar('\r'); putchar(*s++); }
}

static int g_pass = 0, g_fail = 0;

static void check32(const char *label, int32_t got, int32_t expected) {
    if (got == expected) {
        log_write(NONE, "  PASS  %s\n", label); g_pass++;
    } else {
        log_write(NONE, "  FAIL  %s: got %08x  exp %08x\n",
                  label, (uint32_t)got, (uint32_t)expected); g_fail++;
    }
}

static void checku32(const char *label, uint32_t got, uint32_t expected) {
    check32(label, (int32_t)got, (int32_t)expected);
}

// -- Inline-asm wrappers ----------------------------------------------------

static inline int32_t do_mul(int32_t a, int32_t b) {
    int32_t r; asm volatile("mul %0,%1,%2" : "=r"(r) : "r"(a), "r"(b)); return r;
}
static inline int32_t do_mulh(int32_t a, int32_t b) {
    int32_t r; asm volatile("mulh %0,%1,%2" : "=r"(r) : "r"(a), "r"(b)); return r;
}
static inline int32_t do_mulhsu(int32_t a, uint32_t b) {
    int32_t r; asm volatile("mulhsu %0,%1,%2" : "=r"(r) : "r"(a), "r"(b)); return r;
}
static inline uint32_t do_mulhu(uint32_t a, uint32_t b) {
    uint32_t r; asm volatile("mulhu %0,%1,%2" : "=r"(r) : "r"(a), "r"(b)); return r;
}
static inline int32_t do_div(int32_t a, int32_t b) {
    int32_t r; asm volatile("div %0,%1,%2" : "=r"(r) : "r"(a), "r"(b)); return r;
}
static inline uint32_t do_divu(uint32_t a, uint32_t b) {
    uint32_t r; asm volatile("divu %0,%1,%2" : "=r"(r) : "r"(a), "r"(b)); return r;
}
static inline int32_t do_rem(int32_t a, int32_t b) {
    int32_t r; asm volatile("rem %0,%1,%2" : "=r"(r) : "r"(a), "r"(b)); return r;
}
static inline uint32_t do_remu(uint32_t a, uint32_t b) {
    uint32_t r; asm volatile("remu %0,%1,%2" : "=r"(r) : "r"(a), "r"(b)); return r;
}

// -- MUL (lower 32 bits of product) ----------------------------------------

static void test_mul(void) {
    log_write(NONE, "\n=== MUL (lower 32 bits) ===\n");

    check32("0 * 0 = 0",             do_mul(0, 0),           0);
    check32("1 * 1 = 1",             do_mul(1, 1),           1);
    check32("7 * 6 = 42",            do_mul(7, 6),           42);
    check32("-1 * 1 = -1",           do_mul(-1, 1),          -1);
    check32("-3 * -4 = 12",          do_mul(-3, -4),         12);
    check32("100 * 200 = 20000",     do_mul(100, 200),       20000);
    // Overflow wraps mod 2^32
    // 0x7FFFFFFF * 2 = 0xFFFFFFFE (low 32 bits)
    check32("INT_MAX*2 lo32",        do_mul(0x7FFFFFFF, 2),  (int32_t)0xFFFFFFFE);
    // 0x80000000 * 2 = 0 (wraps)
    check32("INT_MIN*2 lo32=0",      do_mul((int32_t)0x80000000, 2), 0);
}

// -- MULH (signed * signed -> upper 32 bits) --------------------------------

static void test_mulh(void) {
    log_write(NONE, "\n=== MULH (signed upper 32 bits) ===\n");

    check32("1 * 1 hi=0",            do_mulh(1, 1),          0);
    check32("-1 * -1 hi=0",          do_mulh(-1, -1),        0);
    check32("-1 * 1 hi=-1",          do_mulh(-1, 1),         -1);
    // 0x40000000 * 4 = 0x100000000 -> hi = 1
    check32("0x4000_0000*4 hi=1",    do_mulh(0x40000000, 4), 1);
    // INT_MIN * INT_MIN = 2^62 -> hi = 0x40000000
    check32("INT_MIN*INT_MIN hi",    do_mulh((int32_t)0x80000000,
                                            (int32_t)0x80000000),
                                     0x40000000);
    // INT_MIN * -1 = INT_MIN (overflow), hi bits = 0
    // Full 64-bit: 0x80000000 * 0xFFFFFFFF = -(INT_MIN) = 2^31
    // That's 0x00000000_80000000 -> hi = 0
    check32("INT_MIN*-1 hi=0",       do_mulh((int32_t)0x80000000, -1), 0);
}

// -- MULHSU (signed * unsigned -> upper 32 bits) ----------------------------

static void test_mulhsu(void) {
    log_write(NONE, "\n=== MULHSU (signed * unsigned upper 32 bits) ===\n");

    check32("1 su* 1 hi=0",          do_mulhsu(1, 1u),        0);
    // -1 (signed) * 1 (unsigned) = 0xFFFFFFFF * 1 treated as signed*unsigned
    // Full 64: sign-extended(-1)=-1, unsigned 1 -> product = -1 = 0xFFFFFFFF_FFFFFFFF -> hi=-1
    check32("-1 su* 1 hi=-1",        do_mulhsu(-1, 1u),      -1);
    // -1 (signed) * UINT_MAX -> full product = -UINT_MAX = -0xFFFFFFFF
    // = 0xFFFF_FFFF_0000_0001 -> hi = -1
    check32("-1 su* UINT_MAX hi=-1", do_mulhsu(-1, 0xFFFFFFFFu), -1);
    // 2 (signed) * 0x80000000 (unsigned) = 0x100000000 -> hi = 1
    check32("2 su* 0x8000_0000 hi=1", do_mulhsu(2, 0x80000000u), 1);
    // 0x40000000 * 4u -> hi=1 (same as signed version for same-sign inputs)
    check32("0x4000_0000 su*4 hi=1", do_mulhsu(0x40000000, 4u), 1);
}

// -- MULHU (unsigned * unsigned -> upper 32 bits) ---------------------------

static void test_mulhu(void) {
    log_write(NONE, "\n=== MULHU (unsigned upper 32 bits) ===\n");

    checku32("1u*1u hi=0",              do_mulhu(1u, 1u),             0);
    // UINT_MAX * UINT_MAX = 0xFFFFFFFE_00000001 -> hi = 0xFFFFFFFE
    checku32("UINT_MAX*UINT_MAX hi",    do_mulhu(0xFFFFFFFFu,
                                                 0xFFFFFFFFu),
                                         0xFFFFFFFEu);
    // 0x80000000 * 2 = 0x100000000 -> hi = 1
    checku32("0x8000_0000u*2 hi=1",     do_mulhu(0x80000000u, 2u),    1u);
    // 0x80000000 * 0x80000000 = 2^62 -> hi = 0x40000000
    checku32("0x8000_0000u^2 hi",       do_mulhu(0x80000000u,
                                                 0x80000000u),
                                         0x40000000u);
}

// -- DIV (signed division) -------------------------------------------------

static void test_div(void) {
    log_write(NONE, "\n=== DIV (signed) ===\n");

    check32("10 / 3 = 3",           do_div(10, 3),          3);
    check32("-10 / 3 = -3",         do_div(-10, 3),         -3);
    check32("10 / -3 = -3",         do_div(10, -3),         -3);
    check32("-10 / -3 = 3",         do_div(-10, -3),        3);
    check32("0 / 5 = 0",            do_div(0, 5),           0);
    // RISC-V spec: dividend / 0 = -1 (all ones)
    check32("5 / 0 = -1",           do_div(5, 0),           -1);
    check32("-1 / 0 = -1",          do_div(-1, 0),          -1);
    // INT_MIN / -1 overflows -> result = INT_MIN (spec-defined)
    check32("INT_MIN / -1 = INT_MIN", do_div((int32_t)0x80000000, -1),
                                      (int32_t)0x80000000);
    check32("1 / 1 = 1",            do_div(1, 1),           1);
    check32("100 / 10 = 10",        do_div(100, 10),        10);
    check32("INT_MAX / 2",          do_div(0x7FFFFFFF, 2),  0x3FFFFFFF);
}

// -- DIVU (unsigned division) ----------------------------------------------

static void test_divu(void) {
    log_write(NONE, "\n=== DIVU (unsigned) ===\n");

    checku32("10u / 3u = 3",        do_divu(10u, 3u),       3u);
    checku32("0u / 5u = 0",         do_divu(0u, 5u),        0u);
    checku32("UINT_MAX / 1 = UINT_MAX", do_divu(0xFFFFFFFFu, 1u),
                                         0xFFFFFFFFu);
    // RISC-V spec: n / 0 = UINT_MAX (all ones)
    checku32("5u / 0u = UINT_MAX",  do_divu(5u, 0u),        0xFFFFFFFFu);
    checku32("UINT_MAX / 0 = UINT_MAX", do_divu(0xFFFFFFFFu, 0u),
                                         0xFFFFFFFFu);
    // 0x80000000 treated as large positive unsigned value
    checku32("0x8000_0000u / 2u",   do_divu(0x80000000u, 2u),
                                     0x40000000u);
    checku32("100u / 10u = 10",     do_divu(100u, 10u),     10u);
}

// -- REM (signed remainder) ------------------------------------------------

static void test_rem(void) {
    log_write(NONE, "\n=== REM (signed) ===\n");

    check32("10 % 3 = 1",           do_rem(10, 3),          1);
    check32("-10 % 3 = -1",         do_rem(-10, 3),         -1);
    check32("10 % -3 = 1",          do_rem(10, -3),         1);
    check32("-10 % -3 = -1",        do_rem(-10, -3),        -1);
    check32("0 % 5 = 0",            do_rem(0, 5),           0);
    // RISC-V spec: n % 0 = n (dividend unchanged)
    check32("5 % 0 = 5",            do_rem(5, 0),           5);
    check32("-7 % 0 = -7",          do_rem(-7, 0),          -7);
    // INT_MIN % -1 overflows -> result = 0 (spec-defined)
    check32("INT_MIN % -1 = 0",     do_rem((int32_t)0x80000000, -1), 0);
    check32("100 % 10 = 0",         do_rem(100, 10),        0);
    check32("7 % 7 = 0",            do_rem(7, 7),           0);
}

// -- REMU (unsigned remainder) ---------------------------------------------

static void test_remu(void) {
    log_write(NONE, "\n=== REMU (unsigned) ===\n");

    checku32("10u % 3u = 1",        do_remu(10u, 3u),       1u);
    checku32("0u % 5u = 0",         do_remu(0u, 5u),        0u);
    // RISC-V spec: n % 0 = n
    checku32("5u % 0u = 5",         do_remu(5u, 0u),        5u);
    checku32("UINT_MAX % 0 = UINT_MAX", do_remu(0xFFFFFFFFu, 0u),
                                         0xFFFFFFFFu);
    checku32("UINT_MAX % 2 = 1",    do_remu(0xFFFFFFFFu, 2u), 1u);
    checku32("100u % 10u = 0",      do_remu(100u, 10u),     0u);
    // 0x80000001 % 2 = 1
    checku32("0x8000_0001u % 2 = 1", do_remu(0x80000001u, 2u), 1u);
}

// -- Main ------------------------------------------------------------------

int main(void) {
    uart_puts("=== M-Extension Test ===\n");
    if (log_init("m-ext-test.log") != 0) {
        uart_puts("ERROR: log_init failed\n");
        return 1;
    }

    log_write(NONE, "=== M Extension Test (RV32IMC) ===\n");
    log_write(NONE, "All 8 M instructions with edge cases.\n");

    test_mul();
    test_mulh();
    test_mulhsu();
    test_mulhu();
    test_div();
    test_divu();
    test_rem();
    test_remu();

    log_write(NONE, "\n=== Summary ===\n");
    log_write(NONE, "  PASS: %d\n", g_pass);
    log_write(NONE, "  FAIL: %d\n", g_fail);
    log_write(NONE, "  %s\n", g_fail == 0 ? "ALL TESTS PASSED" : "SOME TESTS FAILED");

    log_close();
    uart_puts(g_fail == 0 ? "ALL PASSED\n" : "SOME FAILED\n");
    return g_fail;
}
