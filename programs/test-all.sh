#!/usr/bin/env bash
# Run every log-based test program and print a PASS/FAIL summary table.
# By Ulrik Hørlyk Hjort 2026
#
# Usage:  cd programs && ./test-all.sh [--rebuild]
#   --rebuild  : force-rebuild all test binaries before running
#   (default)  : run existing binaries, rebuild only if missing

set -euo pipefail
cd "$(dirname "$0")"

REBUILD=0
[[ "${1:-}" == "--rebuild" ]] && REBUILD=1

EMULATOR="../bin/riscv_emulator"
LOG_DIR="logs"
mkdir -p "$LOG_DIR"
PASS_TOTAL=0
FAIL_TOTAL=0
ERROR_COUNT=0
RESULTS=()

# -----------------------------------------------------------------------
# List of (test-name  make-target  log-file) tuples.
# Only tests that write a log file via log_init() are listed here.
# printf-float-test is excluded (UART-only, no log file).
# -----------------------------------------------------------------------
TESTS=(
    "branch-test       branch-test       branch-test.log"
    "load-store-test   load-store-test   load-store-test.log"
    "csr-test          csr-test          csr-test.log"
    "trap-test         trap-test         trap-test.log"
    "fp-math-test      fp-math-test      fp-math-test.log"
    "m-ext-test        m-ext-test        m-ext-test.log"
    "lz77              lz77              lz77.log"
    "string-ops        string-ops        string-ops.log"
    "rvv-advanced      rvv-advanced      rvv-advanced.log"
    "rvv-float         rvv-float         rvv-float.log"
    "rvv-strided       rvv-strided       rvv-strided.log"
    "float-classify    float-classify    float-classify.log"
    "crc32-test        crc32-test        crc32-test.log"
    "sha256-test       sha256-test       sha256-test.log"
    "aes128            aes128            aes128.log"
    "base64            base64            base64.log"
    "huffman           huffman           huffman.log"
    "sort-bench        sort-bench        sort-bench.log"
    "fir-filter        fir-filter        fir-filter.log"
    "zbb-test          zbb-test          zbb-test.log"
    "zba-test          zba-test          zba-test.log"
    "fixedpoint-test   fixedpoint-test   fixedpoint-test.log"
    "atomic-test       atomic-test       atomic-test.log"
    "clmul-test        clmul-test        clmul-test.log"
    "gf256-test        gf256-test        gf256-test.log"
    "pid-test          pid-test          pid-test.log"
    "lfsr-test         lfsr-test         lfsr-test.log"
    "iir-test          iir-test          iir-test.log"
    "fft-test          fft-test          fft-test.log"
    "montgomery-test   montgomery-test   montgomery-test.log"
    "reed-solomon-test reed-solomon-test reed-solomon-test.log"
    "ntt-test          ntt-test          ntt-test.log"
    "ecc-test          ecc-test          ecc-test.log"
    "rs-correct-test   rs-correct-test   rs-correct-test.log"
    "chacha20          chacha20          chacha20.log"
    "chacha20-poly1305 chacha20-poly1305 chacha20-poly1305.log"
    "aes-gcm           aes-gcm           aes-gcm.log"
    "blake2s           blake2s           blake2s.log"
    "sha3              sha3              sha3.log"
    "viterbi           viterbi           viterbi.log"
    "fft-conv          fft-conv          fft-conv.log"
    "scanf-test        scanf-test        scanf-test.log"
    "rtos-test         rtos-test         rtos-test.log"
    "fat12-test        fat12-test        fat12-test.log"
    "modbus-test       modbus-test       modbus-test.log"
    "deflate-test      deflate-test      deflate-test.log"
    "setjmp-test       setjmp-test       setjmp-test.log"
    "smode-test        smode-test        smode-test.log"
    "umode-test        umode-test        umode-test.log"
    "hmac-sha256-test  hmac-sha256-test  hmac-sha256-test.log"
    "aes-modes-test    aes-modes-test    aes-modes-test.log"
    "csr-more-test     csr-more-test     csr-more-test.log"
    "plic-test         plic-test         plic-test.log"
    "rv64-test         rv64-test         rv64-test.log         elf"
    "rv64-fp-test      rv64-fp-test      rv64-fp-test.log      elf"
    "rv64-sha256-test  rv64-sha256-test  rv64-sha256-test.log  elf"
    "rv64-wops-test    rv64-wops-test    rv64-wops-test.log    elf"
    "rv64-zbb64-test   rv64-zbb64-test   rv64-zbb64-test.log   elf"
    "rv64-atomic-test  rv64-atomic-test  rv64-atomic-test.log  elf"
    "rv64-zba64-test   rv64-zba64-test   rv64-zba64-test.log   elf"
    "rv64-zicond-test  rv64-zicond-test  rv64-zicond-test.log  elf"
    "rv64-zbs64-test   rv64-zbs64-test   rv64-zbs64-test.log   elf"
    "rv64-zbc64-test   rv64-zbc64-test   rv64-zbc64-test.log   elf"
    "rv64-zbkx64-test  rv64-zbkx64-test  rv64-zbkx64-test.log  elf"
    "rv64-zbkb64-test  rv64-zbkb64-test  rv64-zbkb64-test.log  elf"
    "rv64-reserved-test rv64-reserved-test rv64-reserved-test.log elf"
    "prtos-test        prtos-test        prtos-test.log"
    "prtos2-test       prtos2-test       prtos2-test.log"
    "virtio-blk-test   virtio-blk-test   virtio-blk-test.log"
    "sv39-test         sv39-test         sv39-test.log         elf"
    "p256-ecdsa-test   p256-ecdsa-test   p256-ecdsa-test.log"
    "x25519-test       x25519-test       x25519-test.log"
    "timing-test       timing-test       timing-test.log"
    "zfh-test          zfh-test          zfh-test.log"
    "multihart-test    multihart-test    multihart-test.log  harts2"
    "pthread-test      pthread-test      pthread-test.log    harts2"
    "rv32e-test        rv32e-test        rv32e-test.log      rv32e"
    "rv64e-test        rv64e-test        rv64e-test.log      rv64e"
    "time-test         time-test         time-test.log       elf"
    "coremark-test     coremark-test     coremark-test.log"
    "gzip-test         gzip-test         gzip-test.log         elf"
    "ed25519-test      ed25519-test      ed25519-test.log"
    "pipeline-test     pipeline-test     pipeline-test.log"
)

