-- ***************************************************************************
--             RISC-V Emulator - Floating Point Unit
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

package body RISCV.FPU is

   --  Suppress validity and overflow checks for IEEE 754 special values
   --  (NaN, Inf, subnormals) which are valid in RISC-V FPU operations
   --  but trigger CONSTRAINT_ERROR under Ada's -gnatVa flag.
   pragma Suppress (Validity_Check);
   pragma Suppress (Overflow_Check);
   pragma Suppress (Range_Check);

   --  IEEE 754 bit conversions
   type Float_32 is new Interfaces.IEEE_Float_32;
   type Float_64 is new Interfaces.IEEE_Float_64;

   function To_Float is new Ada.Unchecked_Conversion (Word, Float_32);
   function To_Double is new Ada.Unchecked_Conversion (FP_Register, Float_64);
   function To_Bits is new Ada.Unchecked_Conversion (Float_64, FP_Register);

   --  C helper imports for IEEE 754 operations with rounding mode
   --  and exception flag support
   function C_FP_Add_S (A, B : Word; RM : Integer;
                         Flags : access Word) return Word;
   pragma Import (C, C_FP_Add_S, "riscv_fp_add_s");

   function C_FP_Sub_S (A, B : Word; RM : Integer;
                         Flags : access Word) return Word;
   pragma Import (C, C_FP_Sub_S, "riscv_fp_sub_s");

   function C_FP_Mul_S (A, B : Word; RM : Integer;
                         Flags : access Word) return Word;
   pragma Import (C, C_FP_Mul_S, "riscv_fp_mul_s");

   function C_FP_Div_S (A, B : Word; RM : Integer;
                         Flags : access Word) return Word;
   pragma Import (C, C_FP_Div_S, "riscv_fp_div_s");

   function C_FP_Sqrt_S (A : Word; RM : Integer;
                          Flags : access Word) return Word;
   pragma Import (C, C_FP_Sqrt_S, "riscv_fp_sqrt_s");

   function C_FP_Fmadd_S (A, B, C : Word; RM : Integer;
                            Flags : access Word) return Word;
   pragma Import (C, C_FP_Fmadd_S, "riscv_fp_fmadd_s");

   function C_FP_Round_S (A : Word; RM : Integer;
                          Flags : access Word) return Word;
   pragma Import (C, C_FP_Round_S, "riscv_fp_round_s");

   function C_FP_I2F_S (A : Integer_32; RM : Integer;
                         Flags : access Word) return Word;
   pragma Import (C, C_FP_I2F_S, "riscv_fp_i2f_s");

   function C_FP_U2F_S (A : Word; RM : Integer;
                         Flags : access Word) return Word;
   pragma Import (C, C_FP_U2F_S, "riscv_fp_u2f_s");

   --  Double-precision C helper imports
   function C_FP_Add_D (A, B : Unsigned_64; RM : Integer;
                         Flags : access Word) return Unsigned_64;
   pragma Import (C, C_FP_Add_D, "riscv_fp_add_d");

   function C_FP_Sub_D (A, B : Unsigned_64; RM : Integer;
                         Flags : access Word) return Unsigned_64;
   pragma Import (C, C_FP_Sub_D, "riscv_fp_sub_d");

   function C_FP_Mul_D (A, B : Unsigned_64; RM : Integer;
                         Flags : access Word) return Unsigned_64;
   pragma Import (C, C_FP_Mul_D, "riscv_fp_mul_d");

   function C_FP_Div_D (A, B : Unsigned_64; RM : Integer;
                         Flags : access Word) return Unsigned_64;
   pragma Import (C, C_FP_Div_D, "riscv_fp_div_d");

   function C_FP_Sqrt_D (A : Unsigned_64; RM : Integer;
                          Flags : access Word) return Unsigned_64;
   pragma Import (C, C_FP_Sqrt_D, "riscv_fp_sqrt_d");

   function C_FP_Fmadd_D (A, B, C : Unsigned_64; RM : Integer;
                            Flags : access Word) return Unsigned_64;
   pragma Import (C, C_FP_Fmadd_D, "riscv_fp_fmadd_d");

   function C_FP_Round_D (A : Unsigned_64; RM : Integer;
                           Flags : access Word) return Unsigned_64;
   pragma Import (C, C_FP_Round_D, "riscv_fp_round_d");

   function C_FP_I2D (A : Integer_32; RM : Integer;
                       Flags : access Word) return Unsigned_64;
   pragma Import (C, C_FP_I2D, "riscv_fp_i2d");

   function C_FP_U2D (A : Word; RM : Integer;
                       Flags : access Word) return Unsigned_64;
   pragma Import (C, C_FP_U2D, "riscv_fp_u2d");

   function C_FP_D2S (A : Unsigned_64; RM : Integer;
                       Flags : access Word) return Word;
   pragma Import (C, C_FP_D2S, "riscv_fp_d2s");

   --  RV64 64-bit integer <-> double helpers
   function C_FP_L2D (A : Integer_64; RM : Integer;
                       Flags : access Word) return Unsigned_64;
   pragma Import (C, C_FP_L2D, "riscv_fp_l2d");

   function C_FP_LU2D (A : Unsigned_64; RM : Integer;
                        Flags : access Word) return Unsigned_64;
   pragma Import (C, C_FP_LU2D, "riscv_fp_lu2d");

   function C_FP_D2L (A : Unsigned_64; RM : Integer;
                       Flags : access Word) return Unsigned_64;
   pragma Import (C, C_FP_D2L, "riscv_fp_d2l");

   function C_FP_D2LU (A : Unsigned_64; RM : Integer;
                        Flags : access Word) return Unsigned_64;
   pragma Import (C, C_FP_D2LU, "riscv_fp_d2lu");

   function C_FP_S2L (A : Word; RM : Integer;
                      Flags : access Word) return Unsigned_64;
   pragma Import (C, C_FP_S2L, "riscv_fp_s2l");

   function C_FP_S2LU (A : Word; RM : Integer;
                       Flags : access Word) return Unsigned_64;
   pragma Import (C, C_FP_S2LU, "riscv_fp_s2lu");

   function C_FP_L2S (A : Integer_64; RM : Integer;
                      Flags : access Word) return Word;
   pragma Import (C, C_FP_L2S, "riscv_fp_l2s");

   function C_FP_LU2S (A : Unsigned_64; RM : Integer;
                       Flags : access Word) return Word;
   pragma Import (C, C_FP_LU2S, "riscv_fp_lu2s");

   --  Helper to get integer RM value for C calls
   function RM_To_Int (FPU : FPU_State; RM : Rounding_Mode) return Integer is
      Effective : constant Rounding_Mode := Get_Rounding_Mode (FPU, RM);
   begin
      return Rounding_Mode'Pos (Effective);
   end RM_To_Int;

   --  Apply C flags to FPU state (OR into existing flags)
   procedure Apply_C_Flags (FPU : in out FPU_State; C_Flags : Word) is
   begin
      if (C_Flags and 1) /= 0 then FPU.FCSR.Flags.NX := True; end if;
      if (C_Flags and 2) /= 0 then FPU.FCSR.Flags.UF := True; end if;
      if (C_Flags and 4) /= 0 then FPU.FCSR.Flags.OVF := True; end if;
      if (C_Flags and 8) /= 0 then FPU.FCSR.Flags.DZ := True; end if;
      if (C_Flags and 16) /= 0 then FPU.FCSR.Flags.NV := True; end if;
   end Apply_C_Flags;

   --  NaN boxing for single-precision values in 64-bit registers
   --  Upper 32 bits must be all 1s for a valid single-precision value
   NaN_Box_Mask : constant FP_Register := 16#FFFFFFFF_00000000#;

   function Is_NaN_Boxed (V : FP_Register) return Boolean is
   begin
      return (V and NaN_Box_Mask) = NaN_Box_Mask;
   end Is_NaN_Boxed;

   function NaN_Box (V : Word) return FP_Register is
   begin
      return NaN_Box_Mask or FP_Register (V);
   end NaN_Box;

   function Unbox_Single (V : FP_Register) return Word is
   begin
      if Is_NaN_Boxed (V) then
         return Word (V and 16#FFFFFFFF#);
      else
         --  Return canonical NaN if not properly boxed
         return 16#7FC00000#;
      end if;
   end Unbox_Single;

   --  Single-precision special value checks
   function Is_NaN_S (V : Word) return Boolean is
      Exp  : constant Word := (V and 16#7F800000#);
      Frac : constant Word := (V and 16#007FFFFF#);
   begin
      return Exp = 16#7F800000# and Frac /= 0;
   end Is_NaN_S;

   function Is_SNaN_S (V : Word) return Boolean is
      Exp  : constant Word := (V and 16#7F800000#);
      Frac : constant Word := (V and 16#007FFFFF#);
   begin
      --  Signaling NaN: exponent all 1s, fraction MSB = 0, fraction /= 0
      return Exp = 16#7F800000# and Frac /= 0 and (Frac and 16#00400000#) = 0;
   end Is_SNaN_S;

   function Is_QNaN_S (V : Word) return Boolean is
      Exp  : constant Word := (V and 16#7F800000#);
      Frac : constant Word := (V and 16#007FFFFF#);
   begin
      --  Quiet NaN: exponent all 1s, fraction MSB = 1
      return Exp = 16#7F800000# and (Frac and 16#00400000#) /= 0;
   end Is_QNaN_S;

   function Is_Inf_S (V : Word) return Boolean is
      Exp  : constant Word := (V and 16#7F800000#);
      Frac : constant Word := (V and 16#007FFFFF#);
   begin
      return Exp = 16#7F800000# and Frac = 0;
   end Is_Inf_S;

   function Is_Zero_S (V : Word) return Boolean is
   begin
      return (V and 16#7FFFFFFF#) = 0;
   end Is_Zero_S;

   function Is_Subnormal_S (V : Word) return Boolean is
      Exp  : constant Word := (V and 16#7F800000#);
      Frac : constant Word := (V and 16#007FFFFF#);
   begin
      return Exp = 0 and Frac /= 0;
   end Is_Subnormal_S;

   function Is_Negative_S (V : Word) return Boolean is
   begin
      return (V and 16#80000000#) /= 0;
   end Is_Negative_S;

   --  Double-precision special value checks
   function Is_NaN_D (V : FP_Register) return Boolean is
      Exp  : constant FP_Register := (V and 16#7FF0_0000_0000_0000#);
      Frac : constant FP_Register := (V and 16#000F_FFFF_FFFF_FFFF#);
   begin
      return Exp = 16#7FF0_0000_0000_0000# and Frac /= 0;
   end Is_NaN_D;

   function Is_SNaN_D (V : FP_Register) return Boolean is
      Exp  : constant FP_Register := (V and 16#7FF0_0000_0000_0000#);
      Frac : constant FP_Register := (V and 16#000F_FFFF_FFFF_FFFF#);
   begin
      return Exp = 16#7FF0_0000_0000_0000# and Frac /= 0 and
             (Frac and 16#0008_0000_0000_0000#) = 0;
   end Is_SNaN_D;

   function Is_Inf_D (V : FP_Register) return Boolean is
      Exp  : constant FP_Register := (V and 16#7FF0_0000_0000_0000#);
      Frac : constant FP_Register := (V and 16#000F_FFFF_FFFF_FFFF#);
   begin
      return Exp = 16#7FF0_0000_0000_0000# and Frac = 0;
   end Is_Inf_D;

   function Is_Zero_D (V : FP_Register) return Boolean is
   begin
      return (V and 16#7FFF_FFFF_FFFF_FFFF#) = 0;
   end Is_Zero_D;

   function Is_Subnormal_D (V : FP_Register) return Boolean is
      Exp  : constant FP_Register := (V and 16#7FF0_0000_0000_0000#);
      Frac : constant FP_Register := (V and 16#000F_FFFF_FFFF_FFFF#);
   begin
      return Exp = 0 and Frac /= 0;
   end Is_Subnormal_D;

   function Is_Negative_D (V : FP_Register) return Boolean is
   begin
      return (V and 16#8000_0000_0000_0000#) /= 0;
   end Is_Negative_D;

   --  Canonical NaN values
   Canonical_NaN_S : constant Word := 16#7FC00000#;
   Canonical_NaN_D : constant FP_Register := 16#7FF8_0000_0000_0000#;

   ----------------
   -- Initialize --
   ----------------

   procedure Initialize (FPU : out FPU_State) is
   begin
      FPU.Registers := (others => 0);
      FPU.FCSR := (Flags => (others => False), RM => RNE);
   end Initialize;

   -------------------
   -- Read_Register --
   -------------------

   function Read_Register (FPU : FPU_State;
                           Reg : Register_Index) return FP_Register is
   begin
      return FPU.Registers (Reg);
   end Read_Register;

   --------------------
   -- Write_Register --
   --------------------

   procedure Write_Register (FPU   : in out FPU_State;
                             Reg   : Register_Index;
                             Value : FP_Register) is
   begin
      FPU.Registers (Reg) := Value;
   end Write_Register;

   -----------------
   -- Read_Single --
   -----------------

   function Read_Single (FPU : FPU_State;
                         Reg : Register_Index) return Word is
   begin
      return Unbox_Single (FPU.Registers (Reg));
   end Read_Single;

   ------------------
   -- Write_Single --
   ------------------

   procedure Write_Single (FPU   : in out FPU_State;
                           Reg   : Register_Index;
                           Value : Word) is
   begin
      FPU.Registers (Reg) := NaN_Box (Value);
   end Write_Single;

   -----------------
   -- Read_Double --
   -----------------

   function Read_Double (FPU : FPU_State;
                         Reg : Register_Index) return FP_Register is
   begin
      return FPU.Registers (Reg);
   end Read_Double;

   ------------------
   -- Write_Double --
   ------------------

   procedure Write_Double (FPU   : in out FPU_State;
                           Reg   : Register_Index;
                           Value : FP_Register) is
   begin
      FPU.Registers (Reg) := Value;
   end Write_Double;

   ---------------
   -- Read_FCSR --
   ---------------

   function Read_FCSR (FPU : FPU_State) return Word is
      Result : Word := 0;
   begin
      if FPU.FCSR.Flags.NX then Result := Result or 1; end if;
      if FPU.FCSR.Flags.UF then Result := Result or 2; end if;
      if FPU.FCSR.Flags.OVF then Result := Result or 4; end if;
      if FPU.FCSR.Flags.DZ then Result := Result or 8; end if;
      if FPU.FCSR.Flags.NV then Result := Result or 16; end if;
      Result := Result or Shift_Left (Word (Rounding_Mode'Pos (FPU.FCSR.RM)), 5);
      return Result;
   end Read_FCSR;

   ----------------
   -- Write_FCSR --
   ----------------

   procedure Write_FCSR (FPU : in out FPU_State; Value : Word) is
      RM_Val : constant Natural := Natural (Shift_Right (Value, 5) and 7);
   begin
      FPU.FCSR.Flags.NX := (Value and 1) /= 0;
      FPU.FCSR.Flags.UF := (Value and 2) /= 0;
      FPU.FCSR.Flags.OVF := (Value and 4) /= 0;
      FPU.FCSR.Flags.DZ := (Value and 8) /= 0;
      FPU.FCSR.Flags.NV := (Value and 16) /= 0;
      if RM_Val <= Rounding_Mode'Pos (RMM) then
         FPU.FCSR.RM := Rounding_Mode'Val (RM_Val);
      else
         FPU.FCSR.RM := RNE;  -- Invalid RM defaults to RNE
      end if;
   end Write_FCSR;

   --------------
   -- Read_FRM --
   --------------

   function Read_FRM (FPU : FPU_State) return Word is
   begin
      return Word (Rounding_Mode'Pos (FPU.FCSR.RM));
   end Read_FRM;

   ---------------
   -- Write_FRM --
   ---------------

   procedure Write_FRM (FPU : in out FPU_State; Value : Word) is
      RM_Val : constant Natural := Natural (Value and 7);
   begin
      if RM_Val <= Rounding_Mode'Pos (RMM) then
         FPU.FCSR.RM := Rounding_Mode'Val (RM_Val);
      end if;
   end Write_FRM;

   -----------------
   -- Read_FFLAGS --
   -----------------

   function Read_FFLAGS (FPU : FPU_State) return Word is
      Result : Word := 0;
   begin
      if FPU.FCSR.Flags.NX then Result := Result or 1; end if;
      if FPU.FCSR.Flags.UF then Result := Result or 2; end if;
      if FPU.FCSR.Flags.OVF then Result := Result or 4; end if;
      if FPU.FCSR.Flags.DZ then Result := Result or 8; end if;
      if FPU.FCSR.Flags.NV then Result := Result or 16; end if;
      return Result;
   end Read_FFLAGS;

   ------------------
   -- Write_FFLAGS --
   ------------------

   procedure Write_FFLAGS (FPU : in out FPU_State; Value : Word) is
   begin
      FPU.FCSR.Flags.NX := (Value and 1) /= 0;
      FPU.FCSR.Flags.UF := (Value and 2) /= 0;
      FPU.FCSR.Flags.OVF := (Value and 4) /= 0;
      FPU.FCSR.Flags.DZ := (Value and 8) /= 0;
      FPU.FCSR.Flags.NV := (Value and 16) /= 0;
   end Write_FFLAGS;

   -----------------------
   -- Get_Rounding_Mode --
   -----------------------

   function Get_Rounding_Mode (FPU : FPU_State;
                               RM  : Rounding_Mode) return Rounding_Mode is
   begin
      if RM = DYN then
         return FPU.FCSR.RM;
      else
         return RM;
      end if;
   end Get_Rounding_Mode;

   --------------
   -- Set_Flag --
   --------------

   procedure Set_Flag (FPU  : in out FPU_State;
                       Flag : FP_Flags) is
   begin
      FPU.FCSR.Flags.NX := FPU.FCSR.Flags.NX or Flag.NX;
      FPU.FCSR.Flags.UF := FPU.FCSR.Flags.UF or Flag.UF;
      FPU.FCSR.Flags.OVF := FPU.FCSR.Flags.OVF or Flag.OVF;
      FPU.FCSR.Flags.DZ := FPU.FCSR.Flags.DZ or Flag.DZ;
      FPU.FCSR.Flags.NV := FPU.FCSR.Flags.NV or Flag.NV;
   end Set_Flag;

   ----------------------------------------------------------------------------
   --  Single-Precision Operations
   ----------------------------------------------------------------------------

   ------------
   -- FADD_S --
   ------------

   function FADD_S (FPU  : in out FPU_State;
                    A, B : Word;
                    RM   : Rounding_Mode) return Word is
      C_Flags : aliased Word := 0;
      Result  : Word;
   begin
      --  Handle NaN inputs (canonicalize before C call)
      if Is_SNaN_S (A) or Is_SNaN_S (B) then
         FPU.FCSR.Flags.NV := True;
         return Canonical_NaN_S;
      end if;
      if Is_NaN_S (A) or Is_NaN_S (B) then
         return Canonical_NaN_S;
      end if;

      Result := C_FP_Add_S (A, B, RM_To_Int (FPU, RM), C_Flags'Access);

      --  Canonicalize NaN result (C may produce non-canonical NaN)
      if Is_NaN_S (Result) then
         Apply_C_Flags (FPU, C_Flags);
         return Canonical_NaN_S;
      end if;

      Apply_C_Flags (FPU, C_Flags);
      return Result;
   end FADD_S;

   ------------
   -- FSUB_S --
   ------------

   function FSUB_S (FPU  : in out FPU_State;
                    A, B : Word;
                    RM   : Rounding_Mode) return Word is
      C_Flags : aliased Word := 0;
      Result  : Word;
   begin
      if Is_SNaN_S (A) or Is_SNaN_S (B) then
         FPU.FCSR.Flags.NV := True;
         return Canonical_NaN_S;
      end if;
      if Is_NaN_S (A) or Is_NaN_S (B) then
         return Canonical_NaN_S;
      end if;

      Result := C_FP_Sub_S (A, B, RM_To_Int (FPU, RM), C_Flags'Access);

      if Is_NaN_S (Result) then
         Apply_C_Flags (FPU, C_Flags);
         return Canonical_NaN_S;
      end if;

      Apply_C_Flags (FPU, C_Flags);
      return Result;
   end FSUB_S;

   ------------
   -- FMUL_S --
   ------------

   function FMUL_S (FPU  : in out FPU_State;
                    A, B : Word;
                    RM   : Rounding_Mode) return Word is
      C_Flags : aliased Word := 0;
      Result  : Word;
   begin
      if Is_SNaN_S (A) or Is_SNaN_S (B) then
         FPU.FCSR.Flags.NV := True;
         return Canonical_NaN_S;
      end if;
      if Is_NaN_S (A) or Is_NaN_S (B) then
         return Canonical_NaN_S;
      end if;

      --  0 * inf = NaN
      if (Is_Zero_S (A) and Is_Inf_S (B)) or
         (Is_Inf_S (A) and Is_Zero_S (B))
      then
         FPU.FCSR.Flags.NV := True;
         return Canonical_NaN_S;
      end if;

      Result := C_FP_Mul_S (A, B, RM_To_Int (FPU, RM), C_Flags'Access);

      if Is_NaN_S (Result) then
         Apply_C_Flags (FPU, C_Flags);
         return Canonical_NaN_S;
      end if;

      Apply_C_Flags (FPU, C_Flags);
      return Result;
   end FMUL_S;

   ------------
   -- FDIV_S --
   ------------

   function FDIV_S (FPU  : in out FPU_State;
                    A, B : Word;
                    RM   : Rounding_Mode) return Word is
      C_Flags : aliased Word := 0;
      Result  : Word;
   begin
      if Is_SNaN_S (A) or Is_SNaN_S (B) then
         FPU.FCSR.Flags.NV := True;
         return Canonical_NaN_S;
      end if;
      if Is_NaN_S (A) or Is_NaN_S (B) then
         return Canonical_NaN_S;
      end if;

      --  Let C handle all the division cases (0/0, inf/inf, x/0)
      --  and report proper flags
      Result := C_FP_Div_S (A, B, RM_To_Int (FPU, RM), C_Flags'Access);

      if Is_NaN_S (Result) then
         Apply_C_Flags (FPU, C_Flags);
         return Canonical_NaN_S;
      end if;

      Apply_C_Flags (FPU, C_Flags);
      return Result;
   end FDIV_S;

   -------------
   -- FSQRT_S --
   -------------

   function FSQRT_S (FPU : in out FPU_State;
                     A   : Word;
                     RM  : Rounding_Mode) return Word is
      C_Flags : aliased Word := 0;
      Result  : Word;
   begin
      if Is_SNaN_S (A) then
         FPU.FCSR.Flags.NV := True;
         return Canonical_NaN_S;
      end if;
      if Is_NaN_S (A) then
         return Canonical_NaN_S;
      end if;

      --  sqrt of negative (except -0) = NaN
      if Is_Negative_S (A) and not Is_Zero_S (A) then
         FPU.FCSR.Flags.NV := True;
         return Canonical_NaN_S;
      end if;

      --  sqrt(+Inf) = +Inf, sqrt(+-0) = +-0
      if Is_Inf_S (A) or Is_Zero_S (A) then
         return A;
      end if;

      Result := C_FP_Sqrt_S (A, RM_To_Int (FPU, RM), C_Flags'Access);
      Apply_C_Flags (FPU, C_Flags);
      return Result;
   end FSQRT_S;

   --------------
   -- FMADD_S --
   --------------

   function FMADD_S (FPU      : in out FPU_State;
                     A, B, C  : Word;
                     RM       : Rounding_Mode) return Word is
      C_Flags : aliased Word := 0;
      Result  : Word;
   begin
      --  Any signaling NaN raises NV
      if Is_SNaN_S (A) or Is_SNaN_S (B) or Is_SNaN_S (C) then
         FPU.FCSR.Flags.NV := True;
      end if;

      --  0 * inf or inf * 0 is invalid even with a qNaN addend
      if (Is_Zero_S (A) and Is_Inf_S (B)) or
         (Is_Inf_S (A) and Is_Zero_S (B))
      then
         FPU.FCSR.Flags.NV := True;
         return Canonical_NaN_S;
      end if;

      --  Any NaN input produces canonical NaN
      if Is_NaN_S (A) or Is_NaN_S (B) or Is_NaN_S (C) then
         return Canonical_NaN_S;
      end if;

      --  inf*x + (-inf) where product sign differs from addend sign
      if (Is_Inf_S (A) or Is_Inf_S (B)) and Is_Inf_S (C) then
         declare
            Prod_Sign : constant Boolean :=
               Is_Negative_S (A) xor Is_Negative_S (B);
         begin
            if Prod_Sign /= Is_Negative_S (C) then
               FPU.FCSR.Flags.NV := True;
               return Canonical_NaN_S;
            end if;
         end;
      end if;

      Result := C_FP_Fmadd_S (A, B, C, RM_To_Int (FPU, RM), C_Flags'Access);

      if Is_NaN_S (Result) then
         Apply_C_Flags (FPU, C_Flags);
         return Canonical_NaN_S;
      end if;

      Apply_C_Flags (FPU, C_Flags);
      return Result;
   end FMADD_S;

   --------------
   -- FMSUB_S --
   --------------

   function FMSUB_S (FPU      : in out FPU_State;
                     A, B, C  : Word;
                     RM       : Rounding_Mode) return Word is
      Neg_C : constant Word := C xor 16#80000000#;
   begin
      return FMADD_S (FPU, A, B, Neg_C, RM);
   end FMSUB_S;

   ---------------
   -- FNMADD_S --
   ---------------

   function FNMADD_S (FPU      : in out FPU_State;
                      A, B, C  : Word;
                      RM       : Rounding_Mode) return Word is
      Neg_A : constant Word := A xor 16#80000000#;
      Neg_C : constant Word := C xor 16#80000000#;
   begin
      return FMADD_S (FPU, Neg_A, B, Neg_C, RM);
   end FNMADD_S;

   ---------------
   -- FNMSUB_S --
   ---------------

   function FNMSUB_S (FPU      : in out FPU_State;
                      A, B, C  : Word;
                      RM       : Rounding_Mode) return Word is
      Neg_A : constant Word := A xor 16#80000000#;
   begin
      return FMADD_S (FPU, Neg_A, B, C, RM);
   end FNMSUB_S;

   ------------
   -- FMIN_S --
   ------------

   function FMIN_S (FPU  : in out FPU_State;
                    A, B : Word) return Word is
      FA, FB : Float_32;
   begin
      --  Signaling NaN raises invalid
      if Is_SNaN_S (A) or Is_SNaN_S (B) then
         FPU.FCSR.Flags.NV := True;
      end if;

      --  If either is NaN, return the other
      if Is_NaN_S (A) and Is_NaN_S (B) then
         return Canonical_NaN_S;
      end if;
      if Is_NaN_S (A) then return B; end if;
      if Is_NaN_S (B) then return A; end if;

      --  Both zeros: prefer -0
      if Is_Zero_S (A) and Is_Zero_S (B) then
         if Is_Negative_S (A) then return A; else return B; end if;
      end if;

      FA := To_Float (A);
      FB := To_Float (B);
      if FA < FB then
         return A;
      else
         return B;
      end if;
   end FMIN_S;

   ------------
   -- FMAX_S --
   ------------

   function FMAX_S (FPU  : in out FPU_State;
                    A, B : Word) return Word is
      FA, FB : Float_32;
   begin
      if Is_SNaN_S (A) or Is_SNaN_S (B) then
         FPU.FCSR.Flags.NV := True;
      end if;

      if Is_NaN_S (A) and Is_NaN_S (B) then
         return Canonical_NaN_S;
      end if;
      if Is_NaN_S (A) then return B; end if;
      if Is_NaN_S (B) then return A; end if;

      --  Both zeros: prefer +0
      if Is_Zero_S (A) and Is_Zero_S (B) then
         if Is_Negative_S (A) then return B; else return A; end if;
      end if;

      FA := To_Float (A);
      FB := To_Float (B);
      if FA > FB then
         return A;
      else
         return B;
      end if;
   end FMAX_S;

   -------------
   -- FSGNJ_S --
   -------------

   function FSGNJ_S (A, B : Word) return Word is
   begin
      --  Result has magnitude of A and sign of B
      return (A and 16#7FFFFFFF#) or (B and 16#80000000#);
   end FSGNJ_S;

   --------------
   -- FSGNJN_S --
   --------------

   function FSGNJN_S (A, B : Word) return Word is
   begin
      --  Result has magnitude of A and negated sign of B
      return (A and 16#7FFFFFFF#) or ((not B) and 16#80000000#);
   end FSGNJN_S;

   --------------
   -- FSGNJX_S --
   --------------

   function FSGNJX_S (A, B : Word) return Word is
   begin
      --  Result has magnitude of A and XOR of signs
      return (A and 16#7FFFFFFF#) or ((A xor B) and 16#80000000#);
   end FSGNJX_S;

   -----------
   -- FEQ_S --
   -----------

   function FEQ_S (FPU  : in out FPU_State;
                   A, B : Word) return Word is
      FA, FB : Float_32;
   begin
      --  Signaling NaN raises invalid
      if Is_SNaN_S (A) or Is_SNaN_S (B) then
         FPU.FCSR.Flags.NV := True;
      end if;

      --  NaN is never equal
      if Is_NaN_S (A) or Is_NaN_S (B) then
         return 0;
      end if;

      --  +0 equals -0
      if Is_Zero_S (A) and Is_Zero_S (B) then
         return 1;
      end if;

      FA := To_Float (A);
      FB := To_Float (B);
      if FA = FB then
         return 1;
      else
         return 0;
      end if;
   end FEQ_S;

   -----------
   -- FLT_S --
   -----------

   function FLT_S (FPU  : in out FPU_State;
                   A, B : Word) return Word is
      FA, FB : Float_32;
   begin
      --  Any NaN raises invalid for LT comparison
      if Is_NaN_S (A) or Is_NaN_S (B) then
         FPU.FCSR.Flags.NV := True;
         return 0;
      end if;

      FA := To_Float (A);
      FB := To_Float (B);
      if FA < FB then
         return 1;
      else
         return 0;
      end if;
   end FLT_S;

   -----------
   -- FLE_S --
   -----------

   function FLE_S (FPU  : in out FPU_State;
                   A, B : Word) return Word is
      FA, FB : Float_32;
   begin
      if Is_NaN_S (A) or Is_NaN_S (B) then
         FPU.FCSR.Flags.NV := True;
         return 0;
      end if;

      FA := To_Float (A);
      FB := To_Float (B);
      if FA <= FB then
         return 1;
      else
         return 0;
      end if;
   end FLE_S;

   --------------
   -- FCLASS_S --
   --------------

   function FCLASS_S (A : Word) return Word is
   begin
      if Is_Negative_S (A) then
         if Is_Inf_S (A) then return 1; end if;                -- bit 0: -inf
         if not Is_Zero_S (A) and not Is_Subnormal_S (A) and
            not Is_NaN_S (A) and not Is_Inf_S (A)
         then
            return 2;  -- bit 1: negative normal
         end if;
         if Is_Subnormal_S (A) then return 4; end if;          -- bit 2: -subnormal
         if Is_Zero_S (A) then return 8; end if;               -- bit 3: -0
      else
         if Is_Zero_S (A) then return 16; end if;              -- bit 4: +0
         if Is_Subnormal_S (A) then return 32; end if;         -- bit 5: +subnormal
         if not Is_Zero_S (A) and not Is_Subnormal_S (A) and
            not Is_NaN_S (A) and not Is_Inf_S (A)
         then
            return 64;  -- bit 6: positive normal
         end if;
         if Is_Inf_S (A) then return 128; end if;              -- bit 7: +inf
      end if;
      if Is_SNaN_S (A) then return 256; end if;                -- bit 8: sNaN
      if Is_QNaN_S (A) then return 512; end if;                -- bit 9: qNaN

      --  Fallback (shouldn't reach here)
      return 512;
   end FCLASS_S;

   ---------------
   -- FCVT_W_S --
   ---------------

   function FCVT_W_S (FPU : in out FPU_State;
                      A   : Word;
                      RM  : Rounding_Mode) return Word is
      function To_Word_From_Signed is
         new Ada.Unchecked_Conversion (Integer_32, Word);
      C_Flags    : aliased Word := 0;
      RM_Int     : constant Integer := RM_To_Int (FPU, RM);
      Rounded_W  : Word;
      FR         : Float_32;
   begin
      if Is_NaN_S (A) then
         FPU.FCSR.Flags.NV := True;
         return 16#7FFFFFFF#;
      end if;

      if Is_Inf_S (A) and not Is_Negative_S (A) then
         FPU.FCSR.Flags.NV := True;
         return 16#7FFFFFFF#;
      end if;

      if Is_Inf_S (A) and Is_Negative_S (A) then
         FPU.FCSR.Flags.NV := True;
         return 16#80000000#;
      end if;

      --  Round the float to integer-valued float using specified RM
      Rounded_W := C_FP_Round_S (A, RM_Int, C_Flags'Access);
      FR := To_Float (Rounded_W);

      --  Check overflow after rounding
      if FR >= 2147483648.0 then
         FPU.FCSR.Flags.NV := True;
         return 16#7FFFFFFF#;
      end if;
      if FR < -2147483648.0 then
         FPU.FCSR.Flags.NV := True;
         return 16#80000000#;
      end if;

      --  Set inexact flag if rounding changed the value
      Apply_C_Flags (FPU, C_Flags);
      return To_Word_From_Signed (Integer_32 (FR));
   end FCVT_W_S;

   ----------------
   -- FCVT_WU_S --
   ----------------

   function FCVT_WU_S (FPU : in out FPU_State;
                       A   : Word;
                       RM  : Rounding_Mode) return Word is
      C_Flags    : aliased Word := 0;
      RM_Int     : constant Integer := RM_To_Int (FPU, RM);
      Rounded_W  : Word;
      FR         : Float_32;
      FD         : Float_64;
   begin
      if Is_NaN_S (A) then
         FPU.FCSR.Flags.NV := True;
         return 16#FFFFFFFF#;
      end if;

      if Is_Inf_S (A) and not Is_Negative_S (A) then
         FPU.FCSR.Flags.NV := True;
         return 16#FFFFFFFF#;
      end if;

      if Is_Inf_S (A) and Is_Negative_S (A) then
         FPU.FCSR.Flags.NV := True;
         return 0;
      end if;

      --  Round the float to integer-valued float using specified RM
      Rounded_W := C_FP_Round_S (A, RM_Int, C_Flags'Access);
      FR := To_Float (Rounded_W);

      --  Use double precision for range check to avoid precision loss
      FD := Float_64 (FR);

      if FD >= 4294967296.0 then
         FPU.FCSR.Flags.NV := True;
         return 16#FFFFFFFF#;
      end if;
      if FD < 0.0 then
         FPU.FCSR.Flags.NV := True;
         return 0;
      end if;

      Apply_C_Flags (FPU, C_Flags);
      --  Convert via double to safely handle full uint32 range
      return Word (Unsigned_64 (FD) and 16#FFFFFFFF#);
   end FCVT_WU_S;

   ---------------
   -- FCVT_L_S --
   ---------------

   function FCVT_L_S (FPU : in out FPU_State;
                      A   : Word;
                      RM  : Rounding_Mode) return FP_Register is
      C_Flags : aliased Word := 0;
      Result  : Unsigned_64;
   begin
      Result := C_FP_S2L (A, RM_To_Int (FPU, RM), C_Flags'Access);
      Apply_C_Flags (FPU, C_Flags);
      return FP_Register (Result);
   end FCVT_L_S;

   ----------------
   -- FCVT_LU_S --
   ----------------

   function FCVT_LU_S (FPU : in out FPU_State;
                       A   : Word;
                       RM  : Rounding_Mode) return FP_Register is
      C_Flags : aliased Word := 0;
      Result  : Unsigned_64;
   begin
      Result := C_FP_S2LU (A, RM_To_Int (FPU, RM), C_Flags'Access);
      Apply_C_Flags (FPU, C_Flags);
      return FP_Register (Result);
   end FCVT_LU_S;

   ---------------
   -- FCVT_S_W --
   ---------------

   function FCVT_S_W (FPU : in out FPU_State;
                      A   : Word;
                      RM  : Rounding_Mode) return Word is
      function To_Signed is new Ada.Unchecked_Conversion (Word, Integer_32);
      C_Flags : aliased Word := 0;
      Result  : Word;
   begin
      Result := C_FP_I2F_S (To_Signed (A), RM_To_Int (FPU, RM),
                             C_Flags'Access);
      Apply_C_Flags (FPU, C_Flags);
      return Result;
   end FCVT_S_W;

   ----------------
   -- FCVT_S_WU --
   ----------------

   function FCVT_S_WU (FPU : in out FPU_State;
                       A   : Word;
                       RM  : Rounding_Mode) return Word is
      C_Flags : aliased Word := 0;
      Result  : Word;
   begin
      Result := C_FP_U2F_S (A, RM_To_Int (FPU, RM), C_Flags'Access);
      Apply_C_Flags (FPU, C_Flags);
      return Result;
   end FCVT_S_WU;

   ---------------
   -- FCVT_S_L --
   ---------------

   function FCVT_S_L (FPU : in out FPU_State;
                      A   : FP_Register;
                      RM  : Rounding_Mode) return Word is
      function To_Int64 is new Ada.Unchecked_Conversion (Unsigned_64, Integer_64);
      C_Flags : aliased Word := 0;
      Result  : Word;
   begin
      Result := C_FP_L2S (To_Int64 (Unsigned_64 (A)), RM_To_Int (FPU, RM),
                          C_Flags'Access);
      Apply_C_Flags (FPU, C_Flags);
      return Result;
   end FCVT_S_L;

   ----------------
   -- FCVT_S_LU --
   ----------------

   function FCVT_S_LU (FPU : in out FPU_State;
                       A   : FP_Register;
                       RM  : Rounding_Mode) return Word is
      C_Flags : aliased Word := 0;
      Result  : Word;
   begin
      Result := C_FP_LU2S (Unsigned_64 (A), RM_To_Int (FPU, RM),
                           C_Flags'Access);
      Apply_C_Flags (FPU, C_Flags);
      return Result;
   end FCVT_S_LU;

   --------------
   -- FMV_X_W --
   --------------

   function FMV_X_W (A : Word) return Word is
   begin
      return A;  -- Bit-level move, no conversion
   end FMV_X_W;

   --------------
   -- FMV_W_X --
   --------------

   function FMV_W_X (A : Word) return Word is
   begin
      return A;
   end FMV_W_X;

   ----------------------------------------------------------------------------
   --  Double-Precision Operations
   ----------------------------------------------------------------------------

   ------------
   -- FADD_D --
   ------------

   function FADD_D (FPU  : in out FPU_State;
                    A, B : FP_Register;
                    RM   : Rounding_Mode) return FP_Register is
      C_Flags : aliased Word := 0;
      Result  : Unsigned_64;
   begin
      if Is_SNaN_D (A) or Is_SNaN_D (B) then
         FPU.FCSR.Flags.NV := True;
         return Canonical_NaN_D;
      end if;
      if Is_NaN_D (A) or Is_NaN_D (B) then
         return Canonical_NaN_D;
      end if;

      Result := C_FP_Add_D (Unsigned_64 (A), Unsigned_64 (B),
                             RM_To_Int (FPU, RM), C_Flags'Access);

      if Is_NaN_D (FP_Register (Result)) then
         Apply_C_Flags (FPU, C_Flags);
         return Canonical_NaN_D;
      end if;

      Apply_C_Flags (FPU, C_Flags);
      return FP_Register (Result);
   end FADD_D;

   ------------
   -- FSUB_D --
   ------------

   function FSUB_D (FPU  : in out FPU_State;
                    A, B : FP_Register;
                    RM   : Rounding_Mode) return FP_Register is
      C_Flags : aliased Word := 0;
      Result  : Unsigned_64;
   begin
      if Is_SNaN_D (A) or Is_SNaN_D (B) then
         FPU.FCSR.Flags.NV := True;
         return Canonical_NaN_D;
      end if;
      if Is_NaN_D (A) or Is_NaN_D (B) then
         return Canonical_NaN_D;
      end if;

      Result := C_FP_Sub_D (Unsigned_64 (A), Unsigned_64 (B),
                             RM_To_Int (FPU, RM), C_Flags'Access);

      if Is_NaN_D (FP_Register (Result)) then
         Apply_C_Flags (FPU, C_Flags);
         return Canonical_NaN_D;
      end if;

      Apply_C_Flags (FPU, C_Flags);
      return FP_Register (Result);
   end FSUB_D;

   ------------
   -- FMUL_D --
   ------------

   function FMUL_D (FPU  : in out FPU_State;
                    A, B : FP_Register;
                    RM   : Rounding_Mode) return FP_Register is
      C_Flags : aliased Word := 0;
      Result  : Unsigned_64;
   begin
      if Is_SNaN_D (A) or Is_SNaN_D (B) then
         FPU.FCSR.Flags.NV := True;
         return Canonical_NaN_D;
      end if;
      if Is_NaN_D (A) or Is_NaN_D (B) then
         return Canonical_NaN_D;
      end if;

      if (Is_Zero_D (A) and Is_Inf_D (B)) or
         (Is_Inf_D (A) and Is_Zero_D (B))
      then
         FPU.FCSR.Flags.NV := True;
         return Canonical_NaN_D;
      end if;

      Result := C_FP_Mul_D (Unsigned_64 (A), Unsigned_64 (B),
                             RM_To_Int (FPU, RM), C_Flags'Access);

      if Is_NaN_D (FP_Register (Result)) then
         Apply_C_Flags (FPU, C_Flags);
         return Canonical_NaN_D;
      end if;

      Apply_C_Flags (FPU, C_Flags);
      return FP_Register (Result);
   end FMUL_D;

   ------------
   -- FDIV_D --
   ------------

   function FDIV_D (FPU  : in out FPU_State;
                    A, B : FP_Register;
                    RM   : Rounding_Mode) return FP_Register is
      C_Flags : aliased Word := 0;
      Result  : Unsigned_64;
   begin
      if Is_SNaN_D (A) or Is_SNaN_D (B) then
         FPU.FCSR.Flags.NV := True;
         return Canonical_NaN_D;
      end if;
      if Is_NaN_D (A) or Is_NaN_D (B) then
         return Canonical_NaN_D;
      end if;

      Result := C_FP_Div_D (Unsigned_64 (A), Unsigned_64 (B),
                             RM_To_Int (FPU, RM), C_Flags'Access);

      if Is_NaN_D (FP_Register (Result)) then
         Apply_C_Flags (FPU, C_Flags);
         return Canonical_NaN_D;
      end if;

      Apply_C_Flags (FPU, C_Flags);
      return FP_Register (Result);
   end FDIV_D;

   -------------
   -- FSQRT_D --
   -------------

   function FSQRT_D (FPU : in out FPU_State;
                     A   : FP_Register;
                     RM  : Rounding_Mode) return FP_Register is
      C_Flags : aliased Word := 0;
      Result  : Unsigned_64;
   begin
      if Is_SNaN_D (A) then
         FPU.FCSR.Flags.NV := True;
         return Canonical_NaN_D;
      end if;
      if Is_NaN_D (A) then
         return Canonical_NaN_D;
      end if;

      if Is_Negative_D (A) and not Is_Zero_D (A) then
         FPU.FCSR.Flags.NV := True;
         return Canonical_NaN_D;
      end if;

      if Is_Inf_D (A) or Is_Zero_D (A) then
         return A;
      end if;

      Result := C_FP_Sqrt_D (Unsigned_64 (A), RM_To_Int (FPU, RM),
                              C_Flags'Access);
      Apply_C_Flags (FPU, C_Flags);
      return FP_Register (Result);
   end FSQRT_D;

   ------------
   -- FMIN_D --
   ------------

   function FMIN_D (FPU  : in out FPU_State;
                    A, B : FP_Register) return FP_Register is
      FA, FB : Float_64;
   begin
      if Is_SNaN_D (A) or Is_SNaN_D (B) then
         FPU.FCSR.Flags.NV := True;
      end if;

      if Is_NaN_D (A) and Is_NaN_D (B) then
         return Canonical_NaN_D;
      end if;
      if Is_NaN_D (A) then return B; end if;
      if Is_NaN_D (B) then return A; end if;

      if Is_Zero_D (A) and Is_Zero_D (B) then
         if Is_Negative_D (A) then return A; else return B; end if;
      end if;

      FA := To_Double (A);
      FB := To_Double (B);
      if FA < FB then
         return A;
      else
         return B;
      end if;
   end FMIN_D;

   ------------
   -- FMAX_D --
   ------------

   function FMAX_D (FPU  : in out FPU_State;
                    A, B : FP_Register) return FP_Register is
      FA, FB : Float_64;
   begin
      if Is_SNaN_D (A) or Is_SNaN_D (B) then
         FPU.FCSR.Flags.NV := True;
      end if;

      if Is_NaN_D (A) and Is_NaN_D (B) then
         return Canonical_NaN_D;
      end if;
      if Is_NaN_D (A) then return B; end if;
      if Is_NaN_D (B) then return A; end if;

      if Is_Zero_D (A) and Is_Zero_D (B) then
         if Is_Negative_D (A) then return B; else return A; end if;
      end if;

      FA := To_Double (A);
      FB := To_Double (B);
      if FA > FB then
         return A;
      else
         return B;
      end if;
   end FMAX_D;

   -------------
   -- FSGNJ_D --
   -------------

   function FSGNJ_D (A, B : FP_Register) return FP_Register is
   begin
      return (A and 16#7FFF_FFFF_FFFF_FFFF#) or
             (B and 16#8000_0000_0000_0000#);
   end FSGNJ_D;

   --------------
   -- FSGNJN_D --
   --------------

   function FSGNJN_D (A, B : FP_Register) return FP_Register is
   begin
      return (A and 16#7FFF_FFFF_FFFF_FFFF#) or
             ((not B) and 16#8000_0000_0000_0000#);
   end FSGNJN_D;

   --------------
   -- FSGNJX_D --
   --------------

   function FSGNJX_D (A, B : FP_Register) return FP_Register is
   begin
      return (A and 16#7FFF_FFFF_FFFF_FFFF#) or
             ((A xor B) and 16#8000_0000_0000_0000#);
   end FSGNJX_D;

   -----------
   -- FEQ_D --
   -----------

   function FEQ_D (FPU  : in out FPU_State;
                   A, B : FP_Register) return Word is
      FA, FB : Float_64;
   begin
      if Is_SNaN_D (A) or Is_SNaN_D (B) then
         FPU.FCSR.Flags.NV := True;
      end if;

      if Is_NaN_D (A) or Is_NaN_D (B) then
         return 0;
      end if;

      if Is_Zero_D (A) and Is_Zero_D (B) then
         return 1;
      end if;

      FA := To_Double (A);
      FB := To_Double (B);
      if FA = FB then return 1; else return 0; end if;
   end FEQ_D;

   -----------
   -- FLT_D --
   -----------

   function FLT_D (FPU  : in out FPU_State;
                   A, B : FP_Register) return Word is
      FA, FB : Float_64;
   begin
      if Is_NaN_D (A) or Is_NaN_D (B) then
         FPU.FCSR.Flags.NV := True;
         return 0;
      end if;

      FA := To_Double (A);
      FB := To_Double (B);
      if FA < FB then return 1; else return 0; end if;
   end FLT_D;

   -----------
   -- FLE_D --
   -----------

   function FLE_D (FPU  : in out FPU_State;
                   A, B : FP_Register) return Word is
      FA, FB : Float_64;
   begin
      if Is_NaN_D (A) or Is_NaN_D (B) then
         FPU.FCSR.Flags.NV := True;
         return 0;
      end if;

      FA := To_Double (A);
      FB := To_Double (B);
      if FA <= FB then return 1; else return 0; end if;
   end FLE_D;

   --------------
   -- FCLASS_D --
   --------------

   function FCLASS_D (A : FP_Register) return Word is
   begin
      if Is_Negative_D (A) then
         if Is_Inf_D (A) then return 1; end if;
         if not Is_Zero_D (A) and not Is_Subnormal_D (A) and
            not Is_NaN_D (A) and not Is_Inf_D (A)
         then
            return 2;
         end if;
         if Is_Subnormal_D (A) then return 4; end if;
         if Is_Zero_D (A) then return 8; end if;
      else
         if Is_Zero_D (A) then return 16; end if;
         if Is_Subnormal_D (A) then return 32; end if;
         if not Is_Zero_D (A) and not Is_Subnormal_D (A) and
            not Is_NaN_D (A) and not Is_Inf_D (A)
         then
            return 64;
         end if;
         if Is_Inf_D (A) then return 128; end if;
      end if;
      if Is_SNaN_D (A) then return 256; end if;
      return 512;  -- qNaN
   end FCLASS_D;

   ---------------
   -- FCVT_W_D --
   ---------------

   function FCVT_W_D (FPU : in out FPU_State;
                      A   : FP_Register;
                      RM  : Rounding_Mode) return Word is
      function To_Word_From_Signed is
         new Ada.Unchecked_Conversion (Integer_32, Word);
      C_Flags    : aliased Word := 0;
      RM_Int     : constant Integer := RM_To_Int (FPU, RM);
      Rounded_U  : Unsigned_64;
      FR         : Float_64;
   begin
      if Is_NaN_D (A) then
         FPU.FCSR.Flags.NV := True;
         return 16#7FFFFFFF#;
      end if;

      if Is_Inf_D (A) and not Is_Negative_D (A) then
         FPU.FCSR.Flags.NV := True;
         return 16#7FFFFFFF#;
      end if;

      if Is_Inf_D (A) and Is_Negative_D (A) then
         FPU.FCSR.Flags.NV := True;
         return 16#80000000#;
      end if;

      Rounded_U := C_FP_Round_D (Unsigned_64 (A), RM_Int, C_Flags'Access);
      FR := To_Double (FP_Register (Rounded_U));

      if FR >= 2147483648.0 then
         FPU.FCSR.Flags.NV := True;
         return 16#7FFFFFFF#;
      end if;
      if FR < -2147483648.0 then
         FPU.FCSR.Flags.NV := True;
         return 16#80000000#;
      end if;

      Apply_C_Flags (FPU, C_Flags);
      return To_Word_From_Signed (Integer_32 (FR));
   end FCVT_W_D;

   ----------------
   -- FCVT_WU_D --
   ----------------

   function FCVT_WU_D (FPU : in out FPU_State;
                       A   : FP_Register;
                       RM  : Rounding_Mode) return Word is
      C_Flags    : aliased Word := 0;
      RM_Int     : constant Integer := RM_To_Int (FPU, RM);
      Rounded_U  : Unsigned_64;
      FR         : Float_64;
   begin
      if Is_NaN_D (A) then
         FPU.FCSR.Flags.NV := True;
         return 16#FFFFFFFF#;
      end if;

      if Is_Inf_D (A) and not Is_Negative_D (A) then
         FPU.FCSR.Flags.NV := True;
         return 16#FFFFFFFF#;
      end if;

      if Is_Inf_D (A) and Is_Negative_D (A) then
         FPU.FCSR.Flags.NV := True;
         return 0;
      end if;

      Rounded_U := C_FP_Round_D (Unsigned_64 (A), RM_Int, C_Flags'Access);
      FR := To_Double (FP_Register (Rounded_U));

      if FR >= 4294967296.0 then
         FPU.FCSR.Flags.NV := True;
         return 16#FFFFFFFF#;
      end if;
      if FR < 0.0 then
         FPU.FCSR.Flags.NV := True;
         return 0;
      end if;

      Apply_C_Flags (FPU, C_Flags);
      return Word (Unsigned_64 (FR) and 16#FFFFFFFF#);
   end FCVT_WU_D;

   ---------------
   -- FCVT_D_W --
   ---------------

   function FCVT_D_W (FPU : in out FPU_State;
                      A   : Word;
                      RM  : Rounding_Mode) return FP_Register is
      function To_Signed is new Ada.Unchecked_Conversion (Word, Integer_32);
      C_Flags : aliased Word := 0;
      Result  : Unsigned_64;
   begin
      Result := C_FP_I2D (To_Signed (A), RM_To_Int (FPU, RM),
                           C_Flags'Access);
      Apply_C_Flags (FPU, C_Flags);
      return FP_Register (Result);
   end FCVT_D_W;

   ----------------
   -- FCVT_D_WU --
   ----------------

   function FCVT_D_WU (FPU : in out FPU_State;
                       A   : Word;
                       RM  : Rounding_Mode) return FP_Register is
      C_Flags : aliased Word := 0;
      Result  : Unsigned_64;
   begin
      Result := C_FP_U2D (A, RM_To_Int (FPU, RM), C_Flags'Access);
      Apply_C_Flags (FPU, C_Flags);
      return FP_Register (Result);
   end FCVT_D_WU;

   ----------------
   -- FCVT_L_D --
   ----------------

   function FCVT_L_D (FPU : in out FPU_State;
                      A   : FP_Register;
                      RM  : Rounding_Mode) return FP_Register is
      C_Flags : aliased Word := 0;
      Result  : Unsigned_64;
   begin
      Result := C_FP_D2L (Unsigned_64 (A), RM_To_Int (FPU, RM), C_Flags'Access);
      Apply_C_Flags (FPU, C_Flags);
      return FP_Register (Result);
   end FCVT_L_D;

   -----------------
   -- FCVT_LU_D --
   -----------------

   function FCVT_LU_D (FPU : in out FPU_State;
                       A   : FP_Register;
                       RM  : Rounding_Mode) return FP_Register is
      C_Flags : aliased Word := 0;
      Result  : Unsigned_64;
   begin
      Result := C_FP_D2LU (Unsigned_64 (A), RM_To_Int (FPU, RM), C_Flags'Access);
      Apply_C_Flags (FPU, C_Flags);
      return FP_Register (Result);
   end FCVT_LU_D;

   ----------------
   -- FCVT_D_L --
   ----------------

   function FCVT_D_L (FPU : in out FPU_State;
                      A   : FP_Register;
                      RM  : Rounding_Mode) return FP_Register is
      function To_Int64 is new Ada.Unchecked_Conversion (Unsigned_64, Integer_64);
      C_Flags : aliased Word := 0;
      Result  : Unsigned_64;
   begin
      Result := C_FP_L2D (To_Int64 (Unsigned_64 (A)), RM_To_Int (FPU, RM),
                           C_Flags'Access);
      Apply_C_Flags (FPU, C_Flags);
      return FP_Register (Result);
   end FCVT_D_L;

   -----------------
   -- FCVT_D_LU --
   -----------------

   function FCVT_D_LU (FPU : in out FPU_State;
                       A   : FP_Register;
                       RM  : Rounding_Mode) return FP_Register is
      C_Flags : aliased Word := 0;
      Result  : Unsigned_64;
   begin
      Result := C_FP_LU2D (Unsigned_64 (A), RM_To_Int (FPU, RM), C_Flags'Access);
      Apply_C_Flags (FPU, C_Flags);
      return FP_Register (Result);
   end FCVT_D_LU;

   --------------
   -- FMADD_D --
   --------------

   function FMADD_D (FPU      : in out FPU_State;
                     A, B, C  : FP_Register;
                     RM       : Rounding_Mode) return FP_Register is
      C_Flags : aliased Word := 0;
      Result  : Unsigned_64;
   begin
      --  Any signaling NaN raises NV
      if Is_SNaN_D (A) or Is_SNaN_D (B) or Is_SNaN_D (C) then
         FPU.FCSR.Flags.NV := True;
      end if;

      --  0 * inf or inf * 0 is invalid even with a qNaN addend
      if (Is_Zero_D (A) and Is_Inf_D (B)) or
         (Is_Inf_D (A) and Is_Zero_D (B))
      then
         FPU.FCSR.Flags.NV := True;
         return Canonical_NaN_D;
      end if;

      --  Any NaN input produces canonical NaN
      if Is_NaN_D (A) or Is_NaN_D (B) or Is_NaN_D (C) then
         return Canonical_NaN_D;
      end if;

      --  inf*x + (-inf) where product sign differs from addend sign
      if (Is_Inf_D (A) or Is_Inf_D (B)) and Is_Inf_D (C) then
         declare
            Prod_Sign : constant Boolean :=
               Is_Negative_D (A) xor Is_Negative_D (B);
         begin
            if Prod_Sign /= Is_Negative_D (C) then
               FPU.FCSR.Flags.NV := True;
               return Canonical_NaN_D;
            end if;
         end;
      end if;

      Result := C_FP_Fmadd_D (Unsigned_64 (A), Unsigned_64 (B),
                                Unsigned_64 (C),
                                RM_To_Int (FPU, RM), C_Flags'Access);

      if Is_NaN_D (FP_Register (Result)) then
         Apply_C_Flags (FPU, C_Flags);
         return Canonical_NaN_D;
      end if;

      Apply_C_Flags (FPU, C_Flags);
      return FP_Register (Result);
   end FMADD_D;

   --------------
   -- FMSUB_D --
   --------------

   function FMSUB_D (FPU      : in out FPU_State;
                     A, B, C  : FP_Register;
                     RM       : Rounding_Mode) return FP_Register is
      Neg_C : constant FP_Register := C xor 16#8000_0000_0000_0000#;
   begin
      return FMADD_D (FPU, A, B, Neg_C, RM);
   end FMSUB_D;

   ---------------
   -- FNMADD_D --
   ---------------

   function FNMADD_D (FPU      : in out FPU_State;
                      A, B, C  : FP_Register;
                      RM       : Rounding_Mode) return FP_Register is
      Neg_A : constant FP_Register := A xor 16#8000_0000_0000_0000#;
      Neg_C : constant FP_Register := C xor 16#8000_0000_0000_0000#;
   begin
      return FMADD_D (FPU, Neg_A, B, Neg_C, RM);
   end FNMADD_D;

   ---------------
   -- FNMSUB_D --
   ---------------

   function FNMSUB_D (FPU      : in out FPU_State;
                      A, B, C  : FP_Register;
                      RM       : Rounding_Mode) return FP_Register is
      Neg_A : constant FP_Register := A xor 16#8000_0000_0000_0000#;
   begin
      return FMADD_D (FPU, Neg_A, B, C, RM);
   end FNMSUB_D;

   ---------------
   -- FCVT_S_D --
   ---------------

   function FCVT_S_D (FPU : in out FPU_State;
                      A   : FP_Register;
                      RM  : Rounding_Mode) return Word is
      C_Flags : aliased Word := 0;
      Result  : Word;
   begin
      if Is_SNaN_D (A) then
         FPU.FCSR.Flags.NV := True;
         return Canonical_NaN_S;
      end if;
      if Is_NaN_D (A) then
         return Canonical_NaN_S;
      end if;

      Result := C_FP_D2S (Unsigned_64 (A), RM_To_Int (FPU, RM),
                           C_Flags'Access);

      if Is_NaN_S (Result) then
         Apply_C_Flags (FPU, C_Flags);
         return Canonical_NaN_S;
      end if;

      Apply_C_Flags (FPU, C_Flags);
      return Result;
   end FCVT_S_D;

   ---------------
   -- FCVT_D_S --
   ---------------

   function FCVT_D_S (FPU : in out FPU_State;
                      A   : Word;
                      RM  : Rounding_Mode) return FP_Register is
      pragma Unreferenced (RM);
      FS : Float_32;
      FD : Float_64;
   begin
      if Is_SNaN_S (A) then
         FPU.FCSR.Flags.NV := True;
         return Canonical_NaN_D;
      end if;
      if Is_NaN_S (A) then
         return Canonical_NaN_D;
      end if;

      FS := To_Float (A);
      FD := Float_64 (FS);
      return To_Bits (FD);
   end FCVT_D_S;

   -------------------
   -- FP16_To_FP32  --
   -------------------

   function FP16_To_FP32 (H : Word) return Word is
      Sign : constant Word    := Shift_Left (H and 16#8000#, 16);
      Exp  : constant Natural := Natural (Shift_Right (H, 10) and 16#1F#);
      Mant : constant Word    := H and 16#3FF#;
   begin
      if Exp = 0 then
         if Mant = 0 then
            return Sign;  --  +-0
         else
            --  Subnormal fp16 -> normal fp32
            declare
               M : Word    := Mant;
               E : Natural := 112;  --  127 - 15
            begin
               while (M and 16#400#) = 0 loop
                  M := Shift_Left (M, 1);
                  E := E - 1;
               end loop;
               return Sign
                 or Shift_Left (Word (E), 23)
                 or Shift_Left (M and 16#3FF#, 13);
            end;
         end if;
      elsif Exp = 31 then
         return Sign or 16#7F800000# or Shift_Left (Mant, 13);  --  Inf / NaN
      else
         return Sign or Shift_Left (Word (Exp + 112), 23) or Shift_Left (Mant, 13);
      end if;
   end FP16_To_FP32;

   -------------------
   -- FP32_To_FP16  --
   -------------------

   function FP32_To_FP16 (F : Word; RM : Rounding_Mode) return Word is
      Sign   : constant Word    := Shift_Right (F, 16) and 16#8000#;
      Exp32  : constant Natural := Natural (Shift_Right (F, 23) and 16#FF#);
      Mant32 : constant Word    := F and 16#7FFFFF#;
      Exp16  : Integer;
      Mant16 : Word;
      Guard   : Boolean;
      Sticky  : Boolean;
      RoundUp : Boolean;
   begin
      if Exp32 = 255 then
         if Mant32 = 0 then
            return Sign or 16#7C00#;  --  +-Inf
         else
            return Sign or 16#7E00# or Shift_Right (Mant32, 13);  --  NaN
         end if;
      end if;
      if Exp32 = 0 and Mant32 = 0 then
         return Sign;  --  +-0
      end if;
      Exp16 := Exp32 - 127 + 15;
      if Exp16 >= 31 then
         return Sign or 16#7C00#;  --  Overflow -> +-Inf
      end if;
      if Exp16 <= 0 then
         if Exp16 < -10 then
            return Sign;  --  Underflow -> +-0
         end if;
         declare
            Shift    : constant Natural := Natural (1 - Exp16);
            Full32   : constant Word    := 16#800000# or Mant32;
            Mant_S   : constant Word    := Shift_Right (Full32, Shift + 13);
            Guard_S  : constant Boolean :=
               (Shift_Right (Full32, Shift + 12) and 1) /= 0;
            Sticky_S : constant Boolean :=
               (Full32 and (Shift_Left (1, Natural'Min (Shift + 12, 31)) - 1)) /= 0;
            Do_Round : Boolean := False;
         begin
            case RM is
               when RNE =>
                  Do_Round := Guard_S and (Sticky_S or (Mant_S and 1) /= 0);
               when RUP =>
                  Do_Round := (Guard_S or Sticky_S) and (Sign = 0);
               when RDN =>
                  Do_Round := (Guard_S or Sticky_S) and (Sign /= 0);
               when others => null;
            end case;
            if Do_Round then
               return Sign or ((Mant_S + 1) and 16#3FF#);
            else
               return Sign or (Mant_S and 16#3FF#);
            end if;
         end;
      end if;
      Mant16  := Shift_Right (Mant32, 13);
      Guard   := (Mant32 and 16#1000#) /= 0;
      Sticky  := (Mant32 and 16#0FFF#) /= 0;
      RoundUp := False;
      case RM is
         when RNE =>
            RoundUp := Guard and (Sticky or (Mant16 and 1) /= 0);
         when RUP =>
            RoundUp := (Guard or Sticky) and (Sign = 0);
         when RDN =>
            RoundUp := (Guard or Sticky) and (Sign /= 0);
         when RMM =>
            RoundUp := Guard;
         when others => null;
      end case;
      if RoundUp then
         Mant16 := Mant16 + 1;
         if Mant16 >= 16#400# then
            Exp16  := Exp16 + 1;
            Mant16 := 0;
            if Exp16 >= 31 then
               return Sign or 16#7C00#;
            end if;
         end if;
      end if;
      return Sign or Shift_Left (Word (Exp16), 10) or Mant16;
   end FP32_To_FP16;

   ---------------
   -- Read_Half --
   ---------------

   function Read_Half (FPU : FPU_State; Reg : Register_Index) return Word is
      Val : constant FP_Register := FPU.Registers (Reg);
   begin
      if (Val and 16#FFFFFFFFFFFF0000#) = 16#FFFFFFFFFFFF0000# then
         return Word (Val and 16#FFFF#);
      else
         return 16#7E00#;  --  canonical qNaN for unboxed value
      end if;
   end Read_Half;

   ----------------
   -- Write_Half --
   ----------------

   procedure Write_Half (FPU : in out FPU_State; Reg : Register_Index; H : Word) is
   begin
      FPU.Registers (Reg) :=
         16#FFFFFFFFFFFF0000# or FP_Register (H and 16#FFFF#);
   end Write_Half;

   ------------
   -- FADD_H --
   ------------

   function FADD_H (FPU : in out FPU_State; A, B : Word; RM : Rounding_Mode) return Word is
   begin
      return FP32_To_FP16 (FADD_S (FPU, FP16_To_FP32 (A), FP16_To_FP32 (B), RM), RM);
   end FADD_H;

   function FSUB_H (FPU : in out FPU_State; A, B : Word; RM : Rounding_Mode) return Word is
   begin
      return FP32_To_FP16 (FSUB_S (FPU, FP16_To_FP32 (A), FP16_To_FP32 (B), RM), RM);
   end FSUB_H;

   function FMUL_H (FPU : in out FPU_State; A, B : Word; RM : Rounding_Mode) return Word is
   begin
      return FP32_To_FP16 (FMUL_S (FPU, FP16_To_FP32 (A), FP16_To_FP32 (B), RM), RM);
   end FMUL_H;

   function FDIV_H (FPU : in out FPU_State; A, B : Word; RM : Rounding_Mode) return Word is
   begin
      return FP32_To_FP16 (FDIV_S (FPU, FP16_To_FP32 (A), FP16_To_FP32 (B), RM), RM);
   end FDIV_H;

   function FSQRT_H (FPU : in out FPU_State; A : Word; RM : Rounding_Mode) return Word is
   begin
      return FP32_To_FP16 (FSQRT_S (FPU, FP16_To_FP32 (A), RM), RM);
   end FSQRT_H;

   function FMIN_H (FPU : in out FPU_State; A, B : Word) return Word is
   begin
      return FP32_To_FP16 (FMIN_S (FPU, FP16_To_FP32 (A), FP16_To_FP32 (B)), RNE);
   end FMIN_H;

   function FMAX_H (FPU : in out FPU_State; A, B : Word) return Word is
   begin
      return FP32_To_FP16 (FMAX_S (FPU, FP16_To_FP32 (A), FP16_To_FP32 (B)), RNE);
   end FMAX_H;

   function FSGNJ_H (A, B : Word) return Word is
   begin
      return (A and 16#7FFF#) or (B and 16#8000#);
   end FSGNJ_H;

   function FSGNJN_H (A, B : Word) return Word is
   begin
      return (A and 16#7FFF#) or ((not B) and 16#8000#);
   end FSGNJN_H;

   function FSGNJX_H (A, B : Word) return Word is
   begin
      return (A and 16#7FFF#) or ((A xor B) and 16#8000#);
   end FSGNJX_H;

   function FEQ_H (FPU : in out FPU_State; A, B : Word) return Word is
   begin
      return FEQ_S (FPU, FP16_To_FP32 (A), FP16_To_FP32 (B));
   end FEQ_H;

   function FLT_H (FPU : in out FPU_State; A, B : Word) return Word is
   begin
      return FLT_S (FPU, FP16_To_FP32 (A), FP16_To_FP32 (B));
   end FLT_H;

   function FLE_H (FPU : in out FPU_State; A, B : Word) return Word is
   begin
      return FLE_S (FPU, FP16_To_FP32 (A), FP16_To_FP32 (B));
   end FLE_H;

   --------------
   -- FCLASS_H --
   --------------

   function FCLASS_H (A : Word) return Word is
      Sign : constant Boolean := (A and 16#8000#) /= 0;
      Exp  : constant Natural := Natural (Shift_Right (A, 10) and 16#1F#);
      Mant : constant Word    := A and 16#3FF#;
   begin
      if Exp = 31 then
         if Mant = 0 then
            return (if Sign then 1 else Shift_Left (1, 7));  --  +-Inf
         else
            return (if (Mant and 16#200#) /= 0
                    then Shift_Left (1, 9)                    --  qNaN
                    else Shift_Left (1, 8));                  --  sNaN
         end if;
      end if;
      if Exp = 0 then
         if Mant = 0 then
            return (if Sign then Shift_Left (1, 3) else Shift_Left (1, 4));  --  +-0
         else
            return (if Sign then Shift_Left (1, 2) else Shift_Left (1, 5));  --  +-subnormal
         end if;
      end if;
      return (if Sign then Shift_Left (1, 1) else Shift_Left (1, 6));  --  +-normal
   end FCLASS_H;

   ----------------
   -- FCVT_W_H   --
   ----------------

   function FCVT_W_H (FPU : in out FPU_State; A : Word; RM : Rounding_Mode) return Word is
   begin
      return FCVT_W_S (FPU, FP16_To_FP32 (A), RM);
   end FCVT_W_H;

   function FCVT_WU_H (FPU : in out FPU_State; A : Word; RM : Rounding_Mode) return Word is
   begin
      return FCVT_WU_S (FPU, FP16_To_FP32 (A), RM);
   end FCVT_WU_H;

   function FCVT_H_W (FPU : in out FPU_State; A : Word; RM : Rounding_Mode) return Word is
   begin
      return FP32_To_FP16 (FCVT_S_W (FPU, A, RM), RM);
   end FCVT_H_W;

   function FCVT_H_WU (FPU : in out FPU_State; A : Word; RM : Rounding_Mode) return Word is
   begin
      return FP32_To_FP16 (FCVT_S_WU (FPU, A, RM), RM);
   end FCVT_H_WU;

   function FCVT_S_H (A : Word) return Word is
   begin
      return FP16_To_FP32 (A);
   end FCVT_S_H;

   function FCVT_H_S (FPU : in out FPU_State; A : Word; RM : Rounding_Mode) return Word is
      pragma Unreferenced (FPU);
   begin
      return FP32_To_FP16 (A, RM);
   end FCVT_H_S;

   function FCVT_D_H (A : Word) return FP_Register is
      F32 : constant Word := FP16_To_FP32 (A);
      Tmp : FPU_State;
   begin
      Initialize (Tmp);
      return FCVT_D_S (Tmp, F32, RNE);
   end FCVT_D_H;

   function FCVT_H_D (FPU : in out FPU_State; A : FP_Register; RM : Rounding_Mode) return Word is
   begin
      return FP32_To_FP16 (FCVT_S_D (FPU, A, RM), RM);
   end FCVT_H_D;

   function FMADD_H (FPU : in out FPU_State; A, B, C : Word; RM : Rounding_Mode) return Word is
   begin
      return FP32_To_FP16
        (FMADD_S (FPU, FP16_To_FP32 (A), FP16_To_FP32 (B), FP16_To_FP32 (C), RM), RM);
   end FMADD_H;

   function FMSUB_H (FPU : in out FPU_State; A, B, C : Word; RM : Rounding_Mode) return Word is
   begin
      return FP32_To_FP16
        (FMSUB_S (FPU, FP16_To_FP32 (A), FP16_To_FP32 (B), FP16_To_FP32 (C), RM), RM);
   end FMSUB_H;

   function FNMADD_H (FPU : in out FPU_State; A, B, C : Word; RM : Rounding_Mode) return Word is
   begin
      return FP32_To_FP16
        (FNMADD_S (FPU, FP16_To_FP32 (A), FP16_To_FP32 (B), FP16_To_FP32 (C), RM), RM);
   end FNMADD_H;

   function FNMSUB_H (FPU : in out FPU_State; A, B, C : Word; RM : Rounding_Mode) return Word is
   begin
      return FP32_To_FP16
        (FNMSUB_S (FPU, FP16_To_FP32 (A), FP16_To_FP32 (B), FP16_To_FP32 (C), RM), RM);
   end FNMSUB_H;

end RISCV.FPU;
