/* **************************************************************************
 *    RISC-V Emulator - RISC-V A-extension atomic memory operation tests
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

// atomic-test.c -- RISC-V A-extension atomic memory operation tests.
//
// Tests all RV32A instructions:
//   LR.W / SC.W   -- load-reserved / store-conditional (lock-free CAS)
//   AMOSWAP.W     -- atomic swap
//   AMOADD.W      -- atomic add
//   AMOXOR.W      -- atomic XOR
//   AMOAND.W      -- atomic AND
//   AMOOR.W       -- atomic OR
//   AMOMIN.W      -- atomic signed min
//   AMOMAX.W      -- atomic signed max
//   AMOMINU.W     -- atomic unsigned min
//   AMOMAXU.W     -- atomic unsigned max
//
// Also tests higher-level patterns built from atomics:
//   Compare-and-swap (CAS) using LR/SC
//   Fetch-and-add
//   Spinlock acquire/release (single-hart simulation)
//   Bit-test-and-set
//
// Build: cd programs && make run-atomic-test
// By Ulrik Hørlyk Hjort 2026

#include <stdint.h>
#include <stddef.h>
#include "log.h"

void putchar(char c);
static void uart_puts(const char *s) {
    while (*s) { if (*s == '\n') putchar('\r'); putchar(*s++); }
}

static int g_pass = 0, g_fail = 0;

/* -- Helper ---------------------------------------------------------------- */

static void chk32(const char *lbl, int32_t got, int32_t exp) {
    if (got == exp) {
        log_write(NONE, "  PASS  %s\n", lbl);
        g_pass++;
    } else {
        log_write(NONE, "  FAIL  %s: got %d (0x%x)  exp %d (0x%x)\n",
                  lbl, (int)got, (uint32_t)got, (int)exp, (uint32_t)exp);
        g_fail++;
    }
}

/* -- Raw AMO wrappers (inline asm, no compiler reordering) ---------------- */

/* Returns old value at *addr, stores new_val */
static inline int32_t amoswap(volatile int32_t *addr, int32_t new_val) {
    int32_t old;
    asm volatile("amoswap.w %0, %2, %1"
                 : "=r"(old), "+A"(*addr)
                 : "r"(new_val)
                 : "memory");
    return old;
}

static inline int32_t amoadd(volatile int32_t *addr, int32_t val) {
    int32_t old;
    asm volatile("amoadd.w %0, %2, %1"
                 : "=r"(old), "+A"(*addr)
                 : "r"(val)
                 : "memory");
    return old;
}

static inline int32_t amoxor(volatile int32_t *addr, int32_t val) {
    int32_t old;
    asm volatile("amoxor.w %0, %2, %1"
                 : "=r"(old), "+A"(*addr)
                 : "r"(val)
                 : "memory");
    return old;
}

static inline int32_t amoand(volatile int32_t *addr, int32_t val) {
    int32_t old;
    asm volatile("amoand.w %0, %2, %1"
                 : "=r"(old), "+A"(*addr)
                 : "r"(val)
                 : "memory");
    return old;
}

static inline int32_t amoor(volatile int32_t *addr, int32_t val) {
    int32_t old;
    asm volatile("amoor.w %0, %2, %1"
                 : "=r"(old), "+A"(*addr)
                 : "r"(val)
                 : "memory");
    return old;
}

static inline int32_t amomin(volatile int32_t *addr, int32_t val) {
    int32_t old;
    asm volatile("amomin.w %0, %2, %1"
                 : "=r"(old), "+A"(*addr)
                 : "r"(val)
                 : "memory");
    return old;
}

static inline int32_t amomax(volatile int32_t *addr, int32_t val) {
    int32_t old;
    asm volatile("amomax.w %0, %2, %1"
                 : "=r"(old), "+A"(*addr)
                 : "r"(val)
                 : "memory");
    return old;
}

