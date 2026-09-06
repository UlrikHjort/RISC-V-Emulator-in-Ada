# RISC-V Architecture Compliance Test Runner
# Uses riscv-arch-test suite (old-framework-2.x) as a git submodule

RUNNER = ./run_arch_tests.sh

.PHONY: init test test-I test-M test-C test-F test-K test-Zifencei \
        test-privilege test-all clean

# Initialise / update the submodule (run once after cloning the repo).
# Runs from the repo root so the target works from any directory.
init:
	cd $(shell git rev-parse --show-toplevel) && \
	    git submodule update --init arch-test/riscv-arch-test

# Guard: fail early if the submodule has not been initialised
riscv-arch-test/riscv-test-suite:
	@echo "riscv-arch-test submodule not found. Run 'make init' first (from repo root)."
	@exit 1

# Individual suite targets
test-I: riscv-arch-test/riscv-test-suite
	$(RUNNER) I

test-M: riscv-arch-test/riscv-test-suite
	$(RUNNER) M

test-C: riscv-arch-test/riscv-test-suite
	$(RUNNER) C

test-F: riscv-arch-test/riscv-test-suite
	$(RUNNER) F

test-K: riscv-arch-test/riscv-test-suite
	$(RUNNER) K

test-Zifencei: riscv-arch-test/riscv-test-suite
	$(RUNNER) Zifencei

test-privilege: riscv-arch-test/riscv-test-suite
	$(RUNNER) privilege

# Phase 1: baseline (I + M + C)
test: test-I test-M test-C

# All suites
test-all: test-I test-M test-C test-F test-Zifencei test-privilege

clean:
	rm -rf work
