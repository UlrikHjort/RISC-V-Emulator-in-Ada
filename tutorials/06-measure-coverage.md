# 6. Find untested code

**Goal:** you ran a program (or a test) and want to know which instructions -
and which functions - actually executed, so you can spot dead paths and gaps.

**You will use:** `--coverage`, which records every PC visited and, when the ELF
has symbols, breaks the result down per function.

---

## Step 1 - run with coverage

```bash
cd tutorials
make out/elf/primes-fast.elf
../bin/riscv_emulator --machine qemu-virt --log-dir /tmp -q \
    --coverage /tmp/pf.cov out/elf/primes-fast.elf
cat /tmp/pf.cov
```

```
=== RISC-V Instruction Coverage Report ===
Base PC : 0x 2147483648
Slots   :  445  ( 1780 bytes)
Covered :  126 /  445  028.3%

--- Per-Function Coverage ---
is_prime                                 100.0%  ( 12 / 12)
count_primes.constprop.0                 100.0%  ( 12 / 12)
main                                     100.0%  ( 11 / 11)
log_init                                 100.0%  ( 8 / 8)
log_close                                100.0%  ( 3 / 3)
log_regs                                 025.0%  ( 1 / 4)
log_write                                019.9%  ( 69 / 346)
putchar                                  000.0%  ( 0 / 15)
puts                                     000.0%  ( 0 / 16)
getchar                                  000.0%  ( 0 / 6)
```

## Step 2 - read it

* The code you care about - `is_prime`, `count_primes`, `main` - is **100%**
  covered: this run exercised every instruction of the algorithm.
* `putchar`, `puts`, `getchar` are **0%**: they are linked in from the support
  library but this program never calls them. Dead weight for this workload,
  not a test gap.
* `log_write` is **19.9%**: the program used only a couple of format
  conversions, so most of the big `printf`-style formatter is untouched. If you
  were testing `log_write` itself, that low number is the signal you are
  missing cases (widths, `%x`, floats, ...).

The overall 28.3% is dominated by that one large, mostly-unused formatter -
which is exactly why the **per-function** breakdown matters more than the
single headline number.

## What to take away

* `--coverage` answers "did this actually run?" at instruction granularity.
* The **per-function** table separates "code I didn't exercise" (a real gap)
  from "library code this workload never needs" (fine).
* Point it at a *test* rather than a demo to find genuine holes: 100% on the
  functions under test is the goal; a low number on one of them is a to-do.

## Try it yourself

* Run coverage over one of the `../programs` self-tests (build with
  `make -C ../programs`, then `--coverage` an `out/elf/*.elf`).
* `--coverage` composes with `--profile` (both accumulate in the same run).
* Default output file is `coverage.txt` if you omit the filename.
