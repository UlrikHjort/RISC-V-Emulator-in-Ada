#!/bin/bash
# Run riscv-arch-test compliance tests against our emulator
#
# Usage: ./run_arch_tests.sh <suite> [test_name]
#   suite: I, M, A, C, F, D, Zicsr, privilege
#   test_name: optional, run only a specific test (without .S extension)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EMULATOR="${SCRIPT_DIR}/../bin/riscv_emulator"
SUITE_BASE="${SCRIPT_DIR}/riscv-arch-test/riscv-test-suite/rv32i_m"
ENV_DIR="${SCRIPT_DIR}/env"
CONFIG="${ENV_DIR}/arch-test.cfg"
LINK_SCRIPT="${ENV_DIR}/link.ld"
WORK_DIR="${SCRIPT_DIR}/work"

# Cross-compiler prefix
CROSS="${RISCV_PREFIX:-riscv32-unknown-elf}"
CC="${CROSS}-gcc"
NM="${CROSS}-nm"
OBJDUMP="${CROSS}-objdump"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

if [ $# -lt 1 ]; then
    echo "Usage: $0 <suite> [test_name]"
    echo "  suite: I, M, A, C, F, D, Zicsr, privilege"
    echo "  test_name: optional specific test (without .S)"
    exit 1
fi

SUITE="$1"
SPECIFIC_TEST="${2:-}"

# Map suite to -march flag and extra defines
EXTRA_DEFINES="-DXLEN=32"
case "$SUITE" in
    I|M)
        MARCH="rv32im_zicsr"
        ;;
    K)
        MARCH="rv32im_zicsr_zbkb_zbkc_zbkx_zkne_zknd_zknh_zksed_zksh"
        ;;
    privilege)
        MARCH="rv32im_zicsr"
        EXTRA_DEFINES="$EXTRA_DEFINES -Drvtest_mtrap_routine"
        ;;
    Zifencei)
        MARCH="rv32im_zicsr_zifencei"
        ;;
    C)
        MARCH="rv32imc_zicsr"
        ;;
    F)
        MARCH="rv32imf_zicsr"
        EXTRA_DEFINES="$EXTRA_DEFINES -DFLEN=32"
        ;;
    *)
        echo "Unknown suite: $SUITE"
        echo "Available suites: I, M, C, F, K, Zifencei, privilege"
        exit 1
        ;;
esac

SUITE_DIR="${SUITE_BASE}/${SUITE}/src"
REF_DIR="${SUITE_BASE}/${SUITE}/references"

if [ ! -d "$SUITE_DIR" ]; then
    echo "Suite directory not found: $SUITE_DIR"
    echo "Did you run 'make clone' first?"
    exit 1
fi

# Include paths for arch test headers
ARCH_TEST_INCLUDE="${SCRIPT_DIR}/riscv-arch-test/riscv-test-suite/env"

mkdir -p "$WORK_DIR"

PASS=0
FAIL=0
SKIP=0
ERRORS=""

# Find test files
if [ -n "$SPECIFIC_TEST" ]; then
    TESTS="${SUITE_DIR}/${SPECIFIC_TEST}.S"
    if [ ! -f "$TESTS" ]; then
        echo "Test not found: $TESTS"
        exit 1
    fi
    TESTS_LIST="$TESTS"
else
    TESTS_LIST=$(find "$SUITE_DIR" -name '*.S' | sort)
fi

TOTAL=$(echo "$TESTS_LIST" | wc -l)
COUNT=0

