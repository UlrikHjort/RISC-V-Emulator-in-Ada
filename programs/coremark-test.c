/* **************************************************************************
 *     RISC-V Emulator - Coremark-inspired workload for RISC-V emulator
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
 * coremark-test.c  --  Coremark-inspired workload for RISC-V emulator
 *
 * Exercises linked-list sort, 2x2 matrix multiply, state machine, and
 * CRC-16/IBM -- the four core workloads of the EEMBC CoreMark benchmark.
 * Verifies determinism (two runs with identical seed produce identical
 * results) and reports cycle counts via the rdcycle CSR.
 *
 * Target: 5 assertions
 * By Ulrik Hørlyk Hjort 2026
 */
#include <stdint.h>
#include <stddef.h>
#include "log.h"

/* ---- assertion helpers -------------------------------------------------- */
static int g_pass = 0, g_fail = 0;
static void chk(const char *label, int ok) {
    if (ok) { log_write(NONE, "PASS %s\n", label); g_pass++; }
    else    { log_write(NONE, "FAIL %s\n", label); g_fail++; }
}

/* ---- CSR helpers --------------------------------------------------------- */
static uint32_t rdcycle_u(void) {
    uint32_t v;
    asm volatile("rdcycle %0" : "=r"(v));
    return v;
}
static uint32_t rdinstret_u(void) {
    uint32_t v;
    asm volatile("rdinstret %0" : "=r"(v));
    return v;
}

/* ==========================================================================
 * A) Linked-list insertion sort
 * ========================================================================== */
#define LIST_SIZE 16

typedef struct list_node {
    int16_t val;
    struct list_node *next;
} list_node_t;

static list_node_t g_nodes[LIST_SIZE];

static void list_init(uint32_t seed) {
    uint32_t s = seed;
    for (int i = 0; i < LIST_SIZE; i++) {
        s = s * 1664525u + 1013904223u;   /* LCG */
        g_nodes[i].val  = (int16_t)(s >> 16);
        g_nodes[i].next = (i < LIST_SIZE - 1) ? &g_nodes[i + 1] : (list_node_t *)0;
    }
}

/* Insertion sort; returns number of swaps (used as result). */
static uint32_t list_sort(void) {
    uint32_t swaps = 0;
    for (int i = 1; i < LIST_SIZE; i++) {
        int16_t key = g_nodes[i].val;
        int j = i - 1;
        while (j >= 0 && g_nodes[j].val > key) {
            g_nodes[j + 1].val = g_nodes[j].val;
            j--;
            swaps++;
        }
        g_nodes[j + 1].val = key;
    }
    return swaps;
}

/* ==========================================================================
 * B) 2x2 signed-integer matrix multiply
 * ========================================================================== */
typedef struct { int16_t m[2][2]; } mat2_t;

static mat2_t mat_mul(mat2_t a, mat2_t b) {
    mat2_t r;
    for (int i = 0; i < 2; i++) {
        for (int j = 0; j < 2; j++) {
            int32_t s = 0;
            for (int k = 0; k < 2; k++) {
                s += (int32_t)a.m[i][k] * (int32_t)b.m[k][j];
            }
            r.m[i][j] = (int16_t)(s & 0xFFFF);
        }
    }
    return r;
}

static uint32_t mat_bench(uint32_t seed) {
    mat2_t a;
    mat2_t b;
    mat2_t r;
    a.m[0][0] = (int16_t)(seed >> 16);
    a.m[0][1] = (int16_t)(seed);
    a.m[1][0] = (int16_t)(seed >> 8);
    a.m[1][1] = (int16_t)(seed >> 24);
    b.m[0][0] = (int16_t)((~seed) >> 16);
    b.m[0][1] = (int16_t)(~seed);
    b.m[1][0] = (int16_t)((~seed) >> 8);
    b.m[1][1] = (int16_t)((~seed) >> 24);
    r = mat_mul(a, b);
    return (uint32_t)(uint16_t)r.m[0][0] ^
           (uint32_t)(uint16_t)r.m[0][1] ^
           (uint32_t)(uint16_t)r.m[1][0] ^
           (uint32_t)(uint16_t)r.m[1][1];
}

/* ==========================================================================
 * C) Simple 4-state machine over a fixed string
 * ========================================================================== */
static const char sm_str[] = "aaabbbaaacccbbbaaaccc";

typedef enum { SM_S0 = 0, SM_S1, SM_S2, SM_S3 } sm_state_t;

static uint32_t state_machine(void) {
    sm_state_t s = SM_S0;
    uint32_t transitions = 0;
    for (int i = 0; sm_str[i]; i++) {
        sm_state_t ns;
        switch (s) {
            case SM_S0: ns = (sm_str[i] == 'a') ? SM_S1 : SM_S0; break;
            case SM_S1: ns = (sm_str[i] == 'b') ? SM_S2 : SM_S1; break;
            case SM_S2: ns = (sm_str[i] == 'c') ? SM_S3 : SM_S0; break;
            case SM_S3: ns = SM_S0;                                break;
            default:    ns = SM_S0;                                break;
        }
        if (ns != s) transitions++;
        s = ns;
    }
    return transitions;
}

