/* **************************************************************************
 *               RISC-V Emulator - Preemptive RTOS Scheduler
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
 * Timer-interrupt-driven preemptive scheduler.
 *
 * How it works:
 *   1. prtos_run() installs trap_entry as mtvec, enables MTIE + MIE, arms the
 *      CLINT timer, then enters an idle WFI loop.
 *   2. Every PRTOS_TICK_CYCLES mtime ticks the hardware fires a machine timer
 *      interrupt.  trap_entry (prtos_trap.S) saves all 30 integer registers
 *      plus mepc/mstatus as a 128-byte frame on the interrupted stack, then
 *      calls prtos_timer_isr(saved_sp).
 *   3. prtos_timer_isr saves the frame pointer, reprograms mtimecmp, wakes
 *      sleeping tasks, and does round-robin to pick the next READY task.
 *      It returns the new task's saved_sp; trap_entry restores that frame and
 *      executes mret to jump into the new task with interrupts re-enabled.
 *   4. task_yield() / task_sleep_ms() / task_exit() all force an immediate
 *      preemption by writing mtimecmp = mtime (already elapsed), then execute
 *      WFI.  Because WFI is treated as NOP in this emulator the interrupt is
 *      taken on the very next cycle check.
 *
 * CLINT memory map (qemu-virt, base 0x02000000):
 *   0x02000000  msip       (4 bytes)
 *   0x02004000  mtimecmp   (8 bytes, lo word first)
 *   0x0200BFF8  mtime      (8 bytes, lo word first)
 */

#include "prtos.h"
#include <stddef.h>
#include <stdint.h>

/* ------------------------------------------------------------------ */
/* CLINT register addresses                                             */
/* ------------------------------------------------------------------ */
#define CLINT_BASE          0x02000000UL
#define CLINT_MTIMECMP_LO   (*(volatile uint32_t *)(CLINT_BASE + 0x4000UL))
#define CLINT_MTIMECMP_HI   (*(volatile uint32_t *)(CLINT_BASE + 0x4004UL))
#define CLINT_MTIME_LO      (*(volatile uint32_t *)(CLINT_BASE + 0xBFF8UL))
#define CLINT_MTIME_HI      (*(volatile uint32_t *)(CLINT_BASE + 0xBFFCUL))

/*
 * Timer quantum: preempt every PRTOS_TICK_CYCLES mtime ticks.
 * mtime increments once per emulated instruction, so this equals the
 * maximum number of instructions a task may run before being preempted.
 */
#define PRTOS_TICK_CYCLES   2000UL

/*
 * Initial mstatus for a brand-new task started via mret:
 *   MPP  = 3 (bits 12:11, machine mode -- stay in M-mode after mret)
 *   MPIE = 1 (bit  7    -- mret copies MPIE->MIE, enabling interrupts)
 *   MIE  = 0 (bit  3    -- cleared; will be enabled by mret via MPIE)
 */
#define TASK_MSTATUS_INIT   0x1880UL

/*
 * Frame indices into the uint32_t array at saved_sp.
 * Must match prtos_trap.S layout exactly.
 *   [0]  x1  ra
 *   [1]  x3  gp   <- must be pre-populated with the real GP value
 *   ...
 *   [30] mepc
 *   [31] mstatus
 */
#define FRAME_GP      1
#define FRAME_MEPC   30
#define FRAME_MSTATUS 31

/* ------------------------------------------------------------------ */
/* Internal types                                                       */
/* ------------------------------------------------------------------ */

typedef enum {
    TASK_DEAD = 0,
    TASK_READY,
    TASK_SLEEPING,
    TASK_BLOCKED    /* waiting on mutex or message queue */
} task_state_t;

typedef struct {
    uint32_t      *sp;            /* saved stack pointer -- points to frame   */
    task_state_t   state;
    uint64_t       wake_mtime;    /* mtime value when sleeping task wakes     */
    void          (*fn)(void);
    int            priority;      /* scheduling priority (higher = first)     */
    uint32_t       stack[PRTOS_STACK_WORDS];
} tcb_t;

