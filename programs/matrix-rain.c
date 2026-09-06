/* **************************************************************************
 *                   RISC-V Emulator - Matrix Rain Effect
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

// Matrix Rain Effect
// Classic "digital rain" animation from The Matrix
// Cascading green characters with varying speeds
// By Ulrik Hørlyk Hjort 2026

#include "uart.h"
#include "printf.h"
#include "time.h"

// Screen dimensions
#define COLS 60
#define ROWS 24

// Rain drop state
typedef struct {
    int position;      // Current row position
    int speed;         // How fast it falls (1-3)
    int length;        // Length of the trail
    int brightness;    // Character brightness variation
    char character;    // The character to display
} RainDrop;

static RainDrop drops[COLS];
static unsigned int rand_seed;

// Character set (numbers, letters, katakana-like symbols)
static const char charset[] = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz!@#$%^&*()-=_+[]{}|;:,.<>?";
static const int charset_size = sizeof(charset) - 1;

// ============================================================================
// Random Number Generator
// ============================================================================

void seed_random(unsigned int seed) {
    rand_seed = seed;
}

int random_int(int max) {
    if (max <= 0) return 0;
    rand_seed = rand_seed * 1103515245 + 12345;
    return (rand_seed >> 16) % max;
}

// ============================================================================
// Display Functions
// ============================================================================

void clear_screen(void) {
    printf("\033[2J\033[H");
}

void move_cursor(int row, int col) {
    printf("\033[%d;%dH", row + 1, col + 1);
}

void set_color_green_bright(void) {
    printf("\033[1;32m");  // Bright green
}

void set_color_green_normal(void) {
    printf("\033[0;32m");  // Normal green
}

void set_color_green_dim(void) {
    printf("\033[2;32m");  // Dim green
}

void set_color_white(void) {
    printf("\033[1;37m");  // Bright white (for leading character)
}

void reset_color(void) {
    printf("\033[0m");
}

// ============================================================================
// Rain Drop Functions
// ============================================================================

void init_drop(int col) {
    drops[col].position = -random_int(ROWS);  // Start above screen
    drops[col].speed = 1 + random_int(3);     // Speed 1-3
    drops[col].length = 8 + random_int(12);   // Length 8-19
    drops[col].brightness = random_int(3);     // Brightness variation
    drops[col].character = charset[random_int(charset_size)];
}

void update_drop(int col) {
    drops[col].position += drops[col].speed;

    // Reset if off screen
    if (drops[col].position - drops[col].length > ROWS) {
        init_drop(col);
    }

    // Occasionally change character
    if (random_int(10) == 0) {
        drops[col].character = charset[random_int(charset_size)];
    }
}

void draw_drop(int col) {
    RainDrop *drop = &drops[col];

    // Draw the trail
    for (int i = 0; i < drop->length; i++) {
        int row = drop->position - i;

        if (row >= 0 && row < ROWS) {
            move_cursor(row, col);

            if (i == 0) {
                // Leading character - bright white
                set_color_white();
            } else if (i < 3) {
                // Near head - bright green
                set_color_green_bright();
            } else if (i < drop->length / 2) {
                // Middle - normal green
                set_color_green_normal();
            } else {
                // Tail - dim green
                set_color_green_dim();
            }

            // Display character (vary it slightly for effect)
            char c = drop->character;
            if (i > 0 && random_int(5) == 0) {
                c = charset[random_int(charset_size)];
            }
            putchar(c);
        }
    }

    // Erase tail
    int erase_row = drop->position - drop->length;
    if (erase_row >= 0 && erase_row < ROWS) {
        move_cursor(erase_row, col);
        putchar(' ');
    }
}

// ============================================================================
// Animation Functions
// ============================================================================

void init_rain(void) {
    for (int col = 0; col < COLS; col++) {
        init_drop(col);
        // Stagger start positions
        drops[col].position = -random_int(ROWS * 2);
    }
}

void update_rain(void) {
    for (int col = 0; col < COLS; col++) {
        update_drop(col);
    }
}

void draw_rain(void) {
    for (int col = 0; col < COLS; col++) {
        draw_drop(col);
    }
}

// ============================================================================
// Title Screen
// ============================================================================

void show_title(void) {
    clear_screen();
    set_color_green_bright();

    printf("\n");
    printf("    ###+   ###+ #####+ ########+######+ ##+##+  ##+\n");
    printf("    ####+ ####|##+==##++==##+==+##+==##+##|+##+##++\n");
    printf("    ##+####+##|#######|   ##|   ######++##| +###++ \n");
    printf("    ##|+##++##|##+==##|   ##|   ##+==##+##| ##+##+ \n");
    printf("    ##| +=+ ##|##|  ##|   ##|   ##|  ##|##|##++ ##+\n");
    printf("    +=+     +=++=+  +=+   +=+   +=+  +=++=++=+  +=+\n");
    printf("\n");

    set_color_green_normal();
    printf("              Digital Rain Effect - RISC-V\n");
    printf("\n");
    reset_color();

    delay_ms(2000);
}

void show_stats(void) {
    move_cursor(ROWS + 1, 0);
    set_color_green_dim();
    printf("RISC-V Emulator | Matrix Rain Demo | Press Ctrl+C to exit");
    reset_color();
}

// ============================================================================
// Demo Variations
// ============================================================================

void demo_classic_rain(void) {
    show_title();
    clear_screen();

    init_rain();

    printf("Classic Matrix Rain - Running for 20 seconds...\n\n");
    delay_ms(1000);

    clear_screen();

    // Run for about 20 seconds
    for (int frame = 0; frame < 200; frame++) {
        update_rain();
        draw_rain();
        show_stats();
        delay_ms(100);
    }
}

void demo_fast_rain(void) {
    clear_screen();
    printf("\nFast Rain Mode - Increased speed!\n\n");
    delay_ms(1500);

    // Make drops faster
    for (int col = 0; col < COLS; col++) {
        drops[col].speed = 2 + random_int(3);  // Speed 2-4
    }

    clear_screen();

    for (int frame = 0; frame < 150; frame++) {
        update_rain();
        draw_rain();
        show_stats();
        delay_ms(50);  // Faster refresh
    }
}

void demo_slow_zen(void) {
    clear_screen();
    printf("\nZen Mode - Slow and peaceful...\n\n");
    delay_ms(1500);

    // Make drops slower
    for (int col = 0; col < COLS; col++) {
        drops[col].speed = 1;
        drops[col].length = 5 + random_int(5);
    }

    clear_screen();

    for (int frame = 0; frame < 100; frame++) {
        update_rain();
        draw_rain();
        show_stats();
        delay_ms(150);  // Slower refresh
    }
}

// ============================================================================
// Main
// ============================================================================

int main(void) {
    uart_init();
    seed_random(11111);

    // Hide cursor
    printf("\033[?25l");

    // Run demonstrations
    demo_classic_rain();
    demo_fast_rain();
    demo_slow_zen();

    // Final screen
    clear_screen();
    set_color_green_bright();
    printf("\n");
    printf("+============================================================+\n");
    printf("|                  Matrix Rain Demo Complete                 |\n");
    printf("+============================================================+\n");
    printf("\n");
    reset_color();

    printf("Thank you for watching the digital rain.\n");
    printf("Wake up, Neo...\n\n");

    // Show cursor
    printf("\033[?25h");

    // Infinite loop
    while (1);

    return 0;
}
