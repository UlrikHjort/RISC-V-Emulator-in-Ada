/* **************************************************************************
 *          RISC-V Emulator - setjmp / longjmp for RV32 bare-metal
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

/* setjmp / longjmp for RV32 bare-metal
 *
 * Saves / restores the minimal callee-saved register set:
 *   ra, sp, s0-s11  (14 registers x 4 bytes = 56 bytes)
 *
 * Floating-point callee-saved registers (fs0-fs11) are NOT saved here;
 * add them if the program uses FP and crosses a longjmp boundary.
 */

.section .text
.option norvc            /* force 32-bit encodings throughout */
.align 2

/* ------------------------------------------------------------------
 * int setjmp(jmp_buf env)   -- a0 = pointer to env
 *
 * Saves ra/sp/s0-s11 into env[], returns 0.
 * ------------------------------------------------------------------ */
.global setjmp
.type   setjmp, @function
setjmp:
    sw   ra,   0*4(a0)
    sw   sp,   1*4(a0)
    sw   s0,   2*4(a0)
    sw   s1,   3*4(a0)
    sw   s2,   4*4(a0)
    sw   s3,   5*4(a0)
    sw   s4,   6*4(a0)
    sw   s5,   7*4(a0)
    sw   s6,   8*4(a0)
    sw   s7,   9*4(a0)
    sw   s8,  10*4(a0)
    sw   s9,  11*4(a0)
    sw   s10, 12*4(a0)
    sw   s11, 13*4(a0)
    li   a0, 0
    jalr zero, ra, 0     /* ret */
.size setjmp, .-setjmp


/* ------------------------------------------------------------------
 * void longjmp(jmp_buf env, int val)   -- a0 = env, a1 = val
 *
 * Returns (val ? val : 1) in a0 to the caller of setjmp.
 * ------------------------------------------------------------------ */
.global longjmp
.type   longjmp, @function
longjmp:
    /* Normalise return value: 0 -> 1 */
    bne  a1, zero, .Lnonzero
    li   a1, 1
.Lnonzero:
    /* Restore callee-saved registers */
    lw   ra,   0*4(a0)
    lw   sp,   1*4(a0)
    lw   s0,   2*4(a0)
    lw   s1,   3*4(a0)
    lw   s2,   4*4(a0)
    lw   s3,   5*4(a0)
    lw   s4,   6*4(a0)
    lw   s5,   7*4(a0)
    lw   s6,   8*4(a0)
    lw   s7,   9*4(a0)
    lw   s8,  10*4(a0)
    lw   s9,  11*4(a0)
    lw   s10, 12*4(a0)
    lw   s11, 13*4(a0)
    mv   a0, a1
    jalr zero, ra, 0     /* ret -- jumps back into setjmp's caller */
.size longjmp, .-longjmp
