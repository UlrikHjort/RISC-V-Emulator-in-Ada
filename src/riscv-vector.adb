-- ***************************************************************************
--          RISC-V Emulator - Vector Extension (RVV 1.0)
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

package body RISCV.Vector is

   function To_Signed is new Ada.Unchecked_Conversion (Word, Signed_Word);
   function To_Word is new Ada.Unchecked_Conversion (Signed_Word, Word);
   function To_U64 is new Ada.Unchecked_Conversion (Integer_64, Unsigned_64);
   function To_I64 is new Ada.Unchecked_Conversion (Unsigned_64, Integer_64);

   --  Arithmetic right shift helper for Signed_Word

   ----------------
   -- Initialize --
   ----------------

   procedure Initialize (VU : out Vector_State) is
   begin
      for I in Register_Index loop
         VU.Registers (I).Data := (others => 0);
      end loop;
      VU.VL := 0;
      VU.VType := (VSEW => SEW_8, VLMUL => LMUL_1,
                   VTA => False, VMA => False, VILL => True);
      VU.VStart := 0;
   end Initialize;

   -------------
   -- Read_VL --
   -------------

   function Read_VL (VU : Vector_State) return Word is
   begin
      return VU.VL;
   end Read_VL;

   ----------------
   -- Read_VType --
   ----------------

   function Read_VType (VU : Vector_State) return Word is
   begin
      return Encode_VType (VU.VType);
   end Read_VType;

   ----------------
   -- Read_VLENB --
   ----------------

   function Read_VLENB return Word is
   begin
      return Word (VLENB);
   end Read_VLENB;

   -----------------
   -- Read_VStart --
   -----------------

   function Read_VStart (VU : Vector_State) return Word is
   begin
      return VU.VStart;
   end Read_VStart;

   ------------------
   -- Write_VStart --
   ------------------

   procedure Write_VStart (VU : in out Vector_State; Value : Word) is
   begin
      VU.VStart := Value;
   end Write_VStart;

   function Read_VXSat (VU : Vector_State) return Word is
   begin
      return (if VU.VXSat then 1 else 0);
   end Read_VXSat;

   procedure Write_VXSat (VU : in out Vector_State; Value : Word) is
   begin
      VU.VXSat := (Value and 1) /= 0;
   end Write_VXSat;

   function Read_VXRM (VU : Vector_State) return Word is
   begin
      return Word (VU.VXRM);
   end Read_VXRM;

   procedure Write_VXRM (VU : in out Vector_State; Value : Word) is
   begin
      VU.VXRM := Natural (Value and 3);
   end Write_VXRM;

   --  Helper: saturate unsigned value to Bits width
   function Saturate_Unsigned (Val : Unsigned_64; Bits : Natural;
                               Sat : out Boolean) return Word is
      Max : constant Unsigned_64 :=
         Shift_Left (Unsigned_64'(1), Bits) - 1;
   begin
      if Val > Max then
         Sat := True;
         return Word (Max and 16#FFFFFFFF#);
      else
         Sat := False;
         return Word (Val and 16#FFFFFFFF#);
      end if;
   end Saturate_Unsigned;

   --  Helper: saturate signed value to Bits width
   function Saturate_Signed (Val : Integer_64; Bits : Natural;
                             Sat : out Boolean) return Word is
      function To_W is new Ada.Unchecked_Conversion (Signed_Word, Word);
      Max : constant Integer_64 :=
         Integer_64 (Shift_Left (Unsigned_64'(1), Bits - 1)) - 1;
      Min : constant Integer_64 := -Max - 1;
   begin
      if Val > Max then
         Sat := True;
         return To_W (Signed_Word (Max));
      elsif Val < Min then
         Sat := True;
         return To_W (Signed_Word (Min));
      else
         Sat := False;
         return To_W (Signed_Word (Val));
      end if;
   end Saturate_Signed;

   --  Helper: rounding shift right per VXRM spec
   function Roundoff_Unsigned (Val : Unsigned_64; Shamt : Natural;
                               VXRM : Natural) return Unsigned_64 is
      Round_Bit : Unsigned_64 := 0;
   begin
      if Shamt = 0 then
         return Val;
      end if;
      case VXRM is
         when 0 =>  -- rnu: round-to-nearest-up
            Round_Bit := Shift_Right (Val, Shamt - 1) and 1;
         when 1 =>  -- rne: round-to-nearest-even
            if Shamt = 1 then
               Round_Bit := (Val and 1) and Shift_Right (Val, 1);
            else
               declare
                  V_D_Minus_1 : constant Unsigned_64 :=
                     Shift_Right (Val, Shamt - 1) and 1;
                  Low_Mask : constant Unsigned_64 :=
                     Shift_Left (Unsigned_64'(1), Shamt - 1) - 1;
                  V_Low : constant Unsigned_64 := Val and Low_Mask;
               begin
                  if V_D_Minus_1 = 1 and V_Low /= 0 then
                     Round_Bit := 1;
                  elsif V_D_Minus_1 = 1 and V_Low = 0 then
                     Round_Bit := Shift_Right (Val, Shamt) and 1;
                  end if;
               end;
            end if;
         when 2 =>  -- rdn: round-down (truncate)
            Round_Bit := 0;
         when 3 =>  -- rod: round-to-odd
            declare
               Low_Mask : constant Unsigned_64 :=
                  Shift_Left (Unsigned_64'(1), Shamt) - 1;
            begin
               if (Val and Low_Mask) /= 0
                 and (Shift_Right (Val, Shamt) and 1) = 0
               then
                  Round_Bit := 1;
               end if;
            end;
         when others => null;
      end case;
      return Shift_Right (Val, Shamt) + Round_Bit;
   end Roundoff_Unsigned;

   ------------------
   -- Decode_VType --
   ------------------

   function Decode_VType (Encoded : Word) return VType_Record is
      Result : VType_Record;
      --  RVV 1.0: vtype[2:0]=vlmul, vtype[5:3]=vsew, vtype[6]=vta, vtype[7]=vma
      VSEW_Val : constant Natural := Natural (Shift_Right (Encoded, 3) and 7);
      VLMUL_Val : constant Natural := Natural (Encoded and 7);
   begin
      --  Check for illegal vtype (vill bit or reserved values)
      if (Encoded and 16#80000000#) /= 0 then
         Result.VILL := True;
         Result.VSEW := SEW_8;
         Result.VLMUL := LMUL_1;
         Result.VTA := False;
         Result.VMA := False;
         return Result;
      end if;

      --  Decode VSEW
      case VSEW_Val is
         when 0 => Result.VSEW := SEW_8;
         when 1 => Result.VSEW := SEW_16;
         when 2 => Result.VSEW := SEW_32;
         when 3 => Result.VSEW := SEW_64;
         when others =>
            Result.VILL := True;
            Result.VSEW := SEW_8;
            Result.VLMUL := LMUL_1;
            Result.VTA := False;
            Result.VMA := False;
            return Result;
      end case;

      --  Decode VLMUL
      case VLMUL_Val is
         when 0 => Result.VLMUL := LMUL_1;
         when 1 => Result.VLMUL := LMUL_2;
         when 2 => Result.VLMUL := LMUL_4;
         when 3 => Result.VLMUL := LMUL_8;
         when 5 => Result.VLMUL := LMUL_F8;
         when 6 => Result.VLMUL := LMUL_F4;
         when 7 => Result.VLMUL := LMUL_F2;
         when others =>
            Result.VILL := True;
            Result.VSEW := SEW_8;
            Result.VLMUL := LMUL_1;
            Result.VTA := False;
            Result.VMA := False;
            return Result;
      end case;

      Result.VTA := (Encoded and 64) /= 0;
      Result.VMA := (Encoded and 128) /= 0;
      Result.VILL := False;

      --  Check SEW <= ELEN
      if Get_SEW_Bits (Result.VSEW) > ELEN then
         Result.VILL := True;
      end if;

      return Result;
   end Decode_VType;

   ------------------
   -- Encode_VType --
   ------------------

   function Encode_VType (VT : VType_Record) return Word is
      Result : Word := 0;
   begin
      if VT.VILL then
         return 16#80000000#;
      end if;

      Result := Word (LMUL_Type'Pos (VT.VLMUL));
      Result := Result or Shift_Left (Word (SEW_Type'Pos (VT.VSEW)), 3);
      if VT.VTA then Result := Result or 64; end if;
      if VT.VMA then Result := Result or 128; end if;

      return Result;
   end Encode_VType;

   ----------------
   -- Get_VLMAX --
   ----------------

   function Get_VLMAX (SEW : SEW_Type; LMUL : LMUL_Type) return Natural is
      SEW_Bits : constant Natural := Get_SEW_Bits (SEW);
      Num, Den : Natural;
   begin
      Get_LMUL_Fraction (LMUL, Num, Den);
      return (VLEN * Num) / (SEW_Bits * Den);
   end Get_VLMAX;

   ------------------
   -- Get_SEW_Bits --
   ------------------

   function Get_SEW_Bits (SEW : SEW_Type) return Natural is
   begin
      case SEW is
         when SEW_8  => return 8;
         when SEW_16 => return 16;
         when SEW_32 => return 32;
         when SEW_64 => return 64;
      end case;
   end Get_SEW_Bits;

   ------------------------
   -- Get_LMUL_Fraction --
   ------------------------

   procedure Get_LMUL_Fraction (LMUL : LMUL_Type;
                                 Num  : out Natural;
                                 Den  : out Natural) is
   begin
      case LMUL is
         when LMUL_1  => Num := 1; Den := 1;
         when LMUL_2  => Num := 2; Den := 1;
         when LMUL_4  => Num := 4; Den := 1;
         when LMUL_8  => Num := 8; Den := 1;
         when LMUL_F8 => Num := 1; Den := 8;
         when LMUL_F4 => Num := 1; Den := 4;
         when LMUL_F2 => Num := 1; Den := 2;
      end case;
   end Get_LMUL_Fraction;

   ------------
   -- Vsetvl --
   ------------

   function Vsetvl (VU    : in out Vector_State;
                    AVL   : Word;
                    VType : Word) return Word is
      VT : constant VType_Record := Decode_VType (VType);
      VLMAX : Natural;
   begin
      VU.VType := VT;

      if VT.VILL then
         VU.VL := 0;
         return 0;
      end if;

      VLMAX := Get_VLMAX (VT.VSEW, VT.VLMUL);

      if AVL <= Word (VLMAX) then
         VU.VL := AVL;
      elsif AVL < Word (2 * VLMAX) then
         VU.VL := Word ((Natural (AVL) + 1) / 2);
      else
         VU.VL := Word (VLMAX);
      end if;

      VU.VStart := 0;
      return VU.VL;
   end Vsetvl;

   ------------------
   -- Read_Element --
   ------------------

   function Read_Element (VU    : Vector_State;
                          Reg   : Register_Index;
                          Index : Natural;
                          SEW   : SEW_Type) return Word is
      --  Number of elements that fit in one physical register for each SEW.
      EPR    : Natural;
      AR_Pos : Natural;   --  actual physical register index
      AR     : Register_Index;
      LI     : Natural;   --  local element index within AR
      Offset : Natural;
      Result : Word := 0;
   begin
      case SEW is
         when SEW_8 =>
            EPR    := VLENB;           --  16 bytes/reg
            AR_Pos := Natural (Reg) + Index / EPR;
            if AR_Pos > 31 then return 0; end if;
            AR     := Register_Index (AR_Pos);
            LI     := Index mod EPR;
            Result := Word (VU.Registers (AR).Data (LI));

         when SEW_16 =>
            EPR    := VLENB / 2;       --  8 halfwords/reg
            AR_Pos := Natural (Reg) + Index / EPR;
            if AR_Pos > 31 then return 0; end if;
            AR     := Register_Index (AR_Pos);
            LI     := Index mod EPR;
            Offset := LI * 2;
            Result := Word (VU.Registers (AR).Data (Offset)) or
                      Shift_Left (Word (VU.Registers (AR).Data (Offset + 1)), 8);

         when SEW_32 =>
            EPR    := VLENB / 4;       --  4 words/reg
            AR_Pos := Natural (Reg) + Index / EPR;
            if AR_Pos > 31 then return 0; end if;
            AR     := Register_Index (AR_Pos);
            LI     := Index mod EPR;
            Offset := LI * 4;
            Result := Word (VU.Registers (AR).Data (Offset)) or
                      Shift_Left (Word (VU.Registers (AR).Data (Offset + 1)), 8) or
                      Shift_Left (Word (VU.Registers (AR).Data (Offset + 2)), 16) or
                      Shift_Left (Word (VU.Registers (AR).Data (Offset + 3)), 24);

         when SEW_64 =>
            EPR    := VLENB / 8;       --  2 doublewords/reg
            AR_Pos := Natural (Reg) + Index / EPR;
            if AR_Pos > 31 then return 0; end if;
            AR     := Register_Index (AR_Pos);
            LI     := Index mod EPR;
            Offset := LI * 8;
            Result := Word (VU.Registers (AR).Data (Offset)) or
                      Shift_Left (Word (VU.Registers (AR).Data (Offset + 1)), 8) or
                      Shift_Left (Word (VU.Registers (AR).Data (Offset + 2)), 16) or
                      Shift_Left (Word (VU.Registers (AR).Data (Offset + 3)), 24);
      end case;

      return Result;
   end Read_Element;

   ---------------------
   -- Read_Element_64 --
   ---------------------

   function Read_Element_64 (VU    : Vector_State;
                             Reg   : Register_Index;
                             Index : Natural) return Unsigned_64 is
      EPR    : constant Natural := VLENB / 8;  --  2 doublewords/reg
      AR_Pos : constant Natural := Natural (Reg) + Index / EPR;
      AR     : Register_Index;
      LI     : constant Natural := Index mod EPR;
      Offset : constant Natural := LI * 8;
      Result : Unsigned_64 := 0;
   begin
      if AR_Pos > 31 then return 0; end if;
      AR := Register_Index (AR_Pos);
      for I in 0 .. 7 loop
         Result := Result or
           Shift_Left (Unsigned_64 (VU.Registers (AR).Data (Offset + I)),
                       I * 8);
      end loop;
      return Result;
   end Read_Element_64;

   -------------------
   -- Write_Element --
   -------------------

   procedure Write_Element (VU    : in out Vector_State;
                            Reg   : Register_Index;
                            Index : Natural;
                            SEW   : SEW_Type;
                            Value : Word) is
      EPR    : Natural;
      AR_Pos : Natural;
      AR     : Register_Index;
      LI     : Natural;
      Offset : Natural;
   begin
      case SEW is
         when SEW_8 =>
            EPR    := VLENB;
            AR_Pos := Natural (Reg) + Index / EPR;
            if AR_Pos > 31 then return; end if;
            AR := Register_Index (AR_Pos);
            LI := Index mod EPR;
            VU.Registers (AR).Data (LI) := Byte (Value and 16#FF#);

         when SEW_16 =>
            EPR    := VLENB / 2;
            AR_Pos := Natural (Reg) + Index / EPR;
            if AR_Pos > 31 then return; end if;
            AR     := Register_Index (AR_Pos);
            LI     := Index mod EPR;
            Offset := LI * 2;
            VU.Registers (AR).Data (Offset)     := Byte (Value and 16#FF#);
            VU.Registers (AR).Data (Offset + 1) :=
              Byte (Shift_Right (Value, 8) and 16#FF#);

         when SEW_32 =>
            EPR    := VLENB / 4;
            AR_Pos := Natural (Reg) + Index / EPR;
            if AR_Pos > 31 then return; end if;
            AR     := Register_Index (AR_Pos);
            LI     := Index mod EPR;
            Offset := LI * 4;
            VU.Registers (AR).Data (Offset)     := Byte (Value and 16#FF#);
            VU.Registers (AR).Data (Offset + 1) :=
              Byte (Shift_Right (Value, 8) and 16#FF#);
            VU.Registers (AR).Data (Offset + 2) :=
              Byte (Shift_Right (Value, 16) and 16#FF#);
            VU.Registers (AR).Data (Offset + 3) :=
              Byte (Shift_Right (Value, 24) and 16#FF#);

         when SEW_64 =>
            EPR    := VLENB / 8;
            AR_Pos := Natural (Reg) + Index / EPR;
            if AR_Pos > 31 then return; end if;
            AR     := Register_Index (AR_Pos);
            LI     := Index mod EPR;
            Offset := LI * 8;
            VU.Registers (AR).Data (Offset)     := Byte (Value and 16#FF#);
            VU.Registers (AR).Data (Offset + 1) :=
              Byte (Shift_Right (Value, 8) and 16#FF#);
            VU.Registers (AR).Data (Offset + 2) :=
              Byte (Shift_Right (Value, 16) and 16#FF#);
            VU.Registers (AR).Data (Offset + 3) :=
              Byte (Shift_Right (Value, 24) and 16#FF#);
      end case;
   end Write_Element;

   ----------------------
   -- Write_Element_64 --
   ----------------------

   procedure Write_Element_64 (VU    : in out Vector_State;
                               Reg   : Register_Index;
                               Index : Natural;
                               Value : Unsigned_64) is
      EPR    : constant Natural := VLENB / 8;
      AR_Pos : constant Natural := Natural (Reg) + Index / EPR;
      AR     : Register_Index;
      LI     : constant Natural := Index mod EPR;
      Offset : constant Natural := LI * 8;
   begin
      if AR_Pos > 31 then return; end if;
      AR := Register_Index (AR_Pos);
      for I in 0 .. 7 loop
         VU.Registers (AR).Data (Offset + I) :=
           Byte (Shift_Right (Value, I * 8) and 16#FF#);
      end loop;
   end Write_Element_64;

   --  =====================================================================
   --  SEW-aware 64-bit element helpers
   --
   --  The plain Read_Element/Write_Element carry a 32-bit Word, which is
   --  correct only when SEW=32 (and, for zero-extended low-result ops, at
   --  smaller SEW). These widen the datapath to 64 bits and extend from the
   --  *true* SEW boundary, so an op written against them is correct at
   --  SEW=8/16/32/64 -- signed operations included.
   --  =====================================================================

   --  Zero-extended element value.
   function VRead_U (VU    : Vector_State;
                     Reg   : Register_Index;
                     Index : Natural;
                     SEW   : SEW_Type) return Unsigned_64 is
   begin
      if SEW = SEW_64 then
         return Read_Element_64 (VU, Reg, Index);
      else
         return Unsigned_64 (Read_Element (VU, Reg, Index, SEW));
      end if;
   end VRead_U;

   --  Sign-extended element value (from bit SEW-1 up to 64 bits).
   function VRead_S (VU    : Vector_State;
                     Reg   : Register_Index;
                     Index : Natural;
                     SEW   : SEW_Type) return Integer_64 is
      U    : constant Unsigned_64 := VRead_U (VU, Reg, Index, SEW);
      Bits : constant Natural := Get_SEW_Bits (SEW);
   begin
      if Bits < 64
        and then (U and Shift_Left (Unsigned_64'(1), Bits - 1)) /= 0
      then
         --  set bit -> extend the sign across the high bits
         return To_I64 (U or not (Shift_Left (Unsigned_64'(1), Bits) - 1));
      else
         return To_I64 (U);
      end if;
   end VRead_S;

   --  Write the low SEW bits of Value into the element.
   procedure VWrite (VU    : in out Vector_State;
                     Reg   : Register_Index;
                     Index : Natural;
                     SEW   : SEW_Type;
                     Value : Unsigned_64) is
   begin
      if SEW = SEW_64 then
         Write_Element_64 (VU, Reg, Index, Value);
      else
         Write_Element (VU, Reg, Index, SEW,
                        Word (Value and 16#FFFF_FFFF#));
      end if;
   end VWrite;

   --  Sign-extend a 32-bit scalar (RV32 XLEN) to 64 bits. For SEW<64 the
   --  high bits are masked off by VWrite, so this is correct at every SEW.
   function Splat_U (Rs1 : Word) return Unsigned_64 is
   begin
      if (Rs1 and 16#8000_0000#) /= 0 then
         return Unsigned_64 (Rs1) or 16#FFFF_FFFF_0000_0000#;
      else
         return Unsigned_64 (Rs1);
      end if;
   end Splat_U;

   --  Arithmetic shift right of a value already sign-extended to 64 bits.
   function ASR64 (V : Unsigned_64; Shamt : Natural) return Unsigned_64 is
      R : Unsigned_64;
   begin
      if Shamt = 0 then
         return V;
      elsif Shamt >= 64 then
         return (if (V and 16#8000_0000_0000_0000#) /= 0
                 then 16#FFFF_FFFF_FFFF_FFFF# else 0);
      end if;
      R := Shift_Right (V, Shamt);
      if (V and 16#8000_0000_0000_0000#) /= 0 then
         R := R or not (Shift_Right (16#FFFF_FFFF_FFFF_FFFF#, Shamt));
      end if;
      return R;
   end ASR64;

   --  Unsigned 64x64 -> 128-bit product (Hi:Lo), schoolbook on 32-bit limbs.
   procedure UMul128 (A, B : Unsigned_64; Hi, Lo : out Unsigned_64) is
      A0 : constant Unsigned_64 := A and 16#FFFF_FFFF#;
      A1 : constant Unsigned_64 := Shift_Right (A, 32);
      B0 : constant Unsigned_64 := B and 16#FFFF_FFFF#;
      B1 : constant Unsigned_64 := Shift_Right (B, 32);
      P00 : constant Unsigned_64 := A0 * B0;
      P01 : constant Unsigned_64 := A0 * B1;
      P10 : constant Unsigned_64 := A1 * B0;
      P11 : constant Unsigned_64 := A1 * B1;
      Mid : constant Unsigned_64 :=
         Shift_Right (P00, 32) + (P01 and 16#FFFF_FFFF#) + (P10 and 16#FFFF_FFFF#);
   begin
      Lo := (P00 and 16#FFFF_FFFF#) or Shift_Left (Mid and 16#FFFF_FFFF#, 32);
      Hi := P11 + Shift_Right (P01, 32) + Shift_Right (P10, 32) + Shift_Right (Mid, 32);
   end UMul128;

   --  High 64 bits of a signed*signed 64-bit product.
   function SMulhi64 (A, B : Integer_64) return Unsigned_64 is
      Hi, Lo : Unsigned_64;
   begin
      UMul128 (To_U64 (A), To_U64 (B), Hi, Lo);
      --  Correct the unsigned high for the two sign terms.
      if A < 0 then Hi := Hi - To_U64 (B); end if;
      if B < 0 then Hi := Hi - To_U64 (A); end if;
      return Hi;
   end SMulhi64;

   --  High 64 bits of a signed*unsigned 64-bit product.
   function SUMulhi64 (A : Integer_64; B : Unsigned_64) return Unsigned_64 is
      Hi, Lo : Unsigned_64;
   begin
      UMul128 (To_U64 (A), B, Hi, Lo);
      if A < 0 then Hi := Hi - B; end if;
      return Hi;
   end SUMulhi64;

   --  Signed convenience wrapper for VWrite.
   procedure VWrite_S (VU    : in out Vector_State;
                       Reg   : Register_Index;
                       Index : Natural;
                       SEW   : SEW_Type;
                       Value : Integer_64) is
   begin
      VWrite (VU, Reg, Index, SEW, To_U64 (Value));
   end VWrite_S;

   ------------------
   -- Get_Mask_Bit --
   ------------------

   function Get_Mask_Bit (VU    : Vector_State;
                          Index : Natural) return Boolean is
      Byte_Idx : constant Natural := Index / 8;
      Bit_Idx  : constant Natural := Index mod 8;
   begin
      if Byte_Idx < VLENB then
         return (VU.Registers (0).Data (Byte_Idx) and
                 Byte (Shift_Left (Word (1), Bit_Idx))) /= 0;
      end if;
      return False;
   end Get_Mask_Bit;

   ------------------
   -- Set_Mask_Bit --
   ------------------

   procedure Set_Mask_Bit (VU    : in out Vector_State;
                           Reg   : Register_Index;
                           Index : Natural;
                           Value : Boolean) is
      Byte_Idx : constant Natural := Index / 8;
      Bit_Idx  : constant Natural := Index mod 8;
      Mask     : constant Byte := Byte (Shift_Left (Word (1), Bit_Idx));
   begin
      if Byte_Idx < VLENB then
         if Value then
            VU.Registers (Reg).Data (Byte_Idx) :=
              VU.Registers (Reg).Data (Byte_Idx) or Mask;
         else
            VU.Registers (Reg).Data (Byte_Idx) :=
              VU.Registers (Reg).Data (Byte_Idx) and (not Mask);
         end if;
      end if;
   end Set_Mask_Bit;

   ------------------------------
   -- Vector_Load_Unit_Stride --
   ------------------------------

   procedure Vector_Load_Unit_Stride
     (VU      : in out Vector_State;
      Mem     : in out Memory.Memory_Unit;
      Vd      : Register_Index;
      Rs1     : Word;
      VM      : Boolean;
      EEW     : SEW_Type)
   is
      Addr : Word := Rs1;
      EEW_Bytes : constant Natural := Get_SEW_Bits (EEW) / 8;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            case EEW is
               when SEW_8 =>
                  Write_Element (VU, Vd, I, EEW,
                    Word (Memory.Read_Byte (Mem, Memory_Address (Addr))));
               when SEW_16 =>
                  Write_Element (VU, Vd, I, EEW,
                    Word (Memory.Read_Half_Word (Mem, Memory_Address (Addr))));
               when SEW_32 =>
                  Write_Element (VU, Vd, I, EEW,
                    Memory.Read_Word (Mem, Memory_Address (Addr)));
               when SEW_64 =>
                  declare
                     Lo : constant Word := Memory.Read_Word (Mem, Memory_Address (Addr));
                     Hi : constant Word := Memory.Read_Word (Mem, Memory_Address (Addr + 4));
                  begin
                     Write_Element_64 (VU, Vd, I,
                       Unsigned_64 (Lo) or Shift_Left (Unsigned_64 (Hi), 32));
                  end;
            end case;
         end if;
         Addr := Addr + Word (EEW_Bytes);
      end loop;
      VU.VStart := 0;
   end Vector_Load_Unit_Stride;

   -------------------------------
   -- Vector_Store_Unit_Stride --
   -------------------------------

   procedure Vector_Store_Unit_Stride
     (VU      : in out Vector_State;
      Mem     : in out Memory.Memory_Unit;
      Vs3     : Register_Index;
      Rs1     : Word;
      VM      : Boolean;
      EEW     : SEW_Type)
   is
      Addr : Word := Rs1;
      EEW_Bytes : constant Natural := Get_SEW_Bits (EEW) / 8;
      Val : Word;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            Val := Read_Element (VU, Vs3, I, EEW);
            case EEW is
               when SEW_8 =>
                  Memory.Write_Byte (Mem, Memory_Address (Addr), Byte (Val and 16#FF#));
               when SEW_16 =>
                  Memory.Write_Half_Word (Mem, Memory_Address (Addr),
                    Half_Word (Val and 16#FFFF#));
               when SEW_32 =>
                  Memory.Write_Word (Mem, Memory_Address (Addr), Val);
               when SEW_64 =>
                  declare
                     Val64 : constant Unsigned_64 := Read_Element_64 (VU, Vs3, I);
                  begin
                     Memory.Write_Word (Mem, Memory_Address (Addr),
                       Word (Val64 and 16#FFFFFFFF#));
                     Memory.Write_Word (Mem, Memory_Address (Addr + 4),
                       Word (Shift_Right (Val64, 32)));
                  end;
            end case;
         end if;
         Addr := Addr + Word (EEW_Bytes);
      end loop;
      VU.VStart := 0;
   end Vector_Store_Unit_Stride;

   --------------------------
   -- Vector_Load_Strided --
   --------------------------

   procedure Vector_Load_Strided
     (VU      : in out Vector_State;
      Mem     : in out Memory.Memory_Unit;
      Vd      : Register_Index;
      Rs1     : Word;
      Rs2     : Word;
      VM      : Boolean;
      EEW     : SEW_Type)
   is
      Addr : Word;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         Addr := Rs1 + Word (I) * Rs2;
         if VM or else Get_Mask_Bit (VU, I) then
            case EEW is
               when SEW_8 =>
                  Write_Element (VU, Vd, I, EEW,
                    Word (Memory.Read_Byte (Mem, Memory_Address (Addr))));
               when SEW_16 =>
                  Write_Element (VU, Vd, I, EEW,
                    Word (Memory.Read_Half_Word (Mem, Memory_Address (Addr))));
               when SEW_32 =>
                  Write_Element (VU, Vd, I, EEW,
                    Memory.Read_Word (Mem, Memory_Address (Addr)));
               when SEW_64 =>
                  declare
                     Lo : constant Word := Memory.Read_Word (Mem, Memory_Address (Addr));
                     Hi : constant Word := Memory.Read_Word (Mem, Memory_Address (Addr + 4));
                  begin
                     Write_Element_64 (VU, Vd, I,
                       Unsigned_64 (Lo) or Shift_Left (Unsigned_64 (Hi), 32));
                  end;
            end case;
         end if;
      end loop;
      VU.VStart := 0;
   end Vector_Load_Strided;

   ---------------------------
   -- Vector_Store_Strided --
   ---------------------------

   procedure Vector_Store_Strided
     (VU      : in out Vector_State;
      Mem     : in out Memory.Memory_Unit;
      Vs3     : Register_Index;
      Rs1     : Word;
      Rs2     : Word;
      VM      : Boolean;
      EEW     : SEW_Type)
   is
      Addr : Word;
      Val : Word;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         Addr := Rs1 + Word (I) * Rs2;
         if VM or else Get_Mask_Bit (VU, I) then
            Val := Read_Element (VU, Vs3, I, EEW);
            case EEW is
               when SEW_8 =>
                  Memory.Write_Byte (Mem, Memory_Address (Addr), Byte (Val and 16#FF#));
               when SEW_16 =>
                  Memory.Write_Half_Word (Mem, Memory_Address (Addr),
                    Half_Word (Val and 16#FFFF#));
               when SEW_32 =>
                  Memory.Write_Word (Mem, Memory_Address (Addr), Val);
               when SEW_64 =>
                  declare
                     Val64 : constant Unsigned_64 := Read_Element_64 (VU, Vs3, I);
                  begin
                     Memory.Write_Word (Mem, Memory_Address (Addr),
                       Word (Val64 and 16#FFFFFFFF#));
                     Memory.Write_Word (Mem, Memory_Address (Addr + 4),
                       Word (Shift_Right (Val64, 32)));
                  end;
            end case;
         end if;
      end loop;
      VU.VStart := 0;
   end Vector_Store_Strided;

   ----------------------------
   -- Load_Mem / Store_Mem helpers
   ----------------------------

   procedure Load_Mem_Element
     (VU   : in out Vector_State;
      Mem  : in out Memory.Memory_Unit;
      Reg  : Register_Index;
      Idx  : Natural;
      Addr : Word;
      EEW  : SEW_Type) is
   begin
      case EEW is
         when SEW_8 =>
            Write_Element (VU, Reg, Idx, EEW,
              Word (Memory.Read_Byte (Mem, Memory_Address (Addr))));
         when SEW_16 =>
            Write_Element (VU, Reg, Idx, EEW,
              Word (Memory.Read_Half_Word (Mem, Memory_Address (Addr))));
         when SEW_32 =>
            Write_Element (VU, Reg, Idx, EEW,
              Memory.Read_Word (Mem, Memory_Address (Addr)));
         when SEW_64 =>
            declare
               Lo : constant Word := Memory.Read_Word (Mem, Memory_Address (Addr));
               Hi : constant Word := Memory.Read_Word (Mem, Memory_Address (Addr + 4));
            begin
               Write_Element_64 (VU, Reg, Idx,
                 Unsigned_64 (Lo) or Shift_Left (Unsigned_64 (Hi), 32));
            end;
      end case;
   end Load_Mem_Element;

   procedure Store_Mem_Element
     (VU   : Vector_State;
      Mem  : in out Memory.Memory_Unit;
      Reg  : Register_Index;
      Idx  : Natural;
      Addr : Word;
      EEW  : SEW_Type)
   is
      Val : Word;
   begin
      Val := Read_Element (VU, Reg, Idx, EEW);
      case EEW is
         when SEW_8 =>
            Memory.Write_Byte (Mem, Memory_Address (Addr), Byte (Val and 16#FF#));
         when SEW_16 =>
            Memory.Write_Half_Word (Mem, Memory_Address (Addr),
              Half_Word (Val and 16#FFFF#));
         when SEW_32 =>
            Memory.Write_Word (Mem, Memory_Address (Addr), Val);
         when SEW_64 =>
            declare
               Val64 : constant Unsigned_64 := Read_Element_64 (VU, Reg, Idx);
            begin
               Memory.Write_Word (Mem, Memory_Address (Addr),
                 Word (Val64 and 16#FFFFFFFF#));
               Memory.Write_Word (Mem, Memory_Address (Addr + 4),
                 Word (Shift_Right (Val64, 32)));
            end;
      end case;
   end Store_Mem_Element;

   ----------------------------
   -- Vector_Load_Indexed --
   ----------------------------

   procedure Vector_Load_Indexed
     (VU        : in out Vector_State;
      Mem       : in out Memory.Memory_Unit;
      Vd        : Register_Index;
      Rs1       : Word;
      Vs2_Reg   : Register_Index;
      VM        : Boolean;
      Data_EEW  : SEW_Type;
      Index_EEW : SEW_Type)
   is
      Offset : Word;
      Addr   : Word;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            Offset := Read_Element (VU, Vs2_Reg, I, Index_EEW);
            Addr := Rs1 + Offset;
            Load_Mem_Element (VU, Mem, Vd, I, Addr, Data_EEW);
         end if;
      end loop;
      VU.VStart := 0;
   end Vector_Load_Indexed;

   -----------------------------
   -- Vector_Store_Indexed --
   -----------------------------

   procedure Vector_Store_Indexed
     (VU        : in out Vector_State;
      Mem       : in out Memory.Memory_Unit;
      Vs3       : Register_Index;
      Rs1       : Word;
      Vs2_Reg   : Register_Index;
      VM        : Boolean;
      Data_EEW  : SEW_Type;
      Index_EEW : SEW_Type)
   is
      Offset : Word;
      Addr   : Word;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            Offset := Read_Element (VU, Vs2_Reg, I, Index_EEW);
            Addr := Rs1 + Offset;
            Store_Mem_Element (VU, Mem, Vs3, I, Addr, Data_EEW);
         end if;
      end loop;
      VU.VStart := 0;
   end Vector_Store_Indexed;

   ----------------------------------
   -- Vector_Load_Segment_Unit --
   ----------------------------------

   procedure Vector_Load_Segment_Unit
     (VU      : in out Vector_State;
      Mem     : in out Memory.Memory_Unit;
      Vd      : Register_Index;
      Rs1     : Word;
      VM      : Boolean;
      EEW     : SEW_Type;
      Nf      : Positive)
   is
      EEW_Bytes : constant Word := Word (Get_SEW_Bits (EEW) / 8);
      Addr      : Word;
      Dest_Reg  : Register_Index;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            for F in 0 .. Nf loop
               Addr := Rs1 + Word (I) * Word (Nf + 1) * EEW_Bytes
                            + Word (F) * EEW_Bytes;
               Dest_Reg := Register_Index
                 ((Natural (Vd) + F) mod 32);
               Load_Mem_Element (VU, Mem, Dest_Reg, I, Addr, EEW);
            end loop;
         end if;
      end loop;
      VU.VStart := 0;
   end Vector_Load_Segment_Unit;

   -----------------------------------
   -- Vector_Store_Segment_Unit --
   -----------------------------------

   procedure Vector_Store_Segment_Unit
     (VU      : in out Vector_State;
      Mem     : in out Memory.Memory_Unit;
      Vs3     : Register_Index;
      Rs1     : Word;
      VM      : Boolean;
      EEW     : SEW_Type;
      Nf      : Positive)
   is
      EEW_Bytes : constant Word := Word (Get_SEW_Bits (EEW) / 8);
      Addr      : Word;
      Src_Reg   : Register_Index;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            for F in 0 .. Nf loop
               Addr := Rs1 + Word (I) * Word (Nf + 1) * EEW_Bytes
                            + Word (F) * EEW_Bytes;
               Src_Reg := Register_Index
                 ((Natural (Vs3) + F) mod 32);
               Store_Mem_Element (VU, Mem, Src_Reg, I, Addr, EEW);
            end loop;
         end if;
      end loop;
      VU.VStart := 0;
   end Vector_Store_Segment_Unit;

   -------------------------------------
   -- Vector_Load_Segment_Strided --
   -------------------------------------

   procedure Vector_Load_Segment_Strided
     (VU      : in out Vector_State;
      Mem     : in out Memory.Memory_Unit;
      Vd      : Register_Index;
      Rs1     : Word;
      Rs2     : Word;
      VM      : Boolean;
      EEW     : SEW_Type;
      Nf      : Positive)
   is
      EEW_Bytes : constant Word := Word (Get_SEW_Bits (EEW) / 8);
      Base_Addr : Word;
      Addr      : Word;
      Dest_Reg  : Register_Index;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         Base_Addr := Rs1 + Word (I) * Rs2;
         if VM or else Get_Mask_Bit (VU, I) then
            for F in 0 .. Nf loop
               Addr := Base_Addr + Word (F) * EEW_Bytes;
               Dest_Reg := Register_Index
                 ((Natural (Vd) + F) mod 32);
               Load_Mem_Element (VU, Mem, Dest_Reg, I, Addr, EEW);
            end loop;
         end if;
      end loop;
      VU.VStart := 0;
   end Vector_Load_Segment_Strided;

   --------------------------------------
   -- Vector_Store_Segment_Strided --
   --------------------------------------

   procedure Vector_Store_Segment_Strided
     (VU      : in out Vector_State;
      Mem     : in out Memory.Memory_Unit;
      Vs3     : Register_Index;
      Rs1     : Word;
      Rs2     : Word;
      VM      : Boolean;
      EEW     : SEW_Type;
      Nf      : Positive)
   is
      EEW_Bytes : constant Word := Word (Get_SEW_Bits (EEW) / 8);
      Base_Addr : Word;
      Addr      : Word;
      Src_Reg   : Register_Index;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         Base_Addr := Rs1 + Word (I) * Rs2;
         if VM or else Get_Mask_Bit (VU, I) then
            for F in 0 .. Nf loop
               Addr := Base_Addr + Word (F) * EEW_Bytes;
               Src_Reg := Register_Index
                 ((Natural (Vs3) + F) mod 32);
               Store_Mem_Element (VU, Mem, Src_Reg, I, Addr, EEW);
            end loop;
         end if;
      end loop;
      VU.VStart := 0;
   end Vector_Store_Segment_Strided;

   -------------------------------------
   -- Vector_Load_Segment_Indexed --
   -------------------------------------

   procedure Vector_Load_Segment_Indexed
     (VU        : in out Vector_State;
      Mem       : in out Memory.Memory_Unit;
      Vd        : Register_Index;
      Rs1       : Word;
      Vs2_Reg   : Register_Index;
      VM        : Boolean;
      Data_EEW  : SEW_Type;
      Index_EEW : SEW_Type;
      Nf        : Positive)
   is
      Data_Bytes : constant Word := Word (Get_SEW_Bits (Data_EEW) / 8);
      Base_Addr  : Word;
      Addr       : Word;
      Dest_Reg   : Register_Index;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            Base_Addr := Rs1 + Read_Element (VU, Vs2_Reg, I, Index_EEW);
            for F in 0 .. Nf loop
               Addr := Base_Addr + Word (F) * Data_Bytes;
               Dest_Reg := Register_Index
                 ((Natural (Vd) + F) mod 32);
               Load_Mem_Element (VU, Mem, Dest_Reg, I, Addr, Data_EEW);
            end loop;
         end if;
      end loop;
      VU.VStart := 0;
   end Vector_Load_Segment_Indexed;

   --------------------------------------
   -- Vector_Store_Segment_Indexed --
   --------------------------------------

   procedure Vector_Store_Segment_Indexed
     (VU        : in out Vector_State;
      Mem       : in out Memory.Memory_Unit;
      Vs3       : Register_Index;
      Rs1       : Word;
      Vs2_Reg   : Register_Index;
      VM        : Boolean;
      Data_EEW  : SEW_Type;
      Index_EEW : SEW_Type;
      Nf        : Positive)
   is
      Data_Bytes : constant Word := Word (Get_SEW_Bits (Data_EEW) / 8);
      Base_Addr  : Word;
      Addr       : Word;
      Src_Reg    : Register_Index;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            Base_Addr := Rs1 + Read_Element (VU, Vs2_Reg, I, Index_EEW);
            for F in 0 .. Nf loop
               Addr := Base_Addr + Word (F) * Data_Bytes;
               Src_Reg := Register_Index
                 ((Natural (Vs3) + F) mod 32);
               Store_Mem_Element (VU, Mem, Src_Reg, I, Addr, Data_EEW);
            end loop;
         end if;
      end loop;
      VU.VStart := 0;
   end Vector_Store_Segment_Indexed;

   ------------------------------------
   -- Vector_Load_Whole_Register --
   ------------------------------------

   procedure Vector_Load_Whole_Register
     (VU      : in out Vector_State;
      Mem     : in out Memory.Memory_Unit;
      Vd      : Register_Index;
      Rs1     : Word;
      NReg    : Positive)
   is
      Addr    : Word := Rs1;
      Reg     : Register_Index;
   begin
      for R in 0 .. NReg - 1 loop
         Reg := Register_Index ((Natural (Vd) + R) mod 32);
         for B in 0 .. VLENB - 1 loop
            VU.Registers (Reg).Data (B) :=
              Memory.Read_Byte (Mem, Memory_Address (Addr));
            Addr := Addr + 1;
         end loop;
      end loop;
      VU.VStart := 0;
   end Vector_Load_Whole_Register;

   -------------------------------------
   -- Vector_Store_Whole_Register --
   -------------------------------------

   procedure Vector_Store_Whole_Register
     (VU      : in out Vector_State;
      Mem     : in out Memory.Memory_Unit;
      Vs3     : Register_Index;
      Rs1     : Word;
      NReg    : Positive)
   is
      Addr    : Word := Rs1;
      Reg     : Register_Index;
   begin
      for R in 0 .. NReg - 1 loop
         Reg := Register_Index ((Natural (Vs3) + R) mod 32);
         for B in 0 .. VLENB - 1 loop
            Memory.Write_Byte (Mem, Memory_Address (Addr),
              VU.Registers (Reg).Data (B));
            Addr := Addr + 1;
         end loop;
      end loop;
      VU.VStart := 0;
   end Vector_Store_Whole_Register;

   -------------
   -- VADD_VV --
   -------------

   procedure VADD_VV (VU : in out Vector_State;
                      Vd, Vs2, Vs1 : Register_Index;
                      VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            VWrite (VU, Vd, I, SEW, VRead_U (VU, Vs2, I, SEW) + VRead_U (VU, Vs1, I, SEW));
         end if;
      end loop;
      VU.VStart := 0;
   end VADD_VV;

   -------------
   -- VADD_VX --
   -------------

   procedure VADD_VX (VU : in out Vector_State;
                      Vd, Vs2 : Register_Index;
                      Rs1 : Word;
                      VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            VWrite (VU, Vd, I, SEW, VRead_U (VU, Vs2, I, SEW) + Splat_U (Rs1));
         end if;
      end loop;
      VU.VStart := 0;
   end VADD_VX;

   -------------
   -- VADD_VI --
   -------------

   procedure VADD_VI (VU : in out Vector_State;
                      Vd, Vs2 : Register_Index;
                      Imm : Signed_Word;
                      VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            VWrite (VU, Vd, I, SEW, VRead_U (VU, Vs2, I, SEW) + To_U64 (Integer_64 (Imm)));
         end if;
      end loop;
      VU.VStart := 0;
   end VADD_VI;

   -------------
   -- VSUB_VV --
   -------------

   procedure VSUB_VV (VU : in out Vector_State;
                      Vd, Vs2, Vs1 : Register_Index;
                      VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            VWrite (VU, Vd, I, SEW, VRead_U (VU, Vs2, I, SEW) - VRead_U (VU, Vs1, I, SEW));
         end if;
      end loop;
      VU.VStart := 0;
   end VSUB_VV;

   -------------
   -- VSUB_VX --
   -------------

   procedure VSUB_VX (VU : in out Vector_State;
                      Vd, Vs2 : Register_Index;
                      Rs1 : Word;
                      VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            VWrite (VU, Vd, I, SEW, VRead_U (VU, Vs2, I, SEW) - Splat_U (Rs1));
         end if;
      end loop;
      VU.VStart := 0;
   end VSUB_VX;

   --------------
   -- VRSUB_VX --
   --------------

   procedure VRSUB_VX (VU : in out Vector_State;
                       Vd, Vs2 : Register_Index;
                       Rs1 : Word;
                       VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            VWrite (VU, Vd, I, SEW, Splat_U (Rs1) - VRead_U (VU, Vs2, I, SEW));
         end if;
      end loop;
      VU.VStart := 0;
   end VRSUB_VX;

   --------------
   -- VRSUB_VI --
   --------------

   procedure VRSUB_VI (VU : in out Vector_State;
                       Vd, Vs2 : Register_Index;
                       Imm : Signed_Word;
                       VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            VWrite (VU, Vd, I, SEW, To_U64 (Integer_64 (Imm)) - VRead_U (VU, Vs2, I, SEW));
         end if;
      end loop;
      VU.VStart := 0;
   end VRSUB_VI;

   -------------
   -- VAND_VV --
   -------------

   procedure VAND_VV (VU : in out Vector_State;
                      Vd, Vs2, Vs1 : Register_Index;
                      VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            VWrite (VU, Vd, I, SEW, VRead_U (VU, Vs2, I, SEW) and VRead_U (VU, Vs1, I, SEW));
         end if;
      end loop;
      VU.VStart := 0;
   end VAND_VV;

   -------------
   -- VAND_VX --
   -------------

   procedure VAND_VX (VU : in out Vector_State;
                      Vd, Vs2 : Register_Index;
                      Rs1 : Word;
                      VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            VWrite (VU, Vd, I, SEW, VRead_U (VU, Vs2, I, SEW) and Splat_U (Rs1));
         end if;
      end loop;
      VU.VStart := 0;
   end VAND_VX;

   -------------
   -- VAND_VI --
   -------------

   procedure VAND_VI (VU : in out Vector_State;
                      Vd, Vs2 : Register_Index;
                      Imm : Signed_Word;
                      VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            VWrite (VU, Vd, I, SEW, VRead_U (VU, Vs2, I, SEW) and To_U64 (Integer_64 (Imm)));
         end if;
      end loop;
      VU.VStart := 0;
   end VAND_VI;

   ------------
   -- VOR_VV --
   ------------

   procedure VOR_VV (VU : in out Vector_State;
                     Vd, Vs2, Vs1 : Register_Index;
                     VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            VWrite (VU, Vd, I, SEW, VRead_U (VU, Vs2, I, SEW) or VRead_U (VU, Vs1, I, SEW));
         end if;
      end loop;
      VU.VStart := 0;
   end VOR_VV;

   ------------
   -- VOR_VX --
   ------------

   procedure VOR_VX (VU : in out Vector_State;
                     Vd, Vs2 : Register_Index;
                     Rs1 : Word;
                     VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            VWrite (VU, Vd, I, SEW, VRead_U (VU, Vs2, I, SEW) or Splat_U (Rs1));
         end if;
      end loop;
      VU.VStart := 0;
   end VOR_VX;

   ------------
   -- VOR_VI --
   ------------

   procedure VOR_VI (VU : in out Vector_State;
                     Vd, Vs2 : Register_Index;
                     Imm : Signed_Word;
                     VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            VWrite (VU, Vd, I, SEW, VRead_U (VU, Vs2, I, SEW) or To_U64 (Integer_64 (Imm)));
         end if;
      end loop;
      VU.VStart := 0;
   end VOR_VI;

   -------------
   -- VXOR_VV --
   -------------

   procedure VXOR_VV (VU : in out Vector_State;
                      Vd, Vs2, Vs1 : Register_Index;
                      VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            VWrite (VU, Vd, I, SEW, VRead_U (VU, Vs2, I, SEW) xor VRead_U (VU, Vs1, I, SEW));
         end if;
      end loop;
      VU.VStart := 0;
   end VXOR_VV;

   -------------
   -- VXOR_VX --
   -------------

   procedure VXOR_VX (VU : in out Vector_State;
                      Vd, Vs2 : Register_Index;
                      Rs1 : Word;
                      VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            VWrite (VU, Vd, I, SEW, VRead_U (VU, Vs2, I, SEW) xor Splat_U (Rs1));
         end if;
      end loop;
      VU.VStart := 0;
   end VXOR_VX;

   -------------
   -- VXOR_VI --
   -------------

   procedure VXOR_VI (VU : in out Vector_State;
                      Vd, Vs2 : Register_Index;
                      Imm : Signed_Word;
                      VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            VWrite (VU, Vd, I, SEW, VRead_U (VU, Vs2, I, SEW) xor To_U64 (Integer_64 (Imm)));
         end if;
      end loop;
      VU.VStart := 0;
   end VXOR_VI;

   -------------
   -- VSLL_VV --
   -------------

   procedure VSLL_VV (VU : in out Vector_State;
                      Vd, Vs2, Vs1 : Register_Index;
                      VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               Shamt : constant Natural := Natural (VRead_U (VU, Vs1, I, SEW) and Unsigned_64 (Get_SEW_Bits (SEW) - 1));
            begin
               VWrite (VU, Vd, I, SEW, Shift_Left (VRead_U (VU, Vs2, I, SEW), Shamt));
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VSLL_VV;

   -------------
   -- VSLL_VX --
   -------------

   procedure VSLL_VX (VU : in out Vector_State;
                      Vd, Vs2 : Register_Index;
                      Rs1 : Word;
                      VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               Shamt : constant Natural := Natural (Splat_U (Rs1) and Unsigned_64 (Get_SEW_Bits (SEW) - 1));
            begin
               VWrite (VU, Vd, I, SEW, Shift_Left (VRead_U (VU, Vs2, I, SEW), Shamt));
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VSLL_VX;

   -------------
   -- VSLL_VI --
   -------------

   procedure VSLL_VI (VU : in out Vector_State;
                      Vd, Vs2 : Register_Index;
                      Imm : Natural;
                      VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               Shamt : constant Natural := Imm mod Get_SEW_Bits (SEW);
            begin
               VWrite (VU, Vd, I, SEW, Shift_Left (VRead_U (VU, Vs2, I, SEW), Shamt));
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VSLL_VI;

   -------------
   -- VSRL_VV --
   -------------

   procedure VSRL_VV (VU : in out Vector_State;
                      Vd, Vs2, Vs1 : Register_Index;
                      VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               Shamt : constant Natural := Natural (VRead_U (VU, Vs1, I, SEW) and Unsigned_64 (Get_SEW_Bits (SEW) - 1));
            begin
               VWrite (VU, Vd, I, SEW, Shift_Right (VRead_U (VU, Vs2, I, SEW), Shamt));
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VSRL_VV;

   -------------
   -- VSRL_VX --
   -------------

   procedure VSRL_VX (VU : in out Vector_State;
                      Vd, Vs2 : Register_Index;
                      Rs1 : Word;
                      VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               Shamt : constant Natural := Natural (Splat_U (Rs1) and Unsigned_64 (Get_SEW_Bits (SEW) - 1));
            begin
               VWrite (VU, Vd, I, SEW, Shift_Right (VRead_U (VU, Vs2, I, SEW), Shamt));
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VSRL_VX;

   -------------
   -- VSRL_VI --
   -------------

   procedure VSRL_VI (VU : in out Vector_State;
                      Vd, Vs2 : Register_Index;
                      Imm : Natural;
                      VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               Shamt : constant Natural := Imm mod Get_SEW_Bits (SEW);
            begin
               VWrite (VU, Vd, I, SEW, Shift_Right (VRead_U (VU, Vs2, I, SEW), Shamt));
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VSRL_VI;

   -------------
   -- VSRA_VV --
   -------------

   procedure VSRA_VV (VU : in out Vector_State;
                      Vd, Vs2, Vs1 : Register_Index;
                      VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               Shamt : constant Natural := Natural (VRead_U (VU, Vs1, I, SEW) and Unsigned_64 (Get_SEW_Bits (SEW) - 1));
            begin
               VWrite (VU, Vd, I, SEW, ASR64 (To_U64 (VRead_S (VU, Vs2, I, SEW)), Shamt));
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VSRA_VV;

   -------------
   -- VSRA_VX --
   -------------

   procedure VSRA_VX (VU : in out Vector_State;
                      Vd, Vs2 : Register_Index;
                      Rs1 : Word;
                      VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               Shamt : constant Natural := Natural (Splat_U (Rs1) and Unsigned_64 (Get_SEW_Bits (SEW) - 1));
            begin
               VWrite (VU, Vd, I, SEW, ASR64 (To_U64 (VRead_S (VU, Vs2, I, SEW)), Shamt));
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VSRA_VX;

   -------------
   -- VSRA_VI --
   -------------

   procedure VSRA_VI (VU : in out Vector_State;
                      Vd, Vs2 : Register_Index;
                      Imm : Natural;
                      VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               Shamt : constant Natural := Imm mod Get_SEW_Bits (SEW);
            begin
               VWrite (VU, Vd, I, SEW, ASR64 (To_U64 (VRead_S (VU, Vs2, I, SEW)), Shamt));
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VSRA_VI;

   --------------
   -- VMINU_VV --
   --------------

   procedure VMINU_VV (VU : in out Vector_State;
                       Vd, Vs2, Vs1 : Register_Index;
                       VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               A : constant Unsigned_64 := VRead_U (VU, Vs2, I, SEW);
               B : constant Unsigned_64 := VRead_U (VU, Vs1, I, SEW);
            begin
               VWrite (VU, Vd, I, SEW, (if A < B then A else B));
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VMINU_VV;

   --------------
   -- VMINU_VX --
   --------------

   procedure VMINU_VX (VU : in out Vector_State;
                       Vd, Vs2 : Register_Index;
                       Rs1 : Word;
                       VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               A : constant Unsigned_64 := VRead_U (VU, Vs2, I, SEW);
               B : constant Unsigned_64 := Splat_U (Rs1);
            begin
               VWrite (VU, Vd, I, SEW, (if A < B then A else B));
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VMINU_VX;

   -------------
   -- VMIN_VV --
   -------------

   procedure VMIN_VV (VU : in out Vector_State;
                      Vd, Vs2, Vs1 : Register_Index;
                      VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               A : constant Integer_64 := VRead_S (VU, Vs2, I, SEW);
               B : constant Integer_64 := VRead_S (VU, Vs1, I, SEW);
            begin
               VWrite_S (VU, Vd, I, SEW, (if A < B then A else B));
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VMIN_VV;

   -------------
   -- VMIN_VX --
   -------------

   procedure VMIN_VX (VU : in out Vector_State;
                      Vd, Vs2 : Register_Index;
                      Rs1 : Word;
                      VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               A : constant Integer_64 := VRead_S (VU, Vs2, I, SEW);
               B : constant Integer_64 := To_I64 (Splat_U (Rs1));
            begin
               VWrite_S (VU, Vd, I, SEW, (if A < B then A else B));
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VMIN_VX;

   --------------
   -- VMAXU_VV --
   --------------

   procedure VMAXU_VV (VU : in out Vector_State;
                       Vd, Vs2, Vs1 : Register_Index;
                       VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               A : constant Unsigned_64 := VRead_U (VU, Vs2, I, SEW);
               B : constant Unsigned_64 := VRead_U (VU, Vs1, I, SEW);
            begin
               VWrite (VU, Vd, I, SEW, (if A > B then A else B));
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VMAXU_VV;

   --------------
   -- VMAXU_VX --
   --------------

   procedure VMAXU_VX (VU : in out Vector_State;
                       Vd, Vs2 : Register_Index;
                       Rs1 : Word;
                       VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               A : constant Unsigned_64 := VRead_U (VU, Vs2, I, SEW);
               B : constant Unsigned_64 := Splat_U (Rs1);
            begin
               VWrite (VU, Vd, I, SEW, (if A > B then A else B));
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VMAXU_VX;

   -------------
   -- VMAX_VV --
   -------------

   procedure VMAX_VV (VU : in out Vector_State;
                      Vd, Vs2, Vs1 : Register_Index;
                      VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               A : constant Integer_64 := VRead_S (VU, Vs2, I, SEW);
               B : constant Integer_64 := VRead_S (VU, Vs1, I, SEW);
            begin
               VWrite_S (VU, Vd, I, SEW, (if A > B then A else B));
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VMAX_VV;

   -------------
   -- VMAX_VX --
   -------------

   procedure VMAX_VX (VU : in out Vector_State;
                      Vd, Vs2 : Register_Index;
                      Rs1 : Word;
                      VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               A : constant Integer_64 := VRead_S (VU, Vs2, I, SEW);
               B : constant Integer_64 := To_I64 (Splat_U (Rs1));
            begin
               VWrite_S (VU, Vd, I, SEW, (if A > B then A else B));
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VMAX_VX;

   --  Comparison and merge operations

   procedure VMSEQ_VV (VU : in out Vector_State; Vd, Vs2, Vs1 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            Set_Mask_Bit (VU, Vd, I, VRead_U (VU, Vs2, I, SEW) = VRead_U (VU, Vs1, I, SEW));
         end if;
      end loop;
      VU.VStart := 0;
   end VMSEQ_VV;

   procedure VMSEQ_VX (VU : in out Vector_State; Vd, Vs2 : Register_Index; Rs1 : Word; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            Set_Mask_Bit (VU, Vd, I, VRead_U (VU, Vs2, I, SEW) = Splat_U (Rs1));
         end if;
      end loop;
      VU.VStart := 0;
   end VMSEQ_VX;

   procedure VMSEQ_VI (VU : in out Vector_State; Vd, Vs2 : Register_Index; Imm : Signed_Word; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            Set_Mask_Bit (VU, Vd, I, VRead_U (VU, Vs2, I, SEW) = To_U64 (Integer_64 (Imm)));
         end if;
      end loop;
      VU.VStart := 0;
   end VMSEQ_VI;

   procedure VMSNE_VV (VU : in out Vector_State; Vd, Vs2, Vs1 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            Set_Mask_Bit (VU, Vd, I, VRead_U (VU, Vs2, I, SEW) /= VRead_U (VU, Vs1, I, SEW));
         end if;
      end loop;
      VU.VStart := 0;
   end VMSNE_VV;

   procedure VMSNE_VX (VU : in out Vector_State; Vd, Vs2 : Register_Index; Rs1 : Word; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            Set_Mask_Bit (VU, Vd, I, VRead_U (VU, Vs2, I, SEW) /= Splat_U (Rs1));
         end if;
      end loop;
      VU.VStart := 0;
   end VMSNE_VX;

   procedure VMSNE_VI (VU : in out Vector_State; Vd, Vs2 : Register_Index; Imm : Signed_Word; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            Set_Mask_Bit (VU, Vd, I, VRead_U (VU, Vs2, I, SEW) /= To_U64 (Integer_64 (Imm)));
         end if;
      end loop;
      VU.VStart := 0;
   end VMSNE_VI;

   procedure VMSLTU_VV (VU : in out Vector_State; Vd, Vs2, Vs1 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            Set_Mask_Bit (VU, Vd, I, VRead_U (VU, Vs2, I, SEW) < VRead_U (VU, Vs1, I, SEW));
         end if;
      end loop;
      VU.VStart := 0;
   end VMSLTU_VV;

   procedure VMSLTU_VX (VU : in out Vector_State; Vd, Vs2 : Register_Index; Rs1 : Word; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            Set_Mask_Bit (VU, Vd, I, VRead_U (VU, Vs2, I, SEW) < Splat_U (Rs1));
         end if;
      end loop;
      VU.VStart := 0;
   end VMSLTU_VX;

   procedure VMSLT_VV (VU : in out Vector_State; Vd, Vs2, Vs1 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            Set_Mask_Bit (VU, Vd, I, VRead_S (VU, Vs2, I, SEW) < VRead_S (VU, Vs1, I, SEW));
         end if;
      end loop;
      VU.VStart := 0;
   end VMSLT_VV;

   procedure VMSLT_VX (VU : in out Vector_State; Vd, Vs2 : Register_Index; Rs1 : Word; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            Set_Mask_Bit (VU, Vd, I, VRead_S (VU, Vs2, I, SEW) < To_I64 (Splat_U (Rs1)));
         end if;
      end loop;
      VU.VStart := 0;
   end VMSLT_VX;

   procedure VMSLEU_VV (VU : in out Vector_State; Vd, Vs2, Vs1 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            Set_Mask_Bit (VU, Vd, I, VRead_U (VU, Vs2, I, SEW) <= VRead_U (VU, Vs1, I, SEW));
         end if;
      end loop;
      VU.VStart := 0;
   end VMSLEU_VV;

   procedure VMSLEU_VX (VU : in out Vector_State; Vd, Vs2 : Register_Index; Rs1 : Word; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            Set_Mask_Bit (VU, Vd, I, VRead_U (VU, Vs2, I, SEW) <= Splat_U (Rs1));
         end if;
      end loop;
      VU.VStart := 0;
   end VMSLEU_VX;

   procedure VMSLEU_VI (VU : in out Vector_State; Vd, Vs2 : Register_Index; Imm : Signed_Word; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            Set_Mask_Bit (VU, Vd, I, VRead_U (VU, Vs2, I, SEW) <= To_U64 (Integer_64 (Imm)));
         end if;
      end loop;
      VU.VStart := 0;
   end VMSLEU_VI;

   procedure VMSLE_VV (VU : in out Vector_State; Vd, Vs2, Vs1 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            Set_Mask_Bit (VU, Vd, I, VRead_S (VU, Vs2, I, SEW) <= VRead_S (VU, Vs1, I, SEW));
         end if;
      end loop;
      VU.VStart := 0;
   end VMSLE_VV;

   procedure VMSLE_VX (VU : in out Vector_State; Vd, Vs2 : Register_Index; Rs1 : Word; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            Set_Mask_Bit (VU, Vd, I, VRead_S (VU, Vs2, I, SEW) <= To_I64 (Splat_U (Rs1)));
         end if;
      end loop;
      VU.VStart := 0;
   end VMSLE_VX;

   procedure VMSLE_VI (VU : in out Vector_State; Vd, Vs2 : Register_Index; Imm : Signed_Word; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            Set_Mask_Bit (VU, Vd, I, VRead_S (VU, Vs2, I, SEW) <= Integer_64 (Imm));
         end if;
      end loop;
      VU.VStart := 0;
   end VMSLE_VI;

   procedure VMSGTU_VX (VU : in out Vector_State; Vd, Vs2 : Register_Index; Rs1 : Word; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            Set_Mask_Bit (VU, Vd, I, VRead_U (VU, Vs2, I, SEW) > Splat_U (Rs1));
         end if;
      end loop;
      VU.VStart := 0;
   end VMSGTU_VX;

   procedure VMSGTU_VI (VU : in out Vector_State; Vd, Vs2 : Register_Index; Imm : Signed_Word; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            Set_Mask_Bit (VU, Vd, I, VRead_U (VU, Vs2, I, SEW) > To_U64 (Integer_64 (Imm)));
         end if;
      end loop;
      VU.VStart := 0;
   end VMSGTU_VI;

   procedure VMSGT_VX (VU : in out Vector_State; Vd, Vs2 : Register_Index; Rs1 : Word; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            Set_Mask_Bit (VU, Vd, I, VRead_S (VU, Vs2, I, SEW) > To_I64 (Splat_U (Rs1)));
         end if;
      end loop;
      VU.VStart := 0;
   end VMSGT_VX;

   procedure VMSGT_VI (VU : in out Vector_State; Vd, Vs2 : Register_Index; Imm : Signed_Word; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            Set_Mask_Bit (VU, Vd, I, VRead_S (VU, Vs2, I, SEW) > Integer_64 (Imm));
         end if;
      end loop;
      VU.VStart := 0;
   end VMSGT_VI;

   --  Multiply/Divide operations
   procedure VMUL_VV (VU : in out Vector_State; Vd, Vs2, Vs1 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            VWrite (VU, Vd, I, SEW, VRead_U (VU, Vs2, I, SEW) * VRead_U (VU, Vs1, I, SEW));
         end if;
      end loop;
      VU.VStart := 0;
   end VMUL_VV;

   procedure VMUL_VX (VU : in out Vector_State; Vd, Vs2 : Register_Index; Rs1 : Word; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            VWrite (VU, Vd, I, SEW, VRead_U (VU, Vs2, I, SEW) * Splat_U (Rs1));
         end if;
      end loop;
      VU.VStart := 0;
   end VMUL_VX;

   procedure VMULH_VV (VU : in out Vector_State; Vd, Vs2, Vs1 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               A : constant Integer_64 := VRead_S (VU, Vs2, I, SEW);
               B : constant Integer_64 := VRead_S (VU, Vs1, I, SEW);
            begin
               if SEW = SEW_64 then
                  VWrite (VU, Vd, I, SEW, SMulhi64 (A, B));
               else
                  VWrite (VU, Vd, I, SEW,
                    Shift_Right (To_U64 (A * B), Get_SEW_Bits (SEW)));
               end if;
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VMULH_VV;

   procedure VMULH_VX (VU : in out Vector_State; Vd, Vs2 : Register_Index; Rs1 : Word; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               A : constant Integer_64 := VRead_S (VU, Vs2, I, SEW);
               B : constant Integer_64 := To_I64 (Splat_U (Rs1));
            begin
               if SEW = SEW_64 then
                  VWrite (VU, Vd, I, SEW, SMulhi64 (A, B));
               else
                  VWrite (VU, Vd, I, SEW,
                    Shift_Right (To_U64 (A * B), Get_SEW_Bits (SEW)));
               end if;
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VMULH_VX;

   procedure VMULHU_VV (VU : in out Vector_State; Vd, Vs2, Vs1 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               A : constant Unsigned_64 := VRead_U (VU, Vs2, I, SEW);
               B : constant Unsigned_64 := VRead_U (VU, Vs1, I, SEW);
               Hi, Lo : Unsigned_64;
            begin
               if SEW = SEW_64 then
                  UMul128 (A, B, Hi, Lo);
                  VWrite (VU, Vd, I, SEW, Hi);
               else
                  VWrite (VU, Vd, I, SEW,
                    Shift_Right (A * B, Get_SEW_Bits (SEW)));
               end if;
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VMULHU_VV;

   procedure VMULHU_VX (VU : in out Vector_State; Vd, Vs2 : Register_Index; Rs1 : Word; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               A : constant Unsigned_64 := VRead_U (VU, Vs2, I, SEW);
               B : constant Unsigned_64 := Splat_U (Rs1);
               Hi, Lo : Unsigned_64;
            begin
               if SEW = SEW_64 then
                  UMul128 (A, B, Hi, Lo);
                  VWrite (VU, Vd, I, SEW, Hi);
               else
                  VWrite (VU, Vd, I, SEW,
                    Shift_Right (A * B, Get_SEW_Bits (SEW)));
               end if;
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VMULHU_VX;

   procedure VDIVU_VV (VU : in out Vector_State; Vd, Vs2, Vs1 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               A : constant Unsigned_64 := VRead_U (VU, Vs2, I, SEW);
               B : constant Unsigned_64 := VRead_U (VU, Vs1, I, SEW);
            begin
               if B = 0 then
                  VWrite (VU, Vd, I, SEW, 16#FFFF_FFFF_FFFF_FFFF#);
               else
                  VWrite (VU, Vd, I, SEW, A / B);
               end if;
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VDIVU_VV;

   procedure VDIVU_VX (VU : in out Vector_State; Vd, Vs2 : Register_Index; Rs1 : Word; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               A : constant Unsigned_64 := VRead_U (VU, Vs2, I, SEW);
               B : constant Unsigned_64 := Splat_U (Rs1);
            begin
               if B = 0 then
                  VWrite (VU, Vd, I, SEW, 16#FFFF_FFFF_FFFF_FFFF#);
               else
                  VWrite (VU, Vd, I, SEW, A / B);
               end if;
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VDIVU_VX;

   procedure VDIV_VV (VU : in out Vector_State; Vd, Vs2, Vs1 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               A : constant Integer_64 := VRead_S (VU, Vs2, I, SEW);
               B : constant Integer_64 := VRead_S (VU, Vs1, I, SEW);
            begin
               if B = 0 then
                  VWrite (VU, Vd, I, SEW, 16#FFFF_FFFF_FFFF_FFFF#);
               elsif SEW = SEW_64 and then A = Integer_64'First and then B = -1 then
                  VWrite_S (VU, Vd, I, SEW, A);
               else
                  VWrite_S (VU, Vd, I, SEW, A / B);
               end if;
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VDIV_VV;

   procedure VDIV_VX (VU : in out Vector_State; Vd, Vs2 : Register_Index; Rs1 : Word; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               A : constant Integer_64 := VRead_S (VU, Vs2, I, SEW);
               B : constant Integer_64 := To_I64 (Splat_U (Rs1));
            begin
               if B = 0 then
                  VWrite (VU, Vd, I, SEW, 16#FFFF_FFFF_FFFF_FFFF#);
               elsif SEW = SEW_64 and then A = Integer_64'First and then B = -1 then
                  VWrite_S (VU, Vd, I, SEW, A);
               else
                  VWrite_S (VU, Vd, I, SEW, A / B);
               end if;
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VDIV_VX;

   procedure VREMU_VV (VU : in out Vector_State; Vd, Vs2, Vs1 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               A : constant Unsigned_64 := VRead_U (VU, Vs2, I, SEW);
               B : constant Unsigned_64 := VRead_U (VU, Vs1, I, SEW);
            begin
               if B = 0 then
                  VWrite (VU, Vd, I, SEW, A);
               else
                  VWrite (VU, Vd, I, SEW, A mod B);
               end if;
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VREMU_VV;

   procedure VREMU_VX (VU : in out Vector_State; Vd, Vs2 : Register_Index; Rs1 : Word; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               A : constant Unsigned_64 := VRead_U (VU, Vs2, I, SEW);
               B : constant Unsigned_64 := Splat_U (Rs1);
            begin
               if B = 0 then
                  VWrite (VU, Vd, I, SEW, A);
               else
                  VWrite (VU, Vd, I, SEW, A mod B);
               end if;
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VREMU_VX;

   procedure VREM_VV (VU : in out Vector_State; Vd, Vs2, Vs1 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               A : constant Integer_64 := VRead_S (VU, Vs2, I, SEW);
               B : constant Integer_64 := VRead_S (VU, Vs1, I, SEW);
            begin
               if B = 0 then
                  VWrite_S (VU, Vd, I, SEW, A);
               elsif SEW = SEW_64 and then A = Integer_64'First and then B = -1 then
                  VWrite (VU, Vd, I, SEW, 0);
               else
                  VWrite_S (VU, Vd, I, SEW, A rem B);
               end if;
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VREM_VV;

   procedure VREM_VX (VU : in out Vector_State; Vd, Vs2 : Register_Index; Rs1 : Word; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               A : constant Integer_64 := VRead_S (VU, Vs2, I, SEW);
               B : constant Integer_64 := To_I64 (Splat_U (Rs1));
            begin
               if B = 0 then
                  VWrite_S (VU, Vd, I, SEW, A);
               elsif SEW = SEW_64 and then A = Integer_64'First and then B = -1 then
                  VWrite (VU, Vd, I, SEW, 0);
               else
                  VWrite_S (VU, Vd, I, SEW, A rem B);
               end if;
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VREM_VX;

   ---------------------
   -- Slide operations
   ---------------------

   procedure VSLIDEUP_VX (VU : in out Vector_State;
                          Vd, Vs2 : Register_Index;
                          Rs1 : Word; VM : Boolean) is
      SEW    : constant SEW_Type := VU.VType.VSEW;
      Offset : constant Natural := Natural (Rs1);
      Src_Idx : Natural;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if I >= Offset then
               Src_Idx := I - Offset;
               Write_Element (VU, Vd, I, SEW,
                 Read_Element (VU, Vs2, Src_Idx, SEW));
            end if;
            --  Elements below offset keep their old value in vd
         end if;
      end loop;
      VU.VStart := 0;
   end VSLIDEUP_VX;

   procedure VSLIDEUP_VI (VU : in out Vector_State;
                          Vd, Vs2 : Register_Index;
                          Imm : Natural; VM : Boolean) is
   begin
      VSLIDEUP_VX (VU, Vd, Vs2, Word (Imm), VM);
   end VSLIDEUP_VI;

   procedure VSLIDEDOWN_VX (VU : in out Vector_State;
                            Vd, Vs2 : Register_Index;
                            Rs1 : Word; VM : Boolean) is
      SEW     : constant SEW_Type := VU.VType.VSEW;
      Offset  : constant Natural := Natural (Rs1);
      Src_Idx : Natural;
      VLMAX   : constant Natural := Get_VLMAX (SEW, VU.VType.VLMUL);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            Src_Idx := I + Offset;
            if Src_Idx < VLMAX then
               Write_Element (VU, Vd, I, SEW,
                 Read_Element (VU, Vs2, Src_Idx, SEW));
            else
               Write_Element (VU, Vd, I, SEW, 0);
            end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VSLIDEDOWN_VX;

   procedure VSLIDEDOWN_VI (VU : in out Vector_State;
                            Vd, Vs2 : Register_Index;
                            Imm : Natural; VM : Boolean) is
   begin
      VSLIDEDOWN_VX (VU, Vd, Vs2, Word (Imm), VM);
   end VSLIDEDOWN_VI;

   procedure VSLIDE1UP_VX (VU : in out Vector_State;
                           Vd, Vs2 : Register_Index;
                           Rs1 : Word; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if I = 0 then
               Write_Element (VU, Vd, 0, SEW, Rs1);
            else
               Write_Element (VU, Vd, I, SEW,
                 Read_Element (VU, Vs2, I - 1, SEW));
            end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VSLIDE1UP_VX;

   procedure VSLIDE1DOWN_VX (VU : in out Vector_State;
                             Vd, Vs2 : Register_Index;
                             Rs1 : Word; VM : Boolean) is
      SEW   : constant SEW_Type := VU.VType.VSEW;
      VL_N  : constant Natural := Natural (VU.VL);
   begin
      for I in Natural (VU.VStart) .. VL_N - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if I = VL_N - 1 then
               Write_Element (VU, Vd, I, SEW, Rs1);
            else
               Write_Element (VU, Vd, I, SEW,
                 Read_Element (VU, Vs2, I + 1, SEW));
            end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VSLIDE1DOWN_VX;

   ----------------------
   -- Gather operations
   ----------------------

   procedure VRGATHER_VV (VU : in out Vector_State;
                          Vd, Vs2, Vs1 : Register_Index;
                          VM : Boolean) is
      SEW   : constant SEW_Type := VU.VType.VSEW;
      VLMAX : constant Natural := Get_VLMAX (SEW, VU.VType.VLMUL);
      Idx   : Natural;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            Idx := Natural (Read_Element (VU, Vs1, I, SEW));
            if Idx < VLMAX then
               Write_Element (VU, Vd, I, SEW,
                 Read_Element (VU, Vs2, Idx, SEW));
            else
               Write_Element (VU, Vd, I, SEW, 0);
            end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VRGATHER_VV;

   procedure VRGATHER_VX (VU : in out Vector_State;
                          Vd, Vs2 : Register_Index;
                          Rs1 : Word; VM : Boolean) is
      SEW   : constant SEW_Type := VU.VType.VSEW;
      VLMAX : constant Natural := Get_VLMAX (SEW, VU.VType.VLMUL);
      Idx   : constant Natural := Natural (Rs1);
      Val   : Word;
   begin
      if Idx < VLMAX then
         Val := Read_Element (VU, Vs2, Idx, SEW);
      else
         Val := 0;
      end if;
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            Write_Element (VU, Vd, I, SEW, Val);
         end if;
      end loop;
      VU.VStart := 0;
   end VRGATHER_VX;

   procedure VRGATHER_VI (VU : in out Vector_State;
                          Vd, Vs2 : Register_Index;
                          Imm : Natural; VM : Boolean) is
   begin
      VRGATHER_VX (VU, Vd, Vs2, Word (Imm), VM);
   end VRGATHER_VI;

   procedure VRGATHEREI16_VV (VU : in out Vector_State;
                              Vd, Vs2, Vs1 : Register_Index;
                              VM : Boolean) is
      SEW   : constant SEW_Type := VU.VType.VSEW;
      VLMAX : constant Natural := Get_VLMAX (SEW, VU.VType.VLMUL);
      Idx   : Natural;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            --  Index is always 16-bit from vs1
            Idx := Natural (Read_Element (VU, Vs1, I, SEW_16));
            if Idx < VLMAX then
               Write_Element (VU, Vd, I, SEW,
                 Read_Element (VU, Vs2, Idx, SEW));
            else
               Write_Element (VU, Vd, I, SEW, 0);
            end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VRGATHEREI16_VV;

   ---------------
   -- Compress
   ---------------

   procedure VCOMPRESS_VM (VU : in out Vector_State;
                           Vd, Vs2, Vs1 : Register_Index) is
      SEW    : constant SEW_Type := VU.VType.VSEW;
      Dest_I : Natural := 0;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         --  vs1 is the mask source (read mask bit from vs1 register)
         declare
            Byte_Idx : constant Natural := I / 8;
            Bit_Idx  : constant Natural := I mod 8;
            Mask_Set : constant Boolean :=
              Byte_Idx < VLENB and then
              (VU.Registers (Vs1).Data (Byte_Idx) and
               Byte (Shift_Left (Word (1), Bit_Idx))) /= 0;
         begin
            if Mask_Set then
               Write_Element (VU, Vd, Dest_I, SEW,
                 Read_Element (VU, Vs2, I, SEW));
               Dest_I := Dest_I + 1;
            end if;
         end;
      end loop;
      VU.VStart := 0;
   end VCOMPRESS_VM;

   ---------------------------
   -- Integer multiply-add
   ---------------------------

   --  vmacc.vv: vd[i] = (vs1[i] * vs2[i]) + vd[i]
   procedure VMACC_VV (VU : in out Vector_State;
                       Vd, Vs1, Vs2 : Register_Index;
                       VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      A, B, D : Word;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            A := Read_Element (VU, Vs1, I, SEW);
            B := Read_Element (VU, Vs2, I, SEW);
            D := Read_Element (VU, Vd, I, SEW);
            Write_Element (VU, Vd, I, SEW, A * B + D);
         end if;
      end loop;
      VU.VStart := 0;
   end VMACC_VV;

   --  vmacc.vx: vd[i] = (rs1 * vs2[i]) + vd[i]
   procedure VMACC_VX (VU : in out Vector_State;
                       Vd : Register_Index; Rs1 : Word;
                       Vs2 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      B, D : Word;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            B := Read_Element (VU, Vs2, I, SEW);
            D := Read_Element (VU, Vd, I, SEW);
            Write_Element (VU, Vd, I, SEW, Rs1 * B + D);
         end if;
      end loop;
      VU.VStart := 0;
   end VMACC_VX;

   --  vnmsac.vv: vd[i] = -(vs1[i] * vs2[i]) + vd[i]
   procedure VNMSAC_VV (VU : in out Vector_State;
                        Vd, Vs1, Vs2 : Register_Index;
                        VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      A, B, D : Word;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            A := Read_Element (VU, Vs1, I, SEW);
            B := Read_Element (VU, Vs2, I, SEW);
            D := Read_Element (VU, Vd, I, SEW);
            Write_Element (VU, Vd, I, SEW, D - A * B);
         end if;
      end loop;
      VU.VStart := 0;
   end VNMSAC_VV;

   procedure VNMSAC_VX (VU : in out Vector_State;
                        Vd : Register_Index; Rs1 : Word;
                        Vs2 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      B, D : Word;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            B := Read_Element (VU, Vs2, I, SEW);
            D := Read_Element (VU, Vd, I, SEW);
            Write_Element (VU, Vd, I, SEW, D - Rs1 * B);
         end if;
      end loop;
      VU.VStart := 0;
   end VNMSAC_VX;

   --  vmadd.vv: vd[i] = (vs1[i] * vd[i]) + vs2[i]
   procedure VMADD_VV (VU : in out Vector_State;
                       Vd, Vs1, Vs2 : Register_Index;
                       VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      A, B, D : Word;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            A := Read_Element (VU, Vs1, I, SEW);
            B := Read_Element (VU, Vs2, I, SEW);
            D := Read_Element (VU, Vd, I, SEW);
            Write_Element (VU, Vd, I, SEW, A * D + B);
         end if;
      end loop;
      VU.VStart := 0;
   end VMADD_VV;

   procedure VMADD_VX (VU : in out Vector_State;
                       Vd : Register_Index; Rs1 : Word;
                       Vs2 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      B, D : Word;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            B := Read_Element (VU, Vs2, I, SEW);
            D := Read_Element (VU, Vd, I, SEW);
            Write_Element (VU, Vd, I, SEW, Rs1 * D + B);
         end if;
      end loop;
      VU.VStart := 0;
   end VMADD_VX;

   --  vnmsub.vv: vd[i] = -(vs1[i] * vd[i]) + vs2[i]
   procedure VNMSUB_VV (VU : in out Vector_State;
                        Vd, Vs1, Vs2 : Register_Index;
                        VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      A, B, D : Word;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            A := Read_Element (VU, Vs1, I, SEW);
            B := Read_Element (VU, Vs2, I, SEW);
            D := Read_Element (VU, Vd, I, SEW);
            Write_Element (VU, Vd, I, SEW, B - A * D);
         end if;
      end loop;
      VU.VStart := 0;
   end VNMSUB_VV;

   procedure VNMSUB_VX (VU : in out Vector_State;
                        Vd : Register_Index; Rs1 : Word;
                        Vs2 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      B, D : Word;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            B := Read_Element (VU, Vs2, I, SEW);
            D := Read_Element (VU, Vd, I, SEW);
            Write_Element (VU, Vd, I, SEW, B - Rs1 * D);
         end if;
      end loop;
      VU.VStart := 0;
   end VNMSUB_VX;

   ---------------------------
   -- Integer extension
   ---------------------------

   --  Helper: get source SEW for a given fractional extension
   function Half_SEW (SEW : SEW_Type) return SEW_Type is
   begin
      case SEW is
         when SEW_16 => return SEW_8;
         when SEW_32 => return SEW_16;
         when SEW_64 => return SEW_32;
         when SEW_8  => return SEW_8;  -- invalid but safe
      end case;
   end Half_SEW;

   function Quarter_SEW (SEW : SEW_Type) return SEW_Type is
   begin
      case SEW is
         when SEW_32 => return SEW_8;
         when SEW_64 => return SEW_16;
         when others => return SEW_8;  -- invalid but safe
      end case;
   end Quarter_SEW;

   procedure VZEXT_VF2 (VU : in out Vector_State;
                        Vd, Vs2 : Register_Index;
                        VM : Boolean) is
      SEW     : constant SEW_Type := VU.VType.VSEW;
      Src_SEW : constant SEW_Type := Half_SEW (SEW);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            Write_Element (VU, Vd, I, SEW,
              Read_Element (VU, Vs2, I, Src_SEW));
         end if;
      end loop;
      VU.VStart := 0;
   end VZEXT_VF2;

   procedure VZEXT_VF4 (VU : in out Vector_State;
                        Vd, Vs2 : Register_Index;
                        VM : Boolean) is
      SEW     : constant SEW_Type := VU.VType.VSEW;
      Src_SEW : constant SEW_Type := Quarter_SEW (SEW);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            Write_Element (VU, Vd, I, SEW,
              Read_Element (VU, Vs2, I, Src_SEW));
         end if;
      end loop;
      VU.VStart := 0;
   end VZEXT_VF4;

   procedure VZEXT_VF8 (VU : in out Vector_State;
                        Vd, Vs2 : Register_Index;
                        VM : Boolean) is
   begin
      --  Only valid for SEW=64, source is SEW_8
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            Write_Element (VU, Vd, I, VU.VType.VSEW,
              Read_Element (VU, Vs2, I, SEW_8));
         end if;
      end loop;
      VU.VStart := 0;
   end VZEXT_VF8;

   procedure VSEXT_VF2 (VU : in out Vector_State;
                        Vd, Vs2 : Register_Index;
                        VM : Boolean) is
      SEW     : constant SEW_Type := VU.VType.VSEW;
      Src_SEW : constant SEW_Type := Half_SEW (SEW);
      Val     : Word;
      Src_Bits : constant Natural := Get_SEW_Bits (Src_SEW);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            Val := Read_Element (VU, Vs2, I, Src_SEW);
            --  Sign extend
            if (Val and Shift_Left (1, Src_Bits - 1)) /= 0 then
               Val := Val or not (Shift_Left (1, Src_Bits) - 1);
            end if;
            Write_Element (VU, Vd, I, SEW, Val);
         end if;
      end loop;
      VU.VStart := 0;
   end VSEXT_VF2;

   procedure VSEXT_VF4 (VU : in out Vector_State;
                        Vd, Vs2 : Register_Index;
                        VM : Boolean) is
      SEW      : constant SEW_Type := VU.VType.VSEW;
      Src_SEW  : constant SEW_Type := Quarter_SEW (SEW);
      Val      : Word;
      Src_Bits : constant Natural := Get_SEW_Bits (Src_SEW);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            Val := Read_Element (VU, Vs2, I, Src_SEW);
            if (Val and Shift_Left (1, Src_Bits - 1)) /= 0 then
               Val := Val or not (Shift_Left (1, Src_Bits) - 1);
            end if;
            Write_Element (VU, Vd, I, SEW, Val);
         end if;
      end loop;
      VU.VStart := 0;
   end VSEXT_VF4;

   procedure VSEXT_VF8 (VU : in out Vector_State;
                        Vd, Vs2 : Register_Index;
                        VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      Val : Word;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            Val := Read_Element (VU, Vs2, I, SEW_8);
            if (Val and 16#80#) /= 0 then
               Val := Val or 16#FFFFFF00#;
            end if;
            Write_Element (VU, Vd, I, SEW, Val);
         end if;
      end loop;
      VU.VStart := 0;
   end VSEXT_VF8;

   -- Merge/Move operations
   procedure VMERGE_VVM (VU : in out Vector_State; Vd, Vs2, Vs1 : Register_Index) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if Get_Mask_Bit (VU, I) then
            Write_Element (VU, Vd, I, SEW, Read_Element (VU, Vs1, I, SEW));
         else
            Write_Element (VU, Vd, I, SEW, Read_Element (VU, Vs2, I, SEW));
         end if;
      end loop;
      VU.VStart := 0;
   end VMERGE_VVM;

   procedure VMERGE_VXM (VU : in out Vector_State; Vd, Vs2 : Register_Index; Rs1 : Word) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if Get_Mask_Bit (VU, I) then
            Write_Element (VU, Vd, I, SEW, Rs1);
         else
            Write_Element (VU, Vd, I, SEW, Read_Element (VU, Vs2, I, SEW));
         end if;
      end loop;
      VU.VStart := 0;
   end VMERGE_VXM;

   procedure VMERGE_VIM (VU : in out Vector_State; Vd, Vs2 : Register_Index; Imm : Signed_Word) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if Get_Mask_Bit (VU, I) then
            Write_Element (VU, Vd, I, SEW, To_Word (Imm));
         else
            Write_Element (VU, Vd, I, SEW, Read_Element (VU, Vs2, I, SEW));
         end if;
      end loop;
      VU.VStart := 0;
   end VMERGE_VIM;

   procedure VMV_V_V (VU : in out Vector_State; Vd, Vs1 : Register_Index) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         Write_Element (VU, Vd, I, SEW, Read_Element (VU, Vs1, I, SEW));
      end loop;
      VU.VStart := 0;
   end VMV_V_V;

   procedure VMV_V_X (VU : in out Vector_State; Vd : Register_Index; Rs1 : Word) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         Write_Element (VU, Vd, I, SEW, Rs1);
      end loop;
      VU.VStart := 0;
   end VMV_V_X;

   procedure VMV_V_I (VU : in out Vector_State; Vd : Register_Index; Imm : Signed_Word) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         Write_Element (VU, Vd, I, SEW, To_Word (Imm));
      end loop;
      VU.VStart := 0;
   end VMV_V_I;

   function VMV_X_S (VU : Vector_State; Vs2 : Register_Index) return Word is
   begin
      return Read_Element (VU, Vs2, 0, VU.VType.VSEW);
   end VMV_X_S;

   procedure VMV_S_X (VU : in out Vector_State; Vd : Register_Index; Rs1 : Word) is
   begin
      if VU.VL > 0 then
         Write_Element (VU, Vd, 0, VU.VType.VSEW, Rs1);
      end if;
   end VMV_S_X;

   -- Reduction operations
   function VREDSUM_VS (VU : in out Vector_State; Vs2, Vs1 : Register_Index; VM : Boolean) return Word is
      SEW : constant SEW_Type := VU.VType.VSEW;
      Acc : Word := Read_Element (VU, Vs1, 0, SEW);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            Acc := Acc + Read_Element (VU, Vs2, I, SEW);
         end if;
      end loop;
      VU.VStart := 0;
      return Acc;
   end VREDSUM_VS;

   function VREDMAXU_VS (VU : in out Vector_State; Vs2, Vs1 : Register_Index; VM : Boolean) return Word is
      SEW : constant SEW_Type := VU.VType.VSEW;
      Acc : Word := Read_Element (VU, Vs1, 0, SEW);
      Val : Word;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            Val := Read_Element (VU, Vs2, I, SEW);
            if Val > Acc then Acc := Val; end if;
         end if;
      end loop;
      VU.VStart := 0;
      return Acc;
   end VREDMAXU_VS;

   function VREDMAX_VS (VU : in out Vector_State; Vs2, Vs1 : Register_Index; VM : Boolean) return Word is
      SEW : constant SEW_Type := VU.VType.VSEW;
      Acc : Signed_Word := To_Signed (Read_Element (VU, Vs1, 0, SEW));
      Val : Signed_Word;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            Val := To_Signed (Read_Element (VU, Vs2, I, SEW));
            if Val > Acc then Acc := Val; end if;
         end if;
      end loop;
      VU.VStart := 0;
      return To_Word (Acc);
   end VREDMAX_VS;

   function VREDMINU_VS (VU : in out Vector_State; Vs2, Vs1 : Register_Index; VM : Boolean) return Word is
      SEW : constant SEW_Type := VU.VType.VSEW;
      Acc : Word := Read_Element (VU, Vs1, 0, SEW);
      Val : Word;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            Val := Read_Element (VU, Vs2, I, SEW);
            if Val < Acc then Acc := Val; end if;
         end if;
      end loop;
      VU.VStart := 0;
      return Acc;
   end VREDMINU_VS;

   function VREDMIN_VS (VU : in out Vector_State; Vs2, Vs1 : Register_Index; VM : Boolean) return Word is
      SEW : constant SEW_Type := VU.VType.VSEW;
      Acc : Signed_Word := To_Signed (Read_Element (VU, Vs1, 0, SEW));
      Val : Signed_Word;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            Val := To_Signed (Read_Element (VU, Vs2, I, SEW));
            if Val < Acc then Acc := Val; end if;
         end if;
      end loop;
      VU.VStart := 0;
      return To_Word (Acc);
   end VREDMIN_VS;

   function VREDAND_VS (VU : in out Vector_State; Vs2, Vs1 : Register_Index; VM : Boolean) return Word is
      SEW : constant SEW_Type := VU.VType.VSEW;
      Acc : Word := Read_Element (VU, Vs1, 0, SEW);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            Acc := Acc and Read_Element (VU, Vs2, I, SEW);
         end if;
      end loop;
      VU.VStart := 0;
      return Acc;
   end VREDAND_VS;

   function VREDOR_VS (VU : in out Vector_State; Vs2, Vs1 : Register_Index; VM : Boolean) return Word is
      SEW : constant SEW_Type := VU.VType.VSEW;
      Acc : Word := Read_Element (VU, Vs1, 0, SEW);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            Acc := Acc or Read_Element (VU, Vs2, I, SEW);
         end if;
      end loop;
      VU.VStart := 0;
      return Acc;
   end VREDOR_VS;

   function VREDXOR_VS (VU : in out Vector_State; Vs2, Vs1 : Register_Index; VM : Boolean) return Word is
      SEW : constant SEW_Type := VU.VType.VSEW;
      Acc : Word := Read_Element (VU, Vs1, 0, SEW);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            Acc := Acc xor Read_Element (VU, Vs2, I, SEW);
         end if;
      end loop;
      VU.VStart := 0;
      return Acc;
   end VREDXOR_VS;

   -- Mask-to-mask operations
   procedure VMAND_MM (VU : in out Vector_State; Vd, Vs2, Vs1 : Register_Index) is
   begin
      for I in 0 .. VLENB - 1 loop
         VU.Registers (Vd).Data (I) :=
           VU.Registers (Vs2).Data (I) and VU.Registers (Vs1).Data (I);
      end loop;
   end VMAND_MM;

   procedure VMNAND_MM (VU : in out Vector_State; Vd, Vs2, Vs1 : Register_Index) is
   begin
      for I in 0 .. VLENB - 1 loop
         VU.Registers (Vd).Data (I) :=
           not (VU.Registers (Vs2).Data (I) and VU.Registers (Vs1).Data (I));
      end loop;
   end VMNAND_MM;

   procedure VMANDNOT_MM (VU : in out Vector_State; Vd, Vs2, Vs1 : Register_Index) is
   begin
      for I in 0 .. VLENB - 1 loop
         VU.Registers (Vd).Data (I) :=
           VU.Registers (Vs2).Data (I) and (not VU.Registers (Vs1).Data (I));
      end loop;
   end VMANDNOT_MM;

   procedure VMXOR_MM (VU : in out Vector_State; Vd, Vs2, Vs1 : Register_Index) is
   begin
      for I in 0 .. VLENB - 1 loop
         VU.Registers (Vd).Data (I) :=
           VU.Registers (Vs2).Data (I) xor VU.Registers (Vs1).Data (I);
      end loop;
   end VMXOR_MM;

   procedure VMOR_MM (VU : in out Vector_State; Vd, Vs2, Vs1 : Register_Index) is
   begin
      for I in 0 .. VLENB - 1 loop
         VU.Registers (Vd).Data (I) :=
           VU.Registers (Vs2).Data (I) or VU.Registers (Vs1).Data (I);
      end loop;
   end VMOR_MM;

   procedure VMNOR_MM (VU : in out Vector_State; Vd, Vs2, Vs1 : Register_Index) is
   begin
      for I in 0 .. VLENB - 1 loop
         VU.Registers (Vd).Data (I) :=
           not (VU.Registers (Vs2).Data (I) or VU.Registers (Vs1).Data (I));
      end loop;
   end VMNOR_MM;

   procedure VMORNOT_MM (VU : in out Vector_State; Vd, Vs2, Vs1 : Register_Index) is
   begin
      for I in 0 .. VLENB - 1 loop
         VU.Registers (Vd).Data (I) :=
           VU.Registers (Vs2).Data (I) or (not VU.Registers (Vs1).Data (I));
      end loop;
   end VMORNOT_MM;

   procedure VMXNOR_MM (VU : in out Vector_State; Vd, Vs2, Vs1 : Register_Index) is
   begin
      for I in 0 .. VLENB - 1 loop
         VU.Registers (Vd).Data (I) :=
           not (VU.Registers (Vs2).Data (I) xor VU.Registers (Vs1).Data (I));
      end loop;
   end VMXNOR_MM;

   function VCPOP_M (VU : Vector_State; Vs2 : Register_Index; VM : Boolean) return Word is
      Count : Word := 0;
   begin
      for I in 0 .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if (VU.Registers (Vs2).Data (I / 8) and
                Byte (Shift_Left (Word (1), I mod 8))) /= 0
            then
               Count := Count + 1;
            end if;
         end if;
      end loop;
      return Count;
   end VCPOP_M;

   function VFIRST_M (VU : Vector_State; Vs2 : Register_Index; VM : Boolean) return Signed_Word is
   begin
      for I in 0 .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if (VU.Registers (Vs2).Data (I / 8) and
                Byte (Shift_Left (Word (1), I mod 8))) /= 0
            then
               return Signed_Word (I);
            end if;
         end if;
      end loop;
      return -1;
   end VFIRST_M;

   procedure VMSBF_M (VU : in out Vector_State; Vd, Vs2 : Register_Index; VM : Boolean) is
      Found : Boolean := False;
   begin
      for I in 0 .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if not Found then
               if (VU.Registers (Vs2).Data (I / 8) and
                   Byte (Shift_Left (Word (1), I mod 8))) /= 0
               then
                  Found := True;
                  Set_Mask_Bit (VU, Vd, I, False);
               else
                  Set_Mask_Bit (VU, Vd, I, True);
               end if;
            else
               Set_Mask_Bit (VU, Vd, I, False);
            end if;
         end if;
      end loop;
   end VMSBF_M;

   procedure VMSIF_M (VU : in out Vector_State; Vd, Vs2 : Register_Index; VM : Boolean) is
      Found : Boolean := False;
   begin
      for I in 0 .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if not Found then
               Set_Mask_Bit (VU, Vd, I, True);
               if (VU.Registers (Vs2).Data (I / 8) and
                   Byte (Shift_Left (Word (1), I mod 8))) /= 0
               then
                  Found := True;
               end if;
            else
               Set_Mask_Bit (VU, Vd, I, False);
            end if;
         end if;
      end loop;
   end VMSIF_M;

   procedure VMSOF_M (VU : in out Vector_State; Vd, Vs2 : Register_Index; VM : Boolean) is
      Found : Boolean := False;
   begin
      for I in 0 .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if not Found and then
               (VU.Registers (Vs2).Data (I / 8) and
                Byte (Shift_Left (Word (1), I mod 8))) /= 0
            then
               Set_Mask_Bit (VU, Vd, I, True);
               Found := True;
            else
               Set_Mask_Bit (VU, Vd, I, False);
            end if;
         end if;
      end loop;
   end VMSOF_M;

   procedure VIOTA_M (VU : in out Vector_State; Vd, Vs2 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      Count : Word := 0;
   begin
      for I in 0 .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            Write_Element (VU, Vd, I, SEW, Count);
            if (VU.Registers (Vs2).Data (I / 8) and
                Byte (Shift_Left (Word (1), I mod 8))) /= 0
            then
               Count := Count + 1;
            end if;
         end if;
      end loop;
   end VIOTA_M;

   procedure VID_V (VU : in out Vector_State; Vd : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            Write_Element (VU, Vd, I, SEW, Word (I));
         end if;
      end loop;
      VU.VStart := 0;
   end VID_V;

   ----------------
   -- VMV_NR_V --
   ----------------

   procedure VMV_NR_V (VU   : in out Vector_State;
                       Vd   : Register_Index;
                       Vs2  : Register_Index;
                       NReg : Positive) is
   begin
      for I in 0 .. NReg - 1 loop
         declare
            Dst : constant Register_Index :=
               Register_Index (Natural (Vd) + I);
            Src : constant Register_Index :=
               Register_Index (Natural (Vs2) + I);
         begin
            VU.Registers (Dst).Data := VU.Registers (Src).Data;
         end;
      end loop;
   end VMV_NR_V;

   ----------------
   -- Widening add/sub
   ----------------

   procedure VWADDU_VV (VU : in out Vector_State;
                        Vd, Vs2, Vs1 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               A : constant Unsigned_64 := Unsigned_64 (Read_Element (VU, Vs2, I, SEW));
               B : constant Unsigned_64 := Unsigned_64 (Read_Element (VU, Vs1, I, SEW));
            begin
               Write_Element_64 (VU, Vd, I, A + B);
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VWADDU_VV;

   procedure VWADDU_VX (VU : in out Vector_State;
                        Vd, Vs2 : Register_Index; Rs1 : Word; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      B   : constant Unsigned_64 := Unsigned_64 (Rs1);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               A : constant Unsigned_64 := Unsigned_64 (Read_Element (VU, Vs2, I, SEW));
            begin
               Write_Element_64 (VU, Vd, I, A + B);
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VWADDU_VX;

   procedure VWADD_VV (VU : in out Vector_State;
                       Vd, Vs2, Vs1 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               A : constant Integer_64 :=
                  Integer_64 (To_Signed (Read_Element (VU, Vs2, I, SEW)));
               B : constant Integer_64 :=
                  Integer_64 (To_Signed (Read_Element (VU, Vs1, I, SEW)));
            begin
               Write_Element_64 (VU, Vd, I, To_U64 (A + B));
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VWADD_VV;

   procedure VWADD_VX (VU : in out Vector_State;
                       Vd, Vs2 : Register_Index; Rs1 : Word; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      B   : constant Integer_64 := Integer_64 (To_Signed (Rs1));
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               A : constant Integer_64 :=
                  Integer_64 (To_Signed (Read_Element (VU, Vs2, I, SEW)));
            begin
               Write_Element_64 (VU, Vd, I, To_U64 (A + B));
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VWADD_VX;

   procedure VWSUBU_VV (VU : in out Vector_State;
                        Vd, Vs2, Vs1 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               A : constant Unsigned_64 := Unsigned_64 (Read_Element (VU, Vs2, I, SEW));
               B : constant Unsigned_64 := Unsigned_64 (Read_Element (VU, Vs1, I, SEW));
            begin
               Write_Element_64 (VU, Vd, I, A - B);
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VWSUBU_VV;

   procedure VWSUBU_VX (VU : in out Vector_State;
                        Vd, Vs2 : Register_Index; Rs1 : Word; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      B   : constant Unsigned_64 := Unsigned_64 (Rs1);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               A : constant Unsigned_64 := Unsigned_64 (Read_Element (VU, Vs2, I, SEW));
            begin
               Write_Element_64 (VU, Vd, I, A - B);
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VWSUBU_VX;

   procedure VWSUB_VV (VU : in out Vector_State;
                       Vd, Vs2, Vs1 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               A : constant Integer_64 :=
                  Integer_64 (To_Signed (Read_Element (VU, Vs2, I, SEW)));
               B : constant Integer_64 :=
                  Integer_64 (To_Signed (Read_Element (VU, Vs1, I, SEW)));
            begin
               Write_Element_64 (VU, Vd, I, To_U64 (A - B));
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VWSUB_VV;

   procedure VWSUB_VX (VU : in out Vector_State;
                       Vd, Vs2 : Register_Index; Rs1 : Word; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      B   : constant Integer_64 := Integer_64 (To_Signed (Rs1));
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               A : constant Integer_64 :=
                  Integer_64 (To_Signed (Read_Element (VU, Vs2, I, SEW)));
            begin
               Write_Element_64 (VU, Vd, I, To_U64 (A - B));
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VWSUB_VX;

   ----------------
   -- Widening multiply
   ----------------

   procedure VWMULU_VV (VU : in out Vector_State;
                        Vd, Vs2, Vs1 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               A : constant Unsigned_64 := Unsigned_64 (Read_Element (VU, Vs2, I, SEW));
               B : constant Unsigned_64 := Unsigned_64 (Read_Element (VU, Vs1, I, SEW));
            begin
               Write_Element_64 (VU, Vd, I, A * B);
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VWMULU_VV;

   procedure VWMULU_VX (VU : in out Vector_State;
                        Vd, Vs2 : Register_Index; Rs1 : Word; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      B   : constant Unsigned_64 := Unsigned_64 (Rs1);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               A : constant Unsigned_64 := Unsigned_64 (Read_Element (VU, Vs2, I, SEW));
            begin
               Write_Element_64 (VU, Vd, I, A * B);
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VWMULU_VX;

   procedure VWMUL_VV (VU : in out Vector_State;
                       Vd, Vs2, Vs1 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               A : constant Integer_64 :=
                  Integer_64 (To_Signed (Read_Element (VU, Vs2, I, SEW)));
               B : constant Integer_64 :=
                  Integer_64 (To_Signed (Read_Element (VU, Vs1, I, SEW)));
            begin
               Write_Element_64 (VU, Vd, I, To_U64 (A * B));
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VWMUL_VV;

   procedure VWMUL_VX (VU : in out Vector_State;
                       Vd, Vs2 : Register_Index; Rs1 : Word; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      B   : constant Integer_64 := Integer_64 (To_Signed (Rs1));
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               A : constant Integer_64 :=
                  Integer_64 (To_Signed (Read_Element (VU, Vs2, I, SEW)));
            begin
               Write_Element_64 (VU, Vd, I, To_U64 (A * B));
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VWMUL_VX;

   procedure VWMULSU_VV (VU : in out Vector_State;
                         Vd, Vs2, Vs1 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               A : constant Integer_64 :=
                  Integer_64 (To_Signed (Read_Element (VU, Vs2, I, SEW)));
               B : constant Unsigned_64 :=
                  Unsigned_64 (Read_Element (VU, Vs1, I, SEW));
            begin
               Write_Element_64 (VU, Vd, I, To_U64 (A * Integer_64 (B)));
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VWMULSU_VV;

   procedure VWMULSU_VX (VU : in out Vector_State;
                         Vd, Vs2 : Register_Index; Rs1 : Word; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      B   : constant Unsigned_64 := Unsigned_64 (Rs1);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               A : constant Integer_64 :=
                  Integer_64 (To_Signed (Read_Element (VU, Vs2, I, SEW)));
            begin
               Write_Element_64 (VU, Vd, I, To_U64 (A * Integer_64 (B)));
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VWMULSU_VX;

   ----------------
   -- Narrowing shifts
   ----------------

   procedure VNSRL_WV (VU : in out Vector_State;
                       Vd, Vs2, Vs1 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               Src   : constant Unsigned_64 := Read_Element_64 (VU, Vs2, I);
               Shamt : constant Natural :=
                  Natural (Read_Element (VU, Vs1, I, SEW) and 16#3F#);
            begin
               Write_Element (VU, Vd, I, SEW,
                 Word (Shift_Right (Src, Shamt) and 16#FFFFFFFF#));
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VNSRL_WV;

   procedure VNSRL_WX (VU : in out Vector_State;
                       Vd, Vs2 : Register_Index; Rs1 : Word; VM : Boolean) is
      SEW   : constant SEW_Type := VU.VType.VSEW;
      Shamt : constant Natural := Natural (Rs1 and 16#3F#);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               Src : constant Unsigned_64 := Read_Element_64 (VU, Vs2, I);
            begin
               Write_Element (VU, Vd, I, SEW,
                 Word (Shift_Right (Src, Shamt) and 16#FFFFFFFF#));
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VNSRL_WX;

   procedure VNSRL_WI (VU : in out Vector_State;
                       Vd, Vs2 : Register_Index; Imm : Natural; VM : Boolean) is
      SEW   : constant SEW_Type := VU.VType.VSEW;
      Shamt : constant Natural := Imm mod 64;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               Src : constant Unsigned_64 := Read_Element_64 (VU, Vs2, I);
            begin
               Write_Element (VU, Vd, I, SEW,
                 Word (Shift_Right (Src, Shamt) and 16#FFFFFFFF#));
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VNSRL_WI;

   procedure VNSRA_WV (VU : in out Vector_State;
                       Vd, Vs2, Vs1 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               Src   : constant Unsigned_64 := Read_Element_64 (VU, Vs2, I);
               Shamt : constant Natural :=
                  Natural (Read_Element (VU, Vs1, I, SEW) and 16#3F#);
               U_Shifted : Unsigned_64;
            begin
               U_Shifted := Shift_Right (Src, Shamt);
               --  Sign extend if negative (bit 63 set)
               if Shamt > 0 and (Src and 16#8000000000000000#) /= 0 then
                  U_Shifted := U_Shifted or
                    Shift_Left (16#FFFFFFFFFFFFFFFF#, 64 - Shamt);
               end if;
               Write_Element (VU, Vd, I, SEW,
                 Word (U_Shifted and 16#FFFFFFFF#));
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VNSRA_WV;

   procedure VNSRA_WX (VU : in out Vector_State;
                       Vd, Vs2 : Register_Index; Rs1 : Word; VM : Boolean) is
      SEW   : constant SEW_Type := VU.VType.VSEW;
      Shamt : constant Natural := Natural (Rs1 and 16#3F#);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               Src : constant Unsigned_64 := Read_Element_64 (VU, Vs2, I);
               U_Shifted : Unsigned_64;
            begin
               U_Shifted := Shift_Right (Src, Shamt);
               --  Sign extend if negative (bit 63 set)
               if Shamt > 0 and (Src and 16#8000000000000000#) /= 0 then
                  U_Shifted := U_Shifted or
                    Shift_Left (16#FFFFFFFFFFFFFFFF#, 64 - Shamt);
               end if;
               Write_Element (VU, Vd, I, SEW,
                 Word (U_Shifted and 16#FFFFFFFF#));
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VNSRA_WX;

   procedure VNSRA_WI (VU : in out Vector_State;
                       Vd, Vs2 : Register_Index; Imm : Natural; VM : Boolean) is
      SEW   : constant SEW_Type := VU.VType.VSEW;
      Shamt : constant Natural := Imm mod 64;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               Src : constant Unsigned_64 := Read_Element_64 (VU, Vs2, I);
               U_Shifted : Unsigned_64;
            begin
               U_Shifted := Shift_Right (Src, Shamt);
               --  Sign extend if negative (bit 63 set)
               if Shamt > 0 and (Src and 16#8000000000000000#) /= 0 then
                  U_Shifted := U_Shifted or
                    Shift_Left (16#FFFFFFFFFFFFFFFF#, 64 - Shamt);
               end if;
               Write_Element (VU, Vd, I, SEW,
                 Word (U_Shifted and 16#FFFFFFFF#));
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VNSRA_WI;

   ----------------
   -- FP vector operations
   ----------------

   use RISCV.FPU;

   function Resolve_RM (FP : FPU_Access) return Rounding_Mode is
   begin
      return Get_Rounding_Mode (FP.all, DYN);
   end Resolve_RM;

   procedure VFADD_VV (VU : in out Vector_State; FP : FPU_Access;
                       Vd, Vs2, Vs1 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      RM  : constant Rounding_Mode := Resolve_RM (FP);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if SEW = SEW_32 then
               Write_Element (VU, Vd, I, SEW,
                 FADD_S (FP.all, Read_Element (VU, Vs2, I, SEW),
                         Read_Element (VU, Vs1, I, SEW), RM));
            elsif SEW = SEW_64 then
               Write_Element_64 (VU, Vd, I,
                 Unsigned_64 (FADD_D (FP.all,
                   FP_Register (Read_Element_64 (VU, Vs2, I)),
                   FP_Register (Read_Element_64 (VU, Vs1, I)), RM)));
            end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VFADD_VV;

   procedure VFADD_VF (VU : in out Vector_State; FP : FPU_Access;
                       Vd, Vs2 : Register_Index; Fs1 : Word; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      RM  : constant Rounding_Mode := Resolve_RM (FP);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if SEW = SEW_32 then
               Write_Element (VU, Vd, I, SEW,
                 FADD_S (FP.all, Read_Element (VU, Vs2, I, SEW), Fs1, RM));
            end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VFADD_VF;

   procedure VFSUB_VV (VU : in out Vector_State; FP : FPU_Access;
                       Vd, Vs2, Vs1 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      RM  : constant Rounding_Mode := Resolve_RM (FP);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if SEW = SEW_32 then
               Write_Element (VU, Vd, I, SEW,
                 FSUB_S (FP.all, Read_Element (VU, Vs2, I, SEW),
                         Read_Element (VU, Vs1, I, SEW), RM));
            elsif SEW = SEW_64 then
               Write_Element_64 (VU, Vd, I,
                 Unsigned_64 (FSUB_D (FP.all,
                   FP_Register (Read_Element_64 (VU, Vs2, I)),
                   FP_Register (Read_Element_64 (VU, Vs1, I)), RM)));
            end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VFSUB_VV;

   procedure VFSUB_VF (VU : in out Vector_State; FP : FPU_Access;
                       Vd, Vs2 : Register_Index; Fs1 : Word; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      RM  : constant Rounding_Mode := Resolve_RM (FP);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if SEW = SEW_32 then
               Write_Element (VU, Vd, I, SEW,
                 FSUB_S (FP.all, Read_Element (VU, Vs2, I, SEW), Fs1, RM));
            end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VFSUB_VF;

   procedure VFMUL_VV (VU : in out Vector_State; FP : FPU_Access;
                       Vd, Vs2, Vs1 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      RM  : constant Rounding_Mode := Resolve_RM (FP);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if SEW = SEW_32 then
               Write_Element (VU, Vd, I, SEW,
                 FMUL_S (FP.all, Read_Element (VU, Vs2, I, SEW),
                         Read_Element (VU, Vs1, I, SEW), RM));
            elsif SEW = SEW_64 then
               Write_Element_64 (VU, Vd, I,
                 Unsigned_64 (FMUL_D (FP.all,
                   FP_Register (Read_Element_64 (VU, Vs2, I)),
                   FP_Register (Read_Element_64 (VU, Vs1, I)), RM)));
            end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VFMUL_VV;

   procedure VFMUL_VF (VU : in out Vector_State; FP : FPU_Access;
                       Vd, Vs2 : Register_Index; Fs1 : Word; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      RM  : constant Rounding_Mode := Resolve_RM (FP);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if SEW = SEW_32 then
               Write_Element (VU, Vd, I, SEW,
                 FMUL_S (FP.all, Read_Element (VU, Vs2, I, SEW), Fs1, RM));
            end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VFMUL_VF;

   procedure VFDIV_VV (VU : in out Vector_State; FP : FPU_Access;
                       Vd, Vs2, Vs1 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      RM  : constant Rounding_Mode := Resolve_RM (FP);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if SEW = SEW_32 then
               Write_Element (VU, Vd, I, SEW,
                 FDIV_S (FP.all, Read_Element (VU, Vs2, I, SEW),
                         Read_Element (VU, Vs1, I, SEW), RM));
            elsif SEW = SEW_64 then
               Write_Element_64 (VU, Vd, I,
                 Unsigned_64 (FDIV_D (FP.all,
                   FP_Register (Read_Element_64 (VU, Vs2, I)),
                   FP_Register (Read_Element_64 (VU, Vs1, I)), RM)));
            end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VFDIV_VV;

   procedure VFDIV_VF (VU : in out Vector_State; FP : FPU_Access;
                       Vd, Vs2 : Register_Index; Fs1 : Word; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      RM  : constant Rounding_Mode := Resolve_RM (FP);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if SEW = SEW_32 then
               Write_Element (VU, Vd, I, SEW,
                 FDIV_S (FP.all, Read_Element (VU, Vs2, I, SEW), Fs1, RM));
            end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VFDIV_VF;

   procedure VFMIN_VV (VU : in out Vector_State; FP : FPU_Access;
                       Vd, Vs2, Vs1 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if SEW = SEW_32 then
               Write_Element (VU, Vd, I, SEW,
                 FMIN_S (FP.all, Read_Element (VU, Vs2, I, SEW),
                         Read_Element (VU, Vs1, I, SEW)));
            elsif SEW = SEW_64 then
               Write_Element_64 (VU, Vd, I,
                 Unsigned_64 (FMIN_D (FP.all,
                   FP_Register (Read_Element_64 (VU, Vs2, I)),
                   FP_Register (Read_Element_64 (VU, Vs1, I)))));
            end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VFMIN_VV;

   procedure VFMIN_VF (VU : in out Vector_State; FP : FPU_Access;
                       Vd, Vs2 : Register_Index; Fs1 : Word; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if SEW = SEW_32 then
               Write_Element (VU, Vd, I, SEW,
                 FMIN_S (FP.all, Read_Element (VU, Vs2, I, SEW), Fs1));
            end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VFMIN_VF;

   procedure VFMAX_VV (VU : in out Vector_State; FP : FPU_Access;
                       Vd, Vs2, Vs1 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if SEW = SEW_32 then
               Write_Element (VU, Vd, I, SEW,
                 FMAX_S (FP.all, Read_Element (VU, Vs2, I, SEW),
                         Read_Element (VU, Vs1, I, SEW)));
            elsif SEW = SEW_64 then
               Write_Element_64 (VU, Vd, I,
                 Unsigned_64 (FMAX_D (FP.all,
                   FP_Register (Read_Element_64 (VU, Vs2, I)),
                   FP_Register (Read_Element_64 (VU, Vs1, I)))));
            end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VFMAX_VV;

   procedure VFMAX_VF (VU : in out Vector_State; FP : FPU_Access;
                       Vd, Vs2 : Register_Index; Fs1 : Word; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if SEW = SEW_32 then
               Write_Element (VU, Vd, I, SEW,
                 FMAX_S (FP.all, Read_Element (VU, Vs2, I, SEW), Fs1));
            end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VFMAX_VF;

   procedure VFSQRT_V (VU : in out Vector_State; FP : FPU_Access;
                       Vd, Vs2 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      RM  : constant Rounding_Mode := Resolve_RM (FP);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if SEW = SEW_32 then
               Write_Element (VU, Vd, I, SEW,
                 FSQRT_S (FP.all, Read_Element (VU, Vs2, I, SEW), RM));
            elsif SEW = SEW_64 then
               Write_Element_64 (VU, Vd, I,
                 Unsigned_64 (FSQRT_D (FP.all,
                   FP_Register (Read_Element_64 (VU, Vs2, I)), RM)));
            end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VFSQRT_V;

   --  FMA: vd = +(vs1 * vs2) + vd
   procedure VFMACC_VV (VU : in out Vector_State; FP : FPU_Access;
                        Vd, Vs1, Vs2 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      RM  : constant Rounding_Mode := Resolve_RM (FP);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if SEW = SEW_32 then
               Write_Element (VU, Vd, I, SEW,
                 FMADD_S (FP.all, Read_Element (VU, Vs1, I, SEW),
                          Read_Element (VU, Vs2, I, SEW),
                          Read_Element (VU, Vd, I, SEW), RM));
            elsif SEW = SEW_64 then
               Write_Element_64 (VU, Vd, I,
                 Unsigned_64 (FMADD_D (FP.all,
                   FP_Register (Read_Element_64 (VU, Vs1, I)),
                   FP_Register (Read_Element_64 (VU, Vs2, I)),
                   FP_Register (Read_Element_64 (VU, Vd, I)), RM)));
            end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VFMACC_VV;

   procedure VFMACC_VF (VU : in out Vector_State; FP : FPU_Access;
                        Vd : Register_Index; Fs1 : Word;
                        Vs2 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      RM  : constant Rounding_Mode := Resolve_RM (FP);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if SEW = SEW_32 then
               Write_Element (VU, Vd, I, SEW,
                 FMADD_S (FP.all, Fs1,
                          Read_Element (VU, Vs2, I, SEW),
                          Read_Element (VU, Vd, I, SEW), RM));
            end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VFMACC_VF;

   --  FMA: vd = -(vs1 * vs2) + vd  =>  FNMSUB
   procedure VFNMACC_VV (VU : in out Vector_State; FP : FPU_Access;
                         Vd, Vs1, Vs2 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      RM  : constant Rounding_Mode := Resolve_RM (FP);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if SEW = SEW_32 then
               Write_Element (VU, Vd, I, SEW,
                 FNMADD_S (FP.all, Read_Element (VU, Vs1, I, SEW),
                           Read_Element (VU, Vs2, I, SEW),
                           Read_Element (VU, Vd, I, SEW), RM));
            elsif SEW = SEW_64 then
               Write_Element_64 (VU, Vd, I,
                 Unsigned_64 (FNMADD_D (FP.all,
                   FP_Register (Read_Element_64 (VU, Vs1, I)),
                   FP_Register (Read_Element_64 (VU, Vs2, I)),
                   FP_Register (Read_Element_64 (VU, Vd, I)), RM)));
            end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VFNMACC_VV;

   procedure VFNMACC_VF (VU : in out Vector_State; FP : FPU_Access;
                         Vd : Register_Index; Fs1 : Word;
                         Vs2 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      RM  : constant Rounding_Mode := Resolve_RM (FP);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if SEW = SEW_32 then
               Write_Element (VU, Vd, I, SEW,
                 FNMADD_S (FP.all, Fs1,
                           Read_Element (VU, Vs2, I, SEW),
                           Read_Element (VU, Vd, I, SEW), RM));
            end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VFNMACC_VF;

   --  FMA: vd = +(vs1 * vs2) - vd  =>  FMSUB
   procedure VFMSAC_VV (VU : in out Vector_State; FP : FPU_Access;
                        Vd, Vs1, Vs2 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      RM  : constant Rounding_Mode := Resolve_RM (FP);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if SEW = SEW_32 then
               Write_Element (VU, Vd, I, SEW,
                 FMSUB_S (FP.all, Read_Element (VU, Vs1, I, SEW),
                          Read_Element (VU, Vs2, I, SEW),
                          Read_Element (VU, Vd, I, SEW), RM));
            elsif SEW = SEW_64 then
               Write_Element_64 (VU, Vd, I,
                 Unsigned_64 (FMSUB_D (FP.all,
                   FP_Register (Read_Element_64 (VU, Vs1, I)),
                   FP_Register (Read_Element_64 (VU, Vs2, I)),
                   FP_Register (Read_Element_64 (VU, Vd, I)), RM)));
            end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VFMSAC_VV;

   procedure VFMSAC_VF (VU : in out Vector_State; FP : FPU_Access;
                        Vd : Register_Index; Fs1 : Word;
                        Vs2 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      RM  : constant Rounding_Mode := Resolve_RM (FP);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if SEW = SEW_32 then
               Write_Element (VU, Vd, I, SEW,
                 FMSUB_S (FP.all, Fs1,
                          Read_Element (VU, Vs2, I, SEW),
                          Read_Element (VU, Vd, I, SEW), RM));
            end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VFMSAC_VF;

   --  FMA: vd = -(vs1 * vs2) - vd  =>  FNMSUB
   procedure VFNMSAC_VV (VU : in out Vector_State; FP : FPU_Access;
                         Vd, Vs1, Vs2 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      RM  : constant Rounding_Mode := Resolve_RM (FP);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if SEW = SEW_32 then
               Write_Element (VU, Vd, I, SEW,
                 FNMSUB_S (FP.all, Read_Element (VU, Vs1, I, SEW),
                           Read_Element (VU, Vs2, I, SEW),
                           Read_Element (VU, Vd, I, SEW), RM));
            elsif SEW = SEW_64 then
               Write_Element_64 (VU, Vd, I,
                 Unsigned_64 (FNMSUB_D (FP.all,
                   FP_Register (Read_Element_64 (VU, Vs1, I)),
                   FP_Register (Read_Element_64 (VU, Vs2, I)),
                   FP_Register (Read_Element_64 (VU, Vd, I)), RM)));
            end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VFNMSAC_VV;

   procedure VFNMSAC_VF (VU : in out Vector_State; FP : FPU_Access;
                         Vd : Register_Index; Fs1 : Word;
                         Vs2 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      RM  : constant Rounding_Mode := Resolve_RM (FP);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if SEW = SEW_32 then
               Write_Element (VU, Vd, I, SEW,
                 FNMSUB_S (FP.all, Fs1,
                           Read_Element (VU, Vs2, I, SEW),
                           Read_Element (VU, Vd, I, SEW), RM));
            end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VFNMSAC_VF;

   ----------------
   -- Widening .w variants (wide vs2, narrow vs1, wide result)
   ----------------

   procedure VWADDUW_VV (VU : in out Vector_State;
                         Vd, Vs2, Vs1 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               A : constant Unsigned_64 := Read_Element_64 (VU, Vs2, I);
               B : constant Unsigned_64 := Unsigned_64 (Read_Element (VU, Vs1, I, SEW));
            begin
               Write_Element_64 (VU, Vd, I, A + B);
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VWADDUW_VV;

   procedure VWADDUW_VX (VU : in out Vector_State;
                         Vd, Vs2 : Register_Index; Rs1 : Word; VM : Boolean) is
      B : constant Unsigned_64 := Unsigned_64 (Rs1);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            Write_Element_64 (VU, Vd, I, Read_Element_64 (VU, Vs2, I) + B);
         end if;
      end loop;
      VU.VStart := 0;
   end VWADDUW_VX;

   procedure VWADDW_VV (VU : in out Vector_State;
                        Vd, Vs2, Vs1 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               A : constant Integer_64 :=
                  Integer_64 (Unsigned_64'(Read_Element_64 (VU, Vs2, I)));
               B : constant Integer_64 :=
                  Integer_64 (To_Signed (Read_Element (VU, Vs1, I, SEW)));
            begin
               Write_Element_64 (VU, Vd, I, To_U64 (A + B));
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VWADDW_VV;

   procedure VWADDW_VX (VU : in out Vector_State;
                        Vd, Vs2 : Register_Index; Rs1 : Word; VM : Boolean) is
      B : constant Integer_64 := Integer_64 (To_Signed (Rs1));
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               A : constant Integer_64 :=
                  Integer_64 (Unsigned_64'(Read_Element_64 (VU, Vs2, I)));
            begin
               Write_Element_64 (VU, Vd, I, To_U64 (A + B));
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VWADDW_VX;

   procedure VWSUBUW_VV (VU : in out Vector_State;
                         Vd, Vs2, Vs1 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               A : constant Unsigned_64 := Read_Element_64 (VU, Vs2, I);
               B : constant Unsigned_64 := Unsigned_64 (Read_Element (VU, Vs1, I, SEW));
            begin
               Write_Element_64 (VU, Vd, I, A - B);
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VWSUBUW_VV;

   procedure VWSUBUW_VX (VU : in out Vector_State;
                         Vd, Vs2 : Register_Index; Rs1 : Word; VM : Boolean) is
      B : constant Unsigned_64 := Unsigned_64 (Rs1);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            Write_Element_64 (VU, Vd, I, Read_Element_64 (VU, Vs2, I) - B);
         end if;
      end loop;
      VU.VStart := 0;
   end VWSUBUW_VX;

   procedure VWSUBW_VV (VU : in out Vector_State;
                        Vd, Vs2, Vs1 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               A : constant Integer_64 :=
                  Integer_64 (Unsigned_64'(Read_Element_64 (VU, Vs2, I)));
               B : constant Integer_64 :=
                  Integer_64 (To_Signed (Read_Element (VU, Vs1, I, SEW)));
            begin
               Write_Element_64 (VU, Vd, I, To_U64 (A - B));
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VWSUBW_VV;

   procedure VWSUBW_VX (VU : in out Vector_State;
                        Vd, Vs2 : Register_Index; Rs1 : Word; VM : Boolean) is
      B : constant Integer_64 := Integer_64 (To_Signed (Rs1));
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               A : constant Integer_64 :=
                  Integer_64 (Unsigned_64'(Read_Element_64 (VU, Vs2, I)));
            begin
               Write_Element_64 (VU, Vd, I, To_U64 (A - B));
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VWSUBW_VX;

   ----------------
   -- Carry/Borrow operations
   ----------------

   procedure VADC_VVM (VU : in out Vector_State;
                       Vd, Vs2, Vs1 : Register_Index) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         declare
            A : constant Unsigned_64 :=
               Unsigned_64 (Read_Element (VU, Vs2, I, SEW));
            B : constant Unsigned_64 :=
               Unsigned_64 (Read_Element (VU, Vs1, I, SEW));
            C : constant Unsigned_64 :=
               (if Get_Mask_Bit (VU, I) then 1 else 0);
         begin
            Write_Element (VU, Vd, I, SEW, Word ((A + B + C) and 16#FFFFFFFF#));
         end;
      end loop;
      VU.VStart := 0;
   end VADC_VVM;

   procedure VADC_VXM (VU : in out Vector_State;
                       Vd, Vs2 : Register_Index; Rs1 : Word) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      B   : constant Unsigned_64 := Unsigned_64 (Rs1);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         declare
            A : constant Unsigned_64 :=
               Unsigned_64 (Read_Element (VU, Vs2, I, SEW));
            C : constant Unsigned_64 :=
               (if Get_Mask_Bit (VU, I) then 1 else 0);
         begin
            Write_Element (VU, Vd, I, SEW, Word ((A + B + C) and 16#FFFFFFFF#));
         end;
      end loop;
      VU.VStart := 0;
   end VADC_VXM;

   procedure VADC_VIM (VU : in out Vector_State;
                       Vd, Vs2 : Register_Index; Imm : Signed_Word) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      B   : constant Unsigned_64 := Unsigned_64 (To_Word (Imm));
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         declare
            A : constant Unsigned_64 :=
               Unsigned_64 (Read_Element (VU, Vs2, I, SEW));
            C : constant Unsigned_64 :=
               (if Get_Mask_Bit (VU, I) then 1 else 0);
         begin
            Write_Element (VU, Vd, I, SEW, Word ((A + B + C) and 16#FFFFFFFF#));
         end;
      end loop;
      VU.VStart := 0;
   end VADC_VIM;

   procedure VMADC_VVM (VU : in out Vector_State;
                        Vd, Vs2, Vs1 : Register_Index; VM : Boolean) is
      SEW      : constant SEW_Type := VU.VType.VSEW;
      SEW_Bits : constant Natural := Get_SEW_Bits (SEW);
      Max_Val  : constant Unsigned_64 :=
         Shift_Left (Unsigned_64'(1), SEW_Bits) - 1;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         declare
            A : constant Unsigned_64 :=
               Unsigned_64 (Read_Element (VU, Vs2, I, SEW));
            B : constant Unsigned_64 :=
               Unsigned_64 (Read_Element (VU, Vs1, I, SEW));
            C : constant Unsigned_64 :=
               (if not VM and then Get_Mask_Bit (VU, I) then 1 else 0);
            Sum : constant Unsigned_64 := A + B + C;
         begin
            Set_Mask_Bit (VU, Vd, I, Sum > Max_Val);
         end;
      end loop;
      VU.VStart := 0;
   end VMADC_VVM;

   procedure VMADC_VXM (VU : in out Vector_State;
                        Vd, Vs2 : Register_Index; Rs1 : Word;
                        VM : Boolean) is
      SEW      : constant SEW_Type := VU.VType.VSEW;
      SEW_Bits : constant Natural := Get_SEW_Bits (SEW);
      Max_Val  : constant Unsigned_64 :=
         Shift_Left (Unsigned_64'(1), SEW_Bits) - 1;
      B : constant Unsigned_64 := Unsigned_64 (Rs1);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         declare
            A : constant Unsigned_64 :=
               Unsigned_64 (Read_Element (VU, Vs2, I, SEW));
            C : constant Unsigned_64 :=
               (if not VM and then Get_Mask_Bit (VU, I) then 1 else 0);
            Sum : constant Unsigned_64 := A + B + C;
         begin
            Set_Mask_Bit (VU, Vd, I, Sum > Max_Val);
         end;
      end loop;
      VU.VStart := 0;
   end VMADC_VXM;

   procedure VMADC_VIM (VU : in out Vector_State;
                        Vd, Vs2 : Register_Index; Imm : Signed_Word;
                        VM : Boolean) is
      SEW      : constant SEW_Type := VU.VType.VSEW;
      SEW_Bits : constant Natural := Get_SEW_Bits (SEW);
      Max_Val  : constant Unsigned_64 :=
         Shift_Left (Unsigned_64'(1), SEW_Bits) - 1;
      B : constant Unsigned_64 := Unsigned_64 (To_Word (Imm));
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         declare
            A : constant Unsigned_64 :=
               Unsigned_64 (Read_Element (VU, Vs2, I, SEW));
            C : constant Unsigned_64 :=
               (if not VM and then Get_Mask_Bit (VU, I) then 1 else 0);
            Sum : constant Unsigned_64 := A + B + C;
         begin
            Set_Mask_Bit (VU, Vd, I, Sum > Max_Val);
         end;
      end loop;
      VU.VStart := 0;
   end VMADC_VIM;

   procedure VSBC_VVM (VU : in out Vector_State;
                       Vd, Vs2, Vs1 : Register_Index) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         declare
            A : constant Unsigned_64 :=
               Unsigned_64 (Read_Element (VU, Vs2, I, SEW));
            B : constant Unsigned_64 :=
               Unsigned_64 (Read_Element (VU, Vs1, I, SEW));
            C : constant Unsigned_64 :=
               (if Get_Mask_Bit (VU, I) then 1 else 0);
         begin
            Write_Element (VU, Vd, I, SEW, Word ((A - B - C) and 16#FFFFFFFF#));
         end;
      end loop;
      VU.VStart := 0;
   end VSBC_VVM;

   procedure VSBC_VXM (VU : in out Vector_State;
                       Vd, Vs2 : Register_Index; Rs1 : Word) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      B   : constant Unsigned_64 := Unsigned_64 (Rs1);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         declare
            A : constant Unsigned_64 :=
               Unsigned_64 (Read_Element (VU, Vs2, I, SEW));
            C : constant Unsigned_64 :=
               (if Get_Mask_Bit (VU, I) then 1 else 0);
         begin
            Write_Element (VU, Vd, I, SEW, Word ((A - B - C) and 16#FFFFFFFF#));
         end;
      end loop;
      VU.VStart := 0;
   end VSBC_VXM;

   procedure VMSBC_VVM (VU : in out Vector_State;
                        Vd, Vs2, Vs1 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         declare
            A : constant Unsigned_64 :=
               Unsigned_64 (Read_Element (VU, Vs2, I, SEW));
            B : constant Unsigned_64 :=
               Unsigned_64 (Read_Element (VU, Vs1, I, SEW));
            C : constant Unsigned_64 :=
               (if not VM and then Get_Mask_Bit (VU, I) then 1 else 0);
         begin
            Set_Mask_Bit (VU, Vd, I, A < B + C);
         end;
      end loop;
      VU.VStart := 0;
   end VMSBC_VVM;

   procedure VMSBC_VXM (VU : in out Vector_State;
                        Vd, Vs2 : Register_Index; Rs1 : Word;
                        VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      B   : constant Unsigned_64 := Unsigned_64 (Rs1);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         declare
            A : constant Unsigned_64 :=
               Unsigned_64 (Read_Element (VU, Vs2, I, SEW));
            C : constant Unsigned_64 :=
               (if not VM and then Get_Mask_Bit (VU, I) then 1 else 0);
         begin
            Set_Mask_Bit (VU, Vd, I, A < B + C);
         end;
      end loop;
      VU.VStart := 0;
   end VMSBC_VXM;

   ----------------
   -- Fixed-point saturating operations
   ----------------

   procedure VSADDU_VV (VU : in out Vector_State;
                        Vd, Vs2, Vs1 : Register_Index; VM : Boolean) is
      SEW      : constant SEW_Type := VU.VType.VSEW;
      SEW_Bits : constant Natural := Get_SEW_Bits (SEW);
      Sat      : Boolean;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               A : constant Unsigned_64 :=
                  Unsigned_64 (Read_Element (VU, Vs2, I, SEW));
               B : constant Unsigned_64 :=
                  Unsigned_64 (Read_Element (VU, Vs1, I, SEW));
            begin
               Write_Element (VU, Vd, I, SEW,
                 Saturate_Unsigned (A + B, SEW_Bits, Sat));
               if Sat then VU.VXSat := True; end if;
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VSADDU_VV;

   procedure VSADDU_VX (VU : in out Vector_State;
                        Vd, Vs2 : Register_Index; Rs1 : Word; VM : Boolean) is
      SEW      : constant SEW_Type := VU.VType.VSEW;
      SEW_Bits : constant Natural := Get_SEW_Bits (SEW);
      B        : constant Unsigned_64 := Unsigned_64 (Rs1);
      Sat      : Boolean;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            Write_Element (VU, Vd, I, SEW,
              Saturate_Unsigned (Unsigned_64 (Read_Element (VU, Vs2, I, SEW)) + B,
                                SEW_Bits, Sat));
            if Sat then VU.VXSat := True; end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VSADDU_VX;

   procedure VSADDU_VI (VU : in out Vector_State;
                        Vd, Vs2 : Register_Index; Imm : Signed_Word;
                        VM : Boolean) is
      SEW      : constant SEW_Type := VU.VType.VSEW;
      SEW_Bits : constant Natural := Get_SEW_Bits (SEW);
      B        : constant Unsigned_64 := Unsigned_64 (To_Word (Imm));
      Sat      : Boolean;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            Write_Element (VU, Vd, I, SEW,
              Saturate_Unsigned (Unsigned_64 (Read_Element (VU, Vs2, I, SEW)) + B,
                                SEW_Bits, Sat));
            if Sat then VU.VXSat := True; end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VSADDU_VI;

   procedure VSADD_VV (VU : in out Vector_State;
                       Vd, Vs2, Vs1 : Register_Index; VM : Boolean) is
      SEW      : constant SEW_Type := VU.VType.VSEW;
      SEW_Bits : constant Natural := Get_SEW_Bits (SEW);
      Sat      : Boolean;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               A : constant Integer_64 :=
                  Integer_64 (To_Signed (Read_Element (VU, Vs2, I, SEW)));
               B : constant Integer_64 :=
                  Integer_64 (To_Signed (Read_Element (VU, Vs1, I, SEW)));
            begin
               Write_Element (VU, Vd, I, SEW,
                 Saturate_Signed (A + B, SEW_Bits, Sat));
               if Sat then VU.VXSat := True; end if;
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VSADD_VV;

   procedure VSADD_VX (VU : in out Vector_State;
                       Vd, Vs2 : Register_Index; Rs1 : Word; VM : Boolean) is
      SEW      : constant SEW_Type := VU.VType.VSEW;
      SEW_Bits : constant Natural := Get_SEW_Bits (SEW);
      B        : constant Integer_64 := Integer_64 (To_Signed (Rs1));
      Sat      : Boolean;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            Write_Element (VU, Vd, I, SEW,
              Saturate_Signed (Integer_64 (To_Signed (Read_Element (VU, Vs2, I, SEW))) + B,
                              SEW_Bits, Sat));
            if Sat then VU.VXSat := True; end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VSADD_VX;

   procedure VSADD_VI (VU : in out Vector_State;
                       Vd, Vs2 : Register_Index; Imm : Signed_Word;
                       VM : Boolean) is
      SEW      : constant SEW_Type := VU.VType.VSEW;
      SEW_Bits : constant Natural := Get_SEW_Bits (SEW);
      B        : constant Integer_64 := Integer_64 (Imm);
      Sat      : Boolean;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            Write_Element (VU, Vd, I, SEW,
              Saturate_Signed (Integer_64 (To_Signed (Read_Element (VU, Vs2, I, SEW))) + B,
                              SEW_Bits, Sat));
            if Sat then VU.VXSat := True; end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VSADD_VI;

   procedure VSSUBU_VV (VU : in out Vector_State;
                        Vd, Vs2, Vs1 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               A : constant Unsigned_64 :=
                  Unsigned_64 (Read_Element (VU, Vs2, I, SEW));
               B : constant Unsigned_64 :=
                  Unsigned_64 (Read_Element (VU, Vs1, I, SEW));
            begin
               if A >= B then
                  Write_Element (VU, Vd, I, SEW, Word ((A - B) and 16#FFFFFFFF#));
               else
                  Write_Element (VU, Vd, I, SEW, 0);
                  VU.VXSat := True;
               end if;
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VSSUBU_VV;

   procedure VSSUBU_VX (VU : in out Vector_State;
                        Vd, Vs2 : Register_Index; Rs1 : Word; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      B   : constant Unsigned_64 := Unsigned_64 (Rs1);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               A : constant Unsigned_64 :=
                  Unsigned_64 (Read_Element (VU, Vs2, I, SEW));
            begin
               if A >= B then
                  Write_Element (VU, Vd, I, SEW, Word ((A - B) and 16#FFFFFFFF#));
               else
                  Write_Element (VU, Vd, I, SEW, 0);
                  VU.VXSat := True;
               end if;
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VSSUBU_VX;

   procedure VSSUB_VV (VU : in out Vector_State;
                       Vd, Vs2, Vs1 : Register_Index; VM : Boolean) is
      SEW      : constant SEW_Type := VU.VType.VSEW;
      SEW_Bits : constant Natural := Get_SEW_Bits (SEW);
      Sat      : Boolean;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               A : constant Integer_64 :=
                  Integer_64 (To_Signed (Read_Element (VU, Vs2, I, SEW)));
               B : constant Integer_64 :=
                  Integer_64 (To_Signed (Read_Element (VU, Vs1, I, SEW)));
            begin
               Write_Element (VU, Vd, I, SEW,
                 Saturate_Signed (A - B, SEW_Bits, Sat));
               if Sat then VU.VXSat := True; end if;
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VSSUB_VV;

   procedure VSSUB_VX (VU : in out Vector_State;
                       Vd, Vs2 : Register_Index; Rs1 : Word; VM : Boolean) is
      SEW      : constant SEW_Type := VU.VType.VSEW;
      SEW_Bits : constant Natural := Get_SEW_Bits (SEW);
      B        : constant Integer_64 := Integer_64 (To_Signed (Rs1));
      Sat      : Boolean;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            Write_Element (VU, Vd, I, SEW,
              Saturate_Signed (Integer_64 (To_Signed (Read_Element (VU, Vs2, I, SEW))) - B,
                              SEW_Bits, Sat));
            if Sat then VU.VXSat := True; end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VSSUB_VX;

   ----------------
   -- VSMUL (signed fractional multiply)
   ----------------

   procedure VSMUL_VV (VU : in out Vector_State;
                       Vd, Vs2, Vs1 : Register_Index; VM : Boolean) is
      SEW      : constant SEW_Type := VU.VType.VSEW;
      SEW_Bits : constant Natural := Get_SEW_Bits (SEW);
      Sat      : Boolean;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               A : constant Integer_64 :=
                  Integer_64 (To_Signed (Read_Element (VU, Vs2, I, SEW)));
               B : constant Integer_64 :=
                  Integer_64 (To_Signed (Read_Element (VU, Vs1, I, SEW)));
               Product : constant Integer_64 := A * B;
               Shifted : Integer_64;
            begin
               if SEW_Bits > 1 then
                  Shifted := Integer_64 (Roundoff_Unsigned (
                     To_U64 (Product), SEW_Bits - 1, VU.VXRM));
               else
                  Shifted := Product;
               end if;
               Write_Element (VU, Vd, I, SEW,
                 Saturate_Signed (Shifted, SEW_Bits, Sat));
               if Sat then VU.VXSat := True; end if;
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VSMUL_VV;

   procedure VSMUL_VX (VU : in out Vector_State;
                       Vd, Vs2 : Register_Index; Rs1 : Word; VM : Boolean) is
      SEW      : constant SEW_Type := VU.VType.VSEW;
      SEW_Bits : constant Natural := Get_SEW_Bits (SEW);
      B        : constant Integer_64 := Integer_64 (To_Signed (Rs1));
      Sat      : Boolean;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               A : constant Integer_64 :=
                  Integer_64 (To_Signed (Read_Element (VU, Vs2, I, SEW)));
               Product : constant Integer_64 := A * B;
               Shifted : Integer_64;
            begin
               if SEW_Bits > 1 then
                  Shifted := Integer_64 (Roundoff_Unsigned (
                     To_U64 (Product), SEW_Bits - 1, VU.VXRM));
               else
                  Shifted := Product;
               end if;
               Write_Element (VU, Vd, I, SEW,
                 Saturate_Signed (Shifted, SEW_Bits, Sat));
               if Sat then VU.VXSat := True; end if;
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VSMUL_VX;

   ----------------
   -- Rounding shift right
   ----------------

   procedure VSSRL_VV (VU : in out Vector_State;
                       Vd, Vs2, Vs1 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               A     : constant Unsigned_64 :=
                  Unsigned_64 (Read_Element (VU, Vs2, I, SEW));
               Shamt : constant Natural :=
                  Natural (Read_Element (VU, Vs1, I, SEW)
                           and Word (Get_SEW_Bits (SEW) - 1));
            begin
               Write_Element (VU, Vd, I, SEW,
                 Word (Roundoff_Unsigned (A, Shamt, VU.VXRM) and 16#FFFFFFFF#));
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VSSRL_VV;

   procedure VSSRL_VX (VU : in out Vector_State;
                       Vd, Vs2 : Register_Index; Rs1 : Word; VM : Boolean) is
      SEW   : constant SEW_Type := VU.VType.VSEW;
      Shamt : constant Natural :=
         Natural (Rs1 and Word (Get_SEW_Bits (SEW) - 1));
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            Write_Element (VU, Vd, I, SEW,
              Word (Roundoff_Unsigned (
                Unsigned_64 (Read_Element (VU, Vs2, I, SEW)), Shamt, VU.VXRM)
                and 16#FFFFFFFF#));
         end if;
      end loop;
      VU.VStart := 0;
   end VSSRL_VX;

   procedure VSSRL_VI (VU : in out Vector_State;
                       Vd, Vs2 : Register_Index; Imm : Natural;
                       VM : Boolean) is
      SEW   : constant SEW_Type := VU.VType.VSEW;
      Shamt : constant Natural := Imm mod Get_SEW_Bits (SEW);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            Write_Element (VU, Vd, I, SEW,
              Word (Roundoff_Unsigned (
                Unsigned_64 (Read_Element (VU, Vs2, I, SEW)), Shamt, VU.VXRM)
                and 16#FFFFFFFF#));
         end if;
      end loop;
      VU.VStart := 0;
   end VSSRL_VI;

   procedure VSSRA_VV (VU : in out Vector_State;
                       Vd, Vs2, Vs1 : Register_Index; VM : Boolean) is
      SEW      : constant SEW_Type := VU.VType.VSEW;
      SEW_Bits : constant Natural := Get_SEW_Bits (SEW);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               A_S   : constant Integer_64 :=
                  Integer_64 (To_Signed (Read_Element (VU, Vs2, I, SEW)));
               Shamt : constant Natural :=
                  Natural (Read_Element (VU, Vs1, I, SEW)
                           and Word (SEW_Bits - 1));
               Result : Integer_64;
            begin
               if Shamt = 0 then
                  Result := A_S;
               else
                  --  Arithmetic right shift, then round
                  Result := Integer_64 (Roundoff_Unsigned (
                     To_U64 (A_S), Shamt, VU.VXRM));
                  --  Sign extend
                  if A_S < 0 and Shamt > 0 then
                     Result := To_I64 (To_U64 (Result) or
                        Shift_Left (16#FFFFFFFFFFFFFFFF#, 64 - Shamt));
                  end if;
               end if;
               Write_Element (VU, Vd, I, SEW, Word (To_U64 (Result) and 16#FFFFFFFF#));
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VSSRA_VV;

   procedure VSSRA_VX (VU : in out Vector_State;
                       Vd, Vs2 : Register_Index; Rs1 : Word; VM : Boolean) is
      SEW      : constant SEW_Type := VU.VType.VSEW;
      SEW_Bits : constant Natural := Get_SEW_Bits (SEW);
      Shamt    : constant Natural := Natural (Rs1 and Word (SEW_Bits - 1));
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               A_S    : constant Integer_64 :=
                  Integer_64 (To_Signed (Read_Element (VU, Vs2, I, SEW)));
               Result : Integer_64;
            begin
               if Shamt = 0 then
                  Result := A_S;
               else
                  Result := Integer_64 (Roundoff_Unsigned (
                     To_U64 (A_S), Shamt, VU.VXRM));
                  if A_S < 0 then
                     Result := To_I64 (To_U64 (Result) or
                        Shift_Left (16#FFFFFFFFFFFFFFFF#, 64 - Shamt));
                  end if;
               end if;
               Write_Element (VU, Vd, I, SEW, Word (To_U64 (Result) and 16#FFFFFFFF#));
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VSSRA_VX;

   procedure VSSRA_VI (VU : in out Vector_State;
                       Vd, Vs2 : Register_Index; Imm : Natural;
                       VM : Boolean) is
      SEW   : constant SEW_Type := VU.VType.VSEW;
      Shamt : constant Natural := Imm mod Get_SEW_Bits (SEW);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               A_S    : constant Integer_64 :=
                  Integer_64 (To_Signed (Read_Element (VU, Vs2, I, SEW)));
               Result : Integer_64;
            begin
               if Shamt = 0 then
                  Result := A_S;
               else
                  Result := Integer_64 (Roundoff_Unsigned (
                     To_U64 (A_S), Shamt, VU.VXRM));
                  if A_S < 0 then
                     Result := To_I64 (To_U64 (Result) or
                        Shift_Left (16#FFFFFFFFFFFFFFFF#, 64 - Shamt));
                  end if;
               end if;
               Write_Element (VU, Vd, I, SEW, Word (To_U64 (Result) and 16#FFFFFFFF#));
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VSSRA_VI;

   ----------------
   -- Narrowing clip
   ----------------

   procedure VNCLIPU_WV (VU : in out Vector_State;
                         Vd, Vs2, Vs1 : Register_Index; VM : Boolean) is
      SEW      : constant SEW_Type := VU.VType.VSEW;
      SEW_Bits : constant Natural := Get_SEW_Bits (SEW);
      Sat      : Boolean;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               Src   : constant Unsigned_64 := Read_Element_64 (VU, Vs2, I);
               Shamt : constant Natural :=
                  Natural (Read_Element (VU, Vs1, I, SEW) and 16#3F#);
               Shifted : constant Unsigned_64 :=
                  Roundoff_Unsigned (Src, Shamt, VU.VXRM);
            begin
               Write_Element (VU, Vd, I, SEW,
                 Saturate_Unsigned (Shifted, SEW_Bits, Sat));
               if Sat then VU.VXSat := True; end if;
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VNCLIPU_WV;

   procedure VNCLIPU_WX (VU : in out Vector_State;
                         Vd, Vs2 : Register_Index; Rs1 : Word;
                         VM : Boolean) is
      SEW      : constant SEW_Type := VU.VType.VSEW;
      SEW_Bits : constant Natural := Get_SEW_Bits (SEW);
      Shamt    : constant Natural := Natural (Rs1 and 16#3F#);
      Sat      : Boolean;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               Shifted : constant Unsigned_64 :=
                  Roundoff_Unsigned (Read_Element_64 (VU, Vs2, I), Shamt, VU.VXRM);
            begin
               Write_Element (VU, Vd, I, SEW,
                 Saturate_Unsigned (Shifted, SEW_Bits, Sat));
               if Sat then VU.VXSat := True; end if;
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VNCLIPU_WX;

   procedure VNCLIPU_WI (VU : in out Vector_State;
                         Vd, Vs2 : Register_Index; Imm : Natural;
                         VM : Boolean) is
      SEW      : constant SEW_Type := VU.VType.VSEW;
      SEW_Bits : constant Natural := Get_SEW_Bits (SEW);
      Shamt    : constant Natural := Imm mod 64;
      Sat      : Boolean;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               Shifted : constant Unsigned_64 :=
                  Roundoff_Unsigned (Read_Element_64 (VU, Vs2, I), Shamt, VU.VXRM);
            begin
               Write_Element (VU, Vd, I, SEW,
                 Saturate_Unsigned (Shifted, SEW_Bits, Sat));
               if Sat then VU.VXSat := True; end if;
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VNCLIPU_WI;

   procedure VNCLIP_WV (VU : in out Vector_State;
                        Vd, Vs2, Vs1 : Register_Index; VM : Boolean) is
      SEW      : constant SEW_Type := VU.VType.VSEW;
      SEW_Bits : constant Natural := Get_SEW_Bits (SEW);
      Sat      : Boolean;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               Src   : constant Unsigned_64 := Read_Element_64 (VU, Vs2, I);
               Shamt : constant Natural :=
                  Natural (Read_Element (VU, Vs1, I, SEW) and 16#3F#);
               Shifted_U : Unsigned_64;
               Shifted_S : Integer_64;
            begin
               Shifted_U := Shift_Right (Src, Shamt);
               if Shamt > 0 and (Src and 16#8000000000000000#) /= 0 then
                  Shifted_U := Shifted_U or
                    Shift_Left (16#FFFFFFFFFFFFFFFF#, 64 - Shamt);
               end if;
               Shifted_S := Integer_64 (Shifted_U);
               Write_Element (VU, Vd, I, SEW,
                 Saturate_Signed (Shifted_S, SEW_Bits, Sat));
               if Sat then VU.VXSat := True; end if;
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VNCLIP_WV;

   procedure VNCLIP_WX (VU : in out Vector_State;
                        Vd, Vs2 : Register_Index; Rs1 : Word;
                        VM : Boolean) is
      SEW      : constant SEW_Type := VU.VType.VSEW;
      SEW_Bits : constant Natural := Get_SEW_Bits (SEW);
      Shamt    : constant Natural := Natural (Rs1 and 16#3F#);
      Sat      : Boolean;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               Src : constant Unsigned_64 := Read_Element_64 (VU, Vs2, I);
               Shifted_U : Unsigned_64;
               Shifted_S : Integer_64;
            begin
               Shifted_U := Shift_Right (Src, Shamt);
               if Shamt > 0 and (Src and 16#8000000000000000#) /= 0 then
                  Shifted_U := Shifted_U or
                    Shift_Left (16#FFFFFFFFFFFFFFFF#, 64 - Shamt);
               end if;
               Shifted_S := Integer_64 (Shifted_U);
               Write_Element (VU, Vd, I, SEW,
                 Saturate_Signed (Shifted_S, SEW_Bits, Sat));
               if Sat then VU.VXSat := True; end if;
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VNCLIP_WX;

   procedure VNCLIP_WI (VU : in out Vector_State;
                        Vd, Vs2 : Register_Index; Imm : Natural;
                        VM : Boolean) is
      SEW      : constant SEW_Type := VU.VType.VSEW;
      SEW_Bits : constant Natural := Get_SEW_Bits (SEW);
      Shamt    : constant Natural := Imm mod 64;
      Sat      : Boolean;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               Src : constant Unsigned_64 := Read_Element_64 (VU, Vs2, I);
               Shifted_U : Unsigned_64;
               Shifted_S : Integer_64;
            begin
               Shifted_U := Shift_Right (Src, Shamt);
               if Shamt > 0 and (Src and 16#8000000000000000#) /= 0 then
                  Shifted_U := Shifted_U or
                    Shift_Left (16#FFFFFFFFFFFFFFFF#, 64 - Shamt);
               end if;
               Shifted_S := Integer_64 (Shifted_U);
               Write_Element (VU, Vd, I, SEW,
                 Saturate_Signed (Shifted_S, SEW_Bits, Sat));
               if Sat then VU.VXSat := True; end if;
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VNCLIP_WI;

   ----------------
   -- Widening multiply-add
   ----------------

   procedure VWMACCU_VV (VU : in out Vector_State;
                         Vd, Vs1, Vs2 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               A : constant Unsigned_64 := Unsigned_64 (Read_Element (VU, Vs1, I, SEW));
               B : constant Unsigned_64 := Unsigned_64 (Read_Element (VU, Vs2, I, SEW));
               D : constant Unsigned_64 := Read_Element_64 (VU, Vd, I);
            begin
               Write_Element_64 (VU, Vd, I, D + A * B);
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VWMACCU_VV;

   procedure VWMACCU_VX (VU : in out Vector_State;
                         Vd : Register_Index; Rs1 : Word;
                         Vs2 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      A   : constant Unsigned_64 := Unsigned_64 (Rs1);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               B : constant Unsigned_64 := Unsigned_64 (Read_Element (VU, Vs2, I, SEW));
               D : constant Unsigned_64 := Read_Element_64 (VU, Vd, I);
            begin
               Write_Element_64 (VU, Vd, I, D + A * B);
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VWMACCU_VX;

   procedure VWMACC_VV (VU : in out Vector_State;
                        Vd, Vs1, Vs2 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               A : constant Integer_64 := Integer_64 (To_Signed (Read_Element (VU, Vs1, I, SEW)));
               B : constant Integer_64 := Integer_64 (To_Signed (Read_Element (VU, Vs2, I, SEW)));
               D : constant Integer_64 := Integer_64 (Read_Element_64 (VU, Vd, I));
            begin
               Write_Element_64 (VU, Vd, I, To_U64 (D + A * B));
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VWMACC_VV;

   procedure VWMACC_VX (VU : in out Vector_State;
                        Vd : Register_Index; Rs1 : Word;
                        Vs2 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      A   : constant Integer_64 := Integer_64 (To_Signed (Rs1));
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               B : constant Integer_64 := Integer_64 (To_Signed (Read_Element (VU, Vs2, I, SEW)));
               D : constant Integer_64 := Integer_64 (Read_Element_64 (VU, Vd, I));
            begin
               Write_Element_64 (VU, Vd, I, To_U64 (D + A * B));
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VWMACC_VX;

   procedure VWMACCSU_VV (VU : in out Vector_State;
                          Vd, Vs1, Vs2 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               A : constant Integer_64 := Integer_64 (To_Signed (Read_Element (VU, Vs1, I, SEW)));
               B : constant Unsigned_64 := Unsigned_64 (Read_Element (VU, Vs2, I, SEW));
               D : constant Integer_64 := Integer_64 (Read_Element_64 (VU, Vd, I));
            begin
               Write_Element_64 (VU, Vd, I, To_U64 (D + A * Integer_64 (B)));
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VWMACCSU_VV;

   procedure VWMACCSU_VX (VU : in out Vector_State;
                          Vd : Register_Index; Rs1 : Word;
                          Vs2 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      A   : constant Integer_64 := Integer_64 (To_Signed (Rs1));
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               B : constant Unsigned_64 := Unsigned_64 (Read_Element (VU, Vs2, I, SEW));
               D : constant Integer_64 := Integer_64 (Read_Element_64 (VU, Vd, I));
            begin
               Write_Element_64 (VU, Vd, I, To_U64 (D + A * Integer_64 (B)));
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VWMACCSU_VX;

   procedure VWMACCUS_VX (VU : in out Vector_State;
                          Vd : Register_Index; Rs1 : Word;
                          Vs2 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      A   : constant Unsigned_64 := Unsigned_64 (Rs1);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               B : constant Integer_64 := Integer_64 (To_Signed (Read_Element (VU, Vs2, I, SEW)));
               D : constant Integer_64 := Integer_64 (Read_Element_64 (VU, Vd, I));
            begin
               Write_Element_64 (VU, Vd, I, To_U64 (D + Integer_64 (A) * B));
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VWMACCUS_VX;

   ----------------
   -- VMULHSU
   ----------------

   procedure VMULHSU_VV (VU : in out Vector_State;
                         Vd, Vs2, Vs1 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               A : constant Integer_64  := VRead_S (VU, Vs2, I, SEW);
               B : constant Unsigned_64 := VRead_U (VU, Vs1, I, SEW);
            begin
               if SEW = SEW_64 then
                  VWrite (VU, Vd, I, SEW, SUMulhi64 (A, B));
               else
                  VWrite (VU, Vd, I, SEW,
                    Shift_Right (To_U64 (A * To_I64 (B)), Get_SEW_Bits (SEW)));
               end if;
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VMULHSU_VV;

   procedure VMULHSU_VX (VU : in out Vector_State;
                         Vd, Vs2 : Register_Index; Rs1 : Word; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               A : constant Integer_64  := VRead_S (VU, Vs2, I, SEW);
               B : constant Unsigned_64 := Splat_U (Rs1);
            begin
               if SEW = SEW_64 then
                  VWrite (VU, Vd, I, SEW, SUMulhi64 (A, B));
               else
                  VWrite (VU, Vd, I, SEW,
                    Shift_Right (To_U64 (A * To_I64 (B)), Get_SEW_Bits (SEW)));
               end if;
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VMULHSU_VX;

   ----------------
   -- Averaging add/sub
   ----------------

   procedure VAADDU_VV (VU : in out Vector_State;
                        Vd, Vs2, Vs1 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               A : constant Unsigned_64 := Unsigned_64 (Read_Element (VU, Vs2, I, SEW));
               B : constant Unsigned_64 := Unsigned_64 (Read_Element (VU, Vs1, I, SEW));
            begin
               Write_Element (VU, Vd, I, SEW,
                 Word (Roundoff_Unsigned (A + B, 1, VU.VXRM) and 16#FFFFFFFF#));
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VAADDU_VV;

   procedure VAADDU_VX (VU : in out Vector_State;
                        Vd, Vs2 : Register_Index; Rs1 : Word; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      B   : constant Unsigned_64 := Unsigned_64 (Rs1);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            Write_Element (VU, Vd, I, SEW,
              Word (Roundoff_Unsigned (
                Unsigned_64 (Read_Element (VU, Vs2, I, SEW)) + B, 1, VU.VXRM)
                and 16#FFFFFFFF#));
         end if;
      end loop;
      VU.VStart := 0;
   end VAADDU_VX;

   procedure VAADD_VV (VU : in out Vector_State;
                       Vd, Vs2, Vs1 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               A : constant Integer_64 := Integer_64 (To_Signed (Read_Element (VU, Vs2, I, SEW)));
               B : constant Integer_64 := Integer_64 (To_Signed (Read_Element (VU, Vs1, I, SEW)));
               Sum : constant Unsigned_64 := To_U64 (A + B);
            begin
               Write_Element (VU, Vd, I, SEW,
                 Word (Roundoff_Unsigned (Sum, 1, VU.VXRM) and 16#FFFFFFFF#));
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VAADD_VV;

   procedure VAADD_VX (VU : in out Vector_State;
                       Vd, Vs2 : Register_Index; Rs1 : Word; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      B   : constant Integer_64 := Integer_64 (To_Signed (Rs1));
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               A : constant Integer_64 := Integer_64 (To_Signed (Read_Element (VU, Vs2, I, SEW)));
            begin
               Write_Element (VU, Vd, I, SEW,
                 Word (Roundoff_Unsigned (To_U64 (A + B), 1, VU.VXRM) and 16#FFFFFFFF#));
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VAADD_VX;

   procedure VASUBU_VV (VU : in out Vector_State;
                        Vd, Vs2, Vs1 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               A : constant Unsigned_64 := Unsigned_64 (Read_Element (VU, Vs2, I, SEW));
               B : constant Unsigned_64 := Unsigned_64 (Read_Element (VU, Vs1, I, SEW));
            begin
               Write_Element (VU, Vd, I, SEW,
                 Word (Roundoff_Unsigned (A - B, 1, VU.VXRM) and 16#FFFFFFFF#));
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VASUBU_VV;

   procedure VASUBU_VX (VU : in out Vector_State;
                        Vd, Vs2 : Register_Index; Rs1 : Word; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      B   : constant Unsigned_64 := Unsigned_64 (Rs1);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            Write_Element (VU, Vd, I, SEW,
              Word (Roundoff_Unsigned (
                Unsigned_64 (Read_Element (VU, Vs2, I, SEW)) - B, 1, VU.VXRM)
                and 16#FFFFFFFF#));
         end if;
      end loop;
      VU.VStart := 0;
   end VASUBU_VX;

   procedure VASUB_VV (VU : in out Vector_State;
                       Vd, Vs2, Vs1 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               A : constant Integer_64 := Integer_64 (To_Signed (Read_Element (VU, Vs2, I, SEW)));
               B : constant Integer_64 := Integer_64 (To_Signed (Read_Element (VU, Vs1, I, SEW)));
            begin
               Write_Element (VU, Vd, I, SEW,
                 Word (Roundoff_Unsigned (To_U64 (A - B), 1, VU.VXRM) and 16#FFFFFFFF#));
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VASUB_VV;

   procedure VASUB_VX (VU : in out Vector_State;
                       Vd, Vs2 : Register_Index; Rs1 : Word; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      B   : constant Integer_64 := Integer_64 (To_Signed (Rs1));
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            declare
               A : constant Integer_64 := Integer_64 (To_Signed (Read_Element (VU, Vs2, I, SEW)));
            begin
               Write_Element (VU, Vd, I, SEW,
                 Word (Roundoff_Unsigned (To_U64 (A - B), 1, VU.VXRM) and 16#FFFFFFFF#));
            end;
         end if;
      end loop;
      VU.VStart := 0;
   end VASUB_VX;

   ----------------
   -- FP comparison
   ----------------

   procedure VMFEQ_VV (VU : in out Vector_State; FP : FPU_Access;
                       Vd, Vs2, Vs1 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if SEW = SEW_32 then
               Set_Mask_Bit (VU, Vd, I,
                 FEQ_S (FP.all, Read_Element (VU, Vs2, I, SEW),
                        Read_Element (VU, Vs1, I, SEW)) = 1);
            elsif SEW = SEW_64 then
               Set_Mask_Bit (VU, Vd, I,
                 FEQ_D (FP.all, FP_Register (Read_Element_64 (VU, Vs2, I)),
                        FP_Register (Read_Element_64 (VU, Vs1, I))) = 1);
            end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VMFEQ_VV;

   procedure VMFEQ_VF (VU : in out Vector_State; FP : FPU_Access;
                       Vd, Vs2 : Register_Index; Fs1 : Word; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if SEW = SEW_32 then
               Set_Mask_Bit (VU, Vd, I,
                 FEQ_S (FP.all, Read_Element (VU, Vs2, I, SEW), Fs1) = 1);
            end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VMFEQ_VF;

   procedure VMFLE_VV (VU : in out Vector_State; FP : FPU_Access;
                       Vd, Vs2, Vs1 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if SEW = SEW_32 then
               Set_Mask_Bit (VU, Vd, I,
                 FLE_S (FP.all, Read_Element (VU, Vs2, I, SEW),
                        Read_Element (VU, Vs1, I, SEW)) = 1);
            elsif SEW = SEW_64 then
               Set_Mask_Bit (VU, Vd, I,
                 FLE_D (FP.all, FP_Register (Read_Element_64 (VU, Vs2, I)),
                        FP_Register (Read_Element_64 (VU, Vs1, I))) = 1);
            end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VMFLE_VV;

   procedure VMFLE_VF (VU : in out Vector_State; FP : FPU_Access;
                       Vd, Vs2 : Register_Index; Fs1 : Word; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if SEW = SEW_32 then
               Set_Mask_Bit (VU, Vd, I,
                 FLE_S (FP.all, Read_Element (VU, Vs2, I, SEW), Fs1) = 1);
            end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VMFLE_VF;

   procedure VMFLT_VV (VU : in out Vector_State; FP : FPU_Access;
                       Vd, Vs2, Vs1 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if SEW = SEW_32 then
               Set_Mask_Bit (VU, Vd, I,
                 FLT_S (FP.all, Read_Element (VU, Vs2, I, SEW),
                        Read_Element (VU, Vs1, I, SEW)) = 1);
            elsif SEW = SEW_64 then
               Set_Mask_Bit (VU, Vd, I,
                 FLT_D (FP.all, FP_Register (Read_Element_64 (VU, Vs2, I)),
                        FP_Register (Read_Element_64 (VU, Vs1, I))) = 1);
            end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VMFLT_VV;

   procedure VMFLT_VF (VU : in out Vector_State; FP : FPU_Access;
                       Vd, Vs2 : Register_Index; Fs1 : Word; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if SEW = SEW_32 then
               Set_Mask_Bit (VU, Vd, I,
                 FLT_S (FP.all, Read_Element (VU, Vs2, I, SEW), Fs1) = 1);
            end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VMFLT_VF;

   procedure VMFNE_VV (VU : in out Vector_State; FP : FPU_Access;
                       Vd, Vs2, Vs1 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if SEW = SEW_32 then
               Set_Mask_Bit (VU, Vd, I,
                 FEQ_S (FP.all, Read_Element (VU, Vs2, I, SEW),
                        Read_Element (VU, Vs1, I, SEW)) = 0);
            elsif SEW = SEW_64 then
               Set_Mask_Bit (VU, Vd, I,
                 FEQ_D (FP.all, FP_Register (Read_Element_64 (VU, Vs2, I)),
                        FP_Register (Read_Element_64 (VU, Vs1, I))) = 0);
            end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VMFNE_VV;

   procedure VMFNE_VF (VU : in out Vector_State; FP : FPU_Access;
                       Vd, Vs2 : Register_Index; Fs1 : Word; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if SEW = SEW_32 then
               Set_Mask_Bit (VU, Vd, I,
                 FEQ_S (FP.all, Read_Element (VU, Vs2, I, SEW), Fs1) = 0);
            end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VMFNE_VF;

   procedure VMFGT_VF (VU : in out Vector_State; FP : FPU_Access;
                       Vd, Vs2 : Register_Index; Fs1 : Word; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if SEW = SEW_32 then
               Set_Mask_Bit (VU, Vd, I,
                 FLT_S (FP.all, Fs1, Read_Element (VU, Vs2, I, SEW)) = 1);
            end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VMFGT_VF;

   procedure VMFGE_VF (VU : in out Vector_State; FP : FPU_Access;
                       Vd, Vs2 : Register_Index; Fs1 : Word; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if SEW = SEW_32 then
               Set_Mask_Bit (VU, Vd, I,
                 FLE_S (FP.all, Fs1, Read_Element (VU, Vs2, I, SEW)) = 1);
            end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VMFGE_VF;

   ----------------
   -- FP sign injection
   ----------------

   procedure VFSGNJ_VV (VU : in out Vector_State; FP : FPU_Access;
                        Vd, Vs2, Vs1 : Register_Index; VM : Boolean) is
      pragma Unreferenced (FP);
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if SEW = SEW_32 then
               Write_Element (VU, Vd, I, SEW,
                 FSGNJ_S (Read_Element (VU, Vs2, I, SEW),
                          Read_Element (VU, Vs1, I, SEW)));
            elsif SEW = SEW_64 then
               Write_Element_64 (VU, Vd, I,
                 Unsigned_64 (FSGNJ_D (
                   FP_Register (Read_Element_64 (VU, Vs2, I)),
                   FP_Register (Read_Element_64 (VU, Vs1, I)))));
            end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VFSGNJ_VV;

   procedure VFSGNJ_VF (VU : in out Vector_State; FP : FPU_Access;
                        Vd, Vs2 : Register_Index; Fs1 : Word; VM : Boolean) is
      pragma Unreferenced (FP);
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if SEW = SEW_32 then
               Write_Element (VU, Vd, I, SEW,
                 FSGNJ_S (Read_Element (VU, Vs2, I, SEW), Fs1));
            end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VFSGNJ_VF;

   procedure VFSGNJN_VV (VU : in out Vector_State; FP : FPU_Access;
                         Vd, Vs2, Vs1 : Register_Index; VM : Boolean) is
      pragma Unreferenced (FP);
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if SEW = SEW_32 then
               Write_Element (VU, Vd, I, SEW,
                 FSGNJN_S (Read_Element (VU, Vs2, I, SEW),
                           Read_Element (VU, Vs1, I, SEW)));
            elsif SEW = SEW_64 then
               Write_Element_64 (VU, Vd, I,
                 Unsigned_64 (FSGNJN_D (
                   FP_Register (Read_Element_64 (VU, Vs2, I)),
                   FP_Register (Read_Element_64 (VU, Vs1, I)))));
            end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VFSGNJN_VV;

   procedure VFSGNJN_VF (VU : in out Vector_State; FP : FPU_Access;
                         Vd, Vs2 : Register_Index; Fs1 : Word; VM : Boolean) is
      pragma Unreferenced (FP);
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if SEW = SEW_32 then
               Write_Element (VU, Vd, I, SEW,
                 FSGNJN_S (Read_Element (VU, Vs2, I, SEW), Fs1));
            end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VFSGNJN_VF;

   procedure VFSGNJX_VV (VU : in out Vector_State; FP : FPU_Access;
                         Vd, Vs2, Vs1 : Register_Index; VM : Boolean) is
      pragma Unreferenced (FP);
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if SEW = SEW_32 then
               Write_Element (VU, Vd, I, SEW,
                 FSGNJX_S (Read_Element (VU, Vs2, I, SEW),
                           Read_Element (VU, Vs1, I, SEW)));
            elsif SEW = SEW_64 then
               Write_Element_64 (VU, Vd, I,
                 Unsigned_64 (FSGNJX_D (
                   FP_Register (Read_Element_64 (VU, Vs2, I)),
                   FP_Register (Read_Element_64 (VU, Vs1, I)))));
            end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VFSGNJX_VV;

   procedure VFSGNJX_VF (VU : in out Vector_State; FP : FPU_Access;
                         Vd, Vs2 : Register_Index; Fs1 : Word; VM : Boolean) is
      pragma Unreferenced (FP);
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if SEW = SEW_32 then
               Write_Element (VU, Vd, I, SEW,
                 FSGNJX_S (Read_Element (VU, Vs2, I, SEW), Fs1));
            end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VFSGNJX_VF;

   ----------------
   -- FP class, reciprocal, merge/move, reverse ops
   ----------------

   procedure VFCLASS_V (VU : in out Vector_State; FP : FPU_Access;
                        Vd, Vs2 : Register_Index; VM : Boolean) is
      pragma Unreferenced (FP);
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if SEW = SEW_32 then
               Write_Element (VU, Vd, I, SEW,
                 FCLASS_S (Read_Element (VU, Vs2, I, SEW)));
            elsif SEW = SEW_64 then
               Write_Element (VU, Vd, I, SEW,
                 FCLASS_D (FP_Register (Read_Element_64 (VU, Vs2, I))));
            end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VFCLASS_V;

   procedure VFRSQRT7_V (VU : in out Vector_State; FP : FPU_Access;
                         Vd, Vs2 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      RM  : constant Rounding_Mode := Resolve_RM (FP);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if SEW = SEW_32 then
               declare
                  Sq : constant Word := FSQRT_S (FP.all, Read_Element (VU, Vs2, I, SEW), RM);
                  One : constant Word := 16#3F800000#;  -- 1.0f
               begin
                  Write_Element (VU, Vd, I, SEW, FDIV_S (FP.all, One, Sq, RM));
               end;
            elsif SEW = SEW_64 then
               declare
                  Sq : constant FP_Register := FSQRT_D (FP.all,
                     FP_Register (Read_Element_64 (VU, Vs2, I)), RM);
                  One : constant FP_Register := 16#3FF0000000000000#;
               begin
                  Write_Element_64 (VU, Vd, I,
                    Unsigned_64 (FDIV_D (FP.all, One, Sq, RM)));
               end;
            end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VFRSQRT7_V;

   procedure VFREC7_V (VU : in out Vector_State; FP : FPU_Access;
                       Vd, Vs2 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      RM  : constant Rounding_Mode := Resolve_RM (FP);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if SEW = SEW_32 then
               declare
                  One : constant Word := 16#3F800000#;
               begin
                  Write_Element (VU, Vd, I, SEW,
                    FDIV_S (FP.all, One, Read_Element (VU, Vs2, I, SEW), RM));
               end;
            elsif SEW = SEW_64 then
               declare
                  One : constant FP_Register := 16#3FF0000000000000#;
               begin
                  Write_Element_64 (VU, Vd, I,
                    Unsigned_64 (FDIV_D (FP.all, One,
                      FP_Register (Read_Element_64 (VU, Vs2, I)), RM)));
               end;
            end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VFREC7_V;

   procedure VFMERGE_VF (VU : in out Vector_State;
                         Vd, Vs2 : Register_Index; Fs1 : Word) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if Get_Mask_Bit (VU, I) then
            Write_Element (VU, Vd, I, SEW, Fs1);
         else
            Write_Element (VU, Vd, I, SEW, Read_Element (VU, Vs2, I, SEW));
         end if;
      end loop;
      VU.VStart := 0;
   end VFMERGE_VF;

   procedure VFMV_V_F (VU : in out Vector_State;
                       Vd : Register_Index; Fs1 : Word) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         Write_Element (VU, Vd, I, SEW, Fs1);
      end loop;
      VU.VStart := 0;
   end VFMV_V_F;

   procedure VFRDIV_VF (VU : in out Vector_State; FP : FPU_Access;
                        Vd, Vs2 : Register_Index; Fs1 : Word; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      RM  : constant Rounding_Mode := Resolve_RM (FP);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if SEW = SEW_32 then
               Write_Element (VU, Vd, I, SEW,
                 FDIV_S (FP.all, Fs1, Read_Element (VU, Vs2, I, SEW), RM));
            end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VFRDIV_VF;

   procedure VFRSUB_VF (VU : in out Vector_State; FP : FPU_Access;
                        Vd, Vs2 : Register_Index; Fs1 : Word; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      RM  : constant Rounding_Mode := Resolve_RM (FP);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if SEW = SEW_32 then
               Write_Element (VU, Vd, I, SEW,
                 FSUB_S (FP.all, Fs1, Read_Element (VU, Vs2, I, SEW), RM));
            end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VFRSUB_VF;

   function VFMV_F_S (VU : Vector_State; Vs2 : Register_Index) return Word is
   begin
      return Read_Element (VU, Vs2, 0, VU.VType.VSEW);
   end VFMV_F_S;

   procedure VFMV_S_F (VU : in out Vector_State;
                       Vd : Register_Index; Fs1 : Word) is
   begin
      if VU.VL > 0 then
         Write_Element (VU, Vd, 0, VU.VType.VSEW, Fs1);
      end if;
   end VFMV_S_F;

   ----------------
   -- FP single-width conversion
   ----------------

   procedure VFCVT_XU_F_V (VU : in out Vector_State; FP : FPU_Access;
                           Vd, Vs2 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      RM  : constant Rounding_Mode := Resolve_RM (FP);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if SEW = SEW_32 then
               Write_Element (VU, Vd, I, SEW,
                 FCVT_WU_S (FP.all, Read_Element (VU, Vs2, I, SEW), RM));
            end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VFCVT_XU_F_V;

   procedure VFCVT_X_F_V (VU : in out Vector_State; FP : FPU_Access;
                          Vd, Vs2 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      RM  : constant Rounding_Mode := Resolve_RM (FP);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if SEW = SEW_32 then
               Write_Element (VU, Vd, I, SEW,
                 FCVT_W_S (FP.all, Read_Element (VU, Vs2, I, SEW), RM));
            end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VFCVT_X_F_V;

   procedure VFCVT_F_XU_V (VU : in out Vector_State; FP : FPU_Access;
                           Vd, Vs2 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      RM  : constant Rounding_Mode := Resolve_RM (FP);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if SEW = SEW_32 then
               Write_Element (VU, Vd, I, SEW,
                 FCVT_S_WU (FP.all, Read_Element (VU, Vs2, I, SEW), RM));
            end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VFCVT_F_XU_V;

   procedure VFCVT_F_X_V (VU : in out Vector_State; FP : FPU_Access;
                          Vd, Vs2 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      RM  : constant Rounding_Mode := Resolve_RM (FP);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if SEW = SEW_32 then
               Write_Element (VU, Vd, I, SEW,
                 FCVT_S_W (FP.all, Read_Element (VU, Vs2, I, SEW), RM));
            end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VFCVT_F_X_V;

   procedure VFCVT_RTZ_XU_F_V (VU : in out Vector_State; FP : FPU_Access;
                               Vd, Vs2 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if SEW = SEW_32 then
               Write_Element (VU, Vd, I, SEW,
                 FCVT_WU_S (FP.all, Read_Element (VU, Vs2, I, SEW), RTZ));
            end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VFCVT_RTZ_XU_F_V;

   procedure VFCVT_RTZ_X_F_V (VU : in out Vector_State; FP : FPU_Access;
                              Vd, Vs2 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if SEW = SEW_32 then
               Write_Element (VU, Vd, I, SEW,
                 FCVT_W_S (FP.all, Read_Element (VU, Vs2, I, SEW), RTZ));
            end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VFCVT_RTZ_X_F_V;

   ----------------
   -- FP widening conversion
   ----------------

   procedure VFWCVT_XU_F_V (VU : in out Vector_State; FP : FPU_Access;
                            Vd, Vs2 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      RM  : constant Rounding_Mode := Resolve_RM (FP);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if SEW = SEW_32 then
               declare
                  Val : constant Word := Read_Element (VU, Vs2, I, SEW);
                  Dbl : constant FP_Register := FCVT_D_S (FP.all, Val, RM);
                  Res : constant Word := FCVT_WU_D (FP.all, Dbl, RM);
               begin
                  Write_Element_64 (VU, Vd, I, Unsigned_64 (Res));
               end;
            end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VFWCVT_XU_F_V;

   procedure VFWCVT_X_F_V (VU : in out Vector_State; FP : FPU_Access;
                           Vd, Vs2 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      RM  : constant Rounding_Mode := Resolve_RM (FP);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if SEW = SEW_32 then
               declare
                  Val : constant Word := Read_Element (VU, Vs2, I, SEW);
                  Dbl : constant FP_Register := FCVT_D_S (FP.all, Val, RM);
                  Res : constant Word := FCVT_W_D (FP.all, Dbl, RM);
               begin
                  Write_Element_64 (VU, Vd, I, Unsigned_64 (Res));
               end;
            end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VFWCVT_X_F_V;

   procedure VFWCVT_F_XU_V (VU : in out Vector_State; FP : FPU_Access;
                            Vd, Vs2 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      RM  : constant Rounding_Mode := Resolve_RM (FP);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if SEW = SEW_32 then
               Write_Element_64 (VU, Vd, I,
                 Unsigned_64 (FCVT_D_WU (FP.all, Read_Element (VU, Vs2, I, SEW), RM)));
            end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VFWCVT_F_XU_V;

   procedure VFWCVT_F_X_V (VU : in out Vector_State; FP : FPU_Access;
                           Vd, Vs2 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      RM  : constant Rounding_Mode := Resolve_RM (FP);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if SEW = SEW_32 then
               Write_Element_64 (VU, Vd, I,
                 Unsigned_64 (FCVT_D_W (FP.all, Read_Element (VU, Vs2, I, SEW), RM)));
            end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VFWCVT_F_X_V;

   procedure VFWCVT_F_F_V (VU : in out Vector_State; FP : FPU_Access;
                           Vd, Vs2 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      RM  : constant Rounding_Mode := Resolve_RM (FP);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if SEW = SEW_32 then
               Write_Element_64 (VU, Vd, I,
                 Unsigned_64 (FCVT_D_S (FP.all, Read_Element (VU, Vs2, I, SEW), RM)));
            end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VFWCVT_F_F_V;

   procedure VFWCVT_RTZ_XU_F_V (VU : in out Vector_State; FP : FPU_Access;
                                Vd, Vs2 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if SEW = SEW_32 then
               declare
                  Dbl : constant FP_Register := FCVT_D_S (FP.all,
                     Read_Element (VU, Vs2, I, SEW), RTZ);
               begin
                  Write_Element_64 (VU, Vd, I,
                    Unsigned_64 (FCVT_WU_D (FP.all, Dbl, RTZ)));
               end;
            end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VFWCVT_RTZ_XU_F_V;

   procedure VFWCVT_RTZ_X_F_V (VU : in out Vector_State; FP : FPU_Access;
                               Vd, Vs2 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if SEW = SEW_32 then
               declare
                  Dbl : constant FP_Register := FCVT_D_S (FP.all,
                     Read_Element (VU, Vs2, I, SEW), RTZ);
               begin
                  Write_Element_64 (VU, Vd, I,
                    Unsigned_64 (FCVT_W_D (FP.all, Dbl, RTZ)));
               end;
            end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VFWCVT_RTZ_X_F_V;

   ----------------
   -- FP narrowing conversion
   ----------------

   procedure VFNCVT_XU_F_W (VU : in out Vector_State; FP : FPU_Access;
                            Vd, Vs2 : Register_Index; VM : Boolean) is
      RM : constant Rounding_Mode := Resolve_RM (FP);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            Write_Element (VU, Vd, I, VU.VType.VSEW,
              FCVT_WU_D (FP.all, FP_Register (Read_Element_64 (VU, Vs2, I)), RM));
         end if;
      end loop;
      VU.VStart := 0;
   end VFNCVT_XU_F_W;

   procedure VFNCVT_X_F_W (VU : in out Vector_State; FP : FPU_Access;
                           Vd, Vs2 : Register_Index; VM : Boolean) is
      RM : constant Rounding_Mode := Resolve_RM (FP);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            Write_Element (VU, Vd, I, VU.VType.VSEW,
              FCVT_W_D (FP.all, FP_Register (Read_Element_64 (VU, Vs2, I)), RM));
         end if;
      end loop;
      VU.VStart := 0;
   end VFNCVT_X_F_W;

   procedure VFNCVT_F_XU_W (VU : in out Vector_State; FP : FPU_Access;
                            Vd, Vs2 : Register_Index; VM : Boolean) is
      RM : constant Rounding_Mode := Resolve_RM (FP);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            Write_Element (VU, Vd, I, VU.VType.VSEW,
              FCVT_S_WU (FP.all, Word (Read_Element_64 (VU, Vs2, I) and 16#FFFFFFFF#), RM));
         end if;
      end loop;
      VU.VStart := 0;
   end VFNCVT_F_XU_W;

   procedure VFNCVT_F_X_W (VU : in out Vector_State; FP : FPU_Access;
                           Vd, Vs2 : Register_Index; VM : Boolean) is
      RM : constant Rounding_Mode := Resolve_RM (FP);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            Write_Element (VU, Vd, I, VU.VType.VSEW,
              FCVT_S_W (FP.all, Word (Read_Element_64 (VU, Vs2, I) and 16#FFFFFFFF#), RM));
         end if;
      end loop;
      VU.VStart := 0;
   end VFNCVT_F_X_W;

   procedure VFNCVT_F_F_W (VU : in out Vector_State; FP : FPU_Access;
                           Vd, Vs2 : Register_Index; VM : Boolean) is
      RM : constant Rounding_Mode := Resolve_RM (FP);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            Write_Element (VU, Vd, I, VU.VType.VSEW,
              FCVT_S_D (FP.all, FP_Register (Read_Element_64 (VU, Vs2, I)), RM));
         end if;
      end loop;
      VU.VStart := 0;
   end VFNCVT_F_F_W;

   procedure VFNCVT_ROD_F_F_W (VU : in out Vector_State; FP : FPU_Access;
                               Vd, Vs2 : Register_Index; VM : Boolean) is
   begin
      --  ROD rounding: use RDN as approximation
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            Write_Element (VU, Vd, I, VU.VType.VSEW,
              FCVT_S_D (FP.all, FP_Register (Read_Element_64 (VU, Vs2, I)), RDN));
         end if;
      end loop;
      VU.VStart := 0;
   end VFNCVT_ROD_F_F_W;

   procedure VFNCVT_RTZ_XU_F_W (VU : in out Vector_State; FP : FPU_Access;
                                Vd, Vs2 : Register_Index; VM : Boolean) is
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            Write_Element (VU, Vd, I, VU.VType.VSEW,
              FCVT_WU_D (FP.all, FP_Register (Read_Element_64 (VU, Vs2, I)), RTZ));
         end if;
      end loop;
      VU.VStart := 0;
   end VFNCVT_RTZ_XU_F_W;

   procedure VFNCVT_RTZ_X_F_W (VU : in out Vector_State; FP : FPU_Access;
                               Vd, Vs2 : Register_Index; VM : Boolean) is
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            Write_Element (VU, Vd, I, VU.VType.VSEW,
              FCVT_W_D (FP.all, FP_Register (Read_Element_64 (VU, Vs2, I)), RTZ));
         end if;
      end loop;
      VU.VStart := 0;
   end VFNCVT_RTZ_X_F_W;

   ----------------
   -- FP widening arithmetic
   ----------------

   procedure VFWADD_VV (VU : in out Vector_State; FP : FPU_Access;
                        Vd, Vs2, Vs1 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      RM  : constant Rounding_Mode := Resolve_RM (FP);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if SEW = SEW_32 then
               declare
                  A : constant FP_Register := FCVT_D_S (FP.all, Read_Element (VU, Vs2, I, SEW), RM);
                  B : constant FP_Register := FCVT_D_S (FP.all, Read_Element (VU, Vs1, I, SEW), RM);
               begin
                  Write_Element_64 (VU, Vd, I, Unsigned_64 (FADD_D (FP.all, A, B, RM)));
               end;
            end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VFWADD_VV;

   procedure VFWADD_VF (VU : in out Vector_State; FP : FPU_Access;
                        Vd, Vs2 : Register_Index; Fs1 : Word; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      RM  : constant Rounding_Mode := Resolve_RM (FP);
      B   : constant FP_Register := FCVT_D_S (FP.all, Fs1, RM);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if SEW = SEW_32 then
               declare
                  A : constant FP_Register := FCVT_D_S (FP.all, Read_Element (VU, Vs2, I, SEW), RM);
               begin
                  Write_Element_64 (VU, Vd, I, Unsigned_64 (FADD_D (FP.all, A, B, RM)));
               end;
            end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VFWADD_VF;

   procedure VFWSUB_VV (VU : in out Vector_State; FP : FPU_Access;
                        Vd, Vs2, Vs1 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      RM  : constant Rounding_Mode := Resolve_RM (FP);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if SEW = SEW_32 then
               declare
                  A : constant FP_Register := FCVT_D_S (FP.all, Read_Element (VU, Vs2, I, SEW), RM);
                  B : constant FP_Register := FCVT_D_S (FP.all, Read_Element (VU, Vs1, I, SEW), RM);
               begin
                  Write_Element_64 (VU, Vd, I, Unsigned_64 (FSUB_D (FP.all, A, B, RM)));
               end;
            end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VFWSUB_VV;

   procedure VFWSUB_VF (VU : in out Vector_State; FP : FPU_Access;
                        Vd, Vs2 : Register_Index; Fs1 : Word; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      RM  : constant Rounding_Mode := Resolve_RM (FP);
      B   : constant FP_Register := FCVT_D_S (FP.all, Fs1, RM);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if SEW = SEW_32 then
               declare
                  A : constant FP_Register := FCVT_D_S (FP.all, Read_Element (VU, Vs2, I, SEW), RM);
               begin
                  Write_Element_64 (VU, Vd, I, Unsigned_64 (FSUB_D (FP.all, A, B, RM)));
               end;
            end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VFWSUB_VF;

   procedure VFWADDW_VV (VU : in out Vector_State; FP : FPU_Access;
                         Vd, Vs2, Vs1 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      RM  : constant Rounding_Mode := Resolve_RM (FP);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if SEW = SEW_32 then
               declare
                  A : constant FP_Register := FP_Register (Read_Element_64 (VU, Vs2, I));
                  B : constant FP_Register := FCVT_D_S (FP.all, Read_Element (VU, Vs1, I, SEW), RM);
               begin
                  Write_Element_64 (VU, Vd, I, Unsigned_64 (FADD_D (FP.all, A, B, RM)));
               end;
            end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VFWADDW_VV;

   procedure VFWADDW_VF (VU : in out Vector_State; FP : FPU_Access;
                         Vd, Vs2 : Register_Index; Fs1 : Word; VM : Boolean) is
      RM : constant Rounding_Mode := Resolve_RM (FP);
      B  : constant FP_Register := FCVT_D_S (FP.all, Fs1, RM);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            Write_Element_64 (VU, Vd, I,
              Unsigned_64 (FADD_D (FP.all,
                FP_Register (Read_Element_64 (VU, Vs2, I)), B, RM)));
         end if;
      end loop;
      VU.VStart := 0;
   end VFWADDW_VF;

   procedure VFWSUBW_VV (VU : in out Vector_State; FP : FPU_Access;
                         Vd, Vs2, Vs1 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      RM  : constant Rounding_Mode := Resolve_RM (FP);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if SEW = SEW_32 then
               declare
                  A : constant FP_Register := FP_Register (Read_Element_64 (VU, Vs2, I));
                  B : constant FP_Register := FCVT_D_S (FP.all, Read_Element (VU, Vs1, I, SEW), RM);
               begin
                  Write_Element_64 (VU, Vd, I, Unsigned_64 (FSUB_D (FP.all, A, B, RM)));
               end;
            end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VFWSUBW_VV;

   procedure VFWSUBW_VF (VU : in out Vector_State; FP : FPU_Access;
                         Vd, Vs2 : Register_Index; Fs1 : Word; VM : Boolean) is
      RM : constant Rounding_Mode := Resolve_RM (FP);
      B  : constant FP_Register := FCVT_D_S (FP.all, Fs1, RM);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            Write_Element_64 (VU, Vd, I,
              Unsigned_64 (FSUB_D (FP.all,
                FP_Register (Read_Element_64 (VU, Vs2, I)), B, RM)));
         end if;
      end loop;
      VU.VStart := 0;
   end VFWSUBW_VF;

   procedure VFWMUL_VV (VU : in out Vector_State; FP : FPU_Access;
                        Vd, Vs2, Vs1 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      RM  : constant Rounding_Mode := Resolve_RM (FP);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if SEW = SEW_32 then
               declare
                  A : constant FP_Register := FCVT_D_S (FP.all, Read_Element (VU, Vs2, I, SEW), RM);
                  B : constant FP_Register := FCVT_D_S (FP.all, Read_Element (VU, Vs1, I, SEW), RM);
               begin
                  Write_Element_64 (VU, Vd, I, Unsigned_64 (FMUL_D (FP.all, A, B, RM)));
               end;
            end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VFWMUL_VV;

   procedure VFWMUL_VF (VU : in out Vector_State; FP : FPU_Access;
                        Vd, Vs2 : Register_Index; Fs1 : Word; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      RM  : constant Rounding_Mode := Resolve_RM (FP);
      B   : constant FP_Register := FCVT_D_S (FP.all, Fs1, RM);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if SEW = SEW_32 then
               declare
                  A : constant FP_Register := FCVT_D_S (FP.all, Read_Element (VU, Vs2, I, SEW), RM);
               begin
                  Write_Element_64 (VU, Vd, I, Unsigned_64 (FMUL_D (FP.all, A, B, RM)));
               end;
            end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VFWMUL_VF;

   ----------------
   -- FP widening MAC
   ----------------

   procedure VFWMACC_VV (VU : in out Vector_State; FP : FPU_Access;
                         Vd, Vs1, Vs2 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      RM  : constant Rounding_Mode := Resolve_RM (FP);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if SEW = SEW_32 then
               declare
                  A : constant FP_Register := FCVT_D_S (FP.all, Read_Element (VU, Vs1, I, SEW), RM);
                  B : constant FP_Register := FCVT_D_S (FP.all, Read_Element (VU, Vs2, I, SEW), RM);
                  D : constant FP_Register := FP_Register (Read_Element_64 (VU, Vd, I));
               begin
                  Write_Element_64 (VU, Vd, I, Unsigned_64 (FMADD_D (FP.all, A, B, D, RM)));
               end;
            end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VFWMACC_VV;

   procedure VFWMACC_VF (VU : in out Vector_State; FP : FPU_Access;
                         Vd : Register_Index; Fs1 : Word;
                         Vs2 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      RM  : constant Rounding_Mode := Resolve_RM (FP);
      A   : constant FP_Register := FCVT_D_S (FP.all, Fs1, RM);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if SEW = SEW_32 then
               declare
                  B : constant FP_Register := FCVT_D_S (FP.all, Read_Element (VU, Vs2, I, SEW), RM);
                  D : constant FP_Register := FP_Register (Read_Element_64 (VU, Vd, I));
               begin
                  Write_Element_64 (VU, Vd, I, Unsigned_64 (FMADD_D (FP.all, A, B, D, RM)));
               end;
            end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VFWMACC_VF;

   procedure VFWNMACC_VV (VU : in out Vector_State; FP : FPU_Access;
                          Vd, Vs1, Vs2 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      RM  : constant Rounding_Mode := Resolve_RM (FP);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if SEW = SEW_32 then
               declare
                  A : constant FP_Register := FCVT_D_S (FP.all, Read_Element (VU, Vs1, I, SEW), RM);
                  B : constant FP_Register := FCVT_D_S (FP.all, Read_Element (VU, Vs2, I, SEW), RM);
                  D : constant FP_Register := FP_Register (Read_Element_64 (VU, Vd, I));
               begin
                  Write_Element_64 (VU, Vd, I, Unsigned_64 (FNMADD_D (FP.all, A, B, D, RM)));
               end;
            end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VFWNMACC_VV;

   procedure VFWNMACC_VF (VU : in out Vector_State; FP : FPU_Access;
                          Vd : Register_Index; Fs1 : Word;
                          Vs2 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      RM  : constant Rounding_Mode := Resolve_RM (FP);
      A   : constant FP_Register := FCVT_D_S (FP.all, Fs1, RM);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if SEW = SEW_32 then
               declare
                  B : constant FP_Register := FCVT_D_S (FP.all, Read_Element (VU, Vs2, I, SEW), RM);
                  D : constant FP_Register := FP_Register (Read_Element_64 (VU, Vd, I));
               begin
                  Write_Element_64 (VU, Vd, I, Unsigned_64 (FNMADD_D (FP.all, A, B, D, RM)));
               end;
            end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VFWNMACC_VF;

   procedure VFWMSAC_VV (VU : in out Vector_State; FP : FPU_Access;
                         Vd, Vs1, Vs2 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      RM  : constant Rounding_Mode := Resolve_RM (FP);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if SEW = SEW_32 then
               declare
                  A : constant FP_Register := FCVT_D_S (FP.all, Read_Element (VU, Vs1, I, SEW), RM);
                  B : constant FP_Register := FCVT_D_S (FP.all, Read_Element (VU, Vs2, I, SEW), RM);
                  D : constant FP_Register := FP_Register (Read_Element_64 (VU, Vd, I));
               begin
                  Write_Element_64 (VU, Vd, I, Unsigned_64 (FMSUB_D (FP.all, A, B, D, RM)));
               end;
            end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VFWMSAC_VV;

   procedure VFWMSAC_VF (VU : in out Vector_State; FP : FPU_Access;
                         Vd : Register_Index; Fs1 : Word;
                         Vs2 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      RM  : constant Rounding_Mode := Resolve_RM (FP);
      A   : constant FP_Register := FCVT_D_S (FP.all, Fs1, RM);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if SEW = SEW_32 then
               declare
                  B : constant FP_Register := FCVT_D_S (FP.all, Read_Element (VU, Vs2, I, SEW), RM);
                  D : constant FP_Register := FP_Register (Read_Element_64 (VU, Vd, I));
               begin
                  Write_Element_64 (VU, Vd, I, Unsigned_64 (FMSUB_D (FP.all, A, B, D, RM)));
               end;
            end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VFWMSAC_VF;

   procedure VFWNMSAC_VV (VU : in out Vector_State; FP : FPU_Access;
                          Vd, Vs1, Vs2 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      RM  : constant Rounding_Mode := Resolve_RM (FP);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if SEW = SEW_32 then
               declare
                  A : constant FP_Register := FCVT_D_S (FP.all, Read_Element (VU, Vs1, I, SEW), RM);
                  B : constant FP_Register := FCVT_D_S (FP.all, Read_Element (VU, Vs2, I, SEW), RM);
                  D : constant FP_Register := FP_Register (Read_Element_64 (VU, Vd, I));
               begin
                  Write_Element_64 (VU, Vd, I, Unsigned_64 (FNMSUB_D (FP.all, A, B, D, RM)));
               end;
            end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VFWNMSAC_VV;

   procedure VFWNMSAC_VF (VU : in out Vector_State; FP : FPU_Access;
                          Vd : Register_Index; Fs1 : Word;
                          Vs2 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      RM  : constant Rounding_Mode := Resolve_RM (FP);
      A   : constant FP_Register := FCVT_D_S (FP.all, Fs1, RM);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if SEW = SEW_32 then
               declare
                  B : constant FP_Register := FCVT_D_S (FP.all, Read_Element (VU, Vs2, I, SEW), RM);
                  D : constant FP_Register := FP_Register (Read_Element_64 (VU, Vd, I));
               begin
                  Write_Element_64 (VU, Vd, I, Unsigned_64 (FNMSUB_D (FP.all, A, B, D, RM)));
               end;
            end if;
         end if;
      end loop;
      VU.VStart := 0;
   end VFWNMSAC_VF;

   ----------------
   -- FP reduction
   ----------------

   procedure VFREDOSUM_VS (VU : in out Vector_State; FP : FPU_Access;
                           Vd, Vs2, Vs1 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      RM  : constant Rounding_Mode := Resolve_RM (FP);
      Acc : Word := Read_Element (VU, Vs1, 0, SEW);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if SEW = SEW_32 then
               Acc := FADD_S (FP.all, Acc, Read_Element (VU, Vs2, I, SEW), RM);
            end if;
         end if;
      end loop;
      Write_Element (VU, Vd, 0, SEW, Acc);
      VU.VStart := 0;
   end VFREDOSUM_VS;

   procedure VFREDUSUM_VS (VU : in out Vector_State; FP : FPU_Access;
                           Vd, Vs2, Vs1 : Register_Index; VM : Boolean) is
   begin
      VFREDOSUM_VS (VU, FP, Vd, Vs2, Vs1, VM);
   end VFREDUSUM_VS;

   procedure VFREDMIN_VS (VU : in out Vector_State; FP : FPU_Access;
                          Vd, Vs2, Vs1 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      Acc : Word := Read_Element (VU, Vs1, 0, SEW);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if SEW = SEW_32 then
               Acc := FMIN_S (FP.all, Acc, Read_Element (VU, Vs2, I, SEW));
            end if;
         end if;
      end loop;
      Write_Element (VU, Vd, 0, SEW, Acc);
      VU.VStart := 0;
   end VFREDMIN_VS;

   procedure VFREDMAX_VS (VU : in out Vector_State; FP : FPU_Access;
                          Vd, Vs2, Vs1 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      Acc : Word := Read_Element (VU, Vs1, 0, SEW);
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if SEW = SEW_32 then
               Acc := FMAX_S (FP.all, Acc, Read_Element (VU, Vs2, I, SEW));
            end if;
         end if;
      end loop;
      Write_Element (VU, Vd, 0, SEW, Acc);
      VU.VStart := 0;
   end VFREDMAX_VS;

   ----------------
   -- FP widening reduction
   ----------------

   procedure VFWREDOSUM_VS (VU : in out Vector_State; FP : FPU_Access;
                            Vd, Vs2, Vs1 : Register_Index; VM : Boolean) is
      SEW : constant SEW_Type := VU.VType.VSEW;
      RM  : constant Rounding_Mode := Resolve_RM (FP);
      Acc : FP_Register := FP_Register (Read_Element_64 (VU, Vs1, 0));
   begin
      for I in Natural (VU.VStart) .. Natural (VU.VL) - 1 loop
         if VM or else Get_Mask_Bit (VU, I) then
            if SEW = SEW_32 then
               declare
                  Val : constant FP_Register :=
                     FCVT_D_S (FP.all, Read_Element (VU, Vs2, I, SEW), RM);
               begin
                  Acc := FADD_D (FP.all, Acc, Val, RM);
               end;
            end if;
         end if;
      end loop;
      Write_Element_64 (VU, Vd, 0, Unsigned_64 (Acc));
      VU.VStart := 0;
   end VFWREDOSUM_VS;

   procedure VFWREDUSUM_VS (VU : in out Vector_State; FP : FPU_Access;
                            Vd, Vs2, Vs1 : Register_Index; VM : Boolean) is
   begin
      VFWREDOSUM_VS (VU, FP, Vd, Vs2, Vs1, VM);
   end VFWREDUSUM_VS;

end RISCV.Vector;
