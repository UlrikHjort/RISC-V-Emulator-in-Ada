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
--
--  VirtIO Block Device - MMIO transport version 2 (modern)
--
--  Base address: 0x10001000 (first VirtIO device slot in QEMU virt)
--  Register region size: 4 KB
--
--  MMIO register map (offsets from base):
--    0x000  MagicValue       (R)    0x74726976 "virt"
--    0x004  Version          (R)    2
--    0x008  DeviceID         (R)    2 (block device)
--    0x00C  VendorID         (R)    0x554B5248
--    0x010  DeviceFeatures   (R)    feature bits (page selected by 0x014)
--    0x014  DeviceFeaturesSel(W)    0 = bits 0-31
--    0x020  DriverFeatures   (W)    accepted features
--    0x024  DriverFeaturesSel(W)    0 = bits 0-31
--    0x030  QueueSel         (W)    always 0 (one queue)
--    0x034  QueueNumMax      (R)    16
--    0x038  QueueNum         (W)    number of descriptors
--    0x044  QueueReady       (R/W)  1 = queue active
--    0x050  QueueNotify      (W)    write any value to kick queue
--    0x060  InterruptStatus  (R)    bit 0 = used-buffer notification pending
--    0x064  InterruptACK     (W)    write to clear InterruptStatus bits
--    0x070  Status           (R/W)  device status byte
--    0x080  QueueDescLow     (W)    low 32 bits of descriptor table PA
--    0x084  QueueDescHigh    (W)    high 32 bits (must be 0 for 32-bit guest)
--    0x090  QueueDriverLow   (W)    low 32 bits of available ring PA
--    0x094  QueueDriverHigh  (W)
--    0x0A0  QueueDeviceLow   (W)    low 32 bits of used ring PA
--    0x0A4  QueueDeviceHigh  (W)
--    0x0FC  ConfigGeneration (R)    0
--    0x100  capacity (lo)    (R)    number of sectors (1024)
--    0x104  capacity (hi)    (R)    0
--
--  Disk: 1024 sectors x 512 bytes = 512 KB in-memory storage.
--
--  Queue processing is triggered synchronously when QueueNotify is written
--  (Notify_Pending flag is set, memory.adb calls Process_Queue).

