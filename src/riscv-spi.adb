-- ***************************************************************************
--        RISC-V Emulator - SPI (Serial Peripheral Interface)
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

with Ada.Unchecked_Deallocation;

package body RISCV.SPI is

   ----------------
   -- Initialize --
   ----------------

   procedure Initialize (S    : out SPI_State;
                         Base : Memory_Address := Default_Base_Address) is
   begin
      S := (Base_Address => Base,
            Enabled      => True,
            Control      => CTRL_CS,  -- CS inactive by default
            Status       => STATUS_TX_READY or STATUS_RX_VALID,
            Data_Out     => 0,
            Data_In      => 16#FF#,   -- Flash default read value
            Prescale     => 0,
            Flash        => new Flash_Memory'(others => 16#FF#),
            Flash_FSM    => Idle,
            Flash_Addr   => 0,
            Write_Enable => False);
   end Initialize;

   --------------
   -- Finalize --
   --------------

   procedure Finalize (S : in out SPI_State) is
      procedure Free is new Ada.Unchecked_Deallocation
        (Flash_Memory, Flash_Memory_Access);
   begin
      if S.Flash /= null then
         Free (S.Flash);
      end if;
   end Finalize;

   --------------------
   -- Is_SPI_Address --
   --------------------

   function Is_SPI_Address (S    : SPI_State;
                            Addr : Memory_Address) return Boolean is
   begin
      if not S.Enabled then
         return False;
      end if;
      return Addr >= S.Base_Address and
             Addr < S.Base_Address + SPI_Size;
   end Is_SPI_Address;

   ----------------------
   -- Process_SPI_Byte --
   ----------------------

   --  Process a byte transfer through the SPI (simulate flash chip)
   procedure Process_SPI_Byte (S : in out SPI_State; Data_Out : Byte) is
      Response : Byte := 16#FF#;  -- Default response
   begin
      --  Only process if CS is active (low)
      if (S.Control and CTRL_CS) /= 0 then
         --  CS is inactive, reset state machine
         S.Flash_FSM := Idle;
         S.Data_In := 16#FF#;
         return;
      end if;

      --  Process based on current state
      case S.Flash_FSM is
         when Idle =>
            --  Waiting for command
            case Data_Out is
               when CMD_READ =>
                  S.Flash_FSM := Read_Addr1;
                  S.Flash_Addr := 0;
               when CMD_PAGE_PROGRAM =>
                  if S.Write_Enable then
                     S.Flash_FSM := Program_Addr1;
                     S.Flash_Addr := 0;
                  end if;
               when CMD_READ_ID =>
                  --  Return fake JEDEC ID (Manufacturer: 0xEF, Device: 0x40 0x15)
                  S.Data_In := 16#EF#;
                  S.Flash_FSM := Idle;  -- Next bytes will be device ID
               when CMD_READ_STATUS =>
                  --  Flash status: bit 0 = busy (always 0), bit 1 = WEL
                  Response := (if S.Write_Enable then 16#02# else 16#00#);
                  S.Data_In := Response;
               when CMD_WRITE_ENABLE =>
                  S.Write_Enable := True;
                  S.Data_In := 16#FF#;
               when others =>
                  --  Unknown command
                  S.Data_In := 16#FF#;
            end case;

         when Read_Addr1 =>
            --  First address byte (MSB)
            S.Flash_Addr := Shift_Left (Word (Data_Out), 16);
            S.Flash_FSM := Read_Addr2;
            S.Data_In := 16#FF#;

         when Read_Addr2 =>
            --  Second address byte
            S.Flash_Addr := S.Flash_Addr or Shift_Left (Word (Data_Out), 8);
            S.Flash_FSM := Read_Addr3;
            S.Data_In := 16#FF#;

         when Read_Addr3 =>
            --  Third address byte (LSB); first data byte returned on next transfer
            S.Flash_Addr := S.Flash_Addr or Word (Data_Out);
            S.Flash_FSM := Read_Data;
            S.Data_In := 16#FF#;

         when Read_Data =>
            --  Continue reading sequential bytes
            if S.Flash_Addr < Flash_Size then
               S.Data_In := S.Flash (Natural (S.Flash_Addr));
               S.Flash_Addr := S.Flash_Addr + 1;
            else
               S.Data_In := 16#FF#;
            end if;

         when Program_Addr1 =>
            --  First address byte (MSB)
            S.Flash_Addr := Shift_Left (Word (Data_Out), 16);
            S.Flash_FSM := Program_Addr2;
            S.Data_In := 16#FF#;

         when Program_Addr2 =>
            --  Second address byte
            S.Flash_Addr := S.Flash_Addr or Shift_Left (Word (Data_Out), 8);
            S.Flash_FSM := Program_Addr3;
            S.Data_In := 16#FF#;

         when Program_Addr3 =>
            --  Third address byte (LSB)
            S.Flash_Addr := S.Flash_Addr or Word (Data_Out);
            S.Flash_FSM := Program_Data;
            S.Data_In := 16#FF#;

         when Program_Data =>
            --  Write data to flash
            if S.Flash_Addr < Flash_Size then
               --  In real flash, can only program 1->0, not 0->1
               --  For simulation, we'll just write directly
               S.Flash (Natural (S.Flash_Addr)) := Data_Out;
               S.Flash_Addr := S.Flash_Addr + 1;
            end if;
            S.Data_In := 16#FF#;
            S.Write_Enable := False;  -- Auto-clear after write

         when others =>
            S.Data_In := 16#FF#;
      end case;
   end Process_SPI_Byte;

   ---------------
   -- Read_Word --
   ---------------

   function Read_Word (S    : in out SPI_State;
                       Addr : Memory_Address) return Word is
      Offset : constant Memory_Address := Addr - S.Base_Address;
   begin
      case Offset is
         when REG_CTRL =>
            return Word (S.Control);
         when REG_STATUS =>
            return Word (S.Status);
         when REG_DATA =>
            --  Reading returns received data (MISO)
            return Word (S.Data_In);
         when REG_PRESCALE =>
            return Word (S.Prescale);
         when others =>
            return 0;
      end case;
   end Read_Word;

   ---------------
   -- Read_Byte --
   ---------------

   function Read_Byte (S    : in out SPI_State;
                       Addr : Memory_Address) return Byte is
      Aligned : constant Memory_Address := Addr and not 3;
      Word_Val : constant Word := Read_Word (S, Aligned);
      Byte_Idx : constant Natural := Natural (Addr and 3);
   begin
      return Byte (Shift_Right (Word_Val, Byte_Idx * 8) and 16#FF#);
   end Read_Byte;

   ----------------
   -- Write_Word --
   ----------------

   procedure Write_Word (S    : in out SPI_State;
                         Addr : Memory_Address;
                         Data : Word) is
      Offset : constant Memory_Address := Addr - S.Base_Address;
   begin
      case Offset is
         when REG_CTRL =>
            S.Control := Byte (Data and 16#FF#);
            --  If CS goes from inactive to active, reset state machine
            if (S.Control and CTRL_CS) = 0 then
               --  CS activated
               null;  -- State machine will process on first data write
            else
               --  CS deactivated, reset
               S.Flash_FSM := Idle;
            end if;

         when REG_STATUS =>
            --  Status is mostly read-only, but could clear flags here
            null;

         when REG_DATA =>
            --  Writing transmits a byte
            S.Data_Out := Byte (Data and 16#FF#);
            --  Process the byte through flash simulation
            Process_SPI_Byte (S, S.Data_Out);

         when REG_PRESCALE =>
            S.Prescale := Byte (Data and 16#FF#);

         when others =>
            null;
      end case;
   end Write_Word;

   ----------------
   -- Write_Byte --
   ----------------

   procedure Write_Byte (S    : in out SPI_State;
                         Addr : Memory_Address;
                         Data : Byte) is
      Aligned  : constant Memory_Address := Addr and not 3;
      Byte_Idx : constant Natural := Natural (Addr and 3);
   begin
      --  All SPI registers are byte-wide; only byte 0 of each aligned word
      --  is meaningful.  A 32-bit SW by the CPU decomposes into four
      --  Write_Byte calls; we must ignore the three upper bytes so that the
      --  flash FSM is not driven with spurious 0xFF/0x00 bytes.
      if Byte_Idx = 0 then
         Write_Word (S, Aligned, Word (Data));
      end if;
   end Write_Byte;

   ---------------
   -- Get_Flash --
   ---------------

   function Get_Flash (S : SPI_State) return Flash_Memory_Access is
   begin
      return S.Flash;
   end Get_Flash;

end RISCV.SPI;
