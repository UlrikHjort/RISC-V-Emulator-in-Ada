-- ***************************************************************************
--              RISC-V Emulator - Root Package
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

with Interfaces; use Interfaces;

package RISCV is

   --  Base types for RV32
   type Word is new Unsigned_32;
   type Half_Word is new Unsigned_16;
   type Byte is new Unsigned_8;

   type Signed_Word is new Integer_32;

   --  Base types for RV64
   type Double_Word    is new Unsigned_64;
   type Signed_DWord   is new Integer_64;

   --  Register file: x0-x31 (x0 is hardwired to 0)
   type Register_Index is range 0 .. 31;
   type Register_File is array (Register_Index) of Word;

   --  RV64 register file: x0-x31 are 64-bit
   type Register_File_64 is array (Register_Index) of Double_Word;

   --  Memory size (1 MB default)
   Memory_Size : constant := 16#100000#;
   type Memory_Address is new Word;

   --  64-bit memory address (for RV64 CPU; peripherals/memory still use 32-bit)
   type Memory_Address_64 is new Double_Word;

   --  RV64-only opcodes
   OPCODE_OP_IMM_32 : constant Word := 2#0011011#;  -- ADDIW/SLLIW/SRLIW/SRAIW
   OPCODE_OP_32     : constant Word := 2#0111011#;  -- ADDW/SUBW/SLLW/SRLW/SRAW/MULW/etc.

   --  RV64 additional funct3 for load/store
   FUNCT3_LWU : constant Word := 2#110#;   -- Load word unsigned (zero-extend)
   FUNCT3_LD  : constant Word := 2#011#;   -- Load double-word
   FUNCT3_SD  : constant Word := 2#011#;   -- Store double-word

   --  RV64 AMO double-word width
   FUNCT3_AMO_D : constant Word := 2#011#;

   --  Instruction opcodes (bits 6..0)
   OPCODE_LUI    : constant Word := 2#0110111#;  -- U-type
   OPCODE_AUIPC  : constant Word := 2#0010111#;  -- U-type
   OPCODE_JAL    : constant Word := 2#1101111#;  -- J-type
   OPCODE_JALR   : constant Word := 2#1100111#;  -- I-type
   OPCODE_BRANCH : constant Word := 2#1100011#;  -- B-type
   OPCODE_LOAD   : constant Word := 2#0000011#;  -- I-type
   OPCODE_STORE  : constant Word := 2#0100011#;  -- S-type
   OPCODE_OP_IMM : constant Word := 2#0010011#;  -- I-type
   OPCODE_OP     : constant Word := 2#0110011#;  -- R-type
   OPCODE_SYSTEM : constant Word := 2#1110011#;  -- I-type
   OPCODE_MISC_MEM : constant Word := 2#0001111#;  -- FENCE, FENCE.I

   --  Floating-point opcodes
   OPCODE_LOAD_FP  : constant Word := 2#0000111#;  -- FLW, FLD
   OPCODE_STORE_FP : constant Word := 2#0100111#;  -- FSW, FSD
   OPCODE_OP_FP    : constant Word := 2#1010011#;  -- FP operations
   OPCODE_FMADD    : constant Word := 2#1000011#;  -- Fused multiply-add
   OPCODE_FMSUB    : constant Word := 2#1000111#;  -- Fused multiply-sub
   OPCODE_FNMSUB   : constant Word := 2#1001011#;  -- Negated fused multiply-sub
   OPCODE_FNMADD   : constant Word := 2#1001111#;  -- Negated fused multiply-add

   --  A Extension (Atomics) opcode
   OPCODE_AMO : constant Word := 2#0101111#;  -- Atomic Memory Operations

   --  A Extension funct5 values (bits 31..27)
   FUNCT5_LR      : constant Word := 2#00010#;  -- Load Reserved
   FUNCT5_SC      : constant Word := 2#00011#;  -- Store Conditional
   FUNCT5_AMOSWAP : constant Word := 2#00001#;  -- Atomic Swap
   FUNCT5_AMOADD  : constant Word := 2#00000#;  -- Atomic Add
   FUNCT5_AMOXOR  : constant Word := 2#00100#;  -- Atomic XOR
   FUNCT5_AMOAND  : constant Word := 2#01100#;  -- Atomic AND
   FUNCT5_AMOOR   : constant Word := 2#01000#;  -- Atomic OR
   FUNCT5_AMOMIN  : constant Word := 2#10000#;  -- Atomic Min (signed)
   FUNCT5_AMOMAX  : constant Word := 2#10100#;  -- Atomic Max (signed)
   FUNCT5_AMOMINU : constant Word := 2#11000#;  -- Atomic Min (unsigned)
   FUNCT5_AMOMAXU : constant Word := 2#11100#;  -- Atomic Max (unsigned)

   --  A Extension funct3 (width)
   FUNCT3_AMO_W : constant Word := 2#010#;  -- Word (32-bit)

   --  Funct3 values for branch instructions
   FUNCT3_BEQ  : constant Word := 2#000#;
   FUNCT3_BNE  : constant Word := 2#001#;
   FUNCT3_BLT  : constant Word := 2#100#;
   FUNCT3_BGE  : constant Word := 2#101#;
   FUNCT3_BLTU : constant Word := 2#110#;
   FUNCT3_BGEU : constant Word := 2#111#;

   --  Funct3 values for load instructions
   FUNCT3_LB  : constant Word := 2#000#;
   FUNCT3_LH  : constant Word := 2#001#;
   FUNCT3_LW  : constant Word := 2#010#;
   FUNCT3_LBU : constant Word := 2#100#;
   FUNCT3_LHU : constant Word := 2#101#;

   --  Funct3 values for store instructions
   FUNCT3_SB : constant Word := 2#000#;
   FUNCT3_SH : constant Word := 2#001#;
   FUNCT3_SW : constant Word := 2#010#;

   --  Funct3 values for arithmetic/logic instructions
   FUNCT3_ADD_SUB : constant Word := 2#000#;
   FUNCT3_SLL     : constant Word := 2#001#;
   FUNCT3_SLT     : constant Word := 2#010#;
   FUNCT3_SLTU    : constant Word := 2#011#;
   FUNCT3_XOR     : constant Word := 2#100#;
   FUNCT3_SRL_SRA : constant Word := 2#101#;
   FUNCT3_OR      : constant Word := 2#110#;
   FUNCT3_AND     : constant Word := 2#111#;

   --  Funct7 values
   FUNCT7_NORMAL : constant Word := 2#0000000#;
   FUNCT7_ALT    : constant Word := 2#0100000#;  -- SUB, SRA
   FUNCT7_MULDIV : constant Word := 2#0000001#;  -- M extension

   --  M extension funct3 values
   FUNCT3_MUL    : constant Word := 2#000#;
   FUNCT3_MULH   : constant Word := 2#001#;
   FUNCT3_MULHSU : constant Word := 2#010#;
   FUNCT3_MULHU  : constant Word := 2#011#;
   FUNCT3_DIV    : constant Word := 2#100#;
   FUNCT3_DIVU   : constant Word := 2#101#;
   FUNCT3_REM    : constant Word := 2#110#;
   FUNCT3_REMU   : constant Word := 2#111#;

   --  System instructions
   FUNCT3_ECALL_EBREAK : constant Word := 2#000#;
   FUNCT3_CSRRW  : constant Word := 2#001#;
   FUNCT3_CSRRS  : constant Word := 2#010#;
   FUNCT3_CSRRC  : constant Word := 2#011#;
   FUNCT3_CSRRWI : constant Word := 2#101#;
   FUNCT3_CSRRSI : constant Word := 2#110#;
   FUNCT3_CSRRCI : constant Word := 2#111#;

   --  Floating-point funct7 values (OP-FP)
   FUNCT7_FADD_S    : constant Word := 2#0000000#;
   FUNCT7_FSUB_S    : constant Word := 2#0000100#;
   FUNCT7_FMUL_S    : constant Word := 2#0001000#;
   FUNCT7_FDIV_S    : constant Word := 2#0001100#;
   FUNCT7_FSQRT_S   : constant Word := 2#0101100#;
   FUNCT7_FSGNJ_S   : constant Word := 2#0010000#;
   FUNCT7_FMINMAX_S : constant Word := 2#0010100#;
   FUNCT7_FCVT_W_S  : constant Word := 2#1100000#;
   FUNCT7_FMV_X_W   : constant Word := 2#1110000#;
   FUNCT7_FCMP_S    : constant Word := 2#1010000#;
   FUNCT7_FCLASS_S  : constant Word := 2#1110000#;
   FUNCT7_FCVT_S_W  : constant Word := 2#1101000#;
   FUNCT7_FMV_W_X   : constant Word := 2#1111000#;

   FUNCT7_FADD_D    : constant Word := 2#0000001#;
   FUNCT7_FSUB_D    : constant Word := 2#0000101#;
   FUNCT7_FMUL_D    : constant Word := 2#0001001#;
   FUNCT7_FDIV_D    : constant Word := 2#0001101#;
   FUNCT7_FSQRT_D   : constant Word := 2#0101101#;
   FUNCT7_FSGNJ_D   : constant Word := 2#0010001#;
   FUNCT7_FMINMAX_D : constant Word := 2#0010101#;
   FUNCT7_FCVT_S_D  : constant Word := 2#0100000#;
   FUNCT7_FCVT_D_S  : constant Word := 2#0100001#;
   FUNCT7_FCVT_W_D  : constant Word := 2#1100001#;  -- also FCVT.L.D (rs2=2), FCVT.LU.D (rs2=3)
   FUNCT7_FCMP_D    : constant Word := 2#1010001#;
   FUNCT7_FCLASS_D  : constant Word := 2#1110001#;  -- also FMV.X.D (funct3=0, rs2=0)
   FUNCT7_FCVT_D_W  : constant Word := 2#1101001#;  -- also FCVT.D.L (rs2=2), FCVT.D.LU (rs2=3)
   FUNCT7_FMV_D_X   : constant Word := 2#1111001#;  -- FMV.D.X (RV64)

   --  Zfh half-precision funct7 values (fmt=10 ->bits[1:0]=10)
   FUNCT7_FADD_H    : constant Word := 2#0000010#;   --  0x02
   FUNCT7_FSUB_H    : constant Word := 2#0000110#;   --  0x06
   FUNCT7_FMUL_H    : constant Word := 2#0001010#;   --  0x0A
   FUNCT7_FDIV_H    : constant Word := 2#0001110#;   --  0x0E
   FUNCT7_FSQRT_H   : constant Word := 2#0101110#;   --  0x2E
   FUNCT7_FSGNJ_H   : constant Word := 2#0010010#;   --  0x12
   FUNCT7_FMINMAX_H : constant Word := 2#0010110#;   --  0x16
   FUNCT7_FCVT_W_H  : constant Word := 2#1100010#;   --  0x62
   FUNCT7_FCVT_H_W  : constant Word := 2#1101010#;   --  0x6A
   FUNCT7_FMV_X_H   : constant Word := 2#1110010#;   --  0x72
   FUNCT7_FMV_H_X   : constant Word := 2#1111010#;   --  0x7A
   FUNCT7_FCMP_H    : constant Word := 2#1010010#;   --  0x52
   FUNCT7_FCVT_H_SD : constant Word := 2#0100010#;   --  0x22

   FUNCT3_FLH : constant Word := 2#001#;   --  load half-precision
   FUNCT3_FSH : constant Word := 2#001#;   --  store half-precision

   --  FP funct3 values for loads/stores
   FUNCT3_FLW : constant Word := 2#010#;
   FUNCT3_FLD : constant Word := 2#011#;
   FUNCT3_FSW : constant Word := 2#010#;
   FUNCT3_FSD : constant Word := 2#011#;

   --  FP funct3 for sign injection
   FUNCT3_FSGNJ  : constant Word := 2#000#;
   FUNCT3_FSGNJN : constant Word := 2#001#;
   FUNCT3_FSGNJX : constant Word := 2#010#;

   --  FP funct3 for min/max
   FUNCT3_FMIN : constant Word := 2#000#;
   FUNCT3_FMAX : constant Word := 2#001#;

   --  FP funct3 for comparisons
   FUNCT3_FEQ : constant Word := 2#010#;
   FUNCT3_FLT : constant Word := 2#001#;
   FUNCT3_FLE : constant Word := 2#000#;

   --  Vector Extension (RVV 1.0) opcodes
   OPCODE_VECTOR : constant Word := 2#1010111#;  -- OP-V

   --  Vector funct3 (width encoding for loads/stores)
   FUNCT3_VLE8   : constant Word := 2#000#;
   FUNCT3_VLE16  : constant Word := 2#101#;
   FUNCT3_VLE32  : constant Word := 2#110#;
   FUNCT3_VLE64  : constant Word := 2#111#;

   --  Vector arithmetic funct3 (OPIVV, OPIVX, OPIVI, etc.)
   FUNCT3_OPIVV  : constant Word := 2#000#;  -- Integer vector-vector
   FUNCT3_OPFVV  : constant Word := 2#001#;  -- FP vector-vector
   FUNCT3_OPMVV  : constant Word := 2#010#;  -- Mask vector-vector
   FUNCT3_OPIVI  : constant Word := 2#011#;  -- Integer vector-immediate
   FUNCT3_OPIVX  : constant Word := 2#100#;  -- Integer vector-scalar
   FUNCT3_OPFVF  : constant Word := 2#101#;  -- FP vector-scalar
   FUNCT3_OPMVX  : constant Word := 2#110#;  -- Mask vector-scalar
   FUNCT3_OPCFG  : constant Word := 2#111#;  -- Configuration (vsetvli)

   --  Vector load/store mop (memory operation) encodings
   VL_MOP_UNIT   : constant Word := 2#00#;  -- Unit-stride
   VL_MOP_STRIDE : constant Word := 2#10#;  -- Strided
   VL_MOP_INDEX  : constant Word := 2#01#;  -- Indexed (unordered)
   VL_MOP_INDEXO : constant Word := 2#11#;  -- Indexed (ordered)

   --  Vector load/store lumop/sumop encodings
   VL_LUMOP_UNIT  : constant Word := 2#00000#;  -- Unit-stride
   VL_LUMOP_WHOLE : constant Word := 2#01000#;  -- Whole register
   VL_SUMOP_UNIT  : constant Word := 2#00000#;  -- Unit-stride
   VL_SUMOP_WHOLE : constant Word := 2#01000#;  -- Whole register

   --  Vector funct6 values for integer arithmetic
   VFUNCT6_VADD     : constant Word := 2#000000#;
   VFUNCT6_VSUB     : constant Word := 2#000010#;
   VFUNCT6_VRSUB    : constant Word := 2#000011#;
   VFUNCT6_VMINU    : constant Word := 2#000100#;
   VFUNCT6_VMIN     : constant Word := 2#000101#;
   VFUNCT6_VMAXU    : constant Word := 2#000110#;
   VFUNCT6_VMAX     : constant Word := 2#000111#;
   VFUNCT6_VAND     : constant Word := 2#001001#;
   VFUNCT6_VOR      : constant Word := 2#001010#;
   VFUNCT6_VXOR     : constant Word := 2#001011#;
   VFUNCT6_VRGATHER : constant Word := 2#001100#;
   VFUNCT6_VSLIDEUP : constant Word := 2#001110#;
   VFUNCT6_VSLIDEDN : constant Word := 2#001111#;
   VFUNCT6_VADC     : constant Word := 2#010000#;
   VFUNCT6_VMADC    : constant Word := 2#010001#;
   VFUNCT6_VSBC     : constant Word := 2#010010#;
   VFUNCT6_VMSBC    : constant Word := 2#010011#;
   VFUNCT6_VMERGE   : constant Word := 2#010111#;
   VFUNCT6_VMV      : constant Word := 2#010111#;  -- Same as merge (vm=1)
   VFUNCT6_VMSEQ    : constant Word := 2#011000#;
   VFUNCT6_VMSNE    : constant Word := 2#011001#;
   VFUNCT6_VMSLTU   : constant Word := 2#011010#;
   VFUNCT6_VMSLT    : constant Word := 2#011011#;
   VFUNCT6_VMSLEU   : constant Word := 2#011100#;
   VFUNCT6_VMSLE    : constant Word := 2#011101#;
   VFUNCT6_VMSGTU   : constant Word := 2#011110#;
   VFUNCT6_VMSGT    : constant Word := 2#011111#;
   VFUNCT6_VSADDU   : constant Word := 2#100000#;
   VFUNCT6_VSADD    : constant Word := 2#100001#;
   VFUNCT6_VSSUBU   : constant Word := 2#100010#;
   VFUNCT6_VSSUB    : constant Word := 2#100011#;
   VFUNCT6_VSLL     : constant Word := 2#100101#;
   VFUNCT6_VSMUL    : constant Word := 2#100111#;
   VFUNCT6_VSRL     : constant Word := 2#101000#;
   VFUNCT6_VSRA     : constant Word := 2#101001#;
   VFUNCT6_VSSRL    : constant Word := 2#101010#;
   VFUNCT6_VSSRA    : constant Word := 2#101011#;
   VFUNCT6_VNSRL    : constant Word := 2#101100#;
   VFUNCT6_VNSRA    : constant Word := 2#101101#;
   VFUNCT6_VNCLIPU  : constant Word := 2#101110#;
   VFUNCT6_VNCLIP   : constant Word := 2#101111#;

   --  OPMVV/OPMVX funct6 values
   VFUNCT6_VREDSUM  : constant Word := 2#000000#;
   VFUNCT6_VREDAND  : constant Word := 2#000001#;
   VFUNCT6_VREDOR   : constant Word := 2#000010#;
   VFUNCT6_VREDXOR  : constant Word := 2#000011#;
   VFUNCT6_VREDMINU : constant Word := 2#000100#;
   VFUNCT6_VREDMIN  : constant Word := 2#000101#;
   VFUNCT6_VREDMAXU : constant Word := 2#000110#;
   VFUNCT6_VREDMAX  : constant Word := 2#000111#;
   VFUNCT6_VMV_X_S  : constant Word := 2#010000#;
   VFUNCT6_VPOPC    : constant Word := 2#010000#;  -- vcpop.m
   VFUNCT6_VFIRST   : constant Word := 2#010000#;  -- same funct6, vs1=10001
   VFUNCT6_VMV_S_X  : constant Word := 2#010000#;
   VFUNCT6_VZEXT    : constant Word := 2#010010#;
   VFUNCT6_VSEXT    : constant Word := 2#010010#;
   VFUNCT6_VMSBF    : constant Word := 2#010100#;
   VFUNCT6_VMSOF    : constant Word := 2#010100#;
   VFUNCT6_VMSIF    : constant Word := 2#010100#;
   VFUNCT6_VIOTA    : constant Word := 2#010100#;
   VFUNCT6_VID      : constant Word := 2#010100#;
   VFUNCT6_VMAND    : constant Word := 2#011001#;
   VFUNCT6_VMNAND   : constant Word := 2#011101#;
   VFUNCT6_VMANDNOT : constant Word := 2#011000#;
   VFUNCT6_VMXOR    : constant Word := 2#011011#;
   VFUNCT6_VMOR     : constant Word := 2#011010#;
   VFUNCT6_VMNOR    : constant Word := 2#011110#;
   VFUNCT6_VMORNOT  : constant Word := 2#011100#;
   VFUNCT6_VMXNOR   : constant Word := 2#011111#;

   --  Whole-register move funct6
   VFUNCT6_VMV_REG  : constant Word := 2#100111#;

   --  Widening integer add/sub funct6
   VFUNCT6_VWADDU   : constant Word := 2#110000#;
   VFUNCT6_VWADD    : constant Word := 2#110001#;
   VFUNCT6_VWSUBU   : constant Word := 2#110010#;
   VFUNCT6_VWSUB    : constant Word := 2#110011#;
   VFUNCT6_VWADDUW  : constant Word := 2#110100#;
   VFUNCT6_VWADDW   : constant Word := 2#110101#;
   VFUNCT6_VWSUBUW  : constant Word := 2#110110#;
   VFUNCT6_VWSUBW   : constant Word := 2#110111#;

   --  Widening multiply funct6 (OPMVV/OPMVX)
   VFUNCT6_VWMULU   : constant Word := 2#111000#;
   VFUNCT6_VWMULSU  : constant Word := 2#111010#;
   VFUNCT6_VWMUL    : constant Word := 2#111011#;

   --  Widening multiply-add funct6 (OPMVV/OPMVX)
   VFUNCT6_VWMACCU  : constant Word := 2#111100#;
   VFUNCT6_VWMACC   : constant Word := 2#111101#;
   VFUNCT6_VWMACCSU : constant Word := 2#111110#;
   VFUNCT6_VWMACCUS : constant Word := 2#111111#;

   --  Averaging add/sub funct6 (OPMVV/OPMVX)
   VFUNCT6_VAADDU   : constant Word := 2#001000#;
   VFUNCT6_VAADD    : constant Word := 2#001001#;
   VFUNCT6_VASUBU   : constant Word := 2#001010#;
   VFUNCT6_VASUB    : constant Word := 2#001011#;

   --  Vector FP funct6
   VFUNCT6_VFADD    : constant Word := 2#000000#;
   VFUNCT6_VFREDOSUM : constant Word := 2#000001#;
   VFUNCT6_VFSUB    : constant Word := 2#000010#;
   VFUNCT6_VFREDUSUM : constant Word := 2#000011#;
   VFUNCT6_VFMIN    : constant Word := 2#000100#;
   VFUNCT6_VFREDMIN : constant Word := 2#000101#;
   VFUNCT6_VFMAX    : constant Word := 2#000110#;
   VFUNCT6_VFREDMAX : constant Word := 2#000111#;
   VFUNCT6_VFSGNJ   : constant Word := 2#001000#;
   VFUNCT6_VFSGNJN  : constant Word := 2#001001#;
   VFUNCT6_VFSGNJX  : constant Word := 2#001010#;
   VFUNCT6_VFUNARY  : constant Word := 2#010010#;  --  conversion, funct determined by vs1
   VFUNCT6_VFSQRT   : constant Word := 2#010011#;
   VFUNCT6_VFCLASS  : constant Word := 2#010011#;  --  same funct6 as sqrt, vs1=10000
   VFUNCT6_VFMERGE  : constant Word := 2#010111#;
   VFUNCT6_VMFEQ    : constant Word := 2#011000#;
   VFUNCT6_VMFLE    : constant Word := 2#011001#;
   VFUNCT6_VMFLT    : constant Word := 2#011011#;
   VFUNCT6_VMFNE    : constant Word := 2#011100#;
   VFUNCT6_VMFGT    : constant Word := 2#011101#;
   VFUNCT6_VMFGE    : constant Word := 2#011111#;
   VFUNCT6_VFDIV    : constant Word := 2#100000#;
   VFUNCT6_VFRDIV   : constant Word := 2#100001#;
   VFUNCT6_VFMUL    : constant Word := 2#100100#;
   VFUNCT6_VFRSUB   : constant Word := 2#100111#;
   VFUNCT6_VFMACC   : constant Word := 2#101100#;
   VFUNCT6_VFNMACC  : constant Word := 2#101101#;
   VFUNCT6_VFMSAC   : constant Word := 2#101110#;
   VFUNCT6_VFNMSAC  : constant Word := 2#101111#;
   VFUNCT6_VFWADD   : constant Word := 2#110000#;
   VFUNCT6_VFWREDOSUM : constant Word := 2#110001#;
   VFUNCT6_VFWSUB   : constant Word := 2#110010#;
   VFUNCT6_VFWREDUSUM : constant Word := 2#110011#;
   VFUNCT6_VFWADDW  : constant Word := 2#110100#;
   VFUNCT6_VFWSUBW  : constant Word := 2#110110#;
   VFUNCT6_VFWMUL   : constant Word := 2#111000#;
   VFUNCT6_VFWMACC  : constant Word := 2#111100#;
   VFUNCT6_VFWNMACC : constant Word := 2#111101#;
   VFUNCT6_VFWMSAC  : constant Word := 2#111110#;
   VFUNCT6_VFWNMSAC : constant Word := 2#111111#;

   --  Multiply funct6
   VFUNCT6_VMUL     : constant Word := 2#100101#;
   VFUNCT6_VMULH    : constant Word := 2#100111#;
   VFUNCT6_VMULHU   : constant Word := 2#100100#;
   VFUNCT6_VMULHSU  : constant Word := 2#100110#;
   VFUNCT6_VDIVU    : constant Word := 2#100000#;
   VFUNCT6_VDIV     : constant Word := 2#100001#;
   VFUNCT6_VREMU    : constant Word := 2#100010#;
   VFUNCT6_VREM     : constant Word := 2#100011#;

   --  Integer multiply-add funct6 (OPMVV/OPMVX)
   VFUNCT6_VMACC    : constant Word := 2#101101#;
   VFUNCT6_VNMSAC   : constant Word := 2#101111#;
   VFUNCT6_VMADD    : constant Word := 2#101001#;
   VFUNCT6_VNMSUB   : constant Word := 2#101011#;

   --  Slide operations funct6
   VFUNCT6_VSLIDE1UP : constant Word := 2#001110#;  -- OPMVX: vslide1up.vx
   VFUNCT6_VSLIDE1DN : constant Word := 2#001111#;  -- OPMVX: vslide1down.vx

   --  Compress funct6 (OPMVV)
   VFUNCT6_VCOMPRESS : constant Word := 2#010111#;

   --  Gather funct6 (OPIVV/OPIVX/OPIVI)
   VFUNCT6_VRGATHEREI16 : constant Word := 2#001110#;  -- OPIVV with EEW16 index

   --  K Extension (Scalar Crypto) funct7 values for OPCODE_OP
   --  Zbkb: bit manipulation for crypto
   FUNCT7_ANDN      : constant Word := 2#0100000#;  -- funct3=111
   FUNCT7_ORN       : constant Word := 2#0100000#;  -- funct3=110
   FUNCT7_XNOR      : constant Word := 2#0100000#;  -- funct3=100
   FUNCT7_ROL       : constant Word := 2#0110000#;  -- funct3=001
   FUNCT7_ROR       : constant Word := 2#0110000#;  -- funct3=101
   FUNCT7_PACK      : constant Word := 2#0000100#;  -- funct3=100
   FUNCT7_PACKH     : constant Word := 2#0000100#;  -- funct3=111
   FUNCT7_REV8      : constant Word := 2#0110100#;  -- OP-IMM, funct3=101
   FUNCT7_REV8_64   : constant Word := 2#0110101#;  -- OP-IMM, funct3=101 (RV64)
   FUNCT7_ZIP       : constant Word := 2#0000100#;  -- OP-IMM, funct3=001
   FUNCT7_UNZIP     : constant Word := 2#0000100#;  -- OP-IMM, funct3=101
   FUNCT7_BREV8     : constant Word := 2#0110100#;  -- OP-IMM, funct3=101

   --  Zbkc: carry-less multiplication
   FUNCT7_CLMUL     : constant Word := 2#0000101#;  -- funct3=001
   FUNCT7_CLMULH    : constant Word := 2#0000101#;  -- funct3=011

   --  Zbkx: crossbar permutations
   FUNCT7_XPERM4    : constant Word := 2#0010100#;  -- funct3=010
   FUNCT7_XPERM8    : constant Word := 2#0010100#;  -- funct3=100

   --  Zkne: AES encryption (funct3=000, bs in bits[31:30])
   FUNCT5_AES32ESI  : constant Word := 2#10001#;
   FUNCT5_AES32ESMI : constant Word := 2#10011#;

   --  Zknd: AES decryption (funct3=000, bs in bits[31:30])
   FUNCT5_AES32DSI  : constant Word := 2#10101#;
   FUNCT5_AES32DSMI : constant Word := 2#10111#;

   --  Zknh: SHA-256 / SHA-512
   FUNCT7_SHA256SIG0  : constant Word := 2#0001000#;
   FUNCT7_SHA256SIG1  : constant Word := 2#0001000#;
   FUNCT7_SHA256SUM0  : constant Word := 2#0001000#;
   FUNCT7_SHA256SUM1  : constant Word := 2#0001000#;
   --  SHA-256 rs2 values to distinguish operations
   SHA256_SIG0_RS2  : constant Word := 2#00010#;
   SHA256_SIG1_RS2  : constant Word := 2#00011#;
   SHA256_SUM0_RS2  : constant Word := 2#00000#;
   SHA256_SUM1_RS2  : constant Word := 2#00001#;
   --  SHA-512 (funct7=01 in bits[31:25], but really funct5+bs)
   FUNCT7_SHA512SIG0H : constant Word := 2#0101110#;
   FUNCT7_SHA512SIG0L : constant Word := 2#0101010#;
   FUNCT7_SHA512SIG1H : constant Word := 2#0101111#;
   FUNCT7_SHA512SIG1L : constant Word := 2#0101011#;
   FUNCT7_SHA512SUM0R : constant Word := 2#0101000#;
   FUNCT7_SHA512SUM1R : constant Word := 2#0101001#;

   --  Zksed: SM4 (funct3=000, bs in bits[31:30])
   FUNCT5_SM4ED     : constant Word := 2#11000#;
   FUNCT5_SM4KS     : constant Word := 2#11010#;

   --  Zksh: SM3
   FUNCT7_SM3P0     : constant Word := 2#0001000#;
   FUNCT7_SM3P1     : constant Word := 2#0001000#;
   SM3P0_RS2        : constant Word := 2#01000#;
   SM3P1_RS2        : constant Word := 2#01001#;

   --  Zbb: basic bit manipulation (scalar)
   --  CLZ/CTZ/CPOP/SEXT.B/SEXT.H use OP-IMM, funct3=001, funct7=0110000 (=FUNCT7_ROL)
   --  rs2 field selects the operation:
   ZBB_CLZ_RS2   : constant Word := 0;
   ZBB_CTZ_RS2   : constant Word := 1;
   ZBB_CPOP_RS2  : constant Word := 2;
   ZBB_SEXTB_RS2 : constant Word := 4;
   ZBB_SEXTH_RS2 : constant Word := 5;
   --  ORC.B: OP-IMM, funct3=101, funct7=0010100, rs2=7
   FUNCT7_ORC_B  : constant Word := 2#0010100#;
   ZBB_ORCB_RS2  : constant Word := 7;
   --  MIN/MAX/MINU/MAXU: OP, funct7=0000101
   FUNCT7_MINMAX : constant Word := 2#0000101#;

   --  Zba: address generation (sh1add/sh2add/sh3add)
   FUNCT7_ZBA    : constant Word := 2#0010000#;

   --  Zbs: single-bit manipulation
   --  BSET/BSETI: funct7=0010100, funct3=001  (same value as FUNCT7_ORC_B)
   FUNCT7_BSET   : constant Word := 2#0010100#;
   --  BCLR/BCLRI and BEXT/BEXTI: funct7=0100100  (funct3 differs: 001 vs 101)
   FUNCT7_BCLR   : constant Word := 2#0100100#;
   --  BINV/BINVI: funct7=0110100, funct3=001
   FUNCT7_BINV   : constant Word := 2#0110100#;

   --  Zicond: conditional zero (czero.eqz / czero.nez)
   --  Both use opcode=OP, funct7=0000111
   --  czero.eqz: funct3=101 (FUNCT3_SRL_SRA), czero.nez: funct3=111 (FUNCT3_AND)
   FUNCT7_ZICOND : constant Word := 2#0000111#;

   --  Privilege levels
   type Privilege_Level is (User, Supervisor, Reserved, Machine);
   for Privilege_Level use (User => 0, Supervisor => 1, Reserved => 2, Machine => 3);

   --  Exception codes
   type Exception_Code is (
      No_Exception,
      Illegal_Instruction,
      Misaligned_Fetch,
      Misaligned_Load,
      Misaligned_Store,
      Insn_Access_Fault,
      Load_Access_Fault,
      Store_Access_Fault,
      Environment_Call,
      Breakpoint,
      Insn_Page_Fault,
      Load_Page_Fault,
      Store_Page_Fault
   );

end RISCV;
