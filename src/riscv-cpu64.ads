-- ***************************************************************************
--                RISC-V Emulator - 64-bit CPU Core (RV64)
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
with RISCV.CSR64;
with RISCV.MMU;

package RISCV.CPU64 is

   --  Trace configuration for RV64
   type Trace_Config is record
      Enabled      : Boolean := False;
      PC_Start     : Memory_Address_64 := 0;
      PC_End       : Memory_Address_64 := Memory_Address_64'Last;
      Show_Memory  : Boolean := False;
      Show_Regs    : Boolean := False;
   end record;

   type CPU64_State is record
      Registers         : Register_File_64;
      FP                : aliased FPU.FPU_State;
      VU                : Vector.Vector_State;
      CSRs              : CSR64.CSR_State_64;
      PC                : Memory_Address_64;
      Reset_Vector      : Memory_Address_64;
      Halted            : Boolean;
      Exception_Code    : RISCV.Exception_Code;
      --  A Extension: Load-Reserved / Store-Conditional state
      Reserved_Addr     : Memory_Address_64;
      Reservation_Valid : Boolean;
      --  Privilege level tracking
      Priv_Mode         : Privilege_Level;
      --  Sv39 MMU state
      MMU               : RISCV.MMU.MMU_State;
      --  RV64E: 16-register subset
      Rv32e             : Boolean := False;
      --  Hart identifier (0 = boot hart). Selects this hart's CLINT
      --  mtimecmp/msip lane, exactly as on the 32-bit core.
      Hart_ID           : Natural := 0;
   end record;

   --  Initialize CPU state
   procedure Initialize (CPU      : out CPU64_State;
                         Start_PC : Double_Word := 0);

   --  Execute a single instruction
   procedure Step (CPU       : in out CPU64_State;
                   Mem       : in out Memory.Memory_Unit;
                   Trace     : Boolean := False;
                   Trace_Cfg : Trace_Config := (Enabled => False, others => <>));

   --  Run until halted or max cycles reached
   procedure Run (CPU        : in out CPU64_State;
                  Mem        : in out Memory.Memory_Unit;
                  Trace      : Boolean := False;
                  Trace_Cfg  : Trace_Config := (Enabled => False, others => <>);
                  Max_Cycles : Natural := Natural'Last);

   --  Read a register (respects x0 = 0)
   function Read_Register (CPU : CPU64_State;
                           Reg : Register_Index) return Double_Word;

   --  Write a register (ignores writes to x0)
   procedure Write_Register (CPU   : in out CPU64_State;
                              Reg   : Register_Index;
                              Value : Double_Word);

   --  Dump CPU state for debugging
   procedure Dump_State (CPU : CPU64_State);

   --  Trap entry: save state and jump to trap handler
   procedure Trap_Entry (CPU   : in out CPU64_State;
                         Cause : Double_Word;
                         Tval  : Double_Word := 0);

   --  MRET: return from machine trap handler
   procedure Mret (CPU : in out CPU64_State);

   --  SRET: return from supervisor trap handler
   procedure Sret (CPU : in out CPU64_State);

   --  Check and handle pending interrupts
   --  Returns True if an interrupt was taken
   function Check_Interrupts (CPU : in out CPU64_State;
                               Mem : in out Memory.Memory_Unit) return Boolean;

   --  Add cache-stall cycles to mcycle (respects Mcountinhibit CY bit)
   procedure Add_Cycle_Stalls (CPU   : in out CPU64_State;
                                Count : Natural);

end RISCV.CPU64;
