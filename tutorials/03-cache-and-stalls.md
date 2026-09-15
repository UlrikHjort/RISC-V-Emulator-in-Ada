# 3. See why memory-bound code is slow

**Goal:** two programs do the *same* work with the *same* number of
instructions, yet one is twice as slow. Show that the difference is cache
behaviour, and measure it.

**You will use:** `--cache` (L1 I+D cache simulation, miss penalties folded
into the cycle count) together with `--profile`.

The examples `sum-rowmajor.c` and `sum-colmajor.c` both sum a 128x128 int32
matrix (64 KB, larger than the 16 KB L1 data cache). They differ in one thing:
the order they walk the array.

```c
/* row-major (sequential in memory) */        /* column-major (strided) */
for (i) for (j) sum += m[i][j];                for (j) for (i) sum += m[i][j];
```

---

## Step 1 - both give the same answer

```bash
cd tutorials
make out/elf/sum-rowmajor.elf out/elf/sum-colmajor.elf
for v in rowmajor colmajor; do
  ../bin/riscv_emulator --machine qemu-virt --log-dir /tmp -q out/elf/sum-$v.elf
  cat /tmp/sum-$v.log
done
```
```
sum = 134209536
sum = 134209536
```

Same result. Now compare cost with the cache model on.

## Step 2 - run with `--cache --profile`

```bash
../bin/riscv_emulator --machine qemu-virt --log-dir /tmp -q --cache --profile \
    out/elf/sum-rowmajor.elf
../bin/riscv_emulator --machine qemu-virt --log-dir /tmp -q --cache --profile \
    out/elf/sum-colmajor.elf
```

Row-major:
```
Total instructions: 198037
Total wall cycles:  309355
  D-cache:
    Hits:         194943  (98%)
    Misses:       3094  (1%)
    Miss stalls:  61880 cycles
```

Column-major:
```
Total instructions: 198039
Total wall cycles:  616857
  D-cache:
    Hits:         179570  (90%)
    Misses:       18469  (9%)
    Miss stalls:  369380 cycles
```

## Step 3 - read the numbers

| | row-major | column-major |
|---|-----------|--------------|
| result | 134209536 | 134209536 |
| instructions | 198,037 | 198,039 |
| D-cache misses | 3,094 (1%) | **18,469 (9%)** |
| miss-stall cycles | 61,880 | **369,380** |
| **total wall cycles** | **309,355** | **616,857** |

The instruction counts are essentially identical - the two programs do the same
arithmetic. Yet the column-major version takes **~2x as many cycles**, and the
table shows exactly why: **six times as many D-cache misses**, and the miss
stalls alone account for almost the entire difference (369,380 - 61,880 =
307,500 cycles, matching the ~307,000-cycle gap in the totals).

Why: row-major access walks memory sequentially, so each 64-byte cache line
that is fetched serves the next several accesses. Column-major access jumps
`128 * 4 = 512` bytes every step, touching a new line almost every time, and the
matrix is far larger than the cache, so lines are evicted before they are
reused.

## What to take away

* Instruction count is not cost. Two programs with identical instruction
  counts differed 2x in cycles purely through **memory access pattern**.
* `--cache` makes that visible: the **miss count** and **miss-stall cycles**
  are the signal, and here they explain the whole gap.
* The practical lesson for real code: iterate arrays in the order they are laid
  out in memory (row-major in C), block large traversals to fit the cache, and
  prefer sequential over strided access.

## Try it yourself

* Shrink `N` to 32 (a 4 KB matrix, smaller than the 16 KB cache) and re-run -
  the two versions converge, because the whole matrix now stays resident.
* Change the cache size with `--dcache 4` (4 KB) or `--dcache 64` and watch the
  miss rate move. `--icache`/`--dcache` imply `--cache`.
* See [../doc/PROFILING.md](../doc/PROFILING.md) for the full cache-report format
  and the associativity/line-size parameters.
