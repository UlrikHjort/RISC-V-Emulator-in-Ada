# Examples Makefile for RISC-V Emulator
# Demonstrates all supported extensions: RV32IMFDV

CROSS ?= riscv32-unknown-elf-
CC = $(CROSS)gcc
AS = $(CROSS)as
OBJCOPY = $(CROSS)objcopy
OBJDUMP = $(CROSS)objdump

# Standard flags for RV32IMFD
CFLAGS = -march=rv32imfd -mabi=ilp32 -nostdlib -ffreestanding -O2
# Flags for vector extension examples
CFLAGS_V = -march=rv32imfd_zve32x -mabi=ilp32 -nostdlib -ffreestanding -O2
ASFLAGS = -march=rv32im -mabi=ilp32
LDFLAGS = -Ttext=0x0 -nostdlib

# Examples
EXAMPLES = 01_basic_integer 02_multiply_divide 03_single_float \
           04_double_float 05_vector_basic 06_vector_advanced

ELFS = $(addsuffix .elf,$(EXAMPLES))

# Startup object (use the one from test dir)
STARTUP = ../test/start.o

.PHONY: all clean run run-all

.PRECIOUS: %.elf

all: $(ELFS)

# Ensure startup code exists
$(STARTUP): ../test/start.S
	$(AS) $(ASFLAGS) -o $@ $<

# Compile non-vector examples
01_basic_integer.o 02_multiply_divide.o 03_single_float.o 04_double_float.o: %.o: %.c
	$(CC) $(CFLAGS) -c -o $@ $<

# Compile vector examples (need V extension)
05_vector_basic.o 06_vector_advanced.o: %.o: %.c
	$(CC) $(CFLAGS_V) -c -o $@ $<

# Link with startup code
%.elf: %.o $(STARTUP)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $(STARTUP) $<

# Generate disassembly
%.asm: %.elf
	$(OBJDUMP) -d $< > $@

clean:
	rm -f *.elf *.o *.asm

# Run all examples
run-all: $(ELFS)
	@echo "=== Running all examples ==="
	@for ex in $(EXAMPLES); do \
		result=$$(../bin/riscv_emulator $$ex.elf 2>&1 | grep "Return value" | awk '{print $$NF}'); \
		if [ "$$result" = "0" ]; then \
			echo "$$ex: PASS"; \
		else \
			echo "$$ex: FAIL (returned $$result)"; \
		fi \
	done

# Run a single example (usage: make run EX=01_basic_integer)
run: $(EX).elf
	../bin/riscv_emulator $(EX).elf