package RISCV.VirtIO_Block is

   --  MMIO parameters
   Default_Base_Address : constant Memory_Address := 16#1000_1000#;
   VirtIO_Block_Size    : constant := 16#1000#;  -- 4 KB

   --  Register offsets
   REG_MAGIC_VALUE       : constant := 16#000#;
   REG_VERSION           : constant := 16#004#;
   REG_DEVICE_ID         : constant := 16#008#;
   REG_VENDOR_ID         : constant := 16#00C#;
   REG_DEVICE_FEATURES   : constant := 16#010#;
   REG_DEVICE_FEAT_SEL   : constant := 16#014#;
   REG_DRIVER_FEATURES   : constant := 16#020#;
   REG_DRIVER_FEAT_SEL   : constant := 16#024#;
   REG_QUEUE_SEL         : constant := 16#030#;
   REG_QUEUE_NUM_MAX     : constant := 16#034#;
   REG_QUEUE_NUM         : constant := 16#038#;
   REG_QUEUE_READY       : constant := 16#044#;
   REG_QUEUE_NOTIFY      : constant := 16#050#;
   REG_INTERRUPT_STATUS  : constant := 16#060#;
   REG_INTERRUPT_ACK     : constant := 16#064#;
   REG_STATUS            : constant := 16#070#;
   REG_QUEUE_DESC_LOW    : constant := 16#080#;
   REG_QUEUE_DESC_HIGH   : constant := 16#084#;
   REG_QUEUE_DRIVER_LOW  : constant := 16#090#;
   REG_QUEUE_DRIVER_HIGH : constant := 16#094#;
   REG_QUEUE_DEVICE_LOW  : constant := 16#0A0#;
   REG_QUEUE_DEVICE_HIGH : constant := 16#0A4#;
   REG_CONFIG_GEN        : constant := 16#0FC#;
   REG_CONFIG_BASE       : constant := 16#100#;

   --  Well-known values
   MAGIC_VALUE  : constant := 16#74726976#;  -- "virt" LE
   MMIO_VERSION : constant := 2;
   DEVICE_ID    : constant := 2;             -- block device
   VENDOR_ID    : constant := 16#554B5248#;  -- "HKRU"

   --  VirtIO device status bits
   VIRTIO_STATUS_ACKNOWLEDGE  : constant := 1;
   VIRTIO_STATUS_DRIVER       : constant := 2;
   VIRTIO_STATUS_DRIVER_OK    : constant := 4;
   VIRTIO_STATUS_FEATURES_OK  : constant := 8;
   VIRTIO_STATUS_FAILED       : constant := 128;

   --  Queue
   Queue_Size : constant := 16;

   --  Disk geometry
   Max_Sectors : constant := 1024;
   Sector_Size : constant := 512;

   --  VirtIO block request types
   VIRTIO_BLK_T_IN  : constant := 0;  -- read  (device ->memory)
   VIRTIO_BLK_T_OUT : constant := 1;  -- write (memory ->device)

   --  Status bytes written to status descriptor
   VIRTIO_BLK_S_OK     : constant := 0;
   VIRTIO_BLK_S_IOERR  : constant := 1;
   VIRTIO_BLK_S_UNSUPP : constant := 2;

   --  Virtqueue descriptor flags
   VIRTQ_DESC_F_NEXT  : constant := 1;  -- chained to next
   VIRTQ_DESC_F_WRITE : constant := 2;  -- device-writable buffer

   --  Flat disk storage (1 024 * 512 = 512 KB)
   type Disk_Data   is array (0 .. Max_Sectors * Sector_Size - 1) of Byte;
   type Disk_Access is access Disk_Data;

   --  Device state
   type VirtIO_Block_State is record
      Base_Address    : Memory_Address;
      Enabled         : Boolean;
      --  Register shadow
      DevFeatureSel   : Word;
      DrvFeatureSel   : Word;
      DrvFeatures0    : Word;
      DrvFeatures1    : Word;
      QueueNum        : Word;
      QueueReady      : Word;
      InterruptStatus : Word;
      DevStatus       : Word;
      QueueDescLo     : Word;
      QueueDescHi     : Word;
      QueueDriverLo   : Word;
      QueueDriverHi   : Word;
      QueueDeviceLo   : Word;
      QueueDeviceHi   : Word;
      --  Queue processing state (wrapping 16-bit counters stored as Word)
      Last_Avail_Idx  : Word;
      Used_Idx        : Word;
      --  Set to True when QueueNotify written; cleared by Process_Queue
      Notify_Pending  : Boolean;
      --  Disk storage (allocated on heap)
      Disk            : Disk_Access;
   end record;

   --  Initialize / finalize
   procedure Initialize (VB   : out VirtIO_Block_State;
                         Base : Memory_Address := Default_Base_Address);

   procedure Finalize (VB : in out VirtIO_Block_State);

   --  Address decoding
   function Is_VirtIO_Block_Address (VB   : VirtIO_Block_State;
                                     Addr : Memory_Address) return Boolean;

   --  Register access
   function Read_Byte (VB   : VirtIO_Block_State;
                       Addr : Memory_Address) return Byte;

   function Read_Word (VB   : VirtIO_Block_State;
                       Addr : Memory_Address) return Word;

   procedure Write_Byte (VB   : in out VirtIO_Block_State;
                         Addr : Memory_Address;
                         Data : Byte);

   procedure Write_Word (VB   : in out VirtIO_Block_State;
                         Addr : Memory_Address;
                         Data : Word);

end RISCV.VirtIO_Block;
