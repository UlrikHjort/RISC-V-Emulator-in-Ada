-- ***************************************************************************
--             RISC-V Emulator - CSR Register File
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

-- Zicsr Extension - Control and Status Registers
package RISCV.CSR is

   --  CSR address type (12 bits, 0x000..0xFFF)
   subtype CSR_Address is Word range 0 .. 16#FFF#;

   --  ========================================================================
   --  Standard CSR Addresses (Machine Mode)
   --  ========================================================================

   --  Machine Information Registers
   CSR_MVENDORID  : constant CSR_Address := 16#F11#;
   CSR_MARCHID    : constant CSR_Address := 16#F12#;
   CSR_MIMPID     : constant CSR_Address := 16#F13#;
   CSR_MHARTID    : constant CSR_Address := 16#F14#;

   --  Supervisor Trap Setup
   CSR_SSTATUS    : constant CSR_Address := 16#100#;
   CSR_SIE        : constant CSR_Address := 16#104#;
   CSR_STVEC      : constant CSR_Address := 16#105#;

   --  Supervisor Trap Handling
   CSR_SSCRATCH   : constant CSR_Address := 16#140#;
   CSR_SEPC       : constant CSR_Address := 16#141#;
   CSR_SCAUSE     : constant CSR_Address := 16#142#;
   CSR_STVAL      : constant CSR_Address := 16#143#;
   CSR_SIP        : constant CSR_Address := 16#144#;

   --  Supervisor Protection and Translation
   CSR_SATP       : constant CSR_Address := 16#180#;

   --  Machine Trap Setup
   CSR_MSTATUS    : constant CSR_Address := 16#300#;
   CSR_MISA       : constant CSR_Address := 16#301#;
   CSR_MEDELEG    : constant CSR_Address := 16#302#;
   CSR_MIDELEG    : constant CSR_Address := 16#303#;
   CSR_MIE        : constant CSR_Address := 16#304#;
   CSR_MTVEC      : constant CSR_Address := 16#305#;

   --  Machine Trap Handling
   CSR_MSCRATCH   : constant CSR_Address := 16#340#;
   CSR_MEPC       : constant CSR_Address := 16#341#;
   CSR_MCAUSE     : constant CSR_Address := 16#342#;
   CSR_MTVAL      : constant CSR_Address := 16#343#;
   CSR_MIP        : constant CSR_Address := 16#344#;

   --  Machine Counters
   CSR_MCYCLE     : constant CSR_Address := 16#B00#;
   CSR_MINSTRET   : constant CSR_Address := 16#B02#;
   CSR_MCYCLEH    : constant CSR_Address := 16#B80#;
   CSR_MINSTRETH  : constant CSR_Address := 16#B82#;

   --  Machine Counter Control
   CSR_MCOUNTINHIBIT : constant CSR_Address := 16#320#;
   CSR_MCOUNTEREN    : constant CSR_Address := 16#306#;
   CSR_SCOUNTEREN    : constant CSR_Address := 16#106#;

   --  HPM counter/event ranges (stubs: read 0, writes ignored)
   --  mhpmcounter3..31  = 0xB03..0xB1F
   --  mhpmcounterh3..31 = 0xB83..0xB9F
   --  mhpmevent3..31    = 0x323..0x33F
   CSR_MHPMCOUNTER_LO  : constant CSR_Address := 16#B03#;
   CSR_MHPMCOUNTER_HI  : constant CSR_Address := 16#B1F#;
   CSR_MHPMCOUNTERH_LO : constant CSR_Address := 16#B83#;
   CSR_MHPMCOUNTERH_HI : constant CSR_Address := 16#B9F#;
   CSR_MHPMEVENT_LO    : constant CSR_Address := 16#323#;
   CSR_MHPMEVENT_HI    : constant CSR_Address := 16#33F#;

   --  Floating-point CSRs
   CSR_FFLAGS     : constant CSR_Address := 16#001#;
   CSR_FRM        : constant CSR_Address := 16#002#;
   CSR_FCSR       : constant CSR_Address := 16#003#;

   --  Vector CSRs
   CSR_VSTART     : constant CSR_Address := 16#008#;
   CSR_VXSAT      : constant CSR_Address := 16#009#;
   CSR_VXRM       : constant CSR_Address := 16#00A#;
   CSR_VCSR       : constant CSR_Address := 16#00F#;
   CSR_VL         : constant CSR_Address := 16#C20#;
   CSR_VTYPE      : constant CSR_Address := 16#C21#;
   CSR_VLENB      : constant CSR_Address := 16#C22#;

   --  User-mode read-only shadows
   CSR_CYCLE      : constant CSR_Address := 16#C00#;
   CSR_TIME       : constant CSR_Address := 16#C01#;
   CSR_INSTRET    : constant CSR_Address := 16#C02#;
   CSR_CYCLEH     : constant CSR_Address := 16#C80#;
   CSR_TIMEH      : constant CSR_Address := 16#C81#;
   CSR_INSTRETH   : constant CSR_Address := 16#C82#;

   --  ========================================================================
   --  MSTATUS bit fields
   --  ========================================================================
   MSTATUS_SIE    : constant Word := Shift_Left (1, 1);   --  Supervisor IE
   MSTATUS_MIE    : constant Word := Shift_Left (1, 3);   --  Machine IE
   MSTATUS_SPIE   : constant Word := Shift_Left (1, 5);   --  Previous SIE
   MSTATUS_MPIE   : constant Word := Shift_Left (1, 7);   --  Previous MIE
   MSTATUS_SPP    : constant Word := Shift_Left (1, 8);   --  Previous S priv
   MSTATUS_MPP_MASK : constant Word := Shift_Left (3, 11); --  Previous priv
   MSTATUS_MXR    : constant Word := Shift_Left (1, 19);  --  Make eXec Readable
   MSTATUS_TVM    : constant Word := Shift_Left (1, 20);  --  Trap SFENCE.VMA
   MSTATUS_TW     : constant Word := Shift_Left (1, 21);  --  Timeout Wait (WFI)
   MSTATUS_TSR    : constant Word := Shift_Left (1, 22);  --  Trap SRET

   --  SSTATUS is a view of MSTATUS with this mask.  MXR belongs here: the
   --  MMU reads it straight out of mstatus, so leaving it out of the mask
   --  made it unreachable for an S-mode kernel that needs to read from
   --  execute-only pages.
   SSTATUS_MASK   : constant Word := MSTATUS_SIE or MSTATUS_SPIE or
                                      MSTATUS_SPP or Shift_Left (3, 13) or
                                      Shift_Left (1, 18) or MSTATUS_MXR;
   --  bits: SIE(1), SPIE(5), SPP(8), FS(13:14), SUM(18), MXR(19)

   --  ========================================================================
   --  MIE/MIP bit fields (interrupt enable/pending)
   --  ========================================================================
   --  Supervisor interrupt bits
   MIE_SSIE       : constant Word := Shift_Left (1, 1);   --  S SW interrupt
   MIE_STIE       : constant Word := Shift_Left (1, 5);   --  S Timer interrupt
   MIE_SEIE       : constant Word := Shift_Left (1, 9);   --  S External int

   --  Machine interrupt bits
   MIE_MSIE       : constant Word := Shift_Left (1, 3);   --  SW interrupt
   MIE_MTIE       : constant Word := Shift_Left (1, 7);   --  Timer interrupt
   MIE_MEIE       : constant Word := Shift_Left (1, 11);  --  External int

   --  SIE/SIP is a view of MIE/MIP with this mask.  It is the right mask for
   --  reading either, and for writing sie, where all three bits are writable.
   SIP_MASK       : constant Word := MIE_SSIE or MIE_STIE or MIE_SEIE;

   --  Writing sip is different: STIP is owned by the timer and SEIP by the
   --  PLIC, so S-mode may only set or clear SSIP.  Using SIP_MASK for writes
   --  would let a guest both inject phantom timer/external interrupts and
   --  drop real pending ones by acknowledging a software interrupt.
   SIP_WRITE_MASK : constant Word := MIE_SSIE;

   --  ========================================================================
   --  CSR State
   --  ========================================================================

   --  Number of implemented CSR slots
   --  We use a sparse map: store only the CSRs we actually need
   Max_CSR_Count : constant := 52;

   type CSR_Entry is record
      Address : CSR_Address;
      Value   : Word;
   end record;

   type CSR_Entry_Array is array (0 .. Max_CSR_Count - 1) of CSR_Entry;

   type CSR_State is record
      Entries : CSR_Entry_Array;
      Count   : Natural;
      --  64-bit counters stored as pairs
      Mcycle        : Unsigned_64;
      Minstret      : Unsigned_64;
      --  Counter inhibit (direct field for hot-path efficiency)
      --  Bit 0 = CY (inhibit mcycle), bit 2 = IR (inhibit minstret)
      Mcountinhibit : Word;
   end record;

   --  ========================================================================
   --  Operations
   --  ========================================================================

   procedure Initialize (State : out CSR_State);

   --  Read a CSR, returns 0 for unimplemented CSRs
   function Read (State : CSR_State; Addr : CSR_Address) return Word;

   --  Write a CSR
   procedure Write (State : in out CSR_State;
                    Addr  : CSR_Address;
                    Value : Word);

   --  Increment instruction counter
   procedure Increment_Instret (State : in out CSR_State);

   --  Increment cycle counter
   procedure Increment_Mcycle (State : in out CSR_State; Count : Positive := 1);

   --  Check if CSR address is read-only (bits [11:10] = 11)
   function Is_Read_Only (Addr : CSR_Address) return Boolean;

   --  Get CSR name for disassembly
   function CSR_Name (Addr : CSR_Address) return String;

   --  ========================================================================
   --  Trap/Interrupt Support
   --  ========================================================================

   --  MCAUSE exception codes (synchronous exceptions)
   CAUSE_INSN_MISALIGNED    : constant Word := 0;
   CAUSE_INSN_ACCESS_FAULT  : constant Word := 1;
   CAUSE_ILLEGAL_INSN       : constant Word := 2;
   CAUSE_BREAKPOINT         : constant Word := 3;
   CAUSE_LOAD_MISALIGNED    : constant Word := 4;
   CAUSE_LOAD_ACCESS_FAULT  : constant Word := 5;
   CAUSE_STORE_MISALIGNED   : constant Word := 6;
   CAUSE_STORE_ACCESS_FAULT : constant Word := 7;
   CAUSE_ECALL_U            : constant Word := 8;
   CAUSE_ECALL_S            : constant Word := 9;
   CAUSE_ECALL_M            : constant Word := 11;
   CAUSE_INSN_PAGE_FAULT    : constant Word := 12;
   CAUSE_LOAD_PAGE_FAULT    : constant Word := 13;
   CAUSE_STORE_PAGE_FAULT   : constant Word := 15;

   --  MCAUSE interrupt codes (bit 31 set = interrupt)
   CAUSE_S_SOFTWARE_INT     : constant Word := 16#80000001#;
   CAUSE_S_TIMER_INT        : constant Word := 16#80000005#;
   CAUSE_S_EXTERNAL_INT     : constant Word := 16#80000009#;
   CAUSE_M_SOFTWARE_INT     : constant Word := 16#80000003#;
   CAUSE_M_TIMER_INT        : constant Word := 16#80000007#;
   CAUSE_M_EXTERNAL_INT     : constant Word := 16#8000000B#;

   --  Map Exception_Code enum to RISC-V mcause value
   function To_Mcause (Code : Exception_Code) return Word;

   --  Get minimum privilege level required to access a CSR
   --  Based on CSR address bits [9:8]
   function Get_Min_Privilege (Addr : CSR_Address) return Privilege_Level;

   --  Check if a given privilege level can access a CSR
   function Can_Access_CSR (Addr : CSR_Address;
                            Priv : Privilege_Level) return Boolean;

end RISCV.CSR;
