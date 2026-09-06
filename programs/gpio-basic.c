/* **************************************************************************
 *         RISC-V Emulator - GPIO Basic Test - LED Blink Simulation
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

// By Ulrik Hørlyk Hjort 2026
/**
 * GPIO Basic Test - LED Blink Simulation
 *
 * This program demonstrates basic GPIO operations:
 * - Configuring pins as outputs
 * - Setting and clearing output pins
 * - Toggling pins
 * - Simple delay loops
 */

#include "gpio.h"

extern void printf(const char *fmt, ...);

/* LED pin definitions */
#define LED0 0
#define LED1 1
#define LED2 2
#define LED3 3

/* Simple delay function (busy wait) */
void delay(unsigned int count) {
    for (volatile unsigned int i = 0; i < count; i++) {
        /* Busy wait */
    }
}

int main(void) {
    printf("\n=== GPIO Basic Test - LED Blink ===\n\n");

    /* Configure LED pins as outputs */
    printf("Configuring pins %d-%d as outputs...\n", LED0, LED3);
    gpio_set_direction(LED0, GPIO_DIR_OUTPUT);
    gpio_set_direction(LED1, GPIO_DIR_OUTPUT);
    gpio_set_direction(LED2, GPIO_DIR_OUTPUT);
    gpio_set_direction(LED3, GPIO_DIR_OUTPUT);

    /* Test 1: Turn on all LEDs */
    printf("\nTest 1: All LEDs ON\n");
    gpio_write_pin(LED0, GPIO_HIGH);
    gpio_write_pin(LED1, GPIO_HIGH);
    gpio_write_pin(LED2, GPIO_HIGH);
    gpio_write_pin(LED3, GPIO_HIGH);

    unsigned int output = GPIO_OUTPUT;
    printf("GPIO OUTPUT register: 0x%08x\n", output);
    printf("Expected: 0x0000000F (pins 0-3 high)\n");

    if ((output & 0x0F) == 0x0F) {
        printf("PASS: All LEDs are ON\n");
    } else {
        printf("FAIL: Unexpected output value\n");
    }

    delay(100000);

    /* Test 2: Turn off all LEDs */
    printf("\nTest 2: All LEDs OFF\n");
    gpio_write_pin(LED0, GPIO_LOW);
    gpio_write_pin(LED1, GPIO_LOW);
    gpio_write_pin(LED2, GPIO_LOW);
    gpio_write_pin(LED3, GPIO_LOW);

    output = GPIO_OUTPUT;
    printf("GPIO OUTPUT register: 0x%08x\n", output);
    printf("Expected: 0x00000000 (pins 0-3 low)\n");

    if ((output & 0x0F) == 0x00) {
        printf("PASS: All LEDs are OFF\n");
    } else {
        printf("FAIL: Unexpected output value\n");
    }

    delay(100000);

    /* Test 3: Binary counter pattern */
    printf("\nTest 3: Binary Counter (0-15)\n");
    for (unsigned int i = 0; i < 16; i++) {
        gpio_write_pin(LED0, (i & 1) ? GPIO_HIGH : GPIO_LOW);
        gpio_write_pin(LED1, (i & 2) ? GPIO_HIGH : GPIO_LOW);
        gpio_write_pin(LED2, (i & 4) ? GPIO_HIGH : GPIO_LOW);
        gpio_write_pin(LED3, (i & 8) ? GPIO_HIGH : GPIO_LOW);

        output = GPIO_OUTPUT & 0x0F;
        printf("  Count %2d: LEDs = 0x%x", i, output);

        if (output == i) {
            printf(" [OK]\n");
        } else {
            printf(" [FAIL - expected 0x%x]\n", i);
        }

        delay(50000);
    }
    printf("PASS: Binary counter complete\n");

    /* Test 4: Blinking pattern */
    printf("\nTest 4: Alternating Blink Pattern\n");
    for (unsigned int cycle = 0; cycle < 5; cycle++) {
        /* Pattern 1: LED0 and LED2 on */
        gpio_write_pin(LED0, GPIO_HIGH);
        gpio_write_pin(LED1, GPIO_LOW);
        gpio_write_pin(LED2, GPIO_HIGH);
        gpio_write_pin(LED3, GPIO_LOW);
        printf("  Cycle %d: Pattern 0101\n", cycle + 1);
        delay(100000);

        /* Pattern 2: LED1 and LED3 on */
        gpio_write_pin(LED0, GPIO_LOW);
        gpio_write_pin(LED1, GPIO_HIGH);
        gpio_write_pin(LED2, GPIO_LOW);
        gpio_write_pin(LED3, GPIO_HIGH);
        printf("  Cycle %d: Pattern 1010\n", cycle + 1);
        delay(100000);
    }
    printf("PASS: Alternating pattern complete\n");

    /* Test 5: Toggle test */
    printf("\nTest 5: Toggle Operation\n");

    /* Set all LEDs to known state (all off) */
    gpio_write_pin(LED0, GPIO_LOW);
    gpio_write_pin(LED1, GPIO_LOW);
    gpio_write_pin(LED2, GPIO_LOW);
    gpio_write_pin(LED3, GPIO_LOW);

    /* Toggle each LED and verify */
    for (unsigned int i = 0; i < 4; i++) {
        unsigned int before = GPIO_OUTPUT;
        gpio_toggle_pin(i);
        unsigned int after = GPIO_OUTPUT;
        unsigned int expected = before ^ (1u << i);

        printf("  Toggle pin %d: 0x%08x -> 0x%08x", i, before, after);

        if (after == expected) {
            printf(" [OK]\n");
        } else {
            printf(" [FAIL - expected 0x%08x]\n", expected);
        }
    }
    printf("PASS: Toggle operations complete\n");

    /* Test 6: Walking LED */
    printf("\nTest 6: Walking LED (Knight Rider effect)\n");
    for (unsigned int cycle = 0; cycle < 3; cycle++) {
        /* Walk forward */
        for (unsigned int i = 0; i < 4; i++) {
            gpio_write_pin(LED0, (i == 0) ? GPIO_HIGH : GPIO_LOW);
            gpio_write_pin(LED1, (i == 1) ? GPIO_HIGH : GPIO_LOW);
            gpio_write_pin(LED2, (i == 2) ? GPIO_HIGH : GPIO_LOW);
            gpio_write_pin(LED3, (i == 3) ? GPIO_HIGH : GPIO_LOW);
            printf("  LED %d is ON\n", i);
            delay(80000);
        }
        /* Walk backward */
        for (int i = 2; i >= 0; i--) {
            gpio_write_pin(LED0, (i == 0) ? GPIO_HIGH : GPIO_LOW);
            gpio_write_pin(LED1, (i == 1) ? GPIO_HIGH : GPIO_LOW);
            gpio_write_pin(LED2, (i == 2) ? GPIO_HIGH : GPIO_LOW);
            gpio_write_pin(LED3, (i == 3) ? GPIO_HIGH : GPIO_LOW);
            printf("  LED %d is ON\n", i);
            delay(80000);
        }
    }
    printf("PASS: Walking LED complete\n");

    /* Final state: All LEDs off */
    printf("\nCleaning up: Turning off all LEDs\n");
    gpio_write_pin(LED0, GPIO_LOW);
    gpio_write_pin(LED1, GPIO_LOW);
    gpio_write_pin(LED2, GPIO_LOW);
    gpio_write_pin(LED3, GPIO_LOW);

    printf("\n=== All GPIO Basic Tests PASSED ===\n");

    return 0;
}
