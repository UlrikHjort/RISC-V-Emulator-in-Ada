# RISC-V Emulator Documentation

An Ada-based RISC-V (RV32/RV64) emulator targeting embedded software testing and development.
Supports RV32IMAFDC + V + Zbb/Zbs/Zba/Zbkc/Zbkx/A/Zicond/Zfh + RV32E and RV64IMAFD + Zbb/Zba/A/Zicond.

## Documentation Index

| Document | Description |
|----------|-------------|
| [Quick Start](QUICKSTART.md) | Getting started guide |
| [Architecture](ARCHITECTURE.md) | Code structure and design |
| [Instruction Set](ISA.md) | Supported instructions (RV32IMAFDC + V + RV64IMAFD + Zb*/Zicond/Zfh) |
| [Peripherals](PERIPHERALS.md) | UART, CLINT, GPIO, SPI, I2C, Timer, DMA |
| [Hardware Profiles](PROFILES.md) | Memory layouts and configuration |
| [Debugging](DEBUGGING.md) | Interactive debugger and tracing |
| [Profiling](PROFILING.md) | Profiler, coverage tracking, trace/replay |
| [GDB](GDB.md) | GDB remote stub |
| [Building](BUILDING.md) | Build instructions and toolchain |
| [Writing C Programs](WRITING-PROGRAMS.md) | Installing a cross-compiler and compiling your own programs |
| [Testing](TESTING.md) | Ada unit tests and program validation |
| [C Library](C-LIBRARY.md) | Bare-metal C runtime (stdio, string, malloc, setjmp) |
| [Math Library](MATH_LIBRARY.md) | `math.h` for bare-metal programs |
| [Advanced Debugging](DEBUGGING-ADVANCED.md) | Watchpoints, tracing, replay |
| [DMA](DMA.md) | DMA controller peripheral |
| [Watchdog](WATCHDOG.md) | Watchdog timer peripheral |
| [RTOS Demo](RTOS_DEMO.md) | Mini-RTOS educational demo |

Top-level guides live in the repository root: [TUTORIAL.md](../TUTORIAL.md),
[USER-MANUAL.md](../USER-MANUAL.md), [QUICK_REFERENCE.md](../QUICK_REFERENCE.md),
[STATUS.md](../STATUS.md), [TESTING.md](../TESTING.md).

## Features at a Glance

- **RV32IMAFDC + V + Zbb/Zbs/Zba + Zbkc/Zbkx + Zicond + Zfh + RV32E** - Full 32-bit ISA suite
- **RV64IMAFD + Zbb/Zba/A/Zicond** - 64-bit ISA auto-detected from ELF class
- **78 test programs, 2189 assertions** - All passing
- **Hardware profiles** - `simple` (RAM@0x0) and `qemu-virt` (RAM@0x80000000, 128MB)
- **Interactive debugger** - Breakpoints, watchpoints, single-step, backtrace, symbol lookup
- **GDB remote stub** - Software + hardware watchpoints, `target.xml`, vCont (RV32 + RV64)
- **Instruction profiler** - Function %, opcode histogram, hot-PC, call graph, flamegraph export
- **Cycle-accurate stall model** - MUL/DIV/FP/CSR stalls; total wall cycles, CPI display
- **L1 cache simulation** - Set-associative I+D cache (`--cache`/`--icache`/`--dcache`), LRU
- **Instruction coverage** - Packed bitmap + per-function % (ELF symbols)
- **Binary trace/replay** - Record execution; verify a second run is bit-for-bit identical
- **Supervisor mode + SBI** - S-mode, U-mode, SBI shim, PLIC, Sv39 MMU
- **Extended CSRs** - mcountinhibit, mcounteren, scounteren, HPM stubs
- **Multi-hart** - Configurable hart count (`--harts N`), independent registers/CSRs per hart
- **Peripherals** - UART (PTY), GPIO, SPI + 64KB flash, I2C, Timer, Watchdog, DMA, CLINT, PLIC, VirtIO block
- **C runtime** - crt0, printf/sprintf, malloc/free, qsort, sscanf, atof, setjmp/longjmp, time.h (clock_gettime/gettimeofday)

## Quick Example

```bash
# Build the emulator
make

# Run an ELF with the qemu-virt profile
./bin/riscv_emulator --machine qemu-virt program.elf

# Debug interactively
./bin/riscv_emulator --machine qemu-virt -d program.elf

# Profile (function breakdown + flamegraph)
./bin/riscv_emulator --machine qemu-virt --profile --flamegraph out.fg program.elf

# Coverage report
./bin/riscv_emulator --machine qemu-virt --coverage coverage.txt program.elf

# Record a binary trace, then replay to verify
./bin/riscv_emulator --machine qemu-virt --irecord run.trace program.elf
./bin/riscv_emulator --machine qemu-virt --ireplay run.trace program.elf
```

## Project Status

See [../STATUS.md](../STATUS.md) for current feature status and the full test inventory.

## License

MIT License - See [../LICENSE](../LICENSE). The vendored DOOM engine under
`programs/doom/` is GPLv2; see [../programs/doom/README.md](../programs/doom/README.md).
