# Bare-metal programs for RISC-V Emulator

# Toolchain (override on the command line, e.g. make CROSS=riscv64-unknown-elf-)
CROSS ?= riscv32-unknown-elf-
CC = $(CROSS)gcc
OBJCOPY = $(CROSS)objcopy
OBJDUMP = $(CROSS)objdump
SIZE = $(CROSS)size

# Compiler flags (RV32)
ARCH = rv32imc
ABI = ilp32
CFLAGS = -march=$(ARCH) -mabi=$(ABI) -nostdlib -nostartfiles -fno-builtin
CFLAGS += -O2 -g -Wall
LDFLAGS = -T hello.ld

# Compiler flags (RV64)
ARCH64 = rv64imafd
ABI64  = lp64d
CFLAGS64 = -march=$(ARCH64) -mabi=$(ABI64) -mcmodel=medany -nostdlib -nostartfiles -fno-builtin
CFLAGS64 += -O2 -g -Wall
LDFLAGS64 = -T hello64.ld

# Emulator path
EMULATOR = ../bin/riscv_emulator

# Log directory (all semihosting log files land here)
LOG_DIR  := logs
LOGFLAGS := --log-dir $(LOG_DIR)

# Output directories
OUT := out
BIN := $(OUT)/bin
ELF := $(OUT)/elf
DIS := $(OUT)/dis


.PHONY: all clean hello echo forth fibonacci primes mandelbrot malloc-test test-runner printf-float-test string-test stdlib-test math-test time-test string-parse-test game-of-life snake-game maze-generator falling-tiles matrix-rain \
        gpio-basic gpio-interrupt gpio-input spi-flash-test uart-interrupt cli i2c-test timer-test sensor-monitor pwm-fade \
        debug-demo profile-demo rtos-demo watchdog-test dma-test \
        run-hello run-echo run-forth run-fibonacci run-primes run-mandelbrot run-malloc-test run-test-runner run-printf-float-test run-string-test run-stdlib-test run-math-test run-time-test run-string-parse-test run-game-of-life run-snake-game run-maze-generator run-falling-tiles run-matrix-rain \
        run-gpio-basic run-gpio-interrupt run-gpio-input run-spi-flash-test run-uart-interrupt run-cli run-i2c-test run-timer-test run-sensor-monitor run-pwm-fade \
        run-debug-demo run-profile-demo run-rtos-demo run-watchdog-test run-dma-test \
        log-test run-log-test \
        vector-demo run-vector-demo \
        matrix-demo run-matrix-demo \
        crc32-test run-crc32-test \
        sort-bench run-sort-bench \
        fir-filter run-fir-filter \
        sha256-test run-sha256-test \
        fp-math-test run-fp-math-test \
        rvv-advanced run-rvv-advanced \
        string-ops run-string-ops \
        chacha20 run-chacha20 \
        rvv-float run-rvv-float \
        trap-test run-trap-test \
        m-ext-test run-m-ext-test \
        lz77 run-lz77 \
        branch-test run-branch-test \
        load-store-test run-load-store-test \
        csr-test run-csr-test \
        rvv-strided run-rvv-strided \
        float-classify run-float-classify \
        aes128 run-aes128 \
        base64 run-base64 \
        huffman run-huffman \
        zbb-test run-zbb-test \
        fixedpoint-test run-fixedpoint-test \
        atomic-test run-atomic-test \
        clmul-test run-clmul-test \
        gf256-test run-gf256-test \
        pid-test run-pid-test \
        lfsr-test run-lfsr-test \
        iir-test run-iir-test \
        fft-test run-fft-test \
        montgomery-test run-montgomery-test \
        reed-solomon-test run-reed-solomon-test \
        zba-test run-zba-test \
        ntt-test run-ntt-test \
        ecc-test run-ecc-test \
        rs-correct-test run-rs-correct-test \
        chacha20-poly1305 run-chacha20-poly1305 \
        aes-gcm run-aes-gcm \
        aes-modes-test run-aes-modes-test \
        csr-more-test run-csr-more-test \
        blake2s run-blake2s \
        sha3 run-sha3 \
        viterbi run-viterbi \
        fft-conv run-fft-conv \
        scanf-test run-scanf-test \
        rtos-test run-rtos-test \
        fat12-test run-fat12-test \
        modbus-test run-modbus-test \
        deflate-test run-deflate-test \
        setjmp-test run-setjmp-test \
        smode-test run-smode-test \
        umode-test run-umode-test \
        hmac-sha256-test run-hmac-sha256-test \
        plic-test run-plic-test \
        rv64-test run-rv64-test \
        rv64-fp-test run-rv64-fp-test \
        rv64-sha256-test run-rv64-sha256-test \
        rv64-wops-test run-rv64-wops-test \
        rv64-zbb64-test run-rv64-zbb64-test \
        rv64-atomic-test run-rv64-atomic-test \
        rv64-zba64-test run-rv64-zba64-test \
        rv64-zicond-test run-rv64-zicond-test \
        rv64-zbs64-test run-rv64-zbs64-test \
        rv64-zbc64-test run-rv64-zbc64-test \
        rv64-zbkx64-test run-rv64-zbkx64-test \
        rv64-zbkb64-test run-rv64-zbkb64-test \
        rv64-reserved-test run-rv64-reserved-test \
        prtos-test run-prtos-test \
        prtos2-test run-prtos2-test \
        virtio-blk-test run-virtio-blk-test \
        sv39-test run-sv39-test \
        p256-ecdsa-test run-p256-ecdsa-test \
        x25519-test run-x25519-test \
        timing-test run-timing-test \
        zfh-test run-zfh-test \
        multihart-test run-multihart-test \
        pthread-test run-pthread-test \
        rv32e-test run-rv32e-test \
        rv64e-test run-rv64e-test \
        coremark-test run-coremark-test \
        gzip-test run-gzip-test \
        ed25519-test run-ed25519-test \
        pipeline-test run-pipeline-test \
        test-all

all: $(BIN)/hello.bin $(BIN)/echo.bin $(BIN)/forth.bin $(BIN)/fibonacci.bin $(BIN)/primes.bin $(BIN)/mandelbrot.bin $(BIN)/malloc-test.bin $(BIN)/test-runner.bin $(BIN)/printf-float-test.bin $(BIN)/string-test.bin $(BIN)/stdlib-test.bin $(BIN)/math-test.bin $(BIN)/time-test.bin $(BIN)/string-parse-test.bin $(BIN)/game-of-life.bin $(BIN)/snake-game.bin $(BIN)/maze-generator.bin $(BIN)/falling-tiles.bin $(BIN)/matrix-rain.bin \
     $(BIN)/gpio-basic.bin $(BIN)/gpio-interrupt.bin $(BIN)/gpio-input.bin $(BIN)/spi-flash-test.bin $(BIN)/uart-interrupt.bin $(BIN)/cli.bin $(BIN)/i2c-test.bin $(BIN)/timer-test.bin $(BIN)/sensor-monitor.bin $(BIN)/pwm-fade.bin \
     $(BIN)/debug-demo.bin $(BIN)/profile-demo.bin $(BIN)/rtos-demo.bin $(BIN)/watchdog-test.bin $(BIN)/dma-test.bin \
     $(BIN)/log-test.bin \
     $(BIN)/vector-demo.bin \
     $(BIN)/matrix-demo.bin \
     $(BIN)/crc32-test.bin \
     $(BIN)/sort-bench.bin \
     $(BIN)/fir-filter.bin \
     $(BIN)/sha256-test.bin \
     $(BIN)/fp-math-test.bin \
     $(BIN)/rvv-advanced.bin \
     $(BIN)/string-ops.bin \
     $(BIN)/chacha20.bin \
     $(BIN)/rvv-float.bin \
     $(BIN)/trap-test.bin \
     $(BIN)/m-ext-test.bin \
     $(BIN)/lz77.bin \
     $(BIN)/branch-test.bin \
     $(BIN)/load-store-test.bin \
     $(BIN)/csr-test.bin \
     $(BIN)/rvv-strided.bin \
     $(BIN)/float-classify.bin \
     $(BIN)/aes128.bin \
     $(BIN)/base64.bin \
     $(BIN)/huffman.bin \
     $(BIN)/zbb-test.bin \
     $(BIN)/fixedpoint-test.bin \
     $(BIN)/atomic-test.bin \
     $(BIN)/clmul-test.bin \
     $(BIN)/gf256-test.bin \
     $(BIN)/pid-test.bin \
     $(BIN)/lfsr-test.bin \
     $(BIN)/iir-test.bin \
     $(BIN)/fft-test.bin \
     $(BIN)/montgomery-test.bin \
     $(BIN)/reed-solomon-test.bin \
     $(BIN)/zba-test.bin \
     $(BIN)/ntt-test.bin \
     $(BIN)/ecc-test.bin \
     $(BIN)/rs-correct-test.bin \
     $(BIN)/chacha20-poly1305.bin \
     $(BIN)/aes-gcm.bin \
     $(BIN)/blake2s.bin \
     $(BIN)/sha3.bin \
     $(BIN)/viterbi.bin \
     $(BIN)/fft-conv.bin \
     $(BIN)/scanf-test.bin \
     $(BIN)/rtos-test.bin \
     $(BIN)/fat12-test.bin \
     $(BIN)/modbus-test.bin \
     $(BIN)/deflate-test.bin \
     $(BIN)/setjmp-test.bin \
     $(BIN)/smode-test.bin \
     $(BIN)/umode-test.bin \
     $(BIN)/hmac-sha256-test.bin \
     $(BIN)/aes-modes-test.bin \
     $(BIN)/csr-more-test.bin \
     $(BIN)/plic-test.bin \
     $(ELF)/rv64-test.elf \
     $(ELF)/rv64-fp-test.elf \
     $(ELF)/rv64-sha256-test.elf \
     $(ELF)/rv64-wops-test.elf \
     $(ELF)/rv64-zbb64-test.elf \
     $(ELF)/rv64-atomic-test.elf \
     $(ELF)/rv64-zba64-test.elf \
     $(ELF)/rv64-zicond-test.elf \
     $(ELF)/rv64-zbs64-test.elf \
     $(ELF)/rv64-zbc64-test.elf \
     $(ELF)/rv64-zbkx64-test.elf \
     $(ELF)/rv64-zbkb64-test.elf \
     $(ELF)/rv64-reserved-test.elf \
     $(BIN)/prtos-test.bin \
     $(BIN)/prtos2-test.bin \
     $(BIN)/virtio-blk-test.bin \
     $(ELF)/sv39-test.elf \
     $(BIN)/p256-ecdsa-test.bin \
     $(BIN)/x25519-test.bin \
     $(BIN)/timing-test.bin \
     $(BIN)/zfh-test.bin \
     $(BIN)/multihart-test.bin \
     $(BIN)/pthread-test.bin \
     $(ELF)/rv32e-test.elf \
     $(ELF)/rv64e-test.elf \
     $(ELF)/time-test-posix.elf \
     $(BIN)/coremark-test.bin \
     $(ELF)/gzip-test.elf \
     $(BIN)/ed25519-test.bin \
     $(BIN)/pipeline-test.bin

# Common startup code (will be created on demand)
crt0.S:
	@echo "Creating startup code..."
	@echo '.section .text.start' > $@
	@echo '.global _start' >> $@
	@echo '' >> $@
	@echo '_start:' >> $@
	@echo '    # Set up stack pointer' >> $@
	@echo '    la sp, _stack_top' >> $@
	@echo '' >> $@
	@echo '    # Zero out .bss section' >> $@
	@echo '    la t0, __bss_start' >> $@
	@echo '    la t1, __bss_end' >> $@
	@echo '1:' >> $@
	@echo '    bge t0, t1, 2f' >> $@
	@echo '    sw zero, 0(t0)' >> $@
	@echo '    addi t0, t0, 4' >> $@
	@echo '    j 1b' >> $@
	@echo '2:' >> $@
	@echo '    # Call main' >> $@
	@echo '    call main' >> $@
	@echo '' >> $@
	@echo '    # If main returns, loop forever' >> $@
	@echo '3:' >> $@
	@echo '    j 3b' >> $@
	@echo '' >> $@
	@echo '.section .bss' >> $@
	@echo '__bss_start:' >> $@
	@echo '__bss_end:' >> $@

# Common linker script (will be created on demand)
hello.ld:
	@echo "Creating linker script..."
	@echo 'OUTPUT_ARCH("riscv")' > $@
	@echo 'ENTRY(_start)' >> $@
	@echo '' >> $@
	@echo 'MEMORY {' >> $@
	@echo '    RAM (rwx) : ORIGIN = 0x80000000, LENGTH = 1M' >> $@
	@echo '}' >> $@
	@echo '' >> $@
	@echo 'SECTIONS {' >> $@
	@echo '    .text : {' >> $@
	@echo '        *(.text.start)' >> $@
	@echo '        *(.text*)' >> $@
	@echo '    } > RAM' >> $@
	@echo '' >> $@
	@echo '    .rodata : {' >> $@
	@echo '        *(.rodata*)' >> $@
	@echo '    } > RAM' >> $@
	@echo '' >> $@
	@echo '    .data : {' >> $@
	@echo '        *(.data*)' >> $@
	@echo '    } > RAM' >> $@
	@echo '' >> $@
	@echo '    .bss : {' >> $@
	@echo '        . = ALIGN(8);' >> $@
	@echo '        __bss_start = .;' >> $@
	@echo '        *(.bss*)' >> $@
	@echo '        *(.sbss*)' >> $@
	@echo '        *(COMMON)' >> $@
	@echo '        . = ALIGN(8);' >> $@
	@echo '        __bss_end = .;' >> $@
	@echo '    } > RAM' >> $@
	@echo '' >> $@
	@echo '    _end = .;' >> $@
	@echo '    _stack_top = ORIGIN(RAM) + LENGTH(RAM);' >> $@
	@echo '}' >> $@

# UART driver (will be created on demand)
uart.c:
	@echo "Creating UART driver..."
	@echo '#define UART_BASE 0x10000000' > $@
	@echo '#define UART_RBR  (*(volatile unsigned char *)(UART_BASE + 0))' >> $@
	@echo '#define UART_THR  (*(volatile unsigned char *)(UART_BASE + 0))' >> $@
	@echo '#define UART_LSR  (*(volatile unsigned char *)(UART_BASE + 5))' >> $@
	@echo '#define LSR_DR    (1 << 0)' >> $@
	@echo '#define LSR_THRE  (1 << 5)' >> $@
	@echo '' >> $@
	@echo 'void putchar(char c) {' >> $@
	@echo '    if (c == 0x0A) {' >> $@
	@echo '        while ((UART_LSR & LSR_THRE) == 0);' >> $@
	@echo '        UART_THR = 0x0D;' >> $@
	@echo '    }' >> $@
	@echo '    while ((UART_LSR & LSR_THRE) == 0);' >> $@
	@echo '    UART_THR = c;' >> $@
	@echo '}' >> $@
	@echo '' >> $@
	@echo 'char getchar(void) {' >> $@
	@echo '    while ((UART_LSR & LSR_DR) == 0);' >> $@
	@echo '    return UART_RBR;' >> $@
	@echo '}' >> $@
	@echo '' >> $@
	@echo 'void puts(const char *s) {' >> $@
	@echo '    while (*s) {' >> $@
	@echo '        putchar(*s++);' >> $@
	@echo '    }' >> $@
	@echo '}' >> $@

