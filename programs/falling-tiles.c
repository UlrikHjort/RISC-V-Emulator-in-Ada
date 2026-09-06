/* **************************************************************************
 *                   RISC-V Emulator - Falling Tiles Game
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

// Falling Tiles Game
// Classic falling blocks game with keyboard controls
// Demonstrates game logic, collision detection, and line clearing
// By Ulrik Hørlyk Hjort 2026

#include "uart.h"
#include "printf.h"
#include "time.h"

// UART registers for non-blocking input
#define UART_BASE 0x10000000
#define UART_RBR  (*(volatile unsigned char *)(UART_BASE + 0))
#define UART_LSR  (*(volatile unsigned char *)(UART_BASE + 5))
#define LSR_DR    (1 << 0)

// Board dimensions
#define BOARD_WIDTH  12
#define BOARD_HEIGHT 20

// Piece dimensions
#define PIECE_SIZE 4

// Game constants
#define EMPTY 0
#define PIECE 1
#define LOCKED 2

// Display characters
#define CHAR_EMPTY  ' '
#define CHAR_PIECE  '#'
#define CHAR_LOCKED '*'

// Tetromino shapes (7 classic pieces)
// I, O, T, S, Z, J, L
static const int pieces[7][4][4] = {
    // I piece
    {{0,0,0,0}, {1,1,1,1}, {0,0,0,0}, {0,0,0,0}},
    // O piece
    {{0,0,0,0}, {0,1,1,0}, {0,1,1,0}, {0,0,0,0}},
    // T piece
    {{0,0,0,0}, {0,1,0,0}, {1,1,1,0}, {0,0,0,0}},
    // S piece
    {{0,0,0,0}, {0,1,1,0}, {1,1,0,0}, {0,0,0,0}},
    // Z piece
    {{0,0,0,0}, {1,1,0,0}, {0,1,1,0}, {0,0,0,0}},
    // J piece
    {{0,0,0,0}, {1,0,0,0}, {1,1,1,0}, {0,0,0,0}},
    // L piece
    {{0,0,0,0}, {0,0,1,0}, {1,1,1,0}, {0,0,0,0}}
};

// Game state
static char board[BOARD_HEIGHT][BOARD_WIDTH];
static int current_piece[PIECE_SIZE][PIECE_SIZE];
static int piece_x, piece_y;
static int piece_type;
static int score;
static int lines_cleared;
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
// Keyboard Input
// ============================================================================

// Check if a character is available (non-blocking)
int kbhit(void) {
    return (UART_LSR & LSR_DR) != 0;
}

// Get character without blocking (returns 0 if none available)
char getch_nonblock(void) {
    if (kbhit()) {
        return UART_RBR;
    }
    return 0;
}

// ============================================================================
// Display
// ============================================================================

void clear_screen(void) {
    printf("\033[2J\033[H");
}

void display_board(void) {
    printf("\033[H");  // Home cursor

    printf("+==================================+\n");
    printf("|   FALLING TILES - RISC-V         |\n");
    printf("+==================================+\n\n");

    // Top border
    printf("  +");
    for (int x = 0; x < BOARD_WIDTH; x++) printf("=");
    printf("+\n");

    // Board with current piece
    for (int y = 0; y < BOARD_HEIGHT; y++) {
        printf("  |");
        for (int x = 0; x < BOARD_WIDTH; x++) {
            char c = CHAR_EMPTY;

            // Check if current piece occupies this position
            int px = x - piece_x;
            int py = y - piece_y;
            if (px >= 0 && px < PIECE_SIZE && py >= 0 && py < PIECE_SIZE) {
                if (current_piece[py][px]) {
                    c = CHAR_PIECE;
                }
            }

            // Check board
            if (c == CHAR_EMPTY && board[y][x] == LOCKED) {
                c = CHAR_LOCKED;
            }

            putchar(c);
        }
        printf("|\n");
    }

    // Bottom border
    printf("  +");
    for (int x = 0; x < BOARD_WIDTH; x++) printf("=");
    printf("+\n");

    // Stats
    printf("\n  Score: %d  |  Lines: %d\n", score, lines_cleared);

    // Controls
    if (!game_over) {
        printf("\n  Controls: A/D=Move  W=Rotate  S=Drop  Space=HardDrop\n");
    }

    if (game_over) {
        printf("\n  +==============================+\n");
        printf("  |        GAME OVER!            |\n");
        printf("  |     Final Score: %-6d     |\n", score);
        printf("  +==============================+\n");
    }
}

// ============================================================================
// Board Operations
// ============================================================================

void init_board(void) {
    for (int y = 0; y < BOARD_HEIGHT; y++) {
        for (int x = 0; x < BOARD_WIDTH; x++) {
            board[y][x] = EMPTY;
        }
    }
}

int check_collision(int offset_x, int offset_y) {
    for (int py = 0; py < PIECE_SIZE; py++) {
        for (int px = 0; px < PIECE_SIZE; px++) {
            if (current_piece[py][px]) {
                int bx = piece_x + px + offset_x;
                int by = piece_y + py + offset_y;

                // Check bounds
                if (bx < 0 || bx >= BOARD_WIDTH || by >= BOARD_HEIGHT) {
                    return 1;
                }

                // Check collision with locked pieces
                if (by >= 0 && board[by][bx] == LOCKED) {
                    return 1;
                }
            }
        }
    }
    return 0;
}

void lock_piece(void) {
    for (int py = 0; py < PIECE_SIZE; py++) {
        for (int px = 0; px < PIECE_SIZE; px++) {
            if (current_piece[py][px]) {
                int bx = piece_x + px;
                int by = piece_y + py;
                if (by >= 0 && by < BOARD_HEIGHT && bx >= 0 && bx < BOARD_WIDTH) {
                    board[by][bx] = LOCKED;
                }
            }
        }
    }
}

int check_line_full(int y) {
    for (int x = 0; x < BOARD_WIDTH; x++) {
        if (board[y][x] == EMPTY) {
            return 0;
        }
    }
    return 1;
}

void clear_line(int y) {
    // Move all lines above down
    for (int cy = y; cy > 0; cy--) {
        for (int x = 0; x < BOARD_WIDTH; x++) {
            board[cy][x] = board[cy - 1][x];
        }
    }

    // Clear top line
    for (int x = 0; x < BOARD_WIDTH; x++) {
        board[0][x] = EMPTY;
    }
}

int clear_lines(void) {
    int cleared = 0;

    for (int y = BOARD_HEIGHT - 1; y >= 0; y--) {
        if (check_line_full(y)) {
            clear_line(y);
            cleared++;
            y++;  // Check same line again
        }
    }

    return cleared;
}

// ============================================================================
// Piece Operations
// ============================================================================

void spawn_piece(void) {
    piece_type = random_int(7);
    piece_x = BOARD_WIDTH / 2 - 2;
    piece_y = 0;

    // Copy piece shape
    for (int y = 0; y < PIECE_SIZE; y++) {
        for (int x = 0; x < PIECE_SIZE; x++) {
            current_piece[y][x] = pieces[piece_type][y][x];
        }
    }

    // Check if spawn position is blocked
    if (check_collision(0, 0)) {
        game_over = 1;
    }
}

void rotate_piece_cw(void) {
    int temp[PIECE_SIZE][PIECE_SIZE];

    // Rotate 90 degrees clockwise
    for (int y = 0; y < PIECE_SIZE; y++) {
        for (int x = 0; x < PIECE_SIZE; x++) {
            temp[x][PIECE_SIZE - 1 - y] = current_piece[y][x];
        }
    }

    // Check if rotation is valid
    int old_piece[PIECE_SIZE][PIECE_SIZE];
    for (int y = 0; y < PIECE_SIZE; y++) {
        for (int x = 0; x < PIECE_SIZE; x++) {
            old_piece[y][x] = current_piece[y][x];
            current_piece[y][x] = temp[y][x];
        }
    }

    if (check_collision(0, 0)) {
        // Revert rotation
        for (int y = 0; y < PIECE_SIZE; y++) {
            for (int x = 0; x < PIECE_SIZE; x++) {
                current_piece[y][x] = old_piece[y][x];
            }
        }
    }
}

// ============================================================================
// Keyboard Controls
// ============================================================================

// Process keyboard input
void handle_keyboard(void) {
    char key = getch_nonblock();

    if (key == 0) return;  // No key pressed

    // Convert to lowercase
    if (key >= 'A' && key <= 'Z') {
        key = key + ('a' - 'A');
    }

    switch (key) {
        case 'a':  // Move left
        case 'h':  // Vim style
            if (!check_collision(-1, 0)) {
                piece_x--;
            }
            break;

        case 'd':  // Move right
        case 'l':  // Vim style
            if (!check_collision(1, 0)) {
                piece_x++;
            }
            break;

        case 'w':  // Rotate
        case 'k':  // Vim style
            rotate_piece_cw();
            break;

        case 's':  // Soft drop (move down one)
        case 'j':  // Vim style
            if (!check_collision(0, 1)) {
                piece_y++;
                score += 1;  // Bonus point for soft drop
            }
            break;

        case ' ':  // Hard drop (instant drop)
            while (!check_collision(0, 1)) {
                piece_y++;
                score += 2;  // Bonus points for hard drop
            }
            break;
    }
}

// ============================================================================
// Game Loop
// ============================================================================

int main(void) {
    uart_init();
    seed_random(54321);

    printf("\n");
    printf("+==================================+\n");
    printf("|   FALLING TILES - RISC-V         |\n");
    printf("|   Classic Falling Blocks Game    |\n");
    printf("+==================================+\n");
    printf("\n");
    printf("Controls:\n");
    printf("  A/D - Move Left/Right\n");
    printf("  W   - Rotate\n");
    printf("  S   - Soft Drop\n");
    printf("  Space - Hard Drop\n");
    printf("\n");
    printf("Starting in 3 seconds...\n");
    delay_ms(3000);

    // Initialize game
    init_board();
    spawn_piece();
    score = 0;
    lines_cleared = 0;
    game_over = 0;

    clear_screen();

    // Game loop
    int move_counter = 0;
    int drop_speed = 10;  // Piece drops every 10 frames (~1 second at 100ms/frame)

    while (!game_over) {
        display_board();

        // Handle keyboard input (non-blocking, checks every frame)
        for (int i = 0; i < 5; i++) {  // Check multiple times per frame
            handle_keyboard();
            delay_ms(20);  // 5 * 20ms = 100ms total per frame
        }

        move_counter++;

        // Auto-drop piece every N frames
        if (move_counter >= drop_speed) {
            move_counter = 0;

            // Try to move piece down
            if (!check_collision(0, 1)) {
                piece_y++;
            } else {
                // Lock piece
                lock_piece();

                // Clear lines
                int cleared = clear_lines();
                if (cleared > 0) {
                    lines_cleared += cleared;
                    score += cleared * cleared * 10;  // More points for multiple lines
                }

                // Spawn new piece
                spawn_piece();

                // Speed up as you clear more lines
                if (lines_cleared > 20) {
                    drop_speed = 5;  // Faster
                } else if (lines_cleared > 10) {
                    drop_speed = 7;  // Medium
                }
            }
        }
    }

    // Final display
    display_board();

    printf("\n");
    printf("Game ended after clearing %d lines!\n", lines_cleared);

    // Infinite loop
    while (1);

    return 0;
}
