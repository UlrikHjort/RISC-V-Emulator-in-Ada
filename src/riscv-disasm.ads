-- ***************************************************************************
--               RISC-V Emulator - Disassembler
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

package RISCV.Disasm is

   --  Disassemble a single instruction, returning the assembly string.
   --  Xlen64 selects RV64 decoding where the two differ: 6-bit shift
   --  amounts, the RV64 rev8 encoding, and the OP-IMM-32 / OP-32 W ops.
   function Disassemble (Instruction : Word;
                         PC          : Word;
                         Xlen64      : Boolean := False) return String;

   --  Get register name (x0, ra, sp, gp, tp, t0-t6, s0-s11, a0-a7)
   function Reg_Name (Reg : Register_Index) return String;

end RISCV.Disasm;
