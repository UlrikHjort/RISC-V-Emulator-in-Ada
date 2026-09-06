/* **************************************************************************
 *            RISC-V Emulator - POSIX Threads Subset - Interface
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

#ifndef PTHREAD_H
#define PTHREAD_H

#include <stdint.h>

/* -----------------------------------------------------------------------
 * Configuration
 * ----------------------------------------------------------------------- */
#define MAX_HARTS        4
#define MAX_THREADS      4       /* one thread slot per hart (hart 0 = main) */
#define PTHREAD_STACK_SIZE 4096  /* per-thread stack, 16-byte aligned */

/* -----------------------------------------------------------------------
 * Thread handle -- index into internal TCB table
 * ----------------------------------------------------------------------- */
typedef uint32_t pthread_t;

/* -----------------------------------------------------------------------
 * Mutex -- LR/SC spinlock
 * ----------------------------------------------------------------------- */
typedef struct {
    volatile uint32_t lock;   /* 0 = unlocked, 1 = locked */
} pthread_mutex_t;

#define PTHREAD_MUTEX_INITIALIZER { 0 }

/* -----------------------------------------------------------------------
 * API
 * ----------------------------------------------------------------------- */
int pthread_create(pthread_t *thread, void *attr,
                   void *(*fn)(void *), void *arg);

int pthread_join(pthread_t thread, void **retval);

int pthread_mutex_init(pthread_mutex_t *m, void *attr);
int pthread_mutex_lock(pthread_mutex_t *m);
int pthread_mutex_trylock(pthread_mutex_t *m);
int pthread_mutex_unlock(pthread_mutex_t *m);
int pthread_mutex_destroy(pthread_mutex_t *m);

/* -----------------------------------------------------------------------
 * Internal -- called by crt0-pthread.S secondary hart wrapper
 * ----------------------------------------------------------------------- */
/* _pthread_entry_wrapper(fn, arg, tcb_ptr):
 *   calls fn(arg), stores return value in tcb, marks thread done.
 *   Signature matches how crt0-pthread.S loads registers:
 *     a0 = fn, a1 = arg, a2 = tcb_ptr
 */
void _pthread_entry_wrapper(void *(*fn)(void *), void *arg, void *tcb_ptr);

#endif /* PTHREAD_H */