# Hello world example (will be created on demand)
hello.c:
	@echo "Creating hello.c..."
	@printf 'void puts(const char *s);\n' > $@
	@printf '\n' >> $@
	@printf 'int main(void) {\n' >> $@
	@printf '    puts("Hello from RISC-V!\\n");\n' >> $@
	@printf '    puts("Emulator is working!\\n");\n' >> $@
	@printf '    while (1);\n' >> $@
	@printf '    return 0;\n' >> $@
	@printf '}\n' >> $@

# Echo example (will be created on demand)
echo.c:
	@echo "Creating echo.c..."
	@printf 'void putchar(char c);\n' > $@
	@printf 'char getchar(void);\n' >> $@
	@printf 'void puts(const char *s);\n' >> $@
	@printf '\n' >> $@
	@printf 'int main(void) {\n' >> $@
	@printf '    puts("Echo test - type characters:\\n");\n' >> $@
	@printf '    while (1) {\n' >> $@
	@printf '        char c = getchar();\n' >> $@
	@printf '        putchar(c);\n' >> $@
	@printf '        if (c == 0x0D) putchar(0x0A);\n' >> $@
	@printf '    }\n' >> $@
	@printf '    return 0;\n' >> $@
	@printf '}\n' >> $@

# Build hello
$(ELF)/hello.elf: crt0.S uart.c hello.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ crt0.S uart.c hello.c
	$(SIZE) $@

$(BIN)/hello.bin: $(ELF)/hello.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/hello.dis

# Build echo
$(ELF)/echo.elf: crt0.S uart.c echo.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ crt0.S uart.c echo.c
	$(SIZE) $@

$(BIN)/echo.bin: $(ELF)/echo.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/echo.dis

# Build Forth interpreter
$(ELF)/forth.elf: crt0.S uart.c syscalls.c forth-bare.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ crt0.S uart.c syscalls.c forth-bare.c
	$(SIZE) $@

$(BIN)/forth.bin: $(ELF)/forth.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/forth.dis

# Build fibonacci (needs FPU because printf.c uses ftoa.c)
$(ELF)/fibonacci.elf: crt0.S uart.c syscalls.c printf.c ftoa.c fibonacci.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) -march=rv32imfd $(LDFLAGS) -o $@ crt0.S uart.c syscalls.c printf.c ftoa.c fibonacci.c
	$(SIZE) $@

$(BIN)/fibonacci.bin: $(ELF)/fibonacci.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/fibonacci.dis

# Build primes (needs FPU because printf.c uses ftoa.c)
$(ELF)/primes.elf: crt0.S uart.c syscalls.c printf.c ftoa.c primes.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) -march=rv32imfd $(LDFLAGS) -o $@ crt0.S uart.c syscalls.c printf.c ftoa.c primes.c
	$(SIZE) $@

$(BIN)/primes.bin: $(ELF)/primes.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/primes.dis

# Build mandelbrot (needs floating-point)
$(ELF)/mandelbrot.elf: crt0.S uart.c syscalls.c printf.c ftoa.c mandelbrot.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) -march=rv32imfd $(LDFLAGS) -o $@ crt0.S uart.c syscalls.c printf.c ftoa.c mandelbrot.c
	$(SIZE) $@

$(BIN)/mandelbrot.bin: $(ELF)/mandelbrot.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/mandelbrot.dis

# Build malloc-test (needs FPU because printf.c uses ftoa.c)
$(ELF)/malloc-test.elf: crt0.S uart.c syscalls.c printf.c ftoa.c malloc-test.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) -march=rv32imfd $(LDFLAGS) -o $@ crt0.S uart.c syscalls.c printf.c ftoa.c malloc-test.c
	$(SIZE) $@

$(BIN)/malloc-test.bin: $(ELF)/malloc-test.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/malloc-test.dis

# Build test-runner (needs FPU for floating-point tests)
$(ELF)/test-runner.elf: crt0.S uart.c syscalls.c printf.c ftoa.c test_runner.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) -march=rv32imfd $(LDFLAGS) -o $@ crt0.S uart.c syscalls.c printf.c ftoa.c test_runner.c
	$(SIZE) $@

$(BIN)/test-runner.bin: $(ELF)/test-runner.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/test-runner.dis

# Build printf-float-test (floating-point printf testing)
$(ELF)/printf-float-test.elf: crt0.S uart.c syscalls.c printf.c ftoa.c printf-float-test.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) -march=rv32imfd $(LDFLAGS) -o $@ crt0.S uart.c syscalls.c printf.c ftoa.c printf-float-test.c
	$(SIZE) $@

$(BIN)/printf-float-test.bin: $(ELF)/printf-float-test.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/printf-float-test.dis

# Build string-test (needs FPU because printf.c now uses ftoa.c)
$(ELF)/string-test.elf: crt0.S uart.c syscalls.c printf.c ftoa.c string.c string-test.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) -march=rv32imfd $(LDFLAGS) -o $@ crt0.S uart.c syscalls.c printf.c ftoa.c string.c string-test.c
	$(SIZE) $@

$(BIN)/string-test.bin: $(ELF)/string-test.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/string-test.dis

# Build stdlib-test (needs FPU for atof and printf float support)
$(ELF)/stdlib-test.elf: crt0.S uart.c syscalls.c printf.c ftoa.c atof.c stdlib-test.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) -march=rv32imfd $(LDFLAGS) -o $@ crt0.S uart.c syscalls.c printf.c ftoa.c atof.c stdlib-test.c
	$(SIZE) $@

$(BIN)/stdlib-test.bin: $(ELF)/stdlib-test.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/stdlib-test.dis

# Build math-test (comprehensive math library test)
$(ELF)/math-test.elf: crt0.S uart.c syscalls.c printf.c ftoa.c math.c math-test.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) -march=rv32imfd $(LDFLAGS) -o $@ crt0.S uart.c syscalls.c printf.c ftoa.c math.c math-test.c
	$(SIZE) $@

$(BIN)/math-test.bin: $(ELF)/math-test.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/math-test.dis

# Build time-test (POSIX time library test using log.h)
$(ELF)/time-test.elf: crt0.S uart.c log.c time.c time-test.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) -march=rv32imfd $(LDFLAGS) -o $@ crt0.S uart.c log.c time.c time-test.c -lgcc
	$(SIZE) $@

$(BIN)/time-test.bin: $(ELF)/time-test.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/time-test.dis

# time-test-posix: alias ELF target (same as time-test.elf)
$(ELF)/time-test-posix.elf: $(ELF)/time-test.elf
	cp $< $@

# Build string-parse-test (advanced string parsing functions test)
$(ELF)/string-parse-test.elf: crt0.S uart.c syscalls.c printf.c ftoa.c string.c string-parse-test.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) -march=rv32imfd $(LDFLAGS) -o $@ crt0.S uart.c syscalls.c printf.c ftoa.c string.c string-parse-test.c
	$(SIZE) $@

$(BIN)/string-parse-test.bin: $(ELF)/string-parse-test.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/string-parse-test.dis

# Build game-of-life (Conway's Game of Life cellular automaton)
$(ELF)/game-of-life.elf: crt0.S uart.c syscalls.c printf.c ftoa.c string.c time.c game-of-life.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) -march=rv32imfd $(LDFLAGS) -o $@ crt0.S uart.c syscalls.c printf.c ftoa.c string.c time.c game-of-life.c -lgcc
	$(SIZE) $@

$(BIN)/game-of-life.bin: $(ELF)/game-of-life.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/game-of-life.dis

# Build snake-game (Snake game with AI)
$(ELF)/snake-game.elf: crt0.S uart.c syscalls.c printf.c ftoa.c time.c snake-game.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) -march=rv32imfd $(LDFLAGS) -o $@ crt0.S uart.c syscalls.c printf.c ftoa.c time.c snake-game.c -lgcc
	$(SIZE) $@

$(BIN)/snake-game.bin: $(ELF)/snake-game.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/snake-game.dis

# Build maze-generator (Recursive backtracking maze generator)
$(ELF)/maze-generator.elf: crt0.S uart.c syscalls.c printf.c ftoa.c time.c maze-generator.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) -march=rv32imfd $(LDFLAGS) -o $@ crt0.S uart.c syscalls.c printf.c ftoa.c time.c maze-generator.c -lgcc
	$(SIZE) $@

$(BIN)/maze-generator.bin: $(ELF)/maze-generator.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/maze-generator.dis

# Build falling-tiles (Falling blocks game with AI)
$(ELF)/falling-tiles.elf: crt0.S uart.c syscalls.c printf.c ftoa.c time.c falling-tiles.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) -march=rv32imfd $(LDFLAGS) -o $@ crt0.S uart.c syscalls.c printf.c ftoa.c time.c falling-tiles.c -lgcc
	$(SIZE) $@

$(BIN)/falling-tiles.bin: $(ELF)/falling-tiles.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/falling-tiles.dis

# Build matrix-rain (Matrix digital rain effect)
$(ELF)/matrix-rain.elf: crt0.S uart.c syscalls.c printf.c ftoa.c time.c matrix-rain.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) -march=rv32imfd $(LDFLAGS) -o $@ crt0.S uart.c syscalls.c printf.c ftoa.c time.c matrix-rain.c -lgcc
	$(SIZE) $@

$(BIN)/matrix-rain.bin: $(ELF)/matrix-rain.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/matrix-rain.dis

# Build debug-demo (debugging features demonstration)
$(ELF)/debug-demo.elf: crt0.S uart.c syscalls.c printf.c ftoa.c debug-demo.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) -march=rv32imfd $(LDFLAGS) -o $@ crt0.S uart.c syscalls.c printf.c ftoa.c debug-demo.c
	$(SIZE) $@

$(BIN)/debug-demo.bin: $(ELF)/debug-demo.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/debug-demo.dis

# Build profile-demo (profiling features demonstration)
$(ELF)/profile-demo.elf: crt0.S uart.c syscalls.c printf.c ftoa.c profile-demo.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) -march=rv32imfd $(LDFLAGS) -o $@ crt0.S uart.c syscalls.c printf.c ftoa.c profile-demo.c
	$(SIZE) $@

$(BIN)/profile-demo.bin: $(ELF)/profile-demo.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/profile-demo.dis

# Build rtos-demo (Mini-RTOS demonstration)
$(ELF)/rtos-demo.elf: crt0.S rtos-demo.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) -march=rv32imc_zicsr $(LDFLAGS) -o $@ crt0.S rtos-demo.c
	$(SIZE) $@

$(BIN)/rtos-demo.bin: $(ELF)/rtos-demo.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/rtos-demo.dis

# Build watchdog-test (Watchdog timer demonstration)
$(ELF)/watchdog-test.elf: crt0.S uart.c syscalls.c printf.c ftoa.c watchdog-test.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) -march=rv32imfd $(LDFLAGS) -o $@ crt0.S uart.c syscalls.c printf.c ftoa.c watchdog-test.c
	$(SIZE) $@

$(BIN)/watchdog-test.bin: $(ELF)/watchdog-test.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/watchdog-test.dis

# Build dma-test (DMA controller demonstration)
$(ELF)/dma-test.elf: crt0.S uart.c syscalls.c printf.c ftoa.c dma-test.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) -march=rv32imfd $(LDFLAGS) -o $@ crt0.S uart.c syscalls.c printf.c ftoa.c dma-test.c
	$(SIZE) $@

$(BIN)/dma-test.bin: $(ELF)/dma-test.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/dma-test.dis

# Build log-test (Host logging module demonstration)
$(ELF)/log-test.elf: crt0.S uart.c log.c log-test.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ crt0.S uart.c log.c log-test.c
	$(SIZE) $@

$(BIN)/log-test.bin: $(ELF)/log-test.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/log-test.dis

# Build vector-demo (RVV 1.0 intrinsics + inline assembly)
# Needs -march=rv32imv to enable the V extension
$(ELF)/vector-demo.elf: crt0.S uart.c log.c vector-demo.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) -march=rv32imv $(LDFLAGS) -o $@ crt0.S uart.c log.c vector-demo.c
	$(SIZE) $@

$(BIN)/vector-demo.bin: $(ELF)/vector-demo.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/vector-demo.dis

# Build matrix-demo (RVV matrix library test)
$(ELF)/matrix-demo.elf: crt0.S uart.c log.c matlib.c matrix-demo.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) -march=rv32imv $(LDFLAGS) -o $@ crt0.S uart.c log.c matlib.c matrix-demo.c
	$(SIZE) $@

$(BIN)/matrix-demo.bin: $(ELF)/matrix-demo.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/matrix-demo.dis

# Build crc32-test (CRC32 correctness and performance test)
$(ELF)/crc32-test.elf: crt0.S uart.c log.c crc32-test.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ crt0.S uart.c log.c crc32-test.c
	$(SIZE) $@

$(BIN)/crc32-test.bin: $(ELF)/crc32-test.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/crc32-test.dis

# Build sort-bench (sorting algorithm benchmark)
$(ELF)/sort-bench.elf: crt0.S uart.c log.c sort-bench.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ crt0.S uart.c log.c sort-bench.c
	$(SIZE) $@

$(BIN)/sort-bench.bin: $(ELF)/sort-bench.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/sort-bench.dis

# Build fir-filter (16-tap FIR filter, scalar + RVV via matlib)
# Needs -march=rv32imv for RVV intrinsics in matlib.c
$(ELF)/fir-filter.elf: crt0.S uart.c log.c matlib.c fir-filter.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) -march=rv32imv $(LDFLAGS) -o $@ crt0.S uart.c log.c matlib.c fir-filter.c
	$(SIZE) $@

$(BIN)/fir-filter.bin: $(ELF)/fir-filter.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/fir-filter.dis

# Build sha256-test (SHA-256 FIPS 180-4 with NIST test vectors)
$(ELF)/sha256-test.elf: crt0.S uart.c log.c sha256-test.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ crt0.S uart.c log.c sha256-test.c
	$(SIZE) $@

$(BIN)/sha256-test.bin: $(ELF)/sha256-test.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/sha256-test.dis

# Build gpio-basic (GPIO LED blink test)
$(ELF)/gpio-basic.elf: crt0.S uart.c syscalls.c printf.c ftoa.c gpio.c gpio-basic.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) -march=rv32imfd $(LDFLAGS) -o $@ crt0.S uart.c syscalls.c printf.c ftoa.c gpio.c gpio-basic.c
	$(SIZE) $@

$(BIN)/gpio-basic.bin: $(ELF)/gpio-basic.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/gpio-basic.dis

# Build gpio-interrupt (GPIO interrupt and edge detection test)
$(ELF)/gpio-interrupt.elf: crt0.S uart.c syscalls.c printf.c ftoa.c gpio.c gpio-interrupt.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) -march=rv32imfd $(LDFLAGS) -o $@ crt0.S uart.c syscalls.c printf.c ftoa.c gpio.c gpio-interrupt.c
	$(SIZE) $@

