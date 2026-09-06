# DMA Controller Peripheral

## Overview

The Direct Memory Access (DMA) Controller is a hardware peripheral that enables high-performance bulk data transfers without CPU intervention. It can copy data between memory regions or between peripherals and memory while the CPU continues executing other tasks.

**Phase:** 5A.3 - Real-Time Features
**Status:** Complete and functional
**Base Address:** 0x10060000 (configurable)
**Channels:** 4 independent channels
**Purpose:** High-performance data transfers, reduced CPU overhead

## Key Features

- **4 independent channels**: Concurrent transfers on different channels
- **Memory-to-memory transfers**: Fast block copy operations
- **Configurable addressing**: Source/destination increment or fixed
- **Transfer size**: Byte-level granularity
- **Status flags**: BUSY, DONE, ERROR tracking
- **Interrupt support**: Optional interrupt on completion (flag only, no interrupt line)
- **Non-blocking**: CPU can continue executing while DMA works
- **Zero-copy**: Direct memory access without CPU involvement

## Memory Map

**Base Address**: 0x10060000

Each channel occupies 32 bytes (0x20), with the following register layout:

### Channel 0 (Base + 0x00)
| Offset | Register | Access | Description |
|--------|----------|--------|-------------|
| 0x00 | CH0_SRC | R/W | Source address |
| 0x04 | CH0_DST | R/W | Destination address |
| 0x08 | CH0_COUNT | R/W | Transfer count (bytes) |
| 0x0C | CH0_CTRL | R/W | Control register |
| 0x10 | CH0_STATUS | R/W1C | Status register |

### Channel 1 (Base + 0x20)
Same layout as Channel 0, offset by 0x20

### Channel 2 (Base + 0x40)
Same layout as Channel 0, offset by 0x40

### Channel 3 (Base + 0x60)
Same layout as Channel 0, offset by 0x60

### Register Descriptions

#### CH_SRC (0x00) - Source Address Register

**Read/Write**: Full 32-bit address

**Purpose**: Starting address for data source

**Behavior**:
- If `SRC_INC` bit is set: Address increments after each byte transferred
- If `SRC_INC` bit is clear: Address remains fixed (useful for peripheral reads)

#### CH_DST (0x04) - Destination Address Register

**Read/Write**: Full 32-bit address

**Purpose**: Starting address for data destination

**Behavior**:
- If `DST_INC` bit is set: Address increments after each byte transferred
- If `DST_INC` bit is clear: Address remains fixed (useful for peripheral writes)

#### CH_COUNT (0x08) - Transfer Count Register

**Read/Write**: Number of bytes to transfer

**Range**: 0 to 2^32-1 bytes

**Behavior**:
- Decrements by 1 for each byte transferred
- When reaches 0, transfer is complete
- Reading shows remaining bytes

#### CH_CTRL (0x0C) - Control Register

| Bit | Name | Access | Description |
|-----|------|--------|-------------|
| 0 | ENABLE | R/W | Enable channel (1=enabled, 0=disabled) |
| 1 | START | R/W | Start transfer (auto-clears when done) |
| 2 | INT_EN | R/W | Interrupt enable (sets flag in STATUS) |
| 3 | SRC_INC | R/W | Increment source address (1=yes, 0=no) |
| 4 | DST_INC | R/W | Increment destination address (1=yes, 0=no) |
| 6:5 | XFER_SIZE | R/W | Transfer size (reserved, currently byte-only) |
| 31:7 | - | - | Reserved (read as 0) |

**ENABLE**: Must be set before starting transfer.

**START**: Write 1 to begin transfer. Automatically clears when transfer completes or on error.

**INT_EN**: If set, the DONE flag will indicate an interrupt should be generated (note: actual interrupt delivery not implemented).

**SRC_INC/DST_INC**: Control address increment behavior.

#### CH_STATUS (0x10) - Status Register

| Bit | Name | Access | Description |
|-----|------|--------|-------------|
| 0 | BUSY | R | Transfer in progress (1=busy, 0=idle) |
| 1 | DONE | R/W1C | Transfer complete (write 1 to clear) |
| 2 | ERROR | R/W1C | Transfer error occurred (write 1 to clear) |
| 31:3 | - | - | Reserved (read as 0) |

**BUSY**: Read-only. Set by hardware when transfer is active.

