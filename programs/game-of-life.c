/* **************************************************************************
 *                 RISC-V Emulator - Conway's Game of Life
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
 * **************************************************************************/

// Conway's Game of Life
// Classic cellular automaton simulation
// Prints animated patterns to UART
// By Ulrik Hørlyk Hjort 2026

#include "uart.h"
#include "printf.h"
#include "string.h"
#include "time.h"

// Grid dimensions
#define WIDTH  40
#define HEIGHT 20

// Cell states
#define DEAD  0
#define ALIVE 1

// Display characters
#define CHAR_ALIVE '#'
#define CHAR_DEAD  ' '

// Double buffering for smooth updates
static char grid[HEIGHT][WIDTH];
static char next_grid[HEIGHT][WIDTH];

// Statistics
static int generation = 0;
static int population = 0;

// ============================================================================
// Grid Operations
// ============================================================================

// Clear the grid
void clear_grid(void) {
    for (int y = 0; y < HEIGHT; y++) {
        for (int x = 0; x < WIDTH; x++) {
            grid[y][x] = DEAD;
            next_grid[y][x] = DEAD;
        }
    }
}

// Set a cell to alive
void set_cell(int x, int y) {
    if (x >= 0 && x < WIDTH && y >= 0 && y < HEIGHT) {
        grid[y][x] = ALIVE;
    }
}

// Count living neighbors (8-connected)
int count_neighbors(int x, int y) {
    int count = 0;

    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            if (dx == 0 && dy == 0) continue;  // Skip center cell

            int nx = x + dx;
            int ny = y + dy;

            // Wrap around edges (toroidal topology)
            if (nx < 0) nx = WIDTH - 1;
            if (nx >= WIDTH) nx = 0;
            if (ny < 0) ny = HEIGHT - 1;
            if (ny >= HEIGHT) ny = 0;

            if (grid[ny][nx] == ALIVE) {
                count++;
            }
        }
    }

    return count;
}

// Apply Game of Life rules
void update_grid(void) {
    population = 0;

    for (int y = 0; y < HEIGHT; y++) {
        for (int x = 0; x < WIDTH; x++) {
            int neighbors = count_neighbors(x, y);
            int current = grid[y][x];

            // Conway's rules:
            // 1. Any live cell with 2-3 neighbors survives
            // 2. Any dead cell with exactly 3 neighbors becomes alive
            // 3. All other cells die or stay dead

            if (current == ALIVE) {
                next_grid[y][x] = (neighbors == 2 || neighbors == 3) ? ALIVE : DEAD;
            } else {
                next_grid[y][x] = (neighbors == 3) ? ALIVE : DEAD;
            }

            if (next_grid[y][x] == ALIVE) {
                population++;
            }
        }
    }

    // Copy next_grid to grid
    for (int y = 0; y < HEIGHT; y++) {
        for (int x = 0; x < WIDTH; x++) {
            grid[y][x] = next_grid[y][x];
        }
    }

    generation++;
}

// ============================================================================
// Display
// ============================================================================

// Clear screen (ANSI escape code)
void clear_screen(void) {
    printf("\033[2J\033[H");  // Clear screen and move cursor to home
}

// Move cursor to home position
void home_cursor(void) {
    printf("\033[H");
}

// Display the grid
void display_grid(void) {
    home_cursor();

    // Top border
    printf("+");
    for (int i = 0; i < WIDTH; i++) printf("-");
    printf("+\n");

    // Grid contents
    for (int y = 0; y < HEIGHT; y++) {
        printf("|");
        for (int x = 0; x < WIDTH; x++) {
            putchar(grid[y][x] == ALIVE ? CHAR_ALIVE : CHAR_DEAD);
        }
        printf("|\n");
    }

    // Bottom border
    printf("+");
    for (int i = 0; i < WIDTH; i++) printf("-");
    printf("+\n");

    // Statistics
    printf("Generation: %d  |  Population: %d  |  Press Ctrl+C to exit\n",
           generation, population);
}

// ============================================================================
// Pattern Library
// ============================================================================

// Glider - moves diagonally
void spawn_glider(int x, int y) {
    set_cell(x+1, y);
    set_cell(x+2, y+1);
    set_cell(x, y+2);
    set_cell(x+1, y+2);
    set_cell(x+2, y+2);
}

// Blinker - oscillates with period 2
void spawn_blinker(int x, int y) {
    set_cell(x, y);
    set_cell(x+1, y);
    set_cell(x+2, y);
}

// Toad - oscillates with period 2
void spawn_toad(int x, int y) {
    set_cell(x+1, y);
    set_cell(x+2, y);
    set_cell(x+3, y);
    set_cell(x, y+1);
    set_cell(x+1, y+1);
    set_cell(x+2, y+1);
}

// Beacon - oscillates with period 2
void spawn_beacon(int x, int y) {
    set_cell(x, y);
    set_cell(x+1, y);
    set_cell(x, y+1);
    set_cell(x+3, y+2);
    set_cell(x+2, y+3);
    set_cell(x+3, y+3);
}

