/* **************************************************************************
 *              RISC-V Emulator - Debug Feature Demonstration
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

// Debug Feature Demonstration
// This program demonstrates various debugging features:
//   - Breakpoints (by function name and address)
//   - Watchpoints (memory access tracking)
//   - Call stack backtrace
//   - Register inspection
//   - Memory inspection
//
// Usage:
//   ./bin/riscv_emulator -d programs/debug-demo.elf
//
// Try these debugger commands:
//   b main                 # Breakpoint at main
//   b recursive_sum        # Breakpoint at function
//   c                      # Continue to breakpoint
//   bt                     # Show call stack
//   watch 80100000 w       # Watch stack memory writes
//   r                      # Show registers
//   m 80100000 64          # Dump stack memory
//   d 800000bc 20          # Disassemble from main
//   info functions         # List all functions
// By Ulrik Hørlyk Hjort 2026

#include <stdio.h>

// Global variables to demonstrate watchpoints
int global_counter = 0;
int global_array[10];

// Forward declarations
void demonstrate_calls(void);
void demonstrate_memory(void);
void demonstrate_loops(void);
int recursive_sum(int n);
int fibonacci(int n);

// Helper function to show call stack depth
int level_1(int val);
int level_2(int val);
int level_3(int val);
int level_4(int val);

int main(void) {
    printf("=== Debug Demo Program ===\n\n");

    printf("This program demonstrates debugging features.\n");
    printf("Try setting breakpoints, watchpoints, and using backtrace.\n\n");

    // Demonstrate function calls (good for breakpoints)
    printf("--- Function Calls ---\n");
    demonstrate_calls();
    printf("\n");

    // Demonstrate memory access (good for watchpoints)
    printf("--- Memory Operations ---\n");
    demonstrate_memory();
    printf("\n");

    // Demonstrate loops (good for stepping)
    printf("--- Loop Operations ---\n");
    demonstrate_loops();
    printf("\n");

    // Demonstrate deep call stack (good for backtrace)
    printf("--- Deep Call Stack ---\n");
    int result = level_1(42);
    printf("Deep call result: %d\n\n", result);

    // Demonstrate recursion (good for backtrace)
    printf("--- Recursion ---\n");
    int sum = recursive_sum(10);
    printf("Sum(1..10) = %d\n", sum);

    int fib = fibonacci(8);
    printf("Fibonacci(8) = %d\n\n", fib);

    printf("=== Debug Demo Complete ===\n");
    printf("\nTry these debug commands:\n");
    printf("  b main                  - Break at main\n");
    printf("  b recursive_sum         - Break at recursive function\n");
    printf("  watch 80100000 w        - Watch stack writes\n");
    printf("  bt                      - Show call stack\n");
    printf("  info functions          - List functions\n");
    printf("  r                       - Show registers\n");
    printf("  fregs                   - Show FP registers\n");

    return 0;
}

// Demonstrate various function calls
void demonstrate_calls(void) {
    printf("Calling multiple functions...\n");

    // Simple call
    int sum = recursive_sum(5);
    printf("  recursive_sum(5) = %d\n", sum);

    // Another call
    int fib = fibonacci(6);
    printf("  fibonacci(6) = %d\n", fib);

    printf("Function calls complete.\n");
}

// Demonstrate memory operations (good for watchpoints)
void demonstrate_memory(void) {
    printf("Writing to global memory...\n");

    // Write to global counter (set watchpoint here)
    global_counter = 100;
    printf("  global_counter = %d\n", global_counter);

    // Write to array
    for (int i = 0; i < 10; i++) {
        global_array[i] = i * 10;  // Try: watch &global_array[5] w
    }

    printf("  global_array[5] = %d\n", global_array[5]);

    // Stack operations
    int local_array[5];
    for (int i = 0; i < 5; i++) {
        local_array[i] = i + 1;
    }

    printf("  local_array[2] = %d\n", local_array[2]);
    printf("Memory operations complete.\n");
}

// Demonstrate loops (good for stepping)
void demonstrate_loops(void) {
    printf("Running loops...\n");

    // Simple counting loop
    int sum = 0;
    for (int i = 1; i <= 10; i++) {
        sum += i;  // Try stepping through this
    }
    printf("  Sum(1..10) = %d\n", sum);

    // Nested loop
    int product = 0;
    for (int i = 1; i <= 5; i++) {
        for (int j = 1; j <= 3; j++) {
            product += i * j;  // Try stepping here
        }
    }
    printf("  Nested loop product sum = %d\n", product);

    printf("Loop operations complete.\n");
}

// Recursive function (demonstrates call stack)
int recursive_sum(int n) {
    // Base case
    if (n <= 0) {
        return 0;
    }

    // Recursive case - try setting breakpoint here
    // Then use 'bt' to see call stack
    return n + recursive_sum(n - 1);
}

// Fibonacci recursion (deep call stack)
int fibonacci(int n) {
    if (n <= 1) {
        return n;
    }

    // Deep recursion - good for backtrace
    return fibonacci(n - 1) + fibonacci(n - 2);
}

// Deep call stack demonstration
int level_1(int val) {
    printf("  Level 1 (val=%d)\n", val);
    return level_2(val + 1);
}

int level_2(int val) {
    printf("  Level 2 (val=%d)\n", val);
    return level_3(val + 2);
}

int level_3(int val) {
    printf("  Level 3 (val=%d)\n", val);
    return level_4(val + 3);
}

int level_4(int val) {
    printf("  Level 4 (val=%d)\n", val);
    // Set breakpoint here and use 'bt' to see full call stack:
    // #0 level_4
    // #1 level_3
    // #2 level_2
    // #3 level_1
    // #4 main
    return val + 4;
}
