/* **************************************************************************
 *               RISC-V Emulator - Preemptive RTOS
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
 * Timer-interrupt-driven preemptive scheduler for bare-metal RISC-V.
 * Uses the CLINT machine timer (mtime/mtimecmp) to fire a periodic interrupt.
 * The machine-mode trap handler (prtos_trap.S) saves ALL registers on the
 * interrupted task's stack, then calls the C scheduler which picks the next
 * READY task and returns its stack pointer.  mret restores that context.
 *
 * API is intentionally identical to the cooperative RTOS (rtos.h) so that
 * test programs can be adapted with only a header change.
 */
#ifndef PRTOS_H
#define PRTOS_H

#include <stdint.h>

#define PRTOS_MAX_TASKS   8
#define PRTOS_STACK_WORDS 1024   /* 4 KiB per task (log_write needs ~1 KiB) */

/* Initialise scheduler and calibrate cycle timer. Call before task_create. */
void prtos_init(void);

/* Register a task. Returns task index, or -1 on error. */
int  prtos_task_create(void (*fn)(void));

/* Start scheduling. Returns when all tasks have exited. */
void prtos_run(void);

/* ---- called from inside a running task ---- */
void task_yield(void);              /* voluntarily give up the CPU             */
void task_sleep_ms(uint32_t ms);    /* sleep for ~ms milliseconds then return  */
void task_exit(void);               /* mark current task dead (also on return) */

/* Calibrated mtime-ticks per millisecond (set by prtos_init). */
extern uint32_t g_mtime_per_ms;

/* Current task index; -1 when in the idle loop.  Read-only for tests. */
extern int g_cur;

/* Called from prtos_trap.S; do not call directly. */
uint32_t *prtos_timer_isr(uint32_t *saved_sp);

/* ======================================================================
 * Extension 1: Priority-based task creation
 * ====================================================================== */

/* Create a task with an explicit scheduling priority.
 * Higher value = higher priority.  Same-priority tasks share the CPU
 * round-robin.  prtos_task_create() uses priority 0. */
int prtos_task_create_prio(void (*fn)(void), int priority);

/* ======================================================================
 * Extension 2: Mutex (binary semaphore)
 * ====================================================================== */

typedef struct {
    volatile int locked;
    int          owner;
    int          waiters[PRTOS_MAX_TASKS];
    int          n_waiters;
} prtos_mutex_t;

#define PRTOS_MUTEX_INIT  { 0, -1, {0}, 0 }

void prtos_mutex_init   (prtos_mutex_t *m);
void prtos_mutex_lock   (prtos_mutex_t *m);   /* blocks if already locked   */
void prtos_mutex_unlock (prtos_mutex_t *m);   /* wakes one blocked waiter   */

/* ======================================================================
 * Extension 3: Message queue (blocking FIFO)
 * ====================================================================== */

#define PRTOS_MQ_DEPTH  8

typedef struct {
    uint32_t buf[PRTOS_MQ_DEPTH];
    int      head, tail, count;
    int      send_waiters[PRTOS_MAX_TASKS];
    int      recv_waiters[PRTOS_MAX_TASKS];
    int      n_send_waiters, n_recv_waiters;
} prtos_mq_t;

void     prtos_mq_init (prtos_mq_t *q);
void     prtos_mq_send (prtos_mq_t *q, uint32_t msg);  /* blocks if full   */
uint32_t prtos_mq_recv (prtos_mq_t *q);                /* blocks if empty  */

/* ======================================================================
 * Extension 4: Stack-overflow detection
 * ====================================================================== */

/* -1 = no overflow; >= 0 = index of first task whose stack canary was
 * clobbered.  Checked every timer tick; NOT reset by prtos_init(). */
extern int g_stack_overflow_task;

/* ======================================================================
 * Extension 5: Deadline-based sleep
 * ====================================================================== */

/* Sleep until the CLINT mtime counter reaches abs_mtime.
 * Returns immediately if abs_mtime is already in the past. */
void task_sleep_until(uint64_t abs_mtime);

/* Read the raw 64-bit CLINT mtime counter. */
uint64_t prtos_read_mtime(void);

#endif /* PRTOS_H */
