#include "doomgeneric.h"
#include "d_main.h"
#include "m_argv.h"
#include <stdlib.h>

uint32_t *DG_ScreenBuffer = 0;
int       doomgeneric_argc = 0;
char    **doomgeneric_argv = 0;

void dg_Create(void) {
    DG_ScreenBuffer = malloc(DOOMGENERIC_RESX * DOOMGENERIC_RESY * 4);
    DG_Init();
}

void doomgeneric_Create(int argc, char **argv) {
    doomgeneric_argc = argc;
    doomgeneric_argv = argv;
    myargc = argc;
    myargv = argv;
    DG_ScreenBuffer = malloc(DOOMGENERIC_RESX * DOOMGENERIC_RESY * 4);
    DG_Init();
    D_DoomMain();
}

void doomgeneric_Tick(void) {
    /* D_DoomMain() runs its own loop, so this is never called from our main */
}
