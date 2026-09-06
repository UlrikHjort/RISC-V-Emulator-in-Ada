# RISC-V Emulator Demo Programs

This document describes the interactive demo programs that showcase the emulator's capabilities.

## Overview

The emulator includes several demo programs that demonstrate:
- **Graphics and Animation**: Terminal-based graphics using ANSI escape codes
- **Game Logic**: AI-driven games with collision detection and state management
- **Algorithms**: Pathfinding, cellular automata, and procedural generation
- **Timing**: Real-time animations using the CLINT timer

All demos use the bare-metal C runtime with full floating-point support, time library, and UART I/O.

---

## Demo Programs

### 1. Conway's Game of Life (`game-of-life.c`)

**Description**: Classic cellular automaton simulation with multiple pattern presets.

**Features**:
- 40x20 toroidal grid (wraps around edges)
- Multiple starting patterns: Blinker, Glider, R-pentomino, Random soup
- Animated evolution with neighbor counting
- Generation counter and statistics

**Running**:
```bash
make run-game-of-life
```

**What to watch for**:
- Blinker: Simple oscillator (period 2)
- Glider: Moves diagonally across the grid
- R-pentomino: Chaotic pattern that stabilizes after ~1103 generations
- Random soup: Unpredictable evolution

**Technical highlights**:
- Uses `time.h` delay functions for animation timing
- Double-buffered grid updates
- Efficient neighbor counting algorithm

---

### 2. Snake Game (`snake-game.c`)

**Description**: Classic snake game with AI autopilot.

**Features**:
- 40x20 playfield with walls
- AI pathfinding to food
- Growing snake (score increases as snake eats)
- Collision detection (walls and self)
- Real-time score and length display

**Running**:
```bash
make run-snake-game
```

**What to watch for**:
- AI uses greedy pathfinding (moves toward food)
- Falls back to safe moves when blocked
- Game ends when AI traps itself or fills the board
- Score increases by 10 for each food item

**Technical highlights**:
- Manhattan distance heuristic for AI
- Grid-based collision detection
- Dynamic snake body using array of points

---

### 3. Maze Generator (`maze-generator.c`)

**Description**: Generates perfect mazes using recursive backtracking and solves them with depth-first search.

**Features**:
- 39x19 maze (guaranteed single solution)
- Animated generation showing the algorithm in action
- Pathfinding with visualization
- Multiple maze variations with different random seeds

**Running**:
```bash
make run-maze-generator
```

**What to watch for**:
- Generation animation shows the backtracking algorithm
- Solving animation shows DFS exploration
- Solution path marked with '*' characters
- Three different maze layouts with varying difficulty

**Technical highlights**:
- Recursive backtracking for maze generation
- DFS with path reconstruction for solving
- PRNG for randomized direction selection
- Stack-based backtracking

---

### 4. Falling Tiles (`falling-tiles.c`) - **PLAYABLE!**

**Description**: Classic falling blocks game with full keyboard controls - now you can actually play!

**Features**:
- 12x20 playfield
- All 7 classic tetrominoes (I, O, T, S, Z, J, L)
- Full keyboard controls (WASD or Vim-style HJKL)
- Piece rotation
- Soft drop and hard drop with bonus points
- Line clearing with exponential scoring
- Progressive difficulty (speeds up after 10 and 20 lines)
- Quit anytime with Q key

**Controls**:
- **A/D** (or H/L): Move left/right
- **W** (or K): Rotate
- **S** (or J): Soft drop (+1 point per row)
- **Space**: Hard drop (+2 points per row)

**Running**:
```bash
make run-falling-tiles
# Connect with minicom to the PTY device shown
```

**Scoring**:
- Single line: 10 points
- Double: 40 points (4x per line)
- Triple: 90 points (9x per line)
- Four lines: 160 points (16x per line!)
- Plus soft/hard drop bonuses

**Technical highlights**:
- Non-blocking UART keyboard input (kbhit/getch_nonblock)
- Real-time input processing at 10 FPS
- 2D array representation of pieces
- Matrix rotation for piece transformations
- Collision detection for boundaries and locked pieces
- Line clearing with array shifting

---

### 5. Matrix Rain (`matrix-rain.c`)

**Description**: Digital rain effect inspired by "The Matrix" with cascading characters.

**Features**:
- 60 columns x 24 rows of falling characters
- Varying drop speeds and trail lengths
- Brightness gradients (white -> bright green -> normal green -> dim green)
- Three animation modes: Classic, Fast, and Zen

