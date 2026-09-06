/* **************************************************************************
 *               RISC-V Emulator - Preemptive RTOS Extension Test
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
 * Tests all five RTOS extensions in separate phases:
 *
 *  Phase 1 -- Mutex: two tasks race on a shared counter; the mutex must
 *             ensure the final count is exactly 40 with no lost updates.
 *
 *  Phase 2 -- Message queue: producer sends 8 messages; consumer receives
 *             them and verifies they arrive in order.
 *
 *  Phase 3 -- Priority scheduling: a high-priority task (prio 5) and a
 *             low-priority task (prio 1) are both READY.  The scheduler
 *             must always run the high-priority task first.  Expected
 *             exec_log = [H,H,H,H,H, L,L,L,L,L].
 *
 *  Phase 4 -- Stack canary: after all phases g_stack_overflow_task == -1
 *             (no task has clobbered its stack guard words).
 *
 *  Phase 5 -- task_sleep_until: a periodic task sleeps to absolute mtime
 *             deadlines and verifies it woke at or after each target.
 */
#include "prtos.h"
#include "log.h"
#include <stddef.h>

/* ------------------------------------------------------------------ */
/* Test harness                                                         */
/* ------------------------------------------------------------------ */

static int g_pass = 0, g_fail = 0;

static void chk(int cond, const char *label)
{
    if (cond) {
        log_write(NONE, "  PASS  %s\n", label);
        g_pass++;
    } else {
        log_write(NONE, "  FAIL  %s\n", label);
        g_fail++;
    }
}

static void chk_eq(int got, int exp, const char *label)
{
    if (got == exp) {
        log_write(NONE, "  PASS  %s\n", label);
        g_pass++;
    } else {
        log_write(NONE, "  FAIL  %s  got=%d  exp=%d\n", label, got, exp);
        g_fail++;
    }
}

/* ================================================================== */
/* Phase 1: Mutex                                                       */
/* ================================================================== */

static prtos_mutex_t  g_mtx;
static volatile int   g_shared_ctr = 0;

/* Each task locks the mutex, loads the counter into a temp, then stores
 * temp+1 back.  Without the mutex the timer could fire between the load
 * and store, causing another task to also load the old value -- a classic
 * read-modify-write race.  With the mutex the final value must be 40. */
static void mutex_task_a(void)
{
    for (int i = 0; i < 20; i++) {
        prtos_mutex_lock(&g_mtx);
        volatile int tmp = g_shared_ctr;
        task_yield();           /* provoke interrupt inside critical section */
        g_shared_ctr = tmp + 1;
        prtos_mutex_unlock(&g_mtx);
    }
}

static void mutex_task_b(void)
{
    for (int i = 0; i < 20; i++) {
        prtos_mutex_lock(&g_mtx);
        volatile int tmp = g_shared_ctr;
        task_yield();
        g_shared_ctr = tmp + 1;
        prtos_mutex_unlock(&g_mtx);
    }
}

/* ================================================================== */
/* Phase 2: Message queue                                               */
/* ================================================================== */

#define MQ_COUNT  8

static prtos_mq_t  g_mq;
static uint32_t    g_recv_buf[MQ_COUNT];
static int         g_recv_count = 0;

static void mq_producer(void)
{
    for (uint32_t i = 0; i < MQ_COUNT; i++) {
        prtos_mq_send(&g_mq, 100 + i);
        task_yield();
    }
}

static void mq_consumer(void)
{
    for (int i = 0; i < MQ_COUNT; i++) {
        g_recv_buf[i] = prtos_mq_recv(&g_mq);
        g_recv_count++;
    }
}

/* ================================================================== */
/* Phase 3: Priority scheduling                                         */
/* ================================================================== */

#define PLOG_SIZE  12

static int g_plog[PLOG_SIZE];
static int g_plog_pos = 0;

static void hiprio_task(void)   /* priority 5 */
{
    for (int i = 0; i < 5; i++) {
        if (g_plog_pos < PLOG_SIZE)
            g_plog[g_plog_pos++] = 1;   /* 1 = high-priority task */
        task_yield();
    }
}

static void loprio_task(void)   /* priority 1 */
{
    for (int i = 0; i < 5; i++) {
        if (g_plog_pos < PLOG_SIZE)
            g_plog[g_plog_pos++] = 0;   /* 0 = low-priority task */
        task_yield();
    }
}

/* ================================================================== */
/* Phase 5: task_sleep_until (deadline sleep)                          */
/* ================================================================== */

#define PERIOD_COUNT  3

static uint64_t g_target[PERIOD_COUNT];
static uint64_t g_wakeup[PERIOD_COUNT];

