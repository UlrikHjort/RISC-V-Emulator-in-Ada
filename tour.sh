#!/usr/bin/env bash
# tour.sh — Interactive feature tour of the RISC-V emulator
# Run from the repo root:  bash tour.sh
#
# By Ulrik Hørlyk Hjort 2026

set -euo pipefail
cd "$(dirname "$0")"

EMU="bin/riscv_emulator"
PROG="programs/out/bin"
ELF="programs/out/elf"
LOGS="programs/logs"

# -- Colours ----------------------------------------------------------------
C_RESET='\033[0m'
C_BOLD='\033[1m'
C_DIM='\033[2m'
C_CYAN='\033[1;36m'
C_YELLOW='\033[1;33m'
C_GREEN='\033[1;32m'
C_BLUE='\033[1;34m'
C_MAGENTA='\033[1;35m'
C_WHITE='\033[1;37m'
C_RED='\033[1;31m'

# -- Helpers -----------------------------------------------------------------

# Print a top-level section banner
section() {
    local num="$1" title="$2"
    echo
    echo -e "${C_CYAN}${C_BOLD}------------------------------------------------------------${C_RESET}"
    echo -e "${C_CYAN}${C_BOLD}  $num  $title${C_RESET}"
    echo -e "${C_CYAN}${C_BOLD}------------------------------------------------------------${C_RESET}"
    echo
}

# Print a sub-section heading
sub() {
    echo -e "\n${C_MAGENTA}${C_BOLD}▸ $*${C_RESET}"
}

# Print explanatory text
info() {
    echo -e "${C_DIM}$*${C_RESET}"
}

# Show a command in yellow, then run it; optionally pipe through head -N
run_cmd() {
    local head_n=0
    if [[ "$1" == "--head" ]]; then head_n="$2"; shift 2; fi
    echo -e "\n${C_YELLOW}  \$${C_RESET} ${C_WHITE}$*${C_RESET}"
    echo
    if [[ $head_n -gt 0 ]]; then
        eval "$*" 2>&1 | head -"$head_n" || true
    else
        eval "$*" 2>&1 || true
    fi
}

# Wait for the user
pause() {
    echo
    echo -e "${C_GREEN}${C_BOLD}  Press Enter to continue…${C_RESET}"
    read -r _
}

skip_if_missing() {
    local f="$1"
    if [[ ! -f "$f" ]]; then
        echo -e "${C_RED}  (skipping — $f not found, run 'cd programs && make all' first)${C_RESET}"
        return 1
    fi
    return 0
}

# ----------------------------------------------------------------------------
# WELCOME
# ----------------------------------------------------------------------------
clear
echo -e "${C_CYAN}${C_BOLD}"
cat <<'ART'
  ██████╗ ██╗███████╗ ██████╗      ██╗   ██╗
  ██╔══██╗██║██╔════╝██╔════╝      ██║   ██║
  ██████╔╝██║███████╗██║     █████╗██║   ██║
  ██╔══██╗██║╚════██║██║     ╚════╝╚██╗ ██╔╝
  ██║  ██║██║███████║╚██████╗       ╚████╔╝
  ╚═╝  ╚═╝╚═╝╚══════╝ ╚═════╝        ╚═══╝
ART
echo -e "${C_RESET}"
echo -e "${C_WHITE}${C_BOLD}  RISC-V Emulator — Interactive Feature Tour${C_RESET}"
echo -e "${C_DIM}  RV32IMAFDC + RVV + Zbb/Zba/Zbkc/Zbkx + A + RV64 + Sv39 + VirtIO + Ed25519${C_RESET}"
echo
echo -e "  This tour runs real commands against real binaries."
echo -e "  You can follow along in another terminal."
echo -e "  Run from the repository root:  ${C_YELLOW}bash tour.sh${C_RESET}"
pause

# ----------------------------------------------------------------------------
# 1. RUNNING A PROGRAM
# ----------------------------------------------------------------------------
section "1/13" "Running a Program"

info "  The emulator loads a flat binary or ELF and runs it bare-metal."
info "  --machine qemu-virt places RAM at 0x80000000 (128 MB) with UART, PLIC, etc."
info "  -q suppresses the UART PTY message; results appear in a log file."
info "  --log-dir tells the emulator where to put that log (default: current dir)."

sub "SHA-256 test — 6 NIST test vectors"
skip_if_missing "$PROG/sha256-test.bin" && \
run_cmd $EMU --machine qemu-virt --log-dir $LOGS -q $PROG/sha256-test.bin 80000000
run_cmd cat $LOGS/sha256-test.log

