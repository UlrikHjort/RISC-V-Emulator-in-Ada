/* **************************************************************************
 *         RISC-V Emulator - multi-hart startup for pthread library
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

/* crt0-pthread.S -- multi-hart startup for pthread library
 *
 * Hart 0: zeros BSS, sets up stack at _stack_top, calls main()
 * Hart 1+: spin-wait on _pthread_launch table, executing tasks as assigned.
 *
 * _pthread_launch layout (MAX_HARTS=4 entries, 4 words each):
 *   offset  0: fn   -- function pointer (NULL = idle)
 *   offset  4: arg  -- argument pointer
 *   offset  8: sp   -- stack pointer for this task
 *   offset 12: tcb  -- pointer to TCB (for storing retval + state)
 *
 * When pthread_create wants to run a task on hart N, it fills
 * _pthread_launch[N] with (fn, arg, sp, tcb) and stores fn last
 * so the secondary hart sees a non-NULL fn and starts working.
 */

.section .text.start
.option norvc
.global _start
.align 2

_start:
    csrr t0, mhartid
    bnez t0, .Lsecondary_hart

    /* ---- Hart 0: normal startup ---- */
    la   sp, _stack_top

    /* Zero BSS */
    la   t0, __bss_start
    la   t1, __bss_end
1:  bge  t0, t1, 2f
    sw   zero, 0(t0)
    addi t0, t0, 4
    j    1b
2:
    call main
    li   a7, 93
    ecall

/* ---- Secondary hart (hart 1) spin loop ---- */
.Lsecondary_hart:
    /* a0 = mhartid (we re-read it to be safe) */
    csrr a0, mhartid

    /* Compute address of _pthread_launch[hartid]:
     * each entry is 16 bytes (4 words x 4 bytes) */
    li   t0, 16
    mul  t1, a0, t0          /* offset = hartid * 16 */
    la   t2, _pthread_launch
    add  t2, t2, t1          /* t2 = &_pthread_launch[hartid] */

.Lpoll:
    /* Spin until fn pointer is non-NULL */
    lw   t0, 0(t2)           /* load fn */
    beqz t0, .Lpoll          /* if NULL, keep spinning */

    fence                    /* acquire barrier */

    /* Load sp, arg, tcb */
    lw   sp, 8(t2)           /* load stack pointer */
    lw   a0, 4(t2)           /* load arg */
    lw   a1, 12(t2)          /* load tcb pointer */

    /* Call _pthread_entry_wrapper(fn, arg, tcb) */
    /* a0=arg, a1=tcb, need fn in t0 */
    /* Rearrange: a2=tcb, a1=arg, a0=fn */
    mv   a2, a1              /* a2 = tcb */
    mv   a1, a0              /* a1 = arg */
    mv   a0, t0              /* a0 = fn */

    /* Clear the fn pointer BEFORE calling (so next iteration works) */
    sw   zero, 0(t2)
    fence

    call _pthread_entry_wrapper

    /* After task completes, re-compute t2 (caller-saved, clobbered by call)
     * and loop back to polling.                                              */
    csrr a0, mhartid
    li   t0, 16
    mul  t1, a0, t0
    la   t2, _pthread_launch
    add  t2, t2, t1
    j    .Lpoll

/* ---- Launch table in BSS ---- */
.section .bss
.align 4
.global _pthread_launch
_pthread_launch:
    .space 4 * 4 * 4         /* MAX_HARTS=4 entries x 4 words x 4 bytes */

/* Hart 1 stack (declared here; pthread.c provides per-thread stacks) */
.align 4
.global _hart1_stack_base
_hart1_stack_base:
    .space 1024
