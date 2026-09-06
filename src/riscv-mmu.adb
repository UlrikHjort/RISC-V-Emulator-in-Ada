-- ***************************************************************************
--              RISC-V Emulator - Sv39 MMU (3-level page table)
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

with RISCV.CSR;

package body RISCV.MMU is

   --  ======================================================================
   --  Sv39 constants
   --  ======================================================================

   --  PTE bit positions
   PTE_V_BIT : constant Natural := 0;   --  Valid
   PTE_R_BIT : constant Natural := 1;   --  Read
   PTE_W_BIT : constant Natural := 2;   --  Write
   PTE_X_BIT : constant Natural := 3;   --  Execute
   PTE_U_BIT : constant Natural := 4;   --  User
   PTE_A_BIT : constant Natural := 6;   --  Accessed
   PTE_D_BIT : constant Natural := 7;   --  Dirty

   --  mstatus bit positions
   MSTATUS_SUM_BIT : constant Natural := 18;  --  Supervisor User Memory
   MSTATUS_MXR_BIT : constant Natural := 19;  --  Make eXecutable Readable

   --  Page size
   Page_Shift : constant Natural := 12;  --  4096 = 2**12

   --  PPN mask (44 bits in PTE at bits 53:10)
   PPN_Mask : constant Double_Word := 16#FFF_FFFF_FFFF#;

   --  VPN field mask (9 bits)
   VPN_Mask : constant Double_Word := 16#1FF#;

   --  ======================================================================
   --  Read a 64-bit PTE from memory (two 32-bit reads)
   --  ======================================================================
   function Read_PTE (Mem  : in out Memory.Memory_Unit;
                      Addr : Double_Word) return Double_Word is
      Lo : constant Word := Memory.Read_Word (Mem, Memory_Address (Addr));
      Hi : constant Word := Memory.Read_Word (Mem, Memory_Address (Addr + 4));
   begin
      return Double_Word (Lo) or Shift_Left (Double_Word (Hi), 32);
   end Read_PTE;

   --  ======================================================================
   --  Write a 64-bit PTE back to memory
   --  ======================================================================
   procedure Write_PTE (Mem   : in out Memory.Memory_Unit;
                        Addr  : Double_Word;
                        Value : Double_Word) is
   begin
      Memory.Write_Word (Mem, Memory_Address (Addr),
                         Word (Value and 16#FFFF_FFFF#));
      Memory.Write_Word (Mem, Memory_Address (Addr + 4),
                         Word (Shift_Right (Value, 32)));
   end Write_PTE;

   ---------------
   -- Flush_TLB --
   ---------------

   procedure Flush_TLB (State : in out MMU_State) is
   begin
      for I in State.TLB'Range loop
         State.TLB (I).Valid := False;
      end loop;
   end Flush_TLB;

   ---------------
   -- Translate --
   ---------------

   function Translate
     (State   : in out MMU_State;
      VA      : Memory_Address_64;
      Acc     : Access_Type;
      Priv    : Privilege_Level;
      SATP    : Double_Word;
      Mstatus : Double_Word;
      Mem     : in out RISCV.Memory.Memory_Unit;
      PA      : out Memory_Address_64;
      Cause   : out Double_Word;
      Tval    : out Double_Word) return Boolean
   is
      --  SATP fields
      SATP_Mode : constant Double_Word := Shift_Right (SATP, 60) and 16#F#;
      SATP_ASID : constant Half_Word   :=
         Half_Word (Shift_Right (SATP, 44) and 16#FFFF#);
      SATP_PPN  : constant Double_Word := SATP and 16#FFF_FFFF_FFFF#;

      --  VPN tag (VA >> 12) for TLB lookup
      VA_VPN_Tag : constant Double_Word :=
         Shift_Right (Double_Word (VA), Page_Shift);

      --  mstatus flags
      MXR : constant Boolean :=
         (Shift_Right (Mstatus, MSTATUS_MXR_BIT) and 1) = 1;
      SUM : constant Boolean :=
         (Shift_Right (Mstatus, MSTATUS_SUM_BIT) and 1) = 1;

      --  Helper: set page fault cause
      procedure Page_Fault is
      begin
         case Acc is
            when Execute => Cause := Double_Word (CSR.CAUSE_INSN_PAGE_FAULT);
            when Load    => Cause := Double_Word (CSR.CAUSE_LOAD_PAGE_FAULT);
            when Store   => Cause := Double_Word (CSR.CAUSE_STORE_PAGE_FAULT);
         end case;
         Tval := Double_Word (VA);
         PA   := 0;
      end Page_Fault;

      --  Helper: check leaf PTE permissions
      --  Returns True if access is permitted
      function Check_Perms (PTE_R, PTE_W_F, PTE_X_F, PTE_U_F : Boolean)
         return Boolean
      is
         Allow : Boolean := False;
      begin
         case Acc is
            when Execute =>
               Allow := PTE_X_F;
            when Load =>
               Allow := PTE_R or (MXR and PTE_X_F);
            when Store =>
               Allow := PTE_W_F;
         end case;
         if not Allow then
            return False;
         end if;
         --  U-mode: page must have U bit
         if Priv = User then
            return PTE_U_F;
         end if;
         --  S-mode: page must NOT have U bit, unless SUM
         if Priv = Supervisor then
            if PTE_U_F and not SUM then
               return False;
            end if;
         end if;
         return True;
      end Check_Perms;

   begin
      --  Bare/physical mode: MODE=0 or Machine mode
      if SATP_Mode = 0 or else Priv = Machine then
         PA    := VA;
         Cause := 0;
         Tval  := 0;
         return True;
      end if;

      --  Check TLB
      for I in State.TLB'Range loop
         declare
            E : TLB_Entry renames State.TLB (I);
         begin
            if E.Valid
               and then (E.G or else E.ASID = SATP_ASID)
               and then E.VPN_Tag = VA_VPN_Tag
            then
               --  TLB hit: check permissions
               if not Check_Perms (E.R, E.W, E.X, E.U) then
                  Page_Fault;
                  return False;
               end if;
               --  Compute physical address
               PA := Memory_Address_64
                  (Shift_Left (E.PPN, Page_Shift) or
                   (Double_Word (VA) and 16#FFF#));
               Cause := 0;
               Tval  := 0;
               return True;
            end if;
         end;
      end loop;

      --  TLB miss: page table walk
      declare
         Root_Addr : constant Double_Word := Shift_Left (SATP_PPN, Page_Shift);
         Walk_Addr : Double_Word := Root_Addr;
         PTE       : Double_Word;
         PTE_Addr  : Double_Word;
         PTE_PPN   : Double_Word;
         PTE_V     : Boolean;
         PTE_R_F   : Boolean;
         PTE_W_F   : Boolean;
         PTE_X_F   : Boolean;
         PTE_U_F   : Boolean;
         PTE_A     : Boolean;
         PTE_D     : Boolean;
         PTE_G     : Boolean;
         VPN_I     : Double_Word;
         Found     : Boolean := False;

         --  For leaf: 4KB-aligned PPN (handling superpage offsets)
         Leaf_PPN  : Double_Word;
      begin
         for I in reverse 0 .. 2 loop
            --  Extract VPN[i]
            VPN_I := Shift_Right (Double_Word (VA), Page_Shift + I * 9)
                     and VPN_Mask;

            --  PTE address = walk_addr + vpn_i * 8
            PTE_Addr := Walk_Addr + Shift_Left (VPN_I, 3);

            --  The memory bus is addressed by Memory_Address, which is 32
            --  bits wide, so a page table placed above 4 GB cannot be
            --  walked.  Report a page fault: letting the conversion inside
            --  Read_PTE raise Constraint_Error would take the whole
            --  emulator down on a value the guest chose.
            if PTE_Addr > Double_Word (Memory_Address'Last) - 7 then
               Page_Fault;
               return False;
            end if;

            --  Read PTE (two 32-bit reads)
            PTE := Read_PTE (Mem, PTE_Addr);

            --  Decode PTE bits
            PTE_V   := (Shift_Right (PTE, PTE_V_BIT) and 1) = 1;
            PTE_R_F := (Shift_Right (PTE, PTE_R_BIT) and 1) = 1;
            PTE_W_F := (Shift_Right (PTE, PTE_W_BIT) and 1) = 1;
            PTE_X_F := (Shift_Right (PTE, PTE_X_BIT) and 1) = 1;
            PTE_U_F := (Shift_Right (PTE, PTE_U_BIT) and 1) = 1;
            PTE_A   := (Shift_Right (PTE, PTE_A_BIT) and 1) = 1;
            PTE_D   := (Shift_Right (PTE, PTE_D_BIT) and 1) = 1;
            PTE_G   := (Shift_Right (PTE, 5) and 1) = 1;
            PTE_PPN := Shift_Right (PTE, 10) and PPN_Mask;

            --  Step d: invalid PTE
            if (not PTE_V) or (PTE_W_F and not PTE_R_F) then
               Page_Fault;
               return False;
            end if;

            --  Step e: is this a leaf? (R or X bit set)
            if PTE_R_F or PTE_X_F then
               --  Check for misaligned superpage
               if I > 0 then
                  --  Lower (i*9) bits of PTE.PPN must be zero
                  if (PTE_PPN and (Shift_Left (Double_Word (1), I * 9) - 1))
                     /= 0
                  then
                     Page_Fault;
                     return False;
                  end if;
               end if;

               --  Check permissions
               if not Check_Perms (PTE_R_F, PTE_W_F, PTE_X_F, PTE_U_F) then
                  Page_Fault;
                  return False;
               end if;

               --  Update A bit (and D if store)
               if not PTE_A or (Acc = Store and not PTE_D) then
                  declare
                     New_PTE : Double_Word := PTE;
                  begin
                     New_PTE := New_PTE or Shift_Left (Double_Word (1), PTE_A_BIT);
                     if Acc = Store then
                        New_PTE := New_PTE or
                                   Shift_Left (Double_Word (1), PTE_D_BIT);
                     end if;
                     Write_PTE (Mem, PTE_Addr, New_PTE);
                  end;
               end if;

               --  Compute leaf PPN (4KB):
               --  Superpage: keep upper bits from PTE_PPN, fill lower (I*9)
               --  bits from VA
               if I = 0 then
                  Leaf_PPN := PTE_PPN;
               else
                  declare
                     Superpage_Bits : constant Natural := I * 9;
                     Low_Mask : constant Double_Word :=
                        Shift_Left (Double_Word (1), Superpage_Bits) - 1;
                     VA_Low : constant Double_Word :=
                        Shift_Right (Double_Word (VA), Page_Shift) and Low_Mask;
                  begin
                     Leaf_PPN :=
                        (PTE_PPN and (not Low_Mask)) or VA_Low;
                  end;
               end if;

               --  Physical address
               PA := Memory_Address_64
                  (Shift_Left (Leaf_PPN, Page_Shift) or
                   (Double_Word (VA) and 16#FFF#));

               --  Insert into TLB (round-robin)
               declare
                  Way : constant Natural := State.Next_Way;
               begin
                  State.TLB (Way).VPN_Tag := VA_VPN_Tag;
                  State.TLB (Way).ASID    := SATP_ASID;
                  State.TLB (Way).PPN     := Leaf_PPN;
                  State.TLB (Way).R       := PTE_R_F;
                  State.TLB (Way).W       := PTE_W_F;
                  State.TLB (Way).X       := PTE_X_F;
                  State.TLB (Way).U       := PTE_U_F;
                  State.TLB (Way).G       := PTE_G;
                  State.TLB (Way).Valid   := True;
                  State.Next_Way :=
                     Natural ((State.Next_Way + 1) mod TLB_Size);
               end;

               Cause  := 0;
               Tval   := 0;
               Found  := True;
               exit;
            else
               --  Non-leaf: descend
               Walk_Addr := Shift_Left (PTE_PPN, Page_Shift);
            end if;
         end loop;

         if not Found then
            Page_Fault;
            return False;
         end if;
      end;

      return True;
   end Translate;

end RISCV.MMU;