static inline uint32_t amominu(volatile uint32_t *addr, uint32_t val) {
    uint32_t old;
    asm volatile("amominu.w %0, %2, %1"
                 : "=r"(old), "+A"(*addr)
                 : "r"(val)
                 : "memory");
    return old;
}

static inline uint32_t amomaxu(volatile uint32_t *addr, uint32_t val) {
    uint32_t old;
    asm volatile("amomaxu.w %0, %2, %1"
                 : "=r"(old), "+A"(*addr)
                 : "r"(val)
                 : "memory");
    return old;
}

/* LR.W / SC.W wrappers */
static inline int32_t lr_w(volatile int32_t *addr) {
    int32_t val;
    asm volatile("lr.w %0, %1" : "=r"(val) : "A"(*addr) : "memory");
    return val;
}

/* Returns 0 on success, non-zero on failure */
static inline int sc_w(volatile int32_t *addr, int32_t val) {
    int32_t result;
    asm volatile("sc.w %0, %2, %1"
                 : "=r"(result), "+A"(*addr)
                 : "r"(val)
                 : "memory");
    return (int)result;
}

/* -- Individual AMO tests -------------------------------------------------- */

static void test_amoswap(void) {
    log_write(NONE, "\n=== AMOSWAP.W ===\n");
    volatile int32_t mem;

    mem = 42;
    int32_t old = amoswap(&mem, 100);
    chk32("amoswap: old=42",      old, 42);
    chk32("amoswap: mem=100",     mem, 100);

    mem = -1;
    old = amoswap(&mem, 0);
    chk32("amoswap: old=-1",      old, -1);
    chk32("amoswap: mem=0",       mem, 0);

    /* Swap with same value */
    mem = 7;
    old = amoswap(&mem, 7);
    chk32("amoswap: same old=7",  old, 7);
    chk32("amoswap: same mem=7",  mem, 7);
}

static void test_amoadd(void) {
    log_write(NONE, "\n=== AMOADD.W ===\n");
    volatile int32_t mem;

    mem = 10;
    int32_t old = amoadd(&mem, 5);
    chk32("amoadd: old=10",       old, 10);
    chk32("amoadd: mem=15",       mem, 15);

    mem = 0;
    old = amoadd(&mem, -1);
    chk32("amoadd: 0+(-1) old=0", old, 0);
    chk32("amoadd: 0+(-1) mem=-1",mem, -1);

    /* Wrap-around: MAX_INT + 1 */
    mem = 0x7FFFFFFF;
    amoadd(&mem, 1);
    chk32("amoadd: wrap old==",    mem, (int32_t)0x80000000u);

    /* Accumulate multiple adds */
    mem = 0;
    amoadd(&mem, 10);
    amoadd(&mem, 20);
    amoadd(&mem, 30);
    chk32("amoadd: 0+10+20+30=60", mem, 60);
}

static void test_amoxor(void) {
    log_write(NONE, "\n=== AMOXOR.W ===\n");
    volatile int32_t mem;

    mem = 0xFF00FF00;
    int32_t old = amoxor(&mem, 0x00FF00FF);
    chk32("amoxor: old=0xFF00FF00",  old, (int32_t)0xFF00FF00u);
    chk32("amoxor: mem=0xFFFFFFFF",  mem, (int32_t)0xFFFFFFFFu);

    /* XOR with same -> zeros */
    mem = 0x12345678;
    amoxor(&mem, 0x12345678);
    chk32("amoxor: a^a=0",           mem, 0);

    /* Toggle bits */
    mem = 0xA5A5A5A5;
    amoxor(&mem, 0xFFFFFFFF);
    chk32("amoxor: a^~0=~a",         mem, (int32_t)0x5A5A5A5Au);
}

