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
--
--  Simulates a set-associative L1 instruction/data cache with LRU replacement.
--  Used by the profiler (--cache flag) to model cache-miss stall cycles.
--  Does NOT affect the mcycle CSR -- miss stalls are profiler-side only.

package RISCV.Cache is

   --  Configuration for one cache (I-cache or D-cache)
   Max_Sets : constant := 256;
   Max_Ways : constant := 8;

   --  Per-way entry: tag + valid
   type Way_Entry is record
      Tag   : Word    := 0;
      Valid : Boolean := False;
   end record;

   type Tag_Matrix is array (0 .. Max_Sets - 1, 0 .. Max_Ways - 1) of Way_Entry;
   --  LRU position: 0 = MRU, Ways-1 = LRU (next to evict)
   type LRU_Matrix is array (0 .. Max_Sets - 1, 0 .. Max_Ways - 1) of Natural;

   type Cache_State is record
      Num_Sets     : Natural  := 0;
      Num_Ways     : Natural  := 0;
      Line_Bits    : Natural  := 6;  --  log2(line_size), default 64B -> 6
      Set_Bits     : Natural  := 0;  --  log2(Num_Sets), computed during Initialize
      Miss_Penalty : Positive := 20; --  cycles per miss
      Tags         : Tag_Matrix;
      LRU          : LRU_Matrix;
      --  Statistics
      Hits         : Long_Long_Integer := 0;
      Misses       : Long_Long_Integer := 0;
      Miss_Stalls  : Long_Long_Integer := 0;
      Enabled      : Boolean := False;
   end record;

   --  Initialise cache. size_kb*1024 / (ways*line_size) must be <= Max_Sets.
   procedure Initialize (C            : out Cache_State;
                         Size_KB      : Positive;
                         Ways         : Positive;
                         Line_Size    : Positive := 64;
                         Miss_Penalty : Positive := 20);

   --  Access cache at Address. Returns 0 on hit, Miss_Penalty on miss.
   --  Updates LRU and statistics.
   function Access_Cache (C       : in out Cache_State;
                          Address : Memory_Address) return Natural;

   --  Print cache statistics (called on exit).
   procedure Print_Stats (C    : Cache_State;
                          Name : String);

end RISCV.Cache;
