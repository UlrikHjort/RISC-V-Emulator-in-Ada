/* **************************************************************************
 *     RISC-V Emulator - Verify cycle-accurate instruction timing model
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
 * timing-test.c -- Verify cycle-accurate instruction timing model
 *
 * Tests that mcycle correctly counts more cycles for expensive instructions.
 * Each benchmark block executes exactly 100 instructions of one type.
 *
 * Expected cycle costs:
 *   ADD    : 1 cycle each  -> 100 total
 *   MUL    : 3 cycles each -> 300 total
 *   DIVU   : 33 cycles each -> 3300 total
 *   FADD.S : 4 cycles each -> 400 total
 *   FDIV.S : 20 cycles each -> 2000 total
 *
 * The second csrr (reading t1) costs 2 cycles included in t1 but not t0,
 * so: delta = t1 - t0 - 2
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

static uint32_t read_mcycle(void)
{
    uint32_t v;
    asm volatile("csrr %0, mcycle" : "=r"(v));
    return v;
}

static uint32_t bench_add(void)
{
    uint32_t t0, t1;
    asm volatile("csrr %0, mcycle" : "=r"(t0));
    /* 20 groups of 5 = 100 ADD instructions */
    asm volatile(
        "add t0,t0,t1\n\t" "add t0,t0,t1\n\t" "add t0,t0,t1\n\t" "add t0,t0,t1\n\t" "add t0,t0,t1\n\t"
        "add t0,t0,t1\n\t" "add t0,t0,t1\n\t" "add t0,t0,t1\n\t" "add t0,t0,t1\n\t" "add t0,t0,t1\n\t"
        "add t0,t0,t1\n\t" "add t0,t0,t1\n\t" "add t0,t0,t1\n\t" "add t0,t0,t1\n\t" "add t0,t0,t1\n\t"
        "add t0,t0,t1\n\t" "add t0,t0,t1\n\t" "add t0,t0,t1\n\t" "add t0,t0,t1\n\t" "add t0,t0,t1\n\t"
        "add t0,t0,t1\n\t" "add t0,t0,t1\n\t" "add t0,t0,t1\n\t" "add t0,t0,t1\n\t" "add t0,t0,t1\n\t"
        "add t0,t0,t1\n\t" "add t0,t0,t1\n\t" "add t0,t0,t1\n\t" "add t0,t0,t1\n\t" "add t0,t0,t1\n\t"
        "add t0,t0,t1\n\t" "add t0,t0,t1\n\t" "add t0,t0,t1\n\t" "add t0,t0,t1\n\t" "add t0,t0,t1\n\t"
        "add t0,t0,t1\n\t" "add t0,t0,t1\n\t" "add t0,t0,t1\n\t" "add t0,t0,t1\n\t" "add t0,t0,t1\n\t"
        "add t0,t0,t1\n\t" "add t0,t0,t1\n\t" "add t0,t0,t1\n\t" "add t0,t0,t1\n\t" "add t0,t0,t1\n\t"
        "add t0,t0,t1\n\t" "add t0,t0,t1\n\t" "add t0,t0,t1\n\t" "add t0,t0,t1\n\t" "add t0,t0,t1\n\t"
        "add t0,t0,t1\n\t" "add t0,t0,t1\n\t" "add t0,t0,t1\n\t" "add t0,t0,t1\n\t" "add t0,t0,t1\n\t"
        "add t0,t0,t1\n\t" "add t0,t0,t1\n\t" "add t0,t0,t1\n\t" "add t0,t0,t1\n\t" "add t0,t0,t1\n\t"
        "add t0,t0,t1\n\t" "add t0,t0,t1\n\t" "add t0,t0,t1\n\t" "add t0,t0,t1\n\t" "add t0,t0,t1\n\t"
        "add t0,t0,t1\n\t" "add t0,t0,t1\n\t" "add t0,t0,t1\n\t" "add t0,t0,t1\n\t" "add t0,t0,t1\n\t"
        "add t0,t0,t1\n\t" "add t0,t0,t1\n\t" "add t0,t0,t1\n\t" "add t0,t0,t1\n\t" "add t0,t0,t1\n\t"
        "add t0,t0,t1\n\t" "add t0,t0,t1\n\t" "add t0,t0,t1\n\t" "add t0,t0,t1\n\t" "add t0,t0,t1\n\t"
        "add t0,t0,t1\n\t" "add t0,t0,t1\n\t" "add t0,t0,t1\n\t" "add t0,t0,t1\n\t" "add t0,t0,t1\n\t"
        "add t0,t0,t1\n\t" "add t0,t0,t1\n\t" "add t0,t0,t1\n\t" "add t0,t0,t1\n\t" "add t0,t0,t1\n\t"
        "add t0,t0,t1\n\t" "add t0,t0,t1\n\t" "add t0,t0,t1\n\t" "add t0,t0,t1\n\t" "add t0,t0,t1\n\t"
        "add t0,t0,t1\n\t" "add t0,t0,t1\n\t" "add t0,t0,t1\n\t" "add t0,t0,t1\n\t" "add t0,t0,t1\n\t"
        : : : "t0", "t1");
    asm volatile("csrr %0, mcycle" : "=r"(t1));
    return t1 - t0 - 2;
}

