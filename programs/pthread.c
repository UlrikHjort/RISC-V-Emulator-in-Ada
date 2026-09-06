/* **************************************************************************
 *RISC-V Emulator - minimal pthread-like API for bare-metal RISC-V multi-hart
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

/* pthread.c -- minimal pthread-like API for bare-metal RISC-V multi-hart
 *
 * Supports up to MAX_THREADS concurrent threads (one per hart).
 * Hart 0 is always the "main" thread; harts 1..N are worker harts.
 *
 * Secondary harts spin on _pthread_launch[] (defined in crt0-pthread.S).
 * pthread_create fills a launch entry and waits for the hart to pick it up.
 *
 * This file is intentionally free of floating-point operations.
 */

#include "pthread.h"
#include <stdint.h>
#include <stddef.h>

/* -----------------------------------------------------------------------
 * Thread states
 * ----------------------------------------------------------------------- */
#define TSTATE_IDLE    0
#define TSTATE_RUNNING 1
#define TSTATE_DONE    2

/* -----------------------------------------------------------------------
 * Thread control block
 * ----------------------------------------------------------------------- */
typedef struct {
    volatile uint32_t  state;    /* TSTATE_* */
    void             *(*fn)(void *);
    void              *arg;
    void              *retval;
    uint32_t           hart_id;
} _pthread_tcb_t;

/* -----------------------------------------------------------------------
 * Per-thread stacks (hart 0 uses the linker-script stack)
 * stacks[0] is unused (hart 0 uses _stack_top from linker script)
 * stacks[1..MAX_THREADS-1] belong to worker threads
 * ----------------------------------------------------------------------- */
static uint8_t _pthread_stacks[MAX_THREADS][PTHREAD_STACK_SIZE]
    __attribute__((aligned(16)));

/* -----------------------------------------------------------------------
 * Thread control block table
 * Index 0 is reserved for the main thread (always running on hart 0).
 * ----------------------------------------------------------------------- */
static _pthread_tcb_t _pthread_tcbs[MAX_THREADS];

/* -----------------------------------------------------------------------
 * Launch table shared with crt0-pthread.S
 * Layout per entry (4 words x 4 bytes = 16 bytes):
 *   word 0: fn   -- function pointer (NULL = idle)
 *   word 1: arg  -- argument pointer
 *   word 2: sp   -- stack pointer
 *   word 3: tcb  -- pointer to _pthread_tcb_t
 * ----------------------------------------------------------------------- */
typedef struct {
    volatile uint32_t fn;
    volatile uint32_t arg;
    volatile uint32_t sp;
    volatile uint32_t tcb;
} _launch_entry_t;

extern _launch_entry_t _pthread_launch[MAX_HARTS];  /* defined in crt0-pthread.S .bss */

/* -----------------------------------------------------------------------
 * _pthread_entry_wrapper
 * Called by the secondary hart assembly stub:
 *   a0 = fn, a1 = arg, a2 = tcb_ptr
 * ----------------------------------------------------------------------- */
void _pthread_entry_wrapper(void *(*fn)(void *), void *arg, void *tcb_ptr)
{
    _pthread_tcb_t *tcb = (_pthread_tcb_t *)tcb_ptr;

    /* Run the user function */
    void *result = fn(arg);

    /* Store result and mark done */
    tcb->retval = result;
    /* Memory barrier before state update */
    __asm__ volatile ("fence" ::: "memory");
    tcb->state = TSTATE_DONE;
    __asm__ volatile ("fence" ::: "memory");
}

/* -----------------------------------------------------------------------
 * pthread_create
 *
 * Finds a free secondary hart, fills the launch table, and returns.
 * Currently only supports one worker thread at a time per hart.
 * ----------------------------------------------------------------------- */
