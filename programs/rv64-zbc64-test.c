/* **************************************************************************
 *               RISC-V Emulator - RV64 Zbc / Zbkc Test
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
 * Tests the Zbc (carry-less multiply) extension on RV64, which is the same
 * encoding used by Zbkc. On RV64 these operate on the full 64-bit operands
 * and produce the 128-bit carry-less product split as:
 *
 *   CLMUL   rd = product[63:0]     (low half)
 *   CLMULH  rd = product[127:64]   (high half)
 *   CLMULR  rd = product[126:63]   (reversed, Zbc only)
 *
 * A decoder bug that aliased these to a shift produced wrong values with no
 * trap. The reference values below are computed independently below with a
 * plain-C carry-less multiply.
 *
 * Build: -march=rv64imafd_zbc -mabi=lp64d
 */

#include <stdint.h>
#include "log.h"

static int g_pass = 0, g_fail = 0;

static void chk(const char *label, int ok)
{
    if (ok) { log_write(NONE, "PASS %s\n", label); g_pass++; }
    else    { log_write(NONE, "FAIL %s\n", label); g_fail++; }
}

static uint64_t clmul(uint64_t a, uint64_t b)
{ uint64_t r; __asm__ volatile("clmul %0,%1,%2"  : "=r"(r) : "r"(a), "r"(b)); return r; }
static uint64_t clmulh(uint64_t a, uint64_t b)
{ uint64_t r; __asm__ volatile("clmulh %0,%1,%2" : "=r"(r) : "r"(a), "r"(b)); return r; }
static uint64_t clmulr(uint64_t a, uint64_t b)
{ uint64_t r; __asm__ volatile("clmulr %0,%1,%2" : "=r"(r) : "r"(a), "r"(b)); return r; }

/* Independent reference: full 128-bit carry-less product in software. */
static void ref_clmul128(uint64_t a, uint64_t b,
                         uint64_t *lo, uint64_t *hi)
{
    uint64_t l = 0, h = 0;
    for (int i = 0; i < 64; i++) {
        if ((b >> i) & 1) {
            /* XOR in (a << i) across the 128-bit accumulator */
            l ^= (i == 0) ? a : (a << i);
            if (i != 0) h ^= (a >> (64 - i));
        }
    }
    *lo = l; *hi = h;
}

static uint64_t ref_clmul(uint64_t a, uint64_t b)
{ uint64_t l, h; ref_clmul128(a, b, &l, &h); return l; }
static uint64_t ref_clmulh(uint64_t a, uint64_t b)
{ uint64_t l, h; ref_clmul128(a, b, &l, &h); return h; }
/* clmulr = bits [126:63] = (clmulh << 1) | (clmul >> 63) */
static uint64_t ref_clmulr(uint64_t a, uint64_t b)
{ uint64_t l, h; ref_clmul128(a, b, &l, &h); return (h << 1) | (l >> 63); }

int main(void)
{
    log_init("rv64-zbc64-test.log");
    log_write(NONE, "RV64 Zbc/Zbkc Test\n\n");

    static const uint64_t vec[] = {
        0, 1, 3, 5, 0xFFULL, 0x1234ULL,
        0x00000000FFFFFFFFULL, 0x0000000100000000ULL,
        0x8000000000000000ULL, 0xDEADBEEFCAFEBABEULL,
        0xFFFFFFFFFFFFFFFFULL, 0x0102030405060708ULL
    };
    const int n = (int)(sizeof(vec) / sizeof(vec[0]));

    /* ---- CLMUL low half ---- */
    log_write(NONE, "--- CLMUL ---\n");
    chk("clmul(3,5) = 15",   clmul(3, 5)   == 15ULL);
    chk("clmul(0xFF,0xFF)",  clmul(0xFF, 0xFF) == 0x5555ULL);
    chk("clmul(x,0) = 0",    clmul(0xDEADBEEF, 0) == 0ULL);
    chk("clmul(x,1) = x",    clmul(0xDEADBEEFCAFEBABEULL, 1) == 0xDEADBEEFCAFEBABEULL);

    /* ---- CLMULH high half ---- */
    log_write(NONE, "--- CLMULH ---\n");
    chk("clmulh(3,5) = 0",   clmulh(3, 5) == 0ULL);
    /* (1<<63) * 2 = 1<<64  -> low = 0, high = 1 */
    chk("clmulh(1<<63,2) = 1", clmulh(0x8000000000000000ULL, 2) == 1ULL);

    /* ---- CLMULR ---- */
    log_write(NONE, "--- CLMULR ---\n");
    /* (1<<63) clmul 1 -> bit 63 set in low half -> clmulr bit 0 set */
    chk("clmulr(1<<63,1) = 1", clmulr(0x8000000000000000ULL, 1) == 1ULL);

    /* ---- exhaustive cross-check against the software reference ---- */
    log_write(NONE, "--- vs reference (%d x %d pairs) ---\n", n, n);
    int lo_ok = 1, hi_ok = 1, r_ok = 1;
    for (int i = 0; i < n; i++) {
        for (int j = 0; j < n; j++) {
            uint64_t a = vec[i], b = vec[j];
            if (clmul(a, b)  != ref_clmul(a, b))  lo_ok = 0;
            if (clmulh(a, b) != ref_clmulh(a, b)) hi_ok = 0;
            if (clmulr(a, b) != ref_clmulr(a, b)) r_ok  = 0;
        }
    }
    chk("clmul  matches reference for all pairs", lo_ok);
    chk("clmulh matches reference for all pairs", hi_ok);
    chk("clmulr matches reference for all pairs", r_ok);

    /* Commutativity (carry-less multiply is commutative) */
    chk("clmul commutes",
        clmul(0xDEADBEEFULL, 0xCAFEBABEULL) == clmul(0xCAFEBABEULL, 0xDEADBEEFULL));

    log_write(NONE, "\n%d PASS  %d FAIL\n", g_pass, g_fail);
    log_close();
    return g_fail;
}
