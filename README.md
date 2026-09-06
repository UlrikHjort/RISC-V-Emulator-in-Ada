# RISC-V Emulator (RV32IMAFDC + RVV + Zbb/Zba/Zbkc/Zbkx + Zfh + RV32E + A + C + RV64 + PLIC + VirtIO + Multi-hart)

A RISC-V emulator written in Ada. Supports RV32IMAFDC + RVV 1.0 + Zbb/Zbs/Zba + Zbkc/Zbkx + A + C + Zicond + Zfh + **RV32E/RV64E** (16-register subset) plus **RV64IMAFD + Zbb/Zba/A/Zicond** (auto-detected from ELF class). Includes PLIC, VirtIO MMIO block device, Sv39 MMU, multi-hart support, load-use/branch-taken pipeline stall model, L1 cache simulation (miss stalls visible in `mcycle`), and GDB hardware watchpoint stop reply (watch/rwatch/awatch). A semihosting host file-I/O interface (ECALLs 0x505-0x50C) even runs a bare-metal **DOOM** port (doomgeneric). 78 test programs, 2189 assertions - all passing.

## Documentation

### User Guides

- **[TUTORIAL.md](TUTORIAL.md)** - Hands-on walkthrough of every feature, with commands you can run
- **[USER-MANUAL.md](USER-MANUAL.md)** - Reference manual (CLI, profiles, peripherals, debugger)
- **[QUICK_REFERENCE.md](QUICK_REFERENCE.md)** - Quick reference for all commands and workflows
- **[STATUS.md](STATUS.md)** - Feature status, test inventory, CLI flag summary
- **[TESTING.md](TESTING.md)** - Test suite and validation procedures

### Reference Documentation

- **[doc/README.md](doc/README.md)** - Full documentation index
- **[doc/DEBUGGING.md](doc/DEBUGGING.md)** - Complete debugging guide (interactive debugger, breakpoints, watchpoints, backtrace)
- **[doc/PROFILING.md](doc/PROFILING.md)** - Performance profiling and flamegraph visualization
- **[doc/GDB.md](doc/GDB.md)** - GDB Remote Serial Protocol debugging

## Features

### Instruction Set

- **RV32I Base Integer ISA** - all 40 base instructions (arithmetic, loads/stores, branches, jumps, system)
- **M Extension** - MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM, REMU
- **A Extension** - atomic operations: LR.W, SC.W, AMOSWAP.W, AMOADD.W, AMOAND.W, AMOOR.W, AMOXOR.W, AMOMIN.W, AMOMAX.W, AMOMINU.W, AMOMAXU.W
- **F Extension** - single-precision FP (32 registers, arithmetic, min/max, compare, convert, FMA, FMV, FCLASS, FLD/FSD)
- **D Extension** - double-precision FP (same operations as F for 64-bit doubles)
- **C Extension** - 16-bit compressed instructions (RVC 1.0, ~40% code size reduction)
- **V Extension** - RVV 1.0 vector (32 registers, VLEN=128; integer/FP arithmetic, reductions, masks, gather/scatter, strided load/store)
- **Zbb/Zbs/Zba** - bit-manipulation (count leading/trailing zeros, popcount, byte/bit set/clear, address generation)
- **Zbkc/Zbkx** - carry-less multiply (CLMUL, CLMULH, CLMULR) for crypto applications
- **Zicsr** - CSR instructions (CSRRW, CSRRS, CSRRC + immediate variants)
- **Privileged ISA** - M-mode and S-mode, mstatus/mtvec/mepc/mcause/mscratch, mret/sret, ECALL/EBREAK, MISA, MIDELEG/MEDELEG, SBI shim for S-mode programs
- **CSR extensions** - mcountinhibit (0x320), mcounteren (0x306), scounteren (0x106), HPM counter stubs (0xB03-0xB1F)
- **Zfh** - half-precision float (fp16): FADD.H/FSUB.H/FMUL.H/FDIV.H/FSQRT.H, FCVT (h<->s<->d), FMINMAX.H, FCMP.H, FMV.X.H/H.X, FCLASS.H, FLH/FSH; NaN-boxing to fp32 register
- **RV64IMAFD** - full 64-bit ISA: 64-bit ALU, LD/SD/LWU, W-suffix ops (ADDIW/ADDW/SUBW/SLLW etc.), 64-bit AMOs, FCVT.L.D/LU.D/D.L/D.LU, FMV.X.D/D.X, auto-detected from ELF header
- **Multi-hart** - configurable hart count via `--harts N`; each hart gets independent registers/CSRs; hart ID exposed via `mhartid` CSR
- **RV32E** - 16-register embedded subset (`--rv32e`); MISA.E set, MISA.I/V cleared; register-limit enforcement for OP/LOAD/STORE/BRANCH
- **RV64E** - 16-register embedded subset for RV64 (`--rv64e`); MISA.E set, MXL=2, MISA.I/V cleared

