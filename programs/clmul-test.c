/* **************************************************************************
 *RISC-V Emulator - RISC-V Zbkc (CLMUL/CLMULH) and Zbkx (XPERM4/XPERM8) tests
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

// clmul-test.c -- RISC-V Zbkc (CLMUL/CLMULH) and Zbkx (XPERM4/XPERM8) tests.
//
// Zbkc: carry-less multiplication in GF(2)[x]
//   CLMUL  rd, rs1, rs2  -- lower 32 bits of 64-bit carry-less product
//   CLMULH rd, rs1, rs2  -- upper 32 bits
//
// Zbkx: crossbar (nibble/byte) permutation
//   XPERM4 rd, rs1, rs2  -- each nibble of rs2 indexes into nibbles of rs1
//   XPERM8 rd, rs1, rs2  -- each byte  of rs2 indexes into bytes  of rs1
//
// Build: cd programs && make run-clmul-test
// By Ulrik Hørlyk Hjort 2026

#include <stdint.h>
#include "log.h"

void putchar(char c);
static void uart_puts(const char *s) {
    while (*s) { if (*s == '\n') putchar('\r'); putchar(*s++); }
}

static int g_pass = 0, g_fail = 0;

static void chk32u(const char *lbl, uint32_t got, uint32_t exp) {
    if (got == exp) {
        log_write(NONE, "  PASS  %s\n", lbl);
        g_pass++;
    } else {
        log_write(NONE, "  FAIL  %s: got 0x%x  exp 0x%x\n", lbl, got, exp);
        g_fail++;
    }
}

/* -- CLMUL / CLMULH ------------------------------------------------------- */
/*
 * Carry-less multiplication (polynomial multiplication in GF(2)[x]).
 * The 64-bit carry-less product of a and b:
 *   bit k of product = XOR of (a_i & b_{k-i}) for all i in [0, k]
 * CLMUL  -> lower 32 bits
 * CLMULH -> upper 32 bits
 *
 * Key test vectors (verified by hand):
 *   CLMUL(0xB, 0xD) = 0x7F
 *     0xB = 1011 = x^3+x+1,  0xD = 1101 = x^3+x^2+1
 *     product = x^6+x^5+x^4+x^3+x^2+x+1 = 0x7F
 *
 *   CLMUL(0x80000001, 0x80000001) = 0x00000001
 *   CLMULH(0x80000001, 0x80000001) = 0x40000000
 *     (x^31+1)^2 = x^62+1 -> lower=1, upper=x^30=0x40000000
 */