int pthread_create(pthread_t *thread, void *attr,
                   void *(*fn)(void *), void *arg)
{
    (void)attr;

    /* Find a free TCB slot (slot 0 = main thread, skip it) */
    int slot = -1;
    for (int i = 1; i < MAX_THREADS; i++) {
        if (_pthread_tcbs[i].state == TSTATE_IDLE) {
            slot = i;
            break;
        }
    }
    if (slot < 0)
        return -1;  /* EAGAIN -- no free slots */

    /* Hart IDs: worker harts start at 1 */
    uint32_t hart_id = (uint32_t)slot;  /* hart 1 -> slot 1, etc. */

    /* Fill the TCB */
    _pthread_tcbs[slot].fn      = fn;
    _pthread_tcbs[slot].arg     = arg;
    _pthread_tcbs[slot].retval  = NULL;
    _pthread_tcbs[slot].hart_id = hart_id;
    _pthread_tcbs[slot].state   = TSTATE_RUNNING;

    /* Stack pointer = top of this thread's stack (descending, 16-byte aligned) */
    uint32_t sp = (uint32_t)(_pthread_stacks[slot] + PTHREAD_STACK_SIZE);
    sp &= ~(uint32_t)15;  /* 16-byte align */

    /* Fill the launch entry -- write fn LAST so the spinning hart sees a
     * consistent entry when fn becomes non-NULL.                         */
    _pthread_launch[hart_id].tcb = (uint32_t)&_pthread_tcbs[slot];
    _pthread_launch[hart_id].sp  = sp;
    _pthread_launch[hart_id].arg = (uint32_t)arg;
    __asm__ volatile ("fence" ::: "memory");
    _pthread_launch[hart_id].fn  = (uint32_t)fn;
    __asm__ volatile ("fence" ::: "memory");

    if (thread)
        *thread = (pthread_t)slot;

    return 0;
}

/* -----------------------------------------------------------------------
 * pthread_join
 *
 * Spin until the target thread reaches TSTATE_DONE.
 * Using WFI wastes less power than a tight spin, but a plain spin also
 * works because the emulator interleaves harts each cycle.
 * ----------------------------------------------------------------------- */
int pthread_join(pthread_t thread, void **retval)
{
    if (thread >= MAX_THREADS)
        return -1;

    _pthread_tcb_t *tcb = &_pthread_tcbs[thread];

    while (tcb->state != TSTATE_DONE) {
        __asm__ volatile ("" ::: "memory");  /* compiler barrier; emulator interleaves */
    }

    __asm__ volatile ("fence" ::: "memory");

    if (retval)
        *retval = tcb->retval;

    /* Reset TCB so the slot can be reused */
    tcb->state = TSTATE_IDLE;

    return 0;
}

/* -----------------------------------------------------------------------
 * Mutex operations (LR/SC spinlock)
 * ----------------------------------------------------------------------- */
int pthread_mutex_init(pthread_mutex_t *m, void *attr)
{
    (void)attr;
    m->lock = 0;
    return 0;
}

int pthread_mutex_lock(pthread_mutex_t *m)
{
    uint32_t tmp;
    do {
        __asm__ volatile (
            "1: lr.w  %0, (%1)    \n"
            "   bnez  %0, 1b      \n"  /* spin if already locked */
            "   li    %0, 1       \n"
            "   sc.w  %0, %0, (%1)\n"
            : "=&r"(tmp)
            : "r"(&m->lock)
            : "memory"
        );
    } while (tmp != 0);  /* retry if SC failed */
    return 0;
}

int pthread_mutex_trylock(pthread_mutex_t *m)
{
    uint32_t old, sc_fail;
    __asm__ volatile (
        "lr.w  %0, (%2)    \n"
        "bnez  %0, 1f      \n"  /* already locked -> fail */
        "li    %0, 1       \n"
        "sc.w  %1, %0, (%2)\n"
        "bnez  %1, 1f      \n"  /* SC failed -> fail */
        "li    %0, 0       \n"  /* success: return 0 */
        "j     2f          \n"
        "1: li %0, 1       \n"  /* failure: return non-zero (EBUSY) */
        "2:                \n"
        : "=&r"(old), "=&r"(sc_fail)
        : "r"(&m->lock)
        : "memory"
    );
    return (int)old;
}

int pthread_mutex_unlock(pthread_mutex_t *m)
{
    __asm__ volatile ("fence" ::: "memory");
    m->lock = 0;
    return 0;
}

int pthread_mutex_destroy(pthread_mutex_t *m)
{
    m->lock = 0;
    return 0;
}