### Memory
- Configurable memory maps via hardware profiles
- Region-based memory system (RAM, ROM, Flash)
- Little-endian byte ordering
- Byte, half-word, and word access
- Permission checking (read/write/execute)

### Hardware Profiles
- Built-in profiles: `simple`, `qemu-virt`
- Custom profiles via INI-style configuration files
- Configurable memory regions, peripherals, and CPU settings
- QEMU virt machine compatibility for testing with QEMU-built binaries

### File Loading
- **ELF executables** - Auto-detected, entry point extracted from header
- **Raw binaries** - Load at specified address (default: 0x0)

### Disassembler
- Full RV32IM instruction decoding
- ABI register names (ra, sp, a0-a7, s0-s11, t0-t6)
- Pseudo-instruction recognition (li, mv, ret, j, beqz, bnez, etc.)
- Instruction trace mode

### Debugging & Profiling

**Interactive Debugger:**
- Single-step execution (`s`, `step`)
- Continue until breakpoint (`c`, `continue`)
- Breakpoints by address or function name (`b main`, `b 0x80000100`)
- Watchpoints for memory (read/write) (`watch <addr> [r|w|rw]`)
- Call stack backtrace (`bt`) with symbol names
- Register display: integer (`r`), FP (`fregs`), vector (`vregs`)
- Memory dump (`m <addr> [count]`) and disassembly (`d <addr> [count]`)
- Symbol table support - load from ELF files
- Up to 16 breakpoints + 16 watchpoints

**GDB Remote Debugging:**
- GDB Remote Serial Protocol (RSP) server
- Connect with `riscv32-unknown-elf-gdb` via TCP/IP (port 1234)
- Full GDB commands: breakpoints, watchpoints, memory/register access
- Source-level debugging with debug symbols
- IDE integration (VS Code, Eclipse, CLion)

**Performance Profiling:**
- Per-function profiling (cycles, instructions, call counts)
- Call graph analysis (caller->callee relationships)
- Flamegraph export for visual analysis
- Hotspot identification and optimization guidance
- Compatible with Brendan Gregg's flamegraph.pl

**Enhanced Tracing:**
- Instruction trace with disassembly (`-t`)
- Trace to file (`--trace-file <file>`)
- Filter by PC range (`--trace-range <start> <end>`)
- Memory access logging (`--trace-mem`)
- Register change tracking (`--trace-regs`)
- Symbol-aware output (function names in traces)

### UART Emulation
- 16550-compatible memory-mapped UART at `0x10000000`
- Console output for program printf/putchar
- Register layout:
  - `0x10000000` (THR/RBR): Transmit/Receive data
  - `0x10000005` (LSR): Line status (bit 0=data ready, bit 5=TX empty)
- Enabled by default, use `--no-uart` to disable
- **PTY backend** (`--pty`): connects UART to a pseudo-terminal for use with minicom/screen/picocom

## Building

### Requirements
- GNAT (Ada compiler)
- Make

### Build Commands
```bash
# Clone (include submodule for architecture compliance tests)
git clone --recurse-submodules <repo-url>
# or, after a plain clone:
git submodule update --init

make              # Build emulator
make clean        # Clean build artifacts
make debug        # Build with debug symbols
```

## Usage

