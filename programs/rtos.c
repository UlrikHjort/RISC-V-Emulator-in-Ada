/* **************************************************************************
 *  RISC-V Emulator - Cooperative RISC-V RTOS -- scheduler implementation
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

/* Cooperative RISC-V RTOS -- scheduler implementation
 * By Ulrik Hørlyk Hjort 2026
 *
 * Context switch saves: ra + s0-s11 (13 regs, 52 bytes) per RISC-V ABI.
 * Each task gets a 4 KiB stack (RTOS_STACK_WORDS = 1024 x 4).
 */
#include "rtos.h"

/* ------------------------------------------------------------------ */
/* Internal types                                                       */
/* ------------------------------------------------------------------ */

typedef enum { TASK_DEAD = 0, TASK_READY, TASK_SLEEPING } task_state_t;

typedef struct {
    uint32_t       *sp;           /* saved stack pointer                    */
    task_state_t    state;
    uint32_t        wake_cycle;   /* rdcycle value when task should wake    */
    void          (*fn)(void);
    uint32_t        stack[RTOS_STACK_WORDS];
} tcb_t;

static tcb_t    g_tasks[RTOS_MAX_TASKS];
static int      g_n_tasks   = 0;
static int      g_cur       = -1;   /* running task index, -1 = scheduler   */
static int      g_last      = -1;   /* last-run index for round-robin       */
static uint32_t *g_sched_sp;        /* scheduler's saved stack pointer      */

uint32_t g_cycles_per_ms = 1000000; /* default; calibrated in rtos_init    */

/* ------------------------------------------------------------------ */
/* Low-level helpers                                                    */
/* ------------------------------------------------------------------ */

