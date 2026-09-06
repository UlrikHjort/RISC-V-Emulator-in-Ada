/* **************************************************************************
 *               RISC-V Emulator - RV64 Atomic Operations Test
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
 * Tests all 64-bit AMO instructions (A extension, .D suffix):
 *
 *   LR.D / SC.D    -- load-reserved / store-conditional
 *   AMOSWAP.D      -- atomic swap
 *   AMOADD.D       -- atomic add
 *   AMOXOR.D       -- atomic XOR
 *   AMOAND.D       -- atomic AND
 *   AMOOR.D        -- atomic OR
 *   AMOMIN.D       -- atomic signed min
 *   AMOMAX.D       -- atomic signed max
 *   AMOMINU.D      -- atomic unsigned min
 *   AMOMAXU.D      -- atomic unsigned max
 *
 * Each AMO returns the old memory value and updates memory.
 * All operations use 64-bit (doubleword) values.
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
/* Inline-asm AMO wrappers -- force the exact 64-bit instruction       */
/* ------------------------------------------------------------------ */

static uint64_t amoswap_d(uint64_t *addr, uint64_t val)
{
    uint64_t old;
    __asm__ volatile("amoswap.d %0, %2, (%1)"
                     : "=r"(old) : "r"(addr), "r"(val) : "memory");
    return old;
}

static uint64_t amoadd_d(uint64_t *addr, uint64_t val)
{
    uint64_t old;
    __asm__ volatile("amoadd.d %0, %2, (%1)"
                     : "=r"(old) : "r"(addr), "r"(val) : "memory");
    return old;
}

static uint64_t amoxor_d(uint64_t *addr, uint64_t val)
{
    uint64_t old;
    __asm__ volatile("amoxor.d %0, %2, (%1)"
                     : "=r"(old) : "r"(addr), "r"(val) : "memory");
    return old;
}

static uint64_t amoand_d(uint64_t *addr, uint64_t val)
{
    uint64_t old;
    __asm__ volatile("amoand.d %0, %2, (%1)"
                     : "=r"(old) : "r"(addr), "r"(val) : "memory");
    return old;
}

static uint64_t amoor_d(uint64_t *addr, uint64_t val)
{
    uint64_t old;
    __asm__ volatile("amoor.d %0, %2, (%1)"
                     : "=r"(old) : "r"(addr), "r"(val) : "memory");
    return old;
}

static uint64_t amomin_d(uint64_t *addr, int64_t val)
{
    uint64_t old;
    __asm__ volatile("amomin.d %0, %2, (%1)"
                     : "=r"(old) : "r"(addr), "r"(val) : "memory");
    return old;
}

static uint64_t amomax_d(uint64_t *addr, int64_t val)
{
    uint64_t old;
    __asm__ volatile("amomax.d %0, %2, (%1)"
                     : "=r"(old) : "r"(addr), "r"(val) : "memory");
    return old;
}

static uint64_t amominu_d(uint64_t *addr, uint64_t val)
{
    uint64_t old;
    __asm__ volatile("amominu.d %0, %2, (%1)"
                     : "=r"(old) : "r"(addr), "r"(val) : "memory");
    return old;
}

static uint64_t amomaxu_d(uint64_t *addr, uint64_t val)
{
    uint64_t old;
    __asm__ volatile("amomaxu.d %0, %2, (%1)"
                     : "=r"(old) : "r"(addr), "r"(val) : "memory");
    return old;
}

/* LR.D / SC.D */
static uint64_t lr_d(uint64_t *addr)
{
    uint64_t val;
    __asm__ volatile("lr.d %0, (%1)" : "=r"(val) : "r"(addr) : "memory");
    return val;
}

static int sc_d(uint64_t *addr, uint64_t val)
{
    uint64_t res;
    __asm__ volatile("sc.d %0, %2, (%1)"
                     : "=r"(res) : "r"(addr), "r"(val) : "memory");
    return (int)res;   /* 0 = success, 1 = failure */
}

/* ------------------------------------------------------------------ */

