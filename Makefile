# RISCV Emulator Makefile
# RV32IM implementation in Ada

# Compiler and flags
GNATMAKE = gnatmake
GNATCLEAN = gnatclean
GNAT_FLAGS = -gnata -gnatwae -gnatVa -gnatybfhiklnprtu
OPT_FLAGS = -O2
CC = gcc
CFLAGS = -O1 -Wall -frounding-math -march=native

# Directories
SRC_DIR = src
OBJ_DIR = obj
BIN_DIR = bin

# Output binary
TARGET = $(BIN_DIR)/riscv_emulator

# Main source file
MAIN = main.adb

# C helper object
C_FP_OBJ = $(OBJ_DIR)/riscv_fp_helpers.o

.PHONY: all clean rebuild run debug arch-test

all: $(TARGET)

$(C_FP_OBJ): $(SRC_DIR)/riscv_fp_helpers.c
	@mkdir -p $(OBJ_DIR)
	$(CC) $(CFLAGS) -c -o $@ $<

$(TARGET): $(SRC_DIR)/*.adb $(SRC_DIR)/*.ads $(C_FP_OBJ)
	@mkdir -p $(OBJ_DIR) $(BIN_DIR)
	$(GNATMAKE) -D $(OBJ_DIR) -o $(TARGET) $(SRC_DIR)/$(MAIN) \
		$(GNAT_FLAGS) $(OPT_FLAGS) -aI$(SRC_DIR) \
		-largs $(C_FP_OBJ) -lm

debug: $(SRC_DIR)/*.adb $(SRC_DIR)/*.ads $(C_FP_OBJ)
	@mkdir -p $(OBJ_DIR) $(BIN_DIR)
	$(GNATMAKE) -D $(OBJ_DIR) -o $(BIN_DIR)/riscv_emulator_debug $(SRC_DIR)/$(MAIN) \
		$(GNAT_FLAGS) -g -O0 -aI$(SRC_DIR) \
		-largs $(C_FP_OBJ) -lm

clean:
	rm -rf $(OBJ_DIR)/*
	rm -rf $(BIN_DIR)/*

rebuild: clean all

run: $(TARGET)
	@echo "Usage: $(TARGET) <binary_file> [start_address]"

# Unit tests for peripherals
test-peripherals: $(SRC_DIR)/*.adb $(SRC_DIR)/*.ads test/test_peripherals.adb
	@mkdir -p $(OBJ_DIR) $(BIN_DIR)
	$(GNATMAKE) -D $(OBJ_DIR) -o $(BIN_DIR)/test_peripherals test/test_peripherals.adb \
		$(GNAT_FLAGS) $(OPT_FLAGS) -aI$(SRC_DIR)
	@$(BIN_DIR)/test_peripherals

# Unit tests for A extension (atomics)
test-atomics: $(SRC_DIR)/*.adb $(SRC_DIR)/*.ads test/test_atomics.adb $(C_FP_OBJ)
	@mkdir -p $(OBJ_DIR) $(BIN_DIR)
	$(GNATMAKE) -D $(OBJ_DIR) -o $(BIN_DIR)/test_atomics test/test_atomics.adb \
		$(GNAT_FLAGS) $(OPT_FLAGS) -aI$(SRC_DIR) \
		-largs $(C_FP_OBJ) -lm
	@$(BIN_DIR)/test_atomics

# Unit tests for C extension (compressed)
test-compressed: $(SRC_DIR)/*.adb $(SRC_DIR)/*.ads test/test_compressed.adb $(C_FP_OBJ)
	@mkdir -p $(OBJ_DIR) $(BIN_DIR)
	$(GNATMAKE) -D $(OBJ_DIR) -o $(BIN_DIR)/test_compressed test/test_compressed.adb \
		$(GNAT_FLAGS) $(OPT_FLAGS) -aI$(SRC_DIR) \
		-largs $(C_FP_OBJ) -lm
	@$(BIN_DIR)/test_compressed

# Unit tests for Zicsr extension (CSR)
test-csr: $(SRC_DIR)/*.adb $(SRC_DIR)/*.ads test/test_csr.adb $(C_FP_OBJ)
	@mkdir -p $(OBJ_DIR) $(BIN_DIR)
	$(GNATMAKE) -D $(OBJ_DIR) -o $(BIN_DIR)/test_csr test/test_csr.adb \
		$(GNAT_FLAGS) $(OPT_FLAGS) -aI$(SRC_DIR) \
		-largs $(C_FP_OBJ) -lm
	@$(BIN_DIR)/test_csr

# Unit tests for trap/interrupt handling
test-traps: $(SRC_DIR)/*.adb $(SRC_DIR)/*.ads test/test_traps.adb $(C_FP_OBJ)
	@mkdir -p $(OBJ_DIR) $(BIN_DIR)
	$(GNATMAKE) -D $(OBJ_DIR) -o $(BIN_DIR)/test_traps test/test_traps.adb \
		$(GNAT_FLAGS) $(OPT_FLAGS) -aI$(SRC_DIR) \
		-largs $(C_FP_OBJ) -lm
	@$(BIN_DIR)/test_traps

# Unit tests for privilege levels (M/S/U)
test-privilege: $(SRC_DIR)/*.adb $(SRC_DIR)/*.ads test/test_privilege.adb $(C_FP_OBJ)
	@mkdir -p $(OBJ_DIR) $(BIN_DIR)
	$(GNATMAKE) -D $(OBJ_DIR) -o $(BIN_DIR)/test_privilege test/test_privilege.adb \
		$(GNAT_FLAGS) $(OPT_FLAGS) -aI$(SRC_DIR) \
		-largs $(C_FP_OBJ) -lm
	@$(BIN_DIR)/test_privilege

# Unit tests for V extension (vector)
test-vector: $(SRC_DIR)/*.adb $(SRC_DIR)/*.ads test/test_vector.adb $(C_FP_OBJ)
	@mkdir -p $(OBJ_DIR) $(BIN_DIR)
	$(GNATMAKE) -D $(OBJ_DIR) -o $(BIN_DIR)/test_vector test/test_vector.adb \
		$(GNAT_FLAGS) $(OPT_FLAGS) -aI$(SRC_DIR) \
		-largs $(C_FP_OBJ) -lm
	@$(BIN_DIR)/test_vector

# Integration tests: run compiled RISC-V vector test programs on emulator
test-vector-elf: $(TARGET)
	@echo "==================================================="
	@echo "       RISCV Vector ELF Integration Tests"
	@echo "==================================================="
	@fail=0; \
	for t in vector_simple vector; do \
		if [ -f test/$$t.elf ]; then \
			result=$$($(BIN_DIR)/riscv_emulator test/$$t.elf 2>&1 | grep "Return value" | awk '{print $$NF}'); \
			if [ "$$result" = "0" ]; then \
				echo "  PASS: $$t (return 0)"; \
			else \
				echo "  FAIL: $$t (return $$result)"; \
				fail=1; \
			fi; \
		else \
			echo "  SKIP: $$t (ELF not found, run 'make -C test' to build)"; \
		fi; \
	done; \
	echo "==================================================="; \
	if [ $$fail -ne 0 ]; then exit 1; fi

# Run all tests
test: test-peripherals test-atomics test-compressed test-csr test-traps test-privilege test-vector test-vector-elf
	@echo ""
	@echo "All tests complete."

# Architecture compliance tests
arch-test: $(TARGET)
	$(MAKE) -C arch-test test

help:
	@echo "RISC-V Emulator (RV32IM) Build System"
	@echo ""
	@echo "Targets:"
	@echo "  all      - Build the emulator (default)"
	@echo "  debug    - Build with debug symbols"
	@echo "  clean    - Remove build artifacts"
	@echo "  rebuild  - Clean and rebuild"
	@echo "  run      - Show usage"
	@echo "  help     - Show this help"
