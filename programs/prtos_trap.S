/* **************************************************************************
 *               RISC-V Emulator - Preemptive RTOS Trap Handler
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
 * Machine-mode timer interrupt handler for the preemptive RTOS.
 *
 * Frame layout (128 bytes, 32 x uint32_t):
 *   [ 0] x1  ra          [  4] x3  gp         [  8] x4  tp
 *   [12] x5  t0          [ 16] x6  t1          [ 20] x7  t2
 *   [24] x8  s0/fp       [ 28] x9  s1
 *   [32] x10 a0          [ 36] x11 a1          [ 40] x12 a2
 *   [44] x13 a3          [ 48] x14 a4          [ 52] x15 a5
 *   [56] x16 a6          [ 60] x17 a7
 *   [64] x18 s2          [ 68] x19 s3          [ 72] x20 s4
 *   [76] x21 s5          [ 80] x22 s6          [ 84] x23 s7
 *   [88] x24 s8          [ 92] x25 s9          [ 96] x26 s10
 *  [100] x27 s11         [104] x28 t3          [108] x29 t4
 *  [112] x30 t5          [116] x31 t6
 *  [120] mepc            [124] mstatus
 *
 * Note: x2 (sp) is NOT in the frame -- it is stored separately in the TCB.
 *       After pushing the frame (addi sp,-128), saved_sp = the new sp value.
 *
 * Calling convention:
 *   uint32_t *prtos_timer_isr(uint32_t *saved_sp)
 *   -> returns the stack pointer of the next task to run
 *   -> trap_entry sets sp = return value, restores frame, mret
 */

    .section .text
    .global  trap_entry
    .align   2            /* mtvec requires 4-byte alignment for direct mode */

trap_entry:
    /* --- push 128-byte frame on current stack --- */
    addi  sp,  sp, -128

    sw    x1,    0(sp)
    sw    x3,    4(sp)
    sw    x4,    8(sp)
    sw    x5,   12(sp)
    sw    x6,   16(sp)
    sw    x7,   20(sp)
    sw    x8,   24(sp)
    sw    x9,   28(sp)
    sw    x10,  32(sp)
    sw    x11,  36(sp)
    sw    x12,  40(sp)
    sw    x13,  44(sp)
    sw    x14,  48(sp)
    sw    x15,  52(sp)
    sw    x16,  56(sp)
    sw    x17,  60(sp)
    sw    x18,  64(sp)
    sw    x19,  68(sp)
    sw    x20,  72(sp)
    sw    x21,  76(sp)
    sw    x22,  80(sp)
    sw    x23,  84(sp)
    sw    x24,  88(sp)
    sw    x25,  92(sp)
    sw    x26,  96(sp)
    sw    x27, 100(sp)
    sw    x28, 104(sp)
    sw    x29, 108(sp)
    sw    x30, 112(sp)
    sw    x31, 116(sp)

    csrr  t0, mepc
    sw    t0,  120(sp)
    csrr  t0, mstatus
    sw    t0,  124(sp)

    /* --- call C scheduler: prtos_timer_isr(saved_sp) -> new_sp --- */
    mv    a0,  sp
    call  prtos_timer_isr       /* a0 = new task's saved_sp */
    mv    sp,  a0

    /* --- restore CSRs first (uses t0 = x5; safe to overwrite before restore) --- */
    lw    t0,  120(sp)
    csrw  mepc,    t0
    lw    t0,  124(sp)
    csrw  mstatus, t0

    /* --- restore all GPRs (t0 is last, overwrites the temp value above) --- */
    lw    x1,    0(sp)
    lw    x3,    4(sp)
    lw    x4,    8(sp)
    lw    x5,   12(sp)          /* t0 -- overwrites CSR temp, already written */
    lw    x6,   16(sp)
    lw    x7,   20(sp)
    lw    x8,   24(sp)
    lw    x9,   28(sp)
    lw    x10,  32(sp)
    lw    x11,  36(sp)
    lw    x12,  40(sp)
    lw    x13,  44(sp)
    lw    x14,  48(sp)
    lw    x15,  52(sp)
    lw    x16,  56(sp)
    lw    x17,  60(sp)
    lw    x18,  64(sp)
    lw    x19,  68(sp)
    lw    x20,  72(sp)
    lw    x21,  76(sp)
    lw    x22,  80(sp)
    lw    x23,  84(sp)
    lw    x24,  88(sp)
    lw    x25,  92(sp)
    lw    x26,  96(sp)
    lw    x27, 100(sp)
    lw    x28, 104(sp)
    lw    x29, 108(sp)
    lw    x30, 112(sp)
    lw    x31, 116(sp)

    addi  sp,  sp, 128
    mret
