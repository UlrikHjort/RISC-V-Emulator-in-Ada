# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/), and the project aims to follow
[Semantic Versioning](https://semver.org/): MAJOR.MINOR.PATCH.

The running version is reported by `riscv_emulator --version` and defined in
`src/riscv-version.ads`.

## [Unreleased]

Nothing yet.

## [1.0.0] - 2026-09-16

First tagged release. The emulator is a RISC-V ISA simulator written in Ada,
built with full runtime checking (`-gnata -gnatVa -gnatwae`), for embedded
software testing and development.

### Instruction set
- **RV32** core: RV32IMAFDC + RVV 1.0 + Zicsr + Zicond + Zfh, and the
  bit-manipulation / scalar-crypto sets Zba/Zbb/Zbs, Zbkb/Zbkc/Zbkx and the
  Zkn*/Zks* families.
- **RV64** core: RV64IMAFDC + Zba/Zbb/Zbs/Zbc + Zbkb/Zbkc/Zbkx + Zicond. The
  core is selected automatically from the ELF class byte.
- Both integer decoders reject reserved `funct7`/`funct6` encodings with an
  illegal-instruction trap instead of aliasing them to a base operation.
- RV32E / RV64E 16-register subsets (`--rv32e` / `--rv64e`).

### Privilege, memory and peripherals
- M / S / U privilege modes, Sv39 MMU (RV64), PLIC, CLINT, SBI shim,
  multi-hart (`--harts N`) on both cores.
- Peripherals: 16550 UART (PTY-backed), GPIO, SPI + flash, I2C, timer,
  watchdog, DMA, VirtIO MMIO block.
- Access faults: an unmapped fetch/load/store, or a store to a read-only
  region, traps (`mcause` 1/5/7) rather than silently succeeding;
  `--no-access-faults` restores the older permissive behaviour.
- Misaligned data accesses are emulated; only AMOs require natural alignment.

### Tooling
- Interactive debugger (`-d`) and a GDB remote stub (`--gdb`), including FP
  registers and hardware watchpoints - both on RV32 and RV64.
- Instruction profiler with a load-use/branch/mul-div stall model and
  flamegraph export, L1 I+D cache simulation (`--cache`), instruction coverage
  (`--coverage`), and binary trace record/replay (`--irecord`/`--ireplay`).
- Semihosting host file I/O, confined to a root directory and gated by
  `--host-io off|ro|rw`.
- Hardware profiles: built-in `simple` and `qemu-virt`, plus `--config`
  profile files resolved by path or by name from a search path.

### Installation and configuration
- `make install` / `make uninstall` (honour `PREFIX`, `BINDIR`, `DATADIR`,
  `DESTDIR`); installs the binary, example profiles and `riscv_emulatorrc.example`.
- `--config <name>` resolves a bare profile name via a search path, so an
  installed emulator finds its shipped profiles automatically.
- rc file (`~/.riscv_emulatorrc`, `~/.config/riscv_emulator/config`, or
  `$RISCV_EMULATORRC`) sets defaults for `machine`, `config`, `host-io`,
  `host-io-root` and `log-dir`; command-line flags override them.
- `--version` / `-V`.

### Tests
- 83 bare-metal test programs (2263 assertions), 850+ Ada unit-test assertions,
  the official riscv-tests (284/293; the remainder are deep M/S-mode CSR
  features), and riscv-arch-test suites (`arch-test/run_arch_tests.sh`, with an
  `all` combined run). A bare-metal DOOM port runs from a fresh clone.
- Task-oriented walkthroughs under `tutorials/`.

### Known limitations
- The vector unit's element datapath is correct for the core integer
  operations (arithmetic, logical, shift, min/max, multiply, divide, compare)
  at SEW=8/16/32/64, but the widening, narrowing, fixed-point, reduction and
  floating-point vector families are correct only at SEW=32. RVV is RV32 only;
  the RV64 core does not decode vector instructions. See `STATUS.md`.
- 9 riscv-tests and 5 privilege arch-tests deviate by design or exercise
  unimplemented deep CSR features; see `STATUS.md`.

