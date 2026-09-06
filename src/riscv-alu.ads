-- ***************************************************************************
--               RISC-V Emulator - ALU Operations
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

package RISCV.ALU is

   --  Basic arithmetic operations
   function Add (A, B : Word) return Word;
   function Sub (A, B : Word) return Word;

   --  Logical operations
   function Op_And (A, B : Word) return Word;
   function Op_Or (A, B : Word) return Word;
   function Op_Xor (A, B : Word) return Word;

   --  Shift operations
   function Shift_Left_Logical (A : Word; Shamt : Natural) return Word;
   function Shift_Right_Logical (A : Word; Shamt : Natural) return Word;
   function Shift_Right_Arithmetic (A : Word; Shamt : Natural) return Word;

   --  Comparison operations (return 1 if true, 0 if false)
   function Set_Less_Than (A, B : Word) return Word;          -- Signed
   function Set_Less_Than_Unsigned (A, B : Word) return Word; -- Unsigned

   --  M extension: Multiply operations
   function Mul (A, B : Word) return Word;
   function Mulh (A, B : Word) return Word;     -- Signed * Signed, high bits
   function Mulhsu (A, B : Word) return Word;   -- Signed * Unsigned, high bits
   function Mulhu (A, B : Word) return Word;    -- Unsigned * Unsigned, high bits

   --  M extension: Division operations
   function Div (A, B : Word) return Word;      -- Signed division
   function Divu (A, B : Word) return Word;     -- Unsigned division
   function Op_Rem (A, B : Word) return Word;   -- Signed remainder
   function Remu (A, B : Word) return Word;     -- Unsigned remainder

end RISCV.ALU;
