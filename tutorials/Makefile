# Build the tutorial example programs.
#
# These are deliberately small, self-contained RV32 programs used by the
# walkthroughs in this directory. They reuse the startup code, semihosting
# log and linker script from ../programs, so nothing here is duplicated.
#
#   make            build every tutorial example (.elf + .bin)
#   make clean      remove built artefacts
#
# Override the toolchain prefix if yours differs (see doc/WRITING-PROGRAMS.md):
#   make CROSS=riscv64-unknown-elf-

CROSS   ?= riscv32-unknown-elf-
CC       = $(CROSS)gcc
OBJCOPY  = $(CROSS)objcopy
OBJDUMP  = $(CROSS)objdump
SIZE     = $(CROSS)size

P        = ../programs
CFLAGS   = -march=rv32imc -mabi=ilp32 -nostdlib -nostartfiles -fno-builtin -O2 -g -Wall -I$(P)
LDFLAGS  = -T $(P)/hello.ld

# Common support objects (startup + semihosting log).
SUPPORT  = $(P)/crt0.S $(P)/uart.c $(P)/log.c

OUT      = out
ELF      = $(OUT)/elf
BIN      = $(OUT)/bin
DIS      = $(OUT)/dis

EXAMPLES = primes-slow primes-fast wildptr sum-rowmajor sum-colmajor

ELFS = $(patsubst %,$(ELF)/%.elf,$(EXAMPLES))
BINS = $(patsubst %,$(BIN)/%.bin,$(EXAMPLES))

all: $(ELFS) $(BINS)

$(ELF) $(BIN) $(DIS):
	@mkdir -p $@

$(ELF)/%.elf: %.c $(P)/hello.ld | $(ELF)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $(SUPPORT) $<
	@$(SIZE) $@

$(BIN)/%.bin: $(ELF)/%.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	@$(OBJDUMP) -d $< > $(DIS)/$*.dis

clean:
	rm -rf $(OUT)

.PHONY: all clean