$(BIN)/gpio-interrupt.bin: $(ELF)/gpio-interrupt.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/gpio-interrupt.dis

# Build gpio-input (GPIO input with pull-up/down test)
$(ELF)/gpio-input.elf: crt0.S uart.c syscalls.c printf.c ftoa.c gpio.c gpio-input.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) -march=rv32imfd $(LDFLAGS) -o $@ crt0.S uart.c syscalls.c printf.c ftoa.c gpio.c gpio-input.c
	$(SIZE) $@

$(BIN)/gpio-input.bin: $(ELF)/gpio-input.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/gpio-input.dis

# Build spi-flash-test (SPI flash read/write test)
$(ELF)/spi-flash-test.elf: crt0.S uart.c syscalls.c printf.c ftoa.c spi.c spi-flash-test.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) -march=rv32imfd $(LDFLAGS) -o $@ crt0.S uart.c syscalls.c printf.c ftoa.c spi.c spi-flash-test.c
	$(SIZE) $@

$(BIN)/spi-flash-test.bin: $(ELF)/spi-flash-test.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/spi-flash-test.dis

# Build uart-interrupt (UART interrupt test)
$(ELF)/uart-interrupt.elf: crt0.S uart.c syscalls.c printf.c ftoa.c uart-interrupt.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) -march=rv32imfd $(LDFLAGS) -o $@ crt0.S uart.c syscalls.c printf.c ftoa.c uart-interrupt.c
	$(SIZE) $@

$(BIN)/uart-interrupt.bin: $(ELF)/uart-interrupt.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/uart-interrupt.dis

# Build i2c-test (I2C controller test with simulated devices)
$(ELF)/i2c-test.elf: crt0.S uart.c syscalls.c printf.c ftoa.c i2c.c i2c-test.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) -march=rv32imfd $(LDFLAGS) -o $@ crt0.S uart.c syscalls.c printf.c ftoa.c i2c.c i2c-test.c
	$(SIZE) $@

$(BIN)/i2c-test.bin: $(ELF)/i2c-test.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/i2c-test.dis

# Build timer-test (Hardware timer/PWM test)
$(ELF)/timer-test.elf: crt0.S uart.c syscalls.c printf.c ftoa.c timer.c timer-test.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) -march=rv32imfd $(LDFLAGS) -o $@ crt0.S uart.c syscalls.c printf.c ftoa.c timer.c timer-test.c
	$(SIZE) $@

$(BIN)/timer-test.bin: $(ELF)/timer-test.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/timer-test.dis

# Build sensor-monitor (I2C sensor monitoring demo)
$(ELF)/sensor-monitor.elf: crt0.S uart.c syscalls.c printf.c ftoa.c i2c.c timer.c gpio.c sensor-monitor.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) -march=rv32imfd $(LDFLAGS) -o $@ crt0.S uart.c syscalls.c printf.c ftoa.c i2c.c timer.c gpio.c sensor-monitor.c
	$(SIZE) $@

$(BIN)/sensor-monitor.bin: $(ELF)/sensor-monitor.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/sensor-monitor.dis

# Build pwm-fade (PWM LED fading demo)
$(ELF)/pwm-fade.elf: crt0.S uart.c syscalls.c printf.c ftoa.c timer.c gpio.c pwm-fade.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) -march=rv32imfd $(LDFLAGS) -o $@ crt0.S uart.c syscalls.c printf.c ftoa.c timer.c gpio.c pwm-fade.c
	$(SIZE) $@

$(BIN)/pwm-fade.bin: $(ELF)/pwm-fade.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/pwm-fade.dis

# Build cli (Command-Line Interface)
$(ELF)/cli.elf: crt0.S uart.c syscalls.c printf.c ftoa.c string.c gpio.c spi.c i2c.c timer.c cli.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) -march=rv32imfd $(LDFLAGS) -o $@ crt0.S uart.c syscalls.c printf.c ftoa.c string.c gpio.c spi.c i2c.c timer.c cli.c
	$(SIZE) $@

$(BIN)/cli.bin: $(ELF)/cli.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/cli.dis

# Run targets (require emulator to be built)
run-hello: $(BIN)/hello.bin
	@echo ""
	@echo "=== Running Hello World ==="
	@echo "Connect with: minicom -D /dev/pts/X (where X is shown below)"
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt --pty --wait $< 80000000

run-echo: $(BIN)/echo.bin
	@echo ""
	@echo "=== Running Echo Test ==="
	@echo "Connect with: minicom -D /dev/pts/X (where X is shown below)"
	@echo "Type characters and they will be echoed back"
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt --pty --wait $< 80000000

run-forth: $(BIN)/forth.bin
	@echo ""
	@echo "=== Running Forth Interpreter ==="
	@echo "Connect with: minicom -D /dev/pts/X (where X is shown below)"
	@echo "Try: 5 5 + ."
	@echo "     : SQUARE DUP * ;"
	@echo "     7 SQUARE ."
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt --pty --wait $< 80000000

run-fibonacci: $(BIN)/fibonacci.bin
	@echo ""
	@echo "=== Running Fibonacci Test ==="
	@echo "Connect with: minicom -D /dev/pts/X (where X is shown below)"
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt --pty --wait $< 80000000

run-primes: $(BIN)/primes.bin
	@echo ""
	@echo "=== Running Prime Number Finder ==="
	@echo "Connect with: minicom -D /dev/pts/X (where X is shown below)"
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt --pty --wait $< 80000000

run-mandelbrot: $(BIN)/mandelbrot.bin
	@echo ""
	@echo "=== Running Mandelbrot Set Generator ==="
	@echo "Connect with: minicom -D /dev/pts/X (where X is shown below)"
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt --pty --wait $< 80000000

run-malloc-test: $(BIN)/malloc-test.bin
	@echo ""
	@echo "=== Running Memory Allocator Test ==="
	@echo "Connect with: minicom -D /dev/pts/X (where X is shown below)"
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt --pty --wait $< 80000000

run-test-runner: $(BIN)/test-runner.bin
	@echo ""
	@echo "=== Running Regression Tests ==="
	@echo "Connect with: minicom -D /dev/pts/X (where X is shown below)"
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt --pty --wait $< 80000000

run-printf-float-test: $(BIN)/printf-float-test.bin
	@echo ""
	@echo "=== Running Floating-Point Printf Test ==="
	@echo "Connect with: minicom -D /dev/pts/X (where X is shown below)"
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt --pty --wait $< 80000000

run-string-test: $(BIN)/string-test.bin
	@echo ""
	@echo "=== Running String Library Test ==="
	@echo "Connect with: minicom -D /dev/pts/X (where X is shown below)"
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt --pty --wait $< 80000000

run-stdlib-test: $(BIN)/stdlib-test.bin
	@echo ""
	@echo "=== Running Standard Library Utilities Test ==="
	@echo "Connect with: minicom -D /dev/pts/X (where X is shown below)"
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt --pty --wait $< 80000000

run-math-test: $(BIN)/math-test.bin
	@echo ""
	@echo "=== Running Math Library Test ==="
	@echo "Connect with: minicom -D /dev/pts/X (where X is shown below)"
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt --pty --wait $< 80000000

run-time-test: $(ELF)/time-test.elf
	@echo ""
	@echo "=== Running Time Library Test ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt -q $(ELF)/time-test.elf
	@echo ""
	@cat $(LOG_DIR)/time-test.log 2>/dev/null || echo "(time-test.log not found)"

run-string-parse-test: $(BIN)/string-parse-test.bin
	@echo ""
	@echo "=== Running String Parsing Functions Test ==="
	@echo "Connect with: minicom -D /dev/pts/X (where X is shown below)"
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt --pty --wait $< 80000000

run-game-of-life: $(BIN)/game-of-life.bin
	@echo ""
	@echo "=== Running Conway's Game of Life ==="
	@echo "Connect with: minicom -D /dev/pts/X (where X is shown below)"
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt --pty --wait $< 80000000

run-snake-game: $(BIN)/snake-game.bin
	@echo ""
	@echo "=== Running Snake Game ==="
	@echo "Connect with: minicom -D /dev/pts/X (where X is shown below)"
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt --pty --wait $< 80000000

run-maze-generator: $(BIN)/maze-generator.bin
	@echo ""
	@echo "=== Running Maze Generator ==="
	@echo "Connect with: minicom -D /dev/pts/X (where X is shown below)"
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt --pty --wait $< 80000000

run-falling-tiles: $(BIN)/falling-tiles.bin
	@echo ""
	@echo "=== Running Tetris ==="
	@echo "Connect with: minicom -D /dev/pts/X (where X is shown below)"
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt --pty --wait $< 80000000

run-matrix-rain: $(BIN)/matrix-rain.bin
	@echo ""
	@echo "=== Running Matrix Rain ==="
	@echo "Connect with: minicom -D /dev/pts/X (where X is shown below)"
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt --pty --wait $< 80000000

run-gpio-basic: $(BIN)/gpio-basic.bin
	@echo ""
	@echo "=== Running GPIO Basic Test (LED Blink) ==="
	@echo "Connect with: minicom -D /dev/pts/X (where X is shown below)"
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt --pty --wait $< 80000000

run-gpio-interrupt: $(BIN)/gpio-interrupt.bin
	@echo ""
	@echo "=== Running GPIO Interrupt Test ==="
	@echo "Connect with: minicom -D /dev/pts/X (where X is shown below)"
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt --pty --wait $< 80000000

run-gpio-input: $(BIN)/gpio-input.bin
	@echo ""
	@echo "=== Running GPIO Input Test (Pull-up/Pull-down) ==="
	@echo "Connect with: minicom -D /dev/pts/X (where X is shown below)"
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt --pty --wait $< 80000000

run-spi-flash-test: $(BIN)/spi-flash-test.bin
	@echo ""
	@echo "=== Running SPI Flash Test ==="
	@echo "Connect with: minicom -D /dev/pts/X (where X is shown below)"
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt --pty --wait $< 80000000

run-uart-interrupt: $(BIN)/uart-interrupt.bin
	@echo ""
	@echo "=== Running UART Interrupt Test ==="
	@echo "Connect with: minicom -D /dev/pts/X (where X is shown below)"
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt --pty --wait $< 80000000

run-i2c-test: $(BIN)/i2c-test.bin
	@echo ""
	@echo "=== Running I2C Test ==="
	@echo "Connect with: minicom -D /dev/pts/X (where X is shown below)"
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt --pty --wait $< 80000000

run-timer-test: $(BIN)/timer-test.bin
	@echo ""
	@echo "=== Running Timer/PWM Test ==="
	@echo "Connect with: minicom -D /dev/pts/X (where X is shown below)"
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt --pty --wait $< 80000000

run-sensor-monitor: $(BIN)/sensor-monitor.bin
	@echo ""
	@echo "=== Running I2C Sensor Monitor Demo ==="
	@echo "Connect with: minicom -D /dev/pts/X (where X is shown below)"
	@echo "Displays real-time sensor data (temperature + accelerometer)"
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt --pty --wait $< 80000000

run-pwm-fade: $(BIN)/pwm-fade.bin
	@echo ""
	@echo "=== Running PWM LED Fade Demo ==="
	@echo "Connect with: minicom -D /dev/pts/X (where X is shown below)"
	@echo "Shows 4 channels with different fade patterns"
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt --pty --wait $< 80000000

run-cli: $(BIN)/cli.bin
	@echo ""
	@echo "=== Running Command-Line Interface ==="
	@echo "Connect with: minicom -D /dev/pts/X (where X is shown below)"
	@echo "Type 'help' for available commands"
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt --pty --wait $< 80000000

run-debug-demo: debug-demo.elf
	@echo ""
	@echo "=== Running Debug Demo ==="
	@echo ""
	@echo "This program demonstrates debugging features."
	@echo "Start with: ./bin/riscv_emulator -d programs/debug-demo.elf"
	@echo ""
	@echo "Try these debugger commands:"
	@echo "  b main                 - Break at main"
	@echo "  b recursive_sum        - Break at function"
	@echo "  c                      - Continue to breakpoint"
	@echo "  bt                     - Show call stack"
	@echo "  watch 80100000 w       - Watch memory writes"
	@echo "  info functions         - List all functions"
	@echo ""
	@read -p "Press Enter to start debugger..." dummy; \
	$(EMULATOR) $(LOGFLAGS) -d --machine qemu-virt $< 80000000

run-profile-demo: profile-demo.elf
	@echo ""
	@echo "=== Running Profile Demo ==="
	@echo ""
	@echo "This program demonstrates profiling features."
	@echo ""
	@echo "Option 1: Basic profiling"
	@echo "  ./bin/riscv_emulator --profile -max-instructions 100000 programs/profile-demo.elf"
	@echo ""
	@echo "Option 2: Flamegraph generation"
	@echo "  ./bin/riscv_emulator --flamegraph profile.fg -max-instructions 100000 programs/profile-demo.elf"
	@echo "  flamegraph.pl profile.fg > profile.svg"
	@echo "  firefox profile.svg"
	@echo ""
	@echo "Running basic profiling now..."
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --profile -max-instructions 100000 --machine qemu-virt $< 80000000

run-rtos-demo: rtos-demo.elf
	@echo ""
	@echo "=== Running Mini-RTOS Demo ==="
	@echo ""
	@echo "This program demonstrates a simple RTOS with:"
	@echo "  - Multiple concurrent tasks"
	@echo "  - Priority-based scheduling"
	@echo "  - Task delays and yielding"
	@echo "  - System tick (cooperative in this demo)"
	@echo ""
	@echo "Tasks:"
	@echo "  Task 1 (HIGH):   LED blink every 1 second"
	@echo "  Task 2 (NORMAL): Sensor monitor every 2 seconds"
	@echo "  Task 3 (IDLE):   Counts idle cycles"
	@echo ""
	@echo "Press Ctrl+C to stop."
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt -max-instructions 1000000 $< 80000000

run-watchdog-test: watchdog-test.elf
	@echo ""
	@echo "=== Running Watchdog Timer Test ==="
	@echo ""
	@echo "This program demonstrates watchdog timer functionality:"
	@echo "  - Configure watchdog with timeout period"
	@echo "  - Periodic feeding to prevent reset"
	@echo "  - Intentional timeout to trigger reset"
	@echo "  - Reset flag detection and recovery"
	@echo ""
	@echo "The watchdog is mapped at 0x10050000"
	@echo "Registers: CTRL (0x00), COUNT (0x04), RELOAD (0x08), FEED (0x0C)"
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt $< 80000000

run-dma-test: dma-test.elf
	@echo ""
	@echo "=== Running DMA Controller Test ==="
	@echo ""
	@echo "This program demonstrates DMA controller functionality:"
	@echo "  - Memory-to-memory transfers"
	@echo "  - Large bulk transfers (256 bytes)"
	@echo "  - Fixed source address (memory fill)"
	@echo "  - Multiple concurrent channels"
	@echo "  - Status flags (BUSY, DONE, ERROR)"
	@echo ""
	@echo "The DMA controller has 4 channels at 0x10060000"
	@echo "Each channel: SRC, DST, COUNT, CTRL, STATUS registers"
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt $< 80000000

