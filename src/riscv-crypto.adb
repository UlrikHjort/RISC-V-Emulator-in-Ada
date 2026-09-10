-- ***************************************************************************
--          RISC-V Emulator - K Extension (Scalar Crypto)
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
package body RISCV.Crypto is

   --  AES Forward S-box
   AES_Sbox : constant array (0 .. 255) of Byte := (
      16#63#, 16#7C#, 16#77#, 16#7B#, 16#F2#, 16#6B#, 16#6F#, 16#C5#,
      16#30#, 16#01#, 16#67#, 16#2B#, 16#FE#, 16#D7#, 16#AB#, 16#76#,
      16#CA#, 16#82#, 16#C9#, 16#7D#, 16#FA#, 16#59#, 16#47#, 16#F0#,
      16#AD#, 16#D4#, 16#A2#, 16#AF#, 16#9C#, 16#A4#, 16#72#, 16#C0#,
      16#B7#, 16#FD#, 16#93#, 16#26#, 16#36#, 16#3F#, 16#F7#, 16#CC#,
      16#34#, 16#A5#, 16#E5#, 16#F1#, 16#71#, 16#D8#, 16#31#, 16#15#,
      16#04#, 16#C7#, 16#23#, 16#C3#, 16#18#, 16#96#, 16#05#, 16#9A#,
      16#07#, 16#12#, 16#80#, 16#E2#, 16#EB#, 16#27#, 16#B2#, 16#75#,
      16#09#, 16#83#, 16#2C#, 16#1A#, 16#1B#, 16#6E#, 16#5A#, 16#A0#,
      16#52#, 16#3B#, 16#D6#, 16#B3#, 16#29#, 16#E3#, 16#2F#, 16#84#,
      16#53#, 16#D1#, 16#00#, 16#ED#, 16#20#, 16#FC#, 16#B1#, 16#5B#,
      16#6A#, 16#CB#, 16#BE#, 16#39#, 16#4A#, 16#4C#, 16#58#, 16#CF#,
      16#D0#, 16#EF#, 16#AA#, 16#FB#, 16#43#, 16#4D#, 16#33#, 16#85#,
      16#45#, 16#F9#, 16#02#, 16#7F#, 16#50#, 16#3C#, 16#9F#, 16#A8#,
      16#51#, 16#A3#, 16#40#, 16#8F#, 16#92#, 16#9D#, 16#38#, 16#F5#,
      16#BC#, 16#B6#, 16#DA#, 16#21#, 16#10#, 16#FF#, 16#F3#, 16#D2#,
      16#CD#, 16#0C#, 16#13#, 16#EC#, 16#5F#, 16#97#, 16#44#, 16#17#,
      16#C4#, 16#A7#, 16#7E#, 16#3D#, 16#64#, 16#5D#, 16#19#, 16#73#,
      16#60#, 16#81#, 16#4F#, 16#DC#, 16#22#, 16#2A#, 16#90#, 16#88#,
      16#46#, 16#EE#, 16#B8#, 16#14#, 16#DE#, 16#5E#, 16#0B#, 16#DB#,
      16#E0#, 16#32#, 16#3A#, 16#0A#, 16#49#, 16#06#, 16#24#, 16#5C#,
      16#C2#, 16#D3#, 16#AC#, 16#62#, 16#91#, 16#95#, 16#E4#, 16#79#,
      16#E7#, 16#C8#, 16#37#, 16#6D#, 16#8D#, 16#D5#, 16#4E#, 16#A9#,
      16#6C#, 16#56#, 16#F4#, 16#EA#, 16#65#, 16#7A#, 16#AE#, 16#08#,
      16#BA#, 16#78#, 16#25#, 16#2E#, 16#1C#, 16#A6#, 16#B4#, 16#C6#,
      16#E8#, 16#DD#, 16#74#, 16#1F#, 16#4B#, 16#BD#, 16#8B#, 16#8A#,
      16#70#, 16#3E#, 16#B5#, 16#66#, 16#48#, 16#03#, 16#F6#, 16#0E#,
      16#61#, 16#35#, 16#57#, 16#B9#, 16#86#, 16#C1#, 16#1D#, 16#9E#,
      16#E1#, 16#F8#, 16#98#, 16#11#, 16#69#, 16#D9#, 16#8E#, 16#94#,
      16#9B#, 16#1E#, 16#87#, 16#E9#, 16#CE#, 16#55#, 16#28#, 16#DF#,
      16#8C#, 16#A1#, 16#89#, 16#0D#, 16#BF#, 16#E6#, 16#42#, 16#68#,
      16#41#, 16#99#, 16#2D#, 16#0F#, 16#B0#, 16#54#, 16#BB#, 16#16#);

   --  AES Inverse S-box
   AES_Inv_Sbox : constant array (0 .. 255) of Byte := (
      16#52#, 16#09#, 16#6A#, 16#D5#, 16#30#, 16#36#, 16#A5#, 16#38#,
      16#BF#, 16#40#, 16#A3#, 16#9E#, 16#81#, 16#F3#, 16#D7#, 16#FB#,
      16#7C#, 16#E3#, 16#39#, 16#82#, 16#9B#, 16#2F#, 16#FF#, 16#87#,
      16#34#, 16#8E#, 16#43#, 16#44#, 16#C4#, 16#DE#, 16#E9#, 16#CB#,
      16#54#, 16#7B#, 16#94#, 16#32#, 16#A6#, 16#C2#, 16#23#, 16#3D#,
      16#EE#, 16#4C#, 16#95#, 16#0B#, 16#42#, 16#FA#, 16#C3#, 16#4E#,
      16#08#, 16#2E#, 16#A1#, 16#66#, 16#28#, 16#D9#, 16#24#, 16#B2#,
      16#76#, 16#5B#, 16#A2#, 16#49#, 16#6D#, 16#8B#, 16#D1#, 16#25#,
      16#72#, 16#F8#, 16#F6#, 16#64#, 16#86#, 16#68#, 16#98#, 16#16#,
      16#D4#, 16#A4#, 16#5C#, 16#CC#, 16#5D#, 16#65#, 16#B6#, 16#92#,
      16#6C#, 16#70#, 16#48#, 16#50#, 16#FD#, 16#ED#, 16#B9#, 16#DA#,
      16#5E#, 16#15#, 16#46#, 16#57#, 16#A7#, 16#8D#, 16#9D#, 16#84#,
      16#90#, 16#D8#, 16#AB#, 16#00#, 16#8C#, 16#BC#, 16#D3#, 16#0A#,
      16#F7#, 16#E4#, 16#58#, 16#05#, 16#B8#, 16#B3#, 16#45#, 16#06#,
      16#D0#, 16#2C#, 16#1E#, 16#8F#, 16#CA#, 16#3F#, 16#0F#, 16#02#,
      16#C1#, 16#AF#, 16#BD#, 16#03#, 16#01#, 16#13#, 16#8A#, 16#6B#,
      16#3A#, 16#91#, 16#11#, 16#41#, 16#4F#, 16#67#, 16#DC#, 16#EA#,
      16#97#, 16#F2#, 16#CF#, 16#CE#, 16#F0#, 16#B4#, 16#E6#, 16#73#,
      16#96#, 16#AC#, 16#74#, 16#22#, 16#E7#, 16#AD#, 16#35#, 16#85#,
      16#E2#, 16#F9#, 16#37#, 16#E8#, 16#1C#, 16#75#, 16#DF#, 16#6E#,
      16#47#, 16#F1#, 16#1A#, 16#71#, 16#1D#, 16#29#, 16#C5#, 16#89#,
      16#6F#, 16#B7#, 16#62#, 16#0E#, 16#AA#, 16#18#, 16#BE#, 16#1B#,
      16#FC#, 16#56#, 16#3E#, 16#4B#, 16#C6#, 16#D2#, 16#79#, 16#20#,
      16#9A#, 16#DB#, 16#C0#, 16#FE#, 16#78#, 16#CD#, 16#5A#, 16#F4#,
      16#1F#, 16#DD#, 16#A8#, 16#33#, 16#88#, 16#07#, 16#C7#, 16#31#,
      16#B1#, 16#12#, 16#10#, 16#59#, 16#27#, 16#80#, 16#EC#, 16#5F#,
      16#60#, 16#51#, 16#7F#, 16#A9#, 16#19#, 16#B5#, 16#4A#, 16#0D#,
      16#2D#, 16#E5#, 16#7A#, 16#9F#, 16#93#, 16#C9#, 16#9C#, 16#EF#,
      16#A0#, 16#E0#, 16#3B#, 16#4D#, 16#AE#, 16#2A#, 16#F5#, 16#B0#,
      16#C8#, 16#EB#, 16#BB#, 16#3C#, 16#83#, 16#53#, 16#99#, 16#61#,
      16#17#, 16#2B#, 16#04#, 16#7E#, 16#BA#, 16#77#, 16#D6#, 16#26#,
      16#E1#, 16#69#, 16#14#, 16#63#, 16#55#, 16#21#, 16#0C#, 16#7D#);

   --  SM4 S-box
   SM4_Sbox : constant array (0 .. 255) of Byte := (
      16#D6#, 16#90#, 16#E9#, 16#FE#, 16#CC#, 16#E1#, 16#3D#, 16#B7#,
      16#16#, 16#B6#, 16#14#, 16#C2#, 16#28#, 16#FB#, 16#2C#, 16#05#,
      16#2B#, 16#67#, 16#9A#, 16#76#, 16#2A#, 16#BE#, 16#04#, 16#C3#,
      16#AA#, 16#44#, 16#13#, 16#26#, 16#49#, 16#86#, 16#06#, 16#99#,
      16#9C#, 16#42#, 16#50#, 16#F4#, 16#91#, 16#EF#, 16#98#, 16#7A#,
      16#33#, 16#54#, 16#0B#, 16#43#, 16#ED#, 16#CF#, 16#AC#, 16#62#,
      16#E4#, 16#B3#, 16#1C#, 16#A9#, 16#C9#, 16#08#, 16#E8#, 16#95#,
      16#80#, 16#DF#, 16#94#, 16#FA#, 16#75#, 16#8F#, 16#3F#, 16#A6#,
      16#47#, 16#07#, 16#A7#, 16#FC#, 16#F3#, 16#73#, 16#17#, 16#BA#,
      16#83#, 16#59#, 16#3C#, 16#19#, 16#E6#, 16#85#, 16#4F#, 16#A8#,
      16#68#, 16#6B#, 16#81#, 16#B2#, 16#71#, 16#64#, 16#DA#, 16#8B#,
      16#F8#, 16#EB#, 16#0F#, 16#4B#, 16#70#, 16#56#, 16#9D#, 16#35#,
      16#1E#, 16#24#, 16#0E#, 16#5E#, 16#63#, 16#58#, 16#D1#, 16#A2#,
      16#25#, 16#22#, 16#7C#, 16#3B#, 16#01#, 16#21#, 16#78#, 16#87#,
      16#D4#, 16#00#, 16#46#, 16#57#, 16#9F#, 16#D3#, 16#27#, 16#52#,
      16#4C#, 16#36#, 16#02#, 16#E7#, 16#A0#, 16#C4#, 16#C8#, 16#9E#,
      16#EA#, 16#BF#, 16#8A#, 16#D2#, 16#40#, 16#C7#, 16#38#, 16#B5#,
      16#A3#, 16#F7#, 16#F2#, 16#CE#, 16#F9#, 16#61#, 16#15#, 16#A1#,
      16#E0#, 16#AE#, 16#5D#, 16#A4#, 16#9B#, 16#34#, 16#1A#, 16#55#,
      16#AD#, 16#93#, 16#32#, 16#30#, 16#F5#, 16#8C#, 16#B1#, 16#E3#,
      16#1D#, 16#F6#, 16#E2#, 16#2E#, 16#82#, 16#66#, 16#CA#, 16#60#,
      16#C0#, 16#29#, 16#23#, 16#AB#, 16#0D#, 16#53#, 16#4E#, 16#6F#,
      16#D5#, 16#DB#, 16#37#, 16#45#, 16#DE#, 16#FD#, 16#8E#, 16#2F#,
      16#03#, 16#FF#, 16#6A#, 16#72#, 16#6D#, 16#6C#, 16#5B#, 16#51#,
      16#8D#, 16#1B#, 16#AF#, 16#92#, 16#BB#, 16#DD#, 16#BC#, 16#7F#,
      16#11#, 16#D9#, 16#5C#, 16#41#, 16#1F#, 16#10#, 16#5A#, 16#D8#,
      16#0A#, 16#C1#, 16#31#, 16#88#, 16#A5#, 16#CD#, 16#7B#, 16#BD#,
      16#2D#, 16#74#, 16#D0#, 16#12#, 16#B8#, 16#E5#, 16#B4#, 16#B0#,
      16#89#, 16#69#, 16#97#, 16#4A#, 16#0C#, 16#96#, 16#77#, 16#7E#,
      16#65#, 16#B9#, 16#F1#, 16#09#, 16#C5#, 16#6E#, 16#C6#, 16#84#,
      16#18#, 16#F0#, 16#7D#, 16#EC#, 16#3A#, 16#DC#, 16#4D#, 16#20#,
      16#79#, 16#EE#, 16#5F#, 16#3E#, 16#D7#, 16#CB#, 16#39#, 16#48#);

   --  AES GF(2^8) multiply by 2 (xtime)
   function Xtime (X : Word) return Word is
   begin
      if (X and 16#80#) /= 0 then
         return (Shift_Left (X, 1) xor 16#1B#) and 16#FF#;
      else
         return Shift_Left (X, 1) and 16#FF#;
      end if;
   end Xtime;

   --  AES GF(2^8) multiply
   function GF_Mul (A, B : Word) return Word is
      Result : Word := 0;
      Aa     : Word := A and 16#FF#;
      Bb     : Word := B and 16#FF#;
   begin
      for Bit in 0 .. 7 loop
         pragma Unreferenced (Bit);
         if (Bb and 1) /= 0 then
            Result := Result xor Aa;
         end if;
         Aa := Xtime (Aa);
         Bb := Shift_Right (Bb, 1);
      end loop;
      return Result and 16#FF#;
   end GF_Mul;

   --  Rotate left 32-bit
   function Rot_Left (X : Word; N : Natural) return Word is
      Shamt : constant Natural := N mod 32;
   begin
      if Shamt = 0 then
         return X;
      end if;
      return Shift_Left (X, Shamt) or Shift_Right (X, 32 - Shamt);
   end Rot_Left;

   --  Rotate right 32-bit
   function Rot_Right (X : Word; N : Natural) return Word is
      Shamt : constant Natural := N mod 32;
   begin
      if Shamt = 0 then
         return X;
      end if;
      return Shift_Right (X, Shamt) or Shift_Left (X, 32 - Shamt);
   end Rot_Right;

   ----------------
   -- Zbkb
   ----------------

   function ANDN (Rs1, Rs2 : Word) return Word is
   begin
      return Rs1 and (not Rs2);
   end ANDN;

   function ORN (Rs1, Rs2 : Word) return Word is
   begin
      return Rs1 or (not Rs2);
   end ORN;

   function XNOR_Op (Rs1, Rs2 : Word) return Word is
   begin
      return not (Rs1 xor Rs2);
   end XNOR_Op;

   function ROL (Rs1, Rs2 : Word) return Word is
   begin
      return Rot_Left (Rs1, Natural (Rs2 and 16#1F#));
   end ROL;

   function ROR_Op (Rs1, Rs2 : Word) return Word is
   begin
      return Rot_Right (Rs1, Natural (Rs2 and 16#1F#));
   end ROR_Op;

   function RORI (Rs1 : Word; Shamt : Natural) return Word is
   begin
      return Rot_Right (Rs1, Shamt);
   end RORI;

   function PACK (Rs1, Rs2 : Word) return Word is
   begin
      return (Rs1 and 16#FFFF#) or Shift_Left (Rs2 and 16#FFFF#, 16);
   end PACK;

   function PACKH (Rs1, Rs2 : Word) return Word is
   begin
      return (Rs1 and 16#FF#) or Shift_Left (Rs2 and 16#FF#, 8);
   end PACKH;

   function REV8 (Rs1 : Word) return Word is
      B0 : constant Word := Rs1 and 16#FF#;
      B1 : constant Word := Shift_Right (Rs1, 8) and 16#FF#;
      B2 : constant Word := Shift_Right (Rs1, 16) and 16#FF#;
      B3 : constant Word := Shift_Right (Rs1, 24) and 16#FF#;
   begin
      return Shift_Left (B0, 24) or Shift_Left (B1, 16) or
             Shift_Left (B2, 8) or B3;
   end REV8;

   function ZIP (Rs1 : Word) return Word is
      Result : Word := 0;
   begin
      for I in 0 .. 15 loop
         --  Interleave lower and upper halves
         if (Rs1 and Shift_Left (1, I)) /= 0 then
            Result := Result or Shift_Left (1, 2 * I);
         end if;
         if (Rs1 and Shift_Left (1, I + 16)) /= 0 then
            Result := Result or Shift_Left (1, 2 * I + 1);
         end if;
      end loop;
      return Result;
   end ZIP;

   function UNZIP (Rs1 : Word) return Word is
      Result : Word := 0;
   begin
      for I in 0 .. 15 loop
         --  De-interleave even/odd bits
         if (Rs1 and Shift_Left (1, 2 * I)) /= 0 then
            Result := Result or Shift_Left (1, I);
         end if;
         if (Rs1 and Shift_Left (1, 2 * I + 1)) /= 0 then
            Result := Result or Shift_Left (1, I + 16);
         end if;
      end loop;
      return Result;
   end UNZIP;

   function BREV8 (Rs1 : Word) return Word is
      Result : Word := 0;
      B      : Word;
      Rev    : Word;
   begin
      for Bi in 0 .. 3 loop
         B := Shift_Right (Rs1, Bi * 8) and 16#FF#;
         Rev := 0;
         for Bit in 0 .. 7 loop
            if (B and Shift_Left (1, Bit)) /= 0 then
               Rev := Rev or Shift_Left (1, 7 - Bit);
            end if;
         end loop;
         Result := Result or Shift_Left (Rev, Bi * 8);
      end loop;
      return Result;
   end BREV8;

   ----------------
   -- Zbkc
   ----------------

   function CLMUL (Rs1, Rs2 : Word) return Word is
      Result : Word := 0;
   begin
      for I in 0 .. 31 loop
         if (Rs2 and Shift_Left (1, I)) /= 0 then
            Result := Result xor Shift_Left (Rs1, I);
         end if;
      end loop;
      return Result;
   end CLMUL;

   function CLMULH (Rs1, Rs2 : Word) return Word is
      Result : Word := 0;
   begin
      for I in 1 .. 31 loop
         if (Rs2 and Shift_Left (1, I)) /= 0 then
            Result := Result xor Shift_Right (Rs1, 32 - I);
         end if;
      end loop;
      return Result;
   end CLMULH;

   function CLMULR (Rs1, Rs2 : Word) return Word is
      Result : Word := 0;
   begin
      for I in 0 .. 31 loop
         if (Rs2 and Shift_Left (1, I)) /= 0 then
            Result := Result xor Shift_Right (Rs1, 31 - I);
         end if;
      end loop;
      return Result;
   end CLMULR;

   ----------------
   -- Zbkx
   ----------------

   function XPERM4 (Rs1, Rs2 : Word) return Word is
      Result : Word := 0;
      Idx    : Natural;
   begin
      for I in 0 .. 7 loop
         Idx := Natural (Shift_Right (Rs2, I * 4) and 16#F#);
         Result := Result or
           Shift_Left (Shift_Right (Rs1, Idx * 4) and 16#F#, I * 4);
      end loop;
      return Result;
   end XPERM4;

   function XPERM8 (Rs1, Rs2 : Word) return Word is
      Result : Word := 0;
      Idx    : Natural;
   begin
      for I in 0 .. 3 loop
         Idx := Natural (Shift_Right (Rs2, I * 8) and 16#FF#);
         if Idx < 4 then
            Result := Result or
              Shift_Left (Shift_Right (Rs1, Idx * 8) and 16#FF#, I * 8);
         end if;
      end loop;
      return Result;
   end XPERM8;

   ----------------
   -- Zkne: AES Encryption
   ----------------

   function AES32ESI (Rs1, Rs2 : Word; BS : Natural) return Word is
      SI    : constant Natural := Natural (Shift_Right (Rs2, BS * 8) and 16#FF#);
      Sbval : constant Word := Word (AES_Sbox (SI));
      Shamt : constant Natural := BS * 8;
   begin
      return Rs1 xor Rot_Left (Sbval, Shamt);
   end AES32ESI;

   function AES32ESMI (Rs1, Rs2 : Word; BS : Natural) return Word is
      SI    : constant Natural := Natural (Shift_Right (Rs2, BS * 8) and 16#FF#);
      Sbval : constant Word := Word (AES_Sbox (SI));
      --  MixColumn on single byte: gfmul(so,3) @ so @ so @ gfmul(so,2)
      X2    : constant Word := Xtime (Sbval);
      X3    : constant Word := X2 xor Sbval;
      Mixed : constant Word := Shift_Left (X3, 24) or
                                Shift_Left (Sbval, 16) or
                                Shift_Left (Sbval, 8) or X2;
      Shamt : constant Natural := BS * 8;
   begin
      return Rs1 xor Rot_Left (Mixed, Shamt);
   end AES32ESMI;

   ----------------
   -- Zknd: AES Decryption
   ----------------

   function AES32DSI (Rs1, Rs2 : Word; BS : Natural) return Word is
      SI    : constant Natural := Natural (Shift_Right (Rs2, BS * 8) and 16#FF#);
      Sbval : constant Word := Word (AES_Inv_Sbox (SI));
      Shamt : constant Natural := BS * 8;
   begin
      return Rs1 xor Rot_Left (Sbval, Shamt);
   end AES32DSI;

   function AES32DSMI (Rs1, Rs2 : Word; BS : Natural) return Word is
      SI    : constant Natural := Natural (Shift_Right (Rs2, BS * 8) and 16#FF#);
      Sbval : constant Word := Word (AES_Inv_Sbox (SI));
      --  InvMixColumn: gfmul(so,0xb) @ gfmul(so,0xd) @ gfmul(so,0x9) @ gfmul(so,0xe)
      Mixed : constant Word :=
         Shift_Left (GF_Mul (Sbval, 16#0B#), 24) or
         Shift_Left (GF_Mul (Sbval, 16#0D#), 16) or
         Shift_Left (GF_Mul (Sbval, 16#09#), 8) or
         GF_Mul (Sbval, 16#0E#);
      Shamt : constant Natural := BS * 8;
   begin
      return Rs1 xor Rot_Left (Mixed, Shamt);
   end AES32DSMI;

   ----------------
   -- Zknh: SHA-256
   ----------------

   function SHA256SIG0 (Rs1 : Word) return Word is
   begin
      return Rot_Right (Rs1, 7) xor Rot_Right (Rs1, 18) xor
             Shift_Right (Rs1, 3);
   end SHA256SIG0;

   function SHA256SIG1 (Rs1 : Word) return Word is
   begin
      return Rot_Right (Rs1, 17) xor Rot_Right (Rs1, 19) xor
             Shift_Right (Rs1, 10);
   end SHA256SIG1;

   function SHA256SUM0 (Rs1 : Word) return Word is
   begin
      return Rot_Right (Rs1, 2) xor Rot_Right (Rs1, 13) xor
             Rot_Right (Rs1, 22);
   end SHA256SUM0;

   function SHA256SUM1 (Rs1 : Word) return Word is
   begin
      return Rot_Right (Rs1, 6) xor Rot_Right (Rs1, 11) xor
             Rot_Right (Rs1, 25);
   end SHA256SUM1;

   ----------------
   -- Zknh: SHA-512 (RV32)
   ----------------

   function SHA512SIG0H (Rs1, Rs2 : Word) return Word is
   begin
      return Shift_Right (Rs1, 1) xor Shift_Right (Rs1, 7) xor
             Shift_Right (Rs1, 8) xor Shift_Left (Rs2, 31) xor
             Shift_Left (Rs2, 24);
   end SHA512SIG0H;

   function SHA512SIG0L (Rs1, Rs2 : Word) return Word is
   begin
      return Shift_Right (Rs1, 1) xor Shift_Right (Rs1, 7) xor
             Shift_Right (Rs1, 8) xor Shift_Left (Rs2, 31) xor
             Shift_Left (Rs2, 25) xor Shift_Left (Rs2, 24);
   end SHA512SIG0L;

   function SHA512SIG1H (Rs1, Rs2 : Word) return Word is
   begin
      return Shift_Left (Rs1, 3) xor Shift_Right (Rs1, 6) xor
             Shift_Right (Rs1, 19) xor Shift_Right (Rs2, 29) xor
             Shift_Left (Rs2, 13);
   end SHA512SIG1H;

   function SHA512SIG1L (Rs1, Rs2 : Word) return Word is
   begin
      return Shift_Left (Rs1, 3) xor Shift_Right (Rs1, 6) xor
             Shift_Right (Rs1, 19) xor Shift_Right (Rs2, 29) xor
             Shift_Left (Rs2, 26) xor Shift_Left (Rs2, 13);
   end SHA512SIG1L;

   function SHA512SUM0R (Rs1, Rs2 : Word) return Word is
   begin
      return Shift_Left (Rs1, 25) xor Shift_Left (Rs1, 30) xor
             Shift_Right (Rs1, 28) xor Shift_Right (Rs2, 7) xor
             Shift_Right (Rs2, 2) xor Shift_Left (Rs2, 4);
   end SHA512SUM0R;

   function SHA512SUM1R (Rs1, Rs2 : Word) return Word is
   begin
      return Shift_Left (Rs1, 23) xor Shift_Right (Rs1, 14) xor
             Shift_Right (Rs1, 18) xor Shift_Right (Rs2, 9) xor
             Shift_Left (Rs2, 18) xor Shift_Left (Rs2, 14);
   end SHA512SUM1R;

   ----------------
   -- Zksed: SM4
   ----------------

   function SM4ED (Rs1, Rs2 : Word; BS : Natural) return Word is
      SI    : constant Natural := Natural (Shift_Right (Rs2, BS * 8) and 16#FF#);
      X     : constant Word := Word (SM4_Sbox (SI));
      --  SM4 linear transform L for ED (per Sail spec)
      Y     : constant Word := X xor
                                Shift_Left (X, 8) xor
                                Shift_Left (X, 2) xor
                                Shift_Left (X, 18) xor
                                Shift_Left (X and 16#3F#, 26) xor
                                Shift_Left (X and 16#C0#, 10);
      Shamt : constant Natural := BS * 8;
   begin
      return Rot_Left (Y, Shamt) xor Rs1;
   end SM4ED;

   function SM4KS (Rs1, Rs2 : Word; BS : Natural) return Word is
      SI    : constant Natural := Natural (Shift_Right (Rs2, BS * 8) and 16#FF#);
      X     : constant Word := Word (SM4_Sbox (SI));
      --  SM4 linear transform L' for KS (per Sail spec)
      Y     : constant Word := X xor
                                Shift_Left (X and 16#07#, 29) xor
                                Shift_Left (X and 16#FE#, 7) xor
                                Shift_Left (X and 16#01#, 23) xor
                                Shift_Left (X and 16#F8#, 13);
      Shamt : constant Natural := BS * 8;
   begin
      return Rot_Left (Y, Shamt) xor Rs1;
   end SM4KS;

   ----------------
   -- Zksh: SM3
   ----------------

   function SM3P0 (Rs1 : Word) return Word is
   begin
      return Rs1 xor Rot_Left (Rs1, 9) xor Rot_Left (Rs1, 17);
   end SM3P0;

   function SM3P1 (Rs1 : Word) return Word is
   begin
      return Rs1 xor Rot_Left (Rs1, 15) xor Rot_Left (Rs1, 23);
   end SM3P1;

   ----------------
   -- Zbb scalar
   ----------------

   function CLZ (Rs1 : Word) return Word is
      X : Word := Rs1;
      N : Word := 0;
   begin
      if X = 0 then return 32; end if;
      if (X and 16#FFFF0000#) = 0 then N := N + 16; X := Shift_Left (X, 16); end if;
      if (X and 16#FF000000#) = 0 then N := N + 8;  X := Shift_Left (X, 8);  end if;
      if (X and 16#F0000000#) = 0 then N := N + 4;  X := Shift_Left (X, 4);  end if;
      if (X and 16#C0000000#) = 0 then N := N + 2;  X := Shift_Left (X, 2);  end if;
      if (X and 16#80000000#) = 0 then N := N + 1; end if;
      return N;
   end CLZ;

   function CTZ (Rs1 : Word) return Word is
      X : Word := Rs1;
      N : Word := 0;
   begin
      if X = 0 then return 32; end if;
      if (X and 16#0000FFFF#) = 0 then N := N + 16; X := Shift_Right (X, 16); end if;
      if (X and 16#000000FF#) = 0 then N := N + 8;  X := Shift_Right (X, 8);  end if;
      if (X and 16#0000000F#) = 0 then N := N + 4;  X := Shift_Right (X, 4);  end if;
      if (X and 16#00000003#) = 0 then N := N + 2;  X := Shift_Right (X, 2);  end if;
      if (X and 16#00000001#) = 0 then N := N + 1; end if;
      return N;
   end CTZ;

   function CPOP (Rs1 : Word) return Word is
      X : Word := Rs1;
      N : Word := 0;
   begin
      while X /= 0 loop
         N := N + (X and 1);
         X := Shift_Right (X, 1);
      end loop;
      return N;
   end CPOP;

   function SEXT_B (Rs1 : Word) return Word is
      X : constant Word := Rs1 and 16#FF#;
   begin
      if (X and 16#80#) /= 0 then
         return X or 16#FFFFFF00#;
      end if;
      return X;
   end SEXT_B;

   function SEXT_H (Rs1 : Word) return Word is
      X : constant Word := Rs1 and 16#FFFF#;
   begin
      if (X and 16#8000#) /= 0 then
         return X or 16#FFFF0000#;
      end if;
      return X;
   end SEXT_H;

   function ORC_B (Rs1 : Word) return Word is
      Result : Word := 0;
   begin
      for I in 0 .. 3 loop
         if (Shift_Right (Rs1, I * 8) and 16#FF#) /= 0 then
            Result := Result or Shift_Left (16#FF#, I * 8);
         end if;
      end loop;
      return Result;
   end ORC_B;

   --  Helper: signed less-than using two's-complement bit manipulation
   function Signed_LT (A, B : Word) return Boolean is
      Sign_A : constant Boolean := (A and 16#80000000#) /= 0;
      Sign_B : constant Boolean := (B and 16#80000000#) /= 0;
   begin
      if Sign_A = Sign_B then
         return A < B;
      end if;
      return Sign_A;  --  A negative, B non-negative ->A < B
   end Signed_LT;

   function ZBB_MIN (Rs1, Rs2 : Word) return Word is
   begin
      if Signed_LT (Rs1, Rs2) then return Rs1; else return Rs2; end if;
   end ZBB_MIN;

   function ZBB_MAX (Rs1, Rs2 : Word) return Word is
   begin
      if Signed_LT (Rs2, Rs1) then return Rs1; else return Rs2; end if;
   end ZBB_MAX;

   function ZBB_MINU (Rs1, Rs2 : Word) return Word is
   begin
      if Rs1 < Rs2 then return Rs1; else return Rs2; end if;
   end ZBB_MINU;

   function ZBB_MAXU (Rs1, Rs2 : Word) return Word is
   begin
      if Rs1 > Rs2 then return Rs1; else return Rs2; end if;
   end ZBB_MAXU;

   ----------------
   -- Zbs scalar
   ----------------

   function BSET (Rs1, Rs2 : Word) return Word is
      Shamt : constant Natural := Natural (Rs2 and 16#1F#);
   begin
      return Rs1 or Shift_Left (1, Shamt);
   end BSET;

   function BCLR (Rs1, Rs2 : Word) return Word is
      Shamt : constant Natural := Natural (Rs2 and 16#1F#);
   begin
      return Rs1 and not Shift_Left (1, Shamt);
   end BCLR;

   function BINV (Rs1, Rs2 : Word) return Word is
      Shamt : constant Natural := Natural (Rs2 and 16#1F#);
   begin
      return Rs1 xor Shift_Left (1, Shamt);
   end BINV;

   function BEXT (Rs1, Rs2 : Word) return Word is
      Shamt : constant Natural := Natural (Rs2 and 16#1F#);
   begin
      return Shift_Right (Rs1, Shamt) and 1;
   end BEXT;

   -- -------------------------------------------------------------------------
   --  Zbb: 64-bit variants (RV64)
   -- -------------------------------------------------------------------------

   --  Sign-extend lower 32 bits of V to 64 bits.
   function Sign_Extend_32 (V : Double_Word) return Double_Word is
      W32 : constant Double_Word := V and 16#FFFF_FFFF#;
   begin
      if (W32 and 16#8000_0000#) /= 0 then
         return W32 or 16#FFFF_FFFF_0000_0000#;
      end if;
      return W32;
   end Sign_Extend_32;

   function CLZ64 (Rs1 : Double_Word) return Double_Word is
      X : Double_Word := Rs1;
      N : Double_Word := 0;
   begin
      if X = 0 then return 64; end if;
      if (X and 16#FFFF_FFFF_0000_0000#) = 0 then N := N + 32; X := Shift_Left (X, 32); end if;
      if (X and 16#FFFF_0000_0000_0000#) = 0 then N := N + 16; X := Shift_Left (X, 16); end if;
      if (X and 16#FF00_0000_0000_0000#) = 0 then N := N + 8;  X := Shift_Left (X, 8);  end if;
      if (X and 16#F000_0000_0000_0000#) = 0 then N := N + 4;  X := Shift_Left (X, 4);  end if;
      if (X and 16#C000_0000_0000_0000#) = 0 then N := N + 2;  X := Shift_Left (X, 2);  end if;
      if (X and 16#8000_0000_0000_0000#) = 0 then N := N + 1; end if;
      return N;
   end CLZ64;

   function CTZ64 (Rs1 : Double_Word) return Double_Word is
      X : Double_Word := Rs1;
      N : Double_Word := 0;
   begin
      if X = 0 then return 64; end if;
      if (X and 16#0000_0000_FFFF_FFFF#) = 0 then N := N + 32; X := Shift_Right (X, 32); end if;
      if (X and 16#0000_0000_0000_FFFF#) = 0 then N := N + 16; X := Shift_Right (X, 16); end if;
      if (X and 16#0000_0000_0000_00FF#) = 0 then N := N + 8;  X := Shift_Right (X, 8);  end if;
      if (X and 16#0000_0000_0000_000F#) = 0 then N := N + 4;  X := Shift_Right (X, 4);  end if;
      if (X and 16#0000_0000_0000_0003#) = 0 then N := N + 2;  X := Shift_Right (X, 2);  end if;
      if (X and 16#0000_0000_0000_0001#) = 0 then N := N + 1; end if;
      return N;
   end CTZ64;

   function CPOP64 (Rs1 : Double_Word) return Double_Word is
      X : Double_Word := Rs1;
      N : Double_Word := 0;
   begin
      while X /= 0 loop
         N := N + (X and 1);
         X := Shift_Right (X, 1);
      end loop;
      return N;
   end CPOP64;

   function CLZW (Rs1 : Double_Word) return Double_Word is
      W : constant Word := Word (Rs1 and 16#FFFF_FFFF#);
   begin
      return Double_Word (CLZ (W));
   end CLZW;

   function CTZW (Rs1 : Double_Word) return Double_Word is
      W : constant Word := Word (Rs1 and 16#FFFF_FFFF#);
   begin
      return Double_Word (CTZ (W));
   end CTZW;

   function CPOPW (Rs1 : Double_Word) return Double_Word is
      W : constant Word := Word (Rs1 and 16#FFFF_FFFF#);
   begin
      return Double_Word (CPOP (W));
   end CPOPW;

   function REV8_64 (Rs1 : Double_Word) return Double_Word is
      B0 : constant Double_Word := Rs1 and 16#FF#;
      B1 : constant Double_Word := Shift_Right (Rs1, 8)  and 16#FF#;
      B2 : constant Double_Word := Shift_Right (Rs1, 16) and 16#FF#;
      B3 : constant Double_Word := Shift_Right (Rs1, 24) and 16#FF#;
      B4 : constant Double_Word := Shift_Right (Rs1, 32) and 16#FF#;
      B5 : constant Double_Word := Shift_Right (Rs1, 40) and 16#FF#;
      B6 : constant Double_Word := Shift_Right (Rs1, 48) and 16#FF#;
      B7 : constant Double_Word := Shift_Right (Rs1, 56) and 16#FF#;
   begin
      return Shift_Left (B0, 56) or Shift_Left (B1, 48) or
             Shift_Left (B2, 40) or Shift_Left (B3, 32) or
             Shift_Left (B4, 24) or Shift_Left (B5, 16) or
             Shift_Left (B6,  8) or B7;
   end REV8_64;

   function SEXT_B64 (Rs1 : Double_Word) return Double_Word is
      X : constant Double_Word := Rs1 and 16#FF#;
   begin
      if (X and 16#80#) /= 0 then
         return X or 16#FFFF_FFFF_FFFF_FF00#;
      end if;
      return X;
   end SEXT_B64;

   function SEXT_H64 (Rs1 : Double_Word) return Double_Word is
      X : constant Double_Word := Rs1 and 16#FFFF#;
   begin
      if (X and 16#8000#) /= 0 then
         return X or 16#FFFF_FFFF_FFFF_0000#;
      end if;
      return X;
   end SEXT_H64;

   function ZEXT_H64 (Rs1 : Double_Word) return Double_Word is
   begin
      return Rs1 and 16#FFFF#;
   end ZEXT_H64;

   function ROLW (Rs1, Rs2 : Double_Word) return Double_Word is
      Shamt : constant Natural := Natural (Rs2 and 16#1F#);
      W32   : constant Double_Word := Rs1 and 16#FFFF_FFFF#;
      R     : Double_Word;
   begin
      if Shamt = 0 then
         R := W32;
      else
         R := (Shift_Left (W32, Shamt) or Shift_Right (W32, 32 - Shamt))
              and 16#FFFF_FFFF#;
      end if;
      return Sign_Extend_32 (R);
   end ROLW;

   function RORW (Rs1, Rs2 : Double_Word) return Double_Word is
      Shamt : constant Natural := Natural (Rs2 and 16#1F#);
      W32   : constant Double_Word := Rs1 and 16#FFFF_FFFF#;
      R     : Double_Word;
   begin
      if Shamt = 0 then
         R := W32;
      else
         R := (Shift_Right (W32, Shamt) or Shift_Left (W32, 32 - Shamt))
              and 16#FFFF_FFFF#;
      end if;
      return Sign_Extend_32 (R);
   end RORW;

   ----------------------------------------------------
   -- Zbb 64-bit register-register logical / rotate / min-max
   ----------------------------------------------------

   function ANDN64 (Rs1, Rs2 : Double_Word) return Double_Word is
   begin
      return Rs1 and (not Rs2);
   end ANDN64;

   function ORN64 (Rs1, Rs2 : Double_Word) return Double_Word is
   begin
      return Rs1 or (not Rs2);
   end ORN64;

   function XNOR64 (Rs1, Rs2 : Double_Word) return Double_Word is
   begin
      return not (Rs1 xor Rs2);
   end XNOR64;

   function ROL64 (Rs1, Rs2 : Double_Word) return Double_Word is
      Shamt : constant Natural := Natural (Rs2 and 16#3F#);
   begin
      if Shamt = 0 then
         return Rs1;
      end if;
      return Shift_Left (Rs1, Shamt) or Shift_Right (Rs1, 64 - Shamt);
   end ROL64;

   function ROR64 (Rs1, Rs2 : Double_Word) return Double_Word is
      Shamt : constant Natural := Natural (Rs2 and 16#3F#);
   begin
      if Shamt = 0 then
         return Rs1;
      end if;
      return Shift_Right (Rs1, Shamt) or Shift_Left (Rs1, 64 - Shamt);
   end ROR64;

   function RORI64 (Rs1 : Double_Word; Shamt : Natural) return Double_Word is
   begin
      if Shamt = 0 then
         return Rs1;
      end if;
      return Shift_Right (Rs1, Shamt) or Shift_Left (Rs1, 64 - Shamt);
   end RORI64;

   function ORC_B64 (Rs1 : Double_Word) return Double_Word is
      Result : Double_Word := 0;
   begin
      for I in 0 .. 7 loop
         if (Shift_Right (Rs1, I * 8) and 16#FF#) /= 0 then
            Result := Result or Shift_Left (Double_Word (16#FF#), I * 8);
         end if;
      end loop;
      return Result;
   end ORC_B64;

   --  Helper: signed less-than on 64-bit two's-complement values
   function Signed_LT64 (A, B : Double_Word) return Boolean is
      Sign_A : constant Boolean := (A and 16#8000_0000_0000_0000#) /= 0;
      Sign_B : constant Boolean := (B and 16#8000_0000_0000_0000#) /= 0;
   begin
      if Sign_A = Sign_B then
         return A < B;
      end if;
      return Sign_A;  --  A negative, B non-negative ->A < B
   end Signed_LT64;

   function ZBB_MIN64 (Rs1, Rs2 : Double_Word) return Double_Word is
   begin
      if Signed_LT64 (Rs1, Rs2) then return Rs1; else return Rs2; end if;
   end ZBB_MIN64;

   function ZBB_MAX64 (Rs1, Rs2 : Double_Word) return Double_Word is
   begin
      if Signed_LT64 (Rs2, Rs1) then return Rs1; else return Rs2; end if;
   end ZBB_MAX64;

   function ZBB_MINU64 (Rs1, Rs2 : Double_Word) return Double_Word is
   begin
      if Rs1 < Rs2 then return Rs1; else return Rs2; end if;
   end ZBB_MINU64;

   function ZBB_MAXU64 (Rs1, Rs2 : Double_Word) return Double_Word is
   begin
      if Rs1 > Rs2 then return Rs1; else return Rs2; end if;
   end ZBB_MAXU64;

   -- -------------------------------------------------------------------------
   --  Zbs: 64-bit variants (RV64) -- shift amount is Rs2[5:0]
   -- -------------------------------------------------------------------------

   function BSET64 (Rs1, Rs2 : Double_Word) return Double_Word is
      Shamt : constant Natural := Natural (Rs2 and 16#3F#);
   begin
      return Rs1 or Shift_Left (Double_Word (1), Shamt);
   end BSET64;

   function BCLR64 (Rs1, Rs2 : Double_Word) return Double_Word is
      Shamt : constant Natural := Natural (Rs2 and 16#3F#);
   begin
      return Rs1 and not Shift_Left (Double_Word (1), Shamt);
   end BCLR64;

   function BINV64 (Rs1, Rs2 : Double_Word) return Double_Word is
      Shamt : constant Natural := Natural (Rs2 and 16#3F#);
   begin
      return Rs1 xor Shift_Left (Double_Word (1), Shamt);
   end BINV64;

   function BEXT64 (Rs1, Rs2 : Double_Word) return Double_Word is
      Shamt : constant Natural := Natural (Rs2 and 16#3F#);
   begin
      return Shift_Right (Rs1, Shamt) and 1;
   end BEXT64;

   -- -------------------------------------------------------------------------
   --  Zbc / Zbkc: 64-bit carry-less multiply
   -- -------------------------------------------------------------------------

   --  Low 64 bits of the 128-bit carry-less product.
   function CLMUL64 (Rs1, Rs2 : Double_Word) return Double_Word is
      Result : Double_Word := 0;
   begin
      for I in 0 .. 63 loop
         if (Rs2 and Shift_Left (Double_Word (1), I)) /= 0 then
            Result := Result xor Shift_Left (Rs1, I);
         end if;
      end loop;
      return Result;
   end CLMUL64;

   --  High 64 bits of the 128-bit carry-less product.
   function CLMULH64 (Rs1, Rs2 : Double_Word) return Double_Word is
      Result : Double_Word := 0;
   begin
      for I in 1 .. 63 loop
         if (Rs2 and Shift_Left (Double_Word (1), I)) /= 0 then
            Result := Result xor Shift_Right (Rs1, 64 - I);
         end if;
      end loop;
      return Result;
   end CLMULH64;

   --  Bits [126:63] of the 128-bit carry-less product (Zbc clmulr).
   function CLMULR64 (Rs1, Rs2 : Double_Word) return Double_Word is
      Result : Double_Word := 0;
   begin
      for I in 0 .. 63 loop
         if (Rs2 and Shift_Left (Double_Word (1), I)) /= 0 then
            Result := Result xor Shift_Right (Rs1, 63 - I);
         end if;
      end loop;
      return Result;
   end CLMULR64;

   -- -------------------------------------------------------------------------
   --  Zbkx: 64-bit crossbar permutations
   -- -------------------------------------------------------------------------

   --  An index past the end of Rs1 selects zero, per the spec: for xperm4
   --  every 4-bit index is in range on RV64 (16 nibbles), for xperm8 an
   --  index of 8 or more is out of range.
   function XPERM4_64 (Rs1, Rs2 : Double_Word) return Double_Word is
      Result : Double_Word := 0;
      Idx    : Natural;
   begin
      for I in 0 .. 15 loop
         Idx := Natural (Shift_Right (Rs2, I * 4) and 16#F#);
         Result := Result or
           Shift_Left (Shift_Right (Rs1, Idx * 4) and 16#F#, I * 4);
      end loop;
      return Result;
   end XPERM4_64;

   function XPERM8_64 (Rs1, Rs2 : Double_Word) return Double_Word is
      Result : Double_Word := 0;
      Idx    : Natural;
   begin
      for I in 0 .. 7 loop
         Idx := Natural (Shift_Right (Rs2, I * 8) and 16#FF#);
         if Idx < 8 then
            Result := Result or
              Shift_Left (Shift_Right (Rs1, Idx * 8) and 16#FF#, I * 8);
         end if;
      end loop;
      return Result;
   end XPERM8_64;

   -- -------------------------------------------------------------------------
   --  Zbkb: 64-bit variants (RV64)
   -- -------------------------------------------------------------------------

   function PACK64 (Rs1, Rs2 : Double_Word) return Double_Word is
   begin
      return (Rs1 and 16#FFFF_FFFF#) or
             Shift_Left (Rs2 and 16#FFFF_FFFF#, 32);
   end PACK64;

   function PACKH64 (Rs1, Rs2 : Double_Word) return Double_Word is
   begin
      return (Rs1 and 16#FF#) or Shift_Left (Rs2 and 16#FF#, 8);
   end PACKH64;

   function PACKW (Rs1, Rs2 : Double_Word) return Double_Word is
   begin
      return Sign_Extend_32
        ((Rs1 and 16#FFFF#) or Shift_Left (Rs2 and 16#FFFF#, 16));
   end PACKW;

   --  Reverse the bit order within each of the eight bytes.
   function BREV8_64 (Rs1 : Double_Word) return Double_Word is
      Result : Double_Word := 0;
      B      : Double_Word;
      Rev    : Double_Word;
   begin
      for Bi in 0 .. 7 loop
         B   := Shift_Right (Rs1, Bi * 8) and 16#FF#;
         Rev := 0;
         for Bit in 0 .. 7 loop
            if (B and Shift_Left (Double_Word (1), Bit)) /= 0 then
               Rev := Rev or Shift_Left (Double_Word (1), 7 - Bit);
            end if;
         end loop;
         Result := Result or Shift_Left (Rev, Bi * 8);
      end loop;
      return Result;
   end BREV8_64;

end RISCV.Crypto;
