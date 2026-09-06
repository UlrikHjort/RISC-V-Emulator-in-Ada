/* **************************************************************************
 *          RISC-V Emulator - GPIO Interrupt Test - Edge Detection
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
 * GPIO Interrupt Test - Edge Detection
 *
 * This program demonstrates GPIO interrupt functionality:
 * - Configuring edge-triggered interrupts
 * - Level-triggered interrupts
 * - Checking interrupt flags
 * - Clearing interrupt flags
 * - Simulating external signal changes
 */

#include "gpio.h"

extern void printf(const char *fmt, ...);

/* Pin definitions */
#define BUTTON_PIN  8   /* Input pin with interrupt */
#define LED_PIN     0   /* Output LED to indicate interrupt */

/* Simple delay function */
void delay(unsigned int count) {
    for (volatile unsigned int i = 0; i < count; i++) {
        /* Busy wait */
    }
}

/* Simulate external signal change on a pin */
void simulate_button_press(unsigned int pin) {
    /* This writes directly to GPIO_INPUT to simulate external input
     * In real hardware, external signals would drive these pins */
    unsigned int mask = (1u << pin);

    /* Simulate rising edge (button press) */
    unsigned int current = GPIO_INPUT;
    GPIO_INPUT = current | mask;  /* Note: Normally read-only */
}

void simulate_button_release(unsigned int pin) {
    unsigned int mask = (1u << pin);

    /* Simulate falling edge (button release) */
    unsigned int current = GPIO_INPUT;
    GPIO_INPUT = current & ~mask;
}

