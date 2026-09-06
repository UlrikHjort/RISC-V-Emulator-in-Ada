-- ***************************************************************************
--                      RISCV_Emulator - Compressed Extension Tests
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
-- C Extension (RV32C) unit tests
-- ***************************************************************************

with Ada.Text_IO; use Ada.Text_IO;
with RISCV;       use RISCV;
with RISCV.Memory;
with RISCV.CPU;
with RISCV.Compressed;

procedure Test_Compressed is

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

   --  Helper to store a 16-bit instruction at a memory address
   --  Stores as two bytes in little-endian
   procedure Store_Compressed (M    : in out RISCV.Memory.Memory_Unit;
                               Addr : Memory_Address;
                               Inst : Half_Word) is
   begin
      RISCV.Memory.Write_Byte (M, Addr, Byte (Inst and 16#FF#));
      RISCV.Memory.Write_Byte (M, Addr + 1, Byte (Shift_Right (Word (Inst),
                                                                8) and 16#FF#));
   end Store_Compressed;

   --  Store a 32-bit instruction at address (for halting)
   procedure Store_32 (M    : in out RISCV.Memory.Memory_Unit;
                       Addr : Memory_Address;
                       Inst : Word) is
   begin
      RISCV.Memory.Write_Word (M, Addr, Inst);
   end Store_32;

   --  ECALL instruction to halt the CPU
   Ecall : constant Word := OPCODE_SYSTEM;

   --  ======================================================================
   --  Test Compressed Detection
   --  ======================================================================
   procedure Test_Detection is
   begin
      Put_Line ("Testing compressed instruction detection...");

      --  Compressed: bits [1:0] = 00
      Check (Compressed.Is_Compressed (16#0000#), "Quadrant 0 is compressed");
      --  Compressed: bits [1:0] = 01
      Check (Compressed.Is_Compressed (16#0001#), "Quadrant 1 is compressed");
      --  Compressed: bits [1:0] = 10
      Check (Compressed.Is_Compressed (16#0002#), "Quadrant 2 is compressed");
      --  Not compressed: bits [1:0] = 11
      Check (not Compressed.Is_Compressed (16#0003#),
             "32-bit instruction not compressed");
      Check (not Compressed.Is_Compressed (16#00000013#),
             "NOP is not compressed");
   end Test_Detection;

   --  ======================================================================
   --  Test C.ADDI4SPN (addi rd', x2, nzuimm)
   --  ======================================================================
   procedure Test_C_ADDI4SPN is
      C : RISCV.CPU.CPU_State;
      M : RISCV.Memory.Memory_Unit;
      --  C.ADDI4SPN rd'=x8, nzuimm=8
      --  Format: 000 nzuimm[5:4|9:6|2|3] rd' 00
      --  nzuimm=8 -> nzuimm[3]=1 -> bit5=1
      --  rd'=000 (x8)
      --  Encoding: 000 0000010 000 00 = 0x0020
      --  Let me compute carefully:
      --  bits: [15:13]=000 [12:5]=nzuimm_enc [4:2]=rd' [1:0]=00
      --  nzuimm=8 means bit3=1
      --  nzuimm[5:4] -> bits[12:11], nzuimm[9:6] -> bits[10:7]
      --  nzuimm[2] -> bit[6], nzuimm[3] -> bit[5]
      --  For nzuimm=8 (bit3=1): bit[5]=1
      --  0_00000001_000_00 = 16#0020#
      Instr : constant Half_Word := 16#0020#;
   begin
      Put_Line ("Testing C.ADDI4SPN...");

      RISCV.Memory.Initialize (M);
      RISCV.Memory.Add_Region (M, "RAM", 0, 16#2000#,
                               RISCV.Memory.RAM, RISCV.Memory.Permission_RWX);

      RISCV.CPU.Initialize (C, 0);
      C.Registers (2) := 16#1000#;  --  SP = 0x1000

      Store_Compressed (M, 0, Instr);
      Store_32 (M, 2, Ecall);  --  ECALL at byte 2

      RISCV.CPU.Step (C, M);

      --  x8 should be SP + 8 = 0x1008
      Check (C.Registers (8) = 16#1008#, "C.ADDI4SPN x8 = sp + 8");
      Check (C.PC = 2, "PC advanced by 2");
   end Test_C_ADDI4SPN;

   --  ======================================================================
   --  Test C.LW / C.SW (compressed load/store word)
   --  ======================================================================
   procedure Test_C_LW_SW is
      C : RISCV.CPU.CPU_State;
      M : RISCV.Memory.Memory_Unit;
   begin
      Put_Line ("Testing C.LW / C.SW...");

      RISCV.Memory.Initialize (M);
      RISCV.Memory.Add_Region (M, "RAM", 0, 16#2000#,
                               RISCV.Memory.RAM, RISCV.Memory.Permission_RWX);

      --  Store test value at address 0x100
      RISCV.Memory.Write_Word (M, 16#100#, 16#AABBCCDD#);

      --  C.LW rd'=x8, offset=0(rs1'=x9)
      --  Format: 010 uimm[5:3] rs1' uimm[2|6] rd' 00
      --  offset=0 -> all uimm bits=0
      --  rs1'=001 (x9), rd'=000 (x8)
      --  010 000 001 00 000 00 = 16#4080#
      RISCV.CPU.Initialize (C, 0);
      C.Registers (9) := 16#100#;  --  Base address
      Store_Compressed (M, 0, 16#4080#);
      Store_32 (M, 2, Ecall);
      RISCV.CPU.Step (C, M);

      Check (C.Registers (8) = 16#AABBCCDD#, "C.LW loads word correctly");
      Check (C.PC = 2, "C.LW advances PC by 2");

      --  C.SW rs2'=x8, offset=0(rs1'=x9)
      --  Format: 110 uimm[5:3] rs1' uimm[2|6] rs2' 00
      --  offset=0 -> all uimm bits=0
      --  rs1'=001 (x9), rs2'=000 (x8)
      --  110 000 001 00 000 00 = 16#C080#
      RISCV.CPU.Initialize (C, 0);
      C.Registers (8) := 16#12345678#;
      C.Registers (9) := 16#200#;
      Store_Compressed (M, 0, 16#C080#);
      Store_32 (M, 2, Ecall);
      RISCV.CPU.Step (C, M);

      Check (RISCV.Memory.Read_Word (M, 16#200#) = 16#12345678#,
             "C.SW stores word correctly");
   end Test_C_LW_SW;

   --  ======================================================================
   --  Test C.ADDI (addi rd, rd, nzimm)
   --  ======================================================================
   procedure Test_C_ADDI is
      C : RISCV.CPU.CPU_State;
      M : RISCV.Memory.Memory_Unit;
   begin
      Put_Line ("Testing C.ADDI...");

      RISCV.Memory.Initialize (M);
      RISCV.Memory.Add_Region (M, "RAM", 0, 16#2000#,
                               RISCV.Memory.RAM, RISCV.Memory.Permission_RWX);

      --  C.ADDI x10, 5
      --  Format: 000 nzimm[5] rd nzimm[4:0] 01
      --  rd=01010 (x10), nzimm=5 -> nzimm[4:0]=00101, nzimm[5]=0
      --  000 0 01010 00101 01 = 16#0515#
      RISCV.CPU.Initialize (C, 0);
      C.Registers (10) := 100;
      Store_Compressed (M, 0, 16#0515#);
      Store_32 (M, 2, Ecall);
      RISCV.CPU.Step (C, M);

      Check (C.Registers (10) = 105, "C.ADDI x10 += 5");

      --  C.ADDI x10, -1 (nzimm = 0b111111 = -1 sign extended from 6 bits)
      --  nzimm[5]=1, nzimm[4:0]=11111
      --  000 1 01010 11111 01 = 16#157D#
      RISCV.CPU.Initialize (C, 0);
      C.Registers (10) := 100;
      Store_Compressed (M, 0, 16#157D#);
      RISCV.CPU.Step (C, M);

      Check (C.Registers (10) = 99, "C.ADDI x10 += -1");
   end Test_C_ADDI;

   --  ======================================================================
   --  Test C.LI (addi rd, x0, imm)
   --  ======================================================================
   procedure Test_C_LI is
      C : RISCV.CPU.CPU_State;
      M : RISCV.Memory.Memory_Unit;
   begin
      Put_Line ("Testing C.LI...");

      RISCV.Memory.Initialize (M);
      RISCV.Memory.Add_Region (M, "RAM", 0, 16#2000#,
                               RISCV.Memory.RAM, RISCV.Memory.Permission_RWX);

      --  C.LI x10, 7
      --  Format: 010 imm[5] rd imm[4:0] 01
      --  rd=01010 (x10), imm=7 -> imm[4:0]=00111, imm[5]=0
      --  010 0 01010 00111 01 = 16#451D#
      RISCV.CPU.Initialize (C, 0);
      Store_Compressed (M, 0, 16#451D#);
      Store_32 (M, 2, Ecall);
      RISCV.CPU.Step (C, M);

      Check (C.Registers (10) = 7, "C.LI x10 = 7");

      --  C.LI x10, -1
      --  imm[5]=1, imm[4:0]=11111
      --  010 1 01010 11111 01 = 16#557D#
      RISCV.CPU.Initialize (C, 0);
      Store_Compressed (M, 0, 16#557D#);
      RISCV.CPU.Step (C, M);

      Check (C.Registers (10) = 16#FFFFFFFF#, "C.LI x10 = -1");
   end Test_C_LI;

   --  ======================================================================
   --  Test C.LWSP / C.SWSP (stack-relative load/store)
   --  ======================================================================
   procedure Test_C_LWSP_SWSP is
      C : RISCV.CPU.CPU_State;
      M : RISCV.Memory.Memory_Unit;
   begin
      Put_Line ("Testing C.LWSP / C.SWSP...");

      RISCV.Memory.Initialize (M);
      RISCV.Memory.Add_Region (M, "RAM", 0, 16#2000#,
                               RISCV.Memory.RAM, RISCV.Memory.Permission_RWX);

      --  Store test value at SP + 0 = 0x100
      RISCV.Memory.Write_Word (M, 16#100#, 16#DEADBEEF#);

      --  C.LWSP x10, 0(sp)
      --  Format: 010 uimm[5] rd uimm[4:2|7:6] 10
      --  rd=01010 (x10), uimm=0
      --  010 0 01010 00000 10 = 16#4502#
      RISCV.CPU.Initialize (C, 0);
      C.Registers (2) := 16#100#;  --  SP
      Store_Compressed (M, 0, 16#4502#);
      Store_32 (M, 2, Ecall);
      RISCV.CPU.Step (C, M);

      Check (C.Registers (10) = 16#DEADBEEF#, "C.LWSP loads from stack");

      --  C.SWSP x10, 0(sp)
      --  Format: 110 uimm[5:2|7:6] rs2 10
      --  uimm=0, rs2=01010 (x10)
      --  110 000000 01010 10 = 16#C02A#
      RISCV.CPU.Initialize (C, 0);
      C.Registers (2) := 16#200#;  --  SP
      C.Registers (10) := 16#CAFEBABE#;
      Store_Compressed (M, 0, 16#C02A#);
      Store_32 (M, 2, Ecall);
      RISCV.CPU.Step (C, M);

      Check (RISCV.Memory.Read_Word (M, 16#200#) = 16#CAFEBABE#,
             "C.SWSP stores to stack");
   end Test_C_LWSP_SWSP;

   --  ======================================================================
   --  Test C.MV and C.ADD
   --  ======================================================================
   procedure Test_C_MV_ADD is
      C : RISCV.CPU.CPU_State;
      M : RISCV.Memory.Memory_Unit;
   begin
      Put_Line ("Testing C.MV / C.ADD...");

      RISCV.Memory.Initialize (M);
      RISCV.Memory.Add_Region (M, "RAM", 0, 16#2000#,
                               RISCV.Memory.RAM, RISCV.Memory.Permission_RWX);

      --  C.MV x10, x11 (bit12=0, rs2!=0)
      --  Format: 100 0 rd rs2 10
      --  rd=01010 (x10), rs2=01011 (x11)
      --  100 0 01010 01011 10 = 16#852E#
      RISCV.CPU.Initialize (C, 0);
      C.Registers (11) := 42;
      Store_Compressed (M, 0, 16#852E#);
      Store_32 (M, 2, Ecall);
      RISCV.CPU.Step (C, M);

      Check (C.Registers (10) = 42, "C.MV x10 = x11");

      --  C.ADD x10, x11 (bit12=1, rs2!=0)
      --  Format: 100 1 rd rs2 10
      --  rd=01010 (x10), rs2=01011 (x11)
      --  100 1 01010 01011 10 = 16#952E#
      RISCV.CPU.Initialize (C, 0);
      C.Registers (10) := 100;
      C.Registers (11) := 50;
      Store_Compressed (M, 0, 16#952E#);
      Store_32 (M, 2, Ecall);
      RISCV.CPU.Step (C, M);

      Check (C.Registers (10) = 150, "C.ADD x10 += x11");
   end Test_C_MV_ADD;

   --  ======================================================================
   --  Test C.J (unconditional jump)
   --  ======================================================================
   procedure Test_C_J is
      C : RISCV.CPU.CPU_State;
      M : RISCV.Memory.Memory_Unit;
   begin
      Put_Line ("Testing C.J...");

      RISCV.Memory.Initialize (M);
      RISCV.Memory.Add_Region (M, "RAM", 0, 16#2000#,
                               RISCV.Memory.RAM, RISCV.Memory.Permission_RWX);

      --  C.J offset=+8
      --  Format: 101 imm[11|4|9:8|10|6|7|3:1|5] 01
      --  offset=8 -> bit3=1
      --  imm[3:1]=100 -> bits[5:3]=100
      --  101 00000000 100 01 = 16#A021#
      RISCV.CPU.Initialize (C, 0);
      Store_Compressed (M, 0, 16#A021#);
      Store_32 (M, 8, Ecall);  --  Target at offset 8
      RISCV.CPU.Step (C, M);

      Check (C.PC = 8, "C.J jumps to PC+8");
   end Test_C_J;

   --  ======================================================================
   --  Test C.BEQZ / C.BNEZ
   --  ======================================================================
   procedure Test_C_BEQZ_BNEZ is
      C : RISCV.CPU.CPU_State;
      M : RISCV.Memory.Memory_Unit;
   begin
      Put_Line ("Testing C.BEQZ / C.BNEZ...");

      RISCV.Memory.Initialize (M);
      RISCV.Memory.Add_Region (M, "RAM", 0, 16#2000#,
                               RISCV.Memory.RAM, RISCV.Memory.Permission_RWX);

      --  C.BEQZ x8, offset=+8
      --  Format: 110 offset[8|4:3] rs1' offset[7:6|2:1|5] 01
      --  rs1'=000 (x8), offset=8 -> bit3=1
      --  offset[4:3]=01 -> bits[11:10]=01
      --  110 01 000 00 000 01 = 16#C401#
      RISCV.CPU.Initialize (C, 0);
      C.Registers (8) := 0;  --  Equal to zero -> should branch
      Store_Compressed (M, 0, 16#C401#);
      Store_32 (M, 8, Ecall);
      RISCV.CPU.Step (C, M);

      Check (C.PC = 8, "C.BEQZ branches when rs1=0");

      --  Same instruction but x8 != 0
      RISCV.CPU.Initialize (C, 0);
      C.Registers (8) := 1;  --  Not zero -> should not branch
      Store_Compressed (M, 0, 16#C401#);
      RISCV.CPU.Step (C, M);

      Check (C.PC = 2, "C.BEQZ falls through when rs1!=0");

      --  C.BNEZ x8, offset=+8
      --  Format: 111 offset[8|4:3] rs1' offset[7:6|2:1|5] 01
      --  rs1'=000 (x8), offset=8
      --  111 01 000 00 000 01 = 16#E401#
      RISCV.CPU.Initialize (C, 0);
      C.Registers (8) := 1;  --  Not zero -> should branch
      Store_Compressed (M, 0, 16#E401#);
      Store_32 (M, 8, Ecall);
      RISCV.CPU.Step (C, M);

      Check (C.PC = 8, "C.BNEZ branches when rs1!=0");

      --  C.BNEZ but x8 = 0
      RISCV.CPU.Initialize (C, 0);
      C.Registers (8) := 0;  --  Zero -> should not branch
      Store_Compressed (M, 0, 16#E401#);
      RISCV.CPU.Step (C, M);

      Check (C.PC = 2, "C.BNEZ falls through when rs1=0");
   end Test_C_BEQZ_BNEZ;

   --  ======================================================================
   --  Test C.SUB / C.XOR / C.OR / C.AND
   --  ======================================================================
   procedure Test_C_Arith is
      C : RISCV.CPU.CPU_State;
      M : RISCV.Memory.Memory_Unit;
   begin
      Put_Line ("Testing C.SUB / C.XOR / C.OR / C.AND...");

      RISCV.Memory.Initialize (M);
      RISCV.Memory.Add_Region (M, "RAM", 0, 16#2000#,
                               RISCV.Memory.RAM, RISCV.Memory.Permission_RWX);

      --  C.SUB x8, x9: rd'=000 (x8), rs2'=001 (x9)
      --  Format: 100 0 11 rd' 00 rs2' 01
      --  100 0 11 000 00 001 01 = 16#8C05#
      RISCV.CPU.Initialize (C, 0);
      C.Registers (8) := 100;
      C.Registers (9) := 30;
      Store_Compressed (M, 0, 16#8C05#);
      Store_32 (M, 2, Ecall);
      RISCV.CPU.Step (C, M);

      Check (C.Registers (8) = 70, "C.SUB x8 -= x9");

      --  C.XOR x8, x9: rd'=000 (x8), rs2'=001 (x9)
      --  Format: 100 0 11 rd' 01 rs2' 01
      --  100 0 11 000 01 001 01 = 16#8C25#
      RISCV.CPU.Initialize (C, 0);
      C.Registers (8) := 16#FF00FF00#;
      C.Registers (9) := 16#0F0F0F0F#;
      Store_Compressed (M, 0, 16#8C25#);
      RISCV.CPU.Step (C, M);

      Check (C.Registers (8) = 16#F00FF00F#, "C.XOR x8 ^= x9");

      --  C.OR x8, x9: rd'=000 (x8), rs2'=001 (x9)
      --  Format: 100 0 11 rd' 10 rs2' 01
      --  100 0 11 000 10 001 01 = 16#8C45#
      RISCV.CPU.Initialize (C, 0);
      C.Registers (8) := 16#F0F0F0F0#;
      C.Registers (9) := 16#0F0F0F0F#;
      Store_Compressed (M, 0, 16#8C45#);
      RISCV.CPU.Step (C, M);

      Check (C.Registers (8) = 16#FFFFFFFF#, "C.OR x8 |= x9");

      --  C.AND x8, x9: rd'=000 (x8), rs2'=001 (x9)
      --  Format: 100 0 11 rd' 11 rs2' 01
      --  100 0 11 000 11 001 01 = 16#8C65#
      RISCV.CPU.Initialize (C, 0);
      C.Registers (8) := 16#FFFFFFFF#;
      C.Registers (9) := 16#0F0F0F0F#;
      Store_Compressed (M, 0, 16#8C65#);
      RISCV.CPU.Step (C, M);

      Check (C.Registers (8) = 16#0F0F0F0F#, "C.AND x8 &= x9");
   end Test_C_Arith;

   --  ======================================================================
   --  Test C.SLLI
   --  ======================================================================
   procedure Test_C_SLLI is
      C : RISCV.CPU.CPU_State;
      M : RISCV.Memory.Memory_Unit;
   begin
      Put_Line ("Testing C.SLLI...");

      RISCV.Memory.Initialize (M);
      RISCV.Memory.Add_Region (M, "RAM", 0, 16#2000#,
                               RISCV.Memory.RAM, RISCV.Memory.Permission_RWX);

      --  C.SLLI x10, 4
      --  Format: 000 shamt[5] rd shamt[4:0] 10
      --  rd=01010 (x10), shamt=4 -> shamt[4:0]=00100, shamt[5]=0
      --  000 0 01010 00100 10 = 16#0512#
      RISCV.CPU.Initialize (C, 0);
      C.Registers (10) := 1;
      Store_Compressed (M, 0, 16#0512#);
      Store_32 (M, 2, Ecall);
      RISCV.CPU.Step (C, M);

      Check (C.Registers (10) = 16, "C.SLLI x10 <<= 4");
   end Test_C_SLLI;

   --  ======================================================================
   --  Test expansion round-trip
   --  ======================================================================
   procedure Test_Expansion is
      Expanded : Word;
   begin
      Put_Line ("Testing compressed expansion...");

      --  C.NOP: 000 0 00000 00000 01 = 0x0001
      Expanded := Compressed.Expand (16#0001#);
      --  Should expand to: addi x0, x0, 0 = 0x00000013
      Check (Expanded = 16#00000013#, "C.NOP expands to ADDI x0,x0,0");

      --  Illegal: all zeros (C.ADDI4SPN with nzuimm=0 is reserved)
      Expanded := Compressed.Expand (16#0000#);
      Check (Expanded = 0, "All-zero half-word is illegal");

      --  C.EBREAK: 100 1 00000 00000 10 = 0x9002
      Expanded := Compressed.Expand (16#9002#);
      --  Should expand to: ebreak = 0x00100073
      Check (Expanded = 16#00100073#, "C.EBREAK expands correctly");
   end Test_Expansion;

   --  ======================================================================
   --  Test mixed 16/32-bit instruction sequence
   --  ======================================================================
   procedure Test_Mixed_Sequence is
      C : RISCV.CPU.CPU_State;
      M : RISCV.Memory.Memory_Unit;
   begin
      Put_Line ("Testing mixed 16/32-bit instruction sequence...");

      RISCV.Memory.Initialize (M);
      RISCV.Memory.Add_Region (M, "RAM", 0, 16#2000#,
                               RISCV.Memory.RAM, RISCV.Memory.Permission_RWX);

      --  Byte 0: C.LI x10, 5 (16-bit) = 0x4515
      Store_Compressed (M, 0, 16#4515#);
      --  Byte 2: ADDI x10, x10, 3 (32-bit) = 0x00350513
      Store_32 (M, 2, 16#00350513#);
      --  Byte 6: ECALL (32-bit)
      Store_32 (M, 6, Ecall);

      RISCV.CPU.Initialize (C, 0);
      RISCV.CPU.Step (C, M);  --  C.LI x10, 5
      Check (C.PC = 2, "After C.LI, PC=2");
      Check (C.Registers (10) = 5, "C.LI set x10=5");

      RISCV.CPU.Step (C, M);  --  ADDI x10, x10, 3
      Check (C.PC = 6, "After ADDI, PC=6");
      Check (C.Registers (10) = 8, "ADDI x10 = 5+3 = 8");
   end Test_Mixed_Sequence;

begin
   Put_Line ("=================================================");
   Put_Line ("       RISCV Emulator C Extension Tests");
   Put_Line ("=================================================");
   New_Line;

   Test_Detection;
   New_Line;

   Test_Expansion;
   New_Line;

   Test_C_ADDI4SPN;
   New_Line;

   Test_C_LW_SW;
   New_Line;

   Test_C_ADDI;
   New_Line;

   Test_C_LI;
   New_Line;

   Test_C_LWSP_SWSP;
   New_Line;

   Test_C_MV_ADD;
   New_Line;

   Test_C_J;
   New_Line;

   Test_C_BEQZ_BNEZ;
   New_Line;

   Test_C_Arith;
   New_Line;

   Test_C_SLLI;
   New_Line;

   Test_Mixed_Sequence;
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
end Test_Compressed;
