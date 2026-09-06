#ifndef DOOM_GENERIC
#define DOOM_GENERIC

#include <stdlib.h>
#include <stdint.h>

#define DOOMGENERIC_RESX 320
#define DOOMGENERIC_RESY 200

extern uint32_t* DG_ScreenBuffer;

/* argc/argv passed in by the platform via doomgeneric_Create() */
extern int   doomgeneric_argc;
extern char **doomgeneric_argv;

/* Platform must implement these: */
void DG_Init(void);
void DG_DrawFrame(void);
void DG_SleepMs(uint32_t ms);
uint32_t DG_GetTicksMs(void);
int DG_GetKey(int* pressed, unsigned char* key);
void DG_SetWindowTitle(const char * title);

/* Library provides these: */
void doomgeneric_Create(int argc, char **argv);
void doomgeneric_Tick(void);
void dg_Create(void);  /* legacy alias */

#endif //DOOM_GENERIC