static void test_amoand(void) {
    log_write(NONE, "\n=== AMOAND.W ===\n");
    volatile int32_t mem;

    mem = 0xFFFF0000;
    int32_t old = amoand(&mem, 0xF0F0F0F0);
    chk32("amoand: old=0xFFFF0000",  old, (int32_t)0xFFFF0000u);
    chk32("amoand: result",          mem, (int32_t)0xF0F00000u);

    /* AND with 0 -> clears */
    mem = 0x12345678;
    amoand(&mem, 0);
    chk32("amoand: a&0=0",           mem, 0);

    /* AND with ~0 -> unchanged */
    mem = 0xABCDEF01;
    amoand(&mem, (int32_t)0xFFFFFFFFu);
    chk32("amoand: a&~0=a",          mem, (int32_t)0xABCDEF01u);
}

static void test_amoor(void) {
    log_write(NONE, "\n=== AMOOR.W ===\n");
    volatile int32_t mem;

    mem = 0x00FF00FF;
    int32_t old = amoor(&mem, 0xFF00FF00);
    chk32("amoor: old=0x00FF00FF",   old, (int32_t)0x00FF00FFu);
    chk32("amoor: result=0xFFFFFFFF",mem, (int32_t)0xFFFFFFFFu);

    /* OR with 0 -> unchanged */
    mem = 0xDEADBEEF;
    amoor(&mem, 0);
    chk32("amoor: a|0=a",            mem, (int32_t)0xDEADBEEFu);

    /* Accumulate bits */
    mem = 0;
    amoor(&mem, 0x1);
    amoor(&mem, 0x2);
    amoor(&mem, 0x4);
    chk32("amoor: set bits",         mem, 7);
}

static void test_amomin_max(void) {
    log_write(NONE, "\n=== AMOMIN.W / AMOMAX.W ===\n");
    volatile int32_t mem;

    /* Signed min: 10 vs 5 -> 5 wins */
    mem = 10;
    int32_t old = amomin(&mem, 5);
    chk32("amomin: old=10",          old, 10);
    chk32("amomin: mem=5",           mem, 5);

    /* Signed min: negative wins */
    mem = 0;
    amomin(&mem, -1);
    chk32("amomin: 0 vs -1 -> -1",   mem, -1);

    /* Signed min: INT_MIN wins over anything */
    mem = 1;
    amomin(&mem, (int32_t)0x80000000u);
    chk32("amomin: INT_MIN wins",    mem, (int32_t)0x80000000u);

    /* Signed max: 10 vs 5 -> 10 */
    mem = 5;
    old = amomax(&mem, 10);
    chk32("amomax: old=5",           old, 5);
    chk32("amomax: mem=10",          mem, 10);

    /* Signed max: positive wins over negative */
    mem = -5;
    amomax(&mem, 0);
    chk32("amomax: -5 vs 0 -> 0",    mem, 0);

    /* Signed max: INT_MAX wins */
    mem = 0;
    amomax(&mem, 0x7FFFFFFF);
    chk32("amomax: INT_MAX wins",    mem, 0x7FFFFFFF);
}

static void test_amominu_maxu(void) {
    log_write(NONE, "\n=== AMOMINU.W / AMOMAXU.W ===\n");
    volatile uint32_t mem;

    /* Unsigned min: 0xFFFFFFFF vs 0 -> 0 wins */
    mem = 0xFFFFFFFF;
    uint32_t old = amominu(&mem, 0);
    chk32("amominu: old=UINT_MAX",   (int32_t)old, (int32_t)0xFFFFFFFFu);
    chk32("amominu: mem=0",          (int32_t)mem, 0);

    /* Unsigned min: smaller value wins */
    mem = 100;
    amominu(&mem, 50);
    chk32("amominu: 100 vs 50=50",   (int32_t)mem, 50);

    /* Unsigned min: 0xFFFFFFFF is LARGE (not negative) */
    mem = 5;
    amominu(&mem, 0xFFFFFFFF);
    chk32("amominu: 5 vs UINT_MAX=5",(int32_t)mem, 5);

    /* Unsigned max */
    mem = 0;
    old = amomaxu(&mem, 0xFFFFFFFF);
    chk32("amomaxu: old=0",          (int32_t)old, 0);
    chk32("amomaxu: mem=UINT_MAX",   (int32_t)mem, (int32_t)0xFFFFFFFFu);

    mem = 100;
    amomaxu(&mem, 50);
    chk32("amomaxu: 100 vs 50=100",  (int32_t)mem, 100);
}