**DONE**: Set by hardware when transfer completes successfully. Write 1 to clear.

**ERROR**: Set by hardware if memory access fails. Write 1 to clear.

## Implementation Details

### Hardware Implementation

**Files**:
- `src/riscv-dma.ads` - Ada specification (106 lines)
- `src/riscv-dma.adb` - Ada implementation (264 lines)

**State Structure**:
```ada
type DMA_Channel is record
   Source_Addr    : Word := 0;
   Dest_Addr      : Word := 0;
   Count          : Word := 0;
   Initial_Count  : Word := 0;
   Control        : Byte := 0;
   Status         : Byte := 0;
   Current_Src    : Word := 0;  -- Working source pointer
   Current_Dst    : Word := 0;  -- Working destination pointer
end record;

type DMA_State is record
   Base_Address   : Memory_Address;
   Enabled        : Boolean := False;
   Channels       : DMA_Channel_Array;  -- 4 channels
end record;
```

### Transfer Processing

DMA transfers are processed **every 10 CPU cycles** for performance:

```ada
-- In CPU execution loop
if Cycles mod 10 = 0 then
   DMA_Complete := Memory.DMA_Process (Mem);
end if;
```

**Process Algorithm** (per channel):
```ada
function Process (DMA : in out DMA_State) return Boolean is
begin
   for each channel loop
      if channel is enabled and busy and count > 0 then
         -- Read one byte from source
         Memory_Read(Current_Src, Data, Success);

         if Success then
            -- Write one byte to destination
            Memory_Write(Current_Dst, Data, Success);

            if Success then
               -- Update addresses if increment enabled
               if SRC_INC then Current_Src := Current_Src + 1;
               if DST_INC then Current_Dst := Current_Dst + 1;

               -- Decrement counter
               Count := Count - 1;

               -- Check if complete
               if Count = 0 then
                  Status := DONE;
                  Control := Control and not START;
               end if;
            else
               -- Write error
               Status := ERROR;
            end if;
         else
            -- Read error
            Status := ERROR;
         end if;
      end if;
   end loop;
end Process;
```

### Transfer Rate

**Rate**: 1 byte per 10 CPU cycles

**Example**:
- 1 MHz CPU (1,000,000 Hz)
- Transfer rate: 100,000 bytes/second (~97.7 KB/s)
- 1 KB transfer: ~10 ms

**Comparison**:
- CPU memcpy (optimized): ~500,000 bytes/second
- DMA benefit: CPU is free during transfer

## How to Use

### C Programming Interface

```c
// DMA Controller base
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
// ... etc

// Control bits
#define CTRL_ENABLE    (1 << 0)
#define CTRL_START     (1 << 1)
#define CTRL_INT_EN    (1 << 2)
#define CTRL_SRC_INC   (1 << 3)
#define CTRL_DST_INC   (1 << 4)

// Status bits
#define STATUS_BUSY    (1 << 0)
#define STATUS_DONE    (1 << 1)
#define STATUS_ERROR   (1 << 2)
```

### Basic Memory-to-Memory Copy

```c
void dma_memcpy(void *dest, const void *src, size_t len) {
    // Configure DMA channel 0
    CH0_SRC = (uint32_t)src;
    CH0_DST = (uint32_t)dest;
    CH0_COUNT = len;

    // Enable with source and destination increment
    CH0_CTRL = CTRL_ENABLE | CTRL_SRC_INC | CTRL_DST_INC;

    // Start transfer
    CH0_CTRL |= CTRL_START;

    // Wait for completion
    while (CH0_STATUS & STATUS_BUSY) {
        // CPU can do other work here
    }

    // Check result
    if (CH0_STATUS & STATUS_DONE) {
        printf("Transfer complete!\n");
        CH0_STATUS = STATUS_DONE;  // Clear flag
    } else if (CH0_STATUS & STATUS_ERROR) {
        printf("Transfer error!\n");
        CH0_STATUS = STATUS_ERROR;  // Clear flag
    }
}
```

### Non-Blocking Transfer

