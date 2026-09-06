/* **************************************************************************
 *                     RISC-V Emulator - Maze Generator
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

// Maze Generator
// Uses recursive backtracking algorithm to generate perfect mazes
// Displays the generation process and then shows the solution
// By Ulrik Hørlyk Hjort 2026

#include "uart.h"
#include "printf.h"
#include "time.h"

// Maze dimensions (must be odd numbers)
#define WIDTH  39
#define HEIGHT 19

// Cell types
#define WALL    '#'
#define PATH    ' '
#define VISITED '.'
#define CURRENT '@'
#define SOLUTION '*'

// Directions
#define NORTH 0
#define EAST  1
#define SOUTH 2
#define WEST  3

// Maze grid
static char maze[HEIGHT][WIDTH];
static unsigned int rand_seed;

// Stack for backtracking (DFS)
typedef struct {
    int x;
    int y;
} Point;

static Point stack[WIDTH * HEIGHT];
static int stack_top;

// Solution path
static Point solution[WIDTH * HEIGHT];
static int solution_length;

// ============================================================================
// Random Number Generator
// ============================================================================

void seed_random(unsigned int seed) {
    rand_seed = seed;
}

int random_int(int max) {
    rand_seed = rand_seed * 1103515245 + 12345;
    return (rand_seed >> 16) % max;
}

void shuffle_array(int *array, int size) {
    for (int i = size - 1; i > 0; i--) {
        int j = random_int(i + 1);
        int temp = array[i];
        array[i] = array[j];
        array[j] = temp;
    }
}

// ============================================================================
// Display
// ============================================================================

void clear_screen(void) {
    printf("\033[2J\033[H");
}

void display_maze(const char *title) {
    printf("\033[H");  // Home cursor

    printf("+===========================================+\n");
    printf("|  %-40s |\n", title);
    printf("+===========================================+\n");

    for (int y = 0; y < HEIGHT; y++) {
        putchar(' ');
        for (int x = 0; x < WIDTH; x++) {
            putchar(maze[y][x]);
        }
        putchar('\n');
    }

    printf("\n");
}

// ============================================================================
// Maze Generation
// ============================================================================

void init_maze(void) {
    // Fill with walls
    for (int y = 0; y < HEIGHT; y++) {
        for (int x = 0; x < WIDTH; x++) {
            maze[y][x] = WALL;
        }
    }
}

int is_valid_cell(int x, int y) {
    return x > 0 && x < WIDTH - 1 && y > 0 && y < HEIGHT - 1;
}

void carve_path(int x, int y) {
    maze[y][x] = PATH;
}

// Get neighbor cell in given direction (2 steps away for walls)
void get_neighbor(int x, int y, int dir, int *nx, int *ny) {
    switch (dir) {
        case NORTH: *nx = x; *ny = y - 2; break;
        case EAST:  *nx = x + 2; *ny = y; break;
        case SOUTH: *nx = x; *ny = y + 2; break;
        case WEST:  *nx = x - 2; *ny = y; break;
    }
}

// Carve wall between current and neighbor
void carve_between(int x1, int y1, int x2, int y2) {
    int mx = (x1 + x2) / 2;
    int my = (y1 + y2) / 2;
    carve_path(mx, my);
}

void generate_maze_recursive(int x, int y, int animate) {
    carve_path(x, y);

    // Show animation
    if (animate) {
        maze[y][x] = CURRENT;
        display_maze("Generating Maze...");
        delay_ms(20);
        maze[y][x] = PATH;
    }

    // Try all directions in random order
    int dirs[] = {NORTH, EAST, SOUTH, WEST};
    shuffle_array(dirs, 4);

    for (int i = 0; i < 4; i++) {
        int nx, ny;
        get_neighbor(x, y, dirs[i], &nx, &ny);

        // If neighbor is valid and unvisited
        if (is_valid_cell(nx, ny) && maze[ny][nx] == WALL) {
            carve_between(x, y, nx, ny);
            generate_maze_recursive(nx, ny, animate);
        }
    }
}

// ============================================================================
// Maze Solving
// ============================================================================

int solve_maze_dfs(int x, int y, int end_x, int end_y, int animate) {
    // Reached destination
    if (x == end_x && y == end_y) {
        solution[solution_length].x = x;
        solution[solution_length].y = y;
        solution_length++;
        return 1;
    }

    // Mark as visited
    if (maze[y][x] == PATH) {
        maze[y][x] = VISITED;

        // Show animation
        if (animate) {
            display_maze("Solving Maze...");
            delay_ms(10);
        }

        // Try all 4 directions
        int dirs[][2] = {{0, -1}, {1, 0}, {0, 1}, {-1, 0}};
        for (int i = 0; i < 4; i++) {
            int nx = x + dirs[i][0];
            int ny = y + dirs[i][1];

            if (is_valid_cell(nx, ny) && maze[ny][nx] != WALL && maze[ny][nx] != VISITED) {
                if (solve_maze_dfs(nx, ny, end_x, end_y, animate)) {
                    // Add to solution path
                    solution[solution_length].x = x;
                    solution[solution_length].y = y;
                    solution_length++;
                    return 1;
                }
            }
        }

        // Backtrack
        if (animate) {
            maze[y][x] = PATH;
        }
    }

    return 0;
}

void mark_solution(void) {
    for (int i = 0; i < solution_length; i++) {
        int x = solution[i].x;
        int y = solution[i].y;
        maze[y][x] = SOLUTION;
    }
}

// ============================================================================
// Demo Variations
// ============================================================================

void demo_simple_maze(void) {
    printf("\n=== Simple Maze Generation ===\n");
    printf("Watch as the maze is carved out using recursive backtracking.\n\n");
    delay_ms(2000);

    init_maze();
    clear_screen();

    // Generate maze starting from (1, 1)
    generate_maze_recursive(1, 1, 1);

    display_maze("Maze Generated!");
    delay_ms(2000);
}

void demo_maze_with_solution(void) {
    printf("\n=== Maze with Solution ===\n");
    printf("Generate a maze and find the path from start to finish.\n\n");
    delay_ms(2000);

    init_maze();
    clear_screen();

    // Generate maze
    generate_maze_recursive(1, 1, 0);

    // Define start and end
    int start_x = 1, start_y = 1;
    int end_x = WIDTH - 2, end_y = HEIGHT - 2;

    // Mark start and end
    maze[start_y][start_x] = 'S';
    maze[end_y][end_x] = 'E';

    display_maze("Finding Solution...");
    delay_ms(1000);

    // Restore for solving
    maze[start_y][start_x] = PATH;
    maze[end_y][end_x] = PATH;

    // Solve maze
    solution_length = 0;
    if (solve_maze_dfs(start_x, start_y, end_x, end_y, 1)) {
        // Mark solution path
        mark_solution();
        maze[start_y][start_x] = 'S';
        maze[end_y][end_x] = 'E';

        display_maze("Solution Found!");
        printf("Path length: %d steps\n", solution_length);
    } else {
        display_maze("No solution found!");
    }

    delay_ms(3000);
}

void demo_multiple_mazes(void) {
    printf("\n=== Multiple Maze Variations ===\n");
    printf("Generating different maze layouts.\n\n");
    delay_ms(2000);

    for (int i = 0; i < 3; i++) {
        init_maze();
        clear_screen();

        // Use different seed for variety
        seed_random(12345 + i * 1000);

        generate_maze_recursive(1, 1, 0);

        // Display with variation number
        if (i == 0) display_maze("Maze Variation 1");
        else if (i == 1) display_maze("Maze Variation 2");
        else display_maze("Maze Variation 3");
        delay_ms(2000);
    }
}

// ============================================================================
// Main
// ============================================================================

int main(void) {
    uart_init();
    seed_random(42);

    printf("\n");
    printf("+===========================================+\n");
    printf("|       MAZE GENERATOR - RISC-V             |\n");
    printf("|    Recursive Backtracking Algorithm       |\n");
    printf("+===========================================+\n");
    printf("\n");
    printf("Features:\n");
    printf("  - Generates perfect mazes (one solution)\n");
    printf("  - Animated generation process\n");
    printf("  - Pathfinding with visualization\n");
    printf("\n");

    delay_ms(3000);

    // Run demonstrations
    demo_simple_maze();
    demo_maze_with_solution();
    demo_multiple_mazes();

    // Final message
    printf("\n");
    printf("+===========================================+\n");
    printf("|       Maze Generation Complete!           |\n");
    printf("+===========================================+\n");
    printf("\n");

    // Infinite loop
    while (1);

    return 0;
}
