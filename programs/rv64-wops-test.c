/* **************************************************************************
 *               RISC-V Emulator - RV64 W-ops Test
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
 * Exhaustive test of all RV64 W-suffix instructions (32-bit operations
 * on 64-bit registers whose result is sign-extended to 64 bits):
 *
 *   ADDW / ADDIW   SUBW
 *   MULW
 *   DIVW / DIVUW
 *   REMW / REMUW
 *   SLLW / SLLIW
 *   SRLW / SRLIW
 *   SRAW / SRAIW
 *
 * Specifically exercises results where bit 31 is set, verifying that the
 * result stored in the 64-bit destination register has bits 63:32 all 1
 * (negative sign extension).  These cases were broken before the SE32 fix.
 */

#include <stdint.h>
#include "log.h"

static int g_pass = 0, g_fail = 0;

static void chk(const char *label, int ok)
{
    if (ok) { log_write(NONE, "PASS %s\n", label); g_pass++; }
    else     { log_write(NONE, "FAIL %s\n", label); g_fail++; }
}

/* Verify that upper 32 bits of a 64-bit int64 value are the sign-extension
 * of bit 31, i.e. either all-0 (positive) or all-1 (negative). */
static int sext_ok(int64_t v)
{
    uint64_t u = (uint64_t)v;
    uint32_t hi = (uint32_t)(u >> 32);
    uint32_t lo_sign = (u & 0x80000000u) ? 0xFFFFFFFFu : 0u;
    return hi == lo_sign;
}

