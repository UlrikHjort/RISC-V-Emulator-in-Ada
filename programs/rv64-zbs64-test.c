/* **************************************************************************
 *               RISC-V Emulator - RV64 Zbs Test
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
 * Tests the Zbs single-bit extension on RV64. The point of interest versus
 * RV32 is the shift amount: on RV64 it is the low 6 bits of the operand
 * (0..63), so bits above 31 are reachable. A bug where the decoder aliased
 * these to plain shifts (funct6 ignored) produced wrong values with no trap;
 * these cases exercise both the register and immediate forms across the full
 * 64-bit width.
 *
 *   BSET / BSETI   rd = rs1 |  (1 << (shamt & 63))
 *   BCLR / BCLRI   rd = rs1 & ~(1 << (shamt & 63))
 *   BINV / BINVI   rd = rs1 ^  (1 << (shamt & 63))
 *   BEXT / BEXTI   rd = (rs1 >> (shamt & 63)) & 1
 *
 * Build: -march=rv64imafd_zbs -mabi=lp64d
 */

#include <stdint.h>
#include "log.h"

static int g_pass = 0, g_fail = 0;

static void chk(const char *label, int ok)
{
    if (ok) { log_write(NONE, "PASS %s\n", label); g_pass++; }
    else    { log_write(NONE, "FAIL %s\n", label); g_fail++; }
}

/* Register forms (shift amount in a register). volatile + register
 * constraints stop the compiler folding these to constants. */
static uint64_t bset(uint64_t a, uint64_t b)
{ uint64_t r; __asm__ volatile("bset %0,%1,%2" : "=r"(r) : "r"(a), "r"(b)); return r; }
static uint64_t bclr(uint64_t a, uint64_t b)
{ uint64_t r; __asm__ volatile("bclr %0,%1,%2" : "=r"(r) : "r"(a), "r"(b)); return r; }
static uint64_t binv(uint64_t a, uint64_t b)
{ uint64_t r; __asm__ volatile("binv %0,%1,%2" : "=r"(r) : "r"(a), "r"(b)); return r; }
static uint64_t bext(uint64_t a, uint64_t b)
{ uint64_t r; __asm__ volatile("bext %0,%1,%2" : "=r"(r) : "r"(a), "r"(b)); return r; }

/* Immediate forms. The shift amount must be a compile-time constant, so
 * one wrapper per amount that the tests need. */
static uint64_t bseti40(uint64_t a)
{ uint64_t r; __asm__ volatile("bseti %0,%1,40" : "=r"(r) : "r"(a)); return r; }
static uint64_t bseti63(uint64_t a)
{ uint64_t r; __asm__ volatile("bseti %0,%1,63" : "=r"(r) : "r"(a)); return r; }
static uint64_t bclri40(uint64_t a)
{ uint64_t r; __asm__ volatile("bclri %0,%1,40" : "=r"(r) : "r"(a)); return r; }
static uint64_t binvi63(uint64_t a)
{ uint64_t r; __asm__ volatile("binvi %0,%1,63" : "=r"(r) : "r"(a)); return r; }
static uint64_t bexti40(uint64_t a)
{ uint64_t r; __asm__ volatile("bexti %0,%1,40" : "=r"(r) : "r"(a)); return r; }
static uint64_t bexti5(uint64_t a)
{ uint64_t r; __asm__ volatile("bexti %0,%1,5" : "=r"(r) : "r"(a)); return r; }

int main(void)
{
    log_init("rv64-zbs64-test.log");
    log_write(NONE, "RV64 Zbs Test\n\n");

    /* ---- BSET (register) ---- */
    log_write(NONE, "--- BSET ---\n");
    chk("bset(0,5) = 32",              bset(0, 5)   == 32ULL);
    chk("bset(1,3) = 9",               bset(1, 3)   == 9ULL);
    chk("bset(0,63) = 1<<63",          bset(0, 63)  == 0x8000000000000000ULL);
    chk("bset(0,40) = 1<<40",          bset(0, 40)  == (1ULL << 40));
    chk("bset already-set is a no-op", bset(0x100, 8) == 0x100ULL);
    /* shift amount is taken mod 64 */
    chk("bset(0,64) == bset(0,0)",     bset(0, 64)  == 1ULL);

    /* ---- BCLR ---- */
    log_write(NONE, "--- BCLR ---\n");
    chk("bclr(0xFF,3) = 0xF7",              bclr(0xFF, 3) == 0xF7ULL);
    chk("bclr(1<<40,40) = 0",               bclr(1ULL << 40, 40) == 0ULL);
    chk("bclr(all,63) clears top bit",
        bclr(0xFFFFFFFFFFFFFFFFULL, 63) == 0x7FFFFFFFFFFFFFFFULL);
    chk("bclr of clear bit is a no-op",     bclr(0, 20) == 0ULL);

    /* ---- BINV ---- */
    log_write(NONE, "--- BINV ---\n");
    chk("binv(5,3) = 13",                   binv(5, 3)  == 13ULL);
    chk("binv sets then clears",            binv(binv(0, 50), 50) == 0ULL);
    chk("binv(0,63) = 1<<63",               binv(0, 63) == 0x8000000000000000ULL);

    /* ---- BEXT ---- */
    log_write(NONE, "--- BEXT ---\n");
    chk("bext(0xFF,3) = 1",                 bext(0xFF, 3) == 1ULL);
    chk("bext(0xFF,8) = 0",                 bext(0xFF, 8) == 0ULL);
    chk("bext(1<<40,40) = 1",               bext(1ULL << 40, 40) == 1ULL);
    chk("bext(1<<40,39) = 0",               bext(1ULL << 40, 39) == 0ULL);
    chk("bext top bit",                     bext(0x8000000000000000ULL, 63) == 1ULL);

    /* ---- immediate forms, high shift amounts (RV64-specific) ---- */
    log_write(NONE, "--- immediates ---\n");
    chk("bseti(0,40) = 1<<40",              bseti40(0)  == (1ULL << 40));
    chk("bseti(0,63) = 1<<63",              bseti63(0)  == 0x8000000000000000ULL);
    chk("bclri(1<<40,40) = 0",              bclri40(1ULL << 40) == 0ULL);
    chk("binvi(0,63) = 1<<63",              binvi63(0)  == 0x8000000000000000ULL);
    chk("bexti(1<<40,40) = 1",              bexti40(1ULL << 40) == 1ULL);
    chk("bexti(0xFF,5) = 1",                bexti5(0xFF) == 1ULL);

    log_write(NONE, "\n%d PASS  %d FAIL\n", g_pass, g_fail);
    log_close();
    return g_fail;
}
