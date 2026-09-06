#!/bin/bash
# Interactive Forth session helper

echo "Starting Forth interpreter..."
echo "In another terminal, run:"
echo ""
echo "  minicom -D /dev/pts/X"
echo ""
echo "(Replace X with the PTY number shown below)"
echo ""

cd "$(dirname "$0")"

if [ ! -f out/bin/forth.bin ]; then
    echo "out/bin/forth.bin not found -- run 'make forth' first." >&2
    exit 1
fi

exec ../bin/riscv_emulator --machine qemu-virt --pty out/bin/forth.bin 80000000
