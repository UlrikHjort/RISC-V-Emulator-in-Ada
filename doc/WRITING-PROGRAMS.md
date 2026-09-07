# Writing C Programs for the Emulator

How to install a RISC-V cross-compiler, compile a program of your own, and
run it under the emulator.

This guide covers programs you write yourself. To build the ~78 programs that
ship with the repository, see [Building](BUILDING.md); for the runtime library
they use, see [C Library](C-LIBRARY.md).

## Contents

1. [Installing a cross-compiler](#1-installing-a-cross-compiler)
2. [Hello world from scratch](#2-hello-world-from-scratch)
3. [What the startup code and linker script do](#3-what-the-startup-code-and-linker-script-do)
4. [Using printf and the rest of the C library](#4-using-printf-and-the-rest-of-the-c-library)
5. [Adding your program to the Makefile](#5-adding-your-program-to-the-makefile)
6. [Building for RV64](#6-building-for-rv64)
7. [Running what you built](#7-running-what-you-built)
8. [Adding a program to the test suite](#8-adding-a-program-to-the-test-suite)
9. [Troubleshooting](#9-troubleshooting)

---

## 1. Installing a cross-compiler

You need a bare-metal ("newlib" or "elf") RISC-V GCC. A Linux-targeted
compiler such as `gcc-riscv64-linux-gnu` will *not* work: these programs are
freestanding, built with `-nostdlib -nostartfiles`.

Nearly every RISC-V bare-metal toolchain -- distribution packages, prebuilt
tarballs and vendor SDKs alike -- is built from the upstream
[riscv-collab/riscv-gnu-toolchain](https://github.com/riscv-collab/riscv-gnu-toolchain)
sources. That repository is both the place to get a
[prebuilt release](https://github.com/riscv-collab/riscv-gnu-toolchain/releases)
and the reference for building one yourself; the sections below use it for
both.

### Which prefix do the Makefiles expect?

All three Makefiles (`programs/`, `test/`, `examples/`) default to:

```makefile
CROSS ?= riscv32-unknown-elf-
```

Toolchains from different sources use different prefixes, and **the prefix is
part of the program name**, not something GCC figures out. The common ones:

| Source | Compiler name |
|--------|---------------|
| Built from source with `--with-arch=rv32imc` | `riscv32-unknown-elf-gcc` |
| Debian/Ubuntu package `gcc-riscv64-unknown-elf` | `riscv64-unknown-elf-gcc` |
| [riscv-collab](https://github.com/riscv-collab/riscv-gnu-toolchain/releases) prebuilt release tarballs | `riscv32-unknown-elf-gcc` or `riscv64-unknown-elf-gcc` |
| xPack `riscv-none-elf-gcc` | `riscv-none-elf-gcc` |

If yours is not `riscv32-unknown-elf-`, do not rename anything -- pass the
prefix on the command line:

```bash
make -C programs CROSS=riscv64-unknown-elf-
```

or export it once for the shell session:

```bash
export CROSS=riscv64-unknown-elf-
```

### Can a 64-bit toolchain build the 32-bit programs?

Yes, provided it was built with multilib support (most prebuilt ones are).
`riscv64-unknown-elf-gcc` targets RV32 through the same `-march`/`-mabi` flags
the Makefiles already pass. Check what your compiler can produce:

```bash
riscv64-unknown-elf-gcc --print-multi-lib
```

If the list contains `rv32imc/ilp32` (or the `-march` you intend to use), you
are set. If it only offers `rv64*`, you need an RV32-capable toolchain.

### Installing

**Debian / Ubuntu**

```bash
sudo apt install gcc-riscv64-unknown-elf
make -C programs CROSS=riscv64-unknown-elf-
```

**Fedora**

```bash
sudo dnf install riscv64-elf-gcc
make -C programs CROSS=riscv64-elf-
```

**Arch**

```bash
sudo pacman -S riscv64-elf-gcc      # or riscv32-elf-gcc from the AUR
```

**Prebuilt tarball (any distro, and the easiest route to a real
`riscv32-unknown-elf-` prefix)**

Download a release from
<https://github.com/riscv-collab/riscv-gnu-toolchain/releases>, unpack it, and
put its `bin/` on your `PATH`:

```bash
tar xf riscv32-elf-ubuntu-24.04-gcc-nightly-*.tar.gz -C /opt
export PATH=/opt/riscv/bin:$PATH
```

**macOS**

```bash
brew tap riscv-software-src/riscv
brew install riscv-tools           # installs riscv64-unknown-elf-*
```

**From source** (slowest, but gives you exactly the prefix and default arch
you want):

```bash
git clone https://github.com/riscv-collab/riscv-gnu-toolchain
cd riscv-gnu-toolchain
./configure --prefix=/opt/riscv --with-arch=rv32imc --with-abi=ilp32
make          # builds the newlib cross-compiler; takes a while
```

### Verifying

```bash
riscv32-unknown-elf-gcc --version         # or your prefix
riscv32-unknown-elf-gcc -march=rv32imc -mabi=ilp32 -nostdlib -x c - -o /dev/null <<'EOF'
void _start(void) { }
EOF
```

If that produces no output, the toolchain works. You also need `objcopy`,
`objdump` and `size` from the same prefix -- every real toolchain ships them
alongside `gcc`.

---

## 2. Hello world from scratch

The shortest complete program. Create `programs/myprog.c`:

```c
#include "uart.h"

int main(void)
{
    puts("Hello from my own program!\n");
    return 0;
}
```

Build it by hand, from inside `programs/`:

```bash
cd programs
riscv32-unknown-elf-gcc \
    -march=rv32imc -mabi=ilp32 \
    -nostdlib -nostartfiles -fno-builtin -O2 -g -Wall \
    -T hello.ld \
    -o myprog.elf \
    crt0.S uart.c myprog.c
```

Run it:

```bash
../bin/riscv_emulator --machine qemu-virt myprog.elf
```

Three things make this work, and all three are required:

- **`crt0.S`** -- without it there is no `_start`, no stack pointer, and no
  zeroed `.bss`.
- **`-T hello.ld`** -- places the program at `0x80000000`, where the
  `qemu-virt` profile has RAM.
- **`uart.c`** -- provides `putchar`/`puts`, which write to the UART at
  `0x10000000`.

`-nostdlib -nostartfiles` means you get no host C library and no default
startup code, which is exactly why the three files above have to be listed
explicitly.

---

## 3. What the startup code and linker script do

### Startup files

| File | Use it when |
|------|-------------|
| `programs/crt0.S` | Normal RV32 program (the usual choice) |
| `programs/crt0-64.S` | RV64 program -- zeroes `.bss` 8 bytes at a time |
| `programs/crt0-smode.S` | RV32 program that must run in Supervisor mode |
| `programs/crt0-smode-64.S` | RV64 Supervisor-mode program |
| `test/start.S` | Minimal RV32 startup for `test/` and `examples/`: sets `sp` to `0x100000`, calls `_main`, no BSS zeroing |

`crt0.S` does three things and then gets out of the way:

```asm
_start:
    la sp, _stack_top     # 1. stack at the top of RAM
    ...                   # 2. zero .bss from __bss_start to __bss_end
    call main             # 3. enter your code
    li a7, 93             # main returned -- exit(a0)
    ecall                 # the emulator halts here
```

The exit path matters: **returning from `main` halts the emulator**, and the
value you return becomes the emulator's reported return value. `ecall` with
`a7 = 93` is the newlib/Linux `exit` syscall number; the emulator intercepts
it rather than trapping.

### Linker scripts

| Script | Origin | Length | Use with |
|--------|--------|--------|----------|
| `programs/hello.ld` | `0x80000000` | 1 MB | RV32, `--machine qemu-virt` |
| `programs/hello64.ld` | `0x80000000` | 128 MB | RV64, `--machine qemu-virt` |
| *(none)* -- `-Ttext=0x0` | `0x0` | 1 MB | `test/` and `examples/`, `--machine simple` |

Both scripts set `ENTRY(_start)`, order the sections `.text` (with
`.text.start` forced first), `.rodata`, `.data`, `.bss`, and define the three
symbols `crt0.S` needs: `__bss_start`, `__bss_end`, and `_stack_top` (the top
of RAM).

**The linker script and the `--machine` profile must agree.** A program linked
at `0x80000000` will fault immediately under `--machine simple`, whose RAM
starts at `0x0`. See [Hardware Profiles](PROFILES.md).

---

## 4. Using printf and the rest of the C library

There is no library archive to link against -- you add the `.c` files you need
to the compiler command line. Header and source come in pairs:

| Want | Include | Add to the build |
|------|---------|------------------|
| `putchar`, `getchar`, `puts` | `uart.h` | `uart.c` |
| `printf`, `sprintf`, `snprintf` | `printf.h` | `printf.c ftoa.c` |
| `malloc`, `free`, `qsort`, `strtol`, `sscanf` | *(declare as needed)* | `syscalls.c` |
| `memcpy`, `strlen`, `strcmp`, ... | `string.h` | `string.c` |
| `sin`, `cos`, `sqrt`, `pow`, ... | `math.h` | `math.c` |
| `atof` | *(declare as needed)* | `atof.c` |
| `clock_gettime`, `gettimeofday` | `time.h` | `time.c` |
| `setjmp`, `longjmp` | `setjmp.h` | `setjmp.S` |
| Host-side log files | `log.h` | `log.c` (RV32) or `log64.c` (RV64) |

`printf.c` depends on `ftoa.c` for `%f`/`%e`/`%g` -- always list both. `printf`
writes through `putchar`, so `uart.c` is needed too:

```bash
riscv32-unknown-elf-gcc -march=rv32imfd -mabi=ilp32 \
    -nostdlib -nostartfiles -fno-builtin -O2 -g -Wall -T hello.ld \
    -o myprog.elf \
    crt0.S uart.c syscalls.c printf.c ftoa.c myprog.c
```

Note the `-march=rv32imfd` -- **not** the `rv32imc` used in
[section 2](#2-hello-world-from-scratch). `ftoa.c` does real `double`
arithmetic, and `rv32imc` has no FPU, so GCC emits calls to the soft-float
helpers `__adddf3`, `__subdf3`, `__muldf3`, `__divdf3` and friends. Those live
in `libgcc`, which `-nostdlib` excludes, and the link fails with a wall of
`undefined reference` errors.

There are two ways out, and `programs/Makefile` uses both:

```bash
# 1. Give the target an FPU (what most rules do -- note the -march override)
$(CC) $(CFLAGS) -march=rv32imfd $(LDFLAGS) -o $@ ... printf.c ftoa.c prog.c

# 2. Keep soft float and link libgcc explicitly
$(CC) $(CFLAGS) $(LDFLAGS) -o $@ ... printf.c ftoa.c prog.c -lgcc
```

Option 1 is the better default here: the emulator implements F and D, so you
get real FP instructions instead of emulated ones. Reach for `-lgcc` when you
specifically want to test the soft-float path.

Full API documentation is in [C Library](C-LIBRARY.md) and
[Math Library](MATH_LIBRARY.md).

### Writing to a file on the host

`log.h` is specific to this emulator: it lets a bare-metal program create and
write real files on the host filesystem through custom ECALLs (`a7 =
0x500..0x504`), which is often more convenient than reading UART output.

```c
#include "log.h"

int main(void)
{
    log_init("run.log");
    log_write(CYCLES, "value = %d\n", 42);
    log_close();
    return 0;
}
```

Files land in the emulator's working directory, or in the directory given by
`--log-dir`.

---

## 5. Adding your program to the Makefile

Hand-typed compiler commands get old quickly. `programs/Makefile` uses one
explicit rule per program; copy the `hello` pair and edit the names.

**Step 1** -- add the ELF and BIN rules next to the others:

```makefile
# Build myprog
$(ELF)/myprog.elf: crt0.S uart.c syscalls.c printf.c ftoa.c myprog.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) -march=rv32imfd $(LDFLAGS) -o $@ crt0.S uart.c syscalls.c printf.c ftoa.c myprog.c
	$(SIZE) $@

$(BIN)/myprog.bin: $(ELF)/myprog.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/myprog.dis
```

The `-march=rv32imfd` override is there because this example uses `ftoa.c`; see
[section 4](#4-using-printf-and-the-rest-of-the-c-library). Drop it if your
program has no floating point.

The prerequisite list and the command list must name the same `.c` files --
the first makes `make` rebuild when a source changes, the second is what
actually gets compiled. Listing `hello.ld` as a prerequisite means a change to
the memory layout also forces a relink.

**Step 2** -- add a convenience target and a run target, **and declare both
phony**:

```makefile
.PHONY: myprog run-myprog

myprog: $(BIN)/myprog.bin

run-myprog: $(BIN)/myprog.bin
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt --pty --wait $< 80000000
```

The `.PHONY` line is not cosmetic. Without it, `make myprog` finds a file
named `myprog.c` in the directory, applies its own built-in `%: %.c` rule, and
tries to link a host executable called `myprog` -- which fails with
`out/bin/myprog.bin: file not recognized: file format not recognized`. Add the
two names to the existing `.PHONY` list at the top of the file, or write a
separate `.PHONY` line as above; make accepts both.

**Step 3** -- add `$(BIN)/myprog.bin` to the `all:` target if it should build
by default.

Then:

```bash
make -C programs myprog
make -C programs run-myprog
```

Output lands in `programs/out/elf/`, `programs/out/bin/` and
`programs/out/dis/` (disassembly).

---

## 6. Building for RV64

Same toolchain, different flags -- and a different startup file and linker
script. `programs/Makefile` already defines them:

```makefile
ARCH64   = rv64imafd
ABI64    = lp64d
CFLAGS64 = -march=$(ARCH64) -mabi=$(ABI64) -mcmodel=medany \
           -nostdlib -nostartfiles -fno-builtin -O2 -g -Wall
LDFLAGS64 = -T hello64.ld
```

What has to change relative to RV32:

- **`crt0-64.S`** instead of `crt0.S` (zeroes `.bss` with `sd`, 8 bytes per
  step)
- **`hello64.ld`** instead of `hello.ld` (128 MB of RAM rather than 1 MB)
- **`log64.c`** instead of `log.c`, if you use the host logger -- it passes
  64-bit pointers as `long`
- **`-mcmodel=medany`**, required for code linked above the 2 GB boundary

A complete RV64 rule:

```makefile
$(ELF)/myprog64.elf: crt0-64.S uart.c log64.c myprog64.c hello64.ld | $(ELF)
	$(CC) $(CFLAGS64) $(LDFLAGS64) -o $@ crt0-64.S uart.c log64.c myprog64.c
	$(SIZE) $@
```

You do not tell the emulator which core to use: **it reads the ELF class from
the file header** and selects the RV32 or RV64 core automatically.

---

## 7. Running what you built

### ELF files

```bash
bin/riscv_emulator --machine qemu-virt programs/out/elf/myprog.elf
```

`--machine` is effectively mandatory. The default profile has no MTVEC
configured, so any trap in your program becomes unrecoverable.

### Raw binaries

A `.bin` has no headers, so you must supply the load address yourself, **in
hex, without a `0x` prefix**:

```bash
bin/riscv_emulator --machine qemu-virt programs/out/bin/myprog.bin 80000000
```

### Interactive programs

If your program reads from the UART, give it a PTY and connect a terminal:

```bash
bin/riscv_emulator --machine qemu-virt --pty --wait myprog.elf
# prints e.g. /dev/pts/7 -- then, in a second terminal:
minicom -D /dev/pts/7
```

`--wait` holds execution until the terminal attaches, so you do not miss the
first lines of output.

### Debugging your own code

```bash
bin/riscv_emulator --machine qemu-virt -d myprog.elf        # interactive debugger
bin/riscv_emulator --machine qemu-virt -t myprog.elf        # instruction trace
bin/riscv_emulator --machine qemu-virt --gdb myprog.elf     # GDB stub on :1234
bin/riscv_emulator --machine qemu-virt --profile myprog.elf # function profile
```

Build with `-g` (the default `CFLAGS` already does) so the debugger and GDB
can resolve symbols. See [Debugging](DEBUGGING.md), [GDB](GDB.md) and
[Profiling](PROFILING.md).

---

## 8. Adding a program to the test suite

`programs/test-all.sh` drives a table of programs and checks their output. To
include yours, add a row to the `TESTS` array:

```bash
TESTS=(
    ...
    "myprog            myprog            myprog.log"
)
```

The three fields are the program name, the binary basename, and the log file
it is expected to produce. An optional fourth field `elf` makes the harness
pass the ELF directly instead of `.bin` plus a load address -- required for
RV64 programs:

```bash
    "myprog64          myprog64          myprog64.log      elf"
```

**`test-all.sh` does not build the programs it runs.** Run `make -C programs
all` first, and after editing a source rebuild *both* outputs -- the harness
loads the `.bin`, so a freshly rebuilt `.elf` alone will not change the
result.

See [Testing](TESTING.md) for the full harness description.

---

## 9. Troubleshooting

**`riscv32-unknown-elf-gcc: command not found`**

Your toolchain uses a different prefix. See
[section 1](#1-installing-a-cross-compiler) and pass `CROSS=`:

```bash
make -C programs CROSS=riscv64-unknown-elf-
```

**`cannot find crt0.o` / `undefined reference to main`**

`-nostartfiles` is missing, or `crt0.S` is not in the source list. Both are
required.

**`undefined reference to putchar` / `printf` / `memcpy`**

The corresponding `.c` file is not on the command line. See the table in
[section 4](#4-using-printf-and-the-rest-of-the-c-library). `memcpy` and
friends come from `string.c`; GCC can also emit calls to them on its own,
which is what `-fno-builtin` is there to prevent.

**`undefined reference to __adddf3` (or `__subdf3`, `__muldf3`, `__fixdfsi`, ...)**

Double-underscore names like these are `libgcc` soft-float helpers, pulled in
because the `-march` you chose has no hardware FP but the code does
floating-point arithmetic -- most often via `ftoa.c`. Either add the FPU with
`-march=rv32imfd`, or append `-lgcc` to the link. See
[section 4](#4-using-printf-and-the-rest-of-the-c-library).

**`make <program>` says "Nothing to be done" and builds nothing**

Most program names in `programs/Makefile` appear in `.PHONY` without a rule
behind them, so make has nothing to do. Ask for the output file instead:

```bash
make -C programs out/bin/branch-test.bin
```

If you follow [section 5](#5-adding-your-program-to-the-makefile) your own
`myprog:` target does have a prerequisite, so `make myprog` works.

**The program produces no output and exits immediately**

Usually a mismatch between the link address and the profile. A program linked
with `hello.ld` (origin `0x80000000`) needs `--machine qemu-virt`; one linked
with `-Ttext=0x0` needs `--machine simple`. Check with:

```bash
riscv32-unknown-elf-objdump -h myprog.elf | head
```

**`Illegal instruction` on something you expected to work**

The `-march` string does not include the extension. `rv32imc` has no
hardware floating point -- use `rv32imfd` for `float`/`double`, or
`rv32imfd_zve32x` for vector intrinsics. The emulator implements
RV32IMAFDC + V + Zb*/Zicond/Zfh; see [Instruction Set](ISA.md).

**`-march`/`-mabi` mismatch, or "attempt to link with incompatible objects"**

Every object in one link must use the same ABI. `-march=rv64imafd` needs
`-mabi=lp64d`; `-march=rv32imc` needs `-mabi=ilp32`. If you change one, change
it everywhere, and delete stale `.o` files.

---

## See also

- [Building](BUILDING.md) -- building the emulator itself and the shipped programs
- [C Library](C-LIBRARY.md) -- full API reference for the bare-metal runtime
- [Hardware Profiles](PROFILES.md) -- memory layouts and custom config files
- [Instruction Set](ISA.md) -- which extensions are implemented
- [Testing](TESTING.md) -- the test harness
- [../TUTORIAL.md](../TUTORIAL.md) -- hands-on tour of the emulator's features
