/* **************************************************************************
 *               RISC-V Emulator - User privilege mode tests
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

/*
 * umode-test.c -- User privilege mode tests
 *
 * Entry: smode_main() called by crt0-smode.S after mret to S-mode.
 *
 * Tests:
 *  1    user_task() executes in U-mode (g_user_task_reached == 1)
 *  2    cycle CSR readable from U-mode (scounteren.CY=1, set by crt0-smode.S)
 *  3    USYS_PING ecall from U-mode -> cause=8, delegated to S-mode (count==2)
 *  4    illegal CSR (mstatus) from U-mode -> cause=2, delegated to S-mode
 *  5    USYS_EXIT ecall -> S-mode returns cleanly to smode_main
 *  6    total trap count == 4 (2xping + 1xillegal + 1xexit; no spurious traps)
 *  7    last scause == 8 (U-mode ecall for USYS_EXIT)
 *
 * Stack layout:
 *   s_trap_stack[256]  -- dedicated S-mode trap handler stack
 *   u_stack[128]       -- user-mode stack (switched in enter_umode)
 *   sscratch           -- always holds trap-stack top when outside trap
 */

#include <stdint.h>
#include "log.h"

static int g_pass = 0, g_fail = 0;

static void chk(const char *label, int ok)
{
    if (ok) { log_write(NONE, "PASS %s\n", label); g_pass++; }
    else     { log_write(NONE, "FAIL %s\n", label); g_fail++; }
}

/* Custom ecall numbers used by user_task */
#define USYS_PING  100
#define USYS_EXIT  101

/* ------------------------------------------------------------------ */
/* Globals shared between trap handler and smode_main                  */
/* ------------------------------------------------------------------ */
static volatile int      g_user_task_reached;
static volatile int      g_ping_count;
static volatile int      g_illegal_count;
static volatile int      g_trap_count;
static volatile uint32_t g_trap_scause;
static volatile uint32_t g_cycle_val;      /* written by user_task after csrr cycle */

/* S-mode context saved by enter_umode before SRET to U-mode */
static volatile uint32_t g_smode_ra;
static volatile uint32_t g_smode_sp;

/* Stacks */
static uint32_t u_stack[128] __attribute__((used)); /* user-mode stack (512 bytes) */
static uint32_t s_trap_stack[256];         /* S-mode trap stack (1 KB)     */
static volatile uint32_t g_trap_stack_top; /* = s_trap_stack + 256         */

