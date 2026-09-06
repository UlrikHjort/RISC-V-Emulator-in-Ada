/* **************************************************************************
 *               RISC-V Emulator - Tests for additional CSRs:
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
 * csr-more-test.c -- Tests for additional CSRs:
 *   mcountinhibit (0x320), mcounteren (0x306), scounteren (0x106),
 *   HPM counter stubs (mhpmcounter3, mhpmevent3),
 *   and RO machine info registers (mhartid, mvendorid, marchid, mimpid).
 *
 * By Ulrik Hørlyk Hjort 2026
 */
#include <stdint.h>
#include "log.h"

static int g_pass = 0, g_fail = 0;

static void chk(const char *label, int ok) {
    if (ok) { log_write(NONE, "PASS %s\n", label); g_pass++; }
    else     { log_write(NONE, "FAIL %s\n", label); g_fail++; }
}

/* ------------------------------------------------------------------ */
/* CSR read/write helpers using inline asm                             */
/* ------------------------------------------------------------------ */

static inline uint32_t csr_read(uint32_t csr_num) {
    uint32_t val;
    /* We can't use a variable as CSR operand directly in GCC inline asm
       for RISC-V, so we use csrrs with a switch on common CSRs. */
    (void)csr_num;
    /* Unused -- each test below reads via named pseudo-ops */
    return val = 0;
}

#define READ_CSR(name)  ({ uint32_t _v; asm volatile("csrr %0, " #name : "=r"(_v)); _v; })
#define WRITE_CSR(name, val) asm volatile("csrw " #name ", %0" :: "r"((uint32_t)(val)))
#define SET_CSR(name, val)   asm volatile("csrs " #name ", %0" :: "r"((uint32_t)(val)))
#define CLEAR_CSR(name, val) asm volatile("csrc " #name ", %0" :: "r"((uint32_t)(val)))

int main(void) {
    log_init("csr-more-test.log");

    /* ---------------------------------------------------------------- */
    /* 1. Read-only machine info registers must read 0 on this emulator */
    /* ---------------------------------------------------------------- */
    chk("mhartid=0",    READ_CSR(mhartid)   == 0);
    chk("mvendorid=0",  READ_CSR(mvendorid)  == 0);
    chk("marchid=0",    READ_CSR(marchid)    == 0);
    chk("mimpid=0",     READ_CSR(mimpid)     == 0);

    /* ---------------------------------------------------------------- */
    /* 2. mcounteren / scounteren round-trip                            */
    /* ---------------------------------------------------------------- */
    WRITE_CSR(mcounteren, 0x5);          /* set bits 0 and 2 */
    chk("mcounteren=0x5", READ_CSR(mcounteren) == 0x5);
    WRITE_CSR(mcounteren, 0);            /* clear */
    chk("mcounteren=0",   READ_CSR(mcounteren) == 0);

    WRITE_CSR(scounteren, 0x7);
    chk("scounteren=0x7", READ_CSR(scounteren) == 0x7);
    WRITE_CSR(scounteren, 0);
    chk("scounteren=0",   READ_CSR(scounteren) == 0);

    /* ---------------------------------------------------------------- */
    /* 3. HPM counter stubs read 0                                      */
    /* ---------------------------------------------------------------- */
    chk("mhpmcounter3=0",  READ_CSR(mhpmcounter3)  == 0);
    chk("mhpmevent3=0",    READ_CSR(mhpmevent3)     == 0);

    /* ---------------------------------------------------------------- */
    /* 4. mcountinhibit -- inhibit minstret (bit 2) and verify           */
    /* ---------------------------------------------------------------- */

    /* Inhibit instret counter (bit 2 = IR) */
    WRITE_CSR(mcountinhibit, 0x4);
    chk("mcountinhibit=4", READ_CSR(mcountinhibit) == 0x4);

    /* Execute several instructions while inhibited */
    uint32_t ir1 = READ_CSR(minstret);
    uint32_t ir2 = READ_CSR(minstret);
    uint32_t ir3 = READ_CSR(minstret);

    /* Counter must not advance while inhibited -- all three reads should
       return the same value (or very close; the csrr itself may or may
       not count depending on strict spec interpretation, but our emulator
       checks the inhibit flag *before* incrementing). */
    chk("instret_inhibited", ir1 == ir2 && ir2 == ir3);

    /* Re-enable instret counting */
    WRITE_CSR(mcountinhibit, 0x0);
    chk("mcountinhibit=0", READ_CSR(mcountinhibit) == 0x0);

    /* Now the counter should advance again */
    uint32_t ir4 = READ_CSR(minstret);
    uint32_t ir5 = READ_CSR(minstret);
    chk("instret_resumed", ir5 > ir4);

    /* ---------------------------------------------------------------- */
    /* 5. mcountinhibit -- inhibit mcycle (bit 0) and verify             */
    /* ---------------------------------------------------------------- */

    WRITE_CSR(mcountinhibit, 0x1);   /* CY inhibit */

    uint32_t cy1 = READ_CSR(mcycle);
    uint32_t cy2 = READ_CSR(mcycle);

    chk("cycle_inhibited", cy1 == cy2);

    WRITE_CSR(mcountinhibit, 0x0);

    uint32_t cy3 = READ_CSR(mcycle);
    uint32_t cy4 = READ_CSR(mcycle);
    chk("cycle_resumed", cy4 > cy3);

    /* ---------------------------------------------------------------- */
    /* Done                                                             */
    /* ---------------------------------------------------------------- */
    log_write(NONE, "\n%d PASS  %d FAIL\n", g_pass, g_fail);
    log_close();
    return g_fail ? 1 : 0;
}
