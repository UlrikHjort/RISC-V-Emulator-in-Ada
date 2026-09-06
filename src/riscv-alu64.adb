-- ***************************************************************************
--              RISC-V Emulator - 64-bit ALU Operations (RV64)
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

package body RISCV.ALU64 is

   function To_Signed64  is new Ada.Unchecked_Conversion (Double_Word, Signed_DWord);
   function To_DWord     is new Ada.Unchecked_Conversion (Signed_DWord, Double_Word);
   function To_Signed32  is new Ada.Unchecked_Conversion (Word, Signed_Word);
   function To_Word_UC   is new Ada.Unchecked_Conversion (Signed_Word, Word);

   --  Sign-extend a 32-bit value to 64 bits
   function SE32 (W : Word) return Double_Word is
   begin
      return To_DWord (Signed_DWord (Integer_64 (To_Signed32 (W))));
   end SE32;

   ---------
   -- Add --
   ---------

   function Add (A, B : Double_Word) return Double_Word is
   begin
      return A + B;
   end Add;

   ---------
   -- Sub --
   ---------

   function Sub (A, B : Double_Word) return Double_Word is
   begin
      return A - B;
   end Sub;

   ------------
   -- Op_And --
   ------------

   function Op_And (A, B : Double_Word) return Double_Word is
   begin
      return A and B;
   end Op_And;

   -----------
   -- Op_Or --
   -----------

   function Op_Or (A, B : Double_Word) return Double_Word is
   begin
      return A or B;
   end Op_Or;

   ------------
   -- Op_Xor --
   ------------

   function Op_Xor (A, B : Double_Word) return Double_Word is
   begin
      return A xor B;
   end Op_Xor;

   ------------------------
   -- Shift_Left_Logical --
   ------------------------

   function Shift_Left_Logical (A : Double_Word; Shamt : Natural)
      return Double_Word is
   begin
      return Shift_Left (A, Shamt mod 64);
   end Shift_Left_Logical;

   -------------------------
   -- Shift_Right_Logical --
   -------------------------

   function Shift_Right_Logical (A : Double_Word; Shamt : Natural)
      return Double_Word is
   begin
      return Shift_Right (A, Shamt mod 64);
   end Shift_Right_Logical;

   ----------------------------
   -- Shift_Right_Arithmetic --
   ----------------------------

   function Shift_Right_Arithmetic (A : Double_Word; Shamt : Natural)
      return Double_Word is
      Amount   : constant Natural := Shamt mod 64;
      Sign_Bit : constant Double_Word := A and 16#8000_0000_0000_0000#;
   begin
      if Sign_Bit /= 0 then
         return Shift_Right (A, Amount) or
                not Shift_Right (16#FFFF_FFFF_FFFF_FFFF#, Amount);
      else
         return Shift_Right (A, Amount);
      end if;
   end Shift_Right_Arithmetic;

   -------------------
   -- Set_Less_Than --
   -------------------

   function Set_Less_Than (A, B : Double_Word) return Double_Word is
   begin
      if To_Signed64 (A) < To_Signed64 (B) then
         return 1;
      else
         return 0;
      end if;
   end Set_Less_Than;

   ----------------------------
   -- Set_Less_Than_Unsigned --
   ----------------------------

   function Set_Less_Than_Unsigned (A, B : Double_Word) return Double_Word is
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
   --  Low 64 bits of 64*64 product
   function Mul (A, B : Double_Word) return Double_Word is
   begin
      return A * B;
   end Mul;

   ----------
   -- Mulh --
   ----------
   --  High 64 bits of signed*signed 128-bit product
   --  Computed via: (a * b) = (a_hi * 2^32 + a_lo) * (b_hi * 2^32 + b_lo)
   --  We use partial products and carry tracking.
   function Mulh (A, B : Double_Word) return Double_Word is
      A_Neg  : constant Boolean := (A and 16#8000_0000_0000_0000#) /= 0;
      B_Neg  : constant Boolean := (B and 16#8000_0000_0000_0000#) /= 0;
      UA     : constant Double_Word := (if A_Neg then 0 - A else A);
      UB     : constant Double_Word := (if B_Neg then 0 - B else B);
      --  Unsigned partial products (32-bit halves)
      A_Lo   : constant Double_Word := UA and 16#FFFF_FFFF#;
      A_Hi   : constant Double_Word := Shift_Right (UA, 32);
      B_Lo   : constant Double_Word := UB and 16#FFFF_FFFF#;
      B_Hi   : constant Double_Word := Shift_Right (UB, 32);
      T0     : constant Double_Word := A_Lo * B_Lo;
      T1     : constant Double_Word := A_Hi * B_Lo + Shift_Right (T0, 32);
      T2     : constant Double_Word := A_Lo * B_Hi + (T1 and 16#FFFF_FFFF#);
      Hi     : constant Double_Word := A_Hi * B_Hi +
                                       Shift_Right (T1, 32) +
                                       Shift_Right (T2, 32);
      Lo     : constant Double_Word := A_Lo * B_Lo +
                                       Shift_Left (A_Hi * B_Lo, 32) +
                                       Shift_Left (A_Lo * B_Hi, 32);
      Result : Double_Word := Hi;
   begin
      --  Correct sign: if signs differ, negate the 128-bit result
      if A_Neg xor B_Neg then
         if Lo = 0 then
            Result := 0 - Hi;
         else
            Result := 0 - Hi - 1;
         end if;
      end if;
      return Result;
   end Mulh;

   ------------
   -- Mulhsu --
   ------------
   --  High 64 bits of signed(A) * unsigned(B)
   function Mulhsu (A, B : Double_Word) return Double_Word is
      A_Neg  : constant Boolean := (A and 16#8000_0000_0000_0000#) /= 0;
      UA     : constant Double_Word := (if A_Neg then 0 - A else A);
      A_Lo   : constant Double_Word := UA and 16#FFFF_FFFF#;
      A_Hi   : constant Double_Word := Shift_Right (UA, 32);
      B_Lo   : constant Double_Word := B and 16#FFFF_FFFF#;
      B_Hi   : constant Double_Word := Shift_Right (B, 32);
      T1     : constant Double_Word := A_Hi * B_Lo +
                                       Shift_Right (A_Lo * B_Lo, 32);
      T2     : constant Double_Word := A_Lo * B_Hi +
                                       (T1 and 16#FFFF_FFFF#);
      Hi     : constant Double_Word := A_Hi * B_Hi +
                                       Shift_Right (T1, 32) +
                                       Shift_Right (T2, 32);
      Lo     : constant Double_Word := UA * B;
      Result : Double_Word := Hi;
   begin
      if A_Neg then
         if Lo = 0 then
            Result := 0 - Hi;
         else
            Result := 0 - Hi - 1;
         end if;
      end if;
      return Result;
   end Mulhsu;

   -----------
   -- Mulhu --
   -----------
   --  High 64 bits of unsigned * unsigned
   function Mulhu (A, B : Double_Word) return Double_Word is
      A_Lo : constant Double_Word := A and 16#FFFF_FFFF#;
      A_Hi : constant Double_Word := Shift_Right (A, 32);
      B_Lo : constant Double_Word := B and 16#FFFF_FFFF#;
      B_Hi : constant Double_Word := Shift_Right (B, 32);
      T0   : constant Double_Word := A_Lo * B_Lo;
      T1   : constant Double_Word := A_Hi * B_Lo + Shift_Right (T0, 32);
      T2   : constant Double_Word := A_Lo * B_Hi + (T1 and 16#FFFF_FFFF#);
   begin
      return A_Hi * B_Hi + Shift_Right (T1, 32) + Shift_Right (T2, 32);
   end Mulhu;

   ---------
   -- Div --
   ---------

   function Div (A, B : Double_Word) return Double_Word is
      AS : constant Signed_DWord := To_Signed64 (A);
      BS : constant Signed_DWord := To_Signed64 (B);
   begin
      if B = 0 then
         return Double_Word'Last;
      elsif A = 16#8000_0000_0000_0000# and B = 16#FFFF_FFFF_FFFF_FFFF# then
         return A;  -- overflow: INT64_MIN / -1
      else
         return To_DWord (AS / BS);
      end if;
   end Div;

   ----------
   -- Divu --
   ----------

   function Divu (A, B : Double_Word) return Double_Word is
   begin
      if B = 0 then
         return Double_Word'Last;
      else
         return A / B;
      end if;
   end Divu;

   ------------
   -- Op_Rem --
   ------------

   function Op_Rem (A, B : Double_Word) return Double_Word is
      AS : constant Signed_DWord := To_Signed64 (A);
      BS : constant Signed_DWord := To_Signed64 (B);
   begin
      if B = 0 then
         return A;
      elsif A = 16#8000_0000_0000_0000# and B = 16#FFFF_FFFF_FFFF_FFFF# then
         return 0;
      else
         return To_DWord (AS rem BS);
      end if;
   end Op_Rem;

   ----------
   -- Remu --
   ----------

   function Remu (A, B : Double_Word) return Double_Word is
   begin
      if B = 0 then
         return A;
      else
         return A rem B;
      end if;
   end Remu;

   -----------
   -- Addw --
   -----------

   function Addw (A, B : Double_Word) return Double_Word is
      R : constant Word := Word (A and 16#FFFF_FFFF#) +
                           Word (B and 16#FFFF_FFFF#);
   begin
      return SE32 (R);
   end Addw;

   -----------
   -- Subw --
   -----------

   function Subw (A, B : Double_Word) return Double_Word is
      R : constant Word := Word (A and 16#FFFF_FFFF#) -
                           Word (B and 16#FFFF_FFFF#);
   begin
      return SE32 (R);
   end Subw;

   ----------
   -- Sllw --
   ----------

   function Sllw (A : Double_Word; Shamt : Natural) return Double_Word is
      R : constant Word := Shift_Left (Word (A and 16#FFFF_FFFF#),
                                       Shamt mod 32);
   begin
      return SE32 (R);
   end Sllw;

   ----------
   -- Srlw --
   ----------

   function Srlw (A : Double_Word; Shamt : Natural) return Double_Word is
      R : constant Word := Shift_Right (Word (A and 16#FFFF_FFFF#),
                                        Shamt mod 32);
   begin
      return SE32 (R);
   end Srlw;

   ----------
   -- Sraw --
   ----------

   function Sraw (A : Double_Word; Shamt : Natural) return Double_Word is
      W32    : constant Word    := Word (A and 16#FFFF_FFFF#);
      Amount : constant Natural := Shamt mod 32;
      Sign   : constant Word    := W32 and 16#80000000#;
      R      : Word;
   begin
      if Sign /= 0 then
         R := Shift_Right (W32, Amount) or not Shift_Right (16#FFFFFFFF#, Amount);
      else
         R := Shift_Right (W32, Amount);
      end if;
      return SE32 (R);
   end Sraw;

   ----------
   -- Mulw --
   ----------

   function Mulw (A, B : Double_Word) return Double_Word is
      R : constant Word := Word (A and 16#FFFF_FFFF#) *
                           Word (B and 16#FFFF_FFFF#);
   begin
      return SE32 (R);
   end Mulw;

   ----------
   -- Divw --
   ----------

   function Divw (A, B : Double_Word) return Double_Word is
      AW : constant Word        := Word (A and 16#FFFF_FFFF#);
      BW : constant Word        := Word (B and 16#FFFF_FFFF#);
      AS : constant Signed_Word := To_Signed32 (AW);
      BS : constant Signed_Word := To_Signed32 (BW);
   begin
      if BW = 0 then
         return 16#FFFF_FFFF_FFFF_FFFF#;
      elsif AW = 16#80000000# and BW = 16#FFFFFFFF# then
         return SE32 (AW);
      else
         return SE32 (To_Word_UC (AS / BS));
      end if;
   end Divw;

   -----------
   -- Divuw --
   -----------

   function Divuw (A, B : Double_Word) return Double_Word is
      AW : constant Word := Word (A and 16#FFFF_FFFF#);
      BW : constant Word := Word (B and 16#FFFF_FFFF#);
   begin
      if BW = 0 then
         return 16#FFFF_FFFF_FFFF_FFFF#;
      else
         return SE32 (AW / BW);
      end if;
   end Divuw;

   ----------
   -- Remw --
   ----------

   function Remw (A, B : Double_Word) return Double_Word is
      AW : constant Word        := Word (A and 16#FFFF_FFFF#);
      BW : constant Word        := Word (B and 16#FFFF_FFFF#);
      AS : constant Signed_Word := To_Signed32 (AW);
      BS : constant Signed_Word := To_Signed32 (BW);
   begin
      if BW = 0 then
         return SE32 (AW);
      elsif AW = 16#80000000# and BW = 16#FFFFFFFF# then
         return 0;
      else
         return SE32 (To_Word_UC (AS rem BS));
      end if;
   end Remw;

   -----------
   -- Remuw --
   -----------

   function Remuw (A, B : Double_Word) return Double_Word is
      AW : constant Word := Word (A and 16#FFFF_FFFF#);
      BW : constant Word := Word (B and 16#FFFF_FFFF#);
   begin
      if BW = 0 then
         return SE32 (AW);
      else
         return SE32 (AW rem BW);
      end if;
   end Remuw;

end RISCV.ALU64;
