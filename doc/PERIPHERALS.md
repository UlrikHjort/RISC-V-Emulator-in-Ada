# Peripheral Reference

Complete guide to all peripheral features: UART, CLINT, PLIC, GPIO, SPI Flash,
I2C, Timer, Watchdog, DMA, and VirtIO Block.

## GPIO (General Purpose I/O)

**Base:** 0x10010000 | **Size:** 32 bytes

Registers: INPUT(0x00), OUTPUT(0x04), DIRECTION(0x08), INT_EN(0x0C), INT_FLAG(0x10), INT_TYPE(0x14), PULL_EN(0x18), PULL_DIR(0x1C)

C API (gpio.h):
- gpio_set_direction(pin, GPIO_DIR_INPUT/OUTPUT)
- gpio_write_pin(pin, GPIO_LOW/HIGH), gpio_read_pin(pin), gpio_toggle_pin(pin)
- gpio_set_pull(pin, enable, GPIO_PULL_UP/DOWN)
- gpio_enable/disable_interrupt(pin, GPIO_INT_LEVEL/EDGE)
- gpio_clear_interrupt(pin), gpio_interrupt_pending(pin)

Test Programs: gpio-basic.bin, gpio-interrupt.bin, gpio-input.bin

## SPI Flash Controller

**Base:** 0x10020000 | **Size:** 16 bytes | **Flash:** 64KB

Registers: CTRL(0x00), STATUS(0x04), DATA(0x08), PRESCALE(0x0C)

Commands: READ(0x03), PAGE_PROGRAM(0x02), READ_ID(0x9F), READ_STATUS(0x05), WRITE_ENABLE(0x06)

C API (spi.h):
- spi_init(), spi_cs_active/inactive(), spi_transfer(data)
- spi_flash_read_id(id), spi_flash_read(addr, buf, len)
- spi_flash_write_enable(), spi_flash_write(addr, buf, len)

Test Program: spi-flash-test.bin

## UART with Interrupts

**Base:** 0x10000000 | **Registers:** THR/RBR(0x00), IER(0x01), IIR(0x02), LSR(0x05)

IER Bits: RDA(0x01), THRE(0x02)
IIR: NO_INT(0x01), INT_ID(bits 1-3): THR(0x02), RDA(0x04)
Priority: RDA > THR

Test Program: uart-interrupt.bin

## I2C Controller

**Base:** 0x10030000 | **Size:** 20 bytes | **Devices:** 3 simulated

Registers: CTRL(0x00), STATUS(0x04), DATA(0x08), PRESCALE(0x0C), SLAVE_ADDR(0x10)

**CTRL Bits:** ENABLE(0x01), START(0x02), STOP(0x04), READ(0x08), WRITE(0x10), ACK(0x20), FAST_MODE(0x40)

**STATUS Bits:** BUSY(0x01), ACK_RECV(0x02), NACK_RECV(0x04), ARB_LOST(0x08), READY(0x10)

**Simulated Devices:**
- Temperature Sensor (TMP102-like) @ 0x48: Returns 25degC (0x0190), 12-bit resolution
- Accelerometer (ADXL345-like) @ 0x1D: Device ID 0xE5, 3-axis data (Z=1g)
- EEPROM (24C02-like) @ 0x50: 256 bytes, read/write persistent storage

C API (i2c.h):
- i2c_init(), i2c_start/restart/stop(addr)
- i2c_write(data), i2c_read_ack/nack()
- i2c_busy(), i2c_wait(), i2c_set_fast_mode(enable)
- Addresses: I2C_ADDR_TEMP, I2C_ADDR_ACCEL, I2C_ADDR_EEPROM

Test Program: i2c-test.bin (8 comprehensive tests)

CLI Commands:
- i2c scan - Scan bus for devices
- i2c temp - Read temperature sensor
- i2c accel - Read accelerometer
- i2c eeprom <addr> [data] - EEPROM operations

## Hardware Timers/PWM

**Base:** 0x10040000 | **Size:** 80 bytes | **Channels:** 4

Global Registers: PRESCALE(0x00), INT_STATUS(0x04), INT_ENABLE(0x08)

Per-Channel Registers (offset: 0x10 + channel*0x10):
- COUNTER(0x00) - 32-bit counter value
- COMPARE(0x04) - 32-bit compare/match value
- CTRL(0x08) - Control bits
- OUTPUT(0x0C) - PWM duty cycle (0-255)

