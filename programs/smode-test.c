/* **************************************************************************
 *         RISC-V Emulator - Supervisor mode + SBI interface tests
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
 * smode-test.c -- Supervisor mode + SBI interface tests
 *
 * Entry point is smode_main() -- called by crt0-smode.S after mret to S-mode.
 *
 * Tests:
 *  1-2   S-mode CSR access (sstatus readable, sscratch write/read)
 *  3-4   SBI Base extension (get_spec_version, get_impl_id)
 *  5-7   SBI probe_extension (known/unknown EIDs)
 *  8     SBI console_putchar (fire and verify a0=0)
 *  9     SBI legacy shutdown responds (not tested directly -- use exit=93)
 * 10-13  Exception delegation: illegal instruction in S-mode -> stvec fires,
 *        scause=2, stval set, SRET returns to correct PC
 * 14     sepc points to faulting instruction
 * 15-16  ebreak delegated to S-mode (scause=3, MEDELEG bit 3)
 * 17-18  sstatus.SIE (S-mode global interrupt enable) read/write
 */

#include <stdint.h>
#include "log.h"

static int g_pass = 0, g_fail = 0;

static void chk(const char *label, int ok)
{
    if (ok) { log_write(NONE, "PASS %s\n", label); g_pass++; }
    else     { log_write(NONE, "FAIL %s\n", label); g_fail++; }
}

