-- ***************************************************************************
--               RISC-V Emulator - CSR Register File
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
package body RISCV.CSR is

   ----------------
   -- Initialize --
   ----------------

   procedure Initialize (State : out CSR_State) is
   begin
      State.Entries := (others => (Address => 0, Value => 0));
      State.Count := 0;
      State.Mcycle := 0;
      State.Minstret := 0;
      State.Mcountinhibit := 0;

      --  Initialize default CSR values
      --  MISA: RV32IMAFDCV + S extension
      Write (State, CSR_MISA,
             Shift_Left (1, 0) or   --  A (Atomic)
             Shift_Left (1, 2) or   --  C (Compressed)
             Shift_Left (1, 3) or   --  D (Double FP)
             Shift_Left (1, 5) or   --  F (Single FP)
             Shift_Left (1, 8) or   --  I (Base Integer)
             Shift_Left (1, 12) or  --  M (Multiply/Divide)
             Shift_Left (1, 18) or  --  S (Supervisor)
             Shift_Left (1, 20) or  --  U (User)
             Shift_Left (1, 21) or  --  V (Vector)
             Shift_Left (1, 30));    --  MXL=1 (32-bit)

      --  MSTATUS: machine mode, interrupts disabled
      Write (State, CSR_MSTATUS, 0);

      --  MTVEC: direct mode, address 0
      Write (State, CSR_MTVEC, 0);

      --  Delegation registers: default no delegation
      Write (State, CSR_MEDELEG, 0);
      Write (State, CSR_MIDELEG, 0);

      --  Supervisor CSRs
      Write (State, CSR_STVEC, 0);
      Write (State, CSR_SSCRATCH, 0);
      Write (State, CSR_SEPC, 0);
      Write (State, CSR_SCAUSE, 0);
      Write (State, CSR_STVAL, 0);
      Write (State, CSR_SATP, 0);

      --  Vendor/implementation IDs
      Write (State, CSR_MVENDORID, 0);
      Write (State, CSR_MARCHID, 0);
      Write (State, CSR_MIMPID, 0);
      Write (State, CSR_MHARTID, 0);

      --  Counter access control
      Write (State, CSR_MCOUNTEREN, 0);
      Write (State, CSR_SCOUNTEREN, 0);
   end Initialize;

   ----------
   -- Read --
   ----------

   function Read (State : CSR_State; Addr : CSR_Address) return Word is
   begin
      --  Handle counter CSRs specially (64-bit split)
      case Addr is
         when CSR_MCYCLE | CSR_CYCLE =>
            return Word (State.Mcycle and 16#FFFFFFFF#);
         when CSR_MCYCLEH | CSR_CYCLEH =>
            return Word (Shift_Right (State.Mcycle, 32) and 16#FFFFFFFF#);
         when CSR_MINSTRET | CSR_INSTRET =>
            return Word (State.Minstret and 16#FFFFFFFF#);
         when CSR_MINSTRETH | CSR_INSTRETH =>
            return Word (Shift_Right (State.Minstret, 32) and 16#FFFFFFFF#);
         when CSR_TIME =>
            return Word (State.Mcycle and 16#FFFFFFFF#);  --  Alias to mcycle
         when CSR_TIMEH =>
            return Word (Shift_Right (State.Mcycle, 32) and 16#FFFFFFFF#);

         --  Supervisor CSR views of machine CSRs
         when CSR_SSTATUS =>
            --  SSTATUS is a masked view of MSTATUS
            return Read (State, CSR_MSTATUS) and SSTATUS_MASK;
         when CSR_SIE =>
            --  SIE is a masked view of MIE
            return Read (State, CSR_MIE) and SIP_MASK;
         when CSR_SIP =>
            --  SIP is a masked view of MIP
            return Read (State, CSR_MIP) and SIP_MASK;

         when CSR_MCOUNTINHIBIT =>
            return State.Mcountinhibit;

         --  HPM counter/event stubs: always read 0
         when CSR_MHPMCOUNTER_LO .. CSR_MHPMCOUNTER_HI   => return 0;
         when CSR_MHPMCOUNTERH_LO .. CSR_MHPMCOUNTERH_HI => return 0;
         when CSR_MHPMEVENT_LO .. CSR_MHPMEVENT_HI       => return 0;

         when others =>
            --  Look up in sparse map
            for I in 0 .. State.Count - 1 loop
               if State.Entries (I).Address = Addr then
                  return State.Entries (I).Value;
               end if;
            end loop;
            return 0;
      end case;
   end Read;

   -----------
   -- Write --
   -----------

   procedure Write (State : in out CSR_State;
                    Addr  : CSR_Address;
                    Value : Word) is
   begin
      --  Handle counter CSRs specially
      case Addr is
         when CSR_MCYCLE =>
            State.Mcycle := (State.Mcycle and 16#FFFFFFFF00000000#) or
                            Unsigned_64 (Value);
            return;
         when CSR_MCYCLEH =>
            State.Mcycle := (State.Mcycle and 16#00000000FFFFFFFF#) or
                            Shift_Left (Unsigned_64 (Value), 32);
            return;
         when CSR_MINSTRET =>
            State.Minstret := (State.Minstret and 16#FFFFFFFF00000000#) or
                              Unsigned_64 (Value);
            return;
         when CSR_MINSTRETH =>
            State.Minstret := (State.Minstret and 16#00000000FFFFFFFF#) or
                              Shift_Left (Unsigned_64 (Value), 32);
            return;

         --  Supervisor CSR views: write through to machine CSRs with masking
         when CSR_SSTATUS =>
            declare
               Mstatus : constant Word := Read (State, CSR_MSTATUS);
            begin
               Write (State, CSR_MSTATUS,
                      (Mstatus and not SSTATUS_MASK) or
                      (Value and SSTATUS_MASK));
            end;
            return;
         when CSR_SIE =>
            declare
               Mie_Val : constant Word := Read (State, CSR_MIE);
            begin
               Write (State, CSR_MIE,
                      (Mie_Val and not SIP_MASK) or (Value and SIP_MASK));
            end;
            return;
         when CSR_SIP =>
            declare
               Mip_Val : constant Word := Read (State, CSR_MIP);
            begin
               --  Only SSIP is writable from S-mode; STIP and SEIP are
               --  read-only here and stay under hardware control.
               Write (State, CSR_MIP,
                      (Mip_Val and not SIP_WRITE_MASK) or
                      (Value and SIP_WRITE_MASK));
            end;
            return;

         when CSR_MCOUNTINHIBIT =>
            --  Bit 1 is reserved/WARL; mask it out
            State.Mcountinhibit := Value and not Word (2);
            return;

         --  HPM counter/event stubs: writes are ignored
         when CSR_MHPMCOUNTER_LO .. CSR_MHPMCOUNTER_HI   => return;
         when CSR_MHPMCOUNTERH_LO .. CSR_MHPMCOUNTERH_HI => return;
         when CSR_MHPMEVENT_LO .. CSR_MHPMEVENT_HI       => return;

         when others =>
            null;  --  Fall through to sparse map
      end case;

      --  Look up existing entry
      for I in 0 .. State.Count - 1 loop
         if State.Entries (I).Address = Addr then
            State.Entries (I).Value := Value;
            return;
         end if;
      end loop;

      --  Add new entry if space available
      if State.Count < Max_CSR_Count then
         State.Entries (State.Count) := (Address => Addr, Value => Value);
         State.Count := State.Count + 1;
      end if;
   end Write;

   -------------------------
   -- Increment_Instret --
   -------------------------

   procedure Increment_Instret (State : in out CSR_State) is
   begin
      --  mcountinhibit bit 2 (IR) inhibits minstret
      if (State.Mcountinhibit and 4) = 0 then
         State.Minstret := State.Minstret + 1;
      end if;
   end Increment_Instret;

   -----------------------
   -- Increment_Mcycle --
   -----------------------

   procedure Increment_Mcycle (State : in out CSR_State; Count : Positive := 1) is
   begin
      --  mcountinhibit bit 0 (CY) inhibits mcycle
      if (State.Mcountinhibit and 1) = 0 then
         State.Mcycle := State.Mcycle + Unsigned_64 (Count);
      end if;
   end Increment_Mcycle;

   ------------------
   -- Is_Read_Only --
   ------------------

   function Is_Read_Only (Addr : CSR_Address) return Boolean is
   begin
      --  CSR address bits [11:10] = 11 means read-only
      return (Shift_Right (Addr, 10) and 3) = 3;
   end Is_Read_Only;

   ----------------------
   -- Get_Min_Privilege --
   ----------------------

   function Get_Min_Privilege (Addr : CSR_Address) return Privilege_Level is
      Level : constant Word := Shift_Right (Addr, 8) and 3;
   begin
      case Level is
         when 0 => return User;
         when 1 => return Supervisor;
         when 2 => return Reserved;
         when 3 => return Machine;
         when others => return Machine;
      end case;
   end Get_Min_Privilege;

   ---------------------
   -- Can_Access_CSR --
   ---------------------

   function Can_Access_CSR (Addr : CSR_Address;
                            Priv : Privilege_Level) return Boolean is
      Required : constant Privilege_Level := Get_Min_Privilege (Addr);
   begin
      return Privilege_Level'Pos (Priv) >= Privilege_Level'Pos (Required);
   end Can_Access_CSR;

   --------------
   -- CSR_Name --
   --------------

   function CSR_Name (Addr : CSR_Address) return String is
   begin
      case Addr is
         --  Supervisor CSRs
         when CSR_SSTATUS   => return "sstatus";
         when CSR_SIE       => return "sie";
         when CSR_STVEC     => return "stvec";
         when CSR_SSCRATCH  => return "sscratch";
         when CSR_SEPC      => return "sepc";
         when CSR_SCAUSE    => return "scause";
         when CSR_STVAL     => return "stval";
         when CSR_SIP       => return "sip";
         when CSR_SATP      => return "satp";
         --  Machine CSRs
         when CSR_MSTATUS   => return "mstatus";
         when CSR_MISA      => return "misa";
         when CSR_MEDELEG   => return "medeleg";
         when CSR_MIDELEG   => return "mideleg";
         when CSR_MIE       => return "mie";
         when CSR_MTVEC     => return "mtvec";
         when CSR_MSCRATCH  => return "mscratch";
         when CSR_MEPC      => return "mepc";
         when CSR_MCAUSE    => return "mcause";
         when CSR_MTVAL     => return "mtval";
         when CSR_MIP       => return "mip";
         when CSR_MCYCLE    => return "mcycle";
         when CSR_MINSTRET  => return "minstret";
         when CSR_MCYCLEH   => return "mcycleh";
         when CSR_MINSTRETH => return "minstreth";
         when CSR_MVENDORID => return "mvendorid";
         when CSR_MARCHID   => return "marchid";
         when CSR_MIMPID    => return "mimpid";
         when CSR_MHARTID   => return "mhartid";
         when CSR_CYCLE          => return "cycle";
         when CSR_TIME           => return "time";
         when CSR_INSTRET        => return "instret";
         when CSR_CYCLEH         => return "cycleh";
         when CSR_TIMEH          => return "timeh";
         when CSR_INSTRETH       => return "instreth";
         when CSR_MCOUNTINHIBIT  => return "mcountinhibit";
         when CSR_MCOUNTEREN     => return "mcounteren";
         when CSR_SCOUNTEREN     => return "scounteren";
         when others =>
            declare
               Hex : constant String := "0123456789abcdef";
               Res : String (1 .. 5) := "0x???";
            begin
               Res (3) := Hex (Natural (Shift_Right (Addr, 8) and 16#F#) + 1);
               Res (4) := Hex (Natural (Shift_Right (Addr, 4) and 16#F#) + 1);
               Res (5) := Hex (Natural (Addr and 16#F#) + 1);
               return Res;
            end;
      end case;
   end CSR_Name;

   ----------------
   -- To_Mcause --
   ----------------

   function To_Mcause (Code : Exception_Code) return Word is
   begin
      case Code is
         when No_Exception       => return 0;
         when Illegal_Instruction => return CAUSE_ILLEGAL_INSN;
         when Misaligned_Fetch   => return CAUSE_INSN_MISALIGNED;
         when Misaligned_Load    => return CAUSE_LOAD_MISALIGNED;
         when Misaligned_Store   => return CAUSE_STORE_MISALIGNED;
         when Load_Access_Fault  => return CAUSE_LOAD_ACCESS_FAULT;
         when Store_Access_Fault => return CAUSE_STORE_ACCESS_FAULT;
         when Environment_Call   => return CAUSE_ECALL_U;
         when Breakpoint         => return CAUSE_BREAKPOINT;
         when Insn_Page_Fault    => return CAUSE_INSN_PAGE_FAULT;
         when Load_Page_Fault    => return CAUSE_LOAD_PAGE_FAULT;
         when Store_Page_Fault   => return CAUSE_STORE_PAGE_FAULT;
      end case;
   end To_Mcause;

end RISCV.CSR;
