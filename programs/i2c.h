/* **************************************************************************
 *                RISC-V Emulator - I2C Controller C Library
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
 * I2C Controller C Library
 *
 * Provides convenient access to the I2C controller peripheral.
 * Base address: 0x10030000
 *
 * Typical usage:
 *   i2c_init();
 *   i2c_start(0x48);                    // Start + address temperature sensor
 *   i2c_write(0x00);                    // Select register 0
 *   i2c_restart(0x48 | I2C_READ);      // Restart with read
 *   temp_msb = i2c_read_ack();
 *   temp_lsb = i2c_read_nack();
 *   i2c_stop();
 */

#ifndef I2C_H
#define I2C_H

/* I2C Controller Registers */
#define I2C_BASE          0x10030000

#define I2C_CTRL          (*(volatile unsigned char *)(I2C_BASE + 0x00))
#define I2C_STATUS        (*(volatile unsigned char *)(I2C_BASE + 0x04))
#define I2C_DATA          (*(volatile unsigned char *)(I2C_BASE + 0x08))
#define I2C_PRESCALE      (*(volatile unsigned char *)(I2C_BASE + 0x0C))
#define I2C_SLAVE_ADDR    (*(volatile unsigned char *)(I2C_BASE + 0x10))

/* Control Register Bits */
#define I2C_CTRL_ENABLE      0x01
#define I2C_CTRL_START       0x02
#define I2C_CTRL_STOP        0x04
#define I2C_CTRL_READ        0x08
#define I2C_CTRL_WRITE       0x10
#define I2C_CTRL_ACK         0x20
#define I2C_CTRL_FAST_MODE   0x40

/* Status Register Bits */
#define I2C_STATUS_BUSY      0x01
#define I2C_STATUS_ACK_RECV  0x02
#define I2C_STATUS_NACK_RECV 0x04
#define I2C_STATUS_ARB_LOST  0x08
#define I2C_STATUS_READY     0x10

/* Address flags */
#define I2C_READ  0x01  /* OR with 7-bit address for read operation */
#define I2C_WRITE 0x00  /* 7-bit address for write operation */

/* Device addresses (7-bit) */
#define I2C_ADDR_TEMP        0x48  /* Temperature sensor (TMP102) */
#define I2C_ADDR_ACCEL       0x1D  /* Accelerometer (ADXL345) */
#define I2C_ADDR_EEPROM      0x50  /* 256-byte EEPROM (24C02) */

/**
 * Initialize I2C controller
 * Sets prescaler for standard mode (100 kHz)
 */
void i2c_init(void);

/**
 * Generate START condition and send address
 * Returns 1 if ACK received, 0 if NACK
 */
int i2c_start(unsigned char address);

/**
 * Generate repeated START (for direction change)
 * Returns 1 if ACK received, 0 if NACK
 */
int i2c_restart(unsigned char address);

/**
 * Generate STOP condition
 */
void i2c_stop(void);

/**
 * Write a byte to I2C bus
 * Returns 1 if ACK received, 0 if NACK
 */
int i2c_write(unsigned char data);

/**
 * Read a byte and send ACK (for multi-byte reads)
 */
unsigned char i2c_read_ack(void);

/**
 * Read a byte and send NACK (for last byte)
 */
unsigned char i2c_read_nack(void);

/**
 * Check if bus is busy
 */
int i2c_busy(void);

/**
 * Wait for operation to complete
 */
void i2c_wait(void);

/**
 * Enable fast mode (400 kHz)
 */
void i2c_set_fast_mode(int enable);

#endif /* I2C_H */
