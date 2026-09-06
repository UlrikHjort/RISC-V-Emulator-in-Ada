# Advanced Debugging Features

This document describes the advanced debugging features added in Phase 3.

## Memory Watchpoints

Watchpoints allow you to break execution when specific memory addresses are accessed.

### Commands

```
watch <addr> [r|w|rw]  - Set watchpoint at address
                         r  = break on read
                         w  = break on write
                         rw = break on read or write (default)

wl                     - List all watchpoints
wc <n>                 - Clear watchpoint number n
wc all                 - Clear all watchpoints
```

### Examples

```
(riscv) watch 0x80001000 rw
Watchpoint  1 set at 0x80001000 (read/write)

(riscv) watch 0x80002000 w
Watchpoint  2 set at 0x80002000 (write)

(riscv) wl
Watchpoint 1: 0x80001000 (read/write)
Watchpoint 2: 0x80002000 (write)

(riscv) wc 1
Watchpoint  1 cleared

(riscv) wc all
All watchpoints cleared
```

### Usage Notes

- Maximum 16 watchpoints
- Watchpoints persist across continue/step commands
- Useful for debugging memory corruption, buffer overflows
- Monitor stack pointer, heap allocations, peripheral registers

## Floating-Point Register Inspection

View and inspect floating-point registers during debugging.

### Commands

```
fregs       - Show all FP registers (f0-f31)
freg <n>    - Show detail for FP register n (0-31)
```

### Examples

```
(riscv) fregs
Floating-Point Registers:

f0 =0x00000000   f1 =0x3f800000   f2 =0x40000000   f3 =0x40400000
f4 =0x00000000   f5 =0x00000000   f6 =0x00000000   f7 =0x00000000
...

(riscv) freg 1
f 1:
  Hex:    0x3f800000
  Double: (use as 64-bit FP value)
```

### Usage Notes

- Values shown in hexadecimal (raw IEEE-754 format)
- f1 = 0x3f800000 is float 1.0
- f2 = 0x40000000 is float 2.0
- Useful for debugging FPU calculations in mandelbrot, etc.

## Vector Register Inspection

View vector extension status and configuration.

### Commands

```
vregs       - Show vector register status
```

### Example

```
(riscv) vregs
Vector Registers:
  VL (Vector Length):  16
  VStart:              0
  VTYPE SEW:           32 bits

  Vector register data not displayed (use vector-aware debugger)
```

### Usage Notes

- Shows VL (vector length) - number of elements to process
- Shows VStart - starting element index
- Shows SEW (Selected Element Width) in bits (8, 16, 32, 64)
- Full vector register display would show hundreds of elements

## Enhanced Trace Output

The emulator supports advanced instruction tracing with filtering and file output.

### Command-Line Options

```bash
-t                         Enable basic instruction trace
--trace-file <file>         Redirect trace to file (instead of stdout)
--trace-range <s> <e>       Only trace PC in range [start, end] (hex)
--trace-mem                 Log all memory accesses (reads/writes)
--trace-regs                Show register changes (before -> after)
--max-instructions <count>  Stop after executing N instructions (prevents infinite loops)
```

### Basic Tracing

```bash
# Trace to terminal
./bin/riscv_emulator -t --machine qemu-virt program.bin

# Trace to file (automatic redirection)
./bin/riscv_emulator --trace-file trace.txt --machine qemu-virt program.bin

# Trace specific PC range only
./bin/riscv_emulator --trace-range 80000000 80001000 --machine qemu-virt program.bin

# Trace with memory access logging
./bin/riscv_emulator --trace-mem --machine qemu-virt program.bin

# Limit execution to prevent infinite loops (bare-metal programs often loop forever)
./bin/riscv_emulator --trace-file trace.txt --max-instructions 10000 \
  --machine qemu-virt program.bin

# Combined: range + memory to file
./bin/riscv_emulator --trace-file out.txt --trace-range 80000100 80000200 \
  --trace-mem --machine qemu-virt program.bin
```

### Trace Output Format

**Basic instruction trace:**
```
80000000:  00100117  auipc   sp, 0x100
80000004:  00010113  mv      sp, sp
80000008:  00000297  auipc   t0, 0x0
8000000c:  10028293  addi    t0, t0,  256
```

**With memory access logging (--trace-mem):**
```
800000be:      00812423  [C] sw      s0,  8(sp)
    MEM: WRITE 0x800ffffb
800000c0:      00912223  [C] sw      s1,  4(sp)
    MEM: WRITE 0x800ffff7
8000007c:  00054683  lbu     a3,  0(a0)
    MEM: READ  0x800000dc
```

