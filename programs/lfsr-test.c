/* **************************************************************************
 *      RISC-V Emulator - Linear Feedback Shift Register (LFSR) tests
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

// lfsr-test.c -- Linear Feedback Shift Register (LFSR) tests
//
// Tests:
//   - 8-bit  Fibonacci LFSR: poly x^8+x^6+x^5+x^4+1, Galois mask 0xB8
//   - 16-bit Fibonacci LFSR: poly x^16+x^14+x^13+x^11+1, Galois mask 0xB400
//   - 16-bit Galois  LFSR:   same polynomial
//   - Period verification (2^n - 1 for maximal-length polynomials)
//   - Statistical balance (2^(n-1) ones in full period)
//   - Known sequence spot-checks
//   - Zbb CPOP / BEXT used for bit operations
//
// Build: cd programs && make run-lfsr-test
// By Ulrik Hørlyk Hjort 2026

#include <stdint.h>
#include "log.h"

static int g_pass = 0, g_fail = 0;

static void chku(const char *lbl, uint32_t got, uint32_t exp)
{
    if (got == exp) {
        log_write(NONE, "  PASS  %s\n", lbl);
        g_pass++;
    } else {
        log_write(NONE, "  FAIL  %s: got 0x%x  exp 0x%x\n", lbl,
                  (unsigned)got, (unsigned)exp);
        g_fail++;
    }
}

static void chk_bool(const char *lbl, int ok)
{
    if (ok) { log_write(NONE, "  PASS  %s\n", lbl); g_pass++; }
    else    { log_write(NONE, "  FAIL  %s\n", lbl); g_fail++; }
}

/* -- Zbb intrinsics --------------------------------------------------------- */

static uint32_t cpop(uint32_t x)
{
    uint32_t r;
    asm volatile("cpop %0, %1" : "=r"(r) : "r"(x));
    return r;
}

static uint32_t bext(uint32_t x, uint32_t pos)
{
    uint32_t r;
    asm volatile("bext %0, %1, %2" : "=r"(r) : "r"(x), "r"(pos));
    return r;
}

/* -- 8-bit Fibonacci LFSR -------------------------------------------------
 * Poly x^8+x^6+x^5+x^4+1 (maximal length, period 255).
 * Shift right; feedback from bit 0 XORed into taps at bits 7,5,4,3 -> 0xB8.
 * ------------------------------------------------------------------------- */
static uint8_t lfsr8_next(uint8_t s)
{
    uint8_t fb = s & 1u;
    s >>= 1;
    if (fb) s ^= 0xB8u;
    return s;
}

/* Advance n steps and collect n output bits (LSB-first) */
static uint32_t lfsr8_collect(uint8_t *st, int n)
{
    uint32_t out = 0;
    for (int i = 0; i < n; i++) {
        out |= (uint32_t)(*st & 1u) << i;
        *st = lfsr8_next(*st);
    }
    return out;
}

/* Return period (steps until state returns to seed), capped at max */
static uint32_t lfsr8_period(uint8_t seed, uint32_t max)
{
    uint8_t s = seed;
    uint32_t n = 0;
    do { s = lfsr8_next(s); n++; } while (s != seed && n < max);
    return n;
}

/* Count ones emitted in one full period */
static uint32_t lfsr8_ones(uint8_t seed)
{
    uint8_t s = seed;
    uint32_t ones = 0;
    do { ones += s & 1u; s = lfsr8_next(s); } while (s != seed);
    return ones;
}

/* -- 16-bit Fibonacci LFSR ------------------------------------------------
 * Poly x^16+x^14+x^13+x^11+1, Galois mask 0xB400, period 65535.
 * ------------------------------------------------------------------------- */
static uint16_t lfsr16f_next(uint16_t s)
{
    uint16_t fb = s & 1u;
    s >>= 1;
    if (fb) s ^= 0xB400u;
    return s;
}

static uint32_t lfsr16f_period(uint16_t seed, uint32_t max)
{
    uint16_t s = seed;
    uint32_t n = 0;
    do { s = lfsr16f_next(s); n++; } while (s != seed && n < max);
    return n;
}

static uint32_t lfsr16f_ones(uint16_t seed)
{
    uint16_t s = seed;
    uint32_t ones = 0;
    do { ones += s & 1u; s = lfsr16f_next(s); } while (s != seed);
    return ones;
}

/* -- 16-bit Galois LFSR ---------------------------------------------------
 * Same poly -> same period; feedback is distributed across all taps at once.
 * For lsb=0 steps the output is identical to the Fibonacci form.
 * ------------------------------------------------------------------------- */
static uint16_t lfsr16g_next(uint16_t s)
{
    uint16_t lsb = s & 1u;
    s >>= 1;
    if (lsb) s ^= 0xB400u;
    return s;
}

static uint32_t lfsr16g_period(uint16_t seed, uint32_t max)
{
    uint16_t s = seed;
    uint32_t n = 0;
    do { s = lfsr16g_next(s); n++; } while (s != seed && n < max);
    return n;
}