static void periodic_task(void)
{
    /* Sleep to three successive absolute deadlines, each 5 ms apart. */
    uint64_t t = prtos_read_mtime();
    for (int i = 0; i < PERIOD_COUNT; i++) {
        t += (uint64_t)g_mtime_per_ms * 5;
        g_target[i] = t;
        task_sleep_until(t);
        g_wakeup[i] = prtos_read_mtime();
    }
}

/* ================================================================== */
/* main                                                                 */
/* ================================================================== */

int main(void)
{
    log_init("prtos2-test.log");
    log_write(NONE, "Preemptive RTOS Extension Test\n\n");

    /* ----------------------------------------------------------------
     * Phase 1: Mutex
     * -------------------------------------------------------------- */
    log_write(NONE, "=== Phase 1: Mutex ===\n");

    prtos_mutex_init(&g_mtx);
    g_shared_ctr = 0;

    prtos_init();
    prtos_task_create(mutex_task_a);
    prtos_task_create(mutex_task_b);
    prtos_run();

    chk_eq(g_shared_ctr, 40,
           "mutex: shared counter == 40 (no lost updates)");

    /* ----------------------------------------------------------------
     * Phase 2: Message queue
     * -------------------------------------------------------------- */
    log_write(NONE, "\n=== Phase 2: Message queue ===\n");

    prtos_mq_init(&g_mq);
    g_recv_count = 0;

    prtos_init();
    prtos_task_create(mq_producer);
    prtos_task_create(mq_consumer);
    prtos_run();

    chk_eq(g_recv_count, MQ_COUNT, "mq: received all 8 messages");
    chk_eq((int)g_recv_buf[0], 100, "mq: msg[0] == 100");
    chk_eq((int)g_recv_buf[1], 101, "mq: msg[1] == 101");
    chk_eq((int)g_recv_buf[2], 102, "mq: msg[2] == 102");
    chk_eq((int)g_recv_buf[3], 103, "mq: msg[3] == 103");
    chk_eq((int)g_recv_buf[4], 104, "mq: msg[4] == 104");
    chk_eq((int)g_recv_buf[5], 105, "mq: msg[5] == 105");
    chk_eq((int)g_recv_buf[6], 106, "mq: msg[6] == 106");
    chk_eq((int)g_recv_buf[7], 107, "mq: msg[7] == 107");

    /* ----------------------------------------------------------------
     * Phase 3: Priority scheduling
     * -------------------------------------------------------------- */
    log_write(NONE, "\n=== Phase 3: Priority scheduling ===\n");

    g_plog_pos = 0;

    prtos_init();
    prtos_task_create_prio(loprio_task, 1);   /* created first, lower prio */
    prtos_task_create_prio(hiprio_task, 5);   /* higher prio must run first */
    prtos_run();

    /* The high-priority task should monopolise the CPU until it exits,
     * then the low-priority task runs. */
    chk_eq(g_plog_pos, 10,  "prio: exactly 10 log entries");
    chk_eq(g_plog[0], 1,    "prio: log[0] == H (hiprio ran first)");
    chk_eq(g_plog[1], 1,    "prio: log[1] == H");
    chk_eq(g_plog[2], 1,    "prio: log[2] == H");
    chk_eq(g_plog[3], 1,    "prio: log[3] == H");
    chk_eq(g_plog[4], 1,    "prio: log[4] == H (hiprio done)");
    chk_eq(g_plog[5], 0,    "prio: log[5] == L (loprio runs after hiprio exits)");
    chk_eq(g_plog[6], 0,    "prio: log[6] == L");
    chk_eq(g_plog[7], 0,    "prio: log[7] == L");
    chk_eq(g_plog[8], 0,    "prio: log[8] == L");
    chk_eq(g_plog[9], 0,    "prio: log[9] == L");

    /* ----------------------------------------------------------------
     * Phase 4: Stack canary (checked across all phases)
     * -------------------------------------------------------------- */
    log_write(NONE, "\n=== Phase 4: Stack canary ===\n");

    chk_eq(g_stack_overflow_task, -1,
           "canary: no stack overflow in any task");

    /* ----------------------------------------------------------------
     * Phase 5: task_sleep_until (deadline sleep)
     * -------------------------------------------------------------- */
    log_write(NONE, "\n=== Phase 5: task_sleep_until ===\n");

    prtos_init();
    prtos_task_create(periodic_task);
    prtos_run();

    chk((int)(g_wakeup[0] >= g_target[0]),
        "sleep_until: wakeup[0] >= target[0]");
    chk((int)(g_wakeup[1] >= g_target[1]),
        "sleep_until: wakeup[1] >= target[1]");
    chk((int)(g_wakeup[2] >= g_target[2]),
        "sleep_until: wakeup[2] >= target[2]");

    /* ----------------------------------------------------------------
     * Summary
     * -------------------------------------------------------------- */
    log_write(NONE, "\n%d PASS  %d FAIL\n", g_pass, g_fail);
    log_close();
    return g_fail ? 1 : 0;
}
