-- ***************************************************************************
--       RISC-V Emulator - VirtIO Block Device (MMIO transport v2)
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

package body RISCV.VirtIO_Block is

   procedure Free_Disk is new Ada.Unchecked_Deallocation (Disk_Data, Disk_Access);

   -- =========================================================================
   --  Initialize / Finalize
   -- =========================================================================

   procedure Initialize (VB   : out VirtIO_Block_State;
                         Base : Memory_Address := Default_Base_Address) is
   begin
      VB.Base_Address    := Base;
      VB.Enabled         := True;
      VB.DevFeatureSel   := 0;
      VB.DrvFeatureSel   := 0;
      VB.DrvFeatures0    := 0;
      VB.DrvFeatures1    := 0;
      VB.QueueNum        := 0;
      VB.QueueReady      := 0;
      VB.InterruptStatus := 0;
      VB.DevStatus       := 0;
      VB.QueueDescLo     := 0;
      VB.QueueDescHi     := 0;
      VB.QueueDriverLo   := 0;
      VB.QueueDriverHi   := 0;
      VB.QueueDeviceLo   := 0;
      VB.QueueDeviceHi   := 0;
      VB.Last_Avail_Idx  := 0;
      VB.Used_Idx        := 0;
      VB.Notify_Pending  := False;
      VB.Disk            := new Disk_Data'(others => 0);
   end Initialize;

   procedure Finalize (VB : in out VirtIO_Block_State) is
   begin
      if VB.Disk /= null then
         Free_Disk (VB.Disk);
      end if;
   end Finalize;

   -- =========================================================================
   --  Address Decoding
   -- =========================================================================

   function Is_VirtIO_Block_Address (VB   : VirtIO_Block_State;
                                     Addr : Memory_Address) return Boolean is
   begin
      return VB.Enabled and then
             Addr >= VB.Base_Address and then
             Addr < VB.Base_Address + VirtIO_Block_Size;
   end Is_VirtIO_Block_Address;

   -- =========================================================================
   --  Register Read
   -- =========================================================================

   function Read_Word (VB   : VirtIO_Block_State;
                       Addr : Memory_Address) return Word is
      Offset : constant Word := Word (Addr - VB.Base_Address);
   begin
      case Offset is
         when REG_MAGIC_VALUE      => return MAGIC_VALUE;
         when REG_VERSION          => return MMIO_VERSION;
         when REG_DEVICE_ID        => return DEVICE_ID;
         when REG_VENDOR_ID        => return VENDOR_ID;
         when REG_DEVICE_FEATURES   => return 0;
         when REG_DEVICE_FEAT_SEL   => return VB.DevFeatureSel;
         when REG_DRIVER_FEATURES   =>
            if VB.DrvFeatureSel = 0 then return VB.DrvFeatures0;
            else return VB.DrvFeatures1; end if;
         when REG_DRIVER_FEAT_SEL   => return VB.DrvFeatureSel;
         when REG_QUEUE_SEL         => return 0;
         when REG_QUEUE_NUM_MAX     => return Queue_Size;
         when REG_QUEUE_NUM         => return VB.QueueNum;
         when REG_QUEUE_READY       => return VB.QueueReady;
         when REG_INTERRUPT_STATUS  => return VB.InterruptStatus;
         when REG_STATUS            => return VB.DevStatus;
         when REG_QUEUE_DESC_LOW    => return VB.QueueDescLo;
         when REG_QUEUE_DESC_HIGH   => return VB.QueueDescHi;
         when REG_QUEUE_DRIVER_LOW  => return VB.QueueDriverLo;
         when REG_QUEUE_DRIVER_HIGH => return VB.QueueDriverHi;
         when REG_QUEUE_DEVICE_LOW  => return VB.QueueDeviceLo;
         when REG_QUEUE_DEVICE_HIGH => return VB.QueueDeviceHi;
         when REG_CONFIG_GEN        => return 0;
         when REG_CONFIG_BASE       => return Max_Sectors;  -- capacity lo
         when REG_CONFIG_BASE + 4   => return 0;            -- capacity hi
         when REG_CONFIG_BASE + 8   => return 0;            -- size_max
         when REG_CONFIG_BASE + 12  => return 0;            -- seg_max
         when others                => return 0;
      end case;
   end Read_Word;

   function Read_Byte (VB   : VirtIO_Block_State;
                       Addr : Memory_Address) return Byte is
      W      : constant Word := Read_Word (VB, Addr and not 3);
      Offset : constant Word := Word (Addr) and 3;
   begin
      return Byte (Shift_Right (W, Natural (Offset * 8)) and 16#FF#);
   end Read_Byte;

   -- =========================================================================
   --  Register Write
   -- =========================================================================

   procedure Write_Word (VB   : in out VirtIO_Block_State;
                         Addr : Memory_Address;
                         Data : Word) is
      Offset : constant Word := Word (Addr - VB.Base_Address);
   begin
      case Offset is
         when REG_DEVICE_FEAT_SEL   => VB.DevFeatureSel := Data;
         when REG_DRIVER_FEATURES   =>
            if VB.DrvFeatureSel = 0 then
               VB.DrvFeatures0 := Data;
            else
               VB.DrvFeatures1 := Data;
            end if;
         when REG_DRIVER_FEAT_SEL   => VB.DrvFeatureSel := Data;
         when REG_QUEUE_SEL         => null;  -- only queue 0
         when REG_QUEUE_NUM         =>
            if Data <= Queue_Size then
               VB.QueueNum := Data;
            else
               VB.QueueNum := Queue_Size;
            end if;
         when REG_QUEUE_READY       => VB.QueueReady := Data;
         when REG_QUEUE_NOTIFY      => VB.Notify_Pending := True;
         when REG_INTERRUPT_ACK     =>
            VB.InterruptStatus := VB.InterruptStatus and not Data;
         when REG_STATUS            =>
            --  Write 0 = device reset
            if Data = 0 then
               VB.DevStatus       := 0;
               VB.QueueReady      := 0;
               VB.QueueNum        := 0;
               VB.InterruptStatus := 0;
               VB.Last_Avail_Idx  := 0;
               VB.Used_Idx        := 0;
               VB.Notify_Pending  := False;
            else
               VB.DevStatus := Data;
            end if;
         when REG_QUEUE_DESC_LOW    => VB.QueueDescLo    := Data;
         when REG_QUEUE_DESC_HIGH   => VB.QueueDescHi    := Data;
         when REG_QUEUE_DRIVER_LOW  => VB.QueueDriverLo  := Data;
         when REG_QUEUE_DRIVER_HIGH => VB.QueueDriverHi  := Data;
         when REG_QUEUE_DEVICE_LOW  => VB.QueueDeviceLo  := Data;
         when REG_QUEUE_DEVICE_HIGH => VB.QueueDeviceHi  := Data;
         when others                => null;
      end case;
   end Write_Word;

   procedure Write_Byte (VB   : in out VirtIO_Block_State;
                         Addr : Memory_Address;
                         Data : Byte) is
      Aligned : constant Memory_Address := Addr and not 3;
      Shift   : constant Natural := Natural ((Word (Addr) and 3) * 8);
      Old_W   : constant Word    := Read_Word (VB, Aligned);
      Mask    : constant Word    := not Shift_Left (16#FF#, Shift);
      New_W   : constant Word    := (Old_W and Mask) or
                                    Shift_Left (Word (Data), Shift);
   begin
      Write_Word (VB, Aligned, New_W);
   end Write_Byte;

end RISCV.VirtIO_Block;
