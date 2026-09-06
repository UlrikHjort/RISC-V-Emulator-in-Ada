-- ***************************************************************************
--               RISC-V Emulator - Instruction Coverage Tracker
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

--  Instruction-level coverage tracking.
--  Records which instruction addresses were executed and emits a report
--  with overall % covered plus per-function breakdown (when symbols present).
with RISCV.Symbols;

package RISCV.Coverage is

   --  Maximum number of 32-bit instruction slots tracked.
   --  262144 slots * 4 bytes = 1 MB of address space - enough for any
   --  test program in this emulator.
   Max_Coverage_Slots : constant := 262_144;

   --  Packed bitmap: 1 bit per slot, ~32 KB total.
   type Coverage_Bitmap is array (0 .. Max_Coverage_Slots - 1) of Boolean;
   pragma Pack (Coverage_Bitmap);

   type Coverage_State is record
      Bits        : Coverage_Bitmap;
      Base_PC     : Memory_Address;
      Highest_Idx : Natural;
      Initialized : Boolean;
   end record;

   --  Pointer type used when allocating on the heap (avoids large stack frame)
   type Coverage_State_Ptr is access all Coverage_State;

   --  Initialize coverage tracker
   procedure Initialize (State : out Coverage_State);

   --  Record a PC visit (hot path - called once per instruction)
   procedure Record_PC (State : in out Coverage_State;
                        PC    : Memory_Address);

   --  Write coverage report to File.
   --  Syms may be null; if non-null and loaded, per-function stats are shown.
   procedure Dump_Report
     (State    : Coverage_State;
      Filename : String;
      Syms     : access Symbols.Symbol_Table);

end RISCV.Coverage;
