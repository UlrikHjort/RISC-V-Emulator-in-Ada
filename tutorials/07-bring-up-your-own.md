# 7. Get your own algorithm running and self-checked

**Goal:** go from a `.c` file to a running, self-verifying bare-metal program -
the pattern every program in this repo follows.

**You will use:** the startup code, linker script and semihosting log from
`../programs`, plus the exit code as a pass/fail signal.

If your toolchain is not set up yet, read
[../doc/WRITING-PROGRAMS.md](../doc/WRITING-PROGRAMS.md) first (installing a
cross-compiler, prefixes, RV32 vs RV64 flags). This tutorial is about the
*workflow* once it builds.

---

## The shape of a program

A bare-metal program here needs three things: startup (`crt0.S` zeroes BSS,
calls `main`, then does `ecall` to exit), a linker script (`hello.ld` places
code at the RAM base), and a way to report results (`log.c` -> a host log file
via semihosting). The tutorial `Makefile` wires all three together, so a new
example is just a `.c` file added to its `EXAMPLES` list.

## Step 1 - write it with a self-check

The key idea: **compute, compare against a known answer, and return non-zero on
failure.** That turns the program into a test - `make -C programs test` and the
suites all work this way.

```c
#include <stdint.h>
#include "log.h"

/* the algorithm under test */
static uint32_t sum_to(uint32_t n)
{
    uint32_t s = 0;
    for (uint32_t i = 1; i <= n; i++) s += i;
    return s;
}

int main(void)
{
    log_init("myalgo.log");

    int fails = 0;
    struct { uint32_t n, want; } cases[] = {
        { 0, 0 }, { 1, 1 }, { 10, 55 }, { 100, 5050 },
    };
    for (unsigned k = 0; k < sizeof cases / sizeof cases[0]; k++) {
        uint32_t got = sum_to(cases[k].n);
        if (got == cases[k].want) {
            log_write(NONE, "PASS sum_to(%u) = %u\n", cases[k].n, got);
        } else {
            log_write(NONE, "FAIL sum_to(%u) = %u, want %u\n",
                      cases[k].n, got, cases[k].want);
            fails++;
        }
    }

    log_write(NONE, "%d failure(s)\n", fails);
    log_close();
    return fails;              /* exit code = number of failures */
}
```

## Step 2 - build it

Drop `myalgo.c` in `tutorials/`, add `myalgo` to the `EXAMPLES` line in
`tutorials/Makefile`, and:

```bash
make out/elf/myalgo.elf
```

(Or compile directly, the way the Makefile does - see
[../doc/WRITING-PROGRAMS.md](../doc/WRITING-PROGRAMS.md) for the full command.)

## Step 3 - run and read the result

```bash
../bin/riscv_emulator --machine qemu-virt --log-dir /tmp -q out/elf/myalgo.elf
echo "exit code: $?"
cat /tmp/myalgo.log
```

```
exit code: 0
PASS sum_to(0) = 0
PASS sum_to(1) = 1
PASS sum_to(10) = 55
PASS sum_to(100) = 5050
0 failure(s)
```

Exit code 0 means every case passed. Break the algorithm (say `i < n`) and the
failing case prints and the exit code becomes non-zero - which is exactly what a
CI script checks.

## What to take away

* A program becomes a **test** by comparing against known answers and returning
  the failure count - no framework required.
* The `log` interface is your `printf` to a host file; the **exit code** is the
  machine-readable verdict.
* Once it self-checks, everything else in these tutorials applies: profile it
  ([1](01-optimize-a-hot-loop.md)), check coverage ([6](06-measure-coverage.md)),
  debug it ([4](04-debug-with-gdb.md)).

## Next steps

* To add it to the real suite, see [../TUTORIAL.md](../TUTORIAL.md) section 14
  ("Writing Your Own Test Program") and `programs/test-all.sh`.
* For the C runtime available to freestanding programs (malloc, string, printf,
  math), see [../doc/C-LIBRARY.md](../doc/C-LIBRARY.md).
