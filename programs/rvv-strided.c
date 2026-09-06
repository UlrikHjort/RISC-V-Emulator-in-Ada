/* **************************************************************************
 *     RISC-V Emulator - RVV strided and indexed memory operation test
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

// rvv-strided.c -- RVV strided and indexed memory operation test.
//
// Tests:
//   vlse32.v  (strided load, 32-bit elements)
//   vsse32.v  (strided store, 32-bit elements)
//   vlse16.v  (strided load, 16-bit elements)
//   vsse16.v  (strided store, 16-bit elements)
//   vlse8.v   (strided load, 8-bit elements)
//   vsse8.v   (strided store, 8-bit elements)
//   vloxei32.v (indexed unordered load, 32-bit offsets)
//   vsoxei32.v (indexed unordered store, 32-bit offsets)
//
// Build: cd programs && make run-rvv-strided
// By Ulrik Hørlyk Hjort 2026

#include <stdint.h>
#include "log.h"

static void fill32(int32_t *p, int32_t val, int n) {
    for (int i = 0; i < n; i++) p[i] = val;
}
static void fill16(int16_t *p, int16_t val, int n) {
    for (int i = 0; i < n; i++) p[i] = val;
}
static void fill8(uint8_t *p, uint8_t val, int n) {
    for (int i = 0; i < n; i++) p[i] = val;
}

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

// -- Strided 32-bit load/store ---------------------------------------------

static void test_strided32(void) {
    log_write(NONE, "\n=== vlse32/vsse32 (stride 8, every other word) ===\n");

    // Source: 8 words, stride 8 = pick elements 0, 2, 4, 6
    static const int32_t src[8] = {
        10, 99, 20, 99, 30, 99, 40, 99
    };
    int32_t dst[4] = {0, 0, 0, 0};

    asm volatile(
        "vsetivli zero, 4, e32, m1, ta, ma\n"
        "vlse32.v v0, (%0), %1\n"
        "vse32.v  v0, (%2)\n"
        :: "r"(src), "r"((int32_t)8), "r"(dst)
        : "memory"
    );

    check32("stride8: dst[0]=10", dst[0], 10);
    check32("stride8: dst[1]=20", dst[1], 20);
    check32("stride8: dst[2]=30", dst[2], 30);
    check32("stride8: dst[3]=40", dst[3], 40);

    // Strided store: write to every other element (stride 8)
    log_write(NONE, "\n=== vsse32 (stride 8 store) ===\n");
    int32_t out[8];
    fill32(out, -1, 8);  // fill with sentinel 0xFFFFFFFF

    static const int32_t vals[4] = {100, 200, 300, 400};
    asm volatile(
        "vsetivli zero, 4, e32, m1, ta, ma\n"
        "vle32.v  v1, (%0)\n"
        "vsse32.v v1, (%1), %2\n"
        :: "r"(vals), "r"(out), "r"((int32_t)8)
        : "memory"
    );

    check32("sstr8: out[0]=100",          out[0], 100);
    check32("sstr8: out[1] unchanged",    out[1], -1);   // 0xFFFFFFFF
    check32("sstr8: out[2]=200",          out[2], 200);
    check32("sstr8: out[3] unchanged",    out[3], -1);
    check32("sstr8: out[4]=300",          out[4], 300);
    check32("sstr8: out[5] unchanged",    out[5], -1);
    check32("sstr8: out[6]=400",          out[6], 400);
    check32("sstr8: out[7] unchanged",    out[7], -1);
}

// -- Strided 32-bit with negative stride ----------------------------------

static void test_strided32_neg(void) {
    log_write(NONE, "\n=== vlse32 (negative stride, reverse read) ===\n");

    // Read 4 words backwards: start at src[3], stride=-4
    static const int32_t src[4] = {1, 2, 3, 4};
    int32_t dst[4] = {0};

    asm volatile(
        "vsetivli zero, 4, e32, m1, ta, ma\n"
        "vlse32.v v2, (%0), %1\n"
        "vse32.v  v2, (%2)\n"
        :: "r"(src + 3), "r"((int32_t)-4), "r"(dst)
        : "memory"
    );

    check32("neg stride: dst[0]=4", dst[0], 4);
    check32("neg stride: dst[1]=3", dst[1], 3);
    check32("neg stride: dst[2]=2", dst[2], 2);
    check32("neg stride: dst[3]=1", dst[3], 1);
}

// -- Strided 16-bit --------------------------------------------------------

static void test_strided16(void) {
    log_write(NONE, "\n=== vlse16/vsse16 (stride 4, 16-bit) ===\n");

    // 8 halfwords, stride 4 bytes = every other halfword (skip 1 halfword)
    static const int16_t src[8] = {
        10, -1, 20, -1, 30, -1, 40, -1
    };
    int32_t dst[4] = {0};  // store result as 32-bit for check

    asm volatile(
        "vsetivli zero, 4, e16, m1, ta, ma\n"
        "vlse16.v v3, (%0), %1\n"
        "vsetivli zero, 4, e32, m1, ta, ma\n"
        "vsext.vf2 v4, v3\n"    // sign-extend e16 -> e32
        "vse32.v   v4, (%2)\n"
        :: "r"(src), "r"((int32_t)4), "r"(dst)
        : "memory"
    );

    check32("vlse16 stride4: dst[0]=10", dst[0], 10);
    check32("vlse16 stride4: dst[1]=20", dst[1], 20);
    check32("vlse16 stride4: dst[2]=30", dst[2], 30);
    check32("vlse16 stride4: dst[3]=40", dst[3], 40);

    // Strided 16-bit store
    log_write(NONE, "\n=== vsse16 (stride 4 store) ===\n");
    int16_t out[8];
    fill16(out, (int16_t)0xAAAA, 8);
    static const int16_t wvals[4] = {11, 22, 33, 44};

    asm volatile(
        "vsetivli zero, 4, e16, m1, ta, ma\n"
        "vle16.v  v5, (%0)\n"
        "vsse16.v v5, (%1), %2\n"
        :: "r"(wvals), "r"(out), "r"((int32_t)4)
        : "memory"
    );

    check32("vsse16 stride4: out[0]=11",  (int32_t)out[0], 11);
    check32("vsse16 stride4: out[1]=0xAAAA", (int32_t)(uint16_t)out[1], 0xAAAA);
    check32("vsse16 stride4: out[2]=22",  (int32_t)out[2], 22);
    check32("vsse16 stride4: out[4]=33",  (int32_t)out[4], 33);
    check32("vsse16 stride4: out[6]=44",  (int32_t)out[6], 44);
}

// -- Strided 8-bit ---------------------------------------------------------

static void test_strided8(void) {
    log_write(NONE, "\n=== vlse8/vsse8 (stride 3, 8-bit) ===\n");

    // Bytes spaced 3 apart: pick positions 0, 3, 6, 9
    static const uint8_t src[12] = {
        0xAA, 0,0, 0xBB, 0,0, 0xCC, 0,0, 0xDD, 0,0
    };
    uint8_t dst[4] = {0};

    asm volatile(
        "vsetivli zero, 4, e8, m1, ta, ma\n"
        "vlse8.v v6, (%0), %1\n"
        "vse8.v  v6, (%2)\n"
        :: "r"(src), "r"((int32_t)3), "r"(dst)
        : "memory"
    );

    check32("vlse8 stride3: dst[0]=0xAA", (int32_t)dst[0], 0xAA);
    check32("vlse8 stride3: dst[1]=0xBB", (int32_t)dst[1], 0xBB);
    check32("vlse8 stride3: dst[2]=0xCC", (int32_t)dst[2], 0xCC);
    check32("vlse8 stride3: dst[3]=0xDD", (int32_t)dst[3], 0xDD);

    // Strided 8-bit store
    log_write(NONE, "\n=== vsse8 (stride 2 store) ===\n");
    uint8_t out[8];
    fill8(out, 0x55, 8);
    static const uint8_t bvals[4] = {0x11, 0x22, 0x33, 0x44};

    asm volatile(
        "vsetivli zero, 4, e8, m1, ta, ma\n"
        "vle8.v  v7, (%0)\n"
        "vsse8.v v7, (%1), %2\n"
        :: "r"(bvals), "r"(out), "r"((int32_t)2)
        : "memory"
    );

    check32("vsse8 stride2: out[0]=0x11", (int32_t)out[0], 0x11);
    check32("vsse8 stride2: out[1]=0x55", (int32_t)out[1], 0x55);
    check32("vsse8 stride2: out[2]=0x22", (int32_t)out[2], 0x22);
    check32("vsse8 stride2: out[3]=0x55", (int32_t)out[3], 0x55);
    check32("vsse8 stride2: out[4]=0x33", (int32_t)out[4], 0x33);
    check32("vsse8 stride2: out[6]=0x44", (int32_t)out[6], 0x44);
}

// -- Indexed (gather/scatter) -----------------------------------------------

static void test_indexed(void) {
    log_write(NONE, "\n=== vloxei32.v (indexed gather, 32-bit offsets) ===\n");

    // Source array: elements at various offsets
    static const int32_t src[8] = {0, 10, 20, 30, 40, 50, 60, 70};

    // Byte offsets for gather: pick elements 7,3,5,1 (multiply index by 4 for bytes)
    static const uint32_t offsets[4] = {7*4, 3*4, 5*4, 1*4};
    int32_t dst[4] = {0};

    asm volatile(
        "vsetivli zero, 4, e32, m1, ta, ma\n"
        "vle32.v    v8, (%0)\n"     // load offsets into v8
        "vloxei32.v v9, (%1), v8\n" // indexed load from src using offsets in v8
        "vse32.v    v9, (%2)\n"
        :: "r"(offsets), "r"(src), "r"(dst)
        : "memory"
    );

    check32("gather: dst[0]=70 (src[7])", dst[0], 70);
    check32("gather: dst[1]=30 (src[3])", dst[1], 30);
    check32("gather: dst[2]=50 (src[5])", dst[2], 50);
    check32("gather: dst[3]=10 (src[1])", dst[3], 10);

    // Indexed store (scatter)
    log_write(NONE, "\n=== vsoxei32.v (indexed scatter, 32-bit offsets) ===\n");
    int32_t out[8];
    fill32(out, 0, 8);
    // Scatter values {1,2,3,4} to positions {6,4,2,0}
    static const uint32_t soffs[4] = {6*4, 4*4, 2*4, 0*4};
    static const int32_t svals[4] = {100, 200, 300, 400};

    asm volatile(
        "vsetivli zero, 4, e32, m1, ta, ma\n"
        "vle32.v     v10, (%0)\n"       // offsets
        "vle32.v     v11, (%1)\n"       // values
        "vsoxei32.v  v11, (%2), v10\n"  // scatter
        :: "r"(soffs), "r"(svals), "r"(out)
        : "memory"
    );

    check32("scatter: out[0]=400", out[0], 400);
    check32("scatter: out[1]=0",   out[1], 0);
    check32("scatter: out[2]=300", out[2], 300);
    check32("scatter: out[4]=200", out[4], 200);
    check32("scatter: out[6]=100", out[6], 100);
}

// -- Zero stride (broadcast) -----------------------------------------------

static void test_zero_stride(void) {
    log_write(NONE, "\n=== vlse32 (stride 0 = broadcast) ===\n");

    int32_t scalar = 42;
    int32_t dst[4] = {0};

    asm volatile(
        "vsetivli zero, 4, e32, m1, ta, ma\n"
        "vlse32.v v12, (%0), zero\n"  // stride=0 -> all elements = scalar
        "vse32.v  v12, (%1)\n"
        :: "r"(&scalar), "r"(dst)
        : "memory"
    );

    check32("broadcast: dst[0]=42", dst[0], 42);
    check32("broadcast: dst[1]=42", dst[1], 42);
    check32("broadcast: dst[2]=42", dst[2], 42);
    check32("broadcast: dst[3]=42", dst[3], 42);
}

// -- Main ------------------------------------------------------------------

int main(void) {
    uart_puts("=== RVV Strided/Indexed Test ===\n");
    if (log_init("rvv-strided.log") != 0) {
        uart_puts("ERROR: log_init failed\n"); return 1;
    }

    log_write(NONE, "=== RVV Strided/Indexed Memory Test (RV32IMCVZve32x) ===\n");

    test_strided32();
    test_strided32_neg();
    test_strided16();
    test_strided8();
    test_indexed();
    test_zero_stride();

    log_write(NONE, "\n=== Summary ===\n");
    log_write(NONE, "  PASS: %d\n", g_pass);
    log_write(NONE, "  FAIL: %d\n", g_fail);
    log_write(NONE, "  %s\n", g_fail == 0 ? "ALL TESTS PASSED" : "SOME TESTS FAILED");

    log_close();
    uart_puts(g_fail == 0 ? "ALL PASSED\n" : "SOME FAILED\n");
    return g_fail;
}
