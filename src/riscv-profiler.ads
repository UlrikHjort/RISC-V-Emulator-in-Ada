-- ***************************************************************************
--                RISC-V Emulator - Profiler
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

-- Performance profiling for RISC-V programs
-- Tracks instruction counts, cycles, function call statistics,
-- and per-opcode / per-PC instruction histograms.
with RISCV.Symbols;

package RISCV.Profiler is

   --  Access type for symbol table
   type Symbol_Table_Ptr is access all Symbols.Symbol_Table;

   --  Profiler state
   type Profiler_State is limited private;

   --  Initialize profiler
   procedure Initialize (Prof : out Profiler_State;
                        Syms : Symbol_Table_Ptr);

   --  Record instruction execution (RV32)
   procedure Record_Instruction (Prof  : in out Profiler_State;
                                PC    : Memory_Address;
                                Instr : Word);

   --  Record instruction execution (RV64 - PC truncated to lower 32 bits
   --  for symbol lookup; profiler hot-PC table remains 32-bit wide)
   procedure Record_Instruction (Prof  : in out Profiler_State;
                                PC    : Memory_Address_64;
                                Instr : Word);

   --  Print profiling report (function + opcode + hot-PC sections)
   procedure Print_Report (Prof : Profiler_State);

   --  Print call graph
   procedure Print_Call_Graph (Prof : Profiler_State);

   --  Record cache stalls for this instruction (called after CPU.Step).
   --  Adds stall cycles to Total_Wall_Cycles and current function's Cycle_Count.
   procedure Record_Cache_Stalls (Prof     : in out Profiler_State;
                                  I_Stalls : Natural;
                                  I_Hit    : Boolean;
                                  D_Stalls : Natural;
                                  D_Hit    : Boolean;
                                  D_Valid  : Boolean);

   --  Export flamegraph data (folded stack format)
   procedure Export_Flamegraph (Prof : Profiler_State;
                               Filename : String);

private

   --  Use Long_Long_Integer for all cycle/count fields to avoid overflow
   --  on programs that run billions of instructions.
   subtype Cycle_Count_T is Long_Long_Integer;

   --  Function profile data
   type Function_Profile is record
      Name         : String (1 .. 256);
      Name_Len     : Natural := 0;
      Address      : Memory_Address := 0;
      Instr_Count  : Cycle_Count_T := 0;
      Cycle_Count  : Cycle_Count_T := 0;
      Call_Count   : Cycle_Count_T := 0;
      Stall_Count  : Cycle_Count_T := 0;
   end record;

   --  Maximum functions to track
   Max_Functions : constant := 256;

   type Function_Profile_Array is array (1 .. Max_Functions) of Function_Profile;

   --  Call stack entry
   type Call_Stack_Entry is record
      Function_Idx : Natural;
      Entry_Cycles : Cycle_Count_T;
   end record;

   Max_Call_Depth : constant := 128;

   type Call_Stack is array (1 .. Max_Call_Depth) of Call_Stack_Entry;

   --  Call graph edge (caller -> callee relationship)
   type Call_Edge is record
      Caller_Idx : Natural := 0;
      Callee_Idx : Natural := 0;
      Call_Count : Cycle_Count_T := 0;
   end record;

   Max_Call_Edges : constant := 1024;
   type Call_Edge_Array is array (1 .. Max_Call_Edges) of Call_Edge;

   --  Flamegraph sample (stack trace at a point in time)
   type Stack_Array is array (1 .. Max_Call_Depth) of Natural;

   type Flamegraph_Sample is record
      Stack        : Stack_Array;
      Depth        : Natural := 0;
      Sample_Count : Cycle_Count_T := 0;
   end record;

   Max_Samples : constant := 512;
   type Flamegraph_Sample_Array is array (1 .. Max_Samples) of Flamegraph_Sample;

   --  Per-opcode instruction histogram (7-bit opcode ->count)
   type Opcode_Hist is array (0 .. 127) of Cycle_Count_T;

   --  Hot-PC table: tracks the most-executed individual instructions.
   --  Linear probing; capped at Max_Hot_PCs entries.
   Max_Hot_PCs : constant := 1024;

   type Hot_PC_Entry is record
      PC    : Memory_Address := 0;
      Count : Cycle_Count_T  := 0;
      Valid : Boolean        := False;
   end record;

   type Hot_PC_Array is array (0 .. Max_Hot_PCs - 1) of Hot_PC_Entry;

   type Profiler_State is record
      Symbols         : Symbol_Table_Ptr;
      Functions       : Function_Profile_Array;
      Num_Functions   : Natural := 0;
      Total_Cycles    : Cycle_Count_T := 0;
      Call_Stack_Data : Call_Stack;
      Stack_Depth     : Natural := 0;
      Prev_Func_Idx   : Natural := 0;
      --  Call graph tracking
      Call_Edges      : Call_Edge_Array;
      Num_Edges       : Natural := 0;
      --  Flamegraph sampling
      Samples         : Flamegraph_Sample_Array;
      Num_Samples     : Natural := 0;
      Sample_Interval : Cycle_Count_T := 10_000;
      Next_Sample     : Cycle_Count_T := 0;
      --  Instruction-level histograms
      Opcode_Counts   : Opcode_Hist;
      Hot_PCs         : Hot_PC_Array;
      Hot_PC_Count    : Natural := 0;  -- distinct PCs seen so far
      --  Optimisation: only re-lookup the current function after a call/return
      --  transition.  Between transitions the cached index stays valid.
      Current_Func_Idx : Natural := 0;
      Need_Func_Update : Boolean := True;
      --  Cycle-accurate stall model
      Total_Wall_Cycles : Cycle_Count_T := 0;   --  instructions + stalls
      Stalls_Mul        : Cycle_Count_T := 0;   --  MUL/MULH stall cycles
      Stalls_Div        : Cycle_Count_T := 0;   --  DIV/REM stall cycles
      Stalls_FP         : Cycle_Count_T := 0;   --  FP arith/div/sqrt stall cycles
      Stalls_CSR        : Cycle_Count_T := 0;   --  CSR instruction stall cycles
      --  Cache miss stall tracking (populated when --cache is active)
      Cache_I_Hits    : Cycle_Count_T := 0;
      Cache_I_Misses  : Cycle_Count_T := 0;
      Cache_I_Stalls  : Cycle_Count_T := 0;
      Cache_D_Hits    : Cycle_Count_T := 0;
      Cache_D_Misses  : Cycle_Count_T := 0;
      Cache_D_Stalls  : Cycle_Count_T := 0;
      --  Pipeline hazard stall tracking
      Stalls_Load_Use : Cycle_Count_T := 0;   --  Load-use hazard stall cycles
      Stalls_Branch   : Cycle_Count_T := 0;   --  Branch/jump taken stall cycles
      --  State for dynamic stall detection (mirrors cpu.adb logic)
      Prof_Last_Load_Rd  : Natural  := 0;
      Prof_Last_Was_Load : Boolean  := False;
      Prof_Last_PC       : Memory_Address := 0;
      Prof_Last_Is_32bit : Boolean  := True;
   end record;

end RISCV.Profiler;
