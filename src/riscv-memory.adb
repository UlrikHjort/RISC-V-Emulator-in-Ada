-- ***************************************************************************
--              RISC-V Emulator - Memory Subsystem
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

package body RISCV.Memory is

   procedure Free is new Ada.Unchecked_Deallocation (Memory_Array, Memory_Access);
   procedure Free_UART is new Ada.Unchecked_Deallocation
     (RISCV.UART.UART_State, UART_Access);
   procedure Free_CLINT is new Ada.Unchecked_Deallocation
     (RISCV.CLINT.CLINT_State, CLINT_Access);
   procedure Free_GPIO is new Ada.Unchecked_Deallocation
     (RISCV.GPIO.GPIO_State, GPIO_Access);
   procedure Free_SPI is new Ada.Unchecked_Deallocation
     (RISCV.SPI.SPI_State, SPI_Access);
   procedure Free_I2C is new Ada.Unchecked_Deallocation
     (RISCV.I2C.I2C_State, I2C_Access);
   procedure Free_Timer is new Ada.Unchecked_Deallocation
     (RISCV.Timer.Timer_State, Timer_Access);
   procedure Free_Watchdog is new Ada.Unchecked_Deallocation
     (RISCV.Watchdog.Watchdog_State, Watchdog_Access);
   procedure Free_DMA is new Ada.Unchecked_Deallocation
     (RISCV.DMA.DMA_State, DMA_Access);
   procedure Free_PLIC is new Ada.Unchecked_Deallocation
     (RISCV.PLIC.PLIC_State, PLIC_Access);
   procedure Free_VirtIO_Block is new Ada.Unchecked_Deallocation
     (RISCV.VirtIO_Block.VirtIO_Block_State, VirtIO_Block_Access);
   procedure Free_Region_Data is new Ada.Unchecked_Deallocation
     (Region_Data, Region_Data_Access);

   --  ========================================================================
   --  Helper: Pad string to fixed length
   --  ========================================================================

   function Pad_Name (Name : String) return String is
      Result : String (1 .. 16) := (others => ' ');
      Len    : constant Natural := Natural'Min (Name'Length, 16);
   begin
      Result (1 .. Len) := Name (Name'First .. Name'First + Len - 1);
      return Result;
   end Pad_Name;

   --  ========================================================================
   --  Initialization
   --  ========================================================================

   procedure Initialize (Mem : out Memory_Unit) is
   begin
      --  Legacy flat memory mode
      Mem.Data := new Memory_Array'(others => 0);
      Mem.Use_Regions := False;
      Mem.Region_Count := 0;
      Mem.UART := new RISCV.UART.UART_State;
      Mem.UART.Enabled := False;
      Mem.CLINT := new RISCV.CLINT.CLINT_State;
      Mem.CLINT.Enabled := False;
      Mem.GPIO := new RISCV.GPIO.GPIO_State;
      Mem.GPIO.Enabled := False;
      Mem.SPI := new RISCV.SPI.SPI_State;
      Mem.SPI.Enabled := False;
      Mem.I2C := new RISCV.I2C.I2C_State;
      Mem.I2C.Enabled := False;
      Mem.Timer := new RISCV.Timer.Timer_State;
      Mem.Timer.Enabled := False;
      Mem.Watchdog := new RISCV.Watchdog.Watchdog_State;
      Mem.Watchdog.Enabled := False;
      Mem.DMA := new RISCV.DMA.DMA_State;
      Mem.DMA.Enabled := False;
      Mem.PLIC := new RISCV.PLIC.PLIC_State;
      Mem.PLIC.Enabled := False;
      Mem.VirtIO_Blk := new RISCV.VirtIO_Block.VirtIO_Block_State;
      Mem.VirtIO_Blk.Enabled := False;
      Mem.Last_Result := OK;
   end Initialize;

   procedure Initialize_Empty (Mem : out Memory_Unit) is
   begin
      --  Region-based mode, no memory yet
      Mem.Data := null;
      Mem.Use_Regions := True;
      Mem.Region_Count := 0;
      Mem.UART := new RISCV.UART.UART_State;
      Mem.UART.Enabled := False;
      Mem.CLINT := new RISCV.CLINT.CLINT_State;
      Mem.CLINT.Enabled := False;
      Mem.GPIO := new RISCV.GPIO.GPIO_State;
      Mem.GPIO.Enabled := False;
      Mem.SPI := new RISCV.SPI.SPI_State;
      Mem.SPI.Enabled := False;
      Mem.I2C := new RISCV.I2C.I2C_State;
      Mem.I2C.Enabled := False;
      Mem.Timer := new RISCV.Timer.Timer_State;
      Mem.Timer.Enabled := False;
      Mem.Watchdog := new RISCV.Watchdog.Watchdog_State;
      Mem.Watchdog.Enabled := False;
      Mem.DMA := new RISCV.DMA.DMA_State;
      Mem.DMA.Enabled := False;
      Mem.PLIC := new RISCV.PLIC.PLIC_State;
      Mem.PLIC.Enabled := False;
      Mem.VirtIO_Blk := new RISCV.VirtIO_Block.VirtIO_Block_State;
      Mem.VirtIO_Blk.Enabled := False;
      Mem.Last_Result := OK;
   end Initialize_Empty;

   procedure Finalize (Mem : in out Memory_Unit) is
   begin
      --  Free legacy memory
      if Mem.Data /= null then
         Free (Mem.Data);
      end if;

      --  Free region memory
      for I in 0 .. Mem.Region_Count - 1 loop
         if Mem.Regions (Region_Index (I)).Data /= null then
            Free_Region_Data (Mem.Regions (Region_Index (I)).Data);
         end if;
      end loop;
      Mem.Region_Count := 0;

      --  Free peripherals
      if Mem.UART /= null then
         Free_UART (Mem.UART);
      end if;
      if Mem.CLINT /= null then
         Free_CLINT (Mem.CLINT);
      end if;
      if Mem.GPIO /= null then
         Free_GPIO (Mem.GPIO);
      end if;
      if Mem.SPI /= null then
         RISCV.SPI.Finalize (Mem.SPI.all);
         Free_SPI (Mem.SPI);
      end if;
      if Mem.I2C /= null then
         RISCV.I2C.Finalize (Mem.I2C.all);
         Free_I2C (Mem.I2C);
      end if;
      if Mem.Timer /= null then
         Free_Timer (Mem.Timer);
      end if;
      if Mem.Watchdog /= null then
         Free_Watchdog (Mem.Watchdog);
      end if;
      if Mem.DMA /= null then
         Free_DMA (Mem.DMA);
      end if;
      if Mem.PLIC /= null then
         Free_PLIC (Mem.PLIC);
      end if;
      if Mem.VirtIO_Blk /= null then
         RISCV.VirtIO_Block.Finalize (Mem.VirtIO_Blk.all);
         Free_VirtIO_Block (Mem.VirtIO_Blk);
      end if;
   end Finalize;

   --  ========================================================================
   --  Region Management
   --  ========================================================================

   procedure Add_Region (Mem    : in out Memory_Unit;
                         Name   : String;
                         Base   : Memory_Address;
                         Size   : Word;
                         Rtype  : Region_Type := RAM;
                         Perm   : Access_Permission := Permission_RWX) is
      Idx      : Region_Index;
      Data_Len : Natural;
   begin
      if Mem.Region_Count >= Max_Regions then
         return;  --  No room for more regions
      end if;

      if Size = 0 or Size > Word (Max_Region_Size) then
         return;  --  Invalid size
      end if;

      Idx := Region_Index (Mem.Region_Count);
      Data_Len := Natural (Size);

      Mem.Regions (Idx).Name := Pad_Name (Name);
      Mem.Regions (Idx).Name_Len := Natural'Min (Name'Length, 16);
      Mem.Regions (Idx).Base := Base;
      Mem.Regions (Idx).Size := Size;
      Mem.Regions (Idx).Rtype := Rtype;
      Mem.Regions (Idx).Perm := Perm;
      Mem.Regions (Idx).Data := new Region_Data'(0 .. Data_Len - 1 => 0);

      Mem.Region_Count := Mem.Region_Count + 1;
      Mem.Use_Regions := True;
   end Add_Region;

   function Find_Region (Mem     : Memory_Unit;
                         Address : Memory_Address) return Natural is
   begin
      for I in 0 .. Mem.Region_Count - 1 loop
         declare
            R : Memory_Region renames Mem.Regions (Region_Index (I));
         begin
            if Address >= R.Base and then
               Address < R.Base + Memory_Address (R.Size)
            then
               return I;
            end if;
         end;
      end loop;
      return Mem.Region_Count;  --  Not found
   end Find_Region;

   function Is_Mapped (Mem     : Memory_Unit;
                       Address : Memory_Address) return Boolean is
   begin
      if not Mem.Use_Regions then
         return Is_Valid_Address (Address);
      end if;
      return Find_Region (Mem, Address) < Mem.Region_Count;
   end Is_Mapped;

   --  ========================================================================
   --  Memory Operations
   --  ========================================================================

   procedure Load_Binary (Mem      : in out Memory_Unit;
                          Filename : String;
                          Address  : Memory_Address;
                          Success  : out Boolean) is
      use Ada.Streams.Stream_IO;
      File   : File_Type;
      Stream : Stream_Access;
      Addr   : Memory_Address := Address;
      B      : Byte;
   begin
      Success := False;

      Open (File, In_File, Filename);
      Stream := Ada.Streams.Stream_IO.Stream (File);

      while not End_Of_File (File) loop
         Byte'Read (Stream, B);
         Write_Byte (Mem, Addr, B);
         if Mem.Last_Result /= OK then
            Close (File);
            return;
         end if;
         Addr := Addr + 1;
      end loop;

      Close (File);
      Success := True;

   exception
      when others =>
         if Is_Open (File) then
            Close (File);
         end if;
         Success := False;
   end Load_Binary;

   --  ========================================================================
   --  Read Operations
   --  ========================================================================

   function Read_Byte (Mem     : in out Memory_Unit;
                       Address : Memory_Address) return Byte is
   begin
      Mem.Last_Result := OK;

      --  Track memory access for watchpoints
      if Mem.Track_Access then
         Mem.Last_Access_Addr := Address;
         Mem.Last_Access_Write := False;
         Mem.Access_Occurred := True;
         Mem.Last_Access_Valid := True;
      end if;

      --  Call watchpoint hook if set
      if Mem.Access_Hook /= null then
         Mem.Access_Hook (Address, Is_Write => False);
      end if;

      --  Check for peripheral access first
      if Mem.UART /= null and then
         RISCV.UART.Is_UART_Address (Mem.UART.all, Address)
      then
         return RISCV.UART.Read (Mem.UART.all, Address);
      end if;

      if Mem.CLINT /= null and then
         RISCV.CLINT.Is_CLINT_Address (Mem.CLINT.all, Address)
      then
         return RISCV.CLINT.Read_Byte (Mem.CLINT.all, Address);
      end if;

      if Mem.GPIO /= null and then
         RISCV.GPIO.Is_GPIO_Address (Mem.GPIO.all, Address)
      then
         return RISCV.GPIO.Read_Byte (Mem.GPIO.all, Address);
      end if;

      if Mem.SPI /= null and then
         RISCV.SPI.Is_SPI_Address (Mem.SPI.all, Address)
      then
         return RISCV.SPI.Read_Byte (Mem.SPI.all, Address);
      end if;

      if Mem.I2C /= null and then
         RISCV.I2C.Is_I2C_Address (Mem.I2C.all, Address)
      then
         return RISCV.I2C.Read_Byte (Mem.I2C.all, Address);
      end if;

      if Mem.Timer /= null and then
         RISCV.Timer.Is_Timer_Address (Mem.Timer.all, Address)
      then
         return RISCV.Timer.Read_Byte (Mem.Timer.all, Address);
      end if;

      if Mem.Watchdog /= null and then
         RISCV.Watchdog.Is_Watchdog_Address (Mem.Watchdog.all, Address)
      then
         return RISCV.Watchdog.Read_Byte (Mem.Watchdog.all, Address);
      end if;

      if Mem.DMA /= null and then
         RISCV.DMA.Is_DMA_Address (Mem.DMA.all, Address)
      then
         return RISCV.DMA.Read_Byte (Mem.DMA.all, Address);
      end if;

      if Mem.PLIC /= null and then
         RISCV.PLIC.Is_PLIC_Address (Mem.PLIC.all, Address)
      then
         return RISCV.PLIC.Read_Byte (Mem.PLIC.all, Address);
      end if;

      if Mem.VirtIO_Blk /= null and then
         RISCV.VirtIO_Block.Is_VirtIO_Block_Address (Mem.VirtIO_Blk.all, Address)
      then
         return RISCV.VirtIO_Block.Read_Byte (Mem.VirtIO_Blk.all, Address);
      end if;

      --  Legacy flat memory mode
      if not Mem.Use_Regions then
         if Mem.Data = null or else not Is_Valid_Address (Address) then
            --  Out of range must report Unmapped.  Wrapping the address into
            --  the array instead would alias every access past the end of
            --  memory onto a valid byte, silently reading or corrupting it.
            Mem.Last_Result := Unmapped;
            return 0;
         end if;
         return Mem.Data (Natural (Address));
      end if;

      --  Region-based mode
      declare
         Idx : constant Natural := Find_Region (Mem, Address);
      begin
         if Idx >= Mem.Region_Count then
            Mem.Last_Result := Unmapped;
            return 0;
         end if;

         declare
            R      : Memory_Region renames Mem.Regions (Region_Index (Idx));
            Offset : constant Natural := Natural (Address - R.Base);
         begin
            if not R.Perm.Read then
               Mem.Last_Result := Permission_Error;
               return 0;
            end if;
            return R.Data (Offset);
         end;
      end;
   end Read_Byte;

   function Read_Half_Word (Mem     : in out Memory_Unit;
                            Address : Memory_Address) return Half_Word is
      Lo : constant Byte := Read_Byte (Mem, Address);
      Hi : constant Byte := Read_Byte (Mem, Address + 1);
   begin
      --  Correct Last_Access_Addr to base address (byte reads leave it at +1)
      if Mem.Track_Access then
         Mem.Last_Access_Addr := Address;
         Mem.Last_Access_Valid := True;
      end if;
      --  Little-endian
      return Half_Word (Lo) or Shift_Left (Half_Word (Hi), 8);
   end Read_Half_Word;

   function Read_Word (Mem     : in out Memory_Unit;
                       Address : Memory_Address) return Word is
      B0 : constant Byte := Read_Byte (Mem, Address);
      B1 : constant Byte := Read_Byte (Mem, Address + 1);
      B2 : constant Byte := Read_Byte (Mem, Address + 2);
      B3 : constant Byte := Read_Byte (Mem, Address + 3);
   begin
      --  Correct Last_Access_Addr to base address (byte reads leave it at +3)
      if Mem.Track_Access then
         Mem.Last_Access_Addr := Address;
         Mem.Last_Access_Valid := True;
      end if;
      --  Little-endian
      return Word (B0) or
             Shift_Left (Word (B1), 8) or
             Shift_Left (Word (B2), 16) or
             Shift_Left (Word (B3), 24);
   end Read_Word;

   --  ========================================================================
   --  Write Operations
   --  ========================================================================

   --  Process VirtIO block queue synchronously (called when QueueNotify written)
   procedure Process_VirtIO_Queue (Mem : in out Memory_Unit) is
      VB      : RISCV.VirtIO_Block.VirtIO_Block_State renames Mem.VirtIO_Blk.all;
      Queue_N : constant Word :=
         (if VB.QueueNum = 0 then RISCV.VirtIO_Block.Queue_Size else VB.QueueNum);
      Desc_Base  : constant Memory_Address := Memory_Address (VB.QueueDescLo);
      Avail_Base : constant Memory_Address := Memory_Address (VB.QueueDriverLo);
      Used_Base  : constant Memory_Address := Memory_Address (VB.QueueDeviceLo);

      function RHW (Addr : Memory_Address) return Word is
         Lo : constant Word := Word (Read_Byte (Mem, Addr));
         Hi : constant Word := Word (Read_Byte (Mem, Addr + 1));
      begin
         return Lo or Shift_Left (Hi, 8);
      end RHW;

      function RW (Addr : Memory_Address) return Word is
         B0 : constant Word := Word (Read_Byte (Mem, Addr));
         B1 : constant Word := Word (Read_Byte (Mem, Addr + 1));
         B2 : constant Word := Word (Read_Byte (Mem, Addr + 2));
         B3 : constant Word := Word (Read_Byte (Mem, Addr + 3));
      begin
         return B0 or Shift_Left (B1, 8) or Shift_Left (B2, 16) or Shift_Left (B3, 24);
      end RW;

      procedure WHW (Addr : Memory_Address; Val : Word) is
      begin
         Write_Byte (Mem, Addr,     Byte (Val and 16#FF#));
         Write_Byte (Mem, Addr + 1, Byte (Shift_Right (Val, 8) and 16#FF#));
      end WHW;

      procedure WW (Addr : Memory_Address; Val : Word) is
      begin
         Write_Byte (Mem, Addr,     Byte (Val and 16#FF#));
         Write_Byte (Mem, Addr + 1, Byte (Shift_Right (Val, 8)  and 16#FF#));
         Write_Byte (Mem, Addr + 2, Byte (Shift_Right (Val, 16) and 16#FF#));
         Write_Byte (Mem, Addr + 3, Byte (Shift_Right (Val, 24) and 16#FF#));
      end WW;

      Avail_Idx : Word;
      Desc_Idx  : Word;
      DA        : Memory_Address;   --  descriptor address
      D0_Buf    : Memory_Address;
      D0_Next   : Word;
      D1_Buf    : Memory_Address;
      D1_Len    : Word;
      D1_Next   : Word;
      D2_Buf    : Memory_Address;
      Req_Type  : Word;
      Req_Sec   : Word;
      Disk_Off  : Natural;
      Used_Pos  : Memory_Address;

   begin
      if not VB.Notify_Pending or else VB.QueueReady = 0 then
         return;
      end if;

      VB.Notify_Pending := False;

      Avail_Idx := RHW (Avail_Base + 2) and 16#FFFF#;

      while (VB.Last_Avail_Idx and 16#FFFF#) /= Avail_Idx loop
         --  Ring entry: available ring slot ->first descriptor index
         Desc_Idx := RHW (Avail_Base + 4 +
                          Memory_Address ((VB.Last_Avail_Idx mod Queue_N) * 2))
                     and 16#FFFF#;

         --  Descriptor 0: virtio_blk_req header (type:4 + reserved:4 + sector:8 = 16 bytes)
         DA     := Desc_Base + Memory_Address (Desc_Idx) * 16;
         D0_Buf := Memory_Address (RW (DA));          --  low 32 of 64-bit addr
         --  high 32 at DA+4 is 0 for 32-bit guest
         D0_Next := RHW (DA + 14) and 16#FFFF#;

         Req_Type := RW (D0_Buf);                   --  VIRTIO_BLK_T_IN/OUT
         Req_Sec  := RW (D0_Buf + 8);               --  sector (low 32 bits)

         --  Descriptor 1: data buffer
         DA     := Desc_Base + Memory_Address (D0_Next) * 16;
         D1_Buf := Memory_Address (RW (DA));
         D1_Len := RW (DA + 8);
         D1_Next := RHW (DA + 14) and 16#FFFF#;

         --  Descriptor 2: status byte (device-writable)
         DA     := Desc_Base + Memory_Address (D1_Next) * 16;
         D2_Buf := Memory_Address (RW (DA));

         --  Perform disk I/O
         Disk_Off := Natural (Req_Sec) * RISCV.VirtIO_Block.Sector_Size;
         if Disk_Off >= RISCV.VirtIO_Block.Max_Sectors *
                         RISCV.VirtIO_Block.Sector_Size
         then
            --  Out-of-range sector: return I/O error
            Write_Byte (Mem, D2_Buf, RISCV.VirtIO_Block.VIRTIO_BLK_S_IOERR);
         elsif Req_Type = RISCV.VirtIO_Block.VIRTIO_BLK_T_IN then
            --  Read: disk ->guest memory
            for I in 0 .. Natural (D1_Len) - 1 loop
               if Disk_Off + I < RISCV.VirtIO_Block.Max_Sectors *
                                  RISCV.VirtIO_Block.Sector_Size
               then
                  Write_Byte (Mem, D1_Buf + Memory_Address (I), VB.Disk (Disk_Off + I));
               else
                  Write_Byte (Mem, D1_Buf + Memory_Address (I), 0);
               end if;
            end loop;
            Write_Byte (Mem, D2_Buf, RISCV.VirtIO_Block.VIRTIO_BLK_S_OK);
         else
            --  Write: guest memory ->disk
            for I in 0 .. Natural (D1_Len) - 1 loop
               if Disk_Off + I < RISCV.VirtIO_Block.Max_Sectors *
                                  RISCV.VirtIO_Block.Sector_Size
               then
                  VB.Disk (Disk_Off + I) :=
                     Read_Byte (Mem, D1_Buf + Memory_Address (I));
               end if;
            end loop;
            Write_Byte (Mem, D2_Buf, RISCV.VirtIO_Block.VIRTIO_BLK_S_OK);
         end if;

         --  Used ring entry: virtq_used_elem { id:4, len:4 }
         Used_Pos := Used_Base + 4 +
                     Memory_Address ((VB.Used_Idx mod Queue_N) * 8);
         WW (Used_Pos,     Desc_Idx);
         WW (Used_Pos + 4, D1_Len);

         VB.Last_Avail_Idx := VB.Last_Avail_Idx + 1;
         VB.Used_Idx       := VB.Used_Idx + 1;
      end loop;

      --  Update used ring index and signal interrupt
      WHW (Used_Base + 2, VB.Used_Idx and 16#FFFF#);
      VB.InterruptStatus := VB.InterruptStatus or 1;
   end Process_VirtIO_Queue;

   procedure Write_Byte (Mem     : in out Memory_Unit;
                         Address : Memory_Address;
                         Value   : Byte) is
   begin
      Mem.Last_Result := OK;

      --  Track memory access for watchpoints
      if Mem.Track_Access then
         Mem.Last_Access_Addr := Address;
         Mem.Last_Access_Write := True;
         Mem.Access_Occurred := True;
         Mem.Last_Access_Valid := True;
      end if;

      --  Call watchpoint hook if set
      if Mem.Access_Hook /= null then
         Mem.Access_Hook (Address, Is_Write => True);
      end if;

      --  Check for peripheral access first
      if Mem.UART /= null and then
         RISCV.UART.Is_UART_Address (Mem.UART.all, Address)
      then
         RISCV.UART.Write (Mem.UART.all, Address, Value);
         return;
      end if;

      if Mem.CLINT /= null and then
         RISCV.CLINT.Is_CLINT_Address (Mem.CLINT.all, Address)
      then
         RISCV.CLINT.Write_Byte (Mem.CLINT.all, Address, Value);
         return;
      end if;

      if Mem.GPIO /= null and then
         RISCV.GPIO.Is_GPIO_Address (Mem.GPIO.all, Address)
      then
         RISCV.GPIO.Write_Byte (Mem.GPIO.all, Address, Value);
         return;
      end if;

      if Mem.SPI /= null and then
         RISCV.SPI.Is_SPI_Address (Mem.SPI.all, Address)
      then
         RISCV.SPI.Write_Byte (Mem.SPI.all, Address, Value);
         return;
      end if;

      if Mem.I2C /= null and then
         RISCV.I2C.Is_I2C_Address (Mem.I2C.all, Address)
      then
         RISCV.I2C.Write_Byte (Mem.I2C.all, Address, Value);
         return;
      end if;

      if Mem.Timer /= null and then
         RISCV.Timer.Is_Timer_Address (Mem.Timer.all, Address)
      then
         RISCV.Timer.Write_Byte (Mem.Timer.all, Address, Value);
         return;
      end if;

      if Mem.Watchdog /= null and then
         RISCV.Watchdog.Is_Watchdog_Address (Mem.Watchdog.all, Address)
      then
         RISCV.Watchdog.Write_Byte (Mem.Watchdog.all, Address, Value);
         return;
      end if;

      if Mem.DMA /= null and then
         RISCV.DMA.Is_DMA_Address (Mem.DMA.all, Address)
      then
         RISCV.DMA.Write_Byte (Mem.DMA.all, Address, Value);
         return;
      end if;

      if Mem.PLIC /= null and then
         RISCV.PLIC.Is_PLIC_Address (Mem.PLIC.all, Address)
      then
         RISCV.PLIC.Write_Byte (Mem.PLIC.all, Address, Value);
         return;
      end if;

      if Mem.VirtIO_Blk /= null and then
         RISCV.VirtIO_Block.Is_VirtIO_Block_Address (Mem.VirtIO_Blk.all, Address)
      then
         RISCV.VirtIO_Block.Write_Byte (Mem.VirtIO_Blk.all, Address, Value);
         if Mem.VirtIO_Blk.Notify_Pending then
            Process_VirtIO_Queue (Mem);
         end if;
         return;
      end if;

      --  Legacy flat memory mode
      if not Mem.Use_Regions then
         if Mem.Data = null or else not Is_Valid_Address (Address) then
            --  See Read_Byte: out of range is Unmapped, never a wrapped
            --  write onto an unrelated byte.
            Mem.Last_Result := Unmapped;
            return;
         end if;
         Mem.Data (Natural (Address)) := Value;
         return;
      end if;

      --  Region-based mode
      declare
         Idx : constant Natural := Find_Region (Mem, Address);
      begin
         if Idx >= Mem.Region_Count then
            Mem.Last_Result := Unmapped;
            return;
         end if;

         declare
            R      : Memory_Region renames Mem.Regions (Region_Index (Idx));
            Offset : constant Natural := Natural (Address - R.Base);
         begin
            if not R.Perm.Write then
               --  ROM/Flash: silently ignore writes (or could set error)
               if R.Rtype = ROM or R.Rtype = Flash then
                  return;  --  Silent ignore for ROM
               end if;
               Mem.Last_Result := Permission_Error;
               return;
            end if;
            R.Data (Offset) := Value;
         end;
      end;
   end Write_Byte;

   procedure Write_Half_Word (Mem     : in out Memory_Unit;
                              Address : Memory_Address;
                              Value   : Half_Word) is
   begin
      --  Little-endian
      Write_Byte (Mem, Address, Byte (Value and 16#FF#));
      Write_Byte (Mem, Address + 1, Byte (Shift_Right (Value, 8) and 16#FF#));
      --  Correct Last_Access_Addr to base address
      if Mem.Track_Access then
         Mem.Last_Access_Addr := Address;
         Mem.Last_Access_Valid := True;
      end if;
   end Write_Half_Word;

   procedure Write_Word (Mem     : in out Memory_Unit;
                         Address : Memory_Address;
                         Value   : Word) is
   begin
      --  Little-endian
      Write_Byte (Mem, Address, Byte (Value and 16#FF#));
      Write_Byte (Mem, Address + 1, Byte (Shift_Right (Value, 8) and 16#FF#));
      Write_Byte (Mem, Address + 2, Byte (Shift_Right (Value, 16) and 16#FF#));
      Write_Byte (Mem, Address + 3, Byte (Shift_Right (Value, 24) and 16#FF#));
      --  Correct Last_Access_Addr to base address
      if Mem.Track_Access then
         Mem.Last_Access_Addr := Address;
         Mem.Last_Access_Valid := True;
      end if;
      --  HTIF tohost termination (riscv-tests). A 64-bit sd on RV64 lowers to
      --  two Write_Word calls; the low word carries the pass/fail code.
      if Mem.HTIF_Enabled and then Address = Mem.Tohost_Addr then
         Mem.Tohost_Value := Value;
         Mem.Tohost_Written := True;
      end if;
   end Write_Word;

   --  ========================================================================
   --  Utility Functions
   --  ========================================================================

   function Is_Valid_Address (Address : Memory_Address) return Boolean is
   begin
      --  Compare in Memory_Address, not Natural: an address at or above
      --  2**31 does not fit in Natural and the conversion would raise
      --  Constraint_Error before the comparison ever ran.
      return Address < Memory_Address (Memory_Size);
   end Is_Valid_Address;

   function Last_Access_Result (Mem : Memory_Unit) return Access_Result is
   begin
      return Mem.Last_Result;
   end Last_Access_Result;

   --  ========================================================================
   --  UART Control
   --  ========================================================================

   procedure Enable_UART (Mem  : in out Memory_Unit;
                          Base : Memory_Address := UART.Default_Base_Address) is
   begin
      if Mem.UART = null then
         Mem.UART := new RISCV.UART.UART_State;
      end if;
      RISCV.UART.Initialize (Mem.UART.all, Base);
   end Enable_UART;

   procedure Disable_UART (Mem : in out Memory_Unit) is
   begin
      if Mem.UART /= null then
         Mem.UART.Enabled := False;
      end if;
   end Disable_UART;

   function UART_Enabled (Mem : Memory_Unit) return Boolean is
   begin
      return Mem.UART /= null and then Mem.UART.Enabled;
   end UART_Enabled;

   procedure UART_Add_Input (Mem : in out Memory_Unit; Data : Byte) is
   begin
      if Mem.UART /= null and then Mem.UART.Enabled then
         RISCV.UART.Add_Input (Mem.UART.all, Data);
      end if;
   end UART_Add_Input;

   procedure UART_Add_Input_String (Mem : in out Memory_Unit; Str : String) is
   begin
      if Mem.UART /= null and then Mem.UART.Enabled then
         RISCV.UART.Add_Input_String (Mem.UART.all, Str);
      end if;
   end UART_Add_Input_String;

   --  ========================================================================
   --  CLINT Control
   --  ========================================================================

   procedure Enable_CLINT (Mem  : in out Memory_Unit;
                           Base : Memory_Address := CLINT.Default_Base_Address) is
   begin
      if Mem.CLINT = null then
         Mem.CLINT := new RISCV.CLINT.CLINT_State;
      end if;
      RISCV.CLINT.Initialize (Mem.CLINT.all, Base);
   end Enable_CLINT;

   procedure Disable_CLINT (Mem : in out Memory_Unit) is
   begin
      if Mem.CLINT /= null then
         Mem.CLINT.Enabled := False;
      end if;
   end Disable_CLINT;

   function CLINT_Enabled (Mem : Memory_Unit) return Boolean is
   begin
      return Mem.CLINT /= null and then Mem.CLINT.Enabled;
   end CLINT_Enabled;

   procedure CLINT_Tick (Mem : in out Memory_Unit) is
   begin
      if Mem.CLINT /= null and then Mem.CLINT.Enabled then
         RISCV.CLINT.Tick (Mem.CLINT.all);
      end if;
   end CLINT_Tick;

   function CLINT_Timer_Interrupt_Pending (Mem  : Memory_Unit;
                                           Hart : Natural := 0) return Boolean is
   begin
      if Mem.CLINT /= null and then Mem.CLINT.Enabled then
         return RISCV.CLINT.Timer_Interrupt_Pending (Mem.CLINT.all, Hart);
      end if;
      return False;
   end CLINT_Timer_Interrupt_Pending;

   function CLINT_Software_Interrupt_Pending (Mem  : Memory_Unit;
                                              Hart : Natural := 0) return Boolean is
   begin
      if Mem.CLINT /= null and then Mem.CLINT.Enabled then
         return RISCV.CLINT.Software_Interrupt_Pending (Mem.CLINT.all, Hart);
      end if;
      return False;
   end CLINT_Software_Interrupt_Pending;

   procedure CLINT_Clear_Timer (Mem  : in out Memory_Unit;
                                Hart : Natural := 0) is
   begin
      if Mem.CLINT /= null and then Mem.CLINT.Enabled then
         RISCV.CLINT.Clear_Timer_Interrupt (Mem.CLINT.all, Hart);
      end if;
   end CLINT_Clear_Timer;

   --  ========================================================================
   --  GPIO Control
   --  ========================================================================

   procedure Enable_GPIO (Mem  : in out Memory_Unit;
                          Base : Memory_Address := GPIO.Default_Base_Address) is
   begin
      if Mem.GPIO = null then
         Mem.GPIO := new RISCV.GPIO.GPIO_State;
      end if;
      RISCV.GPIO.Initialize (Mem.GPIO.all, Base);
   end Enable_GPIO;

   procedure Disable_GPIO (Mem : in out Memory_Unit) is
   begin
      if Mem.GPIO /= null then
         Mem.GPIO.Enabled := False;
      end if;
   end Disable_GPIO;

   function GPIO_Enabled (Mem : Memory_Unit) return Boolean is
   begin
      return Mem.GPIO /= null and then Mem.GPIO.Enabled;
   end GPIO_Enabled;

   procedure GPIO_Set_External_Input (Mem   : in out Memory_Unit;
                                      Value : Word) is
   begin
      if Mem.GPIO /= null and then Mem.GPIO.Enabled then
         RISCV.GPIO.Set_External_Input (Mem.GPIO.all, Value);
      end if;
   end GPIO_Set_External_Input;

   function GPIO_Get_Output (Mem : Memory_Unit) return Word is
   begin
      if Mem.GPIO /= null and then Mem.GPIO.Enabled then
         return RISCV.GPIO.Get_Output (Mem.GPIO.all);
      end if;
      return 0;
   end GPIO_Get_Output;

   function GPIO_Interrupt_Pending (Mem : Memory_Unit) return Boolean is
   begin
      if Mem.GPIO /= null and then Mem.GPIO.Enabled then
         return RISCV.GPIO.Interrupt_Pending (Mem.GPIO.all);
      end if;
      return False;
   end GPIO_Interrupt_Pending;

   procedure GPIO_Update (Mem : in out Memory_Unit) is
   begin
      if Mem.GPIO /= null and then Mem.GPIO.Enabled then
         RISCV.GPIO.Update (Mem.GPIO.all);
      end if;
   end GPIO_Update;

   --  ========================================================================
   --  SPI Control
   --  ========================================================================

   procedure Enable_SPI (Mem  : in out Memory_Unit;
                         Base : Memory_Address := RISCV.SPI.Default_Base_Address) is
   begin
      if Mem.SPI /= null then
         RISCV.SPI.Initialize (Mem.SPI.all, Base);
      end if;
   end Enable_SPI;

   procedure Disable_SPI (Mem : in out Memory_Unit) is
   begin
      if Mem.SPI /= null then
         Mem.SPI.Enabled := False;
      end if;
   end Disable_SPI;

   function SPI_Enabled (Mem : Memory_Unit) return Boolean is
   begin
      return Mem.SPI /= null and then Mem.SPI.Enabled;
   end SPI_Enabled;

   function SPI_Get_Flash (Mem : Memory_Unit) return RISCV.SPI.Flash_Memory_Access is
   begin
      if Mem.SPI /= null and then Mem.SPI.Enabled then
         return RISCV.SPI.Get_Flash (Mem.SPI.all);
      end if;
      return null;
   end SPI_Get_Flash;

   --  ========================================================================
   --  I2C Control
   --  ========================================================================

   procedure Enable_I2C (Mem  : in out Memory_Unit;
                         Base : Memory_Address := RISCV.I2C.Default_Base_Address) is
   begin
      if Mem.I2C /= null then
         RISCV.I2C.Initialize (Mem.I2C.all, Base);
      end if;
   end Enable_I2C;

   procedure Disable_I2C (Mem : in out Memory_Unit) is
   begin
      if Mem.I2C /= null then
         Mem.I2C.Enabled := False;
      end if;
   end Disable_I2C;

   function I2C_Enabled (Mem : Memory_Unit) return Boolean is
   begin
      return Mem.I2C /= null and then Mem.I2C.Enabled;
   end I2C_Enabled;

   procedure I2C_Add_Device (Mem         : in out Memory_Unit;
                             Device_Type : RISCV.I2C.I2C_Device_Type;
                             Address     : Byte) is
   begin
      if Mem.I2C /= null and then Mem.I2C.Enabled then
         RISCV.I2C.Add_Device (Mem.I2C.all, Device_Type, Address);
      end if;
   end I2C_Add_Device;

   --  ========================================================================
   --  Timer Control
   --  ========================================================================

   procedure Enable_Timer (Mem  : in out Memory_Unit;
                           Base : Memory_Address := RISCV.Timer.Default_Base_Address) is
   begin
      if Mem.Timer /= null then
         RISCV.Timer.Initialize (Mem.Timer.all, Base);
      end if;
   end Enable_Timer;

   procedure Disable_Timer (Mem : in out Memory_Unit) is
   begin
      if Mem.Timer /= null then
         Mem.Timer.Enabled := False;
      end if;
   end Disable_Timer;

   function Timer_Enabled (Mem : Memory_Unit) return Boolean is
   begin
      return Mem.Timer /= null and then Mem.Timer.Enabled;
   end Timer_Enabled;

   procedure Timer_Tick (Mem : in out Memory_Unit) is
   begin
      if Mem.Timer /= null and then Mem.Timer.Enabled then
         RISCV.Timer.Tick (Mem.Timer.all);
      end if;
   end Timer_Tick;

   function Timer_Interrupt_Pending (Mem : Memory_Unit) return Boolean is
   begin
      if Mem.Timer /= null and then Mem.Timer.Enabled then
         return RISCV.Timer.Interrupt_Pending (Mem.Timer.all);
      end if;
      return False;
   end Timer_Interrupt_Pending;

   --  ========================================================================
   --  Watchdog Control
   --  ========================================================================

   procedure Enable_Watchdog (Mem  : in out Memory_Unit;
                              Base : Memory_Address := RISCV.Watchdog.Default_Base_Address) is
   begin
      if Mem.Watchdog = null then
         Mem.Watchdog := new RISCV.Watchdog.Watchdog_State;
      end if;
      RISCV.Watchdog.Initialize (Mem.Watchdog.all, Base);
   end Enable_Watchdog;

   procedure Disable_Watchdog (Mem : in out Memory_Unit) is
   begin
      if Mem.Watchdog /= null then
         Mem.Watchdog.Enabled := False;
      end if;
   end Disable_Watchdog;

   function Watchdog_Enabled (Mem : Memory_Unit) return Boolean is
   begin
      return Mem.Watchdog /= null and then Mem.Watchdog.Enabled;
   end Watchdog_Enabled;

   function Watchdog_Tick (Mem : in out Memory_Unit) return Boolean is
   begin
      if Mem.Watchdog /= null and then Mem.Watchdog.Enabled then
         return RISCV.Watchdog.Tick (Mem.Watchdog.all);
      end if;
      return False;
   end Watchdog_Tick;

   --  ========================================================================
   --  DMA Control
   --  ========================================================================

   procedure Enable_DMA (Mem  : in out Memory_Unit;
                         Base : Memory_Address := RISCV.DMA.Default_Base_Address) is
   begin
      if Mem.DMA = null then
         Mem.DMA := new RISCV.DMA.DMA_State;
      end if;
      RISCV.DMA.Initialize (Mem.DMA.all, Base);
   end Enable_DMA;

   procedure Disable_DMA (Mem : in out Memory_Unit) is
   begin
      if Mem.DMA /= null then
         Mem.DMA.Enabled := False;
      end if;
   end Disable_DMA;

   function DMA_Enabled (Mem : Memory_Unit) return Boolean is
   begin
      return Mem.DMA /= null and then Mem.DMA.Enabled;
   end DMA_Enabled;

   function DMA_Process (Mem : in out Memory_Unit) return Boolean is
      -- Helper procedures for DMA to access memory
      procedure DMA_Read (Addr : Memory_Address; Data : out Byte; Success : out Boolean) is
      begin
         Data := Read_Byte (Mem, Addr);
         Success := Mem.Last_Result = OK;
      end DMA_Read;

      procedure DMA_Write (Addr : Memory_Address; Data : Byte; Success : out Boolean) is
      begin
         Write_Byte (Mem, Addr, Data);
         Success := Mem.Last_Result = OK;
      end DMA_Write;
   begin
      if Mem.DMA /= null and then Mem.DMA.Enabled then
         return RISCV.DMA.Process (Mem.DMA.all, DMA_Read'Access, DMA_Write'Access);
      end if;
      return False;
   end DMA_Process;

   --  ========================================================================
   --  PLIC Control
   --  ========================================================================

   procedure Enable_PLIC (Mem  : in out Memory_Unit;
                           Base : Memory_Address := PLIC.Default_Base_Address) is
   begin
      if Mem.PLIC = null then
         Mem.PLIC := new RISCV.PLIC.PLIC_State;
      end if;
      RISCV.PLIC.Initialize (Mem.PLIC.all, Base);
   end Enable_PLIC;

   procedure Disable_PLIC (Mem : in out Memory_Unit) is
   begin
      if Mem.PLIC /= null then
         Mem.PLIC.Enabled := False;
      end if;
   end Disable_PLIC;

   function PLIC_Enabled (Mem : Memory_Unit) return Boolean is
   begin
      return Mem.PLIC /= null and then Mem.PLIC.Enabled;
   end PLIC_Enabled;

   function PLIC_Update_Mip (Mem : in out Memory_Unit; Mip : Word) return Word is
      use RISCV.PLIC;
      P    : PLIC_State renames Mem.PLIC.all;
      Mip2 : Word := Mip;
   begin
      --  Poll VirtIO interrupt line
      if Mem.VirtIO_Blk /= null and then Mem.VirtIO_Blk.Enabled then
         if (Mem.VirtIO_Blk.InterruptStatus and 1) /= 0 then
            Set_Pending (P, PLIC_SRC_VIRTIO_BLK);
         else
            Clear_Pending (P, PLIC_SRC_VIRTIO_BLK);
         end if;
      end if;

      --  Poll GPIO interrupt line
      if Mem.GPIO /= null and then Mem.GPIO.Enabled then
         if RISCV.GPIO.Interrupt_Pending (Mem.GPIO.all) then
            Set_Pending (P, PLIC_SRC_GPIO);
         else
            Clear_Pending (P, PLIC_SRC_GPIO);
         end if;
      end if;

      --  MEIP: bit 11
      if Interrupt_Pending (P, CTX_M_MODE) then
         Mip2 := Mip2 or 16#800#;
      else
         Mip2 := Mip2 and not 16#800#;
      end if;

      --  SEIP: bit 9
      if Interrupt_Pending (P, CTX_S_MODE) then
         Mip2 := Mip2 or 16#200#;
      else
         Mip2 := Mip2 and not 16#200#;
      end if;

      return Mip2;
   end PLIC_Update_Mip;

   --  ========================================================================
   --  VirtIO Block Control
   --  ========================================================================

   procedure Enable_VirtIO_Block
     (Mem  : in out Memory_Unit;
      Base : Memory_Address := VirtIO_Block.Default_Base_Address) is
   begin
      if Mem.VirtIO_Blk = null then
         Mem.VirtIO_Blk := new RISCV.VirtIO_Block.VirtIO_Block_State;
      end if;
      RISCV.VirtIO_Block.Initialize (Mem.VirtIO_Blk.all, Base);
   end Enable_VirtIO_Block;

   procedure Disable_VirtIO_Block (Mem : in out Memory_Unit) is
   begin
      if Mem.VirtIO_Blk /= null then
         Mem.VirtIO_Blk.Enabled := False;
      end if;
   end Disable_VirtIO_Block;

   function VirtIO_Block_Enabled (Mem : Memory_Unit) return Boolean is
   begin
      return Mem.VirtIO_Blk /= null and then Mem.VirtIO_Blk.Enabled;
   end VirtIO_Block_Enabled;

end RISCV.Memory;