/* ==========================================================================
 * D) CRC-16/IBM (poly 0xA001)
 * ========================================================================== */
static uint16_t crc16(const uint8_t *data, int len) {
    uint16_t crc = 0xFFFF;
    for (int i = 0; i < len; i++) {
        crc ^= (uint16_t)data[i];
        for (int b = 0; b < 8; b++) {
            crc = (crc & 1u) ? ((crc >> 1) ^ 0xA001u) : (crc >> 1);
        }
    }
    return crc;
}

static uint32_t crc_bench(uint32_t seed) {
    uint8_t buf[8];
    for (int i = 0; i < 8; i++) {
        buf[i] = (uint8_t)(seed >> (i * 4));
    }
    return (uint32_t)crc16(buf, 8);
}

/* ==========================================================================
 * Core loop: one iteration = list_sort + mat_bench + state_machine + crc
 * ========================================================================== */
#define ITERATIONS 500
#define SEED       0x3415ABCDu

static uint32_t run_benchmark(void) {
    uint32_t acc = 0;
    for (int iter = 0; iter < ITERATIONS; iter++) {
        uint32_t s = SEED ^ (uint32_t)iter;
        list_init(s);
        acc ^= list_sort();
        acc ^= mat_bench(s);
        acc ^= state_machine();
        acc ^= crc_bench(s);
    }
    return acc;
}

/* ==========================================================================
 * main
 * ========================================================================== */
int main(void) {
    log_init("coremark-test.log");
    log_write(NONE, "=== Coremark-like Benchmark ===\n");
    log_write(NONE, "Iterations: %d x 2 (determinism check)\n", ITERATIONS);

    uint32_t c0 = rdcycle_u();
    uint32_t run1 = run_benchmark();
    uint32_t c1 = rdcycle_u();

    uint32_t run2 = run_benchmark();
    uint32_t c2 = rdcycle_u();

    uint32_t i_end = rdinstret_u();
    uint32_t c_end = rdcycle_u();

    uint32_t cycles1 = c1 - c0;
    uint32_t cycles2 = c2 - c1;

    log_write(NONE, "Run 1 result: 0x%x  cycles: %u\n", run1, cycles1);
    log_write(NONE, "Run 2 result: 0x%x  cycles: %u\n", run2, cycles2);
    log_write(NONE, "Cycles per iteration (run1): %u\n", cycles1 / ITERATIONS);

    chk("full benchmark deterministic (run1==run2)", run1 == run2);
    chk("both runs complete (cycles > 0)", (cycles1 > 0) & (cycles2 > 0));
    chk("mcycle >= minstret", c_end >= i_end);

    /* Individual workload timing */
    {
        uint32_t ca, cb;
        uint32_t r1, r2;

        /* list_sort determinism */
        r1 = 0;
        ca = rdcycle_u();
        for (int i = 0; i < ITERATIONS; i++) {
            list_init(SEED ^ (uint32_t)i);
            r1 ^= list_sort();
        }
        cb = rdcycle_u();
        log_write(NONE, "list_sort   %d x: %u cycles (%u/iter)\n",
                  ITERATIONS, cb - ca, (cb - ca) / ITERATIONS);
        r2 = 0;
        for (int i = 0; i < ITERATIONS; i++) {
            list_init(SEED ^ (uint32_t)i);
            r2 ^= list_sort();
        }
        chk("list_sort deterministic", r1 == r2);

        /* crc16 determinism */
        r1 = 0;
        ca = rdcycle_u();
        for (int i = 0; i < ITERATIONS; i++) {
            r1 ^= crc_bench(SEED ^ (uint32_t)i);
        }
        cb = rdcycle_u();
        log_write(NONE, "crc_bench   %d x: %u cycles (%u/iter)\n",
                  ITERATIONS, cb - ca, (cb - ca) / ITERATIONS);
        r2 = 0;
        for (int i = 0; i < ITERATIONS; i++) {
            r2 ^= crc_bench(SEED ^ (uint32_t)i);
        }
        chk("crc16 deterministic", r1 == r2);

        /* mat and state machine timing (informational only) */
        r1 = 0;
        ca = rdcycle_u();
        for (int i = 0; i < ITERATIONS; i++) {
            r1 ^= mat_bench(SEED ^ (uint32_t)i);
        }
        cb = rdcycle_u();
        log_write(NONE, "mat_bench   %d x: %u cycles (%u/iter)\n",
                  ITERATIONS, cb - ca, (cb - ca) / ITERATIONS);

        r1 = 0;
        ca = rdcycle_u();
        for (int i = 0; i < ITERATIONS; i++) {
            r1 ^= state_machine();
        }
        cb = rdcycle_u();
        log_write(NONE, "state_mach  %d x: %u cycles (%u/iter)\n",
                  ITERATIONS, cb - ca, (cb - ca) / ITERATIONS);
    }

    log_write(NONE, "\n%d PASS  %d FAIL\n", g_pass, g_fail);
    log_close();
    return g_fail ? 1 : 0;
}
