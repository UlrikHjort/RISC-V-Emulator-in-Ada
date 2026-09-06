# RISC-V Emulator - GDB Remote Debugging Guide

This guide covers using the GDB Remote Serial Protocol (RSP) server to debug RISC-V programs with standard GDB.

## Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [GDB Server Setup](#gdb-server-setup)
- [Connecting with GDB](#connecting-with-gdb)
- [GDB Commands](#gdb-commands)
- [Debugging Workflows](#debugging-workflows)
- [Troubleshooting](#troubleshooting)

---

## Overview

The RISC-V emulator includes a GDB Remote Serial Protocol (RSP) server that allows you to use standard GDB for debugging.

### Why Use GDB?

- **Industry standard** - Familiar tool for most developers
- **IDE integration** - Works with VS Code, Eclipse, CLion
- **Powerful features** - Advanced breakpoints, expressions, scripting
- **Standard workflow** - Same commands as hardware debugging

### Architecture

```

                       TCP/IP         
               <---------------------->
     GDB           Port 1234               RISC-V Emulator  
                 (RSP Protocol)             (GDB Server)    
                        |                     |
                        ----------------------

```

---

## Quick Start

### 1. Start the GDB Server

Terminal 1:
```bash
./bin/riscv_emulator --gdb programs/out/elf/hello.elf

# Or with custom port:
./bin/riscv_emulator --gdb 5555 programs/out/elf/hello.elf
```

Output:
```
Loading ELF file: programs/out/elf/hello.elf
GDB server listening on port 1234
Waiting for GDB connection...
```

### 2. Connect with GDB

Terminal 2:
```bash
riscv32-unknown-elf-gdb programs/out/elf/hello.elf

(gdb) target remote localhost:1234
(gdb) break main
(gdb) continue
(gdb) step
(gdb) info registers
(gdb) quit
```

---

## GDB Server Setup

### Starting the Server

#### Default Port (1234)

```bash
./bin/riscv_emulator --gdb program.elf
```

#### Custom Port

```bash
./bin/riscv_emulator --gdb 5555 program.elf
```

Port ranges:
- **1024-49151** - Recommended user ports
- **49152-65535** - Dynamic/private ports
- **Default: 1234** - Standard GDB remote port

### Server Status

When started, you'll see:
```
GDB server listening on port 1234
Waiting for GDB connection...
```

When GDB connects:
```
GDB connected from 127.0.0.1:54321
```

### Stopping the Server

- Press `Ctrl+C` in the emulator terminal
- Or close the GDB connection: `(gdb) quit`

---

## Connecting with GDB

### Required: RISC-V GDB

You need the RISC-V cross-compiled GDB:

```bash
# Check if installed
riscv32-unknown-elf-gdb --version

# If not installed, install RISC-V toolchain:
# Ubuntu/Debian:
sudo apt-get install gcc-riscv64-unknown-elf gdb-multiarch

# Or build from source
```

### Connection Methods

#### Method 1: Interactive

```bash
riscv32-unknown-elf-gdb program.elf

(gdb) target remote localhost:1234
Remote debugging using localhost:1234
0x80000000 in ?? ()

(gdb) break main
Breakpoint 1 at 0x800000bc

(gdb) continue
```

#### Method 2: Command Line

```bash
riscv32-unknown-elf-gdb program.elf \
    -ex "target remote localhost:1234" \
    -ex "break main" \
    -ex "continue"
```

#### Method 3: Script File

Create `debug.gdb`:
```gdb
target remote localhost:1234
break main
continue
list
info registers
```

Run:
```bash
riscv32-unknown-elf-gdb program.elf -x debug.gdb
```

### Verifying Connection

After connecting:
```gdb
(gdb) info threads
  Id   Target Id         Frame
* 1    Thread 1          0x80000000 in ?? ()

(gdb) info registers
ra             0x0      0
sp             0x80100000       2148532224
...
```

---

## GDB Commands

### Execution Control

```gdb
# Run until breakpoint or halt
(gdb) continue
(gdb) c

# Single step (one instruction)
(gdb) stepi
(gdb) si

# Step (one source line - if debug info available)
(gdb) step
(gdb) s

# Next (step over function calls)
(gdb) next
(gdb) n
```

### Breakpoints

```gdb
# Set breakpoint at address
(gdb) break *0x80000100
Breakpoint 1 at 0x80000100

# Set breakpoint at function (requires symbols)
(gdb) break main
Breakpoint 2 at 0x800000bc: file main.c, line 10.

# List breakpoints
(gdb) info breakpoints
Num     Type           Disp Enb Address    What
1       breakpoint     keep y   0x80000100
2       breakpoint     keep y   0x800000bc in main at main.c:10

# Delete breakpoint
(gdb) delete 1

# Disable/enable breakpoint
(gdb) disable 2
(gdb) enable 2

# Clear all breakpoints
(gdb) delete
```

### Hardware Watchpoints

The emulator supports three types of hardware watchpoints (up to 32 of each type):

```gdb
# Write watchpoint - fires when the address is written
(gdb) watch *0x80001000
Hardware watchpoint 1: *0x80001000

# Read watchpoint - fires when the address is read
(gdb) rwatch *0x80001000
Hardware watchpoint 2: *0x80001000

# Access watchpoint - fires on either read or write
(gdb) awatch *0x80001000
Hardware watchpoint 3: *0x80001000

# Remove a watchpoint
(gdb) delete 1
```

#### Watchpoint Stop-Reply Packets

When a watchpoint fires, the emulator sends a typed stop-reply packet so GDB correctly
identifies the cause and displays the triggering address:

| Watchpoint type | RSP stop-reply sent |
|-----------------|---------------------|
| Write (Z2) | `T05 watch:ADDR; 02:sp; 20:pc;` |
| Read (Z3) | `T05 rwatch:ADDR; 02:sp; 20:pc;` |
| Access (Z4) | `T05 awatch:ADDR; 02:sp; 20:pc;` |

GDB will print `Hardware watchpoint N: hit` and show the address that triggered it,
rather than a generic SIGTRAP.

Example session:

```gdb
(gdb) awatch *0x80001000        # access watchpoint
Hardware watchpoint 1: *0x80001000

(gdb) continue
Hardware watchpoint 1: *0x80001000
...
(gdb) backtrace
(gdb) info registers
```

### Examining Memory

```gdb
# Examine memory (various formats)
(gdb) x/10x 0x80000000          # 10 words in hex
(gdb) x/10i 0x80000000          # 10 instructions
(gdb) x/20b 0x80000000          # 20 bytes
(gdb) x/4wx 0x80000000          # 4 words in hex

# Display string
(gdb) x/s 0x80001000

# Watch memory location
(gdb) watch *0x80100000
Hardware watchpoint 3: *0x80100000
```

### Examining Registers

```gdb
# Show all registers
(gdb) info registers
ra             0x80000000       2147483648
sp             0x80100000       2148532224
...

# Show specific register
(gdb) print $pc
$1 = (void (*)()) 0x80000000

(gdb) print/x $sp
$2 = 0x80100000

# Set register value
(gdb) set $a0 = 0x12345678
```

### Stack and Backtrace

```gdb
# Show backtrace (call stack)
(gdb) backtrace
(gdb) bt

#0  0x800007d0 in printf ()
#1  0x800017a4 in main ()

# Show detailed backtrace
(gdb) bt full

# Select frame
(gdb) frame 1
#1  0x800017a4 in main ()

# Info about current frame
(gdb) info frame
```

### Disassembly

```gdb
# Disassemble current location
(gdb) disassemble
Dump of assembler code for function main:
   0x80000100 <+0>:     addi    sp,sp,-32
   0x80000104 <+4>:     sw      ra,28(sp)
=> 0x80000108 <+8>:     sw      s0,24(sp)
...

# Disassemble specific function
(gdb) disassemble main

# Disassemble address range
(gdb) disassemble 0x80000100,0x80000120
```

### Variables and Expressions

```gdb
# Print variable (requires debug symbols)
(gdb) print variable_name

# Print with format
(gdb) print/x variable_name     # Hex
(gdb) print/d variable_name     # Decimal
(gdb) print/t variable_name     # Binary
(gdb) print/c variable_name     # Character

# Evaluate expression
(gdb) print $a0 + $a1
(gdb) print *(int*)0x80100000
```

---

## Debugging Workflows

### Workflow 1: Basic Debugging Session

```bash
# Terminal 1: Start GDB server
./bin/riscv_emulator --gdb programs/out/elf/hello.elf
```

```gdb
# Terminal 2: Connect and debug
riscv32-unknown-elf-gdb programs/out/elf/hello.elf

(gdb) target remote localhost:1234
(gdb) break main
Breakpoint 1 at 0x800000bc

(gdb) continue
Breakpoint 1, 0x800000bc in main ()

(gdb) disassemble
(gdb) info registers
(gdb) stepi
(gdb) stepi
(gdb) info registers

(gdb) continue
Program completed

(gdb) quit
```

### Workflow 2: Debugging with Source Code

Requires program compiled with `-g`:

```bash
riscv32-unknown-elf-gcc -g -o program.elf program.c
```

```gdb
# Terminal 1
./bin/riscv_emulator --gdb program.elf

# Terminal 2
riscv32-unknown-elf-gdb program.elf

(gdb) target remote localhost:1234
(gdb) break main
(gdb) continue

# Now can use source-level commands
(gdb) list              # Show source code
(gdb) step              # Step source lines
(gdb) next              # Step over function calls
(gdb) print var         # Print variables
(gdb) continue
```

### Workflow 3: Automated Debugging Script

Create `auto_debug.gdb`:
```gdb
# Connect
target remote localhost:1234

# Set breakpoints
break main
break printf

# Run to first breakpoint
continue

# Show state
info registers
backtrace

# Continue to next breakpoint
continue

# Examine
x/10i $pc
info registers

# Run to completion
continue
```

Run:
```bash
# Terminal 1
./bin/riscv_emulator --gdb program.elf

# Terminal 2
riscv32-unknown-elf-gdb program.elf -x auto_debug.gdb
```

### Workflow 4: Memory Inspection

```gdb
(gdb) target remote localhost:1234
(gdb) break main
(gdb) continue

# Examine stack
(gdb) x/32wx $sp
(gdb) x/10i $pc

# Watch for memory writes
(gdb) watch *0x80100000
(gdb) continue

# When watchpoint hits, GDB shows the typed reason and address
Hardware watchpoint 1: *0x80100000
Old value = 0
New value = 12345

(gdb) backtrace
(gdb) info registers
```

---

## IDE Integration

### VS Code

Install extensions:
- **Cortex-Debug** (for embedded debugging)
- **C/C++** (Microsoft)

Create `.vscode/launch.json`:
```json
{
    "version": "0.2.0",
    "configurations": [
        {
            "name": "Debug RISC-V",
            "type": "cppdbg",
            "request": "launch",
            "program": "${workspaceFolder}/program.elf",
            "miDebuggerPath": "riscv32-unknown-elf-gdb",
            "miDebuggerServerAddress": "localhost:1234",
            "setupCommands": [
                {
                    "description": "Enable pretty-printing",
                    "text": "-enable-pretty-printing",
                    "ignoreFailures": true
                }
            ]
        }
    ]
}
```

Usage:
1. Start emulator: `./bin/riscv_emulator --gdb program.elf`
2. Press F5 in VS Code
3. Use VS Code debugging UI

### Eclipse

1. Window -> Preferences -> GDB
2. Set GDB Command: `riscv32-unknown-elf-gdb`
3. Run -> Debug Configurations -> C/C++ Remote Application
4. Connection: `localhost:1234`

### CLion

1. Run -> Edit Configurations
2. Add "Remote GDB Server"
3. Target: `localhost:1234`
4. Symbol file: `program.elf`
5. Debugger: `riscv32-unknown-elf-gdb`

---

## Troubleshooting

### "Connection refused"

**Cause:** GDB server not running or wrong port

**Solution:**
```bash
# Check server is running
./bin/riscv_emulator --gdb program.elf

# Try connection again
(gdb) target remote localhost:1234
```

### "Remote communication error"

**Cause:** Connection lost or protocol mismatch

**Solution:**
- Restart GDB server
- Ensure using `riscv32-unknown-elf-gdb` (not regular gdb)
- Check firewall rules

### "Cannot access memory at address 0x..."

**Cause:** Invalid memory address or unmapped region

**Solution:**
```gdb
# Check valid memory ranges
(gdb) info mem

# Only access valid ranges (typically 0x80000000+)
```

### "No symbol table loaded"

**Cause:** ELF file has no symbols or symbols stripped

**Solution:**
```bash
# Recompile with debug symbols
riscv32-unknown-elf-gcc -g -o program.elf program.c

# Or use addresses instead of symbols
(gdb) break *0x80000100
```

### Server Won't Start

**Cause:** Port already in use

**Solution:**
```bash
# Check what's using port
netstat -tln | grep 1234
# or
ss -tln | grep 1234

# Use different port
./bin/riscv_emulator --gdb 5555 program.elf
(gdb) target remote localhost:5555
```

---

## Advanced Topics

### GDB Python Scripting

GDB supports Python for automation:

```python
# script.py
import gdb

class CustomCommand(gdb.Command):
    def __init__(self):
        super(CustomCommand, self).__init__("custom", gdb.COMMAND_USER)

    def invoke(self, arg, from_tty):
        # Get PC
        pc = gdb.parse_and_eval("$pc")
        print(f"PC = {pc}")

        # Read memory
        mem = gdb.inferiors()[0].read_memory(pc, 16)
        print(f"Memory: {mem.hex()}")

CustomCommand()
```

Load in GDB:
```gdb
(gdb) source script.py
(gdb) custom
```

### Conditional Breakpoints

```gdb
# Break only when condition is true
(gdb) break main if $a0 == 5

# Set condition on existing breakpoint
(gdb) condition 1 $a0 > 10

# Remove condition
(gdb) condition 1
```

### Command Hooks

Run commands automatically when breakpoint hits:

```gdb
(gdb) break main
(gdb) commands 1
>info registers
>x/10i $pc
>continue
>end
```

Now when breakpoint 1 hits, it automatically shows registers and disassembly.

---

## Command Quick Reference

| Command | Shorthand | Description |
|---------|-----------|-------------|
| `target remote HOST:PORT` | | Connect to GDB server |
| `break LOCATION` | `b` | Set breakpoint |
| `continue` | `c` | Continue execution |
| `stepi` | `si` | Step one instruction |
| `step` | `s` | Step one source line |
| `next` | `n` | Step over function |
| `backtrace` | `bt` | Show call stack |
| `info registers` | `i r` | Show registers |
| `info breakpoints` | `i b` | List breakpoints |
| `disassemble` | `disas` | Disassemble code |
| `examine` | `x` | Examine memory |
| `print` | `p` | Print expression |
| `quit` | `q` | Exit GDB |

---

## See Also

- [Debugging Guide](DEBUGGING.md) - Interactive debugger
- [Profiling Guide](PROFILING.md) - Performance profiling
- [GDB Documentation](https://sourceware.org/gdb/documentation/) - Official GDB docs
- [README.md](README.md) - Main documentation
