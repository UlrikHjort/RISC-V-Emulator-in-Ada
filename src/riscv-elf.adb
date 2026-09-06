-- ***************************************************************************
--                RISC-V Emulator - ELF Loader
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

with Ada.Streams.Stream_IO;
with Ada.Text_IO;

package body RISCV.ELF is

   use Ada.Streams.Stream_IO;

   --  ELF constants
   ELF_MAGIC      : constant := 16#464C457F#;  -- 0x7F 'E' 'L' 'F'
   ELFCLASS32     : constant := 1;
   ELFCLASS64     : constant := 2;
   ELFDATA2LSB    : constant := 1;  -- Little endian
   EM_RISCV       : constant := 243;
   PT_LOAD        : constant := 1;

   --  ELF32 header structure (52 bytes)
   type ELF32_Header is record
      E_Ident_Magic    : Word;       -- 0x7F 'E' 'L' 'F'
      E_Ident_Class    : Byte;       -- 1 = 32-bit
      E_Ident_Data     : Byte;       -- 1 = little endian
      E_Ident_Version  : Byte;
      E_Ident_OSABI    : Byte;
      E_Ident_Pad      : Word;       -- 8 bytes padding (we read as word + word)
      E_Ident_Pad2     : Word;
      E_Type           : Half_Word;  -- Object file type
      E_Machine        : Half_Word;  -- Machine type
      E_Version        : Word;       -- Object file version
      E_Entry          : Word;       -- Entry point address
      E_Phoff          : Word;       -- Program header offset
      E_Shoff          : Word;       -- Section header offset
      E_Flags          : Word;       -- Processor flags
      E_Ehsize         : Half_Word;  -- ELF header size
      E_Phentsize      : Half_Word;  -- Program header entry size
      E_Phnum          : Half_Word;  -- Program header count
      E_Shentsize      : Half_Word;  -- Section header entry size
      E_Shnum          : Half_Word;  -- Section header count
      E_Shstrndx       : Half_Word;  -- Section name string table index
   end record;

   --  ELF32 program header (32 bytes)
   type ELF32_Phdr is record
      P_Type   : Word;       -- Segment type
      P_Offset : Word;       -- Segment offset in file
      P_Vaddr  : Word;       -- Virtual address
      P_Paddr  : Word;       -- Physical address
      P_Filesz : Word;       -- Size in file
      P_Memsz  : Word;       -- Size in memory
      P_Flags  : Word;       -- Segment flags
      P_Align  : Word;       -- Alignment
   end record;

   --  Helper to read bytes
   function Read_Byte (Stream : Stream_Access) return Byte;
   function Read_Half (Stream : Stream_Access) return Half_Word;
   function Read_Word (Stream : Stream_Access) return Word;

   function Read_Byte (Stream : Stream_Access) return Byte is
      B : Byte;
   begin
      Byte'Read (Stream, B);
      return B;
   end Read_Byte;

   function Read_Half (Stream : Stream_Access) return Half_Word is
      B0, B1 : Byte;
   begin
      Byte'Read (Stream, B0);
      Byte'Read (Stream, B1);
      return Half_Word (B0) or Shift_Left (Half_Word (B1), 8);
   end Read_Half;

   function Read_Word (Stream : Stream_Access) return Word is
      B0, B1, B2, B3 : Byte;
   begin
      Byte'Read (Stream, B0);
      Byte'Read (Stream, B1);
      Byte'Read (Stream, B2);
      Byte'Read (Stream, B3);
      return Word (B0) or
             Shift_Left (Word (B1), 8) or
             Shift_Left (Word (B2), 16) or
             Shift_Left (Word (B3), 24);
   end Read_Word;

   --  Read 8 bytes little-endian as Double_Word
   function Read_DWord (Stream : Stream_Access) return Double_Word is
      B0, B1, B2, B3, B4, B5, B6, B7 : Byte;
   begin
      Byte'Read (Stream, B0);
      Byte'Read (Stream, B1);
      Byte'Read (Stream, B2);
      Byte'Read (Stream, B3);
      Byte'Read (Stream, B4);
      Byte'Read (Stream, B5);
      Byte'Read (Stream, B6);
      Byte'Read (Stream, B7);
      return Double_Word (B0) or
             Shift_Left (Double_Word (B1), 8) or
             Shift_Left (Double_Word (B2), 16) or
             Shift_Left (Double_Word (B3), 24) or
             Shift_Left (Double_Word (B4), 32) or
             Shift_Left (Double_Word (B5), 40) or
             Shift_Left (Double_Word (B6), 48) or
             Shift_Left (Double_Word (B7), 56);
   end Read_DWord;

   --  ELF64 header (64 bytes)
   type ELF64_Header is record
      E_Ident_Magic   : Word;
      E_Ident_Class   : Byte;
      E_Ident_Data    : Byte;
      E_Ident_Version : Byte;
      E_Ident_OSABI   : Byte;
      E_Ident_Pad     : Word;
      E_Ident_Pad2    : Word;
      E_Type          : Half_Word;
      E_Machine       : Half_Word;
      E_Version       : Word;
      E_Entry         : Double_Word;
      E_Phoff         : Double_Word;
      E_Shoff         : Double_Word;
      E_Flags         : Word;
      E_Ehsize        : Half_Word;
      E_Phentsize     : Half_Word;
      E_Phnum         : Half_Word;
      E_Shentsize     : Half_Word;
      E_Shnum         : Half_Word;
      E_Shstrndx      : Half_Word;
   end record;

   --  ELF64 program header (56 bytes; note P_Flags position differs from ELF32)
   type ELF64_Phdr is record
      P_Type   : Word;
      P_Flags  : Word;          -- at offset 4 (swapped vs ELF32)
      P_Offset : Double_Word;
      P_Vaddr  : Double_Word;
      P_Paddr  : Double_Word;
      P_Filesz : Double_Word;
      P_Memsz  : Double_Word;
      P_Align  : Double_Word;
   end record;

   procedure Read_Header64 (Stream : Stream_Access;
                             Header : out ELF64_Header);

   procedure Read_Header64 (Stream : Stream_Access;
                             Header : out ELF64_Header) is
   begin
      Header.E_Ident_Magic   := Read_Word (Stream);
      Header.E_Ident_Class   := Read_Byte (Stream);
      Header.E_Ident_Data    := Read_Byte (Stream);
      Header.E_Ident_Version := Read_Byte (Stream);
      Header.E_Ident_OSABI   := Read_Byte (Stream);
      Header.E_Ident_Pad     := Read_Word (Stream);
      Header.E_Ident_Pad2    := Read_Word (Stream);
      Header.E_Type          := Read_Half (Stream);
      Header.E_Machine       := Read_Half (Stream);
      Header.E_Version       := Read_Word (Stream);
      Header.E_Entry         := Read_DWord (Stream);
      Header.E_Phoff         := Read_DWord (Stream);
      Header.E_Shoff         := Read_DWord (Stream);
      Header.E_Flags         := Read_Word (Stream);
      Header.E_Ehsize        := Read_Half (Stream);
      Header.E_Phentsize     := Read_Half (Stream);
      Header.E_Phnum         := Read_Half (Stream);
      Header.E_Shentsize     := Read_Half (Stream);
      Header.E_Shnum         := Read_Half (Stream);
      Header.E_Shstrndx      := Read_Half (Stream);
   end Read_Header64;

   procedure Read_Phdr64 (Stream : Stream_Access;
                          Phdr   : out ELF64_Phdr);

   procedure Read_Phdr64 (Stream : Stream_Access;
                          Phdr   : out ELF64_Phdr) is
   begin
      Phdr.P_Type   := Read_Word  (Stream);
      Phdr.P_Flags  := Read_Word  (Stream);
      Phdr.P_Offset := Read_DWord (Stream);
      Phdr.P_Vaddr  := Read_DWord (Stream);
      Phdr.P_Paddr  := Read_DWord (Stream);
      Phdr.P_Filesz := Read_DWord (Stream);
      Phdr.P_Memsz  := Read_DWord (Stream);
      Phdr.P_Align  := Read_DWord (Stream);
   end Read_Phdr64;

   --  Read ELF header
   procedure Read_Header (Stream : Stream_Access;
                          Header : out ELF32_Header);

   procedure Read_Header (Stream : Stream_Access;
                          Header : out ELF32_Header) is
   begin
      Header.E_Ident_Magic   := Read_Word (Stream);
      Header.E_Ident_Class   := Read_Byte (Stream);
      Header.E_Ident_Data    := Read_Byte (Stream);
      Header.E_Ident_Version := Read_Byte (Stream);
      Header.E_Ident_OSABI   := Read_Byte (Stream);
      Header.E_Ident_Pad     := Read_Word (Stream);
      Header.E_Ident_Pad2    := Read_Word (Stream);
      Header.E_Type          := Read_Half (Stream);
      Header.E_Machine       := Read_Half (Stream);
      Header.E_Version       := Read_Word (Stream);
      Header.E_Entry         := Read_Word (Stream);
      Header.E_Phoff         := Read_Word (Stream);
      Header.E_Shoff         := Read_Word (Stream);
      Header.E_Flags         := Read_Word (Stream);
      Header.E_Ehsize        := Read_Half (Stream);
      Header.E_Phentsize     := Read_Half (Stream);
      Header.E_Phnum         := Read_Half (Stream);
      Header.E_Shentsize     := Read_Half (Stream);
      Header.E_Shnum         := Read_Half (Stream);
      Header.E_Shstrndx      := Read_Half (Stream);
   end Read_Header;

   --  Read program header
   procedure Read_Phdr (Stream : Stream_Access;
                        Phdr   : out ELF32_Phdr);

   procedure Read_Phdr (Stream : Stream_Access;
                        Phdr   : out ELF32_Phdr) is
   begin
      Phdr.P_Type   := Read_Word (Stream);
      Phdr.P_Offset := Read_Word (Stream);
      Phdr.P_Vaddr  := Read_Word (Stream);
      Phdr.P_Paddr  := Read_Word (Stream);
      Phdr.P_Filesz := Read_Word (Stream);
      Phdr.P_Memsz  := Read_Word (Stream);
      Phdr.P_Flags  := Read_Word (Stream);
      Phdr.P_Align  := Read_Word (Stream);
   end Read_Phdr;

   --------------
   -- Load_ELF --
   --------------

   procedure Load_ELF (Filename    : String;
                       Mem         : in out Memory.Memory_Unit;
                       Info        : out ELF_Info;
                       Result      : out Load_Result;
                       Verbose     : Boolean := False) is
      File   : File_Type;
      Stream : Stream_Access;
      Header : ELF32_Header;
      Phdr   : ELF32_Phdr;
      B      : Byte;
   begin
      --  Initialize info
      Info := (Entry_Point  => 0,
               Num_Segments => 0,
               Load_Address => Word'Last,
               End_Address  => 0);

      --  Open file
      begin
         Open (File, In_File, Filename);
      exception
         when others =>
            Result := File_Not_Found;
            return;
      end;

      Stream := Ada.Streams.Stream_IO.Stream (File);

      --  Read ELF header
      begin
         Read_Header (Stream, Header);
      exception
         when others =>
            Close (File);
            Result := Invalid_Format;
            return;
      end;

      --  Validate ELF magic
      if Header.E_Ident_Magic /= ELF_MAGIC then
         Close (File);
         Result := Invalid_Magic;
         return;
      end if;

      --  Check class (32-bit)
      if Header.E_Ident_Class /= ELFCLASS32 then
         Close (File);
         Result := Wrong_Class;
         return;
      end if;

      --  Check endianness (little endian)
      if Header.E_Ident_Data /= ELFDATA2LSB then
         Close (File);
         Result := Wrong_Endian;
         return;
      end if;

      --  Check machine (RISC-V)
      if Header.E_Machine /= EM_RISCV then
         Close (File);
         Result := Wrong_Machine;
         return;
      end if;

      Info.Entry_Point := Header.E_Entry;

      if Verbose then
         Ada.Text_IO.Put_Line ("ELF Entry point: 0x" &
            Word'Image (Header.E_Entry));
         Ada.Text_IO.Put_Line ("Program headers:" &
            Half_Word'Image (Header.E_Phnum));
      end if;

      --  Process program headers
      for I in 1 .. Natural (Header.E_Phnum) loop
         --  Seek to program header
         Set_Index (File, Positive_Count (Header.E_Phoff +
            Word (I - 1) * Word (Header.E_Phentsize) + 1));

         Read_Phdr (Stream, Phdr);

         --  Only process PT_LOAD segments
         if Phdr.P_Type = PT_LOAD then
            Info.Num_Segments := Info.Num_Segments + 1;

            if Verbose then
               Ada.Text_IO.Put_Line ("  Segment" & Natural'Image (I) &
                  ": vaddr=0x" & Word'Image (Phdr.P_Vaddr) &
                  " offset=0x" & Word'Image (Phdr.P_Offset) &
                  " filesz=" & Word'Image (Phdr.P_Filesz) &
                  " memsz=" & Word'Image (Phdr.P_Memsz));
            end if;

            --  Update address range
            if Phdr.P_Vaddr < Info.Load_Address then
               Info.Load_Address := Phdr.P_Vaddr;
            end if;
            if Phdr.P_Vaddr + Phdr.P_Memsz > Info.End_Address then
               Info.End_Address := Phdr.P_Vaddr + Phdr.P_Memsz;
            end if;

            --  Load segment data from file
            if Phdr.P_Filesz > 0 then
               Set_Index (File, Positive_Count (Phdr.P_Offset + 1));

               for Offset in 0 .. Phdr.P_Filesz - 1 loop
                  Byte'Read (Stream, B);
                  Memory.Write_Byte (Mem,
                     Memory_Address (Phdr.P_Vaddr + Offset), B);
               end loop;
            end if;

            --  Zero-fill remainder (BSS)
            if Phdr.P_Memsz > Phdr.P_Filesz then
               for Offset in Phdr.P_Filesz .. Phdr.P_Memsz - 1 loop
                  Memory.Write_Byte (Mem,
                     Memory_Address (Phdr.P_Vaddr + Offset), 0);
               end loop;
            end if;
         end if;
      end loop;

      Close (File);
      Result := Success;

   exception
      when others =>
         if Is_Open (File) then
            Close (File);
         end if;
         Result := Load_Error;
   end Load_ELF;

   -----------------
   -- Is_ELF_File --
   -----------------

   function Is_ELF_File (Filename : String) return Boolean is
      File   : File_Type;
      Stream : Stream_Access;
      Magic  : Word;
   begin
      begin
         Open (File, In_File, Filename);
      exception
         when others =>
            return False;
      end;

      Stream := Ada.Streams.Stream_IO.Stream (File);

      begin
         Magic := Read_Word (Stream);
      exception
         when others =>
            Close (File);
            return False;
      end;

      Close (File);
      return Magic = ELF_MAGIC;
   end Is_ELF_File;

   -------------------
   -- Get_ELF_Class --
   -------------------

   function Get_ELF_Class (Filename : String) return Natural is
      File   : File_Type;
      Stream : Stream_Access;
      Magic  : Word;
      Class  : Byte;
   begin
      begin
         Open (File, In_File, Filename);
      exception
         when others =>
            return 0;
      end;
      Stream := Ada.Streams.Stream_IO.Stream (File);
      begin
         Magic := Read_Word (Stream);
         Class := Read_Byte (Stream);
      exception
         when others =>
            Close (File);
            return 0;
      end;
      Close (File);
      if Magic /= ELF_MAGIC then
         return 0;
      end if;
      return Natural (Class);
   end Get_ELF_Class;

   ----------------
   -- Load_ELF64 --
   ----------------

   procedure Load_ELF64 (Filename    : String;
                         Mem         : in out Memory.Memory_Unit;
                         Info        : out ELF_Info_64;
                         Result      : out Load_Result;
                         Verbose     : Boolean := False) is
      File   : File_Type;
      Stream : Stream_Access;
      Header : ELF64_Header;
      Phdr   : ELF64_Phdr;
      B      : Byte;
   begin
      Info := (Entry_Point  => 0,
               Num_Segments => 0,
               Load_Address => Double_Word'Last,
               End_Address  => 0);

      begin
         Open (File, In_File, Filename);
      exception
         when others =>
            Result := File_Not_Found;
            return;
      end;

      Stream := Ada.Streams.Stream_IO.Stream (File);

      begin
         Read_Header64 (Stream, Header);
      exception
         when others =>
            Close (File);
            Result := Invalid_Format;
            return;
      end;

      if Header.E_Ident_Magic /= ELF_MAGIC then
         Close (File);
         Result := Invalid_Magic;
         return;
      end if;

      if Header.E_Ident_Class /= ELFCLASS64 then
         Close (File);
         Result := Wrong_Class;
         return;
      end if;

      if Header.E_Ident_Data /= ELFDATA2LSB then
         Close (File);
         Result := Wrong_Endian;
         return;
      end if;

      if Header.E_Machine /= EM_RISCV then
         Close (File);
         Result := Wrong_Machine;
         return;
      end if;

      Info.Entry_Point := Header.E_Entry;

      if Verbose then
         Ada.Text_IO.Put_Line ("ELF64 Entry point: 0x" &
            Double_Word'Image (Header.E_Entry));
         Ada.Text_IO.Put_Line ("Program headers:" &
            Half_Word'Image (Header.E_Phnum));
      end if;

      for I in 1 .. Natural (Header.E_Phnum) loop
         Set_Index (File, Positive_Count (
            Header.E_Phoff +
            Double_Word (I - 1) * Double_Word (Header.E_Phentsize) + 1));

         Read_Phdr64 (Stream, Phdr);

         if Phdr.P_Type = PT_LOAD then
            Info.Num_Segments := Info.Num_Segments + 1;

            if Verbose then
               Ada.Text_IO.Put_Line ("  Segment" & Natural'Image (I) &
                  ": vaddr=0x" & Double_Word'Image (Phdr.P_Vaddr) &
                  " filesz=" & Double_Word'Image (Phdr.P_Filesz));
            end if;

            if Phdr.P_Vaddr < Info.Load_Address then
               Info.Load_Address := Phdr.P_Vaddr;
            end if;
            if Phdr.P_Vaddr + Phdr.P_Memsz > Info.End_Address then
               Info.End_Address := Phdr.P_Vaddr + Phdr.P_Memsz;
            end if;

            if Phdr.P_Filesz > 0 then
               Set_Index (File, Positive_Count (Phdr.P_Offset + 1));
               for Offset in Double_Word range 0 .. Phdr.P_Filesz - 1 loop
                  Byte'Read (Stream, B);
                  Memory.Write_Byte (Mem,
                     Memory_Address (Phdr.P_Vaddr + Offset), B);
               end loop;
            end if;

            if Phdr.P_Memsz > Phdr.P_Filesz then
               for Offset in Double_Word range
                  Phdr.P_Filesz .. Phdr.P_Memsz - 1 loop
                  Memory.Write_Byte (Mem,
                     Memory_Address (Phdr.P_Vaddr + Offset), 0);
               end loop;
            end if;
         end if;
      end loop;

      Close (File);
      Result := Success;

   exception
      when others =>
         if Is_Open (File) then
            Close (File);
         end if;
         Result := Load_Error;
   end Load_ELF64;

   -------------------
   -- Error_Message --
   -------------------

   function Error_Message (Result : Load_Result) return String is
   begin
      case Result is
         when Success =>
            return "Success";
         when File_Not_Found =>
            return "File not found";
         when Invalid_Magic =>
            return "Invalid ELF magic number";
         when Wrong_Class =>
            return "Not a supported ELF class (expected 32-bit or 64-bit RISC-V)";
         when Wrong_Endian =>
            return "Not a little-endian ELF file";
         when Wrong_Machine =>
            return "Not a RISC-V ELF file";
         when Invalid_Format =>
            return "Invalid ELF format";
         when Load_Error =>
            return "Error loading ELF file";
      end case;
   end Error_Message;

end RISCV.ELF;
