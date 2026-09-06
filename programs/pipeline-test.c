/* **************************************************************************
 *     RISC-V Emulator - Verifies cycle-accurate pipeline hazard model
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

// pipeline-test.c - Verifies cycle-accurate pipeline hazard model.
//
// Tests load-use stalls and branch/jump taken penalties using rdcycle.
// Compares sequences with and without hazards to verify qualitative
// timing behaviour.
//
// Build and run:
//   cd programs && make run-pipeline-test
//
// By Ulrik Hørlyk Hjort 2026

#include <stdint.h>
#include "log.h"

static int g_pass = 0;
static int g_fail = 0;

static void chk(const char *name, int cond)
{
    if (cond) {
        log_write(NONE, "PASS: %s\n", name);
        g_pass++;
    } else {
        log_write(NONE, "FAIL: %s\n", name);
        g_fail++;
    }
}

static uint32_t rdcycle_val(void)
{
    uint32_t v;
    __asm__ volatile ("rdcycle %0" : "=r"(v));
    return v;
}

/* Measure N iterations of: lw then immediately use loaded register.
 * Each pair = 1 load + 1 add-with-dependency = 2 insns + 1 load-use stall.
 * Loop overhead (addi + bne) adds branch-taken stall per iteration. */
static uint32_t measure_load_use(volatile uint32_t *p, int n)
{
    uint32_t c0, c1, r;
    c0 = rdcycle_val();
    for (int i = 0; i < n; i++) {
        __asm__ volatile (
            "lw   %[r], 0(%[p])\n"
            "add  %[r], %[r], zero\n"   /* uses loaded reg immediately */
            : [r]"=&r"(r)
            : [p]"r"(p)
            : "memory"
        );
    }
    c1 = rdcycle_val();
    (void)r;
    return c1 - c0;
}

/* Measure N iterations of: lw then use a DIFFERENT register.
 * Each pair = 1 load + 1 add-without-dependency = 2 insns, no stall. */
static uint32_t measure_no_stall(volatile uint32_t *p, int n)
{
    uint32_t c0, c1, r, dummy = 7;
    c0 = rdcycle_val();
    for (int i = 0; i < n; i++) {
        __asm__ volatile (
            "lw   %[r], 0(%[p])\n"
            "add  %[d], %[d], zero\n"   /* uses different reg -- no stall */
            : [r]"=&r"(r), [d]"+r"(dummy)
            : [p]"r"(p)
            : "memory"
        );
    }
    c1 = rdcycle_val();
    (void)r;
    return c1 - c0;
}

/* Measure N taken branches (simple count-down loop). */
static uint32_t measure_taken_branch(int n)
{
    uint32_t c0, c1;
    c0 = rdcycle_val();
    __asm__ volatile (
        "mv   t0, %[n]\n"
        "1:\n"
        "addi t0, t0, -1\n"
        "bnez t0, 1b\n"
        : : [n]"r"(n) : "t0"
    );
    c1 = rdcycle_val();
    return c1 - c0;
}

/* Measure N NOPs (no hazards, no branches, base throughput). */
static uint32_t measure_nops(int n)
{
    uint32_t c0, c1;
    /* Use 10 NOPs per iteration to reduce loop overhead noise. */
    c0 = rdcycle_val();
    for (int i = 0; i < n; i++) {
        __asm__ volatile (
            "nop\nnop\nnop\nnop\nnop\n"
            "nop\nnop\nnop\nnop\nnop\n"
            :::
        );
    }
    c1 = rdcycle_val();
    return c1 - c0;
}

/* Measure a single JAL (just to confirm it costs at least 1 cycle). */
static uint32_t measure_jal(void)
{
    uint32_t c0, c1;
    c0 = rdcycle_val();
    /* A JAL to the next instruction (offset=4) wastes 1 fetch slot. */
    __asm__ volatile (
        "jal  zero, 1f\n"
        "1:\n"
        :::
    );
    c1 = rdcycle_val();
    return c1 - c0;
}

int main(void)
{
    volatile uint32_t mem_val = 42;
    const int N = 200;

    if (log_init("pipeline-test.log") != 0)
        return 1;

    log_write(NONE, "=== Pipeline Hazard Test ===\n");

    /* ------------------------------------------------------------------ */
    /* Test 1: load-use sequence takes more cycles than no-stall sequence  */
    /* ------------------------------------------------------------------ */
    uint32_t cycles_lu   = measure_load_use  (&mem_val, N);
    uint32_t cycles_ns   = measure_no_stall  (&mem_val, N);

    log_write(NONE, "load-use  cycles (%d iters): %u\n", N, cycles_lu);
    log_write(NONE, "no-stall  cycles (%d iters): %u\n", N, cycles_ns);

    chk("load-use > no-stall", cycles_lu > cycles_ns);

    /* Each load-use iteration has 1 extra stall cycle; we expect at least
     * N/2 extra cycles compared to no-stall for N >= 200. */
    chk("load-use stall magnitude", (cycles_lu - cycles_ns) >= (uint32_t)(N / 2));

    /* ------------------------------------------------------------------ */
    /* Test 2: NOP throughput is 1 cycle per NOP                          */
    /* ------------------------------------------------------------------ */
    const int NOPS_ITERS  = 100;   /* 100 * 10 = 1000 NOPs */
    uint32_t  nop_cycles  = measure_nops(NOPS_ITERS);
    uint32_t  nop_total   = (uint32_t)(NOPS_ITERS * 10);

    log_write(NONE, "NOP throughput: %u cycles for %u NOPs\n",
              nop_cycles, nop_total);

    /* Allow 20% slack for loop overhead (addi + bne per iter each cost 1+1 cycle).
     * 100 iters * 10 NOPs = 1000 NOPs + 100 addi + 100 taken bne (with branch stall).
     * Expected: ~1000 + 100 + 200 = ~1300 cycles.  Check at least 900, at most 1800. */
    chk("NOP cycles lower bound",  nop_cycles >= 900);
    chk("NOP cycles upper bound",  nop_cycles <= 1800);

    /* ------------------------------------------------------------------ */
    /* Test 3: taken branch loop costs more than N * 2 cycles             */
    /* (addi=1 + bnez-taken=1+1=2 per iter)                              */
    /* ------------------------------------------------------------------ */
    const int B_ITERS      = 200;
    uint32_t  branch_cycles = measure_taken_branch(B_ITERS);

    log_write(NONE, "branch-loop cycles (%d iters): %u\n", B_ITERS, branch_cycles);

    /* Each iteration: addi(1) + bnez-taken(2) = 3 cycles.
     * Also last iteration the branch is not-taken (1 cycle).
     * Minimum expected: B_ITERS * 2 = 400 (conservative: just stall * N) */
    chk("branch-taken lower bound", branch_cycles >= (uint32_t)(B_ITERS * 2));

    /* ------------------------------------------------------------------ */
    /* Test 4: JAL costs at least 1 cycle                                 */
    /* ------------------------------------------------------------------ */
    uint32_t jal_cycles = measure_jal();
    log_write(NONE, "JAL cycles: %u\n", jal_cycles);
    chk("JAL costs >= 1 cycle", jal_cycles >= 1);

    /* ------------------------------------------------------------------ */
    /* Summary                                                             */
    /* ------------------------------------------------------------------ */
    log_write(NONE, "\nRESULT: %d PASS, %d FAIL\n", g_pass, g_fail);
    log_close();

    return (g_fail == 0) ? 0 : 1;
}
