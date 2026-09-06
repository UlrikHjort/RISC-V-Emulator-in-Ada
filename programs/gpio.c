/* **************************************************************************
 *                      RISC-V Emulator - GPIO Driver
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
#include "gpio.h"

/* Helper macro to create bit mask for a pin */
#define PIN_MASK(pin) (1u << (pin))

void gpio_set_direction(unsigned int pin, unsigned int dir) {
    if (pin >= 32) return;

    unsigned int mask = PIN_MASK(pin);
    if (dir == GPIO_DIR_OUTPUT) {
        GPIO_DIRECTION |= mask;
    } else {
        GPIO_DIRECTION &= ~mask;
    }
}

void gpio_write_pin(unsigned int pin, unsigned int value) {
    if (pin >= 32) return;

    unsigned int mask = PIN_MASK(pin);
    if (value) {
        GPIO_OUTPUT |= mask;
    } else {
        GPIO_OUTPUT &= ~mask;
    }
}

unsigned int gpio_read_pin(unsigned int pin) {
    if (pin >= 32) return 0;

    unsigned int mask = PIN_MASK(pin);
    return (GPIO_INPUT & mask) ? GPIO_HIGH : GPIO_LOW;
}

void gpio_toggle_pin(unsigned int pin) {
    if (pin >= 32) return;

    unsigned int mask = PIN_MASK(pin);
    GPIO_OUTPUT ^= mask;
}

void gpio_set_pull(unsigned int pin, unsigned int enable, unsigned int direction) {
    if (pin >= 32) return;

    unsigned int mask = PIN_MASK(pin);

    /* Set pull enable */
    if (enable) {
        GPIO_PULL_EN |= mask;
    } else {
        GPIO_PULL_EN &= ~mask;
    }

    /* Set pull direction */
    if (direction == GPIO_PULL_UP) {
        GPIO_PULL_DIR |= mask;
    } else {
        GPIO_PULL_DIR &= ~mask;
    }
}

void gpio_enable_interrupt(unsigned int pin, unsigned int type) {
    if (pin >= 32) return;

    unsigned int mask = PIN_MASK(pin);

    /* Set interrupt type */
    if (type == GPIO_INT_EDGE) {
        GPIO_INT_TYPE |= mask;
    } else {
        GPIO_INT_TYPE &= ~mask;
    }

    /* Enable interrupt */
    GPIO_INT_EN |= mask;
}

void gpio_disable_interrupt(unsigned int pin) {
    if (pin >= 32) return;

    unsigned int mask = PIN_MASK(pin);
    GPIO_INT_EN &= ~mask;
}

void gpio_clear_interrupt(unsigned int pin) {
    if (pin >= 32) return;

    unsigned int mask = PIN_MASK(pin);
    /* Write 1 to clear */
    GPIO_INT_FLAG = mask;
}

unsigned int gpio_interrupt_pending(unsigned int pin) {
    if (pin >= 32) return 0;

    unsigned int mask = PIN_MASK(pin);
    return (GPIO_INT_FLAG & mask) ? 1 : 0;
}