pause

# ----------------------------------------------------------------------------
# 2. INSTRUCTION TRACE
# ----------------------------------------------------------------------------
section "2/13" "Instruction Trace  (-t)"

info "  -t enables instruction tracing; each executed instruction is printed."
info "  --max-instructions N halts after N steps — use it to limit the output."
info "  Output: PC  encoding  disassembly  register-result"

sub "First 25 instructions of branch-test"
skip_if_missing "$PROG/branch-test.bin" && \
run_cmd --head 30 $EMU --machine qemu-virt --log-dir $LOGS -q -t --max-instructions 25 $PROG/branch-test.bin 80000000

pause

# ----------------------------------------------------------------------------
# 3. INTERACTIVE DEBUGGER
# ----------------------------------------------------------------------------
section "3/13" "Interactive Debugger  (-d)"

info "  -d starts the built-in debugger (normally fully interactive)."
info "  Here we pipe a scripted session to show what it looks like."
info "  Commands: regs, d (disassemble), b (breakpoint), s (step), c (continue), q (quit)"

sub "Scripted debug session on sha256-test"
skip_if_missing "$PROG/sha256-test.bin" && {
    echo -e "${C_YELLOW}  \$${C_RESET} ${C_WHITE}echo 'regs\\nd 0x80000000 8\\nb main\\nc\\nregs\\nq' | $EMU --machine qemu-virt --log-dir $LOGS -d $PROG/sha256-test.bin 80000000${C_RESET}"
    echo
    printf 'regs\nd 0x80000000 8\nb main\nc\nregs\nq\n' \
        | $EMU --machine qemu-virt --log-dir $LOGS -d "$PROG/sha256-test.bin" 80000000 2>&1 | head -60 || true
}

pause

# ----------------------------------------------------------------------------
# 4. PROFILER
# ----------------------------------------------------------------------------
section "4/13" "Instruction Profiler  (--profile)"

info "  --profile records per-function cycle counts, call counts, and opcode histograms."
info "  --flamegraph <file> writes a folded-stack file for flamegraph.pl."

sub "Profile sha256-test (top functions + opcode histogram excerpt)"
skip_if_missing "$PROG/sha256-test.bin" && \
run_cmd --head 50 $EMU --machine qemu-virt --log-dir $LOGS -q --profile $PROG/sha256-test.bin 80000000

pause

# ----------------------------------------------------------------------------
# 5. COVERAGE
# ----------------------------------------------------------------------------
section "5/13" "Instruction Coverage  (--coverage)"

info "  --coverage tracks which PCs were executed."
info "  With an ELF, it reports per-function coverage percentages."

sub "Coverage report for sha256-test (ELF, RV32)"
skip_if_missing "$ELF/sha256-test.elf" && \
run_cmd --head 30 $EMU --machine qemu-virt --log-dir $LOGS -q --coverage $ELF/sha256-test.elf

pause

# ----------------------------------------------------------------------------
# 6. BINARY TRACE / REPLAY
# ----------------------------------------------------------------------------
section "6/13" "Binary Trace & Replay  (--irecord / --ireplay)"

info "  --irecord <file>  records every instruction (PC, encoding, Rd, value, nextPC)."
info "  --ireplay <file>  re-runs the binary and checks each step matches the trace."
info "  Useful for determinism checks and bisecting non-deterministic bugs."

sub "Record a trace of branch-test, then replay and verify"
skip_if_missing "$PROG/branch-test.bin" && {
    run_cmd $EMU --machine qemu-virt --log-dir $LOGS -q --irecord /tmp/branch.trace $PROG/branch-test.bin 80000000
    run_cmd $EMU --machine qemu-virt --log-dir $LOGS -q --ireplay  /tmp/branch.trace $PROG/branch-test.bin 80000000
    rm -f /tmp/branch.trace
}

pause

# ----------------------------------------------------------------------------
# 7. VECTOR EXTENSION (RVV 1.0)
# ----------------------------------------------------------------------------
section "7/13" "Vector Extension — RVV 1.0"

info "  VLEN=128 (4 × f32 or 2 × f64 per register)."
info "  Supports integer and FP vector arithmetic, reductions, masks, gather/scatter."

sub "RVV advanced test — strided loads, masked ops, gather, FP reductions"
skip_if_missing "$PROG/rvv-advanced.bin" && {
    run_cmd $EMU --machine qemu-virt --log-dir $LOGS -q $PROG/rvv-advanced.bin 80000000
    run_cmd cat $LOGS/rvv-advanced.log
}

