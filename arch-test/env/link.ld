/* Linker script for riscv-arch-test on riscv_emulator */

OUTPUT_ARCH("riscv")
ENTRY(_start)

_stack_top = 0x00400000;

SECTIONS
{
    . = 0x0;

    .text.init : {
        *(.text.init)
    }

    .text : {
        *(.text .text.*)
    }

    .rodata : {
        *(.rodata .rodata.*)
    }

    .data : {
        *(.data .data.*)
    }

    .bss : {
        *(.bss .bss.*)
    }

    .tohost : {
        *(.tohost)
    }

    /* Signature region - placed after everything else */
    .signature : {
        *(.signature)
    }
}
