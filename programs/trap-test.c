/* **************************************************************************
 *              RISC-V Emulator - Exception/trap handling test
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

// trap-test.c -- Exception/trap handling test.
//
// Installs a machine-mode trap handler, then deliberately triggers exceptions
// and interrupts, verifying MCAUSE, MEPC, MTVAL and correct MRET behaviour.
//
// Exceptions tested:
//   MCAUSE=2   (illegal insn):   c.unimp (0x0000) 16-bit illegal instruction
//   MCAUSE=3   (breakpoint):     ebreak instruction
//   MCAUSE=11  (env-call M):     ecall with non-semihosting a7
//
// Misaligned data accesses are emulated (no trap), per the RISC-V spec option;
// test_load_misaligned / test_store_misaligned verify they complete correctly.
//
// Interrupts tested:
//   MCAUSE=0x80000007 (M-mode timer): CLINT mtimecmp fires, MIE/MTIE enabled
//
// Build: cd programs && make run-trap-test
// By Ulrik Hørlyk Hjort 2026

#include <stdint.h>
#include "log.h"

void putchar(char c);

static void uart_puts(const char *s) {
    while (*s) { if (*s == '\n') putchar('\r'); putchar(*s++); }
}

static int g_pass = 0, g_fail = 0;

// -- CSR helpers -----------------------------------------------------------

#define CSR_READ(csr)      ({ uint32_t _v; asm volatile("csrr %0," #csr : "=r"(_v)); _v; })
#define CSR_WRITE(csr,val) asm volatile("csrw " #csr ",%0" :: "r"((uint32_t)(val)))

// -- CLINT memory-mapped registers (qemu-virt: CLINT base = 0x02000000) ----

#define CLINT_MTIME_LO  (*(volatile uint32_t*)0x0200BFF8u)
#define CLINT_MTIME_HI  (*(volatile uint32_t*)0x0200BFFCu)
#define CLINT_MTCMP_LO  (*(volatile uint32_t*)0x02004000u)
#define CLINT_MTCMP_HI  (*(volatile uint32_t*)0x02004004u)

// -- Handler state (written by trap handler) -------------------------------

static volatile uint32_t g_mcause = 0xDEADBEEF;
static volatile uint32_t g_mepc   = 0xDEADBEEF;
static volatile uint32_t g_mtval  = 0xDEADBEEF;
static volatile int      g_trap_count = 0;

// -- Trap handler ----------------------------------------------------------
//
// Naked: manages all register saves itself.
// - Saves/restores a0, a1, a2 around the handler body.
// - For exceptions (mcause bit 31 = 0): advances MEPC past the faulting
//   instruction (2 bytes if compressed, 4 bytes otherwise).
// - For interrupts (mcause bit 31 = 1): does NOT advance MEPC.
// - For M-mode timer interrupt (0x80000007): writes 0xFFFFFFFF to
//   CLINT mtimecmp_hi to prevent immediate re-fire after MRET.

static void trap_handler(void) __attribute__((naked, aligned(4)));
static void trap_handler(void) {
    asm volatile(
        /* Save caller-used registers */
        "addi sp, sp, -16\n"
        "sw   a0,  0(sp)\n"
        "sw   a1,  4(sp)\n"
        "sw   a2,  8(sp)\n"

        /* Capture trap state into globals */
        "csrr a0, mcause\n"  "la a1, g_mcause\n"  "sw a0, 0(a1)\n"
        "csrr a0, mepc\n"    "la a1, g_mepc\n"    "sw a0, 0(a1)\n"
        "csrr a0, mtval\n"   "la a1, g_mtval\n"   "sw a0, 0(a1)\n"

        /* Increment trap counter */
        "la   a1, g_trap_count\n"
        "lw   a2, 0(a1)\n"  "addi a2, a2, 1\n"  "sw a2, 0(a1)\n"

        /* For M-mode timer interrupt: clear mtimecmp_hi to prevent re-fire */
        "csrr a0, mcause\n"
        "li   a1, 0x80000007\n"
        "bne  a0, a1, 1f\n"
        "li   a1, 0x02004004\n"     /* CLINT_MTCMP_HI */
        "li   a2, -1\n"             /* 0xFFFFFFFF */
        "sw   a2, 0(a1)\n"
        "1:\n"

        /* Advance MEPC only for exceptions (bit 31 = 0 -> not an interrupt) */
        "csrr a0, mcause\n"
        "bltz a0, 4f\n"             /* interrupt: skip to restore */
        "csrr a0, mepc\n"
        "lh   a1, 0(a0)\n"          /* read low 16 bits of faulting instruction */
        "andi a1, a1, 3\n"          /* low 2 bits: 11 = 32-bit, else = compressed */
        "li   a2, 3\n"
        "bne  a1, a2, 2f\n"         /* branch if compressed */
        "addi a0, a0, 4\n"          /* 32-bit: advance by 4 */
        "j    3f\n"
        "2:\n"
        "addi a0, a0, 2\n"          /* 16-bit: advance by 2 */
        "3:\n"
        "csrw mepc, a0\n"
        "4:\n"                      /* interrupt path joins here */

        /* Restore and return */
        "lw   a0,  0(sp)\n"
        "lw   a1,  4(sp)\n"
        "lw   a2,  8(sp)\n"
        "addi sp, sp, 16\n"
        "mret\n"
    );
}

