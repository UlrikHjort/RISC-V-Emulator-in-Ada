# RISC-V Emulator - Testing Guide

This guide covers all testing capabilities, regression tests, and validation procedures for the RISC-V emulator.

## Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [Example Programs](#example-programs)
- [Automated Testing](#automated-testing)
- [Manual Testing](#manual-testing)
- [Regression Test Suite](#regression-test-suite)
- [Testing Different Configurations](#testing-different-configurations)
- [Troubleshooting](#troubleshooting)

---

## Overview

The RISC-V emulator includes several independent layers of testing:

| Layer | Command | Scope |
|-------|---------|-------|
| Bare-metal test suite | `cd programs && ./test-all.sh` | 83 programs, 2263 assertions |
| Ada unit tests | `make test` | Peripherals, traps, CSRs, atomics, compressed, vector |
| Official riscv-tests | `bash programs/run-riscv-tests.sh` | 284/293 upstream conformance tests |
| Architecture compliance | `arch-test/run_arch_tests.sh <suite>` (or `all`) | riscv-arch-test, 7 suites (see below) |

- **Self-reporting tests** - Each program emits its own PASS/FAIL assertions
- **Multiple machine profiles** - Test simple and qemu-virt memory layouts
- **RV32 and RV64** - Both XLENs covered, auto-detected from the ELF class

### Architecture compliance: expected results

`arch-test/run_arch_tests.sh` takes one suite name, or `all` to run every
suite in turn and print a combined summary (exit status is non-zero if any
suite has failures). These are the current per-suite numbers, so you can
tell a real regression from a known deviation:

| Suite | Result | Notes |
|-------|--------|-------|
| `I` | 38 / 38 | |
| `M` | 8 / 8 | |
| `C` | 27 / 27 | |
| `F` | 146 / 146 | |
| `Zifencei` | 1 / 1 | |
| `privilege` | 11 / 16 | the 5 `misalign-l*`/`misalign-s*` deviate by design, see below |
| `K` | 60 / 64 | 4 assembler failures, not emulator failures, see below |

**`privilege`: the five misaligned data-access tests.** `misalign-lh`, `-lhu`,
`-lw`, `-sh` and `-sw` report a signature mismatch. This is a deliberate
deviation, not a defect. The RISC-V spec lets an implementation either handle
a misaligned load/store in hardware or raise an address-misaligned exception;
this emulator handles them (see "Misaligned data loads/stores" in `STATUS.md`).
The test sources carry two case definitions, one for
`hw_data_misaligned_support:=True` and one for `False`, but the suite ships a
single reference per test, generated for the trapping variant. The official
RISCOF flow picks the matching reference from the target's YAML description;
this shell harness always compares against the trapping one, so a
misaligned-supporting target necessarily mismatches.

Note which tests still pass: all nine control-transfer misalignment tests
(`jal`, `jalr`, and the six branches) plus `ebreak` and `ecall`. Instruction
address misalignment must *always* trap, and it does. Only the cases the spec
makes optional differ.

**`K`: four compile errors.** `rev8-01`, `rev.b-01`, `unzip-01` and `zip-01`
fail before the emulator is ever invoked -- the harness passes a `-march` for
the K suite without a matching `-mabi`, and the assembler rejects it with
`requested ABI requires '-march' to subsume the 'D' extension`. A harness gap,
not an emulator result.

---

## Quick Start

### Run All Automated Tests

```bash
# Build the emulator, then run the complete test suite
make
cd programs
./test-all.sh
```

**Expected output:**
```
TEST                        PASS   FAIL STATUS
----                        ----   ---- ------
branch-test                   56      0 OK
load-store-test               56      0 OK
csr-test                      48      0 OK
trap-test                     18      0 OK
...
multihart-test                 4      0 OK
pthread-test                   7      0 OK
pipeline-test                  6      0 OK

---                         ----   ----
TOTAL                       2263      0

All tests PASSED (2263 assertions).
```

Per-test output is written to `programs/logs/`. See [STATUS.md](STATUS.md) for
the full inventory of all 83 tests and what each one asserts.

### Run Individual Tests

```bash
cd programs

# Build and run specific program
make run-fibonacci
make run-primes
make run-mandelbrot
make run-malloc-test
make run-test-runner
```

---

## Example Programs

A guided tour of eight representative programs. These are examples, not the
whole suite - `test-all.sh` runs 83 programs; see [STATUS.md](STATUS.md) for the
complete inventory.

### 1. hello.c - Basic Output Test

**What it tests:**
- UART output
- String printing
- Continuous output loop

**Run:**
```bash
cd programs
make run-hello
```

**Expected output:**
```
Hello from RISC-V!
Emulator is working!
Counter: 0
Counter: 1
Counter: 2
...
```

**Use case:** Verify basic emulator functionality

---

### 2. fibonacci.c - Algorithm Test

**What it tests:**
- Integer arithmetic
- Function calls (iterative)
- Recursion
- Call stack depth

**Run:**
```bash
cd programs
make run-fibonacci
```

**Expected output:**
```
=== Fibonacci Sequence ===

Iterative method (0-20):
fib(0) = 0
fib(1) = 1
fib(2) = 1
...
fib(20) = 6765

Recursive method (0-12):
fib(0) = 0
fib(1) = 1
...
fib(12) = 144

Done!
```

**Use case:** Test control flow, recursion, stack handling

---

### 3. primes.c - Algorithm Test

**What it tests:**
- Nested loops
- Array manipulation
- Memory access patterns
- Integer division/modulo

**Run:**
```bash
cd programs
make run-primes
```

**Expected output:**
```
=== Prime Number Finder ===
Finding primes up to 1000...

2 3 5 7 11 13 17 19 23 29 31 37 41 43 47 53 59 61 67 71
...
991 997

Found 168 primes up to 1000
Done!
```

**Use case:** Test loops, arrays, arithmetic

---

### 4. mandelbrot.c - Floating-Point Test

**What it tests:**
- FPU (F and D extensions)
- Double-precision arithmetic
- Complex calculations
- ASCII rendering

**Run:**
```bash
cd programs
make run-mandelbrot
```

**Expected output:**
```
=== Mandelbrot Set ===
Size: 80x40
Max iterations: 50

.....................:::::::::::::::::::::::::::::::...................
..................:::::::::::::::::::::::::::::::::::::::::............
..............:::::::::::::::::::::::::::::::::::::::::::::::::.......
[40 lines of ASCII art]

Done!
```

**Use case:** Test floating-point operations, FPU correctness

---

### 5. malloc-test.c - Memory Allocator Test

**What it tests:**
- malloc/free implementation
- Memory alignment (8-byte)
- Fragmentation handling
- Large allocations
- Realloc functionality

**Run:**
```bash
cd programs
make run-malloc-test
```

**Expected output:**
```
=== Memory Allocator Test ===

Test 1: Basic allocations
  Allocated 10 blocks:
  [0] at 80002c38: 42 PASS
  [1] at 80002c48: 43 PASS
  ...

Test 2: Linked list
  Node 0 at 80002d40: value = 100
  ...
  Walking backwards: 104 103 102 101 100 PASS

Test 3: Large allocation (4096 bytes)
  Large block at 80002e90 PASS

Test 4: Realloc
  Original at 80003ea0, expanded at 80003ea0 PASS

Test 5: Alignment check
  All allocations 8-byte aligned PASS

All tests complete!
```

**Use case:** Test heap allocator correctness

---

### 6. test_runner.c - Regression Test Suite

**What it tests:**
- Basic arithmetic (add, sub, mul, div, mod)
- Bitwise operations (and, or, xor, shift)
- Memory alignment (word, halfword, byte)
- Control flow (if, for, while, break, continue)
- Function calls and recursion
- Floating-point operations
- Memory allocation
- Printf formatting

**Run:**
```bash
cd programs
make run-test-runner
```

**Expected output:**
```
======================================
   RISC-V Emulator Regression Tests
======================================

=== Basic Arithmetic ===
  Test: Addition... PASS
  Test: Subtraction... PASS
  Test: Multiplication... PASS
  Test: Division... PASS
  Test: Modulo... PASS
  Test: Negative numbers... PASS
  Test: Overflow wrap... PASS

=== Bitwise Operations ===
  Test: AND... PASS
  Test: OR... PASS
  Test: XOR... PASS
  Test: NOT... PASS
  Test: Left shift... PASS
  Test: Right shift... PASS
  Test: Arithmetic right shift (signed)... PASS

[... more tests ...]

======================================
Test Summary
======================================
Total:  50
Passed: 50
Failed: 0

SUCCESS: All tests passed!
```

**Use case:** Comprehensive regression testing after changes

---

### 7. echo.c - Interactive Test (Manual)

**What it tests:**
- Character input via UART
- Character output
- Terminal interaction

**Run:**
```bash
cd programs
make run-echo
# In another terminal:
minicom -D /dev/pts/X  # Use the PTY shown
```

**Expected behavior:**
- Each character typed is echoed back
- Press 'q' to quit

**Use case:** Test UART input/output interactivity

---

### 8. forth.c - Interactive Test (Manual)

**What it tests:**
- Forth interpreter
- Complex input parsing
- Stack operations
- Interactive REPL

**Run:**
```bash
cd programs
make run-forth
# In another terminal:
minicom -D /dev/pts/X
```

**Example interaction:**
```
Forth Interpreter (minimal)
> 5 3 + .
8  ok
> 10 2 * .
20  ok
> : square dup * ;
 ok
> 7 square .
49  ok
> bye
```

**Use case:** Test complex interactive programs

---

## Automated Testing

### Running test-all.sh

The automated test runner script:

```bash
cd programs
./test-all.sh              # run existing binaries, build only what is missing
./test-all.sh --rebuild    # force-rebuild every test binary first
```

**What it does:**
1. Builds any missing test binaries (all of them with `--rebuild`)
2. Runs each test under the emulator, writing per-test output to `programs/logs/`
3. Counts PASS/FAIL assertions reported by the program itself
4. Prints a per-test table plus a `TOTAL` row
5. Exits non-zero if any assertion failed

**How a test reports results:**

Each test program links `log.c` and uses the semihosting log ECALLs to emit
`PASS`/`FAIL` lines. The runner counts those lines - it does not compare against
stored golden output, so tests stay valid when unrelated output changes.

**Note on how tests are loaded:** most tests run as a raw `.bin` loaded at
`80000000` (no `0x` prefix), not as an ELF. If you edit a test's C source you
must rebuild both `out/elf/<test>.elf` and `out/bin/<test>.bin`.

### Interactive Programs

Interactive programs are not part of `test-all.sh` because they need keyboard
input:
- **echo** - Requires keyboard input
- **forth** - Requires interactive commands
- **falling-tiles**, **snake-game** - Playable demos

Test these manually using a PTY connection (see [Manual Testing](#manual-testing)).

---

## Manual Testing

### Testing with PTY (Pseudo-Terminal)

For interactive programs:

**Step 1: Start emulator with --wait**
```bash
cd programs
make run-echo
# Or manually:
./bin/riscv_emulator --machine qemu-virt --pty --wait echo.elf
```

Output shows:
```
PTY created: /dev/pts/5
Waiting for PTY connection...
```

**Step 2: Connect from another terminal**
```bash
# Option 1: minicom
minicom -D /dev/pts/5

# Option 2: screen
screen /dev/pts/5

# Option 3: cat/echo (one-way)
cat /dev/pts/5          # Read output only
echo "test" > /dev/pts/5  # Write input only
```

**Step 3: Interact**

Type characters, see output, test program behavior.

**Step 4: Exit**
- Minicom: `Ctrl-A X`
- Screen: `Ctrl-A K` then `y`
- Cat: `Ctrl-C`

---

## Regression Test Suite

The `test_runner.c` program provides comprehensive unit testing.

### Test Categories

**1. Basic Arithmetic (7 tests)**
- Addition, subtraction, multiplication, division
- Modulo operation
- Negative numbers
- Overflow wrapping

**2. Bitwise Operations (7 tests)**
- AND, OR, XOR, NOT
- Left shift, right shift
- Arithmetic right shift (signed)

**3. Memory Alignment (8 tests)**
- Word (32-bit) loads and stores
- Halfword (16-bit) loads and stores
- Byte (8-bit) loads and stores
- Unaligned access handling

**4. Control Flow (8 tests)**
- If statements (true/false)
- If-else (ternary operator)
- For loops
- While loops
- Break and continue
- Loop counters and accumulators

**5. Function Calls (3 tests)**
- Simple function calls
- Recursive functions (factorial)
- Stack depth testing

**6. Floating-Point (10 tests)**
- FP addition, subtraction, multiplication, division
- FP comparisons (>, ==, <)
- Special values (zero, negative)
- Type conversions (int<->float)

**7. Memory Allocation (4 tests)**
- Single allocations
- Array allocations
- Large blocks (1024+ bytes)
- 8-byte alignment verification

**8. Printf (4 tests)**
- Integer formatting (%d)
- Hex formatting (%x)
- String formatting (%s)
- Multiple arguments

### Running Regression Tests

`test_runner.c` is an interactive UART program, so it is run over a PTY rather
than by `test-all.sh`:

```bash
cd programs
make run-test-runner
# then connect from another terminal: minicom -D /dev/pts/X
```

**Success criteria:**
- All 50+ tests pass
- Exit code 0
- Output shows "SUCCESS: All tests passed!"

**Failure handling:**
- Failed tests show line number
- Expected vs actual values displayed
- Exit code 1

---

## Testing Different Configurations

### Machine Profiles

Test with different memory maps and peripherals:

**Simple profile (default):**
```bash
./bin/riscv_emulator program.elf
# RAM at 0x00000000
# UART at 0x10000000
```

**QEMU-virt profile:**
```bash
./bin/riscv_emulator --machine qemu-virt program.elf
# RAM at 0x80000000
# UART at 0x10000000
```

**Embedded profile:**
```bash
./bin/riscv_emulator --machine embedded program.elf
# Custom peripheral layout
```

### Instruction Limits

Prevent infinite loops during testing:

```bash
# Stop after 1 million instructions
./bin/riscv_emulator --max-instructions 1000000 program.elf

# For profiling (shorter runs)
./bin/riscv_emulator --max-instructions 100000 program.elf
```

### Quiet Mode

Suppress program output (for automated testing):

```bash
./bin/riscv_emulator --quiet program.elf
```

---

## Troubleshooting

### Test Failures

**"Emulator not found"**
```bash
# Build the emulator first
make
```

**"RISC-V toolchain not found"**
```bash
# Install toolchain
sudo apt install gcc-riscv64-unknown-elf

# Or install from RISC-V website
```

**"Failed to build programs"**
```bash
# Check for compilation errors
cd programs
make clean
make all
```

**"Test timeout"**
- Program may have an infinite loop
- Run it directly with `--max-instructions <n>` or `--timeout <seconds>`
- Add `-t` to see where it is spinning

**"Test reports FAIL assertions"**
- Read the per-test log in `programs/logs/<test>.log`
- Re-run that single test directly for full output:
  `./bin/riscv_emulator --machine qemu-virt programs/out/bin/<test>.bin 80000000`
- Remember to rebuild both the `.elf` and the `.bin` after editing a test source

### PTY Connection Issues

**"Permission denied on /dev/pts/X"**
```bash
# Add user to tty group
sudo usermod -a -G tty $USER
# Log out and back in
```

**"Cannot connect to PTY"**
- Make sure emulator is running with `--wait`
- Use exact PTY path shown by emulator
- Check PTY exists: `ls -l /dev/pts/X`

**"No input/output on PTY"**
- Some terminal emulators buffer - try `screen` or `minicom`
- Check UART is at correct address for machine profile
- Enable trace mode to debug: `-t`

### Common Issues

**Test runner reports failures**
- Check which specific test failed (line number shown)
- Run with trace: `./bin/riscv_emulator --machine qemu-virt -t programs/out/elf/<test>.elf`
- May indicate emulator bug or missing feature

**FPU tests fail**
- Ensure F and D extensions enabled (they are by default)
- Check floating-point rounding modes
- Verify NaN/Inf handling

**Malloc tests fail**
- Check heap initialization in crt0.S
- Verify .bss section cleared properly
- Check alignment constraints

---

## Test Development

### Adding New Tests

**1. Create test program**

Create `programs/mytest.c`. Tests report results through the semihosting log,
not stdout, so the runner can count assertions:

```c
#include <stdint.h>
#include "log.h"

static int g_pass = 0;
static int g_fail = 0;

static void chk(const char *name, int cond)
{
    if (cond) {
        log_write(NONE, "PASS: %s\n", name);
        g_pass++;
    } else {
        log_write(NONE, "FAIL: %s\n", name);
        g_fail++;
    }
}

int main(void)
{
    log_init("mytest.log");

    chk("addition", 2 + 2 == 4);

    log_write(NONE, "\nTOTAL: %d passed, %d failed\n", g_pass, g_fail);
    log_close();
    return g_fail == 0 ? 0 : 1;
}
```

**2. Add to the Makefile**

Edit `programs/Makefile` and add `mytest` alongside the existing tests so both
`out/elf/mytest.elf` and `out/bin/mytest.bin` are produced, plus a `run-mytest`
target.

**3. Register it with the runner**

Add a row to the `TESTS` array in `programs/test-all.sh`:

```bash
    "mytest            mytest            mytest.log"
```

The columns are: test name, make target, log file, and an optional format
(`bin` is the default; use `elf`, `rv32e`, or `rv64e` where needed).

**4. Test it**
```bash
cd programs
./test-all.sh --rebuild
```

---

## Continuous Integration

The test suite is CI-ready:

```yaml
# .github/workflows/test.yml example
name: Test RISC-V Emulator

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2

      - name: Install RISC-V Toolchain
        run: sudo apt install gcc-riscv64-unknown-elf

      - name: Build Emulator
        run: make

      - name: Run Tests
        run: cd programs && ./test-all.sh --rebuild
```

Exit codes:
- **0** - All tests passed
- **1** - Some tests failed

---

## Performance Testing

### Benchmarking

Use instruction counting for consistent benchmarks:

```bash
# Measure instructions executed
./bin/riscv_emulator --profile --max-instructions 1000000 program.elf

# Compare implementations
./bin/riscv_emulator --machine qemu-virt --profile programs/out/elf/fibonacci.elf > fib.txt
./bin/riscv_emulator --machine qemu-virt --profile programs/out/elf/coremark-test.elf > core.txt
diff fib.txt core.txt
```

### Profiling Tests

Use profiling tools on test programs:

```bash
# Profile test_runner
./bin/riscv_emulator --machine qemu-virt --profile --quiet programs/out/elf/coremark-test.elf

# Generate flamegraph
./bin/riscv_emulator --machine qemu-virt --flamegraph test.fg programs/out/elf/coremark-test.elf
flamegraph.pl test.fg > test-profile.svg
```

---

## See Also

- [README.md](README.md) - Main documentation
- [doc/DEBUGGING.md](doc/DEBUGGING.md) - Debugging features
- [doc/PROFILING.md](doc/PROFILING.md) - Performance profiling
- [doc/GDB.md](doc/GDB.md) - GDB remote debugging
- [doc/TESTING.md](doc/TESTING.md) - Ada unit tests (`make test`)
- [STATUS.md](STATUS.md) - Full per-test assertion inventory
