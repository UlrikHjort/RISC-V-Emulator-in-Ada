/*
 * doomgeneric_riscv.c -- doomgeneric platform layer for our RISC-V emulator.
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
 *
 * Implements the 6 callbacks doomgeneric requires:
 *   DG_Init()            -- called once at startup
 *   DG_DrawFrame()       -- called every frame (35 fps); dumps PPM via ECALL 0x50C
 *   DG_SleepMs(ms)       -- busy-waits on CLINT mtime
 *   DG_GetTicksMs()      -- returns ms since DG_Init via mtime
 *   DG_GetKey(p, k)      -- no keyboard input (demo auto-play)
 *   DG_SetWindowTitle(t) -- ignored
 *
 * Frame output: doom_frame_000000.ppm ... doom_frame_000059.ppm
 * After MAX_FRAMES frames the emulator is halted cleanly via exit(0).
 */

#include "doomgeneric.h"
#include <stdint.h>
#include <string.h>
#include <stdlib.h>

/* -------------------------------------------------------------------------
 * CLINT mtime -- at 0x0200_BFF8 in qemu-virt
 * The emulator increments mtime once per instruction.
 * We calibrate MTIME_FREQ empirically: Doom expects ~35 ticks/sec,
 * so we pick a value that gives reasonable game speed.
 * -------------------------------------------------------------------------*/
#define MTIME_BASE  0x02000000UL
#define MTIME_LO    (*(volatile uint32_t *)(MTIME_BASE + 0xBFF8))
#define MTIME_HI    (*(volatile uint32_t *)(MTIME_BASE + 0xBFFC))

/* 10 MHz CLINT frequency -- matches emulator CLINT default */
#define MTIME_FREQ  10000000ULL

static uint64_t read_mtime(void) {
    uint32_t lo, hi;
    do {
        hi = MTIME_HI;
        lo = MTIME_LO;
    } while (MTIME_HI != hi);
    return ((uint64_t)hi << 32) | lo;
}

static uint64_t start_ticks = 0;

/* -------------------------------------------------------------------------
 * ECALL 0x50C -- HOST_FB_DRAW
 * a0 = pointer to 320x200 ARGB32 buffer
 * a1 = frame number
 * Emulator writes doom_frame_NNNNNN.ppm to current directory.
 * -------------------------------------------------------------------------*/
#define MAX_FRAMES  60   /* capture first ~1.7 seconds at 35 fps */

static void fb_draw(uint32_t *buf, uint32_t frame_no) {
    register uint32_t a0 asm("a0") = (uint32_t)(uintptr_t)buf;
    register uint32_t a1 asm("a1") = frame_no;
    register uint32_t a7 asm("a7") = 0x50C;
    asm volatile("ecall" :: "r"(a0), "r"(a1), "r"(a7) : "memory");
}

#ifdef DOOM_INTERACTIVE
/* -------------------------------------------------------------------------
 * Interactive mode: render each frame to the terminal (ECALL 0x50D) and
 * read keystrokes from the host (ECALL 0x50E).
 *
 * Controls:  W/A/S/D move & turn, Q/E strafe, SPACE fire, F use/open door,
 *            1-7 select weapon, ENTER/ESC menu, ` (backtick) quit.
 * -------------------------------------------------------------------------*/
#include "doomkeys.h"

static void fb_term(uint32_t *buf) {
    register uint32_t a0 asm("a0") = (uint32_t)(uintptr_t)buf;
    register uint32_t a7 asm("a7") = 0x50D;
    asm volatile("ecall" :: "r"(a0), "r"(a7) : "memory");
}

static uint32_t key_poll(void) {
    register uint32_t a0 asm("a0") = 0;
    register uint32_t a7 asm("a7") = 0x50E;
    asm volatile("ecall" : "+r"(a0) : "r"(a7) : "memory");
    return a0;
}

/* Terminals only report key *presses*, never releases. We synthesise a
 * release HOLD_TICKS frames after the last press of a key; terminal
 * auto-repeat re-arms the hold, so holding a key produces continuous motion. */
