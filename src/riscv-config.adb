-- ***************************************************************************
--        RISC-V Emulator - Configuration / Hardware Profiles
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

with Ada.Text_IO;
with Ada.Strings.Fixed;
with RISCV.I2C;

package body RISCV.Config is

   --  ========================================================================
   --  Helper Functions
   --  ========================================================================

   function Pad16 (S : String) return String is
      Result : String (1 .. 16) := (others => ' ');
      Len    : constant Natural := Natural'Min (S'Length, 16);
   begin
      Result (1 .. Len) := S (S'First .. S'First + Len - 1);
      return Result;
   end Pad16;

   function Pad32 (S : String) return String is
      Result : String (1 .. 32) := (others => ' ');
      Len    : constant Natural := Natural'Min (S'Length, 32);
   begin
      Result (1 .. Len) := S (S'First .. S'First + Len - 1);
      return Result;
   end Pad32;

   function Trim (S : String) return String is
   begin
      return Ada.Strings.Fixed.Trim (S, Ada.Strings.Both);
   end Trim;

   function Starts_With (S : String; Prefix : String) return Boolean is
   begin
      return S'Length >= Prefix'Length and then
             S (S'First .. S'First + Prefix'Length - 1) = Prefix;
   end Starts_With;

   --  ========================================================================
   --  Built-in Profiles
   --  ========================================================================

   function Profile_Simple return Hardware_Profile is
      P : Hardware_Profile;
   begin
      P.Name := Pad32 ("simple");
      P.Name_Len := 6;
      P.Num_Regions := 1;
      P.Num_Peripherals := 1;

      --  RAM: 1 MB at 0x0
      P.Memory_Regions (1).Name := Pad16 ("ram");
      P.Memory_Regions (1).Base := 0;
      P.Memory_Regions (1).Size := 16#100000#;
      P.Memory_Regions (1).Rtype := Memory.RAM;
      P.Memory_Regions (1).Perm := Memory.Permission_RWX;

      --  Initialize remaining regions
      for I in 2 .. Max_Memory_Regions loop
         P.Memory_Regions (I).Name := (others => ' ');
         P.Memory_Regions (I).Base := 0;
         P.Memory_Regions (I).Size := 0;
         P.Memory_Regions (I).Rtype := Memory.RAM;
         P.Memory_Regions (I).Perm := Memory.Permission_RWX;
      end loop;

      --  UART at 0x10000000
      P.Peripherals (1).Ptype := UART_16550;
      P.Peripherals (1).Base := 16#10000000#;

      --  Initialize remaining peripherals
      for I in 2 .. Max_Peripherals loop
         P.Peripherals (I).Ptype := None;
         P.Peripherals (I).Base := 0;
      end loop;

      --  CPU config
      P.CPU.Reset_Vector := 0;
      P.CPU.Stack_Init := 16#100000#;
      P.CPU.VLEN := 128;

      return P;
   end Profile_Simple;

   function Profile_QEMU_Virt return Hardware_Profile is
      P : Hardware_Profile;
   begin
      P.Name := Pad32 ("qemu-virt");
      P.Name_Len := 9;
      P.Num_Regions := 2;
      P.Num_Peripherals := 10;

      --  RAM: 128 MB at 0x80000000
      P.Memory_Regions (1).Name := Pad16 ("ram");
      P.Memory_Regions (1).Base := 16#80000000#;
      P.Memory_Regions (1).Size := 16#8000000#;
      P.Memory_Regions (1).Rtype := Memory.RAM;
      P.Memory_Regions (1).Perm := Memory.Permission_RWX;

      --  ROM: 64 KB at 0x1000
      P.Memory_Regions (2).Name := Pad16 ("rom");
      P.Memory_Regions (2).Base := 16#00001000#;
      P.Memory_Regions (2).Size := 16#10000#;
      P.Memory_Regions (2).Rtype := Memory.ROM;
      P.Memory_Regions (2).Perm := Memory.Permission_RX;

      --  Initialize remaining regions
      for I in 3 .. Max_Memory_Regions loop
         P.Memory_Regions (I).Name := (others => ' ');
         P.Memory_Regions (I).Base := 0;
         P.Memory_Regions (I).Size := 0;
         P.Memory_Regions (I).Rtype := Memory.RAM;
         P.Memory_Regions (I).Perm := Memory.Permission_RWX;
      end loop;

      --  UART at 0x10000000
      P.Peripherals (1).Ptype := UART_16550;
      P.Peripherals (1).Base := 16#10000000#;

      --  CLINT at 0x02000000
      P.Peripherals (2).Ptype := CLINT;
      P.Peripherals (2).Base := 16#02000000#;

      --  GPIO at 0x10010000
      P.Peripherals (3).Ptype := GPIO;
      P.Peripherals (3).Base := 16#10010000#;

      --  SPI at 0x10020000
      P.Peripherals (4).Ptype := SPI;
      P.Peripherals (4).Base := 16#10020000#;

      --  I2C at 0x10030000
      P.Peripherals (5).Ptype := I2C;
      P.Peripherals (5).Base := 16#10030000#;

      --  Timer at 0x10040000
      P.Peripherals (6).Ptype := Timer;
      P.Peripherals (6).Base := 16#10040000#;

      --  Watchdog at 0x10050000
      P.Peripherals (7).Ptype := Watchdog;
      P.Peripherals (7).Base := 16#10050000#;

      --  DMA at 0x10060000
      P.Peripherals (8).Ptype := DMA;
      P.Peripherals (8).Base := 16#10060000#;

      --  PLIC at 0x0C000000 (standard QEMU virt address)
      P.Peripherals (9).Ptype := PLIC;
      P.Peripherals (9).Base := 16#0C000000#;

      --  VirtIO Block at 0x10001000 (first VirtIO device slot)
      P.Peripherals (10).Ptype := VIRTIO_BLOCK;
      P.Peripherals (10).Base := 16#10001000#;

      --  Initialize remaining peripherals
      for I in P.Num_Peripherals + 1 .. Max_Peripherals loop
         P.Peripherals (I).Ptype := None;
         P.Peripherals (I).Base := 0;
      end loop;

      --  CPU config
      P.CPU.Reset_Vector := 16#80000000#;
      P.CPU.Stack_Init := 16#88000000#;
      P.CPU.VLEN := 128;

      return P;
   end Profile_QEMU_Virt;

   --  ========================================================================
   --  Apply Profile
   --  ========================================================================

   procedure Apply_Profile (Profile : Hardware_Profile;
                            Mem     : in out Memory.Memory_Unit) is
   begin
      --  Initialize memory in region mode
      Memory.Initialize_Empty (Mem);

      --  Add memory regions
      for I in 1 .. Profile.Num_Regions loop
         declare
            R : Memory_Region_Config renames Profile.Memory_Regions (I);
         begin
            Memory.Add_Region (Mem,
                               Name  => Trim (R.Name),
                               Base  => R.Base,
                               Size  => R.Size,
                               Rtype => R.Rtype,
                               Perm  => R.Perm);
         end;
      end loop;

      --  Configure peripherals
      for I in 1 .. Profile.Num_Peripherals loop
         declare
            P : Peripheral_Config renames Profile.Peripherals (I);
         begin
            case P.Ptype is
               when UART_16550 =>
                  Memory.Enable_UART (Mem, P.Base);
               when CLINT =>
                  Memory.Enable_CLINT (Mem, P.Base);
               when GPIO =>
                  Memory.Enable_GPIO (Mem, P.Base);
               when SPI =>
                  Memory.Enable_SPI (Mem, P.Base);
               when I2C =>
                  Memory.Enable_I2C (Mem, P.Base);
                  -- Add simulated I2C devices for testing
                  Memory.I2C_Add_Device (Mem, RISCV.I2C.Temperature_Sensor, 16#48#);
                  Memory.I2C_Add_Device (Mem, RISCV.I2C.Accelerometer, 16#1D#);
                  Memory.I2C_Add_Device (Mem, RISCV.I2C.EEPROM_256, 16#50#);
               when Timer =>
                  Memory.Enable_Timer (Mem, P.Base);
               when Watchdog =>
                  Memory.Enable_Watchdog (Mem, P.Base);
               when DMA =>
                  Memory.Enable_DMA (Mem, P.Base);
               when PLIC =>
                  Memory.Enable_PLIC (Mem, P.Base);
               when VIRTIO_BLOCK =>
                  Memory.Enable_VirtIO_Block (Mem, P.Base);
               when None =>
                  null;
            end case;
         end;
      end loop;
   end Apply_Profile;

   --  ========================================================================
   --  Get Profile by Name
   --  ========================================================================

   function Get_Profile (Name : String) return Hardware_Profile is
      Lower_Name : String := Name;
   begin
      --  Convert to lowercase for comparison
      for I in Lower_Name'Range loop
         if Lower_Name (I) in 'A' .. 'Z' then
            Lower_Name (I) :=
               Character'Val (Character'Pos (Lower_Name (I)) + 32);
         end if;
      end loop;

      if Lower_Name = "simple" then
         return Profile_Simple;
      elsif Lower_Name = "qemu-virt" or Lower_Name = "qemu_virt" then
         return Profile_QEMU_Virt;
      else
         --  Default to simple
         return Profile_Simple;
      end if;
   end Get_Profile;

   --  ========================================================================
   --  Load Profile from File
   --  ========================================================================

   procedure Load_Profile (Filename : String;
                           Profile  : out Hardware_Profile;
                           Success  : out Boolean) is
      use Ada.Text_IO;
      File : File_Type;
      Line : String (1 .. 256);
      Last : Natural;

      Current_Section : String (1 .. 32) := (others => ' ');
      Region_Idx      : Natural := 0;
      Periph_Idx      : Natural := 0;

      --  Parse hex or decimal number
      function Parse_Number (S : String) return Word is
         Trimmed : constant String := Trim (S);
      begin
         if Trimmed'Length > 2 and then
            (Trimmed (Trimmed'First .. Trimmed'First + 1) = "0x" or
             Trimmed (Trimmed'First .. Trimmed'First + 1) = "0X")
         then
            --  Hex number
            return Word'Value ("16#" &
               Trimmed (Trimmed'First + 2 .. Trimmed'Last) & "#");
         else
            --  Decimal
            return Word'Value (Trimmed);
         end if;
      exception
         when others => return 0;
      end Parse_Number;

      --  Parse a single line
      procedure Parse_Line (L : String) is
         Trimmed : constant String := Trim (L);
         Eq_Pos  : Natural := 0;
         Key     : String (1 .. 64) := (others => ' ');
         Value   : String (1 .. 128) := (others => ' ');
         Key_Len : Natural := 0;
         Val_Len : Natural := 0;
      begin
         --  Skip empty lines and comments
         if Trimmed'Length = 0 or else Trimmed (Trimmed'First) = '#' then
            return;
         end if;

         --  Check for section header [section]
         if Trimmed (Trimmed'First) = '[' then
            for I in Trimmed'Range loop
               if Trimmed (I) = ']' then
                  Current_Section := Pad32 (Trimmed (Trimmed'First + 1 .. I - 1));
                  exit;
               end if;
            end loop;
            return;
         end if;

         --  Find = sign
         for I in Trimmed'Range loop
            if Trimmed (I) = '=' then
               Eq_Pos := I;
               exit;
            end if;
         end loop;

         if Eq_Pos = 0 then
            return;  --  No key=value
         end if;

         --  Extract key and value
         declare
            Key_Str : constant String :=
               Trim (Trimmed (Trimmed'First .. Eq_Pos - 1));
            Val_Str : constant String :=
               Trim (Trimmed (Eq_Pos + 1 .. Trimmed'Last));
         begin
            Key_Len := Natural'Min (Key_Str'Length, 64);
            Key (1 .. Key_Len) := Key_Str;

            Val_Len := Natural'Min (Val_Str'Length, 128);
            Value (1 .. Val_Len) := Val_Str;
         end;

         --  Handle based on current section
         declare
            Sec : constant String := Trim (Current_Section);
         begin
            if Sec = "profile" then
               if Starts_With (Key, "name") then
                  Profile.Name := Pad32 (Trim (Value (1 .. Val_Len)));
                  Profile.Name_Len := Val_Len;
               end if;

            elsif Starts_With (Sec, "memory.") then
               --  Memory region section
               declare
                  Region_Name : constant String :=
                     Sec (Sec'First + 7 .. Sec'Last);
               begin
                  --  Find or create region entry
                  if Key_Len > 0 and then Key (1 .. 4) = "base" and then
                     Region_Idx < Max_Memory_Regions
                  then
                     Region_Idx := Region_Idx + 1;
                     Profile.Memory_Regions (Region_Idx).Name :=
                        Pad16 (Region_Name);
                     Profile.Memory_Regions (Region_Idx).Base :=
                        Memory_Address (Parse_Number (Value (1 .. Val_Len)));
                  elsif Key_Len > 0 and then Key (1 .. 4) = "size" and then
                        Region_Idx > 0
                  then
                     Profile.Memory_Regions (Region_Idx).Size :=
                        Parse_Number (Value (1 .. Val_Len));
                  elsif Key_Len > 0 and then Key (1 .. 4) = "type" and then
                        Region_Idx > 0
                  then
                     declare
                        V : constant String := Trim (Value (1 .. Val_Len));
                     begin
                        if V = "ram" then
                           Profile.Memory_Regions (Region_Idx).Rtype :=
                              Memory.RAM;
                        elsif V = "rom" then
                           Profile.Memory_Regions (Region_Idx).Rtype :=
                              Memory.ROM;
                        elsif V = "flash" then
                           Profile.Memory_Regions (Region_Idx).Rtype :=
                              Memory.Flash;
                        end if;
                     end;
                  end if;
               end;

            elsif Starts_With (Sec, "peripheral.") then
               --  Peripheral section
               if Key_Len > 0 and then Key (1 .. 4) = "type" and then
                  Periph_Idx < Max_Peripherals
               then
                  Periph_Idx := Periph_Idx + 1;
                  declare
                     V : constant String := Trim (Value (1 .. Val_Len));
                  begin
                     if V = "uart16550" or V = "uart" then
                        Profile.Peripherals (Periph_Idx).Ptype := UART_16550;
                     elsif V = "clint" then
                        Profile.Peripherals (Periph_Idx).Ptype := CLINT;
                     elsif V = "gpio" then
                        Profile.Peripherals (Periph_Idx).Ptype := GPIO;
                     end if;
                  end;
               elsif Key_Len > 0 and then Key (1 .. 4) = "base" and then
                     Periph_Idx > 0
               then
                  Profile.Peripherals (Periph_Idx).Base :=
                     Memory_Address (Parse_Number (Value (1 .. Val_Len)));
               end if;

            elsif Sec = "cpu" then
               if Starts_With (Key, "reset") then
                  Profile.CPU.Reset_Vector :=
                     Memory_Address (Parse_Number (Value (1 .. Val_Len)));
               elsif Starts_With (Key, "stack") then
                  Profile.CPU.Stack_Init :=
                     Memory_Address (Parse_Number (Value (1 .. Val_Len)));
               elsif Starts_With (Key, "vlen") then
                  Profile.CPU.VLEN :=
                     Natural (Parse_Number (Value (1 .. Val_Len)));
               end if;
            end if;
         end;
      end Parse_Line;

   begin
      Success := False;

      --  Initialize with defaults
      Profile := Profile_Simple;
      Profile.Num_Regions := 0;
      Profile.Num_Peripherals := 0;

      Open (File, In_File, Filename);

      while not End_Of_File (File) loop
         Get_Line (File, Line, Last);
         Parse_Line (Line (1 .. Last));
      end loop;

      Close (File);

      --  Set final counts
      Profile.Num_Regions := Region_Idx;
      Profile.Num_Peripherals := Periph_Idx;

      Success := True;

   exception
      when others =>
         if Is_Open (File) then
            Close (File);
         end if;
         Success := False;
   end Load_Profile;

end RISCV.Config;
