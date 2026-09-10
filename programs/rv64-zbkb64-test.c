/* **************************************************************************
 *               RISC-V Emulator - RV64 Zbkb Test
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
 * Tests the Zbkb pack/reverse instructions on RV64 (zip/unzip do not exist
 * on RV64 and are intentionally omitted):
 *
 *   PACK    rd = (rs2[31:0] << 32) | rs1[31:0]   (low halves, 64-bit result)
 *   PACKH   rd = (rs2[7:0]  << 8)  | rs1[7:0]     (low bytes, zero-extended)
 *   PACKW   rd = sign_extend32((rs2[15:0] << 16) | rs1[15:0])  (RV64 only)
 *   BREV8   reverse the bit order within each of the eight bytes
 *
 * PACK/PACKW widen versus RV32 (whole 32-bit / 16-bit halves), so they are
 * the interesting RV64 cases. BREV8 operates on all eight bytes.
 *
 * Build: -march=rv64imafd_zbkb -mabi=lp64d
 */

#include <stdint.h>
#include "log.h"

static int g_pass = 0, g_fail = 0;

static void chk(const char *label, int ok)
{
    if (ok) { log_write(NONE, "PASS %s\n", label); g_pass++; }
    else    { log_write(NONE, "FAIL %s\n", label); g_fail++; }
}

static uint64_t pack(uint64_t a, uint64_t b)
{ uint64_t r; __asm__ volatile("pack %0,%1,%2"  : "=r"(r) : "r"(a), "r"(b)); return r; }
static uint64_t packh(uint64_t a, uint64_t b)
{ uint64_t r; __asm__ volatile("packh %0,%1,%2" : "=r"(r) : "r"(a), "r"(b)); return r; }
static int64_t packw(uint64_t a, uint64_t b)
{ int64_t r;  __asm__ volatile("packw %0,%1,%2" : "=r"(r) : "r"(a), "r"(b)); return r; }
static uint64_t brev8(uint64_t a)
{ uint64_t r; __asm__ volatile("brev8 %0,%1"    : "=r"(r) : "r"(a)); return r; }

static uint64_t ref_brev8(uint64_t x)
{
    uint64_t r = 0;
    for (int byte = 0; byte < 8; byte++) {
        uint64_t b = (x >> (byte * 8)) & 0xFF;
        uint64_t rev = 0;
        for (int bit = 0; bit < 8; bit++)
            if (b & (1u << bit)) rev |= 1u << (7 - bit);
        r |= rev << (byte * 8);
    }
    return r;
}

int main(void)
{
    log_init("rv64-zbkb64-test.log");
    log_write(NONE, "RV64 Zbkb Test\n\n");

    /* ---- PACK (low 32-bit halves into a 64-bit result) ---- */
    log_write(NONE, "--- PACK ---\n");
    chk("pack halves whole 32-bit words",
        pack(0x11112222ULL, 0x33334444ULL) == 0x3333444411112222ULL);
    /* upper 32 bits of the operands are ignored */
    chk("pack ignores upper source bits",
        pack(0xAAAAAAAA11112222ULL, 0xBBBBBBBB33334444ULL) == 0x3333444411112222ULL);
    chk("pack(0,0) = 0", pack(0, 0) == 0ULL);

    /* ---- PACKH (low bytes, zero-extended) ---- */
    log_write(NONE, "--- PACKH ---\n");
    chk("packh(0x34,0x56) = 0x5634", packh(0x1234ULL, 0x7856ULL) == 0x5634ULL);
    chk("packh zero-extends", packh(0xFFFFFF12ULL, 0xFFFFFF34ULL) == 0x3412ULL);

    /* ---- PACKW (low 16-bit halves, sign-extended from bit 31) ---- */
    log_write(NONE, "--- PACKW ---\n");
    chk("packw combines 16-bit halves",
        packw(0x1234ULL, 0x5678ULL) == 0x56781234LL);
    /* result with bit 31 set is sign-extended to 64 bits */
    chk("packw sign-extends",
        packw(0x1234ULL, 0x8765ULL) == (int64_t)0xFFFFFFFF87651234LL);
    /* zext.h is packw with rs2 = 0 */
    chk("packw(x,0) zero-extends low half",
        packw(0xABCDULL, 0) == 0xABCDLL);

    /* ---- BREV8 (per-byte bit reversal) ---- */
    log_write(NONE, "--- BREV8 ---\n");
    chk("brev8(0x01) = 0x80", brev8(0x01ULL) == 0x80ULL);
    chk("brev8(0x0102) = 0x8040", brev8(0x0102ULL) == 0x8040ULL);
    chk("brev8 self-inverse",
        brev8(brev8(0xDEADBEEFCAFEBABEULL)) == 0xDEADBEEFCAFEBABEULL);
    chk("brev8 vs reference",
        brev8(0x0123456789ABCDEFULL) == ref_brev8(0x0123456789ABCDEFULL));
    chk("brev8(all ones) = all ones",
        brev8(0xFFFFFFFFFFFFFFFFULL) == 0xFFFFFFFFFFFFFFFFULL);

    log_write(NONE, "\n%d PASS  %d FAIL\n", g_pass, g_fail);
    log_close();
    return g_fail;
}
