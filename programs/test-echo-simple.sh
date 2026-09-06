#!/bin/bash
# Simple echo test - just send CR and see response

BINARY="echo.bin"
EMULATOR="../bin/riscv_emulator"

# Start emulator
EMULATOR_OUT=$(mktemp)
$EMULATOR --machine qemu-virt --pty $BINARY 80000000 > $EMULATOR_OUT 2>&1 &
EMULATOR_PID=$!
sleep 1

# Get PTY
PTY=$(grep "UART PTY:" $EMULATOR_OUT | sed 's/.*UART PTY: \(\/dev\/pts\/[0-9]*\).*/\1/')

if [ -z "$PTY" ]; then
    echo "Error: No PTY found"
    kill $EMULATOR_PID 2>/dev/null
    exit 1
fi

echo "PTY: $PTY"

# Read initial output
echo "Initial output:"
timeout 1 cat $PTY &
sleep 1.5

# Send single character 'A' followed by CR
echo "Sending 'A' + CR..."
printf "A\r" > $PTY
sleep 0.5

# Read response
echo "Response:"
timeout 1 cat $PTY

# Cleanup
kill $EMULATOR_PID 2>/dev/null
rm -f $EMULATOR_OUT
