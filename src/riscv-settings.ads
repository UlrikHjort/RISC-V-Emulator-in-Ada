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

--  ---------------------------------------------------------------------------
--  RISCV.Settings -- runtime configuration from an rc file, and resolution of
--  profile names to files.
--
--  rc file: a simple "key = value" file read before the command line, so it
--  only supplies DEFAULTS that command-line flags override. Two locations are
--  read (later overrides earlier), plus an explicit override:
--     1. $HOME/.riscv_emulatorrc                      (classic)
--     2. $XDG_CONFIG_HOME/riscv_emulator/config       (or ~/.config/...)
--     3. $RISCV_EMULATORRC                            (explicit path, wins)
--
--  Recognised keys mirror the command-line flags:
--     machine, config, host-io, host-io-root, log-dir
--  Lines beginning with '#' or ';' are comments; a leading "~/" in a value is
--  expanded to $HOME. Unknown keys are warned about, not fatal.
--  ---------------------------------------------------------------------------

package RISCV.Settings is

   Max_Val : constant := 512;

   type Setting is record
      Present : Boolean := False;
      Value   : String (1 .. Max_Val) := (others => ' ');
      Length  : Natural := 0;
   end record;

   type RC_Config is record
      Machine      : Setting;
      Config       : Setting;
      Host_IO      : Setting;
      Host_IO_Root : Setting;
      Log_Dir      : Setting;
      --  The most specific rc file that was actually read (for --verbose).
      Source       : String (1 .. Max_Val) := (others => ' ');
      Source_Len   : Natural := 0;
   end record;

   --  Read and merge the rc file(s). Warnings for unknown keys go to stderr.
   function Read_RC return RC_Config;

   --  Resolve a --config argument to an actual file path. If Name is a path
   --  (contains '/') or already names an existing file it is returned as-is;
   --  otherwise the profile search path is tried for "<Name>" and
   --  "<Name>.cfg". Returns "" when nothing is found.
   function Resolve_Profile (Name : String) return String;

   --  Human-readable list of the directories Resolve_Profile searches, for
   --  a "not found" diagnostic.
   function Profile_Search_Description return String;

end RISCV.Settings;
