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

--  Low-level POSIX pseudo-terminal (PTY) bindings.
--  Used to connect the emulated UART to an external terminal emulator
--  (e.g. minicom, screen, picocom) via a /dev/pts/N device.

with Interfaces.C; use Interfaces.C;

package RISCV.PTY is

   type File_Descriptor is new int;
   Invalid_FD : constant File_Descriptor := -1;

   --  Open a PTY master, grant/unlock, return master fd and slave path
   procedure Open (Master_FD  : out File_Descriptor;
                   Slave_Name : out String;
                   Slave_Last : out Natural;
                   Success    : out Boolean);

   --  Close the PTY master
   procedure Close (FD : File_Descriptor);

   --  Write a single byte to PTY
   procedure Write_Byte (FD : File_Descriptor; Data : Byte);

   --  Read a single byte from PTY (non-blocking)
   --  Returns False if no data available
   function Read_Byte (FD : File_Descriptor; Data : out Byte) return Boolean;

end RISCV.PTY;
