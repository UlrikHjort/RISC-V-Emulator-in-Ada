-- ***************************************************************************
--                      RISCV_Emulator - Peripheral Tests
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
with Interfaces;  use Interfaces;
with RISCV;       use RISCV;
with RISCV.CLINT;
with RISCV.GPIO;
with RISCV.Memory; use RISCV.Memory;
with RISCV.Config;

procedure Test_Peripherals is

   Test_Count  : Natural := 0;
   Pass_Count  : Natural := 0;
   Fail_Count  : Natural := 0;

   procedure Check (Condition : Boolean; Name : String) is
   begin
      Test_Count := Test_Count + 1;
      if Condition then
         Pass_Count := Pass_Count + 1;
         Put_Line ("  PASS: " & Name);
      else
         Fail_Count := Fail_Count + 1;
         Put_Line ("  FAIL: " & Name);
      end if;
   end Check;

   --  ========================================================================
   --  CLINT Tests
   --  ========================================================================

   procedure Test_CLINT is
      C : RISCV.CLINT.CLINT_State;
   begin
      Put_Line ("Testing CLINT peripheral...");

      --  Initialize CLINT
      RISCV.CLINT.Initialize (C);

      Check (RISCV.CLINT.Is_CLINT_Address (C, 16#0200_0000#),
             "CLINT address in range (base)");
      Check (RISCV.CLINT.Is_CLINT_Address (C, 16#0200_FFFF#),
             "CLINT address in range (end)");
      Check (not RISCV.CLINT.Is_CLINT_Address (C, 16#0201_0000#),
             "CLINT address out of range");

      --  Test timer initialization
      Check (RISCV.CLINT.Get_Mtime (C) = 0,
             "Initial mtime is 0");
      Check (not RISCV.CLINT.Timer_Interrupt_Pending (C),
             "No timer interrupt initially");

      --  Test timer tick
      RISCV.CLINT.Tick (C);
      Check (RISCV.CLINT.Get_Mtime (C) = 1,
             "Mtime increments with tick");

      RISCV.CLINT.Tick_N (C, 99);
      Check (RISCV.CLINT.Get_Mtime (C) = 100,
             "Mtime increments correctly with Tick_N");

      --  Test mtimecmp and interrupt generation
      --  Write both words of mtimecmp (64-bit register)
      RISCV.CLINT.Write_Word (C, 16#0200_4000#, 50);   --  Low word
      RISCV.CLINT.Write_Word (C, 16#0200_4004#, 0);    --  High word = 0
      Check (RISCV.CLINT.Timer_Interrupt_Pending (C),
             "Timer interrupt when mtime >= mtimecmp");

      --  Clear by setting mtimecmp higher
      RISCV.CLINT.Write_Word (C, 16#0200_4000#, 200);
      Check (not RISCV.CLINT.Timer_Interrupt_Pending (C),
             "No timer interrupt when mtimecmp > mtime");

      --  Test software interrupt
      Check (not RISCV.CLINT.Software_Interrupt_Pending (C),
             "No software interrupt initially");

      RISCV.CLINT.Write_Word (C, 16#0200_0000#, 1);
      Check (RISCV.CLINT.Software_Interrupt_Pending (C),
             "Software interrupt when msip=1");

      RISCV.CLINT.Write_Word (C, 16#0200_0000#, 0);
      Check (not RISCV.CLINT.Software_Interrupt_Pending (C),
             "No software interrupt when msip=0");

      --  Test reading registers
      declare
         Val : constant Word := RISCV.CLINT.Read_Word (C, 16#0200_BFF8#);
      begin
         Check (Val = 100, "Read mtime returns correct value");
      end;

      Put_Line ("");
   end Test_CLINT;

   --  ========================================================================
   --  GPIO Tests
   --  ========================================================================

   procedure Test_GPIO is
      G : RISCV.GPIO.GPIO_State;
   begin
      Put_Line ("Testing GPIO peripheral...");

      --  Initialize GPIO
      RISCV.GPIO.Initialize (G);

      Check (RISCV.GPIO.Is_GPIO_Address (G, 16#1001_0000#),
             "GPIO address in range (base)");
      Check (RISCV.GPIO.Is_GPIO_Address (G, 16#1001_001F#),
             "GPIO address in range (end)");
      Check (not RISCV.GPIO.Is_GPIO_Address (G, 16#1001_0020#),
             "GPIO address out of range");

      --  Test output register
      RISCV.GPIO.Write_Word (G, 16#1001_0004#, 16#ABCD_1234#);
      Check (RISCV.GPIO.Get_Output (G) = 16#ABCD_1234#,
             "Output register write/read");

      --  Test direction register (set all as output)
      RISCV.GPIO.Write_Word (G, 16#1001_0008#, 16#FFFF_FFFF#);

      --  Read input should reflect output when direction is output
      declare
         Input_Val : constant Word := RISCV.GPIO.Read_Word (G, 16#1001_0000#);
      begin
         Check (Input_Val = 16#ABCD_1234#,
                "Input reflects output for output pins");
      end;

      --  Test single pin operations
      RISCV.GPIO.Write_Word (G, 16#1001_0004#, 0);  --  Clear output
      Check (not RISCV.GPIO.Get_Output_Pin (G, 0),
             "Output pin 0 is low");

      RISCV.GPIO.Write_Word (G, 16#1001_0004#, 1);
      Check (RISCV.GPIO.Get_Output_Pin (G, 0),
             "Output pin 0 is high");

      --  Test external input
      RISCV.GPIO.Write_Word (G, 16#1001_0008#, 0);  --  All inputs
      RISCV.GPIO.Set_External_Input (G, 16#5555_AAAA#);

      declare
         Input_Val : constant Word := RISCV.GPIO.Read_Word (G, 16#1001_0000#);
      begin
         Check (Input_Val = 16#5555_AAAA#,
                "External input read correctly");
      end;

      --  Test interrupt flags (edge detection)
      RISCV.GPIO.Write_Word (G, 16#1001_000C#, 16#0000_000F#);  --  Enable int pin 0-3
      RISCV.GPIO.Write_Word (G, 16#1001_0014#, 16#0000_000F#);  --  Edge triggered

      RISCV.GPIO.Set_External_Input (G, 0);
      RISCV.GPIO.Update (G);
      RISCV.GPIO.Set_External_Input (G, 16#0000_0001#);  --  Rising edge on pin 0
      RISCV.GPIO.Update (G);

      Check (RISCV.GPIO.Interrupt_Pending (G),
             "Edge-triggered interrupt detected");

      --  Clear interrupt flag
      RISCV.GPIO.Write_Word (G, 16#1001_0010#, 16#FFFF_FFFF#);
      Check (not RISCV.GPIO.Interrupt_Pending (G),
             "Interrupt cleared after write-1-to-clear");

      Put_Line ("");
   end Test_GPIO;

   --  ========================================================================
   --  Memory System Integration Tests
   --  ========================================================================

   procedure Test_Memory_Integration is
      Mem : RISCV.Memory.Memory_Unit;
   begin
      Put_Line ("Testing memory system integration...");

      --  Initialize with empty memory and add regions
      RISCV.Memory.Initialize_Empty (Mem);
      RISCV.Memory.Add_Region (Mem, "ram", 16#8000_0000#, 16#1000#);

      --  Enable peripherals
      RISCV.Memory.Enable_UART (Mem, 16#1000_0000#);
      RISCV.Memory.Enable_CLINT (Mem, 16#0200_0000#);
      RISCV.Memory.Enable_GPIO (Mem, 16#1001_0000#);

      Check (RISCV.Memory.UART_Enabled (Mem), "UART enabled");
      Check (RISCV.Memory.CLINT_Enabled (Mem), "CLINT enabled");
      Check (RISCV.Memory.GPIO_Enabled (Mem), "GPIO enabled");

      --  Test memory access
      RISCV.Memory.Write_Word (Mem, 16#8000_0000#, 16#DEAD_BEEF#);
      Check (RISCV.Memory.Read_Word (Mem, 16#8000_0000#) = 16#DEAD_BEEF#,
             "RAM read/write works");

      --  Test CLINT access through memory
      RISCV.Memory.Write_Word (Mem, 16#0200_0000#, 1);  --  Set MSIP
      Check (RISCV.Memory.CLINT_Software_Interrupt_Pending (Mem),
             "CLINT access through memory system");

      --  Test GPIO access through memory
      RISCV.Memory.Write_Word (Mem, 16#1001_0004#, 16#1234#);  --  Output register
      Check (RISCV.Memory.GPIO_Get_Output (Mem) = 16#1234#,
             "GPIO access through memory system");

      --  Test unmapped access
      declare
         Dummy : Word;
      begin
         Dummy := RISCV.Memory.Read_Word (Mem, 16#FFFF_0000#);
         Check (RISCV.Memory.Last_Access_Result (Mem) =
                RISCV.Memory.Unmapped,
                "Unmapped read returns error");
      end;

      RISCV.Memory.Finalize (Mem);
      Put_Line ("");
   end Test_Memory_Integration;

   --  ========================================================================
   --  Config Profile Tests
   --  ========================================================================

   procedure Test_Config_Profile is
      Prof : RISCV.Config.Hardware_Profile;
      Mem  : RISCV.Memory.Memory_Unit;
   begin
      Put_Line ("Testing config profiles...");

      --  Test simple profile
      Prof := RISCV.Config.Profile_Simple;
      Check (Prof.Num_Regions = 1, "Simple profile has 1 region");
      Check (Prof.Num_Peripherals = 1, "Simple profile has 1 peripheral");
      Check (Prof.CPU.Reset_Vector = 0, "Simple profile reset at 0");

      --  Test qemu-virt profile
      Prof := RISCV.Config.Profile_QEMU_Virt;
      Check (Prof.Num_Regions = 2, "QEMU-virt profile has 2 regions");
      --  UART, CLINT, GPIO, SPI, I2C, Timer, Watchdog, DMA, PLIC, VirtIO
      Check (Prof.Num_Peripherals = 10,
             "QEMU-virt profile has 10 peripherals");
      Check (Prof.CPU.Reset_Vector = 16#8000_0000#,
             "QEMU-virt reset at 0x80000000");

      --  Test profile lookup
      Prof := RISCV.Config.Get_Profile ("simple");
      Check (Prof.CPU.Reset_Vector = 0, "Get_Profile finds 'simple'");

      Prof := RISCV.Config.Get_Profile ("qemu-virt");
      Check (Prof.CPU.Reset_Vector = 16#8000_0000#,
             "Get_Profile finds 'qemu-virt'");

      Prof := RISCV.Config.Get_Profile ("nonexistent");
      Check (Prof.CPU.Reset_Vector = 0,
             "Get_Profile defaults to simple for unknown");

      --  Test apply profile
      Prof := RISCV.Config.Profile_QEMU_Virt;
      RISCV.Config.Apply_Profile (Prof, Mem);

      Check (RISCV.Memory.UART_Enabled (Mem),
             "Apply_Profile enables UART");
      Check (RISCV.Memory.CLINT_Enabled (Mem),
             "Apply_Profile enables CLINT");

      --  Test memory regions were created
      Check (RISCV.Memory.Is_Mapped (Mem, 16#8000_0000#),
             "RAM region at 0x80000000 exists");
      Check (RISCV.Memory.Is_Mapped (Mem, 16#0000_1000#),
             "ROM region at 0x1000 exists");
      Check (not RISCV.Memory.Is_Mapped (Mem, 0),
             "No region at 0x0");

      RISCV.Memory.Finalize (Mem);
      Put_Line ("");
   end Test_Config_Profile;

begin
   Put_Line ("=================================================");
   Put_Line ("       RISCV Emulator Peripheral Tests");
   Put_Line ("=================================================");
   Put_Line ("");

   Test_CLINT;
   Test_GPIO;
   Test_Memory_Integration;
   Test_Config_Profile;

   Put_Line ("=================================================");
   Put_Line ("Test Results: " &
             Natural'Image (Pass_Count) & " passed," &
             Natural'Image (Fail_Count) & " failed out of" &
             Natural'Image (Test_Count) & " tests");
   Put_Line ("=================================================");

   if Fail_Count > 0 then
      Put_Line ("SOME TESTS FAILED!");
   else
      Put_Line ("ALL TESTS PASSED!");
   end if;
end Test_Peripherals;
