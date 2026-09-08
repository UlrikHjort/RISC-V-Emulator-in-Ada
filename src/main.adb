-- ***************************************************************************
--               RISC-V Emulator - Main Program
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

with Ada.Text_IO;         use Ada.Text_IO;
with Ada.Command_Line;    use Ada.Command_Line;
with Ada.Strings.Fixed;
with Ada.Calendar;        use Ada.Calendar;
with RISCV;               use RISCV;
with RISCV.Memory;
with RISCV.CPU;
with RISCV.UART;
with RISCV.Debugger;
with RISCV.GDB;
with RISCV.Profiler;
with RISCV.Symbols;
with RISCV.Coverage;
with RISCV.Trace_Replay;
with RISCV.CSR;
with RISCV.ELF;           use RISCV.ELF;
with RISCV.Config;
with RISCV.CPU64;
with RISCV.CSR64;
with RISCV.Cache;

procedure Main is
   Mem           : Memory.Memory_Unit;
   Processor     : CPU.CPU_State;
   Dbg           : Debugger.Debugger_State;
   Profile       : Config.Hardware_Profile;
   Success       : Boolean;
   Trace         : Boolean := False;
   Trace_File     : String (1 .. 256) := (others => ' ');
   Trace_File_Len : Natural := 0;
   Trace_Start   : Memory_Address := 0;
   Trace_End     : Memory_Address := Memory_Address'Last;
   Trace_Mem     : Boolean := False;
   Trace_Regs    : Boolean := False;
   Max_Insns     : Natural := Natural'Last;
   Debug         : Boolean := False;
   GDB_Mode      : Boolean := False;
   GDB_Port      : Natural := 1234;
   GDB_All_Ifaces : Boolean := False;
   Profile_Mode  : Boolean := False;
   Flamegraph_File : String (1 .. 256) := (others => ' ');
   Flamegraph_Len  : Natural := 0;
   Coverage_Mode   : Boolean := False;
   Coverage_File   : String (1 .. 256) := (others => ' ');
   Coverage_File_Len : Natural := 0;
   IRecord_Mode    : Boolean := False;
   IRecord_File    : String (1 .. 256) := (others => ' ');
   IRecord_File_Len : Natural := 0;
   IReplay_Mode    : Boolean := False;
   IReplay_File    : String (1 .. 256) := (others => ' ');
   IReplay_File_Len : Natural := 0;
   Verbose       : Boolean := False;
   Quiet         : Boolean := False;
   No_UART       : Boolean := False;
   Program_File  : String (1 .. 256) := (others => ' ');
   Program_File_Len : Natural := 0;
   Is_ELF_File   : Boolean := False;
   Use_PTY       : Boolean := False;
   Wait_For_Key  : Boolean := False;
   Use_Profile   : Boolean := False;
   Machine_Name  : String (1 .. 64) := (others => ' ');
   Machine_Len   : Natural := 0;
   Config_File   : String (1 .. 256) := (others => ' ');
   Config_Len    : Natural := 0;
   Log_Dir_Buf   : String (1 .. 256) := (others => ' ');
   Log_Dir_Len   : Natural := 0;

   --  Host file I/O policy (semihosting ECALLs 0x500, 0x505-0x50C)
   Host_IO_Sel   : Memory.Host_IO_Mode := Memory.Read_Write;
   Host_Root_Buf : String (1 .. Memory.Max_Host_Root) := (others => ' ');
   Host_Root_Len : Natural := 0;

   --  Raise load/store/instruction access faults on unmapped or
   --  permission-denied accesses (default on; --no-access-faults restores
   --  the older silent behaviour).
   Access_Faults : Boolean := True;
   Dump_Sig      : Boolean := False;
   HTIF_Mode     : Boolean := False;
   Tohost_Override     : Memory_Address := 0;
   Tohost_Override_Set : Boolean := False;
   Sig_Begin     : Memory_Address := 0;
   Sig_End       : Memory_Address := 0;
   Sig_File      : String (1 .. 256) := (others => ' ');
   Sig_File_Len  : Natural := 0;
   Is_RV64       : Boolean := False;
   Proc64        : CPU64.CPU64_State;
   Arg_Index     : Positive := 1;
   Timeout_Secs  : Natural := 0;
   Harts         : Natural := 1;
   RV32E_Mode    : Boolean := False;
   RV64E_Mode    : Boolean := False;
   Cache_Mode    : Boolean := False;
   ICache_KB     : Positive := 16;
   DCache_KB     : Positive := 16;
   ICache_Ways   : constant Positive := 4;
   DCache_Ways   : constant Positive := 4;
   Proc2         : CPU.CPU_State;

   use type Config.Peripheral_Type;
   use type Memory.UART_Access;

   procedure Print_Usage;
   procedure Print_Profiles;

   procedure Print_Usage is
   begin
      Put_Line ("RISC-V Emulator (RV32IMFDV)");
      Put_Line ("");
      Put_Line ("Usage: riscv_emulator [options] <file> [start_address]");
      Put_Line ("");
      Put_Line ("Recommended: Always use --machine qemu-virt");
      Put_Line ("  Example: riscv_emulator --machine qemu-virt program.elf");
      Put_Line ("");
      Put_Line ("Options:");
      Put_Line ("  -t                    Enable instruction trace");
      Put_Line ("  --trace-file <file>   Redirect trace output to file");
      Put_Line ("  --trace-range <s> <e> Only trace PC in range [start, end]");
      Put_Line ("  --trace-mem           Log all memory accesses in trace");
      Put_Line ("  --trace-regs          Show register changes in trace");
      Put_Line ("  --max-instructions <n> Stop after n instructions (prevents infinite loops)");
      Put_Line ("  --timeout <n>        Halt after n wall-clock seconds");
      Put_Line ("  --harts <n>          Number of harts to simulate (1 or 2, RV32 only)");
      Put_Line ("  --rv32e               Enable RV32E (16-register subset, sets MISA.E)");
      Put_Line ("  --rv64e               Enable RV64E (16-register subset for RV64, sets MISA.E)");
      Put_Line ("  --cache               Enable L1 I+D cache simulation (16KB 4-way each)");
      Put_Line ("  --icache <kb>         Enable I-cache with given size in KB (4-way)");
      Put_Line ("  --dcache <kb>         Enable D-cache with given size in KB (4-way)");
      Put_Line ("  -d                   Start in interactive debugger");
      Put_Line ("  --gdb [port]         Start GDB remote stub on 127.0.0.1 (default port: 1234)");
      Put_Line ("  --gdb-listen-all     Bind the GDB stub to all interfaces (unauthenticated)");
      Put_Line ("  --profile            Enable profiling (function call statistics)");
      Put_Line ("  --flamegraph [file]  Enable profiling and export flamegraph data");
      Put_Line ("  --coverage [file]    Track instruction coverage (default: coverage.txt)");
      Put_Line ("  --irecord <file>     Record binary instruction trace to file");
      Put_Line ("  --ireplay <file>     Replay and verify against binary trace file");
      Put_Line ("  -v                   Verbose output (show loading details)");
      Put_Line ("  --no-uart         Disable UART emulation");
      Put_Line ("  --pty             Connect UART to a PTY (for minicom/screen)");
      Put_Line ("  --wait            Wait for keypress before starting (requires --pty)");
      Put_Line ("  -q, --quiet       Suppress informational output");
      Put_Line ("  --log-dir <dir>   Write semihosting log files to <dir> (default: CWD)");
      Put_Line ("  --no-access-faults  Do not trap unmapped/read-only accesses (legacy)");
      Put_Line ("  --host-io <mode>  Guest access to host files: off, ro, rw (default: rw)");
      Put_Line ("  --host-io-root <d>  Confine guest host-file paths to <d> (default: CWD)");
      Put_Line ("  --machine <name>  Use hardware profile (simple, qemu-virt)");
      Put_Line ("  --config <file>   Load hardware profile from file");
      Put_Line ("  --list-machines   List available hardware profiles");
      Put_Line ("  --dump-signature <begin_hex> <end_hex> <file>");
      Put_Line ("                    Dump signature memory region after halt");
      Put_Line ("  --htif            Terminate on HTIF tohost write (riscv-tests);");
      Put_Line ("                    reports PASS or FAIL <testnum> and sets exit status");
      Put_Line ("  --tohost <hex>    HTIF tohost address (implies --htif; needed for");
      Put_Line ("                    RV64 where symbol auto-lookup is unavailable)");
      Put_Line ("");
      Put_Line ("Arguments:");
      Put_Line ("  file              ELF executable or raw binary file");
      Put_Line ("  start_address     Starting PC in hex (for raw binary)");
      Put_Line ("");
      Put_Line ("Hardware Profiles:");
      Put_Line ("  simple      1MB RAM at 0x0, UART at 0x10000000 (default)");
      Put_Line ("  qemu-virt   128MB RAM at 0x80000000, QEMU virt compatible");
      Put_Line ("");
      Put_Line ("Example:");
      Put_Line ("  riscv_emulator program.elf");
      Put_Line ("  riscv_emulator --machine qemu-virt firmware.elf");
      Put_Line ("  riscv_emulator --config myboard.cfg program.elf");
   end Print_Usage;

   procedure Print_Profiles is
   begin
      Put_Line ("Available hardware profiles:");
      Put_Line ("");
      Put_Line ("  simple");
      Put_Line ("    Memory: 1 MB RAM at 0x00000000");
      Put_Line ("    UART:   0x10000000");
      Put_Line ("    Reset:  0x00000000");
      Put_Line ("    Stack:  0x00100000");
      Put_Line ("");
      Put_Line ("  qemu-virt");
      Put_Line ("    Memory: 128 MB RAM at 0x80000000");
      Put_Line ("            64 KB ROM at 0x00001000");
      Put_Line ("    UART:   0x10000000");
      Put_Line ("    CLINT:  0x02000000 (timer)");
      Put_Line ("    Reset:  0x80000000");
      Put_Line ("    Stack:  0x88000000");
      Put_Line ("");
      Put_Line ("Custom profiles can be loaded with --config <file>");
      Put_Line ("See profiles/ directory for examples.");
   end Print_Profiles;

