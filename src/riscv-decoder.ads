-- ***************************************************************************
--             RISC-V Emulator - Instruction Decoder
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

package RISCV.Decoder is

   --  Decoded instruction record
   type Decoded_Instruction is record
      Opcode : Word;
      Rd     : Register_Index;
      Rs1    : Register_Index;
      Rs2    : Register_Index;
      Funct3 : Word;
      Funct7 : Word;
      Imm_I  : Signed_Word;   -- I-type immediate
      Imm_S  : Signed_Word;   -- S-type immediate
      Imm_B  : Signed_Word;   -- B-type immediate
      Imm_U  : Word;          -- U-type immediate
      Imm_J  : Signed_Word;   -- J-type immediate
   end record;

   --  Decode a 32-bit instruction
   function Decode (Instruction : Word) return Decoded_Instruction;

   --  Extract individual fields
   function Get_Opcode (Instruction : Word) return Word;
   function Get_Rd (Instruction : Word) return Register_Index;
   function Get_Rs1 (Instruction : Word) return Register_Index;
   function Get_Rs2 (Instruction : Word) return Register_Index;
   function Get_Funct3 (Instruction : Word) return Word;
   function Get_Funct7 (Instruction : Word) return Word;

   --  A Extension fields
   function Get_Funct5 (Instruction : Word) return Word;  -- bits 31..27
   function Get_Aq (Instruction : Word) return Boolean;   -- bit 26 (acquire)
   function Get_Rl (Instruction : Word) return Boolean;   -- bit 25 (release)

   --  Extract immediates
   function Get_Imm_I (Instruction : Word) return Signed_Word;
   function Get_Imm_S (Instruction : Word) return Signed_Word;
   function Get_Imm_B (Instruction : Word) return Signed_Word;
   function Get_Imm_U (Instruction : Word) return Word;
   function Get_Imm_J (Instruction : Word) return Signed_Word;

   --  Sign extend a value
   function Sign_Extend (Value : Word; Bits : Natural) return Signed_Word;

end RISCV.Decoder;
