-- ***************************************************************************
--                 RISC-V Emulator - Symbol Table
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

-- Symbol table support for debugging
-- Loads symbols from ELF files and provides lookup functions
package RISCV.Symbols is

   --  Symbol types
   type Symbol_Type is (
      SYM_UNKNOWN,
      SYM_FUNCTION,
      SYM_OBJECT,
      SYM_SECTION,
      SYM_FILE
   );

   --  Symbol information
   type Symbol_Info is record
      Name    : String (1 .. 256);
      Name_Len : Natural := 0;
      Address : Memory_Address;
      Size    : Word;
      Sym_Type : Symbol_Type;
   end record;

   --  Maximum number of symbols
   Max_Symbols : constant := 2048;

   --  Symbol table
   type Symbol_Table is private;

   --  Initialize empty symbol table
   procedure Init (Syms : out Symbol_Table);

   --  Load symbols from ELF file
   procedure Load_From_ELF (Syms : in out Symbol_Table;
                           Filename : String;
                           Success : out Boolean);

   --  Lookup symbol by address (for traces, disassembly)
   --  Returns true if found, fills Info with symbol data
   function Lookup_By_Address (Syms : Symbol_Table;
                               Addr : Memory_Address;
                               Info : out Symbol_Info) return Boolean;

   --  Lookup symbol by name (for breakpoints)
   --  Returns true if found, fills Info with symbol data
   function Lookup_By_Name (Syms : Symbol_Table;
                           Name : String;
                           Info : out Symbol_Info) return Boolean;

   --  Get number of symbols loaded
   function Get_Symbol_Count (Syms : Symbol_Table) return Natural;

   --  Get symbol by index (for listing)
   function Get_Symbol (Syms : Symbol_Table;
                       Index : Natural;
                       Info : out Symbol_Info) return Boolean;

   --  Print all symbols to stdout
   procedure Print_Symbols (Syms : Symbol_Table);

   --  Get function name at address (returns "" if not found)
   function Get_Function_Name (Syms : Symbol_Table;
                              Addr : Memory_Address) return String;

private

   type Symbol_Entry is record
      Valid    : Boolean := False;
      Name     : String (1 .. 256);
      Name_Len : Natural := 0;
      Address  : Memory_Address := 0;
      Size     : Word := 0;
      Sym_Type : Symbol_Type := SYM_UNKNOWN;
   end record;

   type Symbol_Array is array (1 .. Max_Symbols) of Symbol_Entry;

   type Symbol_Table is record
      Symbols : Symbol_Array;
      Count   : Natural := 0;
      Loaded  : Boolean := False;
   end record;

end RISCV.Symbols;
