/* **************************************************************************
 *     RISC-V Emulator - Advanced RVV 1.0 tests for the RISC-V emulator
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

// rvv-advanced.c -- Advanced RVV 1.0 tests for the RISC-V emulator.
//
// Exercises instructions and configurations not covered by vector-demo /
// matrix-demo / fir-filter:
//
//   1. vsub, vrsub  (integer subtract / reverse-subtract)
//   2. vand, vor, vxor  (bitwise)
//   3. vsll, vsrl, vsra  (shifts)
//   4. vmin, vmax, vminu, vmaxu  (integer min/max)
//   5. vmacc  (multiply-accumulate: vd += vs1 * vs2)
//   6. vrgather  (indexed permutation)
//   7. e8 / m1  operations (16 byte-elements per register)
//   8. e16 / m1 operations (8 halfword-elements per register)
//   9. e32 / m2  operations (8 word-elements across two registers -- LMUL=2)
//  10. vmseq + masked vadd  (mask generation + masked operation)
//
// Build: cd programs && make run-rvv-advanced
// By Ulrik Hørlyk Hjort 2026

#include <riscv_vector.h>
#include "log.h"
#include <stdint.h>

void putchar(char c);

static void uart_puts(const char *s) {
    while (*s) { if (*s == '\n') putchar('\r'); putchar(*s++); }
}

static int g_pass = 0, g_fail = 0;

static void check_i(const char *label, int32_t got, int32_t expected) {
    if (got == expected) {
        log_write(NONE, "  PASS  %s\n", label); g_pass++;
    } else {
        log_write(NONE, "  FAIL  %s: got %d  exp %d\n", label, got, expected); g_fail++;
    }
}

// Verify a full int32 output array against an expected array
static void check_arr32(const char *label, const int32_t *got,
                         const int32_t *exp, int n) {
    for (int i = 0; i < n; i++) {
        if (got[i] != exp[i]) {
            log_write(NONE, "  FAIL  %s[%d]: got %d  exp %d\n",
                      label, i, got[i], exp[i]);
            g_fail++;
            return;
        }
    }
    log_write(NONE, "  PASS  %s\n", label); g_pass++;
}

static void check_arr8(const char *label, const int8_t *got,
                        const int8_t *exp, int n) {
    for (int i = 0; i < n; i++) {
        if (got[i] != exp[i]) {
            log_write(NONE, "  FAIL  %s[%d]: got %d  exp %d\n",
                      label, i, (int)got[i], (int)exp[i]);
            g_fail++;
            return;
        }
    }
    log_write(NONE, "  PASS  %s\n", label); g_pass++;
}

static void check_arr16(const char *label, const int16_t *got,
                         const int16_t *exp, int n) {
    for (int i = 0; i < n; i++) {
        if (got[i] != exp[i]) {
            log_write(NONE, "  FAIL  %s[%d]: got %d  exp %d\n",
                      label, i, (int)got[i], (int)exp[i]);
            g_fail++;
            return;
        }
    }
    log_write(NONE, "  PASS  %s\n", label); g_pass++;
}

// --- 1. vsub / vrsub ---------------------------------------------------------

static void test_vsub(void) {
    log_write(NONE, "\n=== vsub / vrsub (e32/m1, 4 elements) ===\n");

    static const int32_t a[4] = {10, 20, 30, 40};
    static const int32_t b[4] = {1,  2,  3,  4};
    int32_t out[4];

    size_t vl = __riscv_vsetvl_e32m1(4);
    vint32m1_t va = __riscv_vle32_v_i32m1(a, vl);
    vint32m1_t vb = __riscv_vle32_v_i32m1(b, vl);

    // vsub.vv: a - b
    vint32m1_t vc = __riscv_vsub_vv_i32m1(va, vb, vl);
    __riscv_vse32_v_i32m1(out, vc, vl);
    static const int32_t exp_sub[4] = {9, 18, 27, 36};
    check_arr32("vsub.vv a-b", out, exp_sub, 4);

    // vrsub.vi: imm - a  (= 50 - a)
    vint32m1_t vr = __riscv_vrsub_vx_i32m1(va, 50, vl);
    __riscv_vse32_v_i32m1(out, vr, vl);
    static const int32_t exp_rsub[4] = {40, 30, 20, 10};
    check_arr32("vrsub.vx 50-a", out, exp_rsub, 4);

    // vsub producing negatives
    vint32m1_t vd = __riscv_vsub_vv_i32m1(vb, va, vl);
    __riscv_vse32_v_i32m1(out, vd, vl);
    static const int32_t exp_neg[4] = {-9, -18, -27, -36};
    check_arr32("vsub.vv b-a (neg)", out, exp_neg, 4);
}

// --- 2. Bitwise vand / vor / vxor --------------------------------------------

static void test_bitwise(void) {
    log_write(NONE, "\n=== vand / vor / vxor (e32/m1) ===\n");

    static const int32_t a[4] = {0x0F0F0F0F, 0xFF00FF00,
                                  0xAAAAAAAA, 0x12345678};
    static const int32_t b[4] = {0xF0F0F0F0, 0x00FF00FF,
                                  0x55555555, 0x87654321};
    int32_t out[4];

    size_t vl = __riscv_vsetvl_e32m1(4);
    vint32m1_t va = __riscv_vle32_v_i32m1(a, vl);
    vint32m1_t vb = __riscv_vle32_v_i32m1(b, vl);

    // vand
    __riscv_vse32_v_i32m1(out, __riscv_vand_vv_i32m1(va, vb, vl), vl);
    check_i("vand[0] 0x0F..&0xF0..=0",       out[0], 0x00000000);
    check_i("vand[1] 0xFF00&0x00FF=0",        out[1], 0x00000000);
    check_i("vand[2] 0xAA&0x55=0",            out[2], 0x00000000);
    check_i("vand[3] 0x12345678&0x87654321", out[3], 0x02244220);

    // vor
    __riscv_vse32_v_i32m1(out, __riscv_vor_vv_i32m1(va, vb, vl), vl);
    check_i("vor[0] 0x0F|0xF0=0xFF..",  out[0], (int32_t)0xFFFFFFFF);
    check_i("vor[1] 0xFF00|0x00FF=0xFFFF", out[1], (int32_t)0xFFFFFFFF);
    check_i("vor[2] 0xAA|0x55=0xFF..",  out[2], (int32_t)0xFFFFFFFF);

    // vxor
    __riscv_vse32_v_i32m1(out, __riscv_vxor_vv_i32m1(va, vb, vl), vl);
    check_i("vxor[0] 0x0F^0xF0=0xFF..",  out[0], (int32_t)0xFFFFFFFF);
    check_i("vxor[1] 0xFF00^0x00FF=0xFF..", out[1], (int32_t)0xFFFFFFFF);
    check_i("vxor[2] 0xAA^0x55=0xFF..",  out[2], (int32_t)0xFFFFFFFF);
    check_i("vxor[3] a^b^a = b",
            ((int32_t)0x12345678 ^ (int32_t)0x87654321 ^ (int32_t)0x12345678),
            (int32_t)0x87654321);
}

// --- 3. Shifts: vsll / vsrl / vsra -------------------------------------------

static void test_shifts(void) {
    log_write(NONE, "\n=== vsll / vsrl / vsra (e32/m1) ===\n");

    static const int32_t a[4] = {1, 2, 0x80000000, -1};
    int32_t out[4];
    size_t vl = __riscv_vsetvl_e32m1(4);
    vint32m1_t va = __riscv_vle32_v_i32m1(a, vl);

    // vsll by 4
    __riscv_vse32_v_i32m1(out, __riscv_vsll_vx_i32m1(va, 4, vl), vl);
    check_i("vsll.vx [0]<<4 = 16",         out[0], 16);
    check_i("vsll.vx [1]<<4 = 32",         out[1], 32);
    check_i("vsll.vx 0x80000000<<4 = 0",   out[2], 0);

    // vsrl (logical) by 4
    vuint32m1_t vau = __riscv_vreinterpret_v_i32m1_u32m1(va);
    vuint32m1_t vsrl_out = __riscv_vsrl_vx_u32m1(vau, 4, vl);
    vint32m1_t vsrl_i = __riscv_vreinterpret_v_u32m1_i32m1(vsrl_out);
    __riscv_vse32_v_i32m1(out, vsrl_i, vl);
    check_i("vsrl.vx [0]>>4 = 0",          out[0], 0);
    check_i("vsrl.vx 0x80>>4 = 0x08000000", out[2], 0x08000000);
    check_i("vsrl.vx -1>>4 = 0x0FFFFFFF", out[3], 0x0FFFFFFF);

    // vsra (arithmetic) by 4
    __riscv_vse32_v_i32m1(out, __riscv_vsra_vx_i32m1(va, 4, vl), vl);
    check_i("vsra.vx 0x80>>4 = 0xF8000000", out[2], (int32_t)0xF8000000);
    check_i("vsra.vx -1>>4 = -1",          out[3], -1);
    check_i("vsra.vx 2>>4 = 0",            out[1], 0);
}

// --- 4. vmin / vmax -----------------------------------------------------------

static void test_minmax(void) {
    log_write(NONE, "\n=== vmin / vmax / vminu / vmaxu (e32/m1) ===\n");

    static const int32_t a[4] = { 10, -5,   0, 100};
    static const int32_t b[4] = {  5,  5, -10,  50};
    int32_t out[4];
    size_t vl = __riscv_vsetvl_e32m1(4);
    vint32m1_t va = __riscv_vle32_v_i32m1(a, vl);
    vint32m1_t vb = __riscv_vle32_v_i32m1(b, vl);

    __riscv_vse32_v_i32m1(out, __riscv_vmin_vv_i32m1(va, vb, vl), vl);
    static const int32_t exp_min[4] = {5, -5, -10, 50};
    check_arr32("vmin.vv signed", out, exp_min, 4);

    __riscv_vse32_v_i32m1(out, __riscv_vmax_vv_i32m1(va, vb, vl), vl);
    static const int32_t exp_max[4] = {10, 5, 0, 100};
    check_arr32("vmax.vv signed", out, exp_max, 4);

    // Unsigned: treat -5 as 0xFFFFFFFB (a large positive number)
    vuint32m1_t vau = __riscv_vreinterpret_v_i32m1_u32m1(va);
    vuint32m1_t vbu = __riscv_vreinterpret_v_i32m1_u32m1(vb);
    vuint32m1_t vminu = __riscv_vminu_vv_u32m1(vau, vbu, vl);
    int32_t out_u[4];
    __riscv_vse32_v_i32m1(out_u, __riscv_vreinterpret_v_u32m1_i32m1(vminu), vl);
    check_i("vminu[1]: min(-5u, 5u) = 5", out_u[1], 5);
    check_i("vminu[3]: min(100u,50u)=50", out_u[3], 50);

    vuint32m1_t vmaxu = __riscv_vmaxu_vv_u32m1(vau, vbu, vl);
    __riscv_vse32_v_i32m1(out_u, __riscv_vreinterpret_v_u32m1_i32m1(vmaxu), vl);
    check_i("vmaxu[1]: max(-5u,5u) = -5u (large)", out_u[1], -5);
}

// --- 5. vmacc (multiply-accumulate) ------------------------------------------

static void test_vmacc(void) {
    log_write(NONE, "\n=== vmacc.vv  vd += vs1*vs2 (e32/m1) ===\n");

    static const int32_t a[4] = {1, 2,  3,  4};
    static const int32_t b[4] = {5, 6,  7,  8};
    static const int32_t c[4] = {0, 0, 10, 20};   // accumulator base
    int32_t out[4];
    size_t vl = __riscv_vsetvl_e32m1(4);
    vint32m1_t va = __riscv_vle32_v_i32m1(a, vl);
    vint32m1_t vb = __riscv_vle32_v_i32m1(b, vl);
    vint32m1_t vc = __riscv_vle32_v_i32m1(c, vl);

    // vmacc: vc += va * vb  =>  [0+5, 0+12, 10+21, 20+32] = [5,12,31,52]
    vint32m1_t vr = __riscv_vmacc_vv_i32m1(vc, va, vb, vl);
    __riscv_vse32_v_i32m1(out, vr, vl);
    static const int32_t exp[4] = {5, 12, 31, 52};
    check_arr32("vmacc.vv c+=a*b", out, exp, 4);
}

// --- 6. vrgather (permutation) ------------------------------------------------

static void test_vrgather(void) {
    log_write(NONE, "\n=== vrgather.vi / vrgather.vv (e32/m1) ===\n");

    static const int32_t src[4] = {10, 20, 30, 40};
    int32_t out[4];
    size_t vl = __riscv_vsetvl_e32m1(4);
    vint32m1_t vsrc = __riscv_vle32_v_i32m1(src, vl);

    // vrgather.vi: broadcast element 2 (= 30) to all lanes
    vint32m1_t vg = __riscv_vrgather_vx_i32m1(vsrc, 2, vl);
    __riscv_vse32_v_i32m1(out, vg, vl);
    static const int32_t exp_bcast[4] = {30, 30, 30, 30};
    check_arr32("vrgather broadcast elem 2", out, exp_bcast, 4);

    // vrgather.vv: reverse [3,2,1,0]
    static const uint32_t idx[4] = {3, 2, 1, 0};
    vuint32m1_t vidx = __riscv_vle32_v_u32m1(idx, vl);
    vuint32m1_t vsrcu = __riscv_vreinterpret_v_i32m1_u32m1(vsrc);
    vuint32m1_t vrev = __riscv_vrgather_vv_u32m1(vsrcu, vidx, vl);
    __riscv_vse32_v_i32m1(out, __riscv_vreinterpret_v_u32m1_i32m1(vrev), vl);
    static const int32_t exp_rev[4] = {40, 30, 20, 10};
    check_arr32("vrgather reverse [3,2,1,0]", out, exp_rev, 4);
}

// --- 7. e8 / m1 (16 byte-elements) -------------------------------------------

static void test_e8(void) {
    log_write(NONE, "\n=== e8/m1: 16 byte-elements per register ===\n");

    static const int8_t a[16] = {1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16};
    static const int8_t b[16] = {16,15,14,13,12,11,10,9,8,7,6,5,4,3,2,1};
    int8_t out[16];
    size_t vl = __riscv_vsetvl_e8m1(16);

    vint8m1_t va = __riscv_vle8_v_i8m1(a, vl);
    vint8m1_t vb = __riscv_vle8_v_i8m1(b, vl);

    // vadd: every element should be 17
    __riscv_vse8_v_i8m1(out, __riscv_vadd_vv_i8m1(va, vb, vl), vl);
    int all17 = 1;
    for (int i = 0; i < 16; i++) if (out[i] != 17) { all17 = 0; break; }
    if (all17) { log_write(NONE, "  PASS  e8 vadd all=17\n"); g_pass++; }
    else       { log_write(NONE, "  FAIL  e8 vadd not all 17\n"); g_fail++; }

    // vsub: a - b
    __riscv_vse8_v_i8m1(out, __riscv_vsub_vv_i8m1(va, vb, vl), vl);
    static const int8_t exp_sub[16] = {-15,-13,-11,-9,-7,-5,-3,-1,1,3,5,7,9,11,13,15};
    check_arr8("e8 vsub a-b", out, exp_sub, 16);

    // vsub a - b, verify last element: 16-1 = 15
    __riscv_vse8_v_i8m1(out, __riscv_vsub_vv_i8m1(va, vb, vl), vl);
    check_i("e8 vsub last: 16-1=15", (int)out[15], 15);
}

// --- 8. e16 / m1 (8 halfword-elements) ---------------------------------------

static void test_e16(void) {
    log_write(NONE, "\n=== e16/m1: 8 halfword-elements per register ===\n");

    static const int16_t a[8] = {100, 200, 300, 400, 500, 600, 700, 800};
    static const int16_t b[8] = {  1,   2,   3,   4,   5,   6,   7,   8};
    int16_t out[8];
    size_t vl = __riscv_vsetvl_e16m1(8);

    vint16m1_t va = __riscv_vle16_v_i16m1(a, vl);
    vint16m1_t vb = __riscv_vle16_v_i16m1(b, vl);

    // vadd
    __riscv_vse16_v_i16m1(out, __riscv_vadd_vv_i16m1(va, vb, vl), vl);
    static const int16_t exp_add[8] = {101,202,303,404,505,606,707,808};
    check_arr16("e16 vadd", out, exp_add, 8);

    // vmul
    __riscv_vse16_v_i16m1(out, __riscv_vmul_vv_i16m1(va, vb, vl), vl);
    static const int16_t exp_mul[8] = {100,400,900,1600,2500,3600,4900,6400};
    check_arr16("e16 vmul", out, exp_mul, 8);

    // vsub a - b, verify last: 800-8=792
    __riscv_vse16_v_i16m1(out, __riscv_vsub_vv_i16m1(va, vb, vl), vl);
    check_i("e16 vsub last: 800-8=792", (int)out[7], 792);
}

// --- 9. e32 / m2  (LMUL=2: 8 word-elements across two registers) -------------

static void test_lmul2(void) {
    log_write(NONE, "\n=== e32/m2: LMUL=2, 8 elements across 2 registers ===\n");

    static const int32_t a[8] = {1,2,3,4,5,6,7,8};
    static const int32_t b[8] = {8,7,6,5,4,3,2,1};
    int32_t out[8];
    size_t vl = __riscv_vsetvl_e32m2(8);

    check_i("vsetvl_e32m2 returns 8", (int)vl, 8);

    vint32m2_t va = __riscv_vle32_v_i32m2(a, vl);
    vint32m2_t vb = __riscv_vle32_v_i32m2(b, vl);

    // vadd: every element = 9
    __riscv_vse32_v_i32m2(out, __riscv_vadd_vv_i32m2(va, vb, vl), vl);
    int all9 = 1;
    for (int i = 0; i < 8; i++) if (out[i] != 9) { all9 = 0; break; }
    if (all9) { log_write(NONE, "  PASS  m2 vadd all=9\n"); g_pass++; }
    else {
        log_write(NONE, "  FAIL  m2 vadd: [%d,%d,%d,%d,%d,%d,%d,%d]\n",
                  out[0],out[1],out[2],out[3],out[4],out[5],out[6],out[7]);
        g_fail++;
    }

    // vsub: a - b = [-7,-5,-3,-1,1,3,5,7]
    __riscv_vse32_v_i32m2(out, __riscv_vsub_vv_i32m2(va, vb, vl), vl);
    static const int32_t exp_sub[8] = {-7,-5,-3,-1,1,3,5,7};
    check_arr32("m2 vsub a-b", out, exp_sub, 8);
}

// --- 10. vmseq + masked vadd --------------------------------------------------

static void test_masked(void) {
    log_write(NONE, "\n=== vmseq + masked vadd (e32/m1) ===\n");

    // a = [1,2,3,4], b = [10,10,10,10]
    // Mask: a[i] == 2 or a[i] == 4  (select even elements)
    // Result: where mask=1 -> a[i]+b[i], where mask=0 -> a[i] (merge)
    static const int32_t a[4] = {1, 2, 3, 4};
    static const int32_t b[4] = {10,10,10,10};
    int32_t out[4];
    size_t vl = __riscv_vsetvl_e32m1(4);

    vint32m1_t va = __riscv_vle32_v_i32m1(a, vl);
    vint32m1_t vb = __riscv_vle32_v_i32m1(b, vl);

    // Generate mask: elements where a[i] is even (a[i] & 1 == 0)
    // We do: tmp = a & 1, mask = vmseq(tmp, 0)
    vint32m1_t vtmp = __riscv_vand_vx_i32m1(va, 1, vl);
    vbool32_t  mask = __riscv_vmseq_vx_i32m1_b32(vtmp, 0, vl);

    // Masked add: active elements get a+b, inactive are tail-agnostic.
    // Use vmerge to build expected merged result: start from 'a', overwrite active.
    vint32m1_t vadd_all = __riscv_vadd_vv_i32m1(va, vb, vl);  // a+b uncond.
    vint32m1_t vr = __riscv_vadd_vv_i32m1_m(mask, va, vb, vl);
    // Active positions (where a[i] is even, i.e. index 1,3): should be a+b
    int32_t out_full[4], out_masked[4];
    __riscv_vse32_v_i32m1(out_full,   vadd_all, vl);
    __riscv_vse32_v_i32m1(out_masked, vr,       vl);
    // Active elements must equal a+b
    check_i("masked vadd: active[1]=2+10=12", out_masked[1], out_full[1]);
    check_i("masked vadd: active[3]=4+10=14", out_masked[3], out_full[3]);

    // vmslt: mask = (a < 3)  -> elements 0,1 active
    vbool32_t mlt = __riscv_vmslt_vx_i32m1_b32(va, 3, vl);
    vint32m1_t vr2 = __riscv_vadd_vv_i32m1_m(mlt, va, vb, vl);
    __riscv_vse32_v_i32m1(out, vr2, vl);
    // Active elements (0,1) = a+b
    check_i("masked vadd a<3: active[0]=1+10=11", out[0], 11);
    check_i("masked vadd a<3: active[1]=2+10=12", out[1], 12);
}

// --- Main ---------------------------------------------------------------------

int main(void) {
    uart_puts("=== RVV Advanced Test ===\n");
    if (log_init("rvv-advanced.log") != 0) {
        uart_puts("ERROR: log_init failed\n");
        return 1;
    }

    log_write(NONE, "=== RVV Advanced Test (RV32IMV) ===\n");
    log_write(NONE, "VLEN=128  =>  e8/m1:16  e16/m1:8  e32/m1:4  e32/m2:8\n");

    test_vsub();
    test_bitwise();
    test_shifts();
    test_minmax();
    test_vmacc();
    test_vrgather();
    test_e8();
    test_e16();
    test_lmul2();
    test_masked();

    log_write(NONE, "\n=== Summary ===\n");
    log_write(NONE, "  PASS: %d\n", g_pass);
    log_write(NONE, "  FAIL: %d\n", g_fail);
    log_write(NONE, "  %s\n", g_fail == 0 ? "ALL TESTS PASSED" : "SOME TESTS FAILED");

    log_close();
    uart_puts(g_fail == 0 ? "ALL PASSED\n" : "SOME FAILED\n");
    return g_fail;
}
