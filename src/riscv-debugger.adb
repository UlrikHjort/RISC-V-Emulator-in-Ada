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

with Ada.Text_IO;           use Ada.Text_IO;
with Ada.Strings.Maps;
with RISCV.Disasm;
with RISCV.FPU;
with RISCV.Vector;
with RISCV.Symbols;

use type RISCV.Symbols.Symbol_Type;

package body RISCV.Debugger is

   --  Package-level trace file (Ada.Text_IO.File_Type is limited)
   Trace_File : Ada.Text_IO.File_Type;

   --  Helper function declarations
   function To_Hex (V : Word) return String;
   function To_Hex_64 (V : Double_Word) return String;
   function Parse_Hex (S : String) return Word;
   function Parse_Hex_64 (S : String) return Double_Word;
   function Parse_Natural (S : String) return Natural;
   procedure Show_Current_Instruction (Dbg : Debugger_State;
                                       CPU : RISCV.CPU.CPU_State;
                                       Mem : in out Memory.Memory_Unit);
   procedure Show_Current_Instruction_64 (Dbg : Debugger_State;
                                          CPU : RISCV.CPU64.CPU64_State;
                                          Mem : in out Memory.Memory_Unit);
   procedure Show_Registers (CPU : RISCV.CPU.CPU_State);
   procedure Show_Registers_64 (CPU : RISCV.CPU64.CPU64_State);
   procedure Show_FP_Registers (CPU : RISCV.CPU.CPU_State);
   procedure Show_FP_Registers (FP  : RISCV.FPU.FPU_State);
   procedure Show_FP_Register (CPU : RISCV.CPU.CPU_State; Reg : Natural);
   procedure Show_Vector_Registers (CPU : RISCV.CPU.CPU_State);
   procedure Dump_Memory (Mem     : in out Memory.Memory_Unit;
                          Address : Word;
                          Count   : Positive);
   procedure Disassemble_Memory (Dbg     : Debugger_State;
                                 Mem     : in out Memory.Memory_Unit;
                                 Address : Word;
                                 Count   : Positive);
   procedure Print_Help;

   ----------------
   -- Initialize --
   ----------------

   procedure Initialize (Dbg : out Debugger_State) is
   begin
      Dbg.Breakpoints := (others => 0);
      Dbg.Breakpoint_Enabled := (others => False);
      Dbg.Num_Breakpoints := 0;
      Dbg.Watchpoints := (others => (Address => 0, WType => Read));
      Dbg.Watchpoint_Enabled := (others => False);
      Dbg.Num_Watchpoints := 0;
      Dbg.Quit_Requested := False;
      Dbg.Watchpoint_Hit := False;
      Dbg.Last_Watch_Addr := 0;  --  Double_Word
      Dbg.Last_Watch_Type := Read;
      Dbg.Symbols := new Symbols.Symbol_Table;
      Symbols.Init (Dbg.Symbols.all);
      Dbg.Symbols_Loaded := False;
      Dbg.Trace_Enabled  := False;
      Dbg.Trace_File_Open := False;
   end Initialize;

   ------------------
   -- Load_Symbols --
   ------------------

   procedure Load_Symbols (Dbg : in out Debugger_State;
                          Filename : String) is
      Success : Boolean;
   begin
      Symbols.Load_From_ELF (Dbg.Symbols.all, Filename, Success);
      if Success then
         Dbg.Symbols_Loaded := True;
         Put_Line ("Loaded" & Natural'Image (Symbols.Get_Symbol_Count (Dbg.Symbols.all)) &
                  " symbols from " & Filename);
      else
         Dbg.Symbols_Loaded := False;
         Put_Line ("Warning: Could not load symbols from " & Filename);
      end if;
   end Load_Symbols;

   ------------
   -- To_Hex --
   ------------

   function To_Hex (V : Word) return String is
      Hex_Chars : constant String := "0123456789abcdef";
      Result    : String (1 .. 8);
      Val       : Word := V;
   begin
      for I in reverse Result'Range loop
         Result (I) := Hex_Chars (Natural (Val and 16#F#) + 1);
         Val := Shift_Right (Val, 4);
      end loop;
      return Result;
   end To_Hex;

   ----------------
   -- To_Hex_64  --
   ----------------

   function To_Hex_64 (V : Double_Word) return String is
      Hex_Chars : constant String := "0123456789abcdef";
      Result    : String (1 .. 16);
      Val       : Double_Word := V;
   begin
      for I in reverse Result'Range loop
         Result (I) := Hex_Chars (Natural (Val and 16#F#) + 1);
         Val := Shift_Right (Val, 4);
      end loop;
      return Result;
   end To_Hex_64;

   ---------------
   -- Parse_Hex --
   ---------------

   function Parse_Hex (S : String) return Word is
      Result : Word := 0;
      C      : Character;
      Digit  : Word;
      Start  : Positive := S'First;
   begin
      --  Skip 0x prefix if present
      if S'Length >= 2 and then S (S'First .. S'First + 1) = "0x" then
         Start := S'First + 2;
      end if;

      for I in Start .. S'Last loop
         C := S (I);
         case C is
            when '0' .. '9' =>
               Digit := Character'Pos (C) - Character'Pos ('0');
            when 'a' .. 'f' =>
               Digit := Character'Pos (C) - Character'Pos ('a') + 10;
            when 'A' .. 'F' =>
               Digit := Character'Pos (C) - Character'Pos ('A') + 10;
            when others =>
               exit;
         end case;
         Result := Shift_Left (Result, 4) or Digit;
      end loop;

      return Result;
   end Parse_Hex;

   ------------------
   -- Parse_Hex_64 --
   ------------------

   function Parse_Hex_64 (S : String) return Double_Word is
      Result : Double_Word := 0;
      C      : Character;
      Digit  : Double_Word;
      Start  : Positive := S'First;
   begin
      --  Skip 0x prefix if present
      if S'Length >= 2 and then S (S'First .. S'First + 1) = "0x" then
         Start := S'First + 2;
      end if;

      for I in Start .. S'Last loop
         C := S (I);
         case C is
            when '0' .. '9' =>
               Digit := Double_Word (Character'Pos (C) - Character'Pos ('0'));
            when 'a' .. 'f' =>
               Digit := Double_Word (Character'Pos (C) - Character'Pos ('a') + 10);
            when 'A' .. 'F' =>
               Digit := Double_Word (Character'Pos (C) - Character'Pos ('A') + 10);
            when others =>
               exit;
         end case;
         Result := Shift_Left (Result, 4) or Digit;
      end loop;

      return Result;
   end Parse_Hex_64;

   -------------------
   -- Parse_Natural --
   -------------------

   function Parse_Natural (S : String) return Natural is
      Result : Natural := 0;
   begin
      for I in S'Range loop
         exit when S (I) not in '0' .. '9';
         Result := Result * 10 + (Character'Pos (S (I)) - Character'Pos ('0'));
      end loop;
      return Result;
   end Parse_Natural;

   ------------------------------
   -- Show_Current_Instruction --
   ------------------------------

   procedure Show_Current_Instruction (Dbg : Debugger_State;
                                       CPU : RISCV.CPU.CPU_State;
                                       Mem : in out Memory.Memory_Unit) is
      Instruction : Word;
      Info        : Symbols.Symbol_Info;
   begin
      Instruction := Memory.Read_Word (Mem, Memory_Address (CPU.PC));
      Put (To_Hex (CPU.PC) & ":  " & To_Hex (Instruction) & "  ");
      Put (Disasm.Disassemble (Instruction, CPU.PC));

      --  Show function name if available
      if Dbg.Symbols_Loaded and then
         Symbols.Lookup_By_Address (Dbg.Symbols.all, Memory_Address (CPU.PC), Info) and then
         Info.Sym_Type = Symbols.SYM_FUNCTION
      then
         declare
            Offset : constant Memory_Address := Memory_Address (CPU.PC) - Info.Address;
         begin
            Put ("  <" & Info.Name (1 .. Info.Name_Len));
            if Offset > 0 then
               Put ("+" & To_Hex (Word (Offset)));
            end if;
            Put (">");
         end;
      end if;
      New_Line;
   end Show_Current_Instruction;

   --------------------
   -- Show_Registers --
   --------------------

   procedure Show_Registers (CPU : RISCV.CPU.CPU_State) is
      Val : Word;
   begin
      Put_Line ("PC  = 0x" & To_Hex (CPU.PC));
      New_Line;

      for Row in 0 .. 7 loop
         for Col in 0 .. 3 loop
            declare
               Reg : constant Register_Index :=
                  Register_Index (Row * 4 + Col);
            begin
               Val := RISCV.CPU.Read_Register (CPU, Reg);
               Put (Disasm.Reg_Name (Reg));
               if Disasm.Reg_Name (Reg)'Length < 3 then
                  Put (" ");
               end if;
               Put ("=0x" & To_Hex (Val));
               if Col < 3 then
                  Put ("  ");
               end if;
            end;
         end loop;
         New_Line;
      end loop;
   end Show_Registers;

   --------------------------------
   -- Show_Current_Instruction_64 --
   --------------------------------

   procedure Show_Current_Instruction_64 (Dbg : Debugger_State;
                                          CPU : RISCV.CPU64.CPU64_State;
                                          Mem : in out Memory.Memory_Unit) is
      Instruction : Word;
      Info        : Symbols.Symbol_Info;
      PC32        : constant Memory_Address := Memory_Address (CPU.PC);
   begin
      Instruction := Memory.Read_Word (Mem, PC32);
      Put (To_Hex_64 (Double_Word (CPU.PC)) & ":  " & To_Hex (Instruction) & "  ");
      Put (Disasm.Disassemble (Instruction, Word (PC32)));

      --  Show function name if available
      if Dbg.Symbols_Loaded and then
         Symbols.Lookup_By_Address (Dbg.Symbols.all, PC32, Info) and then
         Info.Sym_Type = Symbols.SYM_FUNCTION
      then
         declare
            Offset : constant Memory_Address := PC32 - Info.Address;
         begin
            Put ("  <" & Info.Name (1 .. Info.Name_Len));
            if Offset > 0 then
               Put ("+" & To_Hex (Word (Offset)));
            end if;
            Put (">");
         end;
      end if;
      New_Line;
   end Show_Current_Instruction_64;

   ----------------------
   -- Show_Registers_64 --
   ----------------------

   procedure Show_Registers_64 (CPU : RISCV.CPU64.CPU64_State) is
      Val : Double_Word;
   begin
      Put_Line ("PC  = 0x" & To_Hex_64 (Double_Word (CPU.PC)));
      New_Line;

      for Row in 0 .. 7 loop
         for Col in 0 .. 3 loop
            declare
               Reg : constant Register_Index :=
                  Register_Index (Row * 4 + Col);
            begin
               Val := RISCV.CPU64.Read_Register (CPU, Reg);
               Put (Disasm.Reg_Name (Reg));
               if Disasm.Reg_Name (Reg)'Length < 3 then
                  Put (" ");
               end if;
               Put ("=0x" & To_Hex_64 (Val));
               if Col < 3 then
                  Put ("  ");
               end if;
            end;
         end loop;
         New_Line;
      end loop;
   end Show_Registers_64;

   -----------------------
   -- Show_FP_Registers --
   -----------------------

   procedure Show_FP_Registers (FP : RISCV.FPU.FPU_State) is
      use RISCV.FPU;
      FP_Val : FP_Register;
   begin
      Put_Line ("Floating-Point Registers:");
      New_Line;

      for Row in 0 .. 7 loop
         for Col in 0 .. 3 loop
            declare
               Reg : constant Register_Index :=
                  Register_Index (Row * 4 + Col);
            begin
               FP_Val := Read_Register (FP, Reg);
               Put ("f" & Register_Index'Image (Reg) (2 .. Register_Index'Image (Reg)'Last));
               if Reg < 10 then
                  Put (" ");
               end if;
               Put ("=0x" & To_Hex (Word (FP_Val and 16#FFFFFFFF#)));
               Put (" ");
               if Col < 3 then
                  Put ("  ");
               end if;
            end;
         end loop;
         New_Line;
      end loop;
   end Show_FP_Registers;

   procedure Show_FP_Registers (CPU : RISCV.CPU.CPU_State) is
   begin
      Show_FP_Registers (CPU.FP);
   end Show_FP_Registers;

   ----------------------
   -- Show_FP_Register --
   ----------------------

   procedure Show_FP_Register (CPU : RISCV.CPU.CPU_State; Reg : Natural) is
      use RISCV.FPU;
      FP_Val : FP_Register;
   begin
      if Reg > 31 then
         Put_Line ("Invalid register number (0-31)");
         return;
      end if;

      FP_Val := Read_Register (CPU.FP, Register_Index (Reg));
      Put_Line ("f" & Natural'Image (Reg) & ":");
      Put_Line ("  Hex:    0x" & To_Hex (Word (FP_Val and 16#FFFFFFFF#)));
      Put_Line ("  Double: (use as 64-bit FP value)");
   end Show_FP_Register;

   --------------------------
   -- Show_Vector_Registers --
   --------------------------

   procedure Show_Vector_Registers (CPU : RISCV.CPU.CPU_State) is
      use RISCV.Vector;
      SEW_Val   : Word;
      SEW_Bytes : Natural;
      Elems     : Natural;

      --  Format a byte as a 2-character hex string
      function Hex_B (B : Byte) return String is
         Hex_Chars : constant String := "0123456789abcdef";
      begin
         return Hex_Chars (Natural (Shift_Right (B, 4)) + 1) &
                Hex_Chars (Natural (B and 16#0F#) + 1);
      end Hex_B;

      --  Format the lower 16 bits of a Word as a 4-character hex string
      function Hex_H (V : Word) return String is
         Hex_Chars : constant String := "0123456789abcdef";
         Result    : String (1 .. 4);
         Val       : Word := V and 16#FFFF#;
      begin
         for I in reverse Result'Range loop
            Result (I) := Hex_Chars (Natural (Val and 16#F#) + 1);
            Val := Shift_Right (Val, 4);
         end loop;
         return Result;
      end Hex_H;

      --  Assemble SEW_Bytes consecutive bytes from a register into a Word (LE)
      function Assemble (R : Register_Index; Base : Natural; N : Natural)
                         return Word
      is
         Val : Word := 0;
      begin
         for BI in 0 .. N - 1 loop
            Val := Val or Shift_Left (Word (CPU.VU.Registers (R).Data (Base + BI)),
                                      BI * 8);
         end loop;
         return Val;
      end Assemble;

   begin
      Put_Line ("Vector Registers:");
      Put_Line ("  VL    :" & Word'Image (CPU.VU.VL));
      Put_Line ("  VStart:" & Word'Image (CPU.VU.VStart));

      case CPU.VU.VType.VSEW is
         when SEW_8  => SEW_Val := 8;  SEW_Bytes := 1;
         when SEW_16 => SEW_Val := 16; SEW_Bytes := 2;
         when SEW_32 => SEW_Val := 32; SEW_Bytes := 4;
         when SEW_64 => SEW_Val := 64; SEW_Bytes := 8;
      end case;
      Elems := VLENB / SEW_Bytes;

      Put_Line ("  SEW   :" & Word'Image (SEW_Val) &
                " bits  (" & Natural'Image (Elems) & " elem/reg)");

      Put ("  LMUL  : ");
      case CPU.VU.VType.VLMUL is
         when LMUL_1  => Put_Line ("m1");
         when LMUL_2  => Put_Line ("m2");
         when LMUL_4  => Put_Line ("m4");
         when LMUL_8  => Put_Line ("m8");
         when LMUL_F2 => Put_Line ("mf2");
         when LMUL_F4 => Put_Line ("mf4");
         when LMUL_F8 => Put_Line ("mf8");
      end case;

      New_Line;

      for R in Register_Index loop
         declare
            All_Zero : Boolean := True;
            Ri       : constant Natural := Natural (R);
            Pad      : constant String := (if Ri < 10 then " " else "");
         begin
            for B in 0 .. VLENB - 1 loop
               if CPU.VU.Registers (R).Data (B) /= 0 then
                  All_Zero := False;
               end if;
            end loop;

            Put ("  v" & Pad & Natural'Image (Ri) (2 .. Natural'Image (Ri)'Last)
                 & ": ");

            if All_Zero then
               Put_Line ("[ 0 ... ]");
            else
               Put ("[");
               for E in 0 .. Elems - 1 loop
                  declare
                     Base : constant Natural := E * SEW_Bytes;
                  begin
                     if SEW_Bytes = 1 then
                        Put (" " & Hex_B (CPU.VU.Registers (R).Data (Base)));
                     elsif SEW_Bytes = 2 then
                        Put (" " & Hex_H (Assemble (R, Base, 2)));
                     elsif SEW_Bytes = 4 then
                        Put (" " & To_Hex (Assemble (R, Base, 4)));
                     else
                        --  64-bit: high word first for readability
                        Put (" " & To_Hex (Assemble (R, Base + 4, 4)) &
                                   To_Hex (Assemble (R, Base, 4)));
                     end if;
                  end;
               end loop;
               Put_Line (" ]");
            end if;
         end;
      end loop;
   end Show_Vector_Registers;

   -----------------
   -- Dump_Memory --
   -----------------

   procedure Dump_Memory (Mem     : in out Memory.Memory_Unit;
                          Address : Word;
                          Count   : Positive) is
      Addr    : Word := Address;
      B       : Byte;
      Line_Bytes : String (1 .. 16);
   begin
      for Line in 1 .. (Count + 15) / 16 loop
         Put (To_Hex (Addr) & ": ");

         --  Hex dump
         for I in 0 .. 15 loop
            if Natural ((Line - 1) * 16 + I) < Count then
               B := Memory.Read_Byte (Mem, Memory_Address (Addr + Word (I)));
               declare
                  Hex : constant String := To_Hex (Word (B));
               begin
                  Put (Hex (7 .. 8) & " ");
               end;
               --  Printable character
               if B >= 32 and B < 127 then
                  Line_Bytes (I + 1) := Character'Val (B);
               else
                  Line_Bytes (I + 1) := '.';
               end if;
            else
               Put ("   ");
               Line_Bytes (I + 1) := ' ';
            end if;

            if I = 7 then
               Put (" ");
            end if;
         end loop;

         Put (" |" & Line_Bytes & "|");
         New_Line;

         Addr := Addr + 16;
      end loop;
   end Dump_Memory;

   ------------------------
   -- Disassemble_Memory --
   ------------------------

   procedure Disassemble_Memory (Dbg     : Debugger_State;
                                 Mem     : in out Memory.Memory_Unit;
                                 Address : Word;
                                 Count   : Positive) is
      Addr        : Word := Address;
      Instruction : Word;
      Info        : Symbols.Symbol_Info;
   begin
      for I in 1 .. Count loop
         Instruction := Memory.Read_Word (Mem, Memory_Address (Addr));
         Put (To_Hex (Addr) & ":  " & To_Hex (Instruction) & "  ");
         Put (Disasm.Disassemble (Instruction, Addr));

         --  Show function name if available
         if Dbg.Symbols_Loaded and then
            Symbols.Lookup_By_Address (Dbg.Symbols.all, Memory_Address (Addr), Info) and then
            Info.Sym_Type = Symbols.SYM_FUNCTION
         then
            declare
               Offset : constant Memory_Address := Memory_Address (Addr) - Info.Address;
            begin
               Put ("  <" & Info.Name (1 .. Info.Name_Len));
               if Offset > 0 then
                  Put ("+" & To_Hex (Word (Offset)));
               end if;
               Put (">");
            end;
         end if;
         New_Line;

         Addr := Addr + 4;
      end loop;
   end Disassemble_Memory;

   ----------------
   -- Print_Help --
   ----------------

   procedure Print_Help is
   begin
      Put_Line ("Debugger commands:");
      Put_Line ("  s, step          - Single step one instruction");
      Put_Line ("  c, continue      - Continue until breakpoint or halt");
      Put_Line ("  r, regs          - Show all integer registers");
      Put_Line ("  fregs            - Show all floating-point registers");
      Put_Line ("  freg <n>         - Show floating-point register n (0-31)");
      Put_Line ("  vregs            - Show vector registers (VL/SEW/LMUL + element data)");
      Put_Line ("  m <addr> [n]     - Dump n bytes of memory (default 64)");
      Put_Line ("  d <addr> [n]     - Disassemble n instructions (default 10)");
      Put_Line ("  b <addr|func>    - Set breakpoint at address or function name");
      Put_Line ("  bl               - List all breakpoints");
      Put_Line ("  bc <n>           - Clear breakpoint number n");
      Put_Line ("  bc all           - Clear all breakpoints");
      Put_Line ("  watch <addr> [r|w|rw] - Set watchpoint (default: rw)");
      Put_Line ("  wl               - List all watchpoints");
      Put_Line ("  wc <n>           - Clear watchpoint number n");
      Put_Line ("  wc all           - Clear all watchpoints");
      Put_Line ("  sym <name>       - Look up a symbol by name");
      Put_Line ("  syms             - List all functions from symbol table");
      Put_Line ("  info functions   - Same as syms");
      Put_Line ("  bt, backtrace    - Show call stack backtrace");
      Put_Line ("  x                - Show current instruction");
      Put_Line ("  trace <file>     - Start logging instructions to file");
      Put_Line ("  trace off        - Stop tracing");
      Put_Line ("  trace            - Show trace status");
      Put_Line ("  q, quit          - Quit debugger");
      Put_Line ("  h, help, ?       - Show this help");
      Put_Line ("");
      Put_Line ("Addresses can be hex (0x1000) or decimal (4096)");
      Put_Line ("Watchpoint types: r=read, w=write, rw=read/write");
   end Print_Help;

   -------------------
   -- At_Breakpoint --
   -------------------

   function At_Breakpoint (Dbg : Debugger_State;
                           PC  : Double_Word) return Boolean is
   begin
      for I in 1 .. Max_Breakpoints loop
         if Dbg.Breakpoint_Enabled (I) and then Dbg.Breakpoints (I) = PC then
            return True;
         end if;
      end loop;
      return False;
   end At_Breakpoint;

   --------------------
   -- Add_Breakpoint --
   --------------------

   procedure Add_Breakpoint (Dbg     : in out Debugger_State;
                             Address : Double_Word;
                             Success : out Boolean) is
   begin
      --  Check if already exists
      for I in 1 .. Max_Breakpoints loop
         if Dbg.Breakpoint_Enabled (I) and then
            Dbg.Breakpoints (I) = Address
         then
            Put_Line ("Breakpoint already exists at 0x" & To_Hex_64 (Address));
            Success := True;
            return;
         end if;
      end loop;

      --  Find free slot
      for I in 1 .. Max_Breakpoints loop
         if not Dbg.Breakpoint_Enabled (I) then
            Dbg.Breakpoints (I) := Address;
            Dbg.Breakpoint_Enabled (I) := True;
            Dbg.Num_Breakpoints := Dbg.Num_Breakpoints + 1;
            Put_Line ("Breakpoint " & Positive'Image (I) &
                      " set at 0x" & To_Hex_64 (Address));
            Success := True;
            return;
         end if;
      end loop;

      Put_Line ("Maximum breakpoints reached");
      Success := False;
   end Add_Breakpoint;

   -----------------------
   -- Remove_Breakpoint --
   -----------------------

   procedure Remove_Breakpoint (Dbg     : in out Debugger_State;
                                Index   : Positive;
                                Success : out Boolean) is
   begin
      if Index > Max_Breakpoints then
         Put_Line ("Invalid breakpoint number");
         Success := False;
         return;
      end if;

      if Dbg.Breakpoint_Enabled (Index) then
         Dbg.Breakpoint_Enabled (Index) := False;
         Dbg.Num_Breakpoints := Dbg.Num_Breakpoints - 1;
         Put_Line ("Breakpoint " & Positive'Image (Index) & " cleared");
         Success := True;
      else
         Put_Line ("Breakpoint " & Positive'Image (Index) & " not set");
         Success := False;
      end if;
   end Remove_Breakpoint;

   ----------------------
   -- List_Breakpoints --
   ----------------------

   procedure List_Breakpoints (Dbg : Debugger_State) is
      Found : Boolean := False;
   begin
      for I in 1 .. Max_Breakpoints loop
         if Dbg.Breakpoint_Enabled (I) then
            Put_Line ("Breakpoint" & Positive'Image (I) &
                      ": 0x" & To_Hex_64 (Dbg.Breakpoints (I)));
            Found := True;
         end if;
      end loop;

      if not Found then
         Put_Line ("No breakpoints set");
      end if;
   end List_Breakpoints;

   --------------------
   -- Add_Watchpoint --
   --------------------

   procedure Add_Watchpoint (Dbg     : in out Debugger_State;
                             Address : Double_Word;
                             WType   : Watchpoint_Type;
                             Success : out Boolean) is
   begin
      --  Check if already exists at this address
      for I in 1 .. Max_Watchpoints loop
         if Dbg.Watchpoint_Enabled (I) and then
            Dbg.Watchpoints (I).Address = Address
         then
            Put_Line ("Watchpoint already exists at 0x" & To_Hex_64 (Address));
            Success := True;
            return;
         end if;
      end loop;

      --  Find free slot
      for I in 1 .. Max_Watchpoints loop
         if not Dbg.Watchpoint_Enabled (I) then
            Dbg.Watchpoints (I).Address := Address;
            Dbg.Watchpoints (I).WType := WType;
            Dbg.Watchpoint_Enabled (I) := True;
            Dbg.Num_Watchpoints := Dbg.Num_Watchpoints + 1;

            Put ("Watchpoint " & Positive'Image (I) &
                 " set at 0x" & To_Hex_64 (Address) & " (");
            case WType is
               when Read => Put ("read");
               when Write => Put ("write");
               when ReadWrite => Put ("read/write");
            end case;
            Put_Line (")");

            Success := True;
            return;
         end if;
      end loop;

      Put_Line ("Maximum watchpoints reached");
      Success := False;
   end Add_Watchpoint;

   -----------------------
   -- Remove_Watchpoint --
   -----------------------

   procedure Remove_Watchpoint (Dbg     : in out Debugger_State;
                                Index   : Positive;
                                Success : out Boolean) is
   begin
      if Index > Max_Watchpoints then
         Put_Line ("Invalid watchpoint number");
         Success := False;
         return;
      end if;

      if Dbg.Watchpoint_Enabled (Index) then
         Dbg.Watchpoint_Enabled (Index) := False;
         Dbg.Num_Watchpoints := Dbg.Num_Watchpoints - 1;
         Put_Line ("Watchpoint " & Positive'Image (Index) & " cleared");
         Success := True;
      else
         Put_Line ("Watchpoint " & Positive'Image (Index) & " not set");
         Success := False;
      end if;
   end Remove_Watchpoint;

   ----------------------
   -- List_Watchpoints --
   ----------------------

   procedure List_Watchpoints (Dbg : Debugger_State) is
      Found : Boolean := False;
   begin
      for I in 1 .. Max_Watchpoints loop
         if Dbg.Watchpoint_Enabled (I) then
            Put ("Watchpoint" & Positive'Image (I) &
                 ": 0x" & To_Hex_64 (Dbg.Watchpoints (I).Address) & " (");
            case Dbg.Watchpoints (I).WType is
               when Read => Put ("read");
               when Write => Put ("write");
               when ReadWrite => Put ("read/write");
            end case;
            Put_Line (")");
            Found := True;
         end if;
      end loop;

      if not Found then
         Put_Line ("No watchpoints set");
      end if;
   end List_Watchpoints;

   ----------------------
   -- Check_Watchpoint --
   ----------------------

   function Check_Watchpoint (Dbg       : in out Debugger_State;
                              Address   : Double_Word;
                              Is_Write  : Boolean) return Boolean is
   begin
      for I in 1 .. Max_Watchpoints loop
         if Dbg.Watchpoint_Enabled (I) and then
            Dbg.Watchpoints (I).Address = Address
         then
            --  Check if the access type matches the watchpoint type
            case Dbg.Watchpoints (I).WType is
               when Read =>
                  if not Is_Write then
                     Dbg.Watchpoint_Hit := True;
                     Dbg.Last_Watch_Addr := Address;
                     Dbg.Last_Watch_Type := Read;
                     return True;
                  end if;
               when Write =>
                  if Is_Write then
                     Dbg.Watchpoint_Hit := True;
                     Dbg.Last_Watch_Addr := Address;
                     Dbg.Last_Watch_Type := Write;
                     return True;
                  end if;
               when ReadWrite =>
                  Dbg.Watchpoint_Hit := True;
                  Dbg.Last_Watch_Addr := Address;
                  if Is_Write then
                     Dbg.Last_Watch_Type := Write;
                  else
                     Dbg.Last_Watch_Type := Read;
                  end if;
                  return True;
            end case;
         end if;
      end loop;
      return False;
   end Check_Watchpoint;

   ---------
   -- Run --
   ---------

   procedure Run (Dbg : in out Debugger_State;
                  CPU : in out RISCV.CPU.CPU_State;
                  Mem : in out Memory.Memory_Unit) is
      Line    : String (1 .. 256);
      Last    : Natural;
      Whitespace : constant Ada.Strings.Maps.Character_Set :=
         Ada.Strings.Maps.To_Set (" " & ASCII.HT);

      function Get_Token (S : String; N : Positive) return String;

      function Get_Token (S : String; N : Positive) return String is
         Start : Natural := S'First;
         Finish : Natural;
         Token_Num : Natural := 0;
      begin
         loop
            --  Skip leading whitespace
            while Start <= S'Last and then
                  Ada.Strings.Maps.Is_In (S (Start), Whitespace)
            loop
               Start := Start + 1;
            end loop;

            exit when Start > S'Last;

            --  Find end of token
            Finish := Start;
            while Finish <= S'Last and then
                  not Ada.Strings.Maps.Is_In (S (Finish), Whitespace)
            loop
               Finish := Finish + 1;
            end loop;

            Token_Num := Token_Num + 1;
            if Token_Num = N then
               return S (Start .. Finish - 1);
            end if;

            Start := Finish;
         end loop;

         return "";
      end Get_Token;

   begin
      --  Enable memory access tracking for watchpoints
      Mem.Track_Access := True;

      Put_Line ("RISC-V Debugger. Type 'h' for help.");
      New_Line;

      --  Show initial state
      Show_Current_Instruction (Dbg, CPU, Mem);

      loop
         exit when Dbg.Quit_Requested;
         exit when CPU.Halted;

         Put ("(riscv) ");
         Get_Line (Line, Last);

         declare
            Cmd : constant String := Get_Token (Line (1 .. Last), 1);
            Arg1 : constant String := Get_Token (Line (1 .. Last), 2);
            Arg2 : constant String := Get_Token (Line (1 .. Last), 3);
         begin
            if Cmd = "" then
               --  Empty line: repeat step
               if Dbg.Trace_Enabled and then Dbg.Trace_File_Open then
                  declare
                     Instr : constant Word :=
                        Memory.Read_Word (Mem, Memory_Address (CPU.PC));
                  begin
                     Put_Line (Trace_File,
                               To_Hex (CPU.PC) & ":  " & To_Hex (Instr) & "  " &
                               Disasm.Disassemble (Instr, CPU.PC));
                  end;
               end if;
               Mem.Access_Occurred := False;
               RISCV.CPU.Step (CPU, Mem, Trace => True);
               if Mem.Access_Occurred and then
                  Check_Watchpoint (Dbg, Double_Word (Mem.Last_Access_Addr),
                                   Mem.Last_Access_Write)
               then
                  Put_Line ("Watchpoint hit at 0x" & To_Hex_64 (Double_Word (Mem.Last_Access_Addr)) &
                           (if Mem.Last_Access_Write then " (write)" else " (read)"));
               end if;

            elsif Cmd = "s" or Cmd = "step" then
               if Dbg.Trace_Enabled and then Dbg.Trace_File_Open then
                  declare
                     Instr : constant Word :=
                        Memory.Read_Word (Mem, Memory_Address (CPU.PC));
                  begin
                     Put_Line (Trace_File,
                               To_Hex (CPU.PC) & ":  " & To_Hex (Instr) & "  " &
                               Disasm.Disassemble (Instr, CPU.PC));
                  end;
               end if;
               Mem.Access_Occurred := False;
               RISCV.CPU.Step (CPU, Mem, Trace => True);
               if Mem.Access_Occurred and then
                  Check_Watchpoint (Dbg, Double_Word (Mem.Last_Access_Addr),
                                   Mem.Last_Access_Write)
               then
                  Put_Line ("Watchpoint hit at 0x" & To_Hex_64 (Double_Word (Mem.Last_Access_Addr)) &
                           (if Mem.Last_Access_Write then " (write)" else " (read)"));
               end if;

            elsif Cmd = "c" or Cmd = "continue" then
               --  Run until breakpoint or halt
               loop
                  --  Write trace line if tracing is active
                  if Dbg.Trace_Enabled and then Dbg.Trace_File_Open then
                     declare
                        Instr : constant Word :=
                           Memory.Read_Word (Mem, Memory_Address (CPU.PC));
                     begin
                        Put_Line (Trace_File,
                                  To_Hex (CPU.PC) & ":  " & To_Hex (Instr) & "  " &
                                  Disasm.Disassemble (Instr, CPU.PC));
                     end;
                  end if;

                  --  Clear access tracking
                  Mem.Access_Occurred := False;

                  RISCV.CPU.Step (CPU, Mem, Trace => False);
                  exit when CPU.Halted;

                  --  Check for watchpoint hit
                  if Mem.Access_Occurred and then
                     Check_Watchpoint (Dbg, Double_Word (Mem.Last_Access_Addr),
                                      Mem.Last_Access_Write)
                  then
                     Put_Line ("Watchpoint hit at 0x" & To_Hex (Word (Mem.Last_Access_Addr)) &
                              (if Mem.Last_Access_Write then " (write)" else " (read)"));
                     Show_Current_Instruction (Dbg, CPU, Mem);
                     exit;
                  end if;

                  if At_Breakpoint (Dbg, Double_Word (CPU.PC)) then
                     Put_Line ("Breakpoint hit at 0x" & To_Hex (CPU.PC));
                     Show_Current_Instruction (Dbg, CPU, Mem);
                     exit;
                  end if;
               end loop;

            elsif Cmd = "r" or Cmd = "regs" then
               Show_Registers (CPU);

            elsif Cmd = "fregs" then
               Show_FP_Registers (CPU);

            elsif Cmd = "freg" then
               if Arg1 = "" then
                  Put_Line ("Usage: freg <register_number>");
               else
                  declare
                     Reg_Num : constant Natural := Parse_Natural (Arg1);
                  begin
                     Show_FP_Register (CPU, Reg_Num);
                  end;
               end if;

            elsif Cmd = "vregs" then
               Show_Vector_Registers (CPU);

            elsif Cmd = "m" then
               if Arg1 = "" then
                  Put_Line ("Usage: m <address> [count]");
               else
                  declare
                     Addr  : constant Word := Parse_Hex (Arg1);
                     Count : Natural := 64;
                  begin
                     if Arg2 /= "" then
                        Count := Parse_Natural (Arg2);
                        if Count = 0 then
                           Count := 64;
                        end if;
                     end if;
                     Dump_Memory (Mem, Addr, Count);
                  end;
               end if;

            elsif Cmd = "d" then
               declare
                  Addr  : Word := CPU.PC;
                  Count : Natural := 10;
               begin
                  if Arg1 /= "" then
                     Addr := Parse_Hex (Arg1);
                  end if;
                  if Arg2 /= "" then
                     Count := Parse_Natural (Arg2);
                     if Count = 0 then
                        Count := 10;
                     end if;
                  end if;
                  Disassemble_Memory (Dbg, Mem, Addr, Count);
               end;

            elsif Cmd = "b" then
               if Arg1 = "" then
                  Put_Line ("Usage: b <address|function_name>");
               else
                  declare
                     Addr    : Double_Word;
                     Success : Boolean;
                     Info    : Symbols.Symbol_Info;
                  begin
                     --  Try to parse as hex address
                     if Arg1 (Arg1'First) = '0' or else
                        Arg1 (Arg1'First) in '1' .. '9' or else
                        Arg1 (Arg1'First) in 'a' .. 'f' or else
                        Arg1 (Arg1'First) in 'A' .. 'F'
                     then
                        Addr := Parse_Hex_64 (Arg1);
                        Add_Breakpoint (Dbg, Addr, Success);
                     --  Try to look up as symbol name
                     elsif Dbg.Symbols_Loaded and then
                           Symbols.Lookup_By_Name (Dbg.Symbols.all, Arg1, Info)
                     then
                        Addr := Double_Word (Info.Address);
                        Add_Breakpoint (Dbg, Addr, Success);
                        if Success then
                           Put_Line ("Breakpoint set at " & Info.Name (1 .. Info.Name_Len) &
                                    " (" & To_Hex_64 (Addr) & ")");
                        end if;
                     else
                        Put_Line ("Symbol not found: " & Arg1);
                     end if;
                  end;
               end if;

            elsif Cmd = "bl" then
               List_Breakpoints (Dbg);

            elsif Cmd = "bc" then
               if Arg1 = "" then
                  Put_Line ("Usage: bc <number> or bc all");
               elsif Arg1 = "all" then
                  for I in 1 .. Max_Breakpoints loop
                     Dbg.Breakpoint_Enabled (I) := False;
                  end loop;
                  Dbg.Num_Breakpoints := 0;
                  Put_Line ("All breakpoints cleared");
               else
                  declare
                     Idx     : constant Natural := Parse_Natural (Arg1);
                     Success : Boolean;
                  begin
                     if Idx > 0 then
                        Remove_Breakpoint (Dbg, Idx, Success);
                     else
                        Put_Line ("Invalid breakpoint number");
                     end if;
                  end;
               end if;

            elsif Cmd = "watch" then
               if Arg1 = "" then
                  Put_Line ("Usage: watch <address> [r|w|rw]");
               else
                  declare
                     Addr    : constant Double_Word := Parse_Hex_64 (Arg1);
                     WType   : Watchpoint_Type := ReadWrite;  -- Default
                     Success : Boolean;
                  begin
                     --  Parse watchpoint type
                     if Arg2 /= "" then
                        if Arg2 = "r" then
                           WType := Read;
                        elsif Arg2 = "w" then
                           WType := Write;
                        elsif Arg2 = "rw" then
                           WType := ReadWrite;
                        else
                           Put_Line ("Invalid watchpoint type. Use: r, w, or rw");
                           goto Skip_Watch;
                        end if;
                     end if;

                     Add_Watchpoint (Dbg, Addr, WType, Success);
                     <<Skip_Watch>>
                  end;
               end if;

            elsif Cmd = "wl" then
               List_Watchpoints (Dbg);

            elsif Cmd = "wc" then
               if Arg1 = "" then
                  Put_Line ("Usage: wc <number> or wc all");
               elsif Arg1 = "all" then
                  for I in 1 .. Max_Watchpoints loop
                     Dbg.Watchpoint_Enabled (I) := False;
                  end loop;
                  Dbg.Num_Watchpoints := 0;
                  Put_Line ("All watchpoints cleared");
               else
                  declare
                     Idx     : constant Natural := Parse_Natural (Arg1);
                     Success : Boolean;
                  begin
                     if Idx > 0 then
                        Remove_Watchpoint (Dbg, Idx, Success);
                     else
                        Put_Line ("Invalid watchpoint number");
                     end if;
                  end;
               end if;

            elsif Cmd = "x" then
               Show_Current_Instruction (Dbg, CPU, Mem);

            elsif Cmd = "q" or Cmd = "quit" then
               Dbg.Quit_Requested := True;

            elsif Cmd = "sym" then
               --  Look up a single symbol by name
               if Arg1 = "" then
                  Put_Line ("Usage: sym <name>");
               elsif not Dbg.Symbols_Loaded then
                  Put_Line ("No symbols loaded");
               else
                  declare
                     Info    : Symbols.Symbol_Info;
                     Type_Str : String (1 .. 8);
                  begin
                     if Symbols.Lookup_By_Name (Dbg.Symbols.all, Arg1, Info) then
                        case Info.Sym_Type is
                           when Symbols.SYM_FUNCTION => Type_Str := "FUNC    ";
                           when Symbols.SYM_OBJECT   => Type_Str := "OBJECT  ";
                           when Symbols.SYM_SECTION  => Type_Str := "SECTION ";
                           when Symbols.SYM_FILE     => Type_Str := "FILE    ";
                           when others               => Type_Str := "UNKNOWN ";
                        end case;
                        Put (Type_Str & "  ");
                        Put ("0x" & To_Hex (Word (Info.Address)));
                        if Info.Size > 0 then
                           Put ("  size " & To_Hex (Info.Size));
                        end if;
                        Put_Line ("  " & Info.Name (1 .. Info.Name_Len));
                     else
                        Put_Line ("Symbol not found: " & Arg1);
                     end if;
                  end;
               end if;

            elsif Cmd = "syms" then
               if Dbg.Symbols_Loaded then
                  --  List only function symbols
                  declare
                     Count : Natural := 0;
                     Info  : Symbols.Symbol_Info;
                  begin
                     Put_Line ("Functions (" &
                               Natural'Image (Symbols.Get_Symbol_Count (Dbg.Symbols.all)) &
                               " total symbols):");
                     for I in 1 .. Symbols.Get_Symbol_Count (Dbg.Symbols.all) loop
                        if Symbols.Get_Symbol (Dbg.Symbols.all, I, Info) and then
                           Info.Sym_Type = Symbols.SYM_FUNCTION
                        then
                           Put ("  0x" & To_Hex (Word (Info.Address)));
                           if Info.Size > 0 then
                              Put (" [" & To_Hex (Info.Size) & "]");
                           end if;
                           Put ("  " & Info.Name (1 .. Info.Name_Len));
                           New_Line;
                           Count := Count + 1;
                        end if;
                     end loop;
                     Put_Line (Natural'Image (Count) & " functions");
                  end;
               else
                  Put_Line ("No symbols loaded");
               end if;

            elsif Cmd = "info" then
               if Arg1 = "functions" or Arg1 = "f" then
                  if Dbg.Symbols_Loaded then
                     --  Show only function symbols
                     declare
                        Count : Natural := 0;
                        Info  : Symbols.Symbol_Info;
                     begin
                        Put_Line ("Functions:");
                        for I in 1 .. Symbols.Get_Symbol_Count (Dbg.Symbols.all) loop
                           if Symbols.Get_Symbol (Dbg.Symbols.all, I, Info) and then
                              Info.Sym_Type = Symbols.SYM_FUNCTION
                           then
                              Put ("  0x" & To_Hex (Word (Info.Address)));
                              if Info.Size > 0 then
                                 Put (" [" & To_Hex (Info.Size) & "]");
                              end if;
                              Put_Line ("  " & Info.Name (1 .. Info.Name_Len));
                              Count := Count + 1;
                           end if;
                        end loop;
                        Put_Line (Natural'Image (Count) & " functions found");
                     end;
                  else
                     Put_Line ("No symbols loaded");
                  end if;
               else
                  Put_Line ("Usage: info functions");
               end if;

            elsif Cmd = "trace" then
               if Arg1 = "" then
                  --  Status
                  if Dbg.Trace_Enabled then
                     Put_Line ("Tracing active (file open)");
                  else
                     Put_Line ("Tracing off");
                  end if;
               elsif Arg1 = "off" then
                  if Dbg.Trace_File_Open then
                     Close (Trace_File);
                     Dbg.Trace_File_Open := False;
                  end if;
                  Dbg.Trace_Enabled := False;
                  Put_Line ("Tracing disabled");
               else
                  --  Open a new trace file
                  begin
                     if Dbg.Trace_File_Open then
                        Close (Trace_File);
                        Dbg.Trace_File_Open := False;
                     end if;
                     Create (Trace_File, Out_File, Arg1);
                     Dbg.Trace_File_Open := True;
                     Dbg.Trace_Enabled   := True;
                     Put_Line ("Tracing to " & Arg1);
                  exception
                     when Name_Error =>
                        Put_Line ("Cannot create file: " & Arg1);
                  end;
               end if;

            elsif Cmd = "bt" or Cmd = "backtrace" or Cmd = "where" then
               --  Show call stack backtrace
               Show_Backtrace (Dbg, CPU, Mem);

            elsif Cmd = "h" or Cmd = "help" or Cmd = "?" then
               Print_Help;

            else
               Put_Line ("Unknown command: " & Cmd);
               Put_Line ("Type 'h' for help");
            end if;
         end;

         --  Show next instruction if not halted
         if CPU.Halted then
            Put_Line ("CPU halted: " &
                      Exception_Code'Image (CPU.Exception_Code));
         end if;
      end loop;

      --  Close trace file if open
      if Dbg.Trace_File_Open then
         Close (Trace_File);
         Dbg.Trace_File_Open := False;
         Dbg.Trace_Enabled   := False;
      end if;
   end Run;

   --------------------
   -- Show_Backtrace --
   --------------------

   procedure Show_Backtrace (Dbg : Debugger_State;
                            CPU : RISCV.CPU.CPU_State;
                            Mem : in out RISCV.Memory.Memory_Unit;
                            Max_Frames : Natural := 20) is
      Frame_PC : Word;
      Frame_RA : Word;
      Frame_SP : Word;
      Info : Symbols.Symbol_Info;
      Frame_Num : Natural := 0;
   begin
      Put_Line ("Call Stack:");
      Put_Line ("#  PC         Function");
      Put_Line ("-- ---------- --------------------------------");

      --  Frame 0: Current PC
      Frame_PC := CPU.PC;
      Frame_RA := CPU.Registers (1);  -- ra register
      Frame_SP := CPU.Registers (2);  -- sp register

      loop
         exit when Frame_Num >= Max_Frames;

         --  Display frame
         Put (Natural'Image (Frame_Num));
         Put ("  ");
         Put (To_Hex (Frame_PC));
         Put ("  ");

         --  Look up symbol
         if Dbg.Symbols_Loaded and then
            Symbols.Lookup_By_Address (Dbg.Symbols.all, Memory_Address (Frame_PC), Info) and then
            Info.Sym_Type = Symbols.SYM_FUNCTION
         then
            Put (Info.Name (1 .. Info.Name_Len));
            declare
               Offset : constant Memory_Address := Memory_Address (Frame_PC) - Info.Address;
            begin
               if Offset > 0 then
                  Put ("+");
                  Put (To_Hex (Word (Offset)));
               end if;
            end;
         else
            Put ("???");
         end if;
         New_Line;

         --  Move to previous frame
         Frame_Num := Frame_Num + 1;

         --  Use return address as next PC
         if Frame_RA = 0 then
            exit;  -- No more frames
         end if;

         Frame_PC := Frame_RA;

         --  Try to find saved RA on stack
         --  Simple heuristic: scan stack for likely return addresses
         --  A more robust approach would need frame pointer tracking or DWARF info
         declare
            Found : Boolean := False;
            Saved_RA : Word;
         begin
            --  Scan a reasonable range of stack (16 words)
            for Offset in 0 .. 15 loop
               begin
                  Saved_RA := Memory.Read_Word (Mem, Memory_Address (Frame_SP + Word (Offset * 4)));

                  --  Check if this looks like a valid return address
                  --  (in code region, aligned, has a symbol)
                  if Saved_RA > 16#80000000# and Saved_RA < 16#90000000# and
                     (Saved_RA mod 2) = 0
                  then
                     if Dbg.Symbols_Loaded and then
                        Symbols.Lookup_By_Address (Dbg.Symbols.all, Memory_Address (Saved_RA), Info)
                     then
                        Frame_RA := Saved_RA;
                        Frame_SP := Frame_SP + Word (Offset * 4) + 4;
                        Found := True;
                        exit;
                     end if;
                  end if;
               exception
                  when others =>
                     null;  -- Invalid memory access, continue
               end;
            end loop;

            if not Found then
               Frame_RA := 0;  -- Stop unwinding
            end if;
         end;
      end loop;

      Put_Line ("");
   end Show_Backtrace;

   --------------------
   -- Show_Backtrace (RV64) --
   --------------------

   procedure Show_Backtrace (Dbg : Debugger_State;
                            CPU : RISCV.CPU64.CPU64_State;
                            Mem : in out RISCV.Memory.Memory_Unit;
                            Max_Frames : Natural := 20) is
      Frame_PC  : Double_Word;
      Frame_RA  : Double_Word;
      Frame_SP  : Double_Word;
      Info      : Symbols.Symbol_Info;
      Frame_Num : Natural := 0;
      PC32      : Memory_Address;
   begin
      Put_Line ("Call Stack:");
      Put_Line ("#  PC                   Function");
      Put_Line ("-- -------------------- --------------------------------");

      Frame_PC := Double_Word (CPU.PC);
      Frame_RA := RISCV.CPU64.Read_Register (CPU, 1);  -- ra
      Frame_SP := RISCV.CPU64.Read_Register (CPU, 2);  -- sp

      loop
         exit when Frame_Num >= Max_Frames;

         PC32 := Memory_Address (Frame_PC);

         Put (Natural'Image (Frame_Num));
         Put ("  ");
         Put (To_Hex_64 (Frame_PC));
         Put ("  ");

         if Dbg.Symbols_Loaded and then
            Symbols.Lookup_By_Address (Dbg.Symbols.all, PC32, Info) and then
            Info.Sym_Type = Symbols.SYM_FUNCTION
         then
            Put (Info.Name (1 .. Info.Name_Len));
            declare
               Offset : constant Memory_Address := PC32 - Info.Address;
            begin
               if Offset > 0 then
                  Put ("+" & To_Hex (Word (Offset)));
               end if;
            end;
         else
            Put ("???");
         end if;
         New_Line;

         Frame_Num := Frame_Num + 1;

         if Frame_RA = 0 then
            exit;
         end if;

         Frame_PC := Frame_RA;

         --  Scan stack for saved RA (16 double-words)
         declare
            Found    : Boolean := False;
            Saved_RA : Double_Word;
            Lo, Hi   : Word;
         begin
            for Offset in 0 .. 15 loop
               begin
                  Lo := Memory.Read_Word
                    (Mem, Memory_Address (Frame_SP + Double_Word (Offset * 8)));
                  Hi := Memory.Read_Word
                    (Mem, Memory_Address (Frame_SP + Double_Word (Offset * 8 + 4)));
                  Saved_RA := Double_Word (Lo) or Shift_Left (Double_Word (Hi), 32);

                  if Saved_RA > 16#80000000# and Saved_RA < 16#C0000000_00000000# and
                     (Saved_RA mod 2) = 0
                  then
                     if Dbg.Symbols_Loaded and then
                        Symbols.Lookup_By_Address
                          (Dbg.Symbols.all, Memory_Address (Saved_RA), Info)
                     then
                        Frame_RA := Saved_RA;
                        Frame_SP := Frame_SP + Double_Word (Offset * 8 + 8);
                        Found := True;
                        exit;
                     end if;
                  end if;
               exception
                  when others => null;
               end;
            end loop;

            if not Found then
               Frame_RA := 0;
            end if;
         end;
      end loop;

      Put_Line ("");
   end Show_Backtrace;

   -----------------
   -- Run (RV64)  --
   -----------------

   procedure Run (Dbg : in out Debugger_State;
                  CPU : in out RISCV.CPU64.CPU64_State;
                  Mem : in out Memory.Memory_Unit) is
      Line    : String (1 .. 256);
      Last    : Natural;
      Whitespace : constant Ada.Strings.Maps.Character_Set :=
         Ada.Strings.Maps.To_Set (" " & ASCII.HT);

      function Get_Token (S : String; N : Positive) return String;

      function Get_Token (S : String; N : Positive) return String is
         Start     : Natural := S'First;
         Finish    : Natural;
         Token_Num : Natural := 0;
      begin
         loop
            while Start <= S'Last and then
                  Ada.Strings.Maps.Is_In (S (Start), Whitespace)
            loop
               Start := Start + 1;
            end loop;

            exit when Start > S'Last;

            Finish := Start;
            while Finish <= S'Last and then
                  not Ada.Strings.Maps.Is_In (S (Finish), Whitespace)
            loop
               Finish := Finish + 1;
            end loop;

            Token_Num := Token_Num + 1;
            if Token_Num = N then
               return S (Start .. Finish - 1);
            end if;

            Start := Finish;
         end loop;

         return "";
      end Get_Token;

   begin
      Mem.Track_Access := True;

      Put_Line ("RISC-V Debugger (RV64). Type 'h' for help.");
      New_Line;

      Show_Current_Instruction_64 (Dbg, CPU, Mem);

      loop
         exit when Dbg.Quit_Requested;
         exit when CPU.Halted;

         Put ("(riscv64) ");
         Get_Line (Line, Last);

         declare
            Cmd  : constant String := Get_Token (Line (1 .. Last), 1);
            Arg1 : constant String := Get_Token (Line (1 .. Last), 2);
            Arg2 : constant String := Get_Token (Line (1 .. Last), 3);
         begin
            if Cmd = "" then
               if Dbg.Trace_Enabled and then Dbg.Trace_File_Open then
                  declare
                     Instr : constant Word :=
                        Memory.Read_Word (Mem, Memory_Address (CPU.PC));
                  begin
                     Put_Line (Trace_File,
                               To_Hex_64 (Double_Word (CPU.PC)) & ":  " & To_Hex (Instr) & "  " &
                               Disasm.Disassemble (Instr, Word (Memory_Address (CPU.PC))));
                  end;
               end if;
               Mem.Access_Occurred := False;
               RISCV.CPU64.Step (CPU, Mem, Trace => True);
               if Mem.Access_Occurred and then
                  Check_Watchpoint (Dbg, Double_Word (Mem.Last_Access_Addr),
                                   Mem.Last_Access_Write)
               then
                  Put_Line ("Watchpoint hit at 0x" &
                            To_Hex_64 (Double_Word (Mem.Last_Access_Addr)) &
                           (if Mem.Last_Access_Write then " (write)" else " (read)"));
               end if;

            elsif Cmd = "s" or Cmd = "step" then
               if Dbg.Trace_Enabled and then Dbg.Trace_File_Open then
                  declare
                     Instr : constant Word :=
                        Memory.Read_Word (Mem, Memory_Address (CPU.PC));
                  begin
                     Put_Line (Trace_File,
                               To_Hex_64 (Double_Word (CPU.PC)) & ":  " & To_Hex (Instr) & "  " &
                               Disasm.Disassemble (Instr, Word (Memory_Address (CPU.PC))));
                  end;
               end if;
               Mem.Access_Occurred := False;
               RISCV.CPU64.Step (CPU, Mem, Trace => True);
               if Mem.Access_Occurred and then
                  Check_Watchpoint (Dbg, Double_Word (Mem.Last_Access_Addr),
                                   Mem.Last_Access_Write)
               then
                  Put_Line ("Watchpoint hit at 0x" &
                            To_Hex_64 (Double_Word (Mem.Last_Access_Addr)) &
                           (if Mem.Last_Access_Write then " (write)" else " (read)"));
               end if;

            elsif Cmd = "c" or Cmd = "continue" then
               loop
                  if Dbg.Trace_Enabled and then Dbg.Trace_File_Open then
                     declare
                        Instr : constant Word :=
                           Memory.Read_Word (Mem, Memory_Address (CPU.PC));
                     begin
                        Put_Line (Trace_File,
                                  To_Hex_64 (Double_Word (CPU.PC)) & ":  " & To_Hex (Instr) & "  " &
                                  Disasm.Disassemble (Instr, Word (Memory_Address (CPU.PC))));
                     end;
                  end if;

                  Mem.Access_Occurred := False;
                  RISCV.CPU64.Step (CPU, Mem, Trace => False);
                  exit when CPU.Halted;

                  if Mem.Access_Occurred and then
                     Check_Watchpoint (Dbg, Double_Word (Mem.Last_Access_Addr),
                                      Mem.Last_Access_Write)
                  then
                     Put_Line ("Watchpoint hit at 0x" &
                               To_Hex_64 (Double_Word (Mem.Last_Access_Addr)) &
                              (if Mem.Last_Access_Write then " (write)" else " (read)"));
                     Show_Current_Instruction_64 (Dbg, CPU, Mem);
                     exit;
                  end if;

                  if At_Breakpoint (Dbg, Double_Word (CPU.PC)) then
                     Put_Line ("Breakpoint hit at 0x" & To_Hex_64 (Double_Word (CPU.PC)));
                     Show_Current_Instruction_64 (Dbg, CPU, Mem);
                     exit;
                  end if;
               end loop;

            elsif Cmd = "r" or Cmd = "regs" then
               Show_Registers_64 (CPU);

            elsif Cmd = "fregs" then
               Show_FP_Registers (CPU.FP);

            elsif Cmd = "m" then
               if Arg1 = "" then
                  Put_Line ("Usage: m <address> [count]");
               else
                  declare
                     Addr  : constant Word := Word (Parse_Hex_64 (Arg1));
                     Count : Natural := 64;
                  begin
                     if Arg2 /= "" then
                        Count := Parse_Natural (Arg2);
                        if Count = 0 then
                           Count := 64;
                        end if;
                     end if;
                     Dump_Memory (Mem, Addr, Count);
                  end;
               end if;

            elsif Cmd = "d" then
               declare
                  Addr  : Word := Word (CPU.PC);
                  Count : Natural := 10;
               begin
                  if Arg1 /= "" then
                     Addr := Word (Parse_Hex_64 (Arg1));
                  end if;
                  if Arg2 /= "" then
                     Count := Parse_Natural (Arg2);
                     if Count = 0 then
                        Count := 10;
                     end if;
                  end if;
                  Disassemble_Memory (Dbg, Mem, Addr, Count);
               end;

            elsif Cmd = "b" then
               if Arg1 = "" then
                  Put_Line ("Usage: b <address|function_name>");
               else
                  declare
                     Addr    : Double_Word;
                     Success : Boolean;
                     Info    : Symbols.Symbol_Info;
                  begin
                     if Arg1 (Arg1'First) = '0' or else
                        Arg1 (Arg1'First) in '1' .. '9' or else
                        Arg1 (Arg1'First) in 'a' .. 'f' or else
                        Arg1 (Arg1'First) in 'A' .. 'F'
                     then
                        Addr := Parse_Hex_64 (Arg1);
                        Add_Breakpoint (Dbg, Addr, Success);
                     elsif Dbg.Symbols_Loaded and then
                           Symbols.Lookup_By_Name (Dbg.Symbols.all, Arg1, Info)
                     then
                        Addr := Double_Word (Info.Address);
                        Add_Breakpoint (Dbg, Addr, Success);
                        if Success then
                           Put_Line ("Breakpoint set at " & Info.Name (1 .. Info.Name_Len) &
                                    " (" & To_Hex_64 (Addr) & ")");
                        end if;
                     else
                        Put_Line ("Symbol not found: " & Arg1);
                     end if;
                  end;
               end if;

            elsif Cmd = "bl" then
               List_Breakpoints (Dbg);

            elsif Cmd = "bc" then
               if Arg1 = "" then
                  Put_Line ("Usage: bc <number> or bc all");
               elsif Arg1 = "all" then
                  for I in 1 .. Max_Breakpoints loop
                     Dbg.Breakpoint_Enabled (I) := False;
                  end loop;
                  Dbg.Num_Breakpoints := 0;
                  Put_Line ("All breakpoints cleared");
               else
                  declare
                     Idx     : constant Natural := Parse_Natural (Arg1);
                     Success : Boolean;
                  begin
                     if Idx > 0 then
                        Remove_Breakpoint (Dbg, Idx, Success);
                     else
                        Put_Line ("Invalid breakpoint number");
                     end if;
                  end;
               end if;

            elsif Cmd = "watch" then
               if Arg1 = "" then
                  Put_Line ("Usage: watch <address> [r|w|rw]");
               else
                  declare
                     Addr    : constant Double_Word := Parse_Hex_64 (Arg1);
                     WType   : Watchpoint_Type := ReadWrite;
                     Success : Boolean;
                  begin
                     if Arg2 /= "" then
                        if Arg2 = "r" then
                           WType := Read;
                        elsif Arg2 = "w" then
                           WType := Write;
                        elsif Arg2 = "rw" then
                           WType := ReadWrite;
                        else
                           Put_Line ("Invalid watchpoint type. Use: r, w, or rw");
                           goto Skip_Watch_64;
                        end if;
                     end if;

                     Add_Watchpoint (Dbg, Addr, WType, Success);
                     <<Skip_Watch_64>>
                  end;
               end if;

            elsif Cmd = "wl" then
               List_Watchpoints (Dbg);

            elsif Cmd = "wc" then
               if Arg1 = "" then
                  Put_Line ("Usage: wc <number> or wc all");
               elsif Arg1 = "all" then
                  for I in 1 .. Max_Watchpoints loop
                     Dbg.Watchpoint_Enabled (I) := False;
                  end loop;
                  Dbg.Num_Watchpoints := 0;
                  Put_Line ("All watchpoints cleared");
               else
                  declare
                     Idx     : constant Natural := Parse_Natural (Arg1);
                     Success : Boolean;
                  begin
                     if Idx > 0 then
                        Remove_Watchpoint (Dbg, Idx, Success);
                     else
                        Put_Line ("Invalid watchpoint number");
                     end if;
                  end;
               end if;

            elsif Cmd = "x" then
               Show_Current_Instruction_64 (Dbg, CPU, Mem);

            elsif Cmd = "q" or Cmd = "quit" then
               Dbg.Quit_Requested := True;

            elsif Cmd = "sym" then
               if Arg1 = "" then
                  Put_Line ("Usage: sym <name>");
               elsif not Dbg.Symbols_Loaded then
                  Put_Line ("No symbols loaded");
               else
                  declare
                     Info     : Symbols.Symbol_Info;
                     Type_Str : String (1 .. 8);
                  begin
                     if Symbols.Lookup_By_Name (Dbg.Symbols.all, Arg1, Info) then
                        case Info.Sym_Type is
                           when Symbols.SYM_FUNCTION => Type_Str := "FUNC    ";
                           when Symbols.SYM_OBJECT   => Type_Str := "OBJECT  ";
                           when Symbols.SYM_SECTION  => Type_Str := "SECTION ";
                           when Symbols.SYM_FILE     => Type_Str := "FILE    ";
                           when others               => Type_Str := "UNKNOWN ";
                        end case;
                        Put (Type_Str & "  ");
                        Put ("0x" & To_Hex (Word (Info.Address)));
                        if Info.Size > 0 then
                           Put ("  size " & To_Hex (Info.Size));
                        end if;
                        Put_Line ("  " & Info.Name (1 .. Info.Name_Len));
                     else
                        Put_Line ("Symbol not found: " & Arg1);
                     end if;
                  end;
               end if;

            elsif Cmd = "trace" then
               if Arg1 = "" then
                  if Dbg.Trace_Enabled then
                     Put_Line ("Tracing active (file open)");
                  else
                     Put_Line ("Tracing off");
                  end if;
               elsif Arg1 = "off" then
                  if Dbg.Trace_File_Open then
                     Close (Trace_File);
                     Dbg.Trace_File_Open := False;
                  end if;
                  Dbg.Trace_Enabled := False;
                  Put_Line ("Tracing disabled");
               else
                  begin
                     if Dbg.Trace_File_Open then
                        Close (Trace_File);
                        Dbg.Trace_File_Open := False;
                     end if;
                     Create (Trace_File, Out_File, Arg1);
                     Dbg.Trace_File_Open := True;
                     Dbg.Trace_Enabled   := True;
                     Put_Line ("Tracing to " & Arg1);
                  exception
                     when Name_Error =>
                        Put_Line ("Cannot create file: " & Arg1);
                  end;
               end if;

            elsif Cmd = "bt" or Cmd = "backtrace" or Cmd = "where" then
               Show_Backtrace (Dbg, CPU, Mem);

            elsif Cmd = "h" or Cmd = "help" or Cmd = "?" then
               Print_Help;

            else
               Put_Line ("Unknown command: " & Cmd);
               Put_Line ("Type 'h' for help");
            end if;
         end;

         if CPU.Halted then
            Put_Line ("CPU halted: " &
                      Exception_Code'Image (CPU.Exception_Code));
         end if;
      end loop;

      if Dbg.Trace_File_Open then
         Close (Trace_File);
         Dbg.Trace_File_Open := False;
         Dbg.Trace_Enabled   := False;
      end if;
   end Run;

end RISCV.Debugger;