run-log-test: $(BIN)/log-test.bin
	@echo ""
	@echo "=== Running Host Logging Test ==="
	@echo ""
	@echo "This program writes a log file to the host filesystem."
	@echo "Output: log-test.log (created in the current directory)"
	@echo ""
	@echo "Connect with: minicom -D /dev/pts/X (where X is shown below)"
	@echo "Or just watch: the log file appears when the program runs."
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt --pty --wait $< 80000000
	@echo ""
	@echo "Log file contents:"
	@cat $(LOG_DIR)/log-test.log 2>/dev/null || echo "(log-test.log not found)"

run-matrix-demo: $(BIN)/matrix-demo.bin
	@echo ""
	@echo "=== Running RVV Matrix Library Test ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt --pty --wait $< 80000000
	@echo ""
	@echo "Log file contents:"
	@cat $(LOG_DIR)/matrix-demo.log 2>/dev/null || echo "(matrix-demo.log not found)"

run-vector-demo: $(BIN)/vector-demo.bin
	@echo ""
	@echo "=== Running RISC-V Vector Extension Demo ==="
	@echo ""
	@echo "Demonstrates RVV 1.0 via:"
	@echo "  - C intrinsics: vadd, vmul (dot product), vmax, vmul_vx (scale)"
	@echo "  - Inline asm:   vadd, vsum (vredsum), vmac (vmul+vadd)"
	@echo ""
	@echo "Results written to vector-demo.log"
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt --pty --wait $< 80000000
	@echo ""
	@echo "Log file contents:"
	@cat $(LOG_DIR)/vector-demo.log 2>/dev/null || echo "(vector-demo.log not found)"

run-crc32-test: $(BIN)/crc32-test.bin
	@echo ""
	@echo "=== Running CRC32 Test ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt --pty --wait $< 80000000
	@echo ""
	@echo "Log file contents:"
	@cat $(LOG_DIR)/crc32-test.log 2>/dev/null || echo "(crc32-test.log not found)"

run-sort-bench: $(BIN)/sort-bench.bin
	@echo ""
	@echo "=== Running Sorting Algorithm Benchmark ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt --pty --wait $< 80000000
	@echo ""
	@echo "Log file contents:"
	@cat $(LOG_DIR)/sort-bench.log 2>/dev/null || echo "(sort-bench.log not found)"

run-fir-filter: $(BIN)/fir-filter.bin
	@echo ""
	@echo "=== Running FIR Filter Test (scalar + RVV) ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt --pty --wait $< 80000000
	@echo ""
	@echo "Log file contents:"
	@cat $(LOG_DIR)/fir-filter.log 2>/dev/null || echo "(fir-filter.log not found)"

run-sha256-test: $(BIN)/sha256-test.bin
	@echo ""
	@echo "=== Running SHA-256 Test (FIPS 180-4) ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt --pty --wait $< 80000000
	@echo ""
	@echo "Log file contents:"
	@cat $(LOG_DIR)/sha256-test.log 2>/dev/null || echo "(sha256-test.log not found)"

# Build fp-math-test (float/double FPU exercise, RV32IMFD)
$(ELF)/fp-math-test.elf: crt0.S uart.c log.c fp-math-test.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) -march=rv32imfd $(LDFLAGS) -o $@ crt0.S uart.c log.c fp-math-test.c
	$(SIZE) $@

$(BIN)/fp-math-test.bin: $(ELF)/fp-math-test.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/fp-math-test.dis

run-fp-math-test: $(BIN)/fp-math-test.bin
	@echo ""
	@echo "=== Running FP Math Test (RV32IMFD) ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt --pty --wait $< 80000000
	@echo ""
	@echo "Log file contents:"
	@cat $(LOG_DIR)/fp-math-test.log 2>/dev/null || echo "(fp-math-test.log not found)"

# Build rvv-advanced (advanced RVV: e8/e16/m2, bitwise, shifts, masked ops)
$(ELF)/rvv-advanced.elf: crt0.S uart.c log.c rvv-advanced.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) -march=rv32imv $(LDFLAGS) -o $@ crt0.S uart.c log.c rvv-advanced.c
	$(SIZE) $@

$(BIN)/rvv-advanced.bin: $(ELF)/rvv-advanced.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/rvv-advanced.dis

run-rvv-advanced: $(BIN)/rvv-advanced.bin
	@echo ""
	@echo "=== Running RVV Advanced Test ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt --pty --wait $< 80000000
	@echo ""
	@echo "Log file contents:"
	@cat $(LOG_DIR)/rvv-advanced.log 2>/dev/null || echo "(rvv-advanced.log not found)"

# Build string-ops (string/memory function test)
$(ELF)/string-ops.elf: crt0.S uart.c log.c syscalls.c string.c string-ops.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ crt0.S uart.c log.c syscalls.c string.c string-ops.c
	$(SIZE) $@

$(BIN)/string-ops.bin: $(ELF)/string-ops.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/string-ops.dis

run-string-ops: $(BIN)/string-ops.bin
	@echo ""
	@echo "=== Running String Operations Test ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt --pty --wait $< 80000000
	@echo ""
	@echo "Log file contents:"
	@cat $(LOG_DIR)/string-ops.log 2>/dev/null || echo "(string-ops.log not found)"

# Build chacha20 (ChaCha20 cipher, RFC 7539 test vectors)
$(ELF)/chacha20.elf: crt0.S uart.c log.c chacha20.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ crt0.S uart.c log.c chacha20.c
	$(SIZE) $@

$(BIN)/chacha20.bin: $(ELF)/chacha20.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/chacha20.dis

run-chacha20: $(BIN)/chacha20.bin
	@echo ""
	@echo "=== Running ChaCha20 Test (RFC 7539) ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt --pty --wait $< 80000000
	@echo ""
	@echo "Log file contents:"
	@cat $(LOG_DIR)/chacha20.log 2>/dev/null || echo "(chacha20.log not found)"

# Build rvv-float (RVV 1.0 floating-point vector ops: vfadd, vfmul, vfsqrt, vfredosum, etc.)
# Needs -march=rv32imfdv for both FP and V extensions
$(ELF)/rvv-float.elf: crt0.S uart.c log.c rvv-float.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) -march=rv32imfdv $(LDFLAGS) -o $@ crt0.S uart.c log.c rvv-float.c
	$(SIZE) $@

$(BIN)/rvv-float.bin: $(ELF)/rvv-float.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/rvv-float.dis

run-rvv-float: $(BIN)/rvv-float.bin
	@echo ""
	@echo "=== Running RVV Float Test (RV32IMFDV) ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt --pty --wait $< 80000000
	@echo ""
	@echo "Log file contents:"
	@cat $(LOG_DIR)/rvv-float.log 2>/dev/null || echo "(rvv-float.log not found)"

# Build trap-test (exception/trap handling: ecall, ebreak, mtvec, mret)
# Needs _zicsr for CSR access (csrr, csrw)
$(ELF)/trap-test.elf: crt0.S uart.c log.c trap-test.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) -march=rv32imc_zicsr $(LDFLAGS) -o $@ crt0.S uart.c log.c trap-test.c
	$(SIZE) $@

$(BIN)/trap-test.bin: $(ELF)/trap-test.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/trap-test.dis

run-trap-test: $(BIN)/trap-test.bin
	@echo ""
	@echo "=== Running Trap/Exception Handling Test ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt --pty --wait $< 80000000
	@echo ""
	@echo "Log file contents:"
	@cat $(LOG_DIR)/trap-test.log 2>/dev/null || echo "(trap-test.log not found)"

# Build m-ext-test (M extension: mul/mulh/div/rem edge cases)
$(ELF)/m-ext-test.elf: crt0.S uart.c log.c m-ext-test.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ crt0.S uart.c log.c m-ext-test.c
	$(SIZE) $@

$(BIN)/m-ext-test.bin: $(ELF)/m-ext-test.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/m-ext-test.dis

run-m-ext-test: $(BIN)/m-ext-test.bin
	@echo ""
	@echo "=== Running M-Extension Test (mul/div/rem) ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt --pty --wait $< 80000000
	@echo ""
	@echo "Log file contents:"
	@cat $(LOG_DIR)/m-ext-test.log 2>/dev/null || echo "(m-ext-test.log not found)"

# Build lz77 (LZSS compress/decompress with round-trip verification)
$(ELF)/lz77.elf: crt0.S uart.c log.c syscalls.c lz77.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ crt0.S uart.c log.c syscalls.c lz77.c
	$(SIZE) $@

$(BIN)/lz77.bin: $(ELF)/lz77.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/lz77.dis

run-lz77: $(BIN)/lz77.bin
	@echo ""
	@echo "=== Running LZ77/LZSS Compression Test ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt --pty --wait $< 80000000
	@echo ""
	@echo "Log file contents:"
	@cat $(LOG_DIR)/lz77.log 2>/dev/null || echo "(lz77.log not found)"

# Build branch-test (all 6 branch instructions with edge cases)
$(ELF)/branch-test.elf: crt0.S uart.c log.c branch-test.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ crt0.S uart.c log.c branch-test.c
	$(SIZE) $@

$(BIN)/branch-test.bin: $(ELF)/branch-test.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/branch-test.dis

run-branch-test: $(BIN)/branch-test.bin
	@echo ""
	@echo "=== Running Branch Instruction Test ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt --pty --wait $< 80000000
	@echo ""
	@cat $(LOG_DIR)/branch-test.log 2>/dev/null || echo "(branch-test.log not found)"

# Build load-store-test (LB/LBU/LH/LHU/LW/SB/SH/SW with sign-extension checks)
$(ELF)/load-store-test.elf: crt0.S uart.c log.c load-store-test.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ crt0.S uart.c log.c load-store-test.c
	$(SIZE) $@

$(BIN)/load-store-test.bin: $(ELF)/load-store-test.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/load-store-test.dis

run-load-store-test: $(BIN)/load-store-test.bin
	@echo ""
	@echo "=== Running Load/Store Instruction Test ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt --pty --wait $< 80000000
	@echo ""
	@cat $(LOG_DIR)/load-store-test.log 2>/dev/null || echo "(load-store-test.log not found)"

# Build csr-test (CSR instructions: mscratch, mhartid, misa, cycle, instret, fcsr)
# Needs _zicsr + _f for FCSR
$(ELF)/csr-test.elf: crt0.S uart.c log.c csr-test.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) -march=rv32imfd_zicsr $(LDFLAGS) -o $@ crt0.S uart.c log.c csr-test.c
	$(SIZE) $@

$(BIN)/csr-test.bin: $(ELF)/csr-test.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/csr-test.dis

run-csr-test: $(BIN)/csr-test.bin
	@echo ""
	@echo "=== Running CSR Instruction Test ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt --pty --wait $< 80000000
	@echo ""
	@cat $(LOG_DIR)/csr-test.log 2>/dev/null || echo "(csr-test.log not found)"

# Build rvv-strided (vlse32/vsse32 strided + vloxei32 indexed gather)
$(ELF)/rvv-strided.elf: crt0.S uart.c log.c rvv-strided.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) -march=rv32imv $(LDFLAGS) -o $@ crt0.S uart.c log.c rvv-strided.c
	$(SIZE) $@

$(BIN)/rvv-strided.bin: $(ELF)/rvv-strided.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/rvv-strided.dis

run-rvv-strided: $(BIN)/rvv-strided.bin
	@echo ""
	@echo "=== Running RVV Strided/Indexed Load-Store Test ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt --pty --wait $< 80000000
	@echo ""
	@cat $(LOG_DIR)/rvv-strided.log 2>/dev/null || echo "(rvv-strided.log not found)"

# Build float-classify (fclass.s/d + FCSR rounding modes)
$(ELF)/float-classify.elf: crt0.S uart.c log.c float-classify.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) -march=rv32imfd $(LDFLAGS) -o $@ crt0.S uart.c log.c float-classify.c
	$(SIZE) $@

$(BIN)/float-classify.bin: $(ELF)/float-classify.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/float-classify.dis

run-float-classify: $(BIN)/float-classify.bin
	@echo ""
	@echo "=== Running Float Classify + Rounding Mode Test ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt --pty --wait $< 80000000
	@echo ""
	@cat $(LOG_DIR)/float-classify.log 2>/dev/null || echo "(float-classify.log not found)"

# Build aes128 (AES-128 with NIST test vectors)
$(ELF)/aes128.elf: crt0.S uart.c log.c aes128.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ crt0.S uart.c log.c aes128.c
	$(SIZE) $@

$(BIN)/aes128.bin: $(ELF)/aes128.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/aes128.dis

run-aes128: $(BIN)/aes128.bin
	@echo ""
	@echo "=== Running AES-128 Test (NIST vectors) ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt --pty --wait $< 80000000
	@echo ""
	@cat $(LOG_DIR)/aes128.log 2>/dev/null || echo "(aes128.log not found)"

# Build base64 (encode/decode round-trip)
$(ELF)/base64.elf: crt0.S uart.c log.c base64.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ crt0.S uart.c log.c base64.c
	$(SIZE) $@

$(BIN)/base64.bin: $(ELF)/base64.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/base64.dis

run-base64: $(BIN)/base64.bin
	@echo ""
	@echo "=== Running Base64 Encode/Decode Test ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt --pty --wait $< 80000000
	@echo ""
	@cat $(LOG_DIR)/base64.log 2>/dev/null || echo "(base64.log not found)"

# Build huffman (Huffman tree + encode/decode)
$(ELF)/huffman.elf: crt0.S uart.c log.c syscalls.c string.c huffman.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ crt0.S uart.c log.c syscalls.c string.c huffman.c
	$(SIZE) $@

$(BIN)/huffman.bin: $(ELF)/huffman.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/huffman.dis

run-huffman: $(BIN)/huffman.bin
	@echo ""
	@echo "=== Running Huffman Coding Test ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt --pty --wait $< 80000000
	@echo ""
	@cat $(LOG_DIR)/huffman.log 2>/dev/null || echo "(huffman.log not found)"

# Build zbb-test (Zbb/Zbs scalar bit-manipulation instructions)
$(ELF)/zbb-test.elf: crt0.S uart.c log.c syscalls.c zbb-test.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) -march=rv32imc_zbb_zbs -mabi=ilp32 $(LDFLAGS) -o $@ crt0.S uart.c log.c syscalls.c zbb-test.c
	$(SIZE) $@

$(BIN)/zbb-test.bin: $(ELF)/zbb-test.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/zbb-test.dis

run-zbb-test: $(BIN)/zbb-test.bin
	@echo ""
	@echo "=== Running Zbb/Zbs Bit-Manipulation Test ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt -q $< 80000000
	@echo ""
	@cat $(LOG_DIR)/zbb-test.log 2>/dev/null || echo "(zbb-test.log not found)"

# Build fixedpoint-test (Q15/Q16 fixed-point arithmetic)
$(ELF)/fixedpoint-test.elf: crt0.S uart.c log.c syscalls.c fixedpoint-test.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ crt0.S uart.c log.c syscalls.c fixedpoint-test.c
	$(SIZE) $@

$(BIN)/fixedpoint-test.bin: $(ELF)/fixedpoint-test.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/fixedpoint-test.dis

