-- ***************************************************************************
--          RISC-V Emulator - I2C Controller Peripheral
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
package RISCV.I2C is

   -- Default base address for I2C controller
   Default_Base_Address : constant Memory_Address := 16#10030000#;

   -- I2C Controller Registers (Base + Offset)
   -- Base address typically 0x10030000
   I2C_CTRL_OFFSET       : constant Memory_Address := 16#00#;  -- Control register
   I2C_STATUS_OFFSET     : constant Memory_Address := 16#04#;  -- Status register
   I2C_DATA_OFFSET       : constant Memory_Address := 16#08#;  -- Data register
   I2C_PRESCALE_OFFSET   : constant Memory_Address := 16#0C#;  -- Clock prescaler
   I2C_SLAVE_ADDR_OFFSET : constant Memory_Address := 16#10#;  -- Slave address

   -- Control Register Bits
   CTRL_ENABLE      : constant Byte := 16#01#;  -- Enable I2C controller
   CTRL_START       : constant Byte := 16#02#;  -- Generate START condition
   CTRL_STOP        : constant Byte := 16#04#;  -- Generate STOP condition
   CTRL_READ        : constant Byte := 16#08#;  -- Read operation
   CTRL_WRITE       : constant Byte := 16#10#;  -- Write operation
   CTRL_ACK         : constant Byte := 16#20#;  -- Send ACK (vs NACK)
   CTRL_FAST_MODE   : constant Byte := 16#40#;  -- Fast mode (400kHz vs 100kHz)

   -- Status Register Bits
   STATUS_BUSY      : constant Byte := 16#01#;  -- Transfer in progress
   STATUS_ACK_RECV  : constant Byte := 16#02#;  -- ACK received from slave
   STATUS_NACK_RECV : constant Byte := 16#04#;  -- NACK received from slave
   STATUS_ARB_LOST  : constant Byte := 16#08#;  -- Arbitration lost
   STATUS_READY     : constant Byte := 16#10#;  -- Ready for next operation

   -- I2C Device Types (simulated devices)
   type I2C_Device_Type is (
      None,
      Temperature_Sensor,   -- Simulated temperature sensor (TMP102-like)
      Accelerometer,        -- Simulated accelerometer (ADXL345-like)
      EEPROM_256           -- Simulated 256-byte EEPROM (24C02-like)
   );

   -- Device memory (for simulated I2C devices)
   type Device_Memory is array (Natural range <>) of Byte;
   type Device_Memory_Access is access Device_Memory;

   -- I2C Device State
   type I2C_Device_State is record
      Device_Type   : I2C_Device_Type := None;
      Address       : Byte := 0;        -- 7-bit I2C address
      Reg_Pointer   : Byte := 0;        -- Current register pointer
      Data          : Device_Memory_Access;  -- Device memory/registers
      Data_Size     : Natural := 0;
   end record;

   -- Maximum number of I2C devices on the bus
   Max_I2C_Devices : constant := 4;

   type I2C_Device_Array is array (1 .. Max_I2C_Devices) of I2C_Device_State;

   -- I2C Controller State
   type I2C_State is record
      Base          : Memory_Address;
      Enabled       : Boolean := False;

      -- Registers
      CTRL          : Byte := 0;
      STATUS        : Byte := STATUS_READY;  -- Initially ready
      DATA          : Byte := 0;
      PRESCALE      : Byte := 16#64#;  -- Default: 100 (for 100kHz)
      SLAVE_ADDR    : Byte := 0;       -- Current slave address

      -- Virtual I2C bus devices
      Devices       : I2C_Device_Array;
      Num_Devices   : Natural := 0;

      -- Transfer state
      Current_Device : Natural := 0;   -- 0 = none, 1..Max_I2C_Devices
      Transfer_Active : Boolean := False;
   end record;

   type I2C_Access is access I2C_State;

   -- Initialize I2C controller
   function Create (Base : Memory_Address) return I2C_Access;

   -- Initialize existing I2C state
   procedure Initialize (I2C : out I2C_State; Base : Memory_Address);

   -- Check if address belongs to I2C controller
   function Is_I2C_Address (I2C : I2C_State; Address : Memory_Address) return Boolean;

   -- Finalize I2C controller (free device memory)
   procedure Finalize (I2C : in out I2C_State);

   -- Free I2C controller
   procedure Free (I2C : in out I2C_Access);

   -- Add a virtual device to the I2C bus
   procedure Add_Device (
      I2C         : in out I2C_State;
      Device_Type : I2C_Device_Type;
      Address     : Byte
   );

   -- Read from I2C controller register (by absolute address)
   function Read_Byte (I2C : in out I2C_State; Address : Memory_Address) return Byte;

   -- Write to I2C controller register (by absolute address)
   procedure Write_Byte (
      I2C     : in out I2C_State;
      Address : Memory_Address;
      Value   : Byte
   );

   -- Process I2C operations (called when CTRL is written)
   procedure Process_Operation (I2C : in out I2C_State);

end RISCV.I2C;