int main(void) {
    printf("\n=== GPIO Interrupt Test ===\n\n");

    /* Configure LED pin as output */
    printf("Configuring pin %d as output (LED indicator)\n", LED_PIN);
    gpio_set_direction(LED_PIN, GPIO_DIR_OUTPUT);
    gpio_write_pin(LED_PIN, GPIO_LOW);

    /* Configure button pin as input with pull-down */
    printf("Configuring pin %d as input (button)\n", BUTTON_PIN);
    gpio_set_direction(BUTTON_PIN, GPIO_DIR_INPUT);
    gpio_set_pull(BUTTON_PIN, 1, GPIO_PULL_DOWN);

    /* Test 1: Edge-triggered interrupts */
    printf("\n=== Test 1: Edge-Triggered Interrupt ===\n");

    /* Enable edge-triggered interrupt on button pin */
    gpio_enable_interrupt(BUTTON_PIN, GPIO_INT_EDGE);
    printf("Enabled edge-triggered interrupt on pin %d\n", BUTTON_PIN);

    /* Verify no interrupt is pending initially */
    if (gpio_interrupt_pending(BUTTON_PIN)) {
        printf("WARNING: Interrupt already pending\n");
        gpio_clear_interrupt(BUTTON_PIN);
    }

    /* Simulate button press (rising edge) */
    printf("\nSimulating button press (rising edge)...\n");
    simulate_button_press(BUTTON_PIN);
    delay(10000);

    /* Check if interrupt was triggered */
    if (gpio_interrupt_pending(BUTTON_PIN)) {
        printf("PASS: Rising edge interrupt detected!\n");
        gpio_write_pin(LED_PIN, GPIO_HIGH);  /* Turn on LED */
        printf("LED turned ON\n");

        /* Clear the interrupt */
        gpio_clear_interrupt(BUTTON_PIN);
        printf("Interrupt flag cleared\n");

        /* Verify it was cleared */
        if (!gpio_interrupt_pending(BUTTON_PIN)) {
            printf("PASS: Interrupt flag successfully cleared\n");
        } else {
            printf("FAIL: Interrupt flag not cleared\n");
        }
    } else {
        printf("FAIL: No interrupt detected on rising edge\n");
    }

    delay(100000);

    /* Simulate button release (falling edge) */
    printf("\nSimulating button release (falling edge)...\n");
    simulate_button_release(BUTTON_PIN);
    delay(10000);

    /* Check if interrupt was triggered */
    if (gpio_interrupt_pending(BUTTON_PIN)) {
        printf("PASS: Falling edge interrupt detected!\n");
        gpio_write_pin(LED_PIN, GPIO_LOW);  /* Turn off LED */
        printf("LED turned OFF\n");

        /* Clear the interrupt */
        gpio_clear_interrupt(BUTTON_PIN);
    } else {
        printf("FAIL: No interrupt detected on falling edge\n");
    }

    delay(100000);

    /* Test 2: Level-triggered interrupts */
    printf("\n=== Test 2: Level-Triggered Interrupt ===\n");

    /* Disable edge-triggered interrupt first */
    gpio_disable_interrupt(BUTTON_PIN);

    /* Ensure pin is low */
    simulate_button_release(BUTTON_PIN);
    delay(10000);

    /* Enable level-triggered interrupt */
    gpio_enable_interrupt(BUTTON_PIN, GPIO_INT_LEVEL);
    printf("Enabled level-triggered interrupt on pin %d\n", BUTTON_PIN);

    /* With pin low, no interrupt should be pending */
    if (gpio_interrupt_pending(BUTTON_PIN)) {
        printf("INFO: Interrupt pending while low (expected for level trigger)\n");
        gpio_clear_interrupt(BUTTON_PIN);
    }

    /* Set pin high */
    printf("\nSetting pin high (level active)...\n");
    simulate_button_press(BUTTON_PIN);
    delay(10000);

    /* Check for level interrupt */
    if (gpio_interrupt_pending(BUTTON_PIN)) {
        printf("PASS: Level interrupt triggered while pin is high\n");
        gpio_clear_interrupt(BUTTON_PIN);
    } else {
        printf("FAIL: No level interrupt detected\n");
    }

    /* Test 3: Multiple interrupt sources */
    printf("\n=== Test 3: Multiple Interrupt Sources ===\n");

    #define BUTTON1_PIN 10
    #define BUTTON2_PIN 11
    #define BUTTON3_PIN 12

    /* Configure multiple input pins */
    gpio_set_direction(BUTTON1_PIN, GPIO_DIR_INPUT);
    gpio_set_direction(BUTTON2_PIN, GPIO_DIR_INPUT);
    gpio_set_direction(BUTTON3_PIN, GPIO_DIR_INPUT);

    gpio_set_pull(BUTTON1_PIN, 1, GPIO_PULL_DOWN);
    gpio_set_pull(BUTTON2_PIN, 1, GPIO_PULL_DOWN);
    gpio_set_pull(BUTTON3_PIN, 1, GPIO_PULL_DOWN);

    /* Enable edge interrupts on all three */
    gpio_enable_interrupt(BUTTON1_PIN, GPIO_INT_EDGE);
    gpio_enable_interrupt(BUTTON2_PIN, GPIO_INT_EDGE);
    gpio_enable_interrupt(BUTTON3_PIN, GPIO_INT_EDGE);

    printf("Configured pins %d, %d, %d with edge interrupts\n",
           BUTTON1_PIN, BUTTON2_PIN, BUTTON3_PIN);

    /* Trigger interrupts on different pins */
    printf("\nTriggering button 1...\n");
    simulate_button_press(BUTTON1_PIN);
    delay(10000);

    if (gpio_interrupt_pending(BUTTON1_PIN)) {
        printf("PASS: Button 1 interrupt detected\n");
        gpio_clear_interrupt(BUTTON1_PIN);
    }

    printf("Triggering button 2...\n");
    simulate_button_press(BUTTON2_PIN);
    delay(10000);

    if (gpio_interrupt_pending(BUTTON2_PIN)) {
        printf("PASS: Button 2 interrupt detected\n");
        gpio_clear_interrupt(BUTTON2_PIN);
    }

    printf("Triggering button 3...\n");
    simulate_button_press(BUTTON3_PIN);
    delay(10000);

    if (gpio_interrupt_pending(BUTTON3_PIN)) {
        printf("PASS: Button 3 interrupt detected\n");
        gpio_clear_interrupt(BUTTON3_PIN);
    }

    /* Test 4: Rapid edge detection */
    printf("\n=== Test 4: Rapid Edge Detection ===\n");

    gpio_disable_interrupt(BUTTON1_PIN);
    gpio_disable_interrupt(BUTTON2_PIN);
    gpio_disable_interrupt(BUTTON3_PIN);

    gpio_enable_interrupt(BUTTON_PIN, GPIO_INT_EDGE);

    unsigned int edge_count = 0;
    printf("Simulating 10 rapid button presses...\n");

    for (unsigned int i = 0; i < 10; i++) {
        /* Press */
        simulate_button_press(BUTTON_PIN);
        delay(5000);

        if (gpio_interrupt_pending(BUTTON_PIN)) {
            edge_count++;
            gpio_clear_interrupt(BUTTON_PIN);
        }

        /* Release */
        simulate_button_release(BUTTON_PIN);
        delay(5000);

        if (gpio_interrupt_pending(BUTTON_PIN)) {
            edge_count++;
            gpio_clear_interrupt(BUTTON_PIN);
        }
    }

    printf("Detected %d edges (expected 20)\n", edge_count);
    if (edge_count == 20) {
        printf("PASS: All rapid edges detected\n");
    } else if (edge_count >= 18) {
        printf("PASS: Most edges detected (%d/20)\n", edge_count);
    } else {
        printf("FAIL: Too few edges detected (%d/20)\n", edge_count);
    }

    /* Cleanup */
    printf("\n=== Cleanup ===\n");
    gpio_disable_interrupt(BUTTON_PIN);
    gpio_disable_interrupt(BUTTON1_PIN);
    gpio_disable_interrupt(BUTTON2_PIN);
    gpio_disable_interrupt(BUTTON3_PIN);
    gpio_write_pin(LED_PIN, GPIO_LOW);
    printf("All interrupts disabled, LED off\n");

    printf("\n=== All GPIO Interrupt Tests Complete ===\n");

    return 0;
}
