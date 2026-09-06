/* **************************************************************************
 *        RISC-V Emulator - I2C Controller C Library Implementation
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
 * I2C Controller C Library Implementation
 */

#include "i2c.h"

/* Simple delay for I2C operations */
static void i2c_delay(void) {
    for (volatile int i = 0; i < 100; i++);
}

/**
 * Initialize I2C controller
 */
void i2c_init(void) {
    /* Set prescaler for 100 kHz (standard mode) */
    I2C_PRESCALE = 100;

    /* Enable I2C controller */
    I2C_CTRL = I2C_CTRL_ENABLE;

    i2c_delay();
}

/**
 * Wait for operation to complete
 */
void i2c_wait(void) {
    int timeout = 1000;
    while (!(I2C_STATUS & I2C_STATUS_READY) && timeout > 0) {
        i2c_delay();
        timeout--;
    }
}

/**
 * Generate START condition and send address
 */
int i2c_start(unsigned char address) {
    /* Set slave address */
    I2C_SLAVE_ADDR = address >> 1;  /* Convert 8-bit to 7-bit address */

    /* Generate START condition */
    I2C_CTRL = I2C_CTRL_ENABLE | I2C_CTRL_START;

    i2c_wait();

    /* Check if ACK received */
    return (I2C_STATUS & I2C_STATUS_ACK_RECV) ? 1 : 0;
}

/**
 * Generate repeated START
 */
int i2c_restart(unsigned char address) {
    return i2c_start(address);
}

/**
 * Generate STOP condition
 */
void i2c_stop(void) {
    I2C_CTRL = I2C_CTRL_ENABLE | I2C_CTRL_STOP;
    i2c_wait();
}

/**
 * Write a byte to I2C bus
 */
int i2c_write(unsigned char data) {
    /* Load data register */
    I2C_DATA = data;

    /* Initiate write operation */
    I2C_CTRL = I2C_CTRL_ENABLE | I2C_CTRL_WRITE;

    i2c_wait();

    /* Check if ACK received */
    return (I2C_STATUS & I2C_STATUS_ACK_RECV) ? 1 : 0;
}

/**
 * Read a byte and send ACK
 */
unsigned char i2c_read_ack(void) {
    /* Initiate read with ACK */
    I2C_CTRL = I2C_CTRL_ENABLE | I2C_CTRL_READ | I2C_CTRL_ACK;

    i2c_wait();

    return I2C_DATA;
}

/**
 * Read a byte and send NACK
 */
unsigned char i2c_read_nack(void) {
    /* Initiate read without ACK */
    I2C_CTRL = I2C_CTRL_ENABLE | I2C_CTRL_READ;

    i2c_wait();

    return I2C_DATA;
}

/**
 * Check if bus is busy
 */
int i2c_busy(void) {
    return (I2C_STATUS & I2C_STATUS_BUSY) ? 1 : 0;
}

/**
 * Enable/disable fast mode
 */
void i2c_set_fast_mode(int enable) {
    if (enable) {
        I2C_PRESCALE = 25;  /* 400 kHz */
        I2C_CTRL |= I2C_CTRL_FAST_MODE;
    } else {
        I2C_PRESCALE = 100;  /* 100 kHz */
        I2C_CTRL &= ~I2C_CTRL_FAST_MODE;
    }
}
