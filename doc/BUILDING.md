# Building

## Prerequisites

### Required

- **GNAT Ada Compiler** - Part of GCC or available standalone
  ```bash
  # Ubuntu/Debian
  sudo apt install gnat

  # Fedora
  sudo dnf install gcc-gnat

  # macOS (via Homebrew)
  brew install gnat
  ```

- **Make** - Standard build tool

### Optional (for test programs)

- **RISC-V Cross-Compiler** - For building test C programs
  ```bash
  # Ubuntu/Debian
  sudo apt install gcc-riscv64-unknown-elf

  # Or build from source / use prebuilt toolchains
  ```

## Building the Emulator

### Standard Build

```bash
cd riscv
make
```

Creates `bin/riscv_emulator` (optimized, -O2).

### Debug Build

```bash
make debug
```

Creates `bin/riscv_emulator_debug` with debug symbols (-g -O0).

### Clean Build

```bash
make clean    # Remove build artifacts
make rebuild  # Clean and build
```

## Build Targets

| Target | Description |
|--------|-------------|
| `make` or `make all` | Build optimized emulator |
| `make debug` | Build with debug symbols |
| `make clean` | Remove obj/ and bin/ contents |
| `make rebuild` | Clean then build |
| `make test` | Run unit tests |
| `make help` | Show available targets |

## Compiler Flags

Default flags in Makefile:

```makefile
GNAT_FLAGS = -gnata -gnatwae -gnatVa -gnatybfhiklnprtu
OPT_FLAGS = -O2
```

| Flag | Description |
|------|-------------|
| `-gnata` | Enable assertions |
| `-gnatwae` | Warnings as errors |
| `-gnatVa` | Validity checks |
| `-gnatybfhiklnprtu` | Style checks |
| `-O2` | Optimization level 2 |

## Project Structure

```
riscv/
+-- src/           # Ada source files
+-- obj/           # Object files (generated)
+-- bin/           # Executables (generated)
+-- test/          # Test programs (C source and binaries)
+-- examples/      # Example programs
+-- profiles/      # Hardware profile configs
+-- doc/           # Documentation
+-- Makefile
```

## Building Test Programs

Requires RISC-V cross-compiler.

```bash
cd test
make           # Build all tests
make clean     # Remove generated files
```

### Toolchain Requirements

The test Makefile expects:
- `riscv32-unknown-elf-gcc`
- `riscv32-unknown-elf-objcopy`

Or modify `test/Makefile` for your toolchain prefix.

### Test Program Compilation

Each test is compiled with:
```bash
riscv32-unknown-elf-gcc -march=rv32imfd -mabi=ilp32d \
    -nostdlib -nostartfiles -T linker.ld \
    -o program.elf start.S program.c
```

## Running Tests

### Unit Tests

```bash
make test
```

Runs `test/test_peripherals.adb` which tests:
- CLINT timer peripheral
- GPIO peripheral
- Memory system integration
- Config profiles

### Program Tests

```bash
cd test
make test      # Run all test programs
make test-elf  # Run ELF versions
```

## Troubleshooting

### GNAT Not Found

```
make: gnatmake: Command not found
```

Install GNAT compiler:
```bash
sudo apt install gnat
```

### Style Errors

```
riscv-xxx.adb:123:45: (style) ...
```

The project uses strict style checking. Common issues:
- Mixed case (`in Out` should be `in out`)
- Missing spaces around operators
- Line too long (max ~79 characters)
- Trailing whitespace

### Linker Errors

```
undefined reference to `Ada.Text_IO...'
```

Ensure GNAT runtime is properly installed. Try:
```bash
sudo apt install libgnat-12  # Adjust version as needed
```

### Cross-Compiler Issues

For building test programs:
```bash
# Check if toolchain is available
which riscv32-unknown-elf-gcc

# If not, try riscv64 (can target rv32)
export PATH=/path/to/riscv-toolchain/bin:$PATH
```

## IDE Support

### VS Code

Install "Ada Language Server" extension. Create `.vscode/c_cpp_properties.json`:
```json
{
  "configurations": [{
    "name": "Ada",
    "includePath": ["${workspaceFolder}/src"]
  }]
}
```

### GNAT Studio

Open project directly - it auto-detects Ada files.

### Emacs

Use `ada-mode`:
```elisp
(require 'ada-mode)
```

## Continuous Integration

Example GitHub Actions workflow:

```yaml
name: Build
on: [push, pull_request]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Install GNAT
        run: sudo apt-get install -y gnat
      - name: Build
        run: make
      - name: Test
        run: make test
```
