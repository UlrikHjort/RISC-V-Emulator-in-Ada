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

--  PLIC (Platform-Level Interrupt Controller)
--
--  Implements a simplified RISC-V PLIC with 32 interrupt sources and 2
--  contexts (hart 0 M-mode = context 0, hart 0 S-mode = context 1).
--
--  Memory map (relative to Base_Address, QEMU virt standard 0x0C000000):
--
--    0x000000 + src*4    -- priority[src]  : priority level (0 = disabled)
--    0x001000            -- pending[0]     : 1 bit per source (bit 0 always 0)
--    0x002000 + ctx*0x80 -- enable[ctx][0] : 1 bit per source
--    0x200000 + ctx*0x1000 + 0  -- threshold[ctx]
--    0x200000 + ctx*0x1000 + 4  -- claim/complete[ctx]
--
--  Interrupt source IDs (0 = no interrupt):
--    PLIC_SRC_UART  = 1
--    PLIC_SRC_GPIO  = 2
--    PLIC_SRC_SPI   = 3
--    PLIC_SRC_I2C   = 4
--    PLIC_SRC_TIMER = 5
--
--  This implementation supports level-triggered interrupts.  The pending
--  bit for a source is set externally (via Set_Pending) and cleared when
--  the hart claims the interrupt (via Claim).  The hart must handle the
--  interrupt and write Complete to allow re-assertion.

package RISCV.PLIC is

   --  Default PLIC base address (QEMU virt machine)
   Default_Base_Address : constant Memory_Address := 16#0C00_0000#;

   --  PLIC address range size (4 MB covers all register regions)
   PLIC_Size : constant := 16#0040_0000#;

   --  Number of supported interrupt sources (source 0 = reserved/no int)
   Max_Sources : constant := 32;

   --  Number of supported contexts (0 = M-mode hart 0, 1 = S-mode hart 0)
   Max_Contexts : constant := 2;

   --  Register offsets
   REG_PRIORITY_BASE   : constant := 16#000000#;  -- src*4 from here
   REG_PENDING_BASE    : constant := 16#001000#;  -- 1 word (32 sources)
   REG_ENABLE_BASE     : constant := 16#002000#;  -- ctx*0x80 per context
   REG_THRESHOLD_BASE  : constant := 16#200000#;  -- ctx*0x1000 per context
   --  Claim/complete is at REG_THRESHOLD_BASE + ctx*0x1000 + 4

   --  Context stride for threshold/claim region
   CTX_STRIDE : constant := 16#1000#;

   --  Context IDs
   CTX_M_MODE : constant := 0;  -- Machine mode, hart 0
   CTX_S_MODE : constant := 1;  -- Supervisor mode, hart 0

   --  Interrupt source IDs
   PLIC_SRC_NONE       : constant := 0;
   PLIC_SRC_UART       : constant := 1;
   PLIC_SRC_GPIO       : constant := 2;
   PLIC_SRC_SPI        : constant := 3;
   PLIC_SRC_I2C        : constant := 4;
   PLIC_SRC_TIMER      : constant := 5;
   PLIC_SRC_VIRTIO_BLK : constant := 8;

   --  Priority and enable arrays
   subtype Source_Id   is Natural range 0 .. Max_Sources - 1;
   subtype Context_Id  is Natural range 0 .. Max_Contexts - 1;
   type Priority_Array is array (Source_Id)  of Word;
   type Enable_Array   is array (Context_Id) of Word;
   type Threshold_Array is array (Context_Id) of Word;
   type Claimed_Array  is array (Context_Id) of Source_Id;

   type PLIC_State is record
      Base_Address : Memory_Address;
      Enabled      : Boolean;
      --  Per-source priority (0 = disabled, 1..7 = priority level)
      Priority     : Priority_Array;
      --  Pending bits: bit N = source N is pending
      Pending      : Word;
      --  Enable bits per context: bit N = source N enabled for that context
      Enable       : Enable_Array;
      --  Threshold per context: only interrupts with priority > threshold fire
      Threshold    : Threshold_Array;
      --  Currently claimed source per context (0 = none in service)
      Claimed      : Claimed_Array;
   end record;

   --  Initialize PLIC to reset state
   procedure Initialize (P    : out PLIC_State;
                         Base : Memory_Address := Default_Base_Address);

   --  Check if an address is in the PLIC range
   function Is_PLIC_Address (P    : PLIC_State;
                              Addr : Memory_Address) return Boolean;

   --  Register read/write (byte and word)
   function Read_Byte (P    : PLIC_State;
                       Addr : Memory_Address) return Byte;

   function Read_Word (P    : PLIC_State;
                       Addr : Memory_Address) return Word;

   procedure Write_Byte (P    : in out PLIC_State;
                         Addr : Memory_Address;
                         Data : Byte);

   procedure Write_Word (P    : in out PLIC_State;
                         Addr : Memory_Address;
                         Data : Word);

   --  Assert (set) the pending bit for a source
   procedure Set_Pending (P   : in out PLIC_State;
                          Src : Source_Id);

   --  Clear the pending bit for a source (called by peripheral when cleared)
   procedure Clear_Pending (P   : in out PLIC_State;
                             Src : Source_Id);

   --  Return True if any enabled+pending source with priority > threshold
   --  exists for the given context
   function Interrupt_Pending (P   : PLIC_State;
                                Ctx : Context_Id) return Boolean;

   --  Claim: return the highest-priority pending+enabled source for context,
   --  atomically clearing its pending bit.  Returns 0 if none.
   function Claim (P   : in out PLIC_State;
                   Ctx : Context_Id) return Source_Id;

   --  Complete: signal end-of-interrupt for a claimed source
   procedure Complete (P   : in out PLIC_State;
                       Ctx : Context_Id;
                       Src : Source_Id);

end RISCV.PLIC;