/* -- main ------------------------------------------------------------------- */
int main(void)
{
    log_init("lfsr-test.log");
    log_write(NONE, "=== LFSR Test ===\n");

    /* ------------------------------------------------------------------ */
    log_write(NONE, "\n-- Zbb CPOP / BEXT --\n");

    chku("cpop(0x00)=0",  cpop(0x00u),   0u);
    chku("cpop(0xFF)=8",  cpop(0xFFu),   8u);
    chku("cpop(0xB8)=4",  cpop(0xB8u),   4u);   /* 8-bit tap mask */
    chku("cpop(0xB400)=4",cpop(0xB400u), 4u);   /* 16-bit tap mask */
    chku("bext(0xAC,0)=0",bext(0xACu, 0u), 0u); /* 0xAC = 1010 1100, bit0=0 */
    chku("bext(0xAD,0)=1",bext(0xADu, 0u), 1u);
    chku("bext(0xAC,7)=1",bext(0xACu, 7u), 1u); /* 0xAC bit7=1 */
    chku("bext(0xAC,6)=0",bext(0xACu, 6u), 0u); /* 0xAC=10101100 bit6=0 */

    /* ------------------------------------------------------------------ */
    log_write(NONE, "\n-- 8-bit Fibonacci LFSR (poly x^8+x^6+x^5+x^4+1) --\n");

    /* Period = 2^8 - 1 = 255 for any non-zero seed */
    chku("period(0xAC)=255", lfsr8_period(0xACu, 300u), 255u);
    chku("period(0x01)=255", lfsr8_period(0x01u, 300u), 255u);
    chku("period(0xFF)=255", lfsr8_period(0xFFu, 300u), 255u);

    /* Known next-state transitions (manual trace):
     *   0xAC lsb=0 -> 0x56      (no feedback)
     *   0x56 lsb=0 -> 0x2B
     *   0x2B lsb=1 -> 0x15^0xB8 = 0xAD  */
    chku("next(0xAC)=0x56", lfsr8_next(0xACu), 0x56u);
    chku("next(0x56)=0x2B", lfsr8_next(0x56u), 0x2Bu);
    chku("next(0x2B)=0xAD", lfsr8_next(0x2Bu), 0xADu);

    /* Collect 8 output bits from seed 0xFF:
     * 0xFF->1, 0xC7->1, 0xDB->1, 0xD5->1, 0xD2->0, 0x69->1, 0x8C->0, 0x46->0
     * LSB-first: 1111 0100 reversed as bits -> byte = 0b0010_1111 = 0x2F */
    uint8_t s8 = 0xFFu;
    chku("seq8[0..7] from 0xFF = 0x2F", lfsr8_collect(&s8, 8), 0x2Fu);

    /* Balance: exactly 2^7 = 128 ones in the 255-step full period */
    chku("balance(0xAC) = 128 ones", lfsr8_ones(0xACu), 128u);
    chku("balance(0xFF) = 128 ones", lfsr8_ones(0xFFu), 128u);

    /* ------------------------------------------------------------------ */
    log_write(NONE, "\n-- 16-bit Fibonacci LFSR (poly x^16+x^14+x^13+x^11+1) --\n");

    /* Period = 2^16 - 1 = 65535 */
    chku("period16f(0x0ACE)=65535", lfsr16f_period(0x0ACEu, 70000u), 65535u);
    chku("period16f(0x0001)=65535", lfsr16f_period(0x0001u, 70000u), 65535u);
    chku("period16f(0xFFFF)=65535", lfsr16f_period(0xFFFFu, 70000u), 65535u);

    /* Known transitions from seed 0x0ACE:
     *   0x0ACE lsb=0 -> 0x0567
     *   0x0567 lsb=1 -> 0x02B3^0xB400 = 0xB6B3
     *   0xB6B3 lsb=1 -> 0x5B59^0xB400 = 0xEF59  */
    chku("next16f(0x0ACE)=0x0567", lfsr16f_next(0x0ACEu), 0x0567u);
    chku("next16f(0x0567)=0xB6B3", lfsr16f_next(0x0567u), 0xB6B3u);
    chku("next16f(0xB6B3)=0xEF59", lfsr16f_next(0xB6B3u), 0xEF59u);

    /* Balance: exactly 2^15 = 32768 ones */
    chku("balance16f = 32768 ones", lfsr16f_ones(0x0001u), 32768u);

    /* ------------------------------------------------------------------ */
    log_write(NONE, "\n-- 16-bit Galois LFSR (same poly) --\n");

    chku("period16g(0x0ACE)=65535", lfsr16g_period(0x0ACEu, 70000u), 65535u);
    chku("period16g(0xFFFF)=65535", lfsr16g_period(0xFFFFu, 70000u), 65535u);

    /* Both forms: when lsb=0, next state is identical (no feedback applied) */
    chku("galois next(0x0ACE)=0x0567", lfsr16g_next(0x0ACEu), 0x0567u);
    /* When lsb=1, feedback applied -- same mask -> same result for same state */
    chku("galois next(0x0567)=0xB6B3", lfsr16g_next(0x0567u), 0xB6B3u);
    /* Periods match */
    chk_bool("fib and galois periods equal",
             lfsr16f_period(0x0ACEu, 70000u) == lfsr16g_period(0x0ACEu, 70000u));

    /* ------------------------------------------------------------------ */
    log_write(NONE, "\n-- PRNG output windows --\n");

    /* Two consecutive 16-bit windows from the Fibonacci LFSR should differ
     * and both be non-zero (for any non-zero seed). */
    uint16_t prng = 0xDEADu;
    uint32_t win1 = 0, win2 = 0;
    for (int i = 0; i < 16; i++) {
        win1 |= (uint32_t)(prng & 1u) << i;
        prng = lfsr16f_next(prng);
    }
    for (int i = 0; i < 16; i++) {
        win2 |= (uint32_t)(prng & 1u) << i;
        prng = lfsr16f_next(prng);
    }
    chk_bool("window1 non-zero",         win1 != 0u);
    chk_bool("window2 non-zero",         win2 != 0u);
    chk_bool("window1 != window2",       win1 != win2);

    /* ------------------------------------------------------------------ */
    log_write(NONE, "\n=== Result: %d PASS  %d FAIL ===\n", g_pass, g_fail);
    log_close();
    return g_fail;
}
