/* **************************************************************************
 *                RISC-V Emulator - GPIO Driver - Interface
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

#ifndef GPIO_H
#define GPIO_H

/* GPIO Base Address */
#define GPIO_BASE       0x10010000

/* GPIO Register Offsets */
#define GPIO_INPUT      (*(volatile unsigned int *)(GPIO_BASE + 0x00))
#define GPIO_OUTPUT     (*(volatile unsigned int *)(GPIO_BASE + 0x04))
#define GPIO_DIRECTION  (*(volatile unsigned int *)(GPIO_BASE + 0x08))
#define GPIO_INT_EN     (*(volatile unsigned int *)(GPIO_BASE + 0x0C))
#define GPIO_INT_FLAG   (*(volatile unsigned int *)(GPIO_BASE + 0x10))
#define GPIO_INT_TYPE   (*(volatile unsigned int *)(GPIO_BASE + 0x14))
#define GPIO_PULL_EN    (*(volatile unsigned int *)(GPIO_BASE + 0x18))
#define GPIO_PULL_DIR   (*(volatile unsigned int *)(GPIO_BASE + 0x1C))

/* Pin Direction */
#define GPIO_DIR_INPUT  0
#define GPIO_DIR_OUTPUT 1

/* Pin Values */
#define GPIO_LOW   0
#define GPIO_HIGH  1

/* Interrupt Types */
#define GPIO_INT_LEVEL  0
#define GPIO_INT_EDGE   1

/* Pull Direction */
#define GPIO_PULL_DOWN  0
#define GPIO_PULL_UP    1

/* Helper Functions */

/**
 * Configure a GPIO pin direction
 * @param pin Pin number (0-31)
 * @param dir Direction: GPIO_DIR_INPUT or GPIO_DIR_OUTPUT
 */
void gpio_set_direction(unsigned int pin, unsigned int dir);

/**
 * Set an output pin high or low
 * @param pin Pin number (0-31)
 * @param value GPIO_HIGH or GPIO_LOW
 */
void gpio_write_pin(unsigned int pin, unsigned int value);

/**
 * Read an input pin value
 * @param pin Pin number (0-31)
 * @return GPIO_HIGH or GPIO_LOW
 */
unsigned int gpio_read_pin(unsigned int pin);

/**
 * Toggle an output pin
 * @param pin Pin number (0-31)
 */
void gpio_toggle_pin(unsigned int pin);

/**
 * Configure pull-up/pull-down resistor
 * @param pin Pin number (0-31)
 * @param enable 1 to enable, 0 to disable
 * @param direction GPIO_PULL_UP or GPIO_PULL_DOWN
 */
void gpio_set_pull(unsigned int pin, unsigned int enable, unsigned int direction);

/**
 * Enable interrupt for a pin
 * @param pin Pin number (0-31)
 * @param type GPIO_INT_LEVEL or GPIO_INT_EDGE
 */
void gpio_enable_interrupt(unsigned int pin, unsigned int type);

/**
 * Disable interrupt for a pin
 * @param pin Pin number (0-31)
 */
void gpio_disable_interrupt(unsigned int pin);

/**
 * Clear interrupt flag for a pin
 * @param pin Pin number (0-31)
 */
void gpio_clear_interrupt(unsigned int pin);

/**
 * Check if interrupt is pending for a pin
 * @param pin Pin number (0-31)
 * @return 1 if interrupt pending, 0 otherwise
 */
unsigned int gpio_interrupt_pending(unsigned int pin);

#endif /* GPIO_H */