static uint32_t bench_mul(void)
{
    uint32_t t0, t1;
    asm volatile("csrr %0, mcycle" : "=r"(t0));
    asm volatile(
        "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t"
        "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t"
        "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t"
        "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t"
        "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t"
        "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t"
        "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t"
        "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t"
        "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t"
        "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t"
        "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t"
        "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t"
        "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t"
        "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t"
        "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t"
        "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t"
        "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t"
        "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t"
        "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t"
        "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t" "mul t0,t0,t1\n\t"
        : : : "t0", "t1");
    asm volatile("csrr %0, mcycle" : "=r"(t1));
    return t1 - t0 - 2;
}

static uint32_t bench_divu(void)
{
    uint32_t t0, t1;
    /* Set divisor = 1 to avoid divide by zero */
    asm volatile("li t1, 1" : : : "t1");
    asm volatile("csrr %0, mcycle" : "=r"(t0));
    asm volatile(
        "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t"
        "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t"
        "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t"
        "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t"
        "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t"
        "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t"
        "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t"
        "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t"
        "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t"
        "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t"
        "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t"
        "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t"
        "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t"
        "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t"
        "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t"
        "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t"
        "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t"
        "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t"
        "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t"
        "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t" "divu t0,t0,t1\n\t"
        : : : "t0", "t1");
    asm volatile("csrr %0, mcycle" : "=r"(t1));
    return t1 - t0 - 2;
}

static uint32_t bench_fadd_s(void)
{
    uint32_t t0, t1;
    asm volatile("csrr %0, mcycle" : "=r"(t0));
    asm volatile(
        "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t"
        "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t"
        "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t"
        "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t"
        "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t"
        "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t"
        "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t"
        "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t"
        "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t"
        "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t"
        "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t"
        "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t"
        "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t"
        "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t"
        "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t"
        "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t"
        "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t"
        "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t"
        "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t"
        "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t" "fadd.s fa0,fa0,fa1\n\t"
        : : : "fa0", "fa1");
    asm volatile("csrr %0, mcycle" : "=r"(t1));
    return t1 - t0 - 2;
}

static uint32_t bench_fdiv_s(void)
{
    uint32_t t0, t1;
    asm volatile("csrr %0, mcycle" : "=r"(t0));
    asm volatile(
        "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t"
        "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t"
        "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t"
        "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t"
        "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t"
        "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t"
        "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t"
        "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t"
        "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t"
        "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t"
        "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t"
        "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t"
        "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t"
        "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t"
        "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t"
        "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t"
        "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t"
        "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t"
        "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t"
        "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t" "fdiv.s fa0,fa0,fa1\n\t"
        : : : "fa0", "fa1");
    asm volatile("csrr %0, mcycle" : "=r"(t1));
    return t1 - t0 - 2;
}

int main(void)
{
    uint32_t cycles;
    uint32_t c0, i0;

    log_init("timing-test.log");
    log_write(NONE, "=== Cycle-Accurate Timing Test ===\n");

    /* ADD = 1 cycle */
    cycles = bench_add();
    log_write(NONE, "100 ADD: %d cycles (expect 100)\n", cycles);
    chk("100 ADD = 100 cycles", cycles == 100);

    /* MUL = 3 cycles */
    cycles = bench_mul();
    log_write(NONE, "100 MUL: %d cycles (expect 300)\n", cycles);
    chk("100 MUL = 300 cycles", cycles == 300);

    /* DIVU = 33 cycles */
    cycles = bench_divu();
    log_write(NONE, "100 DIVU: %d cycles (expect 3300)\n", cycles);
    chk("100 DIVU = 3300 cycles", cycles == 3300);

    /* FADD.S = 4 cycles */
    cycles = bench_fadd_s();
    log_write(NONE, "100 FADD.S: %d cycles (expect 400)\n", cycles);
    chk("100 FADD.S = 400 cycles", cycles == 400);

    /* FDIV.S = 20 cycles */
    cycles = bench_fdiv_s();
    log_write(NONE, "100 FDIV.S: %d cycles (expect 2000)\n", cycles);
    chk("100 FDIV.S = 2000 cycles", cycles == 2000);

    /* mcycle >= minstret always */
    c0 = read_mcycle();
    asm volatile("csrr %0, minstret" : "=r"(i0));
    chk("mcycle >= minstret", c0 >= i0);

    log_write(NONE, "\n%d PASS  %d FAIL\n", g_pass, g_fail);
    log_close();
    return g_fail ? 1 : 0;
}
