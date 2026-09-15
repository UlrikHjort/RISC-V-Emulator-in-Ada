# 4. Debug a wrong result with GDB

**Goal:** attach a real debugger, set breakpoints and watchpoints, and inspect
your program at source level - exactly as you would against physical hardware
over a JTAG probe.

**You will use:** `--gdb` (the emulator's GDB Remote Serial Protocol stub) and
any RISC-V GDB (`gdb-multiarch`, or `riscv32-unknown-elf-gdb`).

The example is `primes-fast.c`, but any ELF with symbols works.

---

## Step 1 - start the emulator as a GDB target

```bash
cd tutorials
make out/elf/primes-fast.elf
../bin/riscv_emulator --machine qemu-virt --gdb 3333 out/elf/primes-fast.elf
```

It prints `GDB server listening on 127.0.0.1 port 3333` and waits. (The stub
binds to loopback by default; use `--gdb-listen-all` only if you must reach it
from another machine - it is unauthenticated.)

## Step 2 - connect from another terminal

```bash
gdb-multiarch -ex "target remote :3333" out/elf/primes-fast.elf
```

Then drive it like any GDB session:

```
(gdb) break is_prime
Breakpoint 1 at 0x80000666: file primes-fast.c, line 16.

(gdb) continue
Breakpoint 1, is_prime (n=n@entry=2) at primes-fast.c:16
16          if (n % 2 == 0) return n == 2;

(gdb) backtrace
#0  is_prime (n=n@entry=2) at primes-fast.c:16
#1  0x800006ae in count_primes (limit=4000) at primes-fast.c:26
#2  0x800006d4 in main () at primes-fast.c:33

(gdb) info args
n = 2

(gdb) finish
Value returned is $1 = 1

(gdb) print count
$2 = 0
```

Source-level breakpoints, a full backtrace with argument values, `finish` to
run to the caller and see the return value, and `print` of locals - all against
the emulated CPU.

## Step 3 - watch a variable change

With `count` in scope (stop in `count_primes` first), set a watchpoint on it:

```
(gdb) break count_primes
(gdb) continue
(gdb) watch count
Watchpoint 2: count
(gdb) continue
Watchpoint 2: count
Old value = 0
New value = 1
(gdb) continue
Watchpoint 2: count
Old value = 1
New value = 2
```

Execution stops the moment `count` changes - useful for "what is modifying this
variable, and when?" without single-stepping the whole program. (The emulator
also supports GDB's hardware watchpoints for plain memory addresses; see
[../doc/GDB.md](../doc/GDB.md).)

## What to take away

* `--gdb <port>` turns the emulator into a target that any RISC-V GDB can
  drive, so your normal debugging muscle memory applies.
* Breakpoints, backtraces, `finish`, `print`, and **hardware watchpoints** all
  work at source level (build with `-g`, which the tutorial programs do).
* This is the "step through it on the chip" experience without a chip - and,
  combined with [tutorial 2](02-find-a-crash.md), a way to stop at a fault and
  then poke around.

## Notes

* RV64 targets work identically (the stub advertises the FP registers too);
  just point GDB at an ELF64 and set `set architecture riscv:rv64` if your GDB
  does not infer it.
* For the full command set and multi-hart notes see
  [../doc/GDB.md](../doc/GDB.md) and [../TUTORIAL.md](../TUTORIAL.md) section 8.
