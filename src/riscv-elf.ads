-- ***************************************************************************
--               RISC-V Emulator - ELF Loader
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

with RISCV.Memory;

package RISCV.ELF is

   --  ELF loading result
   type Load_Result is (
      Success,
      File_Not_Found,
      Invalid_Magic,
      Wrong_Class,        -- Not a supported ELF class
      Wrong_Endian,       -- Not little-endian
      Wrong_Machine,      -- Not RISC-V
      Invalid_Format,
      Load_Error
   );

   --  ELF32 file information
   type ELF_Info is record
      Entry_Point    : Word;
      Num_Segments   : Natural;
      Load_Address   : Word;   -- Lowest load address
      End_Address    : Word;   -- Highest end address
   end record;

   --  ELF64 file information
   type ELF_Info_64 is record
      Entry_Point    : Double_Word;
      Num_Segments   : Natural;
      Load_Address   : Double_Word;
      End_Address    : Double_Word;
   end record;

   --  Return the ELF class byte: 1 = ELF32, 2 = ELF64, 0 = not ELF
   function Get_ELF_Class (Filename : String) return Natural;

   --  Load a 32-bit ELF file into memory
   procedure Load_ELF (Filename    : String;
                       Mem         : in out Memory.Memory_Unit;
                       Info        : out ELF_Info;
                       Result      : out Load_Result;
                       Verbose     : Boolean := False);

   --  Load a 64-bit ELF file into memory
   --  Note: segment virtual addresses must fit in 32 bits (Memory_Address range)
   procedure Load_ELF64 (Filename    : String;
                         Mem         : in out Memory.Memory_Unit;
                         Info        : out ELF_Info_64;
                         Result      : out Load_Result;
                         Verbose     : Boolean := False);

   --  Check if a file appears to be an ELF file
   function Is_ELF_File (Filename : String) return Boolean;

   --  Get a human-readable error message
   function Error_Message (Result : Load_Result) return String;

end RISCV.ELF;