```c
// Start transfer without waiting
void dma_start_transfer(uint8_t *dest, uint8_t *src, size_t len) {
    CH0_SRC = (uint32_t)src;
    CH0_DST = (uint32_t)dest;
    CH0_COUNT = len;
    CH0_CTRL = CTRL_ENABLE | CTRL_SRC_INC | CTRL_DST_INC | CTRL_START;
}

// Check if transfer is complete
bool dma_is_complete(void) {
    return (CH0_STATUS & STATUS_DONE) != 0;
}

// Usage
int main(void) {
    uint8_t buffer_a[1024];
    uint8_t buffer_b[1024];

    // Start DMA transfer
    dma_start_transfer(buffer_b, buffer_a, 1024);

    // Do other work while DMA transfers
    process_data();
    calculate_results();

    // Check if DMA is done
    if (dma_is_complete()) {
        printf("DMA finished!\n");
        CH0_STATUS = STATUS_DONE;
    }

    return 0;
}
```

### Memory Fill (Fixed Source)

```c
void dma_memset(void *dest, uint8_t value, size_t len) {
    static uint8_t fill_value;
    fill_value = value;

    // Configure with fixed source (no SRC_INC)
    CH0_SRC = (uint32_t)&fill_value;
    CH0_DST = (uint32_t)dest;
    CH0_COUNT = len;

    // Start with DST_INC only (SRC fixed)
    CH0_CTRL = CTRL_ENABLE | CTRL_DST_INC | CTRL_START;

    while (CH0_STATUS & STATUS_BUSY);

    if (CH0_STATUS & STATUS_DONE) {
        CH0_STATUS = STATUS_DONE;
    }
}
```

### Multiple Concurrent Transfers

```c
void concurrent_transfers(void) {
    uint8_t src1[256], src2[256];
    uint8_t dst1[256], dst2[256];

    // Configure channel 0
    CH0_SRC = (uint32_t)src1;
    CH0_DST = (uint32_t)dst1;
    CH0_COUNT = 256;
    CH0_CTRL = CTRL_ENABLE | CTRL_SRC_INC | CTRL_DST_INC;

    // Configure channel 1
    CH1_SRC = (uint32_t)src2;
    CH1_DST = (uint32_t)dst2;
    CH1_COUNT = 256;
    CH1_CTRL = CTRL_ENABLE | CTRL_SRC_INC | CTRL_DST_INC;

    // Start both simultaneously
    CH0_CTRL |= CTRL_START;
    CH1_CTRL |= CTRL_START;

    // Wait for both to complete
    while ((CH0_STATUS & STATUS_BUSY) || (CH1_STATUS & STATUS_BUSY)) {
        // Both transfers happening in parallel
    }

    // Clear completion flags
    CH0_STATUS = STATUS_DONE;
    CH1_STATUS = STATUS_DONE;
}
```

### Peripheral-to-Memory Transfer

```c
#define UART_RX_FIFO  0x10000000

void dma_uart_receive(uint8_t *buffer, size_t len) {
    // Fixed source (UART RX register)
    // Incrementing destination (buffer)
    CH0_SRC = UART_RX_FIFO;
    CH0_DST = (uint32_t)buffer;
    CH0_COUNT = len;

    // No SRC_INC (peripheral register doesn't move)
    CH0_CTRL = CTRL_ENABLE | CTRL_DST_INC | CTRL_START;

    while (CH0_STATUS & STATUS_BUSY);
}
```

## Performance Optimization

### 1. Use DMA for Large Transfers

```c
// Good: Large block (DMA overhead worthwhile)
if (size >= 64) {
    dma_memcpy(dest, src, size);
} else {
    // Bad for small transfers (overhead > benefit)
    memcpy(dest, src, size);
}
```

**Threshold**: DMA beneficial for transfers >=64 bytes

### 2. Overlap Computation and Transfer

```c
// Prepare next buffer while DMA transfers current
void double_buffer_processing(void) {
    uint8_t buffers[2][1024];
    int current = 0;

    while (has_data()) {
        // Start DMA on current buffer
        dma_start_transfer(output, buffers[current], 1024);

        // Process next buffer while DMA runs
        current = !current;
        process_data(buffers[current]);

        // Wait for DMA to finish
        while (!dma_is_complete());
        CH0_STATUS = STATUS_DONE;
    }
}
```

### 3. Use Multiple Channels

