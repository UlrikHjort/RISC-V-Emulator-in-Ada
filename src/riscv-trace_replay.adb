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

package body RISCV.Trace_Replay is

   -------------------------
   -- Open_For_Recording  --
   -------------------------

   procedure Open_For_Recording (State    : out Recorder_State;
                                 Filename : String) is
   begin
      State.Count := 0;
      State.Open  := False;
      Trace_IO.Create (State.File, Trace_IO.Out_File, Filename);
      State.Open := True;
   end Open_For_Recording;

   ------------
   -- Append --
   ------------

   procedure Append (State    : in out Recorder_State;
                     PC       : Word;
                     Encoding : Word;
                     Rd       : Word;
                     Rd_Value : Word;
                     Next_PC  : Word) is
      Rec : constant Trace_Record :=
        (PC       => PC,
         Encoding => Encoding,
         Rd       => Rd,
         Rd_Value => Rd_Value,
         Next_PC  => Next_PC);
   begin
      Trace_IO.Write (State.File, Rec);
      State.Count := State.Count + 1;
   end Append;

   ---------------------
   -- Close_Recorder  --
   ---------------------

   procedure Close_Recorder (State : in out Recorder_State) is
   begin
      if State.Open then
         Trace_IO.Close (State.File);
         State.Open := False;
      end if;
   end Close_Recorder;

   ----------------------
   -- Open_For_Replay  --
   ----------------------

   procedure Open_For_Replay (State    : out Replayer_State;
                              Filename : String) is
   begin
      State.Step_Count := 0;
      State.Mismatches := 0;
      State.Open       := False;
      Trace_IO.Open (State.File, Trace_IO.In_File, Filename);
      State.Open := True;
   end Open_For_Replay;

   -----------------
   -- Check_Step  --
   -----------------

   procedure Check_Step (State           : in out Replayer_State;
                         Actual_PC       : Word;
                         Actual_Next_PC  : Word;
                         Actual_Rd       : Word;
                         Actual_Rd_Value : Word;
                         Result          : out Replay_Result;
                         Mismatch_Msg    : out String;
                         Msg_Len         : out Natural)
   is
      Rec : Trace_Record;
   begin
      Mismatch_Msg := (others => ' ');
      Msg_Len      := 0;
      Result       := Match;

      if Trace_IO.End_Of_File (State.File) then
         Result := End_Of_Trace;
         return;
      end if;

      Trace_IO.Read (State.File, Rec);
      State.Step_Count := State.Step_Count + 1;

      --  Check PC
      if Actual_PC /= Rec.PC then
         Result := Mismatch;
      elsif Actual_Next_PC /= Rec.Next_PC then
         Result := Mismatch;
      elsif Rec.Rd /= 0 and then Actual_Rd = Rec.Rd and then
            Actual_Rd_Value /= Rec.Rd_Value
      then
         Result := Mismatch;
      end if;

      if Result = Mismatch then
         State.Mismatches := State.Mismatches + 1;

         --  Build mismatch message (fits in caller's 512-char buffer)
         declare
            Step_Img : constant String :=
               Long_Long_Integer'Image (State.Step_Count);
            Msg : String (1 .. 512) := (others => ' ');
            Pos : Natural := 0;

            procedure Append_Str (S : String) is
            begin
               if Pos + S'Length <= Msg'Last then
                  Msg (Pos + 1 .. Pos + S'Length) := S;
                  Pos := Pos + S'Length;
               end if;
            end Append_Str;

            function Hex8 (V : Word) return String is
               Hex_Chars : constant String := "0123456789abcdef";
               S : String (1 .. 8);
               N : Word := V;
            begin
               for I in reverse S'Range loop
                  S (I) := Hex_Chars (Natural (N and 16#F#) + 1);
                  N := Shift_Right (N, 4);
               end loop;
               return S;
            end Hex8;
         begin
            Append_Str ("MISMATCH at step");
            Append_Str (Step_Img);
            Append_Str (" PC=0x");
            Append_Str (Hex8 (Rec.PC));

            if Actual_PC /= Rec.PC then
               Append_Str (" actual_PC=0x");
               Append_Str (Hex8 (Actual_PC));
               Append_Str (" expected_PC=0x");
               Append_Str (Hex8 (Rec.PC));
            elsif Actual_Next_PC /= Rec.Next_PC then
               Append_Str (" next_PC=0x");
               Append_Str (Hex8 (Actual_Next_PC));
               Append_Str (" expected=0x");
               Append_Str (Hex8 (Rec.Next_PC));
            else
               Append_Str (" x");
               declare
                  Rd_Img : constant String :=
                     Word'Image (Rec.Rd);
               begin
                  Append_Str (Rd_Img (Rd_Img'First + 1 .. Rd_Img'Last));
               end;
               Append_Str ("=0x");
               Append_Str (Hex8 (Actual_Rd_Value));
               Append_Str (" expected=0x");
               Append_Str (Hex8 (Rec.Rd_Value));
            end if;

            Mismatch_Msg (Mismatch_Msg'First .. Mismatch_Msg'First + Pos - 1) :=
               Msg (1 .. Pos);
            Msg_Len := Pos;
         end;
      end if;

   exception
      when Trace_IO.End_Error =>
         Result := End_Of_Trace;
      when others =>
         Result := Replay_Error;
   end Check_Step;

   ----------------------
   -- Close_Replayer   --
   ----------------------

   procedure Close_Replayer (State : in out Replayer_State) is
   begin
      if State.Open then
         Trace_IO.Close (State.File);
         State.Open := False;
      end if;
   end Close_Replayer;

end RISCV.Trace_Replay;