/* ------------------------------------------------------------------ */
/* S-mode trap handler (naked -- entire body is assembly)               */
/*                                                                      */
/* On entry from U-mode:                                                */
/*   sp   = user stack pointer (garbage for our purposes)              */
/*   sscratch = top of s_trap_stack                                    */
/* We swap sp <-> sscratch so sp becomes the trap stack.                 */
/* ------------------------------------------------------------------ */
__attribute__((naked, aligned(4)))
static void s_trap_entry(void)
{
    asm volatile(
        /* ---- Save context onto trap stack -------------------------------- */
        "csrrw sp, sscratch, sp\n"         /* sp = trap-stack top; sscratch = caller sp */
        "addi  sp, sp, -72\n"
        "sw    ra,  0(sp)\n"
        "sw    a0,  4(sp)\n"  "sw    a1,  8(sp)\n"
        "sw    a2, 12(sp)\n"  "sw    a3, 16(sp)\n"
        "sw    a4, 20(sp)\n"  "sw    a5, 24(sp)\n"
        "sw    a6, 28(sp)\n"  "sw    a7, 32(sp)\n"
        "sw    t0, 36(sp)\n"  "sw    t1, 40(sp)\n"
        "sw    t2, 44(sp)\n"  "sw    t3, 48(sp)\n"
        "sw    t4, 52(sp)\n"  "sw    t5, 56(sp)\n"
        "sw    t6, 60(sp)\n"
        "csrr  t0, sscratch\n"             /* sscratch = caller sp (from swap above) */
        "sw    t0, 64(sp)\n"               /* save it in slot 64 */

        /* ---- Record scause and bump trap counter ------------------------- */
        "csrr  a0, scause\n"
        "la    a1, g_trap_scause\n"        "sw    a0, 0(a1)\n"
        "la    a1, g_trap_count\n"
        "lw    a0, 0(a1)\n"  "addi a0, a0, 1\n"  "sw a0, 0(a1)\n"

        /* ---- Dispatch on scause ------------------------------------------ */
        "la    a1, g_trap_scause\n"        "lw    a0, 0(a1)\n"
        "li    t0, 8\n"  "beq a0, t0, .Lecall_u\n"    /* cause 8 = U-mode ecall */
        "li    t0, 2\n"  "beq a0, t0, .Lillegal\n"    /* cause 2 = illegal insn */
        "j     .Ladvance4\n"                           /* anything else: skip */

        /* ---- Illegal instruction: bump counter, skip instruction --------- */
        ".Lillegal:\n"
        "la    a1, g_illegal_count\n"
        "lw    a0, 0(a1)\n"  "addi a0, a0, 1\n"  "sw a0, 0(a1)\n"
        "j     .Ladvance4\n"

        /* ---- U-mode ecall: dispatch on EID (saved in a7 slot) ------------ */
        ".Lecall_u:\n"
        "lw    a7, 32(sp)\n"               /* reload saved a7 = EID */
        "li    t0, 101\n"  "beq a7, t0, .Lexit\n"     /* USYS_EXIT */
        /* Default (USYS_PING and anything else): increment ping counter */
        "la    a1, g_ping_count\n"
        "lw    a0, 0(a1)\n"  "addi a0, a0, 1\n"  "sw a0, 0(a1)\n"
        "j     .Ladvance4\n"

        /* ---- Advance sepc by 4 (all our trap sites use 32-bit insns) ----- */
        ".Ladvance4:\n"
        "csrr  a0, sepc\n"  "addi a0, a0, 4\n"  "csrw sepc, a0\n"
        "j     .Ltrap_exit\n"

        /* ---- USYS_EXIT: switch back to S-mode and return to smode_main --- */
        ".Lexit:\n"
        /* sstatus.SPP = 1 -> SRET returns to Supervisor mode */
        "li    t0, (1 << 8)\n"
        "csrrs zero, sstatus, t0\n"
        /* sepc = umode_return_point (label in enter_umode, after its sret) */
        "la    t0, umode_return_point\n"
        "csrw  sepc, t0\n"
        /* Restore S-mode stack pointer saved by enter_umode */
        "la    t0, g_smode_sp\n"           "lw    sp, 0(t0)\n"
        /* Restore sscratch = trap-stack top (ready for future traps) */
        "la    t0, g_trap_stack_top\n"     "lw    t0, 0(t0)\n"
        "csrw  sscratch, t0\n"
        "sret\n"

        /* ---- Normal trap exit: restore regs + sp, then sret -------------- */
        ".Ltrap_exit:\n"
        "lw    ra,  0(sp)\n"
        "lw    a0,  4(sp)\n"  "lw    a1,  8(sp)\n"
        "lw    a2, 12(sp)\n"  "lw    a3, 16(sp)\n"
        "lw    a4, 20(sp)\n"  "lw    a5, 24(sp)\n"
        "lw    a6, 28(sp)\n"  "lw    a7, 32(sp)\n"
        "lw    t0, 36(sp)\n"  "lw    t1, 40(sp)\n"
        "lw    t2, 44(sp)\n"  "lw    t3, 48(sp)\n"
        "lw    t4, 52(sp)\n"  "lw    t5, 56(sp)\n"
        "lw    t6, 60(sp)\n"
        "lw    t1, 64(sp)\n"               /* saved original sp */
        "addi  sp, sp, 72\n"
        "csrw  sscratch, sp\n"             /* restore sscratch = trap-stack top */
        "mv    sp, t1\n"                   /* restore original (user) sp */
        "sret\n"
    );
}

/* ------------------------------------------------------------------ */
/* enter_umode: SRET to user_fn in U-mode.                             */
/* Returns when the USYS_EXIT handler SRETs to umode_return_point.     */
/* ------------------------------------------------------------------ */
extern void umode_return_point(void);   /* defined inside the naked function */

