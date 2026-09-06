# Testing

The emulator includes both unit tests and program tests.

## Unit Tests

### Running Unit Tests

```bash
make test
```

This builds and runs `test/test_peripherals.adb`, which tests:
- CLINT timer functionality
- GPIO input/output and interrupts
- Memory system integration
- Hardware profile configuration

### Test Output

```
=================================================
       RISCV Emulator Peripheral Tests
=================================================

Testing CLINT peripheral...
  PASS: CLINT address in range (base)
  PASS: Initial mtime is 0
  PASS: Timer interrupt when mtime >= mtimecmp
  ...

Testing GPIO peripheral...
  PASS: Output register write/read
  PASS: Edge-triggered interrupt detected
  ...

Testing memory system integration...
  PASS: CLINT access through memory system
  ...

Testing config profiles...
  PASS: QEMU-virt profile has 2 regions
  ...

=================================================
Test Results:  44 passed, 0 failed out of 44 tests
=================================================
ALL TESTS PASSED!
```

## Program Tests

Located in `test/` directory.

### Available Tests

| Test | File | Purpose | Extension |
|------|------|---------|-----------|
| simple | simple.c | Return 42 | RV32I |
| arithmetic | arithmetic.c | Basic math operations | RV32I |
| loop | loop.c | Loop: sum 1+2+...+10 | RV32I |
| fibonacci | fibonacci.c | Recursive fib(10) | RV32I |
| memory | memory.c | Stack/memory access | RV32I |
| hello | hello.c | UART output | UART |
| float | float.c | FP operations | F+D |
| vector | vector.c | Vector operations | V |
| vector_simple | vector_simple.c | Basic vector | V |

### Building Tests

Requires RISC-V cross-compiler:

```bash
cd test
make         # Build all
make clean   # Clean
```

### Running Tests

```bash
# Run single test
./bin/riscv_emulator test/simple.elf

# Run with trace
./bin/riscv_emulator -t test/arithmetic.elf

# Expected outputs:
# simple:      Return value (a0): 42
# arithmetic:  Return value (a0): 11
# loop:        Return value (a0): 55
# fibonacci:   Return value (a0): 55
# hello:       "Hello, World!" then Return value (a0): 0
# float:       Return value (a0): 1 (pass)
```

### Test Makefile Targets

```bash
cd test
make test         # Run all binary tests
make test-elf     # Run all ELF tests
make run-simple   # Run specific test
make trace-simple # Run with tracing
```

## Writing New Tests

### Minimal C Test

```c
// test/mytest.c
int main(void) {
    int result = 0;
    // ... test code ...
    return result;  // 0 = pass, non-zero = fail
}
```

### With UART Output

```c
#define UART_BASE 0x10000000
#define UART_THR  (*(volatile char*)(UART_BASE))
#define UART_LSR  (*(volatile char*)(UART_BASE + 5))

void putc(char c) {
    while (!(UART_LSR & 0x20));
    UART_THR = c;
}

void puts(const char *s) {
    while (*s) putc(*s++);
}

int main(void) {
    puts("Test starting...\n");
    // ... test code ...
    puts("Test passed!\n");
    return 0;
}
```

### Startup Code

Tests use `start.S`:

```asm
.section .text.start
.globl _start
_start:
    lui sp, %hi(_stack_top)
    addi sp, sp, %lo(_stack_top)
    jal main
    # Exit with ecall
    mv a0, a0
    li a7, 93        # exit syscall
    ecall
```

### Linker Script

Basic linker script (`linker.ld`):

```ld
ENTRY(_start)
SECTIONS {
    . = 0x0;
    .text : { *(.text.start) *(.text*) }
    .rodata : { *(.rodata*) }
    .data : { *(.data*) }
    .bss : { *(.bss*) }
    . = ALIGN(16);
    _stack_bottom = .;
    . = . + 0x10000;
    _stack_top = .;
}
```

### Compilation

```bash
riscv32-unknown-elf-gcc -march=rv32imfd -mabi=ilp32d \
    -nostdlib -nostartfiles -T linker.ld \
    -o mytest.elf start.S mytest.c

# Create binary (for raw loading)
riscv32-unknown-elf-objcopy -O binary mytest.elf mytest.bin
```

