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
-- ***************************************************************************

package body RISCV.CSR64 is

   ----------------
   -- Initialize --
   ----------------

   procedure Initialize (State : out CSR_State_64) is
   begin
      State.Entries := (others => (Address => 0, Value => 0));
      State.Count   := 0;
      State.Mcycle  := 0;
      State.Minstret := 0;
      State.Mcountinhibit := 0;

      --  MISA: RV64IMAFDCV + S/U; MXL=2 (64-bit)
      Write (State, CSR_MISA,
             Shift_Left (Double_Word (1),  0) or   --  A
             Shift_Left (Double_Word (1),  2) or   --  C
             Shift_Left (Double_Word (1),  3) or   --  D
             Shift_Left (Double_Word (1),  5) or   --  F
             Shift_Left (Double_Word (1),  8) or   --  I
             Shift_Left (Double_Word (1), 12) or   --  M
             Shift_Left (Double_Word (1), 18) or   --  S
             Shift_Left (Double_Word (1), 20) or   --  U
             Shift_Left (Double_Word (1), 21) or   --  V
             Shift_Left (Double_Word (2), 62));     --  MXL=2 (64-bit)

      --  MSTATUS: UXL=SXL=10 (XLEN=64), interrupts disabled
      Write (State, CSR_MSTATUS, MSTATUS_UXL_64 or MSTATUS_SXL_64);

      Write (State, CSR_MTVEC,   0);
      Write (State, CSR_MEDELEG, 0);
      Write (State, CSR_MIDELEG, 0);
      Write (State, CSR_STVEC,   0);
      Write (State, CSR_SSCRATCH, 0);
      Write (State, CSR_SEPC,    0);
      Write (State, CSR_SCAUSE,  0);
      Write (State, CSR_STVAL,   0);
      Write (State, CSR_SATP,    0);
      Write (State, CSR_MVENDORID, 0);
      Write (State, CSR_MARCHID,   0);
      Write (State, CSR_MIMPID,    0);
      Write (State, CSR_MHARTID,   0);
      Write (State, CSR_MCOUNTEREN, 0);
      Write (State, CSR_SCOUNTEREN, 0);
   end Initialize;

   ----------
   -- Read --
   ----------

   function Read (State : CSR_State_64;
                  Addr  : CSR_Address) return Double_Word is
   begin
      case Addr is
         when CSR_MCYCLE | CSR_CYCLE =>
            return Double_Word (State.Mcycle);
         when CSR_MINSTRET | CSR_INSTRET =>
            return Double_Word (State.Minstret);
         when CSR_TIME =>
            return Double_Word (State.Mcycle);

         --  *H counters read 0 in RV64 (full 64-bit value in base register)
         when 16#B80# | 16#B82# | 16#C80# | 16#C81# | 16#C82# =>
            return 0;

         when CSR_SSTATUS =>
            return Read (State, CSR_MSTATUS) and SSTATUS_MASK;
         when CSR_SIE =>
            return Read (State, CSR_MIE) and SIP_MASK;
         when CSR_SIP =>
            return Read (State, CSR_MIP) and SIP_MASK;

         when CSR_MCOUNTINHIBIT =>
            return Double_Word (State.Mcountinhibit);

         --  HPM stubs
         when CSR_MHPMCOUNTER_LO .. CSR_MHPMCOUNTER_HI => return 0;
         when CSR_MHPMEVENT_LO .. CSR_MHPMEVENT_HI     => return 0;

         when others =>
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

   procedure Write (State : in out CSR_State_64;
                    Addr  : CSR_Address;
                    Value : Double_Word) is
   begin
      case Addr is
         when CSR_MCYCLE =>
            State.Mcycle := Unsigned_64 (Value);
            return;
         when CSR_MINSTRET =>
            State.Minstret := Unsigned_64 (Value);
            return;

         when CSR_SSTATUS =>
            declare
               Mstatus : constant Double_Word := Read (State, CSR_MSTATUS);
            begin
               Write (State, CSR_MSTATUS,
                      (Mstatus and not SSTATUS_MASK) or (Value and SSTATUS_MASK));
            end;
            return;
         when CSR_SIE =>
            declare
               Mie_Val : constant Double_Word := Read (State, CSR_MIE);
            begin
               Write (State, CSR_MIE,
                      (Mie_Val and not SIP_MASK) or (Value and SIP_MASK));
            end;
            return;
         when CSR_SIP =>
            declare
               Mip_Val : constant Double_Word := Read (State, CSR_MIP);
            begin
               --  Only SSIP is writable from S-mode; STIP and SEIP are
               --  read-only here and stay under hardware control.
               Write (State, CSR_MIP,
                      (Mip_Val and not SIP_WRITE_MASK) or
                      (Value and SIP_WRITE_MASK));
            end;
            return;

         when CSR_MCOUNTINHIBIT =>
            State.Mcountinhibit := Word (Value and 16#FD#);  -- mask bit 1
            return;

         --  HPM stubs: writes ignored
         when CSR_MHPMCOUNTER_LO .. CSR_MHPMCOUNTER_HI => return;
         when CSR_MHPMEVENT_LO .. CSR_MHPMEVENT_HI     => return;

         --  *H counter writes ignored in RV64
         when 16#B80# | 16#B82# => return;

         when others =>
            null;
      end case;

      for I in 0 .. State.Count - 1 loop
         if State.Entries (I).Address = Addr then
            State.Entries (I).Value := Value;
            return;
         end if;
      end loop;

      if State.Count < Max_CSR_Count then
         State.Entries (State.Count) := (Address => Addr, Value => Value);
         State.Count := State.Count + 1;
      end if;
   end Write;

   -----------------------
   -- Increment_Instret --
   -----------------------

   procedure Increment_Instret (State : in out CSR_State_64) is
   begin
      if (State.Mcountinhibit and 4) = 0 then
         State.Minstret := State.Minstret + 1;
      end if;
   end Increment_Instret;

   ---------------------
   -- Increment_Mcycle --
   ---------------------

   procedure Increment_Mcycle (State : in out CSR_State_64; Count : Positive := 1) is
   begin
      if (State.Mcountinhibit and 1) = 0 then
         State.Mcycle := State.Mcycle + Unsigned_64 (Count);
      end if;
   end Increment_Mcycle;

end RISCV.CSR64;