run-fixedpoint-test: $(BIN)/fixedpoint-test.bin
	@echo ""
	@echo "=== Running Fixed-Point Arithmetic Test ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt -q $< 80000000
	@echo ""
	@cat $(LOG_DIR)/fixedpoint-test.log 2>/dev/null || echo "(fixedpoint-test.log not found)"

# Build atomic-test (RV32A atomic memory operations)
$(ELF)/atomic-test.elf: crt0.S uart.c log.c syscalls.c atomic-test.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) -march=rv32ima -mabi=ilp32 $(LDFLAGS) -o $@ crt0.S uart.c log.c syscalls.c atomic-test.c
	$(SIZE) $@

$(BIN)/atomic-test.bin: $(ELF)/atomic-test.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/atomic-test.dis

run-atomic-test: $(BIN)/atomic-test.bin
	@echo ""
	@echo "=== Running Atomic Memory Operations Test ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt -q $< 80000000
	@echo ""
	@cat $(LOG_DIR)/atomic-test.log 2>/dev/null || echo "(atomic-test.log not found)"

# Build clmul-test (Zbkc CLMUL/CLMULH + Zbkx XPERM4/XPERM8)
$(ELF)/clmul-test.elf: crt0.S uart.c log.c syscalls.c clmul-test.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) -march=rv32imc_zbkc_zbkx -mabi=ilp32 $(LDFLAGS) -o $@ crt0.S uart.c log.c syscalls.c clmul-test.c
	$(SIZE) $@

$(BIN)/clmul-test.bin: $(ELF)/clmul-test.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/clmul-test.dis

run-clmul-test: $(BIN)/clmul-test.bin
	@echo ""
	@echo "=== Running CLMUL/XPERM (Zbkc/Zbkx) Test ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt -q $< 80000000
	@echo ""
	@cat $(LOG_DIR)/clmul-test.log 2>/dev/null || echo "(clmul-test.log not found)"

# Build gf256-test (GF(2^8) arithmetic, uses CLMUL for fast multiply)
$(ELF)/gf256-test.elf: crt0.S uart.c log.c syscalls.c gf256-test.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) -march=rv32imc_zbkc -mabi=ilp32 $(LDFLAGS) -o $@ crt0.S uart.c log.c syscalls.c gf256-test.c
	$(SIZE) $@

$(BIN)/gf256-test.bin: $(ELF)/gf256-test.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/gf256-test.dis

run-gf256-test: $(BIN)/gf256-test.bin
	@echo ""
	@echo "=== Running GF(2^8) Arithmetic Test ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt -q $< 80000000
	@echo ""
	@cat $(LOG_DIR)/gf256-test.log 2>/dev/null || echo "(gf256-test.log not found)"

# Build pid-test (Q16.16 PID controller)
$(ELF)/pid-test.elf: crt0.S uart.c log.c syscalls.c pid-test.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ crt0.S uart.c log.c syscalls.c pid-test.c
	$(SIZE) $@

$(BIN)/pid-test.bin: $(ELF)/pid-test.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/pid-test.dis

run-pid-test: $(BIN)/pid-test.bin
	@echo ""
	@echo "=== Running PID Controller (Q16.16) Test ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt -q $< 80000000
	@echo ""
	@cat $(LOG_DIR)/pid-test.log 2>/dev/null || echo "(pid-test.log not found)"

# Build lfsr-test (LFSR PRNG: Fibonacci+Galois, period, balance, Zbb CPOP/BEXT)
$(ELF)/lfsr-test.elf: crt0.S uart.c log.c syscalls.c lfsr-test.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) -march=rv32imc_zbb_zbs -mabi=ilp32 $(LDFLAGS) -o $@ crt0.S uart.c log.c syscalls.c lfsr-test.c
	$(SIZE) $@

$(BIN)/lfsr-test.bin: $(ELF)/lfsr-test.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/lfsr-test.dis

run-lfsr-test: $(BIN)/lfsr-test.bin
	@echo ""
	@echo "=== Running LFSR Test ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt -q $< 80000000
	@echo ""
	@cat $(LOG_DIR)/lfsr-test.log 2>/dev/null || echo "(lfsr-test.log not found)"

# Build iir-test (IIR Direct Form II biquad, Q16.16)
$(ELF)/iir-test.elf: crt0.S uart.c log.c syscalls.c iir-test.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ crt0.S uart.c log.c syscalls.c iir-test.c
	$(SIZE) $@

$(BIN)/iir-test.bin: $(ELF)/iir-test.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/iir-test.dis

run-iir-test: $(BIN)/iir-test.bin
	@echo ""
	@echo "=== Running IIR Biquad Filter Test ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt -q $< 80000000
	@echo ""
	@cat $(LOG_DIR)/iir-test.log 2>/dev/null || echo "(iir-test.log not found)"

# Build fft-test (radix-2 DIT FFT, N=8, Q16.16)
$(ELF)/fft-test.elf: crt0.S uart.c log.c syscalls.c fft-test.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ crt0.S uart.c log.c syscalls.c fft-test.c
	$(SIZE) $@

$(BIN)/fft-test.bin: $(ELF)/fft-test.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/fft-test.dis

run-fft-test: $(BIN)/fft-test.bin
	@echo ""
	@echo "=== Running FFT Test (N=8, Q16.16) ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt -q $< 80000000
	@echo ""
	@cat $(LOG_DIR)/fft-test.log 2>/dev/null || echo "(fft-test.log not found)"

# Build montgomery-test (Montgomery modular multiply + modexp, RV32M MULHU)
$(ELF)/montgomery-test.elf: crt0.S uart.c log.c syscalls.c montgomery-test.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ crt0.S uart.c log.c syscalls.c montgomery-test.c
	$(SIZE) $@

$(BIN)/montgomery-test.bin: $(ELF)/montgomery-test.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/montgomery-test.dis

run-montgomery-test: $(BIN)/montgomery-test.bin
	@echo ""
	@echo "=== Running Montgomery Multiplication Test ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt -q $< 80000000
	@echo ""
	@cat $(LOG_DIR)/montgomery-test.log 2>/dev/null || echo "(montgomery-test.log not found)"

# Build reed-solomon-test (RS ECC over GF(2^8))
$(ELF)/reed-solomon-test.elf: crt0.S uart.c log.c syscalls.c reed-solomon-test.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ crt0.S uart.c log.c syscalls.c reed-solomon-test.c
	$(SIZE) $@

$(BIN)/reed-solomon-test.bin: $(ELF)/reed-solomon-test.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/reed-solomon-test.dis

run-reed-solomon-test: $(BIN)/reed-solomon-test.bin
	@echo ""
	@echo "=== Running Reed-Solomon ECC Test ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt -q $< 80000000
	@echo ""
	@cat $(LOG_DIR)/reed-solomon-test.log 2>/dev/null || echo "(reed-solomon-test.log not found)"

# Build zba-test (Zba address-generation: sh1add/sh2add/sh3add)
$(ELF)/zba-test.elf: crt0.S uart.c log.c syscalls.c zba-test.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) -march=rv32imc_zba -mabi=ilp32 $(LDFLAGS) -o $@ crt0.S uart.c log.c syscalls.c zba-test.c
	$(SIZE) $@

$(BIN)/zba-test.bin: $(ELF)/zba-test.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/zba-test.dis

run-zba-test: $(BIN)/zba-test.bin
	@echo ""
	@echo "=== Running Zba Address-Generation Test ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt -q $< 80000000
	@echo ""
	@cat $(LOG_DIR)/zba-test.log 2>/dev/null || echo "(zba-test.log not found)"

# Build ecc-test (Elliptic curve over F_17, y^2=x^3+2x+2, order=19)
$(ELF)/ecc-test.elf: crt0.S uart.c log.c syscalls.c ecc-test.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ crt0.S uart.c log.c syscalls.c ecc-test.c
	$(SIZE) $@

$(BIN)/ecc-test.bin: $(ELF)/ecc-test.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/ecc-test.dis

run-ecc-test: $(BIN)/ecc-test.bin
	@echo ""
	@echo "=== Running ECC Test ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt -q $< 80000000
	@echo ""
	@cat $(LOG_DIR)/ecc-test.log 2>/dev/null || echo "(ecc-test.log not found)"

# Build rs-correct-test (Reed-Solomon BM+Chien+Forney error correction over GF(2^8))
$(ELF)/rs-correct-test.elf: crt0.S uart.c log.c syscalls.c rs-correct-test.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ crt0.S uart.c log.c syscalls.c rs-correct-test.c
	$(SIZE) $@

$(BIN)/rs-correct-test.bin: $(ELF)/rs-correct-test.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/rs-correct-test.dis

run-rs-correct-test: $(BIN)/rs-correct-test.bin
	@echo ""
	@echo "=== Running RS Error Correction Test ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt -q $< 80000000
	@echo ""
	@cat $(LOG_DIR)/rs-correct-test.log 2>/dev/null || echo "(rs-correct-test.log not found)"

# Build ntt-test (NTT over Z_p, p=12289=3*2^12+1)
$(ELF)/ntt-test.elf: crt0.S uart.c log.c syscalls.c ntt-test.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ crt0.S uart.c log.c syscalls.c ntt-test.c
	$(SIZE) $@

$(BIN)/ntt-test.bin: $(ELF)/ntt-test.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/ntt-test.dis

run-ntt-test: $(BIN)/ntt-test.bin
	@echo ""
	@echo "=== Running NTT Test ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt -q $< 80000000
	@echo ""
	@cat $(LOG_DIR)/ntt-test.log 2>/dev/null || echo "(ntt-test.log not found)"

# Build chacha20-poly1305 (ChaCha20-Poly1305 AEAD, RFC 8439)
$(ELF)/chacha20-poly1305.elf: crt0.S uart.c log.c chacha20-poly1305.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ crt0.S uart.c log.c chacha20-poly1305.c
	$(SIZE) $@

$(BIN)/chacha20-poly1305.bin: $(ELF)/chacha20-poly1305.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/chacha20-poly1305.dis

run-chacha20-poly1305: $(BIN)/chacha20-poly1305.bin
	@echo ""
	@echo "=== Running ChaCha20-Poly1305 AEAD Test (RFC 8439) ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt -q $< 80000000
	@echo ""
	@cat $(LOG_DIR)/chacha20-poly1305.log 2>/dev/null || echo "(chacha20-poly1305.log not found)"

# Build aes-gcm (AES-128-GCM authenticated encryption, NIST SP 800-38D)
$(ELF)/aes-gcm.elf: crt0.S uart.c log.c aes-gcm.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ crt0.S uart.c log.c aes-gcm.c
	$(SIZE) $@

$(BIN)/aes-gcm.bin: $(ELF)/aes-gcm.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/aes-gcm.dis

run-aes-gcm: $(BIN)/aes-gcm.bin
	@echo ""
	@echo "=== Running AES-128-GCM Test (NIST SP 800-38D) ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt -q $< 80000000
	@echo ""
	@cat $(LOG_DIR)/aes-gcm.log 2>/dev/null || echo "(aes-gcm.log not found)"

# Build blake2s (BLAKE2s cryptographic hash, RFC 7693)
$(ELF)/blake2s.elf: crt0.S uart.c log.c blake2s.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ crt0.S uart.c log.c blake2s.c
	$(SIZE) $@

$(BIN)/blake2s.bin: $(ELF)/blake2s.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/blake2s.dis

run-blake2s: $(BIN)/blake2s.bin
	@echo ""
	@echo "=== Running BLAKE2s Test (RFC 7693) ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt -q $< 80000000
	@echo ""
	@cat $(LOG_DIR)/blake2s.log 2>/dev/null || echo "(blake2s.log not found)"

# Build sha3 (SHA-3/Keccak-256, FIPS 202)
$(ELF)/sha3.elf: crt0.S uart.c log.c sha3.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ crt0.S uart.c log.c sha3.c
	$(SIZE) $@

$(BIN)/sha3.bin: $(ELF)/sha3.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/sha3.dis

run-sha3: $(BIN)/sha3.bin
	@echo ""
	@echo "=== Running SHA-3/Keccak-256 Test (FIPS 202) ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt -q $< 80000000
	@echo ""
	@cat $(LOG_DIR)/sha3.log 2>/dev/null || echo "(sha3.log not found)"

# Build viterbi (K=7 rate-1/2 Viterbi decoder, soft-decision)
$(ELF)/viterbi.elf: crt0.S uart.c log.c viterbi.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ crt0.S uart.c log.c viterbi.c
	$(SIZE) $@

$(BIN)/viterbi.bin: $(ELF)/viterbi.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/viterbi.dis

run-viterbi: $(BIN)/viterbi.bin
	@echo ""
	@echo "=== Running Viterbi K=7 Decoder Test ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt -q $< 80000000
	@echo ""
	@cat $(LOG_DIR)/viterbi.log 2>/dev/null || echo "(viterbi.log not found)"

# Build fft-conv (FFT-based linear convolution via overlap-add, Q16.16)
$(ELF)/fft-conv.elf: crt0.S uart.c log.c fft-conv.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ crt0.S uart.c log.c fft-conv.c
	$(SIZE) $@

$(BIN)/fft-conv.bin: $(ELF)/fft-conv.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/fft-conv.dis

run-fft-conv: $(BIN)/fft-conv.bin
	@echo ""
	@echo "=== Running FFT Convolution Test (Q16.16, Overlap-Add) ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt -q $< 80000000
	@echo ""
	@cat $(LOG_DIR)/fft-conv.log 2>/dev/null || echo "(fft-conv.log not found)"

# Build scanf-test (sprintf/snprintf/sscanf/strtol/strtoul/strtod)
$(ELF)/scanf-test.elf: crt0.S uart.c log.c syscalls.c printf.c ftoa.c atof.c scanf-test.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) -march=rv32imfd -mabi=ilp32d $(LDFLAGS) -o $@ crt0.S uart.c log.c syscalls.c printf.c ftoa.c atof.c scanf-test.c
	$(SIZE) $@

$(BIN)/scanf-test.bin: $(ELF)/scanf-test.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/scanf-test.dis

scanf-test: $(BIN)/scanf-test.bin

run-scanf-test: $(BIN)/scanf-test.bin
	@echo ""
	@echo "=== Running sprintf/snprintf/sscanf/strtol/strtoul/strtod Test ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt -q $< 80000000
	@echo ""
	@cat $(LOG_DIR)/scanf-test.log 2>/dev/null || echo "(scanf-test.log not found)"

# Build rtos-test (cooperative scheduler: yield, sleep, task exit)
$(ELF)/rtos-test.elf: crt0.S uart.c log.c rtos.c rtos-test.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ crt0.S uart.c log.c rtos.c rtos-test.c
	$(SIZE) $@

$(BIN)/rtos-test.bin: $(ELF)/rtos-test.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/rtos-test.dis

rtos-test: $(BIN)/rtos-test.bin

# Build prtos-test (preemptive scheduler: timer interrupt, mret context switch)
$(ELF)/prtos-test.elf: crt0.S uart.c log.c prtos_trap.S prtos.c prtos-test.c hello.ld | $(ELF)
	$(CC) -march=rv32imc_zicsr -mabi=ilp32 -nostdlib -nostartfiles -fno-builtin -O2 -g -Wall $(LDFLAGS) -o $@ crt0.S uart.c log.c prtos_trap.S prtos.c prtos-test.c
	$(SIZE) $@

