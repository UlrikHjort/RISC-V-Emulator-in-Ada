# Hardware Profiles

Hardware profiles define the memory layout and peripherals for the emulator, allowing simulation of different RISC-V systems.

## Built-in Profiles

### simple (Default)

A minimal configuration suitable for bare-metal test programs.

```
Memory:  1 MB RAM at 0x00000000
UART:    0x10000000
Reset:   0x00000000
Stack:   0x00100000
```

**Use case:** Small programs, educational purposes, quick testing.

```bash
./bin/riscv_emulator program.elf
./bin/riscv_emulator --machine simple program.elf
```

### qemu-virt

Compatible with QEMU's virt machine for RISC-V.

```
Memory:  128 MB RAM at 0x80000000
         64 KB ROM at 0x00001000
UART:    0x10000000
CLINT:   0x02000000
Reset:   0x80000000
Stack:   0x88000000
```

**Use case:** Running images built for QEMU, OS development.

```bash
./bin/riscv_emulator --machine qemu-virt kernel.elf
```

**Note:** Programs must be linked for 0x80000000, not 0x0.

## Listing Available Profiles

```bash
./bin/riscv_emulator --list-machines
```

Output:
```
Available hardware profiles:

  simple
    Memory: 1 MB RAM at 0x00000000
    UART:   0x10000000
    Reset:  0x00000000
    Stack:  0x00100000

  qemu-virt
    Memory: 128 MB RAM at 0x80000000
            64 KB ROM at 0x00001000
    UART:   0x10000000
    CLINT:  0x02000000 (timer)
    Reset:  0x80000000
    Stack:  0x88000000

Custom profiles can be loaded with --config <file>
See profiles/ directory for examples.
```

## Custom Profiles

Create a configuration file with INI-style syntax.

### File Format

```ini
# Comment lines start with #

[profile]
name = my_board

[memory.region_name]
base = 0x00000000
size = 0x10000
type = ram
# access = rwx  (optional, default: rwx)

[peripheral.name]
type = uart16550
base = 0x10000000

[cpu]
reset_vector = 0x00000000
stack_init = 0x00010000
vlen = 128
```

### Sections

#### [profile]

| Key | Description |
|-----|-------------|
| `name` | Profile name (for display) |

#### [memory.NAME]

| Key | Values | Description |
|-----|--------|-------------|
| `base` | Hex address | Base address |
| `size` | Hex size | Size in bytes |
| `type` | `ram`, `rom`, `flash` | Memory type |

- **ram** - Read/write volatile memory
- **rom** - Read-only; a guest store raises a store access fault (mcause 7)
- **flash** - Read-only, same as `rom` (for future programmability)

Permissions follow the `type` key, so a region declared `rom` is genuinely
read-only. The program loader writes through the permission check, so an ELF
or raw image may still populate a `rom` region.

Regions are validated when the profile is applied. A region is rejected, with
a warning naming it, when it:

- has a zero size, or one above 256 MB (`Max_Region_Size`);
- overlaps a region already registered - the first match would silently win
  and part of the second would be unreachable;
- runs past the end of the address space. A region ending *exactly* at 2^32
  (for example base `0xFFF00000`, size `0x100000`) is fine and fully usable.

There is room for 16 regions (`Max_Regions`).

#### [peripheral.NAME]

| Key | Values | Description |
|-----|--------|-------------|
| `type` | `uart16550`, `clint`, `gpio` | Peripheral type |
| `base` | Hex address | Base address |

#### [cpu]

| Key | Default | Description |
|-----|---------|-------------|
| `reset_vector` | 0x0 | Initial PC value |
| `stack_init` | 0x0 | Initial SP value (if non-zero) |
| `vlen` | 128 | Vector register width in bits |

### Example: Embedded Microcontroller

```ini
# profiles/embedded.cfg
[profile]
name = embedded

[memory.flash]
base = 0x00000000
size = 0x20000
type = rom

[memory.sram]
base = 0x20000000
size = 0x8000
type = ram

[peripheral.uart]
type = uart16550
base = 0x40000000

[cpu]
reset_vector = 0x00000000
stack_init = 0x20008000
vlen = 128
```

Usage:
```bash
./bin/riscv_emulator --config profiles/embedded.cfg firmware.bin
```

### Example: Multi-Region System

```ini
# profiles/multi.cfg
[profile]
name = multi-region

[memory.boot]
base = 0x00000000
size = 0x1000
type = rom

[memory.code]
base = 0x00010000
size = 0x40000
type = ram

[memory.data]
base = 0x00100000
size = 0x80000
type = ram

[peripheral.console]
type = uart16550
base = 0x10000000

[peripheral.timer]
type = clint
base = 0x02000000

[peripheral.io]
type = gpio
base = 0x10010000

[cpu]
reset_vector = 0x00000000
stack_init = 0x00180000
```

## Profile Location

Example profiles are in the `profiles/` directory:

```
profiles/
   simple.cfg      # Minimal configuration
   qemu-virt.cfg   # QEMU virt machine
   embedded.cfg    # Microcontroller-style
```

## Programming Notes

### Memory Limits

- Maximum regions: 16
- Maximum region size: 256 MB per region
- Regions can overlap peripherals (peripherals take priority)

### Address Space

Addresses are 32-bit. The emulator checks addresses in this order:

1. UART range
2. CLINT range
3. GPIO range
4. SPI range
5. I2C range
6. Timer range
7. Watchdog range
8. DMA range
9. Memory regions
10. Return "unmapped" error

### Peripheral Initialization

**Important:** All peripherals must have their `Enabled` flag checked before claiming
addresses. When a peripheral state record is allocated but not yet initialized, its
`Base_Address` field defaults to `0x00000000`. Without the enabled check, a disabled
peripheral will incorrectly intercept memory writes to low addresses (including
program code loaded at 0x0), silently dropping data.

All built-in peripherals follow the safe pattern:
```ada
return Peripheral.Enabled and then
       Address >= Peripheral.Base_Address and then
       Address < Peripheral.Base_Address + Peripheral.Size;
```

If you implement a custom peripheral, always include the enabled check.

### Accessing Profile Data

```ada
with RISCV.Config; use RISCV.Config;

-- Get built-in profile
Prof := Get_Profile ("simple");
Prof := Get_Profile ("qemu-virt");

-- Load from file
Load_Profile ("my_profile.cfg", Prof, Success);

-- Apply to memory system
Apply_Profile (Prof, Mem);

-- Access profile data
Put_Line ("Reset: " & Prof.CPU.Reset_Vector'Image);
Put_Line ("Regions: " & Prof.Num_Regions'Image);
```

### Creating Profiles Programmatically

```ada
function My_Profile return Hardware_Profile is
   P : Hardware_Profile;
begin
   P.Name := Pad32 ("custom");
   P.Name_Len := 6;

   -- Memory region
   P.Num_Regions := 1;
   P.Memory_Regions (1).Name := Pad16 ("ram");
   P.Memory_Regions (1).Base := 0;
   P.Memory_Regions (1).Size := 16#100000#;
   P.Memory_Regions (1).Rtype := Memory.RAM;
   P.Memory_Regions (1).Perm := Memory.Permission_RWX;

   -- Peripheral
   P.Num_Peripherals := 1;
   P.Peripherals (1).Ptype := UART_16550;
   P.Peripherals (1).Base := 16#10000000#;

   -- CPU config
   P.CPU.Reset_Vector := 0;
   P.CPU.Stack_Init := 16#100000#;
   P.CPU.VLEN := 128;

   return P;
end My_Profile;
```
