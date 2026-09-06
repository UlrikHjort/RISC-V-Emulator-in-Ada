-- ***************************************************************************
--              RISC-V Emulator - ALU Operations
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

package body RISCV.ALU is

   function To_Signed is new Ada.Unchecked_Conversion (Word, Signed_Word);
   function To_Word is new Ada.Unchecked_Conversion (Signed_Word, Word);
   function To_Unsigned_64 is
      new Ada.Unchecked_Conversion (Integer_64, Unsigned_64);

   ---------
   -- Add --
   ---------

   function Add (A, B : Word) return Word is
   begin
      return A + B;
   end Add;

   ---------
   -- Sub --
   ---------

   function Sub (A, B : Word) return Word is
   begin
      return A - B;
   end Sub;

   ------------
   -- Op_And --
   ------------

   function Op_And (A, B : Word) return Word is
   begin
      return A and B;
   end Op_And;

   -----------
   -- Op_Or --
   -----------

   function Op_Or (A, B : Word) return Word is
   begin
      return A or B;
   end Op_Or;

   ------------
   -- Op_Xor --
   ------------

   function Op_Xor (A, B : Word) return Word is
   begin
      return A xor B;
   end Op_Xor;

   -------------------------
   -- Shift_Left_Logical --
   -------------------------

   function Shift_Left_Logical (A : Word; Shamt : Natural) return Word is
   begin
      return Shift_Left (A, Shamt mod 32);
   end Shift_Left_Logical;

   --------------------------
   -- Shift_Right_Logical --
   --------------------------

   function Shift_Right_Logical (A : Word; Shamt : Natural) return Word is
   begin
      return Shift_Right (A, Shamt mod 32);
   end Shift_Right_Logical;

   -----------------------------
   -- Shift_Right_Arithmetic --
   -----------------------------

   function Shift_Right_Arithmetic (A : Word; Shamt : Natural) return Word is
      Shift_Amount : constant Natural := Shamt mod 32;
      Sign_Bit     : constant Word := A and 16#80000000#;
   begin
      if Sign_Bit /= 0 then
         --  Negative number: shift right and fill with 1s
         return Shift_Right (A, Shift_Amount) or
                not (Shift_Right (16#FFFFFFFF#, Shift_Amount));
      else
         --  Positive number: logical shift
         return Shift_Right (A, Shift_Amount);
      end if;
   end Shift_Right_Arithmetic;

   -------------------
   -- Set_Less_Than --
   -------------------

   function Set_Less_Than (A, B : Word) return Word is
   begin
      if To_Signed (A) < To_Signed (B) then
         return 1;
      else
         return 0;
      end if;
   end Set_Less_Than;

   ----------------------------
   -- Set_Less_Than_Unsigned --
   ----------------------------

   function Set_Less_Than_Unsigned (A, B : Word) return Word is
   begin
      if A < B then
         return 1;
      else
         return 0;
      end if;
   end Set_Less_Than_Unsigned;

   ---------
   -- Mul --
   ---------

   function Mul (A, B : Word) return Word is
      Result : constant Unsigned_64 := Unsigned_64 (A) * Unsigned_64 (B);
   begin
      return Word (Result and 16#FFFFFFFF#);
   end Mul;

   ----------
   -- Mulh --
   ----------

   function Mulh (A, B : Word) return Word is
      A_Signed : constant Integer_64 := Integer_64 (To_Signed (A));
      B_Signed : constant Integer_64 := Integer_64 (To_Signed (B));
      Result   : constant Integer_64 := A_Signed * B_Signed;
   begin
      return Word (Shift_Right (To_Unsigned_64 (Result), 32) and 16#FFFFFFFF#);
   end Mulh;

   ------------
   -- Mulhsu --
   ------------

   function Mulhsu (A, B : Word) return Word is
      A_Signed   : constant Integer_64 := Integer_64 (To_Signed (A));
      B_Unsigned : constant Unsigned_64 := Unsigned_64 (B);
      Result     : Integer_64;
   begin
      if A_Signed < 0 then
         Result := -((-A_Signed) * Integer_64 (B_Unsigned));
      else
         Result := A_Signed * Integer_64 (B_Unsigned);
      end if;
      return Word (Shift_Right (To_Unsigned_64 (Result), 32) and 16#FFFFFFFF#);
   end Mulhsu;

   -----------
   -- Mulhu --
   -----------

   function Mulhu (A, B : Word) return Word is
      Result : constant Unsigned_64 := Unsigned_64 (A) * Unsigned_64 (B);
   begin
      return Word (Shift_Right (Result, 32) and 16#FFFFFFFF#);
   end Mulhu;

   ---------
   -- Div --
   ---------

   function Div (A, B : Word) return Word is
      A_Signed : constant Signed_Word := To_Signed (A);
      B_Signed : constant Signed_Word := To_Signed (B);
   begin
      if B = 0 then
         --  Division by zero returns -1
         return Word'Last;
      elsif A = 16#80000000# and B = 16#FFFFFFFF# then
         --  Overflow: most negative divided by -1
         return A;
      else
         return To_Word (A_Signed / B_Signed);
      end if;
   end Div;

   ----------
   -- Divu --
   ----------

   function Divu (A, B : Word) return Word is
   begin
      if B = 0 then
         --  Division by zero returns max unsigned
         return Word'Last;
      else
         return A / B;
      end if;
   end Divu;

   ------------
   -- Op_Rem --
   ------------

   function Op_Rem (A, B : Word) return Word is
      A_Signed : constant Signed_Word := To_Signed (A);
      B_Signed : constant Signed_Word := To_Signed (B);
   begin
      if B = 0 then
         --  Remainder by zero returns dividend
         return A;
      elsif A = 16#80000000# and B = 16#FFFFFFFF# then
         --  Overflow: most negative mod -1 = 0
         return 0;
      else
         return To_Word (A_Signed rem B_Signed);
      end if;
   end Op_Rem;

   ----------
   -- Remu --
   ----------

   function Remu (A, B : Word) return Word is
   begin
      if B = 0 then
         --  Remainder by zero returns dividend
         return A;
      else
         return A rem B;
      end if;
   end Remu;

end RISCV.ALU;