static void test_clmul(void) {
    log_write(NONE, "\n=== CLMUL (carry-less multiply, lower 32) ===\n");
    uint32_t r;

    /* Identity: clmul(1, x) = x */
    asm volatile("clmul %0, %1, %2" : "=r"(r) : "r"(1u), "r"(0xABCDEF01u));
    chk32u("clmul(1,x)=x",                   r, 0xABCDEF01u);

    /* Zero: clmul(0, x) = 0 */
    asm volatile("clmul %0, %1, %2" : "=r"(r) : "r"(0u), "r"(0xFFFFFFFFu));
    chk32u("clmul(0,x)=0",                   r, 0u);

    /* clmul(0xF, 0xF):
     * (x^3+x^2+x+1)^2 = x^6+x^4+x^2+1 = 0x55 */
    asm volatile("clmul %0, %1, %2" : "=r"(r) : "r"(0xFu), "r"(0xFu));
    chk32u("clmul(0xF,0xF)=0x55",            r, 0x55u);

    /* clmul(0xB, 0xD) = 0x7F (computed above) */
    asm volatile("clmul %0, %1, %2" : "=r"(r) : "r"(0xBu), "r"(0xDu));
    chk32u("clmul(0xB,0xD)=0x7F",            r, 0x7Fu);

    /* clmul(2, 0x80000000): x * x^31 = x^32 -> lower 32 = 0 */
    asm volatile("clmul %0, %1, %2" : "=r"(r) : "r"(2u), "r"(0x80000000u));
    chk32u("clmul(2,0x80000000)=0",          r, 0u);

    /* clmul(0x80000001, 0x80000001) = 1 */
    asm volatile("clmul %0, %1, %2" : "=r"(r) : "r"(0x80000001u), "r"(0x80000001u));
    chk32u("clmul(0x80000001,0x80000001)=1", r, 1u);

    /* clmul(0xFFFFFFFF, 2): shift all bits left 1 -> 0xFFFFFFFE */
    asm volatile("clmul %0, %1, %2" : "=r"(r) : "r"(0xFFFFFFFFu), "r"(2u));
    chk32u("clmul(0xFFFFFFFF,2)=0xFFFFFFFE", r, 0xFFFFFFFEu);

    /* Commutativity: clmul(a,b) = clmul(b,a) */
    uint32_t ab, ba;
    asm volatile("clmul %0, %1, %2" : "=r"(ab) : "r"(0x12345678u), "r"(0xABCDEF01u));
    asm volatile("clmul %0, %1, %2" : "=r"(ba) : "r"(0xABCDEF01u), "r"(0x12345678u));
    chk32u("clmul commutative",              ab, ba);

    log_write(NONE, "\n=== CLMULH (carry-less multiply, upper 32) ===\n");

    /* clmulh(0xB, 0xD) = 0 (7-bit product fits in 32 bits) */
    asm volatile("clmulh %0, %1, %2" : "=r"(r) : "r"(0xBu), "r"(0xDu));
    chk32u("clmulh(0xB,0xD)=0",             r, 0u);

    /* clmulh(2, 0x80000000) = 1 (x^32 -> bit 0 of upper word) */
    asm volatile("clmulh %0, %1, %2" : "=r"(r) : "r"(2u), "r"(0x80000000u));
    chk32u("clmulh(2,0x80000000)=1",        r, 1u);

    /* clmulh(0x80000001, 0x80000001) = 0x40000000 */
    asm volatile("clmulh %0, %1, %2" : "=r"(r) : "r"(0x80000001u), "r"(0x80000001u));
    chk32u("clmulh(0x80000001,0x80000001)=0x40000000", r, 0x40000000u);

    /* clmulh(0xFFFFFFFF, 2) = 1 (high bit carried into upper word) */
    asm volatile("clmulh %0, %1, %2" : "=r"(r) : "r"(0xFFFFFFFFu), "r"(2u));
    chk32u("clmulh(0xFFFFFFFF,2)=1",        r, 1u);

    /* clmulh(0xFFFFFFFF, 0xFFFFFFFF): upper half of full polynomial square
     * (sum_{i=0}^{31} x^i)^2 = sum_{i=0}^{31} x^{2i} = 0x55555555_55555555
     * upper 32 = 0x55555555 */
    asm volatile("clmulh %0, %1, %2" : "=r"(r) : "r"(0xFFFFFFFFu), "r"(0xFFFFFFFFu));
    chk32u("clmulh(0xFFFFFFFF,0xFFFFFFFF)=0x55555555", r, 0x55555555u);
}

/* -- XPERM8 ---------------------------------------------------------------- */
/*
 * xperm8 rd, rs1, rs2:
 *   For each byte position i (0=LSB):
 *     idx = rs2.byte[i]
 *     rd.byte[i] = (idx < 4) ? rs1.byte[idx] : 0
 *
 * Note: rs1.byte[0] is the LEAST significant byte.
 */
