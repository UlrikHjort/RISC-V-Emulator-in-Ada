-- ***************************************************************************
--                      RISCV_Emulator - Vector Extension Tests
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
--
-- V Extension (RVV 1.0) unit tests
-- ***************************************************************************

with Ada.Text_IO; use Ada.Text_IO;
with Ada.Unchecked_Conversion;
with Interfaces;  use Interfaces;
with RISCV;       use RISCV;
with RISCV.Memory;
with RISCV.FPU;
with RISCV.Vector; use RISCV.Vector;

procedure Test_Vector is

   function To_Word is new Ada.Unchecked_Conversion (Signed_Word, Word);

   --  Read mask bit from any register (not just v0)
   function Read_Mask_Bit (VU : Vector_State; Reg : Register_Index;
                           Index : Natural) return Boolean is
      Byte_Idx : constant Natural := Index / 8;
      Bit_Idx  : constant Natural := Index mod 8;
   begin
      return (VU.Registers (Reg).Data (Byte_Idx) and
              Byte (Shift_Left (Word (1), Bit_Idx))) /= 0;
   end Read_Mask_Bit;

   Total_Tests  : Natural := 0;
   Passed_Tests : Natural := 0;
   Failed_Tests : Natural := 0;

   procedure Check (Condition : Boolean; Test_Name : String) is
   begin
      Total_Tests := Total_Tests + 1;
      if Condition then
         Passed_Tests := Passed_Tests + 1;
         Put_Line ("  PASS: " & Test_Name);
      else
         Failed_Tests := Failed_Tests + 1;
         Put_Line ("  FAIL: " & Test_Name);
      end if;
   end Check;

   --  Helper to set up VU for SEW=32, LMUL=1, VL=4
   procedure Setup_VU_32 (VU : in out Vector_State) is
      VL : Word;
      --  vtype encoding: SEW=32 (vsew=2, bits 5:3), LMUL=1 (vlmul=0),
      --  ta=1 (bit 6), ma=1 (bit 7)
      VType_E32_M1 : constant Word := 16#D0#;  -- ma=1, ta=1, sew=32, lmul=1
   begin
      Initialize (VU);
      VL := Vsetvl (VU, 4, VType_E32_M1);
      pragma Unreferenced (VL);
   end Setup_VU_32;

   --  Test vsetvl configuration
   procedure Test_Vsetvl is
      VU : Vector_State;
      VL : Word;
   begin
      Put_Line ("Testing vsetvl configuration...");

      Initialize (VU);

      --  e32, m1: VLMAX = VLEN/SEW * LMUL = 128/32 * 1 = 4
      VL := Vsetvl (VU, 4, 16#D0#);
      Check (VL = 4, "vsetvl e32,m1 AVL=4 returns VL=4");
      Check (VU.VType.VSEW = SEW_32, "vsetvl sets SEW=32");
      Check (VU.VType.VLMUL = LMUL_1, "vsetvl sets LMUL=1");
      Check (not VU.VType.VILL, "vsetvl valid config not VILL");

      --  AVL > VLMAX: VL clamped to VLMAX
      VL := Vsetvl (VU, 100, 16#D0#);
      Check (VL = 4, "vsetvl AVL=100 clamps to VLMAX=4");

      --  e8, m1: VLMAX = 128/8 = 16
      VL := Vsetvl (VU, 16, 16#C0#);  -- e8, m1, ta, ma
      Check (VL = 16, "vsetvl e8,m1 AVL=16 returns VL=16");

      --  e16, m1: VLMAX = 128/16 = 8
      VL := Vsetvl (VU, 8, 16#C8#);  -- e16, m1, ta, ma
      Check (VL = 8, "vsetvl e16,m1 AVL=8 returns VL=8");

      --  e32, m2: VLMAX = 128/32 * 2 = 8
      VL := Vsetvl (VU, 8, 16#D1#);  -- e32, m2, ta, ma
      Check (VL = 8, "vsetvl e32,m2 AVL=8 returns VL=8");

      --  VLENB constant
      Check (Read_VLENB = 16, "VLENB = 16 (128/8)");

      --  Invalid vtype sets VILL
      VL := Vsetvl (VU, 4, 16#80000000#);
      Check (VU.VType.VILL, "Invalid vtype sets VILL");
      Check (VL = 0, "VILL returns VL=0");
   end Test_Vsetvl;

   --  Test element read/write
   procedure Test_Element_Access is
      VU : Vector_State;
   begin
      Put_Line ("Testing element read/write...");

      Setup_VU_32 (VU);

      --  Write and read back elements
      Write_Element (VU, 1, 0, SEW_32, 100);
      Write_Element (VU, 1, 1, SEW_32, 200);
      Write_Element (VU, 1, 2, SEW_32, 300);
      Write_Element (VU, 1, 3, SEW_32, 400);

      Check (Read_Element (VU, 1, 0, SEW_32) = 100,
             "Element [0] = 100");
      Check (Read_Element (VU, 1, 1, SEW_32) = 200,
             "Element [1] = 200");
      Check (Read_Element (VU, 1, 2, SEW_32) = 300,
             "Element [2] = 300");
      Check (Read_Element (VU, 1, 3, SEW_32) = 400,
             "Element [3] = 400");

      --  Test 8-bit elements
      declare
         VL : Word;
      begin
         VL := Vsetvl (VU, 16, 16#C0#);  -- e8, m1
         pragma Unreferenced (VL);
         Write_Element (VU, 2, 0, SEW_8, 16#AA#);
         Write_Element (VU, 2, 1, SEW_8, 16#BB#);
         Check (Read_Element (VU, 2, 0, SEW_8) = 16#AA#,
                "8-bit element [0] = 0xAA");
         Check (Read_Element (VU, 2, 1, SEW_8) = 16#BB#,
                "8-bit element [1] = 0xBB");
      end;
   end Test_Element_Access;

   --  Test VADD
   procedure Test_VADD is
      VU : Vector_State;
   begin
      Put_Line ("Testing VADD...");

      Setup_VU_32 (VU);

      --  v1 = {1, 2, 3, 4}
      Write_Element (VU, 1, 0, SEW_32, 1);
      Write_Element (VU, 1, 1, SEW_32, 2);
      Write_Element (VU, 1, 2, SEW_32, 3);
      Write_Element (VU, 1, 3, SEW_32, 4);

      --  v2 = {10, 20, 30, 40}
      Write_Element (VU, 2, 0, SEW_32, 10);
      Write_Element (VU, 2, 1, SEW_32, 20);
      Write_Element (VU, 2, 2, SEW_32, 30);
      Write_Element (VU, 2, 3, SEW_32, 40);

      --  v3 = v2 + v1 (vadd.vv)
      VADD_VV (VU, Vd => 3, Vs2 => 2, Vs1 => 1, VM => True);

      Check (Read_Element (VU, 3, 0, SEW_32) = 11, "VADD.VV [0] = 11");
      Check (Read_Element (VU, 3, 1, SEW_32) = 22, "VADD.VV [1] = 22");
      Check (Read_Element (VU, 3, 2, SEW_32) = 33, "VADD.VV [2] = 33");
      Check (Read_Element (VU, 3, 3, SEW_32) = 44, "VADD.VV [3] = 44");

      --  v4 = v1 + 5 (vadd.vi)
      VADD_VI (VU, Vd => 4, Vs2 => 1, Imm => 5, VM => True);

      Check (Read_Element (VU, 4, 0, SEW_32) = 6, "VADD.VI [0] = 6");
      Check (Read_Element (VU, 4, 1, SEW_32) = 7, "VADD.VI [1] = 7");
      Check (Read_Element (VU, 4, 2, SEW_32) = 8, "VADD.VI [2] = 8");
      Check (Read_Element (VU, 4, 3, SEW_32) = 9, "VADD.VI [3] = 9");

      --  v5 = v1 + 100 (vadd.vx)
      VADD_VX (VU, Vd => 5, Vs2 => 1, Rs1 => 100, VM => True);

      Check (Read_Element (VU, 5, 0, SEW_32) = 101, "VADD.VX [0] = 101");
      Check (Read_Element (VU, 5, 3, SEW_32) = 104, "VADD.VX [3] = 104");
   end Test_VADD;

   --  Test VSUB
   procedure Test_VSUB is
      VU : Vector_State;
   begin
      Put_Line ("Testing VSUB...");

      Setup_VU_32 (VU);

      --  v1 = {10, 20, 30, 40}, v2 = {1, 2, 3, 4}
      Write_Element (VU, 1, 0, SEW_32, 10);
      Write_Element (VU, 1, 1, SEW_32, 20);
      Write_Element (VU, 1, 2, SEW_32, 30);
      Write_Element (VU, 1, 3, SEW_32, 40);
      Write_Element (VU, 2, 0, SEW_32, 1);
      Write_Element (VU, 2, 1, SEW_32, 2);
      Write_Element (VU, 2, 2, SEW_32, 3);
      Write_Element (VU, 2, 3, SEW_32, 4);

      --  v3 = v1 - v2
      VSUB_VV (VU, Vd => 3, Vs2 => 1, Vs1 => 2, VM => True);

      Check (Read_Element (VU, 3, 0, SEW_32) = 9, "VSUB.VV [0] = 9");
      Check (Read_Element (VU, 3, 1, SEW_32) = 18, "VSUB.VV [1] = 18");
      Check (Read_Element (VU, 3, 2, SEW_32) = 27, "VSUB.VV [2] = 27");
      Check (Read_Element (VU, 3, 3, SEW_32) = 36, "VSUB.VV [3] = 36");

      --  v4 = 100 - v2 (vrsub.vx)
      VRSUB_VX (VU, Vd => 4, Vs2 => 2, Rs1 => 100, VM => True);

      Check (Read_Element (VU, 4, 0, SEW_32) = 99, "VRSUB.VX [0] = 99");
      Check (Read_Element (VU, 4, 3, SEW_32) = 96, "VRSUB.VX [3] = 96");
   end Test_VSUB;

   --  Test bitwise operations
   procedure Test_Bitwise is
      VU : Vector_State;
   begin
      Put_Line ("Testing bitwise operations...");

      Setup_VU_32 (VU);

      --  v1 = {0xFF, 0xF0, 0x0F, 0x55}
      Write_Element (VU, 1, 0, SEW_32, 16#FF#);
      Write_Element (VU, 1, 1, SEW_32, 16#F0#);
      Write_Element (VU, 1, 2, SEW_32, 16#0F#);
      Write_Element (VU, 1, 3, SEW_32, 16#55#);

      --  v2 = {0x0F, 0x0F, 0x0F, 0xAA}
      Write_Element (VU, 2, 0, SEW_32, 16#0F#);
      Write_Element (VU, 2, 1, SEW_32, 16#0F#);
      Write_Element (VU, 2, 2, SEW_32, 16#0F#);
      Write_Element (VU, 2, 3, SEW_32, 16#AA#);

      --  v3 = v1 AND v2
      VAND_VV (VU, Vd => 3, Vs2 => 1, Vs1 => 2, VM => True);
      Check (Read_Element (VU, 3, 0, SEW_32) = 16#0F#,
             "VAND.VV [0] = 0x0F");
      Check (Read_Element (VU, 3, 1, SEW_32) = 16#00#,
             "VAND.VV [1] = 0x00");
      Check (Read_Element (VU, 3, 3, SEW_32) = 16#00#,
             "VAND.VV [3] = 0x00");

      --  v4 = v1 OR v2
      VOR_VV (VU, Vd => 4, Vs2 => 1, Vs1 => 2, VM => True);
      Check (Read_Element (VU, 4, 0, SEW_32) = 16#FF#,
             "VOR.VV [0] = 0xFF");
      Check (Read_Element (VU, 4, 1, SEW_32) = 16#FF#,
             "VOR.VV [1] = 0xFF");
      Check (Read_Element (VU, 4, 2, SEW_32) = 16#0F#,
             "VOR.VV [2] = 0x0F");

      --  v5 = v1 XOR v2
      VXOR_VV (VU, Vd => 5, Vs2 => 1, Vs1 => 2, VM => True);
      Check (Read_Element (VU, 5, 0, SEW_32) = 16#F0#,
             "VXOR.VV [0] = 0xF0");
      Check (Read_Element (VU, 5, 3, SEW_32) = 16#FF#,
             "VXOR.VV [3] = 0xFF");

      --  VAND.VI with immediate
      VAND_VI (VU, Vd => 6, Vs2 => 1, Imm => 15, VM => True);
      Check (Read_Element (VU, 6, 0, SEW_32) = 16#0F#,
             "VAND.VI [0] = 0x0F");
      Check (Read_Element (VU, 6, 1, SEW_32) = 0,
             "VAND.VI [1] = 0");
   end Test_Bitwise;

   --  Test shift operations
   procedure Test_Shifts is
      VU : Vector_State;
   begin
      Put_Line ("Testing shift operations...");

      Setup_VU_32 (VU);

      --  v1 = {1, 2, 4, 8}
      Write_Element (VU, 1, 0, SEW_32, 1);
      Write_Element (VU, 1, 1, SEW_32, 2);
      Write_Element (VU, 1, 2, SEW_32, 4);
      Write_Element (VU, 1, 3, SEW_32, 8);

      --  v2 = v1 << 2 (vsll.vi)
      VSLL_VI (VU, Vd => 2, Vs2 => 1, Imm => 2, VM => True);
      Check (Read_Element (VU, 2, 0, SEW_32) = 4,
             "VSLL.VI [0] = 4");
      Check (Read_Element (VU, 2, 1, SEW_32) = 8,
             "VSLL.VI [1] = 8");
      Check (Read_Element (VU, 2, 2, SEW_32) = 16,
             "VSLL.VI [2] = 16");
      Check (Read_Element (VU, 2, 3, SEW_32) = 32,
             "VSLL.VI [3] = 32");

      --  v3 = v1 >> 1 (logical) (vsrl.vi)
      VSRL_VI (VU, Vd => 3, Vs2 => 1, Imm => 1, VM => True);
      Check (Read_Element (VU, 3, 0, SEW_32) = 0,
             "VSRL.VI [0] = 0");
      Check (Read_Element (VU, 3, 1, SEW_32) = 1,
             "VSRL.VI [1] = 1");
      Check (Read_Element (VU, 3, 2, SEW_32) = 2,
             "VSRL.VI [2] = 2");

      --  Test arithmetic right shift with negative
      Write_Element (VU, 4, 0, SEW_32, 16#FFFFFFF0#);  -- -16
      VSRA_VI (VU, Vd => 5, Vs2 => 4, Imm => 2, VM => True);
      Check (Read_Element (VU, 5, 0, SEW_32) = 16#FFFFFFFC#,
             "VSRA.VI [-16] >> 2 = -4");
   end Test_Shifts;

   --  Test multiply and divide
   procedure Test_Mul_Div is
      VU : Vector_State;
   begin
      Put_Line ("Testing multiply/divide...");

      Setup_VU_32 (VU);

      --  v1 = {2, 3, 4, 5}, v2 = {3, 4, 5, 6}
      Write_Element (VU, 1, 0, SEW_32, 2);
      Write_Element (VU, 1, 1, SEW_32, 3);
      Write_Element (VU, 1, 2, SEW_32, 4);
      Write_Element (VU, 1, 3, SEW_32, 5);
      Write_Element (VU, 2, 0, SEW_32, 3);
      Write_Element (VU, 2, 1, SEW_32, 4);
      Write_Element (VU, 2, 2, SEW_32, 5);
      Write_Element (VU, 2, 3, SEW_32, 6);

      --  v3 = v1 * v2 (vmul.vv)
      VMUL_VV (VU, Vd => 3, Vs2 => 1, Vs1 => 2, VM => True);
      Check (Read_Element (VU, 3, 0, SEW_32) = 6,
             "VMUL.VV [0] = 6");
      Check (Read_Element (VU, 3, 1, SEW_32) = 12,
             "VMUL.VV [1] = 12");
      Check (Read_Element (VU, 3, 2, SEW_32) = 20,
             "VMUL.VV [2] = 20");
      Check (Read_Element (VU, 3, 3, SEW_32) = 30,
             "VMUL.VV [3] = 30");

      --  v4 = v1 * 10 (vmul.vx)
      VMUL_VX (VU, Vd => 4, Vs2 => 1, Rs1 => 10, VM => True);
      Check (Read_Element (VU, 4, 0, SEW_32) = 20,
             "VMUL.VX [0] = 20");
      Check (Read_Element (VU, 4, 3, SEW_32) = 50,
             "VMUL.VX [3] = 50");

      --  v5 = {20, 30, 40, 50} / 10 (vdivu.vx)
      Write_Element (VU, 5, 0, SEW_32, 20);
      Write_Element (VU, 5, 1, SEW_32, 30);
      Write_Element (VU, 5, 2, SEW_32, 40);
      Write_Element (VU, 5, 3, SEW_32, 50);
      VDIVU_VX (VU, Vd => 6, Vs2 => 5, Rs1 => 10, VM => True);
      Check (Read_Element (VU, 6, 0, SEW_32) = 2,
             "VDIVU.VX [0] = 2");
      Check (Read_Element (VU, 6, 1, SEW_32) = 3,
             "VDIVU.VX [1] = 3");

      --  Remainder (vremu.vx)
      Write_Element (VU, 7, 0, SEW_32, 17);
      Write_Element (VU, 7, 1, SEW_32, 23);
      VREMU_VX (VU, Vd => 8, Vs2 => 7, Rs1 => 5, VM => True);
      Check (Read_Element (VU, 8, 0, SEW_32) = 2,
             "VREMU.VX 17%%5 = 2");
      Check (Read_Element (VU, 8, 1, SEW_32) = 3,
             "VREMU.VX 23%%5 = 3");
   end Test_Mul_Div;

   --  Test signed multiply-high, signed divide, signed remainder
   procedure Test_Signed_Mul_Div_Rem is
      VU : Vector_State;
   begin
      Put_Line ("Testing signed mulh/div/rem...");

      Setup_VU_32 (VU);

      --  ===== VMULH (signed multiply high - upper 32 bits of 64-bit product) =====
      --  7 * 3 = 21, upper 32 bits = 0
      Write_Element (VU, 1, 0, SEW_32, 7);
      Write_Element (VU, 1, 1, SEW_32, Word'Last);  -- -1 as signed
      Write_Element (VU, 1, 2, SEW_32, 16#7FFFFFFF#);  -- INT_MAX
      Write_Element (VU, 1, 3, SEW_32, 16#80000000#);  -- INT_MIN
      Write_Element (VU, 2, 0, SEW_32, 3);
      Write_Element (VU, 2, 1, SEW_32, Word'Last);  -- -1
      Write_Element (VU, 2, 2, SEW_32, 2);
      Write_Element (VU, 2, 3, SEW_32, 16#80000000#);  -- INT_MIN

      --  VMULH.VV v3 = mulh(v1, v2)
      VMULH_VV (VU, Vd => 3, Vs2 => 1, Vs1 => 2, VM => True);
      --  7 * 3 = 21, high32 = 0
      Check (Read_Element (VU, 3, 0, SEW_32) = 0,
             "VMULH.VV 7*3 high = 0");
      --  (-1) * (-1) = 1, high32 = 0
      Check (Read_Element (VU, 3, 1, SEW_32) = 0,
             "VMULH.VV (-1)*(-1) high = 0");
      --  0x7FFFFFFF * 2 = 0xFFFFFFFE, high32 = 0
      Check (Read_Element (VU, 3, 2, SEW_32) = 0,
             "VMULH.VV INT_MAX*2 high = 0");
      --  INT_MIN * INT_MIN = 2^62, high32 = 0x40000000
      Check (Read_Element (VU, 3, 3, SEW_32) = 16#40000000#,
             "VMULH.VV INT_MIN*INT_MIN high = 0x40000000");

      --  VMULH.VX v4 = mulh(v1, -2)
      --  Use 0xFFFFFFFE for -2
      VMULH_VX (VU, Vd => 4, Vs2 => 1, Rs1 => 16#FFFFFFFE#, VM => True);
      --  7 * (-2) = -14, high32 = -1 = 0xFFFFFFFF
      Check (Read_Element (VU, 4, 0, SEW_32) = 16#FFFFFFFF#,
             "VMULH.VX 7*(-2) high = -1");
      --  (-1) * (-2) = 2, high32 = 0
      Check (Read_Element (VU, 4, 1, SEW_32) = 0,
             "VMULH.VX (-1)*(-2) high = 0");

      --  ===== VMULHU (unsigned multiply high) =====
      Write_Element (VU, 5, 0, SEW_32, 16#FFFFFFFF#);
      Write_Element (VU, 5, 1, SEW_32, 16#80000000#);
      Write_Element (VU, 5, 2, SEW_32, 100);
      Write_Element (VU, 5, 3, SEW_32, 16#FFFFFFFF#);
      Write_Element (VU, 6, 0, SEW_32, 16#FFFFFFFF#);
      Write_Element (VU, 6, 1, SEW_32, 2);
      Write_Element (VU, 6, 2, SEW_32, 200);
      Write_Element (VU, 6, 3, SEW_32, 16#80000000#);

      VMULHU_VV (VU, Vd => 7, Vs2 => 5, Vs1 => 6, VM => True);
      --  0xFFFFFFFF * 0xFFFFFFFF = 0xFFFFFFFE00000001, high = 0xFFFFFFFE
      Check (Read_Element (VU, 7, 0, SEW_32) = 16#FFFFFFFE#,
             "VMULHU.VV 0xFFFFFFFF*0xFFFFFFFF high = 0xFFFFFFFE");
      --  0x80000000 * 2 = 0x100000000, high = 1
      Check (Read_Element (VU, 7, 1, SEW_32) = 1,
             "VMULHU.VV 0x80000000*2 high = 1");
      --  100 * 200 = 20000, high = 0
      Check (Read_Element (VU, 7, 2, SEW_32) = 0,
             "VMULHU.VV 100*200 high = 0");
      --  0xFFFFFFFF * 0x80000000 = 0x7FFFFFFF80000000, high = 0x7FFFFFFF
      Check (Read_Element (VU, 7, 3, SEW_32) = 16#7FFFFFFF#,
             "VMULHU.VV 0xFFFFFFFF*0x80000000 high = 0x7FFFFFFF");

      --  VMULHU.VX
      VMULHU_VX (VU, Vd => 8, Vs2 => 5, Rs1 => 16#10000#, VM => True);
      --  0xFFFFFFFF * 0x10000 = 0xFFFF0000FFFF, high(32) = 0xFFFF
      Check (Read_Element (VU, 8, 0, SEW_32) = 16#FFFF#,
             "VMULHU.VX 0xFFFFFFFF*0x10000 high = 0xFFFF");
      --  100 * 0x10000 = 6553600, high = 0
      Check (Read_Element (VU, 8, 2, SEW_32) = 0,
             "VMULHU.VX 100*0x10000 high = 0");

      --  ===== VDIV (signed divide) =====
      Write_Element (VU, 1, 0, SEW_32, 20);          -- 20
      Write_Element (VU, 1, 1, SEW_32, 16#FFFFFFEC#); -- -20
      Write_Element (VU, 1, 2, SEW_32, 17);          -- 17
      Write_Element (VU, 1, 3, SEW_32, 16#80000000#); -- INT_MIN
      Write_Element (VU, 2, 0, SEW_32, 3);
      Write_Element (VU, 2, 1, SEW_32, 16#FFFFFFFD#); -- -3
      Write_Element (VU, 2, 2, SEW_32, 0);           -- divide by zero
      Write_Element (VU, 2, 3, SEW_32, 16#FFFFFFFF#); -- -1

      VDIV_VV (VU, Vd => 3, Vs2 => 1, Vs1 => 2, VM => True);
      --  20 / 3 = 6
      Check (Read_Element (VU, 3, 0, SEW_32) = 6,
             "VDIV.VV 20/3 = 6");
      --  -20 / -3 = 6
      Check (Read_Element (VU, 3, 1, SEW_32) = 6,
             "VDIV.VV (-20)/(-3) = 6");
      --  17 / 0 = -1 (RISC-V spec: div by zero returns -1)
      Check (Read_Element (VU, 3, 2, SEW_32) = 16#FFFFFFFF#,
             "VDIV.VV 17/0 = -1 (div-by-zero)");
      --  INT_MIN / -1 = INT_MIN (RISC-V spec: overflow returns dividend)
      Check (Read_Element (VU, 3, 3, SEW_32) = 16#80000000#,
             "VDIV.VV INT_MIN/(-1) = INT_MIN (overflow)");

      --  VDIV.VX: divide by 4
      VDIV_VX (VU, Vd => 4, Vs2 => 1, Rs1 => 4, VM => True);
      Check (Read_Element (VU, 4, 0, SEW_32) = 5,
             "VDIV.VX 20/4 = 5");
      --  -20 / 4 = -5 (0xFFFFFFFB)
      Check (Read_Element (VU, 4, 1, SEW_32) = 16#FFFFFFFB#,
             "VDIV.VX (-20)/4 = -5");

      --  ===== VREM (signed remainder) =====
      VREM_VV (VU, Vd => 5, Vs2 => 1, Vs1 => 2, VM => True);
      --  20 % 3 = 2
      Check (Read_Element (VU, 5, 0, SEW_32) = 2,
             "VREM.VV 20%%3 = 2");
      --  -20 % -3 = -2 (0xFFFFFFFE)
      Check (Read_Element (VU, 5, 1, SEW_32) = 16#FFFFFFFE#,
             "VREM.VV (-20)%%(-3) = -2");
      --  17 % 0 = 17 (RISC-V spec: rem by zero returns dividend)
      Check (Read_Element (VU, 5, 2, SEW_32) = 17,
             "VREM.VV 17%%0 = 17 (rem-by-zero)");
      --  INT_MIN % -1 = 0 (RISC-V spec: overflow returns 0)
      Check (Read_Element (VU, 5, 3, SEW_32) = 0,
             "VREM.VV INT_MIN%%(-1) = 0 (overflow)");

      --  VREM.VX: remainder by 7
      VREM_VX (VU, Vd => 6, Vs2 => 1, Rs1 => 7, VM => True);
      --  20 % 7 = 6
      Check (Read_Element (VU, 6, 0, SEW_32) = 6,
             "VREM.VX 20%%7 = 6");
      --  -20 % 7 = -6 (0xFFFFFFFA)
      Check (Read_Element (VU, 6, 1, SEW_32) = 16#FFFFFFFA#,
             "VREM.VX (-20)%%7 = -6");

   end Test_Signed_Mul_Div_Rem;

   --  Test min/max operations
   procedure Test_MinMax is
      VU : Vector_State;
   begin
      Put_Line ("Testing min/max...");

      Setup_VU_32 (VU);

      --  v1 = {5, 1, 8, 3}, v2 = {3, 7, 2, 9}
      Write_Element (VU, 1, 0, SEW_32, 5);
      Write_Element (VU, 1, 1, SEW_32, 1);
      Write_Element (VU, 1, 2, SEW_32, 8);
      Write_Element (VU, 1, 3, SEW_32, 3);
      Write_Element (VU, 2, 0, SEW_32, 3);
      Write_Element (VU, 2, 1, SEW_32, 7);
      Write_Element (VU, 2, 2, SEW_32, 2);
      Write_Element (VU, 2, 3, SEW_32, 9);

      --  v3 = min(v1, v2) unsigned
      VMINU_VV (VU, Vd => 3, Vs2 => 1, Vs1 => 2, VM => True);
      Check (Read_Element (VU, 3, 0, SEW_32) = 3,
             "VMINU.VV [0] = 3");
      Check (Read_Element (VU, 3, 1, SEW_32) = 1,
             "VMINU.VV [1] = 1");
      Check (Read_Element (VU, 3, 2, SEW_32) = 2,
             "VMINU.VV [2] = 2");

      --  v4 = max(v1, v2) unsigned
      VMAXU_VV (VU, Vd => 4, Vs2 => 1, Vs1 => 2, VM => True);
      Check (Read_Element (VU, 4, 0, SEW_32) = 5,
             "VMAXU.VV [0] = 5");
      Check (Read_Element (VU, 4, 1, SEW_32) = 7,
             "VMAXU.VV [1] = 7");
      Check (Read_Element (VU, 4, 2, SEW_32) = 8,
             "VMAXU.VV [2] = 8");
   end Test_MinMax;

   --  Test comparison operations
   procedure Test_Comparisons is
      VU : Vector_State;
   begin
      Put_Line ("Testing comparisons...");

      Setup_VU_32 (VU);

      --  v1 = {1, 2, 3, 4}, v2 = {2, 2, 2, 2}
      Write_Element (VU, 1, 0, SEW_32, 1);
      Write_Element (VU, 1, 1, SEW_32, 2);
      Write_Element (VU, 1, 2, SEW_32, 3);
      Write_Element (VU, 1, 3, SEW_32, 4);
      Write_Element (VU, 2, 0, SEW_32, 2);
      Write_Element (VU, 2, 1, SEW_32, 2);
      Write_Element (VU, 2, 2, SEW_32, 2);
      Write_Element (VU, 2, 3, SEW_32, 2);

      --  vmseq.vv: v3[i] = (v1[i] == v2[i]) ? 1 : 0 (mask result)
      VMSEQ_VV (VU, Vd => 3, Vs2 => 1, Vs1 => 2, VM => True);
      --  Only element 1 matches (2 == 2)
      Check (not Get_Mask_Bit (VU, 0),
             "VMSEQ [0]: 1 /= 2");
      --  Check mask bit via register 3
      Check (Get_Mask_Bit (VU, 1) = True or
             (VU.Registers (3).Data (0) and 2) /= 0,
             "VMSEQ [1]: 2 == 2");

      --  vmsltu.vv: v4[i] = (v1[i] < v2[i]) ? 1 : 0
      VMSLTU_VV (VU, Vd => 4, Vs2 => 1, Vs1 => 2, VM => True);
      --  Element 0: 1 < 2 = true
      Check ((VU.Registers (4).Data (0) and 1) /= 0,
             "VMSLTU [0]: 1 < 2");
      --  Element 1: 2 < 2 = false
      Check ((VU.Registers (4).Data (0) and 2) = 0,
             "VMSLTU [1]: 2 < 2 is false");
      --  Element 2: 3 < 2 = false
      Check ((VU.Registers (4).Data (0) and 4) = 0,
             "VMSLTU [2]: 3 < 2 is false");
   end Test_Comparisons;

   --  Test merge and move
   procedure Test_Merge_Move is
      VU : Vector_State;
      Scalar : Word;
   begin
      Put_Line ("Testing merge/move...");

      Setup_VU_32 (VU);

      --  vmv.v.x: broadcast scalar to vector
      VMV_V_X (VU, Vd => 1, Rs1 => 42);
      Check (Read_Element (VU, 1, 0, SEW_32) = 42,
             "VMV.V.X [0] = 42");
      Check (Read_Element (VU, 1, 1, SEW_32) = 42,
             "VMV.V.X [1] = 42");
      Check (Read_Element (VU, 1, 2, SEW_32) = 42,
             "VMV.V.X [2] = 42");
      Check (Read_Element (VU, 1, 3, SEW_32) = 42,
             "VMV.V.X [3] = 42");

      --  vmv.v.i: broadcast immediate to vector
      VMV_V_I (VU, Vd => 2, Imm => 7);
      Check (Read_Element (VU, 2, 0, SEW_32) = 7,
             "VMV.V.I [0] = 7");
      Check (Read_Element (VU, 2, 3, SEW_32) = 7,
             "VMV.V.I [3] = 7");

      --  vmv.v.i with negative immediate
      VMV_V_I (VU, Vd => 3, Imm => -1);
      Check (Read_Element (VU, 3, 0, SEW_32) = 16#FFFFFFFF#,
             "VMV.V.I -1 = 0xFFFFFFFF");

      --  vmv.x.s: extract first element to scalar
      Write_Element (VU, 4, 0, SEW_32, 99);
      Write_Element (VU, 4, 1, SEW_32, 88);
      Scalar := VMV_X_S (VU, Vs2 => 4);
      Check (Scalar = 99, "VMV.X.S returns first element");

      --  vmv.s.x: set first element from scalar
      VMV_S_X (VU, Vd => 5, Rs1 => 123);
      Check (Read_Element (VU, 5, 0, SEW_32) = 123,
             "VMV.S.X sets first element");

      --  vmv.v.v: copy vector
      Write_Element (VU, 6, 0, SEW_32, 10);
      Write_Element (VU, 6, 1, SEW_32, 20);
      Write_Element (VU, 6, 2, SEW_32, 30);
      Write_Element (VU, 6, 3, SEW_32, 40);
      VMV_V_V (VU, Vd => 7, Vs1 => 6);
      Check (Read_Element (VU, 7, 0, SEW_32) = 10,
             "VMV.V.V [0] = 10");
      Check (Read_Element (VU, 7, 3, SEW_32) = 40,
             "VMV.V.V [3] = 40");
   end Test_Merge_Move;

   --  Test reduction operations
   procedure Test_Reductions is
      VU : Vector_State;
      Result : Word;
   begin
      Put_Line ("Testing reductions...");

      Setup_VU_32 (VU);

      --  v1 = {1, 2, 3, 4}, v2 (initial) element 0 = 0
      Write_Element (VU, 1, 0, SEW_32, 1);
      Write_Element (VU, 1, 1, SEW_32, 2);
      Write_Element (VU, 1, 2, SEW_32, 3);
      Write_Element (VU, 1, 3, SEW_32, 4);
      Write_Element (VU, 2, 0, SEW_32, 0);

      --  vredsum: sum = 0 + 1 + 2 + 3 + 4 = 10
      Result := VREDSUM_VS (VU, Vs2 => 1, Vs1 => 2, VM => True);
      Check (Result = 10, "VREDSUM {1,2,3,4} + 0 = 10");

      --  vredsum with initial value 100
      Write_Element (VU, 2, 0, SEW_32, 100);
      Result := VREDSUM_VS (VU, Vs2 => 1, Vs1 => 2, VM => True);
      Check (Result = 110, "VREDSUM {1,2,3,4} + 100 = 110");

      --  vredmaxu: max of {1, 2, 3, 4} with initial 0
      Write_Element (VU, 2, 0, SEW_32, 0);
      Result := VREDMAXU_VS (VU, Vs2 => 1, Vs1 => 2, VM => True);
      Check (Result = 4, "VREDMAXU {1,2,3,4} = 4");

      --  vredminu: min of {1, 2, 3, 4} with initial 100
      Write_Element (VU, 2, 0, SEW_32, 100);
      Result := VREDMINU_VS (VU, Vs2 => 1, Vs1 => 2, VM => True);
      Check (Result = 1, "VREDMINU {1,2,3,4} = 1");

      --  vredand: AND of {0xFF, 0x0F, 0xFF, 0x0F} with initial 0xFFFFFFFF
      Write_Element (VU, 3, 0, SEW_32, 16#FF#);
      Write_Element (VU, 3, 1, SEW_32, 16#0F#);
      Write_Element (VU, 3, 2, SEW_32, 16#FF#);
      Write_Element (VU, 3, 3, SEW_32, 16#0F#);
      Write_Element (VU, 2, 0, SEW_32, 16#FFFFFFFF#);
      Result := VREDAND_VS (VU, Vs2 => 3, Vs1 => 2, VM => True);
      Check (Result = 16#0F#, "VREDAND = 0x0F");

      --  vredor: OR of {1, 2, 4, 8} with initial 0
      Write_Element (VU, 4, 0, SEW_32, 1);
      Write_Element (VU, 4, 1, SEW_32, 2);
      Write_Element (VU, 4, 2, SEW_32, 4);
      Write_Element (VU, 4, 3, SEW_32, 8);
      Write_Element (VU, 2, 0, SEW_32, 0);
      Result := VREDOR_VS (VU, Vs2 => 4, Vs1 => 2, VM => True);
      Check (Result = 15, "VREDOR {1,2,4,8} = 15");

      --  vredxor: XOR of {1, 1, 1, 1} with initial 0
      Write_Element (VU, 5, 0, SEW_32, 1);
      Write_Element (VU, 5, 1, SEW_32, 1);
      Write_Element (VU, 5, 2, SEW_32, 1);
      Write_Element (VU, 5, 3, SEW_32, 1);
      Write_Element (VU, 2, 0, SEW_32, 0);
      Result := VREDXOR_VS (VU, Vs2 => 5, Vs1 => 2, VM => True);
      Check (Result = 0, "VREDXOR {1,1,1,1} = 0");
   end Test_Reductions;

   --  Test VID and VIOTA
   procedure Test_VID_VIOTA is
      VU : Vector_State;
   begin
      Put_Line ("Testing VID/VIOTA...");

      Setup_VU_32 (VU);

      --  vid.v: v1[i] = i
      VID_V (VU, Vd => 1, VM => True);
      Check (Read_Element (VU, 1, 0, SEW_32) = 0, "VID [0] = 0");
      Check (Read_Element (VU, 1, 1, SEW_32) = 1, "VID [1] = 1");
      Check (Read_Element (VU, 1, 2, SEW_32) = 2, "VID [2] = 2");
      Check (Read_Element (VU, 1, 3, SEW_32) = 3, "VID [3] = 3");

      --  viota.m: v2 = prefix sum of mask bit popcount
      --  Set mask in v3: bits 0,1,1,0
      VU.Registers (3).Data := (others => 0);
      VU.Registers (3).Data (0) := 16#06#;  -- bits: ...0110
      VIOTA_M (VU, Vd => 2, Vs2 => 3, VM => True);
      Check (Read_Element (VU, 2, 0, SEW_32) = 0,
             "VIOTA [0] = 0 (bit 0 = 0)");
      Check (Read_Element (VU, 2, 1, SEW_32) = 0,
             "VIOTA [1] = 0 (count before bit 1)");
      Check (Read_Element (VU, 2, 2, SEW_32) = 1,
             "VIOTA [2] = 1 (count before bit 2)");
      Check (Read_Element (VU, 2, 3, SEW_32) = 2,
             "VIOTA [3] = 2 (count before bit 3)");
   end Test_VID_VIOTA;

   --  Test mask operations
   procedure Test_Mask_Ops is
      VU : Vector_State;
      Result : Word;
      First  : Signed_Word;
   begin
      Put_Line ("Testing mask operations...");

      Setup_VU_32 (VU);

      --  Set up mask in v1: bits = 1010 (0x0A)
      VU.Registers (1).Data := (others => 0);
      VU.Registers (1).Data (0) := 16#0A#;

      --  Set up mask in v2: bits = 1100 (0x0C)
      VU.Registers (2).Data := (others => 0);
      VU.Registers (2).Data (0) := 16#0C#;

      --  vmand.mm: v3 = v1 AND v2 = 1000 (0x08)
      VMAND_MM (VU, Vd => 3, Vs2 => 1, Vs1 => 2);
      Check ((VU.Registers (3).Data (0) and 16#0F#) = 16#08#,
             "VMAND.MM 1010 & 1100 = 1000");

      --  vmor.mm: v4 = v1 OR v2 = 1110 (0x0E)
      VMOR_MM (VU, Vd => 4, Vs2 => 1, Vs1 => 2);
      Check ((VU.Registers (4).Data (0) and 16#0F#) = 16#0E#,
             "VMOR.MM 1010 | 1100 = 1110");

      --  vmxor.mm: v5 = v1 XOR v2 = 0110 (0x06)
      VMXOR_MM (VU, Vd => 5, Vs2 => 1, Vs1 => 2);
      Check ((VU.Registers (5).Data (0) and 16#0F#) = 16#06#,
             "VMXOR.MM 1010 ^ 1100 = 0110");

      --  vcpop.m: count set bits in v1 (1010 = 2 bits)
      Result := VCPOP_M (VU, Vs2 => 1, VM => True);
      Check (Result = 2, "VCPOP.M of 1010 = 2");

      --  vfirst.m: first set bit in v1 (bit 1)
      First := VFIRST_M (VU, Vs2 => 1, VM => True);
      Check (First = 1, "VFIRST.M of 1010 = 1");

      --  vfirst.m with no bits set
      VU.Registers (6).Data := (others => 0);
      First := VFIRST_M (VU, Vs2 => 6, VM => True);
      Check (First = -1, "VFIRST.M of 0000 = -1");
   end Test_Mask_Ops;

   --  Test load/store with memory
   procedure Test_Load_Store is
      VU  : Vector_State;
      Mem : RISCV.Memory.Memory_Unit;
   begin
      Put_Line ("Testing load/store...");

      Setup_VU_32 (VU);

      RISCV.Memory.Initialize (Mem);
      RISCV.Memory.Add_Region (Mem, "RAM", 0, 16#2000#,
                                RISCV.Memory.RAM,
                                RISCV.Memory.Permission_RWX);

      --  Store values in memory
      RISCV.Memory.Write_Word (Mem, 16#100#, 10);
      RISCV.Memory.Write_Word (Mem, 16#104#, 20);
      RISCV.Memory.Write_Word (Mem, 16#108#, 30);
      RISCV.Memory.Write_Word (Mem, 16#10C#, 40);

      --  Vector load
      Vector_Load_Unit_Stride (VU, Mem, Vd => 1, Rs1 => 16#100#,
                               VM => True, EEW => SEW_32);
      Check (Read_Element (VU, 1, 0, SEW_32) = 10,
             "VLE32 [0] = 10");
      Check (Read_Element (VU, 1, 1, SEW_32) = 20,
             "VLE32 [1] = 20");
      Check (Read_Element (VU, 1, 2, SEW_32) = 30,
             "VLE32 [2] = 30");
      Check (Read_Element (VU, 1, 3, SEW_32) = 40,
             "VLE32 [3] = 40");

      --  Modify and store back
      VADD_VI (VU, Vd => 2, Vs2 => 1, Imm => 5, VM => True);
      Vector_Store_Unit_Stride (VU, Mem, Vs3 => 2, Rs1 => 16#200#,
                                VM => True, EEW => SEW_32);

      Check (RISCV.Memory.Read_Word (Mem, 16#200#) = 15,
             "VSE32 [0] = 15");
      Check (RISCV.Memory.Read_Word (Mem, 16#204#) = 25,
             "VSE32 [1] = 25");
      Check (RISCV.Memory.Read_Word (Mem, 16#208#) = 35,
             "VSE32 [2] = 35");
      Check (RISCV.Memory.Read_Word (Mem, 16#20C#) = 45,
             "VSE32 [3] = 45");

      --  Strided load: load every 8 bytes
      RISCV.Memory.Write_Word (Mem, 16#300#, 100);
      RISCV.Memory.Write_Word (Mem, 16#308#, 200);
      RISCV.Memory.Write_Word (Mem, 16#310#, 300);
      RISCV.Memory.Write_Word (Mem, 16#318#, 400);

      Vector_Load_Strided (VU, Mem, Vd => 3, Rs1 => 16#300#,
                           Rs2 => 8, VM => True, EEW => SEW_32);
      Check (Read_Element (VU, 3, 0, SEW_32) = 100,
             "Strided load [0] = 100");
      Check (Read_Element (VU, 3, 1, SEW_32) = 200,
             "Strided load [1] = 200");
      Check (Read_Element (VU, 3, 2, SEW_32) = 300,
             "Strided load [2] = 300");
      Check (Read_Element (VU, 3, 3, SEW_32) = 400,
             "Strided load [3] = 400");
   end Test_Load_Store;

   --  Test SEW=8 arithmetic
   procedure Test_SEW8 is
      VU : Vector_State;
      VL : Word;
   begin
      Put_Line ("Testing SEW=8 operations...");

      Initialize (VU);
      VL := Vsetvl (VU, 4, 16#C0#);  -- e8, m1, ta, ma
      pragma Unreferenced (VL);

      --  v1 = {10, 20, 30, 40}
      Write_Element (VU, 1, 0, SEW_8, 10);
      Write_Element (VU, 1, 1, SEW_8, 20);
      Write_Element (VU, 1, 2, SEW_8, 30);
      Write_Element (VU, 1, 3, SEW_8, 40);

      --  v2 = {5, 5, 5, 5}
      Write_Element (VU, 2, 0, SEW_8, 5);
      Write_Element (VU, 2, 1, SEW_8, 5);
      Write_Element (VU, 2, 2, SEW_8, 5);
      Write_Element (VU, 2, 3, SEW_8, 5);

      --  v3 = v1 + v2
      VADD_VV (VU, Vd => 3, Vs2 => 1, Vs1 => 2, VM => True);
      Check (Read_Element (VU, 3, 0, SEW_8) = 15,
             "SEW8 VADD [0] = 15");
      Check (Read_Element (VU, 3, 1, SEW_8) = 25,
             "SEW8 VADD [1] = 25");
      Check (Read_Element (VU, 3, 2, SEW_8) = 35,
             "SEW8 VADD [2] = 35");
      Check (Read_Element (VU, 3, 3, SEW_8) = 45,
             "SEW8 VADD [3] = 45");

      --  Test 8-bit overflow wrapping
      Write_Element (VU, 4, 0, SEW_8, 250);
      VADD_VI (VU, Vd => 5, Vs2 => 4, Imm => 10, VM => True);
      --  250 + 10 = 260, truncated to 8 bits = 4
      Check (Read_Element (VU, 5, 0, SEW_8) = 4,
             "SEW8 overflow 250+10 wraps to 4");
   end Test_SEW8;

   --  Test masking (v0 as mask)
   procedure Test_Masking is
      VU : Vector_State;
   begin
      Put_Line ("Testing masked operations...");

      Setup_VU_32 (VU);

      --  v1 = {10, 20, 30, 40}
      Write_Element (VU, 1, 0, SEW_32, 10);
      Write_Element (VU, 1, 1, SEW_32, 20);
      Write_Element (VU, 1, 2, SEW_32, 30);
      Write_Element (VU, 1, 3, SEW_32, 40);

      --  Set mask in v0: bits = 0101 (elements 0 and 2 active)
      VU.Registers (0).Data := (others => 0);
      VU.Registers (0).Data (0) := 16#05#;

      --  Initialize destination to known values
      Write_Element (VU, 3, 0, SEW_32, 16#DEAD#);
      Write_Element (VU, 3, 1, SEW_32, 16#DEAD#);
      Write_Element (VU, 3, 2, SEW_32, 16#DEAD#);
      Write_Element (VU, 3, 3, SEW_32, 16#DEAD#);

      --  v3 = v1 + 5 with mask (VM=False means use v0 as mask)
      VADD_VI (VU, Vd => 3, Vs2 => 1, Imm => 5, VM => False);

      --  Active elements (0, 2) should be updated
      Check (Read_Element (VU, 3, 0, SEW_32) = 15,
             "Masked VADD [0] = 15 (active)");
      --  Inactive element 1 should be unchanged (tail agnostic allows
      --  either keeping old value or setting all-1s)
      Check (Read_Element (VU, 3, 2, SEW_32) = 35,
             "Masked VADD [2] = 35 (active)");
   end Test_Masking;

   --  Test set-before/set-including/set-only-first mask ops
   procedure Test_Mask_Set_Ops is
      VU : Vector_State;
   begin
      Put_Line ("Testing mask set operations...");

      Setup_VU_32 (VU);

      --  Source mask in v1: bits = 0100 (bit 2 is first set)
      VU.Registers (1).Data := (others => 0);
      VU.Registers (1).Data (0) := 16#04#;

      --  vmsbf.m: set before first = 0011 (bits before bit 2)
      VMSBF_M (VU, Vd => 2, Vs2 => 1, VM => True);
      Check ((VU.Registers (2).Data (0) and 16#0F#) = 16#03#,
             "VMSBF.M 0100 -> 0011");

      --  vmsif.m: set including first = 0111
      VMSIF_M (VU, Vd => 3, Vs2 => 1, VM => True);
      Check ((VU.Registers (3).Data (0) and 16#0F#) = 16#07#,
             "VMSIF.M 0100 -> 0111");

      --  vmsof.m: set only first = 0100
      VMSOF_M (VU, Vd => 4, Vs2 => 1, VM => True);
      Check ((VU.Registers (4).Data (0) and 16#0F#) = 16#04#,
             "VMSOF.M 0100 -> 0100");
   end Test_Mask_Set_Ops;

   --  Test additional arithmetic variants (VSUB.VX, VRSUB.VI)
   procedure Test_Arith_Variants is
      VU : Vector_State;
   begin
      Put_Line ("Testing arithmetic variants...");
      Setup_VU_32 (VU);

      --  v1 = {10, 20, 30, 40}
      Write_Element (VU, 1, 0, SEW_32, 10);
      Write_Element (VU, 1, 1, SEW_32, 20);
      Write_Element (VU, 1, 2, SEW_32, 30);
      Write_Element (VU, 1, 3, SEW_32, 40);

      --  VSUB.VX: v2 = v1 - 3
      VSUB_VX (VU, Vd => 2, Vs2 => 1, Rs1 => 3, VM => True);
      Check (Read_Element (VU, 2, 0, SEW_32) = 7,
             "VSUB.VX [0] = 7");
      Check (Read_Element (VU, 2, 3, SEW_32) = 37,
             "VSUB.VX [3] = 37");

      --  VRSUB.VI: v3 = 15 - v1
      VRSUB_VI (VU, Vd => 3, Vs2 => 1, Imm => 15, VM => True);
      Check (Read_Element (VU, 3, 0, SEW_32) = 5,
             "VRSUB.VI 15-10 = 5");
      --  15 - 20 = -5 = 0xFFFFFFFB
      Check (Read_Element (VU, 3, 1, SEW_32) = 16#FFFFFFFB#,
             "VRSUB.VI 15-20 = -5");
   end Test_Arith_Variants;

   --  Test additional bitwise VX/VI variants
   procedure Test_Bitwise_Variants is
      VU : Vector_State;
   begin
      Put_Line ("Testing bitwise VX/VI variants...");
      Setup_VU_32 (VU);

      --  v1 = {0xFF, 0xAA, 0x55, 0x0F}
      Write_Element (VU, 1, 0, SEW_32, 16#FF#);
      Write_Element (VU, 1, 1, SEW_32, 16#AA#);
      Write_Element (VU, 1, 2, SEW_32, 16#55#);
      Write_Element (VU, 1, 3, SEW_32, 16#0F#);

      --  VAND.VX: v1 & 0x0F
      VAND_VX (VU, Vd => 2, Vs2 => 1, Rs1 => 16#0F#, VM => True);
      Check (Read_Element (VU, 2, 0, SEW_32) = 16#0F#,
             "VAND.VX 0xFF & 0x0F = 0x0F");
      Check (Read_Element (VU, 2, 1, SEW_32) = 16#0A#,
             "VAND.VX 0xAA & 0x0F = 0x0A");

      --  VOR.VX: v1 | 0xF0
      VOR_VX (VU, Vd => 3, Vs2 => 1, Rs1 => 16#F0#, VM => True);
      Check (Read_Element (VU, 3, 0, SEW_32) = 16#FF#,
             "VOR.VX 0xFF | 0xF0 = 0xFF");
      Check (Read_Element (VU, 3, 2, SEW_32) = 16#F5#,
             "VOR.VX 0x55 | 0xF0 = 0xF5");

      --  VOR.VI: v1 | 3
      VOR_VI (VU, Vd => 4, Vs2 => 1, Imm => 3, VM => True);
      Check (Read_Element (VU, 4, 3, SEW_32) = 16#0F#,
             "VOR.VI 0x0F | 3 = 0x0F");

      --  VXOR.VX: v1 ^ 0xFF
      VXOR_VX (VU, Vd => 5, Vs2 => 1, Rs1 => 16#FF#, VM => True);
      Check (Read_Element (VU, 5, 0, SEW_32) = 0,
             "VXOR.VX 0xFF ^ 0xFF = 0");
      Check (Read_Element (VU, 5, 1, SEW_32) = 16#55#,
             "VXOR.VX 0xAA ^ 0xFF = 0x55");

      --  VXOR.VI: v1 ^ -1 (all bits, sign-extended)
      VXOR_VI (VU, Vd => 6, Vs2 => 1, Imm => -1, VM => True);
      Check (Read_Element (VU, 6, 2, SEW_32) = 16#FFFFFFAA#,
             "VXOR.VI 0x55 ^ -1 = ~0x55");
   end Test_Bitwise_Variants;

   --  Test shift VV/VX variants
   procedure Test_Shift_Variants is
      VU : Vector_State;
   begin
      Put_Line ("Testing shift VV/VX variants...");
      Setup_VU_32 (VU);

      --  v1 = {1, 4, 16, 0x80000000}
      Write_Element (VU, 1, 0, SEW_32, 1);
      Write_Element (VU, 1, 1, SEW_32, 4);
      Write_Element (VU, 1, 2, SEW_32, 16);
      Write_Element (VU, 1, 3, SEW_32, 16#80000000#);

      --  v2 = {1, 2, 3, 4} (shift amounts)
      Write_Element (VU, 2, 0, SEW_32, 1);
      Write_Element (VU, 2, 1, SEW_32, 2);
      Write_Element (VU, 2, 2, SEW_32, 3);
      Write_Element (VU, 2, 3, SEW_32, 4);

      --  VSLL.VV: v1 << v2
      VSLL_VV (VU, Vd => 3, Vs2 => 1, Vs1 => 2, VM => True);
      Check (Read_Element (VU, 3, 0, SEW_32) = 2,
             "VSLL.VV 1<<1 = 2");
      Check (Read_Element (VU, 3, 1, SEW_32) = 16,
             "VSLL.VV 4<<2 = 16");

      --  VSLL.VX: v1 << 3
      VSLL_VX (VU, Vd => 4, Vs2 => 1, Rs1 => 3, VM => True);
      Check (Read_Element (VU, 4, 0, SEW_32) = 8,
             "VSLL.VX 1<<3 = 8");
      Check (Read_Element (VU, 4, 1, SEW_32) = 32,
             "VSLL.VX 4<<3 = 32");

      --  VSRL.VV: v1 >> v2 (logical)
      VSRL_VV (VU, Vd => 5, Vs2 => 1, Vs1 => 2, VM => True);
      Check (Read_Element (VU, 5, 2, SEW_32) = 2,
             "VSRL.VV 16>>3 = 2");
      Check (Read_Element (VU, 5, 3, SEW_32) = 16#08000000#,
             "VSRL.VV 0x80000000>>4 = 0x08000000");

      --  VSRL.VX: v1 >> 2
      VSRL_VX (VU, Vd => 6, Vs2 => 1, Rs1 => 2, VM => True);
      Check (Read_Element (VU, 6, 1, SEW_32) = 1,
             "VSRL.VX 4>>2 = 1");

      --  VSRA.VV: v1 >>> v2 (arithmetic)
      VSRA_VV (VU, Vd => 7, Vs2 => 1, Vs1 => 2, VM => True);
      --  0x80000000 >>> 4 = 0xF8000000 (sign-extended)
      Check (Read_Element (VU, 7, 3, SEW_32) = 16#F8000000#,
             "VSRA.VV 0x80000000>>>4 = 0xF8000000");

      --  VSRA.VX: v1 >>> 1
      VSRA_VX (VU, Vd => 8, Vs2 => 1, Rs1 => 1, VM => True);
      Check (Read_Element (VU, 8, 3, SEW_32) = 16#C0000000#,
             "VSRA.VX 0x80000000>>>1 = 0xC0000000");
   end Test_Shift_Variants;

   --  Test signed min/max and unsigned VX variants
   procedure Test_MinMax_Variants is
      VU : Vector_State;
   begin
      Put_Line ("Testing min/max variants...");
      Setup_VU_32 (VU);

      --  v1 = {5, 0xFFFFFFFF (-1), 0x80000000 (INT_MIN), 100}
      Write_Element (VU, 1, 0, SEW_32, 5);
      Write_Element (VU, 1, 1, SEW_32, 16#FFFFFFFF#);
      Write_Element (VU, 1, 2, SEW_32, 16#80000000#);
      Write_Element (VU, 1, 3, SEW_32, 100);

      --  v2 = {3, 0, 0x7FFFFFFF (INT_MAX), 50}
      Write_Element (VU, 2, 0, SEW_32, 3);
      Write_Element (VU, 2, 1, SEW_32, 0);
      Write_Element (VU, 2, 2, SEW_32, 16#7FFFFFFF#);
      Write_Element (VU, 2, 3, SEW_32, 50);

      --  VMIN.VV (signed): min(-1, 0) = -1, min(INT_MIN, INT_MAX) = INT_MIN
      VMIN_VV (VU, Vd => 3, Vs2 => 1, Vs1 => 2, VM => True);
      Check (Read_Element (VU, 3, 0, SEW_32) = 3,
             "VMIN.VV min(5,3) = 3");
      Check (Read_Element (VU, 3, 1, SEW_32) = 16#FFFFFFFF#,
             "VMIN.VV min(-1,0) = -1");
      Check (Read_Element (VU, 3, 2, SEW_32) = 16#80000000#,
             "VMIN.VV min(INT_MIN,INT_MAX) = INT_MIN");

      --  VMAX.VV (signed): max(-1, 0) = 0, max(INT_MIN, INT_MAX) = INT_MAX
      VMAX_VV (VU, Vd => 4, Vs2 => 1, Vs1 => 2, VM => True);
      Check (Read_Element (VU, 4, 1, SEW_32) = 0,
             "VMAX.VV max(-1,0) = 0");
      Check (Read_Element (VU, 4, 2, SEW_32) = 16#7FFFFFFF#,
             "VMAX.VV max(INT_MIN,INT_MAX) = INT_MAX");
      Check (Read_Element (VU, 4, 3, SEW_32) = 100,
             "VMAX.VV max(100,50) = 100");

      --  VMIN.VX (signed): min(v1, 10)
      VMIN_VX (VU, Vd => 5, Vs2 => 1, Rs1 => 10, VM => True);
      Check (Read_Element (VU, 5, 0, SEW_32) = 5,
             "VMIN.VX min(5,10) = 5");
      Check (Read_Element (VU, 5, 1, SEW_32) = 16#FFFFFFFF#,
             "VMIN.VX min(-1,10) = -1");

      --  VMAX.VX (signed): max(v1, 10)
      VMAX_VX (VU, Vd => 6, Vs2 => 1, Rs1 => 10, VM => True);
      Check (Read_Element (VU, 6, 0, SEW_32) = 10,
             "VMAX.VX max(5,10) = 10");
      Check (Read_Element (VU, 6, 3, SEW_32) = 100,
             "VMAX.VX max(100,10) = 100");

      --  VMINU.VX (unsigned)
      VMINU_VX (VU, Vd => 7, Vs2 => 1, Rs1 => 10, VM => True);
      Check (Read_Element (VU, 7, 0, SEW_32) = 5,
             "VMINU.VX min(5,10) = 5");
      Check (Read_Element (VU, 7, 3, SEW_32) = 10,
             "VMINU.VX min(100,10) = 10");

      --  VMAXU.VX (unsigned)
      VMAXU_VX (VU, Vd => 8, Vs2 => 1, Rs1 => 10, VM => True);
      Check (Read_Element (VU, 8, 0, SEW_32) = 10,
             "VMAXU.VX max(5,10) = 10");
      --  0xFFFFFFFF is large unsigned
      Check (Read_Element (VU, 8, 1, SEW_32) = 16#FFFFFFFF#,
             "VMAXU.VX max(0xFFFFFFFF,10) = 0xFFFFFFFF");
   end Test_MinMax_Variants;

   --  Test all comparison variants
   procedure Test_Comparison_Variants is
      VU : Vector_State;

      --  Helper: read mask bit from a specific register
      function Mask_Bit (Reg : Register_Index; Bit : Natural) return Boolean is
      begin
         return (VU.Registers (Reg).Data (Bit / 8)
                 and Byte (2 ** (Bit mod 8))) /= 0;
      end Mask_Bit;

   begin
      Put_Line ("Testing comparison variants...");
      Setup_VU_32 (VU);

      --  v1 = {5, 10, 0xFFFFFFFF (-1 signed), 0x80000000 (INT_MIN)}
      Write_Element (VU, 1, 0, SEW_32, 5);
      Write_Element (VU, 1, 1, SEW_32, 10);
      Write_Element (VU, 1, 2, SEW_32, 16#FFFFFFFF#);
      Write_Element (VU, 1, 3, SEW_32, 16#80000000#);

      --  v2 = {5, 20, 0, 0x7FFFFFFF}
      Write_Element (VU, 2, 0, SEW_32, 5);
      Write_Element (VU, 2, 1, SEW_32, 20);
      Write_Element (VU, 2, 2, SEW_32, 0);
      Write_Element (VU, 2, 3, SEW_32, 16#7FFFFFFF#);

      --  VMSEQ.VX: v1 == 5 -> mask {1,0,0,0}
      VMSEQ_VX (VU, Vd => 3, Vs2 => 1, Rs1 => 5, VM => True);
      Check (Mask_Bit (3, 0) = True,
             "VMSEQ.VX 5==5 true");
      Check (Mask_Bit (3, 1) = False,
             "VMSEQ.VX 10==5 false");

      --  VMSEQ.VI: v1 == 5
      VMSEQ_VI (VU, Vd => 4, Vs2 => 1, Imm => 5, VM => True);
      Check (Mask_Bit (4, 0) = True,
             "VMSEQ.VI 5==5 true");
      Check (Mask_Bit (4, 1) = False,
             "VMSEQ.VI 10==5 false");

      --  VMSNE.VV: v1 /= v2
      VMSNE_VV (VU, Vd => 5, Vs2 => 1, Vs1 => 2, VM => True);
      Check (Mask_Bit (5, 0) = False,
             "VMSNE.VV 5/=5 false");
      Check (Mask_Bit (5, 1) = True,
             "VMSNE.VV 10/=20 true");

      --  VMSNE.VX: v1 /= 10
      VMSNE_VX (VU, Vd => 6, Vs2 => 1, Rs1 => 10, VM => True);
      Check (Mask_Bit (6, 0) = True,
             "VMSNE.VX 5/=10 true");
      Check (Mask_Bit (6, 1) = False,
             "VMSNE.VX 10/=10 false");

      --  VMSNE.VI: v1 /= 5
      VMSNE_VI (VU, Vd => 7, Vs2 => 1, Imm => 5, VM => True);
      Check (Mask_Bit (7, 0) = False,
             "VMSNE.VI 5/=5 false");
      Check (Mask_Bit (7, 2) = True,
             "VMSNE.VI -1/=5 true");

      --  VMSLTU.VX: v1 < 10 (unsigned)
      VMSLTU_VX (VU, Vd => 8, Vs2 => 1, Rs1 => 10, VM => True);
      Check (Mask_Bit (8, 0) = True,
             "VMSLTU.VX 5<10 true");
      Check (Mask_Bit (8, 1) = False,
             "VMSLTU.VX 10<10 false");
      --  0xFFFFFFFF is large unsigned
      Check (Mask_Bit (8, 2) = False,
             "VMSLTU.VX 0xFFFFFFFF<10 false");

      --  VMSLT.VV: v1 < v2 (signed)
      VMSLT_VV (VU, Vd => 3, Vs2 => 1, Vs1 => 2, VM => True);
      Check (Mask_Bit (3, 0) = False,
             "VMSLT.VV 5<5 false");
      Check (Mask_Bit (3, 1) = True,
             "VMSLT.VV 10<20 true");
      Check (Mask_Bit (3, 2) = True,
             "VMSLT.VV -1<0 true (signed)");
      Check (Mask_Bit (3, 3) = True,
             "VMSLT.VV INT_MIN<INT_MAX true");

      --  VMSLT.VX: v1 < 10 (signed)
      VMSLT_VX (VU, Vd => 4, Vs2 => 1, Rs1 => 10, VM => True);
      Check (Mask_Bit (4, 0) = True,
             "VMSLT.VX 5<10 true");
      Check (Mask_Bit (4, 2) = True,
             "VMSLT.VX -1<10 true (signed)");

      --  VMSLEU.VV: v1 <= v2 (unsigned)
      VMSLEU_VV (VU, Vd => 5, Vs2 => 1, Vs1 => 2, VM => True);
      Check (Mask_Bit (5, 0) = True,
             "VMSLEU.VV 5<=5 true");
      Check (Mask_Bit (5, 1) = True,
             "VMSLEU.VV 10<=20 true");

      --  VMSLEU.VX: v1 <= 5 (unsigned)
      VMSLEU_VX (VU, Vd => 6, Vs2 => 1, Rs1 => 5, VM => True);
      Check (Mask_Bit (6, 0) = True,
             "VMSLEU.VX 5<=5 true");
      Check (Mask_Bit (6, 1) = False,
             "VMSLEU.VX 10<=5 false");

      --  VMSLEU.VI: v1 <= 10
      VMSLEU_VI (VU, Vd => 7, Vs2 => 1, Imm => 10, VM => True);
      Check (Mask_Bit (7, 0) = True,
             "VMSLEU.VI 5<=10 true");
      Check (Mask_Bit (7, 1) = True,
             "VMSLEU.VI 10<=10 true");

      --  VMSLE.VV: v1 <= v2 (signed)
      VMSLE_VV (VU, Vd => 8, Vs2 => 1, Vs1 => 2, VM => True);
      Check (Mask_Bit (8, 0) = True,
             "VMSLE.VV 5<=5 true");
      Check (Mask_Bit (8, 2) = True,
             "VMSLE.VV -1<=0 true (signed)");

      --  VMSLE.VX: v1 <= 5 (signed)
      VMSLE_VX (VU, Vd => 3, Vs2 => 1, Rs1 => 5, VM => True);
      Check (Mask_Bit (3, 0) = True,
             "VMSLE.VX 5<=5 true");
      Check (Mask_Bit (3, 1) = False,
             "VMSLE.VX 10<=5 false");
      Check (Mask_Bit (3, 2) = True,
             "VMSLE.VX -1<=5 true (signed)");

      --  VMSLE.VI: v1 <= 5
      VMSLE_VI (VU, Vd => 4, Vs2 => 1, Imm => 5, VM => True);
      Check (Mask_Bit (4, 0) = True,
             "VMSLE.VI 5<=5 true");
      Check (Mask_Bit (4, 3) = True,
             "VMSLE.VI INT_MIN<=5 true (signed)");

      --  VMSGTU.VX: v1 > 5 (unsigned)
      VMSGTU_VX (VU, Vd => 5, Vs2 => 1, Rs1 => 5, VM => True);
      Check (Mask_Bit (5, 0) = False,
             "VMSGTU.VX 5>5 false");
      Check (Mask_Bit (5, 1) = True,
             "VMSGTU.VX 10>5 true");
      Check (Mask_Bit (5, 2) = True,
             "VMSGTU.VX 0xFFFFFFFF>5 true");

      --  VMSGTU.VI: v1 > 5
      VMSGTU_VI (VU, Vd => 6, Vs2 => 1, Imm => 5, VM => True);
      Check (Mask_Bit (6, 0) = False,
             "VMSGTU.VI 5>5 false");
      Check (Mask_Bit (6, 1) = True,
             "VMSGTU.VI 10>5 true");

      --  VMSGT.VX: v1 > 5 (signed)
      VMSGT_VX (VU, Vd => 7, Vs2 => 1, Rs1 => 5, VM => True);
      Check (Mask_Bit (7, 0) = False,
             "VMSGT.VX 5>5 false");
      Check (Mask_Bit (7, 1) = True,
             "VMSGT.VX 10>5 true");
      Check (Mask_Bit (7, 2) = False,
             "VMSGT.VX -1>5 false (signed)");

      --  VMSGT.VI: v1 > 0
      VMSGT_VI (VU, Vd => 8, Vs2 => 1, Imm => 0, VM => True);
      Check (Mask_Bit (8, 0) = True,
             "VMSGT.VI 5>0 true");
      Check (Mask_Bit (8, 1) = True,
             "VMSGT.VI 10>0 true");
      Check (Mask_Bit (8, 2) = False,
             "VMSGT.VI -1>0 false (signed)");
      Check (Mask_Bit (8, 3) = False,
             "VMSGT.VI INT_MIN>0 false");
   end Test_Comparison_Variants;

   --  Test VDIVU.VV and VREMU.VV
   procedure Test_Div_Rem_VV is
      VU : Vector_State;
   begin
      Put_Line ("Testing div/rem VV variants...");
      Setup_VU_32 (VU);

      Write_Element (VU, 1, 0, SEW_32, 20);
      Write_Element (VU, 1, 1, SEW_32, 100);
      Write_Element (VU, 1, 2, SEW_32, 17);
      Write_Element (VU, 1, 3, SEW_32, 0);
      Write_Element (VU, 2, 0, SEW_32, 3);
      Write_Element (VU, 2, 1, SEW_32, 10);
      Write_Element (VU, 2, 2, SEW_32, 5);
      Write_Element (VU, 2, 3, SEW_32, 7);

      --  VDIVU.VV
      VDIVU_VV (VU, Vd => 3, Vs2 => 1, Vs1 => 2, VM => True);
      Check (Read_Element (VU, 3, 0, SEW_32) = 6,
             "VDIVU.VV 20/3 = 6");
      Check (Read_Element (VU, 3, 1, SEW_32) = 10,
             "VDIVU.VV 100/10 = 10");
      Check (Read_Element (VU, 3, 2, SEW_32) = 3,
             "VDIVU.VV 17/5 = 3");
      --  0/7 = 0
      Check (Read_Element (VU, 3, 3, SEW_32) = 0,
             "VDIVU.VV 0/7 = 0");

      --  VREMU.VV
      VREMU_VV (VU, Vd => 4, Vs2 => 1, Vs1 => 2, VM => True);
      Check (Read_Element (VU, 4, 0, SEW_32) = 2,
             "VREMU.VV 20%%3 = 2");
      Check (Read_Element (VU, 4, 1, SEW_32) = 0,
             "VREMU.VV 100%%10 = 0");
      Check (Read_Element (VU, 4, 2, SEW_32) = 2,
             "VREMU.VV 17%%5 = 2");
   end Test_Div_Rem_VV;

   --  Test merge operations
   procedure Test_Merge_Ops is
      VU : Vector_State;
   begin
      Put_Line ("Testing merge operations...");
      Setup_VU_32 (VU);

      --  v1 = {10, 20, 30, 40} (used when mask=0)
      Write_Element (VU, 1, 0, SEW_32, 10);
      Write_Element (VU, 1, 1, SEW_32, 20);
      Write_Element (VU, 1, 2, SEW_32, 30);
      Write_Element (VU, 1, 3, SEW_32, 40);

      --  v2 = {100, 200, 300, 400} (used when mask=1)
      Write_Element (VU, 2, 0, SEW_32, 100);
      Write_Element (VU, 2, 1, SEW_32, 200);
      Write_Element (VU, 2, 2, SEW_32, 300);
      Write_Element (VU, 2, 3, SEW_32, 400);

      --  v0 mask = 0101 (bits 0 and 2 set)
      VU.Registers (0).Data := (others => 0);
      VU.Registers (0).Data (0) := 16#05#;

      --  VMERGE.VVM: select v2[i] where mask=1, v1[i] where mask=0
      VMERGE_VVM (VU, Vd => 3, Vs2 => 1, Vs1 => 2);
      Check (Read_Element (VU, 3, 0, SEW_32) = 100,
             "VMERGE.VVM [0] mask=1 -> 100");
      Check (Read_Element (VU, 3, 1, SEW_32) = 20,
             "VMERGE.VVM [1] mask=0 -> 20");
      Check (Read_Element (VU, 3, 2, SEW_32) = 300,
             "VMERGE.VVM [2] mask=1 -> 300");
      Check (Read_Element (VU, 3, 3, SEW_32) = 40,
             "VMERGE.VVM [3] mask=0 -> 40");

      --  VMERGE.VXM: select Rs1 where mask=1, v1[i] where mask=0
      VMERGE_VXM (VU, Vd => 4, Vs2 => 1, Rs1 => 99);
      Check (Read_Element (VU, 4, 0, SEW_32) = 99,
             "VMERGE.VXM [0] mask=1 -> 99");
      Check (Read_Element (VU, 4, 1, SEW_32) = 20,
             "VMERGE.VXM [1] mask=0 -> 20");

      --  VMERGE.VIM: select Imm where mask=1, v1[i] where mask=0
      VMERGE_VIM (VU, Vd => 5, Vs2 => 1, Imm => 7);
      Check (Read_Element (VU, 5, 0, SEW_32) = 7,
             "VMERGE.VIM [0] mask=1 -> 7");
      Check (Read_Element (VU, 5, 1, SEW_32) = 20,
             "VMERGE.VIM [1] mask=0 -> 20");
      Check (Read_Element (VU, 5, 2, SEW_32) = 7,
             "VMERGE.VIM [2] mask=1 -> 7");
   end Test_Merge_Ops;

   --  Test signed reductions (VREDMAX_VS, VREDMIN_VS)
   procedure Test_Signed_Reductions is
      VU : Vector_State;
      R  : Word;
   begin
      Put_Line ("Testing signed reductions...");
      Setup_VU_32 (VU);

      --  v1 = {5, 0xFFFFFFFF (-1), 0x80000000 (INT_MIN), 10}
      Write_Element (VU, 1, 0, SEW_32, 5);
      Write_Element (VU, 1, 1, SEW_32, 16#FFFFFFFF#);
      Write_Element (VU, 1, 2, SEW_32, 16#80000000#);
      Write_Element (VU, 1, 3, SEW_32, 10);

      --  v2[0] = 0 (initial scalar)
      Write_Element (VU, 2, 0, SEW_32, 0);

      --  VREDMAX_VS: signed max of {5, -1, INT_MIN, 10} with init=0 -> 10
      R := VREDMAX_VS (VU, Vs2 => 1, Vs1 => 2, VM => True);
      Check (R = 10,
             "VREDMAX_VS max(5,-1,INT_MIN,10,init=0) = 10");

      --  VREDMIN_VS: signed min of {5, -1, INT_MIN, 10} with init=0 -> INT_MIN
      R := VREDMIN_VS (VU, Vs2 => 1, Vs1 => 2, VM => True);
      Check (R = 16#80000000#,
             "VREDMIN_VS min(5,-1,INT_MIN,10,init=0) = INT_MIN");

      --  With init=100
      Write_Element (VU, 2, 0, SEW_32, 100);
      R := VREDMAX_VS (VU, Vs2 => 1, Vs1 => 2, VM => True);
      Check (R = 100,
             "VREDMAX_VS max(5,-1,INT_MIN,10,init=100) = 100");
   end Test_Signed_Reductions;

   --  Test additional mask operations
   procedure Test_Mask_Logic_Variants is
      VU : Vector_State;
   begin
      Put_Line ("Testing mask logic variants...");
      Setup_VU_32 (VU);

      --  v1 mask = 1010, v2 mask = 1100
      VU.Registers (1).Data := (others => 0);
      VU.Registers (1).Data (0) := 16#0A#;  -- 1010
      VU.Registers (2).Data := (others => 0);
      VU.Registers (2).Data (0) := 16#0C#;  -- 1100

      --  VMNAND: ~(1010 & 1100) = ~1000 = 0111
      VMNAND_MM (VU, Vd => 3, Vs2 => 1, Vs1 => 2);
      Check ((VU.Registers (3).Data (0) and 16#0F#) = 16#07#,
             "VMNAND.MM ~(1010&1100) = 0111");

      --  VMANDNOT: 1010 & ~1100 = 1010 & 0011 = 0010
      VMANDNOT_MM (VU, Vd => 4, Vs2 => 1, Vs1 => 2);
      Check ((VU.Registers (4).Data (0) and 16#0F#) = 16#02#,
             "VMANDNOT.MM 1010&~1100 = 0010");

      --  VMNOR: ~(1010 | 1100) = ~1110 = 0001
      VMNOR_MM (VU, Vd => 5, Vs2 => 1, Vs1 => 2);
      Check ((VU.Registers (5).Data (0) and 16#0F#) = 16#01#,
             "VMNOR.MM ~(1010|1100) = 0001");

      --  VMORNOT: 1010 | ~1100 = 1010 | 0011 = 1011
      VMORNOT_MM (VU, Vd => 6, Vs2 => 1, Vs1 => 2);
      Check ((VU.Registers (6).Data (0) and 16#0F#) = 16#0B#,
             "VMORNOT.MM 1010|~1100 = 1011");

      --  VMXNOR: ~(1010 ^ 1100) = ~0110 = 1001
      VMXNOR_MM (VU, Vd => 7, Vs2 => 1, Vs1 => 2);
      Check ((VU.Registers (7).Data (0) and 16#0F#) = 16#09#,
             "VMXNOR.MM ~(1010^1100) = 1001");
   end Test_Mask_Logic_Variants;

   --  Test strided store
   procedure Test_Strided_Store is
      VU  : Vector_State;
      Mem : RISCV.Memory.Memory_Unit;
   begin
      Put_Line ("Testing strided store...");
      Setup_VU_32 (VU);

      RISCV.Memory.Initialize (Mem);
      RISCV.Memory.Add_Region (Mem, "RAM", 0, 16#2000#,
                                RISCV.Memory.RAM,
                                RISCV.Memory.Permission_RWX);

      --  v1 = {111, 222, 333, 444}
      Write_Element (VU, 1, 0, SEW_32, 111);
      Write_Element (VU, 1, 1, SEW_32, 222);
      Write_Element (VU, 1, 2, SEW_32, 333);
      Write_Element (VU, 1, 3, SEW_32, 444);

      --  Store with stride=8 starting at 0x100
      Vector_Store_Strided (VU, Mem,
                            Vs3 => 1, Rs1 => 16#100#, Rs2 => 8,
                            VM => True, EEW => SEW_32);

      --  Read back: at 0x100, 0x108, 0x110, 0x118
      Check (RISCV.Memory.Read_Word (Mem, 16#100#) = 111,
             "Strided store [0] at 0x100 = 111");
      Check (RISCV.Memory.Read_Word (Mem, 16#108#) = 222,
             "Strided store [1] at 0x108 = 222");
      Check (RISCV.Memory.Read_Word (Mem, 16#110#) = 333,
             "Strided store [2] at 0x110 = 333");
      Check (RISCV.Memory.Read_Word (Mem, 16#118#) = 444,
             "Strided store [3] at 0x118 = 444");
   end Test_Strided_Store;

   --  Test whole-register moves
   procedure Test_VMV_NR is
      VU : Vector_State;
   begin
      Put_Line ("Testing whole-register moves...");
      Setup_VU_32 (VU);

      --  Set up v2 with known data
      Write_Element (VU, 2, 0, SEW_32, 16#AABBCCDD#);
      Write_Element (VU, 2, 1, SEW_32, 16#11223344#);
      Write_Element (VU, 2, 2, SEW_32, 16#55667788#);
      Write_Element (VU, 2, 3, SEW_32, 16#DEADBEEF#);

      --  vmv1r.v: copy v2 -> v4
      VMV_NR_V (VU, 4, 2, 1);
      Check (Read_Element (VU, 4, 0, SEW_32) = 16#AABBCCDD#,
             "vmv1r.v v4,v2 [0]");
      Check (Read_Element (VU, 4, 3, SEW_32) = 16#DEADBEEF#,
             "vmv1r.v v4,v2 [3]");

      --  vmv2r.v: copy v2-v3 -> v4-v5
      Write_Element (VU, 3, 0, SEW_32, 16#F0F0F0F0#);
      VMV_NR_V (VU, 4, 2, 2);
      Check (Read_Element (VU, 4, 0, SEW_32) = 16#AABBCCDD#,
             "vmv2r.v v4,v2 [reg0]");
      Check (Read_Element (VU, 5, 0, SEW_32) = 16#F0F0F0F0#,
             "vmv2r.v v5,v3 [reg1]");

   end Test_VMV_NR;

   --  Test widening add/sub
   procedure Test_Widening is
      VU : Vector_State;
      VL : Word;
      --  SEW=16, LMUL=1: VL = 128/16 = 8 elements
      VType_E16 : constant Word := 16#C8#;
   begin
      Put_Line ("Testing widening add/sub...");

      Initialize (VU);
      VL := Vsetvl (VU, 4, VType_E16);
      pragma Unreferenced (VL);

      --  vs2 = [100, 200, 300, 400] (16-bit)
      Write_Element (VU, 2, 0, SEW_16, 100);
      Write_Element (VU, 2, 1, SEW_16, 200);
      Write_Element (VU, 2, 2, SEW_16, 300);
      Write_Element (VU, 2, 3, SEW_16, 400);

      --  vs1 = [10, 20, 30, 40] (16-bit)
      Write_Element (VU, 1, 0, SEW_16, 10);
      Write_Element (VU, 1, 1, SEW_16, 20);
      Write_Element (VU, 1, 2, SEW_16, 30);
      Write_Element (VU, 1, 3, SEW_16, 40);

      --  vwaddu.vv: result in 32-bit = [110, 220, 330, 440]
      VWADDU_VV (VU, 4, 2, 1, True);
      Check (Word (Read_Element_64 (VU, 4, 0) and 16#FFFFFFFF#) = 110,
             "vwaddu.vv [0] = 110");
      Check (Word (Read_Element_64 (VU, 4, 1) and 16#FFFFFFFF#) = 220,
             "vwaddu.vv [1] = 220");

      --  vwsubu.vv: result = [90, 180, 270, 360]
      VWSUBU_VV (VU, 4, 2, 1, True);
      Check (Word (Read_Element_64 (VU, 4, 0) and 16#FFFFFFFF#) = 90,
             "vwsubu.vv [0] = 90");

   end Test_Widening;

   --  Test widening multiply
   procedure Test_Widening_Mul is
      VU : Vector_State;
   begin
      Put_Line ("Testing widening multiply...");
      Setup_VU_32 (VU);

      Write_Element (VU, 2, 0, SEW_32, 100_000);
      Write_Element (VU, 2, 1, SEW_32, 200_000);
      Write_Element (VU, 1, 0, SEW_32, 300_000);
      Write_Element (VU, 1, 1, SEW_32, 400_000);

      VWMULU_VV (VU, 4, 2, 1, True);
      Check (Read_Element_64 (VU, 4, 0) = 30_000_000_000,
             "vwmulu.vv [0] = 30B");
      Check (Read_Element_64 (VU, 4, 1) = 80_000_000_000,
             "vwmulu.vv [1] = 80B");
   end Test_Widening_Mul;

   --  Test narrowing shift
   procedure Test_Narrowing is
      VU : Vector_State;
   begin
      Put_Line ("Testing narrowing shifts...");
      Setup_VU_32 (VU);

      --  Write 64-bit values to v2
      Write_Element_64 (VU, 2, 0, 16#0000000100000000#);
      Write_Element_64 (VU, 2, 1, 16#00000002FFFFFFFF#);

      --  vnsrl: shift right by 32 => get upper 32 bits
      VNSRL_WI (VU, 4, 2, 32, True);
      Check (Read_Element (VU, 4, 0, SEW_32) = 1,
             "vnsrl.wi [0] >> 32 = 1");
      Check (Read_Element (VU, 4, 1, SEW_32) = 2,
             "vnsrl.wi [1] >> 32 = 2");

      --  vnsrl: shift right by 0 => get lower 32 bits
      VNSRL_WI (VU, 4, 2, 0, True);
      Check (Read_Element (VU, 4, 0, SEW_32) = 0,
             "vnsrl.wi [0] >> 0 = 0");
      Check (Read_Element (VU, 4, 1, SEW_32) = 16#FFFFFFFF#,
             "vnsrl.wi [1] >> 0 = FFFFFFFF");
   end Test_Narrowing;

   --  Test FP vector operations
   procedure Test_FP_Vector is
      VU : Vector_State;
      FP : aliased RISCV.FPU.FPU_State;
      FP_Ptr : constant FPU_Access := FP'Unchecked_Access;
   begin
      Put_Line ("Testing FP vector operations...");
      Setup_VU_32 (VU);
      RISCV.FPU.Initialize (FP);

      --  1.0 = 0x3F800000, 2.0 = 0x40000000
      --  3.0 = 0x40400000, 4.0 = 0x40800000
      Write_Element (VU, 2, 0, SEW_32, 16#3F800000#);  -- 1.0
      Write_Element (VU, 2, 1, SEW_32, 16#40000000#);  -- 2.0
      Write_Element (VU, 2, 2, SEW_32, 16#40400000#);  -- 3.0
      Write_Element (VU, 2, 3, SEW_32, 16#40800000#);  -- 4.0

      Write_Element (VU, 1, 0, SEW_32, 16#3F800000#);  -- 1.0
      Write_Element (VU, 1, 1, SEW_32, 16#3F800000#);  -- 1.0
      Write_Element (VU, 1, 2, SEW_32, 16#3F800000#);  -- 1.0
      Write_Element (VU, 1, 3, SEW_32, 16#3F800000#);  -- 1.0

      --  vfadd.vv: [1+1, 2+1, 3+1, 4+1] = [2.0, 3.0, 4.0, 5.0]
      VFADD_VV (VU, FP_Ptr, 4, 2, 1, True);
      Check (Read_Element (VU, 4, 0, SEW_32) = 16#40000000#,
             "vfadd.vv [0] = 2.0");
      Check (Read_Element (VU, 4, 1, SEW_32) = 16#40400000#,
             "vfadd.vv [1] = 3.0");
      Check (Read_Element (VU, 4, 2, SEW_32) = 16#40800000#,
             "vfadd.vv [2] = 4.0");
      Check (Read_Element (VU, 4, 3, SEW_32) = 16#40A00000#,
             "vfadd.vv [3] = 5.0");

      --  vfsub.vv: [1-1, 2-1, 3-1, 4-1] = [0.0, 1.0, 2.0, 3.0]
      VFSUB_VV (VU, FP_Ptr, 4, 2, 1, True);
      Check (Read_Element (VU, 4, 0, SEW_32) = 0,
             "vfsub.vv [0] = 0.0");
      Check (Read_Element (VU, 4, 1, SEW_32) = 16#3F800000#,
             "vfsub.vv [1] = 1.0");

      --  vfmul.vv: [1*1, 2*1, 3*1, 4*1] = [1.0, 2.0, 3.0, 4.0]
      VFMUL_VV (VU, FP_Ptr, 4, 2, 1, True);
      Check (Read_Element (VU, 4, 0, SEW_32) = 16#3F800000#,
             "vfmul.vv [0] = 1.0");
      Check (Read_Element (VU, 4, 1, SEW_32) = 16#40000000#,
             "vfmul.vv [1] = 2.0");

      --  vfdiv.vv: [1/1, 2/1, 3/1, 4/1] = [1.0, 2.0, 3.0, 4.0]
      VFDIV_VV (VU, FP_Ptr, 4, 2, 1, True);
      Check (Read_Element (VU, 4, 0, SEW_32) = 16#3F800000#,
             "vfdiv.vv [0] = 1.0");

      --  vfmin.vv
      VFMIN_VV (VU, FP_Ptr, 4, 2, 1, True);
      Check (Read_Element (VU, 4, 0, SEW_32) = 16#3F800000#,
             "vfmin.vv [0] = min(1,1) = 1.0");
      Check (Read_Element (VU, 4, 3, SEW_32) = 16#3F800000#,
             "vfmin.vv [3] = min(4,1) = 1.0");

      --  vfmax.vv
      VFMAX_VV (VU, FP_Ptr, 4, 2, 1, True);
      Check (Read_Element (VU, 4, 0, SEW_32) = 16#3F800000#,
             "vfmax.vv [0] = max(1,1) = 1.0");
      Check (Read_Element (VU, 4, 3, SEW_32) = 16#40800000#,
             "vfmax.vv [3] = max(4,1) = 4.0");

      --  vfsqrt.v: sqrt(4.0) = 2.0
      Write_Element (VU, 2, 0, SEW_32, 16#40800000#);  -- 4.0
      VFSQRT_V (VU, FP_Ptr, 4, 2, True);
      Check (Read_Element (VU, 4, 0, SEW_32) = 16#40000000#,
             "vfsqrt.v [0] = sqrt(4.0) = 2.0");

      --  vfadd.vf: broadcast scalar
      Write_Element (VU, 2, 0, SEW_32, 16#3F800000#);  -- 1.0
      Write_Element (VU, 2, 1, SEW_32, 16#40000000#);  -- 2.0
      VFADD_VF (VU, FP_Ptr, 4, 2, 16#40400000#, True);  -- + 3.0
      Check (Read_Element (VU, 4, 0, SEW_32) = 16#40800000#,
             "vfadd.vf [0] = 1.0+3.0 = 4.0");
      Check (Read_Element (VU, 4, 1, SEW_32) = 16#40A00000#,
             "vfadd.vf [1] = 2.0+3.0 = 5.0");

      --  vfmacc.vv: vd = vs1*vs2 + vd
      Write_Element (VU, 1, 0, SEW_32, 16#40000000#);  -- 2.0
      Write_Element (VU, 2, 0, SEW_32, 16#40400000#);  -- 3.0
      Write_Element (VU, 4, 0, SEW_32, 16#3F800000#);  -- 1.0 (accumulator)
      VFMACC_VV (VU, FP_Ptr, 4, 1, 2, True);
      --  vd[0] = 2.0 * 3.0 + 1.0 = 7.0 = 0x40E00000
      Check (Read_Element (VU, 4, 0, SEW_32) = 16#40E00000#,
             "vfmacc.vv [0] = 2*3+1 = 7.0");
   end Test_FP_Vector;

   --  Test indexed load/store
   procedure Test_Indexed_Load_Store is
      VU  : Vector_State;
      Mem : RISCV.Memory.Memory_Unit;
   begin
      Put_Line ("Testing indexed load/store...");

      Setup_VU_32 (VU);

      RISCV.Memory.Initialize (Mem);
      RISCV.Memory.Add_Region (Mem, "RAM", 0, 16#2000#,
                                RISCV.Memory.RAM,
                                RISCV.Memory.Permission_RWX);

      --  Scatter data at non-contiguous addresses
      RISCV.Memory.Write_Word (Mem, 16#100#, 11);  -- offset 0
      RISCV.Memory.Write_Word (Mem, 16#10C#, 22);  -- offset 12
      RISCV.Memory.Write_Word (Mem, 16#104#, 33);  -- offset 4
      RISCV.Memory.Write_Word (Mem, 16#118#, 44);  -- offset 24

      --  Set up index vector in v2: offsets = {0, 12, 4, 24}
      Write_Element (VU, 2, 0, SEW_32, 0);
      Write_Element (VU, 2, 1, SEW_32, 12);
      Write_Element (VU, 2, 2, SEW_32, 4);
      Write_Element (VU, 2, 3, SEW_32, 24);

      --  Indexed load: gather from base 0x100 + offsets
      Vector_Load_Indexed (VU, Mem, Vd => 1, Rs1 => 16#100#,
                           Vs2_Reg => 2, VM => True,
                           Data_EEW => SEW_32, Index_EEW => SEW_32);
      Check (Read_Element (VU, 1, 0, SEW_32) = 11,
             "Indexed load [0] = 11 (offset 0)");
      Check (Read_Element (VU, 1, 1, SEW_32) = 22,
             "Indexed load [1] = 22 (offset 12)");
      Check (Read_Element (VU, 1, 2, SEW_32) = 33,
             "Indexed load [2] = 33 (offset 4)");
      Check (Read_Element (VU, 1, 3, SEW_32) = 44,
             "Indexed load [3] = 44 (offset 24)");

      --  Indexed store: scatter to base 0x200 + offsets
      Write_Element (VU, 3, 0, SEW_32, 55);
      Write_Element (VU, 3, 1, SEW_32, 66);
      Write_Element (VU, 3, 2, SEW_32, 77);
      Write_Element (VU, 3, 3, SEW_32, 88);

      Vector_Store_Indexed (VU, Mem, Vs3 => 3, Rs1 => 16#200#,
                            Vs2_Reg => 2, VM => True,
                            Data_EEW => SEW_32, Index_EEW => SEW_32);
      Check (RISCV.Memory.Read_Word (Mem, 16#200#) = 55,
             "Indexed store [0] at offset 0");
      Check (RISCV.Memory.Read_Word (Mem, 16#20C#) = 66,
             "Indexed store [1] at offset 12");
      Check (RISCV.Memory.Read_Word (Mem, 16#204#) = 77,
             "Indexed store [2] at offset 4");
      Check (RISCV.Memory.Read_Word (Mem, 16#218#) = 88,
             "Indexed store [3] at offset 24");
   end Test_Indexed_Load_Store;

   --  Test segment load/store (unit-stride)
   procedure Test_Segment_Load_Store is
      VU  : Vector_State;
      Mem : RISCV.Memory.Memory_Unit;
   begin
      Put_Line ("Testing segment load/store...");

      Setup_VU_32 (VU);

      RISCV.Memory.Initialize (Mem);
      RISCV.Memory.Add_Region (Mem, "RAM", 0, 16#2000#,
                                RISCV.Memory.RAM,
                                RISCV.Memory.Permission_RWX);

      --  Interleaved data for vlseg2: (x0,y0, x1,y1, x2,y2, x3,y3)
      --  nf=1 means 2 fields
      RISCV.Memory.Write_Word (Mem, 16#100#, 10);   -- x0
      RISCV.Memory.Write_Word (Mem, 16#104#, 100);  -- y0
      RISCV.Memory.Write_Word (Mem, 16#108#, 20);   -- x1
      RISCV.Memory.Write_Word (Mem, 16#10C#, 200);  -- y1
      RISCV.Memory.Write_Word (Mem, 16#110#, 30);   -- x2
      RISCV.Memory.Write_Word (Mem, 16#114#, 300);  -- y2
      RISCV.Memory.Write_Word (Mem, 16#118#, 40);   -- x3
      RISCV.Memory.Write_Word (Mem, 16#11C#, 400);  -- y3

      --  vlseg2e32.v v4, (rs1) -- loads fields into v4 and v5
      Vector_Load_Segment_Unit (VU, Mem, Vd => 4, Rs1 => 16#100#,
                                VM => True, EEW => SEW_32, Nf => 1);

      --  v4 should have x values
      Check (Read_Element (VU, 4, 0, SEW_32) = 10,
             "vlseg2 v4[0] = 10 (x0)");
      Check (Read_Element (VU, 4, 1, SEW_32) = 20,
             "vlseg2 v4[1] = 20 (x1)");
      Check (Read_Element (VU, 4, 2, SEW_32) = 30,
             "vlseg2 v4[2] = 30 (x2)");
      Check (Read_Element (VU, 4, 3, SEW_32) = 40,
             "vlseg2 v4[3] = 40 (x3)");

      --  v5 should have y values
      Check (Read_Element (VU, 5, 0, SEW_32) = 100,
             "vlseg2 v5[0] = 100 (y0)");
      Check (Read_Element (VU, 5, 1, SEW_32) = 200,
             "vlseg2 v5[1] = 200 (y1)");
      Check (Read_Element (VU, 5, 2, SEW_32) = 300,
             "vlseg2 v5[2] = 300 (y2)");
      Check (Read_Element (VU, 5, 3, SEW_32) = 400,
             "vlseg2 v5[3] = 400 (y3)");

      --  Test vlseg3e32: 3 fields interleaved (r,g,b, r,g,b, ...)
      RISCV.Memory.Write_Word (Mem, 16#200#, 1);    -- r0
      RISCV.Memory.Write_Word (Mem, 16#204#, 2);    -- g0
      RISCV.Memory.Write_Word (Mem, 16#208#, 3);    -- b0
      RISCV.Memory.Write_Word (Mem, 16#20C#, 4);    -- r1
      RISCV.Memory.Write_Word (Mem, 16#210#, 5);    -- g1
      RISCV.Memory.Write_Word (Mem, 16#214#, 6);    -- b1
      RISCV.Memory.Write_Word (Mem, 16#218#, 7);    -- r2
      RISCV.Memory.Write_Word (Mem, 16#21C#, 8);    -- g2
      RISCV.Memory.Write_Word (Mem, 16#220#, 9);    -- b2
      RISCV.Memory.Write_Word (Mem, 16#224#, 10);   -- r3
      RISCV.Memory.Write_Word (Mem, 16#228#, 11);   -- g3
      RISCV.Memory.Write_Word (Mem, 16#22C#, 12);   -- b3

      Vector_Load_Segment_Unit (VU, Mem, Vd => 8, Rs1 => 16#200#,
                                VM => True, EEW => SEW_32, Nf => 2);

      Check (Read_Element (VU, 8, 0, SEW_32) = 1,
             "vlseg3 v8[0] = 1 (r0)");
      Check (Read_Element (VU, 8, 1, SEW_32) = 4,
             "vlseg3 v8[1] = 4 (r1)");
      Check (Read_Element (VU, 9, 0, SEW_32) = 2,
             "vlseg3 v9[0] = 2 (g0)");
      Check (Read_Element (VU, 9, 1, SEW_32) = 5,
             "vlseg3 v9[1] = 5 (g1)");
      Check (Read_Element (VU, 10, 0, SEW_32) = 3,
             "vlseg3 v10[0] = 3 (b0)");
      Check (Read_Element (VU, 10, 1, SEW_32) = 6,
             "vlseg3 v10[1] = 6 (b1)");

      --  Test segment store: vsseg2e32.v
      Write_Element (VU, 12, 0, SEW_32, 111);
      Write_Element (VU, 12, 1, SEW_32, 222);
      Write_Element (VU, 13, 0, SEW_32, 333);
      Write_Element (VU, 13, 1, SEW_32, 444);
      --  Only store 2 elements
      declare
         VL_Save : constant Word := VU.VL;
      begin
         VU.VL := 2;
         Vector_Store_Segment_Unit (VU, Mem, Vs3 => 12, Rs1 => 16#400#,
                                   VM => True, EEW => SEW_32, Nf => 1);
         VU.VL := VL_Save;
      end;

      Check (RISCV.Memory.Read_Word (Mem, 16#400#) = 111,
             "vsseg2 [0,0] = 111");
      Check (RISCV.Memory.Read_Word (Mem, 16#404#) = 333,
             "vsseg2 [0,1] = 333");
      Check (RISCV.Memory.Read_Word (Mem, 16#408#) = 222,
             "vsseg2 [1,0] = 222");
      Check (RISCV.Memory.Read_Word (Mem, 16#40C#) = 444,
             "vsseg2 [1,1] = 444");
   end Test_Segment_Load_Store;

   --  Test segment strided load
   procedure Test_Segment_Strided is
      VU  : Vector_State;
      Mem : RISCV.Memory.Memory_Unit;
   begin
      Put_Line ("Testing segment strided load/store...");

      Setup_VU_32 (VU);

      RISCV.Memory.Initialize (Mem);
      RISCV.Memory.Add_Region (Mem, "RAM", 0, 16#2000#,
                                RISCV.Memory.RAM,
                                RISCV.Memory.Permission_RWX);

      --  2 fields per struct, structs at stride=16
      --  Struct 0 at 0x100: {10, 20}
      RISCV.Memory.Write_Word (Mem, 16#100#, 10);
      RISCV.Memory.Write_Word (Mem, 16#104#, 20);
      --  Struct 1 at 0x110: {30, 40}
      RISCV.Memory.Write_Word (Mem, 16#110#, 30);
      RISCV.Memory.Write_Word (Mem, 16#114#, 40);
      --  Struct 2 at 0x120: {50, 60}
      RISCV.Memory.Write_Word (Mem, 16#120#, 50);
      RISCV.Memory.Write_Word (Mem, 16#124#, 60);
      --  Struct 3 at 0x130: {70, 80}
      RISCV.Memory.Write_Word (Mem, 16#130#, 70);
      RISCV.Memory.Write_Word (Mem, 16#134#, 80);

      Vector_Load_Segment_Strided (VU, Mem, Vd => 4, Rs1 => 16#100#,
                                   Rs2 => 16, VM => True,
                                   EEW => SEW_32, Nf => 1);

      Check (Read_Element (VU, 4, 0, SEW_32) = 10,
             "vlsseg2 v4[0] = 10");
      Check (Read_Element (VU, 4, 1, SEW_32) = 30,
             "vlsseg2 v4[1] = 30");
      Check (Read_Element (VU, 4, 2, SEW_32) = 50,
             "vlsseg2 v4[2] = 50");
      Check (Read_Element (VU, 4, 3, SEW_32) = 70,
             "vlsseg2 v4[3] = 70");
      Check (Read_Element (VU, 5, 0, SEW_32) = 20,
             "vlsseg2 v5[0] = 20");
      Check (Read_Element (VU, 5, 1, SEW_32) = 40,
             "vlsseg2 v5[1] = 40");
      Check (Read_Element (VU, 5, 2, SEW_32) = 60,
             "vlsseg2 v5[2] = 60");
      Check (Read_Element (VU, 5, 3, SEW_32) = 80,
             "vlsseg2 v5[3] = 80");
   end Test_Segment_Strided;

   --  Test segment indexed load
   procedure Test_Segment_Indexed is
      VU  : Vector_State;
      Mem : RISCV.Memory.Memory_Unit;
   begin
      Put_Line ("Testing segment indexed load/store...");

      Setup_VU_32 (VU);

      RISCV.Memory.Initialize (Mem);
      RISCV.Memory.Add_Region (Mem, "RAM", 0, 16#2000#,
                                RISCV.Memory.RAM,
                                RISCV.Memory.Permission_RWX);

      --  Structs at scattered offsets, each struct has 2 fields (32-bit)
      --  Struct A at offset 0: {10, 20}
      RISCV.Memory.Write_Word (Mem, 16#100#, 10);
      RISCV.Memory.Write_Word (Mem, 16#104#, 20);
      --  Struct B at offset 16: {30, 40}
      RISCV.Memory.Write_Word (Mem, 16#110#, 30);
      RISCV.Memory.Write_Word (Mem, 16#114#, 40);

      --  Index vector: offsets = {0, 16}
      Write_Element (VU, 2, 0, SEW_32, 0);
      Write_Element (VU, 2, 1, SEW_32, 16);

      --  Only 2 elements
      VU.VL := 2;

      Vector_Load_Segment_Indexed (VU, Mem, Vd => 6, Rs1 => 16#100#,
                                   Vs2_Reg => 2, VM => True,
                                   Data_EEW => SEW_32,
                                   Index_EEW => SEW_32, Nf => 1);

      Check (Read_Element (VU, 6, 0, SEW_32) = 10,
             "vluxseg2 v6[0] = 10");
      Check (Read_Element (VU, 6, 1, SEW_32) = 30,
             "vluxseg2 v6[1] = 30");
      Check (Read_Element (VU, 7, 0, SEW_32) = 20,
             "vluxseg2 v7[0] = 20");
      Check (Read_Element (VU, 7, 1, SEW_32) = 40,
             "vluxseg2 v7[1] = 40");
   end Test_Segment_Indexed;

   --  Test whole-register load/store
   procedure Test_Whole_Register is
      VU  : Vector_State;
      Mem : RISCV.Memory.Memory_Unit;
   begin
      Put_Line ("Testing whole-register load/store...");

      Setup_VU_32 (VU);

      RISCV.Memory.Initialize (Mem);
      RISCV.Memory.Add_Region (Mem, "RAM", 0, 16#2000#,
                                RISCV.Memory.RAM,
                                RISCV.Memory.Permission_RWX);

      --  Fill v4 with known data
      for B in 0 .. VLENB - 1 loop
         VU.Registers (4).Data (B) := Byte (B + 1);
      end loop;

      --  Store whole register (1 register)
      Vector_Store_Whole_Register (VU, Mem, Vs3 => 4, Rs1 => 16#500#,
                                  NReg => 1);

      --  Verify memory contents
      for B in 0 .. VLENB - 1 loop
         Check (RISCV.Memory.Read_Byte (Mem,
           RISCV.Memory_Address (16#500# + Word (B))) = Byte (B + 1),
           "Whole store byte" & Natural'Image (B));
      end loop;

      --  Load whole register back into v8
      Vector_Load_Whole_Register (VU, Mem, Vd => 8, Rs1 => 16#500#,
                                 NReg => 1);

      --  Verify register contents
      for B in 0 .. VLENB - 1 loop
         Check (VU.Registers (8).Data (B) = Byte (B + 1),
           "Whole load byte" & Natural'Image (B));
      end loop;

      --  Test 2-register load/store
      for B in 0 .. VLENB - 1 loop
         VU.Registers (10).Data (B) := Byte (B + 10);
         VU.Registers (11).Data (B) := Byte (B + 20);
      end loop;

      Vector_Store_Whole_Register (VU, Mem, Vs3 => 10, Rs1 => 16#600#,
                                  NReg => 2);
      Vector_Load_Whole_Register (VU, Mem, Vd => 14, Rs1 => 16#600#,
                                 NReg => 2);

      Check (VU.Registers (14).Data (0) = Byte (10),
             "vl2re8 reg0 byte0 = 10");
      Check (VU.Registers (14).Data (VLENB - 1) = Byte (VLENB - 1 + 10),
             "vl2re8 reg0 last byte");
      Check (VU.Registers (15).Data (0) = Byte (20),
             "vl2re8 reg1 byte0 = 20");
      Check (VU.Registers (15).Data (VLENB - 1) = Byte (VLENB - 1 + 20),
             "vl2re8 reg1 last byte");
   end Test_Whole_Register;

   --  Test slide operations
   procedure Test_Slide is
      VU : Vector_State;
   begin
      Put_Line ("Testing slide operations...");

      Setup_VU_32 (VU);

      --  v1 = {10, 20, 30, 40}
      Write_Element (VU, 1, 0, SEW_32, 10);
      Write_Element (VU, 1, 1, SEW_32, 20);
      Write_Element (VU, 1, 2, SEW_32, 30);
      Write_Element (VU, 1, 3, SEW_32, 40);

      --  vslideup.vi v2, v1, 1: shift up by 1, vd[0] unchanged
      --  First set v2 to known values
      Write_Element (VU, 2, 0, SEW_32, 99);
      Write_Element (VU, 2, 1, SEW_32, 99);
      Write_Element (VU, 2, 2, SEW_32, 99);
      Write_Element (VU, 2, 3, SEW_32, 99);
      VSLIDEUP_VI (VU, Vd => 2, Vs2 => 1, Imm => 1, VM => True);
      Check (Read_Element (VU, 2, 0, SEW_32) = 99,
             "vslideup.vi [0] unchanged (99)");
      Check (Read_Element (VU, 2, 1, SEW_32) = 10,
             "vslideup.vi [1] = src[0] = 10");
      Check (Read_Element (VU, 2, 2, SEW_32) = 20,
             "vslideup.vi [2] = src[1] = 20");
      Check (Read_Element (VU, 2, 3, SEW_32) = 30,
             "vslideup.vi [3] = src[2] = 30");

      --  vslidedown.vi v3, v1, 1: shift down by 1
      VSLIDEDOWN_VI (VU, Vd => 3, Vs2 => 1, Imm => 1, VM => True);
      Check (Read_Element (VU, 3, 0, SEW_32) = 20,
             "vslidedown.vi [0] = src[1] = 20");
      Check (Read_Element (VU, 3, 1, SEW_32) = 30,
             "vslidedown.vi [1] = src[2] = 30");
      Check (Read_Element (VU, 3, 2, SEW_32) = 40,
             "vslidedown.vi [2] = src[3] = 40");
      Check (Read_Element (VU, 3, 3, SEW_32) = 0,
             "vslidedown.vi [3] = 0 (past end)");

      --  vslide1up.vx v4, v1, 77
      VSLIDE1UP_VX (VU, Vd => 4, Vs2 => 1, Rs1 => 77, VM => True);
      Check (Read_Element (VU, 4, 0, SEW_32) = 77,
             "vslide1up.vx [0] = 77 (scalar)");
      Check (Read_Element (VU, 4, 1, SEW_32) = 10,
             "vslide1up.vx [1] = src[0] = 10");
      Check (Read_Element (VU, 4, 2, SEW_32) = 20,
             "vslide1up.vx [2] = src[1] = 20");
      Check (Read_Element (VU, 4, 3, SEW_32) = 30,
             "vslide1up.vx [3] = src[2] = 30");

      --  vslide1down.vx v5, v1, 88
      VSLIDE1DOWN_VX (VU, Vd => 5, Vs2 => 1, Rs1 => 88, VM => True);
      Check (Read_Element (VU, 5, 0, SEW_32) = 20,
             "vslide1down.vx [0] = src[1] = 20");
      Check (Read_Element (VU, 5, 1, SEW_32) = 30,
             "vslide1down.vx [1] = src[2] = 30");
      Check (Read_Element (VU, 5, 2, SEW_32) = 40,
             "vslide1down.vx [2] = src[3] = 40");
      Check (Read_Element (VU, 5, 3, SEW_32) = 88,
             "vslide1down.vx [3] = 88 (scalar)");

      --  vslideup.vx with offset=2
      Write_Element (VU, 6, 0, SEW_32, 55);
      Write_Element (VU, 6, 1, SEW_32, 55);
      Write_Element (VU, 6, 2, SEW_32, 55);
      Write_Element (VU, 6, 3, SEW_32, 55);
      VSLIDEUP_VX (VU, Vd => 6, Vs2 => 1, Rs1 => 2, VM => True);
      Check (Read_Element (VU, 6, 0, SEW_32) = 55,
             "vslideup.vx 2 [0] unchanged");
      Check (Read_Element (VU, 6, 1, SEW_32) = 55,
             "vslideup.vx 2 [1] unchanged");
      Check (Read_Element (VU, 6, 2, SEW_32) = 10,
             "vslideup.vx 2 [2] = src[0]");
      Check (Read_Element (VU, 6, 3, SEW_32) = 20,
             "vslideup.vx 2 [3] = src[1]");
   end Test_Slide;

   --  Test gather operations
   procedure Test_Gather is
      VU : Vector_State;
   begin
      Put_Line ("Testing gather operations...");

      Setup_VU_32 (VU);

      --  v1 = {100, 200, 300, 400} (source data)
      Write_Element (VU, 1, 0, SEW_32, 100);
      Write_Element (VU, 1, 1, SEW_32, 200);
      Write_Element (VU, 1, 2, SEW_32, 300);
      Write_Element (VU, 1, 3, SEW_32, 400);

      --  v2 = {3, 0, 2, 1} (indices)
      Write_Element (VU, 2, 0, SEW_32, 3);
      Write_Element (VU, 2, 1, SEW_32, 0);
      Write_Element (VU, 2, 2, SEW_32, 2);
      Write_Element (VU, 2, 3, SEW_32, 1);

      --  vrgather.vv v3, v1, v2: reverse/permute
      VRGATHER_VV (VU, Vd => 3, Vs2 => 1, Vs1 => 2, VM => True);
      Check (Read_Element (VU, 3, 0, SEW_32) = 400,
             "vrgather.vv [0] = src[3] = 400");
      Check (Read_Element (VU, 3, 1, SEW_32) = 100,
             "vrgather.vv [1] = src[0] = 100");
      Check (Read_Element (VU, 3, 2, SEW_32) = 300,
             "vrgather.vv [2] = src[2] = 300");
      Check (Read_Element (VU, 3, 3, SEW_32) = 200,
             "vrgather.vv [3] = src[1] = 200");

      --  vrgather.vx v4, v1, 2: broadcast element 2
      VRGATHER_VX (VU, Vd => 4, Vs2 => 1, Rs1 => 2, VM => True);
      Check (Read_Element (VU, 4, 0, SEW_32) = 300,
             "vrgather.vx [0] = src[2] = 300");
      Check (Read_Element (VU, 4, 1, SEW_32) = 300,
             "vrgather.vx [1] = src[2] = 300");
      Check (Read_Element (VU, 4, 2, SEW_32) = 300,
             "vrgather.vx [2] = src[2] = 300");
      Check (Read_Element (VU, 4, 3, SEW_32) = 300,
             "vrgather.vx [3] = src[2] = 300");

      --  vrgather.vi v5, v1, 1: broadcast element 1
      VRGATHER_VI (VU, Vd => 5, Vs2 => 1, Imm => 1, VM => True);
      Check (Read_Element (VU, 5, 0, SEW_32) = 200,
             "vrgather.vi [0] = src[1] = 200");

      --  Out-of-range index => 0
      Write_Element (VU, 6, 0, SEW_32, 10);  -- in range
      Write_Element (VU, 6, 1, SEW_32, 10);  -- in range
      VRGATHER_VX (VU, Vd => 7, Vs2 => 1, Rs1 => 99, VM => True);
      Check (Read_Element (VU, 7, 0, SEW_32) = 0,
             "vrgather.vx out-of-range = 0");
   end Test_Gather;

   --  Test compress
   procedure Test_Compress is
      VU : Vector_State;
   begin
      Put_Line ("Testing compress...");

      Setup_VU_32 (VU);

      --  v2 = {10, 20, 30, 40} (source)
      Write_Element (VU, 2, 0, SEW_32, 10);
      Write_Element (VU, 2, 1, SEW_32, 20);
      Write_Element (VU, 2, 2, SEW_32, 30);
      Write_Element (VU, 2, 3, SEW_32, 40);

      --  v0 (mask) = 0b0101 => elements 0 and 2 active
      VU.Registers (0).Data := (others => 0);
      VU.Registers (0).Data (0) := 16#05#;

      --  vcompress.vm v3, v2, v0: pack active elements
      VCOMPRESS_VM (VU, Vd => 3, Vs2 => 2, Vs1 => 0);
      Check (Read_Element (VU, 3, 0, SEW_32) = 10,
             "vcompress [0] = 10 (element 0)");
      Check (Read_Element (VU, 3, 1, SEW_32) = 30,
             "vcompress [1] = 30 (element 2)");

      --  All active: 0b1111
      VU.Registers (0).Data (0) := 16#0F#;
      VCOMPRESS_VM (VU, Vd => 4, Vs2 => 2, Vs1 => 0);
      Check (Read_Element (VU, 4, 0, SEW_32) = 10,
             "vcompress all [0] = 10");
      Check (Read_Element (VU, 4, 1, SEW_32) = 20,
             "vcompress all [1] = 20");
      Check (Read_Element (VU, 4, 2, SEW_32) = 30,
             "vcompress all [2] = 30");
      Check (Read_Element (VU, 4, 3, SEW_32) = 40,
             "vcompress all [3] = 40");
   end Test_Compress;

   --  Test integer multiply-add
   procedure Test_MACC is
      VU : Vector_State;
   begin
      Put_Line ("Testing integer multiply-add...");

      Setup_VU_32 (VU);

      --  v1 = {2, 3, 4, 5}, v2 = {10, 20, 30, 40}
      Write_Element (VU, 1, 0, SEW_32, 2);
      Write_Element (VU, 1, 1, SEW_32, 3);
      Write_Element (VU, 1, 2, SEW_32, 4);
      Write_Element (VU, 1, 3, SEW_32, 5);
      Write_Element (VU, 2, 0, SEW_32, 10);
      Write_Element (VU, 2, 1, SEW_32, 20);
      Write_Element (VU, 2, 2, SEW_32, 30);
      Write_Element (VU, 2, 3, SEW_32, 40);

      --  vmacc.vv: vd = vs1*vs2 + vd
      --  vd = {1, 1, 1, 1} initially
      Write_Element (VU, 3, 0, SEW_32, 1);
      Write_Element (VU, 3, 1, SEW_32, 1);
      Write_Element (VU, 3, 2, SEW_32, 1);
      Write_Element (VU, 3, 3, SEW_32, 1);
      VMACC_VV (VU, Vd => 3, Vs1 => 1, Vs2 => 2, VM => True);
      Check (Read_Element (VU, 3, 0, SEW_32) = 21,
             "vmacc.vv [0] = 2*10+1 = 21");
      Check (Read_Element (VU, 3, 1, SEW_32) = 61,
             "vmacc.vv [1] = 3*20+1 = 61");
      Check (Read_Element (VU, 3, 2, SEW_32) = 121,
             "vmacc.vv [2] = 4*30+1 = 121");
      Check (Read_Element (VU, 3, 3, SEW_32) = 201,
             "vmacc.vv [3] = 5*40+1 = 201");

      --  vmacc.vx: vd = rs1*vs2 + vd
      Write_Element (VU, 4, 0, SEW_32, 5);
      Write_Element (VU, 4, 1, SEW_32, 5);
      VMACC_VX (VU, Vd => 4, Rs1 => 3, Vs2 => 2, VM => True);
      Check (Read_Element (VU, 4, 0, SEW_32) = 35,
             "vmacc.vx [0] = 3*10+5 = 35");
      Check (Read_Element (VU, 4, 1, SEW_32) = 65,
             "vmacc.vx [1] = 3*20+5 = 65");

      --  vnmsac.vv: vd = vd - vs1*vs2
      Write_Element (VU, 5, 0, SEW_32, 100);
      Write_Element (VU, 5, 1, SEW_32, 200);
      VNMSAC_VV (VU, Vd => 5, Vs1 => 1, Vs2 => 2, VM => True);
      Check (Read_Element (VU, 5, 0, SEW_32) = 80,
             "vnmsac.vv [0] = 100-2*10 = 80");
      Check (Read_Element (VU, 5, 1, SEW_32) = 140,
             "vnmsac.vv [1] = 200-3*20 = 140");

      --  vmadd.vv: vd = vs1*vd + vs2
      Write_Element (VU, 6, 0, SEW_32, 10);
      Write_Element (VU, 6, 1, SEW_32, 20);
      VMADD_VV (VU, Vd => 6, Vs1 => 1, Vs2 => 2, VM => True);
      Check (Read_Element (VU, 6, 0, SEW_32) = 30,
             "vmadd.vv [0] = 2*10+10 = 30");
      Check (Read_Element (VU, 6, 1, SEW_32) = 80,
             "vmadd.vv [1] = 3*20+20 = 80");

      --  vnmsub.vv: vd = vs2 - vs1*vd
      Write_Element (VU, 7, 0, SEW_32, 5);
      Write_Element (VU, 7, 1, SEW_32, 10);
      VNMSUB_VV (VU, Vd => 7, Vs1 => 1, Vs2 => 2, VM => True);
      Check (Read_Element (VU, 7, 0, SEW_32) = 0,
             "vnmsub.vv [0] = 10-2*5 = 0");
      Check (Read_Element (VU, 7, 1, SEW_32) = Word'Last - 9,
             "vnmsub.vv [1] = 20-3*10 wraps");
   end Test_MACC;

   --  Test integer extension
   procedure Test_Extension is
      VU : Vector_State;
      VL : Word;
   begin
      Put_Line ("Testing integer extension...");

      Setup_VU_32 (VU);

      --  vzext.vf2: zero-extend SEW/2 to SEW
      --  With SEW=32, source is SEW=16
      Write_Element (VU, 1, 0, SEW_16, 16#ABCD#);
      Write_Element (VU, 1, 1, SEW_16, 16#0001#);
      Write_Element (VU, 1, 2, SEW_16, 16#FFFF#);
      Write_Element (VU, 1, 3, SEW_16, 16#8000#);

      VZEXT_VF2 (VU, Vd => 2, Vs2 => 1, VM => True);
      Check (Read_Element (VU, 2, 0, SEW_32) = 16#ABCD#,
             "vzext.vf2 [0] = 0xABCD");
      Check (Read_Element (VU, 2, 1, SEW_32) = 16#0001#,
             "vzext.vf2 [1] = 0x0001");
      Check (Read_Element (VU, 2, 2, SEW_32) = 16#FFFF#,
             "vzext.vf2 [2] = 0xFFFF");
      Check (Read_Element (VU, 2, 3, SEW_32) = 16#8000#,
             "vzext.vf2 [3] = 0x8000");

      --  vsext.vf2: sign-extend SEW/2 to SEW
      VSEXT_VF2 (VU, Vd => 3, Vs2 => 1, VM => True);
      Check (Read_Element (VU, 3, 0, SEW_32) = 16#FFFFABCD#,
             "vsext.vf2 [0] sign ext 0xABCD");
      Check (Read_Element (VU, 3, 1, SEW_32) = 16#0001#,
             "vsext.vf2 [1] positive 0x0001");
      Check (Read_Element (VU, 3, 2, SEW_32) = 16#FFFFFFFF#,
             "vsext.vf2 [2] sign ext 0xFFFF");
      Check (Read_Element (VU, 3, 3, SEW_32) = 16#FFFF8000#,
             "vsext.vf2 [3] sign ext 0x8000");

      --  vzext.vf4: zero-extend SEW/4 to SEW (8->32)
      Write_Element (VU, 4, 0, SEW_8, 16#AB#);
      Write_Element (VU, 4, 1, SEW_8, 16#01#);
      Write_Element (VU, 4, 2, SEW_8, 16#FF#);
      Write_Element (VU, 4, 3, SEW_8, 16#80#);

      VZEXT_VF4 (VU, Vd => 5, Vs2 => 4, VM => True);
      Check (Read_Element (VU, 5, 0, SEW_32) = 16#AB#,
             "vzext.vf4 [0] = 0xAB");
      Check (Read_Element (VU, 5, 2, SEW_32) = 16#FF#,
             "vzext.vf4 [2] = 0xFF");

      --  vsext.vf4: sign-extend SEW/4 to SEW (8->32)
      VSEXT_VF4 (VU, Vd => 6, Vs2 => 4, VM => True);
      Check (Read_Element (VU, 6, 0, SEW_32) = 16#FFFFFFAB#,
             "vsext.vf4 [0] sign ext 0xAB");
      Check (Read_Element (VU, 6, 1, SEW_32) = 16#01#,
             "vsext.vf4 [1] positive 0x01");
      Check (Read_Element (VU, 6, 2, SEW_32) = 16#FFFFFFFF#,
             "vsext.vf4 [2] sign ext 0xFF");
      Check (Read_Element (VU, 6, 3, SEW_32) = 16#FFFFFF80#,
             "vsext.vf4 [3] sign ext 0x80");

      --  Test with SEW=16, vzext.vf2 (8->16)
      Initialize (VU);
      VL := Vsetvl (VU, 4, 16#C8#);  -- e16, m1, ta, ma
      pragma Unreferenced (VL);

      Write_Element (VU, 1, 0, SEW_8, 16#80#);
      Write_Element (VU, 1, 1, SEW_8, 16#7F#);

      VZEXT_VF2 (VU, Vd => 2, Vs2 => 1, VM => True);
      Check (Read_Element (VU, 2, 0, SEW_16) = 16#80#,
             "vzext.vf2 e16 [0] = 0x80");
      Check (Read_Element (VU, 2, 1, SEW_16) = 16#7F#,
             "vzext.vf2 e16 [1] = 0x7F");

      VSEXT_VF2 (VU, Vd => 3, Vs2 => 1, VM => True);
      Check (Read_Element (VU, 3, 0, SEW_16) = 16#FF80#,
             "vsext.vf2 e16 [0] sign ext 0x80");
      Check (Read_Element (VU, 3, 1, SEW_16) = 16#7F#,
             "vsext.vf2 e16 [1] positive 0x7F");
   end Test_Extension;

   --  Test widening .w variants
   procedure Test_Widening_W is
      VU : Vector_State;
   begin
      Put_Line ("Testing widening .w variants...");
      Setup_VU_32 (VU);
      --  v2 = wide (2xSEW=64): {100, 200}
      Write_Element_64 (VU, 2, 0, 100);
      Write_Element_64 (VU, 2, 1, 200);
      --  v1 = narrow (SEW=32): {10, 20, 30, 40}
      Write_Element (VU, 1, 0, SEW_32, 10);
      Write_Element (VU, 1, 1, SEW_32, 20);

      --  vwadd.wv: wide + sign-extend(narrow)
      VWADDW_VV (VU, Vd => 4, Vs2 => 2, Vs1 => 1, VM => True);
      Check (Read_Element_64 (VU, 4, 0) = 110,
             "vwadd.wv [0] = 100+10 = 110");
      Check (Read_Element_64 (VU, 4, 1) = 220,
             "vwadd.wv [1] = 200+20 = 220");

      --  vwaddu.wv: wide + zero-extend(narrow)
      VWADDUW_VV (VU, Vd => 6, Vs2 => 2, Vs1 => 1, VM => True);
      Check (Read_Element_64 (VU, 6, 0) = 110,
             "vwaddu.wv [0] = 100+10 = 110");

      --  vwsub.wv: wide - sign-extend(narrow)
      VWSUBW_VV (VU, Vd => 8, Vs2 => 2, Vs1 => 1, VM => True);
      Check (Read_Element_64 (VU, 8, 0) = 90,
             "vwsub.wv [0] = 100-10 = 90");
      Check (Read_Element_64 (VU, 8, 1) = 180,
             "vwsub.wv [1] = 200-20 = 180");

      --  vwsub.wx: wide - sign-extend(scalar)
      VWSUBW_VX (VU, Vd => 10, Vs2 => 2, Rs1 => 5, VM => True);
      Check (Read_Element_64 (VU, 10, 0) = 95,
             "vwsub.wx [0] = 100-5 = 95");
   end Test_Widening_W;

   --  Test carry/borrow operations
   procedure Test_Carry_Borrow is
      VU : Vector_State;
   begin
      Put_Line ("Testing carry/borrow ops...");
      Setup_VU_32 (VU);
      --  v2 = {10, 20, 30, 40}
      Write_Element (VU, 2, 0, SEW_32, 10);
      Write_Element (VU, 2, 1, SEW_32, 20);
      Write_Element (VU, 2, 2, SEW_32, 30);
      Write_Element (VU, 2, 3, SEW_32, 40);
      --  v1 = {5, 10, 15, 20}
      Write_Element (VU, 1, 0, SEW_32, 5);
      Write_Element (VU, 1, 1, SEW_32, 10);
      Write_Element (VU, 1, 2, SEW_32, 15);
      Write_Element (VU, 1, 3, SEW_32, 20);
      --  v0 mask = {1, 0, 1, 0} (carry bits)
      Set_Mask_Bit (VU, 0, 0, True);
      Set_Mask_Bit (VU, 0, 1, False);
      Set_Mask_Bit (VU, 0, 2, True);
      Set_Mask_Bit (VU, 0, 3, False);

      --  vadc.vvm: vd = vs2 + vs1 + carry
      VADC_VVM (VU, Vd => 3, Vs2 => 2, Vs1 => 1);
      Check (Read_Element (VU, 3, 0, SEW_32) = 16,
             "vadc.vvm [0] = 10+5+1 = 16");
      Check (Read_Element (VU, 3, 1, SEW_32) = 30,
             "vadc.vvm [1] = 20+10+0 = 30");
      Check (Read_Element (VU, 3, 2, SEW_32) = 46,
             "vadc.vvm [2] = 30+15+1 = 46");

      --  vadc.vxm
      VADC_VXM (VU, Vd => 4, Vs2 => 2, Rs1 => 100);
      Check (Read_Element (VU, 4, 0, SEW_32) = 111,
             "vadc.vxm [0] = 10+100+1 = 111");
      Check (Read_Element (VU, 4, 1, SEW_32) = 120,
             "vadc.vxm [1] = 20+100+0 = 120");

      --  vsbc.vvm: vd = vs2 - vs1 - borrow
      VSBC_VVM (VU, Vd => 5, Vs2 => 2, Vs1 => 1);
      Check (Read_Element (VU, 5, 0, SEW_32) = 4,
             "vsbc.vvm [0] = 10-5-1 = 4");
      Check (Read_Element (VU, 5, 1, SEW_32) = 10,
             "vsbc.vvm [1] = 20-10-0 = 10");

      --  vmadc.vvm: carry out from add with carry in
      VMADC_VVM (VU, Vd => 6, Vs2 => 2, Vs1 => 1, VM => False);
      --  10+5+1=16, no carry -> 0
      Check (not Read_Mask_Bit (VU, 6, 0),
             "vmadc.vvm [0] no carry");

      --  Test vmadc with overflow
      Write_Element (VU, 7, 0, SEW_32, Word'Last);
      Write_Element (VU, 8, 0, SEW_32, 1);
      Set_Mask_Bit (VU, 0, 0, False);
      VMADC_VVM (VU, Vd => 9, Vs2 => 7, Vs1 => 8, VM => False);
      Check (Read_Mask_Bit (VU, 9, 0),
             "vmadc.vvm overflow carry = 1");
   end Test_Carry_Borrow;

   --  Test saturating operations
   procedure Test_Saturating is
      VU : Vector_State;
   begin
      Put_Line ("Testing saturating ops...");
      Setup_VU_32 (VU);

      --  vsaddu: unsigned saturating add
      Write_Element (VU, 1, 0, SEW_32, Word'Last - 5);
      Write_Element (VU, 1, 1, SEW_32, 100);
      Write_Element (VU, 2, 0, SEW_32, 10);
      Write_Element (VU, 2, 1, SEW_32, 50);

      VU.VXSat := False;
      VSADDU_VV (VU, Vd => 3, Vs2 => 1, Vs1 => 2, VM => True);
      Check (Read_Element (VU, 3, 0, SEW_32) = Word'Last,
             "vsaddu.vv [0] saturates to max");
      Check (Read_Element (VU, 3, 1, SEW_32) = 150,
             "vsaddu.vv [1] = 100+50 = 150");
      Check (VU.VXSat, "vsaddu.vv sets VXSat on saturation");

      --  vssubu: unsigned saturating subtract
      Write_Element (VU, 4, 0, SEW_32, 10);
      Write_Element (VU, 4, 1, SEW_32, 100);
      Write_Element (VU, 5, 0, SEW_32, 20);
      Write_Element (VU, 5, 1, SEW_32, 50);

      VU.VXSat := False;
      VSSUBU_VV (VU, Vd => 6, Vs2 => 4, Vs1 => 5, VM => True);
      Check (Read_Element (VU, 6, 0, SEW_32) = 0,
             "vssubu.vv [0] saturates to 0");
      Check (Read_Element (VU, 6, 1, SEW_32) = 50,
             "vssubu.vv [1] = 100-50 = 50");

      --  vsadd.vi: signed saturating add immediate
      Write_Element (VU, 7, 0, SEW_32, 16#7FFFFFFF#);  --  INT_MAX
      VU.VXSat := False;
      VSADD_VI (VU, Vd => 8, Vs2 => 7, Imm => 5, VM => True);
      Check (Read_Element (VU, 8, 0, SEW_32) = 16#7FFFFFFF#,
             "vsadd.vi saturates at INT_MAX");
   end Test_Saturating;

   --  Test VSMUL and rounding shifts
   procedure Test_VSMUL_Rounding is
      VU : Vector_State;
   begin
      Put_Line ("Testing VSMUL and rounding shifts...");
      Setup_VU_32 (VU);

      --  vssrl: rounding shift right logical
      Write_Element (VU, 1, 0, SEW_32, 7);   -- 0111 >> 1 = 3 (round nearest)
      Write_Element (VU, 1, 1, SEW_32, 16);  -- 10000 >> 1 = 8
      VU.VXRM := 0;  --  round-to-nearest-up
      VSSRL_VI (VU, Vd => 2, Vs2 => 1, Imm => 1, VM => True);
      Check (Read_Element (VU, 2, 0, SEW_32) = 4,
             "vssrl.vi [0] 7>>1 rnu = 4");
      Check (Read_Element (VU, 2, 1, SEW_32) = 8,
             "vssrl.vi [1] 16>>1 rnu = 8");

      --  vssra: rounding shift right arithmetic
      --  -7 (0xFFFFFFF9) >> 1 arithmetic = -3 with round
      Write_Element (VU, 3, 0, SEW_32,
                     To_Word (Signed_Word'(-7)));
      VU.VXRM := 0;
      VSSRA_VI (VU, Vd => 4, Vs2 => 3, Imm => 1, VM => True);
      Check (Read_Element (VU, 4, 0, SEW_32) =
             To_Word (Signed_Word'(-3)),
             "vssra.vi -7>>1 rnu = -3");
   end Test_VSMUL_Rounding;

   --  Test narrowing clip
   procedure Test_Narrowing_Clip is
      VU : Vector_State;
   begin
      Put_Line ("Testing narrowing clip...");
      Setup_VU_32 (VU);

      --  vnclipu: narrow unsigned clip
      --  Source is 2xSEW (64-bit), result is SEW (32-bit)
      Write_Element_64 (VU, 2, 0, 100);
      Write_Element_64 (VU, 2, 1, Unsigned_64 (Word'Last) + 10);
      VU.VXRM := 0;
      VU.VXSat := False;
      VNCLIPU_WI (VU, Vd => 4, Vs2 => 2, Imm => 0, VM => True);
      Check (Read_Element (VU, 4, 0, SEW_32) = 100,
             "vnclipu.wi [0] = 100 (fits)");
      Check (Read_Element (VU, 4, 1, SEW_32) = Word'Last,
             "vnclipu.wi [1] saturates to max");
      Check (VU.VXSat,
             "vnclipu sets VXSat on clip");

      --  vnclip: narrow signed clip
      Write_Element_64 (VU, 6, 0, 50);
      Write_Element_64 (VU, 6, 1, Unsigned_64'(16#0000000100000000#));
      VU.VXSat := False;
      VNCLIP_WI (VU, Vd => 8, Vs2 => 6, Imm => 0, VM => True);
      Check (Read_Element (VU, 8, 0, SEW_32) = 50,
             "vnclip.wi [0] = 50 (fits signed)");
      Check (Read_Element (VU, 8, 1, SEW_32) = 16#7FFFFFFF#,
             "vnclip.wi [1] saturates to signed max");
   end Test_Narrowing_Clip;

   --  Test widening multiply-add
   procedure Test_Widening_MACC is
      VU : Vector_State;
   begin
      Put_Line ("Testing widening MAC...");
      Setup_VU_32 (VU);

      --  v1 = {3, 5}, v2 = {10, 20}
      Write_Element (VU, 1, 0, SEW_32, 3);
      Write_Element (VU, 1, 1, SEW_32, 5);
      Write_Element (VU, 2, 0, SEW_32, 10);
      Write_Element (VU, 2, 1, SEW_32, 20);
      --  vd (64-bit) = {100, 200}
      Write_Element_64 (VU, 4, 0, 100);
      Write_Element_64 (VU, 4, 1, 200);

      --  vwmaccu.vv: vd(2xSEW) += vs1(SEW) * vs2(SEW)
      VWMACCU_VV (VU, Vd => 4, Vs1 => 1, Vs2 => 2, VM => True);
      Check (Read_Element_64 (VU, 4, 0) = 130,
             "vwmaccu.vv [0] = 100 + 3*10 = 130");
      Check (Read_Element_64 (VU, 4, 1) = 300,
             "vwmaccu.vv [1] = 200 + 5*20 = 300");

      --  vwmacc.vx
      Write_Element_64 (VU, 6, 0, 50);
      VWMACC_VX (VU, Vd => 6, Rs1 => 7, Vs2 => 2, VM => True);
      Check (Read_Element_64 (VU, 6, 0) = 120,
             "vwmacc.vx [0] = 50 + 7*10 = 120");
   end Test_Widening_MACC;

   --  Test VMULHSU
   procedure Test_VMULHSU is
      VU : Vector_State;
   begin
      Put_Line ("Testing vmulhsu...");
      Setup_VU_32 (VU);

      --  signed * unsigned high: -1 * 2 = -2, high word
      Write_Element (VU, 1, 0, SEW_32,
                     To_Word (Signed_Word'(-1)));
      Write_Element (VU, 2, 0, SEW_32, 2);
      VMULHSU_VV (VU, Vd => 3, Vs2 => 1, Vs1 => 2, VM => True);
      --  -1 * 2 = -2, high 32 bits = 0xFFFFFFFF
      Check (Read_Element (VU, 3, 0, SEW_32) = Word'Last,
             "vmulhsu.vv -1*2 high = -1");

      --  3 * 2 = 6, high word = 0
      Write_Element (VU, 4, 0, SEW_32, 3);
      VMULHSU_VV (VU, Vd => 5, Vs2 => 4, Vs1 => 2, VM => True);
      Check (Read_Element (VU, 5, 0, SEW_32) = 0,
             "vmulhsu.vv 3*2 high = 0");
   end Test_VMULHSU;

   --  Test averaging add/sub
   procedure Test_Averaging is
      VU : Vector_State;
   begin
      Put_Line ("Testing averaging ops...");
      Setup_VU_32 (VU);
      VU.VXRM := 0;  -- round-to-nearest-up

      Write_Element (VU, 1, 0, SEW_32, 10);
      Write_Element (VU, 1, 1, SEW_32, 11);
      Write_Element (VU, 2, 0, SEW_32, 20);
      Write_Element (VU, 2, 1, SEW_32, 21);

      --  vaaddu: (vs2 + vs1 + round) >> 1
      VAADDU_VV (VU, Vd => 3, Vs2 => 1, Vs1 => 2, VM => True);
      Check (Read_Element (VU, 3, 0, SEW_32) = 15,
             "vaaddu.vv [0] = (10+20)/2 = 15");
      Check (Read_Element (VU, 3, 1, SEW_32) = 16,
             "vaaddu.vv [1] = (11+21+1)/2 = 16 rnu");

      --  vasubu: (vs2 - vs1 + round) >> 1
      VASUBU_VV (VU, Vd => 4, Vs2 => 2, Vs1 => 1, VM => True);
      Check (Read_Element (VU, 4, 0, SEW_32) = 5,
             "vasubu.vv [0] = (20-10)/2 = 5");
   end Test_Averaging;

   --  Test FP comparison
   procedure Test_FP_Comparison is
      VU : Vector_State;
      FP : aliased RISCV.FPU.FPU_State;
      FP_Ptr : constant FPU_Access := FP'Unchecked_Access;
   begin
      Put_Line ("Testing FP comparison...");
      Setup_VU_32 (VU);
      RISCV.FPU.Initialize (FP);

      --  v2 = {1.0, 2.0, 3.0, 4.0}
      Write_Element (VU, 2, 0, SEW_32, 16#3F800000#);  -- 1.0
      Write_Element (VU, 2, 1, SEW_32, 16#40000000#);  -- 2.0
      Write_Element (VU, 2, 2, SEW_32, 16#40400000#);  -- 3.0
      Write_Element (VU, 2, 3, SEW_32, 16#40800000#);  -- 4.0
      --  v1 = {1.0, 3.0, 2.0, 4.0}
      Write_Element (VU, 1, 0, SEW_32, 16#3F800000#);  -- 1.0
      Write_Element (VU, 1, 1, SEW_32, 16#40400000#);  -- 3.0
      Write_Element (VU, 1, 2, SEW_32, 16#40000000#);  -- 2.0
      Write_Element (VU, 1, 3, SEW_32, 16#40800000#);  -- 4.0

      --  vmfeq.vv
      VMFEQ_VV (VU, FP_Ptr, 3, 2, 1, True);
      Check (Read_Mask_Bit (VU, 3, 0),
             "vmfeq.vv [0] 1.0==1.0 = true");
      Check (not Read_Mask_Bit (VU, 3, 1),
             "vmfeq.vv [1] 2.0==3.0 = false");
      Check (Read_Mask_Bit (VU, 3, 3),
             "vmfeq.vv [3] 4.0==4.0 = true");

      --  vmflt.vv
      VMFLT_VV (VU, FP_Ptr, 4, 2, 1, True);
      Check (not Read_Mask_Bit (VU, 4, 0),
             "vmflt.vv [0] 1.0<1.0 = false");
      Check (Read_Mask_Bit (VU, 4, 1),
             "vmflt.vv [1] 2.0<3.0 = true");
      Check (not Read_Mask_Bit (VU, 4, 2),
             "vmflt.vv [2] 3.0<2.0 = false");

      --  vmfle.vv
      VMFLE_VV (VU, FP_Ptr, 5, 2, 1, True);
      Check (Read_Mask_Bit (VU, 5, 0),
             "vmfle.vv [0] 1.0<=1.0 = true");
      Check (Read_Mask_Bit (VU, 5, 1),
             "vmfle.vv [1] 2.0<=3.0 = true");

      --  vmfne.vv
      VMFNE_VV (VU, FP_Ptr, 6, 2, 1, True);
      Check (not Read_Mask_Bit (VU, 6, 0),
             "vmfne.vv [0] 1.0!=1.0 = false");
      Check (Read_Mask_Bit (VU, 6, 1),
             "vmfne.vv [1] 2.0!=3.0 = true");

      --  vmfgt.vf: vs2[i] > fs1
      RISCV.FPU.Write_Single (FP, 1, 16#40000000#);  -- f1=2.0
      VMFGT_VF (VU, FP_Ptr, 7, 2, 16#40000000#, True);
      Check (not Read_Mask_Bit (VU, 7, 0),
             "vmfgt.vf [0] 1.0>2.0 = false");
      Check (not Read_Mask_Bit (VU, 7, 1),
             "vmfgt.vf [1] 2.0>2.0 = false");
      Check (Read_Mask_Bit (VU, 7, 2),
             "vmfgt.vf [2] 3.0>2.0 = true");
   end Test_FP_Comparison;

   --  Test FP sign injection
   procedure Test_FP_Sign_Inject is
      VU : Vector_State;
      FP : aliased RISCV.FPU.FPU_State;
      FP_Ptr : constant FPU_Access := FP'Unchecked_Access;
   begin
      Put_Line ("Testing FP sign injection...");
      Setup_VU_32 (VU);
      RISCV.FPU.Initialize (FP);

      --  v2 = {1.0, -2.0}
      Write_Element (VU, 2, 0, SEW_32, 16#3F800000#);   -- 1.0
      Write_Element (VU, 2, 1, SEW_32, 16#C0000000#);   -- -2.0
      --  v1 = {-1.0, 3.0}
      Write_Element (VU, 1, 0, SEW_32, 16#BF800000#);   -- -1.0
      Write_Element (VU, 1, 1, SEW_32, 16#40400000#);   -- 3.0

      --  vfsgnj: sign of vs1
      VFSGNJ_VV (VU, FP_Ptr, 3, 2, 1, True);
      Check (Read_Element (VU, 3, 0, SEW_32) = 16#BF800000#,
             "vfsgnj.vv [0] 1.0 with sign(-1.0) = -1.0");
      Check (Read_Element (VU, 3, 1, SEW_32) = 16#40000000#,
             "vfsgnj.vv [1] -2.0 with sign(3.0) = 2.0");

      --  vfsgnjn: negated sign of vs1
      VFSGNJN_VV (VU, FP_Ptr, 4, 2, 1, True);
      Check (Read_Element (VU, 4, 0, SEW_32) = 16#3F800000#,
             "vfsgnjn.vv [0] 1.0 with neg sign(-1.0) = 1.0");

      --  vfsgnjx: xor signs
      VFSGNJX_VV (VU, FP_Ptr, 5, 2, 1, True);
      Check (Read_Element (VU, 5, 0, SEW_32) = 16#BF800000#,
             "vfsgnjx.vv [0] sign xor = negative");
   end Test_FP_Sign_Inject;

   --  Test FP conversion
   procedure Test_FP_Conversion is
      VU : Vector_State;
      FP : aliased RISCV.FPU.FPU_State;
      FP_Ptr : constant FPU_Access := FP'Unchecked_Access;
   begin
      Put_Line ("Testing FP conversion...");
      Setup_VU_32 (VU);
      RISCV.FPU.Initialize (FP);

      --  vfcvt.x.f.v: float to signed int
      Write_Element (VU, 1, 0, SEW_32, 16#40A00000#);  -- 5.0
      Write_Element (VU, 1, 1, SEW_32, 16#C0000000#);  -- -2.0
      VFCVT_X_F_V (VU, FP_Ptr, 2, 1, True);
      Check (Read_Element (VU, 2, 0, SEW_32) = 5,
             "vfcvt.x.f.v [0] 5.0 -> 5");
      Check (Read_Element (VU, 2, 1, SEW_32) =
             To_Word (Signed_Word'(-2)),
             "vfcvt.x.f.v [1] -2.0 -> -2");

      --  vfcvt.f.x.v: signed int to float
      Write_Element (VU, 3, 0, SEW_32, 3);
      Write_Element (VU, 3, 1, SEW_32,
                     To_Word (Signed_Word'(-7)));
      VFCVT_F_X_V (VU, FP_Ptr, 4, 3, True);
      Check (Read_Element (VU, 4, 0, SEW_32) = 16#40400000#,
             "vfcvt.f.x.v [0] 3 -> 3.0");
      Check (Read_Element (VU, 4, 1, SEW_32) = 16#C0E00000#,
             "vfcvt.f.x.v [1] -7 -> -7.0");

      --  vfcvt.xu.f.v: float to unsigned int
      Write_Element (VU, 5, 0, SEW_32, 16#40A00000#);  -- 5.0
      VFCVT_XU_F_V (VU, FP_Ptr, 6, 5, True);
      Check (Read_Element (VU, 6, 0, SEW_32) = 5,
             "vfcvt.xu.f.v [0] 5.0 -> 5");

      --  vfcvt.f.xu.v: unsigned int to float
      Write_Element (VU, 7, 0, SEW_32, 10);
      VFCVT_F_XU_V (VU, FP_Ptr, 8, 7, True);
      Check (Read_Element (VU, 8, 0, SEW_32) = 16#41200000#,
             "vfcvt.f.xu.v [0] 10 -> 10.0");
   end Test_FP_Conversion;

   --  Test FP widening arithmetic
   procedure Test_FP_Widening is
      VU : Vector_State;
      FP : aliased RISCV.FPU.FPU_State;
      FP_Ptr : constant FPU_Access := FP'Unchecked_Access;
   begin
      Put_Line ("Testing FP widening arithmetic...");
      Setup_VU_32 (VU);
      RISCV.FPU.Initialize (FP);

      --  v1 = {1.0f, 2.0f}, v2 = {3.0f, 4.0f}
      Write_Element (VU, 1, 0, SEW_32, 16#3F800000#);  -- 1.0
      Write_Element (VU, 1, 1, SEW_32, 16#40000000#);  -- 2.0
      Write_Element (VU, 2, 0, SEW_32, 16#40400000#);  -- 3.0
      Write_Element (VU, 2, 1, SEW_32, 16#40800000#);  -- 4.0

      --  vfwadd.vv: widen both, add as double
      --  1.0+3.0=4.0 as double = 0x4010000000000000
      VFWADD_VV (VU, FP_Ptr, 4, 2, 1, True);
      Check (Read_Element_64 (VU, 4, 0) = 16#4010000000000000#,
             "vfwadd.vv [0] 3.0+1.0 = 4.0d");
      Check (Read_Element_64 (VU, 4, 1) = 16#4018000000000000#,
             "vfwadd.vv [1] 4.0+2.0 = 6.0d");

      --  vfwsub.vv: widen both, sub as double
      VFWSUB_VV (VU, FP_Ptr, 6, 2, 1, True);
      Check (Read_Element_64 (VU, 6, 0) = 16#4000000000000000#,
             "vfwsub.vv [0] 3.0-1.0 = 2.0d");

      --  vfwmul.vv: widen both, mul as double
      VFWMUL_VV (VU, FP_Ptr, 8, 2, 1, True);
      Check (Read_Element_64 (VU, 8, 0) = 16#4008000000000000#,
             "vfwmul.vv [0] 3.0*1.0 = 3.0d");
      Check (Read_Element_64 (VU, 8, 1) = 16#4020000000000000#,
             "vfwmul.vv [1] 4.0*2.0 = 8.0d");
   end Test_FP_Widening;

   --  Test FP reduction
   procedure Test_FP_Reduction is
      VU : Vector_State;
      FP : aliased RISCV.FPU.FPU_State;
      FP_Ptr : constant FPU_Access := FP'Unchecked_Access;
   begin
      Put_Line ("Testing FP reduction...");
      Setup_VU_32 (VU);
      RISCV.FPU.Initialize (FP);

      --  v2 = {1.0, 2.0, 3.0, 4.0}
      Write_Element (VU, 2, 0, SEW_32, 16#3F800000#);  -- 1.0
      Write_Element (VU, 2, 1, SEW_32, 16#40000000#);  -- 2.0
      Write_Element (VU, 2, 2, SEW_32, 16#40400000#);  -- 3.0
      Write_Element (VU, 2, 3, SEW_32, 16#40800000#);  -- 4.0
      --  v1[0] = 0.0 (initial accumulator)
      Write_Element (VU, 1, 0, SEW_32, 0);

      --  vfredosum: ordered sum = 0+1+2+3+4 = 10.0
      VFREDOSUM_VS (VU, FP_Ptr, 3, 2, 1, True);
      Check (Read_Element (VU, 3, 0, SEW_32) = 16#41200000#,
             "vfredosum 0+1+2+3+4 = 10.0");

      --  vfredmin: min = 1.0
      Write_Element (VU, 1, 0, SEW_32, 16#7F800000#);  -- +inf
      VFREDMIN_VS (VU, FP_Ptr, 4, 2, 1, True);
      Check (Read_Element (VU, 4, 0, SEW_32) = 16#3F800000#,
             "vfredmin = 1.0");

      --  vfredmax: max = 4.0
      Write_Element (VU, 1, 0, SEW_32, 0);  -- 0.0
      VFREDMAX_VS (VU, FP_Ptr, 5, 2, 1, True);
      Check (Read_Element (VU, 5, 0, SEW_32) = 16#40800000#,
             "vfredmax = 4.0");
   end Test_FP_Reduction;

   --  ------------------------------------------------------------------
   --  SEW correctness: signed operations at SEW=8/16 and all operations at
   --  SEW=64. These are the cases the old Word-based element path got wrong
   --  (it sign-extended from bit 31 and truncated 64-bit elements). Expected
   --  values are written as the raw SEW-masked bit pattern to avoid any
   --  signed/unsigned ambiguity in the check.
   --  ------------------------------------------------------------------
   procedure Test_SEW_Correctness is
      VU : Vector_State;
      VL : Word;
      pragma Unreferenced (VL);

      procedure Fill8 (Reg : Register_Index; Val : Word) is
      begin
         for I in 0 .. 3 loop Write_Element (VU, Reg, I, SEW_8, Val); end loop;
      end Fill8;
      procedure Fill16 (Reg : Register_Index; Val : Word) is
      begin
         for I in 0 .. 3 loop Write_Element (VU, Reg, I, SEW_16, Val); end loop;
      end Fill16;
      procedure Fill64 (Reg : Register_Index; Val : Unsigned_64) is
      begin
         for I in 0 .. 1 loop Write_Element_64 (VU, Reg, I, Val); end loop;
      end Fill64;
      function R8  (Reg : Register_Index) return Word is (Read_Element (VU, Reg, 0, SEW_8));
      function R16 (Reg : Register_Index) return Word is (Read_Element (VU, Reg, 0, SEW_16));
      function R64 (Reg : Register_Index) return Unsigned_64 is (Read_Element_64 (VU, Reg, 0));
   begin
      Put_Line ("Testing SEW=8/16/64 correctness (signed + 64-bit)...");

      --  ---- SEW = 8 ----
      Initialize (VU); VL := Vsetvl (VU, 4, 16#C0#);
      Fill8 (1, 16#9C#);   --  -100
      Fill8 (2, 16#32#);   --   50
      Fill8 (3, 16#F8#);   --   -8
      VMIN_VV  (VU, 4, 1, 2, True); Check (R8 (4) = 16#9C#, "e8  vmin(-100,50) = -100");
      VMAX_VV  (VU, 4, 1, 2, True); Check (R8 (4) = 16#32#, "e8  vmax(-100,50) = 50");
      VMINU_VV (VU, 4, 1, 2, True); Check (R8 (4) = 16#32#, "e8  vminu(156,50) = 50");
      VMAXU_VV (VU, 4, 1, 2, True); Check (R8 (4) = 16#9C#, "e8  vmaxu(156,50) = 156");
      VSRA_VI  (VU, 4, 1, 1, True); Check (R8 (4) = 16#CE#, "e8  vsra(-100,1) = -50");
      VSRL_VI  (VU, 4, 1, 1, True); Check (R8 (4) = 78,      "e8  vsrl(156,1) = 78");
      VDIV_VV  (VU, 4, 1, 3, True); Check (R8 (4) = 12,      "e8  vdiv(-100,-8) = 12");
      VREM_VV  (VU, 4, 1, 3, True); Check (R8 (4) = 16#FC#,  "e8  vrem(-100,-8) = -4");
      VMUL_VV  (VU, 4, 1, 3, True); Check (R8 (4) = 32,      "e8  vmul(-100,-8) low = 32");
      VMULH_VV (VU, 4, 1, 3, True); Check (R8 (4) = 3,       "e8  vmulh(-100,-8) = 3");
      VMULHU_VV (VU, 4, 1, 3, True); Check (R8 (4) = 151,    "e8  vmulhu(156,248) = 151");
      VMSLT_VV  (VU, 0, 1, 2, True); Check (Get_Mask_Bit (VU, 0), "e8  vmslt(-100<50) true");
      VMSLTU_VV (VU, 0, 1, 2, True); Check (not Get_Mask_Bit (VU, 0), "e8  vmsltu(156<50) false");

      --  ---- SEW = 16 ----
      Initialize (VU); VL := Vsetvl (VU, 4, 16#C8#);
      Fill16 (1, 16#FF9C#);  --  -100
      Fill16 (2, 16#0032#);  --   50
      Fill16 (3, 16#FFF8#);  --   -8
      VMIN_VV (VU, 4, 1, 2, True); Check (R16 (4) = 16#FF9C#, "e16 vmin(-100,50) = -100");
      VSRA_VX (VU, 4, 1, 1, True); Check (R16 (4) = 16#FFCE#, "e16 vsra(-100,1) = -50");
      VDIV_VV (VU, 4, 1, 3, True); Check (R16 (4) = 12,       "e16 vdiv(-100,-8) = 12");
      VADD_VX (VU, 4, 1, 16#FFFFFFFF#, True);
      Check (R16 (4) = 16#FF9B#, "e16 vadd.vx(-100,-1) = -101 (scalar sign-extended)");

      --  ---- SEW = 64 ----
      Initialize (VU); VL := Vsetvl (VU, 2, 16#D8#);
      Fill64 (1, 16#0000_0001_0000_0000#);  --  2**32
      VADD_VV (VU, 4, 1, 1, True);
      Check (R64 (4) = 16#0000_0002_0000_0000#, "e64 vadd(2**32,2**32) = 2**33");
      VMUL_VX (VU, 4, 1, 3, True);
      Check (R64 (4) = 16#0000_0003_0000_0000#, "e64 vmul.vx(2**32,3) = 3*2**32");
      Fill64 (2, 16#FFFF_FFFF_FFFF_FFF0#);  --  -16
      VSRA_VI (VU, 4, 2, 1, True);
      Check (R64 (4) = 16#FFFF_FFFF_FFFF_FFF8#, "e64 vsra(-16,1) = -8");
      Fill64 (3, 1);
      VSLL_VX (VU, 4, 3, 40, True);
      Check (R64 (4) = 16#0000_0100_0000_0000#, "e64 vsll.vx(1,40) = 2**40");
      Fill64 (5, 16#4000_0000_0000_0000#);  --  2**62
      Fill64 (6, 4);
      VMULH_VV (VU, 4, 5, 6, True);
      Check (R64 (4) = 1, "e64 vmulh(2**62,4) = 1");
      Fill64 (7, 16#8000_0000_0000_0000#);
      Fill64 (8, 2);
      VMULHU_VV (VU, 4, 7, 8, True);
      Check (R64 (4) = 1, "e64 vmulhu(2**63,2) = 1");
      VMIN_VV (VU, 4, 2, 3, True);  --  min(-16, 1) signed
      Check (R64 (4) = 16#FFFF_FFFF_FFFF_FFF0#, "e64 vmin(-16,1) = -16");
   end Test_SEW_Correctness;

begin
   Put_Line ("=================================================");
   Put_Line ("       RISCV Emulator V Extension Tests");
   Put_Line ("=================================================");
   New_Line;

   Test_Vsetvl;
   Test_Element_Access;
   Test_VADD;
   Test_VSUB;
   Test_Bitwise;
   Test_Shifts;
   Test_Mul_Div;
   Test_Signed_Mul_Div_Rem;
   Test_MinMax;
   Test_Comparisons;
   Test_Merge_Move;
   Test_Reductions;
   Test_VID_VIOTA;
   Test_Mask_Ops;
   Test_Load_Store;
   Test_SEW8;
   Test_Masking;
   Test_Mask_Set_Ops;
   Test_Arith_Variants;
   Test_Bitwise_Variants;
   Test_Shift_Variants;
   Test_MinMax_Variants;
   Test_Comparison_Variants;
   Test_Div_Rem_VV;
   Test_Merge_Ops;
   Test_Signed_Reductions;
   Test_Mask_Logic_Variants;
   Test_Strided_Store;
   Test_VMV_NR;
   Test_Widening;
   Test_Widening_Mul;
   Test_Narrowing;
   Test_FP_Vector;
   Test_Indexed_Load_Store;
   Test_Segment_Load_Store;
   Test_Segment_Strided;
   Test_Segment_Indexed;
   Test_Whole_Register;
   Test_Slide;
   Test_Gather;
   Test_Compress;
   Test_MACC;
   Test_Extension;

   Test_Widening_W;
   Test_Carry_Borrow;
   Test_Saturating;
   Test_VSMUL_Rounding;
   Test_Narrowing_Clip;
   Test_Widening_MACC;
   Test_VMULHSU;
   Test_Averaging;
   Test_FP_Comparison;
   Test_FP_Sign_Inject;
   Test_FP_Conversion;
   Test_FP_Widening;
   Test_FP_Reduction;
   Test_SEW_Correctness;

   New_Line;
   Put_Line ("=================================================");
   Put_Line ("Test Results: " & Natural'Image (Passed_Tests)
             & " passed," & Natural'Image (Failed_Tests)
             & " failed out of" & Natural'Image (Total_Tests)
             & " tests");
   Put_Line ("=================================================");

   if Failed_Tests = 0 then
      Put_Line ("ALL TESTS PASSED!");
   end if;
end Test_Vector;