$(BIN)/prtos-test.bin: $(ELF)/prtos-test.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/prtos-test.dis

prtos-test: $(BIN)/prtos-test.bin

# Build prtos2-test (mutex, mq, priority, stack canary, sleep_until)
$(ELF)/prtos2-test.elf: crt0.S uart.c log.c prtos_trap.S prtos.c prtos2-test.c hello.ld | $(ELF)
	$(CC) -march=rv32imc_zicsr -mabi=ilp32 -nostdlib -nostartfiles -fno-builtin -O2 -g -Wall $(LDFLAGS) -o $@ crt0.S uart.c log.c prtos_trap.S prtos.c prtos2-test.c
	$(SIZE) $@

$(BIN)/prtos2-test.bin: $(ELF)/prtos2-test.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/prtos2-test.dis

prtos2-test: $(BIN)/prtos2-test.bin

run-prtos2-test: $(BIN)/prtos2-test.bin
	@echo "=== Running Preemptive RTOS Extension Test (mutex/mq/priority/canary/sleep_until) ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt -q out/bin/prtos2-test.bin 80000000
	@cat $(LOG_DIR)/prtos2-test.log 2>/dev/null || echo "(prtos2-test.log not found)"

# Build fat12-test (FAT12 filesystem on SPI flash)
$(ELF)/fat12-test.elf: crt0.S uart.c log.c string.c syscalls.c spi.c fat12.c fat12-test.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ crt0.S uart.c log.c string.c syscalls.c spi.c fat12.c fat12-test.c
	$(SIZE) $@

$(BIN)/fat12-test.bin: $(ELF)/fat12-test.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/fat12-test.dis

fat12-test: $(BIN)/fat12-test.bin

run-fat12-test: $(BIN)/fat12-test.bin
	@echo ""
	@echo "=== Running FAT12 Filesystem Test ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt -q $< 80000000
	@echo ""
	@cat $(LOG_DIR)/fat12-test.log 2>/dev/null || echo "(fat12-test.log not found)"

# Build modbus-test (MODBUS RTU framing + function codes)
$(ELF)/modbus-test.elf: crt0.S uart.c log.c string.c syscalls.c modbus.c modbus-test.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ crt0.S uart.c log.c string.c syscalls.c modbus.c modbus-test.c
	$(SIZE) $@

$(BIN)/modbus-test.bin: $(ELF)/modbus-test.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/modbus-test.dis

modbus-test: $(BIN)/modbus-test.bin

run-modbus-test: $(BIN)/modbus-test.bin
	@echo ""
	@echo "=== Running MODBUS RTU Test ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt -q $< 80000000
	@echo ""
	@cat $(LOG_DIR)/modbus-test.log 2>/dev/null || echo "(modbus-test.log not found)"

# Build deflate-test (RFC 1951 deflate + RFC 1950 zlib decompressor)
$(ELF)/deflate-test.elf: crt0.S uart.c log.c string.c syscalls.c deflate.c deflate-test.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ crt0.S uart.c log.c string.c syscalls.c deflate.c deflate-test.c
	$(SIZE) $@

$(BIN)/deflate-test.bin: $(ELF)/deflate-test.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/deflate-test.dis

deflate-test: $(BIN)/deflate-test.bin

run-deflate-test: $(BIN)/deflate-test.bin
	@echo ""
	@echo "=== Running Deflate/zlib Test ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt -q $< 80000000
	@echo ""
	@cat $(LOG_DIR)/deflate-test.log 2>/dev/null || echo "(deflate-test.log not found)"

# Build setjmp-test (setjmp / longjmp implementation)
$(ELF)/setjmp-test.elf: crt0.S setjmp.S log.c setjmp-test.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ crt0.S setjmp.S log.c setjmp-test.c
	$(SIZE) $@

$(BIN)/setjmp-test.bin: $(ELF)/setjmp-test.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/setjmp-test.dis

setjmp-test: $(BIN)/setjmp-test.bin

run-setjmp-test: $(BIN)/setjmp-test.bin
	@echo ""
	@echo "=== Running setjmp/longjmp Test ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt -q $< 80000000
	@echo ""
	@cat $(LOG_DIR)/setjmp-test.log 2>/dev/null || echo "(setjmp-test.log not found)"

# Build smode-test (Supervisor mode + SBI interface)
# Uses crt0-smode.S (M-mode startup that mrets to S-mode) instead of crt0.S
$(ELF)/smode-test.elf: crt0-smode.S log.c smode-test.c hello.ld | $(ELF)
	$(CC) -march=rv32imc_zicsr -mabi=$(ABI) -nostdlib -nostartfiles \
	    -fno-builtin -O2 -g -Wall $(LDFLAGS) -o $@ crt0-smode.S log.c smode-test.c
	$(SIZE) $@

$(BIN)/smode-test.bin: $(ELF)/smode-test.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/smode-test.dis

smode-test: $(BIN)/smode-test.bin

run-smode-test: $(BIN)/smode-test.bin
	@echo ""
	@echo "=== Running Supervisor Mode / SBI Test ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt -q $< 80000000
	@echo ""
	@cat $(LOG_DIR)/smode-test.log 2>/dev/null || echo "(smode-test.log not found)"

# Build umode-test (User privilege mode + delegation tests)
# Uses crt0-smode.S so M-mode transitions to S-mode before test; test then
# transitions further to U-mode using SRET.
$(ELF)/umode-test.elf: crt0-smode.S log.c umode-test.c hello.ld | $(ELF)
	$(CC) -march=rv32imc_zicsr -mabi=$(ABI) -nostdlib -nostartfiles \
	    -fno-builtin -O2 -g -Wall $(LDFLAGS) -o $@ crt0-smode.S log.c umode-test.c
	$(SIZE) $@

$(BIN)/umode-test.bin: $(ELF)/umode-test.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/umode-test.dis

umode-test: $(BIN)/umode-test.bin

run-umode-test: $(BIN)/umode-test.bin
	@echo ""
	@echo "=== Running User Mode Test ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt -q $< 80000000
	@echo ""
	@cat $(LOG_DIR)/umode-test.log 2>/dev/null || echo "(umode-test.log not found)"

# Build hmac-sha256-test (HMAC-SHA256 per RFC 2104 with RFC 4231 test vectors)
$(ELF)/hmac-sha256-test.elf: crt0.S uart.c log.c hmac-sha256-test.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ crt0.S uart.c log.c hmac-sha256-test.c
	$(SIZE) $@

$(BIN)/hmac-sha256-test.bin: $(ELF)/hmac-sha256-test.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/hmac-sha256-test.dis

hmac-sha256-test: $(BIN)/hmac-sha256-test.bin

run-hmac-sha256-test: $(BIN)/hmac-sha256-test.bin
	@echo ""
	@echo "=== Running HMAC-SHA256 Test (RFC 2104 / RFC 4231) ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt -q $< 80000000
	@echo ""
	@cat $(LOG_DIR)/hmac-sha256-test.log 2>/dev/null || echo "(hmac-sha256-test.log not found)"

# Build aes-modes-test (AES-128 CBC/CTR mode tests, NIST SP 800-38A)
$(ELF)/aes-modes-test.elf: crt0.S uart.c log.c aes-modes-test.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ crt0.S uart.c log.c aes-modes-test.c
	$(SIZE) $@

$(BIN)/aes-modes-test.bin: $(ELF)/aes-modes-test.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/aes-modes-test.dis

aes-modes-test: $(BIN)/aes-modes-test.bin

run-aes-modes-test: $(BIN)/aes-modes-test.bin
	@echo ""
	@echo "=== Running AES-128 CBC/CTR Mode Tests (NIST SP 800-38A) ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt -q $< 80000000
	@echo ""
	@cat $(LOG_DIR)/aes-modes-test.log 2>/dev/null || echo "(aes-modes-test.log not found)"

# Build csr-more-test (mcountinhibit, mcounteren, scounteren, HPM stubs)
$(ELF)/csr-more-test.elf: crt0.S uart.c log.c csr-more-test.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) $(LDFLAGS) -march=rv32imc_zicsr -mabi=$(ABI) -o $@ crt0.S uart.c log.c csr-more-test.c
	$(SIZE) $@

$(BIN)/csr-more-test.bin: $(ELF)/csr-more-test.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/csr-more-test.dis

csr-more-test: $(BIN)/csr-more-test.bin

run-csr-more-test: $(BIN)/csr-more-test.bin
	@echo ""
	@echo "=== Running CSR Extended Tests (mcountinhibit/mcounteren/HPM) ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt -q $< 80000000
	@echo ""
	@cat $(LOG_DIR)/csr-more-test.log 2>/dev/null || echo "(csr-more-test.log not found)"

# Build plic-test (PLIC register read/write + pending/claim/complete)
$(ELF)/plic-test.elf: crt0.S uart.c log.c plic-test.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ crt0.S uart.c log.c plic-test.c
	$(SIZE) $@

$(BIN)/plic-test.bin: $(ELF)/plic-test.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/plic-test.dis

plic-test: $(BIN)/plic-test.bin

run-plic-test: $(BIN)/plic-test.bin
	@echo ""
	@echo "=== Running PLIC Test (priority/enable/threshold/pending/claim) ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt -q $< 80000000
	@echo ""
	@cat $(LOG_DIR)/plic-test.log 2>/dev/null || echo "(plic-test.log not found)"

# Build rv64-test (RV64 basic arithmetic / LD/SD / W-ops test)
$(ELF)/rv64-test.elf: crt0-64.S log64.c rv64-test.c hello64.ld | $(ELF)
	$(CC) $(CFLAGS64) $(LDFLAGS64) -Wno-overflow -o $@ crt0-64.S log64.c rv64-test.c
	$(SIZE) $@

# Build rv64-fp-test (RV64 FPU: D extension, FCVT.L/LU.D, FMV.X.D, FMA, FCLASS)
$(ELF)/rv64-fp-test.elf: crt0-64.S log64.c rv64-fp-test.c hello64.ld | $(ELF)
	$(CC) $(CFLAGS64) -fno-builtin $(LDFLAGS64) -o $@ crt0-64.S -fno-builtin log64.c rv64-fp-test.c
	$(SIZE) $@

rv64-fp-test: $(ELF)/rv64-fp-test.elf

run-rv64-fp-test: $(ELF)/rv64-fp-test.elf
	@echo ""
	@echo "=== Running RV64 FPU Test (D ext / FCVT.L.D / FMV.X.D / FMA / FCLASS) ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt -q $<
	@echo ""
	@cat $(LOG_DIR)/rv64-fp-test.log 2>/dev/null || echo "(rv64-fp-test.log not found)"

# Build rv64-sha256-test (SHA-256 FIPS 180-4 compiled for RV64)
$(ELF)/rv64-sha256-test.elf: crt0-64.S log64.c rv64-sha256-test.c hello64.ld | $(ELF)
	$(CC) $(CFLAGS64) $(LDFLAGS64) -o $@ crt0-64.S log64.c rv64-sha256-test.c
	$(SIZE) $@

rv64-sha256-test: $(ELF)/rv64-sha256-test.elf

run-rv64-sha256-test: $(ELF)/rv64-sha256-test.elf
	@echo ""
	@echo "=== Running RV64 SHA-256 Test (FIPS 180-4) ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt -q $<
	@echo ""
	@cat $(LOG_DIR)/rv64-sha256-test.log 2>/dev/null || echo "(rv64-sha256-test.log not found)"

# Build rv64-wops-test (exhaustive W-suffix instruction test with negative results)
$(ELF)/rv64-wops-test.elf: crt0-64.S log64.c rv64-wops-test.c hello64.ld | $(ELF)
	$(CC) $(CFLAGS64) $(LDFLAGS64) -o $@ crt0-64.S log64.c rv64-wops-test.c
	$(SIZE) $@

rv64-wops-test: $(ELF)/rv64-wops-test.elf

run-rv64-wops-test: $(ELF)/rv64-wops-test.elf
	@echo ""
	@echo "=== Running RV64 W-ops Test ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt -q $<
	@echo ""
	@cat $(LOG_DIR)/rv64-wops-test.log 2>/dev/null || echo "(rv64-wops-test.log not found)"

# Build rv64-zbb64-test (Zbb on RV64: CLZ/CTZ/CPOP 64-bit, CLZW/CTZW/CPOPW, ROLW/RORW, REV8, SEXT/ZEXT)
$(ELF)/rv64-zbb64-test.elf: crt0-64.S log64.c rv64-zbb64-test.c hello64.ld | $(ELF)
	$(CC) -march=rv64imafd_zbb -mabi=$(ABI64) -mcmodel=medany -nostdlib -nostartfiles -fno-builtin -O2 -g -Wall \
	      $(LDFLAGS64) -o $@ crt0-64.S log64.c rv64-zbb64-test.c
	$(SIZE) $@

rv64-zbb64-test: $(ELF)/rv64-zbb64-test.elf

run-rv64-zbb64-test: $(ELF)/rv64-zbb64-test.elf
	@echo ""
	@echo "=== Running RV64 Zbb Test (CLZ/CTZ/CPOP/ROLW/RORW/REV8/SEXT) ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt -q $<
	@echo ""
	@cat $(LOG_DIR)/rv64-zbb64-test.log 2>/dev/null || echo "(rv64-zbb64-test.log not found)"

# Build rv64-zbs64-test (Zbs single-bit: bset/bclr/binv/bext)
$(ELF)/rv64-zbs64-test.elf: crt0-64.S log64.c rv64-zbs64-test.c hello64.ld | $(ELF)
	$(CC) -march=rv64imafd_zbs -mabi=$(ABI64) -mcmodel=medany -nostdlib -nostartfiles -fno-builtin -O2 -g -Wall \
	      $(LDFLAGS64) -o $@ crt0-64.S log64.c rv64-zbs64-test.c
	$(SIZE) $@

rv64-zbs64-test: $(ELF)/rv64-zbs64-test.elf

run-rv64-zbs64-test: $(ELF)/rv64-zbs64-test.elf
	@echo ""
	@echo "=== Running RV64 Zbs single-bit: bset/bclr/binv/bext ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt -q $<
	@echo ""
	@cat $(LOG_DIR)/rv64-zbs64-test.log 2>/dev/null || echo "(rv64-zbs64-test.log not found)"

# Build rv64-zbc64-test (Zbc/Zbkc carry-less multiply)
$(ELF)/rv64-zbc64-test.elf: crt0-64.S log64.c rv64-zbc64-test.c hello64.ld | $(ELF)
	$(CC) -march=rv64imafd_zbc -mabi=$(ABI64) -mcmodel=medany -nostdlib -nostartfiles -fno-builtin -O2 -g -Wall \
	      $(LDFLAGS64) -o $@ crt0-64.S log64.c rv64-zbc64-test.c
	$(SIZE) $@

rv64-zbc64-test: $(ELF)/rv64-zbc64-test.elf

