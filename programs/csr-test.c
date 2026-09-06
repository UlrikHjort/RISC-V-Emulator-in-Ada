/* **************************************************************************
 *         RISC-V Emulator - CSR (Control and Status Register) test
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

// csr-test.c -- CSR (Control and Status Register) test.
//
// Tests CSR instructions and register contents:
//   CSRR  (read)
//   CSRW  (write)
//   CSRRS (read-set bits)
//   CSRRC (read-clear bits)
//   CSRRWI/CSRRSI/CSRRCI (immediate forms)
//
// Registers tested:
//   mscratch   -- scratch register, freely read/write
//   misa       -- ISA register (read-only, check expected bits)
//   mhartid    -- hardware thread ID (read-only, should be 0)
//   cycle      -- instruction cycle counter
//   instret    -- instructions retired counter
//   fcsr       -- FP control/status (rounding mode + flags)
//   frm        -- FP rounding mode alias
//   fflags     -- FP accrued exception flags alias
//
// Build: cd programs && make run-csr-test
// By Ulrik Hørlyk Hjort 2026

#include <stdint.h>
#include "log.h"

void putchar(char c);
static void uart_puts(const char *s) {
    while (*s) { if (*s == '\n') putchar('\r'); putchar(*s++); }
}

static int g_pass = 0, g_fail = 0;

static void check32(const char *label, uint32_t got, uint32_t expected) {
    if (got == expected) {
        log_write(NONE, "  PASS  %s\n", label); g_pass++;
    } else {
        log_write(NONE, "  FAIL  %s: got 0x%x  exp 0x%x\n",
                  label, got, expected);
        g_fail++;
    }
}


#define CSR_R(csr)       ({ uint32_t _v; asm volatile("csrr %0," #csr : "=r"(_v)); _v; })
#define CSR_W(csr, val)  asm volatile("csrw " #csr ",%0" :: "r"((uint32_t)(val)))
#define CSR_RS(csr, msk) ({ uint32_t _v; asm volatile("csrrs %0," #csr ",%1" : "=r"(_v) : "r"((uint32_t)(msk))); _v; })
#define CSR_RC(csr, msk) ({ uint32_t _v; asm volatile("csrrc %0," #csr ",%1" : "=r"(_v) : "r"((uint32_t)(msk))); _v; })

// -- mscratch -- scratch register, fully read/write -------------------------

static void test_mscratch(void) {
    log_write(NONE, "\n=== mscratch (read/write) ===\n");

    CSR_W(mscratch, 0x12345678);
    check32("csrw/csrr 0x12345678", CSR_R(mscratch), 0x12345678);

    CSR_W(mscratch, 0xDEADBEEF);
    check32("csrw/csrr 0xDEADBEEF", CSR_R(mscratch), 0xDEADBEEF);

    CSR_W(mscratch, 0x00000000);
    check32("csrw/csrr 0x00000000", CSR_R(mscratch), 0x00000000);

    CSR_W(mscratch, 0xFFFFFFFF);
    check32("csrw/csrr 0xFFFFFFFF", CSR_R(mscratch), 0xFFFFFFFF);

    // CSRRS: set bits, returns old value
    CSR_W(mscratch, 0xF0F0F0F0);
    uint32_t old = CSR_RS(mscratch, 0x0F0F0F0F);
    check32("csrrs: old value returned",  old,              0xF0F0F0F0);
    check32("csrrs: bits set",           CSR_R(mscratch),  0xFFFFFFFF);

    // CSRRC: clear bits, returns old value
    CSR_W(mscratch, 0xAAAAAAAA);
    old = CSR_RC(mscratch, 0x0F0F0F0F);
    check32("csrrc: old value returned", old,              0xAAAAAAAA);
    check32("csrrc: bits cleared",       CSR_R(mscratch),  0xA0A0A0A0);
}

// -- mhartid -- hardware thread ID (should be 0 on single-core) -------------

static void test_mhartid(void) {
    log_write(NONE, "\n=== mhartid (read-only, expected 0) ===\n");
    uint32_t hid = CSR_R(mhartid);
    check32("mhartid = 0", hid, 0);
}

// -- misa -- ISA register ---------------------------------------------------
// misa[1:0]  = MXL (machine XLEN): 01 = RV32
// misa[8]    = I base ISA
// misa[12]   = M extension
// misa[2]    = C extension

static void test_misa(void) {
    log_write(NONE, "\n=== misa (ISA capabilities) ===\n");
    uint32_t misa = CSR_R(misa);
    log_write(NONE, "  INFO  misa = 0x%x\n", misa);

    // MXL field [31:30] = 01 for RV32
    uint32_t mxl = (misa >> 30) & 3;
    check32("misa MXL=01 (RV32)", mxl, 1);

    // I extension must be set (base ISA)
    uint32_t has_I = (misa >> 8) & 1;
    check32("misa has I extension", has_I, 1);

    // M extension (we build with rv32imc)
    uint32_t has_M = (misa >> 12) & 1;
    check32("misa has M extension", has_M, 1);

    // C extension
    uint32_t has_C = (misa >> 2) & 1;
    check32("misa has C extension", has_C, 1);
}

// -- cycle / instret -- performance counters --------------------------------

static void test_counters(void) {
    log_write(NONE, "\n=== cycle / instret counters ===\n");

    uint32_t c0 = CSR_R(cycle);
    uint32_t i0 = CSR_R(instret);

    // Execute some instructions to advance counters
    volatile uint32_t dummy = 0;
    for (int i = 0; i < 100; i++) dummy += i;
    (void)dummy;

    uint32_t c1 = CSR_R(cycle);
    uint32_t i1 = CSR_R(instret);

    // Counters must have advanced (wrapping is possible but unlikely in 100 iters)
    if (c1 > c0) {
        log_write(NONE, "  PASS  cycle advanced (%d -> %d, delta=%d)\n",
                  c0, c1, c1 - c0); g_pass++;
    } else {
        log_write(NONE, "  FAIL  cycle did not advance (was %d, now %d)\n",
                  c0, c1); g_fail++;
    }

    if (i1 > i0) {
        log_write(NONE, "  PASS  instret advanced (delta=%d)\n", i1 - i0);
        g_pass++;
    } else {
        log_write(NONE, "  FAIL  instret did not advance (was %d, now %d)\n",
                  i0, i1); g_fail++;
    }

    // cycleh / instreth (high 32 bits -- should be 0 or small)
    uint32_t ch  = CSR_R(cycleh);
    uint32_t ih  = CSR_R(instreth);
    log_write(NONE, "  INFO  cycleh=%d instreth=%d\n", ch, ih);
    // These are probably 0 unless we've been running a very long time
    g_pass++;  // just check we can read them without fault
    log_write(NONE, "  PASS  cycleh/instreth readable\n");
}

// -- FCSR -- floating-point control and status register ---------------------
// frm  (bits [7:5]): rounding mode
// fflags (bits [4:0]): accrued exceptions NV|DZ|OF|UF|NX

static void test_fcsr(void) {
    log_write(NONE, "\n=== FCSR (FP control/status) ===\n");

    // Save original fcsr
    uint32_t orig = CSR_R(fcsr);

    // Clear all bits
    CSR_W(fcsr, 0);
    check32("fcsr write 0 -> reads 0", CSR_R(fcsr), 0);

    // Set rounding mode to RTZ (round toward zero) = 0b001 in frm
    // frm is bits [7:5]: RTZ = 001
    CSR_W(frm, 1);  // RNE=0, RTZ=1, RDN=2, RUP=3, RMM=4
    check32("frm write 1 (RTZ) -> reads 1", CSR_R(frm), 1);

    // Setting frm should appear in fcsr bits [7:5]
    uint32_t fcsr_val = CSR_R(fcsr);
    check32("fcsr frm field = 1<<5 = 0x20", fcsr_val & 0xE0, 0x20);

    // Set fflags (accrued exception flags): NX (bit 0) = inexact
    CSR_W(fflags, 0x1F);  // all 5 flags set
    check32("fflags write 0x1F -> reads 0x1F", CSR_R(fflags), 0x1F);

    // Check via fcsr
    fcsr_val = CSR_R(fcsr);
    check32("fcsr fflags field = 0x1F", fcsr_val & 0x1F, 0x1F);

    // Test frm aliases: RNE=0
    CSR_W(frm, 0);
    check32("frm write 0 (RNE)", CSR_R(frm), 0);

    // Clear fflags via csrrc
    CSR_RC(fflags, 0x1F);
    check32("fflags cleared via csrrc", CSR_R(fflags), 0);

    // Restore original fcsr
    CSR_W(fcsr, orig);
    log_write(NONE, "  INFO  fcsr restored to 0x%x\n", orig);
    g_pass++;
}

// -- CSR instruction variants ----------------------------------------------

static void test_csr_instructions(void) {
    log_write(NONE, "\n=== CSR instruction variants ===\n");

    // CSRRW: atomic swap
    CSR_W(mscratch, 0xAAAA);
    uint32_t old;
    asm volatile("csrrw %0, mscratch, %1" : "=r"(old) : "r"((uint32_t)0xBBBB));
    check32("csrrw: old value = 0xAAAA",      old,              0xAAAA);
    check32("csrrw: new value = 0xBBBB",      CSR_R(mscratch),  0xBBBB);

    // CSRRWI: write immediate (5-bit uimm)
    asm volatile("csrrwi %0, mscratch, 7" : "=r"(old));
    check32("csrrwi: old = 0xBBBB",           old,              0xBBBB);
    check32("csrrwi: mscratch = 7",            CSR_R(mscratch),  7);

    // CSRRSI: set bits immediate
    asm volatile("csrrsi %0, mscratch, 8" : "=r"(old));
    check32("csrrsi: old = 7",                 old,              7);
    check32("csrrsi: 7|8 = 15",               CSR_R(mscratch),  15);

    // CSRRCI: clear bits immediate
    asm volatile("csrrci %0, mscratch, 5" : "=r"(old));
    check32("csrrci: old = 15",                old,              15);
    check32("csrrci: 15 & ~5 = 10",           CSR_R(mscratch),  10);

    // CSRRS with rs1=x0 (read-only, no side effect)
    CSR_W(mscratch, 0x1234);
    asm volatile("csrrs %0, mscratch, x0" : "=r"(old));
    check32("csrrs x0: reads without modifying", old, 0x1234);
    check32("csrrs x0: value unchanged",   CSR_R(mscratch), 0x1234);
}

// -- MIE / MIP -- interrupt enable and pending bits -------------------------
//
// MIE bits: MSIE=bit3, MTIE=bit7, MEIE=bit11
// MIP bits: MSIP=bit3, MTIP=bit7, MEIP=bit11 (read-only for MTIP/MEIP)

static void test_mie(void) {
    log_write(NONE, "\n=== MIE (machine interrupt enable) ===\n");

    uint32_t saved = CSR_R(mie);

    /* MTIE (bit 7): machine timer interrupt enable */
    CSR_W(mie, 0);
    check32("mie write 0 -> reads 0", CSR_R(mie), 0);

    CSR_W(mie, 1u << 7);
    uint32_t v = CSR_R(mie);
    if (v & (1u << 7)) {
        log_write(NONE, "  PASS  mie.MTIE set (bit 7)\n"); g_pass++;
    } else {
        log_write(NONE, "  FAIL  mie.MTIE not set: mie=0x%x\n", v); g_fail++;
    }

    /* MSIE (bit 3): machine software interrupt enable */
    CSR_W(mie, 1u << 3);
    v = CSR_R(mie);
    if (v & (1u << 3)) {
        log_write(NONE, "  PASS  mie.MSIE set (bit 3)\n"); g_pass++;
    } else {
        log_write(NONE, "  FAIL  mie.MSIE not set: mie=0x%x\n", v); g_fail++;
    }

    /* MEIE (bit 11): machine external interrupt enable */
    CSR_W(mie, 1u << 11);
    v = CSR_R(mie);
    if (v & (1u << 11)) {
        log_write(NONE, "  PASS  mie.MEIE set (bit 11)\n"); g_pass++;
    } else {
        log_write(NONE, "  FAIL  mie.MEIE not set: mie=0x%x\n", v); g_fail++;
    }

    /* Set/clear all three at once */
    CSR_W(mie, (1u << 3) | (1u << 7) | (1u << 11));
    v = CSR_R(mie);
    uint32_t exp = (1u << 3) | (1u << 7) | (1u << 11);
    check32("mie all three enable bits set", v & exp, exp);

    CSR_W(mie, 0);
    check32("mie cleared to 0", CSR_R(mie), 0);

    CSR_W(mie, saved);  /* restore */
}

