-- ***************************************************************************
--             RISC-V Emulator - 64-bit CSR Register File (RV64)
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
-- Thin wrapper over RISCV.CSR: stores CSR values as Double_Word (64-bit).
-- CSR address constants are inherited from RISCV.CSR.
-- ***************************************************************************

with RISCV.CSR;

package RISCV.CSR64 is

   subtype CSR_Address is CSR.CSR_Address;

   --  Re-export all standard CSR addresses
   CSR_MVENDORID  : constant CSR_Address := CSR.CSR_MVENDORID;
   CSR_MARCHID    : constant CSR_Address := CSR.CSR_MARCHID;
   CSR_MIMPID     : constant CSR_Address := CSR.CSR_MIMPID;
   CSR_MHARTID    : constant CSR_Address := CSR.CSR_MHARTID;
   CSR_SSTATUS    : constant CSR_Address := CSR.CSR_SSTATUS;
   CSR_SIE        : constant CSR_Address := CSR.CSR_SIE;
   CSR_STVEC      : constant CSR_Address := CSR.CSR_STVEC;
   CSR_SSCRATCH   : constant CSR_Address := CSR.CSR_SSCRATCH;
   CSR_SEPC       : constant CSR_Address := CSR.CSR_SEPC;
   CSR_SCAUSE     : constant CSR_Address := CSR.CSR_SCAUSE;
   CSR_STVAL      : constant CSR_Address := CSR.CSR_STVAL;
   CSR_SIP        : constant CSR_Address := CSR.CSR_SIP;
   CSR_SATP       : constant CSR_Address := CSR.CSR_SATP;
   CSR_MSTATUS    : constant CSR_Address := CSR.CSR_MSTATUS;
   CSR_MISA       : constant CSR_Address := CSR.CSR_MISA;
   CSR_MEDELEG    : constant CSR_Address := CSR.CSR_MEDELEG;
   CSR_MIDELEG    : constant CSR_Address := CSR.CSR_MIDELEG;
   CSR_MIE        : constant CSR_Address := CSR.CSR_MIE;
   CSR_MTVEC      : constant CSR_Address := CSR.CSR_MTVEC;
   CSR_MSCRATCH   : constant CSR_Address := CSR.CSR_MSCRATCH;
   CSR_MEPC       : constant CSR_Address := CSR.CSR_MEPC;
   CSR_MCAUSE     : constant CSR_Address := CSR.CSR_MCAUSE;
   CSR_MTVAL      : constant CSR_Address := CSR.CSR_MTVAL;
   CSR_MIP        : constant CSR_Address := CSR.CSR_MIP;
   CSR_MCYCLE     : constant CSR_Address := CSR.CSR_MCYCLE;
   CSR_MINSTRET   : constant CSR_Address := CSR.CSR_MINSTRET;
   CSR_MCOUNTINHIBIT : constant CSR_Address := CSR.CSR_MCOUNTINHIBIT;
   CSR_MCOUNTEREN : constant CSR_Address := CSR.CSR_MCOUNTEREN;
   CSR_SCOUNTEREN : constant CSR_Address := CSR.CSR_SCOUNTEREN;
   CSR_FFLAGS     : constant CSR_Address := CSR.CSR_FFLAGS;
   CSR_FRM        : constant CSR_Address := CSR.CSR_FRM;
   CSR_FCSR       : constant CSR_Address := CSR.CSR_FCSR;
   CSR_VSTART     : constant CSR_Address := CSR.CSR_VSTART;
   CSR_VXSAT      : constant CSR_Address := CSR.CSR_VXSAT;
   CSR_VXRM       : constant CSR_Address := CSR.CSR_VXRM;
   CSR_VCSR       : constant CSR_Address := CSR.CSR_VCSR;
   CSR_VL         : constant CSR_Address := CSR.CSR_VL;
   CSR_VTYPE      : constant CSR_Address := CSR.CSR_VTYPE;
   CSR_VLENB      : constant CSR_Address := CSR.CSR_VLENB;
   CSR_CYCLE      : constant CSR_Address := CSR.CSR_CYCLE;
   CSR_TIME       : constant CSR_Address := CSR.CSR_TIME;
   CSR_INSTRET    : constant CSR_Address := CSR.CSR_INSTRET;

   --  RV64 MSTATUS bit fields (lower 32 bits same as RV32)
   MSTATUS_SIE    : constant Double_Word := Double_Word (CSR.MSTATUS_SIE);
   MSTATUS_MIE    : constant Double_Word := Double_Word (CSR.MSTATUS_MIE);
   MSTATUS_SPIE   : constant Double_Word := Double_Word (CSR.MSTATUS_SPIE);
   MSTATUS_MPIE   : constant Double_Word := Double_Word (CSR.MSTATUS_MPIE);
   MSTATUS_SPP    : constant Double_Word := Double_Word (CSR.MSTATUS_SPP);
   MSTATUS_MPP_MASK : constant Double_Word := Double_Word (CSR.MSTATUS_MPP_MASK);
   MSTATUS_MXR    : constant Double_Word := Double_Word (CSR.MSTATUS_MXR);
   MSTATUS_TVM    : constant Double_Word := Double_Word (CSR.MSTATUS_TVM);
   MSTATUS_TW     : constant Double_Word := Double_Word (CSR.MSTATUS_TW);
   MSTATUS_TSR    : constant Double_Word := Double_Word (CSR.MSTATUS_TSR);
   --  SSTATUS mask: same lower-32 fields apply
   SSTATUS_MASK   : constant Double_Word := Double_Word (CSR.SSTATUS_MASK);
   --  RV64-specific MSTATUS fields (UXL/SXL bits 32-35, SD bit 63)
   MSTATUS_UXL_MASK : constant Double_Word := Shift_Left (Double_Word (3), 32);
   MSTATUS_SXL_MASK : constant Double_Word := Shift_Left (Double_Word (3), 34);
   MSTATUS_UXL_64   : constant Double_Word := Shift_Left (Double_Word (2), 32);
   MSTATUS_SXL_64   : constant Double_Word := Shift_Left (Double_Word (2), 34);
   MSTATUS_SD       : constant Double_Word := Shift_Left (Double_Word (1), 63);

   --  MIE/MIP bit fields (same values as RV32)
   MIE_SSIE       : constant Double_Word := Double_Word (CSR.MIE_SSIE);
   MIE_STIE       : constant Double_Word := Double_Word (CSR.MIE_STIE);
   MIE_SEIE       : constant Double_Word := Double_Word (CSR.MIE_SEIE);
   MIE_MSIE       : constant Double_Word := Double_Word (CSR.MIE_MSIE);
   MIE_MTIE       : constant Double_Word := Double_Word (CSR.MIE_MTIE);
   MIE_MEIE       : constant Double_Word := Double_Word (CSR.MIE_MEIE);
   SIP_MASK       : constant Double_Word := Double_Word (CSR.SIP_MASK);
   SIP_WRITE_MASK : constant Double_Word := Double_Word (CSR.SIP_WRITE_MASK);

   --  RV64 MCAUSE: interrupt bit is bit 63
   CAUSE_INTERRUPT_BIT : constant Double_Word :=
      Shift_Left (Double_Word (1), 63);

   --  HPM stubs
   CSR_MHPMCOUNTER_LO  : constant CSR_Address := CSR.CSR_MHPMCOUNTER_LO;
   CSR_MHPMCOUNTER_HI  : constant CSR_Address := CSR.CSR_MHPMCOUNTER_HI;
   CSR_MHPMEVENT_LO    : constant CSR_Address := CSR.CSR_MHPMEVENT_LO;
   CSR_MHPMEVENT_HI    : constant CSR_Address := CSR.CSR_MHPMEVENT_HI;

   --  ========================================================================
   --  CSR State (64-bit values)
   --  ========================================================================

   Max_CSR_Count : constant := 52;

   type CSR_Entry_64 is record
      Address : CSR_Address;
      Value   : Double_Word;
   end record;

   type CSR_Entry_Array_64 is array (0 .. Max_CSR_Count - 1) of CSR_Entry_64;

   type CSR_State_64 is record
      Entries       : CSR_Entry_Array_64;
      Count         : Natural;
      Mcycle        : Unsigned_64;
      Minstret      : Unsigned_64;
      Mcountinhibit : Word;   -- only bits 0 and 2 used
   end record;

   --  ========================================================================
   --  Operations
   --  ========================================================================

   procedure Initialize (State : out CSR_State_64);

   function  Read  (State : CSR_State_64;
                    Addr  : CSR_Address) return Double_Word;

   procedure Write (State : in out CSR_State_64;
                    Addr  : CSR_Address;
                    Value : Double_Word);

   procedure Increment_Instret (State : in out CSR_State_64);
   procedure Increment_Mcycle  (State : in out CSR_State_64; Count : Positive := 1);

   function Is_Read_Only (Addr : CSR_Address) return Boolean
      renames CSR.Is_Read_Only;

   function CSR_Name (Addr : CSR_Address) return String
      renames CSR.CSR_Name;

end RISCV.CSR64;
