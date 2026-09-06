-- ***************************************************************************
--               RISC-V Emulator - PTY Support
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

with Interfaces.C.Strings; use type Interfaces.C.Strings.chars_ptr;
with System;

package body RISCV.PTY is

   --  POSIX constants (Linux x86_64/aarch64)
   O_RDWR     : constant int := 2;
   O_NOCTTY   : constant int := 16#100#;
   O_NONBLOCK : constant int := 16#800#;
   F_GETFL    : constant int := 3;
   F_SETFL    : constant int := 4;

   --  Bitwise OR for C int (which is a signed type without built-in "or")
   function C_Or (A, B : int) return int is
   begin
      return int (Interfaces.Unsigned_32 (A) or Interfaces.Unsigned_32 (B));
   end C_Or;

   --  POSIX C function imports
   function C_Posix_Openpt (Flags : int) return int
     with Import, Convention => C, External_Name => "posix_openpt";

   function C_Grantpt (FD : int) return int
     with Import, Convention => C, External_Name => "grantpt";

   function C_Unlockpt (FD : int) return int
     with Import, Convention => C, External_Name => "unlockpt";

   function C_Ptsname (FD : int) return Interfaces.C.Strings.chars_ptr
     with Import, Convention => C, External_Name => "ptsname";

   function C_Close (FD : int) return int
     with Import, Convention => C, External_Name => "close";

   function C_Read (FD : int; Buf : System.Address; Count : size_t) return long
     with Import, Convention => C, External_Name => "read";

   function C_Write (FD : int; Buf : System.Address; Count : size_t) return long
     with Import, Convention => C, External_Name => "write";

   function C_Fcntl_Getfl (FD : int; Cmd : int) return int
     with Import, Convention => C, External_Name => "fcntl";

   function C_Fcntl_Setfl (FD : int; Cmd : int; Flags : int) return int
     with Import, Convention => C, External_Name => "fcntl";

   ----------
   -- Open --
   ----------

   procedure Open (Master_FD  : out File_Descriptor;
                   Slave_Name : out String;
                   Slave_Last : out Natural;
                   Success    : out Boolean) is
      MFD    : int;
      Ret    : int;
      Flags  : int;
      Name_P : Interfaces.C.Strings.chars_ptr;
      pragma Unreferenced (Ret);
   begin
      Master_FD  := Invalid_FD;
      Slave_Name := (others => ' ');
      Slave_Last := 0;
      Success    := False;

      --  Open PTY master
      MFD := C_Posix_Openpt (C_Or (O_RDWR, O_NOCTTY));
      if MFD < 0 then
         return;
      end if;

      --  Grant and unlock slave
      if C_Grantpt (MFD) /= 0 then
         Ret := C_Close (MFD);
         return;
      end if;

      if C_Unlockpt (MFD) /= 0 then
         Ret := C_Close (MFD);
         return;
      end if;

      --  Get slave device path
      Name_P := C_Ptsname (MFD);
      if Name_P = Interfaces.C.Strings.Null_Ptr then
         Ret := C_Close (MFD);
         return;
      end if;

      --  Copy slave name to output string
      declare
         C_Name : constant String := Interfaces.C.Strings.Value (Name_P);
         Len    : constant Natural :=
            Natural'Min (C_Name'Length, Slave_Name'Length);
      begin
         Slave_Name (Slave_Name'First .. Slave_Name'First + Len - 1) :=
            C_Name (C_Name'First .. C_Name'First + Len - 1);
         Slave_Last := Slave_Name'First + Len - 1;
      end;

      --  Set master fd to non-blocking for reads
      Flags := C_Fcntl_Getfl (MFD, F_GETFL);
      if Flags >= 0 then
         Ret := C_Fcntl_Setfl (MFD, F_SETFL, C_Or (Flags, O_NONBLOCK));
      end if;

      Master_FD := File_Descriptor (MFD);
      Success   := True;
   end Open;

   -----------
   -- Close --
   -----------

   procedure Close (FD : File_Descriptor) is
      Ret : int;
      pragma Unreferenced (Ret);
   begin
      if FD /= Invalid_FD then
         Ret := C_Close (int (FD));
      end if;
   end Close;

   ----------------
   -- Write_Byte --
   ----------------

   procedure Write_Byte (FD : File_Descriptor; Data : Byte) is
      Buf : aliased Byte := Data;
      Ret : long;
      pragma Unreferenced (Ret);
   begin
      Ret := C_Write (int (FD), Buf'Address, 1);
   end Write_Byte;

   ---------------
   -- Read_Byte --
   ---------------

   function Read_Byte (FD : File_Descriptor; Data : out Byte) return Boolean is
      Buf : aliased Byte := 0;
      Ret : long;
   begin
      Ret := C_Read (int (FD), Buf'Address, 1);
      if Ret = 1 then
         Data := Buf;
         return True;
      else
         Data := 0;
         return False;
      end if;
   end Read_Byte;

end RISCV.PTY;
