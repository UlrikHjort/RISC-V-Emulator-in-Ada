# Watchdog Timer Peripheral

## Overview

The Watchdog Timer (WDT) is a hardware peripheral that provides automatic system recovery from software faults. If the software fails to "feed" the watchdog within a specified timeout period, the watchdog triggers a system reset.

**Phase:** 5A.2 - Real-Time Features
**Status:** Complete and functional
**Base Address:** 0x10050000 (configurable)
**Purpose:** Fault detection and automatic recovery

## Key Features

- **Configurable timeout**: Set reload value for desired timeout period
- **Down-counting timer**: Decrements each CPU instruction cycle
- **Automatic reset**: Triggers system reset when counter reaches zero
- **Reset flag**: Software can detect if reset was caused by watchdog
- **Feed mechanism**: Writing to FEED register resets counter
- **Enable/disable**: Can be enabled or disabled at runtime
- **Auto-disable on timeout**: Prevents repeated reset loops

## Memory Map

**Base Address**: 0x10050000

| Offset | Register | Access | Description |
|--------|----------|--------|-------------|
| 0x00 | WDT_CTRL | R/W | Control register |
| 0x04 | WDT_COUNT | R | Current counter value |
| 0x08 | WDT_RELOAD | R/W | Reload/timeout value |
| 0x0C | WDT_FEED | W | Feed register (any write reloads) |

### Register Descriptions

#### WDT_CTRL (0x00) - Control Register

| Bit | Name | Access | Description |
|-----|------|--------|-------------|
| 0 | ENABLE | R/W | Enable watchdog (1=enabled, 0=disabled) |
| 1 | RESET | R/W1C | Reset occurred flag (write 1 to clear) |
| 7:2 | - | - | Reserved (read as 0) |

**ENABLE bit**: Set to 1 to start watchdog counting down.

**RESET bit**: Set by hardware when watchdog timeout occurs. Software can read this to detect watchdog-caused resets. Write 1 to clear the flag.

#### WDT_COUNT (0x04) - Counter Register

**Read-only**: Returns current countdown value.

**Range**: 0 to RELOAD value

**Behavior**: Decrements by 1 each CPU instruction cycle when enabled.

#### WDT_RELOAD (0x08) - Reload Value Register

**Read/Write**: Sets the timeout period.

**Units**: CPU instruction cycles

**Example**: Setting to 50000 means watchdog will timeout after 50000 instructions if not fed.

#### WDT_FEED (0x0C) - Feed Register

**Write-only**: Writing any value reloads the counter to RELOAD value.

**Effect**: Resets COUNT to RELOAD, preventing timeout.

## Implementation Details

### Hardware Implementation

**Files**:
- `src/riscv-watchdog.ads` - Ada specification
- `src/riscv-watchdog.adb` - Ada implementation

**State Structure**:
```ada
type Watchdog_State is record
   Base_Address  : Memory_Address;
   Enabled       : Boolean := False;
   Counter       : Word := 0;
   Reload_Value  : Word := 1000;
   Reset_Flag    : Boolean := False;
end record;
```

### Tick Behavior

The watchdog is processed **every CPU instruction cycle** in the main execution loop:

```ada
function Tick (WDT : in out Watchdog_State) return Boolean is
begin
   if not WDT.Enabled then
      return False;  -- Disabled
   end if;

   if WDT.Counter > 0 then
      WDT.Counter := WDT.Counter - 1;

      if WDT.Counter = 0 then
         -- Timeout! Trigger reset
         WDT.Reset_Flag := True;
         WDT.Enabled := False;      -- Auto-disable
         WDT.Counter := WDT.Reload_Value;  -- Reload
         return True;  -- Signal reset needed
      end if;
   end if;

   return False;
end Tick;
```

### CPU Integration

When watchdog timeout occurs (`Tick` returns `True`):

