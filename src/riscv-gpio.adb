-- ***************************************************************************
--           RISC-V Emulator - GPIO (General Purpose I/O)
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

package body RISCV.GPIO is

   ----------------
   -- Initialize --
   ----------------

   procedure Initialize (G    : out GPIO_State;
                         Base : Memory_Address := Default_Base_Address) is
   begin
      G := (Base_Address => Base,
            Enabled      => True,
            Input        => 0,
            Output       => 0,
            Direction    => 0,        -- All inputs by default
            Int_Enable   => 0,
            Int_Flags    => 0,
            Int_Type     => 0,        -- Level-triggered by default
            Pull_Enable  => 0,
            Pull_Dir     => 16#FFFF_FFFF#,  -- Pull-up by default
            External_In  => 0,
            Prev_Input   => 0);
   end Initialize;

   ---------------------
   -- Is_GPIO_Address --
   ---------------------

   function Is_GPIO_Address (G    : GPIO_State;
                             Addr : Memory_Address) return Boolean is
   begin
      if not G.Enabled then
         return False;
      end if;
      return Addr >= G.Base_Address and
             Addr < G.Base_Address + GPIO_Size;
   end Is_GPIO_Address;

   ------------------
   -- Compute_Input --
   ------------------

   --  Compute the effective input value based on direction and output
   function Compute_Input (G : GPIO_State) return Word is
      Result : Word := 0;
   begin
      for I in 0 .. 31 loop
         declare
            Mask : constant Word := Shift_Left (1, I);
         begin
            if (G.Direction and Mask) /= 0 then
               --  Output pin: reflect output value
               if (G.Output and Mask) /= 0 then
                  Result := Result or Mask;
               end if;
            else
               --  Input pin: use external input or pull value
               if (G.External_In and Mask) /= 0 then
                  Result := Result or Mask;
               elsif (G.Pull_Enable and Mask) /= 0 and
                     (G.Pull_Dir and Mask) /= 0
               then
                  --  Pull-up active
                  Result := Result or Mask;
               end if;
            end if;
         end;
      end loop;
      return Result;
   end Compute_Input;

   ---------------
   -- Read_Word --
   ---------------

   function Read_Word (G    : GPIO_State;
                       Addr : Memory_Address) return Word is
      Offset : constant Memory_Address := Addr - G.Base_Address;
   begin
      case Offset is
         when REG_INPUT =>
            return Compute_Input (G);
         when REG_OUTPUT =>
            return G.Output;
         when REG_DIRECTION =>
            return G.Direction;
         when REG_INT_EN =>
            return G.Int_Enable;
         when REG_INT_FLAG =>
            return G.Int_Flags;
         when REG_INT_TYPE =>
            return G.Int_Type;
         when REG_PULL_EN =>
            return G.Pull_Enable;
         when REG_PULL_DIR =>
            return G.Pull_Dir;
         when others =>
            return 0;
      end case;
   end Read_Word;

   ---------------
   -- Read_Byte --
   ---------------

   function Read_Byte (G    : GPIO_State;
                       Addr : Memory_Address) return Byte is
      Aligned : constant Memory_Address := Addr and not 3;
      Word_Val : constant Word := Read_Word (G, Aligned);
      Byte_Idx : constant Natural := Natural (Addr and 3);
   begin
      return Byte (Shift_Right (Word_Val, Byte_Idx * 8) and 16#FF#);
   end Read_Byte;

   ----------------
   -- Write_Word --
   ----------------

   procedure Write_Word (G    : in out GPIO_State;
                         Addr : Memory_Address;
                         Data : Word) is
      Offset : constant Memory_Address := Addr - G.Base_Address;
   begin
      case Offset is
         when REG_INPUT =>
            --  Input register is read-only
            null;
         when REG_OUTPUT =>
            G.Output := Data;
         when REG_DIRECTION =>
            G.Direction := Data;
         when REG_INT_EN =>
            G.Int_Enable := Data;
         when REG_INT_FLAG =>
            --  Write 1 to clear flags
            G.Int_Flags := G.Int_Flags and not Data;
         when REG_INT_TYPE =>
            G.Int_Type := Data;
         when REG_PULL_EN =>
            G.Pull_Enable := Data;
         when REG_PULL_DIR =>
            G.Pull_Dir := Data;
         when others =>
            null;
      end case;
   end Write_Word;

   ----------------
   -- Write_Byte --
   ----------------

   procedure Write_Byte (G    : in out GPIO_State;
                         Addr : Memory_Address;
                         Data : Byte) is
      Aligned  : constant Memory_Address := Addr and not 3;
      Byte_Idx : constant Natural := Natural (Addr and 3);
      Mask     : constant Word := Shift_Left (16#FF#, Byte_Idx * 8);
      Shifted  : constant Word := Shift_Left (Word (Data), Byte_Idx * 8);
      Old_Val  : constant Word := Read_Word (G, Aligned);
      New_Val  : constant Word := (Old_Val and not Mask) or Shifted;
   begin
      Write_Word (G, Aligned, New_Val);
   end Write_Byte;

   ------------------------
   -- Set_External_Input --
   ------------------------

   procedure Set_External_Input (G     : in out GPIO_State;
                                 Value : Word) is
   begin
      G.External_In := Value;
   end Set_External_Input;

   ----------------------
   -- Set_External_Pin --
   ----------------------

   procedure Set_External_Pin (G     : in out GPIO_State;
                               Pin   : Natural;
                               Value : Boolean) is
      Mask : constant Word := Shift_Left (1, Pin mod 32);
   begin
      if Value then
         G.External_In := G.External_In or Mask;
      else
         G.External_In := G.External_In and not Mask;
      end if;
   end Set_External_Pin;

   ----------------
   -- Get_Output --
   ----------------

   function Get_Output (G : GPIO_State) return Word is
   begin
      return G.Output;
   end Get_Output;

   --------------------
   -- Get_Output_Pin --
   --------------------

   function Get_Output_Pin (G   : GPIO_State;
                            Pin : Natural) return Boolean is
      Mask : constant Word := Shift_Left (1, Pin mod 32);
   begin
      return (G.Output and Mask) /= 0;
   end Get_Output_Pin;

   -----------------------
   -- Interrupt_Pending --
   -----------------------

   function Interrupt_Pending (G : GPIO_State) return Boolean is
   begin
      return (G.Int_Flags and G.Int_Enable) /= 0;
   end Interrupt_Pending;

   ------------
   -- Update --
   ------------

   procedure Update (G : in out GPIO_State) is
      Current  : constant Word := Compute_Input (G);
      Rising   : Word;
      Falling  : Word;
   begin
      --  Detect edges
      Rising := Current and not G.Prev_Input;     -- Bits that went 0->1
      Falling := G.Prev_Input and not Current;    -- Bits that went 1->0

      --  Update input register
      G.Input := Current;

      --  Generate interrupts
      for I in 0 .. 31 loop
         declare
            Mask : constant Word := Shift_Left (1, I);
         begin
            if (G.Int_Enable and Mask) /= 0 then
               if (G.Int_Type and Mask) /= 0 then
                  --  Edge-triggered: interrupt on rising or falling edge
                  if (Rising and Mask) /= 0 or (Falling and Mask) /= 0 then
                     G.Int_Flags := G.Int_Flags or Mask;
                  end if;
               else
                  --  Level-triggered: interrupt while high
                  if (Current and Mask) /= 0 then
                     G.Int_Flags := G.Int_Flags or Mask;
                  end if;
               end if;
            end if;
         end;
      end loop;

      --  Save for next edge detection
      G.Prev_Input := Current;
   end Update;

end RISCV.GPIO;
