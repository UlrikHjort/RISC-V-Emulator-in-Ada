/* **************************************************************************
 *      RISC-V Emulator - Zba address-generation extension test (RV32)
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

// zba-test.c -- Zba address-generation extension test (RV32)
//
// Zba instructions (RV32):
//   sh1add rd, rs1, rs2  ->  rd = rs2 + (rs1 << 1)
//   sh2add rd, rs1, rs2  ->  rd = rs2 + (rs1 << 2)
//   sh3add rd, rs1, rs2  ->  rd = rs2 + (rs1 << 3)
//
// Typical use: address calculation for element arrays.
//   int16_t *a; a[i] = ...  ->  sh1add ptr, i, base
//   int32_t *a; a[i] = ...  ->  sh2add ptr, i, base
//   int64_t *a; a[i] = ...  ->  sh3add ptr, i, base
//
// Tests:
//   - Known-value arithmetic checks for each instruction
//   - Zero base, zero index, combined
//   - Large values (wrap in 32-bit)
//   - Array-index pattern: compute element address and read/write
//   - Alias check: sh1add(x, y) == 2*x + y  etc.
//
// Build: cd programs && make run-zba-test
// By Ulrik Hørlyk Hjort 2026

#include <stdint.h>
#include "log.h"

static int g_pass = 0, g_fail = 0;

/* -- inline asm wrappers ---------------------------------------------------- */

static inline uint32_t sh1add(uint32_t rs1, uint32_t rs2)
{
    uint32_t rd;
    asm volatile("sh1add %0, %1, %2" : "=r"(rd) : "r"(rs1), "r"(rs2));
    return rd;
}

static inline uint32_t sh2add(uint32_t rs1, uint32_t rs2)
{
    uint32_t rd;
    asm volatile("sh2add %0, %1, %2" : "=r"(rd) : "r"(rs1), "r"(rs2));
    return rd;
}

static inline uint32_t sh3add(uint32_t rs1, uint32_t rs2)
{
    uint32_t rd;
    asm volatile("sh3add %0, %1, %2" : "=r"(rd) : "r"(rs1), "r"(rs2));
    return rd;
}

/* -- test helpers ----------------------------------------------------------- */

static void chk(const char *lbl, uint32_t got, uint32_t exp)
{
    if (got == exp) {
        log_write(NONE, "  PASS  %s\n", lbl);
        g_pass++;
    } else {
        log_write(NONE, "  FAIL  %s: got 0x%x  exp 0x%x\n", lbl, (int)got, (int)exp);
        g_fail++;
    }
}

/* -- tests ------------------------------------------------------------------ */

static void test_sh1add(void)
{
    log_write(NONE, "\n-- sh1add: rd = rs2 + (rs1 << 1) --\n");

    /* Basic: sh1add(1, 0) = 2 */
    chk("sh1add(1,0) = 2",       sh1add(1, 0),           2);
    /* sh1add(3, 10) = 10 + 6 = 16 */
    chk("sh1add(3,10) = 16",     sh1add(3, 10),          16);
    /* sh1add(0, 5) = 5 + 0 = 5 */
    chk("sh1add(0,5) = 5",       sh1add(0, 5),           5);
    /* sh1add(0, 0) = 0 */
    chk("sh1add(0,0) = 0",       sh1add(0, 0),           0);
    /* sh1add(100, 200) = 200 + 200 = 400 */
    chk("sh1add(100,200) = 400", sh1add(100, 200),       400);
    /* All-ones rs1: (0xFFFFFFFF << 1) + 0 = 0xFFFFFFFE (wraps) */
    chk("sh1add(0xFFFFFFFF,0) = 0xFFFFFFFE",
        sh1add(0xFFFFFFFFu, 0), 0xFFFFFFFEu);
    /* Wrap: sh1add(0x80000000, 1) = 0x00000000 + 1 = 1 */
    chk("sh1add(0x80000000,1) = 1",
        sh1add(0x80000000u, 1), 1u);
    /* 0x7FFFFFFF << 1 = 0xFFFFFFFE; +1 = 0xFFFFFFFF */
    chk("sh1add(0x7FFFFFFF,1) = 0xFFFFFFFF",
        sh1add(0x7FFFFFFFu, 1), 0xFFFFFFFFu);
}

static void test_sh2add(void)
{
    log_write(NONE, "\n-- sh2add: rd = rs2 + (rs1 << 2) --\n");

    chk("sh2add(1,0) = 4",        sh2add(1, 0),           4);
    chk("sh2add(3,10) = 22",      sh2add(3, 10),          22);  /* 10 + 12 */
    chk("sh2add(0,5) = 5",        sh2add(0, 5),           5);
    chk("sh2add(0,0) = 0",        sh2add(0, 0),           0);
    chk("sh2add(10,100) = 140",   sh2add(10, 100),        140); /* 100+40 */
    chk("sh2add(0x40000000,0) = 0",
        sh2add(0x40000000u, 0), 0u);   /* <<2 overflows to 0 */
    chk("sh2add(0x40000001,1) = 5",
        sh2add(0x40000001u, 1), 5u);   /* (1<<2)+1 = 5 in low bits */
    chk("sh2add(0xFFFFFFFF,0) = 0xFFFFFFFC",
        sh2add(0xFFFFFFFFu, 0), 0xFFFFFFFCu);
}

