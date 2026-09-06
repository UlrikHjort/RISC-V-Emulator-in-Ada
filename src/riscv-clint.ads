-- ***************************************************************************
--          RISC-V Emulator - CLINT (Core Local Interruptor)
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

--  CLINT (Core Local Interruptor) - Timer and Software Interrupt Controller
--
--  Standard RISC-V CLINT memory map (2 harts):
--    0x0000        msip[0]     - Machine Software Interrupt Pending hart 0
--    0x0004        msip[1]     - Machine Software Interrupt Pending hart 1
--    0x4000        mtimecmp[0] - Machine Timer Compare hart 0 (8 bytes)
--    0x4008        mtimecmp[1] - Machine Timer Compare hart 1 (8 bytes)
--    0xBFF8        mtime       - Machine Timer (8 bytes, shared)
--
--  The CLINT occupies 64 KB (0x10000 bytes) of address space.
--  Timer increments once per Tick call (typically once per instruction).

package RISCV.CLINT is

   --  Default CLINT base address (QEMU virt machine)
   Default_Base_Address : constant Memory_Address := 16#0200_0000#;

   --  CLINT address range size (64 KB)
   CLINT_Size : constant := 16#10000#;

   --  Register offsets
   REG_MSIP      : constant := 16#0000#;  -- Machine Software Interrupt Pending hart 0
   REG_MSIP1     : constant := 16#0004#;  -- Machine Software Interrupt Pending hart 1
   REG_MTIMECMP  : constant := 16#4000#;  -- Machine Timer Compare hart 0
   REG_MTIMECMP1 : constant := 16#4008#;  -- Machine Timer Compare hart 1
   REG_MTIME     : constant := 16#BFF8#;  -- Machine Timer

   --  64-bit timer value (mtime and mtimecmp are 64-bit)
   subtype Timer_Value is Unsigned_64;

   --  Per-hart array types
   type Timer_Array is array (0 .. 1) of Timer_Value;
   type Bool_Array  is array (0 .. 1) of Boolean;

   type CLINT_State is record
      Base_Address    : Memory_Address;
      Enabled         : Boolean;
      --  Timer registers
      Mtime           : Timer_Value;   -- Current timer value (shared)
      Mtimecmp        : Timer_Array;   -- Timer compare per hart
      --  Software interrupt per hart
      Msip            : Bool_Array;    -- Software IRQ pending
      --  Interrupt status per hart
      Timer_Interrupt : Bool_Array;    -- Timer IRQ pending
   end record;

   --  Initialize CLINT
   procedure Initialize (C    : out CLINT_State;
                         Base : Memory_Address := Default_Base_Address);

   --  Check if an address is in the CLINT range
   function Is_CLINT_Address (C    : CLINT_State;
                              Addr : Memory_Address) return Boolean;

   --  Read from CLINT register (byte access)
   function Read_Byte (C    : CLINT_State;
                       Addr : Memory_Address) return Byte;

   --  Read from CLINT register (word access)
   function Read_Word (C    : CLINT_State;
                       Addr : Memory_Address) return Word;

   --  Write to CLINT register (byte access)
   procedure Write_Byte (C    : in out CLINT_State;
                         Addr : Memory_Address;
                         Data : Byte);

   --  Write to CLINT register (word access)
   procedure Write_Word (C    : in out CLINT_State;
                         Addr : Memory_Address;
                         Data : Word);

   --  Advance timer by one tick (call once per instruction or cycle)
   procedure Tick (C : in out CLINT_State);

   --  Advance timer by multiple ticks
   procedure Tick_N (C : in out CLINT_State; N : Positive);

   --  Check if timer interrupt is pending (for specified hart, default hart 0)
   function Timer_Interrupt_Pending (C    : CLINT_State;
                                     Hart : Natural := 0) return Boolean;

   --  Check if software interrupt is pending (for specified hart, default hart 0)
   function Software_Interrupt_Pending (C    : CLINT_State;
                                        Hart : Natural := 0) return Boolean;

   --  Clear timer interrupt (called when interrupt is handled; default hart 0)
   procedure Clear_Timer_Interrupt (C    : in out CLINT_State;
                                    Hart : Natural := 0);

   --  Get current mtime value
   function Get_Mtime (C : CLINT_State) return Timer_Value;

   --  Get mtimecmp value (for specified hart, default hart 0)
   function Get_Mtimecmp (C    : CLINT_State;
                          Hart : Natural := 0) return Timer_Value;

   --  Set mtimecmp directly (used by SBI set_timer; default hart 0)
   procedure Set_Mtimecmp (C     : in out CLINT_State;
                            Value : Timer_Value;
                            Hart  : Natural := 0);

end RISCV.CLINT;
