-- ***************************************************************************
--          RISC-V Emulator - DMA Controller Peripheral
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

-- RISC-V DMA Controller Peripheral
-- Provides high-performance bulk data transfers
--
-- Memory Map (per channel, base address configurable):
--   Channel 0: Base + 0x00
--   Channel 1: Base + 0x20
--   Channel 2: Base + 0x40
--   Channel 3: Base + 0x60
--
-- Per-Channel Registers (offset from channel base):
--   0x00: CH_SRC     - Source address
--   0x04: CH_DST     - Destination address
--   0x08: CH_COUNT   - Transfer count (bytes)
--   0x0C: CH_CTRL    - Control register
--   0x10: CH_STATUS  - Status register
--
-- Control Register (CH_CTRL) bits:
--   bit 0:    ENABLE     - Enable channel
--   bit 1:    START      - Start transfer (auto-clears)
--   bit 2:    INT_EN     - Interrupt on completion
--   bit 3:    SRC_INC    - Increment source address
--   bit 4:    DST_INC    - Increment destination address
--   bits 5-6: XFER_SIZE  - Transfer size (00=byte, 01=halfword, 10=word)
--
-- Status Register (CH_STATUS) bits:
--   bit 0: BUSY  - Transfer in progress (read-only)
--   bit 1: DONE  - Transfer complete (write 1 to clear)
--   bit 2: ERROR - Transfer error (write 1 to clear)

package RISCV.DMA is

   -- Default memory-mapped base address (configurable)
   Default_Base_Address : constant Memory_Address := 16#10060000#;

   -- Number of DMA channels
   Num_Channels : constant := 4;

   -- DMA channel state
   type DMA_Channel is record
      Source_Addr    : Word := 0;
      Dest_Addr      : Word := 0;
      Count          : Word := 0;       -- Bytes remaining
      Initial_Count  : Word := 0;       -- For tracking progress
      Control        : Byte := 0;
      Status         : Byte := 0;
      -- Internal state
      Current_Src    : Word := 0;       -- Current source position
      Current_Dst    : Word := 0;       -- Current destination position
   end record;

   type DMA_Channel_Array is array (0 .. Num_Channels - 1) of DMA_Channel;

   type DMA_State is record
      Base_Address   : Memory_Address;
      Enabled        : Boolean := False;
      Channels       : DMA_Channel_Array;
   end record;

   procedure Initialize (DMA : out DMA_State;
                        Base : Memory_Address);

   -- Read from DMA register
   function Read (DMA : DMA_State;
                  Offset : Memory_Address) return Byte;

   -- Write to DMA register
   procedure Write (DMA : in out DMA_State;
                   Offset : Memory_Address;
                   Value : Byte);

   -- Process DMA transfers (call periodically from main loop)
   -- Returns True if any channel completed a transfer
   function Process (DMA : in out DMA_State;
                    Memory : access procedure (Addr : Memory_Address;
                                               Data : out Byte;
                                               Success : out Boolean);
                    Memory_Write : access procedure (Addr : Memory_Address;
                                                    Data : Byte;
                                                    Success : out Boolean))
                    return Boolean;

   -- Check if any channel has interrupt pending
   function Interrupt_Pending (DMA : DMA_State) return Boolean;

   -- Get status for debugging
   procedure Print_Status (DMA : DMA_State);

   -- Memory-mapped I/O helpers
   function Is_DMA_Address (DMA : DMA_State;
                            Address : Memory_Address) return Boolean;

   function Read_Byte (DMA : DMA_State;
                       Address : Memory_Address) return Byte;

   procedure Write_Byte (DMA : in out DMA_State;
                         Address : Memory_Address;
                         Value : Byte);

end RISCV.DMA;
