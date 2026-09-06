/* **************************************************************************
 *              RISC-V Emulator - setjmp / longjmp - Interface
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

#ifndef SETJMP_H
#define SETJMP_H

#include <stdint.h>

/*
 * jmp_buf layout (14 x 32-bit words):
 *  [0]  ra   (x1)   return address
 *  [1]  sp   (x2)   stack pointer
 *  [2]  s0   (x8)   callee-saved
 *  [3]  s1   (x9)
 *  [4]  s2   (x18)
 *  [5]  s3   (x19)
 *  [6]  s4   (x20)
 *  [7]  s5   (x21)
 *  [8]  s6   (x22)
 *  [9]  s7   (x23)
 *  [10] s8   (x24)
 *  [11] s9   (x25)
 *  [12] s10  (x26)
 *  [13] s11  (x27)
 */
typedef uint32_t jmp_buf[14];

/* Save the calling environment in env and return 0.
 * When longjmp is called with env, setjmp returns the val passed to longjmp
 * (or 1 if val was 0). */
int setjmp(jmp_buf env);

/* Restore the environment saved by setjmp(env) and return val (or 1 if val==0).
 * Execution continues as if setjmp had returned val. */
void longjmp(jmp_buf env, int val) __attribute__((noreturn));

#endif /* SETJMP_H */
