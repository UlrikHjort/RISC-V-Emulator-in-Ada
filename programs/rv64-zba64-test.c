/* **************************************************************************
 *               RISC-V Emulator - RV64 Zba Extension Test
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
 * **************************************************************************
 * Tests all RV64 Zba instructions:
 *
 *   sh1add   -- rd = rs2 + (rs1 << 1)   (64-bit operands)
 *   sh2add   -- rd = rs2 + (rs1 << 2)
 *   sh3add   -- rd = rs2 + (rs1 << 3)
 *   add.uw   -- rd = rs2 + zero_extend(rs1[31:0])
 *   sh1add.uw -- rd = rs2 + (zero_extend(rs1[31:0]) << 1)
 *   sh2add.uw -- rd = rs2 + (zero_extend(rs1[31:0]) << 2)
 *   sh3add.uw -- rd = rs2 + (zero_extend(rs1[31:0]) << 3)
 */

#include <stdint.h>
#include "log.h"

static int g_pass = 0, g_fail = 0;

static void chk(const char *label, int ok)
{
    if (ok) { log_write(NONE, "PASS %s\n", label); g_pass++; }
    else     { log_write(NONE, "FAIL %s\n", label); g_fail++; }
}

/* ------------------------------------------------------------------ */
/* Inline-asm wrappers to force exact Zba instructions                */
/* ------------------------------------------------------------------ */

static uint64_t sh1add(uint64_t rs1, uint64_t rs2)
{
    uint64_t rd;
    __asm__ volatile("sh1add %0, %1, %2" : "=r"(rd) : "r"(rs1), "r"(rs2));
    return rd;
}

static uint64_t sh2add(uint64_t rs1, uint64_t rs2)
{
    uint64_t rd;
    __asm__ volatile("sh2add %0, %1, %2" : "=r"(rd) : "r"(rs1), "r"(rs2));
    return rd;
}

static uint64_t sh3add(uint64_t rs1, uint64_t rs2)
{
    uint64_t rd;
    __asm__ volatile("sh3add %0, %1, %2" : "=r"(rd) : "r"(rs1), "r"(rs2));
    return rd;
}

static uint64_t add_uw(uint64_t rs1, uint64_t rs2)
{
    uint64_t rd;
    __asm__ volatile("add.uw %0, %1, %2" : "=r"(rd) : "r"(rs1), "r"(rs2));
    return rd;
}

static uint64_t sh1add_uw(uint64_t rs1, uint64_t rs2)
{
    uint64_t rd;
    __asm__ volatile("sh1add.uw %0, %1, %2" : "=r"(rd) : "r"(rs1), "r"(rs2));
    return rd;
}

static uint64_t sh2add_uw(uint64_t rs1, uint64_t rs2)
{
    uint64_t rd;
    __asm__ volatile("sh2add.uw %0, %1, %2" : "=r"(rd) : "r"(rs1), "r"(rs2));
    return rd;
}

static uint64_t sh3add_uw(uint64_t rs1, uint64_t rs2)
{
    uint64_t rd;
    __asm__ volatile("sh3add.uw %0, %1, %2" : "=r"(rd) : "r"(rs1), "r"(rs2));
    return rd;
}

/* ------------------------------------------------------------------ */

