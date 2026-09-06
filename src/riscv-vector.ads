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

--  RISC-V Vector Extension (RVV 1.0) implementation.
--  Supports configurable VLEN (default 128 bits).

with RISCV.Memory;
with RISCV.FPU;

package RISCV.Vector is

   --  VLEN: Vector register length in bits (must be power of 2, >= 128)
   --  Common values: 128, 256, 512, 1024
   VLEN : constant := 128;

   --  ELEN: Maximum element width in bits
   ELEN : constant := 64;

   --  Derived constants
   VLENB : constant := VLEN / 8;  -- Vector register length in bytes

   --  Vector register storage (VLEN bits = VLENB bytes)
   type Vector_Bytes is array (0 .. VLENB - 1) of Byte;
   type Vector_Register is record
      Data : Vector_Bytes;
   end record;

   --  Vector register file (v0-v31)
   type Vector_Register_File is array (Register_Index) of Vector_Register;

   --  Selected Element Width (SEW)
   type SEW_Type is (SEW_8, SEW_16, SEW_32, SEW_64);
   for SEW_Type use (SEW_8 => 0, SEW_16 => 1, SEW_32 => 2, SEW_64 => 3);

   --  Vector Length Multiplier (LMUL)
   --  Encoded as: 0=1, 1=2, 2=4, 3=8, 5=1/8, 6=1/4, 7=1/2
   type LMUL_Type is (LMUL_1, LMUL_2, LMUL_4, LMUL_8,
                      LMUL_F8, LMUL_F4, LMUL_F2);
   for LMUL_Type use (LMUL_1 => 0, LMUL_2 => 1, LMUL_4 => 2, LMUL_8 => 3,
                      LMUL_F8 => 5, LMUL_F4 => 6, LMUL_F2 => 7);

   --  Vector Type (vtype) register fields
   type VType_Record is record
      VSEW   : SEW_Type;    -- Selected Element Width
      VLMUL  : LMUL_Type;   -- Vector Length Multiplier
      VTA    : Boolean;     -- Vector Tail Agnostic
      VMA    : Boolean;     -- Vector Mask Agnostic
      VILL   : Boolean;     -- Illegal vtype setting
   end record;

   --  Vector Unit State
   type Vector_State is record
      Registers : Vector_Register_File;
      VL        : Word;          -- Vector Length (number of elements)
      VType     : VType_Record;  -- Vector Type configuration
      VStart    : Word;          -- Vector start index
      VXSat     : Boolean := False;  -- Fixed-point saturation flag
      VXRM      : Natural range 0 .. 3 := 0;  -- Fixed-point rounding mode
   end record;

   --  Initialize Vector Unit
   procedure Initialize (VU : out Vector_State);

   --  CSR Access
   function Read_VL (VU : Vector_State) return Word;
   function Read_VType (VU : Vector_State) return Word;
   function Read_VLENB return Word;
   function Read_VStart (VU : Vector_State) return Word;
   procedure Write_VStart (VU : in out Vector_State; Value : Word);
   function Read_VXSat (VU : Vector_State) return Word;
   procedure Write_VXSat (VU : in out Vector_State; Value : Word);
   function Read_VXRM (VU : Vector_State) return Word;
   procedure Write_VXRM (VU : in out Vector_State; Value : Word);

   --  Decode vtype from encoded value
   function Decode_VType (Encoded : Word) return VType_Record;

   --  Encode vtype to Word
   function Encode_VType (VT : VType_Record) return Word;

   --  Calculate VLMAX for given SEW and LMUL
   function Get_VLMAX (SEW : SEW_Type; LMUL : LMUL_Type) return Natural;

   --  Get SEW in bits
   function Get_SEW_Bits (SEW : SEW_Type) return Natural;

   --  Get LMUL as a fraction (numerator, denominator)
   procedure Get_LMUL_Fraction (LMUL : LMUL_Type;
                                 Num  : out Natural;
                                 Den  : out Natural);

   --  vsetvl family - Set VL and VType, return new VL
   function Vsetvl (VU    : in out Vector_State;
                    AVL   : Word;
                    VType : Word) return Word;

   --  Element access (read/write elements at specified index)
   function Read_Element (VU    : Vector_State;
                          Reg   : Register_Index;
                          Index : Natural;
                          SEW   : SEW_Type) return Word;

   function Read_Element_64 (VU    : Vector_State;
                             Reg   : Register_Index;
                             Index : Natural) return Unsigned_64;

   procedure Write_Element (VU    : in out Vector_State;
                            Reg   : Register_Index;
                            Index : Natural;
                            SEW   : SEW_Type;
                            Value : Word);

   procedure Write_Element_64 (VU    : in out Vector_State;
                               Reg   : Register_Index;
                               Index : Natural;
                               Value : Unsigned_64);

   --  Mask operations (v0 is the mask register)
   function Get_Mask_Bit (VU    : Vector_State;
                          Index : Natural) return Boolean;

   procedure Set_Mask_Bit (VU    : in out Vector_State;
                           Reg   : Register_Index;
                           Index : Natural;
                           Value : Boolean);

   --  Vector Load/Store operations
   procedure Vector_Load_Unit_Stride
     (VU      : in out Vector_State;
      Mem     : in out Memory.Memory_Unit;
      Vd      : Register_Index;
      Rs1     : Word;
      VM      : Boolean;  -- True = unmasked
      EEW     : SEW_Type);

   procedure Vector_Store_Unit_Stride
     (VU      : in out Vector_State;
      Mem     : in out Memory.Memory_Unit;
      Vs3     : Register_Index;
      Rs1     : Word;
      VM      : Boolean;
      EEW     : SEW_Type);

   procedure Vector_Load_Strided
     (VU      : in out Vector_State;
      Mem     : in out Memory.Memory_Unit;
      Vd      : Register_Index;
      Rs1     : Word;
      Rs2     : Word;  -- Stride
      VM      : Boolean;
      EEW     : SEW_Type);

   procedure Vector_Store_Strided
     (VU      : in out Vector_State;
      Mem     : in out Memory.Memory_Unit;
      Vs3     : Register_Index;
      Rs1     : Word;
      Rs2     : Word;
      VM      : Boolean;
      EEW     : SEW_Type);

   --  Indexed load/store
   procedure Vector_Load_Indexed
     (VU        : in out Vector_State;
      Mem       : in out Memory.Memory_Unit;
      Vd        : Register_Index;
      Rs1       : Word;
      Vs2_Reg   : Register_Index;
      VM        : Boolean;
      Data_EEW  : SEW_Type;
      Index_EEW : SEW_Type);

   procedure Vector_Store_Indexed
     (VU        : in out Vector_State;
      Mem       : in out Memory.Memory_Unit;
      Vs3       : Register_Index;
      Rs1       : Word;
      Vs2_Reg   : Register_Index;
      VM        : Boolean;
      Data_EEW  : SEW_Type;
      Index_EEW : SEW_Type);

   --  Segment load/store (unit-stride)
   procedure Vector_Load_Segment_Unit
     (VU      : in out Vector_State;
      Mem     : in out Memory.Memory_Unit;
      Vd      : Register_Index;
      Rs1     : Word;
      VM      : Boolean;
      EEW     : SEW_Type;
      Nf      : Positive);

   procedure Vector_Store_Segment_Unit
     (VU      : in out Vector_State;
      Mem     : in out Memory.Memory_Unit;
      Vs3     : Register_Index;
      Rs1     : Word;
      VM      : Boolean;
      EEW     : SEW_Type;
      Nf      : Positive);

   --  Segment load/store (strided)
   procedure Vector_Load_Segment_Strided
     (VU      : in out Vector_State;
      Mem     : in out Memory.Memory_Unit;
      Vd      : Register_Index;
      Rs1     : Word;
      Rs2     : Word;
      VM      : Boolean;
      EEW     : SEW_Type;
      Nf      : Positive);

   procedure Vector_Store_Segment_Strided
     (VU      : in out Vector_State;
      Mem     : in out Memory.Memory_Unit;
      Vs3     : Register_Index;
      Rs1     : Word;
      Rs2     : Word;
      VM      : Boolean;
      EEW     : SEW_Type;
      Nf      : Positive);

   --  Segment load/store (indexed)
   procedure Vector_Load_Segment_Indexed
     (VU        : in out Vector_State;
      Mem       : in out Memory.Memory_Unit;
      Vd        : Register_Index;
      Rs1       : Word;
      Vs2_Reg   : Register_Index;
      VM        : Boolean;
      Data_EEW  : SEW_Type;
      Index_EEW : SEW_Type;
      Nf        : Positive);

   procedure Vector_Store_Segment_Indexed
     (VU        : in out Vector_State;
      Mem       : in out Memory.Memory_Unit;
      Vs3       : Register_Index;
      Rs1       : Word;
      Vs2_Reg   : Register_Index;
      VM        : Boolean;
      Data_EEW  : SEW_Type;
      Index_EEW : SEW_Type;
      Nf        : Positive);

   --  Whole-register load/store
   procedure Vector_Load_Whole_Register
     (VU      : in out Vector_State;
      Mem     : in out Memory.Memory_Unit;
      Vd      : Register_Index;
      Rs1     : Word;
      NReg    : Positive);

   procedure Vector_Store_Whole_Register
     (VU      : in out Vector_State;
      Mem     : in out Memory.Memory_Unit;
      Vs3     : Register_Index;
      Rs1     : Word;
      NReg    : Positive);

   --  Slide operations
   procedure VSLIDEUP_VX (VU : in out Vector_State;
                          Vd, Vs2 : Register_Index;
                          Rs1 : Word; VM : Boolean);

   procedure VSLIDEUP_VI (VU : in out Vector_State;
                          Vd, Vs2 : Register_Index;
                          Imm : Natural; VM : Boolean);

   procedure VSLIDEDOWN_VX (VU : in out Vector_State;
                            Vd, Vs2 : Register_Index;
                            Rs1 : Word; VM : Boolean);

   procedure VSLIDEDOWN_VI (VU : in out Vector_State;
                            Vd, Vs2 : Register_Index;
                            Imm : Natural; VM : Boolean);

   procedure VSLIDE1UP_VX (VU : in out Vector_State;
                           Vd, Vs2 : Register_Index;
                           Rs1 : Word; VM : Boolean);

   procedure VSLIDE1DOWN_VX (VU : in out Vector_State;
                             Vd, Vs2 : Register_Index;
                             Rs1 : Word; VM : Boolean);

   --  Gather operations
   procedure VRGATHER_VV (VU : in out Vector_State;
                          Vd, Vs2, Vs1 : Register_Index;
                          VM : Boolean);

   procedure VRGATHER_VX (VU : in out Vector_State;
                          Vd, Vs2 : Register_Index;
                          Rs1 : Word; VM : Boolean);

   procedure VRGATHER_VI (VU : in out Vector_State;
                          Vd, Vs2 : Register_Index;
                          Imm : Natural; VM : Boolean);

   procedure VRGATHEREI16_VV (VU : in out Vector_State;
                              Vd, Vs2, Vs1 : Register_Index;
                              VM : Boolean);

   --  Compress
   procedure VCOMPRESS_VM (VU : in out Vector_State;
                           Vd, Vs2, Vs1 : Register_Index);

   --  Integer multiply-add
   procedure VMACC_VV (VU : in out Vector_State;
                       Vd, Vs1, Vs2 : Register_Index;
                       VM : Boolean);

   procedure VMACC_VX (VU : in out Vector_State;
                       Vd : Register_Index; Rs1 : Word;
                       Vs2 : Register_Index; VM : Boolean);

   procedure VNMSAC_VV (VU : in out Vector_State;
                        Vd, Vs1, Vs2 : Register_Index;
                        VM : Boolean);

   procedure VNMSAC_VX (VU : in out Vector_State;
                        Vd : Register_Index; Rs1 : Word;
                        Vs2 : Register_Index; VM : Boolean);

   procedure VMADD_VV (VU : in out Vector_State;
                       Vd, Vs1, Vs2 : Register_Index;
                       VM : Boolean);

   procedure VMADD_VX (VU : in out Vector_State;
                       Vd : Register_Index; Rs1 : Word;
                       Vs2 : Register_Index; VM : Boolean);

   procedure VNMSUB_VV (VU : in out Vector_State;
                        Vd, Vs1, Vs2 : Register_Index;
                        VM : Boolean);

   procedure VNMSUB_VX (VU : in out Vector_State;
                        Vd : Register_Index; Rs1 : Word;
                        Vs2 : Register_Index; VM : Boolean);

   --  Integer extension (zero/sign extend)
   procedure VZEXT_VF2 (VU : in out Vector_State;
                        Vd, Vs2 : Register_Index;
                        VM : Boolean);

   procedure VZEXT_VF4 (VU : in out Vector_State;
                        Vd, Vs2 : Register_Index;
                        VM : Boolean);

   procedure VZEXT_VF8 (VU : in out Vector_State;
                        Vd, Vs2 : Register_Index;
                        VM : Boolean);

   procedure VSEXT_VF2 (VU : in out Vector_State;
                        Vd, Vs2 : Register_Index;
                        VM : Boolean);

   procedure VSEXT_VF4 (VU : in out Vector_State;
                        Vd, Vs2 : Register_Index;
                        VM : Boolean);

   procedure VSEXT_VF8 (VU : in out Vector_State;
                        Vd, Vs2 : Register_Index;
                        VM : Boolean);

   --  Vector Integer Arithmetic (operate on all active elements)
   procedure VADD_VV (VU : in out Vector_State;
                      Vd, Vs2, Vs1 : Register_Index;
                      VM : Boolean);

   procedure VADD_VX (VU : in out Vector_State;
                      Vd, Vs2 : Register_Index;
                      Rs1 : Word;
                      VM : Boolean);

   procedure VADD_VI (VU : in out Vector_State;
                      Vd, Vs2 : Register_Index;
                      Imm : Signed_Word;
                      VM : Boolean);

   procedure VSUB_VV (VU : in out Vector_State;
                      Vd, Vs2, Vs1 : Register_Index;
                      VM : Boolean);

   procedure VSUB_VX (VU : in out Vector_State;
                      Vd, Vs2 : Register_Index;
                      Rs1 : Word;
                      VM : Boolean);

   procedure VRSUB_VX (VU : in out Vector_State;
                       Vd, Vs2 : Register_Index;
                       Rs1 : Word;
                       VM : Boolean);

   procedure VRSUB_VI (VU : in out Vector_State;
                       Vd, Vs2 : Register_Index;
                       Imm : Signed_Word;
                       VM : Boolean);

   --  Bitwise operations
   procedure VAND_VV (VU : in out Vector_State;
                      Vd, Vs2, Vs1 : Register_Index;
                      VM : Boolean);

   procedure VAND_VX (VU : in out Vector_State;
                      Vd, Vs2 : Register_Index;
                      Rs1 : Word;
                      VM : Boolean);

   procedure VAND_VI (VU : in out Vector_State;
                      Vd, Vs2 : Register_Index;
                      Imm : Signed_Word;
                      VM : Boolean);

   procedure VOR_VV (VU : in out Vector_State;
                     Vd, Vs2, Vs1 : Register_Index;
                     VM : Boolean);

   procedure VOR_VX (VU : in out Vector_State;
                     Vd, Vs2 : Register_Index;
                     Rs1 : Word;
                     VM : Boolean);

   procedure VOR_VI (VU : in out Vector_State;
                     Vd, Vs2 : Register_Index;
                     Imm : Signed_Word;
                     VM : Boolean);

   procedure VXOR_VV (VU : in out Vector_State;
                      Vd, Vs2, Vs1 : Register_Index;
                      VM : Boolean);

   procedure VXOR_VX (VU : in out Vector_State;
                      Vd, Vs2 : Register_Index;
                      Rs1 : Word;
                      VM : Boolean);

   procedure VXOR_VI (VU : in out Vector_State;
                      Vd, Vs2 : Register_Index;
                      Imm : Signed_Word;
                      VM : Boolean);

   --  Shift operations
   procedure VSLL_VV (VU : in out Vector_State;
                      Vd, Vs2, Vs1 : Register_Index;
                      VM : Boolean);

   procedure VSLL_VX (VU : in out Vector_State;
                      Vd, Vs2 : Register_Index;
                      Rs1 : Word;
                      VM : Boolean);

   procedure VSLL_VI (VU : in out Vector_State;
                      Vd, Vs2 : Register_Index;
                      Imm : Natural;
                      VM : Boolean);

   procedure VSRL_VV (VU : in out Vector_State;
                      Vd, Vs2, Vs1 : Register_Index;
                      VM : Boolean);

   procedure VSRL_VX (VU : in out Vector_State;
                      Vd, Vs2 : Register_Index;
                      Rs1 : Word;
                      VM : Boolean);

   procedure VSRL_VI (VU : in out Vector_State;
                      Vd, Vs2 : Register_Index;
                      Imm : Natural;
                      VM : Boolean);

   procedure VSRA_VV (VU : in out Vector_State;
                      Vd, Vs2, Vs1 : Register_Index;
                      VM : Boolean);

   procedure VSRA_VX (VU : in out Vector_State;
                      Vd, Vs2 : Register_Index;
                      Rs1 : Word;
                      VM : Boolean);

   procedure VSRA_VI (VU : in out Vector_State;
                      Vd, Vs2 : Register_Index;
                      Imm : Natural;
                      VM : Boolean);

   --  Min/Max operations
   procedure VMINU_VV (VU : in out Vector_State;
                       Vd, Vs2, Vs1 : Register_Index;
                       VM : Boolean);

   procedure VMINU_VX (VU : in out Vector_State;
                       Vd, Vs2 : Register_Index;
                       Rs1 : Word;
                       VM : Boolean);

   procedure VMIN_VV (VU : in out Vector_State;
                      Vd, Vs2, Vs1 : Register_Index;
                      VM : Boolean);

   procedure VMIN_VX (VU : in out Vector_State;
                      Vd, Vs2 : Register_Index;
                      Rs1 : Word;
                      VM : Boolean);

   procedure VMAXU_VV (VU : in out Vector_State;
                       Vd, Vs2, Vs1 : Register_Index;
                       VM : Boolean);

   procedure VMAXU_VX (VU : in out Vector_State;
                       Vd, Vs2 : Register_Index;
                       Rs1 : Word;
                       VM : Boolean);

   procedure VMAX_VV (VU : in out Vector_State;
                      Vd, Vs2, Vs1 : Register_Index;
                      VM : Boolean);

   procedure VMAX_VX (VU : in out Vector_State;
                      Vd, Vs2 : Register_Index;
                      Rs1 : Word;
                      VM : Boolean);

   --  Comparison operations (write to mask register)
   procedure VMSEQ_VV (VU : in out Vector_State;
                       Vd, Vs2, Vs1 : Register_Index;
                       VM : Boolean);

   procedure VMSEQ_VX (VU : in out Vector_State;
                       Vd, Vs2 : Register_Index;
                       Rs1 : Word;
                       VM : Boolean);

   procedure VMSEQ_VI (VU : in out Vector_State;
                       Vd, Vs2 : Register_Index;
                       Imm : Signed_Word;
                       VM : Boolean);

   procedure VMSNE_VV (VU : in out Vector_State;
                       Vd, Vs2, Vs1 : Register_Index;
                       VM : Boolean);

   procedure VMSNE_VX (VU : in out Vector_State;
                       Vd, Vs2 : Register_Index;
                       Rs1 : Word;
                       VM : Boolean);

   procedure VMSNE_VI (VU : in out Vector_State;
                       Vd, Vs2 : Register_Index;
                       Imm : Signed_Word;
                       VM : Boolean);

   procedure VMSLTU_VV (VU : in out Vector_State;
                        Vd, Vs2, Vs1 : Register_Index;
                        VM : Boolean);

   procedure VMSLTU_VX (VU : in out Vector_State;
                        Vd, Vs2 : Register_Index;
                        Rs1 : Word;
                        VM : Boolean);

   procedure VMSLT_VV (VU : in out Vector_State;
                       Vd, Vs2, Vs1 : Register_Index;
                       VM : Boolean);

   procedure VMSLT_VX (VU : in out Vector_State;
                       Vd, Vs2 : Register_Index;
                       Rs1 : Word;
                       VM : Boolean);

   procedure VMSLEU_VV (VU : in out Vector_State;
                        Vd, Vs2, Vs1 : Register_Index;
                        VM : Boolean);

   procedure VMSLEU_VX (VU : in out Vector_State;
                        Vd, Vs2 : Register_Index;
                        Rs1 : Word;
                        VM : Boolean);

   procedure VMSLEU_VI (VU : in out Vector_State;
                        Vd, Vs2 : Register_Index;
                        Imm : Signed_Word;
                        VM : Boolean);

   procedure VMSLE_VV (VU : in out Vector_State;
                       Vd, Vs2, Vs1 : Register_Index;
                       VM : Boolean);

   procedure VMSLE_VX (VU : in out Vector_State;
                       Vd, Vs2 : Register_Index;
                       Rs1 : Word;
                       VM : Boolean);

   procedure VMSLE_VI (VU : in out Vector_State;
                       Vd, Vs2 : Register_Index;
                       Imm : Signed_Word;
                       VM : Boolean);

   procedure VMSGTU_VX (VU : in out Vector_State;
                        Vd, Vs2 : Register_Index;
                        Rs1 : Word;
                        VM : Boolean);

   procedure VMSGTU_VI (VU : in out Vector_State;
                        Vd, Vs2 : Register_Index;
                        Imm : Signed_Word;
                        VM : Boolean);

   procedure VMSGT_VX (VU : in out Vector_State;
                       Vd, Vs2 : Register_Index;
                       Rs1 : Word;
                       VM : Boolean);

   procedure VMSGT_VI (VU : in out Vector_State;
                       Vd, Vs2 : Register_Index;
                       Imm : Signed_Word;
                       VM : Boolean);

   --  Multiply operations
   procedure VMUL_VV (VU : in out Vector_State;
                      Vd, Vs2, Vs1 : Register_Index;
                      VM : Boolean);

   procedure VMUL_VX (VU : in out Vector_State;
                      Vd, Vs2 : Register_Index;
                      Rs1 : Word;
                      VM : Boolean);

   procedure VMULH_VV (VU : in out Vector_State;
                       Vd, Vs2, Vs1 : Register_Index;
                       VM : Boolean);

   procedure VMULH_VX (VU : in out Vector_State;
                       Vd, Vs2 : Register_Index;
                       Rs1 : Word;
                       VM : Boolean);

   procedure VMULHU_VV (VU : in out Vector_State;
                        Vd, Vs2, Vs1 : Register_Index;
                        VM : Boolean);

   procedure VMULHU_VX (VU : in out Vector_State;
                        Vd, Vs2 : Register_Index;
                        Rs1 : Word;
                        VM : Boolean);

   --  Divide operations
   procedure VDIVU_VV (VU : in out Vector_State;
                       Vd, Vs2, Vs1 : Register_Index;
                       VM : Boolean);

   procedure VDIVU_VX (VU : in out Vector_State;
                       Vd, Vs2 : Register_Index;
                       Rs1 : Word;
                       VM : Boolean);

   procedure VDIV_VV (VU : in out Vector_State;
                      Vd, Vs2, Vs1 : Register_Index;
                      VM : Boolean);

   procedure VDIV_VX (VU : in out Vector_State;
                      Vd, Vs2 : Register_Index;
                      Rs1 : Word;
                      VM : Boolean);

   procedure VREMU_VV (VU : in out Vector_State;
                       Vd, Vs2, Vs1 : Register_Index;
                       VM : Boolean);

   procedure VREMU_VX (VU : in out Vector_State;
                       Vd, Vs2 : Register_Index;
                       Rs1 : Word;
                       VM : Boolean);

   procedure VREM_VV (VU : in out Vector_State;
                      Vd, Vs2, Vs1 : Register_Index;
                      VM : Boolean);

   procedure VREM_VX (VU : in out Vector_State;
                      Vd, Vs2 : Register_Index;
                      Rs1 : Word;
                      VM : Boolean);

   --  Merge and Move
   procedure VMERGE_VVM (VU : in out Vector_State;
                         Vd, Vs2, Vs1 : Register_Index);

   procedure VMERGE_VXM (VU : in out Vector_State;
                         Vd, Vs2 : Register_Index;
                         Rs1 : Word);

   procedure VMERGE_VIM (VU : in out Vector_State;
                         Vd, Vs2 : Register_Index;
                         Imm : Signed_Word);

   procedure VMV_V_V (VU : in out Vector_State;
                      Vd, Vs1 : Register_Index);

   procedure VMV_V_X (VU : in out Vector_State;
                      Vd : Register_Index;
                      Rs1 : Word);

   procedure VMV_V_I (VU : in out Vector_State;
                      Vd : Register_Index;
                      Imm : Signed_Word);

   --  Scalar move (vmv.x.s / vmv.s.x)
   function VMV_X_S (VU : Vector_State;
                     Vs2 : Register_Index) return Word;

   procedure VMV_S_X (VU : in out Vector_State;
                      Vd : Register_Index;
                      Rs1 : Word);

   --  Reduction operations
   function VREDSUM_VS (VU : in out Vector_State;
                        Vs2, Vs1 : Register_Index;
                        VM : Boolean) return Word;

   function VREDMAXU_VS (VU : in out Vector_State;
                         Vs2, Vs1 : Register_Index;
                         VM : Boolean) return Word;

   function VREDMAX_VS (VU : in out Vector_State;
                        Vs2, Vs1 : Register_Index;
                        VM : Boolean) return Word;

   function VREDMINU_VS (VU : in out Vector_State;
                         Vs2, Vs1 : Register_Index;
                         VM : Boolean) return Word;

   function VREDMIN_VS (VU : in out Vector_State;
                        Vs2, Vs1 : Register_Index;
                        VM : Boolean) return Word;

   function VREDAND_VS (VU : in out Vector_State;
                        Vs2, Vs1 : Register_Index;
                        VM : Boolean) return Word;

   function VREDOR_VS (VU : in out Vector_State;
                       Vs2, Vs1 : Register_Index;
                       VM : Boolean) return Word;

   function VREDXOR_VS (VU : in out Vector_State;
                        Vs2, Vs1 : Register_Index;
                        VM : Boolean) return Word;

   --  Mask operations
   procedure VMAND_MM (VU : in out Vector_State;
                       Vd, Vs2, Vs1 : Register_Index);

   procedure VMNAND_MM (VU : in out Vector_State;
                        Vd, Vs2, Vs1 : Register_Index);

   procedure VMANDNOT_MM (VU : in out Vector_State;
                          Vd, Vs2, Vs1 : Register_Index);

   procedure VMXOR_MM (VU : in out Vector_State;
                       Vd, Vs2, Vs1 : Register_Index);

   procedure VMOR_MM (VU : in out Vector_State;
                      Vd, Vs2, Vs1 : Register_Index);

   procedure VMNOR_MM (VU : in out Vector_State;
                       Vd, Vs2, Vs1 : Register_Index);

   procedure VMORNOT_MM (VU : in out Vector_State;
                         Vd, Vs2, Vs1 : Register_Index);

   procedure VMXNOR_MM (VU : in out Vector_State;
                        Vd, Vs2, Vs1 : Register_Index);

   --  Vector count population in mask
   function VCPOP_M (VU : Vector_State;
                     Vs2 : Register_Index;
                     VM : Boolean) return Word;

   --  Find first set bit in mask
   function VFIRST_M (VU : Vector_State;
                      Vs2 : Register_Index;
                      VM : Boolean) return Signed_Word;

   --  Set mask bits
   procedure VMSBF_M (VU : in out Vector_State;
                      Vd, Vs2 : Register_Index;
                      VM : Boolean);

   procedure VMSIF_M (VU : in out Vector_State;
                      Vd, Vs2 : Register_Index;
                      VM : Boolean);

   procedure VMSOF_M (VU : in out Vector_State;
                      Vd, Vs2 : Register_Index;
                      VM : Boolean);

   --  Vector iota
   procedure VIOTA_M (VU : in out Vector_State;
                      Vd, Vs2 : Register_Index;
                      VM : Boolean);

   --  Vector element index
   procedure VID_V (VU : in out Vector_State;
                    Vd : Register_Index;
                    VM : Boolean);

   --  Whole-register move (vmv<n>r.v)
   procedure VMV_NR_V (VU   : in out Vector_State;
                       Vd   : Register_Index;
                       Vs2  : Register_Index;
                       NReg : Positive);

   --  Widening integer add/sub (result is 2*SEW)
   procedure VWADDU_VV (VU : in out Vector_State;
                        Vd, Vs2, Vs1 : Register_Index; VM : Boolean);
   procedure VWADDU_VX (VU : in out Vector_State;
                        Vd, Vs2 : Register_Index; Rs1 : Word; VM : Boolean);
   procedure VWADD_VV (VU : in out Vector_State;
                       Vd, Vs2, Vs1 : Register_Index; VM : Boolean);
   procedure VWADD_VX (VU : in out Vector_State;
                       Vd, Vs2 : Register_Index; Rs1 : Word; VM : Boolean);
   procedure VWSUBU_VV (VU : in out Vector_State;
                        Vd, Vs2, Vs1 : Register_Index; VM : Boolean);
   procedure VWSUBU_VX (VU : in out Vector_State;
                        Vd, Vs2 : Register_Index; Rs1 : Word; VM : Boolean);
   procedure VWSUB_VV (VU : in out Vector_State;
                       Vd, Vs2, Vs1 : Register_Index; VM : Boolean);
   procedure VWSUB_VX (VU : in out Vector_State;
                       Vd, Vs2 : Register_Index; Rs1 : Word; VM : Boolean);

   --  Widening multiply
   procedure VWMULU_VV (VU : in out Vector_State;
                        Vd, Vs2, Vs1 : Register_Index; VM : Boolean);
   procedure VWMULU_VX (VU : in out Vector_State;
                        Vd, Vs2 : Register_Index; Rs1 : Word; VM : Boolean);
   procedure VWMUL_VV (VU : in out Vector_State;
                       Vd, Vs2, Vs1 : Register_Index; VM : Boolean);
   procedure VWMUL_VX (VU : in out Vector_State;
                       Vd, Vs2 : Register_Index; Rs1 : Word; VM : Boolean);
   procedure VWMULSU_VV (VU : in out Vector_State;
                         Vd, Vs2, Vs1 : Register_Index; VM : Boolean);
   procedure VWMULSU_VX (VU : in out Vector_State;
                         Vd, Vs2 : Register_Index; Rs1 : Word; VM : Boolean);

   --  Narrowing shift
   procedure VNSRL_WV (VU : in out Vector_State;
                       Vd, Vs2, Vs1 : Register_Index; VM : Boolean);
   procedure VNSRL_WX (VU : in out Vector_State;
                       Vd, Vs2 : Register_Index; Rs1 : Word; VM : Boolean);
   procedure VNSRL_WI (VU : in out Vector_State;
                       Vd, Vs2 : Register_Index; Imm : Natural; VM : Boolean);
   procedure VNSRA_WV (VU : in out Vector_State;
                       Vd, Vs2, Vs1 : Register_Index; VM : Boolean);
   procedure VNSRA_WX (VU : in out Vector_State;
                       Vd, Vs2 : Register_Index; Rs1 : Word; VM : Boolean);
   procedure VNSRA_WI (VU : in out Vector_State;
                       Vd, Vs2 : Register_Index; Imm : Natural; VM : Boolean);

   --  FP vector operations (require FPU state)
   type FPU_Access is access all RISCV.FPU.FPU_State;

   procedure VFADD_VV (VU : in out Vector_State; FP : FPU_Access;
                       Vd, Vs2, Vs1 : Register_Index; VM : Boolean);
   procedure VFADD_VF (VU : in out Vector_State; FP : FPU_Access;
                       Vd, Vs2 : Register_Index; Fs1 : Word; VM : Boolean);
   procedure VFSUB_VV (VU : in out Vector_State; FP : FPU_Access;
                       Vd, Vs2, Vs1 : Register_Index; VM : Boolean);
   procedure VFSUB_VF (VU : in out Vector_State; FP : FPU_Access;
                       Vd, Vs2 : Register_Index; Fs1 : Word; VM : Boolean);
   procedure VFMUL_VV (VU : in out Vector_State; FP : FPU_Access;
                       Vd, Vs2, Vs1 : Register_Index; VM : Boolean);
   procedure VFMUL_VF (VU : in out Vector_State; FP : FPU_Access;
                       Vd, Vs2 : Register_Index; Fs1 : Word; VM : Boolean);
   procedure VFDIV_VV (VU : in out Vector_State; FP : FPU_Access;
                       Vd, Vs2, Vs1 : Register_Index; VM : Boolean);
   procedure VFDIV_VF (VU : in out Vector_State; FP : FPU_Access;
                       Vd, Vs2 : Register_Index; Fs1 : Word; VM : Boolean);
   procedure VFMIN_VV (VU : in out Vector_State; FP : FPU_Access;
                       Vd, Vs2, Vs1 : Register_Index; VM : Boolean);
   procedure VFMIN_VF (VU : in out Vector_State; FP : FPU_Access;
                       Vd, Vs2 : Register_Index; Fs1 : Word; VM : Boolean);
   procedure VFMAX_VV (VU : in out Vector_State; FP : FPU_Access;
                       Vd, Vs2, Vs1 : Register_Index; VM : Boolean);
   procedure VFMAX_VF (VU : in out Vector_State; FP : FPU_Access;
                       Vd, Vs2 : Register_Index; Fs1 : Word; VM : Boolean);
   procedure VFSQRT_V (VU : in out Vector_State; FP : FPU_Access;
                       Vd, Vs2 : Register_Index; VM : Boolean);
   procedure VFMACC_VV (VU : in out Vector_State; FP : FPU_Access;
                        Vd, Vs1, Vs2 : Register_Index; VM : Boolean);
   procedure VFMACC_VF (VU : in out Vector_State; FP : FPU_Access;
                        Vd : Register_Index; Fs1 : Word;
                        Vs2 : Register_Index; VM : Boolean);
   procedure VFNMACC_VV (VU : in out Vector_State; FP : FPU_Access;
                         Vd, Vs1, Vs2 : Register_Index; VM : Boolean);
   procedure VFNMACC_VF (VU : in out Vector_State; FP : FPU_Access;
                         Vd : Register_Index; Fs1 : Word;
                         Vs2 : Register_Index; VM : Boolean);
   procedure VFMSAC_VV (VU : in out Vector_State; FP : FPU_Access;
                        Vd, Vs1, Vs2 : Register_Index; VM : Boolean);
   procedure VFMSAC_VF (VU : in out Vector_State; FP : FPU_Access;
                        Vd : Register_Index; Fs1 : Word;
                        Vs2 : Register_Index; VM : Boolean);
   procedure VFNMSAC_VV (VU : in out Vector_State; FP : FPU_Access;
                         Vd, Vs1, Vs2 : Register_Index; VM : Boolean);
   procedure VFNMSAC_VF (VU : in out Vector_State; FP : FPU_Access;
                         Vd : Register_Index; Fs1 : Word;
                         Vs2 : Register_Index; VM : Boolean);

   --  Widening .w variants (wide vs2, narrow vs1, wide result)
   procedure VWADDUW_VV (VU : in out Vector_State;
                         Vd, Vs2, Vs1 : Register_Index; VM : Boolean);
   procedure VWADDUW_VX (VU : in out Vector_State;
                         Vd, Vs2 : Register_Index; Rs1 : Word; VM : Boolean);
   procedure VWADDW_VV (VU : in out Vector_State;
                        Vd, Vs2, Vs1 : Register_Index; VM : Boolean);
   procedure VWADDW_VX (VU : in out Vector_State;
                        Vd, Vs2 : Register_Index; Rs1 : Word; VM : Boolean);
   procedure VWSUBUW_VV (VU : in out Vector_State;
                         Vd, Vs2, Vs1 : Register_Index; VM : Boolean);
   procedure VWSUBUW_VX (VU : in out Vector_State;
                         Vd, Vs2 : Register_Index; Rs1 : Word; VM : Boolean);
   procedure VWSUBW_VV (VU : in out Vector_State;
                        Vd, Vs2, Vs1 : Register_Index; VM : Boolean);
   procedure VWSUBW_VX (VU : in out Vector_State;
                        Vd, Vs2 : Register_Index; Rs1 : Word; VM : Boolean);

   --  Carry/Borrow operations
   procedure VADC_VVM (VU : in out Vector_State;
                       Vd, Vs2, Vs1 : Register_Index);
   procedure VADC_VXM (VU : in out Vector_State;
                       Vd, Vs2 : Register_Index; Rs1 : Word);
   procedure VADC_VIM (VU : in out Vector_State;
                       Vd, Vs2 : Register_Index; Imm : Signed_Word);
   procedure VMADC_VVM (VU : in out Vector_State;
                        Vd, Vs2, Vs1 : Register_Index; VM : Boolean);
   procedure VMADC_VXM (VU : in out Vector_State;
                        Vd, Vs2 : Register_Index; Rs1 : Word; VM : Boolean);
   procedure VMADC_VIM (VU : in out Vector_State;
                        Vd, Vs2 : Register_Index; Imm : Signed_Word;
                        VM : Boolean);
   procedure VSBC_VVM (VU : in out Vector_State;
                       Vd, Vs2, Vs1 : Register_Index);
   procedure VSBC_VXM (VU : in out Vector_State;
                       Vd, Vs2 : Register_Index; Rs1 : Word);
   procedure VMSBC_VVM (VU : in out Vector_State;
                        Vd, Vs2, Vs1 : Register_Index; VM : Boolean);
   procedure VMSBC_VXM (VU : in out Vector_State;
                        Vd, Vs2 : Register_Index; Rs1 : Word; VM : Boolean);

   --  Fixed-point saturating operations
   procedure VSADDU_VV (VU : in out Vector_State;
                        Vd, Vs2, Vs1 : Register_Index; VM : Boolean);
   procedure VSADDU_VX (VU : in out Vector_State;
                        Vd, Vs2 : Register_Index; Rs1 : Word; VM : Boolean);
   procedure VSADDU_VI (VU : in out Vector_State;
                        Vd, Vs2 : Register_Index; Imm : Signed_Word;
                        VM : Boolean);
   procedure VSADD_VV (VU : in out Vector_State;
                       Vd, Vs2, Vs1 : Register_Index; VM : Boolean);
   procedure VSADD_VX (VU : in out Vector_State;
                       Vd, Vs2 : Register_Index; Rs1 : Word; VM : Boolean);
   procedure VSADD_VI (VU : in out Vector_State;
                       Vd, Vs2 : Register_Index; Imm : Signed_Word;
                       VM : Boolean);
   procedure VSSUBU_VV (VU : in out Vector_State;
                        Vd, Vs2, Vs1 : Register_Index; VM : Boolean);
   procedure VSSUBU_VX (VU : in out Vector_State;
                        Vd, Vs2 : Register_Index; Rs1 : Word; VM : Boolean);
   procedure VSSUB_VV (VU : in out Vector_State;
                       Vd, Vs2, Vs1 : Register_Index; VM : Boolean);
   procedure VSSUB_VX (VU : in out Vector_State;
                       Vd, Vs2 : Register_Index; Rs1 : Word; VM : Boolean);

   --  VSMUL (signed fractional multiply)
   procedure VSMUL_VV (VU : in out Vector_State;
                       Vd, Vs2, Vs1 : Register_Index; VM : Boolean);
   procedure VSMUL_VX (VU : in out Vector_State;
                       Vd, Vs2 : Register_Index; Rs1 : Word; VM : Boolean);

   --  Rounding shift right
   procedure VSSRL_VV (VU : in out Vector_State;
                       Vd, Vs2, Vs1 : Register_Index; VM : Boolean);
   procedure VSSRL_VX (VU : in out Vector_State;
                       Vd, Vs2 : Register_Index; Rs1 : Word; VM : Boolean);
   procedure VSSRL_VI (VU : in out Vector_State;
                       Vd, Vs2 : Register_Index; Imm : Natural; VM : Boolean);
   procedure VSSRA_VV (VU : in out Vector_State;
                       Vd, Vs2, Vs1 : Register_Index; VM : Boolean);
   procedure VSSRA_VX (VU : in out Vector_State;
                       Vd, Vs2 : Register_Index; Rs1 : Word; VM : Boolean);
   procedure VSSRA_VI (VU : in out Vector_State;
                       Vd, Vs2 : Register_Index; Imm : Natural; VM : Boolean);

   --  Narrowing clip
   procedure VNCLIPU_WV (VU : in out Vector_State;
                         Vd, Vs2, Vs1 : Register_Index; VM : Boolean);
   procedure VNCLIPU_WX (VU : in out Vector_State;
                         Vd, Vs2 : Register_Index; Rs1 : Word; VM : Boolean);
   procedure VNCLIPU_WI (VU : in out Vector_State;
                         Vd, Vs2 : Register_Index; Imm : Natural;
                         VM : Boolean);
   procedure VNCLIP_WV (VU : in out Vector_State;
                        Vd, Vs2, Vs1 : Register_Index; VM : Boolean);
   procedure VNCLIP_WX (VU : in out Vector_State;
                        Vd, Vs2 : Register_Index; Rs1 : Word; VM : Boolean);
   procedure VNCLIP_WI (VU : in out Vector_State;
                        Vd, Vs2 : Register_Index; Imm : Natural;
                        VM : Boolean);

   --  Widening multiply-add
   procedure VWMACCU_VV (VU : in out Vector_State;
                         Vd, Vs1, Vs2 : Register_Index; VM : Boolean);
   procedure VWMACCU_VX (VU : in out Vector_State;
                         Vd : Register_Index; Rs1 : Word;
                         Vs2 : Register_Index; VM : Boolean);
   procedure VWMACC_VV (VU : in out Vector_State;
                        Vd, Vs1, Vs2 : Register_Index; VM : Boolean);
   procedure VWMACC_VX (VU : in out Vector_State;
                        Vd : Register_Index; Rs1 : Word;
                        Vs2 : Register_Index; VM : Boolean);
   procedure VWMACCSU_VV (VU : in out Vector_State;
                          Vd, Vs1, Vs2 : Register_Index; VM : Boolean);
   procedure VWMACCSU_VX (VU : in out Vector_State;
                          Vd : Register_Index; Rs1 : Word;
                          Vs2 : Register_Index; VM : Boolean);
   procedure VWMACCUS_VX (VU : in out Vector_State;
                          Vd : Register_Index; Rs1 : Word;
                          Vs2 : Register_Index; VM : Boolean);

   --  VMULHSU (signed*unsigned high multiply)
   procedure VMULHSU_VV (VU : in out Vector_State;
                         Vd, Vs2, Vs1 : Register_Index; VM : Boolean);
   procedure VMULHSU_VX (VU : in out Vector_State;
                         Vd, Vs2 : Register_Index; Rs1 : Word; VM : Boolean);

   --  Averaging add/sub
   procedure VAADDU_VV (VU : in out Vector_State;
                        Vd, Vs2, Vs1 : Register_Index; VM : Boolean);
   procedure VAADDU_VX (VU : in out Vector_State;
                        Vd, Vs2 : Register_Index; Rs1 : Word; VM : Boolean);
   procedure VAADD_VV (VU : in out Vector_State;
                       Vd, Vs2, Vs1 : Register_Index; VM : Boolean);
   procedure VAADD_VX (VU : in out Vector_State;
                       Vd, Vs2 : Register_Index; Rs1 : Word; VM : Boolean);
   procedure VASUBU_VV (VU : in out Vector_State;
                        Vd, Vs2, Vs1 : Register_Index; VM : Boolean);
   procedure VASUBU_VX (VU : in out Vector_State;
                        Vd, Vs2 : Register_Index; Rs1 : Word; VM : Boolean);
   procedure VASUB_VV (VU : in out Vector_State;
                       Vd, Vs2, Vs1 : Register_Index; VM : Boolean);
   procedure VASUB_VX (VU : in out Vector_State;
                       Vd, Vs2 : Register_Index; Rs1 : Word; VM : Boolean);

   --  FP comparison (write boolean results to mask register)
   procedure VMFEQ_VV (VU : in out Vector_State; FP : FPU_Access;
                       Vd, Vs2, Vs1 : Register_Index; VM : Boolean);
   procedure VMFEQ_VF (VU : in out Vector_State; FP : FPU_Access;
                       Vd, Vs2 : Register_Index; Fs1 : Word; VM : Boolean);
   procedure VMFLE_VV (VU : in out Vector_State; FP : FPU_Access;
                       Vd, Vs2, Vs1 : Register_Index; VM : Boolean);
   procedure VMFLE_VF (VU : in out Vector_State; FP : FPU_Access;
                       Vd, Vs2 : Register_Index; Fs1 : Word; VM : Boolean);
   procedure VMFLT_VV (VU : in out Vector_State; FP : FPU_Access;
                       Vd, Vs2, Vs1 : Register_Index; VM : Boolean);
   procedure VMFLT_VF (VU : in out Vector_State; FP : FPU_Access;
                       Vd, Vs2 : Register_Index; Fs1 : Word; VM : Boolean);
   procedure VMFNE_VV (VU : in out Vector_State; FP : FPU_Access;
                       Vd, Vs2, Vs1 : Register_Index; VM : Boolean);
   procedure VMFNE_VF (VU : in out Vector_State; FP : FPU_Access;
                       Vd, Vs2 : Register_Index; Fs1 : Word; VM : Boolean);
   procedure VMFGT_VF (VU : in out Vector_State; FP : FPU_Access;
                       Vd, Vs2 : Register_Index; Fs1 : Word; VM : Boolean);
   procedure VMFGE_VF (VU : in out Vector_State; FP : FPU_Access;
                       Vd, Vs2 : Register_Index; Fs1 : Word; VM : Boolean);

   --  FP sign injection
   procedure VFSGNJ_VV (VU : in out Vector_State; FP : FPU_Access;
                        Vd, Vs2, Vs1 : Register_Index; VM : Boolean);
   procedure VFSGNJ_VF (VU : in out Vector_State; FP : FPU_Access;
                        Vd, Vs2 : Register_Index; Fs1 : Word; VM : Boolean);
   procedure VFSGNJN_VV (VU : in out Vector_State; FP : FPU_Access;
                         Vd, Vs2, Vs1 : Register_Index; VM : Boolean);
   procedure VFSGNJN_VF (VU : in out Vector_State; FP : FPU_Access;
                         Vd, Vs2 : Register_Index; Fs1 : Word; VM : Boolean);
   procedure VFSGNJX_VV (VU : in out Vector_State; FP : FPU_Access;
                         Vd, Vs2, Vs1 : Register_Index; VM : Boolean);
   procedure VFSGNJX_VF (VU : in out Vector_State; FP : FPU_Access;
                         Vd, Vs2 : Register_Index; Fs1 : Word; VM : Boolean);

   --  FP classify, reciprocal, merge/move, reverse ops
   procedure VFCLASS_V (VU : in out Vector_State; FP : FPU_Access;
                        Vd, Vs2 : Register_Index; VM : Boolean);
   procedure VFRSQRT7_V (VU : in out Vector_State; FP : FPU_Access;
                         Vd, Vs2 : Register_Index; VM : Boolean);
   procedure VFREC7_V (VU : in out Vector_State; FP : FPU_Access;
                       Vd, Vs2 : Register_Index; VM : Boolean);
   procedure VFMERGE_VF (VU : in out Vector_State;
                         Vd, Vs2 : Register_Index; Fs1 : Word);
   procedure VFMV_V_F (VU : in out Vector_State;
                       Vd : Register_Index; Fs1 : Word);
   procedure VFRDIV_VF (VU : in out Vector_State; FP : FPU_Access;
                        Vd, Vs2 : Register_Index; Fs1 : Word; VM : Boolean);
   procedure VFRSUB_VF (VU : in out Vector_State; FP : FPU_Access;
                        Vd, Vs2 : Register_Index; Fs1 : Word; VM : Boolean);

   --  FP scalar move
   function VFMV_F_S (VU : Vector_State;
                      Vs2 : Register_Index) return Word;
   procedure VFMV_S_F (VU : in out Vector_State;
                       Vd : Register_Index; Fs1 : Word);

   --  FP single-width conversion (OPFVV, funct6=010010)
   procedure VFCVT_XU_F_V (VU : in out Vector_State; FP : FPU_Access;
                           Vd, Vs2 : Register_Index; VM : Boolean);
   procedure VFCVT_X_F_V (VU : in out Vector_State; FP : FPU_Access;
                          Vd, Vs2 : Register_Index; VM : Boolean);
   procedure VFCVT_F_XU_V (VU : in out Vector_State; FP : FPU_Access;
                           Vd, Vs2 : Register_Index; VM : Boolean);
   procedure VFCVT_F_X_V (VU : in out Vector_State; FP : FPU_Access;
                          Vd, Vs2 : Register_Index; VM : Boolean);
   procedure VFCVT_RTZ_XU_F_V (VU : in out Vector_State; FP : FPU_Access;
                               Vd, Vs2 : Register_Index; VM : Boolean);
   procedure VFCVT_RTZ_X_F_V (VU : in out Vector_State; FP : FPU_Access;
                              Vd, Vs2 : Register_Index; VM : Boolean);

   --  FP widening conversion
   procedure VFWCVT_XU_F_V (VU : in out Vector_State; FP : FPU_Access;
                            Vd, Vs2 : Register_Index; VM : Boolean);
   procedure VFWCVT_X_F_V (VU : in out Vector_State; FP : FPU_Access;
                           Vd, Vs2 : Register_Index; VM : Boolean);
   procedure VFWCVT_F_XU_V (VU : in out Vector_State; FP : FPU_Access;
                            Vd, Vs2 : Register_Index; VM : Boolean);
   procedure VFWCVT_F_X_V (VU : in out Vector_State; FP : FPU_Access;
                           Vd, Vs2 : Register_Index; VM : Boolean);
   procedure VFWCVT_F_F_V (VU : in out Vector_State; FP : FPU_Access;
                           Vd, Vs2 : Register_Index; VM : Boolean);
   procedure VFWCVT_RTZ_XU_F_V (VU : in out Vector_State; FP : FPU_Access;
                                Vd, Vs2 : Register_Index; VM : Boolean);
   procedure VFWCVT_RTZ_X_F_V (VU : in out Vector_State; FP : FPU_Access;
                               Vd, Vs2 : Register_Index; VM : Boolean);

   --  FP narrowing conversion
   procedure VFNCVT_XU_F_W (VU : in out Vector_State; FP : FPU_Access;
                            Vd, Vs2 : Register_Index; VM : Boolean);
   procedure VFNCVT_X_F_W (VU : in out Vector_State; FP : FPU_Access;
                           Vd, Vs2 : Register_Index; VM : Boolean);
   procedure VFNCVT_F_XU_W (VU : in out Vector_State; FP : FPU_Access;
                            Vd, Vs2 : Register_Index; VM : Boolean);
   procedure VFNCVT_F_X_W (VU : in out Vector_State; FP : FPU_Access;
                           Vd, Vs2 : Register_Index; VM : Boolean);
   procedure VFNCVT_F_F_W (VU : in out Vector_State; FP : FPU_Access;
                           Vd, Vs2 : Register_Index; VM : Boolean);
   procedure VFNCVT_ROD_F_F_W (VU : in out Vector_State; FP : FPU_Access;
                               Vd, Vs2 : Register_Index; VM : Boolean);
   procedure VFNCVT_RTZ_XU_F_W (VU : in out Vector_State; FP : FPU_Access;
                                Vd, Vs2 : Register_Index; VM : Boolean);
   procedure VFNCVT_RTZ_X_F_W (VU : in out Vector_State; FP : FPU_Access;
                               Vd, Vs2 : Register_Index; VM : Boolean);

   --  FP widening arithmetic
   procedure VFWADD_VV (VU : in out Vector_State; FP : FPU_Access;
                        Vd, Vs2, Vs1 : Register_Index; VM : Boolean);
   procedure VFWADD_VF (VU : in out Vector_State; FP : FPU_Access;
                        Vd, Vs2 : Register_Index; Fs1 : Word; VM : Boolean);
   procedure VFWSUB_VV (VU : in out Vector_State; FP : FPU_Access;
                        Vd, Vs2, Vs1 : Register_Index; VM : Boolean);
   procedure VFWSUB_VF (VU : in out Vector_State; FP : FPU_Access;
                        Vd, Vs2 : Register_Index; Fs1 : Word; VM : Boolean);
   procedure VFWADDW_VV (VU : in out Vector_State; FP : FPU_Access;
                         Vd, Vs2, Vs1 : Register_Index; VM : Boolean);
   procedure VFWADDW_VF (VU : in out Vector_State; FP : FPU_Access;
                         Vd, Vs2 : Register_Index; Fs1 : Word; VM : Boolean);
   procedure VFWSUBW_VV (VU : in out Vector_State; FP : FPU_Access;
                         Vd, Vs2, Vs1 : Register_Index; VM : Boolean);
   procedure VFWSUBW_VF (VU : in out Vector_State; FP : FPU_Access;
                         Vd, Vs2 : Register_Index; Fs1 : Word; VM : Boolean);
   procedure VFWMUL_VV (VU : in out Vector_State; FP : FPU_Access;
                        Vd, Vs2, Vs1 : Register_Index; VM : Boolean);
   procedure VFWMUL_VF (VU : in out Vector_State; FP : FPU_Access;
                        Vd, Vs2 : Register_Index; Fs1 : Word; VM : Boolean);

   --  FP widening MAC
   procedure VFWMACC_VV (VU : in out Vector_State; FP : FPU_Access;
                         Vd, Vs1, Vs2 : Register_Index; VM : Boolean);
   procedure VFWMACC_VF (VU : in out Vector_State; FP : FPU_Access;
                         Vd : Register_Index; Fs1 : Word;
                         Vs2 : Register_Index; VM : Boolean);
   procedure VFWNMACC_VV (VU : in out Vector_State; FP : FPU_Access;
                          Vd, Vs1, Vs2 : Register_Index; VM : Boolean);
   procedure VFWNMACC_VF (VU : in out Vector_State; FP : FPU_Access;
                          Vd : Register_Index; Fs1 : Word;
                          Vs2 : Register_Index; VM : Boolean);
   procedure VFWMSAC_VV (VU : in out Vector_State; FP : FPU_Access;
                         Vd, Vs1, Vs2 : Register_Index; VM : Boolean);
   procedure VFWMSAC_VF (VU : in out Vector_State; FP : FPU_Access;
                         Vd : Register_Index; Fs1 : Word;
                         Vs2 : Register_Index; VM : Boolean);
   procedure VFWNMSAC_VV (VU : in out Vector_State; FP : FPU_Access;
                          Vd, Vs1, Vs2 : Register_Index; VM : Boolean);
   procedure VFWNMSAC_VF (VU : in out Vector_State; FP : FPU_Access;
                          Vd : Register_Index; Fs1 : Word;
                          Vs2 : Register_Index; VM : Boolean);

   --  FP reduction
   procedure VFREDOSUM_VS (VU : in out Vector_State; FP : FPU_Access;
                           Vd, Vs2, Vs1 : Register_Index; VM : Boolean);
   procedure VFREDUSUM_VS (VU : in out Vector_State; FP : FPU_Access;
                           Vd, Vs2, Vs1 : Register_Index; VM : Boolean);
   procedure VFREDMIN_VS (VU : in out Vector_State; FP : FPU_Access;
                          Vd, Vs2, Vs1 : Register_Index; VM : Boolean);
   procedure VFREDMAX_VS (VU : in out Vector_State; FP : FPU_Access;
                          Vd, Vs2, Vs1 : Register_Index; VM : Boolean);

   --  FP widening reduction
   procedure VFWREDOSUM_VS (VU : in out Vector_State; FP : FPU_Access;
                            Vd, Vs2, Vs1 : Register_Index; VM : Boolean);
   procedure VFWREDUSUM_VS (VU : in out Vector_State; FP : FPU_Access;
                            Vd, Vs2, Vs1 : Register_Index; VM : Boolean);

end RISCV.Vector;
