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

with Ada.Streams.Stream_IO;
with Ada.Text_IO;
with RISCV.UART;
with RISCV.CLINT;
with RISCV.GPIO;
with RISCV.SPI;
with RISCV.I2C;
with RISCV.Timer;
with RISCV.Watchdog;
with RISCV.DMA;
with RISCV.PLIC;
with RISCV.VirtIO_Block;

package RISCV.Memory is

   --  ========================================================================
   --  Memory Region Types
   --  ========================================================================

   --  Memory region type
   type Region_Type is (RAM, ROM, Flash, IO);

   --  Access permissions
   type Access_Permission is record
      Read    : Boolean := True;
      Write   : Boolean := True;
      Execute : Boolean := True;
   end record;

   Permission_RWX : constant Access_Permission := (True, True, True);
   Permission_RW  : constant Access_Permission := (True, True, False);
   Permission_RX  : constant Access_Permission := (True, False, True);
   Permission_RO  : constant Access_Permission := (True, False, False);

   --  Maximum bytes in a single region (256 MB)
   Max_Region_Size : constant := 256 * 1024 * 1024;

   --  Raw memory array for a region
   type Region_Data is array (Natural range <>) of Byte;
   type Region_Data_Access is access Region_Data;

   --  Memory region descriptor
   type Memory_Region is record
      Name       : String (1 .. 16);  --  Region name (padded with spaces)
      Name_Len   : Natural;           --  Actual name length
      Base       : Memory_Address;    --  Start address
      Size       : Word;              --  Size in bytes
      Rtype      : Region_Type;       --  RAM, ROM, Flash, IO
      Perm       : Access_Permission; --  Read/Write/Execute permissions
      Data       : Region_Data_Access; --  Actual memory data
   end record;

   --  Named access type for the host log file (avoids anonymous-allocator warning)
   type Log_File_Access is access Ada.Text_IO.File_Type;

   --  Maximum number of memory regions
   Max_Regions : constant := 16;

   type Region_Index is range 0 .. Max_Regions - 1;
   type Region_Array is array (Region_Index) of Memory_Region;

   --  ========================================================================
   --  Memory Access Result
   --  ========================================================================

   type Access_Result is (OK, Unmapped, Permission_Error, Alignment_Error);

   --  ========================================================================
   --  Legacy types for backward compatibility
   --  ========================================================================

   type Memory_Array is array (0 .. Memory_Size - 1) of Byte;
   type Memory_Access is access Memory_Array;
   type UART_Access is access RISCV.UART.UART_State;
   type CLINT_Access is access RISCV.CLINT.CLINT_State;
   type GPIO_Access is access RISCV.GPIO.GPIO_State;
   type SPI_Access is access RISCV.SPI.SPI_State;
   type I2C_Access is access RISCV.I2C.I2C_State;
   type Timer_Access is access RISCV.Timer.Timer_State;
   type Watchdog_Access is access RISCV.Watchdog.Watchdog_State;
   type DMA_Access is access RISCV.DMA.DMA_State;
   type PLIC_Access is access RISCV.PLIC.PLIC_State;
   type VirtIO_Block_Access is access RISCV.VirtIO_Block.VirtIO_Block_State;

   --  ========================================================================
   --  Semihosting File I/O (ECALLs 0x505-0x50C)
   --  ========================================================================

   Max_SH_Files : constant := 16;
   type SH_File_Index is range 0 .. Max_SH_Files - 1;
   type SH_File_Type_Acc  is access Ada.Streams.Stream_IO.File_Type;
   type SH_File_Array     is array (SH_File_Index) of SH_File_Type_Acc;
   type SH_File_Open_Array is array (SH_File_Index) of Boolean;

   --  ========================================================================
   --  Memory Unit (main memory system)
   --  ========================================================================

   --  Memory access callback for watchpoints
   type Memory_Access_Callback is access procedure (
      Address  : Memory_Address;
      Is_Write : Boolean
   );

   type Memory_Unit is record
      --  Region-based memory
      Regions      : Region_Array;
      Region_Count : Natural := 0;

      --  Legacy flat memory (for backward compatibility)
      Data         : Memory_Access;
      Use_Regions  : Boolean := False;

      --  Peripherals
      UART         : UART_Access;
      CLINT        : CLINT_Access;
      GPIO         : GPIO_Access;
      SPI          : SPI_Access;
      I2C          : I2C_Access;
      Timer        : Timer_Access;
      Watchdog     : Watchdog_Access;
      DMA          : DMA_Access;
      PLIC         : PLIC_Access;
      VirtIO_Blk   : VirtIO_Block_Access;

      --  Host log file (for semihosting-style logging from emulated programs)
      Log_File      : Log_File_Access := null;
      Log_File_Open : Boolean := False;

      --  Optional directory prefix for semihosting log files (--log-dir)
      Log_Dir     : String (1 .. 256) := (others => ' ');
      Log_Dir_Len : Natural := 0;

      --  Access status (set after each operation)
      Last_Result  : Access_Result := OK;

      --  Watchpoint callback (for debugger)
      Access_Hook  : Memory_Access_Callback := null;

      --  Track last memory access (for watchpoints)
      Track_Access      : Boolean := False;
      Last_Access_Addr  : Memory_Address := 0;
      Last_Access_Write : Boolean := False;
      Access_Occurred   : Boolean := False;
      Last_Access_Valid : Boolean := False;  --  True if data access occurred this step

      --  Semihosting file I/O (ECALLs 0x505-0x50C)
      SH_Files     : SH_File_Array      := (others => null);
      SH_File_Open : SH_File_Open_Array := (others => False);

      --  HTIF tohost termination (riscv-tests), enabled by --htif.
      --  When a store hits Tohost_Addr, the written value is latched and
      --  Tohost_Written is set; Step then halts. Value 1 = pass, otherwise
      --  the failing test number is (Value >> 1).
      HTIF_Enabled   : Boolean := False;

      --  SBI shim for supervisor-mode ECALLs. On by default so S-mode
      --  guests get a firmware to call; clear it to make an S-mode ECALL
      --  trap as the privileged spec defines, which is what the trap
      --  routing and delegation tests need to observe.
      SBI_Enabled    : Boolean := True;
      Tohost_Addr    : Memory_Address := 0;
      Tohost_Value   : Word := 0;
      Tohost_Written : Boolean := False;
   end record;

   --  ========================================================================
   --  Initialization
   --  ========================================================================

   --  Initialize with legacy flat memory (backward compatible)
   procedure Initialize (Mem : out Memory_Unit);

   --  Initialize with no memory (regions must be added)
   procedure Initialize_Empty (Mem : out Memory_Unit);

   --  Free memory
   procedure Finalize (Mem : in out Memory_Unit);

   --  ========================================================================
   --  Region Management
   --  ========================================================================

   --  Add a memory region
   procedure Add_Region (Mem    : in out Memory_Unit;
                         Name   : String;
                         Base   : Memory_Address;
                         Size   : Word;
                         Rtype  : Region_Type := RAM;
                         Perm   : Access_Permission := Permission_RWX);

   --  Find region containing address (returns Region_Count if not found)
   function Find_Region (Mem     : Memory_Unit;
                         Address : Memory_Address) return Natural;

   --  Check if address is in any region
   function Is_Mapped (Mem : Memory_Unit; Address : Memory_Address) return Boolean;

   --  ========================================================================
   --  Memory Operations
   --  ========================================================================

   --  Load binary file into memory at specified address
   procedure Load_Binary (Mem      : in out Memory_Unit;
                          Filename : String;
                          Address  : Memory_Address;
                          Success  : out Boolean);

   --  Read operations
   function Read_Byte (Mem     : in out Memory_Unit;
                       Address : Memory_Address) return Byte;

   function Read_Half_Word (Mem     : in out Memory_Unit;
                            Address : Memory_Address) return Half_Word;

   function Read_Word (Mem     : in out Memory_Unit;
                       Address : Memory_Address) return Word;

   --  Write operations
   procedure Write_Byte (Mem     : in out Memory_Unit;
                         Address : Memory_Address;
                         Value   : Byte);

   procedure Write_Half_Word (Mem     : in out Memory_Unit;
                              Address : Memory_Address;
                              Value   : Half_Word);

   procedure Write_Word (Mem     : in out Memory_Unit;
                         Address : Memory_Address;
                         Value   : Word);

   --  Check if address is valid (legacy - checks flat memory)
   function Is_Valid_Address (Address : Memory_Address) return Boolean;

   --  Check last operation result
   function Last_Access_Result (Mem : Memory_Unit) return Access_Result;

   --  ========================================================================
   --  UART Control
   --  ========================================================================

   procedure Enable_UART (Mem  : in out Memory_Unit;
                          Base : Memory_Address := UART.Default_Base_Address);

   procedure Disable_UART (Mem : in out Memory_Unit);

   function UART_Enabled (Mem : Memory_Unit) return Boolean;

   procedure UART_Add_Input (Mem : in out Memory_Unit; Data : Byte);
   procedure UART_Add_Input_String (Mem : in out Memory_Unit; Str : String);

   --  ========================================================================
   --  CLINT Control
   --  ========================================================================

   procedure Enable_CLINT (Mem  : in out Memory_Unit;
                           Base : Memory_Address := CLINT.Default_Base_Address);

   procedure Disable_CLINT (Mem : in out Memory_Unit);

   function CLINT_Enabled (Mem : Memory_Unit) return Boolean;

   --  Advance CLINT timer by one tick (call once per instruction)
   procedure CLINT_Tick (Mem : in out Memory_Unit);

   --  Check if timer interrupt is pending (for specified hart, default hart 0)
   function CLINT_Timer_Interrupt_Pending (Mem  : Memory_Unit;
                                           Hart : Natural := 0) return Boolean;

   --  Check if software interrupt is pending (for specified hart, default hart 0)
   function CLINT_Software_Interrupt_Pending (Mem  : Memory_Unit;
                                              Hart : Natural := 0) return Boolean;

   --  Clear timer interrupt (for specified hart, default hart 0)
   procedure CLINT_Clear_Timer (Mem  : in out Memory_Unit;
                                Hart : Natural := 0);

   --  ========================================================================
   --  GPIO Control
   --  ========================================================================

   procedure Enable_GPIO (Mem  : in out Memory_Unit;
                          Base : Memory_Address := GPIO.Default_Base_Address);

   procedure Disable_GPIO (Mem : in out Memory_Unit);

   function GPIO_Enabled (Mem : Memory_Unit) return Boolean;

   --  Set external input values (simulates external signals)
   procedure GPIO_Set_External_Input (Mem   : in out Memory_Unit;
                                      Value : Word);

   --  Get current output values
   function GPIO_Get_Output (Mem : Memory_Unit) return Word;

   --  Check if GPIO interrupt is pending
   function GPIO_Interrupt_Pending (Mem : Memory_Unit) return Boolean;

   --  Update GPIO state (call periodically for edge detection)
   procedure GPIO_Update (Mem : in out Memory_Unit);

   --  ========================================================================
   --  SPI Control
   --  ========================================================================

   procedure Enable_SPI (Mem  : in out Memory_Unit;
                         Base : Memory_Address := SPI.Default_Base_Address);

   procedure Disable_SPI (Mem : in out Memory_Unit);

   function SPI_Enabled (Mem : Memory_Unit) return Boolean;

   --  Direct flash access for testing
   function SPI_Get_Flash (Mem : Memory_Unit) return SPI.Flash_Memory_Access;

   --  ========================================================================
   --  I2C Control
   --  ========================================================================

   procedure Enable_I2C (Mem  : in out Memory_Unit;
                         Base : Memory_Address := I2C.Default_Base_Address);

   procedure Disable_I2C (Mem : in out Memory_Unit);

   function I2C_Enabled (Mem : Memory_Unit) return Boolean;

   --  Add virtual I2C devices
   procedure I2C_Add_Device (Mem         : in out Memory_Unit;
                             Device_Type : I2C.I2C_Device_Type;
                             Address     : Byte);

   --  ========================================================================
   --  Timer Control
   --  ========================================================================

   procedure Enable_Timer (Mem  : in out Memory_Unit;
                           Base : Memory_Address := Timer.Default_Base_Address);

   procedure Disable_Timer (Mem : in out Memory_Unit);

   function Timer_Enabled (Mem : Memory_Unit) return Boolean;

   --  Update timer state (call once per instruction or periodically)
   procedure Timer_Tick (Mem : in out Memory_Unit);

   --  Check if timer interrupt is pending
   function Timer_Interrupt_Pending (Mem : Memory_Unit) return Boolean;

   --  ========================================================================
   --  Watchdog Control
   --  ========================================================================

   procedure Enable_Watchdog (Mem  : in out Memory_Unit;
                              Base : Memory_Address := Watchdog.Default_Base_Address);

   procedure Disable_Watchdog (Mem : in out Memory_Unit);

   function Watchdog_Enabled (Mem : Memory_Unit) return Boolean;

   --  Update watchdog state (call once per instruction)
   --  Returns True if watchdog timeout occurred (system should reset)
   function Watchdog_Tick (Mem : in out Memory_Unit) return Boolean;

   --  ========================================================================
   --  DMA Control
   --  ========================================================================

   procedure Enable_DMA (Mem  : in out Memory_Unit;
                         Base : Memory_Address := DMA.Default_Base_Address);

   procedure Disable_DMA (Mem : in out Memory_Unit);

   function DMA_Enabled (Mem : Memory_Unit) return Boolean;

   --  Process DMA transfers (call periodically)
   --  Returns True if any channel completed a transfer
   function DMA_Process (Mem : in out Memory_Unit) return Boolean;

   --  ========================================================================
   --  PLIC Control
   --  ========================================================================

   procedure Enable_PLIC (Mem  : in out Memory_Unit;
                           Base : Memory_Address := PLIC.Default_Base_Address);

   procedure Disable_PLIC (Mem : in out Memory_Unit);

   function PLIC_Enabled (Mem : Memory_Unit) return Boolean;

   --  Update MIP MEIP/SEIP bits from PLIC state; returns updated MIP (low 32 bits)
   function PLIC_Update_Mip (Mem : in out Memory_Unit; Mip : Word) return Word;

   --  ========================================================================
   --  VirtIO Block Control
   --  ========================================================================

   procedure Enable_VirtIO_Block
     (Mem  : in out Memory_Unit;
      Base : Memory_Address := VirtIO_Block.Default_Base_Address);

   procedure Disable_VirtIO_Block (Mem : in out Memory_Unit);

   function VirtIO_Block_Enabled (Mem : Memory_Unit) return Boolean;

end RISCV.Memory;
