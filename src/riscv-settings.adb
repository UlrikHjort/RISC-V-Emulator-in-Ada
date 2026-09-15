-- ***************************************************************************
--          RISC-V Emulator - Runtime configuration
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
with Ada.Environment_Variables;
with Ada.Directories;
with Ada.Strings.Fixed;
with Ada.Strings.Maps.Constants;
with Interfaces.C;

package body RISCV.Settings is

   use Ada.Strings;

   --  ---- small string helpers ------------------------------------------

   function Trim (S : String) return String is
   begin
      return Fixed.Trim (S, Both);
   end Trim;

   function Lower (S : String) return String is
      R : String := S;
   begin
      for I in R'Range loop
         R (I) := Maps.Value (Maps.Constants.Lower_Case_Map, R (I));
      end loop;
      return R;
   end Lower;

   function Env (Name : String) return String is
   begin
      if Ada.Environment_Variables.Exists (Name) then
         return Ada.Environment_Variables.Value (Name);
      end if;
      return "";
   end Env;

   function Home return String is (Env ("HOME"));

   function XDG_Config return String is
      X : constant String := Env ("XDG_CONFIG_HOME");
   begin
      if X /= "" then
         return X;
      elsif Home /= "" then
         return Home & "/.config";
      end if;
      return "";
   end XDG_Config;

   --  Expand a leading "~/" to $HOME.
   function Expand_Tilde (S : String) return String is
   begin
      if S'Length >= 2 and then S (S'First .. S'First + 1) = "~/"
        and then Home /= ""
      then
         return Home & S (S'First + 1 .. S'Last);
      end if;
      return S;
   end Expand_Tilde;

   procedure Set (Item : in out Setting; Value : String) is
      L : constant Natural := Natural'Min (Value'Length, Max_Val);
   begin
      Item.Present := True;
      Item.Length  := L;
      Item.Value   := (others => ' ');
      if L > 0 then
         Item.Value (1 .. L) := Value (Value'First .. Value'First + L - 1);
      end if;
   end Set;

   --  ---- rc file parsing -----------------------------------------------

   procedure Apply_Line (Cfg : in out RC_Config; Line : String) is
      T : constant String := Trim (Line);
   begin
      if T'Length = 0 or else T (T'First) = '#' or else T (T'First) = ';' then
         return;
      end if;
      declare
         Eq : constant Natural := Fixed.Index (T, "=");
      begin
         if Eq = 0 then
            Ada.Text_IO.Put_Line
              (Ada.Text_IO.Standard_Error,
               "Warning: ignoring malformed rc line: " & T);
            return;
         end if;
         declare
            Key : constant String := Lower (Trim (T (T'First .. Eq - 1)));
            Val : constant String := Expand_Tilde (Trim (T (Eq + 1 .. T'Last)));
         begin
            if    Key = "machine"      then Set (Cfg.Machine, Val);
            elsif Key = "config"       then Set (Cfg.Config, Val);
            elsif Key = "host-io"      then Set (Cfg.Host_IO, Val);
            elsif Key = "host-io-root" then Set (Cfg.Host_IO_Root, Val);
            elsif Key = "log-dir"      then Set (Cfg.Log_Dir, Val);
            else
               Ada.Text_IO.Put_Line
                 (Ada.Text_IO.Standard_Error,
                  "Warning: unknown rc key '" & Key & "' (ignored)");
            end if;
         end;
      end;
   end Apply_Line;

   procedure Read_File (Cfg : in out RC_Config; Path : String) is
      use Ada.Text_IO;
      F : File_Type;
   begin
      if Path = "" or else not Ada.Directories.Exists (Path) then
         return;
      end if;
      Open (F, In_File, Path);
      while not End_Of_File (F) loop
         Apply_Line (Cfg, Get_Line (F));
      end loop;
      Close (F);
      --  Record this as the (most specific so far) source.
      declare
         L : constant Natural := Natural'Min (Path'Length, Max_Val);
      begin
         Cfg.Source := (others => ' ');
         Cfg.Source (1 .. L) := Path (Path'First .. Path'First + L - 1);
         Cfg.Source_Len := L;
      end;
   exception
      when others =>
         if Is_Open (F) then
            Close (F);
         end if;
   end Read_File;

   function Read_RC return RC_Config is
      Cfg : RC_Config;
   begin
      --  Least specific first; later files override earlier keys.
      if Home /= "" then
         Read_File (Cfg, Home & "/.riscv_emulatorrc");
      end if;
      if XDG_Config /= "" then
         Read_File (Cfg, XDG_Config & "/riscv_emulator/config");
      end if;
      Read_File (Cfg, Env ("RISCV_EMULATORRC"));  --  explicit path wins
      return Cfg;
   end Read_RC;

   --  ---- profile search path -------------------------------------------

   --  Directory of the running executable via /proc/self/exe (Linux).
   --  Returns "" if it cannot be determined.
   function Exe_Dir return String is
      use Interfaces.C;
      function readlink (Path : char_array; Buf : out char_array;
                         Bufsz : size_t) return long;
      pragma Import (C, readlink, "readlink");

      Buf : char_array (0 .. 4095);
      N   : long;
   begin
      N := readlink (To_C ("/proc/self/exe"), Buf, Buf'Length);
      if N <= 0 then
         return "";
      end if;
      declare
         Full : constant String := To_Ada (Buf (0 .. size_t (N) - 1), False);
         Slash : constant Natural := Fixed.Index (Full, "/", Backward);
      begin
         if Slash = 0 then
            return "";
         end if;
         return Full (Full'First .. Slash - 1);
      end;
   exception
      when others => return "";
   end Exe_Dir;

   --  Build the ordered list of profile directories to search.
   type Dir_List is array (1 .. 16) of Setting;

   procedure Search_Dirs (Dirs : out Dir_List; Count : out Natural) is
      procedure Add (D : String) is
      begin
         if D /= "" and then Count < Dirs'Last then
            Count := Count + 1;
            Set (Dirs (Count), D);
         end if;
      end Add;
   begin
      Count := 0;
      Add (".");
      --  $RISCV_EMULATOR_PROFILES (colon-separated).
      declare
         P : constant String := Env ("RISCV_EMULATOR_PROFILES");
         First : Natural := P'First;
      begin
         for I in P'Range loop
            if P (I) = ':' then
               if I > First then Add (P (First .. I - 1)); end if;
               First := I + 1;
            end if;
         end loop;
         if P'Length > 0 and then First <= P'Last then
            Add (P (First .. P'Last));
         end if;
      end;
      if XDG_Config /= "" then
         Add (XDG_Config & "/riscv_emulator/profiles");
      end if;
      declare
         E : constant String := Exe_Dir;
      begin
         if E /= "" then
            Add (E & "/../share/riscv_emulator/profiles");
         end if;
      end;
   end Search_Dirs;

   function Resolve_Profile (Name : String) return String is
      Dirs  : Dir_List;
      Count : Natural;
   begin
      --  A path, or an existing file: use as given.
      if Fixed.Index (Name, "/") /= 0
        or else Ada.Directories.Exists (Name)
      then
         return Name;
      end if;

      Search_Dirs (Dirs, Count);
      for I in 1 .. Count loop
         declare
            D : constant String := Dirs (I).Value (1 .. Dirs (I).Length);
            C1 : constant String := D & "/" & Name;
            C2 : constant String := D & "/" & Name & ".cfg";
         begin
            if Ada.Directories.Exists (C2) then
               return C2;
            elsif Ada.Directories.Exists (C1) then
               return C1;
            end if;
         end;
      end loop;
      return "";
   end Resolve_Profile;

   function Profile_Search_Description return String is
      Dirs  : Dir_List;
      Count : Natural;
      R     : String (1 .. Max_Val * 2) := (others => ' ');
      Pos   : Natural := 0;
      procedure Append (S : String) is
      begin
         if Pos + S'Length <= R'Last then
            R (Pos + 1 .. Pos + S'Length) := S;
            Pos := Pos + S'Length;
         end if;
      end Append;
   begin
      Search_Dirs (Dirs, Count);
      for I in 1 .. Count loop
         if I > 1 then Append (", "); end if;
         Append (Dirs (I).Value (1 .. Dirs (I).Length));
      end loop;
      return R (1 .. Pos);
   end Profile_Search_Description;

end RISCV.Settings;