begin
   if Argument_Count < 1 then
      Print_Usage;
      return;
   end if;

   --  Parse options
   while Arg_Index <= Argument_Count loop
      declare
         Arg : constant String := Argument (Arg_Index);
      begin
         if Arg = "-t" then
            Trace := True;
            Arg_Index := Arg_Index + 1;
         elsif Arg = "--trace-file" then
            if Arg_Index + 1 > Argument_Count then
               Put_Line ("Error: --trace-file requires a filename");
               return;
            end if;
            Trace := True;
            Arg_Index := Arg_Index + 1;
            declare
               Name : constant String := Argument (Arg_Index);
               Len  : constant Natural := Natural'Min (Name'Length, 256);
            begin
               Trace_File (1 .. Len) :=
                  Name (Name'First .. Name'First + Len - 1);
               Trace_File_Len := Len;
            end;
            Arg_Index := Arg_Index + 1;
         elsif Arg = "--trace-range" then
            if Arg_Index + 2 > Argument_Count then
               Put_Line ("Error: --trace-range requires <start> <end>");
               return;
            end if;
            Trace := True;
            Arg_Index := Arg_Index + 1;
            Trace_Start := Memory_Address'Value ("16#" & Argument (Arg_Index) & "#");
            Arg_Index := Arg_Index + 1;
            Trace_End := Memory_Address'Value ("16#" & Argument (Arg_Index) & "#");
            Arg_Index := Arg_Index + 1;
         elsif Arg = "--trace-mem" then
            Trace := True;
            Trace_Mem := True;
            Arg_Index := Arg_Index + 1;
         elsif Arg = "--trace-regs" then
            Trace := True;
            Trace_Regs := True;
            Arg_Index := Arg_Index + 1;
         elsif Arg = "--max-instructions" then
            if Arg_Index + 1 > Argument_Count then
               Put_Line ("Error: --max-instructions requires a count");
               return;
            end if;
            Arg_Index := Arg_Index + 1;
            Max_Insns := Natural'Value (Argument (Arg_Index));
            Arg_Index := Arg_Index + 1;
         elsif Arg = "--timeout" then
            if Arg_Index + 1 > Argument_Count then
               Put_Line ("Error: --timeout requires a number of seconds");
               return;
            end if;
            Arg_Index := Arg_Index + 1;
            Timeout_Secs := Natural'Value (Argument (Arg_Index));
            Arg_Index := Arg_Index + 1;
         elsif Arg = "--harts" then
            if Arg_Index + 1 > Argument_Count then
               Put_Line ("Error: --harts requires a count (1 or 2)");
               return;
            end if;
            Arg_Index := Arg_Index + 1;
            Harts := Natural'Value (Argument (Arg_Index));
            if Harts < 1 or Harts > 2 then
               Put_Line ("Error: --harts must be 1 or 2");
               return;
            end if;
            Arg_Index := Arg_Index + 1;
         elsif Arg = "--rv32e" then
            RV32E_Mode := True;
            Arg_Index := Arg_Index + 1;
         elsif Arg = "--rv64e" then
            RV64E_Mode := True;
            Arg_Index := Arg_Index + 1;
         elsif Arg = "--cache" then
            Cache_Mode := True;
            Arg_Index := Arg_Index + 1;
         elsif Arg = "--icache" then
            Arg_Index := Arg_Index + 1;
            ICache_KB := Positive'Value (Argument (Arg_Index));
            Cache_Mode := True;
            Arg_Index := Arg_Index + 1;
         elsif Arg = "--dcache" then
            Arg_Index := Arg_Index + 1;
            DCache_KB := Positive'Value (Argument (Arg_Index));
            Cache_Mode := True;
            Arg_Index := Arg_Index + 1;
         elsif Arg = "-d" then
            Debug := True;
            Arg_Index := Arg_Index + 1;
         elsif Arg = "--gdb" then
            GDB_Mode := True;
            Arg_Index := Arg_Index + 1;
            --  Check for optional port number
            if Arg_Index <= Argument_Count then
               declare
                  Next_Arg : constant String := Argument (Arg_Index);
               begin
                  if Next_Arg (Next_Arg'First) in '0' .. '9' then
                     GDB_Port := Natural'Value (Next_Arg);
                     Arg_Index := Arg_Index + 1;
                  end if;
               exception
                  when others => null;  -- Not a valid port, keep default
               end;
            end if;
         elsif Arg = "--gdb-listen-all" then
            GDB_All_Ifaces := True;
            Arg_Index := Arg_Index + 1;
         elsif Arg = "--profile" then
            Profile_Mode := True;
            Arg_Index := Arg_Index + 1;
         elsif Arg = "--flamegraph" then
            Profile_Mode := True;  -- Enable profiling
            Arg_Index := Arg_Index + 1;
            if Arg_Index <= Argument_Count then
               declare
                  Filename : constant String := Argument (Arg_Index);
                  L        : constant Natural := Filename'Length;
                  Is_Binary : constant Boolean :=
                     (L >= 4 and then
                      Filename (Filename'Last - 3 .. Filename'Last) = ".elf")
                     or else
                     (L >= 4 and then
                      Filename (Filename'Last - 3 .. Filename'Last) = ".bin");
               begin
                  if Filename (Filename'First) /= '-' and then not Is_Binary then
                     declare
                        Len : constant Natural :=
                           Natural'Min (L, Flamegraph_File'Length);
                     begin
                        Flamegraph_File (1 .. Len) :=
                           Filename (Filename'First .. Filename'First + Len - 1);
                        Flamegraph_Len := Len;
                        Arg_Index := Arg_Index + 1;
                     end;
                  else
                     --  Default filename
                     Flamegraph_File (1 .. 13) := "flamegraph.fg";
                     Flamegraph_Len := 13;
                  end if;
               end;
            else
               --  Default filename
               Flamegraph_File (1 .. 13) := "flamegraph.fg";
               Flamegraph_Len := 13;
            end if;
         elsif Arg = "--coverage" then
            Coverage_Mode := True;
            Arg_Index := Arg_Index + 1;
            if Arg_Index <= Argument_Count then
               declare
                  Filename : constant String := Argument (Arg_Index);
               begin
                  --  Use filename only if it doesn't start with '-' and
                  --  isn't a program binary (.elf / .bin)
                  declare
                     L : constant Natural := Filename'Length;
                     Is_Binary : constant Boolean :=
                        (L >= 4 and then
                         Filename (Filename'Last - 3 .. Filename'Last) = ".elf")
                        or else
                        (L >= 4 and then
                         Filename (Filename'Last - 3 .. Filename'Last) = ".bin");
                  begin
                     if Filename (Filename'First) /= '-' and then not Is_Binary then
                        declare
                           Len : constant Natural :=
                              Natural'Min (L, Coverage_File'Length);
                        begin
                           Coverage_File (1 .. Len) :=
                              Filename (Filename'First .. Filename'First + Len - 1);
                           Coverage_File_Len := Len;
                           Arg_Index := Arg_Index + 1;
                        end;
                     end if;
                  end;
               end;
            end if;
            if Coverage_File_Len = 0 then
               Coverage_File (1 .. 12) := "coverage.txt";
               Coverage_File_Len := 12;
            end if;
         elsif Arg = "--irecord" then
            Arg_Index := Arg_Index + 1;
            if Arg_Index <= Argument_Count then
               declare
                  Name : constant String := Argument (Arg_Index);
                  Len  : constant Natural :=
                     Natural'Min (Name'Length, IRecord_File'Length);
               begin
                  IRecord_File (1 .. Len) := Name (Name'First .. Name'First + Len - 1);
                  IRecord_File_Len := Len;
                  IRecord_Mode := True;
                  Arg_Index := Arg_Index + 1;
               end;
            else
               Put_Line ("Error: --irecord requires a filename");
               return;
            end if;
         elsif Arg = "--ireplay" then
            Arg_Index := Arg_Index + 1;
            if Arg_Index <= Argument_Count then
               declare
                  Name : constant String := Argument (Arg_Index);
                  Len  : constant Natural :=
                     Natural'Min (Name'Length, IReplay_File'Length);
               begin
                  IReplay_File (1 .. Len) := Name (Name'First .. Name'First + Len - 1);
                  IReplay_File_Len := Len;
                  IReplay_Mode := True;
                  Arg_Index := Arg_Index + 1;
               end;
            else
               Put_Line ("Error: --ireplay requires a filename");
               return;
            end if;
         elsif Arg = "-v" then
            Verbose := True;
            Arg_Index := Arg_Index + 1;
         elsif Arg = "-q" or Arg = "--quiet" then
            Quiet := True;
            Arg_Index := Arg_Index + 1;
         elsif Arg = "--dump-signature" then
            if Arg_Index + 4 > Argument_Count then
               Put_Line ("Error: --dump-signature requires <begin> <end> <file> and a binary file");
               return;
            end if;
            Dump_Sig := True;
            Sig_Begin := Memory_Address'Value
              ("16#" & Argument (Arg_Index + 1) & "#");
            Sig_End := Memory_Address'Value
              ("16#" & Argument (Arg_Index + 2) & "#");
            declare
               Name : constant String := Argument (Arg_Index + 3);
               Len  : constant Natural := Natural'Min (Name'Length, 256);
            begin
               Sig_File (1 .. Len) :=
                  Name (Name'First .. Name'First + Len - 1);
               Sig_File_Len := Len;
            end;
            Arg_Index := Arg_Index + 4;
         elsif Arg = "--htif" then
            HTIF_Mode := True;
            Arg_Index := Arg_Index + 1;
         elsif Arg = "--tohost" then
            if Arg_Index + 1 > Argument_Count then
               Put_Line ("Error: --tohost requires a hex address");
               return;
            end if;
            HTIF_Mode := True;
            Tohost_Override := Memory_Address'Value
              ("16#" & Argument (Arg_Index + 1) & "#");
            Tohost_Override_Set := True;
            Arg_Index := Arg_Index + 2;
         elsif Arg = "--no-uart" then
            No_UART := True;
            Arg_Index := Arg_Index + 1;
         elsif Arg = "--pty" then
            Use_PTY := True;
            Arg_Index := Arg_Index + 1;
         elsif Arg = "--wait" then
            Wait_For_Key := True;
            Arg_Index := Arg_Index + 1;
         elsif Arg = "--log-dir" then
            if Arg_Index + 1 > Argument_Count then
               Put_Line ("Error: --log-dir requires an argument");
               return;
            end if;
            Arg_Index := Arg_Index + 1;
            declare
               Dir : constant String := Argument (Arg_Index);
               Len : constant Natural := Natural'Min (Dir'Length, 256);
            begin
               Log_Dir_Buf (1 .. Len) := Dir (Dir'First .. Dir'First + Len - 1);
               Log_Dir_Len := Len;
            end;
            Arg_Index := Arg_Index + 1;
         elsif Arg = "--no-access-faults" then
            Access_Faults := False;
            Arg_Index := Arg_Index + 1;
         elsif Arg = "--host-io" then
            if Arg_Index + 1 > Argument_Count then
               Put_Line ("Error: --host-io requires off, ro or rw");
               return;
            end if;
            Arg_Index := Arg_Index + 1;
            declare
               V : constant String := Argument (Arg_Index);
            begin
               if V = "off" then
                  Host_IO_Sel := Memory.Off;
               elsif V = "ro" then
                  Host_IO_Sel := Memory.Read_Only;
               elsif V = "rw" then
                  Host_IO_Sel := Memory.Read_Write;
               else
                  Put_Line ("Error: --host-io expects off, ro or rw (got '" &
                     V & "')");
                  return;
               end if;
            end;
            Arg_Index := Arg_Index + 1;
         elsif Arg = "--host-io-root" then
            if Arg_Index + 1 > Argument_Count then
               Put_Line ("Error: --host-io-root requires a directory");
               return;
            end if;
            Arg_Index := Arg_Index + 1;
            declare
               Dir : constant String := Argument (Arg_Index);
               Len : constant Natural :=
                  Natural'Min (Dir'Length, Memory.Max_Host_Root);
            begin
               Host_Root_Buf (1 .. Len) :=
                  Dir (Dir'First .. Dir'First + Len - 1);
               Host_Root_Len := Len;
            end;
            Arg_Index := Arg_Index + 1;
         elsif Arg = "--machine" or Arg = "-m" then
            if Arg_Index + 1 > Argument_Count then
               Put_Line ("Error: --machine requires an argument");
               return;
            end if;
            Arg_Index := Arg_Index + 1;
            declare
               Name : constant String := Argument (Arg_Index);
               Len  : constant Natural := Natural'Min (Name'Length, 64);
            begin
               Machine_Name (1 .. Len) :=
                  Name (Name'First .. Name'First + Len - 1);
               Machine_Len := Len;
               Use_Profile := True;
            end;
            Arg_Index := Arg_Index + 1;
         elsif Arg = "--config" or Arg = "-c" then
            if Arg_Index + 1 > Argument_Count then
               Put_Line ("Error: --config requires a filename");
               return;
            end if;
            Arg_Index := Arg_Index + 1;
            declare
               Name : constant String := Argument (Arg_Index);
               Len  : constant Natural := Natural'Min (Name'Length, 256);
            begin
               Config_File (1 .. Len) :=
                  Name (Name'First .. Name'First + Len - 1);
               Config_Len := Len;
               Use_Profile := True;
            end;
            Arg_Index := Arg_Index + 1;
         elsif Arg = "--list-machines" or Arg = "-l" then
            Print_Profiles;
            return;
         elsif Arg = "-h" or Arg = "--help" then
            Print_Usage;
            return;
         elsif Arg'Length > 0 and then Arg (Arg'First) = '-' then
            Put_Line ("Unknown option: " & Arg);
            Print_Usage;
            return;
         elsif Arg'Length = 0 then
            --  Skip empty arguments
            Arg_Index := Arg_Index + 1;
         else
            exit;  -- Non-option argument (filename)
         end if;
      end;
   end loop;

   if Arg_Index > Argument_Count then
      Put_Line ("Error: No binary file specified");
      Print_Usage;
      return;
   end if;

   --  Load or select hardware profile
   if Config_Len > 0 then
      --  Load profile from file
      Config.Load_Profile (Config_File (1 .. Config_Len), Profile, Success);
      if not Success then
         Put_Line ("Error: Failed to load profile from " &
            Config_File (1 .. Config_Len));
         return;
      end if;
      if Verbose then
         Put_Line ("Loaded profile from: " & Config_File (1 .. Config_Len));
      end if;
   elsif Machine_Len > 0 then
      --  Use built-in profile. Reject unknown names rather than silently
      --  falling back to "simple": the wrong memory map produces a confusing
      --  ILLEGAL_INSTRUCTION far from the actual mistake.
      if not Config.Known_Profile (Machine_Name (1 .. Machine_Len)) then
         Put_Line ("Error: unknown machine profile '" &
            Machine_Name (1 .. Machine_Len) & "'");
         Put_Line ("  Built-in profiles: " & Config.Profile_Names);
         Put_Line ("  To load a profile from a file, use --config <file>");
         return;
      end if;
      Profile := Config.Get_Profile (Machine_Name (1 .. Machine_Len));
      if Verbose then
         Put_Line ("Using profile: " &
            Ada.Strings.Fixed.Trim (Profile.Name, Ada.Strings.Right));
      end if;
   else
      --  Default: use simple profile but initialize in legacy mode
      Profile := Config.Profile_Simple;
   end if;

   --  Initialize memory system
   if Use_Profile then
      --  Use region-based memory from profile
      Config.Apply_Profile (Profile, Mem);
      if Verbose then
         Put_Line ("Memory regions:");
         for I in 1 .. Profile.Num_Regions loop
            Put_Line ("  " &
               Ada.Strings.Fixed.Trim
                  (Profile.Memory_Regions (I).Name, Ada.Strings.Right) &
               ": 0x" &
               Word'Image (Word (Profile.Memory_Regions (I).Base)) &
               " size 0x" &
               Word'Image (Profile.Memory_Regions (I).Size));
         end loop;
      end if;
   else
      --  Legacy flat memory mode (backward compatible)
      Memory.Initialize (Mem);
   end if;

   --  Apply log directory (must be set after Initialize/Apply_Profile)
   Mem.Fault_Traps := Access_Faults;
   Mem.Host_IO := Host_IO_Sel;
   if Host_Root_Len > 0 then
      Mem.Host_Root (1 .. Host_Root_Len) := Host_Root_Buf (1 .. Host_Root_Len);
      Mem.Host_Root_Len := Host_Root_Len;
   end if;

   if Log_Dir_Len > 0 then
      Mem.Log_Dir (1 .. Log_Dir_Len) := Log_Dir_Buf (1 .. Log_Dir_Len);
      Mem.Log_Dir_Len := Log_Dir_Len;
   end if;

   CPU.Initialize (Processor);
   Debugger.Initialize (Dbg);

   --  Enable UART emulation (unless disabled or already set by profile)
   if Use_PTY and not No_UART then
      --  PTY mode: initialize UART with PTY backend
      if not Use_Profile then
         Memory.Enable_UART (Mem);
      end if;
      declare
         PTY_OK : Boolean;
      begin
         UART.Initialize_PTY (Mem.UART.all, UART.Default_Base_Address, PTY_OK);
         if PTY_OK then
            declare
               Path : constant String := UART.Get_PTY_Path (Mem.UART.all);
            begin
               Put_Line ("UART PTY: " & Path &
                  "  (connect with: minicom -D " & Path & ")");
            end;
         else
            Put_Line ("Error: Failed to open PTY");
            Memory.Finalize (Mem);
            return;
         end if;
      end;
   elsif not No_UART and not Use_Profile then
      Memory.Enable_UART (Mem);
      if Verbose then
         Put_Line ("UART enabled at 0x10000000");
      end if;
   elsif Use_Profile and Verbose then
      for I in 1 .. Profile.Num_Peripherals loop
         if Profile.Peripherals (I).Ptype = Config.UART_16550 then
            Put_Line ("UART enabled at 0x" &
               Word'Image (Word (Profile.Peripherals (I).Base)));
         end if;
      end loop;
   end if;

   --  Load file (auto-detect ELF vs raw binary)
   declare
      Filename     : constant String := Argument (Arg_Index);
      Load_Addr    : Memory_Address := 0;
      Entry_Addr   : Memory_Address := 0;
      ELF_Info     : ELF.ELF_Info;
      ELF_Info_64  : ELF.ELF_Info_64;
      ELF_Result   : ELF.Load_Result;
   begin
      --  Save filename for later use (e.g., symbol loading)
      Program_File_Len := Natural'Min (Filename'Length, Program_File'Length);
      Program_File (1 .. Program_File_Len) := Filename (Filename'First .. Filename'First + Program_File_Len - 1);

      --  Determine default entry address from profile
      if Use_Profile then
         Entry_Addr := Profile.CPU.Reset_Vector;
      end if;

      if ELF.Is_ELF_File (Filename) then
         Is_ELF_File := True;

         if ELF.Get_ELF_Class (Filename) = 2 then
            --  RV64 ELF
            if not Quiet then
               Put_Line ("Loading ELF64 file: " & Filename);
            end if;

            ELF.Load_ELF64 (Filename, Mem, ELF_Info_64, ELF_Result, Verbose);

            if ELF_Result /= ELF.Success then
               Put_Line ("Error: " & ELF.Error_Message (ELF_Result));
               Memory.Finalize (Mem);
               return;
            end if;

            Is_RV64 := True;
            CPU64.Initialize (Proc64, ELF_Info_64.Entry_Point);

            if Verbose then
               Put_Line ("  Entry point: 0x" &
                  Double_Word'Image (ELF_Info_64.Entry_Point));
               Put_Line ("  Load segments:" &
                  Natural'Image (ELF_Info_64.Num_Segments));
               Put_Line ("  Address range: 0x" &
                  Double_Word'Image (ELF_Info_64.Load_Address) & " - 0x" &
                  Double_Word'Image (ELF_Info_64.End_Address));
            end if;

         else
            --  RV32 ELF
            if not Quiet then
               Put_Line ("Loading ELF file: " & Filename);
            end if;

            ELF.Load_ELF (Filename, Mem, ELF_Info, ELF_Result, Verbose);

            if ELF_Result /= ELF.Success then
               Put_Line ("Error: " & ELF.Error_Message (ELF_Result));
               Memory.Finalize (Mem);
               return;
            end if;

            --  Set entry point from ELF (overrides profile default)
            Entry_Addr := Memory_Address (ELF_Info.Entry_Point);
            CPU.Initialize (Processor, Word (Entry_Addr));

            if Verbose then
               Put_Line ("  Entry point: 0x" & Word'Image (Word (Entry_Addr)));
               Put_Line ("  Load segments:" &
                  Natural'Image (ELF_Info.Num_Segments));
               Put_Line ("  Address range: 0x" &
                  Word'Image (ELF_Info.Load_Address) & " - 0x" &
                  Word'Image (ELF_Info.End_Address));
            end if;
         end if;
      else
         --  Load raw binary file
         if Argument_Count > Arg_Index then
            --  Explicit start address provided
            Load_Addr := Memory_Address'Value
              ("16#" & Argument (Arg_Index + 1) & "#");
            Entry_Addr := Load_Addr;
         elsif Use_Profile then
            --  Use profile's reset vector as load address for raw binary
            Load_Addr := Profile.CPU.Reset_Vector;
            Entry_Addr := Load_Addr;
         end if;

         if not Quiet then
            Put_Line ("Loading binary " & Filename & " at address 0x" &
                      Word'Image (Word (Load_Addr)));
         end if;

         Memory.Load_Binary (Mem, Filename, Load_Addr, Success);

         if not Success then
            Put_Line ("Error: Failed to load binary file");
            Memory.Finalize (Mem);
            return;
         end if;

         CPU.Initialize (Processor, Word (Entry_Addr));
      end if;
   end;

   --  HTIF tohost setup (riscv-tests): find the "tohost" symbol and arm
   --  memory-side termination detection.
   if HTIF_Mode and Tohost_Override_Set then
      Mem.HTIF_Enabled := True;
      Mem.Tohost_Addr  := Tohost_Override;
      if Verbose then
         Put_Line ("HTIF: tohost @ 0x" &
                   Word'Image (Word (Tohost_Override)));
      end if;
   elsif HTIF_Mode and Is_ELF_File then
      declare
         Syms  : Symbols.Symbol_Table;
         Info  : Symbols.Symbol_Info;
         OK    : Boolean;
         Found : Boolean;
      begin
         Symbols.Init (Syms);
         Symbols.Load_From_ELF
           (Syms, Program_File (1 .. Program_File_Len), OK);
         if OK then
            Found := Symbols.Lookup_By_Name (Syms, "tohost", Info);
            if Found then
               Mem.HTIF_Enabled := True;
               Mem.Tohost_Addr  := Info.Address;
               if Verbose then
                  Put_Line ("HTIF: tohost @ 0x" &
                            Word'Image (Word (Info.Address)));
               end if;
            else
               Put_Line ("Warning: --htif set but no 'tohost' symbol found");
            end if;
         end if;
      end;
   end if;

   --  Multi-hart initialisation (RV32 only)
   if Harts = 2 and not Is_RV64 then
      CPU.Initialize (Proc2, Processor.PC);
      Proc2.Hart_ID := 1;
      CSR.Write (Proc2.CSRs, CSR.CSR_MHARTID, 1);
   end if;

   --  RV32E setup: set Rv32e flag and rewrite MISA
   if RV32E_Mode then
      Processor.Rv32e := True;
      --  Rewrite MISA: replace I(bit8)/V(bit21) with E(bit4)
      CSR.Write (Processor.CSRs, CSR.CSR_MISA,
                 Shift_Left (Word (1), 0) or   --  A (Atomic)
                 Shift_Left (Word (1), 2) or   --  C (Compressed)
                 Shift_Left (Word (1), 3) or   --  D (Double FP)
                 Shift_Left (Word (1), 4) or   --  E (replaces I)
                 Shift_Left (Word (1), 5) or   --  F (Single FP)
                 Shift_Left (Word (1), 12) or  --  M (Multiply/Divide)
                 Shift_Left (Word (1), 30));    --  MXL=1 (32-bit)
   end if;

   --  RV64E setup: set Rv32e flag and rewrite MISA for RV64
   if RV64E_Mode and Is_RV64 then
      Proc64.Rv32e := True;
      --  Rewrite MISA: MXL=2 (bits 63:62), A+C+D+E+F+M bits set, I/V clear
      CSR64.Write (Proc64.CSRs, CSR64.CSR_MISA,
                   Shift_Left (Double_Word (2), 62) or  --  MXL=2 (RV64)
                   Shift_Left (Double_Word (1), 0)  or  --  A (Atomic)
                   Shift_Left (Double_Word (1), 2)  or  --  C (Compressed)
                   Shift_Left (Double_Word (1), 3)  or  --  D (Double FP)
                   Shift_Left (Double_Word (1), 4)  or  --  E (replaces I)
                   Shift_Left (Double_Word (1), 5)  or  --  F (Single FP)
                   Shift_Left (Double_Word (1), 12));   --  M (Multiply/Divide)
   end if;

   --  Wait for keypress if requested
   if Wait_For_Key and Use_PTY then
      Put_Line ("");
      Put_Line ("Waiting for connection... Press any key in minicom to start.");
      Put_Line ("");
      loop
         if UART.Poll_Input (Mem.UART.all) then
            exit;  -- Got a keypress, continue
         end if;
         delay 0.1;  -- Sleep 100ms to avoid busy-waiting
      end loop;
      if not Quiet then
         Put_Line ("Key received, starting execution...");
         Put_Line ("");
      end if;
   end if;

   if GDB_Mode and Is_RV64 then
      --  GDB not yet adapted for RV64; fall back to plain run
      if not Quiet then
         Put_Line ("Note: GDB mode not yet supported for RV64; running normally.");
      end if;
      CPU64.Run (Proc64, Mem, Trace,
                 (Enabled => Trace,
                  PC_Start => Memory_Address_64 (Trace_Start),
                  PC_End   => Memory_Address_64 (Trace_End),
                  Show_Memory => Trace_Mem,
                  Show_Regs   => Trace_Regs),
                 Max_Insns);

   elsif GDB_Mode then
      --  GDB Remote Debugging Mode
      declare
         Server : GDB.GDB_Server;
         Should_Run : Boolean;
         Should_Step : Boolean;
      begin
         GDB.Initialize (Server, GDB_Port, GDB_All_Ifaces);

         --  Track all memory accesses so watchpoints can fire
         Mem.Track_Access := True;

         if GDB.Accept_Connection (Server) then
            Put_Line ("GDB connected. Waiting for commands...");

            loop
               GDB.Process_Commands (Server, Processor, Mem, Should_Run, Should_Step);

               if Should_Run then
                  --  Continue until breakpoint, watchpoint, or halt
                  declare
                     Hit_Watchpoint : Boolean := False;
                  begin
                     loop
                        CPU.Step (Processor, Mem);
                        exit when Processor.Halted;
                        exit when GDB.Is_Breakpoint (Server, Double_Word (Processor.PC));
                        if GDB.Is_Watchpoint_Hit (Server,
                              Double_Word (Mem.Last_Access_Addr),
                              Mem.Last_Access_Write)
                        then
                           Hit_Watchpoint := True;
                           exit;
                        end if;
                     end loop;
                     if Hit_Watchpoint then
                        GDB.Send_Watchpoint_Stop (Server, Processor,
                           Double_Word (Mem.Last_Access_Addr),
                           Mem.Last_Access_Write);
                     else
                        GDB.Send_Stop_Reply (Server, Processor);
                     end if;
                  end;
               elsif Should_Step then
                  --  Single step
                  CPU.Step (Processor, Mem);
                  GDB.Send_Stop_Reply (Server, Processor);
               end if;

               exit when not GDB.Is_Connected (Server);
            end loop;

            GDB.Close (Server);
         end if;
      end;

   elsif Debug and Is_RV64 then
      --  Interactive debugger not yet adapted for RV64; fall back to plain run
      if not Quiet then
         Put_Line ("Note: Interactive debugger not yet supported for RV64; running normally.");
      end if;
      CPU64.Run (Proc64, Mem, Trace,
                 (Enabled => Trace,
                  PC_Start => Memory_Address_64 (Trace_Start),
                  PC_End   => Memory_Address_64 (Trace_End),
                  Show_Memory => Trace_Mem,
                  Show_Regs   => Trace_Regs),
                 Max_Insns);

   elsif Debug then
      --  Load symbols for debugging if we have an ELF file
      if Is_ELF_File and Program_File_Len > 0 then
         Debugger.Load_Symbols (Dbg, Program_File (1 .. Program_File_Len));
      end if;

      --  Run interactive debugger
      Put_Line ("");
      Debugger.Run (Dbg, Processor, Mem);
   else
      --  Run normally
      if not Quiet then
         Put_Line ("Starting emulation...");
         if Trace then
            Put_Line ("Trace enabled.");
            if Trace_File_Len > 0 then
               Put_Line ("  Output: " & Trace_File (1 .. Trace_File_Len));
            end if;
            if Trace_Start /= 0 or Trace_End /= Memory_Address'Last then
               Put_Line ("  Range: " & Memory_Address'Image (Trace_Start) &
                        " - " & Memory_Address'Image (Trace_End));
            end if;
         end if;
         Put_Line ("");
      end if;

      --  Setup trace file output if specified
      declare
         Trace_Output : File_Type;
         Cfg   : CPU.Trace_Config;
         Cfg64 : CPU64.Trace_Config;
      begin
         --  Build trace config (RV32)
         Cfg.Enabled := Trace;
         Cfg.PC_Start := Trace_Start;
         Cfg.PC_End := Trace_End;
         Cfg.Show_Memory := Trace_Mem;
         Cfg.Show_Regs := Trace_Regs;

         --  Build trace config (RV64)
         Cfg64.Enabled     := Trace;
         Cfg64.PC_Start    := Memory_Address_64 (Trace_Start);
         Cfg64.PC_End      := Memory_Address_64 (Trace_End);
         Cfg64.Show_Memory := Trace_Mem;
         Cfg64.Show_Regs   := Trace_Regs;

         --  Enable memory access tracking if needed
         if Trace_Mem then
            Mem.Track_Access := True;
         end if;

         --  Redirect output to file if specified
         if Trace and Trace_File_Len > 0 then
            Create (Trace_Output, Out_File, Trace_File (1 .. Trace_File_Len));
            Set_Output (Trace_Output);
         end if;

         --  Run with profiling / coverage / or plain execution
         if Is_RV64 then
            --  RV64: profile/coverage/trace modes not yet supported; run plainly
            if Profile_Mode or Coverage_Mode or IRecord_Mode or IReplay_Mode then
               if not Quiet then
                  Put_Line ("Note: profiling/coverage/trace not yet supported for RV64.");
               end if;
            end if;
            CPU64.Run (Proc64, Mem, Trace, Cfg64, Max_Insns);

         elsif Profile_Mode then
            --  Profiling mode - record each instruction
            declare
               type Profiler_Ptr is access all Profiler.Profiler_State;
               type Cache_Ptr    is access all Cache.Cache_State;
               Prof        : Profiler_Ptr;
               Syms        : Profiler.Symbol_Table_Ptr;
               Cov         : Coverage.Coverage_State_Ptr;
               IC          : Cache_Ptr := null;
               DC          : Cache_Ptr := null;
               Cycle_Count : Natural := 0;
               Instruction : Word;
               PC_Before   : Memory_Address;
            begin
               --  Initialize profiler with symbols
               Syms := new Symbols.Symbol_Table;
               Symbols.Init (Syms.all);
               if Is_ELF_File and Program_File_Len > 0 then
                  declare
                     Success : Boolean;
                  begin
                     Symbols.Load_From_ELF (Syms.all, Program_File (1 .. Program_File_Len), Success);
                  end;
               end if;

               Prof := new Profiler.Profiler_State;
               Profiler.Initialize (Prof.all, Syms);

               if Coverage_Mode then
                  Cov := new Coverage.Coverage_State;
                  Coverage.Initialize (Cov.all);
               end if;

               --  Initialize caches if requested
               if Cache_Mode then
                  IC := new Cache.Cache_State;
                  DC := new Cache.Cache_State;
                  Cache.Initialize (IC.all, ICache_KB, ICache_Ways);
                  Cache.Initialize (DC.all, DCache_KB, DCache_Ways);
                  Mem.Track_Access := True;
               end if;

               --  Execution loop with profiling (and optional coverage)
               declare
                  Start_Time : constant Time :=
                     (if Timeout_Secs > 0 then Clock else Clock);
               begin
                  while not Processor.Halted and Cycle_Count < Max_Insns loop
                     PC_Before   := Memory_Address (Processor.PC);
                     Instruction := Memory.Read_Word (Mem, PC_Before);
                     Mem.Last_Access_Valid := False;
                     if Coverage_Mode then
                        Coverage.Record_PC (Cov.all, PC_Before);
                     end if;
                     CPU.Step (Processor, Mem, Trace, Cfg);
                     Profiler.Record_Instruction (Prof.all, PC_Before, Instruction);
                     if Cache_Mode then
                        declare
                           I_St  : constant Natural := Cache.Access_Cache (IC.all, PC_Before);
                           I_Hit : constant Boolean := I_St = 0;
                           D_St  : Natural  := 0;
                           D_Hit : Boolean  := True;
                        begin
                           if Mem.Last_Access_Valid then
                              D_St  := Cache.Access_Cache (DC.all, Mem.Last_Access_Addr);
                              D_Hit := D_St = 0;
                           end if;
                           Profiler.Record_Cache_Stalls (Prof.all,
                              I_St, I_Hit, D_St, D_Hit, Mem.Last_Access_Valid);
                           CPU.Add_Cycle_Stalls (Processor, I_St + D_St);
                        end;
                     end if;
                     Cycle_Count := Cycle_Count + 1;
                     if Timeout_Secs > 0 and then
                        (Cycle_Count mod 100_000) = 0 and then
                        Clock - Start_Time >= Duration (Timeout_Secs)
                     then
                        Ada.Text_IO.Put_Line
                          (Ada.Text_IO.Standard_Error,
                           "TIMEOUT: program exceeded" &
                           Natural'Image (Timeout_Secs) & " second(s)");
                        Processor.Halted := True;
                        exit;
                     end if;
                  end loop;
               end;

               --  Print profiling report
               Profiler.Print_Report (Prof.all);

               --  Print call graph
               Profiler.Print_Call_Graph (Prof.all);

               --  Export flamegraph if requested
               if Flamegraph_Len > 0 then
                  Profiler.Export_Flamegraph (Prof.all, Flamegraph_File (1 .. Flamegraph_Len));
               end if;

               --  Print cache statistics if cache simulation was active
               if Cache_Mode then
                  Put_Line ("");
                  Put_Line ("=== Cache Statistics ===");
                  Cache.Print_Stats (IC.all, "I-cache");
                  Cache.Print_Stats (DC.all, "D-cache");
               end if;

               --  Write coverage report if requested
               if Coverage_Mode then
                  Coverage.Dump_Report
                    (Cov.all,
                     Coverage_File (1 .. Coverage_File_Len),
                     Syms);  --  Profiler.Symbol_Table_Ptr is access all Symbols.Symbol_Table
                  if not Quiet then
                     Put_Line ("Coverage report written to " &
                               Coverage_File (1 .. Coverage_File_Len));
                  end if;
               end if;
            end;
         elsif Coverage_Mode then
            --  Coverage-only mode: explicit loop with symbol table
            declare
               type Cov_Ptr is access all Coverage.Coverage_State;
               Cov         : constant Cov_Ptr := new Coverage.Coverage_State;
               St          : aliased Symbols.Symbol_Table;
               Cycle_Count : Natural := 0;
               Sym_Loaded  : Boolean := False;
            begin
               Coverage.Initialize (Cov.all);
               Symbols.Init (St);

               if Is_ELF_File and Program_File_Len > 0 then
                  Symbols.Load_From_ELF
                    (St, Program_File (1 .. Program_File_Len), Sym_Loaded);
               end if;

               declare
                  Cov_Start : constant Time :=
                     (if Timeout_Secs > 0 then Clock else Clock);
               begin
                  while not Processor.Halted and Cycle_Count < Max_Insns loop
                     Coverage.Record_PC (Cov.all, Memory_Address (Processor.PC));
                     CPU.Step (Processor, Mem, Trace, Cfg);
                     Cycle_Count := Cycle_Count + 1;
                     if Timeout_Secs > 0 and then
                        (Cycle_Count mod 100_000) = 0 and then
                        Clock - Cov_Start >= Duration (Timeout_Secs)
                     then
                        Ada.Text_IO.Put_Line
                          (Ada.Text_IO.Standard_Error,
                           "TIMEOUT: program exceeded" &
                           Natural'Image (Timeout_Secs) & " second(s)");
                        Processor.Halted := True;
                        exit;
                     end if;
                  end loop;
               end;

               Coverage.Dump_Report
                 (Cov.all,
                  Coverage_File (1 .. Coverage_File_Len),
                  (if Sym_Loaded then St'Access else null));

               if not Quiet then
                  Put_Line ("Coverage report written to " &
                            Coverage_File (1 .. Coverage_File_Len));
               end if;
            end;
         elsif IRecord_Mode then
            --  Instruction trace recording
            declare
               Rec_State    : Trace_Replay.Recorder_State;
               Cycle_Count  : Natural := 0;
               Encoding     : Word;
               Rd_Idx       : Word;
               Rd_Val_After : Word;
               PC_Before    : Word;
               Rec_Start    : constant Time :=
                  (if Timeout_Secs > 0 then Clock else Clock);
            begin
               Trace_Replay.Open_For_Recording
                 (Rec_State, IRecord_File (1 .. IRecord_File_Len));

               while not Processor.Halted and Cycle_Count < Max_Insns loop
                  PC_Before := Processor.PC;
                  Encoding  := Memory.Read_Word (Mem, Memory_Address (PC_Before));
                  --  Rd is bits [11:7] of the encoding
                  Rd_Idx    := Shift_Right (Encoding, 7) and 16#1F#;

                  CPU.Step (Processor, Mem, Trace, Cfg);
                  Cycle_Count := Cycle_Count + 1;

                  Rd_Val_After := Processor.Registers (Register_Index (Rd_Idx));

                  Trace_Replay.Append
                    (Rec_State,
                     PC       => PC_Before,
                     Encoding => Encoding,
                     Rd       => Rd_Idx,
                     Rd_Value => Rd_Val_After,
                     Next_PC  => Processor.PC);

                  if Timeout_Secs > 0 and then
                     (Cycle_Count mod 100_000) = 0 and then
                     Clock - Rec_Start >= Duration (Timeout_Secs)
                  then
                     Ada.Text_IO.Put_Line
                       (Ada.Text_IO.Standard_Error,
                        "TIMEOUT: program exceeded" &
                        Natural'Image (Timeout_Secs) & " second(s)");
                     Processor.Halted := True;
                     exit;
                  end if;
               end loop;

               Trace_Replay.Close_Recorder (Rec_State);

               if not Quiet then
                  Put_Line ("Instruction trace written to " &
                            IRecord_File (1 .. IRecord_File_Len) &
                            " (" &
                            Long_Long_Integer'Image (Rec_State.Count) &
                            " records)");
               end if;
            end;
         elsif IReplay_Mode then
            --  Instruction trace replay / verification
            declare
               use Trace_Replay;
               Rep_State    : Replayer_State;
               Cycle_Count  : Natural := 0;
               Encoding     : Word;
               Rd_Idx       : Word;
               Rd_Val_After : Word;
               PC_Before    : Word;
               Res          : Replay_Result;
               Msg          : String (1 .. 512);
               Msg_Len      : Natural;
               Rep_Start    : constant Time :=
                  (if Timeout_Secs > 0 then Clock else Clock);
            begin
               Open_For_Replay (Rep_State, IReplay_File (1 .. IReplay_File_Len));

               while not Processor.Halted and Cycle_Count < Max_Insns loop
                  PC_Before := Processor.PC;
                  Encoding  := Memory.Read_Word (Mem, Memory_Address (PC_Before));
                  Rd_Idx    := Shift_Right (Encoding, 7) and 16#1F#;

                  CPU.Step (Processor, Mem, Trace, Cfg);
                  Cycle_Count := Cycle_Count + 1;

                  Rd_Val_After := Processor.Registers (Register_Index (Rd_Idx));

                  Check_Step
                    (State           => Rep_State,
                     Actual_PC       => PC_Before,
                     Actual_Next_PC  => Processor.PC,
                     Actual_Rd       => Rd_Idx,
                     Actual_Rd_Value => Rd_Val_After,
                     Result          => Res,
                     Mismatch_Msg    => Msg,
                     Msg_Len         => Msg_Len);

                  if Res = Mismatch then
                     Put_Line (Msg (1 .. Msg_Len));
                     exit;
                  elsif Res = End_Of_Trace or Res = Replay_Error then
                     exit;
                  end if;

                  if Timeout_Secs > 0 and then
                     (Cycle_Count mod 100_000) = 0 and then
                     Clock - Rep_Start >= Duration (Timeout_Secs)
                  then
                     Ada.Text_IO.Put_Line
                       (Ada.Text_IO.Standard_Error,
                        "TIMEOUT: program exceeded" &
                        Natural'Image (Timeout_Secs) & " second(s)");
                     Processor.Halted := True;
                     exit;
                  end if;
               end loop;

               Close_Replayer (Rep_State);

               if not Quiet then
                  if Rep_State.Mismatches = 0 then
                     Put_Line ("Replay OK -" &
                               Long_Long_Integer'Image (Rep_State.Step_Count) &
                               " steps matched.");
                  else
                     Put_Line ("Replay FAILED -" &
                               Long_Long_Integer'Image (Rep_State.Mismatches) &
                               " mismatch(es).");
                  end if;
               end if;
            end;
         else
            --  Normal execution
            if Harts = 2 then
               --  Multi-hart execution loop (RV32 only)
               declare
                  Cycle_Count : Natural := 0;
                  MH_Start    : constant Time :=
                     (if Timeout_Secs > 0 then Clock else Clock);
               begin
                  while (not Processor.Halted or not Proc2.Halted)
                        and Cycle_Count < Max_Insns
                  loop
                     if not Processor.Halted then
                        CPU.Step (Processor, Mem, Trace, Cfg);
                     end if;
                     if not Proc2.Halted then
                        CPU.Step (Proc2, Mem, Trace, Cfg);
                     end if;
                     Cycle_Count := Cycle_Count + 1;
                     if Timeout_Secs > 0 and then
                        (Cycle_Count mod 100_000) = 0 and then
                        Clock - MH_Start >= Duration (Timeout_Secs)
                     then
                        Ada.Text_IO.Put_Line
                          (Ada.Text_IO.Standard_Error,
                           "TIMEOUT: program exceeded" &
                           Natural'Image (Timeout_Secs) & " second(s)");
                        Processor.Halted := True;
                        Proc2.Halted     := True;
                        exit;
                     end if;
                  end loop;
               end;
            elsif Timeout_Secs > 0 then
               --  Single hart with timeout
               declare
                  Cycle_Count : Natural := 0;
                  TO_Start    : constant Time := Clock;
               begin
                  while not Processor.Halted
                        and Cycle_Count < Max_Insns
                  loop
                     CPU.Step (Processor, Mem, Trace, Cfg);
                     Cycle_Count := Cycle_Count + 1;
                     if (Cycle_Count mod 100_000) = 0 and then
                        Clock - TO_Start >= Duration (Timeout_Secs)
                     then
                        Ada.Text_IO.Put_Line
                          (Ada.Text_IO.Standard_Error,
                           "TIMEOUT: program exceeded" &
                           Natural'Image (Timeout_Secs) & " second(s)");
                        Processor.Halted := True;
                        exit;
                     end if;
                  end loop;
               end;
            else
               --  Single hart, no timeout: maximum speed
               CPU.Run (Processor, Mem, Trace, Cfg, Max_Insns);
            end if;
         end if;

         --  Restore standard output
         if Trace and Trace_File_Len > 0 then
            Set_Output (Standard_Output);
            Close (Trace_Output);
            if not Quiet then
               Put_Line ("Trace written to " & Trace_File (1 .. Trace_File_Len));
            end if;
         end if;
      end;
   end if;

   --  Dump signature region if requested
   if Dump_Sig then
      declare
         package Word_IO is new Ada.Text_IO.Modular_IO (Word);
         Sig_Out : File_Type;
         Addr    : Memory_Address := Sig_Begin;
         Val     : Word;
         Hex     : String (1 .. 20);
      begin
         Create (Sig_Out, Out_File, Sig_File (1 .. Sig_File_Len));
         while Addr < Sig_End loop
            Val := Memory.Read_Word (Mem, Addr);
            Word_IO.Put (Hex, Val, Base => 16);
            --  Convert "16#XXXXXXXX#" to "xxxxxxxx"
            declare
               Start : Natural := 0;
               Stop  : Natural := 0;
            begin
               for I in Hex'Range loop
                  if Hex (I) = '#' then
                     if Start = 0 then
                        Start := I + 1;
                     else
                        Stop := I - 1;
                     end if;
                  end if;
               end loop;
               declare
                  Raw : constant String := Hex (Start .. Stop);
                  Padded : String (1 .. 8) := (others => '0');
                  Offset : constant Natural := 8 - Raw'Length;
               begin
                  Padded (Offset + 1 .. 8) := Raw;
                  --  Convert to lowercase
                  for I in Padded'Range loop
                     if Padded (I) >= 'A' and Padded (I) <= 'F' then
                        Padded (I) :=
                           Character'Val (Character'Pos (Padded (I)) + 32);
                     end if;
                  end loop;
                  Put_Line (Sig_Out, Padded);
               end;
            end;
            Addr := Addr + 4;
         end loop;
         Close (Sig_Out);
      end;
   end if;

   --  Show final state
   if not Quiet then
      Put_Line ("");
      Put_Line ("Emulation stopped.");
      if Is_RV64 then
         CPU64.Dump_State (Proc64);
         Put_Line ("");
         Put ("Return value (a0): ");
         declare
            package DW_IO is new Ada.Text_IO.Modular_IO (Double_Word);
         begin
            DW_IO.Put (CPU64.Read_Register (Proc64, 10), Width => 1);
         end;
         New_Line;
      else
         CPU.Dump_State (Processor);
         Put_Line ("");
         Put ("Return value (a0): ");
         declare
            package Word_IO is new Ada.Text_IO.Modular_IO (Word);
         begin
            Word_IO.Put (CPU.Read_Register (Processor, 10), Width => 1);
         end;
         New_Line;
      end if;
   end if;

   --  HTIF tohost result (riscv-tests): report PASS/FAIL and set exit status.
   if HTIF_Mode then
      if not Mem.Tohost_Written then
         Put_Line ("HTIF: NO-HALT (no tohost write; timed out or hung)");
         Set_Exit_Status (2);
      elsif Mem.Tohost_Value = 1 then
         Put_Line ("HTIF: PASS");
         Set_Exit_Status (0);
      else
         Put_Line ("HTIF: FAIL test" &
                   Word'Image (Mem.Tohost_Value / 2) &
                   " (tohost=" & Word'Image (Mem.Tohost_Value) & ")");
         Set_Exit_Status (1);
      end if;
   end if;

   if Use_PTY and Mem.UART /= null then
      UART.Finalize (Mem.UART.all);
   end if;
   Memory.Finalize (Mem);
end Main;
