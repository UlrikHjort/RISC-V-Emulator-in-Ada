/* **************************************************************************
 *           RISC-V Emulator - SPI Controller Driver - Interface
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

#ifndef SPI_H
#define SPI_H

/* SPI Base Address */
#define SPI_BASE        0x10020000

/* SPI Register Offsets */
#define SPI_CTRL        (*(volatile unsigned int *)(SPI_BASE + 0x00))
#define SPI_STATUS      (*(volatile unsigned int *)(SPI_BASE + 0x04))
#define SPI_DATA        (*(volatile unsigned int *)(SPI_BASE + 0x08))
#define SPI_PRESCALE    (*(volatile unsigned int *)(SPI_BASE + 0x0C))

/* Control register bits */
#define SPI_CTRL_ENABLE  0x01  /* SPI enable */
#define SPI_CTRL_CS      0x02  /* Chip select (0=active, 1=inactive) */

/* Status register bits */
#define SPI_STATUS_BUSY      0x01  /* Transfer in progress */
#define SPI_STATUS_TX_READY  0x02  /* TX ready */
#define SPI_STATUS_RX_VALID  0x04  /* RX data valid */

/* SPI Flash Commands */
#define SPI_CMD_READ          0x03  /* Read data */
#define SPI_CMD_PAGE_PROGRAM  0x02  /* Page program */
#define SPI_CMD_READ_ID       0x9F  /* Read JEDEC ID */
#define SPI_CMD_READ_STATUS   0x05  /* Read status register */
#define SPI_CMD_WRITE_ENABLE  0x06  /* Write enable */

/* Helper Functions */

/**
 * Initialize SPI controller
 */
void spi_init(void);

/**
 * Activate chip select (CS low)
 */
void spi_cs_active(void);

/**
 * Deactivate chip select (CS high)
 */
void spi_cs_inactive(void);

/**
 * Transfer a single byte (write and read)
 * @param data Byte to transmit
 * @return Received byte
 */
unsigned char spi_transfer(unsigned char data);

/**
 * Read JEDEC ID from flash
 * @param id Pointer to 3-byte buffer for ID
 */
void spi_flash_read_id(unsigned char *id);

/**
 * Read data from flash
 * @param address Flash address to read from
 * @param buffer Buffer to store read data
 * @param length Number of bytes to read
 */
void spi_flash_read(unsigned int address, unsigned char *buffer, unsigned int length);

/**
 * Write data to flash (must call spi_flash_write_enable first)
 * @param address Flash address to write to
 * @param buffer Data to write
 * @param length Number of bytes to write
 */
void spi_flash_write(unsigned int address, const unsigned char *buffer, unsigned int length);

/**
 * Enable flash writes (must be called before write/erase operations)
 */
void spi_flash_write_enable(void);

/**
 * Read flash status register
 * @return Status register value
 */
unsigned char spi_flash_read_status(void);

#endif /* SPI_H */
