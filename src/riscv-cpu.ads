-- ***************************************************************************
--                RISC-V Emulator - CPU Core
--
--           Copyright (C) 2026 By Ulrik Hørlyk Hjort
--
-- Permission is hereby granted, free of charge, to any person obtaining
-- a copy of this software and associated documentation files (the
-- "Software"), to deal in the Software without restriction, including
-- without limitation the rights to use, copy, modify, merge, publish,
-- distribute, sublicense, and/or sell copies of the Software, and to
-- permit persons to whom the Software is furnished to do so, subject to
-- the following conditions:
--
-- The above copyright notice and this permission notice shall be
-- included in all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
-- EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
-- MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
-- NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
-- LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
-- OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
-- WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
-- ***************************************************************************

with RISCV.Memory;
with RISCV.FPU;
with RISCV.Vector;
with RISCV.CSR;

package RISCV.CPU is

   --  Trace configuration
   type Trace_Config is record
      Enabled      : Boolean := False;       -- Enable tracing
      PC_Start     : Memory_Address := 0;    -- Start of PC range
      PC_End       : Memory_Address := Memory_Address'Last; -- End of PC range
      Show_Memory  : Boolean := False;       -- Log memory accesses
      Show_Regs    : Boolean := False;       -- Show register changes
   end record;

   type CPU_State is record
      Registers      : Register_File;
      FP             : aliased FPU.FPU_State;
      VU             : Vector.Vector_State;
      CSRs           : CSR.CSR_State;
      PC             : Word;
      Reset_Vector   : Word;  -- Initial PC for system reset
      Halted         : Boolean;
      Exception_Code : RISCV.Exception_Code;
      --  A Extension: Load-Reserved / Store-Conditional state
      Reserved_Addr  : Memory_Address;  -- Address from LR instruction
      Reservation_Valid : Boolean;      -- True if reservation is active
      --  Privilege level tracking
      Priv_Mode      : Privilege_Level; -- Current privilege level
      --  Multi-hart support
      Hart_ID        : Natural;         -- Hart identifier (0 = boot hart)
      --  RV32E: 16-register subset
      Rv32e : Boolean := False;
      --  Pipeline hazard tracking (for cycle-accurate stall model)
      Last_Load_Rd  : Register_Index := 0;   -- Rd of most recent load instruction
      Last_Was_Load : Boolean := False;       -- True if previous instruction was a load
   end record;

   --  Initialize CPU state
   procedure Initialize (CPU : out CPU_State; Start_PC : Word := 0);

   --  Execute a single instruction
   procedure Step (CPU         : in out CPU_State;
                   Mem         : in out Memory.Memory_Unit;
                   Trace       : Boolean := False;
                   Trace_Cfg   : Trace_Config := (Enabled => False, others => <>));

   --  Run until halted or max cycles reached
   procedure Run (CPU        : in out CPU_State;
                  Mem        : in out Memory.Memory_Unit;
                  Trace      : Boolean := False;
                  Trace_Cfg  : Trace_Config := (Enabled => False, others => <>);
                  Max_Cycles : Natural := Natural'Last);

   --  Read a register (respects x0 = 0)
   function Read_Register (CPU : CPU_State;
                           Reg : Register_Index) return Word;

   --  Write a register (ignores writes to x0)
   procedure Write_Register (CPU   : in out CPU_State;
                             Reg   : Register_Index;
                             Value : Word);

   --  Dump CPU state for debugging
   procedure Dump_State (CPU : CPU_State);

   --  Trap entry: save state and jump to trap handler
   --  If trap handling is enabled (mtvec != 0), vectors to handler.
   --  Otherwise falls back to halt behavior.
   procedure Trap_Entry (CPU   : in out CPU_State;
                         Cause : Word;
                         Tval  : Word := 0);

   --  MRET: return from machine trap handler
   procedure Mret (CPU : in out CPU_State);

   --  SRET: return from supervisor trap handler
   procedure Sret (CPU : in out CPU_State);

   --  Check and handle pending interrupts
   --  Returns True if an interrupt was taken
   function Check_Interrupts (CPU : in out CPU_State;
                              Mem : Memory.Memory_Unit) return Boolean;

   --  Add cache-stall cycles to mcycle (respects Mcountinhibit CY bit)
   procedure Add_Cycle_Stalls (CPU   : in out CPU_State;
                                Count : Natural);

end RISCV.CPU;
