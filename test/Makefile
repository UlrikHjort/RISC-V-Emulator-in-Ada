# Test programs Makefile for RISC-V Emulator

CROSS ?= riscv32-unknown-elf-
CC = $(CROSS)gcc
AS = $(CROSS)as
OBJCOPY = $(CROSS)objcopy
OBJDUMP = $(CROSS)objdump

# Compile for RV32IMFD, no standard library, freestanding
CFLAGS = -march=rv32imfd -mabi=ilp32 -nostdlib -ffreestanding -O2
# Flags for vector extension tests (RV32IMFDV)
CFLAGS_V = -march=rv32imfd_zve32x -mabi=ilp32 -nostdlib -ffreestanding -O2
ASFLAGS = -march=rv32im -mabi=ilp32
LDFLAGS = -Ttext=0x0 -nostdlib

# Source files
SOURCES = $(wildcard *.c)
BINS = $(SOURCES:.c=.bin)
ELFS = $(SOURCES:.c=.elf)
ASMS = $(SOURCES:.c=.asm)

# Startup object
STARTUP = start.o

.PHONY: all clean disasm test test-elf elfs

# Keep ELF files (don't delete as intermediate)
.PRECIOUS: %.elf

all: $(BINS)

elfs: $(ELFS)

# Assemble startup code
start.o: start.S
	$(AS) $(ASFLAGS) -o $@ $<

# Compile C to object
%.o: %.c
	$(CC) $(CFLAGS) -c -o $@ $<

# Special rule for vector tests (need V extension)
vector.o: vector.c
	$(CC) $(CFLAGS_V) -c -o $@ $<

vector_simple.o: vector_simple.c
	$(CC) $(CFLAGS_V) -c -o $@ $<

# Link with startup code
%.elf: %.o $(STARTUP)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $(STARTUP) $<

# Extract raw binary from ELF
%.bin: %.elf
	$(OBJCOPY) -O binary $< $@

# Generate disassembly
%.asm: %.elf
	$(OBJDUMP) -d $< > $@

disasm: $(ASMS)

clean:
	rm -f *.elf *.bin *.asm *.o

# Run all tests (binary)
test: $(BINS)
	@echo "Running all tests (binary)..."
	@for t in simple arithmetic loop fibonacci memory float vector; do \
		result=$$(../bin/riscv_emulator $$t.bin 2>&1 | grep "Return value" | awk '{print $$NF}'); \
		echo "$$t: $$result"; \
	done
	@../bin/riscv_emulator hello.bin 2>&1 | grep -q "Hello, World" && echo "hello: OK" || echo "hello: FAIL"

# Run all tests (ELF)
test-elf: $(ELFS)
	@echo "Running all tests (ELF)..."
	@for t in simple arithmetic loop fibonacci memory float vector; do \
		result=$$(../bin/riscv_emulator $$t.elf 2>&1 | grep "Return value" | awk '{print $$NF}'); \
		echo "$$t: $$result"; \
	done

# Run a single test (usage: make run-simple)
run-%: %.bin
	../bin/riscv_emulator $<

# Run with trace (usage: make trace-simple)
trace-%: %.bin
	../bin/riscv_emulator -t $<