static inline uint32_t rdcycle32(void)
{
    uint32_t c;
    __asm__ volatile("rdcycle %0" : "=r"(c));
    return c;
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
/* Context switch (naked -- no compiler prologue/epilogue)               */
/*                                                                      */
/* void ctx_switch(uint32_t **save_sp, uint32_t *load_sp)              */
/*   a0 = save_sp  (address of the pointer variable to write)          */
/*   a1 = load_sp  (stack pointer value to load)                       */
/*                                                                      */
/* Saves ra+s0-s11 (52 bytes) on current stack, stores sp into *a0,   */
/* then loads sp from a1 and restores the saved-register frame.        */
/* ------------------------------------------------------------------ */
__attribute__((naked, noinline))
static void ctx_switch(uint32_t **save_sp, uint32_t *load_sp)
{
    (void)save_sp; (void)load_sp;           /* suppress unused-param warnings */
    __asm__ volatile(
        /* --- save current context --- */
        "addi sp, sp, -52   \n\t"
        "sw   ra,   0(sp)   \n\t"
        "sw   s0,   4(sp)   \n\t"
        "sw   s1,   8(sp)   \n\t"
        "sw   s2,  12(sp)   \n\t"
        "sw   s3,  16(sp)   \n\t"
        "sw   s4,  20(sp)   \n\t"
        "sw   s5,  24(sp)   \n\t"
        "sw   s6,  28(sp)   \n\t"
        "sw   s7,  32(sp)   \n\t"
        "sw   s8,  36(sp)   \n\t"
        "sw   s9,  40(sp)   \n\t"
        "sw   s10, 44(sp)   \n\t"
        "sw   s11, 48(sp)   \n\t"
        /* --- switch stacks --- */
        "sw   sp,  0(a0)    \n\t"   /* *save_sp = sp  */
        "mv   sp,  a1       \n\t"   /*  sp = load_sp  */
        /* --- restore new context --- */
        "lw   ra,   0(sp)   \n\t"
        "lw   s0,   4(sp)   \n\t"
        "lw   s1,   8(sp)   \n\t"
        "lw   s2,  12(sp)   \n\t"
        "lw   s3,  16(sp)   \n\t"
        "lw   s4,  20(sp)   \n\t"
        "lw   s5,  24(sp)   \n\t"
        "lw   s6,  28(sp)   \n\t"
        "lw   s7,  32(sp)   \n\t"
        "lw   s8,  36(sp)   \n\t"
        "lw   s9,  40(sp)   \n\t"
        "lw   s10, 44(sp)   \n\t"
        "lw   s11, 48(sp)   \n\t"
        "addi sp,  sp, 52   \n\t"
        "ret                \n\t"
    );
}

/* ------------------------------------------------------------------ */
/* Task trampoline                                                      */
/* Every new task starts here (ctx_switch ret -> task_trampoline).     */
/* Calls the task function then calls task_exit() on return.           */
/* ------------------------------------------------------------------ */
static void task_trampoline(void)
{
    g_tasks[g_cur].fn();
    task_exit();
}

/* ------------------------------------------------------------------ */
/* Public API                                                           */
/* ------------------------------------------------------------------ */

void rtos_init(void)
{
    g_n_tasks = 0;
    g_cur     = -1;
    g_last    = -1;

    /* Calibrate: count rdcycle ticks per real millisecond over ~10 ms */
    uint32_t t0 = host_time_ms();
    uint32_t c0 = rdcycle32();
    uint32_t t1;
    do { t1 = host_time_ms(); } while (t1 - t0 < 10);
    uint32_t c1   = rdcycle32();
    uint32_t dt   = t1 - t0;
    if (dt > 0 && c1 != c0)
        g_cycles_per_ms = (c1 - c0) / dt;
}

int rtos_task_create(void (*fn)(void))
{
    if (g_n_tasks >= RTOS_MAX_TASKS) return -1;

    tcb_t *t   = &g_tasks[g_n_tasks];
    t->fn       = fn;
    t->state    = TASK_READY;
    t->wake_cycle = 0;

    /* Build initial ctx_switch frame at the top of the task stack.
     * Layout (sp[0]..sp[12]):  ra, s0, s1, ..., s11  (all zero except ra).
     * After ctx_switch pops 13 words (+52 bytes), sp == &stack[RTOS_STACK_WORDS]
     * which is the initial empty-stack position for this task. */
    uint32_t *sp = &t->stack[RTOS_STACK_WORDS - 13];
    for (int i = 0; i < 13; i++) sp[i] = 0;
    sp[0] = (uint32_t)(uintptr_t)task_trampoline;  /* ra */
    t->sp  = sp;

    return g_n_tasks++;
}

void rtos_run(void)
{
    for (;;) {
        /* Wake sleeping tasks whose timer has elapsed (unsigned-safe wrap) */
        uint32_t now = rdcycle32();
        for (int i = 0; i < g_n_tasks; i++) {
            if (g_tasks[i].state == TASK_SLEEPING &&
                    (int32_t)(now - g_tasks[i].wake_cycle) >= 0)
                g_tasks[i].state = TASK_READY;
        }

        /* Round-robin: find next READY task after g_last */
        int next = -1;
        for (int i = 0; i < g_n_tasks; i++) {
            int idx = (g_last + 1 + i) % g_n_tasks;
            if (g_tasks[idx].state == TASK_READY) { next = idx; break; }
        }

        if (next < 0) {
            /* No READY task. Return if all dead, otherwise spin for sleepers. */
            int alive = 0;
            for (int i = 0; i < g_n_tasks; i++)
                if (g_tasks[i].state != TASK_DEAD) alive = 1;
            if (!alive) return;
            continue;   /* spin: a sleeping task will eventually become READY */
        }

        g_last = next;
        g_cur  = next;
        ctx_switch(&g_sched_sp, g_tasks[next].sp);
        /* Resumes here after task_yield / task_sleep_ms / task_exit */
        g_cur = -1;
    }
}

void task_yield(void)
{
    ctx_switch(&g_tasks[g_cur].sp, g_sched_sp);
}

void task_sleep_ms(uint32_t ms)
{
    g_tasks[g_cur].wake_cycle = rdcycle32() + ms * g_cycles_per_ms;
    g_tasks[g_cur].state      = TASK_SLEEPING;
    ctx_switch(&g_tasks[g_cur].sp, g_sched_sp);
}

void task_exit(void)
{
    g_tasks[g_cur].state = TASK_DEAD;
    ctx_switch(&g_tasks[g_cur].sp, g_sched_sp);
    while (1); /* unreachable */
}