```c
// Process multiple data streams simultaneously
void multi_stream_processing(void) {
    // Channel 0: Audio stream
    CH0_SRC = (uint32_t)audio_in;
    CH0_DST = (uint32_t)audio_out;
    CH0_COUNT = 4096;
    CH0_CTRL = CTRL_ENABLE | CTRL_SRC_INC | CTRL_DST_INC | CTRL_START;

    // Channel 1: Video stream (parallel)
    CH1_SRC = (uint32_t)video_in;
    CH1_DST = (uint32_t)video_out;
    CH1_COUNT = 65536;
    CH1_CTRL = CTRL_ENABLE | CTRL_SRC_INC | CTRL_DST_INC | CTRL_START;

    // Both happen concurrently!
}
```

## Known Limitations

### 1. Byte-Only Transfers

**Issue**: Only byte-granularity transfers, no halfword/word optimization.

**Impact**:
- Slower than optimal for word-aligned data
- Cannot exploit 32-bit bus width

**Workaround**: Future enhancement (XFER_SIZE field reserved).

### 2. No Scatter-Gather

**Issue**: Cannot transfer to/from multiple non-contiguous regions in one operation.

**Impact**: Need multiple DMA operations for fragmented data.

**Example**:
```c
// Can't do this in one DMA operation:
struct scatter_gather {
    void *addr1; size_t len1;
    void *addr2; size_t len2;
    void *addr3; size_t len3;
};

// Must do multiple transfers
dma_transfer(dest, sg->addr1, sg->len1);
dma_transfer(dest + sg->len1, sg->addr2, sg->len2);
dma_transfer(dest + sg->len1 + sg->len2, sg->addr3, sg->len3);
```

### 3. No Hardware Handshaking

**Issue**: DMA doesn't coordinate with peripherals via hardware handshake signals.

**Impact**:
- Cannot automatically trigger on peripheral ready
- Software must poll peripheral status

**Workaround**: Use software polling loops.

### 4. No 2D Transfers

**Issue**: Cannot configure stride/pitch for 2D block transfers.

**Impact**: Copying image sub-regions requires multiple transfers.

**Example**:
```c
// Want to copy 100x100 region from 1920x1080 image
// Must do 100 separate row transfers
for (int y = 0; y < 100; y++) {
    dma_transfer(dest + y*100,
                 src + y*1920,
                 100);
}
```

### 5. Fixed Processing Rate

**Issue**: DMA processes at fixed rate (1 byte/10 cycles).

**Impact**:
- Cannot burst faster than this
- Slower than some real hardware DMA

**Note**: This is by design for simulation realism.

### 6. No Priority Levels

**Issue**: All channels have equal priority.

**Impact**: High-priority transfers cannot preempt lower priority.

**Workaround**: Use different channels strategically.

### 7. Interrupt Flag Only

**Issue**: INT_EN sets a flag but doesn't generate actual CPU interrupt.

**Impact**: Must poll DONE flag, cannot use interrupt-driven I/O.

**Workaround**: Use polling or periodic checking.

## Best Practices

### 1. Check Alignment

```c
void dma_transfer_safe(void *dest, void *src, size_t len) {
    // Check 4-byte alignment for best performance
    if (((uintptr_t)dest & 3) || ((uintptr_t)src & 3)) {
        printf("Warning: Unaligned DMA transfer\n");
    }

    dma_memcpy(dest, src, len);
}
```

### 2. Always Check Status

```c
void dma_transfer_checked(void *dest, void *src, size_t len) {
    CH0_SRC = (uint32_t)src;
    CH0_DST = (uint32_t)dest;
    CH0_COUNT = len;
    CH0_CTRL = CTRL_ENABLE | CTRL_SRC_INC | CTRL_DST_INC | CTRL_START;

    uint32_t timeout = 1000000;
    while ((CH0_STATUS & STATUS_BUSY) && timeout--) {
        if (timeout == 0) {
            printf("DMA timeout!\n");
            return;
        }
    }

    if (CH0_STATUS & STATUS_ERROR) {
        printf("DMA error at src=0x%x, dst=0x%x\n",
               CH0_SRC, CH0_DST);
        CH0_STATUS = STATUS_ERROR;
        return;
    }

    CH0_STATUS = STATUS_DONE;
}
```

### 3. Clear Flags After Use

```c
// Always clear status flags
if (CH0_STATUS & STATUS_DONE) {
    CH0_STATUS = STATUS_DONE;  // Write 1 to clear
}
if (CH0_STATUS & STATUS_ERROR) {
    CH0_STATUS = STATUS_ERROR;  // Write 1 to clear
}
```

