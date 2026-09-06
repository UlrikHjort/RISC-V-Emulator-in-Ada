# RISC-V Emulator - Profiling Guide

This guide covers all the profiling and performance analysis features available in the RISC-V emulator.

## Table of Contents

- [Overview](#overview)
- [Basic Profiling](#basic-profiling)
- [Call Graph Analysis](#call-graph-analysis)
- [Flamegraph Visualization](#flamegraph-visualization)
- [Instruction Coverage](#instruction-coverage)
- [Binary Trace and Replay](#binary-trace-and-replay)
- [Performance Analysis Workflows](#performance-analysis-workflows)
- [Understanding the Output](#understanding-the-output)
- [Examples](#examples)

---

## Overview

The RISC-V emulator includes comprehensive profiling capabilities:

- **Per-function profiling** - Instruction and cycle counts
- **Call graph tracking** - Which functions call which
- **Flamegraph export** - Visual performance analysis
- **Hotspot identification** - Find performance bottlenecks

All profiling features work with ELF files containing symbol tables.

---

## Basic Profiling

### Running with Profiling Enabled

```bash
./bin/riscv_emulator --profile program.elf
```

**Important:** Use an instruction limit to prevent overflow:

```bash
./bin/riscv_emulator --profile --max-instructions 100000 program.elf
```

### Basic Profiling Output

```
=== Profiling Report ===
Total cycles: 100000

Function Profile (sorted by cycles):
Cycles    %Time  Instructions  Calls  Function
--------  -----  ------------  -----  --------------------------------
 98562   98%   98562   0  puts
 1430   1%   1430   0  main
```

### Output Columns Explained

- **Cycles** - Total cycles spent in this function
- **%Time** - Percentage of total execution time
- **Instructions** - Number of instructions executed
- **Calls** - Number of times this function was called
- **Function** - Function name from symbol table

---

## Call Graph Analysis

The call graph shows which functions call which other functions.

### Enabling Call Graph

Call graphs are automatically generated with `--profile`:

```bash
./bin/riscv_emulator --profile --max-instructions 50000 programs/out/elf/fibonacci.elf
```

### Call Graph Output

```
=== Call Graph ===
Calls  Caller -> Callee
-----  --------------------------------
 523  main -> printf
 414  printf -> putchar
 190  printf -> put_int
 120  put_int -> putchar
 49  main -> fib_recursive
```

### Understanding Call Graph

Each line shows:
- **Calls** - Number of times the call happened
- **Caller -> Callee** - Function call relationship

Example: `523  main -> printf` means:
- Function `main` called `printf` 523 times

### Use Cases

1. **Understanding program flow**
   ```
   523  main -> printf
   ```
   Shows main calls printf frequently

2. **Identifying call hotspots**
   ```
   414  printf -> putchar
   ```
   Printf spends most time in putchar

3. **Analyzing recursion**
   ```
   49  main -> fib_recursive
   24  fib_recursive -> fib_recursive
   ```
   Shows recursive calls

---

## Flamegraph Visualization

Flamegraphs provide visual insight into where your program spends time.

### Generating Flamegraph Data

```bash
./bin/riscv_emulator --flamegraph output.fg --max-instructions 100000 program.elf
```

Optional: Specify custom output filename:
```bash
./bin/riscv_emulator --flamegraph myprogram.fg program.elf
```

### Output

```
Flamegraph data written to output.fg
Generate SVG with: flamegraph.pl output.fg > flamegraph.svg
```

### Flamegraph File Format

The `.fg` file uses folded stack format:

```
main;printf 82
main 276
main;printf;put_int 16
main;fib_recursive 6
```

Each line shows:
- **Stack trace** - Semicolon-separated function chain (bottom to top)
- **Sample count** - How many times this exact stack was observed

### Creating SVG Visualization

Install Brendan Gregg's flamegraph tool:

```bash
git clone https://github.com/brendangregg/FlameGraph
cd FlameGraph
```

Generate SVG:

```bash
./flamegraph.pl output.fg > flamegraph.svg
```

Open in browser:
```bash
firefox flamegraph.svg
# or
google-chrome flamegraph.svg
```

### Reading Flamegraphs

- **Width** - Proportional to time spent
- **Height** - Call stack depth
- **Color** - Random (for differentiation only)
- **X-axis** - Alphabetically sorted (not time!)
- **Interactive** - Click to zoom, search functions

**Example interpretation:**
- Wide bars = Functions using lots of CPU time
- Tall stacks = Deep call chains
- Click a bar to zoom into that subtree

---

---

## Instruction Coverage

Coverage tracking records which instruction addresses were actually executed and reports
the percentage covered, both overall and per-function.

### Running Coverage Analysis

```bash
# Write report to coverage.txt (default filename)
./bin/riscv_emulator --machine qemu-virt --coverage program.elf

# Custom output filename
./bin/riscv_emulator --machine qemu-virt --coverage my_coverage.txt program.elf

# Combine with profiling (both run in the same loop)
./bin/riscv_emulator --machine qemu-virt --profile --coverage coverage.txt program.elf
```

### Coverage Report Format

```
=== RISC-V Instruction Coverage Report ===
Base PC : 0x80000000
Slots   :  894  ( 3576 bytes)
Covered :  608 /  894  068.0%

--- Per-Function Coverage ---

sha256_block                             100.0%  ( 137 / 137)
sha256                                   089.5%  (  77 /  86)
check_hash                               060.6%  (  20 /  33)
log_write                                037.7%  ( 131 / 347)
puts                                     000.0%  (   0 /  16)
main                                     088.4%  ( 176 / 199)
```

### Notes

- Per-function stats require an **ELF file** (raw `.bin` files have no symbol table).
- The bitmap covers 1 MB of code starting from the first observed PC.
- Functions with 0% coverage indicate dead code paths not exercised by the current test.
- The `Slots` line counts 4-byte instruction slots; actual bytes = Slots * 4.

### Use Cases

- **Test quality** - find functions or branches never reached by the test suite
- **Dead code** - identify unreachable code (0% functions)
- **Coverage gating** - fail CI if total coverage drops below a threshold

---

## Binary Trace and Replay

The trace/replay feature records a binary log of every instruction executed and can
replay it against a second run to detect any divergence.

### Trace Record Format

Each record is **20 bytes**:

| Offset | Field    | Description |
|--------|----------|-------------|
| 0      | PC       | Program counter before execution |
| 4      | Encoding | Raw 32-bit instruction word |
| 8      | Rd       | Destination register index (0 = none/x0) |
| 12     | Rd_Value | Value written to Rd after execution |
| 16     | Next_PC  | Program counter after execution |

### Recording a Trace

```bash
./bin/riscv_emulator --machine qemu-virt --irecord run.trace program.elf
```

Output:
```
Instruction trace written to run.trace ( 60630 records)
```

File size = records * 20 bytes (60630 records ~ 1.2 MB).

### Replaying and Verifying

```bash
./bin/riscv_emulator --machine qemu-virt --ireplay run.trace program.elf
```

On success:
```
Replay OK - 60630 steps matched.
```

On mismatch (different binary, modified emulator, etc.):
```
MISMATCH at step 4 PC=0x8000000c x5=0x80001140 expected=0x80001438
Replay FAILED - 1 mismatch(es).
```

The replay stops at the **first** mismatch and reports:
- Which step diverged
- The PC where it happened
- The field that differs (next PC or register value) and both actual/expected values

### Use Cases

- **Regression testing** - record a known-good run; replay after emulator changes to detect bugs
- **Determinism verification** - confirm two runs of the same program are bit-for-bit identical
- **Bisecting emulator bugs** - compare traces before and after a change to find the first bad instruction
- **Differential debugging** - record reference run from a trusted emulator; replay on the one under test

### Example: Emulator Regression Workflow

```bash
# 1. Record reference trace with current (known-good) emulator
./bin/riscv_emulator --machine qemu-virt --irecord ref.trace program.elf

# 2. Make changes to emulator source
# ... edit src/ ...
make

# 3. Replay reference trace against modified emulator
./bin/riscv_emulator --machine qemu-virt --ireplay ref.trace program.elf
# Replay OK - 60630 steps matched.   <- no regression
# MISMATCH at step 1234 ...          <- something broke
```

---

## Performance Analysis Workflows

### Workflow 1: Find Hotspots

**Goal:** Identify which functions use the most CPU time

```bash
# Run with profiling
./bin/riscv_emulator --profile --max-instructions 100000 program.elf

# Look at top functions in report
```

Example output:
```
Cycles    %Time  Instructions  Calls  Function
 45000   45%   45000   100  expensive_function    <- HOTSPOT
 30000   30%   30000   1000 helper_function       <- HOTSPOT
 15000   15%   15000   10   main
```

**Action:** Optimize `expensive_function` and `helper_function`

### Workflow 2: Analyze Call Patterns

**Goal:** Understand function call relationships

```bash
# Generate call graph
./bin/riscv_emulator --profile --max-instructions 50000 program.elf

# Review call graph section
```

Example analysis:
```
Calls  Caller -> Callee
1000  main -> process_item           <- Called frequently
1000  process_item -> validate       <- Each process validates
1000  validate -> check_bounds       <- Deep call chain
```

**Insight:** Each item goes through 3 function calls. Consider inlining or reducing call overhead.

### Workflow 3: Visual Analysis

**Goal:** Get visual overview of performance

```bash
# Generate flamegraph
./bin/riscv_emulator --flamegraph data.fg --max-instructions 200000 program.elf

# Create SVG
flamegraph.pl data.fg > profile.svg

# Open in browser
firefox profile.svg
```

**Look for:**
- Wide flat bars (hotspots)
- Tall thin spikes (deep call chains)
- Repeated patterns (optimization opportunities)

### Workflow 4: Before/After Comparison

**Goal:** Measure optimization impact

```bash
# Profile before optimization
./bin/riscv_emulator --profile --max-instructions 100000 program_before.elf > before.txt

# Profile after optimization
./bin/riscv_emulator --profile --max-instructions 100000 program_after.elf > after.txt

# Compare
diff before.txt after.txt
```

Or compare flamegraphs:
```bash
./bin/riscv_emulator --flamegraph before.fg --max-instructions 100000 program_before.elf
./bin/riscv_emulator --flamegraph after.fg --max-instructions 100000 program_after.elf

# Generate differential flamegraph
flamegraph.pl --diff before.fg after.fg > comparison.svg
```

---

## Understanding the Output

### Instruction Count vs Wall Cycle Count

The profiler uses a **cycle-accurate stall model** to compute wall cycles per function.
Each instruction costs 1 base cycle plus any stall cycles:

| Instruction type | Extra stall cycles |
|------------------|--------------------|
| MUL/MULH/MULHU/MULHSU | +2 |
| DIV/DIVU/REM/REMU | +32 |
| FADD/FSUB/FMUL (F/D/H), FMA | +3 |
| FDIV/FSQRT (F/D/H) | +19 |
| CSR instructions | +1 |
| Load-use hazard | +1 |
| Branch/jump taken | +1 |

The report shows **total wall cycles**, **average CPI**, and a per-category stall breakdown:

```
Total wall cycles : 1054321
Average CPI       : 1.23
Stall breakdown:
  MUL/MULH  (+2): 1234 (12%)
  DIV/REM  (+32): 280 (3%)
  FP arith (+3/+19): 7700 (73%)
  CSR       (+1): 45 (0%)
  Load-use  (+1): 890 (8%)
  Branch/jump (+1): 412 (4%)
```

**Note:** Cache stalls (see below) are added to wall cycles but do NOT affect the `mcycle` CSR -
this preserves correctness of timing tests that use `rdcycle` for measurement.

### Load-Use Hazard Stalls

A **load-use hazard** occurs when the instruction immediately following a LOAD reads the
register written by that LOAD. In a classic 5-stage pipeline the loaded value is not
available until the end of the MEM stage, so the dependent instruction must be held in
the decode stage for one extra cycle - forwarding cannot help here.

Example (stall inserted between `lw` and `add`):
```asm
lw   a0, 0(sp)      # load
add  a1, a0, a2     # uses a0 immediately - 1 stall cycle
```

**How to reduce load-use stalls:**
- Insert an independent instruction between the load and its first use (instruction scheduling).
- Reorder surrounding code so an unrelated instruction naturally fills the slot.
- Compiler option `-O2` or higher will usually schedule loads automatically.

### Branch/Jump Taken Stalls

A **branch/jump taken** stall is charged whenever a branch is taken, a `JAL` executes,
or a `JALR` executes. The pipeline must refill from the new PC, discarding the
speculatively fetched instruction - one wasted cycle per non-sequential transfer.

**How to reduce branch/jump stalls:**
- Keep hot loop bodies small so the branch-taken path is the rare case (loop ends, not
  loop bodies, should be the taken branch).
- Consider loop unrolling to reduce the number of backward branches.
- Arrange `if/else` chains so the common case falls through (not-taken) rather than jumps.

### Call Count

The profiler tracks function entry/exit to count calls. Note:
- Tail calls may not be counted
- Inline functions are not tracked
- Interrupts/exceptions not included

### Sampling Interval

Flamegraphs sample the call stack every **100 cycles** by default.

This means:
- Functions with < 100 cycles may not appear
- Stack traces are statistical approximations
- More samples = better accuracy

To change sampling interval (requires code modification):
```ada
-- In riscv-profiler.ads, change:
Sample_Interval : Natural := 100;  -- Lower = more samples, slower
```

---

## Examples

### Example 1: Simple Performance Check

```bash
# Quick profile with limited instructions
./bin/riscv_emulator --profile --max-instructions 50000 program.elf
```

Output shows top functions:
```
Cycles    %Time  Instructions  Calls  Function
 35000   70%   35000   500  sort_array
 10000   20%   10000   100  compare
  5000   10%    5000   1    main
```

**Insight:** 70% of time is in `sort_array`. Optimize sorting algorithm.

### Example 2: Call Graph Analysis

```bash
./bin/riscv_emulator --profile --max-instructions 100000 programs/out/elf/fibonacci.elf
```

Output:
```
=== Call Graph ===
Calls  Caller -> Callee
 523  main -> printf
 414  printf -> putchar
 190  printf -> put_int
 120  put_int -> putchar
  49  main -> fib_recursive
```

**Insights:**
- Main calls printf 523 times (lots of output)
- Printf delegates to putchar (414 times) and put_int (190 times)
- Recursive fibonacci is called 49 times from main

### Example 3: Full Flamegraph Workflow

```bash
# 1. Run profiling with flamegraph export
./bin/riscv_emulator --flamegraph fib.fg --max-instructions 100000 programs/out/elf/fibonacci.elf

# 2. Check the output file
cat fib.fg
main;printf 82
main 276
main;printf;put_int 16
main;fib_recursive 6

# 3. Generate SVG (requires flamegraph.pl)
# Download from: https://github.com/brendangregg/FlameGraph
flamegraph.pl fib.fg > fib.svg

# 4. View in browser
firefox fib.svg
```

In the flamegraph:
- Click on `main` to zoom into it
- Wide `printf` bar shows it's a hotspot
- Narrow `fib_recursive` shows less time spent

### Example 4: Comparing Implementations

```bash
# Profile iterative version
./bin/riscv_emulator --profile --max-instructions 50000 fib_iterative.elf > iter.txt

# Profile recursive version
./bin/riscv_emulator --profile --max-instructions 50000 fib_recursive.elf > rec.txt

# Compare
grep "fib_" iter.txt
grep "fib_" rec.txt
```

Results show:
- Iterative: 1000 cycles, 1 call
- Recursive: 50000 cycles, 1000 calls

**Insight:** Recursive version is 50x slower due to call overhead.

### Example 5: Cache Simulation - Finding Memory Bottlenecks

This example uses the included `coremark-test` benchmark to show how cache size affects
wall-cycle counts.

#### Step 1 - Run without cache (instruction count only)

```bash
bin/riscv_emulator --machine qemu-virt --profile \
    --log-dir logs \
    programs/out/elf/coremark-test.elf
```

Example output (abbreviated):
```
=== Function Profile (by WallCyc) ===
WallCyc   %Time  Instrs   Calls  Function
  38210   42%    38210    500    list_sort
  22105   24%    22105    500    crc_bench
  17432   19%    17432    500    mat_bench
  12801   14%    12801    500    state_machine

Total wall cycles : 91234
Average CPI       : 1.00
Stall breakdown:
  MUL/MULH  (+2): 0 (0%)
  DIV/REM  (+32): 0 (0%)
  FP arith (+3/+19): 0 (0%)
  CSR       (+1): 12 (100%)
  Load-use  (+1): 0 (0%)
  Branch/jump (+1): 0 (0%)
```

CPI is 1.00 - no stall model contribution yet because coremark uses integer ops.

#### Step 2 - Enable a small (2KB) I-cache and D-cache to simulate a tiny MCU

```bash
bin/riscv_emulator --machine qemu-virt --profile \
    --log-dir logs \
    --icache 2 --dcache 2 \
    programs/out/elf/coremark-test.elf
```

Example output with cache stats:
```
Total wall cycles : 143860
Average CPI       : 1.58

=== Cache Simulation ===
I-Cache (2KB 4-way): Hits=86104  Misses=5130  (94.4%)  Stall cycles=102600
D-Cache (2KB 4-way): Hits=41920  Misses=2603  (94.2%)  Stall cycles= 52060
```

Wall cycles jumped from 91K to 144K - a **58% increase** driven by cache misses on the
small 2KB caches.

#### Step 3 - Increase to 32KB (typical Cortex-M4 cache size)

```bash
bin/riscv_emulator --machine qemu-virt --profile \
    --log-dir logs \
    --icache 32 --dcache 32 \
    programs/out/elf/coremark-test.elf
```

Example output:
```
Total wall cycles : 93710
Average CPI       : 1.03

=== Cache Simulation ===
I-Cache (32KB 4-way): Hits=91118  Misses=116   (99.9%)  Stall cycles= 2320
D-Cache (32KB 4-way): Hits=44490  Misses= 33   (99.9%)  Stall cycles=  660
```

At 32KB the benchmark fits almost entirely in cache - wall cycles are only 3% above
the no-cache baseline.

#### Step 4 - Combine cache simulation with flamegraph

```bash
bin/riscv_emulator --machine qemu-virt --profile \
    --flamegraph coremark.fg \
    --icache 2 --dcache 2 \
    programs/out/elf/coremark-test.elf

flamegraph.pl coremark.fg > coremark.svg
firefox coremark.svg
```

The flamegraph proportions now reflect **wall cycles including cache stalls**, so
functions with poor locality appear wider relative to their instruction count.

#### Summary table

| Cache size | Wall cycles | CPI  | I-miss% | D-miss% |
|------------|-------------|------|---------|---------|
| none       | ~91 K       | 1.00 | -       | -       |
| 2 KB       | ~144 K      | 1.58 | 5.6%    | 5.8%    |
| 8 KB       | ~97 K       | 1.07 | 1.2%    | 1.5%    |
| 32 KB      | ~94 K       | 1.03 | 0.1%    | 0.1%    |

---

## Profiling Best Practices

### 1. Always Use Instruction Limits

```bash
# Good
./bin/riscv_emulator --profile --max-instructions 100000 program.elf

# Bad - may overflow!
./bin/riscv_emulator --profile program.elf
```

### 2. Use Representative Workloads

Profile with realistic input:
```bash
# Better - realistic workload
./bin/riscv_emulator --profile --max-instructions 1000000 program.elf < real_input.txt

# Worse - trivial input
./bin/riscv_emulator --profile program.elf
```

### 3. Focus on Hotspots

Don't optimize everything - focus on the top 20%:
- Look at functions with >10% total time
- Ignore small, rarely-called functions
- Profile again after each optimization

### 4. Combine Techniques

Use multiple profiling methods:
```bash
# Get numeric data
./bin/riscv_emulator --profile program.elf > profile.txt

# Get visual overview
./bin/riscv_emulator --flamegraph program.fg program.elf
flamegraph.pl program.fg > visual.svg
```

### 5. Verify Optimizations

Always measure before and after:
```bash
# Before
./bin/riscv_emulator --profile --max-instructions 100000 old.elf

# After optimization
./bin/riscv_emulator --profile --max-instructions 100000 new.elf

# Compare cycle counts
```

---

## Command Reference

### Analysis Flags

| Flag | Description | Example |
|------|-------------|---------|
| `--profile` | Enable profiler (function/opcode/call graph) | `--profile` |
| `--flamegraph [FILE]` | Profiler + export flamegraph (default: flamegraph.fg) | `--flamegraph out.fg` |
| `--coverage [FILE]` | Instruction coverage report (default: coverage.txt) | `--coverage cov.txt` |
| `--irecord FILE` | Record binary instruction trace | `--irecord run.trace` |
| `--ireplay FILE` | Replay and verify against trace | `--ireplay run.trace` |
| `--max-instructions N` | Stop after N instructions | `--max-instructions 100000` |
| `--quiet` | Suppress informational output | `--quiet` |

### Example Commands

```bash
# Basic profiling
./bin/riscv_emulator --machine qemu-virt --profile program.elf

# Profiling with flamegraph
./bin/riscv_emulator --machine qemu-virt --flamegraph data.fg program.elf

# Coverage report
./bin/riscv_emulator --machine qemu-virt --coverage cov.txt program.elf

# Profile + coverage combined
./bin/riscv_emulator --machine qemu-virt --profile --coverage cov.txt program.elf

# Record trace, then replay for regression check
./bin/riscv_emulator --machine qemu-virt --irecord run.trace program.elf
./bin/riscv_emulator --machine qemu-virt --ireplay run.trace program.elf

# Quiet profiling (suppress program UART output)
./bin/riscv_emulator --machine qemu-virt --profile --quiet program.elf
```

---

## Troubleshooting

### "No profiling data collected"

**Cause:** Program didn't execute enough instructions

**Solution:** Increase instruction limit:
```bash
./bin/riscv_emulator --profile --max-instructions 1000000 program.elf
```

### "No symbols loaded"

**Cause:** Not using an ELF file or symbols stripped

**Solution:** Use ELF file with symbols:
```bash
# Compile with debug symbols
riscv32-unknown-elf-gcc -g program.c -o program.elf

# Profile
./bin/riscv_emulator --profile program.elf
```

### "overflow check failed"

**Cause:** Ran too many instructions without limit

**Solution:** Always use `--max-instructions`:
```bash
./bin/riscv_emulator --profile --max-instructions 100000 program.elf
```

### "No call graph data collected"

**Cause:** Program has no function calls (e.g., single main function)

**Solution:** This is normal for simple programs. Call graphs only appear when functions call other functions.

---

## Advanced Topics

### Custom Profiling Intervals

The profiler samples every 100 cycles by default. To change (requires source modification):

Edit `src/riscv-profiler.ads`:
```ada
Sample_Interval : Natural := 100;  -- Change this value
```

- **Lower** = More samples, better accuracy, larger output
- **Higher** = Fewer samples, less accurate, smaller output

### Profiling Long-Running Programs

For programs that need >1 million instructions:

```bash
# Use very large limit
./bin/riscv_emulator --profile --max-instructions 10000000 program.elf
```

Consider splitting analysis:
1. Profile initialization separately
2. Profile main loop separately
3. Combine insights

### Differential Flamegraphs

Compare two versions:

```bash
# Generate both profiles
./bin/riscv_emulator --flamegraph before.fg --max-instructions 100000 old.elf
./bin/riscv_emulator --flamegraph after.fg --max-instructions 100000 new.elf

# Create differential flamegraph (requires flamegraph.pl from GitHub)
./FlameGraph/difffolded.pl before.fg after.fg | ./FlameGraph/flamegraph.pl > diff.svg
```

Red = increased time, Blue = decreased time

---

---

## L1 Cache Simulation

The emulator can simulate a set-associative L1 I-cache and D-cache alongside the profiler.
Cache stalls are added to the profiler's wall-cycle totals (but not to the `mcycle` CSR).

### CLI Flags

```bash
# Combined I+D cache (32KB 4-way each, 64B lines, 20-cycle miss penalty)
./bin/riscv_emulator --machine qemu-virt --profile --cache program.elf

# Custom sizes (KB)
./bin/riscv_emulator --machine qemu-virt --profile --icache 16 --dcache 32 program.elf
```

| Flag | Description |
|------|-------------|
| `--cache` | Enable I+D cache (32KB, 4-way, 64B lines) |
| `--icache <kb>` | Set I-cache size in KB (implies cache enable) |
| `--dcache <kb>` | Set D-cache size in KB (implies cache enable) |

### Cache Parameters

| Parameter | Default | Notes |
|-----------|---------|-------|
| Size | 32 KB | Configurable via `--icache`/`--dcache` |
| Ways | 4 | LRU replacement |
| Line size | 64 B | Fixed |
| Miss penalty | 20 cycles | Added to wall cycles |
| Max sets | 256 | `size_KB * 1024 / (ways * 64)`, clamped |

### Cache Stats Output

At the end of `--profile` output, a cache section is printed:

```
=== Cache Simulation ===
I-Cache: Hits=98432  Misses=1568  (98.4% hit rate)  Stall cycles=31360
D-Cache: Hits=71201  Misses=2847  (96.2% hit rate)  Stall cycles=56940
```

---

## See Also

- [Debugging Guide](DEBUGGING.md) - Interactive debugging features
- [GDB Remote Debugging](GDB.md) - Using GDB with the emulator
- [Brendan Gregg's FlameGraph](https://github.com/brendangregg/FlameGraph) - Flamegraph tools
- [README.md](README.md) - Main documentation