#define HOLD_TICKS 4
static int key_hold[256];

static struct { int pressed; unsigned char key; } evq[128];
static int evq_head = 0, evq_tail = 0;

static void ev_push(int pressed, unsigned char key) {
    int nh = (evq_head + 1) & 127;
    if (nh != evq_tail) {
        evq[evq_head].pressed = pressed;
        evq[evq_head].key = key;
        evq_head = nh;
    }
}

static unsigned char map_key(uint32_t c) {
    switch (c) {
        case 'w': case 'W': return KEY_UPARROW;
        case 's': case 'S': return KEY_DOWNARROW;
        case 'a': case 'A': return KEY_LEFTARROW;
        case 'd': case 'D': return KEY_RIGHTARROW;
        case 'q': case 'Q': return KEY_STRAFE_L;
        case 'e': case 'E': return KEY_STRAFE_R;
        case ' ':           return KEY_FIRE;
        case 'f': case 'F': return KEY_USE;
        case '\r': case '\n': return KEY_ENTER;
        case 27:            return KEY_ESCAPE;
        case '1': case '2': case '3': case '4':
        case '5': case '6': case '7':
            return (unsigned char)c;   /* weapon select uses ASCII digits */
        default:            return 0;
    }
}

static void poll_input(void) {
    uint32_t c;
    while ((c = key_poll()) != 0) {
        if (c == '`') exit(0);           /* quit */
        unsigned char dk = map_key(c);
        if (dk) {
            if (!key_hold[dk]) ev_push(1, dk);
            key_hold[dk] = HOLD_TICKS;
        }
    }
    for (int k = 0; k < 256; k++) {
        if (key_hold[k] && --key_hold[k] == 0) {
            ev_push(0, (unsigned char)k);
        }
    }
}
#endif /* DOOM_INTERACTIVE */

/* -------------------------------------------------------------------------
 * doomgeneric callbacks
 * -------------------------------------------------------------------------*/

void DG_Init(void) {
    start_ticks = read_mtime();
}

void DG_DrawFrame(void) {
#ifdef DOOM_INTERACTIVE
    fb_term(DG_ScreenBuffer);
    poll_input();
#else
    static uint32_t frame = 0;
    fb_draw(DG_ScreenBuffer, frame);
    frame++;
    if (frame >= MAX_FRAMES) {
        exit(0);
    }
#endif
}

void DG_SleepMs(uint32_t ms) {
    uint64_t target = read_mtime() + (uint64_t)ms * MTIME_FREQ / 1000ULL;
    while (read_mtime() < target) {
        /* busy-wait */
    }
}

uint32_t DG_GetTicksMs(void) {
    uint64_t elapsed = read_mtime() - start_ticks;
    return (uint32_t)(elapsed * 1000ULL / MTIME_FREQ);
}

int DG_GetKey(int *pressed, unsigned char *doomKey) {
#ifdef DOOM_INTERACTIVE
    if (evq_head == evq_tail) return 0;
    *pressed = evq[evq_tail].pressed;
    *doomKey = evq[evq_tail].key;
    evq_tail = (evq_tail + 1) & 127;
    return 1;
#else
    (void)pressed;
    (void)doomKey;
    return 0;   /* no input -- Doom will play its built-in demo */
#endif
}

void DG_SetWindowTitle(const char *title) {
    (void)title;
}

/* -------------------------------------------------------------------------
 * main -- sets up argv for Doom then hands off to doomgeneric
 * Place doom1.wad in the directory where you run the emulator.
 * -------------------------------------------------------------------------*/
int main(void) {
    static char *argv[] = {
        (char *)"doom",
        (char *)"-iwad",
        (char *)"doom1.wad",
        (char *)"-nomusic",
        (char *)"-nosound",
        0
    };
    int argc = 5;

    doomgeneric_Create(argc, argv);

    while (1) {
        doomgeneric_Tick();
    }
    return 0;
}
