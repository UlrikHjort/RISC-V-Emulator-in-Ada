-- ***************************************************************************
--                      RISCV_Emulator - Privilege Level Tests
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
-- Phase 11: Privilege Levels (M/S/U) unit tests
-- ***************************************************************************

with Ada.Text_IO; use Ada.Text_IO;
with RISCV;       use RISCV;
with RISCV.Memory;
with RISCV.CPU;
with RISCV.CSR;
with RISCV.Disasm;

procedure Test_Privilege is

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

   --  Instruction encoding helpers
   Ecall     : constant Word := 16#00000073#;
   Mret_Insn : constant Word := 16#30200073#;
   Sret_Insn : constant Word := 16#10200073#;
   Wfi_Insn  : constant Word := 16#10500073#;
   --  SFENCE.VMA x0, x0
   Sfence_Vma_Insn : constant Word := 16#12000073#;

   --  ADDI rd, rs1, imm
   function Encode_ADDI (Rd, Rs1 : Register_Index;
                         Imm : Signed_Word) return Word is
      Imm_Bits : constant Word := Word (Imm) and 16#FFF#;
   begin
      return OPCODE_OP_IMM or
             Shift_Left (Word (Rd), 7) or
             Shift_Left (FUNCT3_ADD_SUB, 12) or
             Shift_Left (Word (Rs1), 15) or
             Shift_Left (Imm_Bits, 20);
   end Encode_ADDI;

   --  CSR instruction
   function Encode_CSR (Csr_Addr : CSR.CSR_Address;
                        Rs1_Or_Zimm : Register_Index;
                        Funct3 : Word;
                        Rd : Register_Index) return Word is
   begin
      return OPCODE_SYSTEM or
             Shift_Left (Word (Rd), 7) or
             Shift_Left (Funct3, 12) or
             Shift_Left (Word (Rs1_Or_Zimm), 15) or
             Shift_Left (Word (Csr_Addr), 20);
   end Encode_CSR;

   --  NOP = ADDI x0, x0, 0
   Nop : constant Word := Encode_ADDI (0, 0, 0);

   --  ======================================================================
   --  Test 1: Privilege Init - default M-mode
   --  ======================================================================
   procedure Test_Privilege_Init is
      C : CPU.CPU_State;
      M : Memory.Memory_Unit;
   begin
      Put_Line ("Testing privilege initialization...");
      CPU.Initialize (C, 0);
      Memory.Initialize (M);

      Check (C.Priv_Mode = Machine, "CPU starts in Machine mode");
   end Test_Privilege_Init;

   --  ======================================================================
   --  Test 2: CSR Privilege Checks
   --  ======================================================================
   procedure Test_CSR_Privilege_Checks is
   begin
      Put_Line ("Testing CSR privilege access checks...");

      --  Machine CSRs (0x3xx) require M-mode
      Check (CSR.Can_Access_CSR (CSR.CSR_MSTATUS, Machine),
             "M-mode can access mstatus");
      Check (not CSR.Can_Access_CSR (CSR.CSR_MSTATUS, Supervisor),
             "S-mode cannot access mstatus");
      Check (not CSR.Can_Access_CSR (CSR.CSR_MSTATUS, User),
             "U-mode cannot access mstatus");

      --  Supervisor CSRs (0x1xx) require S-mode or higher
      Check (CSR.Can_Access_CSR (CSR.CSR_SSTATUS, Machine),
             "M-mode can access sstatus");
      Check (CSR.Can_Access_CSR (CSR.CSR_SSTATUS, Supervisor),
             "S-mode can access sstatus");
      Check (not CSR.Can_Access_CSR (CSR.CSR_SSTATUS, User),
             "U-mode cannot access sstatus");

      --  User CSRs (0xCxx) - read-only, accessible from any mode
      Check (CSR.Can_Access_CSR (CSR.CSR_CYCLE, User),
             "U-mode can access cycle");
      Check (CSR.Can_Access_CSR (CSR.CSR_CYCLE, Supervisor),
             "S-mode can access cycle");
      Check (CSR.Can_Access_CSR (CSR.CSR_CYCLE, Machine),
             "M-mode can access cycle");

      --  Machine trap handling CSRs
      Check (CSR.Can_Access_CSR (CSR.CSR_MEPC, Machine),
             "M-mode can access mepc");
      Check (not CSR.Can_Access_CSR (CSR.CSR_MEPC, Supervisor),
             "S-mode cannot access mepc");

      --  Supervisor trap CSRs
      Check (CSR.Can_Access_CSR (CSR.CSR_SEPC, Supervisor),
             "S-mode can access sepc");
      Check (CSR.Can_Access_CSR (CSR.CSR_SEPC, Machine),
             "M-mode can access sepc");
      Check (not CSR.Can_Access_CSR (CSR.CSR_SEPC, User),
             "U-mode cannot access sepc");

      --  Get_Min_Privilege
      Check (CSR.Get_Min_Privilege (CSR.CSR_MSTATUS) = Machine,
             "mstatus requires Machine");
      Check (CSR.Get_Min_Privilege (CSR.CSR_SSTATUS) = Supervisor,
             "sstatus requires Supervisor");
      Check (CSR.Get_Min_Privilege (CSR.CSR_CYCLE) = User,
             "cycle requires User (accessible by all)");
   end Test_CSR_Privilege_Checks;

   --  ======================================================================
   --  Test 3: SSTATUS/SIE/SIP view correctness
   --  ======================================================================
   procedure Test_Supervisor_CSR_Views is
      S : CSR.CSR_State;
   begin
      Put_Line ("Testing supervisor CSR views...");
      CSR.Initialize (S);

      --  Write to MSTATUS and check SSTATUS reflects it
      CSR.Write (S, CSR.CSR_MSTATUS, CSR.MSTATUS_SIE or CSR.MSTATUS_MIE);
      Check ((CSR.Read (S, CSR.CSR_SSTATUS) and CSR.MSTATUS_SIE) /= 0,
             "SSTATUS reflects SIE from MSTATUS");
      Check ((CSR.Read (S, CSR.CSR_SSTATUS) and CSR.MSTATUS_MIE) = 0,
             "SSTATUS does not reflect MIE");

      --  Write to SSTATUS and check MSTATUS updated
      CSR.Write (S, CSR.CSR_MSTATUS, 0);
      CSR.Write (S, CSR.CSR_SSTATUS, CSR.MSTATUS_SIE or CSR.MSTATUS_SPIE);
      Check ((CSR.Read (S, CSR.CSR_MSTATUS) and CSR.MSTATUS_SIE) /= 0,
             "MSTATUS SIE set via SSTATUS write");
      Check ((CSR.Read (S, CSR.CSR_MSTATUS) and CSR.MSTATUS_SPIE) /= 0,
             "MSTATUS SPIE set via SSTATUS write");
      Check ((CSR.Read (S, CSR.CSR_MSTATUS) and CSR.MSTATUS_MIE) = 0,
             "MSTATUS MIE not affected by SSTATUS write");

      --  SIE view of MIE
      CSR.Write (S, CSR.CSR_MIE,
                 CSR.MIE_SSIE or CSR.MIE_MSIE or CSR.MIE_STIE);
      Check (CSR.Read (S, CSR.CSR_SIE) = (CSR.MIE_SSIE or CSR.MIE_STIE),
             "SIE shows only supervisor bits from MIE");

      --  Write to SIE should not affect machine bits
      CSR.Write (S, CSR.CSR_SIE, 0);
      Check ((CSR.Read (S, CSR.CSR_MIE) and CSR.MIE_MSIE) /= 0,
             "Writing SIE preserves MSIE in MIE");
      Check ((CSR.Read (S, CSR.CSR_MIE) and CSR.MIE_SSIE) = 0,
             "Writing SIE clears SSIE in MIE");

      --  SIP view of MIP
      CSR.Write (S, CSR.CSR_MIP,
                 CSR.MIE_SSIE or CSR.MIE_MSIE);
      Check (CSR.Read (S, CSR.CSR_SIP) = CSR.MIE_SSIE,
             "SIP shows only supervisor bits from MIP");
   end Test_Supervisor_CSR_Views;

   --  ======================================================================
   --  Test 4: MRET privilege restore
   --  ======================================================================
   procedure Test_Mret_Privilege_Restore is
      C : CPU.CPU_State;
      M : Memory.Memory_Unit;
   begin
      Put_Line ("Testing MRET privilege restore...");
      Memory.Initialize (M);
      Memory.Add_Region (M, "RAM", 0, 16#10000#);

      --  Test MRET with MPP=0 (User)
      CPU.Initialize (C, 16#100#);
      CSR.Write (C.CSRs, CSR.CSR_MTVEC, 16#100#);
      CSR.Write (C.CSRs, CSR.CSR_MEPC, 16#200#);
      CSR.Write (C.CSRs, CSR.CSR_MSTATUS,
                 CSR.MSTATUS_MPIE);  --  MPP=00 (User), MPIE=1
      Memory.Write_Word (M, 16#100#, Mret_Insn);
      CPU.Step (C, M);
      Check (C.PC = 16#200#, "MRET MPP=0: jumps to MEPC");
      Check (C.Priv_Mode = User, "MRET MPP=0: restores User mode");

      --  Test MRET with MPP=1 (Supervisor)
      CPU.Initialize (C, 16#100#);
      CSR.Write (C.CSRs, CSR.CSR_MTVEC, 16#100#);
      CSR.Write (C.CSRs, CSR.CSR_MEPC, 16#300#);
      CSR.Write (C.CSRs, CSR.CSR_MSTATUS,
                 CSR.MSTATUS_MPIE or Shift_Left (1, 11));  --  MPP=01 (S)
      Memory.Write_Word (M, 16#100#, Mret_Insn);
      CPU.Step (C, M);
      Check (C.PC = 16#300#, "MRET MPP=1: jumps to MEPC");
      Check (C.Priv_Mode = Supervisor, "MRET MPP=1: restores Supervisor mode");

      --  Test MRET with MPP=3 (Machine)
      CPU.Initialize (C, 16#100#);
      CSR.Write (C.CSRs, CSR.CSR_MTVEC, 16#100#);
      CSR.Write (C.CSRs, CSR.CSR_MEPC, 16#400#);
      CSR.Write (C.CSRs, CSR.CSR_MSTATUS,
                 CSR.MSTATUS_MPIE or CSR.MSTATUS_MPP_MASK);  --  MPP=11 (M)
      Memory.Write_Word (M, 16#100#, Mret_Insn);
      CPU.Step (C, M);
      Check (C.PC = 16#400#, "MRET MPP=3: jumps to MEPC");
      Check (C.Priv_Mode = Machine, "MRET MPP=3: restores Machine mode");

      --  After MRET, MPP should be cleared to 0
      Check ((CSR.Read (C.CSRs, CSR.CSR_MSTATUS) and CSR.MSTATUS_MPP_MASK) = 0,
             "MRET clears MPP to 0");
   end Test_Mret_Privilege_Restore;

   --  ======================================================================
   --  Test 5: SRET
   --  ======================================================================
   procedure Test_Sret is
      C : CPU.CPU_State;
      M : Memory.Memory_Unit;
   begin
      Put_Line ("Testing SRET...");
      Memory.Initialize (M);
      Memory.Add_Region (M, "RAM", 0, 16#10000#);

      --  SRET from S-mode with SPP=0 (User)
      CPU.Initialize (C, 16#100#);
      C.Priv_Mode := Supervisor;
      CSR.Write (C.CSRs, CSR.CSR_STVEC, 16#100#);
      CSR.Write (C.CSRs, CSR.CSR_SEPC, 16#500#);
      CSR.Write (C.CSRs, CSR.CSR_MSTATUS, CSR.MSTATUS_SPIE);  --  SPP=0
      Memory.Write_Word (M, 16#100#, Sret_Insn);
      CPU.Step (C, M);
      Check (C.PC = 16#500#, "SRET SPP=0: jumps to SEPC");
      Check (C.Priv_Mode = User, "SRET SPP=0: restores User mode");

      --  SRET from S-mode with SPP=1 (Supervisor)
      CPU.Initialize (C, 16#100#);
      C.Priv_Mode := Supervisor;
      CSR.Write (C.CSRs, CSR.CSR_STVEC, 16#100#);
      CSR.Write (C.CSRs, CSR.CSR_SEPC, 16#600#);
      CSR.Write (C.CSRs, CSR.CSR_MSTATUS,
                 CSR.MSTATUS_SPIE or CSR.MSTATUS_SPP);  --  SPP=1
      Memory.Write_Word (M, 16#100#, Sret_Insn);
      CPU.Step (C, M);
      Check (C.PC = 16#600#, "SRET SPP=1: jumps to SEPC");
      Check (C.Priv_Mode = Supervisor, "SRET SPP=1: restores Supervisor mode");

      --  SRET clears SPP
      Check ((CSR.Read (C.CSRs, CSR.CSR_MSTATUS) and CSR.MSTATUS_SPP) = 0,
             "SRET clears SPP");

      --  SRET restores SIE from SPIE, sets SPIE=1
      Check ((CSR.Read (C.CSRs, CSR.CSR_MSTATUS) and CSR.MSTATUS_SIE) /= 0,
             "SRET restores SIE from SPIE");
      Check ((CSR.Read (C.CSRs, CSR.CSR_MSTATUS) and CSR.MSTATUS_SPIE) /= 0,
             "SRET sets SPIE=1");

      --  SRET from M-mode is legal
      CPU.Initialize (C, 16#100#);
      CSR.Write (C.CSRs, CSR.CSR_SEPC, 16#700#);
      CSR.Write (C.CSRs, CSR.CSR_MSTATUS, CSR.MSTATUS_SPP);
      Memory.Write_Word (M, 16#100#, Sret_Insn);
      CPU.Step (C, M);
      Check (C.PC = 16#700#, "SRET from M-mode: legal, jumps to SEPC");
   end Test_Sret;

   --  ======================================================================
   --  Test 6: SRET illegal from U-mode
   --  ======================================================================
   procedure Test_Sret_Illegal_From_U is
      C : CPU.CPU_State;
      M : Memory.Memory_Unit;
   begin
      Put_Line ("Testing SRET illegal from U-mode...");
      Memory.Initialize (M);
      Memory.Add_Region (M, "RAM", 0, 16#10000#);

      CPU.Initialize (C, 16#100#);
      C.Priv_Mode := User;
      CSR.Write (C.CSRs, CSR.CSR_MTVEC, 16#2000#);
      CSR.Write (C.CSRs, CSR.CSR_SEPC, 16#500#);
      Memory.Write_Word (M, 16#100#, Sret_Insn);
      Memory.Write_Word (M, 16#2000#, Nop);
      CPU.Step (C, M);
      --  Should trap as illegal instruction
      Check (C.PC = 16#2000#, "SRET from U-mode: traps to handler");
      Check (CSR.Read (C.CSRs, CSR.CSR_MCAUSE) = CSR.CAUSE_ILLEGAL_INSN,
             "SRET from U-mode: cause = illegal instruction");
   end Test_Sret_Illegal_From_U;

   --  ======================================================================
   --  Test 7: ECALL routing by privilege
   --  ======================================================================
   procedure Test_Ecall_Routing is
      C : CPU.CPU_State;
      M : Memory.Memory_Unit;
   begin
      Put_Line ("Testing ECALL routing by privilege...");
      Memory.Initialize (M);
      Memory.Add_Region (M, "RAM", 0, 16#10000#);
      --  These cases observe the architectural trap, so the SBI shim
      --  must be off: with it on, an S-mode ECALL is serviced as a
      --  firmware call and never traps at all.
      M.SBI_Enabled := False;

      --  ECALL from M-mode -> cause 11
      CPU.Initialize (C, 16#100#);
      CSR.Write (C.CSRs, CSR.CSR_MTVEC, 16#2000#);
      Memory.Write_Word (M, 16#100#, Ecall);
      Memory.Write_Word (M, 16#2000#, Nop);
      CPU.Step (C, M);
      Check (CSR.Read (C.CSRs, CSR.CSR_MCAUSE) = 11,
             "ECALL from M-mode: cause = 11");

      --  ECALL from S-mode -> cause 9
      CPU.Initialize (C, 16#100#);
      C.Priv_Mode := Supervisor;
      CSR.Write (C.CSRs, CSR.CSR_MTVEC, 16#2000#);
      Memory.Write_Word (M, 16#100#, Ecall);
      CPU.Step (C, M);
      Check (CSR.Read (C.CSRs, CSR.CSR_MCAUSE) = 9,
             "ECALL from S-mode: cause = 9");

      --  ECALL from U-mode -> cause 8
      CPU.Initialize (C, 16#100#);
      C.Priv_Mode := User;
      CSR.Write (C.CSRs, CSR.CSR_MTVEC, 16#2000#);
      Memory.Write_Word (M, 16#100#, Ecall);
      CPU.Step (C, M);
      Check (CSR.Read (C.CSRs, CSR.CSR_MCAUSE) = 8,
             "ECALL from U-mode: cause = 8");
   end Test_Ecall_Routing;

   --  ======================================================================
   --  Test 8: Trap delegation via medeleg
   --  ======================================================================
   procedure Test_Trap_Delegation is
      C : CPU.CPU_State;
      M : Memory.Memory_Unit;
   begin
      Put_Line ("Testing trap delegation...");
      Memory.Initialize (M);
      Memory.Add_Region (M, "RAM", 0, 16#10000#);
      --  These cases observe the architectural trap, so the SBI shim
      --  must be off: with it on, an S-mode ECALL is serviced as a
      --  firmware call and never traps at all.
      M.SBI_Enabled := False;

      --  Delegate ECALL-from-U (cause 8) to S-mode
      CPU.Initialize (C, 16#100#);
      C.Priv_Mode := User;
      CSR.Write (C.CSRs, CSR.CSR_MTVEC, 16#3000#);    --  M-mode handler
      CSR.Write (C.CSRs, CSR.CSR_STVEC, 16#4000#);    --  S-mode handler
      CSR.Write (C.CSRs, CSR.CSR_MEDELEG,
                 Shift_Left (1, 8));  --  Delegate ecall-U
      Memory.Write_Word (M, 16#100#, Ecall);
      Memory.Write_Word (M, 16#3000#, Nop);
      Memory.Write_Word (M, 16#4000#, Nop);
      CPU.Step (C, M);
      Check (C.PC = 16#4000#, "Delegated ECALL-U: goes to stvec");
      Check (C.Priv_Mode = Supervisor,
             "Delegated trap: enters Supervisor mode");
      Check (CSR.Read (C.CSRs, CSR.CSR_SCAUSE) = 8,
             "Delegated trap: scause = 8");
      Check (CSR.Read (C.CSRs, CSR.CSR_SEPC) = 16#100#,
             "Delegated trap: sepc = fault PC");

      --  Non-delegated trap from S-mode goes to M-mode
      CPU.Initialize (C, 16#100#);
      C.Priv_Mode := Supervisor;
      CSR.Write (C.CSRs, CSR.CSR_MTVEC, 16#3000#);
      CSR.Write (C.CSRs, CSR.CSR_STVEC, 16#4000#);
      CSR.Write (C.CSRs, CSR.CSR_MEDELEG, 0);  --  No delegation
      Memory.Write_Word (M, 16#100#, Ecall);
      CPU.Step (C, M);
      Check (C.PC = 16#3000#, "Non-delegated ECALL-S: goes to mtvec");
      Check (C.Priv_Mode = Machine,
             "Non-delegated trap: enters Machine mode");

      --  Traps from M-mode are NEVER delegated
      CPU.Initialize (C, 16#100#);
      CSR.Write (C.CSRs, CSR.CSR_MTVEC, 16#3000#);
      CSR.Write (C.CSRs, CSR.CSR_STVEC, 16#4000#);
      CSR.Write (C.CSRs, CSR.CSR_MEDELEG, 16#FFFFFFFF#);  --  Delegate all
      Memory.Write_Word (M, 16#100#, Ecall);
      CPU.Step (C, M);
      Check (C.PC = 16#3000#, "M-mode trap: never delegated, goes to mtvec");
      Check (C.Priv_Mode = Machine,
             "M-mode trap: stays in Machine mode");
   end Test_Trap_Delegation;

   --  ======================================================================
   --  Test 9: Trap delegation saves correct MPP/SPP
   --  ======================================================================
   procedure Test_Delegation_Status_Bits is
      C : CPU.CPU_State;
      M : Memory.Memory_Unit;
      Mstatus : Word;
   begin
      Put_Line ("Testing delegation status bit updates...");
      Memory.Initialize (M);
      Memory.Add_Region (M, "RAM", 0, 16#10000#);
      --  These cases observe the architectural trap, so the SBI shim
      --  must be off: with it on, an S-mode ECALL is serviced as a
      --  firmware call and never traps at all.
      M.SBI_Enabled := False;

      --  Delegated trap from U-mode: SPP should be 0 (User)
      CPU.Initialize (C, 16#100#);
      C.Priv_Mode := User;
      CSR.Write (C.CSRs, CSR.CSR_MTVEC, 16#3000#);
      CSR.Write (C.CSRs, CSR.CSR_STVEC, 16#4000#);
      CSR.Write (C.CSRs, CSR.CSR_MEDELEG, Shift_Left (1, 8));
      Memory.Write_Word (M, 16#100#, Ecall);
      Memory.Write_Word (M, 16#4000#, Nop);
      CPU.Step (C, M);
      Mstatus := CSR.Read (C.CSRs, CSR.CSR_MSTATUS);
      Check ((Mstatus and CSR.MSTATUS_SPP) = 0,
             "Delegated from U: SPP = 0");

      --  Delegated trap from S-mode: SPP should be 1 (Supervisor)
      CPU.Initialize (C, 16#100#);
      C.Priv_Mode := Supervisor;
      CSR.Write (C.CSRs, CSR.CSR_MTVEC, 16#3000#);
      CSR.Write (C.CSRs, CSR.CSR_STVEC, 16#4000#);
      CSR.Write (C.CSRs, CSR.CSR_MEDELEG, Shift_Left (1, 9));
      Memory.Write_Word (M, 16#100#, Ecall);
      CPU.Step (C, M);
      Mstatus := CSR.Read (C.CSRs, CSR.CSR_MSTATUS);
      Check ((Mstatus and CSR.MSTATUS_SPP) /= 0,
             "Delegated from S: SPP = 1");

      --  Non-delegated trap from U-mode: MPP should be 0 (User)
      CPU.Initialize (C, 16#100#);
      C.Priv_Mode := User;
      CSR.Write (C.CSRs, CSR.CSR_MTVEC, 16#3000#);
      CSR.Write (C.CSRs, CSR.CSR_MEDELEG, 0);
      Memory.Write_Word (M, 16#100#, Ecall);
      Memory.Write_Word (M, 16#3000#, Nop);
      CPU.Step (C, M);
      Mstatus := CSR.Read (C.CSRs, CSR.CSR_MSTATUS);
      Check ((Mstatus and CSR.MSTATUS_MPP_MASK) = 0,
             "Non-delegated from U: MPP = 0 (User)");

      --  Non-delegated trap from S-mode: MPP should be 01
      CPU.Initialize (C, 16#100#);
      C.Priv_Mode := Supervisor;
      CSR.Write (C.CSRs, CSR.CSR_MTVEC, 16#3000#);
      CSR.Write (C.CSRs, CSR.CSR_MEDELEG, 0);
      Memory.Write_Word (M, 16#100#, Ecall);
      CPU.Step (C, M);
      Mstatus := CSR.Read (C.CSRs, CSR.CSR_MSTATUS);
      Check ((Mstatus and CSR.MSTATUS_MPP_MASK) = Shift_Left (1, 11),
             "Non-delegated from S: MPP = 01 (Supervisor)");
   end Test_Delegation_Status_Bits;

   --  ======================================================================
   --  Test 10: Interrupt delegation via mideleg
   --  ======================================================================
   procedure Test_Interrupt_Delegation is
      C : CPU.CPU_State;
      M : Memory.Memory_Unit;
   begin
      Put_Line ("Testing interrupt delegation...");
      Memory.Initialize (M);
      Memory.Add_Region (M, "RAM", 0, 16#10000#);

      --  Delegate S-mode software interrupt
      CPU.Initialize (C, 16#100#);
      C.Priv_Mode := Supervisor;
      CSR.Write (C.CSRs, CSR.CSR_MTVEC, 16#3000#);
      CSR.Write (C.CSRs, CSR.CSR_STVEC, 16#4000#);
      CSR.Write (C.CSRs, CSR.CSR_MIDELEG, CSR.MIE_SSIE);
      CSR.Write (C.CSRs, CSR.CSR_MIE, CSR.MIE_SSIE);
      CSR.Write (C.CSRs, CSR.CSR_MIP, CSR.MIE_SSIE);
      CSR.Write (C.CSRs, CSR.CSR_MSTATUS, CSR.MSTATUS_SIE);
      Memory.Write_Word (M, 16#100#, Nop);
      Memory.Write_Word (M, 16#3000#, Nop);
      Memory.Write_Word (M, 16#4000#, Nop);
      declare
         Taken : Boolean;
      begin
         Taken := CPU.Check_Interrupts (C, M);
         Check (Taken, "Delegated S-SW interrupt: taken");
      end;
      Check (C.PC = 16#4000#,
             "Delegated S-SW interrupt: goes to stvec");
      Check (C.Priv_Mode = Supervisor,
             "Delegated S-SW interrupt: stays in S-mode");
   end Test_Interrupt_Delegation;

   --  ======================================================================
   --  Test 11: WFI as NOP
   --  ======================================================================
   procedure Test_Wfi is
      C : CPU.CPU_State;
      M : Memory.Memory_Unit;
   begin
      Put_Line ("Testing WFI as NOP...");
      Memory.Initialize (M);
      Memory.Add_Region (M, "RAM", 0, 16#10000#);

      CPU.Initialize (C, 16#100#);
      Memory.Write_Word (M, 16#100#, Wfi_Insn);
      CPU.Step (C, M);
      Check (C.PC = 16#104#, "WFI advances PC by 4");
      Check (not C.Halted, "WFI does not halt");
   end Test_Wfi;

   --  ======================================================================
   --  Test 12: SFENCE.VMA as NOP
   --  ======================================================================
   procedure Test_Sfence_Vma is
      C : CPU.CPU_State;
      M : Memory.Memory_Unit;
   begin
      Put_Line ("Testing SFENCE.VMA as NOP...");
      Memory.Initialize (M);
      Memory.Add_Region (M, "RAM", 0, 16#10000#);

      CPU.Initialize (C, 16#100#);
      Memory.Write_Word (M, 16#100#, Sfence_Vma_Insn);
      CPU.Step (C, M);
      Check (C.PC = 16#104#, "SFENCE.VMA advances PC by 4");
      Check (not C.Halted, "SFENCE.VMA does not halt");
   end Test_Sfence_Vma;

   --  ======================================================================
   --  Test 13: CSR privilege check in Step (S-mode accessing M-mode CSR)
   --  ======================================================================
   procedure Test_CSR_Access_Enforcement is
      C : CPU.CPU_State;
      M : Memory.Memory_Unit;
   begin
      Put_Line ("Testing CSR access enforcement in execution...");
      Memory.Initialize (M);
      Memory.Add_Region (M, "RAM", 0, 16#10000#);

      --  S-mode trying to read mstatus (0x300) -> illegal
      CPU.Initialize (C, 16#100#);
      C.Priv_Mode := Supervisor;
      CSR.Write (C.CSRs, CSR.CSR_MTVEC, 16#2000#);
      --  CSRRS x1, mstatus, x0 (read mstatus)
      Memory.Write_Word (M, 16#100#,
         Encode_CSR (CSR.CSR_MSTATUS, 0, FUNCT3_CSRRS, 1));
      Memory.Write_Word (M, 16#2000#, Nop);
      CPU.Step (C, M);
      Check (C.PC = 16#2000#, "S-mode read of mstatus: traps");
      Check (CSR.Read (C.CSRs, CSR.CSR_MCAUSE) = CSR.CAUSE_ILLEGAL_INSN,
             "S-mode read of mstatus: illegal instruction");

      --  S-mode reading sstatus (0x100) -> OK
      CPU.Initialize (C, 16#100#);
      C.Priv_Mode := Supervisor;
      CSR.Write (C.CSRs, CSR.CSR_MTVEC, 16#2000#);
      Memory.Write_Word (M, 16#100#,
         Encode_CSR (CSR.CSR_SSTATUS, 0, FUNCT3_CSRRS, 1));
      CPU.Step (C, M);
      Check (C.PC = 16#104#, "S-mode read of sstatus: succeeds");

      --  U-mode trying to read sstatus (0x100) -> illegal
      CPU.Initialize (C, 16#100#);
      C.Priv_Mode := User;
      CSR.Write (C.CSRs, CSR.CSR_MTVEC, 16#2000#);
      Memory.Write_Word (M, 16#100#,
         Encode_CSR (CSR.CSR_SSTATUS, 0, FUNCT3_CSRRS, 1));
      CPU.Step (C, M);
      Check (C.PC = 16#2000#, "U-mode read of sstatus: traps");
   end Test_CSR_Access_Enforcement;

   --  ======================================================================
   --  Test 14: MRET illegal from non-M-mode
   --  ======================================================================
   procedure Test_Mret_Illegal_From_S is
      C : CPU.CPU_State;
      M : Memory.Memory_Unit;
   begin
      Put_Line ("Testing MRET illegal from non-M-mode...");
      Memory.Initialize (M);
      Memory.Add_Region (M, "RAM", 0, 16#10000#);

      --  MRET from S-mode should trap
      CPU.Initialize (C, 16#100#);
      C.Priv_Mode := Supervisor;
      CSR.Write (C.CSRs, CSR.CSR_MTVEC, 16#2000#);
      Memory.Write_Word (M, 16#100#, Mret_Insn);
      Memory.Write_Word (M, 16#2000#, Nop);
      CPU.Step (C, M);
      Check (C.PC = 16#2000#, "MRET from S-mode: traps");
      Check (CSR.Read (C.CSRs, CSR.CSR_MCAUSE) = CSR.CAUSE_ILLEGAL_INSN,
             "MRET from S-mode: cause = illegal instruction");
   end Test_Mret_Illegal_From_S;

   --  ======================================================================
   --  Test 15: Trap_Entry saves current privilege correctly
   --  ======================================================================
   procedure Test_Trap_Entry_Saves_Priv is
      C : CPU.CPU_State;
      M : Memory.Memory_Unit;
      Mstatus : Word;
   begin
      Put_Line ("Testing Trap_Entry saves privilege...");
      Memory.Initialize (M);
      Memory.Add_Region (M, "RAM", 0, 16#10000#);

      --  Trap from M-mode: MPP should be 11
      CPU.Initialize (C, 16#100#);
      CSR.Write (C.CSRs, CSR.CSR_MTVEC, 16#2000#);
      Memory.Write_Word (M, 16#100#, Ecall);
      Memory.Write_Word (M, 16#2000#, Nop);
      CPU.Step (C, M);
      Mstatus := CSR.Read (C.CSRs, CSR.CSR_MSTATUS);
      Check ((Mstatus and CSR.MSTATUS_MPP_MASK) = CSR.MSTATUS_MPP_MASK,
             "Trap from M: MPP = 11 (Machine)");
   end Test_Trap_Entry_Saves_Priv;

   --  ======================================================================
   --  Test 16: Full round-trip M -> S -> U -> trap -> S -> SRET -> U
   --  ======================================================================
   procedure Test_Full_Round_Trip is
      C : CPU.CPU_State;
      M : Memory.Memory_Unit;
   begin
      Put_Line ("Testing full privilege round-trip...");
      Memory.Initialize (M);
      Memory.Add_Region (M, "RAM", 0, 16#10000#);

      --  Start in M-mode
      CPU.Initialize (C, 16#100#);
      CSR.Write (C.CSRs, CSR.CSR_MTVEC, 16#3000#);
      CSR.Write (C.CSRs, CSR.CSR_STVEC, 16#4000#);

      --  Step 1: MRET to S-mode
      CSR.Write (C.CSRs, CSR.CSR_MEPC, 16#200#);
      CSR.Write (C.CSRs, CSR.CSR_MSTATUS,
                 CSR.MSTATUS_MPIE or Shift_Left (1, 11));  --  MPP=S
      Memory.Write_Word (M, 16#100#, Mret_Insn);
      CPU.Step (C, M);
      Check (C.Priv_Mode = Supervisor, "Round trip: M->S via MRET");
      Check (C.PC = 16#200#, "Round trip: PC = 0x200");

      --  Step 2: SRET from S to U-mode
      CSR.Write (C.CSRs, CSR.CSR_SEPC, 16#300#);
      --  Clear SPP (restore to User)
      declare
         Ms : Word := CSR.Read (C.CSRs, CSR.CSR_MSTATUS);
      begin
         Ms := Ms and not CSR.MSTATUS_SPP;
         Ms := Ms or CSR.MSTATUS_SPIE;
         CSR.Write (C.CSRs, CSR.CSR_MSTATUS, Ms);
      end;
      Memory.Write_Word (M, 16#200#, Sret_Insn);
      CPU.Step (C, M);
      Check (C.Priv_Mode = User, "Round trip: S->U via SRET");
      Check (C.PC = 16#300#, "Round trip: PC = 0x300");

      --  Step 3: ECALL from U-mode, delegated to S-mode
      CSR.Write (C.CSRs, CSR.CSR_MEDELEG,
                 Shift_Left (1, 8));  --  Delegate ecall-U
      Memory.Write_Word (M, 16#300#, Ecall);
      Memory.Write_Word (M, 16#4000#, Nop);
      CPU.Step (C, M);
      Check (C.Priv_Mode = Supervisor,
             "Round trip: U->(trap)->S via delegation");
      Check (C.PC = 16#4000#, "Round trip: PC = stvec");

      --  Step 4: SRET back to U-mode
      CSR.Write (C.CSRs, CSR.CSR_SEPC, 16#304#);
      --  SPP should be 0 from the delegation
      Memory.Write_Word (M, 16#4000#, Sret_Insn);
      CPU.Step (C, M);
      Check (C.Priv_Mode = User, "Round trip: S->U via SRET (return)");
      Check (C.PC = 16#304#, "Round trip: PC = 0x304 (after ecall)");
   end Test_Full_Round_Trip;

   --  ======================================================================
   --  Test 17: Disassembly of SRET, WFI, SFENCE.VMA
   --  ======================================================================
   procedure Test_Disassembly is
   begin
      Put_Line ("Testing disassembly...");

      Check (Disasm.Disassemble (Sret_Insn, 0) = "sret",
             "Disassemble SRET");
      Check (Disasm.Disassemble (Wfi_Insn, 0) = "wfi",
             "Disassemble WFI");
      Check (Disasm.Disassemble (Sfence_Vma_Insn, 0) = "sfence.vma",
             "Disassemble SFENCE.VMA");
      Check (Disasm.Disassemble (Mret_Insn, 0) = "mret",
             "Disassemble MRET (still works)");
   end Test_Disassembly;

   --  ======================================================================
   --  Test 18: CSR Name for supervisor CSRs
   --  ======================================================================
   procedure Test_CSR_Names is
   begin
      Put_Line ("Testing CSR names for supervisor CSRs...");
      Check (CSR.CSR_Name (CSR.CSR_SSTATUS) = "sstatus",
             "CSR name: sstatus");
      Check (CSR.CSR_Name (CSR.CSR_SIE) = "sie",
             "CSR name: sie");
      Check (CSR.CSR_Name (CSR.CSR_STVEC) = "stvec",
             "CSR name: stvec");
      Check (CSR.CSR_Name (CSR.CSR_SSCRATCH) = "sscratch",
             "CSR name: sscratch");
      Check (CSR.CSR_Name (CSR.CSR_SEPC) = "sepc",
             "CSR name: sepc");
      Check (CSR.CSR_Name (CSR.CSR_SCAUSE) = "scause",
             "CSR name: scause");
      Check (CSR.CSR_Name (CSR.CSR_STVAL) = "stval",
             "CSR name: stval");
      Check (CSR.CSR_Name (CSR.CSR_SIP) = "sip",
             "CSR name: sip");
      Check (CSR.CSR_Name (CSR.CSR_SATP) = "satp",
             "CSR name: satp");
      Check (CSR.CSR_Name (CSR.CSR_MEDELEG) = "medeleg",
             "CSR name: medeleg");
      Check (CSR.CSR_Name (CSR.CSR_MIDELEG) = "mideleg",
             "CSR name: mideleg");
   end Test_CSR_Names;

   --  ======================================================================
   --  Test 19: Privilege-aware interrupt enables
   --  ======================================================================
   procedure Test_Privilege_Interrupt_Enable is
      C : CPU.CPU_State;
      M : Memory.Memory_Unit;
      Taken : Boolean;
   begin
      Put_Line ("Testing privilege-aware interrupt enables...");
      Memory.Initialize (M);
      Memory.Add_Region (M, "RAM", 0, 16#10000#);

      --  M-mode with MIE=0: M-mode interrupts not taken
      CPU.Initialize (C, 16#100#);
      CSR.Write (C.CSRs, CSR.CSR_MTVEC, 16#2000#);
      CSR.Write (C.CSRs, CSR.CSR_MSTATUS, 0);  --  MIE=0
      CSR.Write (C.CSRs, CSR.CSR_MIE, CSR.MIE_MSIE);
      CSR.Write (C.CSRs, CSR.CSR_MIP, CSR.MIE_MSIE);
      Memory.Write_Word (M, 16#100#, Nop);
      Memory.Write_Word (M, 16#2000#, Nop);
      Taken := CPU.Check_Interrupts (C, M);
      Check (not Taken, "M-mode MIE=0: M-interrupt not taken");

      --  S-mode: M-mode interrupts always taken regardless of MIE
      CPU.Initialize (C, 16#100#);
      C.Priv_Mode := Supervisor;
      CSR.Write (C.CSRs, CSR.CSR_MTVEC, 16#2000#);
      CSR.Write (C.CSRs, CSR.CSR_MSTATUS, 0);  --  MIE=0, SIE=0
      CSR.Write (C.CSRs, CSR.CSR_MIE, CSR.MIE_MSIE);
      CSR.Write (C.CSRs, CSR.CSR_MIP, CSR.MIE_MSIE);
      Taken := CPU.Check_Interrupts (C, M);
      Check (Taken, "S-mode: M-interrupt taken even with MIE=0");

      --  U-mode: All interrupts taken
      CPU.Initialize (C, 16#100#);
      C.Priv_Mode := User;
      CSR.Write (C.CSRs, CSR.CSR_MTVEC, 16#2000#);
      CSR.Write (C.CSRs, CSR.CSR_MSTATUS, 0);
      CSR.Write (C.CSRs, CSR.CSR_MIE, CSR.MIE_MSIE);
      CSR.Write (C.CSRs, CSR.CSR_MIP, CSR.MIE_MSIE);
      Taken := CPU.Check_Interrupts (C, M);
      Check (Taken, "U-mode: M-interrupt taken");

      --  S-mode with SIE=0: S-mode interrupts not taken
      CPU.Initialize (C, 16#100#);
      C.Priv_Mode := Supervisor;
      CSR.Write (C.CSRs, CSR.CSR_MTVEC, 16#2000#);
      CSR.Write (C.CSRs, CSR.CSR_STVEC, 16#4000#);
      CSR.Write (C.CSRs, CSR.CSR_MSTATUS, 0);  --  SIE=0
      CSR.Write (C.CSRs, CSR.CSR_MIE, CSR.MIE_SSIE);
      CSR.Write (C.CSRs, CSR.CSR_MIP, CSR.MIE_SSIE);
      CSR.Write (C.CSRs, CSR.CSR_MIDELEG, CSR.MIE_SSIE);
      Memory.Write_Word (M, 16#4000#, Nop);
      Taken := CPU.Check_Interrupts (C, M);
      Check (not Taken, "S-mode SIE=0: S-interrupt not taken");
   end Test_Privilege_Interrupt_Enable;

   --  ======================================================================
   --  Test 20: Delegation with S-mode SIE/SPIE handling
   --  ======================================================================
   procedure Test_Delegation_SIE_Handling is
      C : CPU.CPU_State;
      M : Memory.Memory_Unit;
      Mstatus : Word;
   begin
      Put_Line ("Testing delegation SIE/SPIE handling...");
      Memory.Initialize (M);
      Memory.Add_Region (M, "RAM", 0, 16#10000#);

      --  Delegated trap should save SIE to SPIE, clear SIE
      CPU.Initialize (C, 16#100#);
      C.Priv_Mode := User;
      CSR.Write (C.CSRs, CSR.CSR_MTVEC, 16#3000#);
      CSR.Write (C.CSRs, CSR.CSR_STVEC, 16#4000#);
      CSR.Write (C.CSRs, CSR.CSR_MEDELEG, Shift_Left (1, 8));
      CSR.Write (C.CSRs, CSR.CSR_MSTATUS, CSR.MSTATUS_SIE);  --  SIE=1
      Memory.Write_Word (M, 16#100#, Ecall);
      Memory.Write_Word (M, 16#4000#, Nop);
      CPU.Step (C, M);
      Mstatus := CSR.Read (C.CSRs, CSR.CSR_MSTATUS);
      Check ((Mstatus and CSR.MSTATUS_SIE) = 0,
             "Delegated trap: SIE cleared");
      Check ((Mstatus and CSR.MSTATUS_SPIE) /= 0,
             "Delegated trap: SPIE = old SIE (1)");
   end Test_Delegation_SIE_Handling;

   --  ======================================================================
   --  Test 21: Initialization of delegation CSRs
   --  ======================================================================
   procedure Test_Deleg_Init is
      S : CSR.CSR_State;
   begin
      Put_Line ("Testing delegation CSR initialization...");
      CSR.Initialize (S);
      Check (CSR.Read (S, CSR.CSR_MEDELEG) = 0,
             "medeleg initialized to 0");
      Check (CSR.Read (S, CSR.CSR_MIDELEG) = 0,
             "mideleg initialized to 0");
   end Test_Deleg_Init;

   --  ======================================================================
   --  Test 22: MISA includes S and U bits
   --  ======================================================================
   procedure Test_Misa_SU is
      S : CSR.CSR_State;
      Misa : Word;
   begin
      Put_Line ("Testing MISA S/U extension bits...");
      CSR.Initialize (S);
      Misa := CSR.Read (S, CSR.CSR_MISA);
      Check ((Misa and Shift_Left (1, 18)) /= 0,
             "MISA has S bit set");
      Check ((Misa and Shift_Left (1, 20)) /= 0,
             "MISA has U bit set");
   end Test_Misa_SU;

begin
   Put_Line ("=== RISC-V Privilege Level Tests ===");
   Put_Line ("");

   Test_Privilege_Init;
   Test_CSR_Privilege_Checks;
   Test_Supervisor_CSR_Views;
   Test_Mret_Privilege_Restore;
   Test_Sret;
   Test_Sret_Illegal_From_U;
   Test_Ecall_Routing;
   Test_Trap_Delegation;
   Test_Delegation_Status_Bits;
   Test_Interrupt_Delegation;
   Test_Wfi;
   Test_Sfence_Vma;
   Test_CSR_Access_Enforcement;
   Test_Mret_Illegal_From_S;
   Test_Trap_Entry_Saves_Priv;
   Test_Full_Round_Trip;
   Test_Disassembly;
   Test_CSR_Names;
   Test_Privilege_Interrupt_Enable;
   Test_Delegation_SIE_Handling;
   Test_Deleg_Init;
   Test_Misa_SU;

   Put_Line ("");
   Put_Line ("=== Results: " & Natural'Image (Passed_Tests) & " passed," &
             Natural'Image (Failed_Tests) & " failed, out of" &
             Natural'Image (Total_Tests) & " tests ===");

   if Failed_Tests > 0 then
      Put_Line ("SOME TESTS FAILED!");
   else
      Put_Line ("All tests passed.");
   end if;
end Test_Privilege;
