#ifndef _COMPLIANCE_MODEL_H
#define _COMPLIANCE_MODEL_H

//-----------------------------------------------------------------------
// RISC-V Architecture Test Target Macros
//
// Target: riscv_emulator (RV32IMFDCAV)
// Halt mechanism: csrw mtvec, zero; ecall => CPU.Halted := True
//-----------------------------------------------------------------------

//-----------------------------------------------------------------------
// RVMODEL_HALT
// Stop execution. Clear mtvec so ecall triggers halt in Trap_Entry.
//-----------------------------------------------------------------------
#define RVMODEL_HALT                                                    \
        la t0, begin_signature;                                         \
        la t1, end_signature;                                           \
        li  a0, 0;                                                      \
        csrw mtvec, zero;                                               \
        ecall;                                                          \
        j .;

//-----------------------------------------------------------------------
// RVMODEL_BOOT
// Called at the very beginning. Set up stack pointer and jump to start.
//-----------------------------------------------------------------------
// Binutils >= 2.40 rejects "la x0, sym" ("illegal operands") but accepts the
// identical "lla x0, sym". The upstream TEST_JALR_OP macro emits "la rd, sym"
// with rd == x0, so jalr-01 fails to assemble. This build is bare-metal and
// non-PIC, where la and lla expand to the same auipc/addi pair, so shadowing
// la with lla is behaviour-preserving and makes the x0 form assemble.
#define RVMODEL_BOOT                                                    \
        .macro la rd, sym;                                              \
        lla \rd, \sym;                                                  \
        .endm;                                                          \
        .section .text.init;                                            \
        .globl _start;                                                  \
_start:                                                                 \
        la sp, _stack_top;

//-----------------------------------------------------------------------
// RVMODEL_DATA_BEGIN / RVMODEL_DATA_END
// Bracket the signature region.
//-----------------------------------------------------------------------
#define RVMODEL_DATA_BEGIN                                              \
        .align 4;                                                       \
        .global begin_signature;                                        \
begin_signature:

#define RVMODEL_DATA_END                                                \
        .align 4;                                                       \
        .global end_signature;                                          \
end_signature:                                                          \
        .align 4;                                                       \
        .global tohost;                                                 \
tohost:                                                                 \
        .word 0;                                                        \
        .global fromhost;                                               \
fromhost:                                                               \
        .word 0;

//-----------------------------------------------------------------------
// RVMODEL_IO_* stubs (no I/O needed for signature-based testing)
//-----------------------------------------------------------------------
#define RVMODEL_IO_INIT
#define RVMODEL_IO_WRITE_STR(_R, _STR)
#define RVMODEL_IO_CHECK()
#define RVMODEL_IO_ASSERT_GPR_EQ(_S, _R, _I)
#define RVMODEL_IO_ASSERT_SFPR_EQ(_F, _R, _I)
#define RVMODEL_IO_ASSERT_DFPR_EQ(_D, _R, _I)

//-----------------------------------------------------------------------
// Interrupt handling macros (CLINT at 0x02000000)
//-----------------------------------------------------------------------
#define RVMODEL_SET_MSW_INT                                             \
        li t0, 0x02000000;                                              \
        li t1, 1;                                                       \
        sw t1, 0(t0);

#define RVMODEL_CLEAR_MSW_INT                                           \
        li t0, 0x02000000;                                              \
        sw zero, 0(t0);

#define RVMODEL_SET_MTIMER_INT                                          \
        li t0, 0x02004000;                                              \
        sw zero, 0(t0);                                                 \
        sw zero, 4(t0);

#define RVMODEL_CLEAR_MTIMER_INT                                        \
        li t0, 0x02004000;                                              \
        li t1, -1;                                                      \
        sw t1, 0(t0);                                                   \
        sw t1, 4(t0);

//-----------------------------------------------------------------------
// RVMODEL_DATA_SECTION
// Extra data needed by arch tests.
//-----------------------------------------------------------------------
#define RVMODEL_DATA_SECTION                                            \
        .pushsection .tohost, "aw", @progbits;                          \
        .align 4;                                                       \
        .global tohost;                                                 \
tohost:                                                                 \
        .word 0;                                                        \
        .global fromhost;                                               \
fromhost:                                                               \
        .word 0;                                                        \
        .popsection;

#endif // _COMPLIANCE_MODEL_H
