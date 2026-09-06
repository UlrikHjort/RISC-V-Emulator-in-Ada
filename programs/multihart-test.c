/* **************************************************************************
 *            RISC-V Emulator - 2-hart IPI + LR/SC spinlock test
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

/* multihart-test.c -- 2-hart IPI + LR/SC spinlock test
 *
 * Hart 0: initialises log, sends IPI to hart 1, waits for ack,
 *         then does an LR/SC atomic increment.
 * Hart 1: spins until IPI arrives, increments shared counter,
 *         signals hart 0, exits.
 *
 * Run with:  bin/riscv_emulator --machine qemu-virt --harts 2 -q \
 *                programs/out/bin/multihart-test.bin 80000000
 */
#include <stdint.h>
#include "log.h"

/* ---- shared between harts (BSS, zeroed by crt0-multihart.S) ----------- */
static volatile uint32_t g_shared_counter = 0;
static volatile uint32_t g_hart1_ready    = 0;

/* ---- test counters (hart 0 only) --------------------------------------- */
static int g_pass = 0, g_fail = 0;

static void chk(const char *label, int ok)
{
    if (ok) { log_write(NONE, "PASS %s\n", label); g_pass++; }
    else     { log_write(NONE, "FAIL %s\n", label); g_fail++; }
}

/* ---- CSR / CLINT helpers ----------------------------------------------- */
static inline uint32_t read_mhartid(void)
{
    uint32_t id;
    asm volatile("csrr %0, mhartid" : "=r"(id));
    return id;
}

#define CLINT_BASE  0x02000000UL
#define CLINT_MSIP0 (*(volatile uint32_t *)(CLINT_BASE + 0x0000UL))
#define CLINT_MSIP1 (*(volatile uint32_t *)(CLINT_BASE + 0x0004UL))

/* ======================================================================== */
/* Hart 0                                                                    */
/* ======================================================================== */
static void hart0_main(void)
{
    log_init("multihart-test.log");
    log_write(NONE, "=== Multi-Hart Test ===\n");

    chk("hart 0 mhartid == 0", read_mhartid() == 0);

    /* Send IPI to hart 1 */
    CLINT_MSIP1 = 1;

    /* Wait for hart 1 to respond (bounded spin) */
    uint32_t spin = 0;
    while (!g_hart1_ready && spin < 50000000U) spin++;
    chk("hart 1 responded to IPI", g_hart1_ready == 1);
    chk("shared counter set by hart 1", g_shared_counter == 1);

    /* LR/SC atomic increment */
    uint32_t old_val, sc_result;
    do {
        asm volatile(
            "lr.w  %0, (%2)\n"
            "addi  %0, %0, 1\n"
            "sc.w  %1, %0, (%2)\n"
            : "=&r"(old_val), "=&r"(sc_result)
            : "r"((uint32_t *)&g_shared_counter)
            : "memory"
        );
    } while (sc_result != 0);
    chk("LR/SC atomic increment to 2", g_shared_counter == 2);

    log_write(NONE, "\n%d PASS  %d FAIL\n", g_pass, g_fail);
    log_close();
}

/* ======================================================================== */
/* Hart 1                                                                    */
/* ======================================================================== */
static void hart1_main(void)
{
    /* Spin until IPI (MSIP1 written by hart 0) */
    while (CLINT_MSIP1 == 0)
        asm volatile("nop" ::: "memory");

    /* Acknowledge: clear MSIP */
    CLINT_MSIP1 = 0;

    /* Do work: increment shared counter */
    g_shared_counter = 1;

    /* Signal hart 0 */
    g_hart1_ready = 1;
}

/* ======================================================================== */
/* Entry point (dispatches by hart ID)                                       */
/* ======================================================================== */
int main(void)
{
    if (read_mhartid() == 0)
        hart0_main();
    else
        hart1_main();

    asm volatile("li a7, 93\necall" ::: "a7", "memory");
    return 0;
}
