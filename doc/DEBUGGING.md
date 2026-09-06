# RISC-V Emulator - Debugging Guide

This guide covers all the debugging features available in the RISC-V emulator.

## Table of Contents

- [Getting Started](#getting-started)
- [Interactive Debugger](#interactive-debugger)
- [Breakpoints](#breakpoints)
- [Watchpoints](#watchpoints)
- [Call Stack Analysis](#call-stack-analysis)
- [Symbol Table Support](#symbol-table-support)
- [Memory and Register Inspection](#memory-and-register-inspection)
- [Examples and Workflows](#examples-and-workflows)

---

## Getting Started

### Starting the Debugger

```bash
# Start with interactive debugger
./bin/riscv_emulator -d program.elf

# Load symbols automatically from ELF file
./bin/riscv_emulator -d programs/out/elf/hello.elf
```

When the debugger starts, you'll see:

```
Loading ELF file: programs/out/elf/hello.elf
Loaded 12 symbols from programs/out/elf/hello.elf

RISC-V Debugger. Type 'h' for help.

80000000:  00100117  auipc   sp, 0x100
(riscv)
```

### Getting Help

```
(riscv) help
```

This shows all available commands with brief descriptions.

---

## Interactive Debugger

### Basic Commands

| Command | Aliases | Description |
|---------|---------|-------------|
| `s` | `step` | Execute one instruction |
| `c` | `continue` | Continue until breakpoint or halt |
| `r` | `regs` | Show all integer registers |
| `x` | | Show current instruction |
| `q` | `quit` | Exit debugger |
| `h` | `help`, `?` | Show help |

### Stepping Through Code

```
(riscv) s         # Execute one instruction
80000004:  00010113  mv      sp, sp
(riscv) s         # Execute another
80000008:  00000297  auipc   t0, 0x0
```

Each step shows the next instruction to be executed with its disassembly.

### Continuing Execution

```
(riscv) c         # Run until breakpoint or program halt
```

The program will run at full speed until:
- A breakpoint is hit
- A watchpoint is triggered
- The program halts (ECALL or exception)

---

## Breakpoints

### Setting Breakpoints

#### By Address (Hexadecimal)

```
(riscv) b 80000100
Breakpoint 1 set at 0x80000100
```

#### By Function Name (Requires Symbols)

```
(riscv) b main
Breakpoint set at main (800000bc)

(riscv) b printf
Breakpoint set at printf (800007d0)
```

### Listing Breakpoints

```
(riscv) bl
Breakpoints:
  1: 0x800000bc
  2: 0x800007d0
```

### Clearing Breakpoints

```
(riscv) bc 1          # Clear breakpoint #1
(riscv) bc all        # Clear all breakpoints
```

### Breakpoint Behavior

When a breakpoint is hit:

```
Breakpoint hit at 0x800000bc
800000bc:  c4221141  ??? (0xc4221141)  <main>
(riscv)
```

The debugger stops **before** executing the instruction at the breakpoint.

---

## Watchpoints

Watchpoints trigger when memory locations are accessed.

### Setting Watchpoints

```
(riscv) watch 80100000        # Watch for any access (read/write)
(riscv) watch 80100000 r      # Watch for reads only
(riscv) watch 80100000 w      # Watch for writes only
(riscv) watch 80100000 rw     # Explicit read/write
```

### Watchpoint Types

- `r` - Read watchpoint (triggers on load instructions)
- `w` - Write watchpoint (triggers on store instructions)
- `rw` - Read/Write (triggers on any access) - default

### Managing Watchpoints

```
(riscv) wl            # List all watchpoints
Watchpoints:
  1: 0x80100000 (rw)
  2: 0x80100004 (w)

(riscv) wc 1          # Clear watchpoint #1
(riscv) wc all        # Clear all watchpoints
```

### Watchpoint Behavior

When a watchpoint is triggered:

```
Watchpoint hit: WRITE to 0x80100000
80000050:  00a12023  sw      a0, 0(sp)
(riscv)
```

---

## Call Stack Analysis

The backtrace command shows the call stack, helping you understand how execution reached the current point.

### Viewing the Call Stack

```
(riscv) bt            # Show backtrace
Call Stack:
#  PC         Function
-- ---------- --------------------------------
 0  800007d0  printf
 1  800017a4  main+0000002c
```

Aliases: `bt`, `backtrace`, `where`

### Understanding the Output

Each frame shows:
- **#** - Frame number (0 = current)
- **PC** - Program counter at that frame
- **Function** - Function name (if symbol available) with offset

Example interpretation:
- Frame 0: Currently in `printf` at PC 0x800007d0
- Frame 1: Called from `main` at offset +0x2c

### When to Use Backtrace

- **After hitting a breakpoint** - See the call chain
- **Debugging crashes** - Understand how execution got there
- **Understanding program flow** - See nested function calls

---

## Symbol Table Support

Symbols provide human-readable names for functions and variables.

### Automatic Symbol Loading

When loading an ELF file with `-d`, symbols are automatically loaded:

```
Loading ELF file: programs/out/elf/fibonacci.elf
Loaded 46 symbols from programs/out/elf/fibonacci.elf
```

### Listing Symbols

```
(riscv) info functions
Symbol Table (46 symbols):
Address    Size       Type     Name
---------- ---------- -------- --------------------------------
80000028   0000003c   FUNC     putchar
8000007c   00000040   FUNC     puts
800000bc   0000001e   FUNC     main
80000064   00000018   FUNC     getchar
...
```

Alias: `info f`

### Symbol Benefits

With symbols loaded, you can:

1. **Set breakpoints by function name**
   ```
   (riscv) b main
   (riscv) b printf
   ```

2. **See function names in disassembly**
   ```
   800000bc:  c4221141  ??? (0xc4221141)  <main>
   800000c0:  c606c226  ??? (0xc606c226)  <main+00000004>
   ```

3. **Get meaningful backtraces**
   ```
   #  PC         Function
   0  800007d0  printf
   1  800017a4  main+0000002c
   ```

---

## Memory and Register Inspection

### Viewing Registers

#### Integer Registers

```
(riscv) r             # Show all integer registers
(riscv) regs
```

Output:
```
PC  = 0x80000000

x0 =0x00000000  ra =0x00000000  sp =0x80100000  gp =0x00000000
tp =0x00000000  t0 =0x00000000  t1 =0x00000000  t2 =0x00000000
s0 =0x00000000  s1 =0x00000000  a0 =0x00000000  a1 =0x00000000
...
```

#### Floating-Point Registers

```
(riscv) fregs         # Show all FP registers

(riscv) freg 0        # Show specific FP register
f0 = 0.000000 (raw: 0x0000000000000000)
```

#### Vector Registers

```
(riscv) vregs         # Show vector register status
Vector Extension Status:
  vl    = 0
  vtype = 0x00000000
  ...
```

### Memory Inspection

#### Dump Memory (Hex)

```
(riscv) m 80000000           # Dump 64 bytes from address
(riscv) m 80000000 128       # Dump 128 bytes

80000000: 17 01 10 00 13 01 01 00 97 02 00 00 93 82 02 10
80000010: 17 03 00 00 13 03 03 10 97 03 00 00 93 83 03 10
...
```

#### Disassemble Instructions

```
(riscv) d 80000000           # Disassemble 10 instructions
(riscv) d 80000000 20        # Disassemble 20 instructions

80000000:  00100117  auipc   sp, 0x100
80000004:  00010113  mv      sp, sp
80000008:  00000297  auipc   t0, 0x0
8000000c:  10028293  addi    t0, t0,  256
...
```

With symbols, function names are shown:
```
800000bc:  c4221141  ??? (0xc4221141)  <main>
800000c0:  c606c226  ??? (0xc606c226)  <main+00000004>
```

---

## Examples and Workflows

### Example 1: Basic Debugging Session

```bash
# Start debugger
./bin/riscv_emulator -d programs/out/elf/hello.elf

# Set breakpoint at main
(riscv) b main
Breakpoint set at main (800000bc)

# Run to breakpoint
(riscv) c
Breakpoint hit at 0x800000bc

# Show call stack
(riscv) bt
Call Stack:
#  PC         Function
0  800000bc  main
1  8000002c  ???

# Show registers
(riscv) r

# Step a few instructions
(riscv) s
(riscv) s
(riscv) s

# Continue execution
(riscv) c

# Program completes...
(riscv) q
```

### Example 2: Debugging Memory Issues

```bash
# Start debugger
./bin/riscv_emulator -d program.elf

# Set watchpoint on suspect memory location
(riscv) watch 80100000 w

# Run until watchpoint triggers
(riscv) c

Watchpoint hit: WRITE to 0x80100000
80000050:  00a12023  sw      a0, 0(sp)

# Check what's being written
(riscv) r
a0 = 0x12345678

# Check memory after write
(riscv) m 80100000 16

# Show call stack to see who wrote it
(riscv) bt
```

### Example 3: Analyzing Function Calls

```bash
# Start debugger
./bin/riscv_emulator -d programs/out/elf/fibonacci.elf

# List available functions
(riscv) info functions | grep fib
fib_iterative
fib_recursive

# Set breakpoint in recursive function
(riscv) b fib_recursive

# Run to first call
(riscv) c
Breakpoint hit at 0x800012bc

# Show initial call stack
(riscv) bt

# Continue to next call (recursive)
(riscv) c

# Show deeper call stack
(riscv) bt
Call Stack:
#  PC         Function
0  800012bc  fib_recursive
1  800012e4  fib_recursive+00000028
2  800017a4  main+0000002c

# Continue execution
(riscv) c
```

### Example 4: Debugging with Disassembly

```bash
# Start debugger
./bin/riscv_emulator -d program.elf

# Break at function
(riscv) b main

# Run to breakpoint
(riscv) c

# Disassemble the function
(riscv) d 800000bc 20

# Step through each instruction
(riscv) s
(riscv) r     # Check registers after each step
(riscv) s
(riscv) r

# Continue when satisfied
(riscv) c
```

---

## Tips and Best Practices

### 1. Always Load Symbols

Use ELF files with symbols for the best debugging experience:
```bash
./bin/riscv_emulator -d program.elf
```

### 2. Use Function Names

When symbols are loaded, use function names instead of addresses:
```
(riscv) b main        # Better than: b 800000bc
```

### 3. Combine Commands

Use multiple debugging techniques together:
```
(riscv) b main        # Set breakpoint
(riscv) c             # Run to it
(riscv) bt            # See call stack
(riscv) r             # Check registers
(riscv) d 800000bc 10 # Disassemble upcoming code
```

### 4. Watchpoints for Memory Issues

Use watchpoints to catch memory corruption:
```
(riscv) watch <address> w    # Watch for writes
```

### 5. Backtrace for Context

When debugging crashes or unexpected behavior, always check the call stack:
```
(riscv) bt
```

---

## Keyboard Shortcuts

None currently - type full commands or use aliases.

---

## Troubleshooting

### "Symbol not found" Error

If you try to set a breakpoint by function name and get "Symbol not found":
- Make sure you loaded an ELF file (not raw binary)
- Check available symbols: `info functions`
- Use exact function name from symbol table

### Breakpoint Not Triggering

- Verify the address is correct: `d <address>`
- Check if code is actually executed (use tracing: `-t`)
- Ensure breakpoint is set: `bl`

### Watchpoint Not Triggering

- Verify the memory address is actually accessed
- Check watchpoint type matches access (r/w/rw)
- List watchpoints: `wl`

---

## See Also

- [Profiling Guide](PROFILING.md) - Performance analysis and profiling
- [GDB Remote Debugging](GDB.md) - Using standard GDB with the emulator
- [README.md](README.md) - Main documentation