**CTRL Bits:** ENABLE(0x01), PWM_MODE(0x02), AUTO_RELOAD(0x04), INT_ENABLE(0x08), OUTPUT_HIGH(0x10)

**Features:**
- Timer mode: Count to compare value, optional auto-reload
- PWM mode: Generate PWM signals with 0-255 duty cycle
- Interrupts: Per-channel compare match interrupts
- Prescaler: Global 1-255 clock division for all channels

C API (timer.h):
- timer_init(), timer_set_prescale(val)
- timer_set_counter/compare(ch, val), timer_get_counter/compare(ch)
- timer_enable_channel/set_pwm_mode/set_auto_reload/enable_interrupt(ch, enable)
- timer_set/get_output(ch, duty)
- timer_get/clear_interrupt(ch), timer_delay(ticks)

Test Program: timer-test.bin (11 comprehensive tests)

CLI Commands:
- timer set <ch> <val> - Set compare value
- timer pwm <ch> <duty> - Set PWM duty (0-255 = 0-100%)
- timer start/stop <ch> - Enable/disable channel
- timer status [ch] - Show detailed status
- timer prescale <val> - Set clock divider

## Demo Applications

**sensor-monitor.bin** - Real-world I2C monitoring:
- Reads temperature + accelerometer every second
- Timer-based sampling, GPIO heartbeat LED
- Displays real-time sensor data and statistics

**pwm-fade.bin** - LED fading with multiple patterns:
- 4 PWM channels with different animations
- Patterns: breathing, pulse, blink, ramp
- Visual demonstration of PWM capabilities

## Important: Peripheral Enabled Check

Every peripheral's `Is_*_Address()` function **must** check the `Enabled` flag before
checking the address range. Failure to do so causes a subtle but critical bug:

When a peripheral state record is freshly allocated with `new`, all numeric fields
(including `Base_Address`) default to 0. If the enabled check is missing, a disabled
peripheral with `Base_Address=0` will intercept memory reads/writes to low addresses -
silently swallowing program code written to address 0x0.

**Safe pattern:**
```ada
function Is_My_Address (Dev : My_State; Address : Memory_Address) return Boolean is
begin
   return Dev.Enabled and then
          Address >= Dev.Base_Address and then
          Address < Dev.Base_Address + MY_SIZE;
end Is_My_Address;
```

This pattern is already in use for all built-in peripherals (UART, CLINT, GPIO, SPI,
I2C, Timer, Watchdog, DMA). Do not omit it for any new peripherals.

## Build & Run

```bash
# Build all peripheral test programs
cd programs && make gpio-basic.bin spi-flash-test.bin uart-interrupt.bin i2c-test.bin timer-test.bin

# Build demo applications
make sensor-monitor.bin pwm-fade.bin

# Build interactive CLI
make cli.bin

# Run examples
make run-i2c-test          # I2C device tests
make run-timer-test        # Timer/PWM tests
make run-sensor-monitor    # I2C sensor monitoring demo
make run-pwm-fade          # PWM LED fading demo
make run-cli               # Interactive command shell
```

## qemu-virt Profile

All peripherals enabled (6 total):
- UART @ 0x10000000 - Serial console with interrupts
- CLINT @ 0x02000000 - Core Local Interruptor
- UART  @ 0x10000000 - 16550-compatible, PTY or stdio backend
- CLINT @ 0x02000000 - mtime/mtimecmp/msip, software + timer interrupts
- PLIC  @ 0x0C000000 - 32 sources, 2 contexts (M-mode/S-mode)
- GPIO  @ 0x10010000 - 32 pins with interrupts
- SPI   @ 0x10020000 - SPI flash controller (64KB)
- I2C   @ 0x10030000 - I2C controller with 3 simulated devices
- Timer @ 0x10040000 - 4-channel timer/PWM
- Watchdog @ 0x10050000 - configurable timeout reset
- DMA   @ 0x10060000 - 4-channel memory copy
- VirtIO Block @ 0x10001000 - MMIO v2, 512KB disk, PLIC source 8

See doc/C-LIBRARY.md, doc/DEBUGGING-ADVANCED.md for details.

## PLIC (Platform-Level Interrupt Controller)

