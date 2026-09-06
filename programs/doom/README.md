# DOOM on the RISC-V emulator

This directory contains a bare-metal port of DOOM that runs as a guest program
inside the emulator. It is used as an end-to-end validation of the CPU, memory
system, and the semihosting file-I/O interface: unlike the in-house test
programs, DOOM was not written with knowledge of this emulator.

For how the port works end to end, see `doom.md` in the repository root.

## Licensing

**The code in this directory is GPLv2, not MIT.** The rest of the repository
(the Ada emulator and its test programs) is MIT licensed -- see `LICENSE` in the
repository root. The full GPLv2 text is in `COPYING` here.

`doomgeneric/` is vendored third-party source:

- Original DOOM engine, Copyright (C) 1993-1996 id Software, Inc.,
  released under the GPL by id Software in 1999.
- Chocolate DOOM, Copyright (C) 2005-2014 Simon Howard.
- doomgeneric platform abstraction, from https://github.com/ozkl/doomgeneric

The port glue in this directory -- `doomgeneric_riscv.c`, `newlib_syscalls.c`
and `crt0_doom.S` -- is compiled and linked together with the engine, so it is a
derivative work and is likewise GPLv2.

The emulator itself does not link against any of this code. DOOM is
cross-compiled to a RISC-V ELF and executed as guest data, so the emulator and
DOOM are separate programs that are merely distributed together.

## The IWAD is NOT included

DOOM's game data is proprietary; id Software released the engine under the GPL
but not the WAD files. No IWAD is distributed here. `make doom-wad` downloads
the freely redistributable shareware `doom1.wad` at build time into the run
directory (`doom-run/` by default).

## What was changed relative to upstream doomgeneric

The vendored tree is `ozkl/doomgeneric` with bare-metal adaptations:

- Platform backends that need a host OS were removed: allegro, emscripten,
  linuxvt, soso, sosox, win, xlib, plus the SDL sound/music backends and
  `mus2mid`. Sound is stubbed out entirely (`-DNO_SOUND -DNOMIXER`) and
  networking is disabled (`-DNONET`).
- Modified for a no-OS, newlib-nano target: `d_iwad.c`, `d_main.c`, `d_net.c`,
  `doomgeneric.c`, `dummy.c`, `i_cdmus.c`, `i_endoom.c`, `i_sound.c`,
  `i_system.c`, `i_timer.c`, `i_video.c`, `m_misc.c` and the corresponding
  headers (`deh_str.h`, `d_main.h`, `doomfeatures.h`, `doomgeneric.h`,
  `doomtype.h`, `i_sound.h`, `i_swap.h`, `i_system.h`, `i_video.h`).
- `doomgeneric_sdl.c` and `i_main.c` are kept for reference but excluded from
  the build (see `DOOM_SRCS` in `programs/Makefile`).

The tree is vendored rather than fetched at build time so that the port is
reproducible: it depends on these modifications, which do not exist upstream.

## Building and running

```bash
make -C programs doom          # build out/elf/doom.elf
make -C programs doom-wad      # fetch the shareware IWAD
make -C programs run-doom      # render frames to PPM
make -C programs run-doom-tty  # play interactively in the terminal
```