int main(void)
{
    log_init("rv64-zba64-test.log");
    log_write(NONE, "RV64 Zba Extension Test\n\n");

    /* ---- sh1add (64-bit) ---- */
    log_write(NONE, "--- sh1add ---\n");
    /* rd = rs2 + (rs1 << 1) */
    chk("sh1add basic",      sh1add(4, 10)  == 18);    /* 10 + 8 */
    chk("sh1add zero rs1",   sh1add(0, 100) == 100);
    chk("sh1add zero rs2",   sh1add(8, 0)   == 16);
    /* Array-index use: base + index*2 */
    chk("sh1add stride-2",   sh1add(3, 0x1000) == 0x1006);
    /* 64-bit: high bits of rs1 are used */
    chk("sh1add 64bit",
        sh1add(0x100000000ULL, 0) == 0x200000000ULL);

    /* ---- sh2add (64-bit) ---- */
    log_write(NONE, "--- sh2add ---\n");
    /* rd = rs2 + (rs1 << 2) */
    chk("sh2add basic",      sh2add(4, 10)  == 26);    /* 10 + 16 */
    chk("sh2add zero rs1",   sh2add(0, 200) == 200);
    chk("sh2add zero rs2",   sh2add(5, 0)   == 20);
    /* Array-index use: base + index*4 */
    chk("sh2add stride-4",   sh2add(7, 0x2000) == 0x201C);
    chk("sh2add 64bit",
        sh2add(0x100000000ULL, 0) == 0x400000000ULL);

    /* ---- sh3add (64-bit) ---- */
    log_write(NONE, "--- sh3add ---\n");
    /* rd = rs2 + (rs1 << 3) */
    chk("sh3add basic",      sh3add(4, 10)  == 42);    /* 10 + 32 */
    chk("sh3add zero rs1",   sh3add(0, 300) == 300);
    chk("sh3add zero rs2",   sh3add(6, 0)   == 48);
    /* Array-index use: base + index*8 */
    chk("sh3add stride-8",   sh3add(5, 0x3000) == 0x3028);
    chk("sh3add 64bit",
        sh3add(0x100000000ULL, 0) == 0x800000000ULL);

    /* ---- add.uw ---- */
    log_write(NONE, "--- add.uw ---\n");
    /* rd = rs2 + zero_extend(rs1[31:0]) -- upper 32 bits of rs1 ignored */
    chk("add.uw basic",      add_uw(5, 10) == 15);
    chk("add.uw zero rs1",   add_uw(0, 0xABCDULL) == 0xABCDULL);
    /* rs1 has high bits set -- they must be zeroed */
    chk("add.uw clears hi",
        add_uw(0xFFFFFFFF00000001ULL, 0x100) == 0x101);
    /* rs1 lower 32 bits all ones */
    chk("add.uw lo-all-1",
        add_uw(0xFFFFFFFFFFFFFFFFULL, 1) == 0x100000000ULL);
    /* rs2 may be any 64-bit value */
    chk("add.uw big rs2",
        add_uw(1, 0x8000000000000000ULL) == 0x8000000000000001ULL);

    /* ---- sh1add.uw ---- */
    log_write(NONE, "--- sh1add.uw ---\n");
    /* rd = rs2 + (zero_extend(rs1[31:0]) << 1) */
    chk("sh1add.uw basic",   sh1add_uw(4, 10) == 18);
    /* high bits of rs1 must be ignored */
    chk("sh1add.uw clears hi",
        sh1add_uw(0xFFFFFFFF00000004ULL, 10) == 18);
    chk("sh1add.uw lo-max",
        sh1add_uw(0xFFFFFFFFULL, 0) == 0x1FFFFFFFEULL);

    /* ---- sh2add.uw ---- */
    log_write(NONE, "--- sh2add.uw ---\n");
    chk("sh2add.uw basic",   sh2add_uw(4, 10) == 26);
    chk("sh2add.uw clears hi",
        sh2add_uw(0xFFFFFFFF00000004ULL, 10) == 26);
    chk("sh2add.uw lo-max",
        sh2add_uw(0xFFFFFFFFULL, 0) == 0x3FFFFFFFCULL);

    /* ---- sh3add.uw ---- */
    log_write(NONE, "--- sh3add.uw ---\n");
    chk("sh3add.uw basic",   sh3add_uw(4, 10) == 42);
    chk("sh3add.uw clears hi",
        sh3add_uw(0xFFFFFFFF00000004ULL, 10) == 42);
    chk("sh3add.uw lo-max",
        sh3add_uw(0xFFFFFFFFULL, 0) == 0x7FFFFFFF8ULL);

    log_write(NONE, "\n%d PASS  %d FAIL\n", g_pass, g_fail);
    log_close();
    return g_fail;
}
