-- ***************************************************************************
--              RISC-V Emulator - GDB Remote Stub
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

-- GDB Remote Serial Protocol (RSP) server for remote debugging.
-- Allows standard riscv32-unknown-elf-gdb / riscv64-unknown-elf-gdb to
-- connect and debug RISC-V programs.
-- Supports: g/G (registers), m/M (memory), c (continue), s (step),
--           Z0/z0 (breakpoints), qXfer:features:read (target.xml),
--           P (write single reg), vCont, Z2-Z4/z2-z4 (watchpoints).
--           RV32 and RV64 register encoding are both supported.
with GNAT.Sockets;
with RISCV.CPU;
with RISCV.CPU64;
with RISCV.Memory;

package RISCV.GDB is

   --  GDB server state
   type GDB_Server is limited private;

   --  Initialize GDB server on the given TCP port (default 1234)
   procedure Initialize (Server : out GDB_Server;
                        Port   : Natural := 1234);

   --  Block until GDB connects.  Returns True on success.
   function Accept_Connection (Server : in out GDB_Server) return Boolean;

   --  True while GDB is connected
   function Is_Connected (Server : GDB_Server) return Boolean;

   --  Receive and dispatch one GDB packet (RV32 variant).
   --  Should_Run  => GDB issued 'c' (continue)
   --  Should_Step => GDB issued 's' (single step)
   --  CPU is in/out so that 'G'/'P' (register writes) work.
   procedure Process_Commands (Server      : in out GDB_Server;
                               CPU         : in out RISCV.CPU.CPU_State;
                               Mem         : in out RISCV.Memory.Memory_Unit;
                               Should_Run  : out Boolean;
                               Should_Step : out Boolean);

   --  Receive and dispatch one GDB packet (RV64 variant).
   procedure Process_Commands (Server      : in out GDB_Server;
                               CPU         : in out RISCV.CPU64.CPU64_State;
                               Mem         : in out RISCV.Memory.Memory_Unit;
                               Should_Run  : out Boolean;
                               Should_Step : out Boolean);

   --  Send a stop-reply packet to GDB (RV32).  Signal defaults to 5 (SIGTRAP).
   procedure Send_Stop_Reply (Server : in out GDB_Server;
                              CPU    : RISCV.CPU.CPU_State;
                              Signal : Natural := 5);

   --  Send a stop-reply packet to GDB (RV64).
   procedure Send_Stop_Reply (Server : in out GDB_Server;
                              CPU    : RISCV.CPU64.CPU64_State;
                              Signal : Natural := 5);

   --  Returns True if Addr is in the active breakpoint list.
   --  Both RV32 (Word) and RV64 (Double_Word) addresses are supported;
   --  breakpoints are stored as Double_Word internally.
   function Is_Breakpoint (Server : GDB_Server;
                           Addr   : Double_Word) return Boolean;

   --  Watchpoint type: read (Z3), write (Z2), or either (Z4)
   type Watchpoint_Kind is (Watch_Write, Watch_Read, Watch_Access);

   --  Returns True if Addr matches an active watchpoint of the correct kind.
   function Is_Watchpoint_Hit (Server   : GDB_Server;
                                Addr     : Double_Word;
                                Is_Write : Boolean) return Boolean;

   --  Returns the GDB stop-reply watch prefix for the given memory access.
   --  E.g. "watch:0000ff00;" or "rwatch:0000ff00;" or "awatch:0000ff00;".
   --  Returns empty string if no active watchpoint matches.
   function Watchpoint_Stop_Prefix (Server   : GDB_Server;
                                    Addr     : Double_Word;
                                    Is_Write : Boolean) return String;

   --  Send a stop-reply packet with watchpoint info (RV32).
   procedure Send_Watchpoint_Stop (Server     : in out GDB_Server;
                                   CPU        : RISCV.CPU.CPU_State;
                                   Watch_Addr : Double_Word;
                                   Is_Write   : Boolean;
                                   Signal     : Natural := 5);

   --  Send a stop-reply packet with watchpoint info (RV64).
   procedure Send_Watchpoint_Stop (Server     : in out GDB_Server;
                                   CPU        : RISCV.CPU64.CPU64_State;
                                   Watch_Addr : Double_Word;
                                   Is_Write   : Boolean;
                                   Signal     : Natural := 5);

   --  Close the client connection (keeps the listen socket alive)
   procedure Close (Server : in out GDB_Server);

private

   use GNAT.Sockets;

   Max_Breakpoints : constant := 64;
   type BP_Array is array (1 .. Max_Breakpoints) of Double_Word;

   Max_Watchpoints : constant := 32;

   type Watchpoint_Entry is record
      Addr  : Double_Word      := 0;
      Kind  : Watchpoint_Kind  := Watch_Access;
      Valid : Boolean          := False;
   end record;

   type WP_Array is array (1 .. Max_Watchpoints) of Watchpoint_Entry;

   type GDB_Server is record
      Listening_Socket : Socket_Type;
      Client_Socket    : Socket_Type;
      Address          : Sock_Addr_Type;
      Connected        : Boolean := False;
      Port             : Natural := 1234;
      No_Ack_Mode      : Boolean := False;
      --  Software breakpoints (Double_Word to support both RV32 and RV64)
      Breakpoints      : BP_Array;
      Num_Breakpoints  : Natural := 0;
      --  Hardware watchpoints (Z2/Z3/Z4)
      Watchpoints      : WP_Array;
      Num_Watchpoints  : Natural := 0;
   end record;

end RISCV.GDB;
