-- ***************************************************************************
--           RISC-V Emulator - I2C Controller Peripheral
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
with Ada.Unchecked_Deallocation;

package body RISCV.I2C is

   procedure Free_Device_Memory is new Ada.Unchecked_Deallocation (
      Object => Device_Memory,
      Name   => Device_Memory_Access
   );

   procedure Free_I2C is new Ada.Unchecked_Deallocation (
      Object => I2C_State,
      Name   => I2C_Access
   );

   -- Initialize device-specific registers
   procedure Initialize_Device (Device : in out I2C_Device_State) is
   begin
      case Device.Device_Type is
         when None =>
            null;

         when Temperature_Sensor =>
            -- Simulate TMP102-like temperature sensor
            -- Registers: 0x00=Temperature, 0x01=Config, 0x02=T_LOW, 0x03=T_HIGH
            Device.Data_Size := 16;
            Device.Data := new Device_Memory (0 .. Device.Data_Size - 1);
            Device.Data.all := (others => 0);
            -- Initial temperature: 25 degrees C = 0x0190 (12-bit left-justified)
            Device.Data (0) := 16#01#;  -- Temperature MSB
            Device.Data (1) := 16#90#;  -- Temperature LSB
            Device.Data (2) := 16#60#;  -- Config: 12-bit resolution

         when Accelerometer =>
            -- Simulate ADXL345-like accelerometer
            -- Registers: 0x00=DEVID, 0x32-0x37=DATAX0..DATAZ1, 0x2D=POWER_CTL
            Device.Data_Size := 64;
            Device.Data := new Device_Memory (0 .. Device.Data_Size - 1);
            Device.Data.all := (others => 0);
            Device.Data (16#00#) := 16#E5#;  -- Device ID
            -- Initial acceleration values (X=0, Y=0, Z=1g ~ 256)
            Device.Data (16#32#) := 16#00#;  -- DATAX0
            Device.Data (16#33#) := 16#00#;  -- DATAX1
            Device.Data (16#34#) := 16#00#;  -- DATAY0
            Device.Data (16#35#) := 16#00#;  -- DATAY1
            Device.Data (16#36#) := 16#00#;  -- DATAZ0 (1g LSB)
            Device.Data (16#37#) := 16#01#;  -- DATAZ1 (1g MSB)

         when EEPROM_256 =>
            -- Simulate 24C02-like 256-byte EEPROM
            Device.Data_Size := 256;
            Device.Data := new Device_Memory (0 .. Device.Data_Size - 1);
            Device.Data.all := (others => 16#FF#);  -- Erased EEPROM
            Device.Reg_Pointer := 16#FF#;  -- Invalid state (waiting for address)
      end case;
   end Initialize_Device;

   -- Initialize I2C state
   procedure Initialize (I2C : out I2C_State; Base : Memory_Address) is
   begin
      I2C.Base := Base;
      I2C.Enabled := True;
      I2C.CTRL := 0;
      I2C.STATUS := STATUS_READY;
      I2C.DATA := 0;
      I2C.PRESCALE := 16#64#;
      I2C.SLAVE_ADDR := 0;
      I2C.Num_Devices := 0;
      I2C.Current_Device := 0;
      I2C.Transfer_Active := False;

      -- Initialize device array
      for I in I2C.Devices'Range loop
         I2C.Devices (I).Device_Type := None;
         I2C.Devices (I).Address := 0;
         I2C.Devices (I).Reg_Pointer := 0;
         I2C.Devices (I).Data := null;
         I2C.Devices (I).Data_Size := 0;
      end loop;
   end Initialize;

   -- Check if address belongs to I2C controller
   function Is_I2C_Address (I2C : I2C_State; Address : Memory_Address) return Boolean is
   begin
      return I2C.Enabled and then
             Address >= I2C.Base and then
             Address < I2C.Base + 16#14#;  -- 5 registers * 4 bytes
   end Is_I2C_Address;

   -- Create I2C controller
   function Create (Base : Memory_Address) return I2C_Access is
      I2C : I2C_Access;
   begin
      I2C := new I2C_State;
      Initialize (I2C.all, Base);
      return I2C;
   end Create;

   -- Finalize I2C controller
   procedure Finalize (I2C : in out I2C_State) is
   begin
      -- Free all device memory
      for I in I2C.Devices'Range loop
         if I2C.Devices (I).Data /= null then
            Free_Device_Memory (I2C.Devices (I).Data);
         end if;
      end loop;
      I2C.Num_Devices := 0;
   end Finalize;

   -- Free I2C controller
   procedure Free (I2C : in out I2C_Access) is
   begin
      if I2C /= null then
         Finalize (I2C.all);
         Free_I2C (I2C);
      end if;
   end Free;

   -- Add a virtual device to the I2C bus
   procedure Add_Device (
      I2C         : in out I2C_State;
      Device_Type : I2C_Device_Type;
      Address     : Byte
   ) is
   begin
      if I2C.Num_Devices < Max_I2C_Devices then
         I2C.Num_Devices := I2C.Num_Devices + 1;
         I2C.Devices (I2C.Num_Devices).Device_Type := Device_Type;
         I2C.Devices (I2C.Num_Devices).Address := Address;
         Initialize_Device (I2C.Devices (I2C.Num_Devices));
      end if;
   end Add_Device;

   -- Find device by address
   function Find_Device (I2C : I2C_State; Address : Byte) return Natural is
   begin
      for I in 1 .. I2C.Num_Devices loop
         if I2C.Devices (I).Address = Address then
            return I;
         end if;
      end loop;
      return 0;  -- Not found
   end Find_Device;

   -- Read from I2C controller register
   function Read_Byte (I2C : in out I2C_State; Address : Memory_Address) return Byte is
      Offset : constant Memory_Address := Address - I2C.Base;
   begin
      case Offset is
         when I2C_CTRL_OFFSET =>
            return I2C.CTRL;

         when I2C_STATUS_OFFSET =>
            return I2C.STATUS;

         when I2C_DATA_OFFSET =>
            return I2C.DATA;

         when I2C_PRESCALE_OFFSET =>
            return I2C.PRESCALE;

         when I2C_SLAVE_ADDR_OFFSET =>
            return I2C.SLAVE_ADDR;

         when others =>
            return 0;
      end case;
   end Read_Byte;

   -- Write to I2C controller register
   procedure Write_Byte (
      I2C     : in out I2C_State;
      Address : Memory_Address;
      Value   : Byte
   ) is
      Offset : constant Memory_Address := Address - I2C.Base;
   begin
      case Offset is
         when I2C_CTRL_OFFSET =>
            I2C.CTRL := Value;
            -- Process operation when control register is written
            if (Value and CTRL_ENABLE) /= 0 then
               I2C.Enabled := True;
               Process_Operation (I2C);
            else
               I2C.Enabled := False;
            end if;

         when I2C_STATUS_OFFSET =>
            -- Status is mostly read-only, but allow clearing error flags
            I2C.STATUS := I2C.STATUS and not (STATUS_ARB_LOST);

         when I2C_DATA_OFFSET =>
            I2C.DATA := Value;

         when I2C_PRESCALE_OFFSET =>
            I2C.PRESCALE := Value;

         when I2C_SLAVE_ADDR_OFFSET =>
            I2C.SLAVE_ADDR := Value and 16#7F#;  -- 7-bit address

         when others =>
            null;
      end case;
   end Write_Byte;

   -- Process I2C operations (called when CTRL is written)
   procedure Process_Operation (I2C : in out I2C_State) is
      Device_Index : Natural;
      Success : Boolean := True;
   begin
      if not I2C.Enabled then
         return;
      end if;

      -- Handle START condition
      if (I2C.CTRL and CTRL_START) /= 0 then
         I2C.Transfer_Active := True;
         I2C.STATUS := I2C.STATUS or STATUS_BUSY;
         I2C.STATUS := I2C.STATUS and not STATUS_READY;  -- Clear READY during transfer
         I2C.STATUS := I2C.STATUS and not STATUS_NACK_RECV;
         I2C.STATUS := I2C.STATUS and not STATUS_ACK_RECV;

         -- Find device with matching address
         Device_Index := Find_Device (I2C, I2C.SLAVE_ADDR);
         if Device_Index /= 0 then
            I2C.Current_Device := Device_Index;
            I2C.STATUS := I2C.STATUS or STATUS_ACK_RECV;
         else
            I2C.Current_Device := 0;
            I2C.STATUS := I2C.STATUS or STATUS_NACK_RECV;
            Success := False;
         end if;

         -- Clear START bit (auto-clear after execution)
         I2C.CTRL := I2C.CTRL and not CTRL_START;
         -- Set READY for next operation
         I2C.STATUS := I2C.STATUS or STATUS_READY;
      end if;

      -- Handle STOP condition
      if (I2C.CTRL and CTRL_STOP) /= 0 then
         I2C.Transfer_Active := False;

         -- Reset EEPROM pointer on STOP
         if I2C.Current_Device /= 0 and then
            I2C.Devices (I2C.Current_Device).Device_Type = EEPROM_256
         then
            I2C.Devices (I2C.Current_Device).Reg_Pointer := 16#FF#;
         end if;

         I2C.Current_Device := 0;
         I2C.STATUS := (I2C.STATUS and not STATUS_BUSY) or STATUS_READY;
         -- Clear STOP bit (auto-clear after execution)
         I2C.CTRL := I2C.CTRL and not CTRL_STOP;
         return;
      end if;

      -- Handle WRITE operation
      if (I2C.CTRL and CTRL_WRITE) /= 0 and I2C.Transfer_Active then
         if I2C.Current_Device /= 0 then
            declare
               Device : I2C_Device_State renames I2C.Devices (I2C.Current_Device);
            begin
               case Device.Device_Type is
                  when EEPROM_256 =>
                     -- First write sets address, subsequent writes are data
                     if Device.Reg_Pointer = 16#FF# then
                        Device.Reg_Pointer := I2C.DATA;
                     else
                        if Device.Data /= null and then
                           Natural (Device.Reg_Pointer) < Device.Data_Size
                        then
                           Device.Data (Natural (Device.Reg_Pointer)) := I2C.DATA;
                           Device.Reg_Pointer := Device.Reg_Pointer + 1;
                        end if;
                     end if;

                  when Temperature_Sensor | Accelerometer =>
                     -- First write is register address
                     Device.Reg_Pointer := I2C.DATA;

                  when None =>
                     Success := False;
               end case;

               if Success then
                  I2C.STATUS := I2C.STATUS or STATUS_ACK_RECV;
                  I2C.STATUS := I2C.STATUS and not STATUS_NACK_RECV;
               else
                  I2C.STATUS := I2C.STATUS or STATUS_NACK_RECV;
                  I2C.STATUS := I2C.STATUS and not STATUS_ACK_RECV;
               end if;
            end;
         else
            I2C.STATUS := I2C.STATUS or STATUS_NACK_RECV;
            I2C.STATUS := I2C.STATUS and not STATUS_ACK_RECV;
         end if;

         -- Clear WRITE bit (auto-clear after execution)
         I2C.CTRL := I2C.CTRL and not CTRL_WRITE;
         -- Set READY for next operation
         I2C.STATUS := I2C.STATUS or STATUS_READY;
      end if;

      -- Handle READ operation
      if (I2C.CTRL and CTRL_READ) /= 0 and I2C.Transfer_Active then
         if I2C.Current_Device /= 0 then
            declare
               Device : I2C_Device_State renames I2C.Devices (I2C.Current_Device);
            begin
               if Device.Data /= null and then
                  Natural (Device.Reg_Pointer) < Device.Data_Size
               then
                  I2C.DATA := Device.Data (Natural (Device.Reg_Pointer));
                  Device.Reg_Pointer := Device.Reg_Pointer + 1;
                  I2C.STATUS := I2C.STATUS or STATUS_ACK_RECV;
                  I2C.STATUS := I2C.STATUS and not STATUS_NACK_RECV;
               else
                  I2C.DATA := 16#FF#;
                  I2C.STATUS := I2C.STATUS or STATUS_NACK_RECV;
                  I2C.STATUS := I2C.STATUS and not STATUS_ACK_RECV;
               end if;
            end;
         else
            I2C.DATA := 16#FF#;
            I2C.STATUS := I2C.STATUS or STATUS_NACK_RECV;
            I2C.STATUS := I2C.STATUS and not STATUS_ACK_RECV;
         end if;

         -- Clear READ bit (auto-clear after execution)
         I2C.CTRL := I2C.CTRL and not CTRL_READ;
         -- Set READY for next operation
         I2C.STATUS := I2C.STATUS or STATUS_READY;
      end if;
   end Process_Operation;

end RISCV.I2C;
