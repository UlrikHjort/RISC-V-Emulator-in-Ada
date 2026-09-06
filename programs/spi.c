/* **************************************************************************
 *                 RISC-V Emulator - SPI Controller Driver
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
#include "spi.h"

void spi_init(void) {
    /* Enable SPI controller */
    SPI_CTRL = SPI_CTRL_ENABLE | SPI_CTRL_CS;  /* Enable with CS inactive */

    /* Set prescaler (optional, default is fine for simulation) */
    SPI_PRESCALE = 0;
}

void spi_cs_active(void) {
    SPI_CTRL = SPI_CTRL_ENABLE;  /* CS = 0 (active low) */
}

void spi_cs_inactive(void) {
    SPI_CTRL = SPI_CTRL_ENABLE | SPI_CTRL_CS;  /* CS = 1 (inactive) */
}

unsigned char spi_transfer(unsigned char data) {
    /* Write data to transmit */
    SPI_DATA = data;

    /* In simulation, transfer is instant. In real hardware, would wait for BUSY */
    /* while (SPI_STATUS & SPI_STATUS_BUSY); */

    /* Read received data */
    return (unsigned char)(SPI_DATA & 0xFF);
}

void spi_flash_read_id(unsigned char *id) {
    spi_cs_active();

    /* Send READ_ID command */
    spi_transfer(SPI_CMD_READ_ID);

    /* Read 3-byte ID */
    id[0] = spi_transfer(0xFF);  /* Manufacturer ID */
    id[1] = spi_transfer(0xFF);  /* Device ID byte 1 */
    id[2] = spi_transfer(0xFF);  /* Device ID byte 2 */

    spi_cs_inactive();
}

void spi_flash_read(unsigned int address, unsigned char *buffer, unsigned int length) {
    spi_cs_active();

    /* Send READ command */
    spi_transfer(SPI_CMD_READ);

    /* Send 24-bit address (MSB first) */
    spi_transfer((address >> 16) & 0xFF);
    spi_transfer((address >> 8) & 0xFF);
    spi_transfer(address & 0xFF);

    /* Read data bytes */
    for (unsigned int i = 0; i < length; i++) {
        buffer[i] = spi_transfer(0xFF);
    }

    spi_cs_inactive();
}

void spi_flash_write(unsigned int address, const unsigned char *buffer, unsigned int length) {
    spi_cs_active();

    /* Send PAGE_PROGRAM command */
    spi_transfer(SPI_CMD_PAGE_PROGRAM);

    /* Send 24-bit address (MSB first) */
    spi_transfer((address >> 16) & 0xFF);
    spi_transfer((address >> 8) & 0xFF);
    spi_transfer(address & 0xFF);

    /* Write data bytes */
    for (unsigned int i = 0; i < length; i++) {
        spi_transfer(buffer[i]);
    }

    spi_cs_inactive();
}

void spi_flash_write_enable(void) {
    spi_cs_active();
    spi_transfer(SPI_CMD_WRITE_ENABLE);
    spi_cs_inactive();
}

unsigned char spi_flash_read_status(void) {
    unsigned char status;

    spi_cs_active();
    spi_transfer(SPI_CMD_READ_STATUS);
    status = spi_transfer(0xFF);
    spi_cs_inactive();

    return status;
}
