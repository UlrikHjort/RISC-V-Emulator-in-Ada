# Architecture

## Overview

The emulator is structured as a modular Ada application with clear separation between:
- Instruction decoding and execution
- Memory management
- Peripheral emulation
- Configuration and debugging



## Data Flow

```
                    +-------------+
                    |   main.adb  |
                    | (CLI, Init) |
                    +------+------+
                           |
              +------------+------------+
              |            |            |
              v            v            v
        +----------+ +----------+ +----------+
        | ELF Load | |  Config  | | Debugger |
        +----+-----+ +----+-----+ +----+-----+
             |            |            |
             +------------+------------+
                          |
                          v
                    +-----------+
                    |    CPU    |<--------------+
                    |  (state)  |               |
                    +-----+-----+               |
                          |                     |
        +-----------------+-----------------+   |
        |                 |                 |   |
        v                 v                 v   |
   +---------+      +----------+      +-------+ |
   | Decoder |----->|   ALU    |      | Memory| |
   +---------+      |   FPU    |      +---+---+ |
                    |  Vector  |          |     |
                    +----------+          |     |
                                          |     |
                    +---------------------+     |
                    |                           |
        +-----------+-----------+               |
        |           |           |               |
        v           v           v               |
   +--------+  +--------+  +--------+           |
   |  UART  |  | CLINT  |  |  GPIO  |           |
   +--------+  +--------+  +--------+           |
                    |                           |
                    +---------------------------+ 
```

## Key Types

### CPU State (`riscv-cpu.ads`)

```ada
type CPU_State is record
   PC        : Memory_Address;      -- Program counter
   Regs      : Register_File;       -- x0-x31 (32 integer registers)
   FRegs     : FP_Register_File;    -- f0-f31 (32 FP registers)
   VRegs     : Vector_Register_File; -- v0-v31 (32 vector registers)
   Halted    : Boolean;
   Exception : Exception_Code;
   -- Vector state
   VL        : Natural;             -- Vector length
   VTYPE     : Word;                -- Vector type register
   VLEN      : Natural;             -- Physical vector length (bits)
end record;
```

### Memory Unit (`riscv-memory.ads`)

```ada
type Memory_Unit is record
   Regions      : Region_Array;      -- Up to 16 memory regions
   Region_Count : Natural;
   Use_Regions  : Boolean;           -- Region vs flat mode
   -- Peripherals
   UART         : UART_Access;
   CLINT        : CLINT_Access;
   GPIO         : GPIO_Access;
   -- Status
   Last_Result  : Access_Result;
end record;

type Memory_Region is record
   Name   : String (1..16);
   Base   : Memory_Address;
   Size   : Word;
   Rtype  : Region_Type;            -- RAM, ROM, Flash, IO
   Perm   : Access_Permission;      -- Read/Write/Execute
   Data   : Region_Data_Access;
end record;
```

### Hardware Profile (`riscv-config.ads`)

```ada
type Hardware_Profile is record
   Name            : String (1..32);
   Memory_Regions  : Memory_Region_Config_Array;
   Num_Regions     : Natural;
   Peripherals     : Peripheral_Config_Array;
   Num_Peripherals : Natural;
   CPU             : CPU_Config;
end record;
```

## Execution Flow

1. **Initialization**
   - Parse command line arguments
   - Load hardware profile (built-in or from file)
   - Initialize memory system with regions
   - Enable configured peripherals
   - Load program (ELF or binary)

2. **Fetch-Decode-Execute Loop**
   ```ada
   while not CPU.Halted loop
      Instruction := Memory.Read_Word (CPU.PC);
      Decoded := Decoder.Decode (Instruction);
      Execute (CPU, Decoded, Memory);
      CPU.PC := CPU.PC + 4;  -- or branch target
   end loop;
   ```

3. **Instruction Execution**
   - Decoder extracts opcode, registers, immediates
   - Routes to appropriate unit (ALU, FPU, Vector, Memory, Branch)
   - Results written to registers or memory
   - PC updated (increment or branch)

4. **Memory Access**
   - Check peripheral address ranges first (UART, CLINT, GPIO)
   - Find matching memory region
   - Verify permissions
   - Perform read/write operation

5. **Termination**
   - `ecall` instruction triggers halt
   - Exception sets halt flag
   - Debugger `quit` command
   - Max instruction count (if set)

## Extension Points

### Adding a New Peripheral

1. Create `riscv-newperiph.ads/adb`
2. Define state record and register offsets
3. Implement `Initialize`, `Read_Byte/Word`, `Write_Byte/Word`
4. Add to `Memory_Unit` in `riscv-memory.ads`
5. Add enable/disable procedures in `riscv-memory.adb`
6. Update `Apply_Profile` in `riscv-config.adb`

### Adding New Instructions

1. Add opcode/funct constants to `riscv.ads`
2. Update `Decoder.Decode` to recognize instruction
3. Implement execution in appropriate unit (ALU, FPU, Vector)
4. Add disassembly in `riscv-disasm.adb`
