/* **************************************************************************
 *               RISC-V Emulator - Zicond Extension Test
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
 * **************************************************************************
 * Tests both Zicond instructions on RV64:
 *
 *   czero.eqz  rd, rs1, rs2  --  rd = (rs2 == 0) ? 0 : rs1
 *   czero.nez  rd, rs1, rs2  --  rd = (rs2 != 0) ? 0 : rs1
 *
 * These allow branch-free conditional selection (conditional zero-out).
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
/* Inline-asm wrappers                                                */
/* ------------------------------------------------------------------ */

static uint64_t czero_eqz(uint64_t rs1, uint64_t rs2)
{
    uint64_t rd;
    __asm__ volatile("czero.eqz %0, %1, %2"
                     : "=r"(rd) : "r"(rs1), "r"(rs2));
    return rd;
}

static uint64_t czero_nez(uint64_t rs1, uint64_t rs2)
{
    uint64_t rd;
    __asm__ volatile("czero.nez %0, %1, %2"
                     : "=r"(rd) : "r"(rs1), "r"(rs2));
    return rd;
}

/* ------------------------------------------------------------------ */

int main(void)
{
    log_init("rv64-zicond-test.log");
    log_write(NONE, "RV64 Zicond Extension Test\n\n");

    /* ---- czero.eqz: rd = (rs2 == 0) ? 0 : rs1 ---- */
    log_write(NONE, "--- czero.eqz ---\n");

    /* rs2 == 0  -> result must be 0 (zero out rs1) */
    chk("eqz: rs2=0 -> 0",          czero_eqz(0xDEADBEEF, 0) == 0);
    chk("eqz: rs2=0 rs1=0 -> 0",    czero_eqz(0, 0)           == 0);

    /* rs2 != 0  -> result is rs1 unchanged */
    chk("eqz: rs2=1 -> rs1",        czero_eqz(0xDEADBEEF, 1)  == 0xDEADBEEFULL);
    chk("eqz: rs2=neg -> rs1",      czero_eqz(42, (uint64_t)(-1LL)) == 42);

    /* 64-bit values */
    chk("eqz: 64b rs2=0",
        czero_eqz(0xCAFEBABEDEAD0001ULL, 0) == 0);
    chk("eqz: 64b rs2!=0",
        czero_eqz(0xCAFEBABEDEAD0001ULL, 0x8000000000000000ULL) ==
        0xCAFEBABEDEAD0001ULL);

    /* rs1 == 0, rs2 != 0 -> result is rs1 = 0 */
    chk("eqz: rs1=0 rs2!=0 -> 0",   czero_eqz(0, 99) == 0);

    /* ---- czero.nez: rd = (rs2 != 0) ? 0 : rs1 ---- */
    log_write(NONE, "--- czero.nez ---\n");

    /* rs2 != 0  -> result must be 0 */
    chk("nez: rs2=1 -> 0",          czero_nez(0xDEADBEEF, 1)  == 0);
    chk("nez: rs2=neg -> 0",        czero_nez(42, (uint64_t)(-1LL)) == 0);

    /* rs2 == 0  -> result is rs1 unchanged */
    chk("nez: rs2=0 -> rs1",        czero_nez(0xDEADBEEF, 0)  == 0xDEADBEEFULL);
    chk("nez: rs2=0 rs1=0 -> 0",    czero_nez(0, 0)            == 0);

    /* 64-bit values */
    chk("nez: 64b rs2!=0",
        czero_nez(0xCAFEBABEDEAD0001ULL, 5) == 0);
    chk("nez: 64b rs2=0",
        czero_nez(0xCAFEBABEDEAD0001ULL, 0) ==
        0xCAFEBABEDEAD0001ULL);

    /* rs1 == 0, rs2 == 0 -> result is rs1 = 0 */
    chk("nez: rs1=0 rs2=0 -> 0",    czero_nez(0, 0) == 0);

    /* ---- Combined: conditional select (cmov pattern) ---- */
    log_write(NONE, "--- conditional-select pattern ---\n");
    /*
     * Select a if cond != 0, else b:
     *   czero.eqz tmp1, a, cond    -- tmp1 = (cond==0) ? 0 : a  -> keeps a when cond!=0
     *   czero.nez tmp2, b, cond    -- tmp2 = (cond!=0) ? 0 : b  -> keeps b when cond==0
     *   or rd, tmp1, tmp2
     */
    uint64_t a = 0xAAAAAAAA, b = 0xBBBBBBBB;
    uint64_t cond_t = 1, cond_f = 0;

    /* cond=1: select a */
    uint64_t sel_a = czero_eqz(a, cond_t) | czero_nez(b, cond_t);
    chk("cmov cond=1 -> a",  sel_a == a);

    /* cond=0: select b */
    uint64_t sel_b = czero_eqz(a, cond_f) | czero_nez(b, cond_f);
    chk("cmov cond=0 -> b",  sel_b == b);

    log_write(NONE, "\n%d PASS  %d FAIL\n", g_pass, g_fail);
    log_close();
    return g_fail;
}
