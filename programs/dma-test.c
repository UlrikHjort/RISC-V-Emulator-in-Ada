/* **************************************************************************
 *              RISC-V Emulator - DMA Controller Test Program
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

// DMA Controller Test Program
// Demonstrates high-performance bulk data transfers
// By Ulrik Hørlyk Hjort 2026

#include <stdint.h>

// DMA Controller registers (base at 0x10060000)
#define DMA_BASE    0x10060000

// Channel 0 registers
#define CH0_SRC     (*(volatile uint32_t *)(DMA_BASE + 0x00))
#define CH0_DST     (*(volatile uint32_t *)(DMA_BASE + 0x04))
#define CH0_COUNT   (*(volatile uint32_t *)(DMA_BASE + 0x08))
#define CH0_CTRL    (*(volatile uint32_t *)(DMA_BASE + 0x0C))
#define CH0_STATUS  (*(volatile uint32_t *)(DMA_BASE + 0x10))

// Channel 1 registers
#define CH1_SRC     (*(volatile uint32_t *)(DMA_BASE + 0x20))
#define CH1_DST     (*(volatile uint32_t *)(DMA_BASE + 0x24))
#define CH1_COUNT   (*(volatile uint32_t *)(DMA_BASE + 0x28))
#define CH1_CTRL    (*(volatile uint32_t *)(DMA_BASE + 0x2C))
#define CH1_STATUS  (*(volatile uint32_t *)(DMA_BASE + 0x30))

// Control register bits
#define CTRL_ENABLE    (1 << 0)  // Enable channel
#define CTRL_START     (1 << 1)  // Start transfer
#define CTRL_INT_EN    (1 << 2)  // Interrupt enable
#define CTRL_SRC_INC   (1 << 3)  // Increment source address
#define CTRL_DST_INC   (1 << 4)  // Increment destination address

// Status register bits
#define STATUS_BUSY    (1 << 0)  // Transfer in progress
#define STATUS_DONE    (1 << 1)  // Transfer complete
#define STATUS_ERROR   (1 << 2)  // Transfer error

// UART for output
#define UART_BASE   0x10000000
#define UART_THR    (*(volatile uint32_t *)(UART_BASE + 0x00))
#define UART_LSR    (*(volatile uint32_t *)(UART_BASE + 0x14))
#define LSR_THRE    (1 << 5)

// External functions provided by C library
extern int printf(const char *fmt, ...);

// Test data buffers
static uint8_t source_buffer[256];
static uint8_t dest_buffer[256];
static uint8_t verify_buffer[256];

// Helper function to wait for DMA completion
static void wait_for_dma_ch0(void) {
    uint32_t timeout = 1000000;
    while ((CH0_STATUS & STATUS_BUSY) && timeout > 0) {
        timeout--;
    }
    if (timeout == 0) {
        printf("  WARNING: DMA timeout!\n");
    }
}

static void wait_for_dma_ch1(void) {
    uint32_t timeout = 1000000;
    while ((CH1_STATUS & STATUS_BUSY) && timeout > 0) {
        timeout--;
    }
    if (timeout == 0) {
        printf("  WARNING: DMA timeout!\n");
    }
}

int main(void) {
    uint32_t i;
    uint32_t errors;

    printf("\n");
    printf("=============================================\n");
    printf("  DMA Controller Test Program\n");
    printf("=============================================\n");
    printf("\n");

    //=========================================================================
    // Test 1: Simple memory-to-memory transfer (64 bytes)
    //=========================================================================
    printf("Test 1: Simple Memory-to-Memory Transfer\n");
    printf("-----------------------------------------\n");

    // Initialize source buffer with pattern
    for (i = 0; i < 64; i++) {
        source_buffer[i] = (uint8_t)(i + 0xA0);
        dest_buffer[i] = 0x00;  // Clear destination
    }

    printf("  Source buffer filled with pattern 0xA0-0xDF\n");
    printf("  Destination buffer cleared\n");

    // Configure DMA channel 0
    CH0_SRC = (uint32_t)source_buffer;
    CH0_DST = (uint32_t)dest_buffer;
    CH0_COUNT = 64;
    CH0_CTRL = CTRL_ENABLE | CTRL_SRC_INC | CTRL_DST_INC;

    printf("  DMA configured: src=0x%x, dst=0x%x, count=%u\n",
           (uint32_t)source_buffer, (uint32_t)dest_buffer, 64);

    // Start transfer
    CH0_CTRL = CTRL_ENABLE | CTRL_SRC_INC | CTRL_DST_INC | CTRL_START;
    printf("  Transfer started...\n");

    // Wait for completion
    wait_for_dma_ch0();

    // Check status
    if (CH0_STATUS & STATUS_DONE) {
        printf("  Transfer complete!\n");
        // Clear DONE flag
        CH0_STATUS = STATUS_DONE;
    }
    if (CH0_STATUS & STATUS_ERROR) {
        printf("  ERROR: Transfer failed!\n");
        CH0_STATUS = STATUS_ERROR;
    }

    // Verify data
    errors = 0;
    for (i = 0; i < 64; i++) {
        if (dest_buffer[i] != source_buffer[i]) {
            errors++;
        }
    }
    printf("  Verification: %u bytes, %u errors\n", 64, errors);
    if (errors == 0) {
        printf("  \xE2\x9C\x93 Test 1 PASSED\n");
    } else {
        printf("  \xE2\x9C\x97 Test 1 FAILED\n");
    }
    printf("\n");

    //=========================================================================
    // Test 2: Large transfer (256 bytes)
    //=========================================================================
    printf("Test 2: Large Transfer (256 bytes)\n");
    printf("-----------------------------------\n");

    // Initialize buffers
    for (i = 0; i < 256; i++) {
        source_buffer[i] = (uint8_t)(i ^ 0x55);
        dest_buffer[i] = 0xFF;
    }

    printf("  Source buffer filled with XOR pattern\n");

    // Configure and start DMA
    CH0_SRC = (uint32_t)source_buffer;
    CH0_DST = (uint32_t)dest_buffer;
    CH0_COUNT = 256;
    CH0_CTRL = CTRL_ENABLE | CTRL_SRC_INC | CTRL_DST_INC | CTRL_START;

    printf("  Transfer started (256 bytes)...\n");
    wait_for_dma_ch0();

    if (CH0_STATUS & STATUS_DONE) {
        printf("  Transfer complete!\n");
        CH0_STATUS = STATUS_DONE;
    }

    // Verify
    errors = 0;
    for (i = 0; i < 256; i++) {
        if (dest_buffer[i] != source_buffer[i]) {
            errors++;
        }
    }
    printf("  Verification: %u bytes, %u errors\n", 256, errors);
    if (errors == 0) {
        printf("  \xE2\x9C\x93 Test 2 PASSED\n");
    } else {
        printf("  \xE2\x9C\x97 Test 2 FAILED\n");
    }
    printf("\n");

    //=========================================================================
    // Test 3: Fixed source address (fill operation)
    //=========================================================================
    printf("Test 3: Fixed Source (Memory Fill)\n");
    printf("-----------------------------------\n");

    // Set source to a single value
    source_buffer[0] = 0x42;

    // Clear destination
    for (i = 0; i < 128; i++) {
        dest_buffer[i] = 0x00;
    }

    printf("  Filling 128 bytes with value 0x42\n");

    // Configure DMA with fixed source (no SRC_INC)
    CH0_SRC = (uint32_t)&source_buffer[0];
    CH0_DST = (uint32_t)dest_buffer;
    CH0_COUNT = 128;
    CH0_CTRL = CTRL_ENABLE | CTRL_DST_INC | CTRL_START;  // No SRC_INC!

    wait_for_dma_ch0();

    if (CH0_STATUS & STATUS_DONE) {
        printf("  Fill complete!\n");
        CH0_STATUS = STATUS_DONE;
    }

    // Verify all bytes are 0x42
    errors = 0;
    for (i = 0; i < 128; i++) {
        if (dest_buffer[i] != 0x42) {
            errors++;
        }
    }
    printf("  Verification: %u bytes, %u errors\n", 128, errors);
    if (errors == 0) {
        printf("  \xE2\x9C\x93 Test 3 PASSED\n");
    } else {
        printf("  \xE2\x9C\x97 Test 3 FAILED\n");
    }
    printf("\n");

    //=========================================================================
    // Test 4: Multiple concurrent channels
    //=========================================================================
    printf("Test 4: Concurrent Transfers (2 channels)\n");
    printf("------------------------------------------\n");

    // Prepare two independent buffers
    for (i = 0; i < 128; i++) {
        source_buffer[i] = (uint8_t)(i);
        verify_buffer[i] = (uint8_t)(255 - i);
        dest_buffer[i] = 0x00;
        dest_buffer[i + 128] = 0x00;
    }

    printf("  Channel 0: Copy 128 bytes (ascending pattern)\n");
    printf("  Channel 1: Copy 128 bytes (descending pattern)\n");

    // Configure both channels
    CH0_SRC = (uint32_t)source_buffer;
    CH0_DST = (uint32_t)dest_buffer;
    CH0_COUNT = 128;

    CH1_SRC = (uint32_t)verify_buffer;
    CH1_DST = (uint32_t)&dest_buffer[128];
    CH1_COUNT = 128;

    // Start both transfers
    CH0_CTRL = CTRL_ENABLE | CTRL_SRC_INC | CTRL_DST_INC | CTRL_START;
    CH1_CTRL = CTRL_ENABLE | CTRL_SRC_INC | CTRL_DST_INC | CTRL_START;

    printf("  Both transfers started...\n");

    // Wait for both
    wait_for_dma_ch0();
    wait_for_dma_ch1();

    if ((CH0_STATUS & STATUS_DONE) && (CH1_STATUS & STATUS_DONE)) {
        printf("  Both transfers complete!\n");
        CH0_STATUS = STATUS_DONE;
        CH1_STATUS = STATUS_DONE;
    }

    // Verify both transfers
    errors = 0;
    for (i = 0; i < 128; i++) {
        if (dest_buffer[i] != source_buffer[i]) errors++;
        if (dest_buffer[i + 128] != verify_buffer[i]) errors++;
    }
    printf("  Verification: %u bytes, %u errors\n", 256, errors);
    if (errors == 0) {
        printf("  \xE2\x9C\x93 Test 4 PASSED\n");
    } else {
        printf("  \xE2\x9C\x97 Test 4 FAILED\n");
    }
    printf("\n");

    //=========================================================================
    // Summary
    //=========================================================================
    printf("=============================================\n");
    printf("  DMA Controller Test Complete\n");
    printf("=============================================\n");
    printf("\n");
    printf("All DMA features tested:\n");
    printf("  - Memory-to-memory transfers\n");
    printf("  - Address increment modes\n");
    printf("  - Fixed source (memory fill)\n");
    printf("  - Multiple concurrent channels\n");
    printf("  - Status flags (BUSY, DONE)\n");
    printf("\n");

    return 0;
}
