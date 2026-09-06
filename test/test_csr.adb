-- ***************************************************************************
--                      RISCV_Emulator - CSR Extension Tests
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
-- Zicsr Extension unit tests
-- ***************************************************************************

with Ada.Text_IO; use Ada.Text_IO;
with RISCV;       use RISCV;
with RISCV.Memory;
with RISCV.CPU;
with RISCV.CSR;
with RISCV.Disasm;

procedure Test_CSR is

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

   --  Encode CSR instruction
   --  Format: csr[31:20] rs1[19:15] funct3[14:12] rd[11:7] opcode[6:0]
   function Encode_CSR (Csr_Addr : CSR.CSR_Address;
                        Rs1_Or_Zimm : Register_Index;
                        Funct3 : Word;
                        Rd : Register_Index) return Word is
   begin
      return OPCODE_SYSTEM or
             Shift_Left (Word (Rd), 7) or
             Shift_Left (Funct3, 12) or
             Shift_Left (Word (Rs1_Or_Zimm), 15) or
             Shift_Left (Word (Csr_Addr), 20);
   end Encode_CSR;

   --  ECALL instruction
   Ecall : constant Word := OPCODE_SYSTEM;

   --  ======================================================================
   --  Test CSR state initialization
   --  ======================================================================
   procedure Test_CSR_Init is
      S : CSR.CSR_State;
   begin
      Put_Line ("Testing CSR initialization...");

      CSR.Initialize (S);

      --  MISA should have extension bits set
      declare
         Misa : constant Word := CSR.Read (S, CSR.CSR_MISA);
      begin
         Check ((Misa and Shift_Left (1, 8)) /= 0, "MISA has I bit");
         Check ((Misa and Shift_Left (1, 12)) /= 0, "MISA has M bit");
         Check ((Misa and Shift_Left (1, 0)) /= 0, "MISA has A bit");
         Check ((Misa and Shift_Left (1, 2)) /= 0, "MISA has C bit");
         Check ((Misa and Shift_Left (1, 5)) /= 0, "MISA has F bit");
         Check ((Misa and Shift_Left (1, 3)) /= 0, "MISA has D bit");
         Check ((Misa and Shift_Left (1, 30)) /= 0, "MISA MXL=1 (32-bit)");
      end;

      Check (CSR.Read (S, CSR.CSR_MSTATUS) = 0, "MSTATUS initially 0");
      Check (CSR.Read (S, CSR.CSR_MHARTID) = 0, "MHARTID is 0");
   end Test_CSR_Init;

   --  ======================================================================
   --  Test CSR read/write
   --  ======================================================================
   procedure Test_CSR_Read_Write is
      S : CSR.CSR_State;
   begin
      Put_Line ("Testing CSR read/write...");

      CSR.Initialize (S);

      --  Write and read back
      CSR.Write (S, CSR.CSR_MSCRATCH, 16#DEADBEEF#);
      Check (CSR.Read (S, CSR.CSR_MSCRATCH) = 16#DEADBEEF#,
             "MSCRATCH write/read");

      CSR.Write (S, CSR.CSR_MTVEC, 16#1000#);
      Check (CSR.Read (S, CSR.CSR_MTVEC) = 16#1000#, "MTVEC write/read");

      --  Counters
      CSR.Increment_Mcycle (S);
      CSR.Increment_Mcycle (S);
      CSR.Increment_Mcycle (S);
      Check (CSR.Read (S, CSR.CSR_MCYCLE) = 3, "MCYCLE increments");

      CSR.Increment_Instret (S);
      Check (CSR.Read (S, CSR.CSR_MINSTRET) = 1, "MINSTRET increments");

      --  Read-only detection
      Check (CSR.Is_Read_Only (CSR.CSR_MVENDORID), "MVENDORID is read-only");
      Check (CSR.Is_Read_Only (CSR.CSR_CYCLE), "CYCLE is read-only");
      Check (not CSR.Is_Read_Only (CSR.CSR_MSTATUS),
             "MSTATUS is not read-only");
   end Test_CSR_Read_Write;

   --  ======================================================================
   --  Test CSRRW instruction
   --  ======================================================================
   procedure Test_CSRRW is
      C : RISCV.CPU.CPU_State;
      M : RISCV.Memory.Memory_Unit;
      Instr : Word;
   begin
      Put_Line ("Testing CSRRW...");

      RISCV.Memory.Initialize (M);
      RISCV.Memory.Add_Region (M, "RAM", 0, 16#2000#,
                               RISCV.Memory.RAM, RISCV.Memory.Permission_RWX);

      --  CSRRW x10, mscratch, x11 (rd=10, rs1=11)
      Instr := Encode_CSR (CSR.CSR_MSCRATCH, 11, FUNCT3_CSRRW, 10);

      RISCV.CPU.Initialize (C, 0);
      CSR.Write (C.CSRs, CSR.CSR_MSCRATCH, 16#AABBCCDD#);
      C.Registers (11) := 16#12345678#;
      RISCV.Memory.Write_Word (M, 0, Instr);
      RISCV.Memory.Write_Word (M, 4, Ecall);
      RISCV.CPU.Step (C, M);

      Check (C.Registers (10) = 16#AABBCCDD#, "CSRRW reads old CSR value");
      Check (CSR.Read (C.CSRs, CSR.CSR_MSCRATCH) = 16#12345678#,
             "CSRRW writes new CSR value");
   end Test_CSRRW;

   --  ======================================================================
   --  Test CSRRS instruction
   --  ======================================================================
   procedure Test_CSRRS is
      C : RISCV.CPU.CPU_State;
      M : RISCV.Memory.Memory_Unit;
      Instr : Word;
   begin
      Put_Line ("Testing CSRRS...");

      RISCV.Memory.Initialize (M);
      RISCV.Memory.Add_Region (M, "RAM", 0, 16#2000#,
                               RISCV.Memory.RAM, RISCV.Memory.Permission_RWX);

      --  CSRRS x10, mscratch, x11
      Instr := Encode_CSR (CSR.CSR_MSCRATCH, 11, FUNCT3_CSRRS, 10);

      RISCV.CPU.Initialize (C, 0);
      CSR.Write (C.CSRs, CSR.CSR_MSCRATCH, 16#F0F0F0F0#);
      C.Registers (11) := 16#0F0F0F0F#;
      RISCV.Memory.Write_Word (M, 0, Instr);
      RISCV.Memory.Write_Word (M, 4, Ecall);
      RISCV.CPU.Step (C, M);

      Check (C.Registers (10) = 16#F0F0F0F0#, "CSRRS reads old CSR value");
      Check (CSR.Read (C.CSRs, CSR.CSR_MSCRATCH) = 16#FFFFFFFF#,
             "CSRRS sets bits in CSR");

      --  CSRRS with rs1=x0 should not write (read-only)
      Instr := Encode_CSR (CSR.CSR_MSCRATCH, 0, FUNCT3_CSRRS, 10);
      RISCV.CPU.Initialize (C, 0);
      CSR.Write (C.CSRs, CSR.CSR_MSCRATCH, 16#42#);
      RISCV.Memory.Write_Word (M, 0, Instr);
      RISCV.CPU.Step (C, M);

      Check (C.Registers (10) = 16#42#, "CSRR (CSRRS x0) reads CSR");
      Check (CSR.Read (C.CSRs, CSR.CSR_MSCRATCH) = 16#42#,
             "CSRR does not modify CSR");
   end Test_CSRRS;

   --  ======================================================================
   --  Test CSRRC instruction
   --  ======================================================================
   procedure Test_CSRRC is
      C : RISCV.CPU.CPU_State;
      M : RISCV.Memory.Memory_Unit;
      Instr : Word;
   begin
      Put_Line ("Testing CSRRC...");

      RISCV.Memory.Initialize (M);
      RISCV.Memory.Add_Region (M, "RAM", 0, 16#2000#,
                               RISCV.Memory.RAM, RISCV.Memory.Permission_RWX);

      --  CSRRC x10, mscratch, x11
      Instr := Encode_CSR (CSR.CSR_MSCRATCH, 11, FUNCT3_CSRRC, 10);

      RISCV.CPU.Initialize (C, 0);
      CSR.Write (C.CSRs, CSR.CSR_MSCRATCH, 16#FFFFFFFF#);
      C.Registers (11) := 16#0F0F0F0F#;
      RISCV.Memory.Write_Word (M, 0, Instr);
      RISCV.Memory.Write_Word (M, 4, Ecall);
      RISCV.CPU.Step (C, M);

      Check (C.Registers (10) = 16#FFFFFFFF#, "CSRRC reads old CSR value");
      Check (CSR.Read (C.CSRs, CSR.CSR_MSCRATCH) = 16#F0F0F0F0#,
             "CSRRC clears bits in CSR");
   end Test_CSRRC;

   --  ======================================================================
   --  Test CSRRWI/CSRRSI/CSRRCI (immediate forms)
   --  ======================================================================
   procedure Test_CSR_Immediate is
      C : RISCV.CPU.CPU_State;
      M : RISCV.Memory.Memory_Unit;
      Instr : Word;
   begin
      Put_Line ("Testing CSR immediate instructions...");

      RISCV.Memory.Initialize (M);
      RISCV.Memory.Add_Region (M, "RAM", 0, 16#2000#,
                               RISCV.Memory.RAM, RISCV.Memory.Permission_RWX);

      --  CSRRWI x10, mscratch, 15 (zimm=15)
      Instr := Encode_CSR (CSR.CSR_MSCRATCH, 15, FUNCT3_CSRRWI, 10);
      RISCV.CPU.Initialize (C, 0);
      CSR.Write (C.CSRs, CSR.CSR_MSCRATCH, 16#AA#);
      RISCV.Memory.Write_Word (M, 0, Instr);
      RISCV.Memory.Write_Word (M, 4, Ecall);
      RISCV.CPU.Step (C, M);

      Check (C.Registers (10) = 16#AA#, "CSRRWI reads old value");
      Check (CSR.Read (C.CSRs, CSR.CSR_MSCRATCH) = 15,
             "CSRRWI writes zimm");

      --  CSRRSI x10, mscratch, 3
      Instr := Encode_CSR (CSR.CSR_MSCRATCH, 3, FUNCT3_CSRRSI, 10);
      RISCV.CPU.Initialize (C, 0);
      CSR.Write (C.CSRs, CSR.CSR_MSCRATCH, 16#F0#);
      RISCV.Memory.Write_Word (M, 0, Instr);
      RISCV.CPU.Step (C, M);

      Check (C.Registers (10) = 16#F0#, "CSRRSI reads old value");
      Check (CSR.Read (C.CSRs, CSR.CSR_MSCRATCH) = 16#F3#,
             "CSRRSI sets bits with zimm");

      --  CSRRCI x10, mscratch, 3
      Instr := Encode_CSR (CSR.CSR_MSCRATCH, 3, FUNCT3_CSRRCI, 10);
      RISCV.CPU.Initialize (C, 0);
      CSR.Write (C.CSRs, CSR.CSR_MSCRATCH, 16#FF#);
      RISCV.Memory.Write_Word (M, 0, Instr);
      RISCV.CPU.Step (C, M);

      Check (C.Registers (10) = 16#FF#, "CSRRCI reads old value");
      Check (CSR.Read (C.CSRs, CSR.CSR_MSCRATCH) = 16#FC#,
             "CSRRCI clears bits with zimm");
   end Test_CSR_Immediate;

   --  ======================================================================
   --  Test performance counters
   --  ======================================================================
   procedure Test_Counters is
      C : RISCV.CPU.CPU_State;
      M : RISCV.Memory.Memory_Unit;
      Instr : Word;
   begin
      Put_Line ("Testing performance counters...");

      RISCV.Memory.Initialize (M);
      RISCV.Memory.Add_Region (M, "RAM", 0, 16#2000#,
                               RISCV.Memory.RAM, RISCV.Memory.Permission_RWX);

      --  Run 3 instructions: NOP, NOP, ECALL
      --  NOP = addi x0, x0, 0 = 0x00000013
      RISCV.CPU.Initialize (C, 0);
      RISCV.Memory.Write_Word (M, 0, 16#00000013#);   --  NOP
      RISCV.Memory.Write_Word (M, 4, 16#00000013#);   --  NOP
      RISCV.Memory.Write_Word (M, 8, 16#00000013#);   --  NOP
      --  Read mcycle into x10
      Instr := Encode_CSR (CSR.CSR_MCYCLE, 0, FUNCT3_CSRRS, 10);
      RISCV.Memory.Write_Word (M, 12, Instr);
      --  Read minstret into x11
      Instr := Encode_CSR (CSR.CSR_MINSTRET, 0, FUNCT3_CSRRS, 11);
      RISCV.Memory.Write_Word (M, 16, Instr);
      RISCV.Memory.Write_Word (M, 20, Ecall);

      RISCV.CPU.Run (C, M);

      --  3 NOPs + 2 CSR reads = 5 instructions executed before reading
      --  mcycle read at instr #4 sees count of 3 (counter incremented after)
      --  minstret read at instr #5 sees count of 4
      Check (C.Registers (10) = 3, "MCYCLE counted 3 before read");
      Check (C.Registers (11) = 4, "MINSTRET counted 4 before read");
   end Test_Counters;

   --  ======================================================================
   --  Test CSR disassembly
   --  ======================================================================
   procedure Test_CSR_Disasm is
      Instr : Word;

      procedure Check_Disasm (Inst : Word; Expected_Prefix : String) is
         Result : constant String := RISCV.Disasm.Disassemble (Inst, 0);
      begin
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
      Put_Line ("Testing CSR disassembly...");

      --  CSRRW x10, mscratch, x11
      Instr := Encode_CSR (CSR.CSR_MSCRATCH, 11, FUNCT3_CSRRW, 10);
      Check_Disasm (Instr, "csrrw   a0, mscratch, a1");

      --  CSRW mscratch, x11 (rd=x0)
      Instr := Encode_CSR (CSR.CSR_MSCRATCH, 11, FUNCT3_CSRRW, 0);
      Check_Disasm (Instr, "csrw    mscratch, a1");

      --  CSRR x10, mstatus (rs1=x0, read-only)
      Instr := Encode_CSR (CSR.CSR_MSTATUS, 0, FUNCT3_CSRRS, 10);
      Check_Disasm (Instr, "csrr    a0, mstatus");

      --  CSRRWI x10, mscratch, 5
      Instr := Encode_CSR (CSR.CSR_MSCRATCH, 5, FUNCT3_CSRRWI, 10);
      Check_Disasm (Instr, "csrrwi  a0, mscratch, 5");
   end Test_CSR_Disasm;

   --  ======================================================================
   --  Test CSR name lookup
   --  ======================================================================
   procedure Test_CSR_Names is
   begin
      Put_Line ("Testing CSR name lookup...");

      Check (CSR.CSR_Name (CSR.CSR_MSTATUS) = "mstatus", "mstatus name");
      Check (CSR.CSR_Name (CSR.CSR_MEPC) = "mepc", "mepc name");
      Check (CSR.CSR_Name (CSR.CSR_MCAUSE) = "mcause", "mcause name");
      Check (CSR.CSR_Name (CSR.CSR_MCYCLE) = "mcycle", "mcycle name");
      Check (CSR.CSR_Name (CSR.CSR_CYCLE) = "cycle", "cycle name");
   end Test_CSR_Names;

begin
   Put_Line ("=================================================");
   Put_Line ("       RISCV Emulator Zicsr Extension Tests");
   Put_Line ("=================================================");
   New_Line;

   Test_CSR_Init;
   New_Line;

   Test_CSR_Read_Write;
   New_Line;

   Test_CSRRW;
   New_Line;

   Test_CSRRS;
   New_Line;

   Test_CSRRC;
   New_Line;

   Test_CSR_Immediate;
   New_Line;

   Test_Counters;
   New_Line;

   Test_CSR_Disasm;
   New_Line;

   Test_CSR_Names;
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
end Test_CSR;
