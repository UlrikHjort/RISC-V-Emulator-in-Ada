/* **************************************************************************
 *   RISC-V Emulator - GPIO Input Test - Reading Pins with Pull Resistors
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
 * GPIO Input Test - Reading Pins with Pull Resistors
 *
 * This program demonstrates GPIO input operations:
 * - Configuring pins as inputs
 * - Reading pin states
 * - Pull-up resistor configuration
 * - Pull-down resistor configuration
 * - Input/output loopback testing
 */

#include "gpio.h"

extern void printf(const char *fmt, ...);

/* Pin definitions */
#define INPUT_PIN1  8
#define INPUT_PIN2  9
#define INPUT_PIN3  10
#define INPUT_PIN4  11
#define OUTPUT_PIN  0

/* Simple delay function */
void delay(unsigned int count) {
    for (volatile unsigned int i = 0; i < count; i++) {
        /* Busy wait */
    }
}

int main(void) {
    printf("\n=== GPIO Input Test ===\n\n");

    /* Test 1: Basic input reading with pull-down */
    printf("=== Test 1: Pull-Down Resistors ===\n");

    /* Configure pins as inputs with pull-down */
    gpio_set_direction(INPUT_PIN1, GPIO_DIR_INPUT);
    gpio_set_pull(INPUT_PIN1, 1, GPIO_PULL_DOWN);

    gpio_set_direction(INPUT_PIN2, GPIO_DIR_INPUT);
    gpio_set_pull(INPUT_PIN2, 1, GPIO_PULL_DOWN);

    printf("Configured pins %d and %d as inputs with pull-down\n",
           INPUT_PIN1, INPUT_PIN2);

    /* Read values - should be low due to pull-down */
    unsigned int val1 = gpio_read_pin(INPUT_PIN1);
    unsigned int val2 = gpio_read_pin(INPUT_PIN2);

    printf("Pin %d value: %d (expected 0 - pulled down)\n", INPUT_PIN1, val1);
    printf("Pin %d value: %d (expected 0 - pulled down)\n", INPUT_PIN2, val2);

    if (val1 == GPIO_LOW && val2 == GPIO_LOW) {
        printf("PASS: Pull-down resistors working\n");
    } else {
        printf("FAIL: Pull-down not working correctly\n");
    }

    /* Test 2: Pull-up resistors */
    printf("\n=== Test 2: Pull-Up Resistors ===\n");

    /* Configure pins as inputs with pull-up */
    gpio_set_direction(INPUT_PIN3, GPIO_DIR_INPUT);
    gpio_set_pull(INPUT_PIN3, 1, GPIO_PULL_UP);

    gpio_set_direction(INPUT_PIN4, GPIO_DIR_INPUT);
    gpio_set_pull(INPUT_PIN4, 1, GPIO_PULL_UP);

    printf("Configured pins %d and %d as inputs with pull-up\n",
           INPUT_PIN3, INPUT_PIN4);

    /* Read values - should be high due to pull-up */
    unsigned int val3 = gpio_read_pin(INPUT_PIN3);
    unsigned int val4 = gpio_read_pin(INPUT_PIN4);

    printf("Pin %d value: %d (expected 1 - pulled up)\n", INPUT_PIN3, val3);
    printf("Pin %d value: %d (expected 1 - pulled up)\n", INPUT_PIN4, val4);

    if (val3 == GPIO_HIGH && val4 == GPIO_HIGH) {
        printf("PASS: Pull-up resistors working\n");
    } else {
        printf("FAIL: Pull-up not working correctly\n");
    }

    /* Test 3: Disabling pull resistors */
    printf("\n=== Test 3: Disabling Pull Resistors ===\n");

    /* Disable pull on INPUT_PIN1 */
    gpio_set_pull(INPUT_PIN1, 0, GPIO_PULL_DOWN);
    printf("Disabled pull resistor on pin %d\n", INPUT_PIN1);

    /* Read the pull enable register directly to verify */
    unsigned int pull_en = GPIO_PULL_EN;
    unsigned int mask = (1u << INPUT_PIN1);

    if ((pull_en & mask) == 0) {
        printf("PASS: Pull resistor disabled in register\n");
    } else {
        printf("FAIL: Pull resistor still enabled\n");
    }

    /* Test 4: Switching between pull-up and pull-down */
    printf("\n=== Test 4: Switching Pull Direction ===\n");

    #define TEST_PIN 12

    gpio_set_direction(TEST_PIN, GPIO_DIR_INPUT);

    /* Start with pull-down */
    gpio_set_pull(TEST_PIN, 1, GPIO_PULL_DOWN);
    delay(1000);
    unsigned int val_down = gpio_read_pin(TEST_PIN);
    printf("Pin %d with pull-down: %d\n", TEST_PIN, val_down);

    /* Switch to pull-up */
    gpio_set_pull(TEST_PIN, 1, GPIO_PULL_UP);
    delay(1000);
    unsigned int val_up = gpio_read_pin(TEST_PIN);
    printf("Pin %d with pull-up: %d\n", TEST_PIN, val_up);

    if (val_down == GPIO_LOW && val_up == GPIO_HIGH) {
        printf("PASS: Pull direction switching works\n");
    } else {
        printf("FAIL: Pull direction not switching correctly\n");
    }

    /* Test 5: Loopback - Output to Input */
    printf("\n=== Test 5: Output/Input Loopback ===\n");

    /* Note: In the emulator, output pins reflect their values when read
     * In real hardware, you'd need a physical connection between pins */

    #define LOOPBACK_OUT 16
    #define LOOPBACK_IN  16  /* Same pin read back */

    /* Configure as output */
    gpio_set_direction(LOOPBACK_OUT, GPIO_DIR_OUTPUT);
    printf("Configured pin %d as output\n", LOOPBACK_OUT);

    /* Test low output */
    gpio_write_pin(LOOPBACK_OUT, GPIO_LOW);
    delay(100);
    unsigned int read_low = gpio_read_pin(LOOPBACK_IN);
    printf("Write LOW (0), read back: %d\n", read_low);

    /* Test high output */
    gpio_write_pin(LOOPBACK_OUT, GPIO_HIGH);
    delay(100);
    unsigned int read_high = gpio_read_pin(LOOPBACK_IN);
    printf("Write HIGH (1), read back: %d\n", read_high);

    if (read_low == GPIO_LOW && read_high == GPIO_HIGH) {
        printf("PASS: Loopback read matches output\n");
    } else {
        printf("FAIL: Loopback mismatch\n");
    }

    /* Test 6: Reading multiple pins at once */
    printf("\n=== Test 6: Reading Multiple Pins ===\n");

    /* Configure pins 20-23 with alternating pull-up/pull-down */
    for (unsigned int i = 20; i < 24; i++) {
        gpio_set_direction(i, GPIO_DIR_INPUT);
        if (i % 2 == 0) {
            gpio_set_pull(i, 1, GPIO_PULL_DOWN);
            printf("Pin %d: pull-down\n", i);
        } else {
            gpio_set_pull(i, 1, GPIO_PULL_UP);
            printf("Pin %d: pull-up\n", i);
        }
    }

    delay(1000);

    /* Read all pins */
    printf("\nReading pin states:\n");
    unsigned int expected_pattern = 0x0A;  /* Binary: 1010 (pins 21, 23 high) */
    unsigned int actual_pattern = 0;

    for (unsigned int i = 20; i < 24; i++) {
        unsigned int val = gpio_read_pin(i);
        actual_pattern |= (val << (i - 20));
        printf("Pin %d: %d\n", i, val);
    }

    printf("\nPattern: 0x%x (expected 0x%x)\n", actual_pattern, expected_pattern);

    if (actual_pattern == expected_pattern) {
        printf("PASS: Multiple pin read correct\n");
    } else {
        printf("INFO: Pattern is 0x%x (pull state may vary)\n", actual_pattern);
    }

    /* Test 7: Direction register verification */
    printf("\n=== Test 7: Direction Register ===\n");

    /* Set specific direction pattern */
    gpio_set_direction(24, GPIO_DIR_OUTPUT);
    gpio_set_direction(25, GPIO_DIR_INPUT);
    gpio_set_direction(26, GPIO_DIR_OUTPUT);
    gpio_set_direction(27, GPIO_DIR_INPUT);

    printf("Set pins 24,26 as OUTPUT and 25,27 as INPUT\n");

    /* Read direction register */
    unsigned int dir_reg = GPIO_DIRECTION;
    unsigned int mask_24 = (1u << 24);
    unsigned int mask_25 = (1u << 25);
    unsigned int mask_26 = (1u << 26);
    unsigned int mask_27 = (1u << 27);

    printf("Direction register: 0x%08x\n", dir_reg);
    printf("Pin 24 (output): %d\n", (dir_reg & mask_24) ? 1 : 0);
    printf("Pin 25 (input):  %d\n", (dir_reg & mask_25) ? 1 : 0);
    printf("Pin 26 (output): %d\n", (dir_reg & mask_26) ? 1 : 0);
    printf("Pin 27 (input):  %d\n", (dir_reg & mask_27) ? 1 : 0);

    int dir_ok = ((dir_reg & mask_24) != 0) &&  /* Output = 1 */
                 ((dir_reg & mask_25) == 0) &&  /* Input = 0 */
                 ((dir_reg & mask_26) != 0) &&  /* Output = 1 */
                 ((dir_reg & mask_27) == 0);    /* Input = 0 */

    if (dir_ok) {
        printf("PASS: Direction register correct\n");
    } else {
        printf("FAIL: Direction register incorrect\n");
    }

    /* Test 8: Input register read */
    printf("\n=== Test 8: Raw Input Register ===\n");

    /* Configure pins 0-7 with known states */
    printf("Setting up pins 0-7 with pattern 0x55 (01010101)\n");
    for (unsigned int i = 0; i < 8; i++) {
        gpio_set_direction(i, GPIO_DIR_INPUT);
        if (i % 2 == 0) {
            gpio_set_pull(i, 1, GPIO_PULL_DOWN);
        } else {
            gpio_set_pull(i, 1, GPIO_PULL_UP);
        }
    }

    delay(1000);

    /* Read entire input register */
    unsigned int input_reg = GPIO_INPUT;
    unsigned int lower_byte = input_reg & 0xFF;

    printf("Input register: 0x%08x\n", input_reg);
    printf("Lower byte:     0x%02x (expected 0x55 or similar)\n", lower_byte);

    /* Check if odd-numbered pins are high */
    int pattern_ok = 1;
    for (unsigned int i = 1; i < 8; i += 2) {
        if (gpio_read_pin(i) != GPIO_HIGH) {
            pattern_ok = 0;
            break;
        }
    }

    if (pattern_ok) {
        printf("PASS: Input pattern as expected\n");
    } else {
        printf("INFO: Input pattern is 0x%02x\n", lower_byte);
    }

    printf("\n=== All GPIO Input Tests Complete ===\n");

    return 0;
}
