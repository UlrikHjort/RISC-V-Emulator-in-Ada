-- ***************************************************************************
--                RISC-V Emulator - Symbol Table
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
with Ada.Streams.Stream_IO;

package body RISCV.Symbols is

   --  ELF constants
   ELF_MAGIC : constant := 16#464C457F#;  -- 0x7F,'E','L','F'

   --  Section header types
   SHT_SYMTAB   : constant := 2;
   SHT_STRTAB   : constant := 3;

   --  Symbol types
   STT_OBJECT  : constant := 1;
   STT_FUNC    : constant := 2;
   STT_SECTION : constant := 3;
   STT_FILE    : constant := 4;

   --  Helper: Convert word to hex string
   function To_Hex (V : Word) return String is
      Hex_Digits : constant String := "0123456789abcdef";
      Result : String (1 .. 8);
      Val : Word := V;
   begin
      for I in reverse Result'Range loop
         Result (I) := Hex_Digits (Natural (Val mod 16) + 1);
         Val := Val / 16;
      end loop;
      return Result;
   end To_Hex;

   --  Helper: Read 4 bytes as little-endian word
   procedure Read_Word (Stream : Ada.Streams.Stream_IO.Stream_Access; Value : out Word) is
      B0, B1, B2, B3 : Byte;
   begin
      Byte'Read (Stream, B0);
      Byte'Read (Stream, B1);
      Byte'Read (Stream, B2);
      Byte'Read (Stream, B3);
      Value := Word (B0) or
               Shift_Left (Word (B1), 8) or
               Shift_Left (Word (B2), 16) or
               Shift_Left (Word (B3), 24);
   end Read_Word;

   --  Helper: Read 2 bytes as little-endian halfword
   procedure Read_Half (Stream : Ada.Streams.Stream_IO.Stream_Access; Value : out Half_Word) is
      B0, B1 : Byte;
   begin
      Byte'Read (Stream, B0);
      Byte'Read (Stream, B1);
      Value := Half_Word (B0) or Shift_Left (Half_Word (B1), 8);
   end Read_Half;

   --  Helper: Skip N bytes
   --  Read a little-endian 64-bit value (ELF64 fields).
   procedure Read_DWord (Stream : Ada.Streams.Stream_IO.Stream_Access;
                         Value  : out Double_Word) is
      B : Byte;
   begin
      Value := 0;
      for I in 0 .. 7 loop
         Byte'Read (Stream, B);
         Value := Value or Shift_Left (Double_Word (B), I * 8);
      end loop;
   end Read_DWord;

   procedure Skip_Bytes (Stream : Ada.Streams.Stream_IO.Stream_Access; Count : Natural) is
      Dummy : Byte;
   begin
      for I in 1 .. Count loop
         Byte'Read (Stream, Dummy);
      end loop;
   end Skip_Bytes;

   --  Initialize empty symbol table
   procedure Init (Syms : out Symbol_Table) is
   begin
      Syms.Count := 0;
      Syms.Loaded := False;
      for I in Syms.Symbols'Range loop
         Syms.Symbols (I).Valid := False;
      end loop;
   end Init;

   --  Load symbols from ELF file
   procedure Load_From_ELF (Syms : in out Symbol_Table;
                           Filename : String;
                           Success : out Boolean) is
      File : Ada.Streams.Stream_IO.File_Type;
      Stream : Ada.Streams.Stream_IO.Stream_Access;
      Magic : Word;
      Is_64 : Boolean := False;   -- ELFCLASS64: different header, section
                                  -- header and symbol layouts throughout
      E_Shoff : Word;      -- Section header offset
      E_Shnum : Half_Word;  -- Section header count
      E_Shentsize : Half_Word;
      E_Shstrndx : Half_Word;

      Symtab_Offset : Word := 0;
      Symtab_Size   : Word := 0;
      Symtab_Entsize : Word := 0;
      Symtab_Link   : Word := 0;

      Strtab_Offset : Word := 0;
      Strtab_Size   : Word := 0;

      String_Data : array (1 .. 65536) of Byte := (others => 0);

   begin
      Success := False;
      Init (Syms);

      --  Open ELF file
      begin
         Ada.Streams.Stream_IO.Open (File, Ada.Streams.Stream_IO.In_File, Filename);
         Stream := Ada.Streams.Stream_IO.Stream (File);
      exception
         when others =>
            return;
      end;

      --  Read ELF header
      Read_Word (Stream, Magic);
      if Magic /= ELF_MAGIC then
         Ada.Streams.Stream_IO.Close (File);
         return;
      end if;

      --  e_ident[4] is EI_CLASS: 1 = ELF32, 2 = ELF64. Every offset below
      --  depends on it, so read it before anything else.
      declare
         Class_Byte : Byte;
      begin
         Byte'Read (Stream, Class_Byte);
         Is_64 := Class_Byte = 2;
      end;

      if Is_64 then
         --  ELF64 header after e_ident[4] (5 bytes of the file read so far):
         --  11 bytes: rest of e_ident
         --   2 bytes: e_type
         --   2 bytes: e_machine
         --   4 bytes: e_version
         --   8 bytes: e_entry
         --   8 bytes: e_phoff
         --   8 bytes: e_shoff  (at file offset 0x28)
         Skip_Bytes (Stream, 11 + 2 + 2 + 4 + 8 + 8);
         declare
            Shoff64 : Double_Word;
         begin
            Read_DWord (Stream, Shoff64);
            --  Section headers beyond 4 GB would need a 64-bit Set_Index
            --  path; no toolchain produces that for these programs.
            if Shoff64 > Double_Word (Word'Last) then
               Ada.Streams.Stream_IO.Close (File);
               return;
            end if;
            E_Shoff := Word (Shoff64);
         end;
         Skip_Bytes (Stream, 4);  -- e_flags
         Skip_Bytes (Stream, 2);  -- e_ehsize
         Skip_Bytes (Stream, 4);  -- e_phentsize + e_phnum
         Read_Half (Stream, E_Shentsize);
         Read_Half (Stream, E_Shnum);
         Read_Half (Stream, E_Shstrndx);
      else
         --  ELF32 header layout after e_ident[4] (5 bytes read):
         --  11 bytes: rest of e_ident
         --   2 bytes: e_type
         --   2 bytes: e_machine
         --   4 bytes: e_version
         --   4 bytes: e_entry
         --   4 bytes: e_phoff
         --   4 bytes: e_shoff (at file offset 32)
         Skip_Bytes (Stream, 27);
         Read_Word (Stream, E_Shoff);

         --  After e_shoff:
         --  4 bytes: e_flags
         --  2 bytes: e_ehsize
         --  2 bytes: e_phentsize
         --  2 bytes: e_phnum
         --  2 bytes: e_shentsize (we want this)
         --  2 bytes: e_shnum (we want this)
         --  2 bytes: e_shstrndx (we want this)
         Skip_Bytes (Stream, 4);  -- e_flags
         Skip_Bytes (Stream, 2);  -- e_ehsize
         Skip_Bytes (Stream, 4);  -- e_phentsize + e_phnum
         Read_Half (Stream, E_Shentsize);
         Read_Half (Stream, E_Shnum);
         Read_Half (Stream, E_Shstrndx);
      end if;

      --  Find .symtab and .strtab sections
      for I in 0 .. Natural (E_Shnum) - 1 loop
         Ada.Streams.Stream_IO.Set_Index (File, Ada.Streams.Stream_IO.Positive_Count (E_Shoff + Word (I) * Word (E_Shentsize) + 1));

         declare
            Sh_Type : Word;
            Sh_Offset : Word;
            Sh_Size : Word;
            Sh_Link : Word;
            Sh_Entsize : Word;
            Tmp64 : Double_Word;
         begin
            if Is_64 then
               --  Elf64_Shdr: name(4) type(4) flags(8) addr(8) offset(8)
               --  size(8) link(4) info(4) addralign(8) entsize(8)
               Skip_Bytes (Stream, 4);  -- sh_name
               Read_Word (Stream, Sh_Type);
               Skip_Bytes (Stream, 8);  -- sh_flags
               Skip_Bytes (Stream, 8);  -- sh_addr
               Read_DWord (Stream, Tmp64);
               Sh_Offset := Word (Tmp64 and 16#FFFF_FFFF#);
               Read_DWord (Stream, Tmp64);
               Sh_Size := Word (Tmp64 and 16#FFFF_FFFF#);
               Read_Word (Stream, Sh_Link);
               Skip_Bytes (Stream, 4);  -- sh_info
               Skip_Bytes (Stream, 8);  -- sh_addralign
               Read_DWord (Stream, Tmp64);
               Sh_Entsize := Word (Tmp64 and 16#FFFF_FFFF#);
            else
               Skip_Bytes (Stream, 4);  -- sh_name
               Read_Word (Stream, Sh_Type);
               Skip_Bytes (Stream, 4);  -- sh_flags
               Skip_Bytes (Stream, 4);  -- sh_addr
               Read_Word (Stream, Sh_Offset);
               Read_Word (Stream, Sh_Size);
               Read_Word (Stream, Sh_Link);
               Skip_Bytes (Stream, 4);  -- sh_info
               Skip_Bytes (Stream, 4);  -- sh_addralign
               Read_Word (Stream, Sh_Entsize);
            end if;

            if Sh_Type = SHT_SYMTAB then
               Symtab_Offset := Sh_Offset;
               Symtab_Size := Sh_Size;
               Symtab_Entsize := Sh_Entsize;
               Symtab_Link := Sh_Link;
            elsif Sh_Type = SHT_STRTAB then
               if I = Natural (Symtab_Link) then
                  Strtab_Offset := Sh_Offset;
                  Strtab_Size := Sh_Size;
               end if;
            end if;
         end;
      end loop;

      --  Check if we found symbol table
      if Symtab_Offset = 0 or Strtab_Offset = 0 then
         Ada.Streams.Stream_IO.Close (File);
         return;
      end if;

      --  Load string table
      Ada.Streams.Stream_IO.Set_Index (File, Ada.Streams.Stream_IO.Positive_Count (Strtab_Offset + 1));
      for I in 1 .. Natural'Min (Natural (Strtab_Size), String_Data'Length) loop
         Byte'Read (Stream, String_Data (I));
      end loop;

      --  Parse symbol table
      declare
         Num_Symbols : constant Natural := Natural (Symtab_Size / Symtab_Entsize);
      begin
         Ada.Streams.Stream_IO.Set_Index (File, Ada.Streams.Stream_IO.Positive_Count (Symtab_Offset + 1));

         for I in 0 .. Num_Symbols - 1 loop
            exit when Syms.Count >= Max_Symbols;

            declare
               St_Name : Word;
               St_Value : Word;
               St_Size : Word;
               St_Info : Byte;
               St_Other : Byte;
               St_Shndx : Half_Word;
               Value64 : Double_Word := 0;
               Fits    : Boolean := True;

               Sym_TypeVal : Natural;
            begin
               if Is_64 then
                  --  Elf64_Sym reorders the fields relative to Elf32_Sym:
                  --  name(4) info(1) other(1) shndx(2) value(8) size(8),
                  --  where Elf32_Sym is name value size info other shndx.
                  declare
                     Size64 : Double_Word;
                  begin
                     Read_Word (Stream, St_Name);
                     Byte'Read (Stream, St_Info);
                     Byte'Read (Stream, St_Other);
                     Read_Half (Stream, St_Shndx);
                     Read_DWord (Stream, Value64);
                     Read_DWord (Stream, Size64);
                     St_Size := Word (Size64 and 16#FFFF_FFFF#);
                  end;
                  --  Symbol addresses are held in 32 bits throughout the
                  --  debugger, profiler and coverage tracker. Every RV64
                  --  program built here links below 4 GB; one that did not
                  --  could not be looked up anyway, so skip it rather than
                  --  record a wrong address.
                  Fits := Value64 <= Double_Word (Word'Last);
                  St_Value := Word (Value64 and 16#FFFF_FFFF#);
               else
                  Read_Word (Stream, St_Name);
                  Read_Word (Stream, St_Value);
                  Read_Word (Stream, St_Size);
                  Byte'Read (Stream, St_Info);
                  Byte'Read (Stream, St_Other);
                  Read_Half (Stream, St_Shndx);
               end if;

               Sym_TypeVal := Natural (St_Info) mod 16;

               --  Only store named, defined symbols
               if Fits and then
                  (St_Name > 0 and St_Shndx /= 0 and St_Value /= 0)
               then
                  Syms.Count := Syms.Count + 1;

                  Syms.Symbols (Syms.Count).Valid := True;
                  Syms.Symbols (Syms.Count).Address := Memory_Address (St_Value);
                  Syms.Symbols (Syms.Count).Size := St_Size;

                  --  Decode symbol type
                  case Sym_TypeVal is
                     when STT_FUNC =>
                        Syms.Symbols (Syms.Count).Sym_Type := SYM_FUNCTION;
                     when STT_OBJECT =>
                        Syms.Symbols (Syms.Count).Sym_Type := SYM_OBJECT;
                     when STT_SECTION =>
                        Syms.Symbols (Syms.Count).Sym_Type := SYM_SECTION;
                     when STT_FILE =>
                        Syms.Symbols (Syms.Count).Sym_Type := SYM_FILE;
                     when others =>
                        Syms.Symbols (Syms.Count).Sym_Type := SYM_UNKNOWN;
                  end case;

                  --  Extract symbol name from string table
                  declare
                     Str_Idx : Natural := Natural (St_Name) + 1;  -- +1 for 1-indexed array
                     Name_Len : Natural := 0;
                  begin
                     while Str_Idx <= String_Data'Last and then
                           String_Data (Str_Idx) /= 0 and then
                           Name_Len < 256
                     loop
                        Name_Len := Name_Len + 1;
                        Syms.Symbols (Syms.Count).Name (Name_Len) :=
                           Character'Val (String_Data (Str_Idx));
                        Str_Idx := Str_Idx + 1;
                     end loop;
                     Syms.Symbols (Syms.Count).Name_Len := Name_Len;
                  end;
               end if;
            end;
         end loop;
      end;

      Ada.Streams.Stream_IO.Close (File);
      Syms.Loaded := True;
      Success := True;

   exception
      when others =>
         if Ada.Streams.Stream_IO.Is_Open (File) then
            Ada.Streams.Stream_IO.Close (File);
         end if;
         Success := False;
   end Load_From_ELF;

   --  Lookup symbol by address
   function Lookup_By_Address (Syms : Symbol_Table;
                               Addr : Memory_Address;
                               Info : out Symbol_Info) return Boolean is
   begin
      for I in 1 .. Syms.Count loop
         if Syms.Symbols (I).Valid and then
            Syms.Symbols (I).Address <= Addr and then
            Addr < Syms.Symbols (I).Address + Memory_Address (Syms.Symbols (I).Size)
         then
            Info.Address := Syms.Symbols (I).Address;
            Info.Size := Syms.Symbols (I).Size;
            Info.Sym_Type := Syms.Symbols (I).Sym_Type;
            Info.Name (1 .. Syms.Symbols (I).Name_Len) :=
               Syms.Symbols (I).Name (1 .. Syms.Symbols (I).Name_Len);
            Info.Name_Len := Syms.Symbols (I).Name_Len;
            return True;
         end if;
      end loop;
      return False;
   end Lookup_By_Address;

   --  Lookup symbol by name
   function Lookup_By_Name (Syms : Symbol_Table;
                           Name : String;
                           Info : out Symbol_Info) return Boolean is
   begin
      for I in 1 .. Syms.Count loop
         if Syms.Symbols (I).Valid and then
            Syms.Symbols (I).Name (1 .. Syms.Symbols (I).Name_Len) = Name
         then
            Info.Address := Syms.Symbols (I).Address;
            Info.Size := Syms.Symbols (I).Size;
            Info.Sym_Type := Syms.Symbols (I).Sym_Type;
            Info.Name (1 .. Syms.Symbols (I).Name_Len) :=
               Syms.Symbols (I).Name (1 .. Syms.Symbols (I).Name_Len);
            Info.Name_Len := Syms.Symbols (I).Name_Len;
            return True;
         end if;
      end loop;
      return False;
   end Lookup_By_Name;

   --  Get symbol count
   function Get_Symbol_Count (Syms : Symbol_Table) return Natural is
   begin
      return Syms.Count;
   end Get_Symbol_Count;

   --  Get symbol by index
   function Get_Symbol (Syms : Symbol_Table;
                       Index : Natural;
                       Info : out Symbol_Info) return Boolean is
   begin
      if Index >= 1 and then Index <= Syms.Count and then
         Syms.Symbols (Index).Valid
      then
         Info.Address := Syms.Symbols (Index).Address;
         Info.Size := Syms.Symbols (Index).Size;
         Info.Sym_Type := Syms.Symbols (Index).Sym_Type;
         Info.Name (1 .. Syms.Symbols (Index).Name_Len) :=
            Syms.Symbols (Index).Name (1 .. Syms.Symbols (Index).Name_Len);
         Info.Name_Len := Syms.Symbols (Index).Name_Len;
         return True;
      end if;
      return False;
   end Get_Symbol;

   --  Print all symbols
   procedure Print_Symbols (Syms : Symbol_Table) is
      Info : Symbol_Info;
      Type_Str : String (1 .. 8);
   begin
      Ada.Text_IO.Put_Line ("Symbol Table (" & Natural'Image (Syms.Count) & " symbols):");
      Ada.Text_IO.Put_Line ("Address    Size       Type     Name");
      Ada.Text_IO.Put_Line ("---------- ---------- -------- --------------------------------");

      for I in 1 .. Syms.Count loop
         if Get_Symbol (Syms, I, Info) then
            case Info.Sym_Type is
               when SYM_FUNCTION => Type_Str := "FUNC    ";
               when SYM_OBJECT   => Type_Str := "OBJECT  ";
               when SYM_SECTION  => Type_Str := "SECTION ";
               when SYM_FILE     => Type_Str := "FILE    ";
               when others       => Type_Str := "UNKNOWN ";
            end case;

            Ada.Text_IO.Put (To_Hex (Word (Info.Address)));
            Ada.Text_IO.Put ("   ");
            Ada.Text_IO.Put (To_Hex (Info.Size));
            Ada.Text_IO.Put ("   ");
            Ada.Text_IO.Put (Type_Str);
            Ada.Text_IO.Put (" ");
            Ada.Text_IO.Put_Line (Info.Name (1 .. Info.Name_Len));
         end if;
      end loop;
   end Print_Symbols;

   --  Get function name at address
   function Get_Function_Name (Syms : Symbol_Table;
                              Addr : Memory_Address) return String is
      Info : Symbol_Info;
   begin
      if Lookup_By_Address (Syms, Addr, Info) and then
         Info.Sym_Type = SYM_FUNCTION
      then
         return Info.Name (1 .. Info.Name_Len);
      end if;
      return "";
   end Get_Function_Name;

end RISCV.Symbols;
