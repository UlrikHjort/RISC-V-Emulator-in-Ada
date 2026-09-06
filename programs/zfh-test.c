/* **************************************************************************
 *      RISC-V Emulator - Zfh (IEEE 754 half-precision) extension test
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

/*
 * zfh-test.c -- Zfh (IEEE 754 half-precision) extension test
 *
 * Tests basic fp16 arithmetic and conversion instructions using
 * explicit inline asm.
 *
 * fp16 bit patterns used:
 *   1.0h  = 0x3C00
 *   2.0h  = 0x4000
 *   3.0h  = 0x4200
 *   4.0h  = 0x4400
 *   6.0h  = 0x4600
 *   1.5h  = 0x3E00
 *   +Inf  = 0x7C00
 *
 * By Ulrik Hørlyk Hjort 2026
 */
#include <stdint.h>
#include "log.h"

static int g_pass = 0, g_fail = 0;

static void chk(const char *label, int ok)
{
    if (ok) {
        log_write(NONE, "PASS %s\n", label);
        g_pass++;
    } else {
        log_write(NONE, "FAIL %s\n", label);
        g_fail++;
    }
}

int main(void)
{
    uint32_t result;

    log_init("zfh-test.log");
    log_write(NONE, "=== Zfh Half-Precision Test ===\n");

    /* Test 1: FMV.H.X + FMV.X.H round-trip */
    {
        uint32_t val_in = 0x3C00;  /* 1.0h */
        uint32_t val_out;
        asm volatile(
            "fmv.h.x fa0, %1\n\t"
            "fmv.x.h %0, fa0\n\t"
            : "=r"(val_out) : "r"(val_in) : "fa0");
        log_write(NONE, "FMV round-trip 0x3C00: got 0x%x\n", val_out);
        chk("FMV.H.X + FMV.X.H round-trip 1.0h", val_out == 0x3C00);
    }

    /* Test 2: FADD.H: 1.0h + 1.0h = 2.0h */
    {
        uint32_t a = 0x3C00, b = 0x3C00;
        asm volatile(
            "fmv.h.x fa0, %1\n\t"
            "fmv.h.x fa1, %2\n\t"
            "fadd.h  fa2, fa0, fa1\n\t"
            "fmv.x.h %0,  fa2\n\t"
            : "=r"(result) : "r"(a), "r"(b) : "fa0", "fa1", "fa2");
        log_write(NONE, "FADD.H 1.0+1.0: got 0x%x (expect 0x4000)\n", result);
        chk("FADD.H 1.0h + 1.0h = 2.0h", result == 0x4000);
    }

    /* Test 3: FMUL.H: 2.0h * 3.0h = 6.0h */
    {
        uint32_t a = 0x4000, b = 0x4200;
        asm volatile(
            "fmv.h.x fa0, %1\n\t"
            "fmv.h.x fa1, %2\n\t"
            "fmul.h  fa2, fa0, fa1\n\t"
            "fmv.x.h %0,  fa2\n\t"
            : "=r"(result) : "r"(a), "r"(b) : "fa0", "fa1", "fa2");
        log_write(NONE, "FMUL.H 2.0*3.0: got 0x%x (expect 0x4600)\n", result);
        chk("FMUL.H 2.0h * 3.0h = 6.0h", result == 0x4600);
    }

    /* Test 4: FDIV.H: 6.0h / 2.0h = 3.0h */
    {
        uint32_t a = 0x4600, b = 0x4000;
        asm volatile(
            "fmv.h.x fa0, %1\n\t"
            "fmv.h.x fa1, %2\n\t"
            "fdiv.h  fa2, fa0, fa1\n\t"
            "fmv.x.h %0,  fa2\n\t"
            : "=r"(result) : "r"(a), "r"(b) : "fa0", "fa1", "fa2");
        log_write(NONE, "FDIV.H 6.0/2.0: got 0x%x (expect 0x4200)\n", result);
        chk("FDIV.H 6.0h / 2.0h = 3.0h", result == 0x4200);
    }

    /* Test 5: FSQRT.H: sqrt(4.0h) = 2.0h */
    {
        uint32_t a = 0x4400;
        asm volatile(
            "fmv.h.x fa0, %1\n\t"
            "fsqrt.h fa1, fa0\n\t"
            "fmv.x.h %0,  fa1\n\t"
            : "=r"(result) : "r"(a) : "fa0", "fa1");
        log_write(NONE, "FSQRT.H sqrt(4.0): got 0x%x (expect 0x4000)\n", result);
        chk("FSQRT.H sqrt(4.0h) = 2.0h", result == 0x4000);
    }

    /* Test 6: FCVT.S.H: 1.5h (0x3E00) -> float32 (0x3FC00000) */
    {
        uint32_t a = 0x3E00;
        asm volatile(
            "fmv.h.x  fa0, %1\n\t"
            "fcvt.s.h fa1, fa0\n\t"
            "fmv.x.w  %0,  fa1\n\t"
            : "=r"(result) : "r"(a) : "fa0", "fa1");
        log_write(NONE, "FCVT.S.H 1.5h: got 0x%x (expect 0x3FC00000)\n", result);
        chk("FCVT.S.H 1.5h = 0x3FC00000", result == 0x3FC00000);
    }

    /* Test 7: FCVT.H.S: float32 1.5 (0x3FC00000) -> fp16 (0x3E00) */
    {
        uint32_t a = 0x3FC00000;
        asm volatile(
            "fmv.w.x  fa0, %1\n\t"
            "fcvt.h.s fa1, fa0\n\t"
            "fmv.x.h  %0,  fa1\n\t"
            : "=r"(result) : "r"(a) : "fa0", "fa1");
        log_write(NONE, "FCVT.H.S 1.5f: got 0x%x (expect 0x3E00)\n", result);
        chk("FCVT.H.S 1.5f = 0x3E00", result == 0x3E00);
    }

    /* Test 8: FCLASS.H: +Inf (0x7C00) -> bit 7 (value 0x80) */
    {
        uint32_t a = 0x7C00;
        asm volatile(
            "fmv.h.x  fa0, %1\n\t"
            "fclass.h %0,  fa0\n\t"
            : "=r"(result) : "r"(a) : "fa0");
        log_write(NONE, "FCLASS.H +Inf: got 0x%x (expect 0x80)\n", result);
        chk("FCLASS.H +Inf = bit 7", result == 0x80);
    }

    /* Test 9: FLT.H: 1.0h < 2.0h -> 1 */
    {
        uint32_t a = 0x3C00, b = 0x4000;
        asm volatile(
            "fmv.h.x fa0, %1\n\t"
            "fmv.h.x fa1, %2\n\t"
            "flt.h   %0,  fa0, fa1\n\t"
            : "=r"(result) : "r"(a), "r"(b) : "fa0", "fa1");
        log_write(NONE, "FLT.H 1.0<2.0: got %d (expect 1)\n", result);
        chk("FLT.H 1.0h < 2.0h = 1", result == 1);
    }

    /* Test 10: FSGNJ.H: sign injection */
    {
        /* -1.0h = 0xBC00, magnitude of 2.0h=0x4000, inject negative sign -> 0xC000 */
        uint32_t a = 0x4000, b = 0xBC00;
        asm volatile(
            "fmv.h.x  fa0, %1\n\t"
            "fmv.h.x  fa1, %2\n\t"
            "fsgnj.h  fa2, fa0, fa1\n\t"
            "fmv.x.h  %0,  fa2\n\t"
            : "=r"(result) : "r"(a), "r"(b) : "fa0", "fa1", "fa2");
        log_write(NONE, "FSGNJ.H: got 0x%x (expect 0xC000)\n", result);
        chk("FSGNJ.H inject neg sign on 2.0h = -2.0h", result == 0xC000);
    }

    /* Test 11: FCVT.W.H: 3.0h -> integer 3 */
    {
        uint32_t a = 0x4200;
        asm volatile(
            "fmv.h.x  fa0, %1\n\t"
            "fcvt.w.h %0,  fa0, rtz\n\t"
            : "=r"(result) : "r"(a) : "fa0");
        log_write(NONE, "FCVT.W.H 3.0h: got %d (expect 3)\n", result);
        chk("FCVT.W.H 3.0h = 3", result == 3);
    }

    /* Test 12: FCVT.H.W: integer 5 -> 5.0h (0x4500) */
    {
        uint32_t a = 5;
        asm volatile(
            "fcvt.h.w fa0, %1\n\t"
            "fmv.x.h  %0,  fa0\n\t"
            : "=r"(result) : "r"(a) : "fa0");
        log_write(NONE, "FCVT.H.W 5: got 0x%x (expect 0x4500)\n", result);
        chk("FCVT.H.W 5 = 5.0h (0x4500)", result == 0x4500);
    }

    /* Test 13: FLH / FSH store-load round trip */
    {
        static uint16_t store_buf[4];
        uint32_t val_in = 0x4200;  /* 3.0h */
        uint32_t val_out;
        asm volatile(
            "fmv.h.x fa0, %2\n\t"
            "fsh     fa0, 0(%1)\n\t"
            "flh     fa1, 0(%1)\n\t"
            "fmv.x.h %0,  fa1\n\t"
            : "=&r"(val_out)
            : "r"(store_buf), "r"(val_in)
            : "fa0", "fa1", "memory");
        log_write(NONE, "FLH/FSH round-trip 3.0h: got 0x%x (expect 0x4200)\n", val_out);
        chk("FLH/FSH round-trip 3.0h", val_out == 0x4200);
    }

    log_write(NONE, "\n%d PASS  %d FAIL\n", g_pass, g_fail);
    log_close();
    return g_fail ? 1 : 0;
}