/* ------------------------------------------------------------------ */
/* Globals                                                              */
/* ------------------------------------------------------------------ */

static tcb_t        g_tasks[PRTOS_MAX_TASKS];
static int          g_n_tasks  = 0;
int                 g_cur      = -1;    /* -1 = idle, >=0 = task index         */
static uint32_t    *g_idle_sp  = NULL;  /* idle context frame (prtos_run stk) */
static volatile int g_all_done = 0;

uint32_t g_mtime_per_ms        = 1000000; /* calibrated by prtos_init          */
int      g_stack_overflow_task = -1;      /* -1 = none detected               */

#define STACK_CANARY  0xDEADBEEFUL

/* ------------------------------------------------------------------ */
/* Low-level helpers                                                    */
/* ------------------------------------------------------------------ */

static uint64_t clint_read_mtime(void)
{
    /* Guard against a 32->64-bit carry between the two reads. */
    uint32_t lo, hi;
    do {
        hi = CLINT_MTIME_HI;
        lo = CLINT_MTIME_LO;
    } while (CLINT_MTIME_HI != hi);
    return ((uint64_t)hi << 32) | (uint64_t)lo;
}

static void clint_write_mtimecmp(uint64_t val)
{
    /*
     * Write the high word to 0xFFFFFFFF first so that the compare never
     * spuriously fires during the two-word update, then write lo, then hi.
     */
    CLINT_MTIMECMP_HI = 0xFFFFFFFFUL;
    CLINT_MTIMECMP_LO = (uint32_t)(val & 0xFFFFFFFFUL);
    CLINT_MTIMECMP_HI = (uint32_t)(val >> 32);
}

static inline uint32_t rdcycle32(void)
{
    uint32_t c;
    __asm__ volatile("rdcycle %0" : "=r"(c));
    return c;
}

/* Disable/enable machine-mode interrupts (MIE bit in mstatus).
 * Used to make mutex/mq operations atomic on this single-hart system. */
static inline void irq_disable(void)
{
    __asm__ volatile("csrci mstatus, 0x8" ::: "memory");
}

static inline void irq_enable(void)
{
    __asm__ volatile("csrsi mstatus, 0x8" ::: "memory");
}

static uint32_t host_time_ms(void)
{
    uint32_t r;
    __asm__ volatile(
        "li  a7, 0x504\n\t"
        "ecall\n\t"
        "mv  %0, a0"
        : "=r"(r) :: "a7", "a0", "memory"
    );
    return r;
}

/* ------------------------------------------------------------------ */
/* Task trampoline                                                      */
/* Every task starts here after the first mret into its initial frame. */
/* ------------------------------------------------------------------ */

static void task_trampoline(void)
{
    g_tasks[g_cur].fn();
    task_exit();
}

/* ------------------------------------------------------------------ */
/* Timer ISR -- called from trap_entry (prtos_trap.S)                   */
/*                                                                      */
/* saved_sp  : the stack pointer AFTER pushing the 128-byte frame, i.e.*/
/*             &frame[0] for the interrupted context.                  */
/* returns   : saved_sp of the context to restore (next task or idle). */
/* ------------------------------------------------------------------ */