```ada
if Memory.Watchdog_Tick (Mem) then
   Put_Line ("*** WATCHDOG TIMEOUT - System Reset ***");
   Initialize (CPU, CPU.Reset_Vector);  -- Reset to entry point
   Cycles := 0;
end if;
```

**Effect**:
1. CPU state is reinitialized
2. PC set to original entry point
3. Registers cleared
4. Execution restarts from beginning
5. Watchdog is disabled (must be re-enabled)
6. Reset flag is set (detectable by software)

## How to Use

### C Programming Interface

```c
// Watchdog registers
#define WDT_BASE    0x10050000
#define WDT_CTRL    (*(volatile uint32_t *)(WDT_BASE + 0x00))
#define WDT_COUNT   (*(volatile uint32_t *)(WDT_BASE + 0x04))
#define WDT_RELOAD  (*(volatile uint32_t *)(WDT_BASE + 0x08))
#define WDT_FEED    (*(volatile uint32_t *)(WDT_BASE + 0x0C))

// Control bits
#define WDT_CTRL_ENABLE  (1 << 0)
#define WDT_CTRL_RESET   (1 << 1)
```

### Basic Usage

**1. Configure and Enable**:
```c
// Set timeout to 50000 instruction cycles
WDT_RELOAD = 50000;

// Enable watchdog
WDT_CTRL = WDT_CTRL_ENABLE;
```

**2. Feed the Watchdog**:
```c
// In main loop or periodic task
void feed_watchdog(void) {
    WDT_FEED = 0;  // Any value works
}
```

**3. Check for Reset**:
```c
void check_reset_cause(void) {
    if (WDT_CTRL & WDT_CTRL_RESET) {
        printf("System recovered from watchdog timeout!\n");

        // Clear the flag
        WDT_CTRL = WDT_CTRL_RESET;
    } else {
        printf("Normal system startup\n");
    }
}
```

**4. Disable Watchdog**:
```c
void disable_watchdog(void) {
    WDT_CTRL = 0;  // Clear ENABLE bit
}
```

### Complete Example

```c
int main(void) {
    // Check if this is a watchdog reset
    if (WDT_CTRL & WDT_CTRL_RESET) {
        printf("WATCHDOG RESET DETECTED!\n");
        WDT_CTRL = WDT_CTRL_RESET;  // Clear flag
        // Handle recovery...
    }

    // Configure watchdog for 100000 cycles
    WDT_RELOAD = 100000;
    WDT_CTRL = WDT_CTRL_ENABLE;

    while (1) {
        // Do work
        process_data();
        handle_communication();
        update_sensors();

        // Feed watchdog before timeout
        WDT_FEED = 0;

        delay_ms(100);
    }

    return 0;
}
```

## Timeout Calculation

**Formula**: `Timeout (seconds) ~ RELOAD_VALUE / CPU_Frequency`

**Example**:
- CPU running at ~1 MHz (1,000,000 Hz)
- RELOAD = 50,000
- Timeout = 50,000 / 1,000,000 = 0.05 seconds (50ms)

**Note**: Actual timeout depends on instruction execution rate, which varies with code complexity.

### Choosing Timeout Values

| Use Case | Reload Value | Approximate Time |
|----------|-------------|------------------|
| Quick response | 1,000 | ~1ms |
| Normal operation | 50,000 | ~50ms |
| Long tasks | 500,000 | ~500ms |
| Very long tasks | 5,000,000 | ~5s |

**Recommendation**: Set timeout to **2-3x** the longest expected task execution time.

## Known Limitations

### 1. Single Watchdog Instance

**Issue**: Only one watchdog timer available.

**Impact**: Cannot monitor multiple independent subsystems separately.

**Workaround**: Use software-level watchdog tracking for subsystems.

### 2. No Window Watchdog

**Issue**: Only maximum timeout, no minimum timeout.

**Impact**: Cannot detect tasks running too frequently (only too infrequently).

**Standard watchdog**: Feed anytime before timeout
**Window watchdog**: Feed only within specific time window

**Workaround**: Implement window checking in software.

