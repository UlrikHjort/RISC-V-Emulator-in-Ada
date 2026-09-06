-- ***************************************************************************
--               RISC-V Emulator - L1 Cache Simulation
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

package body RISCV.Cache is

   use Ada.Text_IO;

   --  Helper: Trim the leading space from Long_Long_Integer'Image
   function Img (V : Long_Long_Integer) return String is
      S : constant String := Long_Long_Integer'Image (V);
   begin
      if S'Length > 0 and then S (S'First) = ' ' then
         return S (S'First + 1 .. S'Last);
      else
         return S;
      end if;
   end Img;

   ----------------
   -- Initialize --
   ----------------

   procedure Initialize (C            : out Cache_State;
                         Size_KB      : Positive;
                         Ways         : Positive;
                         Line_Size    : Positive := 64;
                         Miss_Penalty : Positive := 20) is
      Computed_Sets : Natural;
      Line_B        : Natural := 0;
      Set_B         : Natural := 0;
      Temp          : Positive;
   begin
      --  Compute Line_Bits = log2(Line_Size)
      Temp := Line_Size;
      while Temp > 1 loop
         Temp   := Temp / 2;
         Line_B := Line_B + 1;
      end loop;

      --  Compute Num_Sets = Size_KB * 1024 / (Ways * Line_Size)
      Computed_Sets := (Size_KB * 1024) / (Ways * Line_Size);
      if Computed_Sets > Max_Sets then
         Computed_Sets := Max_Sets;
      end if;
      if Computed_Sets < 1 then
         Computed_Sets := 1;
      end if;

      --  Compute Set_Bits = log2(Num_Sets)
      Temp := Computed_Sets;
      while Temp > 1 loop
         Temp  := Temp / 2;
         Set_B := Set_B + 1;
      end loop;

      C.Num_Sets     := Computed_Sets;
      C.Num_Ways     := Natural'Min (Ways, Max_Ways);
      C.Line_Bits    := Line_B;
      C.Set_Bits     := Set_B;
      C.Miss_Penalty := Miss_Penalty;
      C.Hits         := 0;
      C.Misses       := 0;
      C.Miss_Stalls  := 0;
      C.Enabled      := True;

      --  Initialize all tag entries to invalid
      for S in 0 .. Max_Sets - 1 loop
         for W in 0 .. Max_Ways - 1 loop
            C.Tags (S, W) := (Tag => 0, Valid => False);
            C.LRU  (S, W) := W;  --  way 0 = MRU (pos 0), way N-1 = LRU (pos N-1)
         end loop;
      end loop;
   end Initialize;

   ------------------
   -- Access_Cache --
   ------------------

   function Access_Cache (C       : in out Cache_State;
                          Address : Memory_Address) return Natural is
      Set_Index : constant Natural :=
         Natural (Shift_Right (Word (Address), C.Line_Bits) mod Word (C.Num_Sets));
      Tag_Val   : constant Word :=
         Shift_Right (Word (Address), C.Line_Bits + C.Set_Bits);
      Old_Pos   : Natural;
      Evict_Way : Natural := 0;
   begin
      --  Search for hit
      for W in 0 .. C.Num_Ways - 1 loop
         if C.Tags (Set_Index, W).Valid and then
            C.Tags (Set_Index, W).Tag = Tag_Val
         then
            --  HIT: promote this way to MRU (position 0)
            Old_Pos := C.LRU (Set_Index, W);
            for Ww in 0 .. C.Num_Ways - 1 loop
               if C.LRU (Set_Index, Ww) < Old_Pos then
                  C.LRU (Set_Index, Ww) := C.LRU (Set_Index, Ww) + 1;
               end if;
            end loop;
            C.LRU (Set_Index, W) := 0;
            C.Hits := C.Hits + 1;
            return 0;
         end if;
      end loop;

      --  MISS: find the LRU way (position = Num_Ways - 1)
      for W in 0 .. C.Num_Ways - 1 loop
         if C.LRU (Set_Index, W) = C.Num_Ways - 1 then
            Evict_Way := W;
            exit;
         end if;
      end loop;

      --  Install new tag in evicted way, promote to MRU
      C.Tags (Set_Index, Evict_Way) := (Tag => Tag_Val, Valid => True);
      for W in 0 .. C.Num_Ways - 1 loop
         if W /= Evict_Way then
            C.LRU (Set_Index, W) := C.LRU (Set_Index, W) + 1;
         end if;
      end loop;
      C.LRU (Set_Index, Evict_Way) := 0;

      C.Misses      := C.Misses + 1;
      C.Miss_Stalls := C.Miss_Stalls + Long_Long_Integer (C.Miss_Penalty);
      return C.Miss_Penalty;
   end Access_Cache;

   -----------------
   -- Print_Stats --
   -----------------

   procedure Print_Stats (C    : Cache_State;
                          Name : String) is
      Total     : constant Long_Long_Integer := C.Hits + C.Misses;
      Total_NZ  : constant Long_Long_Integer := (if Total > 0 then Total else 1);
      Miss_Pct  : constant Long_Long_Integer := (C.Misses * 100) / Total_NZ;
      Hit_Pct   : constant Long_Long_Integer := (C.Hits  * 100) / Total_NZ;
   begin
      Put_Line ("  " & Name & ":");
      Put_Line ("    Hits:         " & Img (C.Hits) &
                "  (" & Img (Hit_Pct) & "%)");
      Put_Line ("    Misses:       " & Img (C.Misses) &
                "  (" & Img (Miss_Pct) & "%)");
      Put_Line ("    Miss stalls:  " & Img (C.Miss_Stalls) & " cycles");
   end Print_Stats;

end RISCV.Cache;