uint32_t *prtos_timer_isr(uint32_t *saved_sp)
{
    /* Save the interrupted context's frame pointer. */
    if (g_cur >= 0)
        g_tasks[g_cur].sp = saved_sp;
    else
        g_idle_sp = saved_sp;

    /* Advance the timer to the next tick. */
    uint64_t now = clint_read_mtime();
    clint_write_mtimecmp(now + PRTOS_TICK_CYCLES);

    /* Check stack canaries (extension 4). */
    if (g_stack_overflow_task < 0) {
        for (int i = 0; i < g_n_tasks; i++) {
            if (g_tasks[i].stack[0] != STACK_CANARY ||
                    g_tasks[i].stack[1] != STACK_CANARY) {
                g_stack_overflow_task = i;
                break;
            }
        }
    }

    /* Wake any sleeping tasks whose deadline has elapsed. */
    for (int i = 0; i < g_n_tasks; i++) {
        if (g_tasks[i].state == TASK_SLEEPING &&
                now >= g_tasks[i].wake_mtime)
            g_tasks[i].state = TASK_READY;
    }

    /* Are all tasks finished? (BLOCKED/SLEEPING count as alive) */
    int alive = 0;
    for (int i = 0; i < g_n_tasks; i++)
        if (g_tasks[i].state != TASK_DEAD) alive = 1;

    if (!alive) {
        g_all_done = 1;
        g_cur = -1;
        return g_idle_sp;
    }

    /* Priority-aware scheduler (extension 1):
     * Find the highest priority among READY tasks, then round-robin
     * within that priority level starting after the current task. */
    int start = (g_cur >= 0) ? g_cur : (g_n_tasks - 1);

    int max_prio = -1;
    for (int i = 0; i < g_n_tasks; i++)
        if (g_tasks[i].state == TASK_READY && g_tasks[i].priority > max_prio)
            max_prio = g_tasks[i].priority;

    int next = -1;
    if (max_prio >= 0) {
        for (int i = 0; i < g_n_tasks; i++) {
            int idx = (start + 1 + i) % g_n_tasks;
            if (g_tasks[idx].state == TASK_READY &&
                    g_tasks[idx].priority == max_prio) {
                next = idx;
                break;
            }
        }
    }

    if (next < 0) {
        /* All alive tasks are sleeping or blocked; return to idle. */
        g_cur = -1;
        return g_idle_sp;
    }

    g_cur = next;
    return g_tasks[next].sp;
}

/* ------------------------------------------------------------------ */
/* Public API                                                           */
/* ------------------------------------------------------------------ */

void prtos_init(void)
{
    g_n_tasks  = 0;
    g_cur      = -1;
    g_all_done = 0;
    g_idle_sp  = NULL;
    /* g_stack_overflow_task is intentionally NOT reset here so that
     * overflows detected across multiple prtos_run() phases are preserved. */

    /* Calibrate: measure rdcycle ticks per real millisecond over ~10 ms.
     * rdcycle and mtime tick at the same rate (once per instruction). */
    uint32_t t0 = host_time_ms();
    uint32_t c0 = rdcycle32();
    uint32_t t1;
    do { t1 = host_time_ms(); } while (t1 - t0 < 10);
    uint32_t c1 = rdcycle32();
    uint32_t dt = t1 - t0;
    if (dt > 0 && c1 != c0)
        g_mtime_per_ms = (c1 - c0) / dt;
}

int prtos_task_create_prio(void (*fn)(void), int priority)
{
    if (g_n_tasks >= PRTOS_MAX_TASKS) return -1;

    tcb_t *t   = &g_tasks[g_n_tasks];
    t->fn       = fn;
    t->state    = TASK_READY;
    t->wake_mtime = 0;
    t->priority = priority;

    /*
     * Write stack canaries at the bottom (extension 4).
     * If the stack pointer ever reaches stack[1], the canary is clobbered
     * and the ISR will set g_stack_overflow_task.
     */
    t->stack[0] = STACK_CANARY;
    t->stack[1] = STACK_CANARY;

    /*
     * Build a fake 128-byte trap frame at the top of the task's stack.
     * The frame (32 x uint32_t) mirrors prtos_trap.S exactly.
     * All entries are zero except:
     *   frame[FRAME_GP]      = current GP (global pointer, shared by all tasks)
     *   frame[FRAME_MEPC]    = task_trampoline  (mret target)
     *   frame[FRAME_MSTATUS] = TASK_MSTATUS_INIT (MPP=3, MPIE=1)
     */
    uint32_t *sp = &t->stack[PRTOS_STACK_WORDS - 32];
    for (int i = 0; i < 32; i++) sp[i] = 0;

    /* Preserve the global pointer so GP-relative addressing works. */
    register uint32_t cur_gp asm("gp");
    sp[FRAME_GP]      = cur_gp;

    sp[FRAME_MEPC]    = (uint32_t)(uintptr_t)task_trampoline;
    sp[FRAME_MSTATUS] = (uint32_t)TASK_MSTATUS_INIT;

    t->sp = sp;
    return g_n_tasks++;
}

