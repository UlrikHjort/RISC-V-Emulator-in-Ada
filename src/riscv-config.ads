-- ***************************************************************************
--         RISC-V Emulator - Configuration / Hardware Profiles
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

with RISCV.Memory;

package RISCV.Config is

   --  ========================================================================
   --  Memory Region Configuration
   --  ========================================================================

   type Memory_Region_Config is record
      Name   : String (1 .. 16);
      Base   : Memory_Address;
      Size   : Word;
      Rtype  : Memory.Region_Type;
      Perm   : Memory.Access_Permission;
   end record;

   Max_Memory_Regions : constant := 8;
   type Memory_Region_Config_Array is
      array (1 .. Max_Memory_Regions) of Memory_Region_Config;

   --  ========================================================================
   --  Peripheral Configuration
   --  ========================================================================

   type Peripheral_Type is (None, UART_16550, CLINT, PLIC, GPIO, SPI, I2C, Timer, Watchdog, DMA,
                            VIRTIO_BLOCK);

   type Peripheral_Config is record
      Ptype : Peripheral_Type;
      Base  : Memory_Address;
   end record;

   Max_Peripherals : constant := 10;
   type Peripheral_Config_Array is
      array (1 .. Max_Peripherals) of Peripheral_Config;

   --  ========================================================================
   --  CPU Configuration
   --  ========================================================================

   type CPU_Config is record
      Reset_Vector : Memory_Address;  --  Initial PC value
      Stack_Init   : Memory_Address;  --  Initial SP value (0 = don't set)
      VLEN         : Natural;         --  Vector register length in bits
   end record;

   --  ========================================================================
   --  Hardware Profile
   --  ========================================================================

   type Hardware_Profile is record
      Name             : String (1 .. 32);
      Name_Len         : Natural;

      --  Memory configuration
      Memory_Regions   : Memory_Region_Config_Array;
      Num_Regions      : Natural;

      --  Peripheral configuration
      Peripherals      : Peripheral_Config_Array;
      Num_Peripherals  : Natural;

      --  CPU configuration
      CPU              : CPU_Config;
   end record;

   --  ========================================================================
   --  Built-in Profiles (functions to avoid elaboration issues)
   --  ========================================================================

   --  Simple: Current default behavior (flat 1MB at 0x0)
   function Profile_Simple return Hardware_Profile;

   --  QEMU virt machine compatible
   function Profile_QEMU_Virt return Hardware_Profile;

   --  ========================================================================
   --  Profile Operations
   --  ========================================================================

   --  Apply profile to memory system
   procedure Apply_Profile (Profile : Hardware_Profile;
                            Mem     : in out Memory.Memory_Unit);

   --  Get profile by name (returns Profile_Simple if not found)
   function Get_Profile (Name : String) return Hardware_Profile;

   --  Load profile from file
   procedure Load_Profile (Filename : String;
                           Profile  : out Hardware_Profile;
                           Success  : out Boolean);

end RISCV.Config;
