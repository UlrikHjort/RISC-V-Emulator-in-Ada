# Mini-RTOS Educational Demonstration

## Overview

The Mini-RTOS demo (`programs/rtos-demo.c`) is an educational demonstration of Real-Time Operating System concepts implemented in bare-metal RISC-V code. It showcases fundamental RTOS principles without requiring complex assembly-level context switching.

**Phase:** 5A.1 - Real-Time Features
**Status:** Complete and functional
**Purpose:** Educational demonstration of RTOS concepts

## Key Features

- **Task Control Blocks (TCB)**: Structured task management
- **Multiple task states**: READY, RUNNING, BLOCKED
- **Round-robin scheduling**: Fair time-slicing between tasks
- **Priority-based preemption**: Higher priority tasks run first
- **Cooperative multitasking**: Tasks can yield or delay
- **System tick**: 1ms time quantum simulation
- **Three concurrent tasks**:
  - Task 0 (HIGH): LED blink every 50 ticks
  - Task 1 (NORMAL): Sensor read every 100 ticks
  - Task 2 (IDLE): Runs when all others blocked

## Implementation Details

### Architecture

The RTOS uses a **state-machine approach** rather than stack-based context switching:

```c
typedef enum {
    TASK_READY,      // Ready to run
    TASK_RUNNING,    // Currently executing
    TASK_BLOCKED     // Waiting (delayed)
} task_state_t;

typedef struct {
    const char *name;
    task_state_t state;
    uint32_t delay_counter;    // Ticks remaining in delay
    uint32_t exec_counter;     // Number of times executed
    uint32_t time_slice_left;  // Time quantum remaining
} task_t;
```

### Scheduler

**Algorithm**: Priority-based round-robin
- Each task gets a 100-tick time slice
- Higher priority tasks preempt lower priority
- Blocked tasks are skipped
- IDLE task runs when all others blocked

```c
void schedule(void) {
    // Save current task state if time slice exhausted or blocked
    if (tasks[current_task].time_slice_left == 0 ||
        tasks[current_task].state == TASK_BLOCKED) {

        // Find next ready task
        uint32_t next_task = find_next_task();

        // Context switch (state-based, not stack-based)
        tasks[current_task].state = TASK_READY;
        current_task = next_task;
        tasks[current_task].state = TASK_RUNNING;
        tasks[current_task].time_slice_left = TIME_SLICE;
    }
}
```

### System Tick

Called periodically to:
1. Decrement time slices
2. Update delay counters
3. Wake up delayed tasks
4. Trigger scheduler

```c
void system_tick(void) {
    sys_tick_count++;

    // Decrement time slice of running task
    if (tasks[current_task].time_slice_left > 0) {
        tasks[current_task].time_slice_left--;
    }

    // Update blocked tasks
    for (i = 0; i < NUM_TASKS; i++) {
        if (tasks[i].state == TASK_BLOCKED &&
            tasks[i].delay_counter > 0) {
            tasks[i].delay_counter--;
            if (tasks[i].delay_counter == 0) {
                tasks[i].state = TASK_READY;
            }
        }
    }
}
```

### Task Functions

Tasks are implemented as **non-returning functions** that maintain their own state:

```c
void task_led_blink(void) {
    // Simulated LED state
    static uint32_t led_state = 0;

    printf("[Task 0] LED %s\n", led_state ? "ON" : "OFF");
    led_state = !led_state;

    // Block self for 50 ticks
    task_delay(50);
}
```

## How to Use

### Building

```bash
cd programs
make rtos-demo.elf
```

**Note**: Requires `-march=rv32imc_zicsr` for CSR instructions.

### Running

```bash
make run-rtos-demo
# Or directly:
../bin/riscv_emulator --machine qemu-virt --max-instructions 1000000 rtos-demo.elf
```

### Expected Output

```
Mini-RTOS Educational Demonstration

System initialized with 3 tasks:
  Task 0 (LED Blink)    - Priority: HIGH   - Delay: 50 ticks
  Task 1 (Sensor Read)  - Priority: NORMAL - Delay: 100 ticks
  Task 2 (Idle Task)    - Priority: IDLE   - Delay: 0 ticks

Starting scheduler...

Tick 0000: [Task 0] LED ON
Tick 0050: [Task 0] LED OFF
Tick 0100: [Task 1] Sensor value: 42
Tick 0150: [Task 0] LED ON
...
```

## Modifying the Demo

### Adding a New Task

1. **Increase task count**:
```c
#define NUM_TASKS 4  // Was 3
```

2. **Define task function**:
```c
void task_my_function(void) {
    printf("[Task 3] Doing work\n");
    task_delay(75);  // Block for 75 ticks
}
```

3. **Register in task table**:
```c
task_t tasks[NUM_TASKS] = {
    // ... existing tasks ...
    {"MyTask", TASK_READY, 0, 0, TIME_SLICE}
};
```

### Changing Priorities

