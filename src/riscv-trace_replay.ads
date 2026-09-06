-- ***************************************************************************
--           RISC-V Emulator - Instruction Trace / Replay
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

--  Binary instruction trace recording and replay.
--
--  Record format (20 bytes per instruction):
--    Offset  0 : PC       (Word) - program counter before execution
--    Offset  4 : Encoding (Word) - raw 32-bit instruction word
--    Offset  8 : Rd       (Word) - destination register index (0 = none)
--    Offset 12 : Rd_Value (Word) - value written to Rd after execution
--    Offset 16 : Next_PC  (Word) - program counter after execution
--
--  Recording: --irecord <file>
--    Captures every instruction executed to a binary file.
--
--  Replay:    --ireplay <file>
--    Runs the emulator and checks PC / Rd_Value / Next_PC against each
--    recorded entry.  Prints a MISMATCH line and stops on the first
--    divergence.

with Ada.Sequential_IO;

package RISCV.Trace_Replay is

   --  One 20-byte trace record
   type Trace_Record is record
      PC       : Word;
      Encoding : Word;
      Rd       : Word;   --  register index 0-31; 0 means x0 / no dest
      Rd_Value : Word;   --  value of Rd after instruction
      Next_PC  : Word;
   end record;

   for Trace_Record use record
      PC       at  0 range 0 .. 31;
      Encoding at  4 range 0 .. 31;
      Rd       at  8 range 0 .. 31;
      Rd_Value at 12 range 0 .. 31;
      Next_PC  at 16 range 0 .. 31;
   end record;
   for Trace_Record'Size use 160;

   package Trace_IO is new Ada.Sequential_IO (Trace_Record);

   --  =====================================================================
   --  Recorder
   --  =====================================================================

   type Recorder_State is record
      File   : Trace_IO.File_Type;
      Open   : Boolean := False;
      Count  : Long_Long_Integer := 0;
   end record;

   procedure Open_For_Recording (State    : out Recorder_State;
                                 Filename : String);

   --  Build and append one record.
   --  Call BEFORE CPU.Step (PC, Encoding taken before step).
   --  Call AFTER  CPU.Step for Next_PC / Rd_Value snapshot.
   procedure Append (State    : in out Recorder_State;
                     PC       : Word;
                     Encoding : Word;
                     Rd       : Word;
                     Rd_Value : Word;
                     Next_PC  : Word);

   procedure Close_Recorder (State : in out Recorder_State);

   --  =====================================================================
   --  Replayer
   --  =====================================================================

   type Replay_Result is (Match, Mismatch, End_Of_Trace, Replay_Error);

   type Replayer_State is record
      File        : Trace_IO.File_Type;
      Open        : Boolean := False;
      Step_Count  : Long_Long_Integer := 0;
      Mismatches  : Long_Long_Integer := 0;
   end record;

   procedure Open_For_Replay (State    : out Replayer_State;
                              Filename : String);

   --  Compare one step:
   --    Actual_PC, Actual_Next_PC, Actual_Rd, Actual_Rd_Value are from the
   --    emulator after executing one instruction.
   --  Returns Match or Mismatch; sets Mismatch_Msg on divergence.
   procedure Check_Step (State          : in out Replayer_State;
                         Actual_PC      : Word;
                         Actual_Next_PC : Word;
                         Actual_Rd      : Word;
                         Actual_Rd_Value : Word;
                         Result         : out Replay_Result;
                         Mismatch_Msg   : out String;
                         Msg_Len        : out Natural);

   procedure Close_Replayer (State : in out Replayer_State);

end RISCV.Trace_Replay;