### 3. Fixed Counter Decrement Rate

**Issue**: Counter decrements every CPU cycle, not on a fixed time base.

**Impact**:
- Timeout varies with CPU clock speed
- Timeout varies with instruction complexity
- Not suitable for precise timing

**Workaround**: Calibrate RELOAD value for your specific code.

### 4. No Prescaler

**Issue**: Cannot slow down counter with clock divider.

**Impact**:
- Long timeouts require large RELOAD values
- Limited to 32-bit counter (max ~4 billion cycles)

**Workaround**: Use software counter to extend timeout.

### 5. Auto-Disable on Timeout

**Behavior**: Watchdog disables itself after triggering reset.

**Impact**: Must re-enable watchdog after reset recovery.

**Rationale**: Prevents infinite reset loops if software is permanently stuck.

**Note**: This is a safety feature, not a limitation.

## Best Practices

### 1. Feed in Main Loop

```c
while (1) {
    // Main loop iterations
    handle_events();

    // Feed at end of each iteration
    feed_watchdog();
}
```

  **Good**: Ensures watchdog is fed regularly
[ ] **Bad**: Feeding in interrupt handlers (may mask main loop hangs)

### 2. Set Generous Timeout

```c
// Bad: Tight timeout
WDT_RELOAD = 1000;  // Too short, might trigger on valid delays

// Good: Generous timeout
WDT_RELOAD = 100000;  // Allows for legitimate delays
```

### 3. Handle Reset Gracefully

```c
if (WDT_CTRL & WDT_CTRL_RESET) {
    // Log the event
    error_log("Watchdog reset occurred");

    // Perform recovery
    reset_peripherals();
    clear_buffers();

    // Re-enable with longer timeout
    WDT_RELOAD = 200000;  // Double previous timeout
    WDT_CTRL = WDT_CTRL_RESET | WDT_CTRL_ENABLE;
}
```

### 4. Disable During Critical Sections

```c
void flash_write(uint32_t addr, uint8_t *data, size_t len) {
    // Flash writes can take a long time
    uint32_t wdt_ctrl = WDT_CTRL;
    WDT_CTRL = 0;  // Temporarily disable

    // Perform flash write
    flash_program(addr, data, len);

    // Re-enable
    WDT_CTRL = wdt_ctrl;
}
```

### 5. Test Watchdog Functionality

```c
void test_watchdog(void) {
    printf("Testing watchdog... do not feed for 10s\n");

    WDT_RELOAD = 5000000;  // 5 second timeout
    WDT_CTRL = WDT_CTRL_ENABLE;

    // Intentionally don't feed
    while (1) {
        // Busy wait, watchdog will reset system
    }
}
```

## Debugging

### Check Watchdog State

```c
void print_watchdog_status(void) {
    printf("Watchdog Status:\n");
    printf("  Enabled: %s\n",
           (WDT_CTRL & WDT_CTRL_ENABLE) ? "YES" : "NO");
    printf("  Reset flag: %s\n",
           (WDT_CTRL & WDT_CTRL_RESET) ? "YES" : "NO");
    printf("  Counter: %u\n", WDT_COUNT);
    printf("  Reload: %u\n", WDT_RELOAD);
}
```

### Trace Watchdog Feeds

```c
void feed_watchdog_debug(void) {
    static uint32_t feed_count = 0;

    WDT_FEED = 0;
    feed_count++;

    if (feed_count % 100 == 0) {
        printf("Watchdog fed %u times, counter=%u\n",
               feed_count, WDT_COUNT);
    }
}
```

## Test Program

**Location**: `programs/watchdog-test.c`

**Features**:
- Test 1: Configure and enable watchdog
- Test 2: Normal operation with periodic feeding
- Test 3: Intentional timeout to trigger reset
- Test 4: Reset flag detection and recovery

**Run**:
```bash
make -C programs run-watchdog-test
```

## Integration with RTOS

### FreeRTOS Example