## Bare-Metal Programs Tests

The emulator includes a comprehensive suite of bare-metal C programs for testing real-world embedded software scenarios.

### Available Programs

Located in `programs/` directory:

| Program | Description | Extensions | Interactive |
|---------|-------------|------------|-------------|
| hello | Continuous hello world output | RV32IMC | No |
| echo | Character echo terminal | RV32IMC | Yes |
| forth | Forth interpreter | RV32IMC | Yes |
| fibonacci | Fibonacci sequences (recursive/iterative) | RV32IMC | No |
| primes | Prime number finder (Sieve of Eratosthenes) | RV32IMC | No |
| mandelbrot | Mandelbrot set ASCII art | RV32IMFD | No |
| malloc-test | Memory allocator stress test | RV32IMC | No |
| test-runner | Automated regression tests | RV32IMFD | No |

### Running Individual Programs

Each program can be run with:
```bash
cd programs
make run-<program-name>
```

Example:
```bash
make run-fibonacci
```

This will:
1. Build the program if needed
2. Start the emulator with PTY support and qemu-virt machine profile
3. Display the PTY device path (e.g., `/dev/pts/5`)
4. Wait for you to connect with a terminal

### Connecting to Programs

In another terminal:
```bash
# Using minicom
minicom -D /dev/pts/X   # Replace X with the number shown

# Or using screen
screen /dev/pts/X
```

Exit minicom: `Ctrl-A X`
Exit screen: `Ctrl-A K`

### Automated Testing

Run the full bare-metal suite:
```bash
cd programs
./test-all.sh
```

This builds and runs 78 programs and counts the `PASS:`/`FAIL:` lines they
report through the semihosting log, for 2189 assertions in total. Add
`--rebuild` to force a rebuild first. See [../TESTING.md](../TESTING.md) for the
full description of the suite and how to add a test to it.

Interactive programs (echo, forth) must be tested manually.

### Test Runner Program

The `test-runner` program is a single-binary regression test covering the core
language and runtime features:

```bash
cd programs
../bin/riscv_emulator --machine qemu-virt -q --no-uart out/bin/test-runner.bin 80000000
```

Tests include:
- **Basic Arithmetic** - add, sub, mul, div, rem, overflow
- **Bitwise Operations** - AND, OR, XOR, NOT, shifts
- **Memory Alignment** - word, halfword, byte loads/stores, unaligned access
- **Control Flow** - if/else, loops, break, continue
- **Function Calls** - simple calls, recursion, stack depth
- **Floating-Point** - fadd, fsub, fmul, fdiv, comparisons, conversions
- **Memory Allocation** - malloc, free, alignment, large blocks
- **Printf** - format strings (smoke test)

It prints a summary and exits 0 on success, 1 on failure. All 52 individual
tests must pass.

### Expected Outputs

There are no golden output files. Each test program reports its own results as
`PASS: <name>` / `FAIL: <name>` lines, and `programs/test-all.sh` tallies them,
so a test is self-describing rather than compared against a stored transcript.

### Building Programs

Build all programs:
```bash
cd programs
make all
```

Build specific program:
```bash
make fibonacci.bin
```

Requirements:
- RISC-V cross-compiler: `riscv32-unknown-elf-gcc`
- Install on Ubuntu: `sudo apt install gcc-riscv64-unknown-elf`

### Program Details

#### hello
Tests basic UART output and infinite loops. Outputs two messages continuously.

#### echo
Interactive character echo. Type characters and they are echoed back. Tests UART input/output.

#### forth
Bare-metal Forth interpreter. Stack-based RPN calculator with word definitions. Tests dynamic memory, string parsing, interpreter loop.

Example session:
```
> 5 5 +
10  ok
> : SQUARE DUP * ;
ok
> 7 SQUARE
49  ok
```

#### fibonacci
Calculates Fibonacci sequences using both iterative (fast) and recursive (stack-intensive) methods. Tests loops, recursion, printf.

Computes fib(0-19) iteratively and fib(0-14) recursively.

#### primes
Finds all prime numbers up to 1000 using Sieve of Eratosthenes. Tests arrays, nested loops, BSS section initialization.

