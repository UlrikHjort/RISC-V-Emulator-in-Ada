/* **************************************************************************
 *      RISC-V Emulator - Hardware Timer/PWM C Library Implementation
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
 * Hardware Timer/PWM C Library Implementation
 */

#include "timer.h"

/**
 * Initialize timer controller
 */
void timer_init(void) {
    /* Set default prescaler */
    TIMER_PRESCALE = 1;

    /* Disable all interrupts initially */
    TIMER_INT_ENABLE = 0;

    /* Clear all interrupt flags */
    TIMER_INT_STATUS = 0x0F;

    /* Disable all channels */
    for (int i = 0; i < 4; i++) {
        TIMER_CH_CTRL(i) = 0;
        TIMER_CH_COUNTER(i) = 0;
        TIMER_CH_COMPARE(i) = 0;
        TIMER_CH_OUTPUT(i) = 0;
    }
}

/**
 * Set global prescaler
 */
void timer_set_prescale(unsigned char prescale) {
    if (prescale == 0) {
        prescale = 1;  /* Minimum prescale */
    }
    TIMER_PRESCALE = prescale;
}

/**
 * Get current prescaler value
 */
unsigned char timer_get_prescale(void) {
    return TIMER_PRESCALE;
}

/**
 * Set counter value for a channel
 */
void timer_set_counter(int channel, unsigned int value) {
    if (channel >= 0 && channel < 4) {
        TIMER_CH_COUNTER(channel) = value;
    }
}

/**
 * Get current counter value for a channel
 */
unsigned int timer_get_counter(int channel) {
    if (channel >= 0 && channel < 4) {
        return TIMER_CH_COUNTER(channel);
    }
    return 0;
}

/**
 * Set compare/match value for a channel
 */
void timer_set_compare(int channel, unsigned int value) {
    if (channel >= 0 && channel < 4) {
        TIMER_CH_COMPARE(channel) = value;
    }
}

/**
 * Get compare value for a channel
 */
unsigned int timer_get_compare(int channel) {
    if (channel >= 0 && channel < 4) {
        return TIMER_CH_COMPARE(channel);
    }
    return 0;
}

/**
 * Enable or disable a timer channel
 */
void timer_enable_channel(int channel, int enable) {
    if (channel >= 0 && channel < 4) {
        unsigned char ctrl = TIMER_CH_CTRL(channel);
        if (enable) {
            ctrl |= TIMER_CTRL_ENABLE;
        } else {
            ctrl &= ~TIMER_CTRL_ENABLE;
        }
        TIMER_CH_CTRL(channel) = ctrl;
    }
}

/**
 * Set PWM mode for a channel
 */
void timer_set_pwm_mode(int channel, int enable) {
    if (channel >= 0 && channel < 4) {
        unsigned char ctrl = TIMER_CH_CTRL(channel);
        if (enable) {
            ctrl |= TIMER_CTRL_PWM_MODE;
        } else {
            ctrl &= ~TIMER_CTRL_PWM_MODE;
        }
        TIMER_CH_CTRL(channel) = ctrl;
    }
}

/**
 * Set auto-reload mode
 */
void timer_set_auto_reload(int channel, int enable) {
    if (channel >= 0 && channel < 4) {
        unsigned char ctrl = TIMER_CH_CTRL(channel);
        if (enable) {
            ctrl |= TIMER_CTRL_AUTO_RELOAD;
        } else {
            ctrl &= ~TIMER_CTRL_AUTO_RELOAD;
        }
        TIMER_CH_CTRL(channel) = ctrl;
    }
}

/**
 * Enable interrupt on compare match
 */
void timer_enable_interrupt(int channel, int enable) {
    if (channel >= 0 && channel < 4) {
        unsigned char ctrl = TIMER_CH_CTRL(channel);
        unsigned char int_mask = 1 << channel;

        if (enable) {
            ctrl |= TIMER_CTRL_INT_ENABLE;
            TIMER_INT_ENABLE |= int_mask;
        } else {
            ctrl &= ~TIMER_CTRL_INT_ENABLE;
            TIMER_INT_ENABLE &= ~int_mask;
        }
        TIMER_CH_CTRL(channel) = ctrl;
    }
}

/**
 * Set PWM output duty cycle
 */
void timer_set_output(int channel, unsigned char duty) {
    if (channel >= 0 && channel < 4) {
        TIMER_CH_OUTPUT(channel) = duty;
    }
}

/**
 * Get PWM output value
 */
unsigned char timer_get_output(int channel) {
    if (channel >= 0 && channel < 4) {
        return TIMER_CH_OUTPUT(channel);
    }
    return 0;
}

/**
 * Check if interrupt is pending for a channel
 */
int timer_get_interrupt(int channel) {
    if (channel >= 0 && channel < 4) {
        unsigned char mask = 1 << channel;
        return (TIMER_INT_STATUS & mask) != 0;
    }
    return 0;
}

/**
 * Clear interrupt flag for a channel
 */
void timer_clear_interrupt(int channel) {
    if (channel >= 0 && channel < 4) {
        unsigned char mask = 1 << channel;
        TIMER_INT_STATUS = mask;  /* Write 1 to clear */
    }
}

/**
 * Simple delay using timer channel 0
 */
void timer_delay(unsigned int ticks) {
    /* Save current timer 0 state */
    unsigned char old_ctrl = TIMER_CH_CTRL(0);

    /* Configure timer 0 for one-shot mode */
    TIMER_CH_COUNTER(0) = 0;
    TIMER_CH_COMPARE(0) = ticks;
    TIMER_CH_CTRL(0) = TIMER_CTRL_ENABLE | TIMER_CTRL_INT_ENABLE;
    TIMER_INT_ENABLE |= TIMER_INT_CH0;

    /* Wait for timer to reach compare value */
    while (!timer_get_interrupt(0)) {
        /* Busy wait */
    }

    /* Clear interrupt and restore state */
    timer_clear_interrupt(0);
    TIMER_CH_CTRL(0) = old_ctrl;
}