/* -- LR.W / SC.W ----------------------------------------------------------- */

static void test_lr_sc(void) {
    log_write(NONE, "\n=== LR.W / SC.W ===\n");
    volatile int32_t mem;
    int32_t loaded;
    int sc_result;

    /* Basic: LR then immediate SC -- should succeed on single hart */
    mem = 42;
    loaded = lr_w(&mem);
    chk32("lr.w: loaded=42", loaded, 42);

    sc_result = sc_w(&mem, 99);
    chk32("sc.w: success (result=0)", sc_result, 0);
    chk32("sc.w: mem=99", mem, 99);

    /* Second LR/SC cycle */
    mem = 1000;
    loaded = lr_w(&mem);
    chk32("lr.w: loaded=1000", loaded, 1000);
    sc_result = sc_w(&mem, -1);
    chk32("sc.w: success", sc_result, 0);
    chk32("sc.w: mem=-1",   mem, -1);
}

/* -- Compare-and-swap (CAS) using LR/SC ----------------------------------- */

/* Returns 1 if swap succeeded (old == expected), 0 otherwise */
static int cas(volatile int32_t *addr, int32_t expected, int32_t new_val) {
    int32_t old;
    int result;
    asm volatile(
        "1: lr.w   %0, %2       \n"  /* load-reserved */
        "   bne    %0, %3, 2f   \n"  /* if old != expected, fail */
        "   sc.w   %1, %4, %2   \n"  /* store-conditional */
        "   bnez   %1, 1b       \n"  /* retry if SC failed */
        "   j      3f           \n"
        "2: li     %1, 1        \n"  /* failure: set result=1 */
        "3:                     \n"
        : "=&r"(old), "=&r"(result), "+A"(*addr)
        : "r"(expected), "r"(new_val)
        : "memory"
    );
    return result == 0;
}

static void test_cas(void) {
    log_write(NONE, "\n=== CAS (LR/SC compare-and-swap) ===\n");
    volatile int32_t mem;

    /* Successful CAS: expected matches */
    mem = 10;
    int ok = cas(&mem, 10, 20);
    chk32("cas: success->1",      ok, 1);
    chk32("cas: mem=20",         mem, 20);

    /* Failed CAS: expected doesn't match */
    mem = 30;
    ok = cas(&mem, 10, 99);  /* expected=10 but mem=30 */
    chk32("cas: fail->0",         ok, 0);
    chk32("cas: mem unchanged",  mem, 30);

    /* Chain of CAS: increment via CAS */
    mem = 0;
    for (int i = 0; i < 5; i++) {
        int32_t old_v = mem;
        while (!cas(&mem, old_v, old_v + 1))
            old_v = mem;
    }
    chk32("cas: chain 5 increments", mem, 5);
}

/* -- Fetch-and-add (using AMOADD) ----------------------------------------- */

static volatile int32_t shared_counter = 0;

static void test_fetch_add(void) {
    log_write(NONE, "\n=== Fetch-and-Add (AMOADD) ===\n");

    shared_counter = 0;

    /* Simulate 8 "threads" each adding their index */
    int32_t results[8];
    for (int i = 0; i < 8; i++)
        results[i] = amoadd(&shared_counter, i);

    /* Each fetch-add returns the OLD value before its add */
    /* Order is deterministic on single hart: 0,0,1,3,6,10,15,21 */
    chk32("faa: result[0]=0",  results[0], 0);
    chk32("faa: result[1]=0",  results[1], 0);
    chk32("faa: result[2]=1",  results[2], 1);
    chk32("faa: result[3]=3",  results[3], 3);
    /* Final sum: 0+1+2+3+4+5+6+7 = 28 */
    chk32("faa: final=28",     shared_counter, 28);
}

