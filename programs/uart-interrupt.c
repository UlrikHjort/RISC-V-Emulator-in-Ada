/* **************************************************************************
 *              RISC-V Emulator - UART Interrupt Test Program
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
 * UART Interrupt Test Program
 *
 * This program demonstrates UART interrupt functionality:
 * - Enabling/disabling receive and transmit interrupts
 * - Checking interrupt identification register
 * - Interrupt-driven I/O simulation
 */

extern void printf(const char *fmt, ...);

/* UART register definitions */
#define UART_BASE 0x10000000
#define UART_RBR  (*(volatile unsigned char *)(UART_BASE + 0))  /* Receive Buffer */
#define UART_THR  (*(volatile unsigned char *)(UART_BASE + 0))  /* Transmit Holding */
#define UART_IER  (*(volatile unsigned char *)(UART_BASE + 1))  /* Interrupt Enable */
#define UART_IIR  (*(volatile unsigned char *)(UART_BASE + 2))  /* Interrupt ID */
#define UART_LSR  (*(volatile unsigned char *)(UART_BASE + 5))  /* Line Status */

/* IER bit masks */
#define IER_RDA   0x01  /* Received Data Available */
#define IER_THRE  0x02  /* THR Empty */

/* IIR bit masks */
#define IIR_NO_INT  0x01  /* No interrupt pending */
#define IIR_THR     0x02  /* THR empty interrupt */
#define IIR_RDA     0x04  /* Received data interrupt */

/* LSR bit masks */
#define LSR_DR    0x01  /* Data Ready */
#define LSR_THRE  0x20  /* THR Empty */

/* Simple delay */
void delay(unsigned int count) {
    for (volatile unsigned int i = 0; i < count; i++) {
        /* Busy wait */
    }
}

