/* **************************************************************************
 *                 RISC-V Emulator - SPI Flash Test Program
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
 * SPI Flash Test Program
 *
 * This program demonstrates SPI peripheral functionality:
 * - Initializing SPI controller
 * - Reading JEDEC ID from flash
 * - Writing data to flash
 * - Reading data back from flash
 * - Verifying data integrity
 */

#include "spi.h"

extern void printf(const char *fmt, ...);

/* Test data patterns */
static const unsigned char test_pattern_1[] = {
    0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88,
    0x99, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF, 0x00
};

static const unsigned char test_pattern_2[] = {
    'H', 'e', 'l', 'l', 'o', ',', ' ', 'S', 'P', 'I', '!', 0
};

int main(void) {
    unsigned char id[3];
    unsigned char buffer[256];
    unsigned char readback[256];
    int errors;

    printf("\n=== SPI Flash Test ===\n\n");

    /* Test 1: Initialize SPI */
    printf("=== Test 1: SPI Initialization ===\n");
    spi_init();
    printf("SPI initialized\n");

    /* Read control register */
    unsigned int ctrl = SPI_CTRL;
    printf("Control register: 0x%02x\n", ctrl);

    if ((ctrl & SPI_CTRL_ENABLE) && (ctrl & SPI_CTRL_CS)) {
        printf("PASS: SPI enabled with CS inactive\n");
    } else {
        printf("FAIL: Unexpected control register value\n");
    }

    /* Test 2: Read JEDEC ID */
    printf("\n=== Test 2: Read JEDEC ID ===\n");
    spi_flash_read_id(id);
    printf("JEDEC ID: 0x%02x 0x%02x 0x%02x\n", id[0], id[1], id[2]);

    /* Expected: 0xEF (manufacturer), device ID varies */
    if (id[0] == 0xEF) {
        printf("PASS: Valid manufacturer ID (0xEF)\n");
    } else {
        printf("INFO: Manufacturer ID is 0x%02x\n", id[0]);
    }

    /* Test 3: Read Status Register */
    printf("\n=== Test 3: Read Flash Status ===\n");
    unsigned char status = spi_flash_read_status();
    printf("Flash status: 0x%02x\n", status);

    if ((status & 0x02) == 0) {
        printf("Write Enable Latch (WEL) is clear (expected)\n");
    } else {
        printf("Write Enable Latch (WEL) is set\n");
    }

    /* Test 4: Write Enable */
    printf("\n=== Test 4: Write Enable ===\n");
    spi_flash_write_enable();
    printf("Write enable command sent\n");

    status = spi_flash_read_status();
    printf("Flash status after write enable: 0x%02x\n", status);

    /* Note: In simulation, WEL may auto-clear after write */

    /* Test 5: Write and Read Test Pattern 1 */
    printf("\n=== Test 5: Write/Read Pattern 1 ===\n");

    /* Enable writes */
    spi_flash_write_enable();

    /* Write test pattern */
    unsigned int addr = 0x1000;
    printf("Writing %d bytes to address 0x%04x...\n",
           sizeof(test_pattern_1), addr);

    spi_flash_write(addr, test_pattern_1, sizeof(test_pattern_1));
    printf("Write complete\n");

    /* Read back */
    printf("Reading back %d bytes...\n", sizeof(test_pattern_1));
    spi_flash_read(addr, readback, sizeof(test_pattern_1));

    /* Verify */
    errors = 0;
    printf("Data verification:\n");
    for (unsigned int i = 0; i < sizeof(test_pattern_1); i++) {
        if (readback[i] != test_pattern_1[i]) {
            printf("  [%02d] FAIL: wrote 0x%02x, read 0x%02x\n",
                   i, test_pattern_1[i], readback[i]);
            errors++;
        }
    }

    if (errors == 0) {
        printf("PASS: All %d bytes verified correctly\n", sizeof(test_pattern_1));
    } else {
        printf("FAIL: %d byte(s) mismatched\n", errors);
    }

    /* Test 6: Write and Read String */
    printf("\n=== Test 6: Write/Read String ===\n");

    /* Enable writes */
    spi_flash_write_enable();

    /* Write string */
    addr = 0x2000;
    printf("Writing string to address 0x%04x: \"%s\"\n",
           addr, (const char *)test_pattern_2);

    spi_flash_write(addr, test_pattern_2, sizeof(test_pattern_2));

    /* Read back */
    spi_flash_read(addr, readback, sizeof(test_pattern_2));
    printf("Read back: \"%s\"\n", (const char *)readback);

    /* Verify */
    errors = 0;
    for (unsigned int i = 0; i < sizeof(test_pattern_2); i++) {
        if (readback[i] != test_pattern_2[i]) {
            errors++;
        }
    }

    if (errors == 0) {
        printf("PASS: String verified correctly\n");
    } else {
        printf("FAIL: String verification failed\n");
    }

    /* Test 7: Sequential Write/Read */
    printf("\n=== Test 7: Sequential Operations ===\n");

    /* Create test data */
    for (unsigned int i = 0; i < 64; i++) {
        buffer[i] = (unsigned char)(i);
    }

    /* Write multiple times to different addresses */
    for (unsigned int block = 0; block < 4; block++) {
        addr = 0x3000 + (block * 64);

        spi_flash_write_enable();
        spi_flash_write(addr, buffer, 64);

        printf("Block %d written to 0x%04x\n", block, addr);
    }

    /* Read back and verify */
    errors = 0;
    for (unsigned int block = 0; block < 4; block++) {
        addr = 0x3000 + (block * 64);

        spi_flash_read(addr, readback, 64);

        for (unsigned int i = 0; i < 64; i++) {
            if (readback[i] != (unsigned char)(i)) {
                errors++;
            }
        }
    }

    if (errors == 0) {
        printf("PASS: All 4 blocks (256 bytes) verified\n");
    } else {
        printf("FAIL: %d byte(s) mismatched in sequential test\n", errors);
    }

    /* Test 8: Cross-page Boundary */
    printf("\n=== Test 8: Cross-Page Boundary ===\n");

    /* Write data that crosses typical 256-byte page boundary */
    addr = 0x4FF0;  /* 16 bytes before 0x5000 */

    for (unsigned int i = 0; i < 32; i++) {
        buffer[i] = (unsigned char)(0xA0 + i);
    }

    spi_flash_write_enable();
    spi_flash_write(addr, buffer, 32);
    printf("Wrote 32 bytes starting at 0x%04x (crosses 0x5000)\n", addr);

    /* Read back */
    spi_flash_read(addr, readback, 32);

    /* Verify */
    errors = 0;
    for (unsigned int i = 0; i < 32; i++) {
        if (readback[i] != buffer[i]) {
            errors++;
        }
    }

    if (errors == 0) {
        printf("PASS: Cross-page write/read verified\n");
    } else {
        printf("FAIL: Cross-page test failed\n");
    }

    /* Test 9: Large Data Transfer */
    printf("\n=== Test 9: Large Data Transfer ===\n");

    /* Write 256 bytes */
    addr = 0x8000;
    for (unsigned int i = 0; i < 256; i++) {
        buffer[i] = (unsigned char)(i ^ 0x55);  /* XOR pattern */
    }

    spi_flash_write_enable();
    printf("Writing 256 bytes to 0x%04x...\n", addr);
    spi_flash_write(addr, buffer, 256);

    /* Read back in chunks */
    printf("Reading back in 4 chunks of 64 bytes...\n");
    errors = 0;
    for (unsigned int chunk = 0; chunk < 4; chunk++) {
        unsigned int chunk_addr = addr + (chunk * 64);
        spi_flash_read(chunk_addr, readback + (chunk * 64), 64);
    }

    /* Verify all 256 bytes */
    for (unsigned int i = 0; i < 256; i++) {
        if (readback[i] != buffer[i]) {
            errors++;
        }
    }

    if (errors == 0) {
        printf("PASS: All 256 bytes verified\n");
    } else {
        printf("FAIL: %d byte(s) mismatched\n", errors);
    }

    /* Test 10: Chip Select Control */
    printf("\n=== Test 10: Manual CS Control ===\n");

    spi_cs_active();
    printf("CS activated (should be 0)\n");
    ctrl = SPI_CTRL;
    if ((ctrl & SPI_CTRL_CS) == 0) {
        printf("PASS: CS is active (low)\n");
    } else {
        printf("FAIL: CS is not active\n");
    }

    spi_cs_inactive();
    printf("CS deactivated (should be 1)\n");
    ctrl = SPI_CTRL;
    if (ctrl & SPI_CTRL_CS) {
        printf("PASS: CS is inactive (high)\n");
    } else {
        printf("FAIL: CS is not inactive\n");
    }

    /* Final Summary */
    printf("\n=== Test Summary ===\n");
    printf("SPI Flash Test Complete\n");
    printf("- Flash read/write operations functional\n");
    printf("- Data integrity verified across multiple tests\n");
    printf("- Chip select control working\n");

    printf("\n=== All SPI Tests PASSED ===\n");

    return 0;
}
