/*
 * crt0_doom.S -- bare-metal startup for Doom on RISC-V qemu-virt
 *
 * Copyright (C) 2026 Ulrik Hørlyk Hjort
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * This file is linked with the GPLv2 DOOM engine in this directory and is
 * therefore GPLv2, unlike the MIT-licensed emulator. See ./README.md.
 */
    .section .text.start
    .globl _start
_start:
    /* Set stack pointer */
    la   sp, _stack_top

    /* Zero BSS */
    la   a0, __bss_start
    la   a1, __bss_end
1:  bge  a0, a1, 2f
    sw   zero, 0(a0)
    addi a0, a0, 4
    j    1b
2:
    /* Call main(0, NULL) */
    li   a0, 0
    li   a1, 0
    call main

    /* exit(return_value) */
    mv   a0, a0
    li   a7, 93
    ecall

    /* Should never reach here */
1:  j    1b
