#!/bin/bash
# Test script to run a program and capture UART output

if [ $# -ne 1 ]; then
    echo "Usage: $0 <binary>"
    exit 1
fi

BINARY=$1
EMULATOR="../bin/riscv_emulator"

# Start emulator in background and capture PTY path
EMULATOR_OUT=$(mktemp)
$EMULATOR --machine qemu-virt --pty $BINARY 80000000 > $EMULATOR_OUT 2>&1 &
EMULATOR_PID=$!

# Wait a moment for emulator to start
sleep 0.5

# Extract PTY path
PTY=$(grep "UART PTY:" $EMULATOR_OUT | sed 's/.*UART PTY: \(\/dev\/pts\/[0-9]*\).*/\1/')

if [ -z "$PTY" ]; then
    echo "Error: Could not find PTY device"
    kill $EMULATOR_PID 2>/dev/null
    rm -f $EMULATOR_OUT
    exit 1
fi

echo "Emulator started with PTY: $PTY"
echo "Reading output for 2 seconds..."
echo "---"

# Read from PTY for 2 seconds
timeout 2 cat $PTY

echo ""
echo "---"

# Clean up
kill $EMULATOR_PID 2>/dev/null
rm -f $EMULATOR_OUT
