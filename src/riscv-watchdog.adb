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
with Ada.Text_IO; use Ada.Text_IO;

package body RISCV.Watchdog is

   -- Register offsets
   WDT_CTRL_OFFSET   : constant := 16#00#;
   WDT_COUNT_OFFSET  : constant := 16#04#;
   WDT_RELOAD_OFFSET : constant := 16#08#;
   WDT_FEED_OFFSET   : constant := 16#0C#;

   -- Control register bits
   CTRL_ENABLE : constant := 16#01#;
   CTRL_RESET  : constant := 16#02#;

   procedure Initialize (WDT : out Watchdog_State;
                        Base : Memory_Address) is
   begin
      WDT.Base_Address := Base;
      WDT.Enabled := False;
      WDT.Counter := 1000;
      WDT.Reload_Value := 1000;
      WDT.Reset_Flag := False;
   end Initialize;

   function Read (WDT : in out Watchdog_State;
                  Offset : Memory_Address) return Byte is
      Reg_Offset : constant Memory_Address := Offset - WDT.Base_Address;
      Value : Byte := 0;
   begin
      case Reg_Offset is
         when WDT_CTRL_OFFSET =>
            -- Control register
            if WDT.Enabled then
               Value := Value or CTRL_ENABLE;
            end if;
            if WDT.Reset_Flag then
               Value := Value or CTRL_RESET;
               -- Clear reset flag on read
               WDT.Reset_Flag := False;
            end if;

         when WDT_COUNT_OFFSET =>
            -- Counter value (32-bit, return first byte)
            Value := Byte (WDT.Counter and 16#FF#);

         when WDT_COUNT_OFFSET + 1 =>
            Value := Byte ((WDT.Counter / 256) and 16#FF#);

         when WDT_COUNT_OFFSET + 2 =>
            Value := Byte ((WDT.Counter / 65536) and 16#FF#);

         when WDT_COUNT_OFFSET + 3 =>
            Value := Byte ((WDT.Counter / 16777216) and 16#FF#);

         when WDT_RELOAD_OFFSET =>
            -- Reload value (32-bit, return first byte)
            Value := Byte (WDT.Reload_Value and 16#FF#);

         when WDT_RELOAD_OFFSET + 1 =>
            Value := Byte ((WDT.Reload_Value / 256) and 16#FF#);

         when WDT_RELOAD_OFFSET + 2 =>
            Value := Byte ((WDT.Reload_Value / 65536) and 16#FF#);

         when WDT_RELOAD_OFFSET + 3 =>
            Value := Byte ((WDT.Reload_Value / 16777216) and 16#FF#);

         when others =>
            Value := 0;
      end case;

      return Value;
   end Read;

   procedure Write (WDT : in out Watchdog_State;
                   Offset : Memory_Address;
                   Value : Byte) is
      Reg_Offset : constant Memory_Address := Offset - WDT.Base_Address;
   begin
      case Reg_Offset is
         when WDT_CTRL_OFFSET =>
            -- Control register
            WDT.Enabled := (Value and CTRL_ENABLE) /= 0;

         when WDT_RELOAD_OFFSET =>
            -- Reload value (32-bit write, byte 0)
            WDT.Reload_Value := (WDT.Reload_Value and 16#FFFFFF00#) or Word (Value);

         when WDT_RELOAD_OFFSET + 1 =>
            WDT.Reload_Value := (WDT.Reload_Value and 16#FFFF00FF#) or (Word (Value) * 256);

         when WDT_RELOAD_OFFSET + 2 =>
            WDT.Reload_Value := (WDT.Reload_Value and 16#FF00FFFF#) or (Word (Value) * 65536);

         when WDT_RELOAD_OFFSET + 3 =>
            WDT.Reload_Value := (WDT.Reload_Value and 16#00FFFFFF#) or (Word (Value) * 16777216);

         when WDT_FEED_OFFSET | WDT_FEED_OFFSET + 1 | WDT_FEED_OFFSET + 2 | WDT_FEED_OFFSET + 3 =>
            -- Feed register - any write resets counter
            Feed (WDT);

         when others =>
            null;  -- Ignore writes to other addresses
      end case;
   end Write;

   function Tick (WDT : in out Watchdog_State) return Boolean is
   begin
      if not WDT.Enabled then
         return False;  -- Watchdog disabled, no reset
      end if;

      if WDT.Counter > 0 then
         WDT.Counter := WDT.Counter - 1;

         if WDT.Counter = 0 then
            -- Timeout! Reset triggered
            WDT.Reset_Flag := True;
            WDT.Enabled := False;  -- Disable watchdog after reset (like real hardware)
            WDT.Counter := WDT.Reload_Value;  -- Reload counter
            return True;
         end if;
      end if;

      return False;
   end Tick;

   procedure Feed (WDT : in out Watchdog_State) is
   begin
      WDT.Counter := WDT.Reload_Value;
   end Feed;

   procedure Print_Status (WDT : Watchdog_State) is
   begin
      Put_Line ("Watchdog Status:");
      Put_Line ("  Enabled:      " & Boolean'Image (WDT.Enabled));
      Put_Line ("  Counter:      " & Word'Image (WDT.Counter));
      Put_Line ("  Reload Value: " & Word'Image (WDT.Reload_Value));
      Put_Line ("  Reset Flag:   " & Boolean'Image (WDT.Reset_Flag));
   end Print_Status;

   function Is_Watchdog_Address (WDT : Watchdog_State;
                                  Address : Memory_Address) return Boolean is
      -- Watchdog has 4 registers at offsets 0x00, 0x04, 0x08, 0x0C
      -- Each is 4 bytes, so total range is 0x00-0x0F (16 bytes)
   begin
      return WDT.Enabled and then
             Address >= WDT.Base_Address and then
             Address < WDT.Base_Address + 16;
   end Is_Watchdog_Address;

   function Read_Byte (WDT : in out Watchdog_State;
                       Address : Memory_Address) return Byte is
   begin
      return Read (WDT, Address);
   end Read_Byte;

   procedure Write_Byte (WDT : in out Watchdog_State;
                         Address : Memory_Address;
                         Value : Byte) is
   begin
      Write (WDT, Address, Value);
   end Write_Byte;

end RISCV.Watchdog;
