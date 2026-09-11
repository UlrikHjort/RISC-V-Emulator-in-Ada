#!/bin/bash
# Run riscv-arch-test compliance tests against our emulator
#
# Usage: ./run_arch_tests.sh <suite> [test_name]
#        ./run_arch_tests.sh all
#   suite: I, M, A, C, F, K, Zifencei, privilege
#          all       - run every suite in turn and print a combined summary
#   test_name: optional, run only a specific test (without .S extension)
#              (not valid together with "all")

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

# Suites run by "all", in a sensible order.
ALL_SUITES="I M C F K Zifencei privilege"

usage() {
    echo "Usage: $0 <suite> [test_name]"
    echo "       $0 all"
    echo "  suite: I, M, C, F, K, Zifencei, privilege"
    echo "         all - run every suite and print a combined summary"
    echo "  test_name: optional specific test (without .S); not valid with 'all'"
}

if [ $# -lt 1 ]; then
    usage
    exit 1
fi

# Grand totals, accumulated across suites (used by "all").
G_PASS=0
G_FAIL=0
G_SKIP=0
G_TOTAL=0
SUMMARY=""

# ---------------------------------------------------------------------------
# run_suite <suite> [specific_test]
#   Builds and runs one suite. Prints per-test lines and a suite summary box.
#   Updates the G_* grand totals and appends a row to SUMMARY.
#   Returns 1 if the suite had any failures, else 0 (never exits, so callers
#   can loop over suites under 'set -e').
# ---------------------------------------------------------------------------
run_suite() {
    local SUITE="$1"
    local SPECIFIC_TEST="${2:-}"

    # Map suite to -march flag and extra defines
    local MARCH EXTRA_DEFINES="-DXLEN=32"
    case "$SUITE" in
        I|M)
            MARCH="rv32im_zicsr" ;;
        K)
            MARCH="rv32im_zicsr_zbkb_zbkc_zbkx_zkne_zknd_zknh_zksed_zksh" ;;
        privilege)
            MARCH="rv32im_zicsr"
            EXTRA_DEFINES="$EXTRA_DEFINES -Drvtest_mtrap_routine" ;;
        Zifencei)
            MARCH="rv32im_zicsr_zifencei" ;;
        C)
            MARCH="rv32imc_zicsr" ;;
        F)
            MARCH="rv32imf_zicsr"
            EXTRA_DEFINES="$EXTRA_DEFINES -DFLEN=32" ;;
        *)
            echo "Unknown suite: $SUITE"
            echo "Available suites: I, M, C, F, K, Zifencei, privilege"
            return 2 ;;
    esac

    local SUITE_DIR="${SUITE_BASE}/${SUITE}/src"
    local REF_DIR="${SUITE_BASE}/${SUITE}/references"

    if [ ! -d "$SUITE_DIR" ]; then
        echo "Suite directory not found: $SUITE_DIR"
        echo "Did you run 'make clone' first?"
        return 2
    fi

    local ARCH_TEST_INCLUDE="${SCRIPT_DIR}/riscv-arch-test/riscv-test-suite/env"
    mkdir -p "$WORK_DIR"

    local PASS=0 FAIL=0 SKIP=0 ERRORS="" TESTS_LIST TOTAL COUNT=0

    if [ -n "$SPECIFIC_TEST" ]; then
        local TESTS="${SUITE_DIR}/${SPECIFIC_TEST}.S"
        if [ ! -f "$TESTS" ]; then
            echo "Test not found: $TESTS"
            return 2
        fi
        TESTS_LIST="$TESTS"
    else
        TESTS_LIST=$(find "$SUITE_DIR" -name '*.S' | sort)
    fi

    TOTAL=$(echo "$TESTS_LIST" | wc -l)

    local TEST_FILE TEST_NAME REF_FILE ELF_FILE SIG_FILE BEGIN_SIG END_SIG
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

    # Accumulate grand totals and record a one-line summary row.
    G_PASS=$((G_PASS + PASS))
    G_FAIL=$((G_FAIL + FAIL))
    G_SKIP=$((G_SKIP + SKIP))
    G_TOTAL=$((G_TOTAL + TOTAL))
    SUMMARY="${SUMMARY}$(printf '  %-12s Total: %3d  Pass: %3d  Fail: %3d  Skip: %3d' \
        "$SUITE" "$TOTAL" "$PASS" "$FAIL" "$SKIP")\n"

    if [ "$FAIL" -gt 0 ]; then
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
if [ "$1" = "all" ] || [ "$1" = "ALL" ]; then
    if [ $# -gt 1 ]; then
        echo "Error: a specific test name cannot be combined with 'all'"
        usage
        exit 1
    fi

    OVERALL_FAIL=0
    for s in $ALL_SUITES; do
        echo ""
        echo "#########################################"
        echo "# Running suite: $s"
        echo "#########################################"
        # Never let one failing suite abort the whole run.
        run_suite "$s" || OVERALL_FAIL=1
    done

    echo ""
    echo "========================================="
    echo " Combined summary (all suites)"
    echo "========================================="
    echo -e "$SUMMARY"
    echo "-----------------------------------------"
    printf '  %-12s Total: %3d  Pass: %3d  Fail: %3d  Skip: %3d\n' \
        "TOTAL" "$G_TOTAL" "$G_PASS" "$G_FAIL" "$G_SKIP"
    echo "========================================="

    exit "$OVERALL_FAIL"
fi

# Single-suite mode (unchanged behaviour).
run_suite "$1" "${2:-}" || exit 1
exit 0
