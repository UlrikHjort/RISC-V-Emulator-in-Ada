/* **************************************************************************
 *                 RISC-V Emulator - Timer/PWM Test Program
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
 * Timer/PWM Test Program
 *
 * Tests hardware timer peripheral with 4 channels
 */

extern void printf(const char *fmt, ...);

#include "timer.h"

void print_test(const char *name, int passed) {
    printf("%s: %s\n", name, passed ? "PASS" : "FAIL");
}

int main(void) {
    printf("\n=== Hardware Timer/PWM Test Program ===\n");
    printf("Testing 4-channel timer peripheral at 0x%x\n", TIMER_BASE);

    /* Test 1: Initialization */
    printf("\n=== Test 1: Timer Initialization ===\n");
    timer_init();
    printf("Prescale: %d\n", timer_get_prescale());
    printf("Interrupt status: 0x%x\n", TIMER_INT_STATUS);
    printf("Interrupt enable: 0x%x\n", TIMER_INT_ENABLE);
    print_test("Prescale initialized", timer_get_prescale() == 1);
    print_test("No interrupts pending", TIMER_INT_STATUS == 0);
    print_test("Interrupts disabled", TIMER_INT_ENABLE == 0);

    /* Test 2: Counter set/get */
    printf("\n=== Test 2: Basic Counter Operation ===\n");
    timer_set_counter(0, 0);
    timer_set_compare(0, 100);
    printf("Counter: %u\n", timer_get_counter(0));
    printf("Compare: %u\n", timer_get_compare(0));
    print_test("Counter set to 0", timer_get_counter(0) == 0);
    print_test("Compare set to 100", timer_get_compare(0) == 100);

    /* Test 3: PWM output */
    printf("\n=== Test 3: PWM Mode Configuration ===\n");
    timer_set_pwm_mode(1, 1);
    timer_set_compare(1, 255);
    timer_set_output(1, 128);
    printf("PWM Period (compare): %u\n", timer_get_compare(1));
    printf("PWM Duty: %u/255\n", timer_get_output(1));
    print_test("PWM period 255", timer_get_compare(1) == 255);
    print_test("PWM duty 128", timer_get_output(1) == 128);

    printf("\n=== Timer Tests Complete ===\n");
    return 0;
}