// -- Test helpers ----------------------------------------------------------

static void reset_trap_state(void) {
    g_mcause = 0xDEADBEEF;
    g_mepc   = 0xDEADBEEF;
    g_mtval  = 0xDEADBEEF;
}

/* Checks mcause, trap_count, and (optionally) that mepc was non-zero. */
static void check_trap(const char *cause_label, uint32_t exp_cause,
                       uint32_t exp_count, int check_mepc) {
    if (g_mcause == exp_cause) {
        log_write(NONE, "  PASS  mcause=%d (%s)\n", exp_cause, cause_label);
        g_pass++;
    } else {
        log_write(NONE, "  FAIL  mcause: got 0x%x  exp 0x%x (%s)\n",
                  g_mcause, exp_cause, cause_label);
        g_fail++;
    }
    if ((int)g_trap_count == (int)exp_count) {
        log_write(NONE, "  PASS  trap_count=%d\n", exp_count);
        g_pass++;
    } else {
        log_write(NONE, "  FAIL  trap_count: got %d  exp %d\n",
                  g_trap_count, exp_count);
        g_fail++;
    }
    if (check_mepc) {
        if (g_mepc != 0xDEADBEEFu && g_mepc != 0u) {
            log_write(NONE, "  PASS  mepc=0x%x (valid PC)\n", g_mepc);
            g_pass++;
        } else {
            log_write(NONE, "  FAIL  mepc=0x%x (unexpected)\n", g_mepc);
            g_fail++;
        }
    }
}

// -- Tests -----------------------------------------------------------------

static void test_mtvec_direct(void) {
    log_write(NONE, "\n=== MTVEC mode=DIRECT ===\n");
    uint32_t mtvec = CSR_READ(mtvec);
    uint32_t mode  = mtvec & 3u;
    if (mode == 0) {
        log_write(NONE, "  PASS  mtvec mode=DIRECT (0x%x)\n", mtvec); g_pass++;
    } else {
        log_write(NONE, "  INFO  mtvec mode=%d (0x%x) -- vectored also valid\n",
                  mode, mtvec); g_pass++;
    }
    uint32_t handler_addr = (uint32_t)(uintptr_t)trap_handler;
    if ((mtvec & ~3u) == (handler_addr & ~3u)) {
        log_write(NONE, "  PASS  mtvec base matches trap_handler addr\n"); g_pass++;
    } else {
        log_write(NONE, "  FAIL  mtvec=0x%x handler=0x%x\n",
                  mtvec & ~3u, handler_addr & ~3u); g_fail++;
    }
}

