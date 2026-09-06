-- ***************************************************************************
--        RISC-V Emulator - Terminal Renderer / Keyboard Poller
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
-- ***************************************************************************
--  RISCV.Term_IO -- live terminal renderer + keyboard poller for the
--  interactive DOOM port.
--
--  Present_Frame renders a 320x200 ARGB framebuffer (read from guest memory)
--  to the terminal using truecolour ANSI escapes and the Unicode upper-half
--  block, so each character cell shows two vertically-stacked pixels.
--  Poll_Key returns one pending keystroke from stdin (0 if none), non-blocking.
--  End_Session restores the terminal (called on guest exit).
-- ***************************************************************************

with RISCV.Memory;

package RISCV.Term_IO is

   --  Render the guest framebuffer at FB_Addr (320x200, one 32-bit ARGB
   --  pixel per word) to the terminal. On first use it switches to the
   --  alternate screen, hides the cursor and puts stdin into raw mode.
   procedure Present_Frame
     (Mem     : in out RISCV.Memory.Memory_Unit;
      FB_Addr : Memory_Address);

   --  Non-blocking single-key read from stdin. Returns the byte value, or
   --  0 when no key is waiting.
   function Poll_Key return Natural;

   --  Restore the terminal if a session was started (idempotent).
   procedure End_Session;

end RISCV.Term_IO;