**Base:** 0x0C000000 | **Size:** 4MB (covers all register regions)

### Register Map

| Offset | Name | R/W | Description |
|--------|------|-----|-------------|
| 0x000000 + src*4 | priority[src] | R/W | Priority level 0-7 (0 = disabled) |
| 0x001000 | pending[0] | R | Pending bits, one per source (bit 0 always 0) |
| 0x002000 + ctx*0x80 | enable[ctx][0] | R/W | Enable bits, one per source |
| 0x200000 + ctx*0x1000 | threshold[ctx] | R/W | Threshold 0-7 |
| 0x200004 + ctx*0x1000 | claim/complete[ctx] | R/W | Claim: returns highest-priority source; Write: complete |

### Source IDs

| Source | ID | Peripheral |
|--------|-----|-----------|
| NONE | 0 | (no interrupt) |
| UART | 1 | UART 16550 |
| GPIO | 2 | GPIO |
| SPI | 3 | SPI |
| I2C | 4 | I2C |
| TIMER | 5 | Hardware timer |
| VIRTIO_BLK | 8 | VirtIO block device |

### Contexts

| Context | ID | Description |
|---------|----|-------------|
| M-mode hart 0 | 0 | Drives MEIP in MIP |
| S-mode hart 0 | 1 | Drives SEIP in MIP |

### Interrupt Flow

1. Peripheral asserts interrupt line
2. `PLIC_Update_Mip` polls lines, calls `Set_Pending(src)`
3. PLIC evaluates: pending & enabled & priority > threshold -> fires context
4. CPU detects MEIP/SEIP in Check_Interrupts -> Trap_Entry
5. ISR: read Claim register -> gets source ID, clears pending
6. ISR handles interrupt, writes source ID to Claim (Complete)

## VirtIO MMIO Block Device

**Base:** 0x10001000 | **Size:** 4KB | **Disk:** 1024 sectors * 512 bytes

VirtIO transport version 2 (modern). Queue processing is **synchronous**:
the emulator processes the virtqueue when the driver writes `QueueNotify`.

### Key Registers

| Offset | Name | R/W | Value |
|--------|------|-----|-------|
| 0x000 | MagicValue | R | 0x74726976 ("virt") |
| 0x004 | Version | R | 2 |
| 0x008 | DeviceID | R | 2 (block) |
| 0x034 | QueueNumMax | R | 16 |
| 0x050 | QueueNotify | W | Write any value to kick queue |
| 0x060 | InterruptStatus | R | Bit 0: used-buffer notification |
| 0x064 | InterruptACK | W | Write to clear InterruptStatus |
| 0x070 | Status | R/W | Device status byte (0 = reset) |
| 0x100 | config.capacity (lo) | R | 1024 (sectors) |

### Negotiation Sequence

```c
VREG(REG_STATUS) = 0;                          // reset
VREG(REG_STATUS) = ACKNOWLEDGE | DRIVER;       // announce driver
VREG(REG_DRV_FEATURES) = 0;                   // accept no optional features
VREG(REG_STATUS) |= FEATURES_OK;              // lock features
// check FEATURES_OK still set
VREG(REG_QUEUE_SEL) = 0;
VREG(REG_QUEUE_NUM) = min(VREG(REG_QUEUE_NUM_MAX), MY_QUEUE_SIZE);
VREG(REG_QUEUE_DESC_LO)  = (uint32_t)desc_table;
VREG(REG_QUEUE_DRIVER_LO) = (uint32_t)avail_ring;
VREG(REG_QUEUE_DEVICE_LO) = (uint32_t)used_ring;
VREG(REG_QUEUE_READY) = 1;
VREG(REG_STATUS) |= DRIVER_OK;
```

### Block Request (3-descriptor chain)

```
desc[0]: header  - addr=&blk_req, len=16, flags=NEXT
desc[1]: data    - addr=buffer,   len=N*512, flags=NEXT|WRITE(for reads)
desc[2]: status  - addr=&status,  len=1,    flags=WRITE
```

`blk_req.type`: 0=read (VIRTIO_BLK_T_IN), 1=write (VIRTIO_BLK_T_OUT)
`blk_req.sector`: 64-bit sector number (0..1023 valid)
`status`: 0=OK, 1=IOERR, 2=UNSUPP (written by device)

