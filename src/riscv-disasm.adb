-- ***************************************************************************
--               RISC-V Emulator - Disassembler
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

with RISCV.Decoder;
with RISCV.CSR;
with Ada.Strings.Fixed;
with Ada.Unchecked_Conversion;

package body RISCV.Disasm is

   function To_Word is new Ada.Unchecked_Conversion (Signed_Word, Word);
   function To_Signed is new Ada.Unchecked_Conversion (Word, Signed_Word);

   --  ABI register names
   Register_Names : constant array (Register_Index) of String (1 .. 3) :=
     ("x0 ", "ra ", "sp ", "gp ", "tp ", "t0 ", "t1 ", "t2 ",
      "s0 ", "s1 ", "a0 ", "a1 ", "a2 ", "a3 ", "a4 ", "a5 ",
      "a6 ", "a7 ", "s2 ", "s3 ", "s4 ", "s5 ", "s6 ", "s7 ",
      "s8 ", "s9 ", "s10", "s11", "t3 ", "t4 ", "t5 ", "t6 ");

   --------------
   -- Reg_Name --
   --------------

   function Reg_Name (Reg : Register_Index) return String is
   begin
      return Ada.Strings.Fixed.Trim (Register_Names (Reg),
                                     Ada.Strings.Right);
   end Reg_Name;

   --  Local helper functions
   function To_Hex (V : Word) return String;
   function To_Hex_Short (V : Word) return String;
   function Signed_Imm (V : Signed_Word) return String;

   function To_Hex (V : Word) return String is
      Hex_Chars : constant String := "0123456789abcdef";
      Result    : String (1 .. 8);
      Val       : Word := V;
   begin
      for I in reverse Result'Range loop
         Result (I) := Hex_Chars (Natural (Val and 16#F#) + 1);
         Val := Shift_Right (Val, 4);
      end loop;
      return Result;
   end To_Hex;

   function To_Hex_Short (V : Word) return String is
      Full : constant String := To_Hex (V);
      I    : Natural := Full'First;
   begin
      while I < Full'Last and then Full (I) = '0' loop
         I := I + 1;
      end loop;
      return Full (I .. Full'Last);
   end To_Hex_Short;

   function Signed_Imm (V : Signed_Word) return String is
   begin
      if V < 0 then
         return Signed_Word'Image (V);
      else
         return " " & Ada.Strings.Fixed.Trim (Signed_Word'Image (V),
                                              Ada.Strings.Left);
      end if;
   end Signed_Imm;

   -----------------
   -- Disassemble --
   -----------------

   function Disassemble (Instruction : Word;
                         PC          : Word;
                         Xlen64      : Boolean := False) return String is
      use Decoder;
      D : constant Decoded_Instruction := Decode (Instruction);

      function Rd return String;
      function Rs1 return String;
      function Rs2 return String;
      function Branch_Target return String;
      function Jump_Target return String;

      function Rd return String is (Reg_Name (D.Rd));
      function Rs1 return String is (Reg_Name (D.Rs1));
      function Rs2 return String is (Reg_Name (D.Rs2));

      function Branch_Target return String is
         Target : constant Word := To_Word (To_Signed (PC) + D.Imm_B);
      begin
         return "0x" & To_Hex_Short (Target);
      end Branch_Target;

      function Jump_Target return String is
         Target : constant Word := To_Word (To_Signed (PC) + D.Imm_J);
      begin
         return "0x" & To_Hex_Short (Target);
      end Jump_Target;

   begin
      case D.Opcode is
         when OPCODE_LUI =>
            return "lui     " & Rd & ", 0x" &
                   To_Hex_Short (Shift_Right (D.Imm_U, 12));

         when OPCODE_AUIPC =>
            return "auipc   " & Rd & ", 0x" &
                   To_Hex_Short (Shift_Right (D.Imm_U, 12));

         when OPCODE_JAL =>
            if D.Rd = 0 then
               return "j       " & Jump_Target;
            elsif D.Rd = 1 then
               return "jal     " & Jump_Target;
            else
               return "jal     " & Rd & ", " & Jump_Target;
            end if;

         when OPCODE_JALR =>
            if D.Rd = 0 and D.Rs1 = 1 and D.Imm_I = 0 then
               return "ret";
            elsif D.Rd = 0 and D.Imm_I = 0 then
               return "jr      " & Rs1;
            elsif D.Rd = 1 and D.Imm_I = 0 then
               return "jalr    " & Rs1;
            else
               return "jalr    " & Rd & ", " & Rs1 & ", " &
                      Signed_Imm (D.Imm_I);
            end if;

         when OPCODE_BRANCH =>
            case D.Funct3 is
               when FUNCT3_BEQ =>
                  if D.Rs2 = 0 then
                     return "beqz    " & Rs1 & ", " & Branch_Target;
                  else
                     return "beq     " & Rs1 & ", " & Rs2 & ", " &
                            Branch_Target;
                  end if;
               when FUNCT3_BNE =>
                  if D.Rs2 = 0 then
                     return "bnez    " & Rs1 & ", " & Branch_Target;
                  else
                     return "bne     " & Rs1 & ", " & Rs2 & ", " &
                            Branch_Target;
                  end if;
               when FUNCT3_BLT =>
                  return "blt     " & Rs1 & ", " & Rs2 & ", " & Branch_Target;
               when FUNCT3_BGE =>
                  if D.Rs1 = 0 then
                     return "blez    " & Rs2 & ", " & Branch_Target;
                  else
                     return "bge     " & Rs1 & ", " & Rs2 & ", " &
                            Branch_Target;
                  end if;
               when FUNCT3_BLTU =>
                  return "bltu    " & Rs1 & ", " & Rs2 & ", " & Branch_Target;
               when FUNCT3_BGEU =>
                  return "bgeu    " & Rs1 & ", " & Rs2 & ", " & Branch_Target;
               when others =>
                  return "???";
            end case;

         when OPCODE_LOAD =>
            declare
               Offset : constant String := Signed_Imm (D.Imm_I);
            begin
               case D.Funct3 is
                  when FUNCT3_LB =>
                     return "lb      " & Rd & ", " & Offset & "(" & Rs1 & ")";
                  when FUNCT3_LH =>
                     return "lh      " & Rd & ", " & Offset & "(" & Rs1 & ")";
                  when FUNCT3_LW =>
                     return "lw      " & Rd & ", " & Offset & "(" & Rs1 & ")";
                  when FUNCT3_LBU =>
                     return "lbu     " & Rd & ", " & Offset & "(" & Rs1 & ")";
                  when FUNCT3_LHU =>
                     return "lhu     " & Rd & ", " & Offset & "(" & Rs1 & ")";
                  when others =>
                     return "???";
               end case;
            end;

         when OPCODE_STORE =>
            declare
               Offset : constant String := Signed_Imm (D.Imm_S);
            begin
               case D.Funct3 is
                  when FUNCT3_SB =>
                     return "sb      " & Rs2 & ", " & Offset & "(" & Rs1 & ")";
                  when FUNCT3_SH =>
                     return "sh      " & Rs2 & ", " & Offset & "(" & Rs1 & ")";
                  when FUNCT3_SW =>
                     return "sw      " & Rs2 & ", " & Offset & "(" & Rs1 & ")";
                  when others =>
                     return "???";
               end case;
            end;

         when OPCODE_OP_IMM =>
            declare
               Imm     : constant String := Signed_Imm (D.Imm_I);
               --  shamt is 6 bits on RV64, 5 on RV32
               Sh_Mask : constant Word := (if Xlen64 then 16#3F# else 16#1F#);
               Shamt   : constant String :=
                  Ada.Strings.Fixed.Trim
                    (Natural'Image (Natural (To_Word (D.Imm_I) and Sh_Mask)),
                     Ada.Strings.Left);
               F6      : constant Word :=
                  Shift_Right (Instruction, 26) and 16#3F#;
               Imm12   : constant Word :=
                  Shift_Right (Instruction, 20) and 16#FFF#;
               --  On RV32 bit 25 is not part of shamt, so when it is set
               --  every shift-immediate form is reserved.
               Sh_Bad  : constant Boolean :=
                  not Xlen64 and then (Instruction and 16#0200_0000#) /= 0;
            begin
               case D.Funct3 is
                  when FUNCT3_ADD_SUB =>
                     if D.Rs1 = 0 then
                        return "li      " & Rd & ", " & Imm;
                     elsif D.Imm_I = 0 then
                        return "mv      " & Rd & ", " & Rs1;
                     else
                        return "addi    " & Rd & ", " & Rs1 & ", " & Imm;
                     end if;
                  when FUNCT3_SLT =>
                     return "slti    " & Rd & ", " & Rs1 & ", " & Imm;
                  when FUNCT3_SLTU =>
                     if D.Imm_I = 1 then
                        return "seqz    " & Rd & ", " & Rs1;
                     else
                        return "sltiu   " & Rd & ", " & Rs1 & ", " & Imm;
                     end if;
                  when FUNCT3_XOR =>
                     if D.Imm_I = -1 then
                        return "not     " & Rd & ", " & Rs1;
                     else
                        return "xori    " & Rd & ", " & Rs1 & ", " & Imm;
                     end if;
                  when FUNCT3_OR =>
                     return "ori     " & Rd & ", " & Rs1 & ", " & Imm;
                  when FUNCT3_AND =>
                     return "andi    " & Rd & ", " & Rs1 & ", " & Imm;
                  when FUNCT3_SLL =>
                     if D.Funct7 = FUNCT7_SHA256SIG0 then
                        case Word (D.Rs2) is
                           when SHA256_SUM0_RS2 =>
                              return "sha256sum0 " & Rd & ", " & Rs1;
                           when SHA256_SUM1_RS2 =>
                              return "sha256sum1 " & Rd & ", " & Rs1;
                           when SHA256_SIG0_RS2 =>
                              return "sha256sig0 " & Rd & ", " & Rs1;
                           when SHA256_SIG1_RS2 =>
                              return "sha256sig1 " & Rd & ", " & Rs1;
                           when SM3P0_RS2 =>
                              return "sm3p0   " & Rd & ", " & Rs1;
                           when SM3P1_RS2 =>
                              return "sm3p1   " & Rd & ", " & Rs1;
                           when others =>
                              return "???";
                        end case;
                     elsif D.Funct7 = FUNCT7_ROL then
                        case Word (D.Rs2) is
                           when ZBB_CLZ_RS2   => return "clz     " & Rd & ", " & Rs1;
                           when ZBB_CTZ_RS2   => return "ctz     " & Rd & ", " & Rs1;
                           when ZBB_CPOP_RS2  => return "cpop    " & Rd & ", " & Rs1;
                           when ZBB_SEXTB_RS2 => return "sext.b  " & Rd & ", " & Rs1;
                           when ZBB_SEXTH_RS2 => return "sext.h  " & Rd & ", " & Rs1;
                           when others        => return "???";
                        end case;
                     elsif not Xlen64 and then D.Funct7 = FUNCT7_ZIP
                       and then Word (D.Rs2) = 15
                     then
                        return "zip     " & Rd & ", " & Rs1;
                     elsif Sh_Bad then
                        return "???";
                     else
                        case F6 is
                           when 2#000000# =>
                              return "slli    " & Rd & ", " & Rs1 & ", " & Shamt;
                           when 2#001010# =>
                              return "bseti   " & Rd & ", " & Rs1 & ", " & Shamt;
                           when 2#010010# =>
                              return "bclri   " & Rd & ", " & Rs1 & ", " & Shamt;
                           when 2#011010# =>
                              return "binvi   " & Rd & ", " & Rs1 & ", " & Shamt;
                           when others =>
                              return "???";
                        end case;
                     end if;
                  when FUNCT3_SRL_SRA =>
                     if Imm12 = 16#287# then
                        return "orc.b   " & Rd & ", " & Rs1;
                     elsif Imm12 = (if Xlen64 then 16#6B8# else 16#698#) then
                        return "rev8    " & Rd & ", " & Rs1;
                     elsif Imm12 = 16#687# then
                        return "brev8   " & Rd & ", " & Rs1;
                     elsif not Xlen64 and then D.Funct7 = FUNCT7_UNZIP
                       and then Word (D.Rs2) = 15
                     then
                        return "unzip   " & Rd & ", " & Rs1;
                     elsif Sh_Bad then
                        return "???";
                     else
                        case F6 is
                           when 2#000000# =>
                              return "srli    " & Rd & ", " & Rs1 & ", " & Shamt;
                           when 2#010000# =>
                              return "srai    " & Rd & ", " & Rs1 & ", " & Shamt;
                           when 2#011000# =>
                              return "rori    " & Rd & ", " & Rs1 & ", " & Shamt;
                           when 2#010010# =>
                              return "bexti   " & Rd & ", " & Rs1 & ", " & Shamt;
                           when others =>
                              return "???";
                        end case;
                     end if;
                  when others =>
                     return "???";
               end case;
            end;

         when OPCODE_OP =>
            --  K extension: check specific funct7/funct3 combos
            declare
               Funct5_K : constant Word :=
                  Shift_Right (Instruction, 25) and 16#1F#;
               BS_K     : constant Natural :=
                  Natural (Shift_Right (Instruction, 30));
               BS_Str   : constant String :=
                  Ada.Strings.Fixed.Trim
                    (Natural'Image (BS_K), Ada.Strings.Left);
            begin
               --  AES/SM4 (funct3=000)
               if D.Funct3 = FUNCT3_ADD_SUB then
                  case Funct5_K is
                     when FUNCT5_AES32ESI =>
                        return "aes32esi " & Rd & ", " & Rs1 & ", " &
                               Rs2 & ", " & BS_Str;
                     when FUNCT5_AES32ESMI =>
                        return "aes32esmi " & Rd & ", " & Rs1 & ", " &
                               Rs2 & ", " & BS_Str;
                     when FUNCT5_AES32DSI =>
                        return "aes32dsi " & Rd & ", " & Rs1 & ", " &
                               Rs2 & ", " & BS_Str;
                     when FUNCT5_AES32DSMI =>
                        return "aes32dsmi " & Rd & ", " & Rs1 & ", " &
                               Rs2 & ", " & BS_Str;
                     when FUNCT5_SM4ED =>
                        return "sm4ed   " & Rd & ", " & Rs1 & ", " &
                               Rs2 & ", " & BS_Str;
                     when FUNCT5_SM4KS =>
                        return "sm4ks   " & Rd & ", " & Rs1 & ", " &
                               Rs2 & ", " & BS_Str;
                     when others => null;
                  end case;
                  --  SHA-512
                  case D.Funct7 is
                     when FUNCT7_SHA512SIG0H =>
                        return "sha512sig0h " & Rd & ", " & Rs1 & ", " & Rs2;
                     when FUNCT7_SHA512SIG0L =>
                        return "sha512sig0l " & Rd & ", " & Rs1 & ", " & Rs2;
                     when FUNCT7_SHA512SIG1H =>
                        return "sha512sig1h " & Rd & ", " & Rs1 & ", " & Rs2;
                     when FUNCT7_SHA512SIG1L =>
                        return "sha512sig1l " & Rd & ", " & Rs1 & ", " & Rs2;
                     when FUNCT7_SHA512SUM0R =>
                        return "sha512sum0r " & Rd & ", " & Rs1 & ", " & Rs2;
                     when FUNCT7_SHA512SUM1R =>
                        return "sha512sum1r " & Rd & ", " & Rs1 & ", " & Rs2;
                     when others => null;
                  end case;
               end if;
               --  Zbkb/Zbkc/Zbkx R-type
               if D.Funct3 = FUNCT3_SLL and D.Funct7 = FUNCT7_ROL then
                  return "rol     " & Rd & ", " & Rs1 & ", " & Rs2;
               elsif D.Funct3 = FUNCT3_SRL_SRA and D.Funct7 = FUNCT7_ROR then
                  return "ror     " & Rd & ", " & Rs1 & ", " & Rs2;
               elsif D.Funct3 = FUNCT3_SLL and D.Funct7 = FUNCT7_CLMUL then
                  return "clmul   " & Rd & ", " & Rs1 & ", " & Rs2;
               elsif D.Funct3 = FUNCT3_SLTU and D.Funct7 = FUNCT7_CLMULH then
                  return "clmulh  " & Rd & ", " & Rs1 & ", " & Rs2;
               elsif D.Funct3 = FUNCT3_SLT and D.Funct7 = FUNCT7_XPERM4 then
                  return "xperm4  " & Rd & ", " & Rs1 & ", " & Rs2;
               elsif D.Funct3 = FUNCT3_SLT and D.Funct7 = FUNCT7_ZBA then
                  return "sh1add  " & Rd & ", " & Rs1 & ", " & Rs2;
               elsif D.Funct3 = FUNCT3_XOR and D.Funct7 = FUNCT7_ZBA then
                  return "sh2add  " & Rd & ", " & Rs1 & ", " & Rs2;
               elsif D.Funct3 = FUNCT3_OR and D.Funct7 = FUNCT7_ZBA then
                  return "sh3add  " & Rd & ", " & Rs1 & ", " & Rs2;
               elsif D.Funct3 = FUNCT3_XOR and D.Funct7 = FUNCT7_XPERM8 then
                  return "xperm8  " & Rd & ", " & Rs1 & ", " & Rs2;
               elsif D.Funct3 = FUNCT3_XOR and D.Funct7 = FUNCT7_PACK then
                  return "pack    " & Rd & ", " & Rs1 & ", " & Rs2;
               elsif D.Funct3 = FUNCT3_AND and D.Funct7 = FUNCT7_PACKH then
                  return "packh   " & Rd & ", " & Rs1 & ", " & Rs2;
               elsif D.Funct3 = FUNCT3_AND and D.Funct7 = FUNCT7_ANDN then
                  return "andn    " & Rd & ", " & Rs1 & ", " & Rs2;
               elsif D.Funct3 = FUNCT3_OR and D.Funct7 = FUNCT7_ORN then
                  return "orn     " & Rd & ", " & Rs1 & ", " & Rs2;
               elsif D.Funct3 = FUNCT3_XOR and D.Funct7 = FUNCT7_ANDN then
                  return "xnor    " & Rd & ", " & Rs1 & ", " & Rs2;
               elsif D.Funct3 = FUNCT3_SLT and D.Funct7 = FUNCT7_CLMUL then
                  return "clmulr  " & Rd & ", " & Rs1 & ", " & Rs2;
               elsif D.Funct7 = FUNCT7_MINMAX and D.Funct3 = FUNCT3_XOR then
                  return "min     " & Rd & ", " & Rs1 & ", " & Rs2;
               elsif D.Funct7 = FUNCT7_MINMAX and D.Funct3 = FUNCT3_SRL_SRA then
                  return "minu    " & Rd & ", " & Rs1 & ", " & Rs2;
               elsif D.Funct7 = FUNCT7_MINMAX and D.Funct3 = FUNCT3_OR then
                  return "max     " & Rd & ", " & Rs1 & ", " & Rs2;
               elsif D.Funct7 = FUNCT7_MINMAX and D.Funct3 = FUNCT3_AND then
                  return "maxu    " & Rd & ", " & Rs1 & ", " & Rs2;
               elsif D.Funct7 = FUNCT7_ZICOND and D.Funct3 = FUNCT3_SRL_SRA then
                  return "czero.eqz " & Rd & ", " & Rs1 & ", " & Rs2;
               elsif D.Funct7 = FUNCT7_ZICOND and D.Funct3 = FUNCT3_AND then
                  return "czero.nez " & Rd & ", " & Rs1 & ", " & Rs2;
               elsif D.Funct7 = FUNCT7_BSET and D.Funct3 = FUNCT3_SLL then
                  return "bset    " & Rd & ", " & Rs1 & ", " & Rs2;
               elsif D.Funct7 = FUNCT7_BCLR and D.Funct3 = FUNCT3_SLL then
                  return "bclr    " & Rd & ", " & Rs1 & ", " & Rs2;
               elsif D.Funct7 = FUNCT7_BCLR and D.Funct3 = FUNCT3_SRL_SRA then
                  return "bext    " & Rd & ", " & Rs1 & ", " & Rs2;
               elsif D.Funct7 = FUNCT7_BINV and D.Funct3 = FUNCT3_SLL then
                  return "binv    " & Rd & ", " & Rs1 & ", " & Rs2;
               end if;
            end;

            if D.Funct7 = FUNCT7_MULDIV then
               case D.Funct3 is
                  when FUNCT3_MUL =>
                     return "mul     " & Rd & ", " & Rs1 & ", " & Rs2;
                  when FUNCT3_MULH =>
                     return "mulh    " & Rd & ", " & Rs1 & ", " & Rs2;
                  when FUNCT3_MULHSU =>
                     return "mulhsu  " & Rd & ", " & Rs1 & ", " & Rs2;
                  when FUNCT3_MULHU =>
                     return "mulhu   " & Rd & ", " & Rs1 & ", " & Rs2;
                  when FUNCT3_DIV =>
                     return "div     " & Rd & ", " & Rs1 & ", " & Rs2;
                  when FUNCT3_DIVU =>
                     return "divu    " & Rd & ", " & Rs1 & ", " & Rs2;
                  when FUNCT3_REM =>
                     return "rem     " & Rd & ", " & Rs1 & ", " & Rs2;
                  when FUNCT3_REMU =>
                     return "remu    " & Rd & ", " & Rs1 & ", " & Rs2;
                  when others =>
                     return "???";
               end case;
            else
               --  Only funct7 = 0000000, and 0100000 for sub/sra, are base
               --  ops; any other funct7 that reaches here is reserved.
               if D.Funct7 /= 0
                 and then not (D.Funct7 = FUNCT7_ALT
                               and then (D.Funct3 = FUNCT3_ADD_SUB
                                         or else D.Funct3 = FUNCT3_SRL_SRA))
               then
                  return "???";
               end if;
               case D.Funct3 is
                  when FUNCT3_ADD_SUB =>
                     if D.Funct7 = FUNCT7_ALT then
                        if D.Rs1 = 0 then
                           return "neg     " & Rd & ", " & Rs2;
                        else
                           return "sub     " & Rd & ", " & Rs1 & ", " & Rs2;
                        end if;
                     else
                        return "add     " & Rd & ", " & Rs1 & ", " & Rs2;
                     end if;
                  when FUNCT3_SLL =>
                     return "sll     " & Rd & ", " & Rs1 & ", " & Rs2;
                  when FUNCT3_SLT =>
                     if D.Rs2 = 0 then
                        return "sltz    " & Rd & ", " & Rs1;
                     else
                        return "slt     " & Rd & ", " & Rs1 & ", " & Rs2;
                     end if;
                  when FUNCT3_SLTU =>
                     if D.Rs1 = 0 then
                        return "snez    " & Rd & ", " & Rs2;
                     else
                        return "sltu    " & Rd & ", " & Rs1 & ", " & Rs2;
                     end if;
                  when FUNCT3_XOR =>
                     return "xor     " & Rd & ", " & Rs1 & ", " & Rs2;
                  when FUNCT3_SRL_SRA =>
                     if D.Funct7 = FUNCT7_ALT then
                        return "sra     " & Rd & ", " & Rs1 & ", " & Rs2;
                     else
                        return "srl     " & Rd & ", " & Rs1 & ", " & Rs2;
                     end if;
                  when FUNCT3_OR =>
                     return "or      " & Rd & ", " & Rs1 & ", " & Rs2;
                  when FUNCT3_AND =>
                     return "and     " & Rd & ", " & Rs1 & ", " & Rs2;
                  when others =>
                     return "???";
               end case;
            end if;

         when OPCODE_OP_IMM_32 =>
            declare
               Imm    : constant String := Signed_Imm (D.Imm_I);
               Shamt5 : constant String :=
                  Ada.Strings.Fixed.Trim
                    (Natural'Image (Natural (To_Word (D.Imm_I) and 16#1F#)),
                     Ada.Strings.Left);
               Shamt6 : constant String :=
                  Ada.Strings.Fixed.Trim
                    (Natural'Image (Natural (To_Word (D.Imm_I) and 16#3F#)),
                     Ada.Strings.Left);
            begin
               case D.Funct3 is
                  when FUNCT3_ADD_SUB =>
                     if D.Imm_I = 0 then
                        return "sext.w  " & Rd & ", " & Rs1;
                     else
                        return "addiw   " & Rd & ", " & Rs1 & ", " & Imm;
                     end if;
                  when FUNCT3_SLL =>
                     if (D.Funct7 and 2#1111110#) = FUNCT7_PACK then
                        return "slli.uw " & Rd & ", " & Rs1 & ", " & Shamt6;
                     elsif D.Funct7 = FUNCT7_ROL then
                        case Word (D.Rs2) is
                           when ZBB_CLZ_RS2  => return "clzw    " & Rd & ", " & Rs1;
                           when ZBB_CTZ_RS2  => return "ctzw    " & Rd & ", " & Rs1;
                           when ZBB_CPOP_RS2 => return "cpopw   " & Rd & ", " & Rs1;
                           when others       => return "???";
                        end case;
                     elsif D.Funct7 = 0 then
                        return "slliw   " & Rd & ", " & Rs1 & ", " & Shamt5;
                     else
                        return "???";
                     end if;
                  when FUNCT3_SRL_SRA =>
                     if D.Funct7 = 0 then
                        return "srliw   " & Rd & ", " & Rs1 & ", " & Shamt5;
                     elsif D.Funct7 = FUNCT7_ALT then
                        return "sraiw   " & Rd & ", " & Rs1 & ", " & Shamt5;
                     elsif D.Funct7 = FUNCT7_ROR then
                        return "roriw   " & Rd & ", " & Rs1 & ", " & Shamt5;
                     else
                        return "???";
                     end if;
                  when others =>
                     return "???";
               end case;
            end;

         when OPCODE_OP_32 =>
            case D.Funct7 is
               when 2#0000000# =>
                  case D.Funct3 is
                     when FUNCT3_ADD_SUB => return "addw    " & Rd & ", " & Rs1 & ", " & Rs2;
                     when FUNCT3_SLL     => return "sllw    " & Rd & ", " & Rs1 & ", " & Rs2;
                     when FUNCT3_SRL_SRA => return "srlw    " & Rd & ", " & Rs1 & ", " & Rs2;
                     when others         => return "???";
                  end case;
               when 2#0100000# =>
                  case D.Funct3 is
                     when FUNCT3_ADD_SUB => return "subw    " & Rd & ", " & Rs1 & ", " & Rs2;
                     when FUNCT3_SRL_SRA => return "sraw    " & Rd & ", " & Rs1 & ", " & Rs2;
                     when others         => return "???";
                  end case;
               when 2#0000001# =>
                  case D.Funct3 is
                     when FUNCT3_MUL  => return "mulw    " & Rd & ", " & Rs1 & ", " & Rs2;
                     when FUNCT3_DIV  => return "divw    " & Rd & ", " & Rs1 & ", " & Rs2;
                     when FUNCT3_DIVU => return "divuw   " & Rd & ", " & Rs1 & ", " & Rs2;
                     when FUNCT3_REM  => return "remw    " & Rd & ", " & Rs1 & ", " & Rs2;
                     when FUNCT3_REMU => return "remuw   " & Rd & ", " & Rs1 & ", " & Rs2;
                     when others      => return "???";
                  end case;
               when 2#0110000# =>
                  case D.Funct3 is
                     when FUNCT3_SLL     => return "rolw    " & Rd & ", " & Rs1 & ", " & Rs2;
                     when FUNCT3_SRL_SRA => return "rorw    " & Rd & ", " & Rs1 & ", " & Rs2;
                     when others         => return "???";
                  end case;
               when 2#0000100# =>
                  case D.Funct3 is
                     when FUNCT3_ADD_SUB =>
                        if D.Rs2 = 0 then
                           return "zext.w  " & Rd & ", " & Rs1;
                        else
                           return "add.uw  " & Rd & ", " & Rs1 & ", " & Rs2;
                        end if;
                     when FUNCT3_XOR =>
                        if D.Rs2 = 0 then
                           return "zext.h  " & Rd & ", " & Rs1;
                        else
                           return "packw   " & Rd & ", " & Rs1 & ", " & Rs2;
                        end if;
                     when others =>
                        return "???";
                  end case;
               when 2#0010000# =>
                  case D.Funct3 is
                     when FUNCT3_SLT => return "sh1add.uw " & Rd & ", " & Rs1 & ", " & Rs2;
                     when FUNCT3_XOR => return "sh2add.uw " & Rd & ", " & Rs1 & ", " & Rs2;
                     when FUNCT3_OR  => return "sh3add.uw " & Rd & ", " & Rs1 & ", " & Rs2;
                     when others     => return "???";
                  end case;
               when others =>
                  return "???";
            end case;

         when OPCODE_SYSTEM =>
            if D.Funct3 = FUNCT3_ECALL_EBREAK then
               if Instruction = 16#30200073# then
                  return "mret";
               elsif Instruction = 16#10200073# then
                  return "sret";
               elsif Instruction = 16#10500073# then
                  return "wfi";
               elsif (Instruction and 16#FE007FFF#) = 16#12000073# then
                  return "sfence.vma";
               elsif D.Imm_I = 0 then
                  return "ecall";
               elsif D.Imm_I = 1 then
                  return "ebreak";
               else
                  return "???";
               end if;
            else
               --  CSR instructions
               declare
                  CSR_Addr : constant CSR.CSR_Address :=
                     CSR.CSR_Address (Shift_Right (Instruction, 20) and
                                     16#FFF#);
                  Csr_N : constant String := CSR.CSR_Name (CSR_Addr);
                  Zimm  : constant String :=
                     Ada.Strings.Fixed.Trim
                       (Natural'Image (Natural (D.Rs1)), Ada.Strings.Left);
               begin
                  case D.Funct3 is
                     when FUNCT3_CSRRW =>
                        if D.Rd = 0 then
                           return "csrw    " & Csr_N & ", " & Rs1;
                        else
                           return "csrrw   " & Rd & ", " & Csr_N & ", " & Rs1;
                        end if;
                     when FUNCT3_CSRRS =>
                        if D.Rs1 = 0 then
                           return "csrr    " & Rd & ", " & Csr_N;
                        elsif D.Rd = 0 then
                           return "csrs    " & Csr_N & ", " & Rs1;
                        else
                           return "csrrs   " & Rd & ", " & Csr_N & ", " & Rs1;
                        end if;
                     when FUNCT3_CSRRC =>
                        if D.Rd = 0 then
                           return "csrc    " & Csr_N & ", " & Rs1;
                        else
                           return "csrrc   " & Rd & ", " & Csr_N & ", " & Rs1;
                        end if;
                     when FUNCT3_CSRRWI =>
                        if D.Rd = 0 then
                           return "csrwi   " & Csr_N & ", " & Zimm;
                        else
                           return "csrrwi  " & Rd & ", " & Csr_N & ", " & Zimm;
                        end if;
                     when FUNCT3_CSRRSI =>
                        return "csrrsi  " & Rd & ", " & Csr_N & ", " & Zimm;
                     when FUNCT3_CSRRCI =>
                        return "csrrci  " & Rd & ", " & Csr_N & ", " & Zimm;
                     when others =>
                        return "csr???";
                  end case;
               end;
            end if;

         when OPCODE_LOAD_FP =>
            --  Both FP loads and vector loads use this opcode
            declare
               Width : constant Word := D.Funct3;
               Nf    : constant Natural :=
                  Natural (Shift_Right (Instruction, 29) and 7);
               Mop   : constant Word :=
                  Shift_Right (Instruction, 26) and 3;
               Lumop : constant Word :=
                  Shift_Right (Instruction, 20) and 16#1F#;
               VM    : constant Boolean :=
                  (Shift_Right (Instruction, 25) and 1) = 1;
               VM_Str : constant String := (if VM then "" else ", v0.t");
               Offset : constant String := Signed_Imm (D.Imm_I);
               Vd_Str : constant String := "v" &
                  Ada.Strings.Fixed.Trim
                    (Natural'Image (Natural (D.Rd)), Ada.Strings.Left);
               Vs2_Str : constant String := "v" &
                  Ada.Strings.Fixed.Trim
                    (Natural'Image (Natural (D.Rs2)), Ada.Strings.Left);
               Nf_Str : constant String :=
                  Ada.Strings.Fixed.Trim
                    (Natural'Image (Nf + 1), Ada.Strings.Left);

               function Width_Str return String is
               begin
                  case Width is
                     when 0 => return "8";
                     when 5 => return "16";
                     when 6 => return "32";
                     when 7 => return "64";
                     when others => return "?";
                  end case;
               end Width_Str;
            begin
               --  FP loads (Width = 2 or 3, Mop = 0, Nf = 0)
               if Mop = 0 and Nf = 0 and (Width = 2 or Width = 3) then
                  if Width = 2 then
                     return "flw     f" &
                        Ada.Strings.Fixed.Trim
                          (Natural'Image (Natural (D.Rd)), Ada.Strings.Left) &
                        ", " & Offset & "(" & Rs1 & ")";
                  else
                     return "fld     f" &
                        Ada.Strings.Fixed.Trim
                          (Natural'Image (Natural (D.Rd)), Ada.Strings.Left) &
                        ", " & Offset & "(" & Rs1 & ")";
                  end if;
               end if;

               --  Whole-register load
               if Mop = 0 and Lumop = VL_LUMOP_WHOLE then
                  return "vl" & Nf_Str & "re" & Width_Str & ".v " &
                     Vd_Str & ", (" & Rs1 & ")";
               end if;

               if Mop = 0 then
                  --  Unit-stride (possibly segment)
                  if Nf = 0 then
                     return "vle" & Width_Str & ".v  " & Vd_Str &
                        ", (" & Rs1 & ")" & VM_Str;
                  else
                     return "vlseg" & Nf_Str & "e" & Width_Str & ".v " &
                        Vd_Str & ", (" & Rs1 & ")" & VM_Str;
                  end if;
               elsif Mop = 2 then
                  --  Strided (possibly segment)
                  if Nf = 0 then
                     return "vlse" & Width_Str & ".v " & Vd_Str &
                        ", (" & Rs1 & "), " & Rs2 & VM_Str;
                  else
                     return "vlsseg" & Nf_Str & "e" & Width_Str & ".v " &
                        Vd_Str & ", (" & Rs1 & "), " & Rs2 & VM_Str;
                  end if;
               elsif Mop = 1 then
                  --  Indexed unordered (possibly segment)
                  if Nf = 0 then
                     return "vluxei" & Width_Str & ".v " & Vd_Str &
                        ", (" & Rs1 & "), " & Vs2_Str & VM_Str;
                  else
                     return "vluxseg" & Nf_Str & "ei" & Width_Str & ".v " &
                        Vd_Str & ", (" & Rs1 & "), " & Vs2_Str & VM_Str;
                  end if;
               elsif Mop = 3 then
                  --  Indexed ordered (possibly segment)
                  if Nf = 0 then
                     return "vloxei" & Width_Str & ".v " & Vd_Str &
                        ", (" & Rs1 & "), " & Vs2_Str & VM_Str;
                  else
                     return "vloxseg" & Nf_Str & "ei" & Width_Str & ".v " &
                        Vd_Str & ", (" & Rs1 & "), " & Vs2_Str & VM_Str;
                  end if;
               else
                  return "vl?     (mop=" &
                     Ada.Strings.Fixed.Trim (Word'Image (Mop), Ada.Strings.Left) &
                     ")";
               end if;
            end;

         when OPCODE_STORE_FP =>
            --  Both FP stores and vector stores use this opcode
            declare
               Width : constant Word := D.Funct3;
               Nf    : constant Natural :=
                  Natural (Shift_Right (Instruction, 29) and 7);
               Mop   : constant Word :=
                  Shift_Right (Instruction, 26) and 3;
               Sumop : constant Word :=
                  Shift_Right (Instruction, 20) and 16#1F#;
               VM    : constant Boolean :=
                  (Shift_Right (Instruction, 25) and 1) = 1;
               VM_Str : constant String := (if VM then "" else ", v0.t");
               Offset : constant String := Signed_Imm (D.Imm_S);
               Vs3_Str : constant String := "v" &
                  Ada.Strings.Fixed.Trim
                    (Natural'Image (Natural (D.Rd)), Ada.Strings.Left);
               Vs2_Str : constant String := "v" &
                  Ada.Strings.Fixed.Trim
                    (Natural'Image (Natural (D.Rs2)), Ada.Strings.Left);
               Nf_Str : constant String :=
                  Ada.Strings.Fixed.Trim
                    (Natural'Image (Nf + 1), Ada.Strings.Left);

               function Width_Str return String is
               begin
                  case Width is
                     when 0 => return "8";
                     when 5 => return "16";
                     when 6 => return "32";
                     when 7 => return "64";
                     when others => return "?";
                  end case;
               end Width_Str;
            begin
               --  FP stores (Width = 2 or 3, Mop = 0, Nf = 0)
               if Mop = 0 and Nf = 0 and (Width = 2 or Width = 3) then
                  if Width = 2 then
                     return "fsw     f" &
                        Ada.Strings.Fixed.Trim
                          (Natural'Image (Natural (D.Rs2)), Ada.Strings.Left) &
                        ", " & Offset & "(" & Rs1 & ")";
                  else
                     return "fsd     f" &
                        Ada.Strings.Fixed.Trim
                          (Natural'Image (Natural (D.Rs2)), Ada.Strings.Left) &
                        ", " & Offset & "(" & Rs1 & ")";
                  end if;
               end if;

               --  Whole-register store
               if Mop = 0 and Sumop = VL_SUMOP_WHOLE then
                  return "vs" & Nf_Str & "r.v " &
                     Vs3_Str & ", (" & Rs1 & ")";
               end if;

               if Mop = 0 then
                  --  Unit-stride (possibly segment)
                  if Nf = 0 then
                     return "vse" & Width_Str & ".v  " & Vs3_Str &
                        ", (" & Rs1 & ")" & VM_Str;
                  else
                     return "vsseg" & Nf_Str & "e" & Width_Str & ".v " &
                        Vs3_Str & ", (" & Rs1 & ")" & VM_Str;
                  end if;
               elsif Mop = 2 then
                  --  Strided (possibly segment)
                  if Nf = 0 then
                     return "vsse" & Width_Str & ".v " & Vs3_Str &
                        ", (" & Rs1 & "), " & Rs2 & VM_Str;
                  else
                     return "vssseg" & Nf_Str & "e" & Width_Str & ".v " &
                        Vs3_Str & ", (" & Rs1 & "), " & Rs2 & VM_Str;
                  end if;
               elsif Mop = 1 then
                  --  Indexed unordered (possibly segment)
                  if Nf = 0 then
                     return "vsuxei" & Width_Str & ".v " & Vs3_Str &
                        ", (" & Rs1 & "), " & Vs2_Str & VM_Str;
                  else
                     return "vsuxseg" & Nf_Str & "ei" & Width_Str & ".v " &
                        Vs3_Str & ", (" & Rs1 & "), " & Vs2_Str & VM_Str;
                  end if;
               elsif Mop = 3 then
                  --  Indexed ordered (possibly segment)
                  if Nf = 0 then
                     return "vsoxei" & Width_Str & ".v " & Vs3_Str &
                        ", (" & Rs1 & "), " & Vs2_Str & VM_Str;
                  else
                     return "vsoxseg" & Nf_Str & "ei" & Width_Str & ".v " &
                        Vs3_Str & ", (" & Rs1 & "), " & Vs2_Str & VM_Str;
                  end if;
               else
                  return "vs?     (mop=" &
                     Ada.Strings.Fixed.Trim (Word'Image (Mop), Ada.Strings.Left) &
                     ")";
               end if;
            end;

         when OPCODE_VECTOR =>
            --  Vector arithmetic and configuration instructions
            declare
               Funct3  : constant Word := D.Funct3;
               Funct6  : constant Word := Shift_Right (Instruction, 26) and 63;
               VM      : constant Boolean :=
                  (Shift_Right (Instruction, 25) and 1) = 1;
               VM_Str  : constant String := (if VM then "" else ", v0.t");
               Vd_Str  : constant String := "v" &
                  Ada.Strings.Fixed.Trim
                    (Natural'Image (Natural (D.Rd)), Ada.Strings.Left);
               Vs1_Str : constant String := "v" &
                  Ada.Strings.Fixed.Trim
                    (Natural'Image (Natural (D.Rs1)), Ada.Strings.Left);
               Vs2_Str : constant String := "v" &
                  Ada.Strings.Fixed.Trim
                    (Natural'Image (Natural (D.Rs2)), Ada.Strings.Left);
               Fs1_Str : constant String := "f" &
                  Ada.Strings.Fixed.Trim
                    (Natural'Image (Natural (D.Rs1)), Ada.Strings.Left);
               Imm5    : constant Word := To_Word (D.Imm_I) and 16#1F#;
               Simm5   : constant Signed_Word :=
                  (if (Imm5 and 16#10#) /= 0 then
                     To_Signed (Imm5 or 16#FFFFFFE0#) else To_Signed (Imm5));
            begin
               --  OPCFG: vsetvli, vsetivli, vsetvl
               if Funct3 = 7 then
                  declare
                     Bit31 : constant Boolean :=
                        (Shift_Right (Instruction, 31) and 1) = 1;
                     Bit30 : constant Boolean :=
                        (Shift_Right (Instruction, 30) and 1) = 1;
                     VSEW  : constant Natural :=
                        Natural (Shift_Right (Instruction, 23) and 7);
                     SEW   : constant Natural := 8 * 2 ** VSEW;
                  begin
                     if not Bit31 then
                        --  vsetvli rd, rs1, vtypei
                        return "vsetvli " & Rd & ", " & Rs1 & ", e" &
                           Ada.Strings.Fixed.Trim
                             (Natural'Image (SEW), Ada.Strings.Left);
                     elsif Bit30 then
                        --  vsetivli rd, uimm, vtypei (immediate form)
                        declare
                           Uimm : constant Natural :=
                              Natural (Shift_Right (Instruction, 15) and 31);
                        begin
                           return "vsetivli " & Rd & ", " &
                              Ada.Strings.Fixed.Trim
                                (Natural'Image (Uimm), Ada.Strings.Left) &
                              ", e" &
                              Ada.Strings.Fixed.Trim
                                (Natural'Image (SEW), Ada.Strings.Left);
                        end;
                     else
                        --  vsetvl rd, rs1, rs2
                        return "vsetvl  " & Rd & ", " & Rs1 & ", " & Rs2;
                     end if;
                  end;
               end if;

               --  OPIVV (funct3=0): vector-vector integer
               if Funct3 = 0 then
                  case Funct6 is
                     when VFUNCT6_VADD =>
                        return "vadd.vv " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VSUB =>
                        return "vsub.vv " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VAND =>
                        return "vand.vv " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VOR =>
                        return "vor.vv  " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VXOR =>
                        return "vxor.vv " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VMINU =>
                        return "vminu.vv " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VMIN =>
                        return "vmin.vv " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VMAXU =>
                        return "vmaxu.vv " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VMAX =>
                        return "vmax.vv " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VMSEQ =>
                        return "vmseq.vv " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VMSNE =>
                        return "vmsne.vv " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VMSLTU =>
                        return "vmsltu.vv " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VMSLT =>
                        return "vmslt.vv " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VRGATHER =>
                        return "vrgather.vv " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VSLIDEUP =>
                        --  In OPIVV context, funct6=001110 is vrgatherei16
                        return "vrgatherei16.vv " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VMSLEU =>
                        return "vmsleu.vv " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VMSLE =>
                        return "vmsle.vv " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VSLL =>
                        return "vsll.vv " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VSRL =>
                        return "vsrl.vv " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VSRA =>
                        return "vsra.vv " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VNSRL =>
                        return "vnsrl.wv " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VNSRA =>
                        return "vnsra.wv " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VWADDU =>
                        return "vwaddu.vv " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VWADD =>
                        return "vwadd.vv " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VWSUBU =>
                        return "vwsubu.vv " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VWSUB =>
                        return "vwsub.vv " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VWADDUW =>
                        return "vwaddu.wv " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VWADDW =>
                        return "vwadd.wv " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VWSUBUW =>
                        return "vwsubu.wv " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VWSUBW =>
                        return "vwsub.wv " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VADC =>
                        return "vadc.vvm " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str;
                     when VFUNCT6_VMADC =>
                        return "vmadc.vvm " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VSBC =>
                        return "vsbc.vvm " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str;
                     when VFUNCT6_VMSBC =>
                        return "vmsbc.vvm " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VMERGE =>
                        return "vmerge.vvm " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str;
                     when VFUNCT6_VSADDU =>
                        return "vsaddu.vv " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VSADD =>
                        return "vsadd.vv " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VSSUBU =>
                        return "vssubu.vv " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VSSUB =>
                        return "vssub.vv " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VSMUL =>
                        return "vsmul.vv " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VSSRL =>
                        return "vssrl.vv " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VSSRA =>
                        return "vssra.vv " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VNCLIPU =>
                        return "vnclipu.wv " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VNCLIP =>
                        return "vnclip.wv " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when others =>
                        return "v?.vv   (f6=" &
                           Ada.Strings.Fixed.Trim
                             (Word'Image (Funct6), Ada.Strings.Left) & ")";
                  end case;
               end if;

               --  OPMVV (funct3=2): vector-vector with mask/reduction
               if Funct3 = 2 then
                  case Funct6 is
                     when VFUNCT6_VREDSUM =>
                        return "vredsum.vs " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VREDAND =>
                        return "vredand.vs " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VREDOR =>
                        return "vredor.vs " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VREDXOR =>
                        return "vredxor.vs " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VREDMINU =>
                        return "vredminu.vs " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VREDMIN =>
                        return "vredmin.vs " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VREDMAXU =>
                        return "vredmaxu.vs " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VREDMAX =>
                        return "vredmax.vs " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VID =>
                        --  vid.v, viota.m, vmsbf.m, etc based on vs1
                        if Natural (D.Rs1) = 17 then
                           return "vid.v   " & Vd_Str & VM_Str;
                        elsif Natural (D.Rs1) = 16 then
                           return "viota.m " & Vd_Str & ", " & Vs2_Str & VM_Str;
                        else
                           return "vm?.m   " & Vd_Str & ", " & Vs2_Str;
                        end if;
                     when VFUNCT6_VMUL =>
                        return "vmul.vv " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VMULH =>
                        return "vmulh.vv " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VMULHU =>
                        return "vmulhu.vv " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VDIVU =>
                        return "vdivu.vv " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VDIV =>
                        return "vdiv.vv " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VREMU =>
                        return "vremu.vv " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VREM =>
                        return "vrem.vv " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VMACC =>
                        return "vmacc.vv " & Vd_Str & ", " &
                           Vs1_Str & ", " & Vs2_Str & VM_Str;
                     when VFUNCT6_VNMSAC =>
                        return "vnmsac.vv " & Vd_Str & ", " &
                           Vs1_Str & ", " & Vs2_Str & VM_Str;
                     when VFUNCT6_VMADD =>
                        return "vmadd.vv " & Vd_Str & ", " &
                           Vs1_Str & ", " & Vs2_Str & VM_Str;
                     when VFUNCT6_VNMSUB =>
                        return "vnmsub.vv " & Vd_Str & ", " &
                           Vs1_Str & ", " & Vs2_Str & VM_Str;
                     when VFUNCT6_VMULHSU =>
                        return "vmulhsu.vv " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VWMULU =>
                        return "vwmulu.vv " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VWMUL =>
                        return "vwmul.vv " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VWMULSU =>
                        return "vwmulsu.vv " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VWMACCU =>
                        return "vwmaccu.vv " & Vd_Str & ", " &
                           Vs1_Str & ", " & Vs2_Str & VM_Str;
                     when VFUNCT6_VWMACC =>
                        return "vwmacc.vv " & Vd_Str & ", " &
                           Vs1_Str & ", " & Vs2_Str & VM_Str;
                     when VFUNCT6_VWMACCSU =>
                        return "vwmaccsu.vv " & Vd_Str & ", " &
                           Vs1_Str & ", " & Vs2_Str & VM_Str;
                     when VFUNCT6_VAADDU =>
                        return "vaaddu.vv " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VAADD =>
                        return "vaadd.vv " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VASUBU =>
                        return "vasubu.vv " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VASUB =>
                        return "vasub.vv " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VCOMPRESS =>
                        return "vcompress.vm " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str;
                     when VFUNCT6_VZEXT =>
                        case D.Rs1 is
                           when 2 => return "vzext.vf4 " & Vd_Str &
                              ", " & Vs2_Str & VM_Str;
                           when 3 => return "vsext.vf4 " & Vd_Str &
                              ", " & Vs2_Str & VM_Str;
                           when 4 => return "vzext.vf2 " & Vd_Str &
                              ", " & Vs2_Str & VM_Str;
                           when 5 => return "vsext.vf2 " & Vd_Str &
                              ", " & Vs2_Str & VM_Str;
                           when 6 => return "vzext.vf8 " & Vd_Str &
                              ", " & Vs2_Str & VM_Str;
                           when 7 => return "vsext.vf8 " & Vd_Str &
                              ", " & Vs2_Str & VM_Str;
                           when others =>
                              return "v?ext " & Vd_Str & ", " & Vs2_Str;
                        end case;
                     when others =>
                        return "v?.vv   (opmvv f6=" &
                           Ada.Strings.Fixed.Trim
                             (Word'Image (Funct6), Ada.Strings.Left) & ")";
                  end case;
               end if;

               --  OPIVI (funct3=3): vector-immediate
               if Funct3 = 3 then
                  case Funct6 is
                     when VFUNCT6_VADD =>
                        return "vadd.vi " & Vd_Str & ", " & Vs2_Str & ", " &
                           Ada.Strings.Fixed.Trim
                             (Signed_Word'Image (Simm5), Ada.Strings.Left) &
                           VM_Str;
                     when VFUNCT6_VRSUB =>
                        return "vrsub.vi " & Vd_Str & ", " & Vs2_Str & ", " &
                           Ada.Strings.Fixed.Trim
                             (Signed_Word'Image (Simm5), Ada.Strings.Left) &
                           VM_Str;
                     when VFUNCT6_VAND =>
                        return "vand.vi " & Vd_Str & ", " & Vs2_Str & ", " &
                           Ada.Strings.Fixed.Trim
                             (Signed_Word'Image (Simm5), Ada.Strings.Left) &
                           VM_Str;
                     when VFUNCT6_VOR =>
                        return "vor.vi  " & Vd_Str & ", " & Vs2_Str & ", " &
                           Ada.Strings.Fixed.Trim
                             (Signed_Word'Image (Simm5), Ada.Strings.Left) &
                           VM_Str;
                     when VFUNCT6_VXOR =>
                        return "vxor.vi " & Vd_Str & ", " & Vs2_Str & ", " &
                           Ada.Strings.Fixed.Trim
                             (Signed_Word'Image (Simm5), Ada.Strings.Left) &
                           VM_Str;
                     when VFUNCT6_VMV =>
                        --  vmv.v.i when vm=1
                        return "vmv.v.i " & Vd_Str & ", " &
                           Ada.Strings.Fixed.Trim
                             (Signed_Word'Image (Simm5), Ada.Strings.Left);
                     when VFUNCT6_VRGATHER =>
                        return "vrgather.vi " & Vd_Str & ", " & Vs2_Str &
                           ", " & Ada.Strings.Fixed.Trim
                             (Word'Image (Imm5), Ada.Strings.Left) & VM_Str;
                     when VFUNCT6_VSLIDEUP =>
                        return "vslideup.vi " & Vd_Str & ", " & Vs2_Str &
                           ", " & Ada.Strings.Fixed.Trim
                             (Word'Image (Imm5), Ada.Strings.Left) & VM_Str;
                     when VFUNCT6_VSLIDEDN =>
                        return "vslidedown.vi " & Vd_Str & ", " & Vs2_Str &
                           ", " & Ada.Strings.Fixed.Trim
                             (Word'Image (Imm5), Ada.Strings.Left) & VM_Str;
                     when VFUNCT6_VMSLEU =>
                        return "vmsleu.vi " & Vd_Str & ", " & Vs2_Str &
                           ", " & Ada.Strings.Fixed.Trim
                             (Signed_Word'Image (Simm5), Ada.Strings.Left) &
                           VM_Str;
                     when VFUNCT6_VMSLE =>
                        return "vmsle.vi " & Vd_Str & ", " & Vs2_Str &
                           ", " & Ada.Strings.Fixed.Trim
                             (Signed_Word'Image (Simm5), Ada.Strings.Left) &
                           VM_Str;
                     when VFUNCT6_VMSGTU =>
                        return "vmsgtu.vi " & Vd_Str & ", " & Vs2_Str &
                           ", " & Ada.Strings.Fixed.Trim
                             (Signed_Word'Image (Simm5), Ada.Strings.Left) &
                           VM_Str;
                     when VFUNCT6_VMSGT =>
                        return "vmsgt.vi " & Vd_Str & ", " & Vs2_Str &
                           ", " & Ada.Strings.Fixed.Trim
                             (Signed_Word'Image (Simm5), Ada.Strings.Left) &
                           VM_Str;
                     when VFUNCT6_VSLL =>
                        return "vsll.vi " & Vd_Str & ", " & Vs2_Str &
                           ", " & Ada.Strings.Fixed.Trim
                             (Word'Image (Imm5), Ada.Strings.Left) & VM_Str;
                     when VFUNCT6_VSRL =>
                        return "vsrl.vi " & Vd_Str & ", " & Vs2_Str &
                           ", " & Ada.Strings.Fixed.Trim
                             (Word'Image (Imm5), Ada.Strings.Left) & VM_Str;
                     when VFUNCT6_VSRA =>
                        return "vsra.vi " & Vd_Str & ", " & Vs2_Str &
                           ", " & Ada.Strings.Fixed.Trim
                             (Word'Image (Imm5), Ada.Strings.Left) & VM_Str;
                     when VFUNCT6_VNSRL =>
                        return "vnsrl.wi " & Vd_Str & ", " & Vs2_Str &
                           ", " & Ada.Strings.Fixed.Trim
                             (Word'Image (Imm5), Ada.Strings.Left) & VM_Str;
                     when VFUNCT6_VNSRA =>
                        return "vnsra.wi " & Vd_Str & ", " & Vs2_Str &
                           ", " & Ada.Strings.Fixed.Trim
                             (Word'Image (Imm5), Ada.Strings.Left) & VM_Str;
                     when VFUNCT6_VADC =>
                        return "vadc.vim " & Vd_Str & ", " & Vs2_Str &
                           ", " & Ada.Strings.Fixed.Trim
                             (Signed_Word'Image (Simm5), Ada.Strings.Left);
                     when VFUNCT6_VMADC =>
                        return "vmadc.vim " & Vd_Str & ", " & Vs2_Str &
                           ", " & Ada.Strings.Fixed.Trim
                             (Signed_Word'Image (Simm5), Ada.Strings.Left) &
                           VM_Str;
                     when VFUNCT6_VSADDU =>
                        return "vsaddu.vi " & Vd_Str & ", " & Vs2_Str &
                           ", " & Ada.Strings.Fixed.Trim
                             (Signed_Word'Image (Simm5), Ada.Strings.Left) &
                           VM_Str;
                     when VFUNCT6_VSADD =>
                        return "vsadd.vi " & Vd_Str & ", " & Vs2_Str &
                           ", " & Ada.Strings.Fixed.Trim
                             (Signed_Word'Image (Simm5), Ada.Strings.Left) &
                           VM_Str;
                     when VFUNCT6_VSSRL =>
                        return "vssrl.vi " & Vd_Str & ", " & Vs2_Str &
                           ", " & Ada.Strings.Fixed.Trim
                             (Word'Image (Imm5), Ada.Strings.Left) & VM_Str;
                     when VFUNCT6_VSSRA =>
                        return "vssra.vi " & Vd_Str & ", " & Vs2_Str &
                           ", " & Ada.Strings.Fixed.Trim
                             (Word'Image (Imm5), Ada.Strings.Left) & VM_Str;
                     when VFUNCT6_VNCLIPU =>
                        return "vnclipu.wi " & Vd_Str & ", " & Vs2_Str &
                           ", " & Ada.Strings.Fixed.Trim
                             (Word'Image (Imm5), Ada.Strings.Left) & VM_Str;
                     when VFUNCT6_VNCLIP =>
                        return "vnclip.wi " & Vd_Str & ", " & Vs2_Str &
                           ", " & Ada.Strings.Fixed.Trim
                             (Word'Image (Imm5), Ada.Strings.Left) & VM_Str;
                     when others =>
                        return "v?.vi   (f6=" &
                           Ada.Strings.Fixed.Trim
                             (Word'Image (Funct6), Ada.Strings.Left) & ")";
                  end case;
               end if;

               --  OPIVX (funct3=4): vector-scalar
               if Funct3 = 4 then
                  case Funct6 is
                     when VFUNCT6_VADD =>
                        return "vadd.vx " & Vd_Str & ", " & Vs2_Str &
                           ", " & Rs1 & VM_Str;
                     when VFUNCT6_VSUB =>
                        return "vsub.vx " & Vd_Str & ", " & Vs2_Str &
                           ", " & Rs1 & VM_Str;
                     when VFUNCT6_VRSUB =>
                        return "vrsub.vx " & Vd_Str & ", " & Vs2_Str &
                           ", " & Rs1 & VM_Str;
                     when VFUNCT6_VAND =>
                        return "vand.vx " & Vd_Str & ", " & Vs2_Str &
                           ", " & Rs1 & VM_Str;
                     when VFUNCT6_VOR =>
                        return "vor.vx  " & Vd_Str & ", " & Vs2_Str &
                           ", " & Rs1 & VM_Str;
                     when VFUNCT6_VXOR =>
                        return "vxor.vx " & Vd_Str & ", " & Vs2_Str &
                           ", " & Rs1 & VM_Str;
                     when VFUNCT6_VRGATHER =>
                        return "vrgather.vx " & Vd_Str & ", " & Vs2_Str &
                           ", " & Rs1 & VM_Str;
                     when VFUNCT6_VSLIDEUP =>
                        return "vslideup.vx " & Vd_Str & ", " & Vs2_Str &
                           ", " & Rs1 & VM_Str;
                     when VFUNCT6_VSLIDEDN =>
                        return "vslidedown.vx " & Vd_Str & ", " & Vs2_Str &
                           ", " & Rs1 & VM_Str;
                     when VFUNCT6_VMSLEU =>
                        return "vmsleu.vx " & Vd_Str & ", " & Vs2_Str &
                           ", " & Rs1 & VM_Str;
                     when VFUNCT6_VMSLE =>
                        return "vmsle.vx " & Vd_Str & ", " & Vs2_Str &
                           ", " & Rs1 & VM_Str;
                     when VFUNCT6_VMSGTU =>
                        return "vmsgtu.vx " & Vd_Str & ", " & Vs2_Str &
                           ", " & Rs1 & VM_Str;
                     when VFUNCT6_VMSGT =>
                        return "vmsgt.vx " & Vd_Str & ", " & Vs2_Str &
                           ", " & Rs1 & VM_Str;
                     when VFUNCT6_VSLL =>
                        return "vsll.vx " & Vd_Str & ", " & Vs2_Str &
                           ", " & Rs1 & VM_Str;
                     when VFUNCT6_VSRL =>
                        return "vsrl.vx " & Vd_Str & ", " & Vs2_Str &
                           ", " & Rs1 & VM_Str;
                     when VFUNCT6_VSRA =>
                        return "vsra.vx " & Vd_Str & ", " & Vs2_Str &
                           ", " & Rs1 & VM_Str;
                     when VFUNCT6_VNSRL =>
                        return "vnsrl.wx " & Vd_Str & ", " & Vs2_Str &
                           ", " & Rs1 & VM_Str;
                     when VFUNCT6_VNSRA =>
                        return "vnsra.wx " & Vd_Str & ", " & Vs2_Str &
                           ", " & Rs1 & VM_Str;
                     when VFUNCT6_VMERGE =>
                        return "vmerge.vxm " & Vd_Str & ", " & Vs2_Str &
                           ", " & Rs1;
                     when VFUNCT6_VWADDU =>
                        return "vwaddu.vx " & Vd_Str & ", " & Vs2_Str &
                           ", " & Rs1 & VM_Str;
                     when VFUNCT6_VWADD =>
                        return "vwadd.vx " & Vd_Str & ", " & Vs2_Str &
                           ", " & Rs1 & VM_Str;
                     when VFUNCT6_VWSUBU =>
                        return "vwsubu.vx " & Vd_Str & ", " & Vs2_Str &
                           ", " & Rs1 & VM_Str;
                     when VFUNCT6_VWSUB =>
                        return "vwsub.vx " & Vd_Str & ", " & Vs2_Str &
                           ", " & Rs1 & VM_Str;
                     when VFUNCT6_VWADDUW =>
                        return "vwaddu.wx " & Vd_Str & ", " & Vs2_Str &
                           ", " & Rs1 & VM_Str;
                     when VFUNCT6_VWADDW =>
                        return "vwadd.wx " & Vd_Str & ", " & Vs2_Str &
                           ", " & Rs1 & VM_Str;
                     when VFUNCT6_VWSUBUW =>
                        return "vwsubu.wx " & Vd_Str & ", " & Vs2_Str &
                           ", " & Rs1 & VM_Str;
                     when VFUNCT6_VWSUBW =>
                        return "vwsub.wx " & Vd_Str & ", " & Vs2_Str &
                           ", " & Rs1 & VM_Str;
                     when VFUNCT6_VADC =>
                        return "vadc.vxm " & Vd_Str & ", " & Vs2_Str &
                           ", " & Rs1;
                     when VFUNCT6_VMADC =>
                        return "vmadc.vxm " & Vd_Str & ", " & Vs2_Str &
                           ", " & Rs1 & VM_Str;
                     when VFUNCT6_VSBC =>
                        return "vsbc.vxm " & Vd_Str & ", " & Vs2_Str &
                           ", " & Rs1;
                     when VFUNCT6_VMSBC =>
                        return "vmsbc.vxm " & Vd_Str & ", " & Vs2_Str &
                           ", " & Rs1 & VM_Str;
                     when VFUNCT6_VSADDU =>
                        return "vsaddu.vx " & Vd_Str & ", " & Vs2_Str &
                           ", " & Rs1 & VM_Str;
                     when VFUNCT6_VSADD =>
                        return "vsadd.vx " & Vd_Str & ", " & Vs2_Str &
                           ", " & Rs1 & VM_Str;
                     when VFUNCT6_VSSUBU =>
                        return "vssubu.vx " & Vd_Str & ", " & Vs2_Str &
                           ", " & Rs1 & VM_Str;
                     when VFUNCT6_VSSUB =>
                        return "vssub.vx " & Vd_Str & ", " & Vs2_Str &
                           ", " & Rs1 & VM_Str;
                     when VFUNCT6_VSMUL =>
                        return "vsmul.vx " & Vd_Str & ", " & Vs2_Str &
                           ", " & Rs1 & VM_Str;
                     when VFUNCT6_VSSRL =>
                        return "vssrl.vx " & Vd_Str & ", " & Vs2_Str &
                           ", " & Rs1 & VM_Str;
                     when VFUNCT6_VSSRA =>
                        return "vssra.vx " & Vd_Str & ", " & Vs2_Str &
                           ", " & Rs1 & VM_Str;
                     when VFUNCT6_VNCLIPU =>
                        return "vnclipu.wx " & Vd_Str & ", " & Vs2_Str &
                           ", " & Rs1 & VM_Str;
                     when VFUNCT6_VNCLIP =>
                        return "vnclip.wx " & Vd_Str & ", " & Vs2_Str &
                           ", " & Rs1 & VM_Str;
                     when others =>
                        return "v?.vx   (f6=" &
                           Ada.Strings.Fixed.Trim
                             (Word'Image (Funct6), Ada.Strings.Left) & ")";
                  end case;
               end if;

               --  OPMVX (funct3=6): vector-scalar multiply/div
               if Funct3 = 6 then
                  case Funct6 is
                     when VFUNCT6_VMUL =>
                        return "vmul.vx " & Vd_Str & ", " & Vs2_Str &
                           ", " & Rs1 & VM_Str;
                     when VFUNCT6_VMULH =>
                        return "vmulh.vx " & Vd_Str & ", " & Vs2_Str &
                           ", " & Rs1 & VM_Str;
                     when VFUNCT6_VDIVU =>
                        return "vdivu.vx " & Vd_Str & ", " & Vs2_Str &
                           ", " & Rs1 & VM_Str;
                     when VFUNCT6_VDIV =>
                        return "vdiv.vx " & Vd_Str & ", " & Vs2_Str &
                           ", " & Rs1 & VM_Str;
                     when VFUNCT6_VREMU =>
                        return "vremu.vx " & Vd_Str & ", " & Vs2_Str &
                           ", " & Rs1 & VM_Str;
                     when VFUNCT6_VREM =>
                        return "vrem.vx " & Vd_Str & ", " & Vs2_Str &
                           ", " & Rs1 & VM_Str;
                     when VFUNCT6_VMV_S_X =>
                        --  vmv.s.x vd, rs1 (vs2=0)
                        if D.Rs2 = 0 then
                           return "vmv.s.x " & Vd_Str & ", " & Rs1;
                        else
                           return "v?.vx   (f6=16)";
                        end if;
                     when VFUNCT6_VMACC =>
                        return "vmacc.vx " & Vd_Str & ", " & Rs1 &
                           ", " & Vs2_Str & VM_Str;
                     when VFUNCT6_VNMSAC =>
                        return "vnmsac.vx " & Vd_Str & ", " & Rs1 &
                           ", " & Vs2_Str & VM_Str;
                     when VFUNCT6_VMADD =>
                        return "vmadd.vx " & Vd_Str & ", " & Rs1 &
                           ", " & Vs2_Str & VM_Str;
                     when VFUNCT6_VNMSUB =>
                        return "vnmsub.vx " & Vd_Str & ", " & Rs1 &
                           ", " & Vs2_Str & VM_Str;
                     when VFUNCT6_VSLIDE1UP =>
                        return "vslide1up.vx " & Vd_Str & ", " & Vs2_Str &
                           ", " & Rs1 & VM_Str;
                     when VFUNCT6_VSLIDE1DN =>
                        return "vslide1down.vx " & Vd_Str & ", " & Vs2_Str &
                           ", " & Rs1 & VM_Str;
                     when VFUNCT6_VMULHSU =>
                        return "vmulhsu.vx " & Vd_Str & ", " & Vs2_Str &
                           ", " & Rs1 & VM_Str;
                     when VFUNCT6_VWMACCU =>
                        return "vwmaccu.vx " & Vd_Str & ", " & Rs1 &
                           ", " & Vs2_Str & VM_Str;
                     when VFUNCT6_VWMACC =>
                        return "vwmacc.vx " & Vd_Str & ", " & Rs1 &
                           ", " & Vs2_Str & VM_Str;
                     when VFUNCT6_VWMACCSU =>
                        return "vwmaccsu.vx " & Vd_Str & ", " & Rs1 &
                           ", " & Vs2_Str & VM_Str;
                     when VFUNCT6_VWMACCUS =>
                        return "vwmaccus.vx " & Vd_Str & ", " & Rs1 &
                           ", " & Vs2_Str & VM_Str;
                     when VFUNCT6_VAADDU =>
                        return "vaaddu.vx " & Vd_Str & ", " & Vs2_Str &
                           ", " & Rs1 & VM_Str;
                     when VFUNCT6_VAADD =>
                        return "vaadd.vx " & Vd_Str & ", " & Vs2_Str &
                           ", " & Rs1 & VM_Str;
                     when VFUNCT6_VASUBU =>
                        return "vasubu.vx " & Vd_Str & ", " & Vs2_Str &
                           ", " & Rs1 & VM_Str;
                     when VFUNCT6_VASUB =>
                        return "vasub.vx " & Vd_Str & ", " & Vs2_Str &
                           ", " & Rs1 & VM_Str;
                     when others =>
                        return "v?.vx   (f6=" &
                           Ada.Strings.Fixed.Trim
                             (Word'Image (Funct6), Ada.Strings.Left) & ")";
                  end case;
               end if;

               --  OPFVV (funct3=1): FP vector-vector
               if Funct3 = 1 then
                  case Funct6 is
                     when VFUNCT6_VFADD =>
                        return "vfadd.vv " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VFSUB =>
                        return "vfsub.vv " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VFMUL =>
                        return "vfmul.vv " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VFDIV =>
                        return "vfdiv.vv " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VFMIN =>
                        return "vfmin.vv " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VFMAX =>
                        return "vfmax.vv " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VFSGNJ =>
                        return "vfsgnj.vv " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VFSGNJN =>
                        return "vfsgnjn.vv " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VFSGNJX =>
                        return "vfsgnjx.vv " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VMFEQ =>
                        return "vmfeq.vv " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VMFLE =>
                        return "vmfle.vv " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VMFLT =>
                        return "vmflt.vv " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VMFNE =>
                        return "vmfne.vv " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VFMACC =>
                        return "vfmacc.vv " & Vd_Str & ", " &
                           Vs1_Str & ", " & Vs2_Str & VM_Str;
                     when VFUNCT6_VFNMACC =>
                        return "vfnmacc.vv " & Vd_Str & ", " &
                           Vs1_Str & ", " & Vs2_Str & VM_Str;
                     when VFUNCT6_VFMSAC =>
                        return "vfmsac.vv " & Vd_Str & ", " &
                           Vs1_Str & ", " & Vs2_Str & VM_Str;
                     when VFUNCT6_VFNMSAC =>
                        return "vfnmsac.vv " & Vd_Str & ", " &
                           Vs1_Str & ", " & Vs2_Str & VM_Str;
                     when VFUNCT6_VFREDOSUM =>
                        return "vfredosum.vs " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VFREDUSUM =>
                        return "vfredusum.vs " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VFREDMIN =>
                        return "vfredmin.vs " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VFREDMAX =>
                        return "vfredmax.vs " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VFWADD =>
                        return "vfwadd.vv " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VFWSUB =>
                        return "vfwsub.vv " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VFWADDW =>
                        return "vfwadd.wv " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VFWSUBW =>
                        return "vfwsub.wv " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VFWMUL =>
                        return "vfwmul.vv " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VFWMACC =>
                        return "vfwmacc.vv " & Vd_Str & ", " &
                           Vs1_Str & ", " & Vs2_Str & VM_Str;
                     when VFUNCT6_VFWNMACC =>
                        return "vfwnmacc.vv " & Vd_Str & ", " &
                           Vs1_Str & ", " & Vs2_Str & VM_Str;
                     when VFUNCT6_VFWMSAC =>
                        return "vfwmsac.vv " & Vd_Str & ", " &
                           Vs1_Str & ", " & Vs2_Str & VM_Str;
                     when VFUNCT6_VFWNMSAC =>
                        return "vfwnmsac.vv " & Vd_Str & ", " &
                           Vs1_Str & ", " & Vs2_Str & VM_Str;
                     when VFUNCT6_VFWREDOSUM =>
                        return "vfwredosum.vs " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VFWREDUSUM =>
                        return "vfwredusum.vs " & Vd_Str & ", " &
                           Vs2_Str & ", " & Vs1_Str & VM_Str;
                     when VFUNCT6_VFSQRT =>
                        case D.Rs1 is
                           when 0 => return "vfsqrt.v " & Vd_Str &
                              ", " & Vs2_Str & VM_Str;
                           when 4 => return "vfrsqrt7.v " & Vd_Str &
                              ", " & Vs2_Str & VM_Str;
                           when 5 => return "vfrec7.v " & Vd_Str &
                              ", " & Vs2_Str & VM_Str;
                           when 16 => return "vfclass.v " & Vd_Str &
                              ", " & Vs2_Str & VM_Str;
                           when others =>
                              return "vf?.v (vs1=" &
                                 Ada.Strings.Fixed.Trim
                                   (Register_Index'Image (D.Rs1),
                                    Ada.Strings.Left) & ")";
                        end case;
                     when VFUNCT6_VFUNARY =>
                        return "vfcvt?.v " & Vd_Str & ", " &
                           Vs2_Str & VM_Str;
                     when others =>
                        return "vf?.vv  (f6=" &
                           Ada.Strings.Fixed.Trim
                             (Word'Image (Funct6), Ada.Strings.Left) & ")";
                  end case;
               end if;

               --  OPFVF (funct3=5): FP vector-scalar
               if Funct3 = 5 then
                  case Funct6 is
                     when VFUNCT6_VFADD =>
                        return "vfadd.vf " & Vd_Str & ", " & Vs2_Str &
                           ", " & Fs1_Str & VM_Str;
                     when VFUNCT6_VFSUB =>
                        return "vfsub.vf " & Vd_Str & ", " & Vs2_Str &
                           ", " & Fs1_Str & VM_Str;
                     when VFUNCT6_VFMUL =>
                        return "vfmul.vf " & Vd_Str & ", " & Vs2_Str &
                           ", " & Fs1_Str & VM_Str;
                     when VFUNCT6_VFDIV =>
                        return "vfdiv.vf " & Vd_Str & ", " & Vs2_Str &
                           ", " & Fs1_Str & VM_Str;
                     when VFUNCT6_VFRDIV =>
                        return "vfrdiv.vf " & Vd_Str & ", " & Vs2_Str &
                           ", " & Fs1_Str & VM_Str;
                     when VFUNCT6_VFMIN =>
                        return "vfmin.vf " & Vd_Str & ", " & Vs2_Str &
                           ", " & Fs1_Str & VM_Str;
                     when VFUNCT6_VFMAX =>
                        return "vfmax.vf " & Vd_Str & ", " & Vs2_Str &
                           ", " & Fs1_Str & VM_Str;
                     when VFUNCT6_VFSGNJ =>
                        return "vfsgnj.vf " & Vd_Str & ", " & Vs2_Str &
                           ", " & Fs1_Str & VM_Str;
                     when VFUNCT6_VFSGNJN =>
                        return "vfsgnjn.vf " & Vd_Str & ", " & Vs2_Str &
                           ", " & Fs1_Str & VM_Str;
                     when VFUNCT6_VFSGNJX =>
                        return "vfsgnjx.vf " & Vd_Str & ", " & Vs2_Str &
                           ", " & Fs1_Str & VM_Str;
                     when VFUNCT6_VFRSUB =>
                        return "vfrsub.vf " & Vd_Str & ", " & Vs2_Str &
                           ", " & Fs1_Str & VM_Str;
                     when VFUNCT6_VFMERGE =>
                        return "vfmerge.vf " & Vd_Str & ", " & Vs2_Str &
                           ", " & Fs1_Str;
                     when VFUNCT6_VMFEQ =>
                        return "vmfeq.vf " & Vd_Str & ", " & Vs2_Str &
                           ", " & Fs1_Str & VM_Str;
                     when VFUNCT6_VMFLE =>
                        return "vmfle.vf " & Vd_Str & ", " & Vs2_Str &
                           ", " & Fs1_Str & VM_Str;
                     when VFUNCT6_VMFLT =>
                        return "vmflt.vf " & Vd_Str & ", " & Vs2_Str &
                           ", " & Fs1_Str & VM_Str;
                     when VFUNCT6_VMFNE =>
                        return "vmfne.vf " & Vd_Str & ", " & Vs2_Str &
                           ", " & Fs1_Str & VM_Str;
                     when VFUNCT6_VMFGT =>
                        return "vmfgt.vf " & Vd_Str & ", " & Vs2_Str &
                           ", " & Fs1_Str & VM_Str;
                     when VFUNCT6_VMFGE =>
                        return "vmfge.vf " & Vd_Str & ", " & Vs2_Str &
                           ", " & Fs1_Str & VM_Str;
                     when VFUNCT6_VFMACC =>
                        return "vfmacc.vf " & Vd_Str & ", " & Fs1_Str &
                           ", " & Vs2_Str & VM_Str;
                     when VFUNCT6_VFNMACC =>
                        return "vfnmacc.vf " & Vd_Str & ", " & Fs1_Str &
                           ", " & Vs2_Str & VM_Str;
                     when VFUNCT6_VFMSAC =>
                        return "vfmsac.vf " & Vd_Str & ", " & Fs1_Str &
                           ", " & Vs2_Str & VM_Str;
                     when VFUNCT6_VFNMSAC =>
                        return "vfnmsac.vf " & Vd_Str & ", " & Fs1_Str &
                           ", " & Vs2_Str & VM_Str;
                     when VFUNCT6_VFWADD =>
                        return "vfwadd.vf " & Vd_Str & ", " & Vs2_Str &
                           ", " & Fs1_Str & VM_Str;
                     when VFUNCT6_VFWSUB =>
                        return "vfwsub.vf " & Vd_Str & ", " & Vs2_Str &
                           ", " & Fs1_Str & VM_Str;
                     when VFUNCT6_VFWADDW =>
                        return "vfwadd.wf " & Vd_Str & ", " & Vs2_Str &
                           ", " & Fs1_Str & VM_Str;
                     when VFUNCT6_VFWSUBW =>
                        return "vfwsub.wf " & Vd_Str & ", " & Vs2_Str &
                           ", " & Fs1_Str & VM_Str;
                     when VFUNCT6_VFWMUL =>
                        return "vfwmul.vf " & Vd_Str & ", " & Vs2_Str &
                           ", " & Fs1_Str & VM_Str;
                     when VFUNCT6_VFWMACC =>
                        return "vfwmacc.vf " & Vd_Str & ", " & Fs1_Str &
                           ", " & Vs2_Str & VM_Str;
                     when VFUNCT6_VFWNMACC =>
                        return "vfwnmacc.vf " & Vd_Str & ", " & Fs1_Str &
                           ", " & Vs2_Str & VM_Str;
                     when VFUNCT6_VFWMSAC =>
                        return "vfwmsac.vf " & Vd_Str & ", " & Fs1_Str &
                           ", " & Vs2_Str & VM_Str;
                     when VFUNCT6_VFWNMSAC =>
                        return "vfwnmsac.vf " & Vd_Str & ", " & Fs1_Str &
                           ", " & Vs2_Str & VM_Str;
                     when others =>
                        return "vf?.vf  (f6=" &
                           Ada.Strings.Fixed.Trim
                             (Word'Image (Funct6), Ada.Strings.Left) & ")";
                  end case;
               end if;

               return "v???    (f3=" &
                  Ada.Strings.Fixed.Trim (Word'Image (Funct3), Ada.Strings.Left) &
                  ", f6=" &
                  Ada.Strings.Fixed.Trim (Word'Image (Funct6), Ada.Strings.Left) &
                  ")";
            end;

         when OPCODE_AMO =>
            --  A Extension: Atomic Memory Operations
            declare
               Funct5 : constant Word := Decoder.Get_Funct5 (Instruction);
               Aq     : constant Boolean := Decoder.Get_Aq (Instruction);
               Rl     : constant Boolean := Decoder.Get_Rl (Instruction);
               Suffix : constant String :=
                  (if Aq and Rl then ".aqrl"
                   elsif Aq then ".aq"
                   elsif Rl then ".rl"
                   else "");

               function Amo_Fmt (Name : String) return String is
               begin
                  return Name & Suffix & " " & Rd & ", " & Rs2 &
                         ", (" & Rs1 & ")";
               end Amo_Fmt;

               function Lr_Fmt return String is
               begin
                  return "lr.w" & Suffix & "    " & Rd & ", (" & Rs1 & ")";
               end Lr_Fmt;

               function Sc_Fmt return String is
               begin
                  return "sc.w" & Suffix & "    " & Rd & ", " & Rs2 &
                         ", (" & Rs1 & ")";
               end Sc_Fmt;
            begin
               --  Check for word-sized atomics
               if D.Funct3 /= FUNCT3_AMO_W then
                  return "amo? (invalid width)";
               end if;

               case Funct5 is
                  when FUNCT5_LR =>
                     return Lr_Fmt;
                  when FUNCT5_SC =>
                     return Sc_Fmt;
                  when FUNCT5_AMOSWAP =>
                     return Amo_Fmt ("amoswap.w");
                  when FUNCT5_AMOADD =>
                     return Amo_Fmt ("amoadd.w");
                  when FUNCT5_AMOXOR =>
                     return Amo_Fmt ("amoxor.w");
                  when FUNCT5_AMOAND =>
                     return Amo_Fmt ("amoand.w");
                  when FUNCT5_AMOOR =>
                     return Amo_Fmt ("amoor.w");
                  when FUNCT5_AMOMIN =>
                     return Amo_Fmt ("amomin.w");
                  when FUNCT5_AMOMAX =>
                     return Amo_Fmt ("amomax.w");
                  when FUNCT5_AMOMINU =>
                     return Amo_Fmt ("amominu.w");
                  when FUNCT5_AMOMAXU =>
                     return Amo_Fmt ("amomaxu.w");
                  when others =>
                     return "amo? (funct5=" &
                        Ada.Strings.Fixed.Trim
                          (Word'Image (Funct5), Ada.Strings.Left) & ")";
               end case;
            end;

         when OPCODE_FMADD =>
            return "fmadd.s";
         when OPCODE_FMSUB =>
            return "fmsub.s";
         when OPCODE_FNMSUB =>
            return "fnmsub.s";
         when OPCODE_FNMADD =>
            return "fnmadd.s";

         when OPCODE_MISC_MEM =>
            if D.Funct3 = 0 then
               return "fence";
            elsif D.Funct3 = 1 then
               return "fence.i";
            else
               return "fence.? (0x" & To_Hex (Instruction) & ")";
            end if;

         when others =>
            return "??? (0x" & To_Hex (Instruction) & ")";
      end case;
   end Disassemble;

end RISCV.Disasm;
