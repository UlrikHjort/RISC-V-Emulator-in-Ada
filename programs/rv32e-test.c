/* **************************************************************************
 *       RISC-V Emulator - Verify RV32E (16-register subset) support
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
 * rv32e-test.c -- Verify RV32E (16-register subset) support
 *
 * Checks MISA.E is set, MISA.I is clear, MISA.V is clear.
 * All arithmetic uses only x0-x15 (a0-a5, t0-t4) which is
 * the portable subset for both RV32I and RV32E programs.
 *
 * Run with: bin/riscv_emulator --machine qemu-virt --rv32e <elf>
 *
 * By Ulrik Hørlyk Hjort 2026
 */
#include <stdint.h>
#include "log.h"

static int g_pass = 0, g_fail = 0;

static void chk(const char *label, int ok)
{
    if (ok) { log_write(NONE, "PASS %s\n", label); g_pass++; }
    else    { log_write(NONE, "FAIL %s\n", label); g_fail++; }
}

static uint32_t read_misa(void)
{
    uint32_t v;
    asm volatile("csrr %0, misa" : "=r"(v));
    return v;
}

int main(void)
{
    uint32_t misa;

    log_init("rv32e-test.log");
    log_write(NONE, "=== RV32E Test ===\n");

    misa = read_misa();
    log_write(NONE, "misa = 0x%x\n", misa);

    /* MISA.E  = bit 4 */
    chk("MISA.E set",   (misa >> 4)  & 1);
    /* MISA.I  = bit 8 -- must be clear for RV32E */
    chk("MISA.I clear", !((misa >> 8) & 1));
    /* MISA.V  = bit 21 -- vector not in E profile */
    chk("MISA.V clear", !((misa >> 21) & 1));
    /* MXL     = bits[31:30] = 1 for RV32 */
    chk("MXL=1 (RV32)", (misa >> 30) == 1);

    /* Basic arithmetic using only low registers (x0-x15) */
    volatile uint32_t a = 0xDEAD, b = 0xBEEF;
    chk("add a0/a1", (a + b) == (uint32_t)(0xDEAD + 0xBEEF));
    chk("xor a0/a1", (a ^ b) == (0xDEAD ^ 0xBEEF));

    log_write(NONE, "\n%d PASS  %d FAIL\n", g_pass, g_fail);
    log_close();
    return g_fail ? 1 : 0;
}