pause

# ----------------------------------------------------------------------------
# 8. CRYPTO SUITE
# ----------------------------------------------------------------------------
section "8/13" "Crypto Suite"

sub "ChaCha20-Poly1305 (RFC 8439 AEAD)"
skip_if_missing "$PROG/chacha20-poly1305.bin" && {
    run_cmd $EMU --machine qemu-virt --log-dir $LOGS -q $PROG/chacha20-poly1305.bin 80000000
    run_cmd cat $LOGS/chacha20-poly1305.log
}

sub "AES-GCM (NIST 128-bit authenticated encryption)"
skip_if_missing "$PROG/aes-gcm.bin" && {
    run_cmd $EMU --machine qemu-virt --log-dir $LOGS -q $PROG/aes-gcm.bin 80000000
    run_cmd cat $LOGS/aes-gcm.log
}

sub "X25519 — Curve25519 Diffie-Hellman (RFC 7748)"
skip_if_missing "$PROG/x25519-test.bin" && {
    run_cmd $EMU --machine qemu-virt --log-dir $LOGS -q $PROG/x25519-test.bin 80000000
    run_cmd cat $LOGS/x25519-test.log
}

sub "Ed25519 — digital signatures (RFC 8032)"
skip_if_missing "$PROG/ed25519-test.bin" && {
    run_cmd $EMU --machine qemu-virt --log-dir $LOGS -q $PROG/ed25519-test.bin 80000000
    run_cmd cat $LOGS/ed25519-test.log
}

pause

# ----------------------------------------------------------------------------
# 9. PIPELINE TIMING MODEL
# ----------------------------------------------------------------------------
section "9/13" "Pipeline Timing Model"

info "  The emulator models a 5-stage in-order pipeline."
info "  Extra stall cycles: MUL(+2), DIV(+32), FP(+3/+19), CSR(+1)."
info "  Load-use hazard: +1 cycle when next instruction reads a just-loaded register."
info "  Branch/jump taken: +1 cycle for pipeline refill."
info "  --profile shows a stall breakdown by category."

sub "Pipeline stall test — load-use + branch-taken penalties"
skip_if_missing "$PROG/pipeline-test.bin" && {
    run_cmd $EMU --machine qemu-virt --log-dir $LOGS -q $PROG/pipeline-test.bin 80000000
    run_cmd cat $LOGS/pipeline-test.log
}

sub "Profiler stall breakdown — sha256-test"
skip_if_missing "$PROG/sha256-test.bin" && \
run_cmd --head 35 $EMU --machine qemu-virt --log-dir $LOGS -q --profile $PROG/sha256-test.bin 80000000

pause

# ----------------------------------------------------------------------------
# 10. RV64 SUPPORT
# ----------------------------------------------------------------------------
section "10/13" "RV64 — 64-bit RISC-V"

info "  The emulator auto-detects ELF class (32/64) from the ELF header."
info "  RV64 programs run with a separate 64-bit CPU core (RISCV.CPU64)."
info "  Supports RV64IMAFD + Zbb/Zba/A + Zicond + Sv39 virtual memory."

sub "RV64 SHA-256 — same algorithm, 64-bit registers"
skip_if_missing "$ELF/rv64-sha256-test.elf" && {
    run_cmd $EMU --machine qemu-virt --log-dir $LOGS -q $ELF/rv64-sha256-test.elf
    run_cmd cat $LOGS/rv64-sha256-test.log
}

sub "RV64 W-suffix ops — ADDIW, ADDW, SUBW, SLLW, SRLW, SRAW (38 assertions)"
skip_if_missing "$ELF/rv64-wops-test.elf" && {
    run_cmd $EMU --machine qemu-virt --log-dir $LOGS -q $ELF/rv64-wops-test.elf
    run_cmd --head 5 cat $LOGS/rv64-wops-test.log
    echo -e "${C_DIM}  … (38 total)${C_RESET}"
}

sub "Sv39 virtual memory — 3-level page table, TLB, page faults"
skip_if_missing "$ELF/sv39-test.elf" && {
    run_cmd $EMU --machine qemu-virt --log-dir $LOGS -q $ELF/sv39-test.elf
    run_cmd --head 12 cat $LOGS/sv39-test.log
}

pause

# ----------------------------------------------------------------------------
# 11. PRIVILEGE MODES
# ----------------------------------------------------------------------------
section "11/13" "Privilege Modes — M / S / U"