```
riscv_emulator [options] <file> [start_address]

Options:
  Execution:
    -d                       Start in interactive debugger
    --max-instructions <n>    Stop after N instructions
    --quiet                  Suppress program output

  GDB & Debugging:
    --gdb [port]             Start GDB remote server (default port: 1234)

  Profiling:
    --profile                Enable per-function profiling
    --flamegraph <file>      Export flamegraph data for visualization

  Tracing:
    -t                       Enable instruction trace
    --trace-file <file>       Redirect trace output to file
    --trace-range <s> <e>     Only trace PC in range [start, end]
    --trace-mem               Log all memory accesses in trace
    --trace-regs              Show register changes in trace

  Hardware:
    --machine <name>         Use hardware profile (simple, qemu-virt)
    --config <file>          Load hardware profile from file
    --list-machines          List available hardware profiles
    --no-uart                Disable UART emulation
    --pty                    Connect UART to a PTY (for minicom/screen)
    --wait                   Wait for PTY connection before starting

  Coverage & Replay:
    --coverage [file]        Record instruction coverage (per-function % with ELF)
    --irecord <file>         Record binary instruction trace (20 bytes/instruction)
    --ireplay <file>         Replay trace and report first mismatch

  General:
    -q, --quiet              Suppress emulator boilerplate (program output only)
    -v                       Verbose output (show loading details)
    -h, --help               Show help

Arguments:
  file          ELF executable or raw binary file
  start_address Starting PC in hex (for raw binary, default: 0)
```

### Examples

**Basic Execution:**
```bash
# Run an ELF executable
./bin/riscv_emulator program.elf

# Run with QEMU virt machine memory map
./bin/riscv_emulator --machine qemu-virt firmware.elf

# Run raw binary at address 0x1000
./bin/riscv_emulator program.bin 1000

# Verbose ELF loading
./bin/riscv_emulator -v program.elf
```

**Interactive Debugging:**
```bash
# Start in interactive debugger
./bin/riscv_emulator -d program.elf

# Then use debugger commands:
(riscv) b main              # Set breakpoint at main
(riscv) c                   # Continue to breakpoint
(riscv) bt                  # Show call stack
(riscv) watch 80100000 w    # Watch for writes
(riscv) r                   # Show registers
(riscv) s                   # Single step
```

**GDB Remote Debugging:**
```bash
# Terminal 1: Start GDB server
./bin/riscv_emulator --gdb program.elf

# Terminal 2: Connect with GDB
riscv32-unknown-elf-gdb program.elf \
    -ex "target remote :1234" \
    -ex "break main" \
    -ex "continue"
```

**Performance Profiling:**
```bash
# Basic profiling
./bin/riscv_emulator --profile --max-instructions 100000 program.elf

# Generate flamegraph
./bin/riscv_emulator --flamegraph data.fg --max-instructions 100000 program.elf
flamegraph.pl data.fg > profile.svg
firefox profile.svg
```

**Advanced Tracing:**
```bash
# Trace with memory and register tracking
./bin/riscv_emulator -t --trace-mem --trace-regs program.elf

# Trace specific PC range to file
./bin/riscv_emulator --trace-file trace.log \
    --trace-range 80000000 80000100 program.elf
```

**PTY Terminal:**
```bash
# Connect UART to PTY for use with minicom
./bin/riscv_emulator --pty --wait program.elf
# Then in another terminal: minicom -D /dev/pts/N
```

**Hardware Profiles:**
```bash
# List available hardware profiles
./bin/riscv_emulator --list-machines

# Run with custom hardware profile
./bin/riscv_emulator --config profiles/embedded.cfg program.elf
```

### Debugger Commands

**Execution:**
| Command | Description |
|---------|-------------|
| `s`, `step` | Execute one instruction |
| `c`, `continue` | Run until breakpoint or halt |
| `x` | Show current instruction |
| `q`, `quit` | Exit debugger |

**Breakpoints:**
| Command | Description |
|---------|-------------|
| `b <addr>` | Set breakpoint at address (hex) |
| `b <function>` | Set breakpoint at function (requires symbols) |
| `bl` | List all breakpoints |
| `bc <n>` | Clear breakpoint number n |
| `bc all` | Clear all breakpoints |

**Watchpoints:**
| Command | Description |
|---------|-------------|
| `watch <addr>` | Watch address for read/write |
| `watch <addr> r` | Watch for reads only |
| `watch <addr> w` | Watch for writes only |
| `wl` | List all watchpoints |
| `wc <n>` | Clear watchpoint number n |
| `wc all` | Clear all watchpoints |

**Inspection:**
| Command | Description |
|---------|-------------|
| `r`, `regs` | Display integer registers |
| `fregs` | Display floating-point registers |
| `freg <n>` | Display specific FP register |
| `vregs` | Display vector registers |
| `m <addr> [n]` | Dump n words of memory (default: 64 bytes) |
| `d <addr> [n]` | Disassemble n instructions (default: 10) |
| `bt`, `backtrace` | Show call stack (requires symbols) |