__attribute__((naked, aligned(4)))
static void enter_umode(void (*user_fn)(void))
{
    asm volatile(
        /* a0 = user_fn */
        /* Save S-mode return address and stack pointer */
        "la   t0, g_smode_ra\n"  "sw   ra, 0(t0)\n"
        "la   t0, g_smode_sp\n"  "sw   sp, 0(t0)\n"
        /* Switch to dedicated U-mode stack */
        "la   sp, u_stack\n"
        "li   t0, 512\n"               /* 128 x 4 bytes */
        "add  sp, sp, t0\n"
        /* sstatus.SPP = 0 -> SRET returns to User mode */
        "li   t0, (1 << 8)\n"
        "csrrc zero, sstatus, t0\n"
        /* sepc = user_fn */
        "csrw sepc, a0\n"
        /* SRET -> U-mode execution begins at user_fn */
        "sret\n"

        /* ================================================================
         * The following is only reached when the USYS_EXIT trap handler
         * sets sepc = umode_return_point and SRETs back here in S-mode.
         * At that point sp = g_smode_sp (restored by the trap handler).
         * ================================================================ */
        ".globl umode_return_point\n"
        "umode_return_point:\n"
        /* Reload S-mode return address and return to smode_main */
        "la   ra, g_smode_ra\n"  "lw   ra, 0(ra)\n"
        "ret\n"
    );
}

/* ------------------------------------------------------------------ */
/* user_task: code that runs in User mode                              */
/* ------------------------------------------------------------------ */
static void user_task(void)
{
    asm volatile(
        /* Mark arrival so smode_main can verify U-mode was reached */
        "li   t0, 1\n"
        "la   t1, g_user_task_reached\n"
        "sw   t0, 0(t1)\n"

        /* Read cycle CSR -- allowed because crt0-smode.S sets scounteren=7 */
        "csrr  t0, cycle\n"
        "la    t1, g_cycle_val\n"
        "sw    t0, 0(t1)\n"

        /* USYS_PING ecall #1 -> scause=8, S-mode handler increments g_ping_count */
        "li    a7, 100\n"
        "ecall\n"

        /* USYS_PING ecall #2 */
        "li    a7, 100\n"
        "ecall\n"

        /* Attempt to read mstatus from U-mode -- requires M-mode -> scause=2.
         * Use .option norvc to guarantee 32-bit encoding so sepc+4 skips past it. */
        ".option push\n"
        ".option norvc\n"
        "csrr  t0, mstatus\n"
        ".option pop\n"

        /* USYS_EXIT ecall -> trap handler SRETs to umode_return_point in S-mode */
        "li    a7, 101\n"
        "ecall\n"

        /* Unreachable */
        ::: "a7", "t0", "t1", "memory"
    );
}

/* ------------------------------------------------------------------ */
/* Entry point (called from crt0-smode.S via mret to S-mode)          */
/* ------------------------------------------------------------------ */
void smode_main(void)
{
    log_init("umode-test.log");
    log_write(NONE, "=== User Mode Test ===\n");

    /* Set up trap stack and initialise sscratch to its top */
    g_trap_stack_top = (uint32_t)(s_trap_stack + 256);
    asm volatile("csrw sscratch, %0" :: "r"(g_trap_stack_top));

    /* Install S-mode trap vector (direct mode) */
    uint32_t tvec = (uint32_t)s_trap_entry & ~3U;
    asm volatile("csrw stvec, %0" :: "r"(tvec));

    /* Transition to U-mode; returns after USYS_EXIT */
    enter_umode(user_task);

    /* ---- Assertions ------------------------------------------------- */
    chk("user_task executed in U-mode",    g_user_task_reached == 1);
    chk("cycle CSR readable from U-mode",  g_cycle_val > 0);
    chk("USYS_PING handled (count==2)",    g_ping_count == 2);
    chk("illegal CSR trapped (count==1)",  g_illegal_count == 1);
    chk("enter_umode returned cleanly",    1);           /* reaching here = OK */
    chk("total trap count == 4",           g_trap_count == 4);
    chk("last scause == 8 (U-mode ecall)", g_trap_scause == 8);

    log_write(NONE, "\n%d PASS  %d FAIL\n", g_pass, g_fail);
    log_close();

    /* Halt */
    asm volatile("li a7, 93\necall" ::: "a7", "memory");
}