run-rv64-zbc64-test: $(ELF)/rv64-zbc64-test.elf
	@echo ""
	@echo "=== Running RV64 Zbc/Zbkc carry-less multiply ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt -q $<
	@echo ""
	@cat $(LOG_DIR)/rv64-zbc64-test.log 2>/dev/null || echo "(rv64-zbc64-test.log not found)"

# Build rv64-zbkx64-test (Zbkx crossbar: xperm4/xperm8)
$(ELF)/rv64-zbkx64-test.elf: crt0-64.S log64.c rv64-zbkx64-test.c hello64.ld | $(ELF)
	$(CC) -march=rv64imafd_zbkx -mabi=$(ABI64) -mcmodel=medany -nostdlib -nostartfiles -fno-builtin -O2 -g -Wall \
	      $(LDFLAGS64) -o $@ crt0-64.S log64.c rv64-zbkx64-test.c
	$(SIZE) $@

rv64-zbkx64-test: $(ELF)/rv64-zbkx64-test.elf

run-rv64-zbkx64-test: $(ELF)/rv64-zbkx64-test.elf
	@echo ""
	@echo "=== Running RV64 Zbkx crossbar: xperm4/xperm8 ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt -q $<
	@echo ""
	@cat $(LOG_DIR)/rv64-zbkx64-test.log 2>/dev/null || echo "(rv64-zbkx64-test.log not found)"

# Build rv64-zbkb64-test (Zbkb pack/packh/packw/brev8)
$(ELF)/rv64-zbkb64-test.elf: crt0-64.S log64.c rv64-zbkb64-test.c hello64.ld | $(ELF)
	$(CC) -march=rv64imafd_zbkb -mabi=$(ABI64) -mcmodel=medany -nostdlib -nostartfiles -fno-builtin -O2 -g -Wall \
	      $(LDFLAGS64) -o $@ crt0-64.S log64.c rv64-zbkb64-test.c
	$(SIZE) $@

rv64-zbkb64-test: $(ELF)/rv64-zbkb64-test.elf

run-rv64-zbkb64-test: $(ELF)/rv64-zbkb64-test.elf
	@echo ""
	@echo "=== Running RV64 Zbkb pack/packh/packw/brev8 ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt -q $<
	@echo ""
	@cat $(LOG_DIR)/rv64-zbkb64-test.log 2>/dev/null || echo "(rv64-zbkb64-test.log not found)"

# Build rv64-reserved-test (reserved-encoding trap coverage)
$(ELF)/rv64-reserved-test.elf: crt0-64.S log64.c rv64-reserved-test.c hello64.ld | $(ELF)
	$(CC) -march=rv64imafd_zbs_zbc_zbkb_zbkx -mabi=$(ABI64) -mcmodel=medany -nostdlib -nostartfiles -fno-builtin -O2 -g -Wall \
	      $(LDFLAGS64) -o $@ crt0-64.S log64.c rv64-reserved-test.c
	$(SIZE) $@

rv64-reserved-test: $(ELF)/rv64-reserved-test.elf

run-rv64-reserved-test: $(ELF)/rv64-reserved-test.elf
	@echo ""
	@echo "=== Running RV64 reserved-encoding trap coverage ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt -q $<
	@echo ""
	@cat $(LOG_DIR)/rv64-reserved-test.log 2>/dev/null || echo "(rv64-reserved-test.log not found)"

# Build rv64-atomic-test (RV64 A extension: LR.D/SC.D + all AMO.D variants)
$(ELF)/rv64-atomic-test.elf: crt0-64.S log64.c rv64-atomic-test.c hello64.ld | $(ELF)
	$(CC) $(CFLAGS64) $(LDFLAGS64) -o $@ crt0-64.S log64.c rv64-atomic-test.c
	$(SIZE) $@

$(BIN)/rv64-atomic-test.bin: $(ELF)/rv64-atomic-test.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/rv64-atomic-test.dis

rv64-atomic-test: $(ELF)/rv64-atomic-test.elf

run-rv64-atomic-test: $(ELF)/rv64-atomic-test.elf
	@echo ""
	@echo "=== Running RV64 Atomic Test (LR.D/SC.D + AMO.D) ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt -q $<
	@echo ""
	@cat $(LOG_DIR)/rv64-atomic-test.log 2>/dev/null || echo "(rv64-atomic-test.log not found)"

# Build rv64-zba64-test (Zba on RV64: sh1add/sh2add/sh3add + .uw variants)
$(ELF)/rv64-zba64-test.elf: crt0-64.S log64.c rv64-zba64-test.c hello64.ld | $(ELF)
	$(CC) -march=rv64imafd_zba -mabi=$(ABI64) -mcmodel=medany -nostdlib -nostartfiles \
	      -fno-builtin -O2 -g -Wall \
	      $(LDFLAGS64) -o $@ crt0-64.S log64.c rv64-zba64-test.c
	$(SIZE) $@

$(BIN)/rv64-zba64-test.bin: $(ELF)/rv64-zba64-test.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/rv64-zba64-test.dis

rv64-zba64-test: $(ELF)/rv64-zba64-test.elf

run-rv64-zba64-test: $(ELF)/rv64-zba64-test.elf
	@echo ""
	@echo "=== Running RV64 Zba Test (sh1add/sh2add/sh3add + .uw variants) ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt -q $<
	@echo ""
	@cat $(LOG_DIR)/rv64-zba64-test.log 2>/dev/null || echo "(rv64-zba64-test.log not found)"

# Build rv64-zicond-test (Zicond: czero.eqz / czero.nez conditional-zero)
$(ELF)/rv64-zicond-test.elf: crt0-64.S log64.c rv64-zicond-test.c hello64.ld | $(ELF)
	$(CC) -march=rv64imafd_zicond -mabi=$(ABI64) -mcmodel=medany -nostdlib \
	      -nostartfiles -fno-builtin -O2 -g -Wall \
	      $(LDFLAGS64) -o $@ crt0-64.S log64.c rv64-zicond-test.c
	$(SIZE) $@

$(BIN)/rv64-zicond-test.bin: $(ELF)/rv64-zicond-test.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/rv64-zicond-test.dis

rv64-zicond-test: $(ELF)/rv64-zicond-test.elf

run-rv64-zicond-test: $(ELF)/rv64-zicond-test.elf
	@echo ""
	@echo "=== Running RV64 Zicond Test (czero.eqz / czero.nez) ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt -q $<
	@echo ""
	@cat $(LOG_DIR)/rv64-zicond-test.log 2>/dev/null || echo "(rv64-zicond-test.log not found)"

rv64-test: $(ELF)/rv64-test.elf

run-rv64-test: $(ELF)/rv64-test.elf
	@echo ""
	@echo "=== Running RV64 Basic Test (64-bit arithmetic / LD-SD / ADDIW / W-ops) ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt -q $<
	@echo ""
	@cat $(LOG_DIR)/rv64-test.log 2>/dev/null || echo "(rv64-test.log not found)"

test-all: all
	@./test-all.sh

run-rtos-test: $(BIN)/rtos-test.bin
	@echo ""
	@echo "=== Running Cooperative RTOS Test (yield / sleep / task exit) ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt -q $< 80000000
	@echo ""
	@cat $(LOG_DIR)/rtos-test.log 2>/dev/null || echo "(rtos-test.log not found)"

run-prtos-test: $(BIN)/prtos-test.bin
	@echo ""
	@echo "=== Running Preemptive RTOS Test (timer interrupt / mret context switch) ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt -q $< 80000000
	@echo ""
	@cat $(LOG_DIR)/prtos-test.log 2>/dev/null || echo "(prtos-test.log not found)"

# Build virtio-blk-test (VirtIO MMIO block device: write/read/verify sectors)
$(ELF)/virtio-blk-test.elf: crt0.S uart.c log.c virtio-blk-test.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ crt0.S uart.c log.c virtio-blk-test.c
	$(SIZE) $@

$(BIN)/virtio-blk-test.bin: $(ELF)/virtio-blk-test.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/virtio-blk-test.dis

virtio-blk-test: $(BIN)/virtio-blk-test.bin

run-virtio-blk-test: $(BIN)/virtio-blk-test.bin
	@echo ""
	@echo "=== Running VirtIO Block Device Test ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt --pty --wait $< 80000000
	@echo ""
	@cat $(LOG_DIR)/virtio-blk-test.log 2>/dev/null || echo "(virtio-blk-test.log not found)"

# Build sv39-test (Sv39 MMU: 3-level page table, RV64 S-mode)
$(ELF)/sv39-test.elf: crt0-smode-64.S log64.c sv39-test.c hello64.ld | $(ELF)
	$(CC) -march=$(ARCH64) -mabi=$(ABI64) -mcmodel=medany -nostdlib -nostartfiles \
	    -fno-builtin -O2 -g -Wall -T hello64.ld \
	    -o $@ crt0-smode-64.S log64.c sv39-test.c
	$(SIZE) $@

sv39-test: $(ELF)/sv39-test.elf

run-sv39-test: $(ELF)/sv39-test.elf
	@echo ""
	@echo "=== Running Sv39 MMU Test ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt -q $<
	@echo ""
	@cat $(LOG_DIR)/sv39-test.log 2>/dev/null || echo "(sv39-test.log not found)"

# Build x25519-test (X25519 Diffie-Hellman on Curve25519 with RFC 7748 test vectors)
$(ELF)/x25519-test.elf: crt0.S uart.c log.c syscalls.c string.c x25519-test.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ crt0.S uart.c log.c syscalls.c string.c x25519-test.c
	$(SIZE) $@

$(BIN)/x25519-test.bin: $(ELF)/x25519-test.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/x25519-test.dis

x25519-test: $(BIN)/x25519-test.bin

run-x25519-test: $(BIN)/x25519-test.bin
	@echo ""
	@echo "=== Running X25519 Curve25519 Test ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt -q $< 80000000
	@echo ""
	@cat $(LOG_DIR)/x25519-test.log 2>/dev/null || echo "(x25519-test.log not found)"

# Build p256-ecdsa-test (ECDSA sign+verify over NIST P-256 with RFC 6979 test vectors)
$(ELF)/p256-ecdsa-test.elf: crt0.S uart.c log.c syscalls.c string.c p256-ecdsa-test.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ crt0.S uart.c log.c syscalls.c string.c p256-ecdsa-test.c
	$(SIZE) $@

$(BIN)/p256-ecdsa-test.bin: $(ELF)/p256-ecdsa-test.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/p256-ecdsa-test.dis

p256-ecdsa-test: $(BIN)/p256-ecdsa-test.bin

run-p256-ecdsa-test: $(BIN)/p256-ecdsa-test.bin
	@echo ""
	@echo "=== Running P-256 ECDSA Test ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt -q $< 80000000
	@echo ""
	@cat $(LOG_DIR)/p256-ecdsa-test.log 2>/dev/null || echo "(p256-ecdsa-test.log not found)"

# Create output directories
$(BIN) $(ELF) $(DIS):
	mkdir -p $@

# Build timing-test (cycle-accurate timing model verification)
$(ELF)/timing-test.elf: crt0.S uart.c log.c timing-test.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) $(LDFLAGS) -march=rv32imafd_zicsr -mabi=$(ABI) -o $@ \
	    crt0.S uart.c log.c timing-test.c
	$(SIZE) $@

$(BIN)/timing-test.bin: $(ELF)/timing-test.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/timing-test.dis

timing-test: $(BIN)/timing-test.bin

run-timing-test: $(BIN)/timing-test.bin
	@echo ""
	@echo "=== Running Cycle-Accurate Timing Test ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt -q $< 80000000
	@echo ""
	@cat $(LOG_DIR)/timing-test.log 2>/dev/null || echo "(timing-test.log not found)"

# Build zfh-test (Zfh half-precision floating-point extension)
$(ELF)/zfh-test.elf: crt0.S uart.c log.c zfh-test.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) $(LDFLAGS) -march=rv32imafd_zfh -mabi=$(ABI) -o $@ \
	    crt0.S uart.c log.c zfh-test.c
	$(SIZE) $@

$(BIN)/zfh-test.bin: $(ELF)/zfh-test.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/zfh-test.dis

zfh-test: $(BIN)/zfh-test.bin

run-zfh-test: $(BIN)/zfh-test.bin
	@echo ""
	@echo "=== Running Zfh Half-Precision Test ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt -q $< 80000000
	@echo ""
	@cat $(LOG_DIR)/zfh-test.log 2>/dev/null || echo "(zfh-test.log not found)"

# Build multihart-test (2-hart IPI + LR/SC spinlock test)
# Uses crt0-multihart.S (2-hart startup) instead of crt0.S
$(ELF)/multihart-test.elf: crt0-multihart.S log.c uart.c multihart-test.c hello.ld | $(ELF)
	$(CC) -march=rv32ima_zicsr -mabi=$(ABI) -nostdlib -nostartfiles \
	    -fno-builtin -O2 -g -Wall $(LDFLAGS) \
	    -o $@ crt0-multihart.S log.c uart.c multihart-test.c
	$(SIZE) $@

$(BIN)/multihart-test.bin: $(ELF)/multihart-test.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/multihart-test.dis

multihart-test: $(BIN)/multihart-test.bin

run-multihart-test: $(BIN)/multihart-test.bin
	@echo ""
	@echo "=== Running Multi-Hart Test ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt --harts 2 -q $< 80000000
	@echo ""
	@cat $(LOG_DIR)/multihart-test.log 2>/dev/null || echo "(multihart-test.log not found)"

# Build pthread-test (minimal pthread-like API, 2-hart, harts2 format)
# Uses crt0-pthread.S (secondary-hart launch-table startup)
$(ELF)/pthread-test.elf: crt0-pthread.S log.c uart.c pthread.c pthread-test.c hello.ld | $(ELF)
	$(CC) -march=rv32ima_zicsr -mabi=$(ABI) -nostdlib -nostartfiles \
	    -fno-builtin -O2 -g -Wall $(LDFLAGS) \
	    -o $@ crt0-pthread.S log.c uart.c pthread.c pthread-test.c
	$(SIZE) $@

$(BIN)/pthread-test.bin: $(ELF)/pthread-test.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/pthread-test.dis

pthread-test: $(BIN)/pthread-test.bin

run-pthread-test: $(BIN)/pthread-test.bin
	@echo ""
	@echo "=== Running pthread-test ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt --harts 2 -q $< 80000000
	@echo ""
	@cat $(LOG_DIR)/pthread-test.log 2>/dev/null || echo "(pthread-test.log not found)"

# Build rv32e-test (RV32E 16-register subset test)
$(ELF)/rv32e-test.elf: crt0.S uart.c log.c rv32e-test.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) -march=rv32imc_zicsr $(LDFLAGS) -o $@ crt0.S uart.c log.c rv32e-test.c
	$(SIZE) $@

rv32e-test: $(ELF)/rv32e-test.elf

run-rv32e-test: $(ELF)/rv32e-test.elf
	@echo ""
	@echo "=== Running RV32E Test ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt --rv32e -q $(ELF)/rv32e-test.elf
	@echo ""
	@cat $(LOG_DIR)/rv32e-test.log 2>/dev/null || echo "(rv32e-test.log not found)"

