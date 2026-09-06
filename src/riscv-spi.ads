-- ***************************************************************************
--         RISC-V Emulator - SPI (Serial Peripheral Interface)
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

--  Simple SPI (Serial Peripheral Interface) peripheral with Flash emulation
--
--  Memory-mapped registers (offset from base address):
--    0x00  CTRL      - Control register
--                      bit 0: Enable (1=enabled, 0=disabled)
--                      bit 1: CS (Chip Select, 0=active, 1=inactive)
--                      bit 2-7: Reserved
--    0x04  STATUS    - Status register
--                      bit 0: Busy (1=transfer in progress, 0=idle)
--                      bit 1: TX Ready (1=can write data, 0=busy)
--                      bit 2: RX Valid (1=data available, 0=empty)
--                      bit 3-7: Reserved
--    0x08  DATA      - Data register (read=MISO, write=MOSI)
--    0x0C  PRESCALE  - Clock prescaler (divides system clock)
--
--  Total size: 16 bytes (0x10)
--
--  Flash Memory Simulation:
--    - 64KB simulated SPI flash at 0x00000000 (flash address space)
--    - Standard SPI flash commands:
--      0x03: Read data
--      0x02: Page program (write)
--      0x9F: Read JEDEC ID
--      0x05: Read status register
--      0x06: Write enable

package RISCV.SPI is

   --  Default SPI base address
   Default_Base_Address : constant Memory_Address := 16#1002_0000#;

   --  SPI address range size
   SPI_Size : constant := 16#10#;  -- 16 bytes

   --  Register offsets
   REG_CTRL     : constant := 16#00#;  -- Control register
   REG_STATUS   : constant := 16#04#;  -- Status register
   REG_DATA     : constant := 16#08#;  -- Data register
   REG_PRESCALE : constant := 16#0C#;  -- Clock prescaler

   --  Control register bits
   CTRL_ENABLE : constant := 16#01#;  -- SPI enable
   CTRL_CS     : constant := 16#02#;  -- Chip select (0=active)

   --  Status register bits
   STATUS_BUSY     : constant := 16#01#;  -- Transfer in progress
   STATUS_TX_READY : constant := 16#02#;  -- TX ready
   STATUS_RX_VALID : constant := 16#04#;  -- RX data valid

   --  SPI Flash commands
   CMD_READ         : constant := 16#03#;  -- Read data
   CMD_PAGE_PROGRAM : constant := 16#02#;  -- Page program
   CMD_READ_ID      : constant := 16#9F#;  -- Read JEDEC ID
   CMD_READ_STATUS  : constant := 16#05#;  -- Read status register
   CMD_WRITE_ENABLE : constant := 16#06#;  -- Write enable

   --  Flash size (64KB)
   Flash_Size : constant := 64 * 1024;

   --  Flash memory array
   type Flash_Memory is array (0 .. Flash_Size - 1) of Byte;
   type Flash_Memory_Access is access Flash_Memory;

   --  Flash state machine
   type Flash_State is (
      Idle,           -- Waiting for command
      Read_Cmd,       -- Read command received, waiting for address
      Read_Addr1,     -- First address byte
      Read_Addr2,     -- Second address byte
      Read_Addr3,     -- Third address byte
      Read_Data,      -- Reading data
      Program_Cmd,    -- Program command received
      Program_Addr1,  -- First address byte
      Program_Addr2,  -- Second address byte
      Program_Addr3,  -- Third address byte
      Program_Data    -- Programming data
   );

   type SPI_State is record
      Base_Address : Memory_Address;
      Enabled      : Boolean;
      --  Registers
      Control      : Byte;    -- Control register
      Status       : Byte;    -- Status register
      Data_Out     : Byte;    -- Data to transmit (MOSI)
      Data_In      : Byte;    -- Received data (MISO)
      Prescale     : Byte;    -- Clock prescaler
      --  Flash simulation
      Flash        : Flash_Memory_Access;
      Flash_FSM    : Flash_State;
      Flash_Addr   : Word;    -- Current flash address
      Write_Enable : Boolean; -- Write enable latch
   end record;

   --  Initialize SPI
   procedure Initialize (S    : out SPI_State;
                         Base : Memory_Address := Default_Base_Address);

   --  Finalize SPI (free flash memory)
   procedure Finalize (S : in out SPI_State);

   --  Check if an address is in the SPI range
   function Is_SPI_Address (S    : SPI_State;
                            Addr : Memory_Address) return Boolean;

   --  Read from SPI register
   function Read_Word (S    : in out SPI_State;
                       Addr : Memory_Address) return Word;

   function Read_Byte (S    : in out SPI_State;
                       Addr : Memory_Address) return Byte;

   --  Write to SPI register
   procedure Write_Word (S    : in out SPI_State;
                         Addr : Memory_Address;
                         Data : Word);

   procedure Write_Byte (S    : in out SPI_State;
                         Addr : Memory_Address;
                         Data : Byte);

   --  Get flash memory for direct access (testing)
   function Get_Flash (S : SPI_State) return Flash_Memory_Access;

end RISCV.SPI;
