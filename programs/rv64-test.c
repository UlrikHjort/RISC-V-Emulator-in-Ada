/* **************************************************************************
 *               RISC-V Emulator - RV64 Basic Test
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
 * Tests RV64-specific instructions: 64-bit arithmetic, LD/SD, ADDIW sign
 * extension, MULW/DIVW, and wide immediate values.
 */

#include <stdint.h>
#include "log.h"

static int g_pass = 0, g_fail = 0;

static void chk(const char *label, int ok) {
    if (ok) { log_write(NONE, "PASS %s\n", label); g_pass++; }
    else     { log_write(NONE, "FAIL %s\n", label); g_fail++; }
}

int main(void) {
    log_init("rv64-test.log");

    /* --- 64-bit add / sub --- */
    volatile uint64_t a = 0x100000000ULL;   /* 4 GB */
    volatile uint64_t b = 0x200000000ULL;   /* 8 GB */
    chk("add64", a + b == 0x300000000ULL);
    chk("sub64", b - a == 0x100000000ULL);

    /* --- 64-bit multiply --- */
    volatile uint64_t x = 0x80000000ULL;    /* 2^31 */
    volatile uint64_t y = 0x80000000ULL;
    chk("mul64", x * y == 0x4000000000000000ULL);

    /* --- 64-bit load / store via pointer --- */
    volatile uint64_t buf[2];
    buf[0] = 0xDEADBEEFCAFEBABEULL;
    buf[1] = 0x0123456789ABCDEFULL;
    chk("sd_ld_0", buf[0] == 0xDEADBEEFCAFEBABEULL);
    chk("sd_ld_1", buf[1] == 0x0123456789ABCDEFULL);

    /* --- ADDIW sign extension: adding to lower 32 bits, sign-extended --- */
    volatile uint64_t hi = 0xFFFFFFFF00000000ULL;  /* high word set, low=0 */
    /* Reading lower 32 bits as int32 then widening: 0x00000000 stays 0 */
    volatile int32_t lo32 = (int32_t)(uint32_t)hi;
    chk("addiw_lo", lo32 == 0);

    /* ADDIW on 0x7FFFFFFF + 1 = 0x80000000 sign-extends to 0xFFFFFFFF80000000 */
    volatile int64_t w = (int32_t)0x7FFFFFFF + 1;  /* compiler uses ADDIW */
    chk("addiw_overflow", w == (int64_t)0xFFFFFFFF80000000LL);

    /* --- 64-bit signed comparison --- */
    volatile int64_t neg = -1LL;
    volatile int64_t pos = 1LL;
    chk("slt64_neg_lt_pos", neg < pos);
    chk("slt64_pos_gt_neg", pos > neg);

    /* --- 64-bit shift --- */
    volatile uint64_t one = 1ULL;
    chk("sll64_32", (one << 32) == 0x100000000ULL);
    chk("sll64_63", (one << 63) == 0x8000000000000000ULL);
    chk("srl64_32", (0x100000000ULL >> 32) == 1ULL);

    /* --- 32-bit W instructions on 64-bit registers --- */
    /* ADDW: add lower 32 bits, sign-extend result */
    volatile uint64_t big = 0xFFFFFFFF00000001ULL;
    volatile int64_t addw_res = (int64_t)(int32_t)((uint32_t)big + (uint32_t)1ULL);
    chk("addw", addw_res == 2LL);

    /* MULW: multiply lower 32 bits */
    volatile int64_t mulw_a = 0x100000003LL;   /* lower 32: 3 */
    volatile int64_t mulw_b = 0x100000004LL;   /* lower 32: 4 */
    volatile int64_t mulw_r = (int64_t)(int32_t)((int32_t)mulw_a * (int32_t)mulw_b);
    chk("mulw", mulw_r == 12LL);

    /* DIVW: signed divide lower 32 bits */
    volatile int64_t divw_a = 0x100000064LL;   /* lower 32: 100 */
    volatile int64_t divw_b = 0x100000005LL;   /* lower 32: 5   */
    volatile int64_t divw_r = (int64_t)(int32_t)((int32_t)divw_a / (int32_t)divw_b);
    chk("divw", divw_r == 20LL);

    /* --- 64-bit unsigned division and remainder --- */
    volatile uint64_t ud = 0x8000000000000001ULL;
    volatile uint64_t ub = 3ULL;
    chk("divu64", ud / ub == 0x2AAAAAAAAAAAAAABULL);
    chk("remu64", ud % ub == 0ULL);

    log_write(NONE, "\n%d PASS  %d FAIL\n", g_pass, g_fail);
    log_close();
    return g_fail ? 1 : 0;
}
