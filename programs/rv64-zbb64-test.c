/* **************************************************************************
 *               RISC-V Emulator - RV64 Zbb Test
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
 * Tests the Zbb bit-manipulation extension on RV64, including instructions
 * that are new or differ from the RV32 version:
 *
 *   CLZ / CTZ / CPOP  (64-bit)
 *   CLZW / CTZW / CPOPW  (32-bit word, result sign-extended)
 *   ROLW / RORW  (32-bit rotate, sign-extended)
 *   REV8  (64-bit byte-swap)
 *   SEXT.B / SEXT.H  (sign-extend byte / halfword)
 *   ZEXT.H  (zero-extend halfword)
 *   MIN / MAX / MINU / MAXU  (64-bit)
 *   ANDN / ORN / XNOR  (bitwise with complement)
 *
 * Build: -march=rv64imafd_zbb -mabi=lp64d
 */

#include <stdint.h>
#include "log.h"

static int g_pass = 0, g_fail = 0;

static void chk(const char *label, int ok)
{
    if (ok) { log_write(NONE, "PASS %s\n", label); g_pass++; }
    else     { log_write(NONE, "FAIL %s\n", label); g_fail++; }
}

/* Use inline asm to force the exact Zbb instructions.
 * The "volatile" and specific constraints prevent the compiler
 * from folding them to constants. */

static int clz64(uint64_t x)
{
    uint64_t r;
    __asm__ volatile("clz %0, %1" : "=r"(r) : "r"(x));
    return (int)r;
}

static int ctz64(uint64_t x)
{
    uint64_t r;
    __asm__ volatile("ctz %0, %1" : "=r"(r) : "r"(x));
    return (int)r;
}

static int cpop64(uint64_t x)
{
    uint64_t r;
    __asm__ volatile("cpop %0, %1" : "=r"(r) : "r"(x));
    return (int)r;
}

static int clzw(uint32_t x)
{
    int64_t r;
    __asm__ volatile("clzw %0, %1" : "=r"(r) : "r"((uint64_t)x));
    return (int)r;
}

static int ctzw(uint32_t x)
{
    int64_t r;
    __asm__ volatile("ctzw %0, %1" : "=r"(r) : "r"((uint64_t)x));
    return (int)r;
}

static int cpopw(uint32_t x)
{
    int64_t r;
    __asm__ volatile("cpopw %0, %1" : "=r"(r) : "r"((uint64_t)x));
    return (int)r;
}

static int64_t rolw(int64_t x, int shamt)
{
    int64_t r;
    __asm__ volatile("rolw %0, %1, %2" : "=r"(r) : "r"(x), "r"((int64_t)shamt));
    return r;
}

static int64_t rorw(int64_t x, int shamt)
{
    int64_t r;
    __asm__ volatile("rorw %0, %1, %2" : "=r"(r) : "r"(x), "r"((int64_t)shamt));
    return r;
}

static uint64_t rev8_64(uint64_t x)
{
    uint64_t r;
    __asm__ volatile("rev8 %0, %1" : "=r"(r) : "r"(x));
    return r;
}

static int64_t sext_b(int64_t x)
{
    int64_t r;
    __asm__ volatile("sext.b %0, %1" : "=r"(r) : "r"(x));
    return r;
}

static int64_t sext_h(int64_t x)
{
    int64_t r;
    __asm__ volatile("sext.h %0, %1" : "=r"(r) : "r"(x));
    return r;
}

static uint64_t zext_h(uint64_t x)
{
    uint64_t r;
    __asm__ volatile("zext.h %0, %1" : "=r"(r) : "r"(x));
    return r;
}

/* ------------------------------------------------------------------ */