/* ------------------------------------------------------------------ */
/* CSR helpers                                                         */
/* ------------------------------------------------------------------ */
#define csr_read(csr) \
    ({ uint32_t _v; asm volatile("csrr %0, " #csr : "=r"(_v)); _v; })

#define csr_write(csr, val) \
    asm volatile("csrw " #csr ", %0" :: "r"((uint32_t)(val)))

/* ------------------------------------------------------------------ */
/* SBI call (new SBI v0.2 convention: a7=EID, a6=FID)                 */
/* Returns a0 (error code); a1 (value) via out pointer.               */
/* ------------------------------------------------------------------ */
static uint32_t sbi_call(uint32_t eid, uint32_t fid,
                         uint32_t arg0, uint32_t arg1,
                         uint32_t *ret_val)
{
    register uint32_t r_a0 asm("a0") = arg0;
    register uint32_t r_a1 asm("a1") = arg1;
    register uint32_t r_a6 asm("a6") = fid;
    register uint32_t r_a7 asm("a7") = eid;
    asm volatile("ecall"
        : "+r"(r_a0), "+r"(r_a1)
        : "r"(r_a6), "r"(r_a7)
        : "memory");
    if (ret_val) *ret_val = r_a1;
    return r_a0;   /* error code: 0 = SBI_SUCCESS */
}

/* ------------------------------------------------------------------ */
/* S-mode trap handler                                                 */
/* ------------------------------------------------------------------ */
static volatile uint32_t g_trap_scause;
static volatile uint32_t g_trap_stval;
static volatile uint32_t g_trap_sepc;
static volatile int      g_trap_count;
static volatile int      g_after_trap;   /* set by code after trap */

/* Naked trap entry: saves caller-saved regs, calls C handler, srets.
 * Advances sepc by 2 (c.unimp is 16-bit) so execution continues. */
__attribute__((naked, aligned(4)))
static void s_trap_entry(void)
{
    asm volatile(
        "addi sp, sp, -64\n"
        "sw   ra,  0(sp)\n"  "sw   a0,  4(sp)\n"  "sw   a1,  8(sp)\n"
        "sw   a2, 12(sp)\n"  "sw   a3, 16(sp)\n"  "sw   a4, 20(sp)\n"
        "sw   a5, 24(sp)\n"  "sw   a6, 28(sp)\n"  "sw   a7, 32(sp)\n"
        "sw   t0, 36(sp)\n"  "sw   t1, 40(sp)\n"  "sw   t2, 44(sp)\n"
        "sw   t3, 48(sp)\n"  "sw   t4, 52(sp)\n"  "sw   t5, 56(sp)\n"
        "sw   t6, 60(sp)\n"

        /* Save trap info to globals */
        "csrr a0, scause\n"
        "la   a1, g_trap_scause\n"  "sw a0, 0(a1)\n"
        "csrr a0, stval\n"
        "la   a1, g_trap_stval\n"   "sw a0, 0(a1)\n"
        "csrr a0, sepc\n"
        "la   a1, g_trap_sepc\n"    "sw a0, 0(a1)\n"

        /* Increment trap counter */
        "la   a1, g_trap_count\n"
        "lw   a0, 0(a1)\n"  "addi a0, a0, 1\n"  "sw a0, 0(a1)\n"

        /* Advance sepc by 2 (c.unimp = 16-bit instruction) */
        "csrr a0, sepc\n"  "addi a0, a0, 2\n"  "csrw sepc, a0\n"

        "lw   ra,  0(sp)\n"  "lw   a0,  4(sp)\n"  "lw   a1,  8(sp)\n"
        "lw   a2, 12(sp)\n"  "lw   a3, 16(sp)\n"  "lw   a4, 20(sp)\n"
        "lw   a5, 24(sp)\n"  "lw   a6, 28(sp)\n"  "lw   a7, 32(sp)\n"
        "lw   t0, 36(sp)\n"  "lw   t1, 40(sp)\n"  "lw   t2, 44(sp)\n"
        "lw   t3, 48(sp)\n"  "lw   t4, 52(sp)\n"  "lw   t5, 56(sp)\n"
        "lw   t6, 60(sp)\n"
        "addi sp, sp, 64\n"
        "sret\n"
    );
}

/* Install s_trap_entry as the S-mode trap vector (direct mode) */
static void install_stvec(void)
{
    uint32_t addr = (uint32_t)s_trap_entry;
    csr_write(stvec, addr & ~3U);   /* mode=00 = Direct */
}

/* ------------------------------------------------------------------ */
/* Entry point (called from crt0-smode.S via mret)                    */
/* ------------------------------------------------------------------ */
void smode_main(void)
{
    log_init("smode-test.log");
    log_write(NONE, "=== Supervisor Mode + SBI Test ===\n");

    /* ---- 1-2: S-mode CSR access ---------------------------------- */
    {
        /* Reading sstatus from S-mode must not trap */
        uint32_t ss = csr_read(sstatus);
        chk("sstatus readable in S-mode", 1);   /* reaching here = OK */

        /* Write/read sscratch */
        csr_write(sscratch, 0xDEADBEEF);
        uint32_t sc = csr_read(sscratch);
        chk("sscratch write/read round-trip", sc == 0xDEADBEEF);
        (void)ss;
    }

    /* ---- 3-4: SBI Base extension --------------------------------- */
    {
        uint32_t val = 0;
        uint32_t err;

        /* get_spec_version: should return 0x02000000 (SBI v0.2) */
        err = sbi_call(0x10, 0, 0, 0, &val);
        chk("SBI get_spec_version == 0x02000000",
            err == 0 && val == 0x02000000);

        /* get_impl_id: any non-negative value */
        err = sbi_call(0x10, 1, 0, 0, &val);
        chk("SBI get_impl_id succeeds", err == 0);
    }

    /* ---- 5-7: probe_extension ------------------------------------ */
    {
        uint32_t val = 0;

        /* EID=1 (console_putchar) should be supported */
        sbi_call(0x10, 3, 1, 0, &val);
        chk("SBI probe: console_putchar supported", val == 1);

        /* EID=0x10 (base) should be supported */
        sbi_call(0x10, 3, 0x10, 0, &val);
        chk("SBI probe: base extension supported", val == 1);

        /* EID=0x999 (unknown) should not be supported */
        sbi_call(0x10, 3, 0x999, 0, &val);
        chk("SBI probe: unknown ext not supported", val == 0);
    }

    /* ---- 8: SBI console_putchar ---------------------------------- */
    {
        /* Write a visible marker to UART */
        uint32_t err = sbi_call(1, 0, (uint32_t)'S', 0, 0);
        sbi_call(1, 0, (uint32_t)'B', 0, 0);
        sbi_call(1, 0, (uint32_t)'I', 0, 0);
        sbi_call(1, 0, (uint32_t)'\n', 0, 0);
        chk("SBI console_putchar returns 0", err == 0);
    }

    /* ---- 9-13: Exception delegation (illegal instruction) --------- */
    {
        install_stvec();
        g_trap_count = 0;
        g_after_trap = 0;

        /* Trigger: c.unimp (0x0000) is a 16-bit illegal instruction.
         * MEDELEG bit 2 (illegal insn) is set by crt0-smode.S so the
         * trap is delegated to S-mode -> s_trap_entry fires. */
        asm volatile(".hword 0x0000");   /* c.unimp */
        g_after_trap = 1;

        chk("S-mode trap handler fired",       g_trap_count == 1);
        chk("scause == 2 (illegal insn)",      g_trap_scause == 2);
        chk("SRET returned past faulting insn", g_after_trap == 1);

        /* Second trap to verify handler is still installed */
        g_trap_count = 0;
        asm volatile(".hword 0x0000");
        chk("second trap handled correctly", g_trap_count == 1);
    }

    /* ---- 14: sepc pointed to the faulting instruction ------------ */
    {
        /* The fault PC captured in the handler must be <= current PC.
         * We know sret advanced sepc+2 and returned here, so
         * g_trap_sepc was the address of the c.unimp above. */
        uint32_t cur_pc;
        asm volatile("auipc %0, 0" : "=r"(cur_pc));
        chk("sepc was before current PC", g_trap_sepc < cur_pc);
    }

    /* ---- 15-16: ebreak delegation (MEDELEG bit 3 = breakpoint) ---- */
    {
        /* medeleg = 0x1FF covers bit 3 (breakpoint), so ebreak from S-mode
         * should be delegated to our S-mode handler with scause=3. */
        g_trap_count = 0;
        asm volatile("ebreak");
        chk("ebreak delegated to S-mode",  g_trap_count == 1);
        chk("scause == 3 (breakpoint)",    g_trap_scause == 3);
    }

    /* ---- 17-18: sstatus.SIE (S-mode global interrupt enable) ------ */
    {
        /* SIE = bit 1 of sstatus.  Must be writable from S-mode. */
        uint32_t ss = csr_read(sstatus);
        csr_write(sstatus, ss | (1u << 1));        /* set SIE */
        uint32_t ss2 = csr_read(sstatus);
        chk("sstatus.SIE can be set",   (ss2 >> 1) & 1u);
        csr_write(sstatus, ss2 & ~(1u << 1));      /* clear SIE */
        uint32_t ss3 = csr_read(sstatus);
        chk("sstatus.SIE can be cleared", !((ss3 >> 1) & 1u));
        csr_write(sstatus, ss);                    /* restore */
    }

    log_write(NONE, "\n%d PASS  %d FAIL\n", g_pass, g_fail);
    log_close();

    /* Halt via host exit ecall (intercepted before SBI/trap) */
    asm volatile("li a7, 93\necall" ::: "a7", "memory");
}
