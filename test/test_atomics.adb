-- ***************************************************************************
--                      RISCV_Emulator - Atomics Tests
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
--
-- A Extension (RV32A) unit tests
-- ***************************************************************************

with Ada.Text_IO; use Ada.Text_IO;
with RISCV;       use RISCV;
with RISCV.Memory;
with RISCV.CPU;
with RISCV.Disasm;

procedure Test_Atomics is

   Total_Tests  : Natural := 0;
   Passed_Tests : Natural := 0;
   Failed_Tests : Natural := 0;

   procedure Check (Condition : Boolean; Test_Name : String) is
   begin
      Total_Tests := Total_Tests + 1;
      if Condition then
         Passed_Tests := Passed_Tests + 1;
         Put_Line ("  PASS: " & Test_Name);
      else
         Failed_Tests := Failed_Tests + 1;
         Put_Line ("  FAIL: " & Test_Name);
      end if;
   end Check;

   --  Instruction encoding helpers for A extension
   --  Format: funct5[31:27] aq[26] rl[25] rs2[24:20] rs1[19:15] funct3[14:12]
   --          rd[11:7] opcode[6:0]
   function Encode_AMO (Funct5 : Word;
                        Aq, Rl : Boolean;
                        Rs2, Rs1, Rd : Register_Index) return Word is
      Result : Word := OPCODE_AMO;
   begin
      Result := Result or Shift_Left (Word (Rd), 7);
      Result := Result or Shift_Left (FUNCT3_AMO_W, 12);
      Result := Result or Shift_Left (Word (Rs1), 15);
      Result := Result or Shift_Left (Word (Rs2), 20);
      if Rl then
         Result := Result or Shift_Left (1, 25);
      end if;
      if Aq then
         Result := Result or Shift_Left (1, 26);
      end if;
      Result := Result or Shift_Left (Funct5, 27);
      return Result;
   end Encode_AMO;

   --  Test LR.W/SC.W instructions
   procedure Test_LR_SC is
      C : RISCV.CPU.CPU_State;
      M : RISCV.Memory.Memory_Unit;
      LR_Instr : Word;
      SC_Instr : Word;
   begin
      Put_Line ("Testing LR.W/SC.W instructions...");

      --  Initialize memory with region at address 0
      RISCV.Memory.Initialize (M);
      RISCV.Memory.Add_Region (M, "RAM", 0, 16#2000#,
                               RISCV.Memory.RAM, RISCV.Memory.Permission_RWX);

      --  Store a value at address 0x100
      RISCV.Memory.Write_Word (M, 16#100#, 16#DEADBEEF#);

      --  LR.W rd=10, rs1=11 (address register), rs2 ignored
      LR_Instr := Encode_AMO (FUNCT5_LR, False, False, 0, 11, 10);
      --  SC.W rd=12, rs1=11, rs2=13
      SC_Instr := Encode_AMO (FUNCT5_SC, False, False, 13, 11, 12);

      --  Test 1: LR.W loads value and sets reservation
      RISCV.CPU.Initialize (C, 0);
      C.Registers (11) := 16#100#;  --  Address
      RISCV.Memory.Write_Word (M, 0, LR_Instr);  --  Store instruction
      RISCV.Memory.Write_Word (M, 4, OPCODE_SYSTEM);  --  ECALL to halt
      RISCV.CPU.Step (C, M);

      Check (C.Registers (10) = 16#DEADBEEF#, "LR.W loads value correctly");
      Check (C.Reservation_Valid, "LR.W sets reservation valid");
      Check (C.Reserved_Addr = 16#100#, "LR.W sets reserved address");

      --  Test 2: SC.W succeeds when reservation is valid
      C.Registers (13) := 16#CAFEBABE#;  --  Value to store
      RISCV.Memory.Write_Word (M, 4, SC_Instr);
      RISCV.Memory.Write_Word (M, 8, OPCODE_SYSTEM);
      RISCV.CPU.Step (C, M);

      Check (C.Registers (12) = 0, "SC.W returns 0 on success");
      Check (RISCV.Memory.Read_Word (M, 16#100#) = 16#CAFEBABE#,
             "SC.W stores value on success");
      Check (not C.Reservation_Valid, "SC.W clears reservation");

      --  Test 3: SC.W fails when reservation is invalid
      RISCV.CPU.Initialize (C, 0);
      C.Registers (11) := 16#100#;
      C.Registers (13) := 16#12345678#;
      --  Don't do LR.W first
      RISCV.Memory.Write_Word (M, 0, SC_Instr);
      RISCV.Memory.Write_Word (M, 4, OPCODE_SYSTEM);
      RISCV.CPU.Step (C, M);

      Check (C.Registers (12) = 1, "SC.W returns 1 on failure");
      Check (RISCV.Memory.Read_Word (M, 16#100#) = 16#CAFEBABE#,
             "SC.W does not store on failure");

      --  Test 4: SC.W fails when address doesn't match
      RISCV.CPU.Initialize (C, 0);
      C.Reservation_Valid := True;
      C.Reserved_Addr := 16#200#;  --  Different address
      C.Registers (11) := 16#100#;
      C.Registers (13) := 16#AAAABBBB#;
      RISCV.Memory.Write_Word (M, 0, SC_Instr);
      RISCV.CPU.Step (C, M);

      Check (C.Registers (12) = 1, "SC.W returns 1 on address mismatch");
   end Test_LR_SC;

   --  Test AMO arithmetic operations
   procedure Test_AMO_Arithmetic is
      C : RISCV.CPU.CPU_State;
      M : RISCV.Memory.Memory_Unit;
      Instr : Word;
   begin
      Put_Line ("Testing AMO arithmetic instructions...");

      RISCV.Memory.Initialize (M);
      RISCV.Memory.Add_Region (M, "RAM", 0, 16#2000#,
                               RISCV.Memory.RAM, RISCV.Memory.Permission_RWX);

      --  AMOSWAP.W: rd=10, rs1=11 (addr), rs2=12 (value)
      RISCV.Memory.Write_Word (M, 16#100#, 16#11111111#);
      RISCV.CPU.Initialize (C, 0);
      C.Registers (11) := 16#100#;
      C.Registers (12) := 16#22222222#;
      Instr := Encode_AMO (FUNCT5_AMOSWAP, False, False, 12, 11, 10);
      RISCV.Memory.Write_Word (M, 0, Instr);
      RISCV.Memory.Write_Word (M, 4, OPCODE_SYSTEM);
      RISCV.CPU.Step (C, M);

      Check (C.Registers (10) = 16#11111111#,
             "AMOSWAP.W returns old value");
      Check (RISCV.Memory.Read_Word (M, 16#100#) = 16#22222222#,
             "AMOSWAP.W stores new value");

      --  AMOADD.W
      RISCV.Memory.Write_Word (M, 16#100#, 100);
      RISCV.CPU.Initialize (C, 0);
      C.Registers (11) := 16#100#;
      C.Registers (12) := 50;
      Instr := Encode_AMO (FUNCT5_AMOADD, False, False, 12, 11, 10);
      RISCV.Memory.Write_Word (M, 0, Instr);
      RISCV.CPU.Step (C, M);

      Check (C.Registers (10) = 100, "AMOADD.W returns old value");
      Check (RISCV.Memory.Read_Word (M, 16#100#) = 150,
             "AMOADD.W adds correctly");

      --  AMOXOR.W
      RISCV.Memory.Write_Word (M, 16#100#, 16#FF00FF00#);
      RISCV.CPU.Initialize (C, 0);
      C.Registers (11) := 16#100#;
      C.Registers (12) := 16#0F0F0F0F#;
      Instr := Encode_AMO (FUNCT5_AMOXOR, False, False, 12, 11, 10);
      RISCV.Memory.Write_Word (M, 0, Instr);
      RISCV.CPU.Step (C, M);

      Check (C.Registers (10) = 16#FF00FF00#, "AMOXOR.W returns old value");
      Check (RISCV.Memory.Read_Word (M, 16#100#) = 16#F00FF00F#,
             "AMOXOR.W XORs correctly");

      --  AMOAND.W
      RISCV.Memory.Write_Word (M, 16#100#, 16#FFFFFFFF#);
      RISCV.CPU.Initialize (C, 0);
      C.Registers (11) := 16#100#;
      C.Registers (12) := 16#0F0F0F0F#;
      Instr := Encode_AMO (FUNCT5_AMOAND, False, False, 12, 11, 10);
      RISCV.Memory.Write_Word (M, 0, Instr);
      RISCV.CPU.Step (C, M);

      Check (C.Registers (10) = 16#FFFFFFFF#, "AMOAND.W returns old value");
      Check (RISCV.Memory.Read_Word (M, 16#100#) = 16#0F0F0F0F#,
             "AMOAND.W ANDs correctly");

      --  AMOOR.W
      RISCV.Memory.Write_Word (M, 16#100#, 16#F0F0F0F0#);
      RISCV.CPU.Initialize (C, 0);
      C.Registers (11) := 16#100#;
      C.Registers (12) := 16#0F0F0F0F#;
      Instr := Encode_AMO (FUNCT5_AMOOR, False, False, 12, 11, 10);
      RISCV.Memory.Write_Word (M, 0, Instr);
      RISCV.CPU.Step (C, M);

      Check (C.Registers (10) = 16#F0F0F0F0#, "AMOOR.W returns old value");
      Check (RISCV.Memory.Read_Word (M, 16#100#) = 16#FFFFFFFF#,
             "AMOOR.W ORs correctly");
   end Test_AMO_Arithmetic;

   --  Test AMO min/max operations
   procedure Test_AMO_MinMax is
      C : RISCV.CPU.CPU_State;
      M : RISCV.Memory.Memory_Unit;
      Instr : Word;
   begin
      Put_Line ("Testing AMO min/max instructions...");

      RISCV.Memory.Initialize (M);
      RISCV.Memory.Add_Region (M, "RAM", 0, 16#2000#,
                               RISCV.Memory.RAM, RISCV.Memory.Permission_RWX);

      --  AMOMIN.W (signed) - mem=10, rs2=-5, result should be -5
      RISCV.Memory.Write_Word (M, 16#100#, Word'(10));
      RISCV.CPU.Initialize (C, 0);
      C.Registers (11) := 16#100#;
      C.Registers (12) := Word'Last - 4;  --  -5 in two's complement
      Instr := Encode_AMO (FUNCT5_AMOMIN, False, False, 12, 11, 10);
      RISCV.Memory.Write_Word (M, 0, Instr);
      RISCV.CPU.Step (C, M);

      Check (C.Registers (10) = 10, "AMOMIN.W returns old value");
      Check (RISCV.Memory.Read_Word (M, 16#100#) = Word'Last - 4,
             "AMOMIN.W stores signed min");

      --  AMOMAX.W (signed) - mem=-5, rs2=10, result should be 10
      RISCV.Memory.Write_Word (M, 16#100#, Word'Last - 4);  --  -5
      RISCV.CPU.Initialize (C, 0);
      C.Registers (11) := 16#100#;
      C.Registers (12) := 10;
      Instr := Encode_AMO (FUNCT5_AMOMAX, False, False, 12, 11, 10);
      RISCV.Memory.Write_Word (M, 0, Instr);
      RISCV.CPU.Step (C, M);

      Check (C.Registers (10) = Word'Last - 4, "AMOMAX.W returns old value");
      Check (RISCV.Memory.Read_Word (M, 16#100#) = 10,
             "AMOMAX.W stores signed max");

      --  AMOMINU.W (unsigned) - mem=0xFFFFFFFF, rs2=0x00000001
      RISCV.Memory.Write_Word (M, 16#100#, 16#FFFFFFFF#);
      RISCV.CPU.Initialize (C, 0);
      C.Registers (11) := 16#100#;
      C.Registers (12) := 1;
      Instr := Encode_AMO (FUNCT5_AMOMINU, False, False, 12, 11, 10);
      RISCV.Memory.Write_Word (M, 0, Instr);
      RISCV.CPU.Step (C, M);

      Check (C.Registers (10) = 16#FFFFFFFF#,
             "AMOMINU.W returns old value");
      Check (RISCV.Memory.Read_Word (M, 16#100#) = 1,
             "AMOMINU.W stores unsigned min");

      --  AMOMAXU.W (unsigned) - mem=1, rs2=0xFFFFFFFF
      RISCV.Memory.Write_Word (M, 16#100#, 1);
      RISCV.CPU.Initialize (C, 0);
      C.Registers (11) := 16#100#;
      C.Registers (12) := 16#FFFFFFFF#;
      Instr := Encode_AMO (FUNCT5_AMOMAXU, False, False, 12, 11, 10);
      RISCV.Memory.Write_Word (M, 0, Instr);
      RISCV.CPU.Step (C, M);

      Check (C.Registers (10) = 1, "AMOMAXU.W returns old value");
      Check (RISCV.Memory.Read_Word (M, 16#100#) = 16#FFFFFFFF#,
             "AMOMAXU.W stores unsigned max");
   end Test_AMO_MinMax;

   --  Test disassembly of A extension instructions
   procedure Test_Disassembly is
      Instr : Word;

      procedure Check_Disasm (Inst : Word; Expected_Prefix : String) is
         Result : constant String := RISCV.Disasm.Disassemble (Inst, 0);
      begin
         --  Check if disassembly starts with expected prefix
         if Result'Length >= Expected_Prefix'Length and then
            Result (Result'First ..
                    Result'First + Expected_Prefix'Length - 1) =
               Expected_Prefix
         then
            Check (True, "Disasm: " & Expected_Prefix);
         else
            Put_Line ("    Expected: " & Expected_Prefix);
            Put_Line ("    Got:      " & Result);
            Check (False, "Disasm: " & Expected_Prefix);
         end if;
      end Check_Disasm;
   begin
      Put_Line ("Testing A extension disassembly...");

      --  LR.W with no ordering
      Instr := Encode_AMO (FUNCT5_LR, False, False, 0, 10, 11);
      Check_Disasm (Instr, "lr.w ");

      --  LR.W with acquire
      Instr := Encode_AMO (FUNCT5_LR, True, False, 0, 10, 11);
      Check_Disasm (Instr, "lr.w.aq");

      --  LR.W with release
      Instr := Encode_AMO (FUNCT5_LR, False, True, 0, 10, 11);
      Check_Disasm (Instr, "lr.w.rl");

      --  LR.W with both
      Instr := Encode_AMO (FUNCT5_LR, True, True, 0, 10, 11);
      Check_Disasm (Instr, "lr.w.aqrl");

      --  SC.W
      Instr := Encode_AMO (FUNCT5_SC, False, False, 12, 10, 11);
      Check_Disasm (Instr, "sc.w ");

      --  AMOSWAP.W
      Instr := Encode_AMO (FUNCT5_AMOSWAP, False, False, 12, 10, 11);
      Check_Disasm (Instr, "amoswap.w");

      --  AMOADD.W
      Instr := Encode_AMO (FUNCT5_AMOADD, False, False, 12, 10, 11);
      Check_Disasm (Instr, "amoadd.w");

      --  AMOXOR.W
      Instr := Encode_AMO (FUNCT5_AMOXOR, False, False, 12, 10, 11);
      Check_Disasm (Instr, "amoxor.w");

      --  AMOAND.W
      Instr := Encode_AMO (FUNCT5_AMOAND, False, False, 12, 10, 11);
      Check_Disasm (Instr, "amoand.w");

      --  AMOOR.W
      Instr := Encode_AMO (FUNCT5_AMOOR, False, False, 12, 10, 11);
      Check_Disasm (Instr, "amoor.w");

      --  AMOMIN.W
      Instr := Encode_AMO (FUNCT5_AMOMIN, False, False, 12, 10, 11);
      Check_Disasm (Instr, "amomin.w");

      --  AMOMAX.W
      Instr := Encode_AMO (FUNCT5_AMOMAX, False, False, 12, 10, 11);
      Check_Disasm (Instr, "amomax.w");

      --  AMOMINU.W
      Instr := Encode_AMO (FUNCT5_AMOMINU, False, False, 12, 10, 11);
      Check_Disasm (Instr, "amominu.w");

      --  AMOMAXU.W
      Instr := Encode_AMO (FUNCT5_AMOMAXU, False, False, 12, 10, 11);
      Check_Disasm (Instr, "amomaxu.w");
   end Test_Disassembly;

begin
   Put_Line ("=================================================");
   Put_Line ("       RISCV Emulator A Extension Tests");
   Put_Line ("=================================================");
   New_Line;

   Test_LR_SC;
   New_Line;

   Test_AMO_Arithmetic;
   New_Line;

   Test_AMO_MinMax;
   New_Line;

   Test_Disassembly;
   New_Line;

   Put_Line ("=================================================");
   Put ("Test Results: ");
   Put (Natural'Image (Passed_Tests) & " passed, ");
   Put (Natural'Image (Failed_Tests) & " failed out of ");
   Put_Line (Natural'Image (Total_Tests) & " tests");
   Put_Line ("=================================================");

   if Failed_Tests = 0 then
      Put_Line ("ALL TESTS PASSED!");
   else
      Put_Line ("SOME TESTS FAILED!");
   end if;
end Test_Atomics;