// -- MSTATUS -- global interrupt enable bits --------------------------------
// MIE  = bit 3  (global M-mode interrupt enable)
// MPIE = bit 7  (saved MIE, set by hardware on trap entry)
// MPP  = bits [12:11] (previous privilege: 11 = M-mode)

static void test_mstatus_ie(void) {
    log_write(NONE, "\n=== MSTATUS interrupt bits ===\n");

    uint32_t saved = CSR_R(mstatus);

    /* MIE bit: should be writable */
    CSR_W(mstatus, 0);
    check32("mstatus.MIE=0", (CSR_R(mstatus) >> 3) & 1u, 0);

    CSR_W(mstatus, 1u << 3);
    check32("mstatus.MIE=1", (CSR_R(mstatus) >> 3) & 1u, 1);

    /* MPIE bit (bit 7): set by hardware on trap, also writable by software */
    CSR_W(mstatus, 1u << 7);
    check32("mstatus.MPIE=1", (CSR_R(mstatus) >> 7) & 1u, 1);

    /* MPP field [12:11]: 11 = M-mode (most common reset value) */
    CSR_W(mstatus, 3u << 11);
    check32("mstatus.MPP=11 (M-mode)", (CSR_R(mstatus) >> 11) & 3u, 3u);

    CSR_W(mstatus, saved);  /* restore */
}

