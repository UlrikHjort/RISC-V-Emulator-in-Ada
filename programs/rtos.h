/* **************************************************************************
 *         RISC-V Emulator - Cooperative RISC-V RTOS -- public API
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

/* Cooperative RISC-V RTOS -- public API
 * By Ulrik Hørlyk Hjort 2026
 */
#ifndef RTOS_H
#define RTOS_H

#include <stdint.h>

#define RTOS_MAX_TASKS   8
#define RTOS_STACK_WORDS 1024   /* 4 KiB per task (log_write needs ~1 KiB) */

/* Initialise scheduler and calibrate cycle timer. Call before task_create. */
void rtos_init(void);

/* Register a task. Returns task index, or -1 on error. */
int  rtos_task_create(void (*fn)(void));

/* Start scheduling. Returns when all tasks have exited. */
void rtos_run(void);

/* ---- called from inside a running task ---- */
void task_yield(void);              /* voluntarily give up the CPU             */
void task_sleep_ms(uint32_t ms);    /* sleep for ~ms milliseconds then return  */
void task_exit(void);               /* mark current task dead (also on return) */

/* Calibrated cycle-per-ms value (set by rtos_init). */
extern uint32_t g_cycles_per_ms;

#endif /* RTOS_H */