/* -- Spinlock (single-hart simulation) ------------------------------------ */

typedef volatile int32_t spinlock_t;

static void spin_lock(spinlock_t *lock) {
    int32_t old;
    do {
        old = amoswap(lock, 1);
    } while (old != 0);  /* 0=free, 1=held */
}

static void spin_unlock(spinlock_t *lock) {
    amoswap(lock, 0);
}

static void test_spinlock(void) {
    log_write(NONE, "\n=== Spinlock (AMOSWAP-based) ===\n");
    spinlock_t lock = 0;

    /* Acquire -- should succeed immediately (lock is free) */
    spin_lock(&lock);
    chk32("lock: acquired (lock=1)", lock, 1);

    /* Release */
    spin_unlock(&lock);
    chk32("lock: released (lock=0)", lock, 0);

    /* Re-acquire, do work, release */
    spin_lock(&lock);
    volatile int32_t data = 42;
    data += 8;  /* protected work */
    spin_unlock(&lock);
    chk32("lock: protected work=50", data, 50);

    /* Lock should be free again */
    chk32("lock: free after release", lock, 0);
}

/* -- Bit-test-and-set (AMOOR) --------------------------------------------- */

static void test_bitmask_ops(void) {
    log_write(NONE, "\n=== Atomic Bit Mask Operations ===\n");
    volatile int32_t flags = 0;

    /* Atomically set bit 3 */
    amoor(&flags, 1 << 3);
    chk32("amoor: set bit3",   flags, 8);

    /* Atomically set bit 7 */
    amoor(&flags, 1 << 7);
    chk32("amoor: set bit7",   flags, 8 | 128);

    /* Atomically clear bit 3 using AMOAND */
    amoand(&flags, ~(1 << 3));
    chk32("amoand: clr bit3",  flags, 128);

    /* Toggle bit 7 using AMOXOR */
    amoxor(&flags, 1 << 7);
    chk32("amoxor: toggle b7=0", flags, 0);

    /* Test-and-set pattern: get old value */
    flags = 0;
    int32_t was = amoor(&flags, 1);
    chk32("test-set: was 0",   was, 0);
    chk32("test-set: now 1",   flags, 1);
    was = amoor(&flags, 1);
    chk32("test-set: was 1",   was, 1);

    /* Fetch-and-clear: clear all, get old */
    flags = 0xDEAD;
    int32_t old_flags = amoand(&flags, 0);
    chk32("fetch-clr: old=0xDEAD", old_flags, 0xDEAD);
    chk32("fetch-clr: now=0",      flags, 0);
}

/* -- Main ------------------------------------------------------------------- */

int main(void) {
    uart_puts("=== Atomic Operations Test ===\n");
    if (log_init("atomic-test.log") != 0) {
        uart_puts("ERROR: log_init failed\n"); return 1;
    }
    log_write(NONE, "=== RISC-V A-Extension Atomic Operations Test ===\n");

    test_amoswap();
    test_amoadd();
    test_amoxor();
    test_amoand();
    test_amoor();
    test_amomin_max();
    test_amominu_maxu();
    test_lr_sc();
    test_cas();
    test_fetch_add();
    test_spinlock();
    test_bitmask_ops();

    log_write(NONE, "\n=== Summary ===\n");
    log_write(NONE, "  PASS: %d\n", g_pass);
    log_write(NONE, "  FAIL: %d\n", g_fail);
    log_write(NONE, "  %s\n", g_fail == 0 ? "ALL TESTS PASSED" : "SOME TESTS FAILED");
    log_close();

    uart_puts(g_fail == 0 ? "ALL PASSED\n" : "SOME FAILED\n");
    return g_fail;
}