int main(void)
{
    log_init("rv64-atomic-test.log");
    log_write(NONE, "RV64 Atomic Operations Test\n\n");

    volatile uint64_t mem;

    /* ---- AMOSWAP.D ---- */
    log_write(NONE, "--- AMOSWAP.D ---\n");
    mem = 0xDEADBEEFCAFEBABEULL;
    uint64_t old = amoswap_d((uint64_t *)&mem, 0x0123456789ABCDEFULL);
    chk("amoswap.d returns old",  old == 0xDEADBEEFCAFEBABEULL);
    chk("amoswap.d memory new",   mem == 0x0123456789ABCDEFULL);

    /* ---- AMOADD.D ---- */
    log_write(NONE, "--- AMOADD.D ---\n");
    mem = 0x100000000ULL;
    old = amoadd_d((uint64_t *)&mem, 0x200000000ULL);
    chk("amoadd.d returns old",   old == 0x100000000ULL);
    chk("amoadd.d memory = sum",  mem == 0x300000000ULL);

    /* Negative add (subtract) using 64-bit wraparound */
    mem = 0x300000000ULL;
    old = amoadd_d((uint64_t *)&mem, (uint64_t)(-1LL));
    chk("amoadd.d -1 returns old", old == 0x300000000ULL);
    chk("amoadd.d -1 wraps",       mem == 0x2FFFFFFFFULL);

    /* ---- AMOXOR.D ---- */
    log_write(NONE, "--- AMOXOR.D ---\n");
    mem = 0xAAAAAAAAAAAAAAAAULL;
    old = amoxor_d((uint64_t *)&mem, 0x5555555555555555ULL);
    chk("amoxor.d returns old",  old == 0xAAAAAAAAAAAAAAAAULL);
    chk("amoxor.d all bits flip", mem == 0xFFFFFFFFFFFFFFFFULL);

    /* XOR with self = 0 */
    old = amoxor_d((uint64_t *)&mem, 0xFFFFFFFFFFFFFFFFULL);
    chk("amoxor.d self = 0",      mem == 0ULL);

    /* ---- AMOAND.D ---- */
    log_write(NONE, "--- AMOAND.D ---\n");
    mem = 0xFFFF0000FFFF0000ULL;
    old = amoand_d((uint64_t *)&mem, 0x0F0F0F0F0F0F0F0FULL);
    chk("amoand.d returns old",  old == 0xFFFF0000FFFF0000ULL);
    chk("amoand.d result",       mem == 0x0F0F00000F0F0000ULL);

    /* ---- AMOOR.D ---- */
    log_write(NONE, "--- AMOOR.D ---\n");
    mem = 0x0F0F0F0F0F0F0F0FULL;
    old = amoor_d((uint64_t *)&mem, 0xF0F0F0F0F0F0F0F0ULL);
    chk("amoor.d returns old",   old == 0x0F0F0F0F0F0F0F0FULL);
    chk("amoor.d all bits set",  mem == 0xFFFFFFFFFFFFFFFFULL);

    /* ---- AMOMIN.D (signed) ---- */
    log_write(NONE, "--- AMOMIN.D ---\n");
    /* negative value < positive: memory gets negative */
    mem = (uint64_t)100LL;
    old = amomin_d((uint64_t *)&mem, -1LL);
    chk("amomin.d returns old",       old == 100ULL);
    chk("amomin.d stores smaller",    (int64_t)mem == -1LL);

    /* positive < existing negative: memory stays negative */
    mem = (uint64_t)(-50LL);
    old = amomin_d((uint64_t *)&mem, 10LL);
    chk("amomin.d -50 < 10: old",     (int64_t)old == -50LL);
    chk("amomin.d -50 < 10: stays",   (int64_t)mem == -50LL);

    /* ---- AMOMAX.D (signed) ---- */
    log_write(NONE, "--- AMOMAX.D ---\n");
    mem = (uint64_t)(-1LL);
    old = amomax_d((uint64_t *)&mem, 42LL);
    chk("amomax.d returns old",       (int64_t)old == -1LL);
    chk("amomax.d stores larger",     (int64_t)mem == 42LL);

    /* smaller value: memory unchanged */
    old = amomax_d((uint64_t *)&mem, -99LL);
    chk("amomax.d 42 > -99: stays",   (int64_t)mem == 42LL);

    /* ---- AMOMINU.D (unsigned) ---- */
    log_write(NONE, "--- AMOMINU.D ---\n");
    /* 0xFFFF... is large unsigned but would be negative signed */
    mem = 0xFFFFFFFFFFFFFFFFULL;
    old = amominu_d((uint64_t *)&mem, 0x8000000000000000ULL);
    chk("amominu.d returns old",      old == 0xFFFFFFFFFFFFFFFFULL);
    chk("amominu.d stores smaller",   mem == 0x8000000000000000ULL);

    /* ---- AMOMAXU.D (unsigned) ---- */
    log_write(NONE, "--- AMOMAXU.D ---\n");
    mem = 0x7FFFFFFFFFFFFFFFULL;
    old = amomaxu_d((uint64_t *)&mem, 0x8000000000000000ULL);
    chk("amomaxu.d returns old",      old == 0x7FFFFFFFFFFFFFFFULL);
    chk("amomaxu.d stores larger",    mem == 0x8000000000000000ULL);

    /* smaller unsigned: unchanged */
    old = amomaxu_d((uint64_t *)&mem, 1ULL);
    chk("amomaxu.d 1 < max: stays",   mem == 0x8000000000000000ULL);

    /* ---- LR.D / SC.D ---- */
    log_write(NONE, "--- LR.D / SC.D ---\n");
    mem = 0xCAFEBABEDEAD1234ULL;
    uint64_t loaded = lr_d((uint64_t *)&mem);
    chk("lr.d reads value",           loaded == 0xCAFEBABEDEAD1234ULL);

    /* SC immediately after LR should succeed (0 = success) */
    int sc_res = sc_d((uint64_t *)&mem, 0x1111222233334444ULL);
    chk("sc.d succeeds (returns 0)",  sc_res == 0);
    chk("sc.d wrote new value",       mem == 0x1111222233334444ULL);

    /* CAS pattern: load, check, conditionally store */
    mem = 0xABCDEF0123456789ULL;
    uint64_t expected = 0xABCDEF0123456789ULL;
    uint64_t desired  = 0x9999999999999999ULL;
    uint64_t got = lr_d((uint64_t *)&mem);
    int cas_ok = 0;
    if (got == expected)
        cas_ok = (sc_d((uint64_t *)&mem, desired) == 0);
    chk("lr.d/sc.d CAS succeeds",     cas_ok);
    chk("lr.d/sc.d CAS wrote value",  mem == desired);

    log_write(NONE, "\n%d PASS  %d FAIL\n", g_pass, g_fail);
    log_close();
    return g_fail;
}
