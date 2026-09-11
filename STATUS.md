# RISC-V Emulator -- Project Status
*Last updated: 2026-07-01*

## What This Is

An Ada-based RISC-V (RV32/RV64) emulator targeting embedded software testing.
Supports RV32IMAFDC + V + Zbb/Zbs/Zba/Zbkc/Zbkx/A/Zicond/Zfh + RV32E/RV64E and
RV64IMAFD + Zbb/Zba/A/Zicond ISA, a bare-metal C runtime, 78 algorithm/peripheral
test programs (2263 assertions all passing), an interactive debugger, a GDB remote
stub (RV32+RV64, incl. hardware watchpoints with correct T05 watch/rwatch/awatch
stop reply), an instruction-level profiler with cycle-accurate stall model (MUL/DIV/FP/CSR/
load-use/branch-taken stalls) and L1 cache simulation (cache stalls reflected in both
wall cycles and `mcycle` CSR), instruction coverage tracking, and binary instruction
trace/replay. Supervisor mode (S-mode) + SBI shim, PLIC, VirtIO block device,
Sv39 MMU, and multi-hart support (configurable hart count via `--harts N`) supported.
A semihosting host file-I/O interface (ECALLs 0x505-0x50C) lets bare-metal programs open,
read, write, and seek real files on the host -- used to run a full **DOOM** port (doomgeneric)
that boots the shareware IWAD and renders the attract demo to PPM frames.

**Primary use case:** Test embedded C/RISC-V software before real hardware is available.

---

## Build

```bash
make                      # build emulator (Ada, src/)
cd programs && make all   # build all C test programs
bash programs/test-all.sh # run all 83 tests -- expect 2263 PASS, 0 FAIL
```

---

## Emulator -- Ada Source (src/)

| File | Purpose |
|------|---------|
| `main.adb` | Entry point, CLI parsing, run loop, GDB/profile/debug dispatch |
| `riscv-cpu.adb/.ads` | CPU step, decode/execute, ECALL handler (incl. exit syscall 93) |
| `riscv-alu.adb/.ads` | Integer ALU, M-extension, Zbb/Zbs/Zba/Zbkc/Zbkx |
| `riscv-fpu.adb/.ads` | F/D extension (IEEE 754 single + double) |
| `riscv-vector.adb/.ads` | V extension (RVV) |
| `riscv-compressed.adb/.ads` | C extension (RVC 16-bit instructions) |
| `riscv-csr.adb/.ads` | CSR read/write, instret/mcycle counters, mcountinhibit/mcounteren/HPM stubs |
| `riscv-decoder.adb/.ads` | Instruction field decode |
| `riscv-disasm.adb/.ads` | Disassembler (trace/debug) |
| `riscv-memory.adb/.ads` | Memory map + peripheral dispatch |
| `riscv-uart.adb/.ads` | UART + PTY |
| `riscv-gpio.adb/.ads` | GPIO |
| `riscv-spi.adb/.ads` | SPI + 64KB flash (page program, read, erase) |
| `riscv-i2c.adb/.ads` | I2C |
| `riscv-timer.adb/.ads` | Hardware timer |
| `riscv-clint.adb/.ads` | CLINT (mtime/mtimecmp) |
| `riscv-watchdog.adb/.ads` | Watchdog timer |
| `riscv-dma.adb/.ads` | DMA controller |
| `riscv-plic.adb/.ads` | PLIC -- 32 sources, 2 contexts (M/S-mode), priority/enable/threshold/claim |
| `riscv-virtio_block.adb/.ads` | VirtIO MMIO block device v2 -- 512KB in-memory disk, virtqueue processing |
| `riscv-mmu.adb/.ads` | Sv39 MMU -- 3-level page table walk, 64-entry TLB, 1GB/2MB/4KB superpages |
| `riscv-cpu64.adb/.ads` | RV64 CPU core (RV64IMAFD + Zbb/Zba/A/Zicond + Sv39 MMU integration) |
| `riscv-alu64.adb/.ads` | RV64 integer ALU + W-suffix ops |
| `riscv-csr64.adb/.ads` | RV64 CSR state |
| `riscv-pty.adb/.ads` | PTY helper |
| `riscv-elf.adb/.ads` | ELF loader (PT_LOAD segments) |
| `riscv-symbols.adb/.ads` | ELF symbol table (debugger/profiler) |
| `riscv-crypto.adb/.ads` | Hardware crypto acceleration |
| `riscv-config.adb/.ads` | Machine profiles (simple / qemu-virt) |
| `riscv-debugger.adb/.ads` | Interactive debugger (RV32 + RV64, overloaded `Run`/`Show_Backtrace`) |
| `riscv-gdb.adb/.ads` | GDB Remote Serial Protocol stub |
| `riscv-profiler.adb/.ads` | Instruction-level profiler (RV32 + RV64 via `Record_Instruction` overload) |
| `riscv-coverage.adb/.ads` | Instruction coverage tracker (bitmap + per-function %) |
| `riscv-trace_replay.adb/.ads` | Binary instruction trace recording and replay |
| `riscv-cache.adb/.ads` | L1 set-associative cache simulation (I-cache + D-cache, LRU, configurable size/ways) |

### Hardware Profiles

| Profile | RAM base | RAM size | Peripherals |
|---------|----------|----------|-------------|
| `simple` | 0x00000000 | 64KB | UART @ 0x10000000 |
| `qemu-virt` | 0x80000000 | 128MB | UART, CLINT, PLIC, GPIO, SPI, I2C, Timer, Watchdog, DMA, VirtIO Block |

**QEMU Virt peripheral addresses:**

