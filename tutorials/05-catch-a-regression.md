# 5. Prove a change didn't alter behaviour

**Goal:** you refactored something - the emulator, or a program - and want to be
sure execution is *bit-for-bit identical* to before. Or you want the first
instruction where two runs diverge.

**You will use:** `--irecord` (record a golden instruction trace) and
`--ireplay` (replay and check against it).

---

## Step 1 - record a golden trace

Run the known-good version once, recording every instruction's PC, encoding,
destination register and result:

```bash
cd tutorials
make out/elf/primes-fast.elf
../bin/riscv_emulator --machine qemu-virt --log-dir /tmp -q \
    --irecord /tmp/pf.trace out/elf/primes-fast.elf
```

The trace is a compact binary file (20 bytes/instruction on RV32; 32 on RV64):

```
$ ls -l /tmp/pf.trace
-rw-r--r-- ... 2414840 /tmp/pf.trace      # 120742 instructions
```

## Step 2 - replay it

After making a change you believe is behaviour-preserving (a refactor of the
emulator, a `-O` bump, a cleanup), replay the same program against the trace:

```bash
../bin/riscv_emulator --machine qemu-virt --log-dir /tmp \
    --ireplay /tmp/pf.trace out/elf/primes-fast.elf
```

```
Replay OK - 120742 steps matched.
```

Every PC and every register write matched - the change is safe.

## Step 3 - what a divergence looks like

If behaviour changes, replay stops at the **first** differing instruction and
tells you exactly where. To see it, replay the trace against a *different*
program (here the slow primes, which shares the entry address but not the code):

```bash
../bin/riscv_emulator --machine qemu-virt --log-dir /tmp \
    --ireplay /tmp/pf.trace out/elf/primes-slow.elf
```

```
MISMATCH at step 4 PC=0x8000000c x5=0x800007b8 expected=0x800007d0
Replay FAILED - 1 mismatch(es).
```

Step 4 is the first instruction whose result differs (register `x5` got
`0x800007b8`, the trace expected `0x800007d0`). In a real regression hunt that
step number and PC point you straight at the divergence instead of leaving you
to bisect output by hand.

## What to take away

* `--irecord` / `--ireplay` give you a **golden-trace regression check** at the
  instruction level - far finer than comparing printed output.
* A clean run reports `Replay OK - N steps matched`; a regression reports the
  **first** diverging step, PC and register, so you localise it immediately.
* It is also a determinism check: record twice and replay - identical runs must
  match to the instruction.

## Try it yourself

* Record `primes-fast`, rebuild the emulator after editing `src/`, and replay
  to confirm your emulator change didn't perturb execution.
* Trace files are XLEN-specific; an RV64 trace (32-byte records) replayed
  against an RV32 run is rejected rather than silently mis-compared.
* See [../doc/PROFILING.md](../doc/PROFILING.md) "Binary Trace and Replay".
