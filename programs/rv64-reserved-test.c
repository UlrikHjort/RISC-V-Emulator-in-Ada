/* **************************************************************************
 *          RISC-V Emulator - RV64 Reserved-Encoding Trap Test
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
 * Guards the RV64 decoder against the "aliased to a base op" bug: an
 * unimplemented funct7/funct6 encoding must raise illegal-instruction, not
 * silently run as whichever base op shares its funct3. Each case below is a
 * reserved encoding emitted as a raw .word; an M-mode trap handler records
 * mcause and steps past the faulting instruction so the run can continue.
 *
 * A control group of *legal* encodings confirms the handler does not fire
 * spuriously.
 *
 * Build: -march=rv64imafd_zbs_zbc_zbkb_zbkx -mabi=lp64d
 */

#include <stdint.h>
#include "log.h"

#define CAUSE_ILLEGAL 2u

static int g_pass = 0, g_fail = 0;

static volatile uint64_t g_mcause = 0;
static volatile uint64_t g_count  = 0;

static void chk(const char *label, int ok)
{
    if (ok) { log_write(NONE, "PASS %s\n", label); g_pass++; }
    else    { log_write(NONE, "FAIL %s\n", label); g_fail++; }
}

/* Naked M-mode trap handler: capture mcause, bump the counter, advance mepc
 * past the faulting instruction (4 bytes for a 32-bit encoding, 2 for a
 * compressed one), then mret. */
static void trap_handler(void) __attribute__((naked, aligned(4), used));
static void trap_handler(void)
{
    asm volatile(
        "addi sp, sp, -32\n"
        "sd   a0,  0(sp)\n"
        "sd   a1,  8(sp)\n"
        "sd   a2, 16(sp)\n"

        "csrr a0, mcause\n"  "la a1, g_mcause\n"  "sd a0, 0(a1)\n"
        "la   a1, g_count\n" "ld a2, 0(a1)\n" "addi a2, a2, 1\n" "sd a2, 0(a1)\n"

        /* advance mepc past the faulting instruction */
        "csrr a0, mepc\n"
        "lh   a1, 0(a0)\n"
        "andi a1, a1, 3\n"
        "li   a2, 3\n"
        "bne  a1, a2, 1f\n"
        "addi a0, a0, 4\n"
        "j    2f\n"
        "1:\n"
        "addi a0, a0, 2\n"
        "2:\n"
        "csrw mepc, a0\n"

        "ld   a0,  0(sp)\n"
        "ld   a1,  8(sp)\n"
        "ld   a2, 16(sp)\n"
        "addi sp, sp, 32\n"
        "mret\n"
    );
}

int main(void)
{
    log_init("rv64-reserved-test.log");
    log_write(NONE, "RV64 Reserved-Encoding Trap Test\n\n");

    /* Install the handler (direct mode). */
    asm volatile("la t0, trap_handler\n csrw mtvec, t0" ::: "t0");

    /* ---- reserved encodings: each must trap illegal (mcause=2) ---- */
    /* We cannot pass the word as a variable to .word, so inline each one and
     * check the handler fired exactly once with mcause = illegal.            */
    #define EXPECT_ILLEGAL(LABEL, WORD)                                     \
        do {                                                               \
            g_mcause = 0; uint64_t _b = g_count;                           \
            asm volatile(".word " #WORD "\n" ::: "memory");                \
            chk(LABEL, g_mcause == CAUSE_ILLEGAL && g_count == _b + 1);    \
        } while (0)

    log_write(NONE, "--- reserved (must trap) ---\n");
    EXPECT_ILLEGAL("OP funct7=0000011 f3=000",        0x06B50533);
    EXPECT_ILLEGAL("OP funct7=0000101 f3=000",        0x0AB50533);
    EXPECT_ILLEGAL("OP funct7=0000111 f3=000",        0x0EB50533);
    EXPECT_ILLEGAL("OP clmul-slot f3=011 reserved",   0x28B53533);
    EXPECT_ILLEGAL("OP funct7=0100000 f3=001",        0x40B51533);
    EXPECT_ILLEGAL("OP-IMM f3=001 funct6=000001",     0x04551513);
    EXPECT_ILLEGAL("OP-IMM Zbb-unary rs2=6",          0x60651513);
    EXPECT_ILLEGAL("OP-IMM f3=101 funct6=011010 rs2=0", 0x68055513);
    EXPECT_ILLEGAL("OP-IMM-32 f3=001 funct7=0000001", 0x0235151B);
    EXPECT_ILLEGAL("OP-32 funct7=0000101 f3=000",     0x0AB5053B);
    EXPECT_ILLEGAL("OP-32 muldiv f3=001 reserved",    0x02B5153B);

    /* ---- legal control group: handler must NOT fire ---- */
    log_write(NONE, "--- legal (must NOT trap) ---\n");
    #define EXPECT_LEGAL(LABEL, WORD)                                       \
        do {                                                               \
            uint64_t _b = g_count;                                         \
            asm volatile(".word " #WORD "\n" ::: "memory");                \
            chk(LABEL, g_count == _b);                                     \
        } while (0)

    EXPECT_LEGAL("mul",              0x02B50533);
    EXPECT_LEGAL("clmul",            0x0AB51533);
    EXPECT_LEGAL("clmulr",           0x0AB52533);
    EXPECT_LEGAL("bset",             0x28B51533);
    EXPECT_LEGAL("zext.h (packw)",   0x0805453B);

    log_write(NONE, "\n%d PASS  %d FAIL\n", g_pass, g_fail);
    log_close();
    return g_fail;
}