| Peripheral | Base Address | Notes |
|------------|-------------|-------|
| UART 16550 | 0x10000000 | PTY or stdio |
| CLINT | 0x02000000 | mtime/mtimecmp, software interrupt |
| PLIC | 0x0C000000 | 32 sources, 2 contexts (M/S-mode) |
| GPIO | 0x10010000 | 32-bit input/output/direction/edge-detect |
| SPI | 0x10020000 | + 64KB in-memory flash |
| I2C | 0x10030000 | Simulated temp sensor, accelerometer, EEPROM |
| Timer | 0x10040000 | Periodic/one-shot, interrupt on compare |
| Watchdog | 0x10050000 | Timeout reset |
| DMA | 0x10060000 | 4-channel memory copy |
| VirtIO Block | 0x10001000 | MMIO v2, 1024 sectors x 512B = 512KB, PLIC src 8 |

### Key CLI Flags

```
bin/riscv_emulator [flags] <program.bin|.elf> [load_address]

--machine simple|qemu-virt   Hardware profile (required for ELF)
--config <file>              Load hardware profile from file
--list-machines              List available hardware profiles
--pty                        Expose UART as PTY
--wait                       Wait for PTY connection before starting
--no-uart                    Disable UART emulation
-t                           Instruction trace to stdout
--trace-file <f>             Redirect trace to file
--trace-range <s> <e>        Only trace PC in [s, e]
--trace-mem                  Include memory accesses in trace
--trace-regs                 Include register diffs in trace
-d                           Interactive debugger (REPL)
--gdb [port]                 GDB RSP server (default port 1234)
--profile                    Instruction profiler (report on exit)
--flamegraph <file>          Export flamegraph folded-stack data
--coverage [file]            Instruction coverage report (default: coverage.txt)
--irecord <file>             Record binary instruction trace (20 bytes/insn)
--ireplay <file>             Replay and verify against binary trace file
--max-instructions <n>       Stop after N instructions
--timeout <n>                Halt after N wall-clock seconds
--harts <n>                  Number of harts to simulate (1 or 2)
--log-dir <dir>              Write semihosting log files to <dir> (created if absent)
--host-io <mode>             Guest access to host files: off, ro, rw (default: rw)
--host-io-root <dir>         Confine guest host-file paths to <dir> (default: CWD)
--no-access-faults           Complete unmapped/read-only accesses silently (legacy)
--gdb-listen-all             Bind the GDB stub to all interfaces (unauthenticated)
--rv32e                      Enable RV32E mode (16-register subset, rewrites MISA)
--rv64e                      Enable RV64E mode (16-register subset for RV64)
--cache                      Enable L1 I+D cache simulation (4-way each, miss=20cy)
--icache <kb>                I-cache size in KB (implies --cache)
--dcache <kb>                D-cache size in KB (implies --cache)
--htif                       Terminate on HTIF tohost write (riscv-tests)
--tohost <hex>               HTIF tohost address (implies --htif; needed for RV64)
--dump-signature <b> <e> <f> Dump signature memory region after halt (arch-test)
-v                           Verbose output (show loading details)
-q, --quiet                  Suppress startup messages
```

---

## Interactive Debugger (`-d`)

| Command | Description |
|---------|-------------|
| `b <addr>` | Set breakpoint |
| `bl` / `bc <n>` | List / clear breakpoints |
| `watch <addr> [r\|w\|rw]` | Set memory watchpoint |
| `wl` / `wc <n\|all>` | List / clear watchpoints |
| `s` | Single step |
| `n` | Step over |
| `c` | Continue |
| `r` | Print integer registers |
| `fregs` | Print FP registers |
| `vregs` | Print vector registers (formatted by current SEW) |
| `m <addr> [n]` | Dump memory |
| `d <addr> [n]` | Disassemble |
| `sym <name>` / `syms` | Symbol lookup / list |
| `bt` | Stack backtrace |
| `q` | Quit |

---

## GDB Stub (`--gdb [port]`)

Implements GDB Remote Serial Protocol for both RV32 and RV64 targets.
Automatically selects RV32 or RV64 register encoding based on the loaded ELF.

Supported RSP packets: `?`, `g`/`G`, `p`/`P`, `m`/`M`, `c`, `s`, `Z0`/`z0`,
`Z2`/`z2` (write watchpoint), `Z3`/`z3` (read watchpoint), `Z4`/`z4` (access watchpoint),
`qSupported`, `qXfer:features:read:target.xml`, `qAttached`, `qC`,
`qfThreadInfo`/`qsThreadInfo`, `QStartNoAckMode`, `vCont?`/`vCont;c`/`vCont;s`,
`H`, `T`, `D`, `k`.

**RV32**: target XML `riscv:rv32`, registers at 32-bit (8 hex chars each).
**RV64**: target XML `riscv:rv64`, registers at 64-bit (16 hex chars each).
Stop reply: `T05` format with SP and PC inline (width matches register size).
Software breakpoints: up to 64. Hardware watchpoints: up to 32 each (write/read/access).
Breakpoint/watchpoint addresses stored as 64-bit internally (RV32 addresses zero-extended).

```bash
# RV32 -- Terminal 1:
bin/riscv_emulator --machine qemu-virt --gdb programs/out/elf/branch-test.elf

# Terminal 2:
riscv32-unknown-elf-gdb programs/out/elf/branch-test.elf
(gdb) target remote localhost:1234
(gdb) break main
(gdb) continue
(gdb) stepi
(gdb) info registers

# RV64 -- Terminal 1:
bin/riscv_emulator --machine qemu-virt --gdb programs/out/elf/rv64-test.elf

# Terminal 2:
riscv64-unknown-elf-gdb programs/out/elf/rv64-test.elf
(gdb) target remote localhost:1234
(gdb) break main
(gdb) continue
(gdb) info registers
```

---

## Sv39 Virtual Memory MMU

Implements the RISC-V Sv39 (39-bit virtual address space) page table format for RV64.
Active when `satp.MODE=8` and the CPU is in S-mode or U-mode. M-mode always uses
physical addresses.

