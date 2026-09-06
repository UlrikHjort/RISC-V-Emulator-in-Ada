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

with Ada.Text_IO;
with Ada.Streams.Stream_IO;

package body RISCV.Profiler is

   use Ada.Text_IO;
   use type Symbols.Symbol_Type;

   --  Helper: Find or create function profile
   function Get_Function_Index (Prof : in out Profiler_State;
                                Addr : Memory_Address) return Natural;

   --  Helper: Detect if instruction is a function call
   function Is_Call_Instruction (Instr : Word; PC : Memory_Address) return Boolean;

   --  Helper: Detect if instruction is a function return
   function Is_Return_Instruction (Instr : Word) return Boolean;

   --  Helper: Record call edge in call graph
   procedure Record_Call_Edge (Prof : in out Profiler_State;
                               Caller_Idx : Natural;
                               Callee_Idx : Natural);

   --  Helper: Sample current call stack for flamegraph
   procedure Sample_Call_Stack (Prof : in out Profiler_State);

   --  Helper: Trim the leading space from Long_Long_Integer'Image
   function Img (V : Cycle_Count_T) return String is
      S : constant String := Cycle_Count_T'Image (V);
   begin
      if S'Length > 0 and then S (S'First) = ' ' then
         return S (S'First + 1 .. S'Last);
      else
         return S;
      end if;
   end Img;

   --  Compute extra stall cycles from instruction encoding.
   --  Matches cpu.adb's Extra_Cycles assignments.
   --  Returns: extra cycles (0 = no stall), Stall_Cat (0=none,1=MUL,2=DIV,3=FP,4=CSR)
   function Instr_Extra_Cycles (Instr : Word;
                                Stall_Cat : out Natural) return Cycle_Count_T is
      Opcode : constant Natural := Natural (Instr and 16#7F#);
      Funct7 : constant Natural := Natural (Shift_Right (Instr, 25));
      Funct3 : constant Natural := Natural (Shift_Right (Instr, 12) and 7);
   begin
      Stall_Cat := 0;
      case Opcode is
         when 16#33# =>  --  OP: MUL/DIV
            if Funct7 = 1 then
               if Funct3 <= 3 then
                  Stall_Cat := 1;
                  return 2;   --  3 cycles total (MUL/MULH)
               else
                  Stall_Cat := 2;
                  return 32;  --  33 cycles total (DIV/REMU)
               end if;
            end if;
         when 16#53# =>  --  OP-FP
            --  FADD/FSUB/FMUL S,D,H: funct7 in {0,1,2,4,5,6,8,9,10}
            --  FDIV S,D,H: funct7 in {12,13,14}
            --  FSQRT S,D,H: funct7 in {44,45,46}
            case Funct7 is
               when 0 | 1 | 2 | 4 | 5 | 6 | 8 | 9 | 10 =>
                  Stall_Cat := 3;
                  return 3;   --  4 cycles total
               when 12 | 13 | 14 =>
                  Stall_Cat := 3;
                  return 19;  --  20 cycles total
               when 44 | 45 | 46 =>
                  Stall_Cat := 3;
                  return 19;  --  20 cycles total
               when others =>
                  null;
            end case;
         when 16#43# | 16#47# | 16#4B# | 16#4F# =>  --  FMA opcodes
            Stall_Cat := 3;
            return 3;  --  4 cycles total
         when 16#73# =>  --  SYSTEM: CSR instructions cost 2 cycles
            if Funct3 /= 0 then
               Stall_Cat := 4;
               return 1;   --  2 cycles total
            end if;
         when others =>
            null;
      end case;
      return 0;
   end Instr_Extra_Cycles;

   --  RISC-V opcode names (7-bit opcode ->short string)
   type Opcode_Name_T is array (0 .. 127) of String (1 .. 10);

   Opcode_Names : constant Opcode_Name_T :=
     (16#03# => "LOAD      ",
      16#07# => "LOAD-FP   ",
      16#0F# => "MISC-MEM  ",
      16#13# => "OP-IMM    ",
      16#17# => "AUIPC     ",
      16#23# => "STORE     ",
      16#27# => "STORE-FP  ",
      16#2F# => "AMO       ",
      16#33# => "OP        ",
      16#37# => "LUI       ",
      16#43# => "MADD      ",
      16#47# => "MSUB      ",
      16#4B# => "NMSUB     ",
      16#4F# => "NMADD     ",
      16#53# => "OP-FP     ",
      16#57# => "OP-V      ",
      16#63# => "BRANCH    ",
      16#67# => "JALR      ",
      16#6F# => "JAL       ",
      16#73# => "SYSTEM    ",
      others => "??        ");

   --  Helper: record a PC hit in the hot-PC table (open-address hash, linear probe)
   procedure Record_Hot_PC (Prof : in out Profiler_State; PC : Memory_Address) is
      Slot : Natural := Natural (PC / 4) mod Max_Hot_PCs;
      Start : constant Natural := Slot;
   begin
      loop
         if not Prof.Hot_PCs (Slot).Valid then
            --  Empty slot: insert
            Prof.Hot_PCs (Slot).PC    := PC;
            Prof.Hot_PCs (Slot).Count := 1;
            Prof.Hot_PCs (Slot).Valid := True;
            Prof.Hot_PC_Count := Prof.Hot_PC_Count + 1;
            return;
         elsif Prof.Hot_PCs (Slot).PC = PC then
            Prof.Hot_PCs (Slot).Count := Prof.Hot_PCs (Slot).Count + 1;
            return;
         else
            Slot := (Slot + 1) mod Max_Hot_PCs;
            exit when Slot = Start;  -- table full, give up
         end if;
      end loop;
   end Record_Hot_PC;

   ----------------
   -- Initialize --
   ----------------

   procedure Initialize (Prof : out Profiler_State;
                        Syms : Symbol_Table_Ptr) is
   begin
      Prof.Symbols := Syms;
      Prof.Num_Functions := 0;
      Prof.Total_Cycles := 0;
      Prof.Stack_Depth := 0;
      Prof.Prev_Func_Idx := 0;
      Prof.Num_Edges := 0;
      Prof.Num_Samples := 0;
      Prof.Sample_Interval := 100;
      Prof.Next_Sample := 0;
      Prof.Hot_PC_Count := 0;
      Prof.Current_Func_Idx := 0;
      Prof.Need_Func_Update := True;
      Prof.Total_Wall_Cycles := 0;
      Prof.Stalls_Mul        := 0;
      Prof.Stalls_Div        := 0;
      Prof.Stalls_FP         := 0;
      Prof.Stalls_CSR        := 0;
      Prof.Cache_I_Hits      := 0;
      Prof.Cache_I_Misses    := 0;
      Prof.Cache_I_Stalls    := 0;
      Prof.Cache_D_Hits      := 0;
      Prof.Cache_D_Misses    := 0;
      Prof.Cache_D_Stalls    := 0;
      Prof.Stalls_Load_Use   := 0;
      Prof.Stalls_Branch     := 0;
      Prof.Prof_Last_Load_Rd  := 0;
      Prof.Prof_Last_Was_Load := False;
      Prof.Prof_Last_PC       := 0;
      Prof.Prof_Last_Is_32bit := True;

      for I in Prof.Functions'Range loop
         Prof.Functions (I).Instr_Count := 0;
         Prof.Functions (I).Cycle_Count := 0;
         Prof.Functions (I).Call_Count := 0;
         Prof.Functions (I).Stall_Count := 0;
      end loop;

      for I in Prof.Call_Edges'Range loop
         Prof.Call_Edges (I).Caller_Idx := 0;
         Prof.Call_Edges (I).Callee_Idx := 0;
         Prof.Call_Edges (I).Call_Count := 0;
      end loop;

      for I in Prof.Opcode_Counts'Range loop
         Prof.Opcode_Counts (I) := 0;
      end loop;

      for I in Prof.Hot_PCs'Range loop
         Prof.Hot_PCs (I).Valid := False;
         Prof.Hot_PCs (I).PC    := 0;
         Prof.Hot_PCs (I).Count := 0;
      end loop;
   end Initialize;

   -------------------------
   -- Get_Function_Index --
   -------------------------

   function Get_Function_Index (Prof : in out Profiler_State;
                                Addr : Memory_Address) return Natural is
      Info : Symbols.Symbol_Info;
   begin
      --  Look up symbol at this address
      if Symbols.Lookup_By_Address (Prof.Symbols.all, Addr, Info) and then
         Info.Sym_Type = Symbols.SYM_FUNCTION
      then
         --  Check if we already have this function
         for I in 1 .. Prof.Num_Functions loop
            if Prof.Functions (I).Address = Info.Address then
               return I;
            end if;
         end loop;

         --  Add new function
         if Prof.Num_Functions < Max_Functions then
            Prof.Num_Functions := Prof.Num_Functions + 1;
            Prof.Functions (Prof.Num_Functions).Name (1 .. Info.Name_Len) :=
               Info.Name (1 .. Info.Name_Len);
            Prof.Functions (Prof.Num_Functions).Name_Len := Info.Name_Len;
            Prof.Functions (Prof.Num_Functions).Address := Info.Address;
            return Prof.Num_Functions;
         end if;
      end if;

      return 0;  -- Not a known function
   end Get_Function_Index;

   ---------------------------
   -- Is_Call_Instruction --
   ---------------------------

   function Is_Call_Instruction (Instr : Word; PC : Memory_Address) return Boolean is
      pragma Unreferenced (PC);
      Opcode : constant Word := Instr and 16#7F#;
      Rd     : constant Word := Shift_Right (Instr and 16#0F80#, 7);
   begin
      --  JAL with rd != x0 (function call)
      if Opcode = 16#6F# and Rd /= 0 then
         return True;
      end if;

      --  JALR with rd != x0 (indirect call)
      if Opcode = 16#67# and Rd /= 0 then
         return True;
      end if;

      return False;
   end Is_Call_Instruction;

   -----------------------------
   -- Is_Return_Instruction --
   -----------------------------

   function Is_Return_Instruction (Instr : Word) return Boolean is
      Opcode : constant Word := Instr and 16#7F#;
      Rd     : constant Word := Shift_Right (Instr and 16#0F80#, 7);
      Rs1    : constant Word := Shift_Right (Instr and 16#0F8000#, 15);
   begin
      --  JALR x0, 0(ra) - standard return (ret instruction)
      if Opcode = 16#67# and Rd = 0 and Rs1 = 1 then
         return True;
      end if;

      return False;
   end Is_Return_Instruction;

   -----------------------
   -- Record_Call_Edge --
   -----------------------

   procedure Record_Call_Edge (Prof : in out Profiler_State;
                               Caller_Idx : Natural;
                               Callee_Idx : Natural) is
   begin
      --  Look for existing edge
      for I in 1 .. Prof.Num_Edges loop
         if Prof.Call_Edges (I).Caller_Idx = Caller_Idx and then
            Prof.Call_Edges (I).Callee_Idx = Callee_Idx
         then
            Prof.Call_Edges (I).Call_Count := Prof.Call_Edges (I).Call_Count + 1;
            return;
         end if;
      end loop;

      --  Add new edge
      if Prof.Num_Edges < Max_Call_Edges then
         Prof.Num_Edges := Prof.Num_Edges + 1;
         Prof.Call_Edges (Prof.Num_Edges).Caller_Idx := Caller_Idx;
         Prof.Call_Edges (Prof.Num_Edges).Callee_Idx := Callee_Idx;
         Prof.Call_Edges (Prof.Num_Edges).Call_Count := 1;
      end if;
   end Record_Call_Edge;

   -----------------------
   -- Sample_Call_Stack --
   -----------------------

   procedure Sample_Call_Stack (Prof : in out Profiler_State) is
      Found : Boolean := False;
   begin
      --  Look for matching stack trace
      for I in 1 .. Prof.Num_Samples loop
         if Prof.Samples (I).Depth = Prof.Stack_Depth then
            Found := True;
            for J in 1 .. Prof.Stack_Depth loop
               if Prof.Samples (I).Stack (J) /= Prof.Call_Stack_Data (J).Function_Idx then
                  Found := False;
                  exit;
               end if;
            end loop;

            if Found then
               Prof.Samples (I).Sample_Count := Prof.Samples (I).Sample_Count + 1;
               return;
            end if;
         end if;
      end loop;

      --  Add new sample
      if Prof.Num_Samples < Max_Samples then
         Prof.Num_Samples := Prof.Num_Samples + 1;
         Prof.Samples (Prof.Num_Samples).Depth := Prof.Stack_Depth;
         for J in 1 .. Prof.Stack_Depth loop
            Prof.Samples (Prof.Num_Samples).Stack (J) := Prof.Call_Stack_Data (J).Function_Idx;
         end loop;
         Prof.Samples (Prof.Num_Samples).Sample_Count := 1;
      end if;
   end Sample_Call_Stack;

   ------------------------
   -- Record_Instruction --
   ------------------------

   procedure Record_Instruction (Prof  : in out Profiler_State;
                                PC    : Memory_Address;
                                Instr : Word) is
      Opcode : constant Natural := Natural (Instr and 16#7F#);
      Is_Call   : constant Boolean := Is_Call_Instruction (Instr, PC);
      Is_Return : constant Boolean := Is_Return_Instruction (Instr);
      Stall_Cat  : Natural;
      Extra      : Cycle_Count_T :=
         Instr_Extra_Cycles (Instr, Stall_Cat);
   begin
      --  Dynamic stall detection
      --  (1) Load-use hazard
      if Prof.Prof_Last_Was_Load and Prof.Prof_Last_Load_Rd /= 0 then
         declare
            Op  : constant Word    := Instr and 16#7F#;
            Rs1 : constant Natural := Natural (Shift_Right (Instr, 15) and 16#1F#);
            Rs2 : constant Natural := Natural (Shift_Right (Instr, 20) and 16#1F#);
         begin
            if Rs1 = Prof.Prof_Last_Load_Rd or
               ((Op = OPCODE_OP or Op = OPCODE_STORE or
                 Op = OPCODE_BRANCH or Op = OPCODE_OP_32) and
                Rs2 = Prof.Prof_Last_Load_Rd)
            then
               Extra := Extra + 1;
               Prof.Stalls_Load_Use := Prof.Stalls_Load_Use + 1;
            end if;
         end;
      end if;
      Prof.Prof_Last_Was_Load := False;
      if (Instr and 16#7F#) = OPCODE_LOAD then
         Prof.Prof_Last_Was_Load := True;
         Prof.Prof_Last_Load_Rd  := Natural (Shift_Right (Instr, 7) and 16#1F#);
      end if;

      --  (2) Branch/jump taken stall: detected by non-sequential PC
      if Prof.Prof_Last_PC /= 0 then
         declare
            Expected_Next_PC : constant Memory_Address :=
               Prof.Prof_Last_PC +
               (if Prof.Prof_Last_Is_32bit then 4 else 2);
         begin
            if PC /= Expected_Next_PC then
               Extra := Extra + 1;
               Prof.Stalls_Branch := Prof.Stalls_Branch + 1;
            end if;
         end;
      end if;
      Prof.Prof_Last_PC      := PC;
      Prof.Prof_Last_Is_32bit := (Instr and 3) = 3;

      --  Fast per-instruction accounting (O(1))
      Prof.Total_Cycles := Prof.Total_Cycles + 1;
      Prof.Total_Wall_Cycles := Prof.Total_Wall_Cycles + 1 + Extra;
      case Stall_Cat is
         when 1 => Prof.Stalls_Mul := Prof.Stalls_Mul + Extra;
         when 2 => Prof.Stalls_Div := Prof.Stalls_Div + Extra;
         when 3 => Prof.Stalls_FP  := Prof.Stalls_FP  + Extra;
         when 4 => Prof.Stalls_CSR := Prof.Stalls_CSR + Extra;
         when others => null;
      end case;
      Prof.Opcode_Counts (Opcode) := Prof.Opcode_Counts (Opcode) + 1;

      --  Update function index only when needed:
      --  - first instruction ever
      --  - after a call or return (Need_Func_Update set by previous cycle)
      if Prof.Need_Func_Update then
         Prof.Need_Func_Update := False;
         declare
            New_Idx : constant Natural := Get_Function_Index (Prof, PC);
         begin
            if New_Idx > 0 then
               --  Record call-graph edge on entry to a new function
               if New_Idx /= Prof.Current_Func_Idx
                  and then Prof.Current_Func_Idx > 0
               then
                  if Prof.Stack_Depth > 0 then
                     declare
                        Caller : constant Natural :=
                           Prof.Call_Stack_Data (Prof.Stack_Depth).Function_Idx;
                     begin
                        if Caller > 0 then
                           Record_Call_Edge (Prof, Caller, New_Idx);
                        end if;
                     end;
                  end if;
               end if;

               Prof.Current_Func_Idx := New_Idx;
               Prof.Prev_Func_Idx := New_Idx;

               --  Bootstrap call stack on first instruction
               if Prof.Total_Cycles = 1 and Prof.Stack_Depth = 0 then
                  Prof.Stack_Depth := 1;
                  Prof.Call_Stack_Data (1).Function_Idx := New_Idx;
                  Prof.Call_Stack_Data (1).Entry_Cycles := 1;
               end if;
            end if;
         end;
      end if;

      --  Charge the current function for this instruction
      if Prof.Current_Func_Idx > 0 then
         Prof.Functions (Prof.Current_Func_Idx).Instr_Count :=
            Prof.Functions (Prof.Current_Func_Idx).Instr_Count + 1;
         Prof.Functions (Prof.Current_Func_Idx).Cycle_Count :=
            Prof.Functions (Prof.Current_Func_Idx).Cycle_Count + 1 + Extra;
         Prof.Functions (Prof.Current_Func_Idx).Stall_Count :=
            Prof.Functions (Prof.Current_Func_Idx).Stall_Count + Extra;
      end if;

      --  Handle call: push stack, schedule function-index update next cycle
      if Is_Call then
         if Prof.Current_Func_Idx > 0 then
            Prof.Functions (Prof.Current_Func_Idx).Call_Count :=
               Prof.Functions (Prof.Current_Func_Idx).Call_Count + 1;
         end if;
         if Prof.Stack_Depth < Max_Call_Depth then
            Prof.Stack_Depth := Prof.Stack_Depth + 1;
            Prof.Call_Stack_Data (Prof.Stack_Depth).Function_Idx :=
               Prof.Current_Func_Idx;
            Prof.Call_Stack_Data (Prof.Stack_Depth).Entry_Cycles :=
               Prof.Total_Cycles;
         end if;
         Prof.Need_Func_Update := True;

      elsif Is_Return then
         if Prof.Stack_Depth > 0 then
            Prof.Stack_Depth := Prof.Stack_Depth - 1;
         end if;
         Prof.Need_Func_Update := True;
      end if;

      --  Periodic sample: hot-PC table + call-stack flamegraph
      if Prof.Total_Cycles >= Prof.Next_Sample then
         Prof.Next_Sample := Prof.Total_Cycles + Prof.Sample_Interval;
         Record_Hot_PC (Prof, PC);
         if Prof.Stack_Depth > 0 then
            Sample_Call_Stack (Prof);
         end if;
      end if;
   end Record_Instruction;

   ------------------
   -- Print_Report --
   ------------------

   procedure Print_Report (Prof : Profiler_State) is
      --  Sort array indexed by function
      type Sort_Entry is record
         Idx    : Natural;
         Cycles : Cycle_Count_T;
      end record;

      Sorted : array (1 .. Max_Functions) of Sort_Entry;
      Temp : Sort_Entry;

      --  Sort array for opcode histogram
      type OSort_Entry is record
         Op    : Natural;
         Count : Cycle_Count_T;
      end record;

      OSorted : array (0 .. 127) of OSort_Entry;
      OTemp : OSort_Entry;
      OCount : Natural := 0;

      --  Sort array for hot-PC table
      type PSort_Entry is record
         Idx   : Natural;   -- index into Hot_PCs
         Count : Cycle_Count_T;
      end record;

      PSorted : array (0 .. Max_Hot_PCs - 1) of PSort_Entry;
      PTemp : PSort_Entry;
      PCount : Natural := 0;

      Total : constant Cycle_Count_T :=
         (if Prof.Total_Wall_Cycles > 0 then Prof.Total_Wall_Cycles else 1);

   begin
      Put_Line ("");
      Put_Line ("=== Profiling Report ===");
      Put_Line ("Total instructions: " & Img (Prof.Total_Cycles));
      Put_Line ("Total wall cycles:  " & Img (Prof.Total_Wall_Cycles));
      declare
         CPI_Int  : constant Long_Long_Integer :=
            (if Prof.Total_Cycles > 0
             then Prof.Total_Wall_Cycles / Prof.Total_Cycles
             else 1);
         CPI_Frac : constant Long_Long_Integer :=
            (if Prof.Total_Cycles > 0
             then ((Prof.Total_Wall_Cycles - CPI_Int * Prof.Total_Cycles) * 100)
                     / Prof.Total_Cycles
             else 0);
      begin
         Put_Line ("Average CPI:        " & Img (CPI_Int) & "." &
                   (if CPI_Frac < 10 then "0" else "") & Img (CPI_Frac));
      end;
      declare
         Tw : constant Cycle_Count_T :=
            (if Prof.Total_Wall_Cycles > 0 then Prof.Total_Wall_Cycles else 1);
      begin
         Put_Line ("Stall breakdown:");
         Put_Line ("  MUL/MULH  (+2): " & Img (Prof.Stalls_Mul) &
                   " (" & Img (Prof.Stalls_Mul * 100 / Tw) & "%)");
         Put_Line ("  DIV/REM  (+32): " & Img (Prof.Stalls_Div) &
                   " (" & Img (Prof.Stalls_Div * 100 / Tw) & "%)");
         Put_Line ("  FP arith (+3/+19): " & Img (Prof.Stalls_FP) &
                   " (" & Img (Prof.Stalls_FP * 100 / Tw) & "%)");
         Put_Line ("  CSR       (+1): " & Img (Prof.Stalls_CSR) &
                   " (" & Img (Prof.Stalls_CSR * 100 / Tw) & "%)");
         Put_Line ("  Load-use  (+1): " & Img (Prof.Stalls_Load_Use) &
                   " (" & Img (Prof.Stalls_Load_Use * 100 / Tw) & "%)");
         Put_Line ("  Branch/jump (+1): " & Img (Prof.Stalls_Branch) &
                   " (" & Img (Prof.Stalls_Branch * 100 / Tw) & "%)");
      end;
      if Prof.Cache_I_Stalls + Prof.Cache_D_Stalls > 0 then
         Put_Line ("Cache miss stalls:");
         declare
            I_Total : constant Cycle_Count_T := Prof.Cache_I_Hits + Prof.Cache_I_Misses;
            D_Total : constant Cycle_Count_T := Prof.Cache_D_Hits + Prof.Cache_D_Misses;
            IT : constant Cycle_Count_T := (if I_Total > 0 then I_Total else 1);
            DT : constant Cycle_Count_T := (if D_Total > 0 then D_Total else 1);
         begin
            Put_Line ("  I-cache hits:   " & Img (Prof.Cache_I_Hits) &
                      "  misses: " & Img (Prof.Cache_I_Misses) &
                      "  (" & Img (Prof.Cache_I_Misses * 100 / IT) & "% miss)" &
                      "  stalls: " & Img (Prof.Cache_I_Stalls));
            Put_Line ("  D-cache hits:   " & Img (Prof.Cache_D_Hits) &
                      "  misses: " & Img (Prof.Cache_D_Misses) &
                      "  (" & Img (Prof.Cache_D_Misses * 100 / DT) & "% miss)" &
                      "  stalls: " & Img (Prof.Cache_D_Stalls));
         end;
      end if;
      Put_Line ("");

      --  ---- Function profile ----
      --  Initialize sort array
      for I in 1 .. Prof.Num_Functions loop
         Sorted (I).Idx := I;
         Sorted (I).Cycles := Prof.Functions (I).Cycle_Count;
      end loop;

      --  Bubble sort by cycle count (descending)
      for I in 1 .. Prof.Num_Functions - 1 loop
         for J in I + 1 .. Prof.Num_Functions loop
            if Sorted (J).Cycles > Sorted (I).Cycles then
               Temp := Sorted (I);
               Sorted (I) := Sorted (J);
               Sorted (J) := Temp;
            end if;
         end loop;
      end loop;

      Put_Line ("--- Function Profile (top 20 by cycles) ---");
      Put_Line (" WallCyc        %    Instructions    Calls  Function");
      Put_Line (" ----------  ----    ------------    -----  --------------------------------");

      for I in 1 .. Natural'Min (Prof.Num_Functions, 20) loop
         declare
            Idx : constant Natural := Sorted (I).Idx;
            F   : Function_Profile renames Prof.Functions (Idx);
            Pct : constant Long_Long_Integer := (F.Cycle_Count * 100) / Total;
         begin
            Put (" ");
            declare
               CS : constant String := Img (F.Cycle_Count);
               PS : constant String := Img (Pct) & "%";
               IS2 : constant String := Img (F.Instr_Count);
               SS : constant String := Img (F.Call_Count);
            begin
               Put (CS);
               for K in CS'Length .. 11 loop Put (' '); end loop;
               Put (PS);
               for K in PS'Length .. 7 loop Put (' '); end loop;
               Put ("    ");
               Put (IS2);
               for K in IS2'Length .. 12 loop Put (' '); end loop;
               Put ("    ");
               Put (SS);
               for K in SS'Length .. 5 loop Put (' '); end loop;
               Put ("  ");
               Put_Line (F.Name (1 .. F.Name_Len));
            end;
         end;
      end loop;

      Put_Line ("");

      --  ---- Opcode histogram ----
      --  Collect non-zero entries
      for I in Prof.Opcode_Counts'Range loop
         if Prof.Opcode_Counts (I) > 0 then
            OSorted (OCount).Op    := I;
            OSorted (OCount).Count := Prof.Opcode_Counts (I);
            OCount := OCount + 1;
         end if;
      end loop;

      --  Sort descending by count
      for I in 0 .. OCount - 2 loop
         for J in I + 1 .. OCount - 1 loop
            if OSorted (J).Count > OSorted (I).Count then
               OTemp := OSorted (I);
               OSorted (I) := OSorted (J);
               OSorted (J) := OTemp;
            end if;
         end loop;
      end loop;

      Put_Line ("--- Instruction Histogram (by opcode) ---");
      Put_Line (" Opcode     Name        Count           % ");
      Put_Line (" --------   ----------  ----------      ---");

      for I in 0 .. Natural'Min (OCount, 20) - 1 loop
         declare
            Op  : constant Natural := OSorted (I).Op;
            Cnt : constant Cycle_Count_T := OSorted (I).Count;
            Pct : constant Long_Long_Integer := (Cnt * 100) / Total;
            CS  : constant String := Img (Cnt);
            PS  : constant String := Img (Pct) & "%";
         begin
            Put (" 0x");
            declare
               Hex : constant String := "0123456789abcdef";
               Hi : constant Character := Hex (Op / 16 + 1);
               Lo : constant Character := Hex (Op mod 16 + 1);
            begin
               Put ((1 => Hi, 2 => Lo));
            end;
            Put ("  ");
            Put ("     ");
            Put (Opcode_Names (Op));
            Put ("  ");
            Put (CS);
            for K in CS'Length .. 14 loop Put (' '); end loop;
            Put ("  ");
            Put_Line (PS);
         end;
      end loop;

      Put_Line ("");

      --  ---- Hot-PC table ----
      --  Collect valid entries
      for I in Prof.Hot_PCs'Range loop
         if Prof.Hot_PCs (I).Valid then
            PSorted (PCount).Idx   := I;
            PSorted (PCount).Count := Prof.Hot_PCs (I).Count;
            PCount := PCount + 1;
         end if;
      end loop;

      --  Sort descending
      for I in 0 .. PCount - 2 loop
         for J in I + 1 .. PCount - 1 loop
            if PSorted (J).Count > PSorted (I).Count then
               PTemp := PSorted (I);
               PSorted (I) := PSorted (J);
               PSorted (J) := PTemp;
            end if;
         end loop;
      end loop;

      Put_Line ("--- Hot Instructions (top 20 PCs) ---");
      Put_Line (" PC          Count           %   Symbol");
      Put_Line (" ----------  ----------      ---  --------------------------------");

      for I in 0 .. Natural'Min (PCount, 20) - 1 loop
         declare
            Slot : constant Natural := PSorted (I).Idx;
            PC   : constant Memory_Address := Prof.Hot_PCs (Slot).PC;
            Cnt  : constant Cycle_Count_T  := Prof.Hot_PCs (Slot).Count;
            Pct  : constant Long_Long_Integer := (Cnt * 100) / Total;
            CS   : constant String := Img (Cnt);
            PS   : constant String := Img (Pct) & "%";
            --  Format PC as hex
            Hex  : constant String := "0123456789abcdef";
            PC_W : Word := Word (PC);
            PC_S : String (1 .. 8);
         begin
            for K in reverse 0 .. 7 loop
               PC_S (K + 1) := Hex (Natural (PC_W and 16#F#) + 1);
               PC_W := Shift_Right (PC_W, 4);
            end loop;
            Put (" 0x");
            Put (PC_S);
            Put ("  ");
            Put (CS);
            for K in CS'Length .. 14 loop Put (' '); end loop;
            Put ("  ");
            Put (PS);
            for K in PS'Length .. 5 loop Put (' '); end loop;
            Put ("  ");
            --  Symbol name: find the registered function with the highest
            --  start address that is still <= this PC.
            declare
               Best_Idx  : Natural := 0;
               Best_Addr : Memory_Address := 0;
            begin
               for F in 1 .. Prof.Num_Functions loop
                  if Prof.Functions (F).Address <= PC and then
                     Prof.Functions (F).Address >= Best_Addr
                  then
                     Best_Addr := Prof.Functions (F).Address;
                     Best_Idx  := F;
                  end if;
               end loop;
               if Best_Idx > 0 then
                  Put_Line (Prof.Functions (Best_Idx).Name
                            (1 .. Prof.Functions (Best_Idx).Name_Len));
               else
                  Put_Line ("");
               end if;
            end;
         end;
      end loop;

      Put_Line ("");
   end Print_Report;

   ----------------------
   -- Print_Call_Graph --
   ----------------------

   procedure Print_Call_Graph (Prof : Profiler_State) is
      type Edge_Sort is record
         Idx : Natural;
         Count : Cycle_Count_T;
      end record;

      Sorted : array (1 .. Max_Call_Edges) of Edge_Sort;
      Temp : Edge_Sort;
   begin
      if Prof.Num_Edges = 0 then
         Put_Line ("No call graph data collected");
         return;
      end if;

      Put_Line ("");
      Put_Line ("=== Call Graph ===");
      Put_Line (" Calls   Caller -> Callee");
      Put_Line (" -----   --------------------------------");

      --  Initialize sort array
      for I in 1 .. Prof.Num_Edges loop
         Sorted (I).Idx := I;
         Sorted (I).Count := Prof.Call_Edges (I).Call_Count;
      end loop;

      --  Sort by call count (descending)
      for I in 1 .. Prof.Num_Edges - 1 loop
         for J in I + 1 .. Prof.Num_Edges loop
            if Sorted (J).Count > Sorted (I).Count then
               Temp := Sorted (I);
               Sorted (I) := Sorted (J);
               Sorted (J) := Temp;
            end if;
         end loop;
      end loop;

      --  Print top edges
      for I in 1 .. Natural'Min (Prof.Num_Edges, 30) loop
         declare
            Idx : constant Natural := Sorted (I).Idx;
            Edge : Call_Edge renames Prof.Call_Edges (Idx);
            Caller : Function_Profile renames Prof.Functions (Edge.Caller_Idx);
            Callee : Function_Profile renames Prof.Functions (Edge.Callee_Idx);
            CS : constant String := Img (Edge.Call_Count);
         begin
            Put (" ");
            Put (CS);
            for K in CS'Length .. 7 loop Put (' '); end loop;
            Put (Caller.Name (1 .. Caller.Name_Len));
            Put (" -> ");
            Put_Line (Callee.Name (1 .. Callee.Name_Len));
         end;
      end loop;

      Put_Line ("");
   end Print_Call_Graph;

   -----------------------
   -- Export_Flamegraph --
   -----------------------

   procedure Export_Flamegraph (Prof : Profiler_State;
                               Filename : String) is
      File : Ada.Streams.Stream_IO.File_Type;
   begin
      if Prof.Num_Samples = 0 then
         Put_Line ("No flamegraph samples collected");
         return;
      end if;

      --  Create output file
      Ada.Streams.Stream_IO.Create (File, Ada.Streams.Stream_IO.Out_File, Filename);

      --  Write samples in folded stack format
      --  Format: func1;func2;func3 count
      for I in 1 .. Prof.Num_Samples loop
         declare
            Sample : Flamegraph_Sample renames Prof.Samples (I);
            Line : String (1 .. 4096);
            Pos : Natural := 1;
         begin
            --  Build stack trace from bottom to top
            for J in 1 .. Sample.Depth loop
               declare
                  Func_Idx : constant Natural := Sample.Stack (J);
               begin
                  if Func_Idx > 0 and Func_Idx <= Prof.Num_Functions then
                     declare
                        Func : Function_Profile renames Prof.Functions (Func_Idx);
                     begin
                        if Func.Name_Len > 0 and Pos < Line'Last - Func.Name_Len then
                           if Pos > 1 then  -- Add separator only if not first function
                              Line (Pos) := ';';
                              Pos := Pos + 1;
                           end if;
                           Line (Pos .. Pos + Func.Name_Len - 1) :=
                              Func.Name (1 .. Func.Name_Len);
                           Pos := Pos + Func.Name_Len;
                        end if;
                     end;
                  end if;
               end;
            end loop;

            --  Add sample count
            if Pos > 1 and Pos < Line'Last - 20 then  -- Leave room for count
               Line (Pos) := ' ';
               Pos := Pos + 1;
               declare
                  Count_Str : constant String := Img (Sample.Sample_Count);
                  Len : constant Natural := Count_Str'Length;
               begin
                  if Pos + Len <= Line'Last then
                     Line (Pos .. Pos + Len - 1) := Count_Str;
                     Pos := Pos + Len;
                  end if;
               end;

               --  Write line to file
               String'Write (Ada.Streams.Stream_IO.Stream (File), Line (1 .. Pos - 1) & ASCII.LF);
            end if;
         end;
      end loop;

      Ada.Streams.Stream_IO.Close (File);
      Put_Line ("Flamegraph data written to " & Filename);
      Put_Line ("Generate SVG with: flamegraph.pl " & Filename & " > flamegraph.svg");
   end Export_Flamegraph;

   -----------------------------------
   -- Record_Instruction (RV64 wrap) --
   -----------------------------------

   procedure Record_Instruction (Prof  : in out Profiler_State;
                                PC    : Memory_Address_64;
                                Instr : Word) is
   begin
      Record_Instruction (Prof, Memory_Address (PC), Instr);
   end Record_Instruction;

   --------------------------
   -- Record_Cache_Stalls --
   --------------------------

   procedure Record_Cache_Stalls (Prof     : in out Profiler_State;
                                  I_Stalls : Natural;
                                  I_Hit    : Boolean;
                                  D_Stalls : Natural;
                                  D_Hit    : Boolean;
                                  D_Valid  : Boolean) is
      Total_Stalls : constant Cycle_Count_T :=
         Cycle_Count_T (I_Stalls) + Cycle_Count_T (D_Stalls);
   begin
      --  Add stall cycles to totals
      Prof.Total_Wall_Cycles := Prof.Total_Wall_Cycles + Total_Stalls;

      --  Charge current function
      if Prof.Current_Func_Idx > 0 then
         Prof.Functions (Prof.Current_Func_Idx).Cycle_Count :=
            Prof.Functions (Prof.Current_Func_Idx).Cycle_Count + Total_Stalls;
         Prof.Functions (Prof.Current_Func_Idx).Stall_Count :=
            Prof.Functions (Prof.Current_Func_Idx).Stall_Count + Total_Stalls;
      end if;

      --  Update I-cache counters
      if I_Hit then
         Prof.Cache_I_Hits := Prof.Cache_I_Hits + 1;
      else
         Prof.Cache_I_Misses  := Prof.Cache_I_Misses + 1;
         Prof.Cache_I_Stalls  := Prof.Cache_I_Stalls + Cycle_Count_T (I_Stalls);
      end if;

      --  Update D-cache counters (only if a data access occurred)
      if D_Valid then
         if D_Hit then
            Prof.Cache_D_Hits := Prof.Cache_D_Hits + 1;
         else
            Prof.Cache_D_Misses := Prof.Cache_D_Misses + 1;
            Prof.Cache_D_Stalls := Prof.Cache_D_Stalls + Cycle_Count_T (D_Stalls);
         end if;
      end if;
   end Record_Cache_Stalls;

end RISCV.Profiler;
