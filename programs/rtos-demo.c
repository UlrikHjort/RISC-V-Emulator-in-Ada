/* **************************************************************************
 *           RISC-V Emulator - Mini-RTOS Demonstration for RISC-V
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

// Mini-RTOS Demonstration for RISC-V
// Educational bare-metal RTOS showing core concepts:
//   - Task Control Blocks (TCB)
//   - Round-robin scheduling
//   - Task states (READY, RUNNING, BLOCKED)
//   - Time-slice scheduling
//   - Task delays
//
// This is a simplified educational RTOS to demonstrate concepts.
// Real RTOS would have assembly context switching.
//
// Usage:
//   ./bin/riscv_emulator --machine qemu-virt programs/rtos-demo.elf
// By Ulrik Hørlyk Hjort 2026

#include <stdint.h>

// Printf declaration (provided by programs/printf.c in full builds,
// but we'll use a simple version here)
int printf(const char *fmt, ...);
void putchar(char c);

// UART definitions
#define UART_BASE 0x10000000
#define UART_THR  (*(volatile unsigned char *)(UART_BASE + 0))
#define UART_LSR  (*(volatile unsigned char *)(UART_BASE + 5))
#define LSR_THRE  (1 << 5)

// CLINT timer
#define CLINT_BASE      0x02000000
#define MTIME           (*(volatile uint64_t *)(CLINT_BASE + 0xBFF8))

// Task configuration
#define MAX_TASKS       3
#define TIME_SLICE      10     // Instructions per time slice

// Task states
typedef enum {
    TASK_READY,
    TASK_RUNNING,
    TASK_BLOCKED,
    TASK_TERMINATED
} task_state_t;

// Task Control Block
typedef struct {
    const char *name;
    task_state_t state;
    uint32_t delay_counter;      // Ticks remaining
    uint32_t exec_counter;       // Execution counter
    uint32_t time_slice_left;    // Time left in current slice
} task_t;

// RTOS state
static task_t tasks[MAX_TASKS];
static uint32_t current_task = 0;
static uint32_t system_tick = 0;

// Task execution counters (simulate work done)
static uint32_t led_state = 0;
static uint32_t sensor_value = 0;
static uint32_t idle_count = 0;

//=============================================================================
// Task Implementations (Simplified - state machine style)
//=============================================================================

void task_led_execute(void) {
    task_t *task = &tasks[0];

    if (task->exec_counter == 0) {
        // Start of task cycle
        led_state = !led_state;
        printf("[Task: LED Blink   ] LED is now %s (tick=%u)\n",
               led_state ? "ON " : "OFF", system_tick);

        // Set delay (block for 50 ticks)
        task->delay_counter = 50;
        task->state = TASK_BLOCKED;
    }

    task->exec_counter++;
}

void task_sensor_execute(void) {
    task_t *task = &tasks[1];

    if (task->exec_counter % 10 == 0) {
        // Execute every 10 time slices
        sensor_value = (sensor_value + 13) % 100;
        printf("[Task: Sensor Read ] Value = %u (tick=%u)\n",
               sensor_value, system_tick);

        // Set delay (block for 100 ticks)
        task->delay_counter = 100;
        task->state = TASK_BLOCKED;
    }

    task->exec_counter++;
}

void task_idle_execute(void) {
    idle_count++;

    if (idle_count % 100 == 0) {
        printf("[Task: Idle        ] Cycles = %u (tick=%u)\n",
               idle_count, system_tick);
    }
}

//=============================================================================
// RTOS Scheduler
//=============================================================================

void scheduler_init(void) {
    // Initialize Task 0: LED Blink
    tasks[0].name = "LED Blink";
    tasks[0].state = TASK_READY;
    tasks[0].delay_counter = 0;
    tasks[0].exec_counter = 0;
    tasks[0].time_slice_left = TIME_SLICE;

    // Initialize Task 1: Sensor Read
    tasks[1].name = "Sensor Read";
    tasks[1].state = TASK_READY;
    tasks[1].delay_counter = 0;
    tasks[1].exec_counter = 0;
    tasks[1].time_slice_left = TIME_SLICE;

    // Initialize Task 2: Idle
    tasks[2].name = "Idle";
    tasks[2].state = TASK_READY;
    tasks[2].delay_counter = 0;
    tasks[2].exec_counter = 0;
    tasks[2].time_slice_left = TIME_SLICE;

    current_task = 0;
}

// Find next ready task (round-robin)
uint32_t find_next_task(void) {
    uint32_t start = current_task;
    uint32_t next = (start + 1) % MAX_TASKS;

    // Search for next ready task
    while (next != start) {
        if (tasks[next].state == TASK_READY) {
            return next;
        }
        next = (next + 1) % MAX_TASKS;
    }

    // Check current task
    if (tasks[current_task].state == TASK_READY) {
        return current_task;
    }

    // No ready task (shouldn't happen with idle task)
    return 2;  // Return idle task
}

// Schedule next task
void schedule(void) {
    // Decrement time slice
    if (tasks[current_task].time_slice_left > 0) {
        tasks[current_task].time_slice_left--;
    }

    // Check if time slice expired or task blocked
    if (tasks[current_task].time_slice_left == 0 ||
        tasks[current_task].state == TASK_BLOCKED) {

        // Find next task
        uint32_t next_task = find_next_task();

        if (next_task != current_task) {
            // Context switch
            if (tasks[current_task].state == TASK_RUNNING) {
                tasks[current_task].state = TASK_READY;
            }

            current_task = next_task;
            tasks[current_task].state = TASK_RUNNING;
            tasks[current_task].time_slice_left = TIME_SLICE;

            printf("[Scheduler] Switch to Task %u: %s\n",
                   current_task, tasks[current_task].name);
        } else {
            // Same task continues
            tasks[current_task].time_slice_left = TIME_SLICE;
        }
    }
}

// System tick (called periodically)
void system_tick_handler(void) {
    system_tick++;

    // Update blocked tasks
    for (uint32_t i = 0; i < MAX_TASKS; i++) {
        if (tasks[i].state == TASK_BLOCKED) {
            if (tasks[i].delay_counter > 0) {
                tasks[i].delay_counter--;
                if (tasks[i].delay_counter == 0) {
                    // Delay expired, make task ready
                    tasks[i].state = TASK_READY;
                    printf("[Scheduler] Task %u (%s) now READY\n",
                           i, tasks[i].name);
                }
            }
        }
    }

    // Every 10 ticks, show scheduler status
    if (system_tick % 10 == 0) {
        printf("\n--- Tick %u Status ---\n", system_tick);
        for (uint32_t i = 0; i < MAX_TASKS; i++) {
            const char *state_str;
            switch (tasks[i].state) {
                case TASK_READY:   state_str = "READY  "; break;
                case TASK_RUNNING: state_str = "RUNNING"; break;
                case TASK_BLOCKED: state_str = "BLOCKED"; break;
                default:           state_str = "UNKNOWN"; break;
            }

            printf("  Task %u (%14s): %s", i, tasks[i].name, state_str);
            if (tasks[i].state == TASK_BLOCKED) {
                printf(" (delay=%u)", tasks[i].delay_counter);
            }
            printf("\n");
        }
        printf("\n");
    }
}

//=============================================================================
// Main Program
//=============================================================================

int main(void) {
    printf("\n");
    printf("========================================\n");
    printf("  Mini-RTOS Educational Demonstration\n");
    printf("========================================\n");
    printf("\n");

    printf("This demonstrates key RTOS concepts:\n");
    printf("  - Task Control Blocks (TCB)\n");
    printf("  - Task states (READY, RUNNING, BLOCKED)\n");
    printf("  - Round-robin scheduling\n");
    printf("  - Time-sliced execution\n");
    printf("  - Task delays\n");
    printf("\n");

    printf("Tasks:\n");
    printf("  Task 0: LED Blink - Toggles LED, delays 50 ticks\n");
    printf("  Task 1: Sensor Read - Reads sensor, delays 100 ticks\n");
    printf("  Task 2: Idle - Runs when others are blocked\n");
    printf("\n");

    printf("Starting scheduler...\n\n");

    // Initialize scheduler
    scheduler_init();

    // Main RTOS loop (simplified)
    for (uint32_t cycle = 0; cycle < 500; cycle++) {
        // Execute current task for one instruction
        switch (current_task) {
            case 0: task_led_execute(); break;
            case 1: task_sensor_execute(); break;
            case 2: task_idle_execute(); break;
        }

        // Call scheduler
        schedule();

        // Every 50 cycles, do a system tick
        if (cycle % 50 == 0 && cycle > 0) {
            system_tick_handler();
        }
    }

    printf("\n");
    printf("========================================\n");
    printf("  RTOS Demo Complete\n");
    printf("========================================\n");
    printf("\n");

    printf("Final Statistics:\n");
    printf("  System ticks:   %u\n", system_tick);
    printf("  LED toggles:    ~%u\n", tasks[0].exec_counter);
    printf("  Sensor reads:   ~%u\n", tasks[1].exec_counter);
    printf("  Idle cycles:    %u\n", idle_count);
    printf("\n");

    printf("Key Observations:\n");
    printf("  1. Tasks run concurrently via time-slicing\n");
    printf("  2. Blocked tasks don't consume CPU time\n");
    printf("  3. Idle task runs when others are blocked\n");
    printf("  4. Scheduler enforces fair time allocation\n");
    printf("\n");

    return 0;
}

//=============================================================================
// Utility Functions
//=============================================================================

void putchar(char c) {
    if (c == '\n') {
        while ((UART_LSR & LSR_THRE) == 0);
        UART_THR = '\r';
    }
    while ((UART_LSR & LSR_THRE) == 0);
    UART_THR = c;
}

// Simple printf implementation
int printf(const char *fmt, ...) {
    typedef __builtin_va_list va_list;
    #define va_start(ap, last) __builtin_va_start(ap, last)
    #define va_arg(ap, type) __builtin_va_arg(ap, type)
    #define va_end(ap) __builtin_va_end(ap)

    va_list args;
    va_start(args, fmt);

    const char *p = fmt;
    while (*p) {
        if (*p == '%') {
            p++;
            switch (*p) {
                case 'd':
                case 'u': {
                    unsigned int val = va_arg(args, unsigned int);
                    char buf[12];
                    int i = 0;
                    if (val == 0) {
                        putchar('0');
                    } else {
                        while (val > 0) {
                            buf[i++] = '0' + (val % 10);
                            val /= 10;
                        }
                        while (i > 0) {
                            putchar(buf[--i]);
                        }
                    }
                    break;
                }
                case 's': {
                    const char *s = va_arg(args, const char *);
                    while (*s) {
                        putchar(*s++);
                    }
                    break;
                }
                case '%':
                    putchar('%');
                    break;
            }
            p++;
        } else {
            putchar(*p++);
        }
    }

    va_end(args);
    return 0;
}