int main(void)
{
    log_init("rv64-wops-test.log");
    log_write(NONE, "RV64 W-ops Test\n\n");

    /* ------------------------------------------------------------------ */
    log_write(NONE, "--- ADDW / ADDIW ---\n");

    /* Positive result: no sign extension needed */
    volatile int32_t a1 = 3, b1 = 4;
    volatile int64_t r1 = (int64_t)(a1 + b1);
    chk("addw  3+4 = 7",          r1 == 7LL);
    chk("addw  3+4 sext ok",      sext_ok(r1));

    /* Overflow into sign bit: 0x7FFFFFFF + 1 = INT32_MIN sign-extended */
    volatile int32_t a2 = 0x7FFFFFFF;
    volatile int64_t r2 = (int64_t)(a2 + (int32_t)1);
    chk("addiw 0x7FFFFFFF+1 = INT32_MIN",    r2 == (int64_t)0xFFFFFFFF80000000LL);
    chk("addiw 0x7FFFFFFF+1 sext ok",        sext_ok(r2));

    /* Negative result: -1 sign-extended = 0xFFFFFFFFFFFFFFFF */
    volatile int32_t a3 = 0, b3 = -1;
    volatile int64_t r3 = (int64_t)(a3 + b3);
    chk("addw  0+(-1) = -1",       r3 == -1LL);
    chk("addw  0+(-1) sext ok",    sext_ok(r3));

    /* ------------------------------------------------------------------ */
    log_write(NONE, "--- SUBW ---\n");

    /* 0 - 1 = -1 -> 0xFFFFFFFFFFFFFFFF */
    volatile int32_t s1 = 0, s2 = 1;
    volatile int64_t rs = (int64_t)(s1 - s2);
    chk("subw  0-1 = -1",          rs == -1LL);
    chk("subw  0-1 sext ok",       sext_ok(rs));

    /* INT32_MIN - 1 wraps to INT32_MAX */
    volatile int32_t s3 = (int32_t)0x80000000u;   /* INT32_MIN */
    volatile int64_t rs2 = (int64_t)(s3 - (int32_t)1);
    chk("subw  INT32_MIN-1 = INT32_MAX",  rs2 == 0x7FFFFFFFLL);
    chk("subw  INT32_MIN-1 sext ok",      sext_ok(rs2));

    /* ------------------------------------------------------------------ */
    log_write(NONE, "--- MULW ---\n");

    /* Positive */
    volatile int32_t m1 = 6, m2 = 7;
    volatile int64_t rm1 = (int64_t)(m1 * m2);
    chk("mulw  6*7 = 42",          rm1 == 42LL);

    /* Negative result: -3 * 5 = -15 */
    volatile int32_t m3 = -3, m4 = 5;
    volatile int64_t rm2 = (int64_t)(m3 * m4);
    chk("mulw  -3*5 = -15",        rm2 == -15LL);
    chk("mulw  -3*5 sext ok",      sext_ok(rm2));

    /* Negative * negative = positive */
    volatile int32_t m5 = -4, m6 = -4;
    volatile int64_t rm3 = (int64_t)(m5 * m6);
    chk("mulw  -4*-4 = 16",        rm3 == 16LL);

    /* Overflow: 0x80000000 * 2 -> lower 32 bits = 0 */
    volatile int32_t m7 = (int32_t)0x80000000u;
    volatile int64_t rm4 = (int64_t)(m7 * (int32_t)2);
    chk("mulw  INT32_MIN*2 lower32=0",  rm4 == 0LL);

    /* ------------------------------------------------------------------ */
    log_write(NONE, "--- DIVW / DIVUW ---\n");

    /* Signed: positive quotient */
    volatile int32_t d1 = 100, d2 = 7;
    volatile int64_t rd1 = (int64_t)(d1 / d2);
    chk("divw  100/7 = 14",        rd1 == 14LL);

    /* Signed: negative numerator */
    volatile int32_t d3 = -100, d4 = 7;
    volatile int64_t rd2 = (int64_t)(d3 / d4);
    chk("divw  -100/7 = -14",      rd2 == -14LL);
    chk("divw  -100/7 sext ok",    sext_ok(rd2));

    /* Signed: negative denominator */
    volatile int32_t d5 = 100, d6 = -7;
    volatile int64_t rd3 = (int64_t)(d5 / d6);
    chk("divw  100/-7 = -14",      rd3 == -14LL);
    chk("divw  100/-7 sext ok",    sext_ok(rd3));

    /* Signed: INT32_MIN / -1 overflow -> INT32_MIN */
    volatile int32_t d7 = (int32_t)0x80000000u, d8 = -1;
    volatile int64_t rd4 = (int64_t)(d7 / d8);
    chk("divw  INT32_MIN/-1 = INT32_MIN (overflow)",
        rd4 == (int64_t)0xFFFFFFFF80000000LL);

    /* Unsigned: large value */
    volatile uint32_t ud1 = 0xFFFFFFFEu, ud2 = 2u;
    volatile int64_t rud1 = (int64_t)(int32_t)(ud1 / ud2);
    chk("divuw 0xFFFFFFFE/2 = 0x7FFFFFFF",  rud1 == 0x7FFFFFFFLL);

    /* ------------------------------------------------------------------ */
    log_write(NONE, "--- REMW / REMUW ---\n");

    /* Positive remainder */
    volatile int32_t r1a = 100, r1b = 7;
    volatile int64_t rr1 = (int64_t)(r1a % r1b);
    chk("remw  100%7 = 2",         rr1 == 2LL);

    /* Negative numerator: remainder has sign of dividend */
    volatile int32_t r2a = -100, r2b = 7;
    volatile int64_t rr2 = (int64_t)(r2a % r2b);
    chk("remw  -100%7 = -2",       rr2 == -2LL);
    chk("remw  -100%7 sext ok",    sext_ok(rr2));

    /* Unsigned remainder */
    volatile uint32_t ur1 = 0xFFFFFFFBu, ur2 = 4u;
    volatile int64_t urr = (int64_t)(int32_t)(ur1 % ur2);
    chk("remuw 0xFFFFFFFB%4 = 3",  urr == 3LL);

    /* ------------------------------------------------------------------ */
    log_write(NONE, "--- SLLW / SLLIW ---\n");

    /* Shift into sign bit: result must be negative when sign-extended */
    volatile int32_t sl1 = 1;
    volatile int64_t rsl1 = (int64_t)(sl1 << 31);
    chk("sllw  1<<31 = INT32_MIN", rsl1 == (int64_t)0xFFFFFFFF80000000LL);
    chk("sllw  1<<31 sext ok",     sext_ok(rsl1));

    volatile int32_t sl2 = 1;
    volatile int64_t rsl2 = (int64_t)(sl2 << 30);
    chk("sllw  1<<30 = 0x40000000",rsl2 == 0x40000000LL);
    chk("sllw  1<<30 sext ok",     sext_ok(rsl2));

    /* ------------------------------------------------------------------ */
    log_write(NONE, "--- SRLW / SRLIW ---\n");

    /* Logical right shift of a "negative" 32-bit word: fills with 0 */
    volatile uint32_t sr1 = 0x80000000u;
    volatile int64_t rsr1 = (int64_t)(int32_t)(sr1 >> 1);
    chk("srlw  0x80000000>>1 = 0x40000000", rsr1 == 0x40000000LL);
    chk("srlw  0x80000000>>1 sext ok",      sext_ok(rsr1));

    volatile uint32_t sr2 = 0xFFFFFFFFu;
    volatile int64_t rsr2 = (int64_t)(int32_t)(sr2 >> 4);
    chk("srlw  0xFFFFFFFF>>4 = 0x0FFFFFFF", rsr2 == 0x0FFFFFFFLL);

    /* ------------------------------------------------------------------ */
    log_write(NONE, "--- SRAW / SRAIW ---\n");

    /* Arithmetic right shift: fills with sign bit */
    volatile int32_t sa1 = -128;
    volatile int64_t rsa1 = (int64_t)(sa1 >> 2);
    chk("sraw  -128>>2 = -32",     rsa1 == -32LL);
    chk("sraw  -128>>2 sext ok",   sext_ok(rsa1));

    volatile int32_t sa2 = (int32_t)0x80000000u;
    volatile int64_t rsa2 = (int64_t)(sa2 >> 31);
    chk("sraw  INT32_MIN>>31 = -1",rsa2 == -1LL);
    chk("sraw  INT32_MIN>>31 sext ok", sext_ok(rsa2));

    /* Positive value: arithmetic shift same as logical */
    volatile int32_t sa3 = 0x40000000;
    volatile int64_t rsa3 = (int64_t)(sa3 >> 1);
    chk("sraw  0x40000000>>1 = 0x20000000", rsa3 == 0x20000000LL);

    log_write(NONE, "\n%d PASS  %d FAIL\n", g_pass, g_fail);
    log_close();
    return g_fail;
}
