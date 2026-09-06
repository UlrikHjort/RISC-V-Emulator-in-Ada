/* **************************************************************************
 *                     RISC-V Emulator - 2-hart startup
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

/* crt0-multihart.S -- 2-hart startup
 * Hart 0: zeros BSS, sets up stack at _stack_top, calls main
 * Hart 1: uses _hart1_stack (1 KB, defined in BSS), calls main
 * Both harts call main(); main() reads mhartid and dispatches.
 */
.section .text.start
.option norvc
.global _start
.align 2
_start:
    csrr t0, mhartid
    bnez t0, .Lhart1_init

    /* Hart 0: set up stack */
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

.Lhart1_init:
    /* Hart 1: use separate stack (1 KB above _hart1_stack_base) */
    la   sp, _hart1_stack_base
    li   t0, 1024
    add  sp, sp, t0
    call main
    li   a7, 93
    ecall

/* Hart 1 stack (1 KB) in BSS */
.section .bss
.align 4
.global _hart1_stack_base
_hart1_stack_base:
    .space 1024
