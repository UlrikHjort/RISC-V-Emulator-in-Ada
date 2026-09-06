-- ***************************************************************************
--         RISC-V Emulator - CLINT (Core Local Interruptor)
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

package body RISCV.CLINT is

   ----------------
   -- Initialize --
   ----------------

   procedure Initialize (C    : out CLINT_State;
                         Base : Memory_Address := Default_Base_Address) is
   begin
      C.Base_Address    := Base;
      C.Enabled         := True;
      C.Mtime           := 0;
      C.Mtimecmp        := (others => Timer_Value'Last);
      C.Msip            := (others => False);
      C.Timer_Interrupt := (others => False);
   end Initialize;

   ----------------------
   -- Is_CLINT_Address --
   ----------------------

   function Is_CLINT_Address (C    : CLINT_State;
                              Addr : Memory_Address) return Boolean is
   begin
      if not C.Enabled then
         return False;
      end if;
      return Addr >= C.Base_Address and
             Addr < C.Base_Address + CLINT_Size;
   end Is_CLINT_Address;

   ---------------
   -- Read_Byte --
   ---------------

   function Read_Byte (C    : CLINT_State;
                       Addr : Memory_Address) return Byte is
      Offset   : constant Memory_Address := Addr - C.Base_Address;
      Byte_Idx : Natural;
      Value64  : Timer_Value;
   begin
      --  MSIP hart 0 (offset 0x0000, 4 bytes)
      if Offset < REG_MSIP1 then
         Byte_Idx := Natural (Offset);
         if Byte_Idx = 0 then
            return (if C.Msip (0) then 1 else 0);
         else
            return 0;
         end if;

      --  MSIP hart 1 (offset 0x0004, 4 bytes)
      elsif Offset < REG_MSIP1 + 4 then
         Byte_Idx := Natural (Offset - REG_MSIP1);
         if Byte_Idx = 0 then
            return (if C.Msip (1) then 1 else 0);
         else
            return 0;
         end if;

      --  MTIMECMP hart 0 (offset 0x4000, 8 bytes)
      elsif Offset >= REG_MTIMECMP and Offset < REG_MTIMECMP + 8 then
         Byte_Idx := Natural (Offset - REG_MTIMECMP);
         Value64 := C.Mtimecmp (0);
         return Byte (Shift_Right (Value64, Byte_Idx * 8) and 16#FF#);

      --  MTIMECMP hart 1 (offset 0x4008, 8 bytes)
      elsif Offset >= REG_MTIMECMP1 and Offset < REG_MTIMECMP1 + 8 then
         Byte_Idx := Natural (Offset - REG_MTIMECMP1);
         Value64 := C.Mtimecmp (1);
         return Byte (Shift_Right (Value64, Byte_Idx * 8) and 16#FF#);

      --  MTIME register (offset 0xBFF8, 8 bytes)
      elsif Offset >= REG_MTIME and Offset < REG_MTIME + 8 then
         Byte_Idx := Natural (Offset - REG_MTIME);
         Value64 := C.Mtime;
         return Byte (Shift_Right (Value64, Byte_Idx * 8) and 16#FF#);

      else
         --  Unmapped region within CLINT
         return 0;
      end if;
   end Read_Byte;

   ---------------
   -- Read_Word --
   ---------------

   function Read_Word (C    : CLINT_State;
                       Addr : Memory_Address) return Word is
      Offset  : constant Memory_Address := Addr - C.Base_Address;
      Value64 : Timer_Value;
   begin
      --  MSIP hart 0 (offset 0x0000)
      if Offset = 0 then
         return (if C.Msip (0) then 1 else 0);

      --  MSIP hart 1 (offset 0x0004)
      elsif Offset = REG_MSIP1 then
         return (if C.Msip (1) then 1 else 0);

      --  MTIMECMP hart 0 low word (offset 0x4000)
      elsif Offset = REG_MTIMECMP then
         return Word (C.Mtimecmp (0) and 16#FFFF_FFFF#);

      --  MTIMECMP hart 0 high word (offset 0x4004)
      elsif Offset = REG_MTIMECMP + 4 then
         Value64 := Shift_Right (C.Mtimecmp (0), 32);
         return Word (Value64 and 16#FFFF_FFFF#);

      --  MTIMECMP hart 1 low word (offset 0x4008)
      elsif Offset = REG_MTIMECMP1 then
         return Word (C.Mtimecmp (1) and 16#FFFF_FFFF#);

      --  MTIMECMP hart 1 high word (offset 0x400C)
      elsif Offset = REG_MTIMECMP1 + 4 then
         Value64 := Shift_Right (C.Mtimecmp (1), 32);
         return Word (Value64 and 16#FFFF_FFFF#);

      --  MTIME low word (offset 0xBFF8)
      elsif Offset = REG_MTIME then
         return Word (C.Mtime and 16#FFFF_FFFF#);

      --  MTIME high word (offset 0xBFFC)
      elsif Offset = REG_MTIME + 4 then
         Value64 := Shift_Right (C.Mtime, 32);
         return Word (Value64 and 16#FFFF_FFFF#);

      else
         --  Other addresses: byte-wise read
         return Word (Read_Byte (C, Addr)) or
                Shift_Left (Word (Read_Byte (C, Addr + 1)), 8) or
                Shift_Left (Word (Read_Byte (C, Addr + 2)), 16) or
                Shift_Left (Word (Read_Byte (C, Addr + 3)), 24);
      end if;
   end Read_Word;

   ----------------
   -- Write_Byte --
   ----------------

   procedure Write_Byte (C    : in out CLINT_State;
                         Addr : Memory_Address;
                         Data : Byte) is
      Offset   : constant Memory_Address := Addr - C.Base_Address;
      Byte_Idx : Natural;
      Mask     : Timer_Value;
      Shifted  : Timer_Value;
   begin
      --  MSIP hart 0 (offset 0x0000, 4 bytes)
      if Offset < REG_MSIP1 then
         Byte_Idx := Natural (Offset);
         if Byte_Idx = 0 then
            C.Msip (0) := (Data and 1) /= 0;
         end if;

      --  MSIP hart 1 (offset 0x0004, 4 bytes)
      elsif Offset < REG_MSIP1 + 4 then
         Byte_Idx := Natural (Offset - REG_MSIP1);
         if Byte_Idx = 0 then
            C.Msip (1) := (Data and 1) /= 0;
         end if;

      --  MTIMECMP hart 0 (offset 0x4000, 8 bytes)
      elsif Offset >= REG_MTIMECMP and Offset < REG_MTIMECMP + 8 then
         Byte_Idx := Natural (Offset - REG_MTIMECMP);
         Mask := Shift_Left (16#FF#, Byte_Idx * 8);
         Shifted := Shift_Left (Timer_Value (Data), Byte_Idx * 8);
         C.Mtimecmp (0) := (C.Mtimecmp (0) and not Mask) or Shifted;
         C.Timer_Interrupt (0) := C.Mtime >= C.Mtimecmp (0);

      --  MTIMECMP hart 1 (offset 0x4008, 8 bytes)
      elsif Offset >= REG_MTIMECMP1 and Offset < REG_MTIMECMP1 + 8 then
         Byte_Idx := Natural (Offset - REG_MTIMECMP1);
         Mask := Shift_Left (16#FF#, Byte_Idx * 8);
         Shifted := Shift_Left (Timer_Value (Data), Byte_Idx * 8);
         C.Mtimecmp (1) := (C.Mtimecmp (1) and not Mask) or Shifted;
         C.Timer_Interrupt (1) := C.Mtime >= C.Mtimecmp (1);

      --  MTIME register (offset 0xBFF8, 8 bytes) - writable for testing
      elsif Offset >= REG_MTIME and Offset < REG_MTIME + 8 then
         Byte_Idx := Natural (Offset - REG_MTIME);
         Mask := Shift_Left (16#FF#, Byte_Idx * 8);
         Shifted := Shift_Left (Timer_Value (Data), Byte_Idx * 8);
         C.Mtime := (C.Mtime and not Mask) or Shifted;
         C.Timer_Interrupt (0) := C.Mtime >= C.Mtimecmp (0);
         C.Timer_Interrupt (1) := C.Mtime >= C.Mtimecmp (1);

      end if;
      --  Other addresses ignored
   end Write_Byte;

   ----------------
   -- Write_Word --
   ----------------

   procedure Write_Word (C    : in out CLINT_State;
                         Addr : Memory_Address;
                         Data : Word) is
      Offset : constant Memory_Address := Addr - C.Base_Address;
   begin
      --  MSIP hart 0 (offset 0x0000)
      if Offset = 0 then
         C.Msip (0) := (Data and 1) /= 0;

      --  MSIP hart 1 (offset 0x0004)
      elsif Offset = REG_MSIP1 then
         C.Msip (1) := (Data and 1) /= 0;

      --  MTIMECMP hart 0 low word (offset 0x4000)
      elsif Offset = REG_MTIMECMP then
         C.Mtimecmp (0) := (C.Mtimecmp (0) and 16#FFFF_FFFF_0000_0000#) or
                           Timer_Value (Data);
         C.Timer_Interrupt (0) := C.Mtime >= C.Mtimecmp (0);

      --  MTIMECMP hart 0 high word (offset 0x4004)
      elsif Offset = REG_MTIMECMP + 4 then
         C.Mtimecmp (0) := (C.Mtimecmp (0) and 16#0000_0000_FFFF_FFFF#) or
                           Shift_Left (Timer_Value (Data), 32);
         C.Timer_Interrupt (0) := C.Mtime >= C.Mtimecmp (0);

      --  MTIMECMP hart 1 low word (offset 0x4008)
      elsif Offset = REG_MTIMECMP1 then
         C.Mtimecmp (1) := (C.Mtimecmp (1) and 16#FFFF_FFFF_0000_0000#) or
                           Timer_Value (Data);
         C.Timer_Interrupt (1) := C.Mtime >= C.Mtimecmp (1);

      --  MTIMECMP hart 1 high word (offset 0x400C)
      elsif Offset = REG_MTIMECMP1 + 4 then
         C.Mtimecmp (1) := (C.Mtimecmp (1) and 16#0000_0000_FFFF_FFFF#) or
                           Shift_Left (Timer_Value (Data), 32);
         C.Timer_Interrupt (1) := C.Mtime >= C.Mtimecmp (1);

      --  MTIME low word (offset 0xBFF8)
      elsif Offset = REG_MTIME then
         C.Mtime := (C.Mtime and 16#FFFF_FFFF_0000_0000#) or
                    Timer_Value (Data);
         C.Timer_Interrupt (0) := C.Mtime >= C.Mtimecmp (0);
         C.Timer_Interrupt (1) := C.Mtime >= C.Mtimecmp (1);

      --  MTIME high word (offset 0xBFFC)
      elsif Offset = REG_MTIME + 4 then
         C.Mtime := (C.Mtime and 16#0000_0000_FFFF_FFFF#) or
                    Shift_Left (Timer_Value (Data), 32);
         C.Timer_Interrupt (0) := C.Mtime >= C.Mtimecmp (0);
         C.Timer_Interrupt (1) := C.Mtime >= C.Mtimecmp (1);

      else
         --  Other addresses: byte-wise write
         Write_Byte (C, Addr, Byte (Data and 16#FF#));
         Write_Byte (C, Addr + 1, Byte (Shift_Right (Data, 8) and 16#FF#));
         Write_Byte (C, Addr + 2, Byte (Shift_Right (Data, 16) and 16#FF#));
         Write_Byte (C, Addr + 3, Byte (Shift_Right (Data, 24) and 16#FF#));
      end if;
   end Write_Word;

   ----------
   -- Tick --
   ----------

   procedure Tick (C : in out CLINT_State) is
   begin
      C.Mtime := C.Mtime + 1;
      --  Check for timer interrupt for each hart
      if C.Mtime >= C.Mtimecmp (0) then
         C.Timer_Interrupt (0) := True;
      end if;
      if C.Mtime >= C.Mtimecmp (1) then
         C.Timer_Interrupt (1) := True;
      end if;
   end Tick;

   ------------
   -- Tick_N --
   ------------

   procedure Tick_N (C : in out CLINT_State; N : Positive) is
   begin
      C.Mtime := C.Mtime + Timer_Value (N);
      --  Check for timer interrupt for each hart
      if C.Mtime >= C.Mtimecmp (0) then
         C.Timer_Interrupt (0) := True;
      end if;
      if C.Mtime >= C.Mtimecmp (1) then
         C.Timer_Interrupt (1) := True;
      end if;
   end Tick_N;

   -----------------------------
   -- Timer_Interrupt_Pending --
   -----------------------------

   function Timer_Interrupt_Pending (C    : CLINT_State;
                                     Hart : Natural := 0) return Boolean is
      H : constant Natural := (if Hart <= 1 then Hart else 0);
   begin
      return C.Timer_Interrupt (H);
   end Timer_Interrupt_Pending;

   --------------------------------
   -- Software_Interrupt_Pending --
   --------------------------------

   function Software_Interrupt_Pending (C    : CLINT_State;
                                        Hart : Natural := 0) return Boolean is
      H : constant Natural := (if Hart <= 1 then Hart else 0);
   begin
      return C.Msip (H);
   end Software_Interrupt_Pending;

   ---------------------------
   -- Clear_Timer_Interrupt --
   ---------------------------

   procedure Clear_Timer_Interrupt (C    : in out CLINT_State;
                                    Hart : Natural := 0) is
      H : constant Natural := (if Hart <= 1 then Hart else 0);
   begin
      C.Timer_Interrupt (H) := False;
   end Clear_Timer_Interrupt;

   ---------------
   -- Get_Mtime --
   ---------------

   function Get_Mtime (C : CLINT_State) return Timer_Value is
   begin
      return C.Mtime;
   end Get_Mtime;

   ------------------
   -- Get_Mtimecmp --
   ------------------

   function Get_Mtimecmp (C    : CLINT_State;
                          Hart : Natural := 0) return Timer_Value is
      H : constant Natural := (if Hart <= 1 then Hart else 0);
   begin
      return C.Mtimecmp (H);
   end Get_Mtimecmp;

   --------------------
   -- Set_Mtimecmp   --
   --------------------

   procedure Set_Mtimecmp (C     : in out CLINT_State;
                            Value : Timer_Value;
                            Hart  : Natural := 0) is
      H : constant Natural := (if Hart <= 1 then Hart else 0);
   begin
      C.Mtimecmp (H) := Value;
      C.Timer_Interrupt (H) := C.Mtime >= C.Mtimecmp (H);
   end Set_Mtimecmp;

end RISCV.CLINT;
