/* **************************************************************************
 *RISC-V Emulator - RV64 M-mode startup that transitions to Supervisor mode
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

/* crt0-smode-64.S -- RV64 M-mode startup that transitions to Supervisor mode
 *
 * Like crt0-smode.S but for RV64 (uses 'sd' for BSS zeroing).
 * Also delegates page fault exceptions (12, 13, 15) to S-mode.
 *
 * Execution flow:
 *   1. Set up stack and zero BSS  (M-mode)
 *   2. Configure M-mode trap handler (safety net)
 *   3. Delegate synchronous exceptions 0-15 to S-mode via MEDELEG
 *   4. Delegate S-mode software/timer interrupts via MIDELEG
 *   5. Set MSTATUS.MPP = Supervisor (01)
 *   6. Load MEPC with smode_main entry point
 *   7. MRET -> now executing in Supervisor mode
 */

.section .text.start
.option norvc
.global _start
.align 2

_start:
    /* --- 1. Stack pointer ----------------------------------------- */
    la   sp, _stack_top

    /* --- 2. Zero BSS (8 bytes at a time) -------------------------- */
    la   t0, __bss_start
    la   t1, __bss_end
1:
    bge  t0, t1, 2f
    sd   zero, 0(t0)
    addi t0, t0, 8
    j    1b
2:
    /* --- 3. M-mode trap handler (unexpected M-mode faults) --------- */
    la   t0, m_trap_entry
    csrw mtvec, t0

    /* --- 4. Delegate synchronous exceptions 0-15 to S-mode ---------
     * Bits 0-8: instruction misaligned (0), instruction fault (1),
     * illegal instruction (2), breakpoint (3), load misaligned (4),
     * load fault (5), store misaligned (6), store fault (7),
     * ecall from U-mode (8).
     * Bits 12,13,15: instruction page fault (12), load page fault (13),
     * store page fault (15).
     * Bits 9 (ecall-S), 10 (ecall-H), 11 (ecall-M) stay in M-mode. */
    li   t0, 0xB1FF
    csrw medeleg, t0

    /* --- 5. Delegate S-mode software (bit 1) and timer (bit 5) ----- */
    li   t0, 0x22
    csrw mideleg, t0

    /* --- 6. Allow S-mode to read cycle/time/instret counters ------- */
    li   t0, 7
    csrw scounteren, t0

    /* --- 7. mstatus.MPP = 01 (Supervisor): bits[12:11] = 0b01 ------ */
    li   t0, (1 << 11)
    csrw mstatus, t0

    /* --- 8. mepc = smode_main entry point -------------------------- */
    la   t0, smode_main
    csrw mepc, t0

    /* --- 9. Disable virtual memory --------------------------------- */
    csrw satp, zero

    /* Drop into Supervisor mode */
    mret

    /* Should never reach here */
    .align 2

/* M-mode trap handler -- fatal: halts via host ecall */
m_trap_entry:
    li   a7, 93
    ecall