info "  The emulator implements M-mode, S-mode, and U-mode."
info "  crt0-smode.S sets up medeleg/mideleg and MRETs into S-mode."
info "  SBI shim handles S-mode ECALLs (set_timer, putchar, shutdown, …)."

sub "S-mode test — CSRs, stvec, sepc, scause, delegation"
skip_if_missing "$PROG/smode-test.bin" && {
    run_cmd $EMU --machine qemu-virt --log-dir $LOGS -q $PROG/smode-test.bin 80000000
    run_cmd cat $LOGS/smode-test.log
}

sub "U-mode test — M→S→U transition, ecall delegation, illegal CSR trap"
skip_if_missing "$PROG/umode-test.bin" && {
    run_cmd $EMU --machine qemu-virt --log-dir $LOGS -q $PROG/umode-test.bin 80000000
    run_cmd cat $LOGS/umode-test.log
}

pause

# ----------------------------------------------------------------------------
# 12. VIRTIO BLOCK DEVICE
# ----------------------------------------------------------------------------
section "12/13" "VirtIO Block Device"

info "  VirtIO MMIO v2 block device at 0x10001000."
info "  512KB disk (1024 × 512-byte sectors).  PLIC source 8 drives interrupts."
info "  Driver negotiates features, builds 3-descriptor virtqueues, reads/writes sectors."

skip_if_missing "$PROG/virtio-blk-test.bin" && {
    run_cmd $EMU --machine qemu-virt --log-dir $LOGS -q $PROG/virtio-blk-test.bin 80000000
    run_cmd cat $LOGS/virtio-blk-test.log
}

pause

# ----------------------------------------------------------------------------
# 13. FULL TEST SUITE
# ----------------------------------------------------------------------------
section "13/13" "Full Test Suite"

info "  76 test programs covering ISA, FPU, RVV, crypto, DSP, RTOS, filesystems,"
info "  Modbus, privilege modes, VirtIO, RV64, Sv39 virtual memory, and more."
info "  Expected: 2192 PASS, 0 FAIL."
echo
echo -e "${C_YELLOW}  \$${C_RESET} ${C_WHITE}cd programs && bash test-all.sh${C_RESET}"
echo
echo -e "  ${C_DIM}(This takes ~30–60 s.  Run it yourself to see the full table.)${C_RESET}"

pause

# ----------------------------------------------------------------------------
# WHAT'S NEXT
# ----------------------------------------------------------------------------
clear
echo
echo -e "${C_CYAN}${C_BOLD}------------------------------------------------------------${C_RESET}"
echo -e "${C_CYAN}${C_BOLD}  Things to explore on your own${C_RESET}"
echo -e "${C_CYAN}${C_BOLD}------------------------------------------------------------${C_RESET}"
echo
echo -e "${C_WHITE}${C_BOLD}  GDB remote debugging${C_RESET}"
echo -e "  ${C_YELLOW}bin/riscv_emulator --machine qemu-virt --gdb 1234 programs/out/bin/sha256-test.bin 80000000${C_RESET}"
echo -e "  ${C_YELLOW}riscv32-unknown-elf-gdb programs/out/elf/sha256-test.elf${C_RESET}  (then: target remote :1234)"
echo
echo -e "${C_WHITE}${C_BOLD}  Flamegraph profiling${C_RESET}"
echo -e "  ${C_YELLOW}bin/riscv_emulator --machine qemu-virt -q --profile --flamegraph /tmp/fg.txt \\${C_RESET}"
echo -e "  ${C_YELLOW}    programs/out/bin/sha256-test.bin 80000000${C_RESET}"
echo -e "  ${C_YELLOW}flamegraph.pl /tmp/fg.txt > /tmp/fg.svg && xdg-open /tmp/fg.svg${C_RESET}"
echo
echo -e "${C_WHITE}${C_BOLD}  Custom hardware profile${C_RESET}"
echo -e "  ${C_YELLOW}bin/riscv_emulator --machine my-board.ini myprogram.bin 0x0${C_RESET}"
echo
echo -e "${C_WHITE}${C_BOLD}  Write your own test${C_RESET}"
echo -e "  See ${C_YELLOW}TUTORIAL.md § 14${C_RESET} for the C skeleton and Makefile pattern."
echo
echo -e "${C_WHITE}${C_BOLD}  RISC-V architecture compliance tests${C_RESET}"
echo -e "  See ${C_YELLOW}TUTORIAL.md § 13${C_RESET} — uses the official riscv-arch-test suite."
echo
echo -e "${C_GREEN}${C_BOLD}  Tour complete.${C_RESET}"
echo