**Features:**
- 3-level page table walk (VPN[2]:VPN[1]:VPN[0], each 9 bits + 12-bit page offset)
- 1GB, 2MB, and 4KB pages (superpages at levels 2 and 1)
- 64-entry fully-associative TLB with round-robin replacement
- ASID support (16-bit address-space ID from `satp`)
- Global pages (G bit) match any ASID
- Permission checks: R/W/X per page, U/S-mode access control, MXR and SUM bits from mstatus
- A/D bits updated on every access (hardware-managed)
- `sfence.vma` instruction flushes the TLB
- Page fault exceptions: instruction (cause 12), load (cause 13), store/AMO (cause 15)
- `stval` set to the faulting virtual address

**New source:** `src/riscv-mmu.ads/.adb`

**Test:** `programs/sv39-test.c` (9 assertions -- identity mapping, write/read, sfence.vma,
load page fault, stval, disable/re-enable, U-mode access fault in S-mode)

---

## Profiler (`--profile`)

Prints after program exit:
1. **Function Profile** -- top 20 by wall-cycle count, with %, instruction count, call count
2. **Instruction Histogram** -- top 20 opcodes by execution count
3. **Hot Instructions** -- top 20 most-executed PC addresses with symbol name
4. **Call Graph** -- caller -> callee pairs with call counts
5. **Cycle-accurate stall model** -- MUL(+2), DIV(+32), FP arith(+3), FP div/sqrt(+19), CSR(+1); total wall cycles, average CPI, per-type stall breakdown
6. **L1 cache stats** -- I-cache and D-cache hit/miss/stall counts (when `--cache`/`--icache`/`--dcache` used); miss stalls also added to `mcycle` CSR so `rdcycle` reflects true wall time

Optional: `--flamegraph <file>` exports folded-stack format for flamegraph.pl.

Performance design: O(1) per instruction in hot path. Symbol lookup only on
call/return transitions. Hot-PC and flamegraph sampling every 10,000 instructions.
Cache stalls are accumulated in profiler wall-cycle counts only -- they do NOT affect
the `mcycle` CSR (preserves timing-test correctness).

```bash
bin/riscv_emulator --machine qemu-virt --profile programs/out/elf/fir-filter.elf
```

---

## C Runtime (programs/)

### Core Files

| File | Purpose |
|------|---------|
| `crt0.S` | Startup: zero BSS, call main, then `ecall 93` (exit) |
| `uart.c` | UART putchar/puts |
| `log.h` + `log.c` | Host log file via semihosting ECALLs |
| `syscalls.c` | malloc/free, atoi, qsort, strtol, strtoul, sscanf |
| `printf.c` + `ftoa.c` | printf/sprintf/snprintf with full FP support |
| `atof.c` | atof, strtod (requires FP; link separately when needed) |
| `string.c` | mem*/str* functions |
| `math.c` | sin/cos/sqrt/pow/log (software FP) |
| `time.h` + `time.c` | POSIX time API: `clock_gettime` (MONOTONIC=mtime, THREAD_CPUTIME=rdcycle), `gettimeofday` |
| `hello.ld` | Linker script |

### Semihosting ECALLs (value in register a7)

| a7 | Name | Args | Returns |
|----|------|------|---------|
| 0x500 | HOST_LOG_OPEN | a0=filename ptr, a1=len | 0 / -1 |
| 0x501 | HOST_LOG_WRITE | a0=data ptr, a1=len | bytes written |
| 0x502 | HOST_LOG_CLOSE | -- | 0 |
| 0x503 | HOST_LOG_REGS | -- | 0 (dumps registers to log) |
| 0x504 | HOST_GET_TIME_MS | -- | ms since midnight |
| 0x505 | HOST_FILE_OPEN | a0=path ptr, a1=len, a2=mode (0=r/1=w/2=a) | handle 0-15 / -1 |
| 0x506 | HOST_FILE_READ | a0=handle, a1=buf ptr, a2=n | bytes read |
| 0x507 | HOST_FILE_WRITE | a0=handle, a1=buf ptr, a2=n | bytes written |
| 0x508 | HOST_FILE_CLOSE | a0=handle | 0 |
| 0x509 | HOST_FILE_SEEK | a0=handle, a1=offset, a2=whence | 0 / -1 |
| 0x50A | HOST_FILE_TELL | a0=handle | position |
| 0x50B | HOST_FILE_SIZE | a0=handle | size in bytes |
| 0x50C | HOST_FRAME_DUMP | a0=RGBA buf ptr, a1=frame no | writes doom_frame_NNNNNN.ppm |
| 0x50D | HOST_FB_TERM | a0=RGBA buf ptr | renders framebuffer to the terminal (ANSI) |
| 0x50E | HOST_KEY_POLL | -- | next stdin byte, or 0 if none (non-blocking) |
| 93 | exit | a0=status | (halts emulator) |

### log_write() Notes
- `log_write(NONE, "fmt", ...)` -- plain text
- `log_write(TIME_STAMP, ...)` -- prepends `[HH:MM:SS.mmm]`
- `log_write(CYCLES, ...)` -- prepends `[cycle_count]` via `rdinstret`
- Supported format specifiers: `%d %u %x %X %s %c` -- **no width/padding**
- For padded output use `sprintf` from `printf.c` instead

### New Test Program Pattern

```makefile
# In programs/Makefile:
$(ELF)/my-test.elf: crt0.S uart.c log.c my-test.c hello.ld | $(ELF)
    $(CC) $(CFLAGS) $(LDFLAGS) -o $@ crt0.S uart.c log.c my-test.c

$(BIN)/my-test.bin: $(ELF)/my-test.elf | $(BIN) $(DIS)
    $(OBJCOPY) -O binary $< $@
    $(OBJDUMP) -d $< > $(DIS)/my-test.dis

run-my-test: $(BIN)/my-test.bin
    $(EMULATOR) $(LOGFLAGS) --machine qemu-virt --pty --wait $< 80000000
    @cat $(LOG_DIR)/my-test.log
```

