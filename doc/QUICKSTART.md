# Quick Start Guide

## Prerequisites

- GNAT Ada compiler (tested with GCC 12)
- Make
- Optional: riscv32-unknown-elf-gcc (for building test programs)

## Building

```bash
# Clone with the architecture-compliance submodule
git clone --recurse-submodules <repo-url>

# Or initialise after a plain clone
git submodule update --init

cd riscv
make
```

This creates `bin/riscv_emulator`.

## Running Programs

### Basic Usage

```bash
# Run an ELF executable
./bin/riscv_emulator program.elf

# Run a raw binary at address 0
./bin/riscv_emulator program.bin

# Run a raw binary at specific address
./bin/riscv_emulator program.bin 0x1000
```

### Command Line Options

```
Usage: riscv_emulator [options] <file> [start_address]

Core options:
  --machine <name>         Hardware profile: simple or qemu-virt (required for ELF)
  -v, --verbose            Show ELF loading details
  -q, --quiet              Suppress informational output
  --no-uart                Disable UART emulation
  --pty                    Connect UART to a PTY (for minicom/screen)
  --wait                   Wait for PTY connection before starting
  --max-instructions <n>   Stop after N instructions

Tracing:
  -t                       Enable instruction trace to stdout
  --trace-file <file>       Redirect trace to file
  --trace-range <s> <e>     Only trace PC in [start, end]
  --trace-mem               Log memory accesses in trace
  --trace-regs              Show register changes in trace

Debugging:
  -d                       Start in interactive debugger
  --gdb [port]             GDB remote stub (default port: 1234)

Analysis:
  --profile                Instruction profiler (report on exit)
  --flamegraph [file]      Profiler + export flamegraph (default: flamegraph.fg)
  --coverage [file]        Instruction coverage report (default: coverage.txt)
  --irecord <file>         Record binary instruction trace (20 bytes/insn)
  --ireplay <file>         Replay and verify against binary trace file
```

### Examples

```bash
# Run a program (always use --machine for ELF files)
./bin/riscv_emulator --machine qemu-virt program.elf

# Trace every instruction
./bin/riscv_emulator --machine qemu-virt -t program.elf

# Interactive debugger
./bin/riscv_emulator --machine qemu-virt -d program.elf

# Profile - prints function breakdown and call graph on exit
./bin/riscv_emulator --machine qemu-virt --profile program.elf

# Coverage - writes per-function coverage % to coverage.txt
./bin/riscv_emulator --machine qemu-virt --coverage program.elf

# Instruction trace recording and replay (detect divergence)
./bin/riscv_emulator --machine qemu-virt --irecord run.trace program.elf
./bin/riscv_emulator --machine qemu-virt --ireplay run.trace program.elf

# GDB remote debugging (terminal 1 + terminal 2)
./bin/riscv_emulator --machine qemu-virt --gdb program.elf
riscv32-unknown-elf-gdb program.elf  # in another terminal
```

## Running Tests

```bash
# Emulator test suite (78 programs, 2189 assertions)
cd programs && ./test-all.sh

# Architecture compliance tests (requires submodule + cross-compiler)
cd arch-test
make test          # I + M + C baseline
make test-all      # all suites (I, M, C, F, Zifencei, privilege)
make test-I        # single suite
```

## Return Values

Programs return their exit value in register `a0` (x10). The emulator displays this after execution:

```
Return value (a0): 42
```

Common exit scenarios:
- **ENVIRONMENT_CALL** - Normal exit via `ecall` (syscall)
- **BREAKPOINT** - Program hit `ebreak` instruction
- **ILLEGAL_INSTRUCTION** - Invalid opcode encountered

## Next Steps

- Read [DEBUGGING.md](DEBUGGING.md) for interactive debugging
- Read [PROFILES.md](PROFILES.md) for custom memory layouts
- Read [ISA.md](ISA.md) for supported instructions
