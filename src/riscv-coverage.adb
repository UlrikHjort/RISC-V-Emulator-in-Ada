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

with Ada.Text_IO;  use Ada.Text_IO;
with RISCV.Symbols; use RISCV.Symbols;

package body RISCV.Coverage is

   ----------------
   -- Initialize --
   ----------------

   procedure Initialize (State : out Coverage_State) is
   begin
      State.Bits        := (others => False);
      State.Base_PC     := 0;
      State.Highest_Idx := 0;
      State.Initialized := False;
   end Initialize;

   ---------------
   -- Record_PC --
   ---------------

   procedure Record_PC (State : in out Coverage_State;
                        PC    : Memory_Address) is
      Idx : Natural;
   begin
      if not State.Initialized then
         State.Base_PC     := PC;
         State.Initialized := True;
      end if;

      if PC >= State.Base_PC then
         Idx := Natural ((PC - State.Base_PC) / 4);
         if Idx < Max_Coverage_Slots then
            State.Bits (Idx) := True;
            if Idx > State.Highest_Idx then
               State.Highest_Idx := Idx;
            end if;
         end if;
      end if;
   end Record_PC;

   procedure Record_PC (State : in out Coverage_State;
                        PC    : Memory_Address_64) is
   begin
      if PC <= Memory_Address_64 (Memory_Address'Last) then
         Record_PC (State, Memory_Address (PC));
      end if;
   end Record_PC;

   -----------------
   -- Dump_Report --
   -----------------

   procedure Dump_Report
     (State    : Coverage_State;
      Filename : String;
      Syms     : access Symbols.Symbol_Table)
   is
      F : File_Type;

      --  Count set bits in [Lo .. Hi]
      function Count_Covered (Lo, Hi : Natural) return Natural is
         N : Natural := 0;
      begin
         for I in Lo .. Hi loop
            if State.Bits (I) then
               N := N + 1;
            end if;
         end loop;
         return N;
      end Count_Covered;

      --  Format a percentage as "NNN.N%"
      function Pct (Covered, Total : Natural) return String is
         P100 : constant Natural := (if Total > 0
                                     then (Covered * 1000) / Total
                                     else 0);
         Int  : constant Natural := P100 / 10;
         Frac : constant Natural := P100 mod 10;
         function Img (N : Natural; W : Natural) return String is
            S : constant String := Natural'Image (N);
            Raw : constant String := S (S'First + 1 .. S'Last);
            Pad : String (1 .. W) := (others => '0');
            Ofs : constant Natural := W - Raw'Length;
         begin
            if Raw'Length >= W then
               return Raw;
            end if;
            Pad (Ofs + 1 .. W) := Raw;
            return Pad;
         end Img;
      begin
         return Img (Int, 3) & "." & Img (Frac, 1) & "%";
      end Pct;

   begin
      if not State.Initialized then
         return;
      end if;

      Create (F, Out_File, Filename);

      declare
         Total_Slots : constant Natural := State.Highest_Idx + 1;
         Total_Cov   : constant Natural := Count_Covered (0, State.Highest_Idx);
      begin
         Put_Line (F, "=== RISC-V Instruction Coverage Report ===");
         Put_Line (F, "Base PC : 0x" & Memory_Address'Image (State.Base_PC));
         Put_Line (F, "Slots   : " & Natural'Image (Total_Slots) &
                      "  (" & Natural'Image (Total_Slots * 4) & " bytes)");
         Put_Line (F, "Covered : " & Natural'Image (Total_Cov) &
                      " / " & Natural'Image (Total_Slots) &
                      "  " & Pct (Total_Cov, Total_Slots));
         New_Line (F);

         --  Per-function breakdown (requires symbol table with function syms)
         if Syms /= null and then Symbols.Get_Symbol_Count (Syms.all) > 0 then
            Put_Line (F, "--- Per-Function Coverage ---");
            Put_Line (F, "");

            declare
               Info    : Symbols.Symbol_Info;
               F_Count : Natural := 0;
            begin
               for I in 1 .. Symbols.Get_Symbol_Count (Syms.all) loop
                  if Symbols.Get_Symbol (Syms.all, I, Info) and then
                     Info.Sym_Type = Symbols.SYM_FUNCTION and then
                     Info.Size > 0
                  then
                     declare
                        Fn_Base : constant Memory_Address := Info.Address;
                        Fn_End  : constant Memory_Address :=
                                     Info.Address + Memory_Address (Info.Size);
                        Lo_Idx  : Natural;
                        Hi_Idx  : Natural;
                        Fn_Tot  : Natural;
                        Fn_Cov  : Natural;
                     begin
                        if Fn_Base >= State.Base_PC then
                           Lo_Idx := Natural
                             ((Fn_Base - State.Base_PC) / 4);
                           Hi_Idx := Natural
                             ((Fn_End - State.Base_PC) / 4);

                           if Hi_Idx > 0 then
                              Hi_Idx := Hi_Idx - 1;
                           end if;

                           if Lo_Idx < Max_Coverage_Slots then
                              if Hi_Idx >= Max_Coverage_Slots then
                                 Hi_Idx := Max_Coverage_Slots - 1;
                              end if;

                              Fn_Tot := Hi_Idx - Lo_Idx + 1;
                              Fn_Cov := Count_Covered (Lo_Idx, Hi_Idx);

                              declare
                                 Name : constant String :=
                                    Info.Name (1 .. Info.Name_Len);
                                 Pad  : String (1 .. 40) :=
                                    (others => ' ');
                                 Len  : constant Natural :=
                                    Natural'Min (Name'Length, 40);
                              begin
                                 Pad (1 .. Len) := Name (1 .. Len);
                                 Put_Line (F, Pad & " " &
                                    Pct (Fn_Cov, Fn_Tot) &
                                    "  (" & Natural'Image (Fn_Cov) &
                                    " /" & Natural'Image (Fn_Tot) & ")");
                                 F_Count := F_Count + 1;
                              end;
                           end if;
                        end if;
                     end;
                  end if;
               end loop;

               if F_Count = 0 then
                  Put_Line (F, "(no function symbols with size found)");
               end if;
            end;
         else
            Put_Line (F, "(no symbol table - run with an ELF file for per-function stats)");
         end if;
      end;

      Close (F);
   end Dump_Report;

end RISCV.Coverage;