### 4. Disable When Not In Use

```c
void dma_shutdown(void) {
    // Disable all channels
    CH0_CTRL = 0;
    CH1_CTRL = 0;
    CH2_CTRL = 0;
    CH3_CTRL = 0;

    // Clear any pending flags
    CH0_STATUS = 0xFF;
    CH1_STATUS = 0xFF;
    CH2_STATUS = 0xFF;
    CH3_STATUS = 0xFF;
}
```

## Common Use Cases

### 1. Buffer Management

```c
typedef struct {
    uint8_t *buffer;
    size_t size;
    volatile bool ready;
} dma_buffer_t;

void dma_buffer_copy(dma_buffer_t *dst, dma_buffer_t *src) {
    dst->ready = false;

    CH0_SRC = (uint32_t)src->buffer;
    CH0_DST = (uint32_t)dst->buffer;
    CH0_COUNT = src->size;
    CH0_CTRL = CTRL_ENABLE | CTRL_SRC_INC | CTRL_DST_INC | CTRL_START;

    while (CH0_STATUS & STATUS_BUSY);
    CH0_STATUS = STATUS_DONE;

    dst->ready = true;
}
```

### 2. Data Streaming

```c
#define STREAM_BUFFER_SIZE 4096

void stream_processor(void) {
    uint8_t input[STREAM_BUFFER_SIZE];
    uint8_t output[STREAM_BUFFER_SIZE];

    while (streaming) {
        // DMA input from peripheral
        CH0_SRC = PERIPHERAL_INPUT;
        CH0_DST = (uint32_t)input;
        CH0_COUNT = STREAM_BUFFER_SIZE;
        CH0_CTRL = CTRL_ENABLE | CTRL_DST_INC | CTRL_START;

        // Wait for input
        while (CH0_STATUS & STATUS_BUSY);
        CH0_STATUS = STATUS_DONE;

        // Process data (CPU work)
        process_stream(output, input, STREAM_BUFFER_SIZE);

        // DMA output to peripheral
        CH1_SRC = (uint32_t)output;
        CH1_DST = PERIPHERAL_OUTPUT;
        CH1_COUNT = STREAM_BUFFER_SIZE;
        CH1_CTRL = CTRL_ENABLE | CTRL_SRC_INC | CTRL_START;

        while (CH1_STATUS & STATUS_BUSY);
        CH1_STATUS = STATUS_DONE;
    }
}
```

### 3. Memory Initialization

```c
void dma_zero_memory(void *addr, size_t len) {
    static const uint8_t zero = 0;

    CH0_SRC = (uint32_t)&zero;
    CH0_DST = (uint32_t)addr;
    CH0_COUNT = len;
    CH0_CTRL = CTRL_ENABLE | CTRL_DST_INC | CTRL_START;  // Fixed source

    while (CH0_STATUS & STATUS_BUSY);
    CH0_STATUS = STATUS_DONE;
}
```

## Test Program

**Location**: `programs/dma-test.c` (340 lines)

**Tests**:
1. Simple 64-byte memory-to-memory transfer
2. Large 256-byte bulk transfer
3. Fixed source (memory fill operation)
4. Concurrent transfers on 2 channels

**Run**:
```bash
make -C programs run-dma-test
```

**Expected Output**:
```
Test 1: Simple Memory-to-Memory Transfer
    Test 1 PASSED

Test 2: Large Transfer (256 bytes)
    Test 2 PASSED

Test 3: Fixed Source (Memory Fill)
    Test 3 PASSED

Test 4: Concurrent Transfers (2 channels)
    Test 4 PASSED
```

## Debugging

### Debug Macros

```c
#define DMA_DEBUG 1

#if DMA_DEBUG
#define DMA_LOG(fmt, ...) printf("[DMA] " fmt "\n", ##__VA_ARGS__)
#else
#define DMA_LOG(fmt, ...)
#endif

void dma_transfer_debug(void *dest, void *src, size_t len) {
    DMA_LOG("Starting transfer: src=0x%x, dst=0x%x, len=%u",
            (uint32_t)src, (uint32_t)dest, len);

    dma_memcpy(dest, src, len);

    DMA_LOG("Transfer complete");
}
```

### Status Monitoring

