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

with Ada.Unchecked_Conversion;

package body RISCV.Decoder is

   function To_Signed is new Ada.Unchecked_Conversion (Word, Signed_Word);

   ------------
   -- Decode --
   ------------

   function Decode (Instruction : Word) return Decoded_Instruction is
   begin
      return (
         Opcode => Get_Opcode (Instruction),
         Rd     => Get_Rd (Instruction),
         Rs1    => Get_Rs1 (Instruction),
         Rs2    => Get_Rs2 (Instruction),
         Funct3 => Get_Funct3 (Instruction),
         Funct7 => Get_Funct7 (Instruction),
         Imm_I  => Get_Imm_I (Instruction),
         Imm_S  => Get_Imm_S (Instruction),
         Imm_B  => Get_Imm_B (Instruction),
         Imm_U  => Get_Imm_U (Instruction),
         Imm_J  => Get_Imm_J (Instruction)
      );
   end Decode;

   ----------------
   -- Get_Opcode --
   ----------------

   function Get_Opcode (Instruction : Word) return Word is
   begin
      return Instruction and 16#7F#;
   end Get_Opcode;

   ------------
   -- Get_Rd --
   ------------

   function Get_Rd (Instruction : Word) return Register_Index is
   begin
      return Register_Index (Shift_Right (Instruction, 7) and 16#1F#);
   end Get_Rd;

   -------------
   -- Get_Rs1 --
   -------------

   function Get_Rs1 (Instruction : Word) return Register_Index is
   begin
      return Register_Index (Shift_Right (Instruction, 15) and 16#1F#);
   end Get_Rs1;

   -------------
   -- Get_Rs2 --
   -------------

   function Get_Rs2 (Instruction : Word) return Register_Index is
   begin
      return Register_Index (Shift_Right (Instruction, 20) and 16#1F#);
   end Get_Rs2;

   ----------------
   -- Get_Funct3 --
   ----------------

   function Get_Funct3 (Instruction : Word) return Word is
   begin
      return Shift_Right (Instruction, 12) and 16#7#;
   end Get_Funct3;

   ----------------
   -- Get_Funct7 --
   ----------------

   function Get_Funct7 (Instruction : Word) return Word is
   begin
      return Shift_Right (Instruction, 25) and 16#7F#;
   end Get_Funct7;

   ----------------
   -- Get_Funct5 --
   ----------------

   function Get_Funct5 (Instruction : Word) return Word is
   begin
      return Shift_Right (Instruction, 27) and 16#1F#;
   end Get_Funct5;

   ------------
   -- Get_Aq --
   ------------

   function Get_Aq (Instruction : Word) return Boolean is
   begin
      return (Shift_Right (Instruction, 26) and 1) /= 0;
   end Get_Aq;

   ------------
   -- Get_Rl --
   ------------

   function Get_Rl (Instruction : Word) return Boolean is
   begin
      return (Shift_Right (Instruction, 25) and 1) /= 0;
   end Get_Rl;

   -----------------
   -- Sign_Extend --
   -----------------

   function Sign_Extend (Value : Word; Bits : Natural) return Signed_Word is
      Sign_Bit : constant Word := Shift_Left (1, Bits - 1);
      Extended : Word;
   begin
      if (Value and Sign_Bit) /= 0 then
         --  Negative: extend with 1s
         Extended := Value or (not (Shift_Left (1, Bits) - 1));
      else
         --  Positive: no extension needed
         Extended := Value;
      end if;
      return To_Signed (Extended);
   end Sign_Extend;

   ---------------
   -- Get_Imm_I --
   ---------------

   function Get_Imm_I (Instruction : Word) return Signed_Word is
      Imm : constant Word := Shift_Right (Instruction, 20);
   begin
      return Sign_Extend (Imm, 12);
   end Get_Imm_I;

   ---------------
   -- Get_Imm_S --
   ---------------

   function Get_Imm_S (Instruction : Word) return Signed_Word is
      Imm_4_0  : constant Word := Shift_Right (Instruction, 7) and 16#1F#;
      Imm_11_5 : constant Word := Shift_Right (Instruction, 25) and 16#7F#;
      Imm      : constant Word := Imm_4_0 or Shift_Left (Imm_11_5, 5);
   begin
      return Sign_Extend (Imm, 12);
   end Get_Imm_S;

   ---------------
   -- Get_Imm_B --
   ---------------

   function Get_Imm_B (Instruction : Word) return Signed_Word is
      Imm_11   : constant Word := Shift_Right (Instruction, 7) and 16#1#;
      Imm_4_1  : constant Word := Shift_Right (Instruction, 8) and 16#F#;
      Imm_10_5 : constant Word := Shift_Right (Instruction, 25) and 16#3F#;
      Imm_12   : constant Word := Shift_Right (Instruction, 31) and 16#1#;
      Imm      : constant Word := Shift_Left (Imm_4_1, 1) or
                                  Shift_Left (Imm_10_5, 5) or
                                  Shift_Left (Imm_11, 11) or
                                  Shift_Left (Imm_12, 12);
   begin
      return Sign_Extend (Imm, 13);
   end Get_Imm_B;

   ---------------
   -- Get_Imm_U --
   ---------------

   function Get_Imm_U (Instruction : Word) return Word is
   begin
      return Instruction and 16#FFFFF000#;
   end Get_Imm_U;

   ---------------
   -- Get_Imm_J --
   ---------------

   function Get_Imm_J (Instruction : Word) return Signed_Word is
      Imm_19_12 : constant Word := Shift_Right (Instruction, 12) and 16#FF#;
      Imm_11    : constant Word := Shift_Right (Instruction, 20) and 16#1#;
      Imm_10_1  : constant Word := Shift_Right (Instruction, 21) and 16#3FF#;
      Imm_20    : constant Word := Shift_Right (Instruction, 31) and 16#1#;
      Imm       : constant Word := Shift_Left (Imm_10_1, 1) or
                                   Shift_Left (Imm_11, 11) or
                                   Shift_Left (Imm_19_12, 12) or
                                   Shift_Left (Imm_20, 20);
   begin
      return Sign_Extend (Imm, 21);
   end Get_Imm_J;

end RISCV.Decoder;
