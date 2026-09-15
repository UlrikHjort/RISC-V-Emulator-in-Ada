# Tutorials

Task-oriented walkthroughs: pick the job you want to do, follow the steps, and
you should see the same numbers printed here. Each one is self-contained and
uses a small example program in this directory (built by the local `Makefile`)
or an existing program from `../programs`.

If you are brand new, read [../TUTORIAL.md](../TUTORIAL.md) first for the
feature-by-feature tour; these go the other way round -- they start from a goal.

## Build the examples

```bash
cd tutorials
make            # builds out/elf/*.elf and out/bin/*.bin
```

You need a bare-metal RISC-V toolchain; see
[../doc/WRITING-PROGRAMS.md](../doc/WRITING-PROGRAMS.md) if `riscv32-unknown-elf-gcc`
is not on your `PATH` (override with `make CROSS=...`).

## The walkthroughs

| # | Goal | Emulator features |
|---|------|-------------------|
| [01](01-optimize-a-hot-loop.md) | Make a slow program fast: profile, find the bottleneck, fix it, measure | `--profile` stall breakdown, cycle model |
| [02](02-find-a-crash.md) | Find a wild pointer / out-of-bounds bug | access-fault traps, `mcause`/`mtval`, `-d` |
| [03](03-cache-and-stalls.md) | See why memory-bound code is slow | `--cache`, `--profile`, `mcycle` |
| [04](04-debug-with-gdb.md) | Debug a wrong result like real hardware | `--gdb`, breakpoints, watchpoints |
| [05](05-catch-a-regression.md) | Prove a change didn't alter behaviour | `--irecord` / `--ireplay` |
| [06](06-measure-coverage.md) | Find untested code | `--coverage` |
| [07](07-bring-up-your-own.md) | Get your own algorithm running + self-checked | linker/startup, semihosting log |
| [08](08-rv32-vs-rv64.md) | Run the same code as 32- and 64-bit | ELF-class auto-detect |

All cycle counts below come from this emulator's timing model (load-use and
branch stalls, a multi-cycle multiply/divide penalty, optional L1 cache
simulation) -- they are a consistent model for reasoning about relative cost,
not silicon-exact numbers.