static void test_xperm8(void) {
    log_write(NONE, "\n=== XPERM8 (byte permutation) ===\n");
    uint32_t r;

    /* Byte-swap (reverse byte order):
     * rs1 = 0xAABBCCDD: byte[0]=DD, byte[1]=CC, byte[2]=BB, byte[3]=AA
     * rs2 = 0x00010203: byte[0]=3, byte[1]=2, byte[2]=1, byte[3]=0
     * rd.byte[0] = rs1.byte[3] = AA
     * rd.byte[1] = rs1.byte[2] = BB
     * rd.byte[2] = rs1.byte[1] = CC
     * rd.byte[3] = rs1.byte[0] = DD
     * result = 0xDDCCBBAA
     */
    asm volatile("xperm8 %0, %1, %2" : "=r"(r) : "r"(0xAABBCCDDu), "r"(0x00010203u));
    chk32u("xperm8 byte-swap AABBCCDD", r, 0xDDCCBBAAu);

    /* Broadcast byte[0]: rs2 = 0x00000000 -> all select byte[0] = 0xDD */
    asm volatile("xperm8 %0, %1, %2" : "=r"(r) : "r"(0xAABBCCDDu), "r"(0x00000000u));
    chk32u("xperm8 broadcast byte[0]", r, 0xDDDDDDDDu);

    /* All out-of-range: rs2 bytes all >= 4 -> result = 0 */
    asm volatile("xperm8 %0, %1, %2" : "=r"(r) : "r"(0xAABBCCDDu), "r"(0x04040404u));
    chk32u("xperm8 all OOB -> 0",      r, 0u);

    /* Partial OOB: rs2 = 0x04000102 -> byte[3]=4(OOB->0), byte[2]=0->DD, byte[1]=1->CC, byte[0]=2->BB */
    asm volatile("xperm8 %0, %1, %2" : "=r"(r) : "r"(0xAABBCCDDu), "r"(0x04000102u));
    chk32u("xperm8 partial OOB",       r, 0x00DDCCBBu);

    /* S-box lookup simulation: lookup rs1.byte by index in rs2 */
    /* rs1 = 0x03020100, rs2 = 0x01020300 -> rd.byte[0]=0x00, .byte[1]=0x03, .byte[2]=0x02, .byte[3]=0x01 */
    asm volatile("xperm8 %0, %1, %2" : "=r"(r) : "r"(0x03020100u), "r"(0x01020300u));
    chk32u("xperm8 lookup",            r, 0x01020300u);
}

/* -- XPERM4 ---------------------------------------------------------------- */
/*
 * xperm4 rd, rs1, rs2:
 *   For each nibble position i (0=lowest):
 *     idx = rs2.nibble[i]
 *     rd.nibble[i] = (idx < 8) ? rs1.nibble[idx] : 0
 */
static void test_xperm4(void) {
    log_write(NONE, "\n=== XPERM4 (nibble permutation) ===\n");
    uint32_t r;

    /* Identity permutation:
     * rs1 = 0x76543210: nibble[i] = i
     * rs2 = 0x76543210: nibble[i] = i -> rd.nibble[i] = rs1.nibble[i] = i
     * result = 0x76543210
     */
    asm volatile("xperm4 %0, %1, %2" : "=r"(r) : "r"(0x76543210u), "r"(0x76543210u));
    chk32u("xperm4 identity",          r, 0x76543210u);

    /* Nibble-reversal:
     * rs2 = 0x01234567: nibble[0]=7, nibble[1]=6, ..., nibble[7]=0
     * rd.nibble[i] = rs1.nibble[7-i]
     * result = 0x01234567 (nibble[7]=0, ..., nibble[0]=7)
     */
    asm volatile("xperm4 %0, %1, %2" : "=r"(r) : "r"(0x76543210u), "r"(0x01234567u));
    chk32u("xperm4 nibble-reverse",    r, 0x01234567u);

    /* Broadcast nibble[0]:
     * rs1 = 0x76543210: nibble[0] = 0
     * rs2 = 0x00000000: all select nibble[0] -> result = 0x00000000
     */
    asm volatile("xperm4 %0, %1, %2" : "=r"(r) : "r"(0x76543210u), "r"(0x00000000u));
    chk32u("xperm4 broadcast nibble[0]=0", r, 0x00000000u);

    /* Broadcast nibble[7]:
     * nibble[7] = 7
     * rs2 = 0x77777777: all select nibble[7] -> result = 0x77777777
     */
    asm volatile("xperm4 %0, %1, %2" : "=r"(r) : "r"(0x76543210u), "r"(0x77777777u));
    chk32u("xperm4 broadcast nibble[7]=7", r, 0x77777777u);

    /* All out-of-range: nibble indices all >= 8 -> result = 0 */
    asm volatile("xperm4 %0, %1, %2" : "=r"(r) : "r"(0x76543210u), "r"(0x88888888u));
    chk32u("xperm4 all OOB -> 0",       r, 0u);

    /* Mixed OOB:
     * rs1 = 0x76543210 (nibble[i]=i), rs2 = 0x08070605:
     *   rs2.nibble[0]=5 -> rd[0]=rs1.nibble[5]=5
     *   rs2.nibble[1]=0 -> rd[1]=rs1.nibble[0]=0
     *   rs2.nibble[2]=6 -> rd[2]=rs1.nibble[6]=6
     *   rs2.nibble[3]=0 -> rd[3]=rs1.nibble[0]=0
     *   rs2.nibble[4]=7 -> rd[4]=rs1.nibble[7]=7
     *   rs2.nibble[5]=0 -> rd[5]=rs1.nibble[0]=0
     *   rs2.nibble[6]=8 (OOB) -> rd[6]=0
     *   rs2.nibble[7]=0 -> rd[7]=rs1.nibble[0]=0
     * result = 0x00070605
     */
    asm volatile("xperm4 %0, %1, %2" : "=r"(r) : "r"(0x76543210u), "r"(0x08070605u));
    chk32u("xperm4 mixed OOB",         r, 0x00070605u);

    /* AES-like nibble S-box lookup:
     * rs1 = 0xFEDCBA98: nibble[0]=8,1=9,2=A,3=B,4=C,5=D,6=E,7=F
     * rs2 = 0x76543210: select nibble[i]=i -> identity
     * result = 0xFEDCBA98
     */
    asm volatile("xperm4 %0, %1, %2" : "=r"(r) : "r"(0xFEDCBA98u), "r"(0x76543210u));
    chk32u("xperm4 identity (0xFEDCBA98)", r, 0xFEDCBA98u);
}

