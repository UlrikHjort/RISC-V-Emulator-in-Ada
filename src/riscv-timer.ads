-- ***************************************************************************
--         RISC-V Emulator - Hardware Timer/PWM Peripheral
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
package RISCV.Timer is

   -- Default base address for timer peripheral
   Default_Base_Address : constant Memory_Address := 16#10040000#;

   -- Number of timer channels
   Num_Channels : constant := 4;

   -- Global Timer Registers (Base + Offset)
   TIMER_PRESCALE_OFFSET   : constant Memory_Address := 16#00#;  -- Clock prescaler (all channels)
   TIMER_INT_STATUS_OFFSET : constant Memory_Address := 16#04#;  -- Interrupt status flags
   TIMER_INT_ENABLE_OFFSET : constant Memory_Address := 16#08#;  -- Interrupt enable bits

   -- Per-Channel Registers (Base + 0x10 + channel*0x10)
   -- Channel 0: 0x10-0x1F, Channel 1: 0x20-0x2F, etc.
   CH_COUNTER_OFFSET : constant Memory_Address := 16#00#;  -- Current counter value
   CH_COMPARE_OFFSET : constant Memory_Address := 16#04#;  -- Compare/match value
   CH_CTRL_OFFSET    : constant Memory_Address := 16#08#;  -- Channel control
   CH_OUTPUT_OFFSET  : constant Memory_Address := 16#0C#;  -- PWM output duty (0-255)

   -- Channel Control Bits
   CH_CTRL_ENABLE      : constant Byte := 16#01#;  -- Enable channel
   CH_CTRL_PWM_MODE    : constant Byte := 16#02#;  -- PWM mode (vs timer mode)
   CH_CTRL_AUTO_RELOAD : constant Byte := 16#04#;  -- Auto-reload on match
   CH_CTRL_INT_ENABLE  : constant Byte := 16#08#;  -- Interrupt on match
   CH_CTRL_OUTPUT_HIGH : constant Byte := 16#10#;  -- PWM output starts high

   -- Interrupt Status/Enable Bits (one bit per channel)
   INT_CH0 : constant Byte := 16#01#;
   INT_CH1 : constant Byte := 16#02#;
   INT_CH2 : constant Byte := 16#04#;
   INT_CH3 : constant Byte := 16#08#;

   -- Timer Channel State
   type Timer_Channel is record
      Enabled      : Boolean := False;
      PWM_Mode     : Boolean := False;
      Auto_Reload  : Boolean := False;
      Int_Enable   : Boolean := False;
      Output_High  : Boolean := False;
      Counter      : Word := 0;
      Compare      : Word := 0;
      Output       : Byte := 0;  -- PWM duty cycle (0-255)
   end record;

   type Channel_Array is array (0 .. Num_Channels - 1) of Timer_Channel;

   -- Timer Controller State
   type Timer_State is record
      Base         : Memory_Address;
      Enabled      : Boolean := False;

      -- Global registers
      Prescale     : Byte := 1;      -- Clock divider
      Int_Status   : Byte := 0;      -- Interrupt flags
      Int_Enable   : Byte := 0;      -- Interrupt enables

      -- Timer channels
      Channels     : Channel_Array;

      -- Internal state
      Tick_Counter : Natural := 0;   -- Counts ticks for prescaler
   end record;

   type Timer_Access is access Timer_State;

   -- Initialize timer controller
   procedure Initialize (Timer : out Timer_State; Base : Memory_Address);

   -- Check if address belongs to timer controller
   function Is_Timer_Address (Timer : Timer_State; Address : Memory_Address) return Boolean;

   -- Read from timer controller register
   function Read_Byte (Timer : Timer_State; Address : Memory_Address) return Byte;

   -- Write to timer controller register
   procedure Write_Byte (
      Timer   : in out Timer_State;
      Address : Memory_Address;
      Value   : Byte
   );

   -- Update timer state (call once per CPU cycle or at regular intervals)
   procedure Tick (Timer : in out Timer_State);

   -- Check if any timer interrupt is pending
   function Interrupt_Pending (Timer : Timer_State) return Boolean;

   -- Get channel number from address offset
   function Get_Channel (Offset : Memory_Address) return Natural;

   -- Get register offset within channel
   function Get_Channel_Register (Offset : Memory_Address) return Memory_Address;

end RISCV.Timer;
