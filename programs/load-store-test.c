/* **************************************************************************
 *              RISC-V Emulator - Load/store instruction test
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

// load-store-test.c -- Load/store instruction test.
//
// Tests every load and store width with sign/zero extension:
//   LB  (load byte, sign-extend)
//   LBU (load byte, zero-extend)
//   LH  (load halfword, sign-extend)
//   LHU (load halfword, zero-extend)
//   LW  (load word)
//   SB  (store byte)
//   SH  (store halfword)
//   SW  (store word)
//
// Key cases:
//   - Sign extension of negative values (0x80, 0x8000)
//   - Zero extension (high bit set, no sign propagation)
//   - Store narrows correctly (SB stores low byte, SH stores low halfword)
//   - Stores don't corrupt adjacent bytes
//   - Read-back after each store
//
// Build: cd programs && make run-load-store-test
// By Ulrik Hørlyk Hjort 2026

#include <stdint.h>
#include "log.h"

void putchar(char c);
static void uart_puts(const char *s) {
    while (*s) { if (*s == '\n') putchar('\r'); putchar(*s++); }
}

static int g_pass = 0, g_fail = 0;

static void check32(const char *label, int32_t got, int32_t expected) {
    if (got == expected) {
        log_write(NONE, "  PASS  %s\n", label); g_pass++;
    } else {
        log_write(NONE, "  FAIL  %s: got 0x%x  exp 0x%x\n",
                  label, (uint32_t)got, (uint32_t)expected);
        g_fail++;
    }
}

// Force actual LB/LBU/LH/LHU/LW via asm to prevent compiler substitution

static inline int32_t do_lb(const void *p) {
    int32_t r; asm volatile("lb %0, 0(%1)" : "=r"(r) : "r"(p)); return r;
}
static inline uint32_t do_lbu(const void *p) {
    uint32_t r; asm volatile("lbu %0, 0(%1)" : "=r"(r) : "r"(p)); return r;
}
static inline int32_t do_lh(const void *p) {
    int32_t r; asm volatile("lh %0, 0(%1)" : "=r"(r) : "r"(p)); return r;
}
static inline uint32_t do_lhu(const void *p) {
    uint32_t r; asm volatile("lhu %0, 0(%1)" : "=r"(r) : "r"(p)); return r;
}
static inline int32_t do_lw(const void *p) {
    int32_t r; asm volatile("lw %0, 0(%1)" : "=r"(r) : "r"(p)); return r;
}
static inline void do_sb(void *p, uint8_t v) {
    asm volatile("sb %0, 0(%1)" :: "r"((uint32_t)v), "r"(p) : "memory");
}
static inline void do_sh(void *p, uint16_t v) {
    asm volatile("sh %0, 0(%1)" :: "r"((uint32_t)v), "r"(p) : "memory");
}
static inline void do_sw(void *p, uint32_t v) {
    asm volatile("sw %0, 0(%1)" :: "r"(v), "r"(p) : "memory");
}

// -- LB (sign-extend byte) -------------------------------------------------

static void test_lb(void) {
    log_write(NONE, "\n=== LB (load byte, sign-extend) ===\n");
    static const uint8_t buf[] = {0x00, 0x01, 0x7F, 0x80, 0xFF};

    check32("lb 0x00 =  0",   do_lb(buf+0),  0x00000000);
    check32("lb 0x01 =  1",   do_lb(buf+1),  0x00000001);
    check32("lb 0x7F =  127", do_lb(buf+2),  0x0000007F);
    // Sign-extended: 0x80 -> 0xFFFFFF80
    check32("lb 0x80 = -128", do_lb(buf+3),  (int32_t)0xFFFFFF80);
    // Sign-extended: 0xFF -> 0xFFFFFFFF = -1
    check32("lb 0xFF = -1",   do_lb(buf+4),  (int32_t)0xFFFFFFFF);
}

// -- LBU (zero-extend byte) ------------------------------------------------

static void test_lbu(void) {
    log_write(NONE, "\n=== LBU (load byte, zero-extend) ===\n");
    static const uint8_t buf[] = {0x00, 0x01, 0x7F, 0x80, 0xFF};

    check32("lbu 0x00 = 0",   (int32_t)do_lbu(buf+0), 0x00);
    check32("lbu 0x01 = 1",   (int32_t)do_lbu(buf+1), 0x01);
    check32("lbu 0x7F = 127", (int32_t)do_lbu(buf+2), 0x7F);
    // No sign extension: 0x80 stays 0x80
    check32("lbu 0x80 = 128", (int32_t)do_lbu(buf+3), 0x80);
    check32("lbu 0xFF = 255", (int32_t)do_lbu(buf+4), 0xFF);
}

// -- LH (sign-extend halfword) ---------------------------------------------

static void test_lh(void) {
    log_write(NONE, "\n=== LH (load halfword, sign-extend) ===\n");
    // Must be 2-byte aligned
    static const uint16_t buf[] = {0x0000, 0x0001, 0x7FFF, 0x8000, 0xFFFF};

    check32("lh 0x0000 =  0",      do_lh(buf+0), 0x00000000);
    check32("lh 0x0001 =  1",      do_lh(buf+1), 0x00000001);
    check32("lh 0x7FFF =  32767",  do_lh(buf+2), 0x00007FFF);
    // Sign-extended: 0x8000 -> 0xFFFF8000
    check32("lh 0x8000 = -32768",  do_lh(buf+3), (int32_t)0xFFFF8000);
    check32("lh 0xFFFF = -1",      do_lh(buf+4), (int32_t)0xFFFFFFFF);
}

// -- LHU (zero-extend halfword) --------------------------------------------

static void test_lhu(void) {
    log_write(NONE, "\n=== LHU (load halfword, zero-extend) ===\n");
    static const uint16_t buf[] = {0x0000, 0x7FFF, 0x8000, 0xFFFF};

    check32("lhu 0x0000 = 0",     (int32_t)do_lhu(buf+0), 0x0000);
    check32("lhu 0x7FFF = 32767", (int32_t)do_lhu(buf+1), 0x7FFF);
    check32("lhu 0x8000 = 32768", (int32_t)do_lhu(buf+2), 0x8000);
    check32("lhu 0xFFFF = 65535", (int32_t)do_lhu(buf+3), 0xFFFF);
}

// -- LW (word, no extension needed) ---------------------------------------

static void test_lw(void) {
    log_write(NONE, "\n=== LW (load word) ===\n");
    static const uint32_t buf[] = {0x00000000, 0x00000001, 0x7FFFFFFF,
                                    0x80000000, 0xFFFFFFFF, 0x12345678};
    check32("lw 0x00000000",  do_lw(buf+0), (int32_t)0x00000000);
    check32("lw 0x00000001",  do_lw(buf+1), (int32_t)0x00000001);
    check32("lw 0x7FFFFFFF",  do_lw(buf+2), (int32_t)0x7FFFFFFF);
    check32("lw 0x80000000",  do_lw(buf+3), (int32_t)0x80000000);
    check32("lw 0xFFFFFFFF",  do_lw(buf+4), (int32_t)0xFFFFFFFF);
    check32("lw 0x12345678",  do_lw(buf+5), (int32_t)0x12345678);
}

// -- SB (store byte, narrow) -----------------------------------------------

static void test_sb(void) {
    log_write(NONE, "\n=== SB (store byte) ===\n");
    static uint32_t buf;

    // Fill with known sentinel
    buf = 0xDEADBEEF;
    do_sb(&buf, 0x42);
    // Little-endian: byte 0 = 0x42, rest unchanged
    check32("sb 0x42: buf[0]=0x42", (int32_t)(buf & 0xFF), 0x42);
    check32("sb 0x42: buf[1..3] unchanged", (int32_t)(buf >> 8), (int32_t)0xDEADBE);

    buf = 0xDEADBEEF;
    do_sb(&buf, 0xFF);
    check32("sb 0xFF: buf = 0xDEADBEFF", buf, (int32_t)0xDEADBEFF);

    buf = 0xDEADBEEF;
    do_sb(&buf, 0x00);
    check32("sb 0x00: buf = 0xDEADBE00", buf, (int32_t)0xDEADBE00);

    // SB stores only low 8 bits of source
    buf = 0xDEADBEEF;
    do_sb(&buf, (uint8_t)0x12345678);  // only 0x78 stored
    check32("sb 0x78 (from 0x12345678)", (int32_t)(buf & 0xFF), 0x78);
}

// -- SH (store halfword, narrow) -------------------------------------------

static void test_sh(void) {
    log_write(NONE, "\n=== SH (store halfword) ===\n");
    static uint32_t buf;

    buf = 0xDEADBEEF;
    do_sh(&buf, 0x1234);
    // Little-endian: low 16 bits = 0x1234, high 16 bits unchanged
    check32("sh 0x1234: low16=0x1234", (int32_t)(buf & 0xFFFF), 0x1234);
    check32("sh 0x1234: high16=0xDEAD", (int32_t)(buf >> 16), (int32_t)0xDEAD);

    buf = 0xDEADBEEF;
    do_sh(&buf, 0x8000);
    check32("sh 0x8000: buf = 0xDEAD8000", buf, (int32_t)0xDEAD8000);

    buf = 0xDEADBEEF;
    do_sh(&buf, 0xFFFF);
    check32("sh 0xFFFF: buf = 0xDEADFFFF", buf, (int32_t)0xDEADFFFF);

    // SH stores only low 16 bits
    buf = 0xDEADBEEF;
    do_sh(&buf, (uint16_t)0x12345678); // only 0x5678 stored
    check32("sh 0x5678 (from 0x12345678)", (int32_t)(buf & 0xFFFF), 0x5678);
}

// -- SW (store word) -------------------------------------------------------

static void test_sw(void) {
    log_write(NONE, "\n=== SW (store word) ===\n");
    static uint32_t buf;

    do_sw(&buf, 0x00000000); check32("sw 0x00000000", buf, (int32_t)0x00000000);
    do_sw(&buf, 0x12345678); check32("sw 0x12345678", buf, (int32_t)0x12345678);
    do_sw(&buf, 0x80000000); check32("sw 0x80000000", buf, (int32_t)0x80000000);
    do_sw(&buf, 0xFFFFFFFF); check32("sw 0xFFFFFFFF", buf, (int32_t)0xFFFFFFFF);
    do_sw(&buf, 0xDEADBEEF); check32("sw 0xDEADBEEF", buf, (int32_t)0xDEADBEEF);
}

// -- Byte array: mixed reads at different offsets ---------------------------

static void test_mixed(void) {
    log_write(NONE, "\n=== Mixed access (store word, read bytes/halves) ===\n");
    static uint32_t word;

    // Store a known word and read back bytes
    // Little-endian: 0xAABBCCDD -> byte[0]=0xDD, [1]=0xCC, [2]=0xBB, [3]=0xAA
    do_sw(&word, 0xAABBCCDD);
    uint8_t *b = (uint8_t *)&word;
    check32("byte[0] of 0xAABBCCDD = 0xDD", (int32_t)do_lbu(b+0), 0xDD);
    check32("byte[1] of 0xAABBCCDD = 0xCC", (int32_t)do_lbu(b+1), 0xCC);
    check32("byte[2] of 0xAABBCCDD = 0xBB", (int32_t)do_lbu(b+2), 0xBB);
    check32("byte[3] of 0xAABBCCDD = 0xAA", (int32_t)do_lbu(b+3), 0xAA);

    // Read halfwords
    uint16_t *h = (uint16_t *)&word;
    check32("half[0] of 0xAABBCCDD = 0xCCDD", (int32_t)do_lhu(h+0), 0xCCDD);
    check32("half[1] of 0xAABBCCDD = 0xAABB", (int32_t)do_lhu(h+1), 0xAABB);

    // Sign extension from halfword
    do_sw(&word, 0x00008000);  // low halfword = 0x8000
    check32("lh 0x8000 sign-extended", do_lh((uint16_t *)&word), (int32_t)0xFFFF8000);
    check32("lhu 0x8000 zero-extended", (int32_t)do_lhu((uint16_t *)&word), 0x8000);
}

// -- Sequential byte stores don't bleed ------------------------------------

static void test_byte_isolation(void) {
    log_write(NONE, "\n=== Byte store isolation ===\n");
    static uint8_t buf[4];

    // Store 4 different bytes
    do_sb(buf+0, 0x11);
    do_sb(buf+1, 0x22);
    do_sb(buf+2, 0x33);
    do_sb(buf+3, 0x44);

    check32("buf[0]=0x11", do_lbu(buf+0), 0x11);
    check32("buf[1]=0x22", do_lbu(buf+1), 0x22);
    check32("buf[2]=0x33", do_lbu(buf+2), 0x33);
    check32("buf[3]=0x44", do_lbu(buf+3), 0x44);

    // Overwrite middle bytes only
    do_sb(buf+1, 0xFF);
    check32("after sb buf[0] unchanged=0x11", do_lbu(buf+0), 0x11);
    check32("after sb buf[1]=0xFF",           do_lbu(buf+1), 0xFF);
    check32("after sb buf[2] unchanged=0x33", do_lbu(buf+2), 0x33);
    check32("after sb buf[3] unchanged=0x44", do_lbu(buf+3), 0x44);
}

// -- Main ------------------------------------------------------------------

int main(void) {
    uart_puts("=== Load/Store Test ===\n");
    if (log_init("load-store-test.log") != 0) {
        uart_puts("ERROR: log_init failed\n"); return 1;
    }

    log_write(NONE, "=== Load/Store Instruction Test (RV32IMC) ===\n");

    test_lb();
    test_lbu();
    test_lh();
    test_lhu();
    test_lw();
    test_sb();
    test_sh();
    test_sw();
    test_mixed();
    test_byte_isolation();

    log_write(NONE, "\n=== Summary ===\n");
    log_write(NONE, "  PASS: %d\n", g_pass);
    log_write(NONE, "  FAIL: %d\n", g_fail);
    log_write(NONE, "  %s\n", g_fail == 0 ? "ALL TESTS PASSED" : "SOME TESTS FAILED");

    log_close();
    uart_puts(g_fail == 0 ? "ALL PASSED\n" : "SOME FAILED\n");
    return g_fail;
}
