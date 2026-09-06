-- ***************************************************************************
--                 RISC-V Emulator - DMA
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

package body RISCV.DMA is

   -- Control register bits
   CTRL_ENABLE     : constant := 16#01#;
   CTRL_START      : constant := 16#02#;
   CTRL_INT_EN     : constant := 16#04#;
   CTRL_SRC_INC    : constant := 16#08#;
   CTRL_DST_INC    : constant := 16#10#;
   CTRL_XFER_SIZE  : constant := 16#60#;  -- bits 5-6 (reserved for future use)
   pragma Unreferenced (CTRL_XFER_SIZE);

   -- Status register bits
   STATUS_BUSY     : constant := 16#01#;
   STATUS_DONE     : constant := 16#02#;
   STATUS_ERROR    : constant := 16#04#;

   -- Register offsets per channel
   REG_SRC         : constant := 16#00#;
   REG_DST         : constant := 16#04#;
   REG_COUNT       : constant := 16#08#;
   REG_CTRL        : constant := 16#0C#;
   REG_STATUS      : constant := 16#10#;

   CHANNEL_SIZE    : constant := 16#20#;  -- 32 bytes per channel

   procedure Initialize (DMA : out DMA_State;
                        Base : Memory_Address) is
   begin
      DMA.Base_Address := Base;
      DMA.Enabled := True;
      for I in DMA.Channels'Range loop
         DMA.Channels (I).Source_Addr := 0;
         DMA.Channels (I).Dest_Addr := 0;
         DMA.Channels (I).Count := 0;
         DMA.Channels (I).Initial_Count := 0;
         DMA.Channels (I).Control := 0;
         DMA.Channels (I).Status := 0;
         DMA.Channels (I).Current_Src := 0;
         DMA.Channels (I).Current_Dst := 0;
      end loop;
   end Initialize;

   function Read (DMA : DMA_State;
                  Offset : Memory_Address) return Byte is
      Channel_Num : constant Natural := Natural (Offset / CHANNEL_SIZE);
      Reg_Offset  : constant Memory_Address := Offset mod CHANNEL_SIZE;
      Byte_Offset : constant Natural := Natural (Reg_Offset mod 4);
   begin
      if Channel_Num >= Num_Channels then
         return 0;
      end if;

      declare
         CH : DMA_Channel renames DMA.Channels (Channel_Num);
         Reg_Base : constant Memory_Address := Reg_Offset - Memory_Address (Byte_Offset);
      begin
         case Reg_Base is
            when REG_SRC =>
               return Byte (Shift_Right (CH.Source_Addr, Byte_Offset * 8) and 16#FF#);

            when REG_DST =>
               return Byte (Shift_Right (CH.Dest_Addr, Byte_Offset * 8) and 16#FF#);

            when REG_COUNT =>
               return Byte (Shift_Right (CH.Count, Byte_Offset * 8) and 16#FF#);

            when REG_CTRL =>
               if Byte_Offset = 0 then
                  return CH.Control;
               end if;

            when REG_STATUS =>
               if Byte_Offset = 0 then
                  return CH.Status;
               end if;

            when others =>
               null;
         end case;
      end;

      return 0;
   end Read;

   procedure Write (DMA : in out DMA_State;
                   Offset : Memory_Address;
                   Value : Byte) is
      Channel_Num : constant Natural := Natural (Offset / CHANNEL_SIZE);
      Reg_Offset  : constant Memory_Address := Offset mod CHANNEL_SIZE;
      Byte_Offset : constant Natural := Natural (Reg_Offset mod 4);
   begin
      if Channel_Num >= Num_Channels then
         return;
      end if;

      declare
         CH : DMA_Channel renames DMA.Channels (Channel_Num);
         Reg_Base : constant Memory_Address := Reg_Offset - Memory_Address (Byte_Offset);
         Mask : constant Word := Shift_Left (16#FF#, Byte_Offset * 8);
         Clear_Mask : constant Word := not Mask;
      begin
         case Reg_Base is
            when REG_SRC =>
               CH.Source_Addr := (CH.Source_Addr and Clear_Mask) or
                                 Shift_Left (Word (Value), Byte_Offset * 8);

            when REG_DST =>
               CH.Dest_Addr := (CH.Dest_Addr and Clear_Mask) or
                               Shift_Left (Word (Value), Byte_Offset * 8);

            when REG_COUNT =>
               CH.Count := (CH.Count and Clear_Mask) or
                          Shift_Left (Word (Value), Byte_Offset * 8);

            when REG_CTRL =>
               if Byte_Offset = 0 then
                  -- Check if START bit is being set
                  if (Value and CTRL_START) /= 0 and (CH.Control and CTRL_START) = 0 then
                     -- Starting a new transfer
                     CH.Current_Src := CH.Source_Addr;
                     CH.Current_Dst := CH.Dest_Addr;
                     CH.Initial_Count := CH.Count;
                     CH.Status := (CH.Status or STATUS_BUSY) and not STATUS_DONE;
                  end if;
                  CH.Control := Value;
               end if;

            when REG_STATUS =>
               if Byte_Offset = 0 then
                  -- Writing 1 to DONE or ERROR bits clears them
                  if (Value and STATUS_DONE) /= 0 then
                     CH.Status := CH.Status and not STATUS_DONE;
                  end if;
                  if (Value and STATUS_ERROR) /= 0 then
                     CH.Status := CH.Status and not STATUS_ERROR;
                  end if;
               end if;

            when others =>
               null;
         end case;
      end;
   end Write;

   function Process (DMA : in out DMA_State;
                    Memory : access procedure (Addr : Memory_Address;
                                               Data : out Byte;
                                               Success : out Boolean);
                    Memory_Write : access procedure (Addr : Memory_Address;
                                                    Data : Byte;
                                                    Success : out Boolean))
                    return Boolean is
      Any_Completed : Boolean := False;
   begin
      if not DMA.Enabled then
         return False;
      end if;

      for I in DMA.Channels'Range loop
         declare
            CH : DMA_Channel renames DMA.Channels (I);
            Transfer_Data : Byte;
            Success : Boolean;
         begin
            -- Check if channel is active
            if (CH.Control and CTRL_ENABLE) /= 0 and
               (CH.Status and STATUS_BUSY) /= 0 and
               CH.Count > 0
            then
               -- Perform one transfer unit (byte, halfword, or word)
               -- For now, always transfer 1 byte per Process call
               -- Real hardware would transfer faster

               -- Read from source
               Memory (Memory_Address (CH.Current_Src), Transfer_Data, Success);

               if Success then
                  -- Write to destination
                  Memory_Write (Memory_Address (CH.Current_Dst), Transfer_Data, Success);

                  if Success then
                     -- Update addresses
                     if (CH.Control and CTRL_SRC_INC) /= 0 then
                        CH.Current_Src := CH.Current_Src + 1;
                     end if;
                     if (CH.Control and CTRL_DST_INC) /= 0 then
                        CH.Current_Dst := CH.Current_Dst + 1;
                     end if;

                     -- Update count
                     CH.Count := CH.Count - 1;

                     -- Check if transfer complete
                     if CH.Count = 0 then
                        CH.Status := (CH.Status and not STATUS_BUSY) or STATUS_DONE;
                        CH.Control := CH.Control and not CTRL_START;
                        Any_Completed := True;
                     end if;
                  else
                     -- Write error
                     CH.Status := (CH.Status and not STATUS_BUSY) or STATUS_ERROR;
                     CH.Control := CH.Control and not CTRL_START;
                     Any_Completed := True;
                  end if;
               else
                  -- Read error
                  CH.Status := (CH.Status and not STATUS_BUSY) or STATUS_ERROR;
                  CH.Control := CH.Control and not CTRL_START;
                  Any_Completed := True;
               end if;
            end if;
         end;
      end loop;

      return Any_Completed;
   end Process;

   function Interrupt_Pending (DMA : DMA_State) return Boolean is
   begin
      for I in DMA.Channels'Range loop
         if (DMA.Channels (I).Control and CTRL_INT_EN) /= 0 and
            (DMA.Channels (I).Status and STATUS_DONE) /= 0
         then
            return True;
         end if;
      end loop;
      return False;
   end Interrupt_Pending;

   procedure Print_Status (DMA : DMA_State) is
   begin
      Put_Line ("DMA Controller Status:");
      Put_Line ("  Enabled: " & Boolean'Image (DMA.Enabled));
      for I in DMA.Channels'Range loop
         Put_Line ("  Channel" & Natural'Image (I) & ":");
         Put_Line ("    Source:  0x" & Word'Image (DMA.Channels (I).Source_Addr));
         Put_Line ("    Dest:    0x" & Word'Image (DMA.Channels (I).Dest_Addr));
         Put_Line ("    Count:   " & Word'Image (DMA.Channels (I).Count));
         Put_Line ("    Control: 0x" & Byte'Image (DMA.Channels (I).Control));
         Put_Line ("    Status:  0x" & Byte'Image (DMA.Channels (I).Status));
      end loop;
   end Print_Status;

   function Is_DMA_Address (DMA : DMA_State;
                            Address : Memory_Address) return Boolean is
      -- DMA has 4 channels * 0x20 bytes = 0x80 (128 bytes) total
   begin
      return DMA.Enabled and then
             Address >= DMA.Base_Address and then
             Address < DMA.Base_Address + (Num_Channels * CHANNEL_SIZE);
   end Is_DMA_Address;

   function Read_Byte (DMA : DMA_State;
                       Address : Memory_Address) return Byte is
      Offset : constant Memory_Address := Address - DMA.Base_Address;
   begin
      return Read (DMA, Offset);
   end Read_Byte;

   procedure Write_Byte (DMA : in out DMA_State;
                         Address : Memory_Address;
                         Value : Byte) is
      Offset : constant Memory_Address := Address - DMA.Base_Address;
   begin
      Write (DMA, Offset, Value);
   end Write_Byte;

end RISCV.DMA;