int prtos_task_create(void (*fn)(void))
{
    return prtos_task_create_prio(fn, 0);
}

void prtos_run(void)
{
    /* Install trap_entry as the machine-mode direct-mode trap vector. */
    __asm__ volatile(
        "la  t0, trap_entry\n\t"
        "csrw mtvec, t0"
        ::: "t0"
    );

    /* Enable MTIE (machine timer interrupt enable) in mie. */
    __asm__ volatile(
        "li   t0, 0x80\n\t"
        "csrrs zero, mie, t0"
        ::: "t0"
    );

    /* Enable MIE (global machine interrupt enable) in mstatus. */
    __asm__ volatile(
        "li   t0, 0x8\n\t"
        "csrrs zero, mstatus, t0"
        ::: "t0"
    );

    /* Arm the CLINT timer for the first tick. */
    uint64_t now = clint_read_mtime();
    clint_write_mtimecmp(now + PRTOS_TICK_CYCLES);

    /*
     * Idle loop.  WFI is a NOP in this emulator, so this is a busy-wait.
     * The timer interrupt fires every PRTOS_TICK_CYCLES instructions and
     * the ISR context-switches to ready tasks.  We return here via mret
     * whenever there is no ready task and whenever g_all_done is set.
     */
    while (!g_all_done) {
        __asm__ volatile("wfi");
    }

    /* Disable the timer: set mtimecmp to maximum value (no interrupt). */
    clint_write_mtimecmp(0xFFFFFFFFFFFFFFFFULL);

    /* Disable machine timer interrupt. */
    __asm__ volatile(
        "li   t0, 0x80\n\t"
        "csrrc zero, mie, t0"
        ::: "t0"
    );
}

void task_yield(void)
{
    /*
     * Force an immediate preemption: set mtimecmp to a value the timer
     * has already passed so the interrupt fires on the very next cycle.
     * WFI advances PC one instruction; the interrupt is taken right after.
     * When this task is rescheduled, execution resumes after the WFI.
     */
    uint64_t now = clint_read_mtime();
    clint_write_mtimecmp(now);          /* <= mtime -> interrupt pending */
    __asm__ volatile("wfi");
}

void task_sleep_ms(uint32_t ms)
{
    uint64_t now = clint_read_mtime();
    g_tasks[g_cur].wake_mtime = now + (uint64_t)ms * (uint64_t)g_mtime_per_ms;
    g_tasks[g_cur].state      = TASK_SLEEPING;
    clint_write_mtimecmp(now);          /* trigger immediate preemption */
    __asm__ volatile("wfi");
    /* Execution resumes here after the task is woken by the ISR. */
}

void task_exit(void)
{
    g_tasks[g_cur].state = TASK_DEAD;
    uint64_t now = clint_read_mtime();
    clint_write_mtimecmp(now);          /* trigger immediate preemption */
    __asm__ volatile("wfi");
    while (1);                          /* unreachable */
}

/* ------------------------------------------------------------------ */
/* Extension 2: Mutex                                                   */
/* ------------------------------------------------------------------ */

void prtos_mutex_init(prtos_mutex_t *m)
{
    m->locked    = 0;
    m->owner     = -1;
    m->n_waiters = 0;
}

