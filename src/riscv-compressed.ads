-- ***************************************************************************
--          RISC-V Emulator - Compressed Extension (RVC)
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

-- C Extension (RV32C) - 16-bit compressed instructions
package RISCV.Compressed is

   --  Check if instruction is compressed (16-bit)
   --  Compressed instructions have bits [1:0] != 11
   function Is_Compressed (Instruction : Word) return Boolean;

   --  Expand a 16-bit compressed instruction to 32-bit equivalent
   --  Returns the expanded instruction, or 0 for illegal compressed instr
   function Expand (Compressed_Instr : Half_Word) return Word;

   --  C extension quadrants (bits 1:0)
   C_QUADRANT_0 : constant := 2#00#;  --  Loads, stores (stack-relative)
   C_QUADRANT_1 : constant := 2#01#;  --  Arithmetic, control flow
   C_QUADRANT_2 : constant := 2#10#;  --  More arithmetic, loads, stores

   --  C0 quadrant funct3 (bits 15:13)
   C0_ADDI4SPN   : constant := 2#000#;
   C0_FLD        : constant := 2#001#;  --  RV32DC only
   C0_LW         : constant := 2#010#;
   C0_FLW        : constant := 2#011#;  --  RV32FC only
   C0_RESERVED   : constant := 2#100#;
   C0_FSD        : constant := 2#101#;  --  RV32DC only
   C0_SW         : constant := 2#110#;
   C0_FSW        : constant := 2#111#;  --  RV32FC only

   --  C1 quadrant funct3 (bits 15:13)
   C1_ADDI       : constant := 2#000#;  --  Also NOP when rd=0, imm=0
   C1_JAL        : constant := 2#001#;  --  RV32 only (RV64: ADDIW)
   C1_LI         : constant := 2#010#;
   C1_LUI_ADDI16SP : constant := 2#011#;  --  LUI or ADDI16SP based on rd
   C1_ARITH      : constant := 2#100#;  --  SRLI/SRAI/ANDI/SUB/XOR/OR/AND
   C1_J          : constant := 2#101#;
   C1_BEQZ       : constant := 2#110#;
   C1_BNEZ       : constant := 2#111#;

   --  C2 quadrant funct3 (bits 15:13)
   C2_SLLI       : constant := 2#000#;
   C2_FLDSP      : constant := 2#001#;  --  RV32DC only
   C2_LWSP       : constant := 2#010#;
   C2_FLWSP      : constant := 2#011#;  --  RV32FC only
   C2_JR_MV_ADD  : constant := 2#100#;  --  JR/JALR/MV/ADD based on bits
   C2_FSDSP      : constant := 2#101#;  --  RV32DC only
   C2_SWSP       : constant := 2#110#;
   C2_FSWSP      : constant := 2#111#;  --  RV32FC only

   --  Illegal instruction constant
   ILLEGAL_INSTR : constant Word := 0;

end RISCV.Compressed;
