-- ***************************************************************************
--               RISC-V Emulator - UART Emulation
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

package body RISCV.UART is

   ----------------
   -- Initialize --
   ----------------

   procedure Initialize (UART : out UART_State;
                         Base : Memory_Address := Default_Base_Address) is
   begin
      UART := (Base_Address  => Base,
               Enabled       => True,
               IER           => 0,
               IIR           => IIR_NO_INT,  -- No interrupt initially
               Input_Buffer  => (others => 0),
               Input_Head    => 0,
               Input_Tail    => 0,
               Input_Count   => 0,
               PTY_Enabled   => False,
               PTY_Master    => PTY.Invalid_FD,
               PTY_Slave     => (others => ' '),
               PTY_Slave_Len => 0);
   end Initialize;

   ---------------------
   -- Is_UART_Address --
   ---------------------

   function Is_UART_Address (UART : UART_State;
                             Addr : Memory_Address) return Boolean is
   begin
      if not UART.Enabled then
         return False;
      end if;
      return Addr >= UART.Base_Address and
             Addr < UART.Base_Address + UART_Size;
   end Is_UART_Address;

   ----------
   -- Read --
   ----------

   function Read (UART : in out UART_State;
                  Addr : Memory_Address) return Byte is
      Offset : constant Memory_Address := Addr - UART.Base_Address;
      Result : Byte := 0;
   begin
      case Offset is
         when REG_THR_RBR =>
            --  Read from receive buffer
            if UART.Input_Count > 0 then
               Result := UART.Input_Buffer (UART.Input_Tail);
               UART.Input_Tail := (UART.Input_Tail + 1) mod Input_Buffer_Size;
               UART.Input_Count := UART.Input_Count - 1;
               --  Update interrupt status after reading
               Update_Interrupts (UART);
            end if;

         when REG_IER =>
            --  Read Interrupt Enable Register
            Result := UART.IER;

         when REG_IIR =>
            --  Read Interrupt Identification Register
            Result := UART.IIR;

         when REG_LSR =>
            --  Poll PTY for input on LSR read (guest naturally polls LSR)
            if UART.PTY_Enabled then
               declare
                  B : Byte;
               begin
                  --  Drain available bytes from PTY into input buffer
                  while UART.Input_Count < Input_Buffer_Size loop
                     if PTY.Read_Byte (UART.PTY_Master, B) then
                        UART.Input_Buffer (UART.Input_Head) := B;
                        UART.Input_Head :=
                           (UART.Input_Head + 1) mod Input_Buffer_Size;
                        UART.Input_Count := UART.Input_Count + 1;
                     else
                        exit;
                     end if;
                  end loop;
               end;
            end if;

            --  Line Status Register
            --  Bit 5 (THRE) and Bit 6 (TEMT) always set (ready to transmit)
            Result := LSR_THRE or LSR_TEMT;
            --  Bit 0 (DR) set if input available
            if UART.Input_Count > 0 then
               Result := Result or LSR_DR;
            end if;

         when others =>
            --  Unimplemented registers return 0
            Result := 0;
      end case;

      return Result;
   end Read;

   -----------
   -- Write --
   -----------

   procedure Write (UART : in out UART_State;
                    Addr : Memory_Address;
                    Data : Byte) is
      Offset : constant Memory_Address := Addr - UART.Base_Address;
   begin
      case Offset is
         when REG_THR_RBR =>
            if UART.PTY_Enabled then
               --  Raw byte passthrough to PTY - let terminal handle display
               PTY.Write_Byte (UART.PTY_Master, Data);
            else
               --  Write to transmit buffer - output character
               if Data >= 32 and Data < 127 then
                  --  Printable ASCII
                  Ada.Text_IO.Put (Character'Val (Data));
               elsif Data = 10 then
                  --  Newline
                  Ada.Text_IO.New_Line;
               elsif Data = 13 then
                  --  Carriage return - ignore (handle only LF)
                  null;
               elsif Data = 9 then
                  --  Tab
                  Ada.Text_IO.Put (Character'Val (9));
               elsif Data = 8 then
                  --  Backspace
                  Ada.Text_IO.Put (Character'Val (8));
               else
                  --  Other control characters - output as-is or ignore
                  null;
               end if;
            end if;
            --  Update interrupt status after write (THR empty)
            Update_Interrupts (UART);

         when REG_IER =>
            --  Write Interrupt Enable Register
            UART.IER := Data and (IER_RDA or IER_THRE);
            --  Update interrupt status when IER changes
            Update_Interrupts (UART);

         when others =>
            --  Ignore writes to other registers
            null;
      end case;
   end Write;

   ---------------
   -- Add_Input --
   ---------------

   procedure Add_Input (UART : in out UART_State;
                        Data : Byte) is
   begin
      if UART.Input_Count < Input_Buffer_Size then
         UART.Input_Buffer (UART.Input_Head) := Data;
         UART.Input_Head := (UART.Input_Head + 1) mod Input_Buffer_Size;
         UART.Input_Count := UART.Input_Count + 1;
         --  Update interrupt status after adding input
         Update_Interrupts (UART);
      end if;
      --  If buffer full, drop the character
   end Add_Input;

   ----------------------
   -- Add_Input_String --
   ----------------------

   procedure Add_Input_String (UART : in out UART_State;
                               Str  : String) is
   begin
      for C of Str loop
         Add_Input (UART, Byte (Character'Pos (C)));
      end loop;
   end Add_Input_String;

   ---------------------
   -- Input_Available --
   ---------------------

   function Input_Available (UART : UART_State) return Boolean is
   begin
      return UART.Input_Count > 0;
   end Input_Available;

   ----------------
   -- Poll_Input --
   ----------------

   function Poll_Input (UART : in out UART_State) return Boolean is
      Got_Data : Boolean := False;
      B        : Byte;
   begin
      if UART.PTY_Enabled then
         --  Drain available bytes from PTY into input buffer
         while UART.Input_Count < Input_Buffer_Size loop
            if PTY.Read_Byte (UART.PTY_Master, B) then
               UART.Input_Buffer (UART.Input_Head) := B;
               UART.Input_Head :=
                  (UART.Input_Head + 1) mod Input_Buffer_Size;
               UART.Input_Count := UART.Input_Count + 1;
               Got_Data := True;
            else
               exit;
            end if;
         end loop;
         return Got_Data;
      end if;

      return False;
   end Poll_Input;

   --------------------
   -- Initialize_PTY --
   --------------------

   procedure Initialize_PTY (UART    : out UART_State;
                              Base    : Memory_Address := Default_Base_Address;
                              Success : out Boolean) is
   begin
      Initialize (UART, Base);

      PTY.Open (Master_FD  => UART.PTY_Master,
                Slave_Name => UART.PTY_Slave,
                Slave_Last => UART.PTY_Slave_Len,
                Success    => Success);

      if Success then
         UART.PTY_Enabled := True;
      end if;
   end Initialize_PTY;

   --------------
   -- Finalize --
   --------------

   procedure Finalize (UART : in out UART_State) is
   begin
      if UART.PTY_Enabled then
         PTY.Close (UART.PTY_Master);
         UART.PTY_Enabled := False;
         UART.PTY_Master  := PTY.Invalid_FD;
      end if;
   end Finalize;

   ------------------
   -- Get_PTY_Path --
   ------------------

   function Get_PTY_Path (UART : UART_State) return String is
   begin
      if UART.PTY_Enabled then
         return UART.PTY_Slave (1 .. UART.PTY_Slave_Len);
      else
         return "";
      end if;
   end Get_PTY_Path;

   ------------------------
   -- Interrupt_Pending --
   ------------------------

   function Interrupt_Pending (UART : UART_State) return Boolean is
   begin
      --  Interrupt is pending if IIR bit 0 is clear
      return (UART.IIR and IIR_NO_INT) = 0;
   end Interrupt_Pending;

   -----------------------
   -- Update_Interrupts --
   -----------------------

   procedure Update_Interrupts (UART : in out UART_State) is
   begin
      --  Start with no interrupt
      UART.IIR := IIR_NO_INT;

      --  Check for Received Data Available interrupt
      if (UART.IER and IER_RDA) /= 0 and UART.Input_Count > 0 then
         --  Received data available interrupt has higher priority
         UART.IIR := IIR_RDA;  -- Bits 1-3 = 010 (received data)
         return;
      end if;

      --  Check for THR Empty interrupt
      if (UART.IER and IER_THRE) /= 0 then
         --  THR is always empty in simulation (instant transmission)
         UART.IIR := IIR_THR;  -- Bits 1-3 = 001 (THR empty)
         return;
      end if;
   end Update_Interrupts;

end RISCV.UART;