**With register change tracking (--trace-regs):**
```
80000000:  00100117  auipc   sp, 0x100
    REG: x 2 = 0x00000000 -> 0x80100000
80000004:  00010113  mv      sp, sp
80000008:  00000297  auipc   t0, 0x0
    REG: x 5 = 0x00000000 -> 0x80000008
8000000c:  10028293  addi    t0, t0,  256
    REG: x 5 = 0x80000008 -> 0x80000108
```

**Combined (--trace-mem --trace-regs):**
```
800000c4:  800004b7  lui     s1, 0x80000
    MEM: READ  0x800000c7
    REG: x 9 = 0x00000000 -> 0x80000000
800000c8:  80000437  lui     s0, 0x80000
    MEM: READ  0x800000cb
    REG: x 8 = 0x00000000 -> 0x80000000
800000cc:  0dc48513  addi    a0, s1,  220
    MEM: READ  0x800000cf
    REG: x 10 = 0x00000000 -> 0x800000dc
```

### Range Filtering

Limit trace output to specific PC range to focus on region of interest:

```bash
# Trace only boot code
./bin/riscv_emulator --trace-range 80000000 80000100 --machine qemu-virt program.bin

# Trace only main function (if you know the address)
./bin/riscv_emulator --trace-range 800001a0 80000300 --machine qemu-virt program.bin

# Combine with file output for large traces
./bin/riscv_emulator --trace-file func.txt --trace-range 80001000 80002000 \
  --machine qemu-virt program.bin
```

### Memory Access Tracing

Track all memory operations to debug memory issues:

```bash
# Show all memory accesses
./bin/riscv_emulator --trace-mem --machine qemu-virt program.bin

# Focus on specific function's memory accesses
./bin/riscv_emulator --trace-mem --trace-range 80001200 80001300 \
  --machine qemu-virt program.bin

# Save to file for analysis
./bin/riscv_emulator --trace-file mem.log --trace-mem \
  --machine qemu-virt program.bin
```

### Register Change Tracking

Show which registers are modified by each instruction:

```bash
# Show all register changes
./bin/riscv_emulator --trace-regs --machine qemu-virt program.bin

# Track register changes in specific function
./bin/riscv_emulator --trace-regs --trace-range 80001000 80001100 \
  --machine qemu-virt program.bin

# Combined with memory for full data flow
./bin/riscv_emulator --trace-mem --trace-regs --trace-range 80000100 80000200 \
  --machine qemu-virt program.bin

# Save detailed trace to file
./bin/riscv_emulator --trace-file debug.txt --trace-mem --trace-regs \
  --machine qemu-virt program.bin
```

### Limiting Trace Output

**IMPORTANT:** Bare-metal programs often run in infinite loops waiting for interrupts or events. Without an instruction limit, trace files will grow indefinitely.

**Prevent infinite trace files:**
```bash
# Limit to 10,000 instructions (reasonable for debugging startup code)
./bin/riscv_emulator --trace-file trace.txt --max-instructions 10000 \
  --machine qemu-virt program.bin

# Capture just boot sequence (first 5000 instructions)
./bin/riscv_emulator --trace-file boot.txt --max-instructions 5000 \
  --machine qemu-virt program.bin

# Combined with other options to trace specific function for limited time
./bin/riscv_emulator --trace-file func.txt --trace-range 80001000 80001100 \
  --trace-mem --trace-regs --max-instructions 1000 --machine qemu-virt program.bin
```

**Recommended instruction limits:**
- Boot/startup analysis: 5,000 - 10,000 instructions
- Function debugging: 1,000 - 5,000 instructions
- Full program trace: 50,000 - 100,000 instructions
- Performance profiling: 1,000,000+ instructions (use with --trace-range)

**File size estimates:**
- Basic trace: ~40 bytes/instruction
- With --trace-mem: ~60 bytes/instruction
- With --trace-regs: ~80 bytes/instruction
- With both: ~100 bytes/instruction

Example: 10,000 instructions with --trace-mem --trace-regs ~ 1 MB

### Use Cases

**Debugging Memory Corruption:**
```bash
# Track writes to specific region
./bin/riscv_emulator --trace-mem --trace-range 80002000 80003000 \
  --machine qemu-virt program.bin | grep "WRITE"
```

**Understanding Data Flow:**
```bash
# See how registers change through a function
./bin/riscv_emulator --trace-regs --trace-range 80001234 80001300 \
  --machine qemu-virt program.bin
```

**Performance Analysis:**
```bash
# Count memory operations in hot loop
./bin/riscv_emulator --trace-mem --trace-range 80001000 80001050 \
  --trace-file loop.txt --machine qemu-virt program.bin
grep -c "MEM:" loop.txt
```

### Advanced Filtering (Unix Tools)

Process trace files with standard tools:

```bash
# Count total instructions
grep -c "^8" trace.txt

# Count memory writes only
grep "MEM: WRITE" trace.txt | wc -l

# Find writes to specific address
grep "MEM: WRITE 0x10000000" trace.txt

# Extract instruction types
awk '{print $3}' trace.txt | sort | uniq -c | sort -rn | head -20

# Find hot spots (most executed addresses)
awk '{print $1}' trace.txt | cut -d: -f1 | sort | uniq -c | sort -rn | head -10
```