// Pulsar - oscillates with period 3
void spawn_pulsar(int x, int y) {
    // Top section
    for (int i = 0; i < 3; i++) {
        set_cell(x+2+i, y);
        set_cell(x+8+i, y);
    }

    // Vertical bars
    for (int j = 0; j < 3; j++) {
        set_cell(x, y+2+j);
        set_cell(x+5, y+2+j);
        set_cell(x+7, y+2+j);
        set_cell(x+12, y+2+j);

        set_cell(x, y+8+j);
        set_cell(x+5, y+8+j);
        set_cell(x+7, y+8+j);
        set_cell(x+12, y+8+j);
    }

    // Bottom section
    for (int i = 0; i < 3; i++) {
        set_cell(x+2+i, y+12);
        set_cell(x+8+i, y+12);
    }
}

// Lightweight spaceship (LWSS) - moves horizontally
void spawn_lwss(int x, int y) {
    set_cell(x+1, y);
    set_cell(x+4, y);
    set_cell(x, y+1);
    set_cell(x, y+2);
    set_cell(x+4, y+2);
    set_cell(x, y+3);
    set_cell(x+1, y+3);
    set_cell(x+2, y+3);
    set_cell(x+3, y+3);
}

// R-pentomino - chaotic pattern that stabilizes after ~1100 generations
void spawn_r_pentomino(int x, int y) {
    set_cell(x+1, y);
    set_cell(x+2, y);
    set_cell(x, y+1);
    set_cell(x+1, y+1);
    set_cell(x+1, y+2);
}

// Acorn - small pattern that takes 5206 generations to stabilize
void spawn_acorn(int x, int y) {
    set_cell(x+1, y);
    set_cell(x+3, y+1);
    set_cell(x, y+2);
    set_cell(x+1, y+2);
    set_cell(x+4, y+2);
    set_cell(x+5, y+2);
    set_cell(x+6, y+2);
}

// Random pattern
void spawn_random(void) {
    // Use a simple LCG for random numbers
    unsigned int seed = 12345;

    for (int y = 0; y < HEIGHT; y++) {
        for (int x = 0; x < WIDTH; x++) {
            // Simple random number generator
            seed = seed * 1103515245 + 12345;
            if ((seed >> 16) % 100 < 30) {  // 30% chance of being alive
                set_cell(x, y);
            }
        }
    }
}

// ============================================================================
// Demo Patterns
// ============================================================================

void demo_oscillators(void) {
    clear_grid();

    printf("\n=== Demo: Oscillators ===\n");
    printf("Various patterns that repeat after a fixed number of steps.\n\n");

    spawn_blinker(5, 3);
    spawn_toad(12, 3);
    spawn_beacon(20, 3);
    spawn_pulsar(5, 8);

    clear_screen();

    for (int i = 0; i < 50; i++) {
        display_grid();
        delay_ms(200);
        update_grid();
    }
}

void demo_spaceships(void) {
    clear_grid();

    printf("\n=== Demo: Spaceships ===\n");
    printf("Patterns that move across the grid.\n\n");

    spawn_glider(5, 5);
    spawn_glider(15, 3);
    spawn_lwss(25, 10);

    clear_screen();

    for (int i = 0; i < 100; i++) {
        display_grid();
        delay_ms(150);
        update_grid();
    }
}

void demo_chaos(void) {
    clear_grid();

    printf("\n=== Demo: Chaotic Patterns ===\n");
    printf("Small patterns that evolve unpredictably.\n\n");

    spawn_r_pentomino(18, 8);

    clear_screen();

    for (int i = 0; i < 200; i++) {
        display_grid();
        delay_ms(100);
        update_grid();

        // Stop if pattern dies out
        if (population == 0) {
            printf("\nPattern died out at generation %d\n", generation);
            break;
        }
    }
}

void demo_random(void) {
    clear_grid();

    printf("\n=== Demo: Random Soup ===\n");
    printf("Random initial configuration.\n\n");

    spawn_random();

    clear_screen();

    for (int i = 0; i < 100; i++) {
        display_grid();
        delay_ms(100);
        update_grid();

        // Stop if pattern dies out or stabilizes
        if (population == 0) {
            printf("\nPattern died out at generation %d\n", generation);
            break;
        }
    }
}

// ============================================================================
// Main
// ============================================================================

int main(void) {
    uart_init();

    printf("\n");
    printf("+=======================================+\n");
    printf("|   Conway's Game of Life - RISC-V     |\n");
    printf("|   Cellular Automaton Simulation      |\n");
    printf("+=======================================+\n");
    printf("\n");
    printf("Rules:\n");
    printf("  1. Any live cell with 2-3 neighbors survives\n");
    printf("  2. Any dead cell with exactly 3 neighbors becomes alive\n");
    printf("  3. All other cells die or stay dead\n");
    printf("\n");

    delay_ms(2000);

    // Run demonstrations
    demo_oscillators();
    delay_ms(1000);

    demo_spaceships();
    delay_ms(1000);

    demo_chaos();
    delay_ms(1000);

    demo_random();

    // Final summary
    printf("\n");
    printf("+=======================================+\n");
    printf("|   Game of Life Demo Complete!        |\n");
    printf("+=======================================+\n");
    printf("\n");
    printf("Final Statistics:\n");
    printf("  Total Generations: %d\n", generation);
    printf("  Final Population:  %d\n", population);
    printf("\n");

    // Infinite loop
    while (1);

    return 0;
}