void prtos_mutex_lock(prtos_mutex_t *m)
{
    for (;;) {
        irq_disable();
        if (!m->locked) {
            m->locked = 1;
            m->owner  = g_cur;
            irq_enable();
            return;
        }
        /* Mutex is held: block this task and yield. */
        m->waiters[m->n_waiters++] = g_cur;
        g_tasks[g_cur].state = TASK_BLOCKED;
        irq_enable();
        /* Trigger an immediate preemption so the scheduler runs. */
        uint64_t now = clint_read_mtime();
        clint_write_mtimecmp(now);
        __asm__ volatile("wfi");
        /* Resumed by mutex_unlock; loop to retry. */
    }
}

void prtos_mutex_unlock(prtos_mutex_t *m)
{
    irq_disable();
    m->locked = 0;
    m->owner  = -1;
    /* Wake the first waiter, if any. */
    if (m->n_waiters > 0) {
        int w = m->waiters[0];
        for (int i = 0; i < m->n_waiters - 1; i++)
            m->waiters[i] = m->waiters[i + 1];
        m->n_waiters--;
        g_tasks[w].state = TASK_READY;
    }
    irq_enable();
}

/* ------------------------------------------------------------------ */
/* Extension 3: Message queue                                           */
/* ------------------------------------------------------------------ */

void prtos_mq_init(prtos_mq_t *q)
{
    q->head = q->tail = q->count = 0;
    q->n_send_waiters = q->n_recv_waiters = 0;
}

void prtos_mq_send(prtos_mq_t *q, uint32_t msg)
{
    for (;;) {
        irq_disable();
        if (q->count < PRTOS_MQ_DEPTH) {
            q->buf[q->tail] = msg;
            q->tail = (q->tail + 1) % PRTOS_MQ_DEPTH;
            q->count++;
            /* Wake one blocked receiver, if any. */
            if (q->n_recv_waiters > 0) {
                int w = q->recv_waiters[0];
                for (int i = 0; i < q->n_recv_waiters - 1; i++)
                    q->recv_waiters[i] = q->recv_waiters[i + 1];
                q->n_recv_waiters--;
                g_tasks[w].state = TASK_READY;
            }
            irq_enable();
            return;
        }
        /* Queue full: block this sender. */
        q->send_waiters[q->n_send_waiters++] = g_cur;
        g_tasks[g_cur].state = TASK_BLOCKED;
        irq_enable();
        uint64_t now = clint_read_mtime();
        clint_write_mtimecmp(now);
        __asm__ volatile("wfi");
    }
}

uint32_t prtos_mq_recv(prtos_mq_t *q)
{
    for (;;) {
        irq_disable();
        if (q->count > 0) {
            uint32_t msg = q->buf[q->head];
            q->head = (q->head + 1) % PRTOS_MQ_DEPTH;
            q->count--;
            /* Wake one blocked sender, if any. */
            if (q->n_send_waiters > 0) {
                int w = q->send_waiters[0];
                for (int i = 0; i < q->n_send_waiters - 1; i++)
                    q->send_waiters[i] = q->send_waiters[i + 1];
                q->n_send_waiters--;
                g_tasks[w].state = TASK_READY;
            }
            irq_enable();
            return msg;
        }
        /* Queue empty: block this receiver. */
        q->recv_waiters[q->n_recv_waiters++] = g_cur;
        g_tasks[g_cur].state = TASK_BLOCKED;
        irq_enable();
        uint64_t now = clint_read_mtime();
        clint_write_mtimecmp(now);
        __asm__ volatile("wfi");
    }
}

/* ------------------------------------------------------------------ */
/* Extension 5: Deadline-based sleep + mtime read                      */
/* ------------------------------------------------------------------ */

uint64_t prtos_read_mtime(void)
{
    return clint_read_mtime();
}

void task_sleep_until(uint64_t abs_mtime)
{
    uint64_t now = clint_read_mtime();
    if (abs_mtime <= now) return;           /* already past */
    g_tasks[g_cur].wake_mtime = abs_mtime;
    g_tasks[g_cur].state      = TASK_SLEEPING;
    clint_write_mtimecmp(now);              /* trigger immediate preemption */
    __asm__ volatile("wfi");
    /* Execution resumes here after the ISR wakes this task. */
}