for TEST_FILE in $TESTS_LIST; do
    TEST_NAME=$(basename "$TEST_FILE" .S)
    COUNT=$((COUNT + 1))

    REF_FILE="${REF_DIR}/${TEST_NAME}.reference_output"
    if [ ! -f "$REF_FILE" ]; then
        printf "[%3d/%3d] %-40s ${YELLOW}SKIP${NC} (no reference)\n" "$COUNT" "$TOTAL" "$TEST_NAME"
        SKIP=$((SKIP + 1))
        continue
    fi

    ELF_FILE="${WORK_DIR}/${TEST_NAME}.elf"
    SIG_FILE="${WORK_DIR}/${TEST_NAME}.sig"

    # Compile
    if ! ${CC} -march=${MARCH} -mabi=ilp32 -static -nostdlib -nostartfiles \
        -mno-relax -Wl,--no-relax \
        -I"${ENV_DIR}" -I"${ARCH_TEST_INCLUDE}" \
        ${EXTRA_DEFINES} \
        -T "${LINK_SCRIPT}" \
        -o "${ELF_FILE}" "${TEST_FILE}" 2>"${WORK_DIR}/${TEST_NAME}.compile.log"; then
        printf "[%3d/%3d] %-40s ${RED}FAIL${NC} (compile error)\n" "$COUNT" "$TOTAL" "$TEST_NAME"
        FAIL=$((FAIL + 1))
        ERRORS="${ERRORS}\n  ${TEST_NAME}: compile error"
        continue
    fi

    # Extract signature addresses
    BEGIN_SIG=$(${NM} "${ELF_FILE}" | grep ' begin_signature$' | awk '{print $1}')
    END_SIG=$(${NM} "${ELF_FILE}" | grep ' end_signature$' | awk '{print $1}')

    if [ -z "$BEGIN_SIG" ] || [ -z "$END_SIG" ]; then
        printf "[%3d/%3d] %-40s ${RED}FAIL${NC} (no signature symbols)\n" "$COUNT" "$TOTAL" "$TEST_NAME"
        FAIL=$((FAIL + 1))
        ERRORS="${ERRORS}\n  ${TEST_NAME}: missing begin_signature/end_signature"
        continue
    fi

    # Run emulator
    if ! timeout 30 "${EMULATOR}" --config "${CONFIG}" --no-uart -q \
        --dump-signature "${BEGIN_SIG}" "${END_SIG}" "${SIG_FILE}" \
        "${ELF_FILE}" 2>"${WORK_DIR}/${TEST_NAME}.run.log"; then
        printf "[%3d/%3d] %-40s ${RED}FAIL${NC} (runtime error/timeout)\n" "$COUNT" "$TOTAL" "$TEST_NAME"
        FAIL=$((FAIL + 1))
        ERRORS="${ERRORS}\n  ${TEST_NAME}: runtime error or timeout"
        continue
    fi

    if [ ! -f "$SIG_FILE" ]; then
        printf "[%3d/%3d] %-40s ${RED}FAIL${NC} (no signature output)\n" "$COUNT" "$TOTAL" "$TEST_NAME"
        FAIL=$((FAIL + 1))
        ERRORS="${ERRORS}\n  ${TEST_NAME}: no signature file produced"
        continue
    fi

    # Compare signatures
    if diff -q "$SIG_FILE" "$REF_FILE" > /dev/null 2>&1; then
        printf "[%3d/%3d] %-40s ${GREEN}PASS${NC}\n" "$COUNT" "$TOTAL" "$TEST_NAME"
        PASS=$((PASS + 1))
    else
        printf "[%3d/%3d] %-40s ${RED}FAIL${NC} (signature mismatch)\n" "$COUNT" "$TOTAL" "$TEST_NAME"
        FAIL=$((FAIL + 1))
        ERRORS="${ERRORS}\n  ${TEST_NAME}: signature mismatch"
        # Save diff for analysis
        diff "$SIG_FILE" "$REF_FILE" > "${WORK_DIR}/${TEST_NAME}.diff" 2>&1 || true
    fi
done

echo ""
echo "========================================="
echo " Suite: ${SUITE}"
echo " Total: ${TOTAL}  Pass: ${PASS}  Fail: ${FAIL}  Skip: ${SKIP}"
echo "========================================="

if [ -n "$ERRORS" ]; then
    echo ""
    echo "Failures:"
    echo -e "$ERRORS"
fi

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