int main(void) {
    unsigned char ier, iir, lsr;

    printf("\n=== UART Interrupt Test ===\n\n");

    /* Test 1: Check initial state */
    printf("=== Test 1: Initial Register State ===\n");

    ier = UART_IER;
    iir = UART_IIR;
    lsr = UART_LSR;

    printf("IER (Interrupt Enable):     0x%02x\n", ier);
    printf("IIR (Interrupt ID):         0x%02x\n", iir);
    printf("LSR (Line Status):          0x%02x\n", lsr);

    if (iir & IIR_NO_INT) {
        printf("PASS: No interrupt pending initially\n");
    } else {
        printf("INFO: Interrupt pending (0x%02x)\n", iir);
    }

    /* Test 2: Enable THR Empty Interrupt */
    printf("\n=== Test 2: Enable THR Empty Interrupt ===\n");

    UART_IER = IER_THRE;
    printf("Set IER = 0x%02x (THR empty enabled)\n", IER_THRE);

    delay(1000);

    ier = UART_IER;
    iir = UART_IIR;

    printf("IER read back: 0x%02x\n", ier);
    printf("IIR: 0x%02x\n", iir);

    if (ier & IER_THRE) {
        printf("PASS: IER_THRE bit is set\n");
    } else {
        printf("FAIL: IER_THRE bit not set\n");
    }

    if ((iir & IIR_NO_INT) == 0) {
        printf("PASS: Interrupt is pending\n");
        if ((iir & 0x0E) == IIR_THR) {
            printf("PASS: Interrupt is THR empty (0x%02x)\n", iir);
        } else {
            printf("INFO: Interrupt type is 0x%02x\n", iir);
        }
    } else {
        printf("INFO: No interrupt pending\n");
    }

    /* Test 3: Disable interrupts */
    printf("\n=== Test 3: Disable All Interrupts ===\n");

    UART_IER = 0;
    printf("Set IER = 0x00 (all interrupts disabled)\n");

    delay(1000);

    ier = UART_IER;
    iir = UART_IIR;

    printf("IER read back: 0x%02x\n", ier);
    printf("IIR: 0x%02x\n", iir);

    if (ier == 0) {
        printf("PASS: All interrupts disabled\n");
    } else {
        printf("FAIL: IER not zero (0x%02x)\n", ier);
    }

    if (iir & IIR_NO_INT) {
        printf("PASS: No interrupt pending\n");
    } else {
        printf("INFO: Interrupt still pending (0x%02x)\n", iir);
    }

    /* Test 4: Enable Received Data Interrupt */
    printf("\n=== Test 4: Enable Received Data Interrupt ===\n");

    UART_IER = IER_RDA;
    printf("Set IER = 0x%02x (RDA enabled)\n", IER_RDA);

    delay(1000);

    ier = UART_IER;
    iir = UART_IIR;
    lsr = UART_LSR;

    printf("IER read back: 0x%02x\n", ier);
    printf("IIR: 0x%02x\n", iir);
    printf("LSR: 0x%02x\n", lsr);

    if (ier & IER_RDA) {
        printf("PASS: IER_RDA bit is set\n");
    }

    if (lsr & LSR_DR) {
        printf("Data available in receive buffer\n");
        if ((iir & IIR_NO_INT) == 0) {
            printf("PASS: RDA interrupt is pending\n");
            if ((iir & 0x0E) == IIR_RDA) {
                printf("PASS: Interrupt type is RDA (0x%02x)\n", iir);
            }
        }
    } else {
        printf("No data in receive buffer\n");
        if (iir & IIR_NO_INT) {
            printf("PASS: No interrupt (no data available)\n");
        }
    }

    /* Test 5: Enable Both Interrupts */
    printf("\n=== Test 5: Enable Both Interrupts ===\n");

    UART_IER = IER_RDA | IER_THRE;
    printf("Set IER = 0x%02x (both RDA and THRE enabled)\n", IER_RDA | IER_THRE);

    delay(1000);

    ier = UART_IER;
    iir = UART_IIR;

    printf("IER read back: 0x%02x\n", ier);
    printf("IIR: 0x%02x\n", iir);

    if ((ier & (IER_RDA | IER_THRE)) == (IER_RDA | IER_THRE)) {
        printf("PASS: Both interrupt enables are set\n");
    }

    if ((iir & IIR_NO_INT) == 0) {
        unsigned char int_type = iir & 0x0E;
        printf("Interrupt pending, type: ");
        if (int_type == IIR_RDA) {
            printf("RDA (0x%02x)\n", int_type);
        } else if (int_type == IIR_THR) {
            printf("THR (0x%02x)\n", int_type);
        } else {
            printf("Unknown (0x%02x)\n", int_type);
        }
    }

    /* Test 6: Interrupt Priority Test */
    printf("\n=== Test 6: Interrupt Priority ===\n");
    printf("RDA interrupt has higher priority than THR interrupt\n");

    UART_IER = IER_RDA | IER_THRE;

    /* Check if data is available */
    lsr = UART_LSR;
    if (lsr & LSR_DR) {
        printf("Data available - RDA should take priority\n");
        iir = UART_IIR;
        if ((iir & 0x0E) == IIR_RDA) {
            printf("PASS: RDA interrupt has priority\n");
        } else {
            printf("INFO: Interrupt type is 0x%02x\n", iir & 0x0E);
        }
    } else {
        printf("No data available - THR interrupt expected\n");
        iir = UART_IIR;
        if ((iir & 0x0E) == IIR_THR) {
            printf("PASS: THR interrupt when no RDA\n");
        }
    }

    /* Test 7: Simulated Interrupt-Driven Receive */
    printf("\n=== Test 7: Simulated Interrupt-Driven Receive ===\n");

    UART_IER = IER_RDA;  /* Only enable receive interrupt */
    printf("Waiting for incoming data...\n");
    printf("(In real system, CPU would handle interrupt here)\n");

    /* Poll for data (simulates interrupt-driven approach) */
    int wait_count = 0;
    while (wait_count < 10) {
        lsr = UART_LSR;
        iir = UART_IIR;

        if (lsr & LSR_DR) {
            /* Data available */
            if ((iir & IIR_NO_INT) == 0) {
                printf("Interrupt triggered! Reading data...\n");
                unsigned char data = UART_RBR;
                printf("Received: 0x%02x ('%c')\n", data,
                       (data >= 32 && data < 127) ? data : '.');

                /* Check if interrupt cleared after read */
                iir = UART_IIR;
                printf("IIR after read: 0x%02x\n", iir);

                break;
            }
        }

        delay(100000);
        wait_count++;
    }

    if (wait_count >= 10) {
        printf("No data received (expected in automated test)\n");
    }

    /* Test 8: Register Read-Only Behavior */
    printf("\n=== Test 8: IIR Read-Only Test ===\n");

    /* Try to write to IIR (should be ignored) */
    iir = UART_IIR;
    printf("IIR before write attempt: 0x%02x\n", iir);

    UART_IIR = 0xFF;  /* Try to write */

    unsigned char iir_after = UART_IIR;
    printf("IIR after write attempt: 0x%02x\n", iir_after);

    if (iir_after == iir || iir_after != 0xFF) {
        printf("PASS: IIR is read-only (value unchanged or not 0xFF)\n");
    } else {
        printf("FAIL: IIR was modified\n");
    }

    /* Clean up */
    printf("\n=== Cleanup ===\n");
    UART_IER = 0;
    printf("All interrupts disabled\n");

    printf("\n=== UART Interrupt Tests Complete ===\n");

    return 0;
}