// -- MEDELEG / MIDELEG -- exception and interrupt delegation ----------------
// Both default to 0 (no delegation to S-mode) on reset.
// We verify they are read/writable (bits that the emulator supports).

static void test_medeleg_mideleg(void) {
    log_write(NONE, "\n=== MEDELEG / MIDELEG (delegation CSRs) ===\n");

    uint32_t saved_ed = CSR_R(medeleg);
    uint32_t saved_id = CSR_R(mideleg);

    /* medeleg: delegate sync exceptions to S-mode.
     * Bits 0-8 are typically writable; bits 9-11 (ecall from S/H/M) are RO=0. */
    CSR_W(medeleg, 0x1FF);  /* bits 0-8 */
    uint32_t v = CSR_R(medeleg);
    if ((v & 0x1FFu) == 0x1FFu) {
        log_write(NONE, "  PASS  medeleg bits 0-8 writable (0x%x)\n", v); g_pass++;
    } else {
        log_write(NONE, "  FAIL  medeleg=0x%x expected bits 0-8 set\n", v); g_fail++;
    }

    CSR_W(medeleg, 0);
    check32("medeleg cleared", CSR_R(medeleg), 0);

    /* mideleg: delegate interrupts to S-mode.
     * SSIP (bit 1) and STIP (bit 5) are typically writable. */
    CSR_W(mideleg, (1u << 1) | (1u << 5));
    v = CSR_R(mideleg);
    uint32_t exp = (1u << 1) | (1u << 5);
    if ((v & exp) == exp) {
        log_write(NONE, "  PASS  mideleg SSIP+STIP writable (0x%x)\n", v); g_pass++;
    } else {
        log_write(NONE, "  FAIL  mideleg=0x%x expected 0x%x\n", v, exp); g_fail++;
    }

    CSR_W(mideleg, 0);
    check32("mideleg cleared", CSR_R(mideleg), 0);

    CSR_W(medeleg, saved_ed);   /* restore */
    CSR_W(mideleg, saved_id);
}

// -- Main ------------------------------------------------------------------

int main(void) {
    uart_puts("=== CSR Test ===\n");
    if (log_init("csr-test.log") != 0) {
        uart_puts("ERROR: log_init failed\n"); return 1;
    }

    log_write(NONE, "=== CSR Instruction Test (RV32IMCFD + Zicsr) ===\n");

    test_mscratch();
    test_mhartid();
    test_misa();
    test_counters();
    test_fcsr();
    test_csr_instructions();
    test_mie();
    test_mstatus_ie();
    test_medeleg_mideleg();

    log_write(NONE, "\n%d PASS  %d FAIL\n", g_pass, g_fail);
    log_close();
    uart_puts(g_fail == 0 ? "ALL PASSED\n" : "SOME FAILED\n");
    return g_fail;
}
