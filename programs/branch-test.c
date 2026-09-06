/* **************************************************************************
 *           RISC-V Emulator - Exhaustive branch instruction test
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

// branch-test.c -- Exhaustive branch instruction test.
//
// Tests all 6 RISC-V branch instructions with edge cases:
//   BEQ, BNE, BLT, BGE, BLTU, BGEU
//
// Edge cases covered:
//   - Equal values, unequal values
//   - Signed: INT_MIN, INT_MAX, -1, 0, 1
//   - Unsigned: 0, 1, UINT_MAX, INT_MAX+1 (0x80000000)
//   - Forward and backward branches (loops)
//   - Taken vs not-taken
//
// Uses inline asm to force the exact branch instructions so the compiler
// cannot substitute equivalent sequences.
//
// Build: cd programs && make run-branch-test
// By Ulrik Hørlyk Hjort 2026

#include <stdint.h>
#include "log.h"

void putchar(char c);
static void uart_puts(const char *s) {
    while (*s) { if (*s == '\n') putchar('\r'); putchar(*s++); }
}

static int g_pass = 0, g_fail = 0;

static void check(const char *label, int got, int expected) {
    if (got == expected) {
        log_write(NONE, "  PASS  %s\n", label); g_pass++;
    } else {
        log_write(NONE, "  FAIL  %s: got %d  exp %d\n", label, got, expected);
        g_fail++;
    }
}

// -- Inline-asm wrappers -- each returns 1 if branch taken, 0 if not --------

static int beq(int32_t a, int32_t b) {
    int r;
    asm volatile(
        "li   %0, 0\n"
        "beq  %1, %2, 1f\n"
        "j    2f\n"
        "1: li %0, 1\n"
        "2:\n"
        : "=&r"(r) : "r"(a), "r"(b)
    );
    return r;
}

static int bne(int32_t a, int32_t b) {
    int r;
    asm volatile(
        "li   %0, 0\n"
        "bne  %1, %2, 1f\n"
        "j    2f\n"
        "1: li %0, 1\n"
        "2:\n"
        : "=&r"(r) : "r"(a), "r"(b)
    );
    return r;
}

static int blt(int32_t a, int32_t b) {
    int r;
    asm volatile(
        "li   %0, 0\n"
        "blt  %1, %2, 1f\n"
        "j    2f\n"
        "1: li %0, 1\n"
        "2:\n"
        : "=&r"(r) : "r"(a), "r"(b)
    );
    return r;
}

static int bge(int32_t a, int32_t b) {
    int r;
    asm volatile(
        "li   %0, 0\n"
        "bge  %1, %2, 1f\n"
        "j    2f\n"
        "1: li %0, 1\n"
        "2:\n"
        : "=&r"(r) : "r"(a), "r"(b)
    );
    return r;
}

static int bltu(uint32_t a, uint32_t b) {
    int r;
    asm volatile(
        "li   %0, 0\n"
        "bltu %1, %2, 1f\n"
        "j    2f\n"
        "1: li %0, 1\n"
        "2:\n"
        : "=&r"(r) : "r"(a), "r"(b)
    );
    return r;
}

static int bgeu(uint32_t a, uint32_t b) {
    int r;
    asm volatile(
        "li   %0, 0\n"
        "bgeu %1, %2, 1f\n"
        "j    2f\n"
        "1: li %0, 1\n"
        "2:\n"
        : "=&r"(r) : "r"(a), "r"(b)
    );
    return r;
}

// -- BEQ -------------------------------------------------------------------

static void test_beq(void) {
    log_write(NONE, "\n=== BEQ (branch if equal) ===\n");
    check("beq  0,  0 -> taken",     beq(0, 0),          1);
    check("beq  1,  1 -> taken",     beq(1, 1),          1);
    check("beq -1, -1 -> taken",     beq(-1, -1),        1);
    check("beq INT_MIN,INT_MIN -> t", beq(0x80000000, 0x80000000), 1);
    check("beq  0,  1 -> not taken", beq(0, 1),          0);
    check("beq  1, -1 -> not taken", beq(1, -1),         0);
    check("beq -1,  0 -> not taken", beq(-1, 0),         0);
    check("beq INT_MAX,INT_MIN -> n", beq(0x7FFFFFFF, 0x80000000), 0);
}

// -- BNE -------------------------------------------------------------------

static void test_bne(void) {
    log_write(NONE, "\n=== BNE (branch if not equal) ===\n");
    check("bne  0,  1 -> taken",     bne(0, 1),          1);
    check("bne  1, -1 -> taken",     bne(1, -1),         1);
    check("bne INT_MAX,INT_MIN -> t", bne(0x7FFFFFFF, 0x80000000), 1);
    check("bne  0,  0 -> not taken", bne(0, 0),          0);
    check("bne -1, -1 -> not taken", bne(-1, -1),        0);
    check("bne INT_MIN,INT_MIN -> n", bne(0x80000000, 0x80000000), 0);
}

// -- BLT (signed) ----------------------------------------------------------

static void test_blt(void) {
    log_write(NONE, "\n=== BLT (signed less than) ===\n");
    check("blt  0,  1 -> taken",      blt(0, 1),          1);
    check("blt -1,  0 -> taken",      blt(-1, 0),         1);
    check("blt -2, -1 -> taken",      blt(-2, -1),        1);
    check("blt INT_MIN, 0 -> taken",  blt(0x80000000, 0), 1);
    check("blt INT_MIN, INT_MAX -> t", blt(0x80000000, 0x7FFFFFFF), 1);
    check("blt -1,  1 -> taken",      blt(-1, 1),         1);
    // not taken
    check("blt  1,  0 -> not taken",  blt(1, 0),          0);
    check("blt  0, -1 -> not taken",  blt(0, -1),         0);
    check("blt  0,  0 -> not taken",  blt(0, 0),          0);
    check("blt  1,  1 -> not taken",  blt(1, 1),          0);
    check("blt INT_MAX,INT_MIN -> n", blt(0x7FFFFFFF, 0x80000000), 0);
    // 0x80000000 is INT_MIN (signed -2147483648), 0x7FFFFFFF is INT_MAX
    // As unsigned: 0x80000000 > 0x7FFFFFFF, but signed: INT_MIN < INT_MAX
    check("blt -1, 0x7FFFFFFF -> t",  blt(-1, 0x7FFFFFFF), 1);
}

// -- BGE (signed) ----------------------------------------------------------

static void test_bge(void) {
    log_write(NONE, "\n=== BGE (signed greater or equal) ===\n");
    check("bge  1,  0 -> taken",      bge(1, 0),          1);
    check("bge  0, -1 -> taken",      bge(0, -1),         1);
    check("bge  0,  0 -> taken",      bge(0, 0),          1);
    check("bge -1, -1 -> taken",      bge(-1, -1),        1);
    check("bge INT_MAX, 0 -> taken",  bge(0x7FFFFFFF, 0), 1);
    check("bge INT_MAX,INT_MIN -> t", bge(0x7FFFFFFF, 0x80000000), 1);
    // not taken
    check("bge  0,  1 -> not taken",  bge(0, 1),          0);
    check("bge -1,  0 -> not taken",  bge(-1, 0),         0);
    check("bge INT_MIN, 0 -> n",      bge(0x80000000, 0), 0);
    check("bge INT_MIN,INT_MAX -> n", bge(0x80000000, 0x7FFFFFFF), 0);
}

// -- BLTU (unsigned) -------------------------------------------------------

static void test_bltu(void) {
    log_write(NONE, "\n=== BLTU (unsigned less than) ===\n");
    check("bltu  0,  1 -> taken",     bltu(0u, 1u),            1);
    check("bltu  0, UINT_MAX -> t",   bltu(0u, 0xFFFFFFFFu),   1);
    check("bltu  1, UINT_MAX -> t",   bltu(1u, 0xFFFFFFFFu),   1);
    // 0x80000000 = 2^31 as unsigned > 0x7FFFFFFF
    check("bltu 0x7FFF,0x8000 -> t",  bltu(0x7FFFFFFFu, 0x80000000u), 1);
    // not taken
    check("bltu  1,  0 -> not taken", bltu(1u, 0u),            0);
    check("bltu  0,  0 -> not taken", bltu(0u, 0u),            0);
    check("bltu UINT_MAX,0 -> n",     bltu(0xFFFFFFFFu, 0u),   0);
    check("bltu 0x8000,0x7FFF -> n",  bltu(0x80000000u, 0x7FFFFFFFu), 0);
    // -1 as unsigned = UINT_MAX > everything else
    check("bltu -1u, 0 -> not taken", bltu(0xFFFFFFFFu, 0u),   0);
}

// -- BGEU (unsigned) -------------------------------------------------------

static void test_bgeu(void) {
    log_write(NONE, "\n=== BGEU (unsigned greater or equal) ===\n");
    check("bgeu  1,  0 -> taken",     bgeu(1u, 0u),            1);
    check("bgeu  0,  0 -> taken",     bgeu(0u, 0u),            1);
    check("bgeu UINT_MAX,0 -> taken", bgeu(0xFFFFFFFFu, 0u),   1);
    check("bgeu UINT_MAX,UINT_MAX -> t", bgeu(0xFFFFFFFFu, 0xFFFFFFFFu), 1);
    check("bgeu 0x8000,0x7FFF -> t",  bgeu(0x80000000u, 0x7FFFFFFFu), 1);
    // not taken
    check("bgeu  0,  1 -> not taken", bgeu(0u, 1u),            0);
    check("bgeu 0x7FFF,0x8000 -> n",  bgeu(0x7FFFFFFFu, 0x80000000u), 0);
    check("bgeu  0, UINT_MAX -> n",   bgeu(0u, 0xFFFFFFFFu),   0);
}

// -- Loop tests (backward branch) ------------------------------------------

static void test_loops(void) {
    log_write(NONE, "\n=== Loop (backward branch) ===\n");

    // Sum 1..10 with BNE loop
    int32_t sum = 0, i = 1;
    asm volatile(
        "1:\n"
        "add  %0, %0, %2\n"
        "addi %2, %2, 1\n"
        "li   t0, 11\n"
        "bne  %2, t0, 1b\n"
        : "+r"(sum), "+r"(i)       // outputs (modified)
        : "1"(i)                   // i as input also
        : "t0"
    );
    // sum should be 1+2+...+10 = 55
    (void)i;
    check("sum 1..10 via BNE loop = 55", sum, 55);

    // Count down with BGE loop
    int32_t count = 0, n = 10;
    asm volatile(
        "1:\n"
        "addi %0, %0, 1\n"
        "addi %1, %1, -1\n"
        "bge  %1, zero, 1b\n"
        : "+r"(count), "+r"(n)
        :
        :
    );
    check("countdown 10..0 via BGE loop = 11", count, 11);

    // BLTU loop: 0 to 7 (unsigned)
    uint32_t ucount = 0, uj = 0;
    asm volatile(
        "1:\n"
        "addi %0, %0, 1\n"
        "addi %1, %1, 1\n"
        "li   t0, 8\n"
        "bltu %1, t0, 1b\n"
        : "+r"(ucount), "+r"(uj)
        :
        : "t0"
    );
    check("bltu loop 0..7 = 8 iterations", (int)ucount, 8);
}

// -- Main ------------------------------------------------------------------

int main(void) {
    uart_puts("=== Branch Test ===\n");
    if (log_init("branch-test.log") != 0) {
        uart_puts("ERROR: log_init failed\n"); return 1;
    }

    log_write(NONE, "=== Branch Instruction Test (RV32IMC) ===\n");

    test_beq();
    test_bne();
    test_blt();
    test_bge();
    test_bltu();
    test_bgeu();
    test_loops();

    log_write(NONE, "\n=== Summary ===\n");
    log_write(NONE, "  PASS: %d\n", g_pass);
    log_write(NONE, "  FAIL: %d\n", g_fail);
    log_write(NONE, "  %s\n", g_fail == 0 ? "ALL TESTS PASSED" : "SOME TESTS FAILED");

    log_close();
    uart_puts(g_fail == 0 ? "ALL PASSED\n" : "SOME FAILED\n");
    return g_fail;
}
