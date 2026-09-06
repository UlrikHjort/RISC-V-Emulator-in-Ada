-- ***************************************************************************
--             RISC-V Emulator - Interactive Debugger
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

with RISCV.CPU;
with RISCV.CPU64;
with RISCV.Memory;
with RISCV.Symbols;

package RISCV.Debugger is

   Max_Breakpoints : constant := 16;
   Max_Watchpoints : constant := 16;

   --  Addresses stored as Double_Word so both RV32 and RV64 can share state.
   --  RV32 addresses are zero-extended when stored.
   type Breakpoint_Array is array (1 .. Max_Breakpoints) of Double_Word;
   type Breakpoint_Active is array (1 .. Max_Breakpoints) of Boolean;

   --  Watchpoint types
   type Watchpoint_Type is (Read, Write, ReadWrite);

   type Watchpoint_Record is record
      Address : Double_Word;
      WType   : Watchpoint_Type;
   end record;

   type Watchpoint_Array is array (1 .. Max_Watchpoints) of Watchpoint_Record;
   type Watchpoint_Active is array (1 .. Max_Watchpoints) of Boolean;

   type Symbol_Table_Ptr is access Symbols.Symbol_Table;

   type Debugger_State is record
      Breakpoints        : Breakpoint_Array;
      Breakpoint_Enabled : Breakpoint_Active;
      Num_Breakpoints    : Natural;
      Watchpoints        : Watchpoint_Array;
      Watchpoint_Enabled : Watchpoint_Active;
      Num_Watchpoints    : Natural;
      Quit_Requested     : Boolean;
      Watchpoint_Hit     : Boolean;
      Last_Watch_Addr    : Double_Word;
      Last_Watch_Type    : Watchpoint_Type;
      Symbols            : Symbol_Table_Ptr;
      Symbols_Loaded     : Boolean;
      Trace_Enabled      : Boolean;
      Trace_File_Open    : Boolean;
   end record;

   --  Initialize debugger state
   procedure Initialize (Dbg : out Debugger_State);

   --  Load symbols from ELF file
   procedure Load_Symbols (Dbg : in out Debugger_State;
                          Filename : String);

   --  Run the interactive debugger loop (RV32)
   procedure Run (Dbg : in out Debugger_State;
                  CPU : in out RISCV.CPU.CPU_State;
                  Mem : in out Memory.Memory_Unit);

   --  Run the interactive debugger loop (RV64)
   procedure Run (Dbg : in out Debugger_State;
                  CPU : in out RISCV.CPU64.CPU64_State;
                  Mem : in out Memory.Memory_Unit);

   --  Check if current PC is at a breakpoint
   function At_Breakpoint (Dbg : Debugger_State;
                           PC  : Double_Word) return Boolean;

   --  Add a breakpoint
   procedure Add_Breakpoint (Dbg     : in out Debugger_State;
                             Address : Double_Word;
                             Success : out Boolean);

   --  Remove a breakpoint by index
   procedure Remove_Breakpoint (Dbg     : in out Debugger_State;
                                Index   : Positive;
                                Success : out Boolean);

   --  List all breakpoints
   procedure List_Breakpoints (Dbg : Debugger_State);

   --  Add a watchpoint
   procedure Add_Watchpoint (Dbg     : in out Debugger_State;
                             Address : Double_Word;
                             WType   : Watchpoint_Type;
                             Success : out Boolean);

   --  Remove a watchpoint by index
   procedure Remove_Watchpoint (Dbg     : in out Debugger_State;
                                Index   : Positive;
                                Success : out Boolean);

   --  List all watchpoints
   procedure List_Watchpoints (Dbg : Debugger_State);

   --  Check if memory access hits a watchpoint
   function Check_Watchpoint (Dbg       : in out Debugger_State;
                              Address   : Double_Word;
                              Is_Write  : Boolean) return Boolean;

   --  Show call stack backtrace (RV32)
   procedure Show_Backtrace (Dbg : Debugger_State;
                            CPU : RISCV.CPU.CPU_State;
                            Mem : in out RISCV.Memory.Memory_Unit;
                            Max_Frames : Natural := 20);

   --  Show call stack backtrace (RV64)
   procedure Show_Backtrace (Dbg : Debugger_State;
                            CPU : RISCV.CPU64.CPU64_State;
                            Mem : in out RISCV.Memory.Memory_Unit;
                            Max_Frames : Natural := 20);

end RISCV.Debugger;
