-- ***************************************************************************
--               RISC-V Emulator - 64-bit ALU Operations (RV64)
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

package RISCV.ALU64 is

   --  Basic arithmetic
   function Add (A, B : Double_Word) return Double_Word;
   function Sub (A, B : Double_Word) return Double_Word;

   --  Logical
   function Op_And (A, B : Double_Word) return Double_Word;
   function Op_Or  (A, B : Double_Word) return Double_Word;
   function Op_Xor (A, B : Double_Word) return Double_Word;

   --  Shifts (6-bit shamt, mod 64)
   function Shift_Left_Logical      (A : Double_Word; Shamt : Natural) return Double_Word;
   function Shift_Right_Logical     (A : Double_Word; Shamt : Natural) return Double_Word;
   function Shift_Right_Arithmetic  (A : Double_Word; Shamt : Natural) return Double_Word;

   --  Comparisons (return 1 if true, 0 if false)
   function Set_Less_Than           (A, B : Double_Word) return Double_Word;
   function Set_Less_Than_Unsigned  (A, B : Double_Word) return Double_Word;

   --  M extension: 64-bit multiply
   function Mul    (A, B : Double_Word) return Double_Word;
   function Mulh   (A, B : Double_Word) return Double_Word;   -- signed * signed, high 64
   function Mulhsu (A, B : Double_Word) return Double_Word;   -- signed * unsigned, high 64
   function Mulhu  (A, B : Double_Word) return Double_Word;   -- unsigned * unsigned, high 64

   --  M extension: 64-bit division
   function Div    (A, B : Double_Word) return Double_Word;   -- signed
   function Divu   (A, B : Double_Word) return Double_Word;   -- unsigned
   function Op_Rem (A, B : Double_Word) return Double_Word;   -- signed remainder
   function Remu   (A, B : Double_Word) return Double_Word;   -- unsigned remainder

   --  RV64 *W operations: 32-bit op, result sign-extended to 64 bits
   function Addw  (A, B : Double_Word) return Double_Word;
   function Subw  (A, B : Double_Word) return Double_Word;
   function Sllw  (A : Double_Word; Shamt : Natural) return Double_Word;
   function Srlw  (A : Double_Word; Shamt : Natural) return Double_Word;
   function Sraw  (A : Double_Word; Shamt : Natural) return Double_Word;

   --  RV64 M *W operations
   function Mulw  (A, B : Double_Word) return Double_Word;
   function Divw  (A, B : Double_Word) return Double_Word;
   function Divuw (A, B : Double_Word) return Double_Word;
   function Remw  (A, B : Double_Word) return Double_Word;
   function Remuw (A, B : Double_Word) return Double_Word;

end RISCV.ALU64;
