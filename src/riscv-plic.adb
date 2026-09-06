-- ***************************************************************************
--          RISC-V Emulator - PLIC (Platform-Level Interrupt Controller)
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

package body RISCV.PLIC is

   --  Return the highest-priority source that is pending, enabled for Ctx,
   --  and has priority > Threshold[Ctx].  Returns 0 if none.
   function Best_Pending (P   : PLIC_State;
                           Ctx : Context_Id) return Source_Id is
      Best_Src  : Source_Id := 0;
      Best_Prio : Word := 0;
      Bit       : Word;
      Prio      : Word;
   begin
      for Src in 1 .. Max_Sources - 1 loop
         Bit := Shift_Left (1, Src);
         if (P.Pending and Bit) /= 0 and then
            (P.Enable (Ctx) and Bit) /= 0
         then
            Prio := P.Priority (Src);
            if Prio > P.Threshold (Ctx) and then Prio > Best_Prio then
               Best_Prio := Prio;
               Best_Src  := Src;
            end if;
         end if;
      end loop;
      return Best_Src;
   end Best_Pending;

   ----------------
   -- Initialize --
   ----------------

   procedure Initialize (P    : out PLIC_State;
                         Base : Memory_Address := Default_Base_Address) is
   begin
      P := (Base_Address => Base,
            Enabled      => True,
            Priority     => (others => 1),  -- default priority 1
            Pending      => 0,
            Enable       => (others => 16#FFFF_FFFF#),  -- all enabled by default
            Threshold    => (others => 0),              -- threshold 0 = all pass
            Claimed      => (others => 0));
      --  Source 0 priority must stay 0 (no interrupt source)
      P.Priority (0) := 0;
   end Initialize;

   ---------------------
   -- Is_PLIC_Address --
   ---------------------

   function Is_PLIC_Address (P    : PLIC_State;
                              Addr : Memory_Address) return Boolean is
   begin
      return P.Enabled and then
             Addr >= P.Base_Address and then
             Addr < P.Base_Address + PLIC_Size;
   end Is_PLIC_Address;

   ---------------
   -- Read_Byte --
   ---------------

   function Read_Byte (P    : PLIC_State;
                       Addr : Memory_Address) return Byte is
      W      : constant Word := Read_Word (P, Addr and not 3);
      Bidx   : constant Natural := Natural (Addr and 3);
   begin
      return Byte (Shift_Right (W, Bidx * 8) and 16#FF#);
   end Read_Byte;

   ---------------
   -- Read_Word --
   ---------------

   function Read_Word (P    : PLIC_State;
                       Addr : Memory_Address) return Word is
      Offset  : constant Memory_Address := Addr - P.Base_Address;
      Src_Nat : Natural;
      Ctx_Nat : Natural;
      Best    : Source_Id;
   begin
      --  Priority registers: 0x000000 + src*4
      if Offset < REG_PENDING_BASE then
         Src_Nat := Natural (Offset / 4);
         if Src_Nat < Max_Sources then
            return P.Priority (Src_Nat);
         end if;
         return 0;

      --  Pending register: 0x001000
      elsif Offset = REG_PENDING_BASE then
         return P.Pending;

      --  Enable registers: 0x002000 + ctx*0x80
      elsif Offset >= REG_ENABLE_BASE and then
            Offset < REG_THRESHOLD_BASE
      then
         Ctx_Nat := Natural ((Offset - REG_ENABLE_BASE) / 16#80#);
         if Ctx_Nat < Max_Contexts then
            return P.Enable (Context_Id (Ctx_Nat));
         end if;
         return 0;

      --  Threshold and claim/complete: 0x200000 + ctx*0x1000 + [0|4]
      elsif Offset >= REG_THRESHOLD_BASE then
         declare
            Ctx_Off : constant Memory_Address := Offset - REG_THRESHOLD_BASE;
         begin
            Ctx_Nat := Natural (Ctx_Off / CTX_STRIDE);
            if Ctx_Nat < Max_Contexts then
               if (Ctx_Off mod CTX_STRIDE) = 0 then
                  return P.Threshold (Context_Id (Ctx_Nat));
               elsif (Ctx_Off mod CTX_STRIDE) = 4 then
                  Best := Best_Pending (P, Context_Id (Ctx_Nat));
                  return Word (Best);
               end if;
            end if;
         end;
         return 0;
      end if;

      return 0;
   end Read_Word;

   ----------------
   -- Write_Byte --
   ----------------

   procedure Write_Byte (P    : in out PLIC_State;
                         Addr : Memory_Address;
                         Data : Byte) is
      Aligned : constant Memory_Address := Addr and not 3;
      Bidx    : constant Natural := Natural (Addr and 3);
      W       : Word := Read_Word (P, Aligned);
      Mask    : constant Word := Shift_Left (16#FF#, Bidx * 8);
   begin
      W := (W and not Mask) or Shift_Left (Word (Data), Bidx * 8);
      Write_Word (P, Aligned, W);
   end Write_Byte;

   ----------------
   -- Write_Word --
   ----------------

   procedure Write_Word (P    : in out PLIC_State;
                         Addr : Memory_Address;
                         Data : Word) is
      Offset  : constant Memory_Address := Addr - P.Base_Address;
      Src_Nat : Natural;
      Ctx_Nat : Natural;
      Best    : Source_Id;
   begin
      --  Priority registers: 0x000000 + src*4
      if Offset < REG_PENDING_BASE then
         Src_Nat := Natural (Offset / 4);
         if Src_Nat > 0 and then Src_Nat < Max_Sources then
            P.Priority (Src_Nat) := Data and 7;  -- max 3-bit priority
         end if;

      --  Pending register: read-only (cleared by claim)
      elsif Offset = REG_PENDING_BASE then
         null;

      --  Enable registers: 0x002000 + ctx*0x80
      elsif Offset >= REG_ENABLE_BASE and then
            Offset < REG_THRESHOLD_BASE
      then
         Ctx_Nat := Natural ((Offset - REG_ENABLE_BASE) / 16#80#);
         if Ctx_Nat < Max_Contexts then
            P.Enable (Context_Id (Ctx_Nat)) :=
               Data and not 1;  -- bit 0 always 0 (source 0)
         end if;

      --  Threshold and claim/complete: 0x200000 + ctx*0x1000 + [0|4]
      elsif Offset >= REG_THRESHOLD_BASE then
         declare
            Ctx_Off : constant Memory_Address := Offset - REG_THRESHOLD_BASE;
         begin
            Ctx_Nat := Natural (Ctx_Off / CTX_STRIDE);
            if Ctx_Nat < Max_Contexts then
               if (Ctx_Off mod CTX_STRIDE) = 0 then
                  P.Threshold (Context_Id (Ctx_Nat)) := Data and 7;
               elsif (Ctx_Off mod CTX_STRIDE) = 4 then
                  Best := Best_Pending (P, Context_Id (Ctx_Nat));
                  Complete (P, Context_Id (Ctx_Nat), Best);
               end if;
            end if;
         end;
      end if;
   end Write_Word;

   -----------------
   -- Set_Pending --
   -----------------

   procedure Set_Pending (P   : in out PLIC_State;
                          Src : Source_Id) is
   begin
      if Src > 0 then
         P.Pending := P.Pending or Shift_Left (1, Src);
      end if;
   end Set_Pending;

   -------------------
   -- Clear_Pending --
   -------------------

   procedure Clear_Pending (P   : in out PLIC_State;
                             Src : Source_Id) is
   begin
      if Src > 0 then
         P.Pending := P.Pending and not Shift_Left (1, Src);
      end if;
   end Clear_Pending;

   ------------------------
   -- Interrupt_Pending --
   ------------------------

   function Interrupt_Pending (P   : PLIC_State;
                                Ctx : Context_Id) return Boolean is
   begin
      return Best_Pending (P, Ctx) /= 0;
   end Interrupt_Pending;

   -----------
   -- Claim --
   -----------

   function Claim (P   : in out PLIC_State;
                   Ctx : Context_Id) return Source_Id is
      Best : constant Source_Id := Best_Pending (P, Ctx);
   begin
      if Best /= 0 then
         --  Clear pending so the interrupt is no longer asserted
         Clear_Pending (P, Best);
         P.Claimed (Ctx) := Best;
      end if;
      return Best;
   end Claim;

   --------------
   -- Complete --
   --------------

   procedure Complete (P   : in out PLIC_State;
                       Ctx : Context_Id;
                       Src : Source_Id) is
   begin
      if Src = P.Claimed (Ctx) then
         P.Claimed (Ctx) := 0;
      end if;
      --  Level-triggered: if the peripheral is still asserting, the run-loop
      --  will re-set the pending bit on the next Check_Interrupts cycle.
   end Complete;

end RISCV.PLIC;
