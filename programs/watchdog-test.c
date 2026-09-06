/* **************************************************************************
 *              RISC-V Emulator - Watchdog Timer Test Program
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

// Watchdog Timer Test Program
// Demonstrates watchdog functionality:
//   - Enable watchdog with timeout
//   - Periodic feeding to prevent reset
//   - Intentional timeout to trigger reset
//   - Recovery after reset
//
// Usage:
//   ./bin/riscv_emulator --machine qemu-virt programs/watchdog-test.elf
// By Ulrik Hørlyk Hjort 2026

#include <stdint.h>

// UART for output
#define UART_BASE 0x10000000
#define UART_THR  (*(volatile unsigned char *)(UART_BASE + 0))
#define UART_LSR  (*(volatile unsigned char *)(UART_BASE + 5))
#define LSR_THRE  (1 << 5)

// Watchdog registers (base at 0x10050000)
#define WDT_BASE    0x10050000
#define WDT_CTRL    (*(volatile uint32_t *)(WDT_BASE + 0x00))
#define WDT_COUNT   (*(volatile uint32_t *)(WDT_BASE + 0x04))
#define WDT_RELOAD  (*(volatile uint32_t *)(WDT_BASE + 0x08))
#define WDT_FEED    (*(volatile uint32_t *)(WDT_BASE + 0x0C))

// Control register bits
#define WDT_CTRL_ENABLE  (1 << 0)
#define WDT_CTRL_RESET   (1 << 1)

// External functions provided by C library
extern int printf(const char *fmt, ...);
extern void delay_ms(uint32_t ms);

static void delay(uint32_t count) {
    volatile uint32_t i;
    for (i = 0; i < count; i++) {
        // Busy wait
    }
}

int main(void) {
    printf("\n");
    printf("=============================================\n");
    printf("  Watchdog Timer Test Program\n");
    printf("=============================================\n");
    printf("\n");

    // Check if reset occurred
    uint32_t ctrl = WDT_CTRL;
    if (ctrl & WDT_CTRL_RESET) {
        printf("*** WATCHDOG RESET DETECTED! ***\n");
        printf("System recovered from watchdog timeout\n\n");
    } else {
        printf("Normal system startup\n\n");
    }

    //=========================================================================
    // Test 1: Configure watchdog
    //=========================================================================
    printf("Test 1: Configure Watchdog\n");
    printf("---------------------------\n");

    // Set reload value (timeout period)
    WDT_RELOAD = 50000;  // 50000 ticks until timeout (long enough for tests)
    printf("  Set reload value: %u ticks\n", WDT_RELOAD);

    // Enable watchdog
    WDT_CTRL = WDT_CTRL_ENABLE;
    printf("  Watchdog enabled\n");
    printf("  Current counter: %u\n", WDT_COUNT);
    printf("\n");

    //=========================================================================
    // Test 2: Periodic feeding (normal operation)
    //=========================================================================
    printf("Test 2: Normal Operation (Periodic Feeding)\n");
    printf("--------------------------------------------\n");
    printf("Feeding watchdog 5 times to prevent reset...\n\n");

    for (int i = 0; i < 5; i++) {
        printf("  Feed %d: counter before = %u", i + 1, WDT_COUNT);

        // Do some work
        delay(100);

        // Feed the watchdog
        WDT_FEED = 0x00;  // Any write feeds it

        printf(", after = %u\n", WDT_COUNT);
    }

    printf("\nWatchdog fed successfully - no reset occurred\n\n");

    //=========================================================================
    // Test 3: Intentional timeout (demonstrate reset)
    //=========================================================================
    printf("Test 3: Watchdog Timeout (Intentional)\n");
    printf("---------------------------------------\n");
    printf("Setting short timeout and NOT feeding...\n");

    // Set short timeout
    WDT_RELOAD = 50;
    WDT_FEED = 0x00;  // Reset counter to new reload value
    printf("  Reload value: %u ticks\n", WDT_RELOAD);
    printf("  Initial counter: %u\n", WDT_COUNT);
    printf("\n");

    printf("Waiting for watchdog timeout (simulated)...\n");
    printf("In real hardware, system would reset now.\n\n");

    // Simulate countdown
    for (int i = 0; i < 10; i++) {
        uint32_t count = WDT_COUNT;
        printf("  Tick %d: counter = %u\n", i, count);

        if (count == 0) {
            printf("\n*** WATCHDOG TIMEOUT! ***\n");
            printf("System would reset here.\n");
            break;
        }

        delay(50);
    }

    printf("\n");

    //=========================================================================
    // Test 4: Disable watchdog
    //=========================================================================
    printf("Test 4: Disable Watchdog\n");
    printf("------------------------\n");

    WDT_CTRL = 0;  // Disable watchdog
    printf("  Watchdog disabled\n");
    printf("  Counter: %u (should stop counting)\n", WDT_COUNT);
    printf("\n");

    //=========================================================================
    // Summary
    //=========================================================================
    printf("=============================================\n");
    printf("  Watchdog Test Complete\n");
    printf("=============================================\n");
    printf("\n");

    printf("Key Observations:\n");
    printf("  1. Watchdog must be fed periodically\n");
    printf("  2. Timeout triggers system reset\n");
    printf("  3. Reset flag indicates recovery\n");
    printf("  4. Can be enabled/disabled as needed\n");
    printf("\n");

    printf("Use Cases:\n");
    printf("  - Fault recovery (hung tasks)\n");
    printf("  - Safety-critical systems\n");
    printf("  - Embedded reliability\n");
    printf("\n");

    return 0;
}
