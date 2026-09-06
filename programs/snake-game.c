/* **************************************************************************
 *                       RISC-V Emulator - Snake Game
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

// Snake Game
// Classic snake game with simulated AI movement
// The snake automatically navigates to find food
// By Ulrik Hørlyk Hjort 2026

#include "uart.h"
#include "printf.h"
#include "time.h"

// Grid dimensions
#define WIDTH  40
#define HEIGHT 20

// Game constants
#define MAX_SNAKE_LENGTH (WIDTH * HEIGHT)
#define INITIAL_LENGTH 4

// Cell types
#define EMPTY 0
#define SNAKE 1
#define FOOD  2
#define WALL  3

// Directions
#define UP    0
#define RIGHT 1
#define DOWN  2
#define LEFT  3

// Display characters
#define CHAR_EMPTY ' '
#define CHAR_SNAKE '#'
#define CHAR_HEAD  'O'
#define CHAR_FOOD  '*'
#define CHAR_WALL  '='

// Snake body segment
typedef struct {
    int x;
    int y;
} Point;

// Game state
static char grid[HEIGHT][WIDTH];
static Point snake[MAX_SNAKE_LENGTH];
static int snake_length;
static int direction;
static Point food;
static int score;
static int game_over;
static unsigned int rand_seed;

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

// ============================================================================
// Grid Operations
// ============================================================================

void clear_grid(void) {
    for (int y = 0; y < HEIGHT; y++) {
        for (int x = 0; x < WIDTH; x++) {
            // Add walls around the border
            if (y == 0 || y == HEIGHT - 1 || x == 0 || x == WIDTH - 1) {
                grid[y][x] = WALL;
            } else {
                grid[y][x] = EMPTY;
            }
        }
    }
}

void draw_grid(void) {
    // Clear screen and home cursor
    printf("\033[2J\033[H");

    // Title
    printf("+========================================+\n");
    printf("|         SNAKE GAME - RISC-V            |\n");
    printf("+========================================+\n\n");

    // Draw grid
    for (int y = 0; y < HEIGHT; y++) {
        for (int x = 0; x < WIDTH; x++) {
            char c = CHAR_EMPTY;

            if (grid[y][x] == WALL) {
                c = CHAR_WALL;
            } else if (grid[y][x] == FOOD) {
                c = CHAR_FOOD;
            } else if (grid[y][x] == SNAKE) {
                // Check if it's the head
                if (x == snake[0].x && y == snake[0].y) {
                    c = CHAR_HEAD;
                } else {
                    c = CHAR_SNAKE;
                }
            }

            putchar(c);
        }
        putchar('\n');
    }

    // Stats
    printf("\nScore: %d  |  Length: %d  |  Food: (%d, %d)\n",
           score, snake_length, food.x, food.y);

    if (game_over) {
        printf("\n+========================================+\n");
        printf("|           GAME OVER!                   |\n");
        printf("|      Final Score: %-5d               |\n", score);
        printf("+========================================+\n");
    }
}

// ============================================================================
// Snake Logic
// ============================================================================

void init_snake(void) {
    snake_length = INITIAL_LENGTH;
    direction = RIGHT;

    // Start in the middle
    int start_x = WIDTH / 2;
    int start_y = HEIGHT / 2;

    for (int i = 0; i < snake_length; i++) {
        snake[i].x = start_x - i;
        snake[i].y = start_y;
        grid[start_y][start_x - i] = SNAKE;
    }
}

void spawn_food(void) {
    // Find random empty location
    int attempts = 0;
    do {
        food.x = 1 + random_int(WIDTH - 2);
        food.y = 1 + random_int(HEIGHT - 2);
        attempts++;
    } while (grid[food.y][food.x] != EMPTY && attempts < 100);

    if (grid[food.y][food.x] == EMPTY) {
        grid[food.y][food.x] = FOOD;
    }
}

int get_next_x(int x, int dir) {
    if (dir == LEFT) return x - 1;
    if (dir == RIGHT) return x + 1;
    return x;
}

int get_next_y(int y, int dir) {
    if (dir == UP) return y - 1;
    if (dir == DOWN) return y + 1;
    return y;
}

// Helper: absolute value
int abs(int x) {
    return x < 0 ? -x : x;
}

// Simple AI: move towards food
void ai_choose_direction(void) {
    int head_x = snake[0].x;
    int head_y = snake[0].y;

    // Try to move towards food
    int dx = food.x - head_x;
    int dy = food.y - head_y;

    // Priority: larger distance first
    if (abs(dx) > abs(dy)) {
        // Try horizontal movement
        int new_dir = (dx > 0) ? RIGHT : LEFT;
        int next_x = get_next_x(head_x, new_dir);
        int next_y = get_next_y(head_y, new_dir);

        if (grid[next_y][next_x] != SNAKE && grid[next_y][next_x] != WALL) {
            direction = new_dir;
            return;
        }
    }

    // Try vertical movement
    int new_dir = (dy > 0) ? DOWN : UP;
    int next_x = get_next_x(head_x, new_dir);
    int next_y = get_next_y(head_y, new_dir);

    if (grid[next_y][next_x] != SNAKE && grid[next_y][next_x] != WALL) {
        direction = new_dir;
        return;
    }

    // If can't move toward food, try any valid direction
    int dirs[] = {UP, RIGHT, DOWN, LEFT};
    for (int i = 0; i < 4; i++) {
        next_x = get_next_x(head_x, dirs[i]);
        next_y = get_next_y(head_y, dirs[i]);

        if (grid[next_y][next_x] != SNAKE && grid[next_y][next_x] != WALL) {
            direction = dirs[i];
            return;
        }
    }
}

void move_snake(void) {
    // Get next head position
    int new_x = get_next_x(snake[0].x, direction);
    int new_y = get_next_y(snake[0].y, direction);

    // Check collision with wall or self
    if (grid[new_y][new_x] == WALL || grid[new_y][new_x] == SNAKE) {
        game_over = 1;
        return;
    }

    // Check if eating food
    int ate_food = (new_x == food.x && new_y == food.y);

    // Move head
    if (!ate_food) {
        // Remove tail
        Point tail = snake[snake_length - 1];
        grid[tail.y][tail.x] = EMPTY;

        // Shift body
        for (int i = snake_length - 1; i > 0; i--) {
            snake[i] = snake[i - 1];
        }
    } else {
        // Growing - shift body but keep tail
        for (int i = snake_length; i > 0; i--) {
            snake[i] = snake[i - 1];
        }
        snake_length++;
        score += 10;

        // Spawn new food
        spawn_food();
    }

    // Place new head
    snake[0].x = new_x;
    snake[0].y = new_y;
    grid[new_y][new_x] = SNAKE;
}

// ============================================================================
// Main Game Loop
// ============================================================================

int main(void) {
    uart_init();
    seed_random(12345);

    printf("\n");
    printf("+========================================+\n");
    printf("|         SNAKE GAME - RISC-V            |\n");
    printf("|     Watch the AI play automatically!   |\n");
    printf("+========================================+\n");
    printf("\n");
    printf("Starting in 2 seconds...\n");
    delay_ms(2000);

    // Initialize game
    clear_grid();
    init_snake();
    spawn_food();
    score = 0;
    game_over = 0;

    // Game loop
    while (!game_over && snake_length < MAX_SNAKE_LENGTH) {
        draw_grid();
        delay_ms(150);  // Control speed

        // AI chooses direction
        ai_choose_direction();

        // Move snake
        move_snake();
    }

    // Final display
    draw_grid();

    if (snake_length >= MAX_SNAKE_LENGTH) {
        printf("\n+========================================+\n");
        printf("|         YOU WON! PERFECT GAME!         |\n");
        printf("+========================================+\n");
    }

    printf("\nGame ended after %d moves!\n", score / 10);

    // Infinite loop
    while (1);

    return 0;
}