# -----------------------------------------------------------------------
# Header
# -----------------------------------------------------------------------
printf "\n%-26s %6s %6s %s\n" "TEST" "PASS" "FAIL" "STATUS"
printf "%-26s %6s %6s %s\n"   "----" "----" "----" "------"

for entry in "${TESTS[@]}"; do
    read -r name target logfile format <<< "$entry"
    format="${format:-bin}"

    # Optionally rebuild
    if [[ $REBUILD -eq 1 ]]; then
        make -s "$target" 2>/dev/null || true
    else
        make -s "$target" 2>/dev/null || true   # build if missing
    fi

    # Run test (quiet: only log output, no UART/PTY)
    rm -f "$LOG_DIR/$logfile"
    if [[ "$format" == "elf" ]]; then
        $EMULATOR --machine qemu-virt --log-dir "$LOG_DIR" -q "out/elf/${target}.elf" \
            2>/dev/null || true
    elif [[ "$format" == "harts2" ]]; then
        $EMULATOR --machine qemu-virt --log-dir "$LOG_DIR" --harts 2 -q "out/bin/${target}.bin" 80000000 \
            2>/dev/null || true
    elif [[ "$format" == "rv32e" ]]; then
        $EMULATOR --machine qemu-virt --log-dir "$LOG_DIR" --rv32e -q "out/elf/${target}.elf" \
            2>/dev/null || true
    elif [[ "$format" == "rv64e" ]]; then
        $EMULATOR --machine qemu-virt --log-dir "$LOG_DIR" --rv64e -q "out/elf/${target}.elf" \
            2>/dev/null || true
    else
        $EMULATOR --machine qemu-virt --log-dir "$LOG_DIR" -q "out/bin/${target}.bin" 80000000 \
            2>/dev/null || true
    fi

    if [[ ! -f "$LOG_DIR/$logfile" ]]; then
        printf "%-26s %6s %6s %s\n" "$name" "-" "-" "NO LOG"
        RESULTS+=("$name NO_LOG 0 0")
        ((ERROR_COUNT++)) || true
        continue
    fi

    # Parse pass/fail counts — two formats are used across the test suite:
    #   Format A (newer):  "65 PASS  0 FAIL"
    #   Format B (older):  "  PASS: 56" / "  FAIL: 0"
    pass=$(grep -oP '\d+(?= PASS)' "$LOG_DIR/$logfile" | tail -1 \
        || grep -oP '(?<=PASS: )\d+' "$LOG_DIR/$logfile" | tail -1 \
        || echo "")
    fail=$(grep -oP '\d+(?= FAIL)' "$LOG_DIR/$logfile" | tail -1 \
        || grep -oP '(?<=FAIL: )\d+' "$LOG_DIR/$logfile" | tail -1 \
        || echo "")

    if [[ -z "$pass" || -z "$fail" ]]; then
        printf "%-26s %6s %6s %s\n" "$name" "-" "-" "NO RESULT LINE"
        RESULTS+=("$name BAD 0 0")
        ((ERROR_COUNT++)) || true
        continue
    fi

    status="OK"
    [[ "$fail" -gt 0 ]] && status="FAIL"
    printf "%-26s %6d %6d %s\n" "$name" "$pass" "$fail" "$status"
    RESULTS+=("$name $status $pass $fail")
    ((PASS_TOTAL += pass)) || true
    ((FAIL_TOTAL += fail)) || true
done

# -----------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------
printf "\n%-26s %6s %6s\n" "---" "----" "----"
printf "%-26s %6d %6d\n"   "TOTAL" "$PASS_TOTAL" "$FAIL_TOTAL"

if [[ $ERROR_COUNT -gt 0 ]]; then
    printf "\n%d test(s) produced no parseable result.\n" "$ERROR_COUNT"
fi

if [[ $FAIL_TOTAL -eq 0 && $ERROR_COUNT -eq 0 ]]; then
    printf "\nAll tests PASSED (%d assertions).\n" "$PASS_TOTAL"
else
    printf "\nFAILED: %d assertions, %d errors.\n" "$FAIL_TOTAL" "$ERROR_COUNT"
    exit 1
fi