# Build rv64e-test (RV64E 16-register subset test)
# Does NOT link log64.c: uses inline semihosting to avoid x16+ register usage
$(ELF)/rv64e-test.elf: crt0-64.S rv64e-test.c hello64.ld | $(ELF)
	$(CC) $(CFLAGS64) $(LDFLAGS64) -o $@ crt0-64.S rv64e-test.c
	$(SIZE) $@

rv64e-test: $(ELF)/rv64e-test.elf

run-rv64e-test: $(ELF)/rv64e-test.elf
	@echo ""
	@echo "=== Running RV64E Test ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt --rv64e -q $<
	@echo ""
	@cat $(LOG_DIR)/rv64e-test.log 2>/dev/null || echo "(rv64e-test.log not found)"

# Build coremark-test (Coremark-inspired benchmark)
$(ELF)/coremark-test.elf: crt0.S uart.c log.c coremark-test.c string.c syscalls.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ \
	    crt0.S uart.c log.c coremark-test.c string.c syscalls.c
	$(SIZE) $@

$(BIN)/coremark-test.bin: $(ELF)/coremark-test.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/coremark-test.dis

coremark-test: $(BIN)/coremark-test.bin

run-coremark-test: $(BIN)/coremark-test.bin
	@echo ""
	@echo "=== Running Coremark-like Benchmark ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt -q $< 80000000
	@echo ""
	@cat $(LOG_DIR)/coremark-test.log 2>/dev/null || echo "(coremark-test.log not found)"

# Build gzip-test (RFC 1952 gzip compress/decompress)
$(ELF)/gzip-test.elf: crt0.S uart.c log.c string.c syscalls.c deflate.c gzip.c gzip-test.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ crt0.S uart.c log.c string.c syscalls.c deflate.c gzip.c gzip-test.c
	$(SIZE) $@

$(BIN)/gzip-test.bin: $(ELF)/gzip-test.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/gzip-test.dis

gzip-test: $(ELF)/gzip-test.elf

run-gzip-test: $(ELF)/gzip-test.elf
	@echo ""
	@echo "=== Running Gzip Compress/Decompress Test ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt -q $<
	@echo ""
	@cat $(LOG_DIR)/gzip-test.log 2>/dev/null || echo "(gzip-test.log not found)"

# Build ed25519-test (Ed25519 RFC 8032 sign/verify with SHA-512)
$(ELF)/ed25519-test.elf: crt0.S uart.c log.c sha512.c ed25519.c ed25519-test.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ crt0.S uart.c log.c sha512.c ed25519.c ed25519-test.c -lgcc
	$(SIZE) $@

$(BIN)/ed25519-test.bin: $(ELF)/ed25519-test.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/ed25519-test.dis

ed25519-test: $(BIN)/ed25519-test.bin

run-ed25519-test: $(BIN)/ed25519-test.bin
	@echo ""
	@echo "=== Running Ed25519 (RFC 8032) Test ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt -q $< 80000000
	@echo ""
	@cat $(LOG_DIR)/ed25519-test.log 2>/dev/null || echo "(ed25519-test.log not found)"

# Build pipeline-test (cycle-accurate pipeline hazard model verification)
$(ELF)/pipeline-test.elf: crt0.S uart.c log.c pipeline-test.c hello.ld | $(ELF)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ crt0.S uart.c log.c pipeline-test.c
	$(SIZE) $@

$(BIN)/pipeline-test.bin: $(ELF)/pipeline-test.elf | $(BIN) $(DIS)
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(DIS)/pipeline-test.dis

pipeline-test: $(BIN)/pipeline-test.bin

run-pipeline-test: $(BIN)/pipeline-test.bin
	@echo ""
	@echo "=== Running Pipeline Hazard Test ==="
	@echo ""
	$(EMULATOR) $(LOGFLAGS) --machine qemu-virt -q $< 80000000
	@echo ""
	@cat $(LOG_DIR)/pipeline-test.log 2>/dev/null || echo "(pipeline-test.log not found)"

# Check if toolchain is available
check-toolchain:
	@which $(CC) > /dev/null || (echo "Error: RISC-V toolchain not found. Install riscv32-unknown-elf-gcc" && exit 1)
	@echo "Toolchain OK: $(shell $(CC) --version | head -1)"

clean:
	rm -rf $(OUT)
	rm -f $(DOOM_RUN_DIR)/doom_frame_*.ppm $(DOOM_RUN_DIR)/doom.mp4 \
	      $(DOOM_RUN_DIR)/doom.gif

distclean: clean
	rm -f crt0.S hello.ld uart.c hello.c echo.c

help:
	@echo "RISC-V Bare-Metal Examples"
	@echo ""
	@echo "Targets:"
	@echo "  make check-toolchain  - Verify RISC-V toolchain is installed"
	@echo "  make all             - Build all examples"
	@echo "  make hello.bin       - Build hello world"
	@echo "  make echo.bin        - Build echo test"
	@echo "  make run-hello       - Build and run hello (needs emulator)"
	@echo "  make run-echo        - Build and run echo (needs emulator)"
	@echo "  make clean           - Remove built files"
	@echo "  make distclean       - Remove all generated files"
	@echo ""
	@echo "Requirements:"
	@echo "  - riscv32-unknown-elf-gcc toolchain"
	@echo "  - Emulator built in ../bin/riscv_emulator"
	@echo ""
	@echo "Install toolchain:"
	@echo "  sudo apt install gcc-riscv64-unknown-elf"

# =============================================================================
# DOOM - doomgeneric port
#
# Requirements:
#   doom1.wad (shareware) in the directory where you run the emulator.
#   "make doom-wad" downloads and checksum-verifies it; no game data is
#   distributed with this repository.
#
# Usage:
#   make doom                    # build doom.elf from the vendored engine
#   make run-doom                # download WAD if needed + run (frames->$(DOOM_RUN_DIR))
#   make doom-video              # stitch PPMs->doom.mp4 (needs ffmpeg)
#   make doom-gif                # stitch PPMs->doom.gif (needs ffmpeg)
#
# The WAD is read from, and frames/video are written to, $(DOOM_RUN_DIR)
# (default: doom-run/ in the repo root). `make clean` removes the generated
# frames + video there (keeping the cached WAD); `make doom-clean` wipes the
# whole directory. Override the location with e.g.
#   make run-doom DOOM_RUN_DIR=/tmp/doom
# =============================================================================

DOOM_SRC     := doom/doomgeneric

# Directory the emulator runs in: where doom1.wad lives and where the
# doom_frame_*.ppm / doom.mp4 files are written. Default: doom-run/ at repo root.
DOOM_RUN_DIR ?= ../doom-run
# Shareware IWAD. No game data is distributed with this repository; it is
# fetched on demand and checksum-verified, because a mirror that 404s otherwise
# leaves an HTML error page named doom1.wad and the engine dies with a
# confusing "doesn't have IWAD or PWAD id".
# Primary source is Debian's non-free source package (stable URL, CDN-backed);
# the direct-file mirror is a fallback.
DOOM_WAD_TARBALL := http://deb.debian.org/debian/pool/non-free/d/doom-wad-shareware/doom-wad-shareware_1.9.fixed.orig.tar.gz
DOOM_WAD_URL := https://distro.ibiblio.org/slitaz/sources/packages/d/doom1.wad
DOOM_WAD_MD5 := f0cefca49926d00903cf57551d901abe
# doomgeneric/ is vendored (GPLv2 -- see doom/README.md), not fetched, because
# the port depends on bare-metal modifications that do not exist upstream.
# doomgeneric_sdl.c and i_main.c are kept for reference but need a host OS.
DOOM_SRCS    := $(filter-out \
                  $(DOOM_SRC)/doomgeneric_sdl.c \
                  $(DOOM_SRC)/i_main.c, \
                $(wildcard $(DOOM_SRC)/*.c))

DOOM_CFLAGS  := -march=rv32imac -mabi=ilp32 -O2 -nostartfiles \
                -I$(DOOM_SRC) -Idoom \
                -DNOMIXER -DNO_SOUND -DNONET \
                -w

DOOM_LDFLAGS := -T doom/hello_doom.ld -lc -lm -lnosys

# Frame rate the engine renders at; used by both doom-video and doom-gif.
DOOM_FPS := 35

# GIF is limited to 256 colours, so build a palette from the clip itself
# instead of using the default web palette. stats_mode=diff weights the
# palette towards the moving parts of the frame, and the ordered Bayer
# dither keeps the flat wall textures from crawling between frames.
DOOM_GIF_FILTER := split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=3

.PHONY: doom run-doom doom-video doom-gif doom-wad doom-clean doom-tty run-doom-tty

$(ELF)/doom.elf: doom/crt0_doom.S $(DOOM_SRCS) doom/doomgeneric_riscv.c \
                 doom/newlib_syscalls.c doom/hello_doom.ld | $(ELF)
	$(CC) $(DOOM_CFLAGS) $(DOOM_LDFLAGS) -o $@ \
	    doom/crt0_doom.S $(DOOM_SRCS) \
	    doom/doomgeneric_riscv.c doom/newlib_syscalls.c

doom: $(ELF)/doom.elf
	@echo "Built doom.elf - run 'make run-doom'"

# Interactive build: renders to the terminal and reads the keyboard
# (ECALLs 0x50D/0x50E) instead of dumping PPM frames.
$(ELF)/doom-tty.elf: doom/crt0_doom.S $(DOOM_SRCS) doom/doomgeneric_riscv.c \
                 doom/newlib_syscalls.c doom/hello_doom.ld | $(ELF)
	$(CC) $(DOOM_CFLAGS) -DDOOM_INTERACTIVE $(DOOM_LDFLAGS) -o $@ \
	    doom/crt0_doom.S $(DOOM_SRCS) \
	    doom/doomgeneric_riscv.c doom/newlib_syscalls.c

doom-tty: $(ELF)/doom-tty.elf
	@echo "Built doom-tty.elf - run 'make run-doom-tty'"

run-doom-tty: $(ELF)/doom-tty.elf $(DOOM_RUN_DIR)/doom1.wad
	@echo "Interactive DOOM - WASD move, Q/E strafe, SPACE fire, F use,"
	@echo "  1-7 weapons, ENTER/ESC menu, \` (backtick) quit."
	@echo "  Use a terminal >= 100 cols x 34 rows. If it exits garbled, run 'reset'."
	cd $(DOOM_RUN_DIR) && $(abspath $(EMULATOR)) --machine qemu-virt -q \
	    $(abspath $(ELF)/doom-tty.elf)

# Download the shareware WAD into the run directory (only if missing).
doom-wad: $(DOOM_RUN_DIR)/doom1.wad
$(DOOM_RUN_DIR)/doom1.wad:
	@mkdir -p $(DOOM_RUN_DIR)
	@echo "Downloading shareware doom1.wad -> $(abspath $@)"
	@set -e; \
	tmp=$@.tmp; rm -f $$tmp; \
	if curl -fsL --max-time 120 -o $$tmp.tar.gz "$(DOOM_WAD_TARBALL)" 2>/dev/null && \
	   tar xzf $$tmp.tar.gz -O --wildcards '*/doom1.wad' > $$tmp 2>/dev/null && [ -s $$tmp ]; then \
	    echo "  fetched from $(DOOM_WAD_TARBALL)"; \
	else \
	    echo "  tarball source failed, trying $(DOOM_WAD_URL)"; \
	    curl -fsL --max-time 120 -o $$tmp "$(DOOM_WAD_URL)" || \
	      { echo "ERROR: could not download doom1.wad from any source."; \
	        echo "       Place a shareware doom1.wad (md5 $(DOOM_WAD_MD5)) at $(abspath $@)"; \
	        rm -f $$tmp $$tmp.tar.gz; exit 1; }; \
	fi; \
	rm -f $$tmp.tar.gz; \
	got=`md5sum $$tmp | cut -d' ' -f1`; \
	if [ "$$got" != "$(DOOM_WAD_MD5)" ]; then \
	    echo "ERROR: doom1.wad checksum mismatch (`wc -c < $$tmp` bytes)."; \
	    echo "       expected md5 $(DOOM_WAD_MD5)"; \
	    echo "       got      md5 $$got"; \
	    echo "       The download was probably an error page, not the WAD."; \
	    rm -f $$tmp; exit 1; \
	fi; \
	mv $$tmp $@; \
	echo "  verified: 4196020 bytes, md5 $(DOOM_WAD_MD5)"

# Wipe the entire run directory (frames, video, AND the cached WAD).
doom-clean:
	rm -rf $(DOOM_RUN_DIR)

run-doom: $(ELF)/doom.elf $(DOOM_RUN_DIR)/doom1.wad
	@echo "Running Doom in $(abspath $(DOOM_RUN_DIR)) - writes doom_frame_000000.ppm ... 000059.ppm there"
	cd $(DOOM_RUN_DIR) && $(abspath $(EMULATOR)) --machine qemu-virt $(abspath $(ELF)/doom.elf)
	@echo "Done - run 'make doom-video' (doom.mp4) or 'make doom-gif' (doom.gif)"
	@echo "       to stitch the frames together."

doom-video:
	@which ffmpeg > /dev/null || { echo "ffmpeg not found"; exit 1; }
	@ls $(DOOM_RUN_DIR)/doom_frame_000000.ppm >/dev/null 2>&1 || \
	  { echo "No doom_frame_*.ppm in $(abspath $(DOOM_RUN_DIR)) - run 'make run-doom' first"; exit 1; }
	cd $(DOOM_RUN_DIR) && ffmpeg -y -framerate $(DOOM_FPS) -i doom_frame_%06d.ppm \
	    -c:v libx264 -pix_fmt yuv420p doom.mp4
	@echo "Created $(abspath $(DOOM_RUN_DIR))/doom.mp4"

# Animated GIF, for embedding in a README or an issue where an mp4 will
# not play. The PPM frames are preferred over doom.mp4: they are the
# engine's original output, so the palette comes out clean. Converting
# the mp4 instead works, but H.264 chroma subsampling adds noise that the
# palette quantiser then has to spend colours on -- for the stock 60-frame
# run that is a 748KB GIF against 472KB from the PPMs.
doom-gif:
	@which ffmpeg > /dev/null || { echo "ffmpeg not found"; exit 1; }
	@cd $(DOOM_RUN_DIR) && \
	 if ls doom_frame_000000.ppm >/dev/null 2>&1; then \
	   echo "Converting doom_frame_*.ppm -> doom.gif"; \
	   ffmpeg -y -framerate $(DOOM_FPS) -i doom_frame_%06d.ppm \
	       -vf "$(DOOM_GIF_FILTER)" -loop 0 doom.gif; \
	 elif [ -f doom.mp4 ]; then \
	   echo "No PPM frames left - converting doom.mp4 -> doom.gif"; \
	   ffmpeg -y -i doom.mp4 -vf "$(DOOM_GIF_FILTER)" -loop 0 doom.gif; \
	 else \
	   echo "No doom_frame_*.ppm and no doom.mp4 in $(abspath $(DOOM_RUN_DIR)) - run 'make run-doom' first"; \
	   exit 1; \
	 fi
	@echo "Created $(abspath $(DOOM_RUN_DIR))/doom.gif"