```c
void print_dma_status(int channel) {
    volatile uint32_t *ctrl, *status;

    switch (channel) {
        case 0: ctrl = &CH0_CTRL; status = &CH0_STATUS; break;
        case 1: ctrl = &CH1_CTRL; status = &CH1_STATUS; break;
        case 2: ctrl = &CH2_CTRL; status = &CH2_STATUS; break;
        case 3: ctrl = &CH3_CTRL; status = &CH3_STATUS; break;
        default: return;
    }

    printf("DMA Channel %d:\n", channel);
    printf("  Enabled: %s\n", (*ctrl & CTRL_ENABLE) ? "YES" : "NO");
    printf("  Busy: %s\n", (*status & STATUS_BUSY) ? "YES" : "NO");
    printf("  Done: %s\n", (*status & STATUS_DONE) ? "YES" : "NO");
    printf("  Error: %s\n", (*status & STATUS_ERROR) ? "YES" : "NO");
}
```

## Performance Benchmarks

Based on test program results:

| Transfer Size | DMA Time (cycles) | CPU Time (est.) | DMA Advantage |
|---------------|------------------|-----------------|---------------|
| 64 bytes | ~640 | ~640 | CPU free |
| 256 bytes | ~2,560 | ~2,560 | CPU free |
| 1 KB | ~10,240 | ~10,240 | CPU free |
| 4 KB | ~40,960 | ~40,960 | CPU free |

**Key Benefit**: CPU can perform other tasks during DMA transfer!

## Integration with RTOS

### FreeRTOS DMA Task

```c
void dma_task(void *params) {
    dma_request_t request;

    while (1) {
        // Wait for DMA request from queue
        xQueueReceive(dma_queue, &request, portMAX_DELAY);

        // Start DMA
        CH0_SRC = request.src;
        CH0_DST = request.dst;
        CH0_COUNT = request.len;
        CH0_CTRL = CTRL_ENABLE | CTRL_SRC_INC | CTRL_DST_INC | CTRL_START;

        // Wait for completion
        while (CH0_STATUS & STATUS_BUSY) {
            vTaskDelay(1);  // Yield to other tasks
        }

        // Notify completion
        xSemaphoreGive(request.complete_sem);
    }
}
```

## Source Files

- **Specification**: `src/riscv-dma.ads` (106 lines)
- **Implementation**: `src/riscv-dma.adb` (264 lines)
- **Test program**: `programs/dma-test.c` (340 lines)
- **Integration**: `src/riscv-memory.adb`, `src/riscv-cpu.adb`, `src/riscv-config.adb`

## Comparison with Real Hardware

| Feature | This Implementation | STM32 DMA | i.MX RT DMA |
|---------|-------------------|-----------|-------------|
| Channels | 4 | 7-16 | 32 |
| Transfer size | Byte only | Byte/Half/Word | Byte/Half/Word/Burst |
| Addressing | Inc/Fixed | Inc/Fixed/Dec | Inc/Fixed/Dec |
| Scatter-gather | No | No | Yes |
| 2D transfers | No | No | Yes |
| Priority | Equal | 4 levels | 16 levels |
| Interrupts | Flag only | Full | Full |

## Future Enhancements

Potential improvements (not yet implemented):

1. **Word/Halfword transfers**: Faster for aligned data
2. **Scatter-gather**: Single operation for fragmented data
3. **2D block transfers**: Stride/pitch configuration
4. **Priority levels**: Preemption between channels
5. **Hardware handshaking**: Peripheral-triggered DMA
6. **Circular mode**: Auto-restart for continuous streaming
7. **Linked lists**: Chain multiple transfers
8. **Real interrupts**: CPU interrupt on completion

## References

- [ARM DMA Controller Documentation](https://developer.arm.com/documentation/ddi0196/g/programmers-model/about-the-programmers-model)
- [STM32 DMA Programming Manual](https://www.st.com/resource/en/application_note/an4031-using-the-stm32f2-stm32f4-and-stm32f7-series-dma-controller-stmicroelectronics.pdf)
- [DMA Best Practices](https://interrupt.memfault.com/blog/dma-best-practices)

## License

Same as main project (MIT License).

## Version History

- **v1.0** (2026-02-15): Initial implementation
  - 4 independent channels
  - Memory-to-memory transfers
  - Configurable addressing modes
  - Status flags (BUSY, DONE, ERROR)
  - Concurrent multi-channel support
  - Test program with 4 comprehensive tests
