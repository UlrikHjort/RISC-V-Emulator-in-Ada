# RISC-V Emulator User Manual

A RISC-V emulator written in Ada, supporting **RV32IMAFDC + V** plus **RV64IMAFD**
(auto-detected from the ELF class):
- **I** -- Base integer (all 40 instructions), plus **E** (16-register subset, `--rv32e` / `--rv64e`)
- **M** -- Multiply/divide
- **A** -- Atomics (LR/SC, AMO)
- **F/D** -- Single and double precision floating point, plus **Zfh** (half precision)
- **C** -- Compressed instructions
- **V** -- Vector extension (RVV 1.0)
- **Zbb/Zbs/Zba/Zbkc/Zbkx** -- Bit manipulation, **Zicond** -- conditional ops, **Zifencei**

---

## Table of Contents

1. [Building](#building)
2. [Quick Start](#quick-start)
3. [Running Programs](#running-programs)
4. [Hardware Profiles](#hardware-profiles)
5. [Command-Line Reference](#command-line-reference)
6. [Interactive Debugger](#interactive-debugger)
7. [GDB Remote Debugging](#gdb-remote-debugging)
8. [Profiling](#profiling)
9. [Peripherals](#peripherals)
10. [Writing Programs](#writing-programs)
11. [Architecture Tests](#architecture-tests)
12. [Troubleshooting](#troubleshooting)

---

## Building

### Requirements

- GNAT Ada compiler (`gnat` or `gcc-12`)
- RISC-V cross-compiler for building test programs: `riscv32-unknown-elf-gcc`

```bash
# Install on Ubuntu/Debian
sudo apt install gnat
sudo apt install gcc-riscv64-unknown-elf
```

The Debian/Ubuntu package installs the compiler as `riscv64-unknown-elf-gcc`,
while the Makefiles default to the `riscv32-unknown-elf-` prefix. Point them at
what you actually have:

```bash
make -C programs CROSS=riscv64-unknown-elf-
```

Prebuilt tarballs for other distributions, and the sources to build a
toolchain yourself, are upstream at
[riscv-collab/riscv-gnu-toolchain](https://github.com/riscv-collab/riscv-gnu-toolchain).
See [Writing C Programs](doc/WRITING-PROGRAMS.md) for other toolchain sources
and how to check that yours can target RV32.

### Building the Emulator

```bash
make
# Output: bin/riscv_emulator
```

### Building Test Programs

```bash
# Unit tests (test/*.elf)
cd test && make

# Bare-metal demo programs (programs/out/elf/*.elf, programs/out/bin/*.bin)
cd programs && make
```

---

## Quick Start

```bash
# Run a simple ELF
./bin/riscv_emulator test/hello.elf
# -> Hello, World!

# Run with instruction trace
./bin/riscv_emulator -t test/hello.elf

# Run in interactive debugger
./bin/riscv_emulator -d test/hello.elf

# Run a program built for QEMU virt memory layout
./bin/riscv_emulator --machine qemu-virt programs/out/elf/fibonacci.elf
```

---

## Running Programs

### ELF Files

ELF files are auto-detected. The entry point and load address are read from the ELF
header -- no manual address specification needed.

```bash
# Default (uses 1MB RAM at 0x0, UART at 0x10000000)
./bin/riscv_emulator program.elf

# Explicit profile
./bin/riscv_emulator --machine simple program.elf
./bin/riscv_emulator --machine qemu-virt program.elf

# Custom config file
./bin/riscv_emulator --config myboard.cfg program.elf
```

### Raw Binary Files

Binary files require a load/start address in hex:

```bash
# Load binary at address 0 (simple profile)
./bin/riscv_emulator --machine simple program.bin 0

# Load binary at 0x80000000 (qemu-virt)
./bin/riscv_emulator --machine qemu-virt program.bin 80000000
```

### Choosing the Right Profile

| Situation | Correct Invocation |
|---|---|
| Program linked at 0x0 (test/*.elf) | `./bin/riscv_emulator --machine simple program.elf` |
| Program linked at 0x80000000 (programs/out/elf/*.elf) | `./bin/riscv_emulator --machine qemu-virt program.elf` |
| Arch-test compliance testing | `./bin/riscv_emulator --config arch-test/env/arch-test.cfg program.elf` |
| Custom embedded target | `./bin/riscv_emulator --config myboard.cfg program.elf` |

### Expected Test Results

| Test | Return (a0) | Output |
|---|---|---|
| test/simple.elf | 42 | -- |
| test/arithmetic.elf | 11 | -- |
| test/loop.elf | 55 | -- |
| test/fibonacci.elf | 55 | -- |
| test/memory.elf | 150 | -- |
| test/hello.elf | 0 | Hello, World! |
| test/float.elf | 1 | -- (1 = all FP tests pass) |
| test/vector.elf | 0 | -- (0 = all 14 subtests pass) |
| test/vector_simple.elf | 0 | -- |

### Programs That Run Indefinitely

Bare-metal programs in `programs/` spin in a loop after completion (no OS to return
to). Use `--max-instructions` to cap execution:

```bash
./bin/riscv_emulator --machine qemu-virt \
    --max-instructions 1000000 \
    programs/out/elf/fibonacci.elf
```

---

## Hardware Profiles

A hardware profile defines the memory layout and peripherals for a target system.

### Built-in Profiles

#### simple

1 MB RAM at 0x0. Good for small test programs.

```
RAM:    1MB  @ 0x00000000
UART:        @ 0x10000000
Reset:       0x00000000
Stack:       0x00100000
```

```bash
./bin/riscv_emulator --machine simple program.elf
```

#### qemu-virt

128 MB RAM at 0x80000000. Compatible with QEMU's virt machine.

```
RAM:    128MB @ 0x80000000
ROM:    64KB  @ 0x00001000
UART:         @ 0x10000000
CLINT:        @ 0x02000000
Reset:        0x80000000
Stack:        0x88000000
```

```bash
./bin/riscv_emulator --machine qemu-virt program.elf
```

> **Note:** Programs must be linked for 0x80000000, not 0x0.

### Custom Config Files

Create an INI-style `.cfg` file:

```ini
# myboard.cfg
[profile]
name = myboard

[memory.ram]
base = 0x0
size = 0x400000   # 4MB
type = ram

[memory.rom]
base = 0x10000000
size = 0x10000    # 64KB
type = rom

[peripheral.uart0]
type = uart16550
base = 0x20000000

[peripheral.timer0]
type = clint
base = 0x02000000

[cpu]
reset_vector = 0x0
stack_init = 0x400000
vlen = 128
```

```bash
./bin/riscv_emulator --config myboard.cfg program.elf
```

#### Memory Types

| Type | Description |
|---|---|
| `ram` | Read/write volatile memory |
| `rom` | Read-only (writes silently ignored) |
| `flash` | Read-only (for future programmability) |

#### Peripheral Types

| Type | Description | Default Base |
|---|---|---|
| `uart16550` | 16550-compatible UART | 0x10000000 |
| `clint` | Core Local Interruptor (timer) | 0x02000000 |
| `gpio` | General Purpose I/O (32 pins) | 0x10010000 |
| `spi` | SPI Flash controller | 0x10020000 |
| `i2c` | I2C controller | 0x10030000 |
| `timer` | 4-channel hardware timer/PWM | 0x10040000 |
| `watchdog` | Watchdog timer | 0x10050000 |
| `dma` | DMA controller | 0x10060000 |

### List Available Profiles

```bash
./bin/riscv_emulator --list-machines
```

---

## Command-Line Reference

```
Usage: riscv_emulator [options] <file> [start_address]
```

### Execution Options

| Option | Description |
|---|---|
| `--machine <name>` | Use built-in profile: `simple`, `qemu-virt` |
| `--config <file>` | Load hardware profile from config file |
| `--list-machines` | List available built-in profiles |
| `--max-instructions <n>` | Stop after n instructions |
| `-q`, `--quiet` | Suppress informational output |
| `-v` | Verbose output (show ELF loading details) |

### Debug & Trace Options

| Option | Description |
|---|---|
| `-d` | Start interactive debugger |
| `--gdb [port]` | Start GDB remote stub (default: 1234) |
| `-t` | Enable instruction trace to stdout |
| `--trace-file <file>` | Redirect trace to a file |
| `--trace-range <start> <end>` | Trace only when PC is in range |
| `--trace-mem` | Include memory accesses in trace |
| `--trace-regs` | Show register changes in trace |

### Profiling Options

| Option | Description |
|---|---|
| `--profile` | Enable function call profiling |
| `--flamegraph [file]` | Enable profiling + export flamegraph data |

### UART Options

| Option | Description |
|---|---|
| `--no-uart` | Disable UART emulation |
| `--pty` | Connect UART to a PTY (for minicom/screen) |
| `--wait` | Wait for keypress before starting (use with `--pty`) |

### Arch-Test Option

| Option | Description |
|---|---|
| `--dump-signature <begin> <end> <file>` | Dump signature memory region after halt |

---

## Interactive Debugger

Start with `-d`:

```bash
./bin/riscv_emulator -d test/hello.elf
```

### Commands

#### Execution

| Command | Description |
|---|---|
| `s`, `step` | Execute one instruction |
| `c`, `continue` | Run until breakpoint or halt |
| `x` | Show current instruction |
| `q`, `quit` | Exit |

#### Breakpoints

| Command | Description |
|---|---|
| `b <addr>` | Set breakpoint at hex address |
| `b <function>` | Set breakpoint at function name |
| `bl` | List breakpoints |
| `bc <n>` | Clear breakpoint #n |
| `bc all` | Clear all breakpoints |

#### Watchpoints

| Command | Description |
|---|---|
| `watch <addr>` | Watch address (read or write) |
| `watch <addr> r` | Watch for reads |
| `watch <addr> w` | Watch for writes |
| `wl` | List watchpoints |
| `wc <n>` | Clear watchpoint #n |

#### Inspection

| Command | Description |
|---|---|
| `r`, `regs` | Show integer registers |
| `fregs` | Show floating-point registers |
| `vregs` | Show vector registers |
| `m <addr> [n]` | Dump n bytes of memory (hex) |
| `d <addr> [n]` | Disassemble n instructions |
| `bt`, `backtrace` | Show call stack |
| `info functions` | List all known function symbols |

### Example Debug Session

```
(riscv) b main
Breakpoint 1 set at 0x00000010 (main)
(riscv) c
Breakpoint 1 hit at 0x00000010
(riscv) r
  x0 =      0x0    x1 =      0x8    x2 = 0x100000  ...
(riscv) d 0x10 5
00000010:  00100513  li      a0,  1
00000014:  00008067  ret
(riscv) s
00000010:  00100513  li      a0,  1
(riscv) bt
#0  main @ 0x10
#1  _start @ 0x4
(riscv) q
```

---

## GDB Remote Debugging

### Setup

**Terminal 1** -- start emulator with GDB stub:
```bash
./bin/riscv_emulator --gdb programs/out/elf/fibonacci.elf
# Listening on port 1234...
```

**Terminal 2** -- connect GDB:
```bash
riscv32-unknown-elf-gdb programs/out/elf/fibonacci.elf \
    -ex "target remote :1234" \
    -ex "break main" \
    -ex "continue"
```

### Useful GDB Commands

```gdb
target remote :1234     # Connect
break main              # Break at function
break *0x80000100       # Break at address
continue                # Run
step / stepi            # Step source line / instruction
next                    # Step over call
info registers          # Show registers
x/10i $pc              # Disassemble 10 instructions
x/16x 0x80000000       # Examine memory
bt                      # Backtrace
```

### Custom Port

```bash
./bin/riscv_emulator --gdb 5678 program.elf
# Then: target remote :5678
```

---

## Profiling

### Function Profile

```bash
./bin/riscv_emulator --profile --max-instructions 1000000 program.elf
```

Output:
```
Cycles    %Time  Instructions  Calls  Function
--------  -----  ------------  -----  ----------------
  98562   98%      98562     523  puts
   1430    1%       1430       1  main
```

### Flamegraph

```bash
# 1. Generate profile data
./bin/riscv_emulator --flamegraph profile.fg \
    --max-instructions 1000000 program.elf

# 2. Convert to SVG (requires flamegraph.pl)
flamegraph.pl profile.fg > profile.svg

# 3. View in browser
firefox profile.svg
```

---

## Peripherals

All peripherals are enabled via config files or the `--machine` option. The complete
set of available peripherals:

### UART 16550

**Base:** 0x10000000 | Available in: all profiles

Standard 16550-compatible UART. The emulator writes UART output directly to stdout
by default, or to a PTY with `--pty`.

```c
#define UART_BASE 0x10000000
#define UART_THR  (*(volatile char*)(UART_BASE + 0))  // TX/RX
#define UART_LSR  (*(volatile char*)(UART_BASE + 5))  // Line status
#define UART_THRE 0x20  // TX holding register empty (bit 5)

void putchar(char c) {
    while (!(UART_LSR & UART_THRE));  // Wait for TX ready
    UART_THR = c;
}
```

### CLINT (Timer)

**Base:** 0x02000000 | Available in: `qemu-virt`, arch-test

RISC-V Core Local Interruptor. Provides `mtime` and `mtimecmp` registers for
timer interrupts.

| Offset | Register | Description |
|---|---|---|
| 0x0000 | MSIP | Software interrupt pending |
| 0x4000 | MTIMECMP | Timer compare (trigger interrupt when mtime >= mtimecmp) |
| 0xBFF8 | MTIME | Current time counter |

### GPIO

**Base:** 0x10010000 | Available in: `qemu-virt`

32-pin GPIO with direction control, interrupts, and pull-up/down.

### SPI Flash

**Base:** 0x10020000 | Available in: `qemu-virt`

SPI Flash controller with 64KB emulated flash storage.

### I2C

**Base:** 0x10030000 | Available in: `qemu-virt`

I2C controller with three simulated devices:
- **0x48** -- Temperature sensor (TMP102-like), returns 25degC
- **0x1D** -- Accelerometer (ADXL345-like)
- **0x50** -- EEPROM, 256 bytes read/write

### Hardware Timer / PWM

**Base:** 0x10040000 | Available in: `qemu-virt`

4-channel timer with compare-match interrupts and 0-255 PWM output.

### Watchdog

**Base:** 0x10050000 | Available in: `qemu-virt`

Watchdog timer. Must be regularly refreshed or it will reset the CPU.

### DMA

**Base:** 0x10060000 | Available in: `qemu-virt`

4-channel DMA controller for memory-to-memory transfers.

---

## Writing Programs

### Program Linked at 0x0 (simple profile)

```c
// test/mytest.c
int _main(void) {
    return 42;   // Return value appears in a0
}
```

**Startup file** (`test/start.S`):
```asm
.section .text
.global _start
_start:
    li sp, 0x100000   # Stack at 1MB
    jal _main
    ecall             # Exit
```

**Build:**
```bash
riscv32-unknown-elf-gcc -march=rv32imfd -mabi=ilp32 \
    -nostdlib -ffreestanding -O2 \
    -Ttext=0x0 -o mytest.elf start.o mytest.c
```

### Program Linked at 0x80000000 (qemu-virt)

Use a linker script:
```ld
/* hello.ld */
OUTPUT_ARCH("riscv")
ENTRY(_start)
MEMORY {
    RAM (rwx) : ORIGIN = 0x80000000, LENGTH = 1M
}
SECTIONS {
    .text : { *(.text.start) *(.text*) } > RAM
    .rodata : { *(.rodata*) } > RAM
    .data : { *(.data*) } > RAM
    .bss : { *(.bss*) } > RAM
}
```

**Build:**
```bash
riscv32-unknown-elf-gcc -march=rv32imc -mabi=ilp32 \
    -nostdlib -nostartfiles -T hello.ld \
    -O2 -o myprogram.elf start.S myprogram.c
```

### UART Output

```c
#define UART_BASE 0x10000000
volatile char *UART_THR = (volatile char*)UART_BASE;
volatile char *UART_LSR = (volatile char*)(UART_BASE + 5);

void puts(const char *s) {
    while (*s) {
        while (!(*UART_LSR & 0x20));  // Wait TX ready
        *UART_THR = *s++;
    }
}
```

### PTY Mode (for interactive programs)

```bash
# Start with PTY
./bin/riscv_emulator --machine qemu-virt --pty --wait programs/out/elf/echo.elf

# Connect from another terminal
minicom -D /dev/pts/X
# or
screen /dev/pts/X
```

---

## Architecture Tests

The emulator supports RISC-V architecture compliance testing via the
[riscv-arch-test](https://github.com/riscv-non-isa/riscv-arch-test) framework.

### Running Tests

```bash
cd arch-test
make test
```

### Test Results

```
Suite: I (rv32i)
Total: 38  Pass: 37  Fail: 1  Skip: 0

Failures:
  jalr-01: compile error  (test suite bug, not emulator bug)
```

### How It Works

Each test binary:
1. Executes a series of instructions
2. Writes results to a "signature" memory region
3. The emulator dumps the signature with `--dump-signature`
4. The dump is compared to a golden reference

```bash
./bin/riscv_emulator \
    --config arch-test/env/arch-test.cfg \
    --dump-signature 0x80002000 0x80002100 output.sig \
    arch-test/work/add-01.elf
```

---

## Troubleshooting

### ILLEGAL_INSTRUCTION at address 0x0 or 0x2

**Symptom:** Program halts immediately with `Exception: ILLEGAL_INSTRUCTION`

**Cause:** ELF loading failed -- bytes from the file are not reaching RAM.

**Solution:** Always use `--machine` or `--config` when running ELF files:
```bash
# Wrong -- may fail depending on peripheral state
./bin/riscv_emulator program.elf

# Correct
./bin/riscv_emulator --machine simple program.elf
```

### Wrong Memory Layout

**Symptom:** Program starts but quickly faults or produces wrong results.

**Cause:** Profile doesn't match what the program was compiled for.

| Compiled for | Use |
|---|---|
| `0x0` | `--machine simple` |
| `0x80000000` | `--machine qemu-virt` |
| Custom address | `--config myboard.cfg` |

### programs/out/elf/*.elf Appears to Hang

Programs in `programs/` don't exit -- they spin in an infinite loop after completion
(bare-metal style). Use `--max-instructions` to stop them:

```bash
./bin/riscv_emulator --machine qemu-virt \
    --max-instructions 1000000 programs/out/elf/fibonacci.elf
```

### No UART Output

- Check the correct profile is used (UART at 0x10000000 for both `simple` and `qemu-virt`)
- For PTY mode: make sure you connected to the right `/dev/pts/X` before the program ran
- Use `--wait` to pause execution until you connect

### GDB Won't Connect

```bash
# Check emulator is listening
./bin/riscv_emulator --gdb program.elf -v
# Should print: "Listening for GDB on port 1234"

# Connect
riscv32-unknown-elf-gdb program.elf -ex "target remote :1234"
```

### Arch-Tests Produce Wrong Signatures

Make sure `--config arch-test/env/arch-test.cfg` is used -- the arch-test config
defines the correct 4MB RAM region and CLINT peripheral that the test binaries expect:

```bash
cd arch-test && make test
# Uses arch-test/env/arch-test.cfg automatically
```

### Toolchain Not Found

```bash
which riscv32-unknown-elf-gcc
# If not found:
sudo apt install gcc-riscv64-unknown-elf

# The package installs a riscv64- prefix, so tell the Makefiles about it:
make -C programs CROSS=riscv64-unknown-elf-
```

---

## Register Reference

### Integer Registers (ABI Names)

| Reg | ABI | Role |
|---|---|---|
| x0 | zero | Always 0 |
| x1 | ra | Return address |
| x2 | sp | Stack pointer |
| x3 | gp | Global pointer |
| x4 | tp | Thread pointer |
| x5-x7 | t0-t2 | Temporaries |
| x8 | s0/fp | Saved / frame pointer |
| x9 | s1 | Saved register |
| x10-x11 | a0-a1 | Args / return values |
| x12-x17 | a2-a7 | Arguments |
| x18-x27 | s2-s11 | Saved registers |
| x28-x31 | t3-t6 | Temporaries |

### Return Value Convention

After emulation stops, the value of `a0` (x10) is printed as the return value.
This is the standard RISC-V calling convention return register.

---

## Further Reading

Detailed documentation in the `doc/` directory:

| File | Contents |
|---|---|
| [doc/QUICKSTART.md](doc/QUICKSTART.md) | Getting started guide |
| [doc/BUILDING.md](doc/BUILDING.md) | Build options and requirements |
| [doc/DEBUGGING.md](doc/DEBUGGING.md) | Interactive debugger full reference |
| [doc/DEBUGGING-ADVANCED.md](doc/DEBUGGING-ADVANCED.md) | Watchpoints, backtrace, symbols |
| [doc/GDB.md](doc/GDB.md) | GDB remote debugging |
| [doc/PROFILING.md](doc/PROFILING.md) | Profiling and flamegraphs |
| [doc/PROFILES.md](doc/PROFILES.md) | Hardware profiles and config format |
| [doc/PERIPHERALS.md](doc/PERIPHERALS.md) | All peripherals reference |
| [doc/ISA.md](doc/ISA.md) | Instruction set reference |
| [doc/ARCHITECTURE.md](doc/ARCHITECTURE.md) | Source code structure |
| [doc/C-LIBRARY.md](doc/C-LIBRARY.md) | C library for bare-metal programs |
| [QUICK_REFERENCE.md](QUICK_REFERENCE.md) | One-page command cheat sheet |
| [STATUS.md](STATUS.md) | Feature status and full test inventory |
| [TUTORIAL.md](TUTORIAL.md) | Hands-on walkthrough of every feature |
