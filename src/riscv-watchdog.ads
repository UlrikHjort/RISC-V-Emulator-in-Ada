-- ***************************************************************************
--      RISC-V Emulator - Watchdog Timer Peripheral Implementation
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

-- RISC-V Watchdog Timer Peripheral
-- Provides system fault recovery via automatic reset
--
-- Memory Map (base address configurable):
--   0x00: WDT_CTRL   - Control register
--   0x04: WDT_COUNT  - Current counter value (read-only)
--   0x08: WDT_RELOAD - Reload value (timeout period)
--   0x0C: WDT_FEED   - Feed register (write any value to reset counter)
--
-- Control Register (WDT_CTRL) bits:
--   bit 0: ENABLE  - Enable watchdog (1=enabled, 0=disabled)
--   bit 1: RESET   - Reset occurred flag (read-only, cleared on read)
--
-- Operation:
--   - Counter counts down from RELOAD value
--   - When counter reaches 0, system resets
--   - Writing to FEED register reloads counter to RELOAD value
--   - Must "feed" watchdog before timeout to prevent reset

package RISCV.Watchdog is

   -- Default memory-mapped base address (configurable)
   Default_Base_Address : constant Memory_Address := 16#10050000#;

   type Watchdog_State is record
      Base_Address  : Memory_Address;
      Enabled       : Boolean := False;
      Counter       : Word := 0;
      Reload_Value  : Word := 1000;      -- Default 1000 ticks
      Reset_Flag    : Boolean := False;  -- Set when reset triggered
   end record;

   procedure Initialize (WDT : out Watchdog_State;
                        Base : Memory_Address);

   -- Read from watchdog register
   function Read (WDT : in out Watchdog_State;
                  Offset : Memory_Address) return Byte;

   -- Write to watchdog register
   procedure Write (WDT : in out Watchdog_State;
                   Offset : Memory_Address;
                   Value : Byte);

   -- Tick the watchdog (decrement counter)
   -- Returns True if reset should occur
   function Tick (WDT : in out Watchdog_State) return Boolean;

   -- Feed the watchdog (reset counter)
   procedure Feed (WDT : in out Watchdog_State);

   -- Get status for debugging
   procedure Print_Status (WDT : Watchdog_State);

   -- Memory-mapped I/O helpers
   function Is_Watchdog_Address (WDT : Watchdog_State;
                                  Address : Memory_Address) return Boolean;

   function Read_Byte (WDT : in out Watchdog_State;
                       Address : Memory_Address) return Byte;

   procedure Write_Byte (WDT : in out Watchdog_State;
                         Address : Memory_Address;
                         Value : Byte);

end RISCV.Watchdog;