**Running**:
```bash
make run-matrix-rain
```

**What to watch for**:
- Classic mode: Standard speed, varied drop lengths
- Fast mode: Increased speed (2-4x), shorter refresh
- Zen mode: Slow, peaceful animation with short trails

**Technical highlights**:
- ANSI color codes for green gradients and white highlights
- Character randomization from extended ASCII set
- Per-column state tracking (position, speed, length)
- Cursor positioning for smooth animation

---

## Performance Notes

All demos run at interactive speeds on the emulator:
- **Game of Life**: ~50ms per generation
- **Snake**: ~150ms per move
- **Maze Generator**: 20ms per step (generation), 10ms per step (solving)
- **Falling Tiles**: ~100ms per frame
- **Matrix Rain**: 50-150ms per frame (mode dependent)

Timing is controlled by `delay_ms()` from the time library, which uses the CLINT mtime register at 10 MHz.

---

## Building All Demos

Build all demos at once:
```bash
make game-of-life.bin snake-game.bin maze-generator.bin falling-tiles.bin matrix-rain.bin
```

Or build everything:
```bash
make all
```

---

## Technical Requirements

All demos require:
- **RISC-V Extensions**: RV32IMF (Integer, Multiply, Floating-Point)
- **C Runtime**: crt0.S startup code with BSS initialization
- **Libraries**: uart.c, syscalls.c, printf.c, time.c
- **Linker**: Custom linker script with proper memory layout
- **Peripherals**: UART at 0x10000000, CLINT at 0x02000000

---

## Source Code Organization

Each demo is self-contained in a single `.c` file:
- Includes all necessary headers (uart.h, printf.h, time.h)
- Implements own random number generator (LCG)
- Contains complete game/animation logic
- Has main() that runs demonstration sequences

Common pattern:
```c
#include "uart.h"
#include "printf.h"
#include "time.h"

// Constants and data structures
#define WIDTH 40
#define HEIGHT 20

// Random number generator
static unsigned int rand_seed;
void seed_random(unsigned int seed);
int random_int(int max);

// Display functions
void clear_screen(void);
void display_frame(void);

// Logic functions
void update_state(void);

// Main demo loop
int main(void) {
    uart_init();
    seed_random(12345);

    while (1) {
        update_state();
        display_frame();
        delay_ms(100);
    }
}
```

---

## Customization

### Changing Animation Speed

Edit the `delay_ms()` value in the main loop:
```c
delay_ms(100);  // Change to 50 for faster, 200 for slower
```

### Changing Grid Size

Modify the `WIDTH` and `HEIGHT` constants at the top of each file:
```c
#define WIDTH  80  // Wider playfield
#define HEIGHT 40  // Taller playfield
```

### Changing Random Seed

Each demo uses a fixed seed for reproducibility. Change the seed in main():
```c
seed_random(99999);  // Different seed = different patterns
```

---

## Debugging Demos

Run with the emulator's trace mode:
```bash
../bin/riscv_emulator -trace game-of-life.bin 0x80000000
```

Or use the interactive debugger:
```bash
../bin/riscv_emulator -d game-of-life.bin 0x80000000
> b 0x80000100    # Set breakpoint
> c               # Continue
> r               # Show registers
```

---

## Future Demo Ideas

Possible additions:
- **Mandelbrot Set**: Fractal visualization with zoom
- **Breakout**: Paddle and brick breaking game
- **Lissajous Curves**: Mathematical curve animations
- **Fire Effect**: Plasma/fire simulation
- **Starfield**: 3D starfield with parallax
- **Pong**: Two-player paddle game with AI
- **Space Invaders**: Classic arcade game

---

## Contributing

To add a new demo:

1. Create `programs/my-demo.c` with the standard structure
2. Add to `Makefile`:
   ```makefile
   .PHONY: my-demo run-my-demo

   my-demo.elf: crt0.S uart.c syscalls.c printf.c time.c my-demo.c hello.ld
       $(CC) $(CFLAGS) -march=rv32imfd $(LDFLAGS) -o $@ $^ -lm -lgcc

   my-demo.bin: my-demo.elf
       $(OBJCOPY) -O binary $< $@

   run-my-demo: my-demo.bin
       $(EMULATOR) --pty --wait $< 0x80000000
   ```
3. Test: `make run-my-demo`
4. Document in this file

---

## License

All demo programs are provided as examples for the RISC-V emulator project.