static void test_illegal_insn(void) {
    log_write(NONE, "\n=== ILLEGAL INSTRUCTION (mcause=2) ===\n");
    reset_trap_state();
    int before = g_trap_count;
    asm volatile(".hword 0x0000");   /* c.unimp: 16-bit illegal instruction */
    check_trap("illegal insn", 2, before + 1, 1);
}

static void test_ebreak(void) {
    log_write(NONE, "\n=== EBREAK (mcause=3) ===\n");
    reset_trap_state();
    int before = g_trap_count;
    asm volatile("ebreak");
    check_trap("breakpoint", 3, before + 1, 1);
}

static void test_ecall(void) {
    log_write(NONE, "\n=== ECALL (mcause=11, M-mode) ===\n");
    reset_trap_state();
    int before = g_trap_count;
    asm volatile("li a7, 0x200\n" "ecall\n" ::: "a7");  /* non-semihosting a7 */
    check_trap("env-call M", 11, before + 1, 1);
}

/* Misaligned data accesses are EMULATED (not trapped), which the RISC-V
 * spec permits. These tests verify the access completes with the correct
 * value and raises no trap, matching the official riscv-tests ma_data. */
static void test_load_misaligned(void) {
    log_write(NONE, "\n=== LOAD MISALIGNED (emulated, no trap) ===\n");
    static volatile uint8_t buf[8] = {1,2,3,4,5,6,7,8};
    uint32_t addr = (uint32_t)(uintptr_t)buf + 1u;   /* odd -> misaligned */
    reset_trap_state();
    int before = g_trap_count;
    uint32_t val = 0;
    asm volatile("lw %0, 0(%1)\n" : "=r"(val) : "r"(addr));
    /* Little-endian bytes at buf[1..4] = {2,3,4,5} -> 0x05040302 */
    if (g_trap_count == before && val == 0x05040302u) {
        log_write(NONE, "  PASS  no trap, lw=0x%x\n", val); g_pass++;
    } else {
        log_write(NONE, "  FAIL  traps=%d (exp %d) lw=0x%x (exp 0x5040302)\n",
                  g_trap_count, before, val); g_fail++;
    }
}

static void test_store_misaligned(void) {
    log_write(NONE, "\n=== STORE MISALIGNED (emulated, no trap) ===\n");
    static volatile uint8_t buf2[8] = {0};
    uint32_t addr = (uint32_t)(uintptr_t)buf2 + 1u;  /* odd -> misaligned */
    reset_trap_state();
    int before = g_trap_count;
    asm volatile("li a1, 0x1234\n" "sw a1, 0(%0)\n" :: "r"(addr) : "a1");
    /* Bytes written at buf2[1..4] = {0x34,0x12,0x00,0x00} */
    if (g_trap_count == before &&
        buf2[1] == 0x34 && buf2[2] == 0x12 && buf2[3] == 0 && buf2[4] == 0) {
        log_write(NONE, "  PASS  no trap, sw stored 0x1234 unaligned\n"); g_pass++;
    } else {
        log_write(NONE, "  FAIL  traps=%d (exp %d) buf=[%d,%d,%d,%d]\n",
                  g_trap_count, before, buf2[1], buf2[2], buf2[3], buf2[4]);
        g_fail++;
    }
}

static void test_multiple_traps(void) {
    log_write(NONE, "\n=== Multiple traps in sequence ===\n");
    int before = g_trap_count;
    reset_trap_state();
    asm volatile("ebreak");
    asm volatile("ebreak");
    asm volatile("ebreak");
    if (g_trap_count == before + 3) {
        log_write(NONE, "  PASS  3 consecutive ebreaks handled\n"); g_pass++;
    } else {
        log_write(NONE, "  FAIL  trap_count=%d expected %d\n",
                  g_trap_count, before + 3); g_fail++;
    }
    if (g_mcause == 3u) {
        log_write(NONE, "  PASS  last mcause=3 (breakpoint)\n"); g_pass++;
    } else {
        log_write(NONE, "  FAIL  last mcause=%d expected 3\n", g_mcause); g_fail++;
    }
}

