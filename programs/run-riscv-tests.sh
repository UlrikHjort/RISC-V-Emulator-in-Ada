#!/usr/bin/env bash
# Build and run the official riscv-tests ISA suite against the emulator.
# Uses the standard bare-metal "p" (machine-mode physical) environment and the
# HTIF tohost termination protocol (emulator flag --htif).
#
# Usage: ./run-riscv-tests.sh [family ...]
#   With no args, runs the default family list below.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
RT="$HERE/riscv-tests"
EMU="$HERE/../bin/riscv_emulator"
CC="${RISCV_CC:-riscv32-unknown-elf-gcc}"
OUT="$RT/out"
MAXI="${MAXI:-5000000}"

mkdir -p "$OUT"

# family:march:abi   (abi picks the multilib; -nostdlib so exact lib not needed)
FAMILIES_DEFAULT="
rv32ui:rv32imac:ilp32
rv32um:rv32imac:ilp32
rv32ua:rv32imac:ilp32
rv32uc:rv32imac:ilp32
rv32uf:rv32imafc:ilp32f
rv32mi:rv32imac:ilp32
rv32si:rv32imac:ilp32
rv32uzba:rv32imac_zba:ilp32
rv32uzbb:rv32imac_zbb:ilp32
rv32uzbs:rv32imac_zbs:ilp32
rv32uzicond:rv32imac_zicond:ilp32
rv64ui:rv64imac:lp64
rv64um:rv64imac:lp64
rv64ua:rv64imac:lp64
rv64uc:rv64imac:lp64
rv64uf:rv64imafdc:lp64d
rv64ud:rv64imafdc:lp64d
rv64mi:rv64imac:lp64
rv64si:rv64imac:lp64
rv64uzba:rv64imac_zba:lp64
rv64uzbb:rv64imac_zbb:lp64
rv64uzicond:rv64imac_zicond:lp64
"

FAMILIES="${*:-$FAMILIES_DEFAULT}"

GTOTAL=0; GPASS=0; GFAIL=0; GERR=0
FAILED_LIST=""

printf "%-14s %5s %5s %5s %5s\n" "FAMILY" "TOTAL" "PASS" "FAIL" "BUILDERR"
printf "%-14s %5s %5s %5s %5s\n" "------" "-----" "----" "----" "--------"

for spec in $FAMILIES; do
  fam="${spec%%:*}"; rest="${spec#*:}"; march="${rest%%:*}"; abi="${rest##*:}"
  dir="$RT/isa/$fam"
  [ -d "$dir" ] || { echo "skip $fam (no dir)"; continue; }

  ft=0; fp=0; ff=0; fe=0
  for src in "$dir"/*.S; do
    base="$(basename "$src" .S)"
    # skip include-only helper files
    case "$base" in *.h) continue;; esac
    elf="$OUT/${fam}-${base}"
    if ! "$CC" -march="${march}_zicsr_zifencei" -mabi="$abi" -mcmodel=medany \
         -static -nostdlib -nostartfiles -fno-builtin -fno-common \
         -I "$RT/isa/macros/scalar" -I "$RT/env/p" \
         -T "$RT/env/p/link.ld" -o "$elf" "$src" 2>>"$OUT/build-errors.log"; then
      fe=$((fe+1)); GERR=$((GERR+1))
      FAILED_LIST="$FAILED_LIST ${fam}/${base}[build]"
      continue
    fi
    ft=$((ft+1)); GTOTAL=$((GTOTAL+1))
    # Resolve the tohost address via nm (works for ELF32 and ELF64).
    tohost="$(${RISCV_NM:-riscv32-unknown-elf-nm} "$elf" 2>/dev/null \
              | awk '$3=="tohost"{print $1}')"
    if [ -n "$tohost" ]; then
      htif_args="--tohost $tohost"
    else
      htif_args="--htif"
    fi
    "$EMU" --machine qemu-virt $htif_args --quiet --max-instructions "$MAXI" "$elf" \
        >"$OUT/${fam}-${base}.log" 2>&1
    rc=$?
    if [ "$rc" -eq 0 ]; then
      fp=$((fp+1)); GPASS=$((GPASS+1))
    else
      ff=$((ff+1)); GFAIL=$((GFAIL+1))
      FAILED_LIST="$FAILED_LIST ${fam}/${base}(rc=$rc)"
    fi
  done
  printf "%-14s %5d %5d %5d %5d\n" "$fam" "$ft" "$fp" "$ff" "$fe"
done

echo "-------------------------------------------------"
printf "%-14s %5d %5d %5d %5d\n" "TOTAL" "$GTOTAL" "$GPASS" "$GFAIL" "$GERR"
if [ -n "$FAILED_LIST" ]; then
  echo
  echo "Non-passing:"
  for f in $FAILED_LIST; do echo "  $f"; done
fi
[ "$GFAIL" -eq 0 ]
