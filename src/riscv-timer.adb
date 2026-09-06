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
package body RISCV.Timer is

   -- Initialize timer state
   procedure Initialize (Timer : out Timer_State; Base : Memory_Address) is
   begin
      Timer.Base := Base;
      Timer.Enabled := True;
      Timer.Prescale := 1;
      Timer.Int_Status := 0;
      Timer.Int_Enable := 0;
      Timer.Tick_Counter := 0;

      -- Initialize all channels
      for I in Timer.Channels'Range loop
         Timer.Channels (I).Enabled := False;
         Timer.Channels (I).PWM_Mode := False;
         Timer.Channels (I).Auto_Reload := False;
         Timer.Channels (I).Int_Enable := False;
         Timer.Channels (I).Output_High := False;
         Timer.Channels (I).Counter := 0;
         Timer.Channels (I).Compare := 0;
         Timer.Channels (I).Output := 0;
      end loop;
   end Initialize;

   -- Check if address belongs to timer controller
   function Is_Timer_Address (Timer : Timer_State; Address : Memory_Address) return Boolean is
   begin
      return Timer.Enabled and then
             Address >= Timer.Base and then
             Address < Timer.Base + 16#50#;  -- Global regs + 4 channels * 16 bytes
   end Is_Timer_Address;

   -- Get channel number from offset
   function Get_Channel (Offset : Memory_Address) return Natural is
   begin
      if Offset >= 16#10# then
         return Natural ((Offset - 16#10#) / 16#10#);
      end if;
      return Num_Channels;  -- Invalid
   end Get_Channel;

   -- Get register offset within channel
   function Get_Channel_Register (Offset : Memory_Address) return Memory_Address is
   begin
      if Offset >= 16#10# then
         return (Offset - 16#10#) mod 16#10#;
      end if;
      return 16#FF#;  -- Invalid
   end Get_Channel_Register;

   -- Read from timer controller register
   function Read_Byte (Timer : Timer_State; Address : Memory_Address) return Byte is
      Offset : constant Memory_Address := Address - Timer.Base;
      Ch_Num : Natural;
      Ch_Reg : Memory_Address;
   begin
      -- Global registers
      case Offset is
         when TIMER_PRESCALE_OFFSET =>
            return Timer.Prescale;

         when TIMER_INT_STATUS_OFFSET =>
            return Timer.Int_Status;

         when TIMER_INT_ENABLE_OFFSET =>
            return Timer.Int_Enable;

         when others =>
            -- Check if it's a channel register
            Ch_Num := Get_Channel (Offset);
            if Ch_Num < Num_Channels then
               Ch_Reg := Get_Channel_Register (Offset);
               declare
                  Ch : Timer_Channel renames Timer.Channels (Ch_Num);
               begin
                  case Ch_Reg is
                     when CH_COUNTER_OFFSET =>
                        return Byte (Ch.Counter and 16#FF#);
                     when CH_COUNTER_OFFSET + 1 =>
                        return Byte (Shift_Right (Ch.Counter, 8) and 16#FF#);
                     when CH_COUNTER_OFFSET + 2 =>
                        return Byte (Shift_Right (Ch.Counter, 16) and 16#FF#);
                     when CH_COUNTER_OFFSET + 3 =>
                        return Byte (Shift_Right (Ch.Counter, 24) and 16#FF#);

                     when CH_COMPARE_OFFSET =>
                        return Byte (Ch.Compare and 16#FF#);
                     when CH_COMPARE_OFFSET + 1 =>
                        return Byte (Shift_Right (Ch.Compare, 8) and 16#FF#);
                     when CH_COMPARE_OFFSET + 2 =>
                        return Byte (Shift_Right (Ch.Compare, 16) and 16#FF#);
                     when CH_COMPARE_OFFSET + 3 =>
                        return Byte (Shift_Right (Ch.Compare, 24) and 16#FF#);

                     when CH_CTRL_OFFSET =>
                        declare
                           Ctrl : Byte := 0;
                        begin
                           if Ch.Enabled then
                              Ctrl := Ctrl or CH_CTRL_ENABLE;
                           end if;
                           if Ch.PWM_Mode then
                              Ctrl := Ctrl or CH_CTRL_PWM_MODE;
                           end if;
                           if Ch.Auto_Reload then
                              Ctrl := Ctrl or CH_CTRL_AUTO_RELOAD;
                           end if;
                           if Ch.Int_Enable then
                              Ctrl := Ctrl or CH_CTRL_INT_ENABLE;
                           end if;
                           if Ch.Output_High then
                              Ctrl := Ctrl or CH_CTRL_OUTPUT_HIGH;
                           end if;
                           return Ctrl;
                        end;

                     when CH_OUTPUT_OFFSET =>
                        return Ch.Output;

                     when others =>
                        return 0;
                  end case;
               end;
            end if;
            return 0;
      end case;
   end Read_Byte;

   -- Write to timer controller register
   procedure Write_Byte (
      Timer   : in out Timer_State;
      Address : Memory_Address;
      Value   : Byte
   ) is
      Offset : constant Memory_Address := Address - Timer.Base;
      Ch_Num : Natural;
      Ch_Reg : Memory_Address;
   begin
      -- Global registers
      case Offset is
         when TIMER_PRESCALE_OFFSET =>
            if Value > 0 then
               Timer.Prescale := Value;
            else
               Timer.Prescale := 1;  -- Minimum prescale
            end if;

         when TIMER_INT_STATUS_OFFSET =>
            -- Clear interrupt flags (write 1 to clear)
            Timer.Int_Status := Timer.Int_Status and not Value;

         when TIMER_INT_ENABLE_OFFSET =>
            Timer.Int_Enable := Value and 16#0F#;  -- Only 4 channels

         when others =>
            -- Check if it's a channel register
            Ch_Num := Get_Channel (Offset);
            if Ch_Num < Num_Channels then
               Ch_Reg := Get_Channel_Register (Offset);
               declare
                  Ch : Timer_Channel renames Timer.Channels (Ch_Num);
               begin
                  case Ch_Reg is
                     when CH_COUNTER_OFFSET =>
                        Ch.Counter := (Ch.Counter and 16#FFFFFF00#) or Word (Value);
                     when CH_COUNTER_OFFSET + 1 =>
                        Ch.Counter := (Ch.Counter and 16#FFFF00FF#) or Shift_Left (Word (Value), 8);
                     when CH_COUNTER_OFFSET + 2 =>
                        Ch.Counter := (Ch.Counter and 16#FF00FFFF#) or Shift_Left (Word (Value), 16);
                     when CH_COUNTER_OFFSET + 3 =>
                        Ch.Counter := (Ch.Counter and 16#00FFFFFF#) or Shift_Left (Word (Value), 24);

                     when CH_COMPARE_OFFSET =>
                        Ch.Compare := (Ch.Compare and 16#FFFFFF00#) or Word (Value);
                     when CH_COMPARE_OFFSET + 1 =>
                        Ch.Compare := (Ch.Compare and 16#FFFF00FF#) or Shift_Left (Word (Value), 8);
                     when CH_COMPARE_OFFSET + 2 =>
                        Ch.Compare := (Ch.Compare and 16#FF00FFFF#) or Shift_Left (Word (Value), 16);
                     when CH_COMPARE_OFFSET + 3 =>
                        Ch.Compare := (Ch.Compare and 16#00FFFFFF#) or Shift_Left (Word (Value), 24);

                     when CH_CTRL_OFFSET =>
                        Ch.Enabled := (Value and CH_CTRL_ENABLE) /= 0;
                        Ch.PWM_Mode := (Value and CH_CTRL_PWM_MODE) /= 0;
                        Ch.Auto_Reload := (Value and CH_CTRL_AUTO_RELOAD) /= 0;
                        Ch.Int_Enable := (Value and CH_CTRL_INT_ENABLE) /= 0;
                        Ch.Output_High := (Value and CH_CTRL_OUTPUT_HIGH) /= 0;

                     when CH_OUTPUT_OFFSET =>
                        Ch.Output := Value;

                     when others =>
                        null;
                  end case;
               end;
            end if;
      end case;
   end Write_Byte;

   -- Update timer state (called periodically)
   procedure Tick (Timer : in out Timer_State) is
   begin
      if not Timer.Enabled then
         return;
      end if;

      -- Increment tick counter
      Timer.Tick_Counter := Timer.Tick_Counter + 1;

      -- Check if we should increment timers (based on prescaler)
      if Timer.Tick_Counter >= Natural (Timer.Prescale) then
         Timer.Tick_Counter := 0;

         -- Update each enabled channel
         for I in Timer.Channels'Range loop
            declare
               Ch : Timer_Channel renames Timer.Channels (I);
               Int_Bit : constant Byte := Shift_Left (Byte (1), I);
            begin
               if Ch.Enabled then
                  -- Increment counter
                  Ch.Counter := Ch.Counter + 1;

                  -- Check for compare match
                  if Ch.Counter >= Ch.Compare and Ch.Compare /= 0 then
                     -- Set interrupt flag if enabled
                     if Ch.Int_Enable then
                        Timer.Int_Status := Timer.Int_Status or Int_Bit;
                     end if;

                     -- Handle auto-reload
                     if Ch.Auto_Reload then
                        Ch.Counter := 0;
                     else
                        Ch.Enabled := False;  -- Stop timer
                     end if;

                     -- Update PWM output state on compare match
                     if Ch.PWM_Mode then
                        -- Toggle output on compare match
                        Ch.Output_High := not Ch.Output_High;
                     end if;
                  end if;

                  -- Note: OUTPUT register is manually set via Write_Byte,
                  -- not auto-calculated. It represents the desired duty cycle (0-255).
               end if;
            end;
         end loop;
      end if;
   end Tick;

   -- Check if any timer interrupt is pending
   function Interrupt_Pending (Timer : Timer_State) return Boolean is
   begin
      return (Timer.Int_Status and Timer.Int_Enable) /= 0;
   end Interrupt_Pending;

end RISCV.Timer;
