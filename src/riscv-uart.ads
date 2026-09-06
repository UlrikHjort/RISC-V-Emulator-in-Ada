-- ***************************************************************************
--              RISC-V Emulator - UART Emulation
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

--  Simple 16550-compatible UART emulation
--
--  Memory-mapped registers (active, offset from base address):
--    0x0 - THR/RBR: Transmit Holding / Receive Buffer Register
--    0x1 - IER: Interrupt Enable Register
--    0x2 - IIR: Interrupt Identification Register (read-only)
--    0x5 - LSR: Line Status Register
--
--  IER bits:
--    Bit 0: Enable Received Data Available Interrupt
--    Bit 1: Enable Transmitter Holding Register Empty Interrupt
--
--  IIR bits:
--    Bit 0: Interrupt Pending (0 = interrupt pending, 1 = no interrupt)
--    Bits 1-3: Interrupt ID (010 = THR empty, 100 = received data)
--
--  LSR bits:
--    Bit 0: Data Ready (DR) - set when input available
--    Bit 5: THR Empty (THRE) - always 1 (ready to transmit)
--    Bit 6: Transmitter Empty (TEMT) - always 1

with RISCV.PTY;

package RISCV.UART is

   --  Default UART base address (same as QEMU virt machine)
   Default_Base_Address : constant Memory_Address := 16#1000_0000#;

   --  UART address range size
   UART_Size : constant := 8;

   --  Register offsets
   REG_THR_RBR : constant := 0;  -- Transmit/Receive buffer
   REG_IER     : constant := 1;  -- Interrupt Enable Register
   REG_IIR     : constant := 2;  -- Interrupt Identification Register
   REG_LSR     : constant := 5;  -- Line Status Register

   --  IER bit masks
   IER_RDA  : constant Byte := 16#01#;  -- Received Data Available
   IER_THRE : constant Byte := 16#02#;  -- THR Empty

   --  IIR bit masks
   IIR_NO_INT  : constant Byte := 16#01#;  -- No interrupt pending
   IIR_THR     : constant Byte := 16#02#;  -- THR empty interrupt (bits 1-3 = 001)
   IIR_RDA     : constant Byte := 16#04#;  -- Received data interrupt (bits 1-3 = 010)

   --  LSR bit masks
   LSR_DR   : constant Byte := 16#01#;  -- Data Ready
   LSR_THRE : constant Byte := 16#20#;  -- THR Empty
   LSR_TEMT : constant Byte := 16#40#;  -- Transmitter Empty

   --  Input buffer size
   Input_Buffer_Size : constant := 256;

   type Input_Buffer_Type is array (0 .. Input_Buffer_Size - 1) of Byte;

   --  Maximum length of PTY slave device path
   PTY_Path_Max : constant := 64;

   type UART_State is record
      Base_Address  : Memory_Address;
      Enabled       : Boolean;
      --  Registers
      IER           : Byte;     -- Interrupt Enable Register
      IIR           : Byte;     -- Interrupt Identification Register
      --  Input buffering
      Input_Buffer  : Input_Buffer_Type;
      Input_Head    : Natural;  -- Next position to write
      Input_Tail    : Natural;  -- Next position to read
      Input_Count   : Natural;  -- Number of bytes in buffer
      --  PTY backend
      PTY_Enabled   : Boolean;
      PTY_Master    : PTY.File_Descriptor;
      PTY_Slave     : String (1 .. PTY_Path_Max);
      PTY_Slave_Len : Natural;
   end record;

   --  Initialize UART
   procedure Initialize (UART : out UART_State;
                         Base : Memory_Address := Default_Base_Address);

   --  Check if an address is in the UART range
   function Is_UART_Address (UART : UART_State;
                             Addr : Memory_Address) return Boolean;

   --  Read from UART register
   function Read (UART : in out UART_State;
                  Addr : Memory_Address) return Byte;

   --  Write to UART register
   procedure Write (UART : in out UART_State;
                    Addr : Memory_Address;
                    Data : Byte);

   --  Add input to the UART receive buffer (for external input)
   procedure Add_Input (UART : in out UART_State;
                        Data : Byte);

   --  Add a string to the input buffer
   procedure Add_Input_String (UART : in out UART_State;
                               Str  : String);

   --  Check if input is available
   function Input_Available (UART : UART_State) return Boolean;

   --  Poll for console input (non-blocking)
   --  Returns True if input was added
   function Poll_Input (UART : in out UART_State) return Boolean;

   --  Initialize UART with PTY backend
   procedure Initialize_PTY (UART    : out UART_State;
                              Base    : Memory_Address := Default_Base_Address;
                              Success : out Boolean);

   --  Close PTY if enabled
   procedure Finalize (UART : in out UART_State);

   --  Get the PTY slave device path
   function Get_PTY_Path (UART : UART_State) return String;

   --  Check if an interrupt is pending
   function Interrupt_Pending (UART : UART_State) return Boolean;

   --  Update interrupt status (call after input changes or reads)
   procedure Update_Interrupts (UART : in out UART_State);

end RISCV.UART;