/* -- CLMUL-based CRC-like checksum ---------------------------------------- */
/*
 * Simple application: use CLMUL to compute a 32-bit carry-less hash
 * of a small data buffer. Verifies CLMUL works in a real use-case.
 */
static uint32_t clmul_hash(const uint32_t *data, int n, uint32_t key) {
    uint32_t acc = 0;
    for (int i = 0; i < n; i++) {
        uint32_t product;
        asm volatile("clmul %0, %1, %2" : "=r"(product)
                     : "r"(data[i] ^ acc), "r"(key));
        acc = product;
    }
    return acc;
}

static void test_clmul_hash(void) {
    log_write(NONE, "\n=== CLMUL application: carry-less hash ===\n");
    static const uint32_t data1[] = {0x11111111u, 0x22222222u, 0x33333333u};
    static const uint32_t data2[] = {0x11111111u, 0x22222222u, 0x33333334u};  /* differs by 1 bit */
    uint32_t key = 0x9E3779B9u;  /* Golden-ratio constant */

    uint32_t h1 = clmul_hash(data1, 3, key);
    uint32_t h2 = clmul_hash(data2, 3, key);
    uint32_t h1b = clmul_hash(data1, 3, key);  /* determinism check */

    /* Hash should be non-zero for non-zero input */
    int ok = (h1 != 0);
    if (ok) { log_write(NONE, "  PASS  clmul hash non-zero (0x%x)\n", h1); g_pass++; }
    else     { log_write(NONE, "  FAIL  clmul hash is zero\n"); g_fail++; }

    /* Different inputs -> different hashes */
    ok = (h1 != h2);
    if (ok) { log_write(NONE, "  PASS  clmul hash sensitive (0x%x != 0x%x)\n", h1, h2); g_pass++; }
    else     { log_write(NONE, "  FAIL  clmul hash not sensitive\n"); g_fail++; }

    /* Deterministic */
    chk32u("clmul hash deterministic", h1, h1b);
}

/* -- Main ------------------------------------------------------------------- */

int main(void) {
    uart_puts("=== CLMUL/XPERM Test ===\n");
    if (log_init("clmul-test.log") != 0) {
        uart_puts("ERROR: log_init failed\n"); return 1;
    }
    log_write(NONE, "=== RISC-V Zbkc (CLMUL/CLMULH) + Zbkx (XPERM4/XPERM8) Test ===\n");

    test_clmul();
    test_xperm8();
    test_xperm4();
    test_clmul_hash();

    log_write(NONE, "\n=== Summary ===\n");
    log_write(NONE, "  PASS: %d\n", g_pass);
    log_write(NONE, "  FAIL: %d\n", g_fail);
    log_write(NONE, "  %s\n", g_fail == 0 ? "ALL TESTS PASSED" : "SOME TESTS FAILED");
    log_close();

    uart_puts(g_fail == 0 ? "ALL PASSED\n" : "SOME FAILED\n");
    return g_fail;
}
