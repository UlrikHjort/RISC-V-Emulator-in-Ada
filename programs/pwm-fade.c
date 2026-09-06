/* **************************************************************************
 *                  RISC-V Emulator - PWM LED Fading Demo
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
 * PWM LED Fading Demo
 *
 * Demonstrates PWM functionality with smooth LED fading:
 * - Timer: Generate PWM signals on multiple channels
 * - GPIO: Simulate LED outputs
 * - UART: Display real-time PWM status
 *
 * Creates various LED fade patterns:
 * - Channel 0: Fade in/out (breathing effect)
 * - Channel 1: Pulse
 * - Channel 2: Fast blink
 * - Channel 3: Slow ramp
 */

extern void printf(const char *fmt, ...);

#include "timer.h"
#include "gpio.h"

/* LED/PWM configuration */
#define NUM_LEDS 4
#define LED_PIN_BASE 0

/* Animation state */
typedef struct {
    unsigned char duty;      /* Current duty cycle (0-255) */
    char direction;          /* 1=increasing, -1=decreasing */
    unsigned char step;      /* Change per update */
    unsigned char min;       /* Minimum duty */
    unsigned char max;       /* Maximum duty */
} led_state_t;

static led_state_t leds[NUM_LEDS];
static unsigned int frame_count = 0;

/**
 * Initialize LED animation patterns
 */
static void init_led_patterns(void) {
    /* LED 0: Breathing (slow fade in/out) */
    leds[0].duty = 0;
    leds[0].direction = 1;
    leds[0].step = 2;
    leds[0].min = 0;
    leds[0].max = 255;

    /* LED 1: Pulse (fast fade in, instant off) */
    leds[1].duty = 0;
    leds[1].direction = 1;
    leds[1].step = 8;
    leds[1].min = 0;
    leds[1].max = 255;

    /* LED 2: Fast blink (50% duty square wave) */
    leds[2].duty = 0;
    leds[2].direction = 1;
    leds[2].step = 255;  /* Instant on/off */
    leds[2].min = 0;
    leds[2].max = 128;

    /* LED 3: Slow ramp (sawtooth wave) */
    leds[3].duty = 0;
    leds[3].direction = 1;
    leds[3].step = 1;
    leds[3].min = 32;
    leds[3].max = 224;
}

/**
 * Update single LED state
 */
static void update_led(int ch) {
    led_state_t *led = &leds[ch];

    /* Update duty cycle */
    if (led->direction > 0) {
        /* Increasing */
        if (led->duty + led->step >= led->max) {
            led->duty = led->max;
            led->direction = -1;
        } else {
            led->duty += led->step;
        }
    } else {
        /* Decreasing */
        if (led->duty <= led->min + led->step) {
            led->duty = led->min;
            led->direction = 1;
        } else {
            led->duty -= led->step;
        }
    }

    /* Update PWM output */
    timer_set_output(ch, led->duty);
}

/**
 * Update all LEDs
 */
static void update_all_leds(void) {
    for (int i = 0; i < NUM_LEDS; i++) {
        update_led(i);
    }
    frame_count++;
}

/**
 * Display PWM bar graph
 */
static void display_bar(unsigned char duty) {
    int bars = (duty * 20) / 255;  /* Scale to 20 characters */

    printf("[");
    for (int i = 0; i < 20; i++) {
        if (i < bars) {
            printf("#");
        } else {
            printf(" ");
        }
    }
    printf("]");
}

/**
 * Display status of all LEDs
 */
static void display_status(void) {
    /* Clear screen and move to top */
    printf("\033[2J\033[H");

    printf("========================================\n");
    printf("      PWM LED Fading Demo\n");
    printf("========================================\n\n");

    printf("Frame: %u\n\n", frame_count);

    /* Display each LED */
    const char *names[] = {"Breathing", "Pulse    ", "Blink    ", "Ramp     "};

    for (int i = 0; i < NUM_LEDS; i++) {
        printf("LED %d (%s): ", i, names[i]);
        display_bar(leds[i].duty);
        printf(" %3d%% (%3d/255)\n",
               (leds[i].duty * 100) / 255,
               leds[i].duty);
    }

    printf("\n");

    /* Timer info */
    printf("Timer Configuration:\n");
    printf("  Prescale: %d\n", timer_get_prescale());
    printf("  Period:   255 (PWM mode)\n");
    printf("  Channels: 4 (all in PWM mode)\n");

    printf("\n========================================\n");
    printf("Press Ctrl+C to stop\n");
}

/**
 * Initialize peripherals
 */
static void init_peripherals(void) {
    printf("Initializing PWM LED fade demo...\n");

    /* Initialize GPIO */
    printf("  Configuring GPIO pins %d-%d as outputs...\n",
           LED_PIN_BASE, LED_PIN_BASE + NUM_LEDS - 1);

    for (int i = 0; i < NUM_LEDS; i++) {
        gpio_set_direction(LED_PIN_BASE + i, GPIO_DIR_OUTPUT);
        gpio_write_pin(LED_PIN_BASE + i, GPIO_LOW);
    }

    /* Initialize timers for PWM */
    printf("  Configuring %d timer channels for PWM...\n", NUM_LEDS);
    timer_init();
    timer_set_prescale(1);  /* Fast PWM update */

    for (int i = 0; i < NUM_LEDS; i++) {
        timer_set_compare(i, 255);       /* PWM period */
        timer_set_pwm_mode(i, 1);        /* Enable PWM mode */
        timer_set_auto_reload(i, 1);     /* Continuous operation */
        timer_set_output(i, 0);          /* Start at 0% */
        timer_enable_channel(i, 1);      /* Start timer */
    }

    /* Initialize animation patterns */
    init_led_patterns();

    printf("  Done!\n\n");
}

/**
 * Simple delay
 */
static void delay(unsigned int ms) {
    /* Approximate delay (depends on CPU speed) */
    for (unsigned int i = 0; i < ms; i++) {
        for (volatile int j = 0; j < 1000; j++);
    }
}

/**
 * Main loop
 */
int main(void) {
    printf("\n");
    printf("========================================\n");
    printf("      PWM LED Fading Demo\n");
    printf("========================================\n\n");

    /* Initialize */
    init_peripherals();

    printf("Starting animation...\n\n");
    delay(1000);

    /* Animation loop */
    while (1) {
        /* Update LED states */
        update_all_leds();

        /* Display status */
        display_status();

        /* Delay between frames (~50ms = 20fps) */
        delay(50);
    }

    return 0;
}
