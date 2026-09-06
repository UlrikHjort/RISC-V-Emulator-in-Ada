/* **************************************************************************
 *              RISC-V Emulator - PLIC (Platform-Level Interrupt Controller) Test
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
 * **************************************************************************
 * Tests the PLIC memory-mapped registers:
 *   - Priority registers (per-source interrupt priority)
 *   - Enable registers (per-context enable bitmask)
 *   - Threshold registers (per-context priority threshold)
 *   - Pending register (read-only, reflects active interrupt lines)
 *   - Claim/complete registers
 *
 * PLIC base address: 0x0C000000 (QEMU virt standard)
 * Source IDs: 1=UART, 2=GPIO, 3=SPI, 4=I2C, 5=TIMER
 * Contexts:   0=M-mode hart 0, 1=S-mode hart 0
 */

#include <stdint.h>
#include "log.h"

static int g_pass = 0, g_fail = 0;

static void chk(const char *label, int ok)
{
    if (ok) { log_write(NONE, "PASS %s\n", label); g_pass++; }
    else     { log_write(NONE, "FAIL %s\n", label); g_fail++; }
}

/* PLIC register accessors */
#define PLIC_BASE        0x0C000000UL

/* Priority: base + src*4 */
#define PLIC_PRIORITY(src)   (*(volatile uint32_t *)(PLIC_BASE + (src)*4))

/* Pending: base + 0x1000 (1 bit per source) */
#define PLIC_PENDING         (*(volatile uint32_t *)(PLIC_BASE + 0x1000))

/* Enable: base + 0x2000 + ctx*0x80 */
#define PLIC_ENABLE(ctx)     (*(volatile uint32_t *)(PLIC_BASE + 0x2000 + (ctx)*0x80))

/* Threshold: base + 0x200000 + ctx*0x1000 */
#define PLIC_THRESHOLD(ctx)  (*(volatile uint32_t *)(PLIC_BASE + 0x200000 + (ctx)*0x1000))

/* Claim/complete: threshold + 4 */
#define PLIC_CLAIM(ctx)      (*(volatile uint32_t *)(PLIC_BASE + 0x200000 + (ctx)*0x1000 + 4))

/* Source IDs */
#define SRC_UART  1
#define SRC_GPIO  2
#define SRC_SPI   3
#define SRC_I2C   4
#define SRC_TIMER 5

/* Contexts */
#define CTX_M 0
#define CTX_S 1

int main(void)
{
    log_init("plic-test.log");
    log_write(NONE, "PLIC Register Test\n\n");

    /* ---- Priority registers ---- */
    log_write(NONE, "--- Priority ---\n");

    /* Default priority is 1 for all sources */
    chk("prio src1 default=1", PLIC_PRIORITY(SRC_UART)  == 1);
    chk("prio src2 default=1", PLIC_PRIORITY(SRC_GPIO)  == 1);
    chk("prio src0 always=0",  PLIC_PRIORITY(0)         == 0);

    /* Write and read back priorities */
    PLIC_PRIORITY(SRC_UART) = 3;
    chk("prio src1 set=3", PLIC_PRIORITY(SRC_UART) == 3);

    PLIC_PRIORITY(SRC_GPIO) = 7;
    chk("prio src2 set=7", PLIC_PRIORITY(SRC_GPIO) == 7);

    /* Priority is masked to 3 bits (0-7) */
    PLIC_PRIORITY(SRC_SPI) = 0xFF;
    chk("prio src3 masked-to-7", PLIC_PRIORITY(SRC_SPI) == 7);

    /* Source 0 priority is read-only 0 */
    PLIC_PRIORITY(0) = 5;
    chk("prio src0 readonly=0", PLIC_PRIORITY(0) == 0);

    /* Restore */
    PLIC_PRIORITY(SRC_UART) = 1;
    PLIC_PRIORITY(SRC_GPIO) = 1;
    PLIC_PRIORITY(SRC_SPI)  = 1;

    /* ---- Enable registers ---- */
    log_write(NONE, "--- Enable ---\n");

    /* Default: all sources enabled (0xFFFFFFFF with bit 0 forced to 0) */
    chk("enable ctx0 default all",
        (PLIC_ENABLE(CTX_M) & ~1u) == (0xFFFFFFFFu & ~1u));
    chk("enable ctx1 default all",
        (PLIC_ENABLE(CTX_S) & ~1u) == (0xFFFFFFFFu & ~1u));

    /* Write enable mask for M-mode: enable only UART and GPIO */
    PLIC_ENABLE(CTX_M) = (1u << SRC_UART) | (1u << SRC_GPIO);
    chk("enable ctx0 uart+gpio",
        PLIC_ENABLE(CTX_M) == ((1u << SRC_UART) | (1u << SRC_GPIO)));

    /* Source 0 bit always stays 0 in enable register */
    PLIC_ENABLE(CTX_M) = 0xFFFFFFFF;
    chk("enable ctx0 bit0-stays-0",
        (PLIC_ENABLE(CTX_M) & 1u) == 0);

    /* S-mode context independently controlled */
    PLIC_ENABLE(CTX_S) = 1u << SRC_TIMER;
    chk("enable ctx1 timer-only",
        PLIC_ENABLE(CTX_S) == (1u << SRC_TIMER));

    /* Restore all enables */
    PLIC_ENABLE(CTX_M) = 0xFFFFFFFF & ~1u;
    PLIC_ENABLE(CTX_S) = 0xFFFFFFFF & ~1u;

    /* ---- Threshold registers ---- */
    log_write(NONE, "--- Threshold ---\n");

    /* Default threshold is 0 (all priorities pass) */
    chk("threshold ctx0 default=0", PLIC_THRESHOLD(CTX_M) == 0);
    chk("threshold ctx1 default=0", PLIC_THRESHOLD(CTX_S) == 0);

    /* Write and read back */
    PLIC_THRESHOLD(CTX_M) = 3;
    chk("threshold ctx0 set=3", PLIC_THRESHOLD(CTX_M) == 3);

    PLIC_THRESHOLD(CTX_S) = 6;
    chk("threshold ctx1 set=6", PLIC_THRESHOLD(CTX_S) == 6);

    /* Threshold masked to 3 bits */
    PLIC_THRESHOLD(CTX_M) = 0xFF;
    chk("threshold ctx0 masked=7", PLIC_THRESHOLD(CTX_M) == 7);

    /* Restore */
    PLIC_THRESHOLD(CTX_M) = 0;
    PLIC_THRESHOLD(CTX_S) = 0;

    /* ---- Pending register (read-only from SW) ---- */
    log_write(NONE, "--- Pending ---\n");

    /* Initially no interrupts pending (no peripheral actively interrupting) */
    chk("pending initially 0", PLIC_PENDING == 0);

    /* Writing to pending has no effect */
    PLIC_PENDING = 0xFFFFFFFF;
    chk("pending write ignored", PLIC_PENDING == 0);

    /* ---- Claim register ---- */
    log_write(NONE, "--- Claim ---\n");

    /* No pending interrupt -> claim returns 0 */
    chk("claim no-pending returns 0", PLIC_CLAIM(CTX_M) == 0);
    chk("claim s-no-pending returns 0", PLIC_CLAIM(CTX_S) == 0);

    log_write(NONE, "\n%d PASS  %d FAIL\n", g_pass, g_fail);
    log_close();
    return g_fail;
}
