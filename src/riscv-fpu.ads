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

--  RISC-V F (single-precision) and D (double-precision) floating-point
--  extensions implementation.

package RISCV.FPU is

   --  64-bit type for double-precision and register storage
   type FP_Register is new Unsigned_64;

   --  Floating-point register file (f0-f31)
   --  Stored as 64-bit to support both F and D extensions
   type FP_Register_File is array (Register_Index) of FP_Register;

   --  Rounding modes (frm field in fcsr)
   type Rounding_Mode is (
      RNE,  -- Round to Nearest, ties to Even
      RTZ,  -- Round towards Zero
      RDN,  -- Round Down (towards -infinity)
      RUP,  -- Round Up (towards +infinity)
      RMM,  -- Round to Nearest, ties to Max Magnitude
      DYN   -- Dynamic (use frm register)
   );
   for Rounding_Mode use (
      RNE => 0,
      RTZ => 1,
      RDN => 2,
      RUP => 3,
      RMM => 4,
      DYN => 7
   );

   --  Exception flags (fflags field in fcsr)
   type FP_Flags is record
      NX  : Boolean;  -- Inexact
      UF  : Boolean;  -- Underflow
      OVF : Boolean;  -- Overflow
      DZ  : Boolean;  -- Divide by Zero
      NV  : Boolean;  -- Invalid Operation
   end record;

   --  Floating-point Control and Status Register
   type FCSR_Type is record
      Flags : FP_Flags;
      RM    : Rounding_Mode;
   end record;

   --  FPU State
   type FPU_State is record
      Registers : FP_Register_File;
      FCSR      : FCSR_Type;
   end record;

   --  Initialize FPU
   procedure Initialize (FPU : out FPU_State);

   --  Register access
   function Read_Register (FPU : FPU_State;
                           Reg : Register_Index) return FP_Register;

   procedure Write_Register (FPU   : in out FPU_State;
                             Reg   : Register_Index;
                             Value : FP_Register);

   --  Single-precision (32-bit) access
   function Read_Single (FPU : FPU_State;
                         Reg : Register_Index) return Word;

   procedure Write_Single (FPU   : in out FPU_State;
                           Reg   : Register_Index;
                           Value : Word);

   --  Double-precision (64-bit) access
   function Read_Double (FPU : FPU_State;
                         Reg : Register_Index) return FP_Register;

   procedure Write_Double (FPU   : in out FPU_State;
                           Reg   : Register_Index;
                           Value : FP_Register);

   --  FCSR access
   function Read_FCSR (FPU : FPU_State) return Word;
   procedure Write_FCSR (FPU : in out FPU_State; Value : Word);

   function Read_FRM (FPU : FPU_State) return Word;
   procedure Write_FRM (FPU : in out FPU_State; Value : Word);

   function Read_FFLAGS (FPU : FPU_State) return Word;
   procedure Write_FFLAGS (FPU : in out FPU_State; Value : Word);

   --  Get effective rounding mode (handles DYN)
   function Get_Rounding_Mode (FPU : FPU_State;
                               RM  : Rounding_Mode) return Rounding_Mode;

   --  Set exception flags
   procedure Set_Flag (FPU  : in out FPU_State;
                       Flag : FP_Flags);

   --  Single-precision arithmetic operations
   function FADD_S (FPU : in out FPU_State;
                    A, B : Word;
                    RM   : Rounding_Mode) return Word;

   function FSUB_S (FPU : in out FPU_State;
                    A, B : Word;
                    RM   : Rounding_Mode) return Word;

   function FMUL_S (FPU : in out FPU_State;
                    A, B : Word;
                    RM   : Rounding_Mode) return Word;

   function FDIV_S (FPU : in out FPU_State;
                    A, B : Word;
                    RM   : Rounding_Mode) return Word;

   function FSQRT_S (FPU : in out FPU_State;
                     A   : Word;
                     RM  : Rounding_Mode) return Word;

   function FMIN_S (FPU  : in out FPU_State;
                    A, B : Word) return Word;

   function FMAX_S (FPU  : in out FPU_State;
                    A, B : Word) return Word;

   --  Single-precision sign manipulation
   function FSGNJ_S (A, B : Word) return Word;   -- Sign injection
   function FSGNJN_S (A, B : Word) return Word;  -- Negated sign injection
   function FSGNJX_S (A, B : Word) return Word;  -- XOR sign injection

   --  Single-precision comparisons
   function FEQ_S (FPU  : in out FPU_State;
                   A, B : Word) return Word;  -- Returns 0 or 1

   function FLT_S (FPU  : in out FPU_State;
                   A, B : Word) return Word;

   function FLE_S (FPU  : in out FPU_State;
                   A, B : Word) return Word;

   --  Single-precision classification
   function FCLASS_S (A : Word) return Word;

   --  Single-precision conversions
   function FCVT_W_S (FPU : in out FPU_State;
                      A   : Word;
                      RM  : Rounding_Mode) return Word;  -- float to signed int

   function FCVT_WU_S (FPU : in out FPU_State;
                       A   : Word;
                       RM  : Rounding_Mode) return Word; -- float to unsigned int

   function FCVT_L_S  (FPU : in out FPU_State;
                       A   : Word;
                       RM  : Rounding_Mode) return FP_Register; -- float->int64

   function FCVT_LU_S (FPU : in out FPU_State;
                       A   : Word;
                       RM  : Rounding_Mode) return FP_Register; -- float->uint64

   function FCVT_S_W (FPU : in out FPU_State;
                      A   : Word;
                      RM  : Rounding_Mode) return Word;  -- signed int to float

   function FCVT_S_WU (FPU : in out FPU_State;
                       A   : Word;
                       RM  : Rounding_Mode) return Word; -- unsigned int to float

   function FCVT_S_L  (FPU : in out FPU_State;
                       A   : FP_Register;
                       RM  : Rounding_Mode) return Word; -- int64 to float

   function FCVT_S_LU (FPU : in out FPU_State;
                       A   : FP_Register;
                       RM  : Rounding_Mode) return Word; -- uint64 to float

   --  Move between integer and FP registers (bit-level, no conversion)
   function FMV_X_W (A : Word) return Word;  -- FP bits to integer reg
   function FMV_W_X (A : Word) return Word;  -- Integer reg to FP bits

   --  Single-precision fused multiply-add
   function FMADD_S (FPU      : in out FPU_State;
                     A, B, C  : Word;
                     RM       : Rounding_Mode) return Word;

   function FMSUB_S (FPU      : in out FPU_State;
                     A, B, C  : Word;
                     RM       : Rounding_Mode) return Word;

   function FNMADD_S (FPU      : in out FPU_State;
                      A, B, C  : Word;
                      RM       : Rounding_Mode) return Word;

   function FNMSUB_S (FPU      : in out FPU_State;
                      A, B, C  : Word;
                      RM       : Rounding_Mode) return Word;

   --  Double-precision arithmetic operations
   function FADD_D (FPU  : in out FPU_State;
                    A, B : FP_Register;
                    RM   : Rounding_Mode) return FP_Register;

   function FSUB_D (FPU  : in out FPU_State;
                    A, B : FP_Register;
                    RM   : Rounding_Mode) return FP_Register;

   function FMUL_D (FPU  : in out FPU_State;
                    A, B : FP_Register;
                    RM   : Rounding_Mode) return FP_Register;

   function FDIV_D (FPU  : in out FPU_State;
                    A, B : FP_Register;
                    RM   : Rounding_Mode) return FP_Register;

   function FSQRT_D (FPU : in out FPU_State;
                     A   : FP_Register;
                     RM  : Rounding_Mode) return FP_Register;

   function FMIN_D (FPU  : in out FPU_State;
                    A, B : FP_Register) return FP_Register;

   function FMAX_D (FPU  : in out FPU_State;
                    A, B : FP_Register) return FP_Register;

   --  Double-precision sign manipulation
   function FSGNJ_D (A, B : FP_Register) return FP_Register;
   function FSGNJN_D (A, B : FP_Register) return FP_Register;
   function FSGNJX_D (A, B : FP_Register) return FP_Register;

   --  Double-precision comparisons
   function FEQ_D (FPU  : in out FPU_State;
                   A, B : FP_Register) return Word;

   function FLT_D (FPU  : in out FPU_State;
                   A, B : FP_Register) return Word;

   function FLE_D (FPU  : in out FPU_State;
                   A, B : FP_Register) return Word;

   --  Double-precision classification
   function FCLASS_D (A : FP_Register) return Word;

   --  Double-precision conversions
   function FCVT_W_D (FPU : in out FPU_State;
                      A   : FP_Register;
                      RM  : Rounding_Mode) return Word;

   function FCVT_WU_D (FPU : in out FPU_State;
                       A   : FP_Register;
                       RM  : Rounding_Mode) return Word;

   function FCVT_D_W (FPU : in out FPU_State;
                      A   : Word;
                      RM  : Rounding_Mode) return FP_Register;

   function FCVT_D_WU (FPU : in out FPU_State;
                       A   : Word;
                       RM  : Rounding_Mode) return FP_Register;

   --  RV64 64-bit integer <-> double conversions
   --  (result/input stored as FP_Register = Unsigned_64 bit pattern)
   function FCVT_L_D  (FPU : in out FPU_State;
                       A   : FP_Register;
                       RM  : Rounding_Mode) return FP_Register;  -- double -> int64

   function FCVT_LU_D (FPU : in out FPU_State;
                       A   : FP_Register;
                       RM  : Rounding_Mode) return FP_Register;  -- double -> uint64

   function FCVT_D_L  (FPU : in out FPU_State;
                       A   : FP_Register;
                       RM  : Rounding_Mode) return FP_Register;  -- int64 -> double

   function FCVT_D_LU (FPU : in out FPU_State;
                       A   : FP_Register;
                       RM  : Rounding_Mode) return FP_Register;  -- uint64 -> double

   --  Double-precision fused multiply-add
   function FMADD_D (FPU      : in out FPU_State;
                     A, B, C  : FP_Register;
                     RM       : Rounding_Mode) return FP_Register;

   function FMSUB_D (FPU      : in out FPU_State;
                     A, B, C  : FP_Register;
                     RM       : Rounding_Mode) return FP_Register;

   function FNMADD_D (FPU      : in out FPU_State;
                      A, B, C  : FP_Register;
                      RM       : Rounding_Mode) return FP_Register;

   function FNMSUB_D (FPU      : in out FPU_State;
                      A, B, C  : FP_Register;
                      RM       : Rounding_Mode) return FP_Register;

   --  Conversions between single and double precision
   function FCVT_S_D (FPU : in out FPU_State;
                      A   : FP_Register;
                      RM  : Rounding_Mode) return Word;

   function FCVT_D_S (FPU : in out FPU_State;
                      A   : Word;
                      RM  : Rounding_Mode) return FP_Register;

   --  ================================================================
   --  Zfh: IEEE 754 half-precision (16-bit) support
   --  ================================================================

   --  fp16 <-> fp32 bit-level conversions
   function FP16_To_FP32 (H : Word) return Word;
   function FP32_To_FP16 (F : Word; RM : Rounding_Mode) return Word;

   --  Half-precision register access (NaN-boxed in 64-bit FP register)
   function  Read_Half  (FPU : FPU_State; Reg : Register_Index) return Word;
   procedure Write_Half (FPU : in out FPU_State; Reg : Register_Index; H : Word);

   --  Half-precision arithmetic (promote to fp32, operate, demote)
   function FADD_H  (FPU : in out FPU_State; A, B : Word; RM : Rounding_Mode) return Word;
   function FSUB_H  (FPU : in out FPU_State; A, B : Word; RM : Rounding_Mode) return Word;
   function FMUL_H  (FPU : in out FPU_State; A, B : Word; RM : Rounding_Mode) return Word;
   function FDIV_H  (FPU : in out FPU_State; A, B : Word; RM : Rounding_Mode) return Word;
   function FSQRT_H (FPU : in out FPU_State; A : Word; RM : Rounding_Mode) return Word;
   function FMIN_H  (FPU : in out FPU_State; A, B : Word) return Word;
   function FMAX_H  (FPU : in out FPU_State; A, B : Word) return Word;
   function FSGNJ_H  (A, B : Word) return Word;
   function FSGNJN_H (A, B : Word) return Word;
   function FSGNJX_H (A, B : Word) return Word;
   function FEQ_H   (FPU : in out FPU_State; A, B : Word) return Word;
   function FLT_H   (FPU : in out FPU_State; A, B : Word) return Word;
   function FLE_H   (FPU : in out FPU_State; A, B : Word) return Word;
   function FCLASS_H (A : Word) return Word;

   --  Integer <-> half conversions
   function FCVT_W_H  (FPU : in out FPU_State; A : Word; RM : Rounding_Mode) return Word;
   function FCVT_WU_H (FPU : in out FPU_State; A : Word; RM : Rounding_Mode) return Word;
   function FCVT_H_W  (FPU : in out FPU_State; A : Word; RM : Rounding_Mode) return Word;
   function FCVT_H_WU (FPU : in out FPU_State; A : Word; RM : Rounding_Mode) return Word;

   --  Cross-format conversions involving half
   function FCVT_S_H  (A : Word) return Word;
   function FCVT_H_S  (FPU : in out FPU_State; A : Word; RM : Rounding_Mode) return Word;
   function FCVT_D_H  (A : Word) return FP_Register;
   function FCVT_H_D  (FPU : in out FPU_State; A : FP_Register; RM : Rounding_Mode) return Word;

   --  Fused multiply-add for half
   function FMADD_H  (FPU : in out FPU_State; A, B, C : Word; RM : Rounding_Mode) return Word;
   function FMSUB_H  (FPU : in out FPU_State; A, B, C : Word; RM : Rounding_Mode) return Word;
   function FNMADD_H (FPU : in out FPU_State; A, B, C : Word; RM : Rounding_Mode) return Word;
   function FNMSUB_H (FPU : in out FPU_State; A, B, C : Word; RM : Rounding_Mode) return Word;

end RISCV.FPU;