```c
// Watchdog task - feeds watchdog if all tasks healthy
void watchdog_task(void *params) {
    WDT_RELOAD = 100000;
    WDT_CTRL = WDT_CTRL_ENABLE;

    while (1) {
        // Check all tasks are alive
        if (check_all_tasks_alive()) {
            WDT_FEED = 0;
        } else {
            // Don't feed - let watchdog reset system
            log_error("Task deadlock detected");
        }

        vTaskDelay(pdMS_TO_TICKS(50));
    }
}
```

### Task Heartbeat Pattern

```c
volatile uint32_t task_heartbeats[NUM_TASKS];

void task_function(void *params) {
    int task_id = (int)params;

    while (1) {
        // Do work
        process_data();

        // Signal alive
        task_heartbeats[task_id]++;

        vTaskDelay(pdMS_TO_TICKS(100));
    }
}

void watchdog_monitor(void) {
    static uint32_t last_heartbeats[NUM_TASKS];
    bool all_alive = true;

    for (int i = 0; i < NUM_TASKS; i++) {
        if (task_heartbeats[i] == last_heartbeats[i]) {
            all_alive = false;  // Task stuck
            break;
        }
        last_heartbeats[i] = task_heartbeats[i];
    }

    if (all_alive) {
        WDT_FEED = 0;
    }
}
```

## Performance Impact

- **Memory overhead**: None (memory-mapped I/O)
- **CPU overhead**: 1 check per instruction cycle
- **Interrupt latency**: No impact (no interrupts generated)
- **Code size**: Minimal (~100 bytes for register access)

## Hardware Details

**Clock source**: CPU instruction cycles (not wall-clock time)

**Counter width**: 32 bits (0 to 4,294,967,295)

**Maximum timeout**: 2^32 cycles (~4.3 seconds at 1 GHz)

**Minimum timeout**: 1 cycle (not practical)

**Reset delay**: Immediate (same cycle as timeout)

## Comparison with Real Hardware

| Feature | This Implementation | STM32 IWDG | NXP Kinetis WDOG |
|---------|-------------------|------------|------------------|
| Timeout range | 1 to 2^32 cycles | 1ms to 32s | 256 cycles to inf |
| Prescaler | No | Yes (4-256) | Yes |
| Window mode | No | No | Yes |
| Interrupt | No | No | Optional |
| Freeze on debug | No | Optional | Yes |
| Independence | No | Yes (separate clock) | No |

## Future Enhancements

Potential improvements (not yet implemented):

1. **Prescaler**: Add configurable clock divider
2. **Window mode**: Minimum and maximum timeout
3. **Interrupt generation**: Warning before reset
4. **Debug freeze**: Stop counting during debugger breaks
5. **Multiple instances**: Independent watchdogs
6. **Real-time clock**: Wall-clock based timeout

## Source Files

- **Specification**: `src/riscv-watchdog.ads` (68 lines)
- **Implementation**: `src/riscv-watchdog.adb` (148 lines)
- **Integration**: `src/riscv-memory.adb`, `src/riscv-cpu.adb`
- **Test program**: `programs/watchdog-test.c` (219 lines)
- **Configuration**: `src/riscv-config.adb` (qemu-virt profile)

## References

- [Watchdog Timer Wikipedia](https://en.wikipedia.org/wiki/Watchdog_timer)
- [STM32 IWDG Documentation](https://www.st.com/resource/en/reference_manual/rm0008-stm32f101xx-stm32f102xx-stm32f103xx-stm32f105xx-and-stm32f107xx-advanced-armbased-32bit-mcus-stmicroelectronics.pdf)
- [Embedded System Watchdog Best Practices](https://embeddedartistry.com/blog/2020/04/13/firmware-watchdog-best-practices/)

## License

Same as main project (MIT License).

## Version History

- **v1.0** (2026-02-15): Initial implementation
  - Basic watchdog functionality
  - Timeout and feed mechanism
  - Reset flag support
  - Auto-disable on timeout
  - Integrated with CPU reset
