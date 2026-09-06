/* **************************************************************************
 *          RISC-V Emulator - Performance Profiling Demonstration
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

// Performance Profiling Demonstration
// This program demonstrates profiling features:
//   - Per-function profiling (instruction counts, cycles)
//   - Call graph analysis (caller -> callee relationships)
//   - Flamegraph visualization
//   - Hotspot identification
//
// Usage:
//   # Basic profiling
//   ./bin/riscv_emulator --profile -max-instructions 100000 programs/profile-demo.elf
//
//   # Flamegraph generation
//   ./bin/riscv_emulator --flamegraph profile.fg -max-instructions 100000 programs/profile-demo.elf
//   flamegraph.pl profile.fg > profile.svg
//   firefox profile.svg
//
// Expected output:
//   - hotspot_function should use most CPU time (70%+)
//   - Call graph shows: main -> worker_function -> hotspot_function
//   - Flamegraph shows wide bar for hotspot
// By Ulrik Hørlyk Hjort 2026

#include <stdio.h>

// Forward declarations
void hotspot_function(int iterations);
void medium_function(int iterations);
void light_function(int iterations);
void worker_function(int work_amount);
void helper_function(int count);
int expensive_computation(int n);
int cheap_computation(int n);

int main(void) {
    printf("=== Profiling Demo Program ===\n\n");

    printf("This program creates different execution patterns for profiling.\n");
    printf("The hotspot_function should dominate CPU usage.\n\n");

    // Main work loop - this creates the primary call pattern
    printf("Starting main work...\n");

    // Call worker function multiple times
    // This creates call graph: main -> worker_function
    for (int i = 0; i < 5; i++) {
        worker_function(100);
    }

    // Some medium-cost work
    medium_function(50);

    // Some light-cost work (called many times)
    for (int i = 0; i < 20; i++) {
        light_function(10);
    }

    // Direct hotspot calls
    printf("Executing hotspot directly...\n");
    hotspot_function(200);

    printf("\n=== Profiling Demo Complete ===\n");
    printf("\nExpected profile results:\n");
    printf("  1. hotspot_function - highest cycles (70%%+)\n");
    printf("  2. medium_function - moderate cycles (15%%)\n");
    printf("  3. light_function - low cycles per call, many calls\n");
    printf("\nCall graph should show:\n");
    printf("  main -> worker_function -> hotspot_function\n");
    printf("  main -> worker_function -> helper_function\n");
    printf("  main -> medium_function\n");
    printf("  main -> light_function\n");

    return 0;
}

// Worker function that calls multiple helpers
// Creates interesting call graph patterns
void worker_function(int work_amount) {
    // This is the main worker - calls both hotspot and helper

    // Do some expensive work (this is the hotspot)
    hotspot_function(work_amount);

    // Do some helper work
    helper_function(work_amount / 2);

    // Do a little computation
    int result = expensive_computation(work_amount);
    (void)result;  // Avoid unused warning
}

// The performance hotspot - uses most CPU time
void hotspot_function(int iterations) {
    // This function does a lot of work
    // It should appear as the widest bar in flamegraph
    // and highest cycles in profile

    volatile int sum = 0;  // volatile prevents optimization

    // Outer loop
    for (int i = 0; i < iterations; i++) {
        // Inner loop - this is where CPU time is spent
        for (int j = 0; j < 100; j++) {
            // Expensive operations
            sum += (i * j) + (i % 7) + (j % 11);
            sum ^= (i << 2) | (j >> 1);
            sum *= (i + 1);
            sum /= (j + 1);

            // Nested computation
            if (sum > 1000) {
                sum = expensive_computation(sum % 50);
            } else {
                sum = cheap_computation(sum);
            }
        }
    }
}

// Medium-cost function
void medium_function(int iterations) {
    // Moderate amount of work
    volatile int product = 1;

    for (int i = 1; i <= iterations; i++) {
        for (int j = 1; j <= 20; j++) {
            product *= (i + j);
            product %= 10000;
        }
    }
}

// Light-weight function (called many times)
void light_function(int iterations) {
    // Small amount of work per call
    // But called frequently

    volatile int count = 0;
    for (int i = 0; i < iterations; i++) {
        count += i * 2;
        count++;
    }
}

// Helper function called by worker
void helper_function(int count) {
    // Does some helper work
    volatile int result = 0;

    for (int i = 0; i < count; i++) {
        result += cheap_computation(i);
    }

    // Sometimes calls expensive computation
    if (count > 25) {
        result += expensive_computation(count / 2);
    }
}

// Expensive computation (shows up in profile)
int expensive_computation(int n) {
    // Simulate expensive operation
    volatile int result = n;

    for (int i = 0; i < 50; i++) {
        result = (result * 7 + 13) % 1000;
        result ^= (i << 1);
    }

    return result;
}

// Cheap computation (minimal cost)
int cheap_computation(int n) {
    // Fast operation
    return (n * 2 + 1) % 100;
}
