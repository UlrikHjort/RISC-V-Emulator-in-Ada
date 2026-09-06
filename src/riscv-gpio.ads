-- ***************************************************************************
--          RISC-V Emulator - GPIO (General Purpose I/O)
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

--  Simple GPIO (General Purpose I/O) peripheral
--
--  Memory-mapped registers (offset from base address):
--    0x00  INPUT     - Read current pin values (32 bits)
--    0x04  OUTPUT    - Set output pin values (32 bits)
--    0x08  DIRECTION - Pin direction: 0=input, 1=output (32 bits)
--    0x0C  INT_EN    - Interrupt enable per pin (32 bits)
--    0x10  INT_FLAG  - Interrupt flags (write 1 to clear)
--    0x14  INT_TYPE  - Interrupt type: 0=level, 1=edge
--    0x18  PULL_EN   - Pull-up/down enable (32 bits)
--    0x1C  PULL_DIR  - Pull direction: 0=down, 1=up
--
--  Total size: 32 bytes (0x20)
--
--  For output pins, INPUT reflects the OUTPUT value.
--  For input pins, INPUT reflects the external value.

package RISCV.GPIO is

   --  Default GPIO base address
   Default_Base_Address : constant Memory_Address := 16#1001_0000#;

   --  GPIO address range size
   GPIO_Size : constant := 16#20#;  -- 32 bytes

   --  Register offsets
   REG_INPUT     : constant := 16#00#;  -- Read pin values
   REG_OUTPUT    : constant := 16#04#;  -- Write output values
   REG_DIRECTION : constant := 16#08#;  -- Direction (0=in, 1=out)
   REG_INT_EN    : constant := 16#0C#;  -- Interrupt enable
   REG_INT_FLAG  : constant := 16#10#;  -- Interrupt flags
   REG_INT_TYPE  : constant := 16#14#;  -- Interrupt type (level/edge)
   REG_PULL_EN   : constant := 16#18#;  -- Pull enable
   REG_PULL_DIR  : constant := 16#1C#;  -- Pull direction

   type GPIO_State is record
      Base_Address : Memory_Address;
      Enabled      : Boolean;
      --  Registers
      Input        : Word;    -- Current input values (external or loopback)
      Output       : Word;    -- Output register
      Direction    : Word;    -- 0=input, 1=output
      Int_Enable   : Word;    -- Interrupt enable mask
      Int_Flags    : Word;    -- Interrupt flags
      Int_Type     : Word;    -- 0=level, 1=edge
      Pull_Enable  : Word;    -- Pull-up/down enable
      Pull_Dir     : Word;    -- 0=pull-down, 1=pull-up
      --  External input (simulated external signals)
      External_In  : Word;    -- External input values
      --  Previous input for edge detection
      Prev_Input   : Word;
   end record;

   --  Initialize GPIO
   procedure Initialize (G    : out GPIO_State;
                         Base : Memory_Address := Default_Base_Address);

   --  Check if an address is in the GPIO range
   function Is_GPIO_Address (G    : GPIO_State;
                             Addr : Memory_Address) return Boolean;

   --  Read from GPIO register
   function Read_Word (G    : GPIO_State;
                       Addr : Memory_Address) return Word;

   function Read_Byte (G    : GPIO_State;
                       Addr : Memory_Address) return Byte;

   --  Write to GPIO register
   procedure Write_Word (G    : in out GPIO_State;
                         Addr : Memory_Address;
                         Data : Word);

   procedure Write_Byte (G    : in out GPIO_State;
                         Addr : Memory_Address;
                         Data : Byte);

   --  Set external input values (simulates external signals)
   procedure Set_External_Input (G     : in out GPIO_State;
                                 Value : Word);

   --  Set a single external input pin
   procedure Set_External_Pin (G     : in out GPIO_State;
                               Pin   : Natural;
                               Value : Boolean);

   --  Get current output values
   function Get_Output (G : GPIO_State) return Word;

   --  Get a single output pin
   function Get_Output_Pin (G   : GPIO_State;
                            Pin : Natural) return Boolean;

   --  Check if any interrupt is pending
   function Interrupt_Pending (G : GPIO_State) return Boolean;

   --  Update GPIO state (call periodically for edge detection)
   procedure Update (G : in out GPIO_State);

end RISCV.GPIO;
