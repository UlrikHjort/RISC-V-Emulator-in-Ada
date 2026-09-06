/* **************************************************************************
 *               RISC-V Emulator - Preemptive RTOS Test
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
 * Tests the preemptive RTOS (prtos.h / prtos.c / prtos_trap.S).
 *
 * Four tasks:
 *   A  - yields 5 times (logs 0)
 *   B  - yields 5 times (logs 1)
 *   C  - sleeps ~10 ms, then yields 3 times (logs 2)
 *   D  - tight spin loop (NO yields) -- verifies pure timer preemption
 *
 * Expected exec_log = [0,1,0,1,0,1,0,1,0,1, 2,2,2]  (13 entries)
 *   A and B alternate for 10 entries while C sleeps (and D runs silently),
 *   then C runs 3 times once it wakes.
 *
 * Additional assertions:
 *   g_count_d == D_ITERS     -- D completed via preemption alone (no yields)
 *   g_c_sleep_start_pos == 2 -- C started sleeping after log entries 0 and 1
 *   g_c_wake_pos == 10       -- C woke after A and B each ran 5 times
 */
#include "prtos.h"
#include "log.h"

/* ------------------------------------------------------------------ */
/* Shared state                                                         */
/* ------------------------------------------------------------------ */

#define EXEC_LOG_SIZE   64
#define D_ITERS         200

static volatile int g_exec_log[EXEC_LOG_SIZE];
static volatile int g_log_pos = 0;

static volatile int g_count_a = 0;
static volatile int g_count_b = 0;
static volatile int g_count_c = 0;
static volatile int g_count_d = 0;

static volatile int g_c_sleep_start_pos = 0;
static volatile int g_c_wake_pos        = 0;

static void log_exec(int id)
{
    if (g_log_pos < EXEC_LOG_SIZE)
        g_exec_log[g_log_pos++] = id;
}

/* ------------------------------------------------------------------ */
/* Task bodies                                                          */
/* ------------------------------------------------------------------ */

static void task_a(void)
{
    for (int i = 0; i < 5; i++) {
        g_count_a++;
        log_exec(0);
        task_yield();
    }
}

static void task_b(void)
{
    for (int i = 0; i < 5; i++) {
        g_count_b++;
        log_exec(1);
        task_yield();
    }
}

static void task_c(void)
{
    g_c_sleep_start_pos = g_log_pos;    /* snapshot before sleep */
    task_sleep_ms(10);
    g_c_wake_pos = g_log_pos;           /* snapshot after wake   */

    for (int i = 0; i < 3; i++) {
        g_count_c++;
        log_exec(2);
        task_yield();
    }
}

static void task_d(void)
{
    /* Tight spin loop -- NO explicit yields.
     * Relies entirely on the timer interrupt for preemption. */
    volatile int i;
    for (i = 0; i < D_ITERS; i++)
        g_count_d++;
    /* returns -> task_trampoline -> task_exit */
}

/* ------------------------------------------------------------------ */
/* Test helpers                                                         */
/* ------------------------------------------------------------------ */

static int g_pass = 0;
static int g_fail = 0;

static void check(int cond, const char *name)
{
    if (cond) {
        log_write(NONE, "  PASS  %s\n", name);
        g_pass++;
    } else {
        log_write(NONE, "  FAIL  %s\n", name);
        g_fail++;
    }
}

static void check_eq(int got, int exp, const char *name)
{
    if (got == exp) {
        log_write(NONE, "  PASS  %s\n", name);
        g_pass++;
    } else {
        log_write(NONE, "  FAIL  %s  got=%d exp=%d\n", name, got, exp);
        g_fail++;
    }
}

/* ------------------------------------------------------------------ */
/* Main                                                                 */
/* ------------------------------------------------------------------ */

int main(void)
{
    log_init("prtos-test.log");
    log_write(NONE, "Preemptive RTOS Test\n\n");

    /* Initialise and calibrate */
    prtos_init();

    log_write(NONE, "=== calibration ===\n");
    check(g_mtime_per_ms > 0, "mtime_per_ms > 0");
    log_write(NONE, "  mtime_per_ms = %d\n", (int)g_mtime_per_ms);

    /* Create tasks in order: A=0, B=1, C=2, D=3 */
    prtos_task_create(task_a);
    prtos_task_create(task_b);
    prtos_task_create(task_c);
    prtos_task_create(task_d);

    /* Run until all tasks exit */
    prtos_run();

    /* ---- verify results ---- */
    log_write(NONE, "\n=== run counts ===\n");
    check_eq(g_count_a, 5,       "task A ran 5 times");
    check_eq(g_count_b, 5,       "task B ran 5 times");
    check_eq(g_count_c, 3,       "task C ran 3 times");
    check_eq(g_count_d, D_ITERS, "task D completed D_ITERS (preemptive)");

    log_write(NONE, "\n=== exec_log length ===\n");
    check_eq(g_log_pos, 13, "total log entries == 13");

    log_write(NONE, "\n=== A/B interleaving (positions 0-9) ===\n");
    check_eq(g_exec_log[0], 0, "log[0] == A");
    check_eq(g_exec_log[1], 1, "log[1] == B");
    check_eq(g_exec_log[2], 0, "log[2] == A  (not C, C is sleeping)");
    check_eq(g_exec_log[3], 1, "log[3] == B");
    check_eq(g_exec_log[4], 0, "log[4] == A");
    check_eq(g_exec_log[5], 1, "log[5] == B");
    check_eq(g_exec_log[8], 0, "log[8] == A (5th)");
    check_eq(g_exec_log[9], 1, "log[9] == B (5th)");

    log_write(NONE, "\n=== C runs after sleep (positions 10-12) ===\n");
    check_eq(g_exec_log[10], 2, "log[10] == C (1st)");
    check_eq(g_exec_log[11], 2, "log[11] == C (2nd)");
    check_eq(g_exec_log[12], 2, "log[12] == C (3rd)");

    log_write(NONE, "\n=== sleep positions ===\n");
    check_eq(g_c_sleep_start_pos, 2,
             "C started sleeping at log_pos 2 (after A[0] and B[0])");
    check_eq(g_c_wake_pos, 10,
             "C woke at log_pos 10 (after A and B each ran 5 times)");

    /* No two consecutive identical entries in positions 0-9 (A/B only) */
    log_write(NONE, "\n=== strict alternation in positions 0-9 ===\n");
    int alternates = 1;
    for (int i = 1; i < 10; i++) {
        if (g_exec_log[i] == g_exec_log[i-1]) { alternates = 0; break; }
    }
    check(alternates, "no consecutive identical task in log[0..9]");

    /* C never appears in the sleeping window (positions 0-9) */
    int c_early = 0;
    for (int i = 0; i < 10; i++)
        if (g_exec_log[i] == 2) { c_early = 1; break; }
    check(!c_early, "C does not appear before log[10] (sleep respected)");

    log_write(NONE, "\n%d PASS  %d FAIL\n", g_pass, g_fail);
    log_close();
    return g_fail;
}
