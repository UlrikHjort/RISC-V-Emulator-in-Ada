/* **************************************************************************
 *             RISC-V Emulator - minimal pthread API smoke test
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

/* pthread-test.c -- minimal pthread API smoke test
 *
 * Run with: bin/riscv_emulator --machine qemu-virt --harts 2 \
 *               --log-dir logs programs/out/bin/pthread-test.bin 80000000
 *
 * Tests:
 *   1. Thread creation + join: worker computes a value, hart 0 checks it.
 *   2. Mutex: protected counter incremented by both harts.
 *   3. Sequential reuse: same worker slot used for a second task.
 *   4. pthread_mutex_trylock: returns 0 when free, non-zero when held.
 *   5. Return value from thread (void*).
 *   6. Multiple join calls return correct per-thread retval.
 *
 * NOTE: log_write is NOT thread-safe -- only hart 0 logs.
 *       Worker threads communicate results via shared volatile variables.
 */

#include <stdint.h>
#include <stddef.h>
#include "log.h"
#include "pthread.h"

/* ---- helpers ---------------------------------------------------------- */
static int g_pass = 0, g_fail = 0;

static void chk(const char *label, int ok)
{
    if (ok) { log_write(NONE, "PASS %s\n", label); g_pass++; }
    else     { log_write(NONE, "FAIL %s\n", label); g_fail++; }
}

/* ---- shared state ----------------------------------------------------- */
static volatile uint32_t g_result1  = 0;
static volatile uint32_t g_counter  = 0;
static volatile uint32_t g_result3  = 0;

static pthread_mutex_t g_mutex = PTHREAD_MUTEX_INITIALIZER;

/* ======================================================================
 * Thread functions (run on hart 1)
 * ====================================================================== */

/* Test 1: simple computation */
static void *thread_compute(void *arg)
{
    uint32_t x = (uint32_t)(uintptr_t)arg;
    g_result1 = x * x;           /* 7*7 = 49 */
    return (void *)(uintptr_t)(x + 1);  /* return value: 8 */
}

/* Test 2: mutex-protected counter increment */
static void *thread_increment(void *arg)
{
    (void)arg;
    pthread_mutex_lock(&g_mutex);
    g_counter++;
    pthread_mutex_unlock(&g_mutex);
    return NULL;
}

/* Test 3: sequential reuse of thread slot */
static void *thread_set_result3(void *arg)
{
    g_result3 = (uint32_t)(uintptr_t)arg;
    return NULL;
}

/* Test 5: return a specific pointer value */
static void *thread_retval(void *arg)
{
    (void)arg;
    return (void *)0xDEADBEEFUL;
}

/* ======================================================================
 * Main (hart 0 only)
 * ====================================================================== */
int main(void)
{
    /* Secondary harts do NOT reach main() -- they spin in crt0-pthread.S.
     * If somehow a secondary hart slipped through, exit safely.          */
    uint32_t hid;
    __asm__ volatile ("csrr %0, mhartid" : "=r"(hid));
    if (hid != 0) {
        __asm__ volatile ("li a7, 93\necall" ::: "a7", "memory");
        return 0;
    }

    log_init("pthread-test.log");
    log_write(NONE, "=== pthread-test ===\n");

    pthread_t tid;
    void *ret;

    /* ------------------------------------------------------------------ */
    /* Test 1: create thread, join, check side effect                      */
    /* ------------------------------------------------------------------ */
    g_result1 = 0;
    pthread_create(&tid, NULL, thread_compute, (void *)(uintptr_t)7);
    pthread_join(tid, &ret);
    chk("t1: g_result1 == 49",  g_result1 == 49);
    chk("t1: retval == 8",      (uint32_t)(uintptr_t)ret == 8);

    /* ------------------------------------------------------------------ */
    /* Test 2: mutex protects shared counter                               */
    /* ------------------------------------------------------------------ */
    g_counter = 0;

    /* Hart 0 takes the lock first, then spawns the worker */
    pthread_mutex_lock(&g_mutex);

    pthread_create(&tid, NULL, thread_increment, NULL);

    /* Verify trylock fails while we hold it */
    int tl = pthread_mutex_trylock(&g_mutex);
    chk("t4: trylock returns non-zero when held", tl != 0);

    /* Increment ourselves under the lock */
    g_counter++;
    pthread_mutex_unlock(&g_mutex);   /* release -> worker can proceed */

    pthread_join(tid, NULL);

    chk("t2: counter == 2 after two locked increments", g_counter == 2);

    /* ------------------------------------------------------------------ */
    /* Test 4: trylock succeeds when mutex is free                         */
    /* ------------------------------------------------------------------ */
    pthread_mutex_t m2 = PTHREAD_MUTEX_INITIALIZER;
    int tl2 = pthread_mutex_trylock(&m2);
    chk("t4: trylock returns 0 when unlocked", tl2 == 0);
    pthread_mutex_unlock(&m2);
    pthread_mutex_destroy(&m2);

    /* ------------------------------------------------------------------ */
    /* Test 3: sequential reuse of thread slot                             */
    /* ------------------------------------------------------------------ */
    g_result3 = 0;
    pthread_create(&tid, NULL, thread_set_result3, (void *)(uintptr_t)0xABCD);
    pthread_join(tid, NULL);
    chk("t3: slot reuse, g_result3 == 0xABCD", g_result3 == 0xABCD);

    /* ------------------------------------------------------------------ */
    /* Test 5: thread return value (void*)                                 */
    /* ------------------------------------------------------------------ */
    pthread_create(&tid, NULL, thread_retval, NULL);
    pthread_join(tid, &ret);
    chk("t5: retval == 0xDEADBEEF",
        (uint32_t)(uintptr_t)ret == 0xDEADBEEFUL);

    /* ------------------------------------------------------------------ */
    /* Summary                                                             */
    /* ------------------------------------------------------------------ */
    log_write(NONE, "\n%d PASS  %d FAIL\n", g_pass, g_fail);
    log_close();

    return 0;
}
