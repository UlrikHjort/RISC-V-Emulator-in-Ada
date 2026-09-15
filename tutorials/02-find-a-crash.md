# 2. Find a wild-pointer bug

**Goal:** a program misbehaves because it writes through a bad pointer. Find
exactly where, and why.

**You will use:** the emulator's **access-fault trap** (an unmapped or
read-only access raises a fault instead of silently corrupting memory), the
faulting PC, and the interactive debugger (`-d`).

Why an emulator helps here: on real hardware a stray write often *succeeds*,
quietly corrupting something you notice much later. This emulator stops at the
instant of the bad access and tells you where it was.

The example is `wildptr.c`: a lookup that returns `NULL` when a key is absent,
and a caller that forgets to check.

---

## Step 1 - run it and watch it trap

```bash
cd tutorials
make out/elf/wildptr.elf
../bin/riscv_emulator --machine qemu-virt --log-dir /tmp out/elf/wildptr.elf
```

```
Loading ELF file: out/elf/wildptr.elf
Starting emulation...

Emulation stopped.
CPU State:
  PC = 16#800006E6#
  ...
  Halted: TRUE
  Exception: STORE_ACCESS_FAULT
```

```bash
cat /tmp/wildptr.log
```
```
looking up key 99...
```

The program stopped with a **STORE_ACCESS_FAULT**, and the log confirms it never
got past the lookup - the "stored ..." line never printed. So a *store*
(a write) went somewhere it should not have, at **PC 0x800006E6**.

## Step 2 - what instruction faulted?

Disassemble around that address:

```bash
riscv32-unknown-elf-objdump -d out/elf/wildptr.elf | grep -B4 '6e6:'
```

```
800006dc:  jal   80000666 <slot_for.constprop.0>
800006de:  li    a2,123
800006e2:  lui   a1,0x80000
800006e6:  sw    a2,0(a0)          <-- the fault
```

The faulting instruction is `sw a2, 0(a0)` - store the value 123 to the address
in `a0`. So `a0` held a bad address. Notice the instruction just before the
sequence: `jal ... <slot_for>` - `a0` is whatever `slot_for` returned.

## Step 3 - inspect the bad pointer in the debugger

Run under `-d`, continue to the fault, and dump registers:

```bash
printf 'c\nregs\nq\n' | \
  ../bin/riscv_emulator --machine qemu-virt --log-dir /tmp -d out/elf/wildptr.elf
```

```
(riscv) CPU halted: STORE_ACCESS_FAULT
  PC = 16#800006E6#
  ...
  a0 = 0x00000000
```

`a0 = 0`. The store was through a **NULL pointer**. (Had a trap handler been
installed, `mtval` would hold that same faulting address, `0`.)

## Step 4 - root cause and fix

`a0` is the return value of `slot_for`. Look at the source:

```c
static int *slot_for(int *table, int n, int key)
{
    for (int i = 0; i < n; i++)
        if (table[i * 2] == key)
            return &table[i * 2 + 1];
    return 0;                     /* not found -> NULL */
}
...
int *v = slot_for(table, 4, lookup_key);   /* key 99 is absent -> NULL */
*v = 123;                                  /* BUG: no NULL check      */
```

Key 99 is not in the table, so `slot_for` returns `NULL`, and `main` writes
through it. The fix is the missing check:

```c
int *v = slot_for(table, 4, lookup_key);
if (v == 0) {
    log_write(NONE, "key not found\n");
} else {
    *v = 123;
}
```

## What to take away

* An unmapped or read-only access **traps** (`STORE_ACCESS_FAULT`,
  `LOAD_ACCESS_FAULT`, or `INSN_ACCESS_FAULT`) instead of silently succeeding -
  the emulator stops *at the bad instruction*, not later.
* The **faulting PC** plus a quick `objdump` identifies the exact access; the
  **base register** in that instruction is the bad pointer.
* From there it is ordinary detective work: where did that register come from?
* If you would rather the emulator *not* trap (to mimic permissive hardware),
  `--no-access-faults` restores the old silent behaviour - but for finding
  bugs, the trap is the point.

## Try it yourself

* Change `lookup_key` to `3` (present) and confirm the program completes and
  logs "stored 30".
* Point a load at unmapped memory instead (`int x = *(volatile int *)0x40000000;`)
  and watch it trap as `LOAD_ACCESS_FAULT`.
* Declare a small `rom` region in a `--config` profile and store into it to see
  a permission fault (see [../doc/PROFILES.md](../doc/PROFILES.md)).