### Combining with Debugger

Use debugger for interactive control, trace for detailed output:

```bash
# Start in debugger
./bin/riscv_emulator -d program.bin 80000000

# At debugger prompt:
(riscv) b 0x80001000           # Set breakpoint
(riscv) watch 0x80002000 w      # Set watchpoint
(riscv) c                       # Continue with trace off
# ... breakpoint hit ...
(riscv) s                       # Single step (shows trace)
(riscv) s
(riscv) s
```

## Debugging Workflows

### Finding Memory Corruption

```
1. Set watchpoints on suspected memory regions
   (riscv) watch 0x80002000 w

2. Continue execution
   (riscv) c

3. When watchpoint hits, examine registers and stack
   (riscv) r
   (riscv) m 0x80002000 64

4. Disassemble nearby code
   (riscv) d
```

### Debugging FPU Code

```
1. Set breakpoint at FP operation
   (riscv) b 0x80001234

2. Continue to breakpoint
   (riscv) c

3. Check FP registers before operation
   (riscv) fregs

4. Step through FP instruction
   (riscv) s

5. Check FP registers after
   (riscv) fregs
   (riscv) freg 1
```

### Debugging Vector Code

```
1. Check vector configuration
   (riscv) vregs

2. Set breakpoint at vector operation
   (riscv) b 0x80005000

3. Step and monitor VL changes
   (riscv) s
   (riscv) vregs
```

## Performance Profiling

Use trace output to profile instruction counts:

```bash
# Count total instructions
./bin/riscv_emulator -t program.bin 80000000 2>&1 | \
  grep -c "^PC="

# Count by instruction type
./bin/riscv_emulator -t program.bin 80000000 2>&1 | \
  awk '{print $3}' | sort | uniq -c | sort -rn | head -20

# Find hot spots (most executed addresses)
./bin/riscv_emulator -t program.bin 80000000 2>&1 | \
  grep "^PC=" | awk '{print $1}' | sort | uniq -c | sort -rn | head -10
```

## Tips and Tricks

### Quick Register Checks

```
# Watch specific register change
(riscv) r | grep "x10"    # Won't work in debugger
# Instead: step and manually check
```

### Memory Dump Analysis

```
# Dump stack
(riscv) m 0x87fff00 256

# Dump heap (if malloc used)
(riscv) m 0x80002000 1024

# Dump code section
(riscv) d 0x80000000 50
```

### Breakpoint Strategies

```
# Break at function entry (if you know address)
(riscv) b 0x80001000

# Break at return (set at all 'ret' instructions)
# Use disassembly to find return addresses

# Break in loop (find loop start address)
(riscv) b 0x80001234
(riscv) c
# ... examine iteration ...
(riscv) c
# ... next iteration ...
```

## Limitations

1. **Vector Registers** - Limited display
   - Shows configuration (VL, VStart, VTYPE)
   - Individual element values not shown
   - Use memory dumps to see vector data

2. **Floating-Point Register Tracing** - Not yet implemented
   - --trace-regs only shows integer registers (x0-x31)
   - FP register changes not tracked in trace
   - Use `fregs` command in debugger to check FP state

## Future Enhancements

Planned for future phases:

- Conditional breakpoints (e.g., "break when x10 == 5")
- Full register change diff display (--trace-regs)
- Hardware performance counters
- Call stack unwinding
- Symbol table support (function names)
- Source-level debugging

## Recent Additions (Phase 3)

  **Watchpoints** - Fully automatic
   - Automatically trigger on memory access
   - Break execution and show hit location
   - Support read, write, or both

  **Trace to File** - Built-in file output
   - Use `--trace-file <file>` for automatic redirection
   - No need for shell redirection
   - Can produce huge traces efficiently

  **Trace Range Filtering** - Built-in PC range
   - Use `--trace-range <start> <end>` to focus output
   - Reduces trace size dramatically
   - Only traces instructions in specified range

  **Memory Access Logging** - Show all reads/writes
   - Use `--trace-mem` to see every memory operation
   - Shows address and type (READ/WRITE)
   - Combine with range for focused debugging

  **Register Change Tracking** - Show modified registers
   - Use `--trace-regs` to see register modifications
   - Shows before and after values (x10: 0x00 -> 0x05)
   - Tracks all 32 integer registers
   - Combine with memory for complete data flow

  **Instruction Limit** - Prevent infinite trace growth
   - Use `--max-instructions <count>` to limit execution
   - Essential for bare-metal programs that loop forever
   - Prevents trace files from growing to GB+ sizes
   - Recommended: 10,000 for boot analysis, 1,000 for function debugging