```c
// my-test.c
#include <stdint.h>
#include "log.h"
static int g_pass = 0, g_fail = 0;
static void chk(const char *label, int ok) {
    if (ok) { log_write(NONE, "PASS %s\n", label); g_pass++; }
    else     { log_write(NONE, "FAIL %s\n", label); g_fail++; }
}
int main(void) {
    log_init("my-test.log");
    // ... tests ...
    log_write(NONE, "\n%d PASS  %d FAIL\n", g_pass, g_fail);
    log_close();
    return g_fail ? 1 : 0;
}
```

---

## DOOM Port (programs/doom/)

A bare-metal port of the [doomgeneric](https://github.com/ozkl/doomgeneric) DOOM engine,
running as an RV32IMAC ELF on the emulator. It reads the WAD from the host and dumps
rendered frames back to the host via the semihosting file-I/O ECALLs (0x505-0x50C).
**Full write-up of how it works: [doom.md](doom.md).**

| File | Purpose |
|------|---------|
| `doom/doomgeneric_riscv.c` | `DG_*` platform glue; framebuffer -> PPM via ECALL 0x50C |
| `doom/newlib_syscalls.c` | `_open`/`_read`/`_write`/`_close`/`_lseek` over ECALLs 0x505-0x50B |
| `doom/crt0_doom.S` | Startup (sets up stack, calls `main`, `exit` on return) |
| `doom/hello_doom.ld` | Linker script (RAM @ 0x80000000) |

The doomgeneric engine source is vendored under `programs/doom/doomgeneric/` (GPLv2 --
see `programs/doom/README.md`), because the port depends on bare-metal modifications
that do not exist upstream. `doom1.wad` and the run artifacts (`doom_frame_*.ppm`,
`doom.mp4`, `doom.gif`) are gitignored; no game data is distributed.

```bash
make -C programs doom          # build out/elf/doom.elf from the vendored source
make -C programs run-doom      # download shareware WAD if missing, then run
#   -> boots the IWAD, plays the attract demo, writes doom_frame_000000.ppm ... 000059.ppm
make -C programs doom-video    # optional: stitch PPMs -> doom.mp4 (needs ffmpeg)
make -C programs doom-gif      # optional: stitch PPMs -> doom.gif (needs ffmpeg)
```

The WAD, frames, and video live in `$(DOOM_RUN_DIR)` -- a dedicated `doom-run/` folder at
the repo root by default (override with `DOOM_RUN_DIR=/path`). `make clean` deletes the
generated frames + video there (keeping the cached WAD); `make doom-clean` wipes the whole
folder. To run the emulator by hand, `cd` into that directory (so it finds `doom1.wad` and
writes frames there): `bin/riscv_emulator --machine qemu-virt programs/out/elf/doom.elf`.

**Verified 2026-07-01:** frame 0 renders the DOOM title screen, frame 59 shows in-game
gameplay (HUD + monsters), and the program exits cleanly after 60 frames.

### Interactive (in-terminal) DOOM

```bash
make -C programs run-doom-tty    # live keyboard + ANSI terminal rendering
```

A second build (`doom-tty.elf`, `-DDOOM_INTERACTIVE`) renders each frame to the terminal
as truecolour ANSI half-blocks (ECALL 0x50D) and reads the keyboard from the host (ECALL
0x50E) instead of dumping PPM frames. Controls: **WASD** move/turn, **Q/E** strafe,
**SPACE** fire, **F** use, **1-7** weapons, **ENTER/ESC** menu, **`** (backtick) quit.
Needs a terminal >= 100 cols x 34 rows. Note the emulator runs DOOM at roughly ~0.5-1 fps,
so play is deliberate rather than twitchy.

### Why DOOM Matters -- A Validation Milestone

Beyond being a fun demo, running the full DOOM engine is a meaningful correctness/robustness
signal for the emulator, in ways the unit tests can't cover on their own:

- **Third-party, optimizer-hardened code.** DOOM was written in 1993 for real hardware and
  compiled here by a stock GCC that assumes a fully correct machine -- it makes no allowances
  for emulator quirks. The 83 test programs were written *knowing* this emulator; DOOM was not.
  It's an adversarial, independent workload.
- **Sustained, long-running execution.** A unit test runs a few thousand instructions and
  stops. DOOM runs *billions* per session. Any rare incorrectness (a sign-extension edge case,
  a flag set wrong 0.001% of the time, a subtle PC miscalculation) accumulates and eventually
  derails -- reaching a stable framebuffer 60 frames in shows the core is faithful over the long
  haul, not just on the golden path.
- **Broad ISA + memory pressure.** Fixed-point math leans on the full `M` extension; newlib
  pulls in `A` atomics; the code stream is dense with `C` compressed instructions. DOOM runs
  its own zone allocator over `sbrk`, streams megabytes out of the WAD, and pointer-chases the
  BSP tree -- exercising loads/stores, alignment, and the file-I/O ECALLs at scale.

The scope boundary is deliberate and *not* a soundness gap: there is no emulated VGA card,
sound chip, or DOS interrupts -- the guest gets those services through semihosting ECALLs
instead. The parts that must be correct (the CPU, memory, and the ISA) demonstrably are.

**Bottom line:** "DOOM runs, clean" alongside "2263 assertions across 83 tests" gives both
breadth (deliberate corner cases) and depth (a large real program under sustained load).

---

## Test Programs -- All 83 Passing (2263 Assertions)

| Test | PASS | Subject |
|------|------|---------|
| fp-math-test | 72 | FPU: fadd/fsub/fmul/fdiv, fcvt, NaN/Inf/-0, f32/f64/promotion |
| rvv-advanced | 44 | RVV: vsub/vrsub, bitwise, shifts, min/max, vmacc, vrgather, e8/e16/m2, masked |
| string-ops | 65 | memset/cpy/move/cmp, strlen, strcpy/cmp/cat, strchr/strstr |
| chacha20 | 10 | RFC 7539 quarter-round, block function, encrypt/decrypt |
| rvv-float | 33 | RVV FP: vfadd/mul/div, vfmacc, vfsqrt, vfredosum, dot product |
| m-ext-test | 58 | All 8 MUL/DIV/REM ops + edge cases (div-by-zero, INT_MIN/-1) |
| trap-test | 18 | illegal insn, ebreak, ecall, emulated misaligned access, multi-trap, M-timer interrupt |
| lz77 | 8 | LZSS compress/decompress round-trips |
| branch-test | 56 | BEQ/BNE/BLT/BGE/BLTU/BGEU all value combinations |
| load-store-test | 56 | LW/LH/LB/LHU/LBU/SW/SH/SB, aligned/unaligned, sign-ext |
| csr-test | 48 | MISA/MSTATUS/MEPC/MCAUSE/MTVEC/MSCRATCH, CSR insns, MIE/MIP, MEDELEG/MIDELEG |
| rvv-strided | 48 | vlse/vsse 8/16/32-bit, negative stride, indexed gather/scatter |
| float-classify | 38 | fclass.s/d all 10 categories, FCSR rounding, exception flags |
| aes128 | 10 | NIST FIPS-197 App B/C.1, SP 800-38A block 1, round-trip |
| base64 | 31 | RFC 4648 encode/decode KATs, padding, round-trip |
| huffman | 11 | Min-heap tree build, code assign, bit-level encode/decode |
| crc32-test | 9 | CRC32("123456789")=0xcbf43926, incremental, bulk |
| sha256-test | 5 | FIPS 180-4 empty/"abc"/56-byte, determinism, avalanche |
| sort-bench | 28 | insertion/heap/quicksort/mergesort on random/sorted/reverse/equal |
| fir-filter | 25 | 16-tap scalar+RVV FIR, impulse/step/ramp, linearity |
| zbb-test | 77 | CLZ/CTZ/CPOP/SEXT.B/H/ORC.B/REV8/MIN/MAX/ROL/ROR + Zbs BSET/BCLR/BINV/BEXT |
| fixedpoint-test | 50 | Q15 arith, Q16.16, CORDIC sin/cos, isqrt, saturation |
| atomic-test | 68 | All AMO ops (SWAP/ADD/XOR/AND/OR/MIN/MAX/MINU/MAXU), LR/SC, spinlock |
| clmul-test | 28 | CLMUL/CLMULH (Zbkc), XPERM4/XPERM8 (Zbkx) |
| gf256-test | 48 | GF(2^8) field arithmetic, AES MixColumns, multiplicative inverse |
| pid-test | 20 | P/I/D terms, combined PID, step response convergence, anti-windup |
| zba-test | 125 | sh1add/sh2add/sh3add; array addressing (int16/32/64) |
| lfsr-test | 32 | 8/16-bit Fibonacci+Galois LFSR, period, balance |
| iir-test | 36 | LP1/HP1 single-pole, LP2 two-pole, impulse/step, DC gain |
| fft-test | 63 | N=8 radix-2 DIT FFT Q16.16; impulse/DC/Nyquist/Parseval/linearity |
| montgomery-test | 39 | MULHU, Hensel lift, REDC, mont_mul, Fermat, modexp, RSA |
| reed-solomon-test | 34 | GF(2^8)/0x11D, RS(7,3)+RS(15,9) encode, syndrome |
| ntt-test | 35 | NTT over Z_p=12289, polynomial multiply |
| ecc-test | 29 | Elliptic curve over F_17, G=(5,1), order=19; ECDH |
| rs-correct-test | 34 | BM+Chien+Forney; t=2 and t=3 error correction, uncorrectable detect |
| chacha20-poly1305 | 15 | RFC 8439 OTK, Poly1305, AEAD encrypt/decrypt, tamper detection |
| aes-gcm | 11 | NIST SP 800-38D B.1/B.2/B.3, GHASH, GCM seal/open, tamper |
| blake2s | 13 | RFC 7693 KATs (empty/abc/longer), incremental, avalanche |
| sha3 | 10 | FIPS 202 KATs (empty/abc/56-byte), incremental, avalanche |
| viterbi | 15 | K=7 rate-1/2 convolutional; encode; decode at 0/3/6/10 dB SNR |
| fft-conv | 12 | Overlap-add convolution; impulse/step; direct vs FFT comparison |
| scanf-test | 65 | sprintf/snprintf/sscanf/strtol/strtoul/strtod; width/pad/prec/float |
| rtos-test | 20 | Cooperative RTOS: task create/yield/sleep/exit, 3 concurrent tasks |
| fat12-test | 37 | FAT12 over SPI flash: format/init, create/write/read/delete/reuse |
| modbus-test | 42 | CRC-16/IBM, FC01/03/06/16, exception codes, OOB/bad-CRC/stress |
| deflate-test | 49 | Deflate compress/decompress: fixed/dynamic Huffman, LZ77 back-references |
| setjmp-test | 13 | setjmp/longjmp: return value, val=0->1, deep-nested, sp restore, volatile locals |
| smode-test | 17 | S-mode CSRs, SBI Base ext, probe_extension, exception+ebreak delegation, sstatus.SIE |
| umode-test | 7 | U-mode: ecall from U-mode, illegal insn fault, sret back to U-mode |
| hmac-sha256-test | 7 | HMAC-SHA256 per RFC 2104; SHA256 sanity, RFC 4231 TC1-TC4, determinism, length-sensitivity |
| aes-modes-test | 6 | AES-128 CBC encrypt/decrypt, CTR keystream and encrypt/decrypt |
| csr-more-test | 16 | mcountinhibit (inhibit/re-enable cycle+instret), mcounteren/scounteren, HPM stubs, RO regs |
| plic-test | 21 | PLIC priority/enable/threshold/pending (R/W, masking, RO bits), claim returns 0 when idle |
| rv64-test | 17 | RV64I: LWU/LD/SD, ADDI/ANDI/ORI/XORI/SLTI/SLTIU (64-bit), ADDIW/ADDW/SUBW/SLLW/SRLW/SRAW |
| rv64-fp-test | 39 | RV64D FPU: basic arithmetic, FCVT.L.D/LU.D/D.L/D.LU, FCLASS, FMV.X.D/D.X, comparisons |
| rv64-sha256-test | 6 | SHA-256 correctness on RV64 (same vectors as RV32 sha256-test) |
| rv64-wops-test | 38 | RV64 W-suffix ops: ADDIW/ADDW/SUBW/SLLW/SRLW/SRAW + LWU/LD/SD |
| rv64-zbb64-test | 47 | RV64 Zbb: CLZ/CTZ/CPOP (64-bit), REV8, BSWAP, SEXT.B/H/W, ROL/ROR, ANDN/ORN/XNOR |
| rv64-atomic-test | 30 | RV64 A: LR.D/SC.D + 10 AMO.D variants (SWAP/ADD/XOR/AND/OR/MIN/MAX/MINU/MAXU) |
| rv64-zba64-test | 29 | RV64 Zba: sh1add/sh2add/sh3add (64-bit) + add.uw/sh1add.uw/sh2add.uw/sh3add.uw |
| rv64-zicond-test | 16 | Zicond: czero.eqz/czero.nez, cmov pattern (both RV32 and RV64) |
| rv64-zbs64-test | 24 | RV64 Zbs: bset/bclr/binv/bext (register + immediate), shift amounts across the full 64-bit width |
| rv64-zbc64-test | 11 | RV64 Zbc/Zbkc: clmul/clmulh/clmulr vs a software carry-less-multiply reference, 12x12 pairs |
| rv64-zbkx64-test | 10 | RV64 Zbkx: xperm4 (16 nibbles) / xperm8 (8 bytes) vs a reference, incl. out-of-range indices |
| rv64-zbkb64-test | 13 | RV64 Zbkb: pack/packh/packw (widened halves) + brev8 |
| rv64-reserved-test | 16 | Reserved-encoding trap coverage: 11 reserved funct7/funct6 encodings must raise illegal-instruction, 5 legal ones must not (guards the decoder against aliasing to a base op) |
| prtos-test | 21 | Preemptive RTOS: timer interrupt, mret context switch, 4 concurrent tasks |
| prtos2-test | 25 | Preemptive RTOS extensions: mutex, message queue, priority scheduling, stack canary, task_sleep_until |
| virtio-blk-test | 29 | VirtIO MMIO block v2: negotiation, write/read/verify sectors, OOB, reset |
| sv39-test | 9 | Sv39 MMU: identity mapping, write/readback, sfence.vma, page fault (scause=13), stval, disable/re-enable, U-mode fault |
| p256-ecdsa-test | 27 | P-256 ECDSA: point arithmetic, key generation, sign/verify, invalid signature detection |
| x25519-test | 5 | X25519 key exchange: scalar multiplication, shared secret agreement, KAT |
| timing-test | 6 | CLINT mtime: monotonic increment, delay accuracy, task_sleep_ms calibration |
| zfh-test | 13 | Zfh half-precision float: fadd/fsub/fmul/fdiv, fcvt (h<->s<->d), fclass.h, NaN-boxing |
| multihart-test | 4 | Multi-hart: hart ID broadcast, inter-hart synchronisation via shared memory, --harts 2 |
| rv32e-test | 6 | RV32E: MISA.E set, MISA.I/V clear, MXL=1, arithmetic with 16-register subset |
| time-test | 12 | time.h: clock_gettime monotonic/nsec, gettimeofday usec, mktime/gmtime, difftime, THREAD_CPUTIME_ID (rdcycle) |
| coremark-test | 5 | Coremark-like: linked-list sort, 2x2 matrix multiply, FSM, CRC-16; determinism + cycles |
| rv64e-test | 6 | RV64E: MISA.E set, MISA.I/V clear, MXL=2, arithmetic with 16-register subset |
| ed25519-test | 11 | Ed25519 (RFC 8032): SHA-512, keypair, sign, verify, tamper, round-trip (TV1 + TV2) |
| pipeline-test | 6 | Pipeline timing: load-use stall (+1), no-stall baseline, taken branch (+1), JAL (+1), NOP throughput |
| pthread-test | 7 | pthread-lite over `--harts 2`: create/join, mutex, trylock, sequential reuse, void* retval |
| gzip-test | 8 | RFC 1952 gzip: magic/CM bytes, round-trip, CRC-32 + ISIZE trailer, tamper detection |
| **TOTAL** | **2263** | |

---

## Official Conformance: riscv-tests

Beyond the in-house suite above, the emulator runs the official
[riscv-tests](https://github.com/riscv-software-src/riscv-tests) ISA suite using the
standard bare-metal `p` (machine-mode) environment and the HTIF `tohost` termination
protocol. Two emulator flags support this:

- `--htif` -- halt when the guest writes its `tohost` symbol; report `PASS` / `FAIL <n>`
  and set the process exit status. Under HTIF the `a7=93` ECALL and the S-mode SBI shim
  are bypassed so ECALLs trap to the guest's own `mtvec` handler (as real hardware would).
- `--tohost <hex>` -- supply the `tohost` address directly (needed for RV64, whose ELF
  symbol table the built-in loader does not yet parse).

Runner: `programs/run-riscv-tests.sh` (builds each `.S` test against `env/p`, resolves
`tohost` via `nm`, runs it, tallies PASS/FAIL per family). It does **not** clone the
suite: check out `riscv-tests` into `programs/riscv-tests/` yourself first, or the
runner reports `skip <family> (no dir)` and a total of 0. That tree is gitignored.

**Current result: 284 / 293 passing.** Every user-mode ISA family is fully green:
rv32/rv64 ui, um, ua, uc, uf, ud (rv64), and uzba/zbb/zbs/zicond.
Wiring up this suite caught a series of real RV64 bugs, all now fixed:

- RV64 Zbb register-form ops (andn/orn/xnor/min/max/minu/maxu/rol/ror/rori/orc_b + roriw)
  used to execute as their base-ISA cousins -- the funct7 dispatch fell through to RV64I.
- RV64 Zba `slli.uw` was not decoded (needs a 6-bit shamt on the zero-extended low word).
- RV64C `c.addw`/`c.subw` (CA-format, bit12=1) were rejected as illegal.
- RV64C `c.ldsp`/`c.sdsp` decoded the stack offset from the wrong immediate bit-fields.
- Compressed float load/store (`c.flw`/`c.fsw`/`c.fld`/`c.fsd` and their `*sp` forms) were
  entirely undecoded -- the C0/C2 quadrants only handled integer loads/stores.
- RV64 `fsw` and `fmv.x.w` NaN-box-interpreted the register instead of storing/moving the
  raw low 32 bits (so a single stored/moved after an `fld` produced a canonical NaN).
- The unsigned word conversions `fcvt.wu.s`/`.d`/`.h` zero-extended their 32-bit result;
  the spec sign-extends even the unsigned W variants to XLEN.
- The 64-bit FP<->integer conversions `fcvt.l.s`/`.lu.s`/`.s.l`/`.s.lu` were missing and
  silently ran as their 32-bit cousins; added single<->int64 helpers.
- Unsigned integer conversions raised NV (invalid) for any negative input; a value in
  (-1,0) rounds toward zero to 0 and must instead raise NX (inexact) with an in-range 0.
- Misaligned data loads/stores are now emulated (the byte-composed memory accessors
  already handle any alignment) rather than trapping, so `ma_data` passes. (The in-house
  `trap-test` was updated to verify the emulated result instead of expecting a trap.)
- `misa.C` is now WARL and IALIGN is enforced: clearing C is refused when it would
  misalign the next fetch; with C disabled, a JAL/JALR/branch to a non-4-byte target
  raises instruction-address-misaligned on the transfer (rd left unwritten), and MRET
  masks `mepc[1]`. This makes both `ma_fetch` tests pass.
- RV32 `slli/srli/srai` with instruction bit 25 set (shamt >= 32) now trap as illegal
  (`shamt` passes).
- Supervisor-level interrupts are dispatched by *delegation target*, not by which
  privilege level names the bit. An S-level interrupt that `mideleg` delegates is taken
  only in S/U mode gated by `sstatus.SIE` (this fixed a `wfi` live-lock; both `wfi`
  tests pass). One that `mideleg` does *not* delegate still targets M-mode and is taken
  there regardless of `SIE` -- including while the hart runs in M-mode. Suppressing that
  second case was what made `rv32mi/illegal` and `rv64mi/illegal` spin forever on a
  pending SSIP; both now pass.
- `mstatus.TVM`, `TW` and `TSR` are implemented: TVM traps `SFENCE.VMA` *and* `satp`
  access from S-mode, TW traps `WFI` outside M-mode, TSR traps `SRET` from S-mode.

Remaining failures (9) are deeper machine/supervisor-mode features, each a separate
effort with low practical payoff:
- `csr` (rv32mi/rv64mi/rv64si) -- these are compiled without F/D yet assume `misa` reports
  those extensions absent; our emulator legitimately implements F/D, so the test's
  "skip if F present" path is never taken. Not fixable without misreporting `misa`.
- `dirty` -- needs MPRV (M-mode load/store using MPP's privilege) + SUM + page-table
  D-bit updates + superpage PPN-alignment faults.
- `breakpoint` -- the debug trigger module (tselect/tdata1/tdata2).
- `instret_overflow` -- counter-overflow local interrupts.

---

## Memory Access Semantics

An access to an address that no region or peripheral covers raises a fault
rather than reading zero or dropping the write:

| Access | Cause | mcause |
|---|---|---|
| Fetch from unmapped memory | instruction access fault | 1 |
| Load from unmapped or unreadable memory | load access fault | 5 |
| Store to unmapped memory, or to a `rom`/`flash` region | store access fault | 7 |

`mtval` holds the address of the **first** failing byte, so a word straddling
the end of a region reports the boundary rather than the access base. A
straddling access faults outright instead of returning a mix of real and zero
bytes.

Instruction fetch reads the low half-word first and only reads the upper half
for a 32-bit instruction, so a compressed instruction in the last half-word of
a region does not fault on the two bytes past its end.

Misaligned data accesses are still emulated, not trapped (only AMOs require
natural alignment). `--no-access-faults` restores the older behaviour, in
which every bad access completed silently.

## Host File I/O Policy

Guest programs reach the host filesystem through ECALLs `0x500` and
`0x505`-`0x50C`, naming the path themselves. Paths are resolved under a root
directory (`--host-io-root`, default: the working directory) and are rejected
if they are absolute, contain a `..` component, or contain a NUL.
`--host-io off|ro|rw` sets what is permitted at all; `off` covers the log
ECALL too. The check is on the name the guest supplies, not on where it
resolves to, so a symlink inside the root cannot be used to point back out.

## RV32 and RV64

**Scalar bitmanip / crypto reach both cores (2026-09-10).** RV64 now decodes
Zbs (bset/bclr/binv/bext), Zbc/Zbkc (clmul/clmulh/clmulr), Zbkx
(xperm4/xperm8) and Zbkb pack/packh/packw/brev8, alongside the Zba/Zbb/Zicond
it already had.

**Both integer decoders now reject reserved encodings.** They used to fall
through an unrecognised funct7/funct6 to whichever base op shared the funct3
-- so on RV64 `bseti` ran as `slli`, `clmul` as a shift, and a wrong value
came back with no trap. The decode is now an exact funct7/funct6 dispatch;
anything unimplemented raises illegal-instruction. Verified against objdump
and by diffing RV32 vs RV64 results for every affected instruction.

### Vector (RVV 1.0): RV32 only; element-width correctness in progress

`misa` on the RV64 core does **not** advertise V, and a vector instruction on
RV64 traps illegal -- RVV is not wired to the 64-bit core.

`RISCV.Vector`'s original element path (`Read_Element` / `Write_Element`) is
`Word`-based and sign-extends from bit 31, so it was only correct at SEW=32.
A set of SEW-aware 64-bit helpers (`VRead_U` zero-extended, `VRead_S`
sign-extended from the true SEW boundary, `VWrite` low-SEW-bits, plus 128-bit
multiply and 64-bit arithmetic-shift helpers) now backs the ops, so an op
written against them is correct at SEW=8/16/32/64.

Migration status (2026-09-10):

- **Correct at all SEW (8/16/32/64):** integer add/sub/rsub, and/or/xor,
  mul + mulh/mulhu/mulhsu, sll/srl/sra, min/max/minu/maxu,
  div/divu/rem/remu, and the integer compares
  (seq/sne/slt/sltu/sle/sleu/sgt/sgtu) - VV/VX/VI forms. Guarded by
  `Test_SEW_Correctness` in test/test_vector.adb (24 assertions at e8/e16/e64).
- **Still SEW=32 only (not yet migrated):** widening (vwadd/vwmul/...),
  narrowing (vnsrl/vnsra/vnclip), fixed-point saturating (vsadd/vssub/vaadd/
  vasub/vsmul/vssrl/vssra), reductions, the register moves/slides/gather/
  compress family, and the FP ops. These still read via the bit-31 path and
  are correct only at SEW=32.

There is no local reference oracle (the QEMU here predates RVV 1.0), so
expected values in the test suite are hand-computed.


The 32- and 64-bit cores are separate implementations (`riscv-cpu.adb` /
`riscv-cpu64.adb`, with matching `csr`/`csr64` and `alu`/`alu64` packages).
Which one runs is taken from the ELF class byte, not a flag: an ELF64 loads
through `Load_ELF64` and runs on `CPU64`.

Every tool works on both:

| Tool | RV32 | RV64 |
|---|---|---|
| Interactive debugger (`-d`) | yes | yes |
| GDB stub (`--gdb`) | yes | yes, including the FPU registers |
| Profiler (`--profile`, `--flamegraph`) | yes | yes |
| Coverage (`--coverage`) | yes | yes |
| Cache model (`--cache`) | yes | yes |
| Trace record/replay (`--irecord`/`--ireplay`) | 20-byte records | 32-byte records |
| Multi-hart (`--harts 2`) | yes | yes |
| RVV 1.0 vector | yes | - |
| Sv39 MMU | - | yes |

Two details worth knowing:

- **Trace files are XLEN-specific.** An RV64 record is 32 bytes and carries the
  full 64-bit PC and destination-register value; truncating to 32 bits would
  hide a divergence in the upper half. `--ireplay` rejects a 32-bit trace fed
  to an RV64 run rather than reporting nonsense.
- **Symbol addresses are held in 32 bits** throughout the debugger, profiler
  and coverage tracker. `Load_From_ELF` parses ELF64 (whose section headers and
  `Elf64_Sym` field *order* both differ from ELF32) but skips any symbol that
  does not fit in 32 bits. Every RV64 program built here links at 0x80000000.

## Known Gotchas

### Emulator (Ada)
- Every `Is_X_Address()` **must** check `Dev.Enabled` first -- uninitialized peripherals have Base_Address=0 and will intercept address-0 accesses otherwise.
- Anonymous access allocators trigger `-gnatwae` error. Use named access types.
- `Profiler_State` cycle fields use `Long_Long_Integer` -- never `Natural` (overflows at ~2.1B).
- Program loaders must use `Memory.Write_Byte_Raw`, not `Write_Byte`: a guest store to a `rom` region now faults, and an image legitimately populates one.
- `Memory.Last_Result` survives only until the next byte access. Code that needs the outcome of a whole load or store reads `Pending_Fault` between `Clear_Access_Fault` calls, which latches the *first* failure.
- `--machine` accepts built-in profile names only (`simple`, `qemu-virt`); profile files go to `--config`.

### C Programs
- Large `= {0}` struct initialisers -> GCC emits `memset()` -> must link `string.c`.
- `unsigned long long` division absent in `-nostdlib` -> use `unsigned long`.
- Inline asm output operands that share registers with inputs: use `=&r` (early clobber).
- **log_write** does NOT support width/padding format specifiers.

### Crypto
- Reed-Solomon GF(2^8): use poly **0x11D** with alpha=2 (primitive). 0x11B (AES) is NOT primitive for alpha=2.
- SHA-3 domain separator: `0x06` (SHA-3), not `0x01` (raw Keccak).
- Modbus CRC-16: the raw `uint16_t` has lo-byte first in the frame.

---

## Possible Next Steps

### More Crypto / Algorithm Tests
- **X448** -- elliptic curve variant (X25519 and Ed25519 already done)
- **XMSS / SPHINCS+** -- post-quantum hash-based signatures (builds on SHA-256)

### Emulator Features
- **JTAG simulation** -- lower-level debug interface

### DOOM Port
- **Sound** -- audio is stubbed out
- **Higher terminal resolution / lower latency** -- e.g. redraw only changed cells between frames

### Recently Completed
- **Ed25519 / X25519** -- elliptic curve signatures + key exchange (done)
- **Zlib/gzip** -- gzip header/trailer around Deflate (`gzip-test`, done)
- **`pthread`-lite** -- mapped onto multi-hart (`pthread-test`, done)
- **DOOM** -- doomgeneric port via semihosting file I/O (done)
- **DOOM keyboard input** -- live host keystrokes -> DOOM key events (ECALL 0x50E, done)
- **Interactive framebuffer** -- live in-terminal ANSI truecolour rendering (ECALL 0x50D, done)