**Symbols:**
| Command | Description |
|---------|-------------|
| `info functions` | List all functions from symbol table |
| `info f` | (short form) |

**Notes:**
- Addresses can be entered with or without `0x` prefix
- Function names require ELF file with symbol table
- Symbols are automatically loaded from ELF files
- See [doc/DEBUGGING.md](doc/DEBUGGING.md) for complete guide

## Hardware Profiles

Hardware profiles define the memory map, peripherals, and CPU settings for different RISC-V machines.

### Built-in Profiles

| Profile | RAM | Peripherals | Reset Vector |
|---------|-----|-------------|--------------|
| `simple` | 1 MB at 0x0 | UART at 0x10000000 | 0x00000000 |
| `qemu-virt` | 128 MB at 0x80000000, 64 KB ROM at 0x1000 | UART at 0x10000000, CLINT at 0x02000000 | 0x80000000 |

Use `--list-machines` to see detailed information about each profile.

### Custom Profile Configuration

Create custom hardware profiles using INI-style configuration files:

```ini
# Example: embedded microcontroller profile
[profile]
name = embedded

[memory.flash]
base = 0x0
size = 0x20000
type = rom

[memory.ram]
base = 0x20000000
size = 0x8000
type = ram

[peripheral.uart0]
type = uart16550
base = 0x40000000

[cpu]
reset_vector = 0x0
stack_init = 0x20008000
vlen = 128
```

#### Configuration Sections

**[profile]**
- `name` - Profile name

**[memory.NAME]**
- `base` - Base address (hex or decimal)
- `size` - Region size in bytes
- `type` - Memory type: `ram`, `rom`, or `flash`

**[peripheral.NAME]**
- `type` - Peripheral type: `uart16550`, `clint`, `gpio`
- `base` - Base address

**[cpu]**
- `reset_vector` - Initial PC value after reset
- `stack_init` - Initial stack pointer (SP/x2) value
- `vlen` - Vector register length in bits (128, 256, etc.)

See the `profiles/` directory for more examples.

## Test Suite

The emulator includes comprehensive testing infrastructure. See **[TESTING.md](TESTING.md)** for complete guide.

### Automated Tests

Run all 78 automated tests:

```bash
cd programs
./test-all.sh
```

Expected: **2189 PASS, 0 FAIL**.  Use `./test-all.sh --rebuild` to recompile first.

| Group | Programs |
|-------|----------|
| **ISA (RV32)** | branch-test, load-store-test, csr-test, trap-test, m-ext-test, float-classify, zbb-test, zba-test, atomic-test, clmul-test, csr-more-test |
| **ISA (RV64)** | rv64-test, rv64-fp-test, rv64-sha256-test, rv64-wops-test, rv64-zbb64-test, rv64-atomic-test, rv64-zba64-test, rv64-zicond-test, rv64e-test |
| **FP / Vector** | rvv-advanced, rvv-float, rvv-strided, fir-filter |
| **String / C lib** | string-ops, scanf-test |
| **Compression** | lz77, huffman, deflate-test, gzip-test |
| **Crypto** | sha256-test, crc32-test, aes128, chacha20, chacha20-poly1305, aes-gcm, blake2s, sha3, hmac-sha256-test, aes-modes-test |
| **Math / DSP** | fixedpoint-test, fft-test, iir-test, pid-test, lfsr-test, fft-conv |
| **Public-key** | montgomery-test, reed-solomon-test, ntt-test, ecc-test, rs-correct-test, ed25519-test |
| **Coding / DSP** | viterbi, sort-bench, gf256-test |
| **Embedded** | rtos-test, prtos-test, prtos2-test, fat12-test, modbus-test, setjmp-test, smode-test, sv39-test, pthread-test |
| **Pipeline / Timing** | pipeline-test |

### Interactive Tests

Programs requiring terminal interaction (manual testing):
- **echo** - Character echo test
- **forth** - Forth interpreter

Test with PTY connection:
```bash
cd programs
make run-echo
# In another terminal: minicom -D /dev/pts/X
```

### Cross-Compiler Requirements

Tests require `riscv32-unknown-elf-gcc` toolchain:
```bash
sudo apt install gcc-riscv64-unknown-elf
```


## Roadmap

### Completed 

**Core ISA & Extensions:**
- [x] RV32I base integer ISA (all 40 instructions)
- [x] M extension (multiply/divide)
- [x] F extension (single-precision float)
- [x] D extension (double-precision float)
- [x] V extension (vector, RVV 1.0)
- [x] Compressed (C) extension support