Modify the `find_next_task()` function to implement your priority scheme:

```c
uint32_t find_next_task(void) {
    // Check high-priority tasks first
    for (i = 0; i < HIGH_PRIORITY_COUNT; i++) {
        if (tasks[i].state == TASK_READY) {
            return i;
        }
    }
    // Then normal priority, etc.
}
```

### Adjusting Time Slice

```c
#define TIME_SLICE 100  // Change quantum (in ticks)
```

Smaller values = more responsive, more overhead
Larger values = less overhead, less responsive

## Known Limitations

### 1. No Stack-Based Context Switching

**Issue**: Tasks cannot be suspended mid-execution. They must explicitly yield or delay.

**Impact**:
- Tasks must be designed cooperatively
- Long-running calculations will monopolize CPU
- Not suitable for truly preemptive multitasking

**Workaround**: Break long tasks into smaller chunks with explicit yields.

### 2. No Dynamic Task Creation

**Issue**: All tasks must be defined at compile time.

**Impact**: Cannot spawn tasks at runtime based on events.

**Workaround**: Pre-allocate task slots and enable/disable them.

### 3. No Synchronization Primitives

**Issue**: No mutexes, semaphores, or message queues.

**Impact**:
- Cannot safely share resources between tasks
- No inter-task communication mechanism

**Workaround**: Use simple global flags with careful ordering.

### 4. Limited to Educational Use

**Issue**: This is a teaching tool, not production-ready.

**Impact**:
- No interrupt handling
- No memory protection
- No priority inheritance
- No deadlock detection

**Note**: For production use, consider FreeRTOS, Zephyr, or similar.

## Technical Details

### CSR Instructions (Zicsr Extension)

The demo uses CSR instructions for cycle counting:

```c
static inline uint32_t get_cycle_count(void) {
    uint32_t count;
    asm volatile ("rdcycle %0" : "=r"(count));
    return count;
}
```

**Requirement**: Must compile with `-march=rv32imc_zicsr`

### Memory Usage

- **Code**: ~4 KB
- **Data**: Minimal (task structures, stack)
- **Stack**: Shared stack (no per-task stacks)

**Total footprint**: ~5 KB

### Performance

- **Task switch overhead**: ~50 instructions
- **System tick overhead**: ~100 instructions
- **Maximum tasks**: Limited only by memory
- **Time quantum**: Configurable (default 100 ticks)

## Educational Value

This demo teaches:

1. **RTOS fundamentals**
   - Task states and transitions
   - Scheduling algorithms
   - Time-slicing and preemption

2. **Bare-metal programming**
   - No OS, no libraries
   - Direct hardware access
   - Timing and delays

3. **Embedded design patterns**
   - State machines
   - Cooperative multitasking
   - Event-driven programming

4. **Real-time concepts**
   - Deterministic timing
   - Priority-based execution
   - Resource management

## Comparison with Production RTOS

| Feature | Mini-RTOS Demo | FreeRTOS | Zephyr |
|---------|---------------|----------|--------|
| Context switching | State-based | Stack-based | Stack-based |
| Preemption | Cooperative | Preemptive | Preemptive |
| Memory protection | None | Optional | Yes |
| Synchronization | None | Full | Full |
| Interrupt handling | No | Yes | Yes |
| Dynamic tasks | No | Yes | Yes |
| Code size | ~5 KB | ~10 KB | ~20 KB |
| Complexity | Simple | Medium | High |
| Use case | Education | Production | Production |

## Further Reading

- [FreeRTOS Documentation](https://www.freertos.org/RTOS.html)
- [RISC-V Privileged Spec](https://riscv.org/specifications/privileged-isa/)
- [Embedded Systems: Real Time Operating Systems](https://www.embedded.com/real-time-operating-systems/)

## Troubleshooting

### Program Hangs

**Problem**: Scheduler stuck in infinite loop

**Solution**: Ensure at least one task is always READY (IDLE task should never block)

### Tasks Not Running

**Problem**: Task never gets scheduled

**Solution**:
1. Check task state is READY
2. Verify priority is being considered
3. Ensure time slice is not zero

### CSR Instruction Errors

**Problem**: `Error: unrecognized opcode 'csrsi'`

**Solution**: Add `-march=rv32imc_zicsr` to compiler flags

### Performance Issues

**Problem**: System runs too slowly

**Solution**:
1. Increase `--max-instructions` limit
2. Reduce number of printf calls
3. Increase time quantum

## Source Files

- **Implementation**: `programs/rtos-demo.c` (~500 lines)
- **Makefile**: `programs/Makefile` (build rules)
- **Startup**: `programs/crt0.S` (boot code)
- **Linker**: `programs/hello.ld` (memory layout)

## License

Same as main project (MIT License).

## Version History

- **v1.0** (2026-02-15): Initial implementation
  - State-machine scheduler
  - Round-robin with priorities
  - Three example tasks
  - Educational focus
