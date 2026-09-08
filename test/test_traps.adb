-- ***************************************************************************
--                      RISCV_Emulator - Trap/Interrupt Tests
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
-- Phase 10: Trap and Interrupt Handling unit tests
-- ***************************************************************************

with Ada.Text_IO; use Ada.Text_IO;
with RISCV;       use RISCV;
with RISCV.Memory;
with RISCV.CPU;
with RISCV.CSR;
with RISCV.Disasm;

procedure Test_Traps is

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
   --  ECALL = 0x00000073
   Ecall : constant Word := 16#00000073#;
   --  EBREAK = 0x00100073
   Ebreak : constant Word := 16#00100073#;
   --  MRET = 0x30200073
   Mret_Insn : constant Word := 16#30200073#;

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

   --  LW rd, imm(rs1)
   function Encode_LW (Rd, Rs1 : Register_Index;
                       Imm : Signed_Word) return Word is
      Imm_Bits : constant Word := Word (Imm) and 16#FFF#;
   begin
      return OPCODE_LOAD or
             Shift_Left (Word (Rd), 7) or
             Shift_Left (FUNCT3_LW, 12) or
             Shift_Left (Word (Rs1), 15) or
             Shift_Left (Imm_Bits, 20);
   end Encode_LW;

   --  SW rs2, imm(rs1)
   function Encode_SW (Rs1, Rs2 : Register_Index;
                       Imm : Signed_Word) return Word is
      Imm_Bits : constant Word := Word (Imm) and 16#FFF#;
   begin
      return OPCODE_STORE or
             Shift_Left (Imm_Bits and 16#1F#, 7) or
             Shift_Left (FUNCT3_SW, 12) or
             Shift_Left (Word (Rs1), 15) or
             Shift_Left (Word (Rs2), 20) or
             Shift_Left (Shift_Right (Imm_Bits, 5), 25);
   end Encode_SW;

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

   --  ======================================================================
   --  Test Trap_Entry basics
   --  ======================================================================
   procedure Test_Trap_Entry_Basic is
      C : CPU.CPU_State;
      M : Memory.Memory_Unit;
   begin
      Put_Line ("Testing trap entry basics...");

      --  Setup: set up mtvec, enable trap handling
      CPU.Initialize (C, 16#1000#);
      Memory.Initialize (M);
      Memory.Add_Region (M, "RAM", 0, 16#10000#);

      --  Set mtvec to 0x2000 (direct mode)
      CSR.Write (C.CSRs, CSR.CSR_MTVEC, 16#2000#);

      --  Enable machine interrupts
      CSR.Write (C.CSRs, CSR.CSR_MSTATUS, CSR.MSTATUS_MIE);

      --  Place ECALL at 0x1000
      Memory.Write_Word (M, 16#1000#, Ecall);

      --  Execute ECALL
      CPU.Step (C, M, False, CPU.Trace_Config'(Enabled => False, others => <>));

      --  Verify trap state
      Check (CSR.Read (C.CSRs, CSR.CSR_MEPC) = 16#1000#,
             "ECALL: mepc saved");
      Check (CSR.Read (C.CSRs, CSR.CSR_MCAUSE) = CSR.CAUSE_ECALL_M,
             "ECALL: mcause = 11 (ecall-M)");
      Check (C.PC = 16#2000#,
             "ECALL: PC jumps to mtvec");
      Check (not C.Halted,
             "ECALL: CPU not halted");
      Check (C.Exception_Code = No_Exception,
             "ECALL: exception cleared");

      --  Verify mstatus: MIE cleared, MPIE set, MPP=11
      declare
         Ms : constant Word := CSR.Read (C.CSRs, CSR.CSR_MSTATUS);
      begin
         Check ((Ms and CSR.MSTATUS_MIE) = 0,
                "ECALL: MIE cleared");
         Check ((Ms and CSR.MSTATUS_MPIE) /= 0,
                "ECALL: MPIE saved old MIE");
         Check ((Ms and CSR.MSTATUS_MPP_MASK) = CSR.MSTATUS_MPP_MASK,
                "ECALL: MPP = 11 (M-mode)");
      end;
   end Test_Trap_Entry_Basic;

   --  ======================================================================
   --  Test EBREAK trap
   --  ======================================================================
   procedure Test_Ebreak_Trap is
      C : CPU.CPU_State;
      M : Memory.Memory_Unit;
   begin
      Put_Line ("Testing EBREAK trap...");

      CPU.Initialize (C, 16#1000#);
      Memory.Initialize (M);
      Memory.Add_Region (M, "RAM", 0, 16#10000#);

      CSR.Write (C.CSRs, CSR.CSR_MTVEC, 16#3000#);
      Memory.Write_Word (M, 16#1000#, Ebreak);

      CPU.Step (C, M, False, CPU.Trace_Config'(Enabled => False, others => <>));

      Check (CSR.Read (C.CSRs, CSR.CSR_MCAUSE) = CSR.CAUSE_BREAKPOINT,
             "EBREAK: mcause = 3 (breakpoint)");
      Check (CSR.Read (C.CSRs, CSR.CSR_MEPC) = 16#1000#,
             "EBREAK: mepc saved");
      Check (CSR.Read (C.CSRs, CSR.CSR_MTVAL) = 16#1000#,
             "EBREAK: mtval = PC");
      Check (C.PC = 16#3000#,
             "EBREAK: PC jumps to mtvec");
      Check (not C.Halted,
             "EBREAK: CPU not halted");
   end Test_Ebreak_Trap;

   --  ======================================================================
   --  Test trap fallback (mtvec = 0 halts)
   --  ======================================================================
   procedure Test_Trap_Fallback is
      C : CPU.CPU_State;
      M : Memory.Memory_Unit;
   begin
      Put_Line ("Testing trap fallback (mtvec=0)...");

      CPU.Initialize (C, 16#1000#);
      Memory.Initialize (M);
      Memory.Add_Region (M, "RAM", 0, 16#10000#);

      --  mtvec defaults to 0, so trap should halt
      Memory.Write_Word (M, 16#1000#, Ecall);
      CPU.Step (C, M, False, CPU.Trace_Config'(Enabled => False, others => <>));

      Check (C.Halted,
             "ECALL with mtvec=0: CPU halted");
      Check (C.Exception_Code = Environment_Call,
             "ECALL with mtvec=0: exception code set");
   end Test_Trap_Fallback;

   --  ======================================================================
   --  Test MRET instruction
   --  ======================================================================
   procedure Test_Mret is
      C : CPU.CPU_State;
      M : Memory.Memory_Unit;
   begin
      Put_Line ("Testing MRET instruction...");

      CPU.Initialize (C, 16#2000#);
      Memory.Initialize (M);
      Memory.Add_Region (M, "RAM", 0, 16#10000#);

      --  Simulate being in a trap handler:
      --  Set mepc to return address
      CSR.Write (C.CSRs, CSR.CSR_MEPC, 16#1004#);
      --  Set mstatus: MIE=0 (in handler), MPIE=1 (was enabled), MPP=11
      CSR.Write (C.CSRs, CSR.CSR_MSTATUS,
                 CSR.MSTATUS_MPIE or CSR.MSTATUS_MPP_MASK);

      --  Place MRET at 0x2000
      Memory.Write_Word (M, 16#2000#, Mret_Insn);

      CPU.Step (C, M, False, CPU.Trace_Config'(Enabled => False, others => <>));

      Check (C.PC = 16#1004#,
             "MRET: PC restored to mepc");
      Check (not C.Halted,
             "MRET: CPU not halted");

      declare
         Ms : constant Word := CSR.Read (C.CSRs, CSR.CSR_MSTATUS);
      begin
         Check ((Ms and CSR.MSTATUS_MIE) /= 0,
                "MRET: MIE restored from MPIE");
         Check ((Ms and CSR.MSTATUS_MPIE) /= 0,
                "MRET: MPIE set to 1");
         Check ((Ms and CSR.MSTATUS_MPP_MASK) = 0,
                "MRET: MPP cleared");
      end;
   end Test_Mret;

   --  ======================================================================
   --  Test MRET with MIE=0 (was disabled before trap)
   --  ======================================================================
   procedure Test_Mret_No_Mie is
      C : CPU.CPU_State;
      M : Memory.Memory_Unit;
   begin
      Put_Line ("Testing MRET with MPIE=0...");

      CPU.Initialize (C, 16#2000#);
      Memory.Initialize (M);
      Memory.Add_Region (M, "RAM", 0, 16#10000#);

      --  MPIE=0 means interrupts were disabled before trap
      CSR.Write (C.CSRs, CSR.CSR_MEPC, 16#1008#);
      CSR.Write (C.CSRs, CSR.CSR_MSTATUS, CSR.MSTATUS_MPP_MASK);

      Memory.Write_Word (M, 16#2000#, Mret_Insn);
      CPU.Step (C, M, False, CPU.Trace_Config'(Enabled => False, others => <>));

      declare
         Ms : constant Word := CSR.Read (C.CSRs, CSR.CSR_MSTATUS);
      begin
         Check ((Ms and CSR.MSTATUS_MIE) = 0,
                "MRET: MIE=0 when MPIE was 0");
         Check (C.PC = 16#1008#,
                "MRET: PC restored");
      end;
   end Test_Mret_No_Mie;

   --  ======================================================================
   --  Test full ECALL -> handler -> MRET round trip
   --  ======================================================================
   procedure Test_Ecall_Mret_Roundtrip is
      C : CPU.CPU_State;
      M : Memory.Memory_Unit;
   begin
      Put_Line ("Testing ECALL -> MRET round trip...");

      CPU.Initialize (C, 16#1000#);
      Memory.Initialize (M);
      Memory.Add_Region (M, "RAM", 0, 16#10000#);

      --  Enable interrupts and set trap vector
      CSR.Write (C.CSRs, CSR.CSR_MSTATUS, CSR.MSTATUS_MIE);
      CSR.Write (C.CSRs, CSR.CSR_MTVEC, 16#2000#);

      --  Program:
      --  0x1000: ADDI x10, x0, 42    -- set x10 = 42
      --  0x1004: ECALL                 -- trap to handler
      --  0x1008: ADDI x11, x0, 99    -- should run after MRET
      Memory.Write_Word (M, 16#1000#, Encode_ADDI (10, 0, 42));
      Memory.Write_Word (M, 16#1004#, Ecall);
      Memory.Write_Word (M, 16#1008#, Encode_ADDI (11, 0, 99));

      --  Trap handler at 0x2000:
      --  0x2000: ADDI x12, x0, 77    -- mark handler entered
      --  0x2004: CSRR x13, mepc      -- read saved PC
      --  0x2008: ADDI x13, x13, 4    -- skip ECALL
      --  0x200C: CSRW mepc, x13      -- update return address
      --  0x2010: MRET                  -- return
      Memory.Write_Word (M, 16#2000#, Encode_ADDI (12, 0, 77));
      Memory.Write_Word (M, 16#2004#,
         Encode_CSR (CSR.CSR_MEPC, 0, FUNCT3_CSRRS, 13));
      Memory.Write_Word (M, 16#2008#, Encode_ADDI (13, 13, 4));
      Memory.Write_Word (M, 16#200C#,
         Encode_CSR (CSR.CSR_MEPC, 13, FUNCT3_CSRRW, 0));
      Memory.Write_Word (M, 16#2010#, Mret_Insn);

      --  Run: ADDI + ECALL + handler(4 insns) + MRET + ADDI = 8 steps
      CPU.Run (C, M, False, CPU.Trace_Config'(Enabled => False, others => <>), 8);

      Check (CPU.Read_Register (C, 10) = 42,
             "Round trip: x10 = 42 before ECALL");
      Check (CPU.Read_Register (C, 12) = 77,
             "Round trip: x12 = 77 (handler ran)");
      Check (CPU.Read_Register (C, 11) = 99,
             "Round trip: x11 = 99 (returned from handler)");
      Check (C.PC = 16#100C#,
             "Round trip: PC at instruction after ECALL return");
      Check (not C.Halted,
             "Round trip: CPU not halted");
   end Test_Ecall_Mret_Roundtrip;

   --  ======================================================================
   --  Test vectored trap mode
   --  ======================================================================
   procedure Test_Vectored_Mode is
      C : CPU.CPU_State;
      M : Memory.Memory_Unit;
      Taken : Boolean;
   begin
      Put_Line ("Testing vectored trap mode...");

      CPU.Initialize (C, 16#1000#);
      Memory.Initialize (M);
      Memory.Add_Region (M, "RAM", 0, 16#10000#);

      --  Set mtvec to 0x4000 with vectored mode (bit 0 = 1)
      CSR.Write (C.CSRs, CSR.CSR_MTVEC, 16#4001#);

      --  ECALL (synchronous exception) should go to base even in vectored
      CSR.Write (C.CSRs, CSR.CSR_MSTATUS, CSR.MSTATUS_MIE);
      Memory.Write_Word (M, 16#1000#, Ecall);
      CPU.Step (C, M, False, CPU.Trace_Config'(Enabled => False, others => <>));

      Check (C.PC = 16#4000#,
             "Vectored: ECALL goes to base address");

      --  Now test interrupt vectoring
      --  Reset CPU to a known state
      CPU.Initialize (C, 16#1000#);
      CSR.Write (C.CSRs, CSR.CSR_MTVEC, 16#4001#);
      CSR.Write (C.CSRs, CSR.CSR_MSTATUS, CSR.MSTATUS_MIE);
      CSR.Write (C.CSRs, CSR.CSR_MIE, CSR.MIE_MTIE);

      --  Set timer interrupt pending
      CSR.Write (C.CSRs, CSR.CSR_MIP, CSR.MIE_MTIE);

      Taken := CPU.Check_Interrupts (C, M);

      Check (Taken,
             "Vectored: timer interrupt taken");
      --  Timer interrupt cause = 7, so vectored target = base + 4*7 = base+28
      Check (C.PC = 16#4000# + 28,
             "Vectored: timer int vectors to base+28");
   end Test_Vectored_Mode;

   --  ======================================================================
   --  Test illegal instruction trap
   --  ======================================================================
   procedure Test_Illegal_Insn_Trap is
      C : CPU.CPU_State;
      M : Memory.Memory_Unit;
   begin
      Put_Line ("Testing illegal instruction trap...");

      CPU.Initialize (C, 16#1000#);
      Memory.Initialize (M);
      Memory.Add_Region (M, "RAM", 0, 16#10000#);

      CSR.Write (C.CSRs, CSR.CSR_MTVEC, 16#3000#);

      --  Place an invalid instruction (all ones except opcode bits)
      Memory.Write_Word (M, 16#1000#, 16#FFFFFFFF#);

      CPU.Step (C, M, False, CPU.Trace_Config'(Enabled => False, others => <>));

      Check (CSR.Read (C.CSRs, CSR.CSR_MCAUSE) = CSR.CAUSE_ILLEGAL_INSN,
             "Illegal insn: mcause = 2");
      Check (CSR.Read (C.CSRs, CSR.CSR_MTVAL) = 16#FFFFFFFF#,
             "Illegal insn: mtval = faulting instruction");
      Check (C.PC = 16#3000#,
             "Illegal insn: PC jumps to handler");
      Check (not C.Halted,
             "Illegal insn: CPU not halted");
   end Test_Illegal_Insn_Trap;

   --  ======================================================================
   --  Test Check_Interrupts with MIE disabled
   --  ======================================================================
   procedure Test_Interrupts_Disabled is
      C : CPU.CPU_State;
      M : Memory.Memory_Unit;
      Taken : Boolean;
   begin
      Put_Line ("Testing interrupt masking...");

      CPU.Initialize (C, 16#1000#);
      Memory.Initialize (M);
      Memory.Add_Region (M, "RAM", 0, 16#10000#);

      CSR.Write (C.CSRs, CSR.CSR_MTVEC, 16#2000#);
      --  MIE is cleared (default), interrupts disabled globally
      CSR.Write (C.CSRs, CSR.CSR_MIE, CSR.MIE_MTIE);
      CSR.Write (C.CSRs, CSR.CSR_MIP, CSR.MIE_MTIE);

      Taken := CPU.Check_Interrupts (C, M);
      Check (not Taken,
             "Interrupts disabled: not taken when MIE=0");
      Check (C.PC = 16#1000#,
             "Interrupts disabled: PC unchanged");

      --  Now enable MIE
      CSR.Write (C.CSRs, CSR.CSR_MSTATUS, CSR.MSTATUS_MIE);
      Taken := CPU.Check_Interrupts (C, M);
      Check (Taken,
             "Interrupts enabled: taken when MIE=1");
      Check (C.PC = 16#2000#,
             "Interrupts enabled: PC at handler");
   end Test_Interrupts_Disabled;

   --  ======================================================================
   --  Test individual interrupt enables (MIE register)
   --  ======================================================================
   procedure Test_Interrupt_Enables is
      C : CPU.CPU_State;
      M : Memory.Memory_Unit;
      Taken : Boolean;
   begin
      Put_Line ("Testing individual interrupt enables...");

      CPU.Initialize (C, 16#1000#);
      Memory.Initialize (M);
      Memory.Add_Region (M, "RAM", 0, 16#10000#);

      CSR.Write (C.CSRs, CSR.CSR_MTVEC, 16#2000#);
      CSR.Write (C.CSRs, CSR.CSR_MSTATUS, CSR.MSTATUS_MIE);

      --  Timer pending but not enabled in MIE
      CSR.Write (C.CSRs, CSR.CSR_MIE, 0);
      CSR.Write (C.CSRs, CSR.CSR_MIP, CSR.MIE_MTIE);

      Taken := CPU.Check_Interrupts (C, M);
      Check (not Taken,
             "Timer pending but not enabled: not taken");

      --  Enable timer in MIE
      CSR.Write (C.CSRs, CSR.CSR_MIE, CSR.MIE_MTIE);
      Taken := CPU.Check_Interrupts (C, M);
      Check (Taken,
             "Timer enabled and pending: taken");
      Check (CSR.Read (C.CSRs, CSR.CSR_MCAUSE) = CSR.CAUSE_M_TIMER_INT,
             "Timer interrupt: correct mcause");
   end Test_Interrupt_Enables;

   --  ======================================================================
   --  Test interrupt priority (MEI > MSI > MTI)
   --  ======================================================================
   procedure Test_Interrupt_Priority is
      C : CPU.CPU_State;
      M : Memory.Memory_Unit;
      Taken : Boolean;
   begin
      Put_Line ("Testing interrupt priority...");

      CPU.Initialize (C, 16#1000#);
      Memory.Initialize (M);
      Memory.Add_Region (M, "RAM", 0, 16#10000#);

      CSR.Write (C.CSRs, CSR.CSR_MTVEC, 16#2000#);
      CSR.Write (C.CSRs, CSR.CSR_MSTATUS, CSR.MSTATUS_MIE);

      --  All three interrupt types pending and enabled
      CSR.Write (C.CSRs, CSR.CSR_MIE,
                 CSR.MIE_MEIE or CSR.MIE_MSIE or CSR.MIE_MTIE);
      CSR.Write (C.CSRs, CSR.CSR_MIP,
                 CSR.MIE_MEIE or CSR.MIE_MSIE or CSR.MIE_MTIE);

      Taken := CPU.Check_Interrupts (C, M);
      Check (Taken,
             "Multiple pending: interrupt taken");
      Check (CSR.Read (C.CSRs, CSR.CSR_MCAUSE) = CSR.CAUSE_M_EXTERNAL_INT,
             "Priority: external wins over software and timer");

      --  Now test MSI > MTI
      CPU.Initialize (C, 16#1000#);
      CSR.Write (C.CSRs, CSR.CSR_MTVEC, 16#2000#);
      CSR.Write (C.CSRs, CSR.CSR_MSTATUS, CSR.MSTATUS_MIE);
      CSR.Write (C.CSRs, CSR.CSR_MIE, CSR.MIE_MSIE or CSR.MIE_MTIE);
      CSR.Write (C.CSRs, CSR.CSR_MIP, CSR.MIE_MSIE or CSR.MIE_MTIE);

      Taken := CPU.Check_Interrupts (C, M);
      Check (CSR.Read (C.CSRs, CSR.CSR_MCAUSE) = CSR.CAUSE_M_SOFTWARE_INT,
             "Priority: software wins over timer");
   end Test_Interrupt_Priority;

   --  ======================================================================
   --  Test To_Mcause mapping
   --  ======================================================================
   procedure Test_To_Mcause is
   begin
      Put_Line ("Testing To_Mcause mapping...");

      Check (CSR.To_Mcause (No_Exception) = 0,
             "To_Mcause: No_Exception = 0");
      Check (CSR.To_Mcause (Illegal_Instruction) = 2,
             "To_Mcause: Illegal_Instruction = 2");
      Check (CSR.To_Mcause (Misaligned_Fetch) = 0,
             "To_Mcause: Misaligned_Fetch = 0");
      Check (CSR.To_Mcause (Misaligned_Load) = 4,
             "To_Mcause: Misaligned_Load = 4");
      Check (CSR.To_Mcause (Misaligned_Store) = 6,
             "To_Mcause: Misaligned_Store = 6");
      Check (CSR.To_Mcause (Environment_Call) = 8,
             "To_Mcause: Environment_Call = 8 (ECALL_U base)");
      Check (CSR.To_Mcause (Breakpoint) = 3,
             "To_Mcause: Breakpoint = 3");
   end Test_To_Mcause;

   --  ======================================================================
   --  Test disassembly of trap instructions
   --  ======================================================================
   procedure Test_Disasm is
   begin
      Put_Line ("Testing trap disassembly...");

      Check (Disasm.Disassemble (Ecall, 0) = "ecall",
             "Disasm: ecall");
      Check (Disasm.Disassemble (Ebreak, 0) = "ebreak",
             "Disasm: ebreak");
      Check (Disasm.Disassemble (Mret_Insn, 0) = "mret",
             "Disasm: mret");
   end Test_Disasm;

   --  ======================================================================
   --  Test nested traps (trap inside handler)
   --  ======================================================================
   procedure Test_Nested_Trap is
      C : CPU.CPU_State;
      M : Memory.Memory_Unit;
   begin
      Put_Line ("Testing nested trap behavior...");

      CPU.Initialize (C, 16#1000#);
      Memory.Initialize (M);
      Memory.Add_Region (M, "RAM", 0, 16#10000#);

      CSR.Write (C.CSRs, CSR.CSR_MTVEC, 16#2000#);
      CSR.Write (C.CSRs, CSR.CSR_MSTATUS, CSR.MSTATUS_MIE);

      --  First ECALL at 0x1000
      Memory.Write_Word (M, 16#1000#, Ecall);
      CPU.Step (C, M, False, CPU.Trace_Config'(Enabled => False, others => <>));

      Check (C.PC = 16#2000#, "Nested: first trap entered");
      --  MIE should be cleared now
      Check ((CSR.Read (C.CSRs, CSR.CSR_MSTATUS) and CSR.MSTATUS_MIE) = 0,
             "Nested: MIE cleared in handler");

      --  Second ECALL at handler (0x2000) - this overwrites mepc!
      Memory.Write_Word (M, 16#2000#, Ecall);
      CPU.Step (C, M, False, CPU.Trace_Config'(Enabled => False, others => <>));

      --  mepc now points to 0x2000, not 0x1000
      Check (CSR.Read (C.CSRs, CSR.CSR_MEPC) = 16#2000#,
             "Nested: mepc overwritten to second trap PC");
   end Test_Nested_Trap;

   --  ======================================================================
   --  Test CLINT timer interrupt integration
   --  ======================================================================
   procedure Test_Clint_Timer_Interrupt is
      C : CPU.CPU_State;
      M : Memory.Memory_Unit;
   begin
      Put_Line ("Testing CLINT timer interrupt...");

      CPU.Initialize (C, 16#1000#);
      Memory.Initialize (M);
      Memory.Add_Region (M, "RAM", 0, 16#10000#);
      Memory.Enable_CLINT (M, 16#2000000#);

      CSR.Write (C.CSRs, CSR.CSR_MTVEC, 16#3000#);
      CSR.Write (C.CSRs, CSR.CSR_MSTATUS, CSR.MSTATUS_MIE);
      CSR.Write (C.CSRs, CSR.CSR_MIE, CSR.MIE_MTIE);

      --  Set mtimecmp to 5 (write both low and high word)
      Memory.Write_Word (M, 16#2000000# + 16#4000#, 5);
      Memory.Write_Word (M, 16#2000000# + 16#4004#, 0);

      --  Tick timer 5 times to trigger (mtime >= mtimecmp)
      for I in 1 .. 5 loop
         Memory.CLINT_Tick (M);
      end loop;

      Check (Memory.CLINT_Timer_Interrupt_Pending (M),
             "CLINT: timer interrupt pending");

      --  Place NOPs at code and handler locations
      Memory.Write_Word (M, 16#1000#, Encode_ADDI (0, 0, 0));
      Memory.Write_Word (M, 16#3000#, Encode_ADDI (0, 0, 0));

      --  Check_Interrupts runs before Step in the Run loop
      --  Interrupt vectors to handler, then Step executes handler NOP
      CPU.Run (C, M, False, CPU.Trace_Config'(Enabled => False, others => <>), 1);

      Check (CSR.Read (C.CSRs, CSR.CSR_MCAUSE) = CSR.CAUSE_M_TIMER_INT,
             "CLINT: mcause = timer interrupt");
      Check (C.PC = 16#3004#,
             "CLINT: PC at handler + 4");
   end Test_Clint_Timer_Interrupt;

   --  ======================================================================
   --  Test CLINT software interrupt
   --  ======================================================================
   procedure Test_Clint_Software_Interrupt is
      C : CPU.CPU_State;
      M : Memory.Memory_Unit;
   begin
      Put_Line ("Testing CLINT software interrupt...");

      CPU.Initialize (C, 16#1000#);
      Memory.Initialize (M);
      Memory.Add_Region (M, "RAM", 0, 16#10000#);
      Memory.Enable_CLINT (M, 16#2000000#);

      CSR.Write (C.CSRs, CSR.CSR_MTVEC, 16#3000#);
      CSR.Write (C.CSRs, CSR.CSR_MSTATUS, CSR.MSTATUS_MIE);
      CSR.Write (C.CSRs, CSR.CSR_MIE, CSR.MIE_MSIE);

      --  Set msip = 1 (software interrupt pending)
      Memory.Write_Word (M, 16#2000000#, 1);

      Check (Memory.CLINT_Software_Interrupt_Pending (M),
             "CLINT: software interrupt pending");

      Memory.Write_Word (M, 16#1000#, Encode_ADDI (0, 0, 0));
      Memory.Write_Word (M, 16#3000#, Encode_ADDI (0, 0, 0));
      CPU.Run (C, M, False, CPU.Trace_Config'(Enabled => False, others => <>), 1);

      Check (CSR.Read (C.CSRs, CSR.CSR_MCAUSE) = CSR.CAUSE_M_SOFTWARE_INT,
             "CLINT: mcause = software interrupt");
   end Test_Clint_Software_Interrupt;

   --  ======================================================================
   --  Access faults: an access outside every region must trap, not be
   --  silently completed with a zero result or a dropped write.
   --  ======================================================================
   procedure Test_Load_Access_Fault is
      C : CPU.CPU_State;
      M : Memory.Memory_Unit;
   begin
      Put_Line ("Testing load access fault...");

      CPU.Initialize (C, 16#1000#);
      Memory.Initialize (M);
      Memory.Add_Region (M, "RAM", 0, 16#10000#);
      CSR.Write (C.CSRs, CSR.CSR_MTVEC, 16#2000#);

      --  x1 = 0 by default, so LW x2, 0x400(x1) reads 0x400 (mapped) and
      --  LW x2, -1(x1) would straddle; use an address past the region.
      C.Registers (1) := 16#0002_0000#;   --  outside the 64 KB region
      Memory.Write_Word (M, 16#1000#, Encode_LW (2, 1, 0));

      CPU.Step (C, M, False, CPU.Trace_Config'(Enabled => False, others => <>));

      Check (CSR.Read (C.CSRs, CSR.CSR_MCAUSE) = CSR.CAUSE_LOAD_ACCESS_FAULT,
             "LW from unmapped address: mcause = 5 (load access fault)");
      Check (CSR.Read (C.CSRs, CSR.CSR_MTVAL) = 16#0002_0000#,
             "LW from unmapped address: mtval = faulting address");
      Check (C.Registers (2) = 0,
             "LW from unmapped address: rd left unwritten");
      Check (C.PC = 16#2000#,
             "LW from unmapped address: PC jumps to mtvec");
   end Test_Load_Access_Fault;

   procedure Test_Store_Access_Fault is
      C : CPU.CPU_State;
      M : Memory.Memory_Unit;
   begin
      Put_Line ("Testing store access fault...");

      CPU.Initialize (C, 16#1000#);
      Memory.Initialize (M);
      Memory.Add_Region (M, "RAM", 0, 16#10000#);
      CSR.Write (C.CSRs, CSR.CSR_MTVEC, 16#2000#);

      C.Registers (1) := 16#0002_0000#;
      C.Registers (3) := 16#DEAD_BEEF#;
      Memory.Write_Word (M, 16#1000#, Encode_SW (1, 3, 0));

      CPU.Step (C, M, False, CPU.Trace_Config'(Enabled => False, others => <>));

      Check (CSR.Read (C.CSRs, CSR.CSR_MCAUSE) = CSR.CAUSE_STORE_ACCESS_FAULT,
             "SW to unmapped address: mcause = 7 (store access fault)");
      Check (C.PC = 16#2000#,
             "SW to unmapped address: PC jumps to mtvec");
   end Test_Store_Access_Fault;

   procedure Test_ROM_Write_Faults is
      C : CPU.CPU_State;
      M : Memory.Memory_Unit;
   begin
      Put_Line ("Testing store to a read-only region...");

      CPU.Initialize (C, 16#1000#);
      Memory.Initialize (M);
      Memory.Add_Region (M, "RAM", 0, 16#10000#);
      Memory.Add_Region (M, "ROM", 16#0002_0000#, 16#1000#,
                         Memory.ROM, Memory.Permission_RX);
      CSR.Write (C.CSRs, CSR.CSR_MTVEC, 16#2000#);

      C.Registers (1) := 16#0002_0000#;
      C.Registers (3) := 16#A5A5_A5A5#;
      Memory.Write_Word (M, 16#1000#, Encode_SW (1, 3, 0));

      CPU.Step (C, M, False, CPU.Trace_Config'(Enabled => False, others => <>));

      Check (CSR.Read (C.CSRs, CSR.CSR_MCAUSE) = CSR.CAUSE_STORE_ACCESS_FAULT,
             "SW to ROM: mcause = 7 (store access fault)");
      Check (Memory.Read_Word (M, 16#0002_0000#) = 0,
             "SW to ROM: memory unchanged");
   end Test_ROM_Write_Faults;

   procedure Test_Straddling_Word_Faults is
      C : CPU.CPU_State;
      M : Memory.Memory_Unit;
   begin
      Put_Line ("Testing a word that straddles the end of a region...");

      CPU.Initialize (C, 16#1000#);
      Memory.Initialize (M);
      Memory.Add_Region (M, "RAM", 0, 16#10000#);
      CSR.Write (C.CSRs, CSR.CSR_MTVEC, 16#2000#);

      --  Last two bytes of the region plus two bytes past its end. This used
      --  to return a mix of real and zero bytes with no indication.
      C.Registers (1) := 16#0000_FFFE#;
      Memory.Write_Word (M, 16#1000#, Encode_LW (2, 1, 0));

      CPU.Step (C, M, False, CPU.Trace_Config'(Enabled => False, others => <>));

      Check (CSR.Read (C.CSRs, CSR.CSR_MCAUSE) = CSR.CAUSE_LOAD_ACCESS_FAULT,
             "LW straddling the region end: mcause = 5");
      Check (CSR.Read (C.CSRs, CSR.CSR_MTVAL) = 16#0001_0000#,
             "LW straddling the region end: mtval = first bad byte");
   end Test_Straddling_Word_Faults;

   procedure Test_Access_Faults_Disabled is
      C : CPU.CPU_State;
      M : Memory.Memory_Unit;
   begin
      Put_Line ("Testing --no-access-faults behaviour...");

      CPU.Initialize (C, 16#1000#);
      Memory.Initialize (M);
      Memory.Add_Region (M, "RAM", 0, 16#10000#);
      M.Fault_Traps := False;
      CSR.Write (C.CSRs, CSR.CSR_MTVEC, 16#2000#);

      C.Registers (1) := 16#0002_0000#;
      Memory.Write_Word (M, 16#1000#, Encode_LW (2, 1, 0));

      CPU.Step (C, M, False, CPU.Trace_Config'(Enabled => False, others => <>));

      Check (C.PC = 16#1004#,
             "Fault_Traps off: unmapped load completes, PC advances");
      Check (C.Registers (2) = 0,
             "Fault_Traps off: unmapped load reads zero");
   end Test_Access_Faults_Disabled;

   --  ======================================================================
   --  Region bookkeeping
   --  ======================================================================
   procedure Test_Region_Bookkeeping is
      M : Memory.Memory_Unit;
   begin
      Put_Line ("Testing region registration...");

      Memory.Initialize_Empty (M);
      Memory.Add_Region (M, "RAM", 16#8000_0000#, 16#1000#);
      Check (M.Region_Count = 1, "Add_Region: first region accepted");

      --  Overlapping the existing region must be rejected, not silently
      --  shadowed by whichever comes first in the scan.
      Memory.Add_Region (M, "OVL", 16#8000_0800#, 16#1000#);
      Check (M.Region_Count = 1, "Add_Region: overlapping region rejected");

      Memory.Add_Region (M, "NEXT", 16#8000_1000#, 16#1000#);
      Check (M.Region_Count = 2, "Add_Region: abutting region accepted");

      --  A region running off the top of the address space has no meaning.
      Memory.Add_Region (M, "WRAP", 16#FFFF_F000#, 16#2000#);
      Check (M.Region_Count = 2, "Add_Region: wrapping region rejected");

      --  ... but one ending exactly at 2**32 is fine and must be reachable.
      Memory.Add_Region (M, "TOP", 16#FFFF_F000#, 16#1000#);
      Check (M.Region_Count = 3, "Add_Region: region ending at 2**32 accepted");
      Memory.Write_Word (M, 16#FFFF_FFFC#, 16#1234_5678#);
      Check (Memory.Read_Word (M, 16#FFFF_FFFC#) = 16#1234_5678#,
             "Find_Region: last word of the address space is reachable");
   end Test_Region_Bookkeeping;

   --  ======================================================================
   --  Host path confinement
   --  ======================================================================
   procedure Test_Host_Path_Confinement is
   begin
      Put_Line ("Testing host path confinement...");

      Check (Memory.Valid_Host_Name ("frame.ppm"),
             "Host path: plain name accepted");
      Check (Memory.Valid_Host_Name ("sub/dir/frame.ppm"),
             "Host path: relative subdirectory accepted");
      Check (not Memory.Valid_Host_Name ("/etc/passwd"),
             "Host path: absolute path refused");
      Check (not Memory.Valid_Host_Name ("../escape"),
             "Host path: leading .. refused");
      Check (not Memory.Valid_Host_Name ("a/../../escape"),
             "Host path: embedded .. refused");
      Check (not Memory.Valid_Host_Name ("dir/.."),
             "Host path: trailing .. refused");
      Check (Memory.Valid_Host_Name ("..hidden"),
             "Host path: name merely starting with dots accepted");
      Check (not Memory.Valid_Host_Name (""),
             "Host path: empty name refused");
   end Test_Host_Path_Confinement;

begin
   Put_Line ("=================================================");
   Put_Line ("       RISCV Emulator Trap/Interrupt Tests");
   Put_Line ("=================================================");
   New_Line;

   Test_Trap_Entry_Basic;
   New_Line;
   Test_Ebreak_Trap;
   New_Line;
   Test_Trap_Fallback;
   New_Line;
   Test_Mret;
   New_Line;
   Test_Mret_No_Mie;
   New_Line;
   Test_Ecall_Mret_Roundtrip;
   New_Line;
   Test_Vectored_Mode;
   New_Line;
   Test_Illegal_Insn_Trap;
   New_Line;
   Test_Interrupts_Disabled;
   New_Line;
   Test_Interrupt_Enables;
   New_Line;
   Test_Interrupt_Priority;
   New_Line;
   Test_To_Mcause;
   New_Line;
   Test_Disasm;
   New_Line;
   Test_Nested_Trap;
   New_Line;
   Test_Clint_Timer_Interrupt;
   New_Line;
   Test_Clint_Software_Interrupt;
   New_Line;
   Test_Load_Access_Fault;
   New_Line;
   Test_Store_Access_Fault;
   New_Line;
   Test_ROM_Write_Faults;
   New_Line;
   Test_Straddling_Word_Faults;
   New_Line;
   Test_Access_Faults_Disabled;
   New_Line;
   Test_Region_Bookkeeping;
   New_Line;
   Test_Host_Path_Confinement;

   New_Line;
   Put_Line ("=================================================");
   Put ("Test Results: ");
   Put (Natural'Image (Passed_Tests) & " passed, ");
   Put (Natural'Image (Failed_Tests) & " failed out of ");
   Put_Line (Natural'Image (Total_Tests) & " tests");
   Put_Line ("=================================================");

   if Failed_Tests = 0 then
      Put_Line ("ALL TESTS PASSED!");
   else
      Put_Line ("SOME TESTS FAILED!");
   end if;
end Test_Traps;
