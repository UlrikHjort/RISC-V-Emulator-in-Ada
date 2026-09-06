/* **************************************************************************
 *              RISC-V Emulator - Hardware Timer/PWM C Library
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

/**
 * Hardware Timer/PWM C Library
 *
 * Provides convenient access to the hardware timer peripheral.
 * Base address: 0x10040000
 * 4 independent channels (0-3)
 *
 * Typical usage for timing:
 *   timer_init();
 *   timer_set_prescale(100);           // Slow down clock
 *   timer_set_compare(0, 10000);       // Channel 0, count to 10000
 *   timer_enable_channel(0, 1);        // Start timer
 *   while (!timer_get_interrupt(0));   // Wait for match
 *   timer_clear_interrupt(0);
 *
 * Typical usage for PWM:
 *   timer_init();
 *   timer_set_pwm_mode(1, 1);          // Channel 1, PWM mode
 *   timer_set_compare(1, 255);         // Period
 *   timer_set_output(1, 128);          // 50% duty cycle
 *   timer_enable_channel(1, 1);
 */

#ifndef TIMER_H
#define TIMER_H

/* Timer Controller Registers */
#define TIMER_BASE        0x10040000

/* Global registers */
#define TIMER_PRESCALE    (*(volatile unsigned char *)(TIMER_BASE + 0x00))
#define TIMER_INT_STATUS  (*(volatile unsigned char *)(TIMER_BASE + 0x04))
#define TIMER_INT_ENABLE  (*(volatile unsigned char *)(TIMER_BASE + 0x08))

/* Helper macros for channel registers */
#define TIMER_CH_BASE(ch)     (TIMER_BASE + 0x10 + ((ch) * 0x10))
#define TIMER_CH_COUNTER(ch)  (*(volatile unsigned int *)(TIMER_CH_BASE(ch) + 0x00))
#define TIMER_CH_COMPARE(ch)  (*(volatile unsigned int *)(TIMER_CH_BASE(ch) + 0x04))
#define TIMER_CH_CTRL(ch)     (*(volatile unsigned char *)(TIMER_CH_BASE(ch) + 0x08))
#define TIMER_CH_OUTPUT(ch)   (*(volatile unsigned char *)(TIMER_CH_BASE(ch) + 0x0C))

/* Channel control bits */
#define TIMER_CTRL_ENABLE       0x01
#define TIMER_CTRL_PWM_MODE     0x02
#define TIMER_CTRL_AUTO_RELOAD  0x04
#define TIMER_CTRL_INT_ENABLE   0x08
#define TIMER_CTRL_OUTPUT_HIGH  0x10

/* Interrupt bits (one per channel) */
#define TIMER_INT_CH0  0x01
#define TIMER_INT_CH1  0x02
#define TIMER_INT_CH2  0x04
#define TIMER_INT_CH3  0x08

/**
 * Initialize timer controller with default settings
 */
void timer_init(void);

/**
 * Set global prescaler (divides clock for all channels)
 * prescale: 1-255 (1 = no division)
 */
void timer_set_prescale(unsigned char prescale);

/**
 * Get current prescaler value
 */
unsigned char timer_get_prescale(void);

/**
 * Set counter value for a channel
 */
void timer_set_counter(int channel, unsigned int value);

/**
 * Get current counter value for a channel
 */
unsigned int timer_get_counter(int channel);

/**
 * Set compare/match value for a channel
 */
void timer_set_compare(int channel, unsigned int value);

/**
 * Get compare value for a channel
 */
unsigned int timer_get_compare(int channel);

/**
 * Enable or disable a timer channel
 */
void timer_enable_channel(int channel, int enable);

/**
 * Set PWM mode for a channel
 */
void timer_set_pwm_mode(int channel, int enable);

/**
 * Set auto-reload mode (counter resets to 0 on match)
 */
void timer_set_auto_reload(int channel, int enable);

/**
 * Enable interrupt on compare match
 */
void timer_enable_interrupt(int channel, int enable);

/**
 * Set PWM output duty cycle (0-255)
 */
void timer_set_output(int channel, unsigned char duty);

/**
 * Get PWM output value
 */
unsigned char timer_get_output(int channel);

/**
 * Check if interrupt is pending for a channel
 */
int timer_get_interrupt(int channel);

/**
 * Clear interrupt flag for a channel
 */
void timer_clear_interrupt(int channel);

/**
 * Simple delay using timer channel 0
 * ticks: number of timer ticks to wait
 */
void timer_delay(unsigned int ticks);

#endif /* TIMER_H */
