# RISC-V Emulator - Quick Reference

Quick reference for debugging and profiling commands.

## Running Modes

```bash
# ELF file - uses default (simple) profile
./bin/riscv_emulator program.elf

# ELF file - with explicit profile (recommended)
./bin/riscv_emulator --machine simple program.elf
./bin/riscv_emulator --machine qemu-virt program.elf

# ELF file - custom config
./bin/riscv_emulator --config myboard.cfg program.elf

# Raw binary - must specify load/start address in hex
./bin/riscv_emulator --machine simple program.bin 0
./bin/riscv_emulator --machine qemu-virt program.bin 80000000

# Interactive debugger
./bin/riscv_emulator -d program.elf

# GDB remote debugging
./bin/riscv_emulator --gdb program.elf
# Then: riscv32-unknown-elf-gdb program.elf -ex "target remote :1234"

# Profiling
./bin/riscv_emulator --profile --max-instructions 100000 program.elf

# Flamegraph profiling
./bin/riscv_emulator --flamegraph output.fg --max-instructions 100000 program.elf

# With tracing
./bin/riscv_emulator -t program.elf
```

---

## Interactive Debugger Commands

### Execution

| Command | Description |
|---------|-------------|
| `s`, `step` | Execute one instruction |
| `c`, `continue` | Run until breakpoint/halt |
| `x` | Show current instruction |
| `q`, `quit` | Exit debugger |

### Breakpoints

| Command | Description |
|---------|-------------|
| `b <addr>` | Set breakpoint at address |
| `b <function>` | Set breakpoint at function (requires symbols) |
| `bl` | List all breakpoints |
| `bc <n>` | Clear breakpoint #n |
| `bc all` | Clear all breakpoints |

### Watchpoints

| Command | Description |
|---------|-------------|
| `watch <addr>` | Watch address (read/write) |
| `watch <addr> r` | Watch for reads |
| `watch <addr> w` | Watch for writes |
| `wl` | List watchpoints |
| `wc <n>` | Clear watchpoint #n |
| `wc all` | Clear all watchpoints |

### Inspection

| Command | Description |
|---------|-------------|
| `r`, `regs` | Show integer registers |
| `fregs` | Show floating-point registers |
| `freg <n>` | Show FP register n |
| `vregs` | Show vector registers |
| `m <addr> [count]` | Dump memory (hex) |
| `d <addr> [count]` | Disassemble instructions |
| `bt`, `backtrace` | Show call stack |

### Symbols

| Command | Description |
|---------|-------------|
| `info functions` | List all functions |
| `info f` | (short form) |

---

## GDB Commands

### Connection

```gdb
target remote localhost:1234   # Connect to emulator
```

### Execution Control

```gdb
c, continue         # Run until breakpoint
s, step             # Step one source line
si, stepi           # Step one instruction
n, next             # Step over function call
```

### Breakpoints

```gdb
break main                     # Break at function
break *0x80000100              # Break at address
info breakpoints               # List breakpoints
delete 1                       # Delete breakpoint #1
disable 1                      # Disable breakpoint
enable 1                       # Enable breakpoint
```

### Inspection

```gdb
info registers                 # Show all registers
print $pc                      # Print PC
print $a0                      # Print register
x/10x 0x80000000              # Examine memory (hex)
x/10i 0x80000000              # Examine instructions
bt, backtrace                  # Show call stack
disassemble                    # Disassemble current location
```

---

## Profiling Output

### Function Profile

```
Cycles    %Time  Instructions  Calls  Function
--------  -----  ------------  -----  ----------------
 98562   98%   98562   0  puts
 1430   1%   1430   0  main
```

### Call Graph

```
Calls  Caller -> Callee
-----  ----------------
 523  main -> printf
 414  printf -> putchar
```

### Flamegraph Generation

```bash
# 1. Generate data
./bin/riscv_emulator --flamegraph output.fg --max-instructions 100000 program.elf

# 2. Create SVG
flamegraph.pl output.fg > flamegraph.svg

# 3. View
firefox flamegraph.svg
```

---

## Common Flags

| Flag | Description |
|------|-------------|
| `-d` | Interactive debugger |
| `--gdb [port]` | GDB remote stub (default port: 1234) |
| `--profile` | Enable profiling |
| `--flamegraph FILE` | Enable profiling + export flamegraph |
| `-t` | Enable instruction trace |
| `--trace-file FILE` | Redirect trace to file |
| `--trace-range <s> <e>` | Trace only PC in range |
| `--max-instructions N` | Stop after N instructions |
| `--quiet` | Suppress output |
| `-v` | Verbose output |

---

## Typical Workflows

### 1. Quick Debug Session

```bash
./bin/riscv_emulator -d program.elf

(riscv) b main
(riscv) c
(riscv) bt
(riscv) r
(riscv) s
(riscv) s
(riscv) c
(riscv) q
```

### 2. GDB Debugging

```bash
# Terminal 1
./bin/riscv_emulator --gdb program.elf

# Terminal 2
riscv32-unknown-elf-gdb program.elf \
    -ex "target remote :1234" \
    -ex "break main" \
    -ex "continue"
```

### 3. Performance Profiling

```bash
# Get profile data
./bin/riscv_emulator --profile --max-instructions 100000 program.elf

# Look at top functions
# Optimize hotspots
# Re-profile to verify
```

### 4. Visual Profiling

```bash
# Generate flamegraph
./bin/riscv_emulator --flamegraph data.fg --max-instructions 100000 program.elf

# Create SVG
flamegraph.pl data.fg > profile.svg

# Analyze in browser
firefox profile.svg
```

### 5. Memory Debugging

```bash
./bin/riscv_emulator -d program.elf

(riscv) watch 80100000 w
(riscv) c
# Watchpoint triggered
(riscv) bt
(riscv) r
(riscv) m 80100000 64
```

---

## Register Names

### Integer Registers

| Number | ABI Name | Description |
|--------|----------|-------------|
| x0 | zero | Always zero |
| x1 | ra | Return address |
| x2 | sp | Stack pointer |
| x3 | gp | Global pointer |
| x4 | tp | Thread pointer |
| x5-x7 | t0-t2 | Temporaries |
| x8 | s0/fp | Saved/frame pointer |
| x9 | s1 | Saved register |
| x10-x11 | a0-a1 | Function args/return |
| x12-x17 | a2-a7 | Function arguments |
| x18-x27 | s2-s11 | Saved registers |
| x28-x31 | t3-t6 | Temporaries |

### Special Registers

- **PC** - Program counter
- **FCSR** - FP control/status register

---

## Memory Map (Default)

| Range | Description |
|-------|-------------|
| 0x00000000 | RAM start (simple profile) |
| 0x10000000 | UART (simple profile) |
| 0x80000000 | RAM start (qemu-virt profile) |
| 0x80100000 | Typical stack top |

Use `--machine qemu-virt` for QEMU-compatible memory map.

---

## Getting Help

```bash
# Show all options
./bin/riscv_emulator --help

# Debugger help
(riscv) help

# GDB help
(gdb) help
```

## Full Documentation

- [doc/DEBUGGING.md](doc/DEBUGGING.md) - Complete debugging guide
- [doc/PROFILING.md](doc/PROFILING.md) - Performance profiling guide
- [doc/GDB.md](doc/GDB.md) - GDB remote debugging guide
- [README.md](README.md) - Main documentation

---

**Keep this reference handy for quick lookups!**