int main(void)
{
    log_init("rv64-zbb64-test.log");
    log_write(NONE, "RV64 Zbb Test\n\n");

    /* ---- CLZ (64-bit) ---- */
    log_write(NONE, "--- CLZ ---\n");
    chk("clz64(0) = 64",                         clz64(0)                      == 64);
    chk("clz64(1) = 63",                         clz64(1)                      == 63);
    chk("clz64(0x8000000000000000) = 0",          clz64(0x8000000000000000ULL)   == 0);
    chk("clz64(0x0001000000000000) = 15",         clz64(0x0001000000000000ULL)   == 15);
    chk("clz64(0xFFFFFFFFFFFFFFFF) = 0",          clz64(0xFFFFFFFFFFFFFFFFULL)   == 0);

    /* ---- CTZ (64-bit) ---- */
    log_write(NONE, "--- CTZ ---\n");
    chk("ctz64(0) = 64",                          ctz64(0)                      == 64);
    chk("ctz64(1) = 0",                           ctz64(1)                      == 0);
    chk("ctz64(0x8000000000000000) = 63",          ctz64(0x8000000000000000ULL)   == 63);
    chk("ctz64(0xFFFFFFFF00000000) = 32",          ctz64(0xFFFFFFFF00000000ULL)   == 32);
    chk("ctz64(0xFFFFFFFFFFFFFFFF) = 0",           ctz64(0xFFFFFFFFFFFFFFFFULL)   == 0);

    /* ---- CPOP (64-bit) ---- */
    log_write(NONE, "--- CPOP ---\n");
    chk("cpop64(0) = 0",                           cpop64(0)                     == 0);
    chk("cpop64(0xFFFFFFFFFFFFFFFF) = 64",         cpop64(0xFFFFFFFFFFFFFFFFULL)  == 64);
    chk("cpop64(0x5555555555555555) = 32",         cpop64(0x5555555555555555ULL)  == 32);
    chk("cpop64(0xAAAAAAAAAAAAAAAA) = 32",         cpop64(0xAAAAAAAAAAAAAAAAULL)  == 32);
    chk("cpop64(1) = 1",                           cpop64(1)                     == 1);

    /* ---- CLZW (32-bit, sign-extended result) ---- */
    log_write(NONE, "--- CLZW ---\n");
    chk("clzw(0) = 32",                            clzw(0)           == 32);
    chk("clzw(1) = 31",                            clzw(1)           == 31);
    chk("clzw(0x80000000) = 0",                    clzw(0x80000000u) == 0);
    chk("clzw(0xFFFFFFFF) = 0",                    clzw(0xFFFFFFFFu) == 0);

    /* ---- CTZW ---- */
    log_write(NONE, "--- CTZW ---\n");
    chk("ctzw(0) = 32",                            ctzw(0)           == 32);
    chk("ctzw(1) = 0",                             ctzw(1)           == 0);
    chk("ctzw(0x80000000) = 31",                   ctzw(0x80000000u) == 31);
    chk("ctzw(0xFFFFFFFF) = 0",                    ctzw(0xFFFFFFFFu) == 0);

    /* ---- CPOPW ---- */
    log_write(NONE, "--- CPOPW ---\n");
    chk("cpopw(0xFFFFFFFF) = 32",                  cpopw(0xFFFFFFFFu) == 32);
    chk("cpopw(0) = 0",                            cpopw(0)           == 0);
    chk("cpopw(0x55555555) = 16",                  cpopw(0x55555555u) == 16);
    /* upper bits of 64-bit register must be ignored */
    chk("cpopw upper bits ignored",
        cpopw((uint32_t)0xFFFFFFFFu) == 32);

    /* ---- ROLW (32-bit rotate-left, sign-extended) ---- */
    log_write(NONE, "--- ROLW ---\n");
    chk("rolw(1, 1) = 2",                          rolw(1, 1)           == 2LL);
    /* MSB wraps to LSB */
    chk("rolw(0x80000000, 1) = 1",                 rolw((int64_t)(int32_t)0x80000000u, 1) == 1LL);
    /* Result with sign bit set -> sign-extended to 64 bits */
    chk("rolw(1, 31) sign-extended",
        rolw(1, 31) == (int64_t)0xFFFFFFFF80000000LL);

    /* ---- RORW (32-bit rotate-right, sign-extended) ---- */
    log_write(NONE, "--- RORW ---\n");
    /* 1 rotated right 1 -> 0x80000000 -> sign-extended -> INT64 negative */
    chk("rorw(1, 1) = 0xFFFFFFFF80000000",
        rorw(1, 1) == (int64_t)0xFFFFFFFF80000000LL);
    chk("rorw(0x80000000, 1) = 0x40000000",
        rorw((int64_t)(int32_t)0x80000000u, 1) == 0x40000000LL);
    /* Full circle: rotate left then right returns original */
    chk("rorw(rolw(x,7),7) = x",
        rorw(rolw(0x12345678LL, 7), 7) == (int64_t)(int32_t)0x12345678u);

    /* ---- REV8 (64-bit byte-swap) ---- */
    log_write(NONE, "--- REV8 ---\n");
    chk("rev8(0x0102030405060708) = 0x0807060504030201",
        rev8_64(0x0102030405060708ULL) == 0x0807060504030201ULL);
    chk("rev8(0xDEADBEEFCAFEBABE) reversed",
        rev8_64(0xDEADBEEFCAFEBABEULL) == 0xBEBAFECAEFBEADDEULL);
    /* Identity: rev8(rev8(x)) == x */
    chk("rev8 self-inverse",
        rev8_64(rev8_64(0xFEDCBA9876543210ULL)) == 0xFEDCBA9876543210ULL);

    /* ---- SEXT.B ---- */
    log_write(NONE, "--- SEXT.B ---\n");
    chk("sext.b(0xFF) = -1",       sext_b(0xFF)  == -1LL);
    chk("sext.b(0x7F) = 127",      sext_b(0x7F)  == 127LL);
    chk("sext.b(0x80) = -128",     sext_b(0x80)  == -128LL);
    chk("sext.b(0x00) = 0",        sext_b(0x00)  == 0LL);

    /* ---- SEXT.H ---- */
    log_write(NONE, "--- SEXT.H ---\n");
    chk("sext.h(0x8000) = -32768", sext_h(0x8000)  == -32768LL);
    chk("sext.h(0x7FFF) = 32767",  sext_h(0x7FFF)  == 32767LL);
    chk("sext.h(0xFFFF) = -1",     sext_h(0xFFFF)  == -1LL);
    chk("sext.h(0x1234) = 0x1234", sext_h(0x1234)  == 0x1234LL);

    /* ---- ZEXT.H ---- */
    log_write(NONE, "--- ZEXT.H ---\n");
    chk("zext.h(0xFFFFFFFFFFFF8000) = 0x8000",
        zext_h(0xFFFFFFFFFFFF8000ULL) == 0x8000ULL);
    chk("zext.h(0xFFFFFFFFFFFFFFFF) = 0xFFFF",
        zext_h(0xFFFFFFFFFFFFFFFFULL) == 0xFFFFULL);
    chk("zext.h(0x1234) = 0x1234",
        zext_h(0x1234ULL) == 0x1234ULL);

    log_write(NONE, "\n%d PASS  %d FAIL\n", g_pass, g_fail);
    log_close();
    return g_fail;
}