**Peripherals:**
- [x] UART emulation (16550-compatible)
- [x] UART PTY backend (minicom/screen/picocom support)
- [x] CLINT timer peripheral (mtime/mtimecmp)
- [x] PLIC (Platform-Level Interrupt Controller) - 32 sources, M/S-mode contexts
- [x] GPIO peripheral with interrupts
- [x] SPI peripheral emulation + 64KB in-memory flash
- [x] I2C peripheral emulation
- [x] Timer peripheral
- [x] DMA controller (4 channels)
- [x] VirtIO MMIO block device v2 (1024 sectors, virtqueue, PLIC interrupt)

**System & Configuration:**
- [x] Hardware profiles (configurable memory maps)
- [x] ELF loader with segment processing and symbol tables
- [x] Bare-metal C runtime (crt0, malloc, printf)
- [x] Multiple machine profiles (simple, qemu-virt, embedded)

**Debugging & Development:**
- [x] Interactive debugger with breakpoints and watchpoints
- [x] Symbol table support (function names, addresses)
- [x] Call stack backtrace with symbols
- [x] GDB Remote Serial Protocol (RSP) server
- [x] Performance profiling (per-function, call graphs)
- [x] Flamegraph export for visual analysis
- [x] Enhanced instruction tracing (memory, registers, PC filtering)
- [x] Comprehensive test suite (78 test programs, 2189 assertions)

**Debugging & Development (continued):**
- [x] Virtual memory / MMU (Sv39) - 3-level page table, 64-entry TLB, page faults
- [x] GDB RSP stub for RV64 - full register/memory/breakpoint/watchpoint support
- [x] L1 instruction + data cache simulation (`--cache`/`--icache`/`--dcache`; miss stalls in `mcycle`)
- [x] Cycle-accurate timing model - load-use (+1 cycle) and branch-taken (+1 cycle) pipeline stalls
- [x] Ed25519 digital signatures (RFC 8032) - sign/verify test (11 assertions)
- [x] GDB hardware watchpoints with correct T05 watch/rwatch/awatch stop reply
- [x] Pipeline hazard model: load-use and branch-taken stall counts visible via `mcycle`/`rdcycle`

**Runtime & Applications:**
- [x] Semihosting host file I/O (ECALLs 0x505-0x50C): open/read/write/close/seek/tell/size
- [x] DOOM port (doomgeneric) - boots shareware IWAD, renders the attract demo to PPM frames
- [x] gzip compress/decompress (RFC 1952) - `gzip-test` (8 assertions)
- [x] X25519 key exchange + Ed25519 signatures (RFC 8032)
- [x] pthread-lite over multi-hart - create/join/mutex/trylock (`pthread-test`)

### Planned 

**Advanced Features:**
- [ ] VirtIO net device (TAP/TUN)
- [ ] JTAG simulation (lower-level debug interface)
- [ ] DOOM: keyboard input + sound (currently attract-demo, video-only)

**Optimizations:**
- [ ] JIT compilation for faster execution

## License

The emulator and its test programs are **MIT** licensed - see [LICENSE](LICENSE).

The vendored DOOM engine under `programs/doom/` is **GPLv2** (id Software /
Chocolate DOOM / doomgeneric) - see [programs/doom/README.md](programs/doom/README.md)
and `programs/doom/COPYING`. The emulator does not link against it: DOOM is
cross-compiled to a RISC-V ELF and executed as guest data.

No DOOM game data (IWAD) is distributed here. `make -C programs doom-wad`
downloads the freely redistributable shareware `doom1.wad` at build time.

## A Note on AI Assistance

This has been a long-running hobby project, and it showed. Features were added
over a long stretch of time, and the surrounding material did not keep up: the
documentation had drifted out of sync with the code, several guides described a
build and test workflow that no longer existed, and a fair amount of
development-process clutter had accumulated in the repository.

I decided to use an LLM to clean it up - Anthropic's **Claude Opus 5**, run
through Claude Code. It was used to review the code and to audit the
documentation: retiring superseded documents, repairing broken links, correcting
command-line examples that no longer worked, and bringing test counts and file
paths back in line with what the code actually does. It also helped prepare the
repository for publication, including the licensing split between the
MIT-licensed emulator and the GPLv2 DOOM engine described above.

The design decisions, the architecture, and the direction of the project remain
my own.