Should find exactly 168 primes.

#### mandelbrot
Generates ASCII art of the Mandelbrot set using floating-point arithmetic. Tests FPU extensively.

- Size: 80x40 characters
- Max iterations: 50
- Region: x=[-2.0, 1.0], y=[-1.0, 1.0]
- ~160,000 FP operations total

#### malloc-test
Comprehensive memory allocator test suite:
1. Basic allocations (int, array, char)
2. Linked list (10 nodes)
3. Large allocation (1KB)
4. Realloc (expand array)
5. Alignment check (8-byte alignment)

All 5 tests must show "PASS".

#### test-runner
Automated regression suite with 50+ tests covering arithmetic, bitwise ops, memory, control flow, functions, FPU, malloc, and printf.

Returns 0 if all tests pass, 1 if any fail.

### Known Limitations

- Programs run in an infinite loop after completion (use Ctrl-C to exit emulator)
- Interactive programs (echo, forth) cannot be tested automatically
- PTY requires proper permissions (`/dev/pts` access)
- Floating-point programs require FPU support (F and D extensions)
- Programs use bare-metal runtime (no OS, minimal C library)

### Troubleshooting

**Program doesn't output anything:**
- Check that you're connected to the correct PTY (`/dev/pts/X`)
- Verify emulator started with `--pty --wait` flags
- Check minicom/screen is not in line mode

**PTY permission denied:**
```bash
# Check permissions
ls -l /dev/pts/

# Your user should have read/write access
# If not, check group membership (usually 'tty' group)
groups
```

**Toolchain not found:**
```bash
# Verify installation
which riscv32-unknown-elf-gcc

# Install if needed
sudo apt install gcc-riscv64-unknown-elf
```

**Tests fail:**
- Run individual test: `cd programs && make run-<name>`
- Read the test's own log file, named in `programs/test-all.sh`
- Use debugger: `./bin/riscv_emulator --machine qemu-virt -d programs/out/bin/<name>.bin 80000000`

## Vector Tests

### Basic Vector Test

```c
// Requires V extension
#include <stdint.h>

// Vector intrinsics or inline assembly
void test_vector(void) {
    uint32_t a[4] = {1, 2, 3, 4};
    uint32_t b[4] = {5, 6, 7, 8};
    uint32_t c[4];

    // Set vector length
    asm volatile("vsetvli t0, %0, e32, m1" : : "r"(4));

    // Load vectors
    asm volatile("vle32.v v1, (%0)" : : "r"(a));
    asm volatile("vle32.v v2, (%0)" : : "r"(b));

    // Add
    asm volatile("vadd.vv v3, v1, v2");

    // Store result
    asm volatile("vse32.v v3, (%0)" : : "r"(c));

    // c = {6, 8, 10, 12}
}
```

### Compilation for V Extension

```bash
riscv32-unknown-elf-gcc -march=rv32imfdv -mabi=ilp32d \
    -nostdlib -nostartfiles -T linker.ld \
    -o vector_test.elf start.S vector_test.c
```

## Debugging Failed Tests

### Check Return Value

```bash
./bin/riscv_emulator test/failing.elf
# Look for: Return value (a0): <value>
```

### Trace Execution

```bash
./bin/riscv_emulator -t test/failing.elf 2>&1 | tail -50
```

### Interactive Debug

```bash
./bin/riscv_emulator -d test/failing.elf
# Use: step, regs, mem, dis commands
```

### Check Memory Layout

```bash
./bin/riscv_emulator -v test/failing.elf
# Shows: Memory regions, entry point, load addresses
```

## Expected Test Results

| Test | Expected a0 | Notes |
|------|-------------|-------|
| simple | 42 | Direct return |
| arithmetic | 11 | 5+3 + 5-3 = 11 |
| loop | 55 | 1+2+...+10 |
| fibonacci | 55 | fib(10) |
| memory | 150 | Array sum |
| hello | 0 | Outputs "Hello, World!" |
| float | 1 | All FP tests pass (1 = pass) |
| vector | 0 | All 14 subtests passed (0 errors) |
| vector_simple | 0 | Basic ops work |
