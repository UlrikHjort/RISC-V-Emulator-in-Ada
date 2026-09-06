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
--  RISCV.Term_IO body -- see spec for overview.
-- ***************************************************************************

with Ada.Text_IO;
with Interfaces.C;

package body RISCV.Term_IO is

   use RISCV.Memory;

   ESC : constant Character := Character'Val (27);

   --  Unicode U+2580 "UPPER HALF BLOCK", UTF-8 encoded.
   Half_Block : constant String :=
     (Character'Val (16#E2#), Character'Val (16#96#), Character'Val (16#80#));

   --  Output geometry (character cells). Each cell = 2 vertical pixels, so
   --  the picture is Out_W columns by Out_H*2 sampled pixel rows.
   Out_W : constant := 100;
   Out_H : constant := 32;

   Src_W : constant := 320;
   Src_H : constant := 200;

   Started : Boolean := False;

   --  Assembly buffer for one frame (grown by Emit, flushed once).
   Buf : String (1 .. 300_000);
   Len : Natural := 0;

   --  ----------------------------------------------------------------------
   --  Minimal libc bindings
   --  ----------------------------------------------------------------------
   function C_System (Command : Interfaces.C.char_array)
     return Interfaces.C.int
     with Import, Convention => C, External_Name => "system";

   function C_Read
     (FD    : Interfaces.C.int;
      Buf   : access Interfaces.C.char;
      Count : Interfaces.C.size_t) return Interfaces.C.long
     with Import, Convention => C, External_Name => "read";

   procedure Run_Stty (Args : String) is
      Ignored : Interfaces.C.int;
   begin
      Ignored := C_System
        (Interfaces.C.To_C ("stty " & Args & " </dev/tty 2>/dev/null"));
      pragma Unreferenced (Ignored);
   end Run_Stty;

   --  ----------------------------------------------------------------------
   --  Frame-buffer emission helpers
   --  ----------------------------------------------------------------------
   procedure Emit (S : String) is
   begin
      if Len + S'Length <= Buf'Length then
         Buf (Len + 1 .. Len + S'Length) := S;
         Len := Len + S'Length;
      end if;
   end Emit;

   procedure Emit_Nat (N : Natural) is
   begin
      if N >= 10 then
         Emit_Nat (N / 10);
      end if;
      Emit ((1 => Character'Val (Character'Pos ('0') + N mod 10)));
   end Emit_Nat;

   --  ----------------------------------------------------------------------
   --  Present_Frame
   --  ----------------------------------------------------------------------
   procedure Present_Frame
     (Mem     : in out RISCV.Memory.Memory_Unit;
      FB_Addr : Memory_Address)
   is
      Last_FG : Integer := -1;
      Last_BG : Integer := -1;

      function Pixel (Sx, Sy : Natural) return Word is
      begin
         return Read_Word
           (Mem,
            FB_Addr + Memory_Address ((Sy * Src_W + Sx) * 4));
      end Pixel;

      procedure Set_Colour (Lead : String; P : Word; Last : in out Integer) is
         R   : constant Natural := Natural ((P / 16#1_0000#) and 16#FF#);
         G   : constant Natural := Natural ((P / 16#100#) and 16#FF#);
         B   : constant Natural := Natural (P and 16#FF#);
         Key : constant Integer := R * 65536 + G * 256 + B;
      begin
         if Key /= Last then
            Emit (ESC & Lead);
            Emit_Nat (R);
            Emit (";");
            Emit_Nat (G);
            Emit (";");
            Emit_Nat (B);
            Emit ("m");
            Last := Key;
         end if;
      end Set_Colour;

   begin
      if not Started then
         Run_Stty ("-echo -icanon min 0 time 0");
         --  Alternate screen + hide cursor.
         Ada.Text_IO.Put (ESC & "[?1049h" & ESC & "[?25l");
         Started := True;
      end if;

      Len := 0;
      Emit (ESC & "[H");   --  cursor home

      for Cy in 0 .. Out_H - 1 loop
         Last_FG := -1;
         Last_BG := -1;
         for Cx in 0 .. Out_W - 1 loop
            declare
               Sx   : constant Natural := Cx * Src_W / Out_W;
               Sy_T : constant Natural := (2 * Cy) * Src_H / (2 * Out_H);
               Sy_B : constant Natural := (2 * Cy + 1) * Src_H / (2 * Out_H);
               Top  : constant Word := Pixel (Sx, Sy_T);
               Bot  : constant Word := Pixel (Sx, Sy_B);
            begin
               Set_Colour ("[38;2;", Top, Last_FG);   --  foreground = top
               Set_Colour ("[48;2;", Bot, Last_BG);   --  background = bottom
               Emit (Half_Block);
            end;
         end loop;
         Emit (ESC & "[0m");
         if Cy < Out_H - 1 then
            Emit (Character'Val (13) & Character'Val (10));
         end if;
      end loop;

      Ada.Text_IO.Put (Buf (1 .. Len));
      Ada.Text_IO.Flush;
   end Present_Frame;

   --  ----------------------------------------------------------------------
   --  Poll_Key
   --  ----------------------------------------------------------------------
   function Poll_Key return Natural is
      use type Interfaces.C.long;
      Ch : aliased Interfaces.C.char;
      N  : Interfaces.C.long;
   begin
      N := C_Read (0, Ch'Access, 1);
      if N = 1 then
         return Character'Pos (Interfaces.C.To_Ada (Ch));
      else
         return 0;
      end if;
   end Poll_Key;

   --  ----------------------------------------------------------------------
   --  End_Session
   --  ----------------------------------------------------------------------
   procedure End_Session is
   begin
      if Started then
         --  Reset colour, show cursor, leave alternate screen.
         Ada.Text_IO.Put (ESC & "[0m" & ESC & "[?25h" & ESC & "[?1049l");
         Ada.Text_IO.Flush;
         Run_Stty ("sane");
         Started := False;
      end if;
   end End_Session;

end RISCV.Term_IO;