static void test_sh3add(void)
{
    log_write(NONE, "\n-- sh3add: rd = rs2 + (rs1 << 3) --\n");

    chk("sh3add(1,0) = 8",        sh3add(1, 0),           8);
    chk("sh3add(3,10) = 34",      sh3add(3, 10),          34);  /* 10 + 24 */
    chk("sh3add(0,5) = 5",        sh3add(0, 5),           5);
    chk("sh3add(0,0) = 0",        sh3add(0, 0),           0);
    chk("sh3add(5,100) = 140",    sh3add(5, 100),         140); /* 100+40 */
    chk("sh3add(0x20000000,0) = 0",
        sh3add(0x20000000u, 0), 0u);   /* <<3 overflows to 0 */
    chk("sh3add(0xFFFFFFFF,0) = 0xFFFFFFF8",
        sh3add(0xFFFFFFFFu, 0), 0xFFFFFFF8u);
    chk("sh3add(1,0xFFFFFFFF) = 7",
        sh3add(1u, 0xFFFFFFFFu), 7u);  /* 0xFFFFFFFF + 8 wraps to 7 */
}

static void test_array_addressing(void)
{
    log_write(NONE, "\n-- Array addressing patterns --\n");

    /* int16_t array, 8 elements */
    int16_t a16[8] = {10, 20, 30, 40, 50, 60, 70, 80};

    /* sh1add to get address of a16[i] (element size=2) */
    for (int i = 0; i < 8; i++) {
        uint32_t base = (uint32_t)(uintptr_t)a16;
        uint32_t addr = sh1add((uint32_t)i, base);
        int16_t *elem = (int16_t *)(uintptr_t)addr;
        if (*elem == (int16_t)(10 * (i + 1))) {
            log_write(NONE, "  PASS  a16[%d] via sh1add = %d\n", i, (int)*elem);
            g_pass++;
        } else {
            log_write(NONE, "  FAIL  a16[%d] via sh1add: got %d exp %d\n",
                      i, (int)*elem, 10*(i+1));
            g_fail++;
        }
    }

    /* int32_t array, 8 elements */
    int32_t a32[8] = {100, 200, 300, 400, 500, 600, 700, 800};

    for (int i = 0; i < 8; i++) {
        uint32_t base = (uint32_t)(uintptr_t)a32;
        uint32_t addr = sh2add((uint32_t)i, base);
        int32_t *elem = (int32_t *)(uintptr_t)addr;
        if (*elem == (int32_t)(100 * (i + 1))) {
            log_write(NONE, "  PASS  a32[%d] via sh2add = %d\n", i, (int)*elem);
            g_pass++;
        } else {
            log_write(NONE, "  FAIL  a32[%d] via sh2add: got %d exp %d\n",
                      i, (int)*elem, 100*(i+1));
            g_fail++;
        }
    }

    /* int64_t array, 4 elements (element size=8) */
    int64_t a64[4] = {1000, 2000, 3000, 4000};

    for (int i = 0; i < 4; i++) {
        uint32_t base = (uint32_t)(uintptr_t)a64;
        uint32_t addr = sh3add((uint32_t)i, base);
        int64_t *elem = (int64_t *)(uintptr_t)addr;
        int64_t exp64 = (int64_t)(1000 * (i + 1));
        if (*elem == exp64) {
            log_write(NONE, "  PASS  a64[%d] via sh3add\n", i);
            g_pass++;
        } else {
            log_write(NONE, "  FAIL  a64[%d] via sh3add: got %d exp %d\n",
                      i, (int)*elem, 1000*(i+1));
            g_fail++;
        }
    }
}

static void test_equivalence(void)
{
    log_write(NONE, "\n-- Equivalence: shnXadd(x,y) == (x << n) + y --\n");

    /* Test a range of values to confirm sh?add == software equivalent */
    uint32_t vals[] = {0, 1, 7, 13, 100, 0x1234, 0xFFFF, 0x80000000u, 0xFFFFFFFFu};
    int nv = (int)(sizeof(vals) / sizeof(vals[0]));

    for (int i = 0; i < nv; i++) {
        for (int j = 0; j < nv; j++) {
            uint32_t a = vals[i], b = vals[j];
            uint32_t e1 = (a << 1) + b;
            uint32_t e2 = (a << 2) + b;
            uint32_t e3 = (a << 3) + b;
            if (sh1add(a, b) != e1) { g_fail++; continue; }
            if (sh2add(a, b) != e2) { g_fail++; continue; }
            if (sh3add(a, b) != e3) { g_fail++; continue; }
            g_pass++;
        }
    }
    log_write(NONE, "  PASS  %d equivalence pairs (sh1/sh2/sh3add)\n", nv * nv);
}

/* -- main ------------------------------------------------------------------- */
int main(void)
{
    log_init("zba-test.log");
    log_write(NONE, "=== Zba Address-Generation Extension Test (RV32) ===\n");

    test_sh1add();
    test_sh2add();
    test_sh3add();
    test_array_addressing();
    test_equivalence();

    log_write(NONE, "\n=== Result: %d PASS  %d FAIL ===\n", g_pass, g_fail);
    log_close();
    return g_fail;
}
