# 1. Make a slow program fast

**Goal:** take a program that runs slowly, use the profiler to find *why*, fix
the hot spot, and confirm the speedup with a hard number.

**You will use:** `--profile` (the stall breakdown and cycle count), and the
before/after cycle comparison that the emulator's timing model makes possible.

The example is `primes-slow.c` / `primes-fast.c` in this directory: both count
the primes below 4000, so the answer must stay the same while the cost drops.

---

## Step 1 - build and run the slow version

```bash
cd tutorials
make out/elf/primes-slow.elf out/bin/primes-slow.bin
../bin/riscv_emulator --machine qemu-virt --log-dir /tmp -q out/elf/primes-slow.elf
cat /tmp/primes-slow.log
```

```
primes below 4000: 550
```

Correct, but how expensive was it? Ask the profiler.

## Step 2 - profile it

```bash
../bin/riscv_emulator --machine qemu-virt --log-dir /tmp -q --profile \
    out/elf/primes-slow.elf
```

```
=== Profiling Report ===
Total instructions: 4134094
Total wall cycles:  37977204
Average CPI:        9.18
Stall breakdown:
  MUL/MULH  (+2): 19 (0%)
  DIV/REM  (+32): 32808672 (86%)
  FP arith (+3/+19): 0 (0%)
  CSR       (+1): 0 (0%)
  Load-use  (+1): 0 (0%)
  Branch/jump (+1): 1030421 (2%)
```

Two things jump out:

* **CPI is 9.18** - each instruction costs, on average, nine cycles. For a
  simple integer program that is enormous; something is stalling the pipe.
* **86% of all cycles are DIV/REM stalls.** The emulator charges a divide or
  remainder a large penalty (as real hardware does - division is slow), and
  here that single category dwarfs everything else.

So the bottleneck is not "too many instructions" in general - it is the
**modulo operation**. Look at the inner loop of `primes-slow.c`:

```c
for (uint32_t d = 2; d < n; d++)      /* trial-divide by everything */
    if (n % d == 0) return 0;
```

For every candidate `n` it does up to `n` modulo operations. That is a lot of
the emulator's most expensive operation.

## Step 3 - fix the hot spot

`primes-fast.c` makes two standard changes to `is_prime`:

```c
if (n % 2 == 0) return n == 2;
for (uint32_t d = 3; d * d <= n; d += 2)   /* odd divisors up to sqrt(n) */
    if (n % d == 0) return 0;
```

* stop at `sqrt(n)` instead of `n` - far fewer iterations;
* skip even divisors - half as many again.

Both cut the number of `%` operations, which is exactly the category the
profile blamed.

## Step 4 - measure again

```bash
make out/elf/primes-fast.elf
../bin/riscv_emulator --machine qemu-virt --log-dir /tmp -q out/elf/primes-fast.elf
cat /tmp/primes-fast.log
../bin/riscv_emulator --machine qemu-virt --log-dir /tmp -q --profile \
    out/elf/primes-fast.elf
```

```
primes below 4000: 550          <- same answer

Total instructions: 120742
Total wall cycles:  687296
Average CPI:        5.69
Stall breakdown:
  DIV/REM  (+32): 508780 (74%)
  ...
```

| | slow | fast | change |
|---|------|------|--------|
| result | 550 | 550 | identical |
| instructions | 4,134,094 | 120,742 | 34x fewer |
| **wall cycles** | **37,977,204** | **687,296** | **~55x faster** |
| CPI | 9.18 | 5.69 | |

The answer is unchanged and the program runs about **55 times faster** in the
emulator's cycle model.

## What to take away

* The **stall breakdown** is the fastest way to a bottleneck: it tells you
  *which class of operation* is eating cycles, not just that the program is
  slow. Here "86% DIV/REM" pointed straight at the `%` in the inner loop.
* **Cycles, not instruction count, are the thing to minimise.** DIV/REM still
  accounts for 74% of the fast version - modulo is inherently costly - but we
  execute vastly fewer of them, so the wall-cycle total collapses.
* Always re-run and check the **result is unchanged** (550 both times). An
  "optimization" that changes the answer is a bug.

## Try it yourself

* Bump `LIMIT` to 20000 in both files and compare again - the gap widens,
  because the slow version is roughly O(n^2) in modulo operations.
* Add `--flamegraph /tmp/primes.txt` to a profile run to export folded-stack
  data for call-heavy programs (see [../doc/PROFILING.md](../doc/PROFILING.md)).
* Combine with `--cache` to see cache behaviour alongside the stall model -
  that is the subject of [tutorial 3](03-cache-and-stalls.md).
