/* **************************************************************************
 *               RISC-V Emulator - RV64 Zbkx Test
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
 * Tests the Zbkx crossbar permutation extension on RV64. Each output
 * element is selected from rs1 by the same-position index in rs2; an
 * out-of-range index yields zero.
 *
 *   XPERM4  16 nibbles, index in 0..15 (all in range on RV64)
 *   XPERM8   8 bytes,   index in 0..7  (index >= 8 -> zero byte)
 *
 * On RV64 XPERM4 spans all 16 nibbles and XPERM8 all 8 bytes -- twice the
 * width of the RV32 forms. A software reference computes the expected
 * permutations independently.
 *
 * Build: -march=rv64imafd_zbkx -mabi=lp64d
 */

#include <stdint.h>
#include "log.h"

static int g_pass = 0, g_fail = 0;

static void chk(const char *label, int ok)
{
    if (ok) { log_write(NONE, "PASS %s\n", label); g_pass++; }
    else    { log_write(NONE, "FAIL %s\n", label); g_fail++; }
}

static uint64_t xperm4(uint64_t a, uint64_t b)
{ uint64_t r; __asm__ volatile("xperm4 %0,%1,%2" : "=r"(r) : "r"(a), "r"(b)); return r; }
static uint64_t xperm8(uint64_t a, uint64_t b)
{ uint64_t r; __asm__ volatile("xperm8 %0,%1,%2" : "=r"(r) : "r"(a), "r"(b)); return r; }

/* Software reference (index >= element count -> zero). */
static uint64_t ref_xperm4(uint64_t a, uint64_t b)
{
    uint64_t r = 0;
    for (int i = 0; i < 16; i++) {
        int idx = (int)((b >> (i * 4)) & 0xF);   /* always in range */
        uint64_t nib = (a >> (idx * 4)) & 0xF;
        r |= nib << (i * 4);
    }
    return r;
}
static uint64_t ref_xperm8(uint64_t a, uint64_t b)
{
    uint64_t r = 0;
    for (int i = 0; i < 8; i++) {
        int idx = (int)((b >> (i * 8)) & 0xFF);
        if (idx < 8) {
            uint64_t byte = (a >> (idx * 8)) & 0xFF;
            r |= byte << (i * 8);
        }
    }
    return r;
}

int main(void)
{
    log_init("rv64-zbkx64-test.log");
    log_write(NONE, "RV64 Zbkx Test\n\n");

    /* Source with distinct nibbles/bytes so a permutation is observable. */
    const uint64_t src4 = 0xFEDCBA9876543210ULL; /* nibble i holds value i */
    const uint64_t src8 = 0x0807060504030201ULL; /* byte i holds value i+1 */

    /* ---- XPERM4 spot checks ---- */
    log_write(NONE, "--- XPERM4 ---\n");
    /* identity permutation reproduces the source */
    chk("xperm4 identity",   xperm4(src4, 0xFEDCBA9876543210ULL) == src4);
    /* index 0 in every slot -> broadcast nibble 0 (value 0) */
    chk("xperm4 broadcast-0", xperm4(src4, 0) == 0ULL);
    /* index 15 in every slot -> broadcast nibble 15 (value 0xF) */
    chk("xperm4 broadcast-15",
        xperm4(src4, 0xFFFFFFFFFFFFFFFFULL) == 0xFFFFFFFFFFFFFFFFULL);
    /* reverse: slot i picks nibble (15-i) */
    chk("xperm4 reverse",
        xperm4(src4, 0x0123456789ABCDEFULL) == 0x0123456789ABCDEFULL);

    /* ---- XPERM8 spot checks ---- */
    log_write(NONE, "--- XPERM8 ---\n");
    chk("xperm8 identity",   xperm8(src8, 0x0706050403020100ULL) == src8);
    chk("xperm8 broadcast-0", xperm8(src8, 0) == 0x0101010101010101ULL);
    /* index 8 is out of range -> zero byte in that slot */
    chk("xperm8 index 8 -> 0",
        (xperm8(src8, 8) & 0xFF) == 0ULL);
    /* high indices (>=8) all produce zero bytes */
    chk("xperm8 all-out-of-range = 0",
        xperm8(src8, 0x0808080808080808ULL) == 0ULL);

    /* ---- exhaustive cross-check against the reference ---- */
    log_write(NONE, "--- vs reference ---\n");
    static const uint64_t av[] = {
        0xFEDCBA9876543210ULL, 0x0102030405060708ULL,
        0xDEADBEEFCAFEBABEULL, 0xFFFFFFFFFFFFFFFFULL, 0
    };
    static const uint64_t bv[] = {
        0x0123456789ABCDEFULL, 0x1111111111111111ULL,
        0xF0F0F0F0F0F0F0F0ULL, 0x0808080808080808ULL, 0
    };
    const int n = (int)(sizeof(av) / sizeof(av[0]));
    int p4_ok = 1, p8_ok = 1;
    for (int i = 0; i < n; i++)
        for (int j = 0; j < n; j++) {
            if (xperm4(av[i], bv[j]) != ref_xperm4(av[i], bv[j])) p4_ok = 0;
            if (xperm8(av[i], bv[j]) != ref_xperm8(av[i], bv[j])) p8_ok = 0;
        }
    chk("xperm4 matches reference for all pairs", p4_ok);
    chk("xperm8 matches reference for all pairs", p8_ok);

    log_write(NONE, "\n%d PASS  %d FAIL\n", g_pass, g_fail);
    log_close();
    return g_fail;
}
