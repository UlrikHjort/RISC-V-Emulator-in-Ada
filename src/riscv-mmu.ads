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

with RISCV.Memory;

package RISCV.MMU is

   type Access_Type is (Load, Store, Execute);

   TLB_Size : constant := 64;

   type TLB_Entry is record
      VPN_Tag : Double_Word  := 0;    --  VA >> 12 (up to 27 bits for Sv39)
      ASID    : Half_Word    := 0;    --  address-space ID from satp
      PPN     : Double_Word  := 0;    --  physical page number (4KB granularity)
      R       : Boolean      := False;
      W       : Boolean      := False;
      X       : Boolean      := False;
      U       : Boolean      := False;
      G       : Boolean      := False;
      Valid   : Boolean      := False;
   end record;

   type TLB_Array is array (0 .. TLB_Size - 1) of TLB_Entry;

   type MMU_State is record
      TLB      : TLB_Array;
      Next_Way : Natural range 0 .. TLB_Size - 1 := 0;
   end record;

   --  Flush all TLB entries
   procedure Flush_TLB (State : in out MMU_State);

   --  Translate VA -> PA.
   --  Returns True on success (PA is set to physical address).
   --  Returns False on page fault (Cause and Tval are set).
   --  When SATP.MODE=0 or Priv=Machine, PA := VA (bare/physical mode).
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
      Tval    : out Double_Word) return Boolean;

end RISCV.MMU;