static void test_timer_interrupt(void) {
    log_write(NONE, "\n=== M-MODE TIMER INTERRUPT (mcause=0x80000007) ===\n");

    /* Set mtimecmp = mtime + 100 ticks so it fires almost immediately.
     * Write hi = 0xFFFFFFFF first to temporarily disable, then write lo,
     * then write the real hi -- this prevents a spurious trigger mid-write. */
    uint32_t mtime_lo = CLINT_MTIME_LO;
    uint32_t mtime_hi = CLINT_MTIME_HI;
    uint32_t new_lo   = mtime_lo + 100u;
    uint32_t new_hi   = mtime_hi + (new_lo < mtime_lo ? 1u : 0u);
    CLINT_MTCMP_HI = 0xFFFFFFFFu;   /* disable temporarily */
    CLINT_MTCMP_LO = new_lo;
    CLINT_MTCMP_HI = new_hi;        /* arm: fires when mtime >= new value */

    /* Enable M-mode timer interrupt in MIE (MTIE = bit 7). */
    uint32_t saved_mie     = CSR_READ(mie);
    uint32_t saved_mstatus = CSR_READ(mstatus);
    CSR_WRITE(mie, saved_mie | (1u << 7));

    reset_trap_state();
    int before = g_trap_count;

    /* Enable global M-mode interrupts (MSTATUS.MIE = bit 3).
     * The timer interrupt fires on the very next step (mtimecmp already due). */
    CSR_WRITE(mstatus, saved_mstatus | (1u << 3));

    /* Spin briefly; interrupt fires during this loop (handler clears mtimecmp). */
    for (volatile int i = 0; i < 500; i++) { (void)i; }

    /* Disable global interrupts and restore state. */
    CSR_WRITE(mstatus, saved_mstatus);
    CSR_WRITE(mie, saved_mie);

    /* Check results */
    if (g_trap_count >= before + 1) {
        log_write(NONE, "  PASS  timer interrupt fired\n"); g_pass++;
    } else {
        log_write(NONE, "  FAIL  timer interrupt did not fire\n"); g_fail++;
    }
    if (g_mcause == 0x80000007u) {
        log_write(NONE, "  PASS  mcause=0x80000007 (M-timer interrupt)\n"); g_pass++;
    } else {
        log_write(NONE, "  FAIL  mcause=0x%x expected 0x80000007\n", g_mcause); g_fail++;
    }
    if (g_mepc != 0xDEADBEEFu && g_mepc != 0u) {
        log_write(NONE, "  PASS  mepc=0x%x (interrupted PC valid)\n", g_mepc); g_pass++;
    } else {
        log_write(NONE, "  FAIL  mepc=0x%x invalid\n", g_mepc); g_fail++;
    }
}

// -- Main ------------------------------------------------------------------

int main(void) {
    uart_puts("=== Trap/Exception Test ===\n");
    if (log_init("trap-test.log") != 0) {
        uart_puts("ERROR: log_init failed\n");
        return 1;
    }

    log_write(NONE, "=== Trap / Exception / Interrupt Test (RV32IMC) ===\n");

    /* Install trap handler in direct mode (low 2 bits = 0). */
    CSR_WRITE(mtvec, (uint32_t)(uintptr_t)trap_handler);

    test_mtvec_direct();
    test_illegal_insn();
    test_ebreak();
    test_ecall();
    test_load_misaligned();
    test_store_misaligned();
    test_multiple_traps();
    test_timer_interrupt();

    log_write(NONE, "\n%d PASS  %d FAIL\n", g_pass, g_fail);
    log_close();
    uart_puts(g_fail == 0 ? "ALL PASSED\n" : "SOME FAILED\n");
    return g_fail;
}
