-- ***************************************************************************
--          RISC-V Emulator - Compressed Extension (RVC)
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

-- C Extension (RV32C) - 16-bit compressed instructions
package body RISCV.Compressed is

   -------------------
   -- Is_Compressed --
   -------------------

   function Is_Compressed (Instruction : Word) return Boolean is
   begin
      --  Compressed if bits [1:0] != 11
      return (Instruction and 2#11#) /= 2#11#;
   end Is_Compressed;

   ------------
   -- Expand --
   ------------

   function Expand (Compressed_Instr : Half_Word) return Word is
      Instr   : constant Word := Word (Compressed_Instr);
      Op      : constant Word := Instr and 2#11#;
      Funct3  : constant Word := Shift_Right (Instr, 13) and 2#111#;

      --  Helper: Extract compressed register (3-bit, maps to x8-x15)
      function CReg (Bits : Word) return Word is
      begin
         return (Bits and 7) + 8;
      end CReg;

      --  Encode R-type instruction
      function R_Type (Opcode : Word; Rd, Rs1, Rs2 : Word;
                       Funct3, Funct7 : Word) return Word is
      begin
         return Opcode or Shift_Left (Rd, 7) or Shift_Left (Funct3, 12) or
                Shift_Left (Rs1, 15) or Shift_Left (Rs2, 20) or
                Shift_Left (Funct7, 25);
      end R_Type;

      --  Encode I-type instruction
      function I_Type (Opcode : Word; Rd, Rs1 : Word;
                       Funct3 : Word; Imm : Word) return Word is
      begin
         return Opcode or Shift_Left (Rd, 7) or Shift_Left (Funct3, 12) or
                Shift_Left (Rs1, 15) or Shift_Left (Imm and 16#FFF#, 20);
      end I_Type;

      --  Encode S-type instruction
      function S_Type (Opcode : Word; Rs1, Rs2 : Word;
                       Funct3 : Word; Imm : Word) return Word is
         Imm_4_0  : constant Word := Imm and 16#1F#;
         Imm_11_5 : constant Word := Shift_Right (Imm, 5) and 16#7F#;
      begin
         return Opcode or Shift_Left (Imm_4_0, 7) or Shift_Left (Funct3, 12) or
                Shift_Left (Rs1, 15) or Shift_Left (Rs2, 20) or
                Shift_Left (Imm_11_5, 25);
      end S_Type;

      --  Encode B-type instruction
      function B_Type (Opcode : Word; Rs1, Rs2 : Word;
                       Funct3 : Word; Imm : Word) return Word is
         Imm_11   : constant Word := Shift_Right (Imm, 11) and 1;
         Imm_4_1  : constant Word := Shift_Right (Imm, 1) and 16#F#;
         Imm_10_5 : constant Word := Shift_Right (Imm, 5) and 16#3F#;
         Imm_12   : constant Word := Shift_Right (Imm, 12) and 1;
      begin
         return Opcode or Shift_Left (Imm_11, 7) or Shift_Left (Imm_4_1, 8) or
                Shift_Left (Funct3, 12) or Shift_Left (Rs1, 15) or
                Shift_Left (Rs2, 20) or Shift_Left (Imm_10_5, 25) or
                Shift_Left (Imm_12, 31);
      end B_Type;

      --  Encode J-type instruction
      function J_Type (Opcode : Word; Rd : Word; Imm : Word) return Word is
         Imm_10_1  : constant Word := Shift_Right (Imm, 1) and 16#3FF#;
         Imm_11    : constant Word := Shift_Right (Imm, 11) and 1;
         Imm_19_12 : constant Word := Shift_Right (Imm, 12) and 16#FF#;
         Imm_20    : constant Word := Shift_Right (Imm, 20) and 1;
      begin
         return Opcode or Shift_Left (Rd, 7) or Shift_Left (Imm_19_12, 12) or
                Shift_Left (Imm_11, 20) or Shift_Left (Imm_10_1, 21) or
                Shift_Left (Imm_20, 31);
      end J_Type;

      --  Encode U-type instruction
      function U_Type (Opcode : Word; Rd : Word; Imm : Word) return Word is
      begin
         return Opcode or Shift_Left (Rd, 7) or (Imm and 16#FFFFF000#);
      end U_Type;

      --  Sign-extend from N bits to 32 bits
      function Sign_Extend (Value : Word; Bits : Natural) return Word is
         Sign_Bit : constant Word := Shift_Left (1, Bits - 1);
      begin
         if (Value and Sign_Bit) /= 0 then
            return Value or (not (Shift_Left (1, Bits) - 1));
         else
            return Value;
         end if;
      end Sign_Extend;

   begin
      case Op is
         --  ============================================================
         --  C0 Quadrant (bits [1:0] = 00)
         --  ============================================================
         when C_QUADRANT_0 =>
            case Funct3 is
               --  C.ADDI4SPN: addi rd', x2, nzuimm
               when C0_ADDI4SPN =>
                  declare
                     Rd_C : constant Word := CReg (Shift_Right (Instr, 2));
                     --  nzuimm[5:4|9:6|2|3]
                     Uimm : Word := 0;
                  begin
                     Uimm := Shift_Left (Shift_Right (Instr, 6) and 1, 2) or
                             Shift_Left (Shift_Right (Instr, 5) and 1, 3) or
                             Shift_Left (Shift_Right (Instr, 11) and 3, 4) or
                             Shift_Left (Shift_Right (Instr, 7) and 16#F#, 6);
                     if Uimm = 0 then
                        return ILLEGAL_INSTR;  --  Reserved
                     end if;
                     return I_Type (OPCODE_OP_IMM, Rd_C, 2, FUNCT3_ADD_SUB,
                                    Uimm);
                  end;

               --  C.LW: lw rd', offset(rs1')
               when C0_LW =>
                  declare
                     Rd_C  : constant Word := CReg (Shift_Right (Instr, 2));
                     Rs1_C : constant Word := CReg (Shift_Right (Instr, 7));
                     --  uimm[5:3|2|6]
                     Uimm  : Word := 0;
                  begin
                     Uimm := Shift_Left (Shift_Right (Instr, 6) and 1, 2) or
                             Shift_Left (Shift_Right (Instr, 10) and 7, 3) or
                             Shift_Left (Shift_Right (Instr, 5) and 1, 6);
                     return I_Type (OPCODE_LOAD, Rd_C, Rs1_C, FUNCT3_LW, Uimm);
                  end;

               --  C.SW: sw rs2', offset(rs1')
               when C0_SW =>
                  declare
                     Rs2_C : constant Word := CReg (Shift_Right (Instr, 2));
                     Rs1_C : constant Word := CReg (Shift_Right (Instr, 7));
                     --  uimm[5:3|2|6]
                     Uimm  : Word := 0;
                  begin
                     Uimm := Shift_Left (Shift_Right (Instr, 6) and 1, 2) or
                             Shift_Left (Shift_Right (Instr, 10) and 7, 3) or
                             Shift_Left (Shift_Right (Instr, 5) and 1, 6);
                     return S_Type (OPCODE_STORE, Rs1_C, Rs2_C, FUNCT3_SW,
                                    Uimm);
                  end;

               --  C.FLW: flw fd', offset(rs1')  (RV32FC; same offset as C.LW)
               when C0_FLW =>
                  declare
                     Rd_C  : constant Word := CReg (Shift_Right (Instr, 2));
                     Rs1_C : constant Word := CReg (Shift_Right (Instr, 7));
                     Uimm  : Word := 0;
                  begin
                     Uimm := Shift_Left (Shift_Right (Instr, 6) and 1, 2) or
                             Shift_Left (Shift_Right (Instr, 10) and 7, 3) or
                             Shift_Left (Shift_Right (Instr, 5) and 1, 6);
                     return I_Type (OPCODE_LOAD_FP, Rd_C, Rs1_C, FUNCT3_FLW,
                                    Uimm);
                  end;

               --  C.FSW: fsw fs2', offset(rs1')  (RV32FC; same offset as C.SW)
               when C0_FSW =>
                  declare
                     Rs2_C : constant Word := CReg (Shift_Right (Instr, 2));
                     Rs1_C : constant Word := CReg (Shift_Right (Instr, 7));
                     Uimm  : Word := 0;
                  begin
                     Uimm := Shift_Left (Shift_Right (Instr, 6) and 1, 2) or
                             Shift_Left (Shift_Right (Instr, 10) and 7, 3) or
                             Shift_Left (Shift_Right (Instr, 5) and 1, 6);
                     return S_Type (OPCODE_STORE_FP, Rs1_C, Rs2_C, FUNCT3_FSW,
                                    Uimm);
                  end;

               --  C.FLD: fld fd', offset(rs1')  (doubleword offset, like C.LD)
               when C0_FLD =>
                  declare
                     Rd_C  : constant Word := CReg (Shift_Right (Instr, 2));
                     Rs1_C : constant Word := CReg (Shift_Right (Instr, 7));
                     Uimm  : Word := 0;
                  begin
                     Uimm := Shift_Left (Shift_Right (Instr, 10) and 7, 3) or
                             Shift_Left (Shift_Right (Instr, 5) and 3, 6);
                     return I_Type (OPCODE_LOAD_FP, Rd_C, Rs1_C, FUNCT3_FLD,
                                    Uimm);
                  end;

               --  C.FSD: fsd fs2', offset(rs1')  (doubleword offset, like C.SD)
               when C0_FSD =>
                  declare
                     Rs2_C : constant Word := CReg (Shift_Right (Instr, 2));
                     Rs1_C : constant Word := CReg (Shift_Right (Instr, 7));
                     Uimm  : Word := 0;
                  begin
                     Uimm := Shift_Left (Shift_Right (Instr, 10) and 7, 3) or
                             Shift_Left (Shift_Right (Instr, 5) and 3, 6);
                     return S_Type (OPCODE_STORE_FP, Rs1_C, Rs2_C, FUNCT3_FSD,
                                    Uimm);
                  end;

               when others =>
                  return ILLEGAL_INSTR;
            end case;

         --  ============================================================
         --  C1 Quadrant (bits [1:0] = 01)
         --  ============================================================
         when C_QUADRANT_1 =>
            case Funct3 is
               --  C.ADDI (also C.NOP when rd=0, imm=0)
               when C1_ADDI =>
                  declare
                     Rd  : constant Word := Shift_Right (Instr, 7) and 16#1F#;
                     --  imm[5|4:0]
                     Imm : Word := (Shift_Right (Instr, 2) and 16#1F#) or
                                   Shift_Left (Shift_Right (Instr, 12) and 1,
                                               5);
                  begin
                     Imm := Sign_Extend (Imm, 6);
                     --  C.NOP is valid (rd=0, imm=0)
                     return I_Type (OPCODE_OP_IMM, Rd, Rd, FUNCT3_ADD_SUB, Imm);
                  end;

               --  C.JAL (RV32 only): jal x1, offset
               when C1_JAL =>
                  declare
                     --  imm[11|4|9:8|10|6|7|3:1|5]
                     Imm : Word := 0;
                  begin
                     Imm := Shift_Left (Shift_Right (Instr, 3) and 7, 1) or
                            Shift_Left (Shift_Right (Instr, 11) and 1, 4) or
                            Shift_Left (Shift_Right (Instr, 2) and 1, 5) or
                            Shift_Left (Shift_Right (Instr, 7) and 1, 6) or
                            Shift_Left (Shift_Right (Instr, 6) and 1, 7) or
                            Shift_Left (Shift_Right (Instr, 9) and 3, 8) or
                            Shift_Left (Shift_Right (Instr, 8) and 1, 10) or
                            Shift_Left (Shift_Right (Instr, 12) and 1, 11);
                     Imm := Sign_Extend (Imm, 12);
                     return J_Type (OPCODE_JAL, 1, Imm);  --  x1 = ra
                  end;

               --  C.LI: addi rd, x0, imm
               when C1_LI =>
                  declare
                     Rd  : constant Word := Shift_Right (Instr, 7) and 16#1F#;
                     Imm : Word := (Shift_Right (Instr, 2) and 16#1F#) or
                                   Shift_Left (Shift_Right (Instr, 12) and 1,
                                               5);
                  begin
                     Imm := Sign_Extend (Imm, 6);
                     return I_Type (OPCODE_OP_IMM, Rd, 0, FUNCT3_ADD_SUB, Imm);
                  end;

               --  C.LUI or C.ADDI16SP
               when C1_LUI_ADDI16SP =>
                  declare
                     Rd : constant Word := Shift_Right (Instr, 7) and 16#1F#;
                  begin
                     if Rd = 2 then
                        --  C.ADDI16SP: addi x2, x2, nzimm
                        declare
                           --  nzimm[9|4|6|8:7|5]
                           Imm : Word := 0;
                        begin
                           Imm := Shift_Left (Shift_Right (Instr, 6) and 1, 4)
                                or Shift_Left (Shift_Right (Instr, 2) and 1, 5)
                                or Shift_Left (Shift_Right (Instr, 5) and 1, 6)
                                or Shift_Left (Shift_Right (Instr, 3) and 3, 7)
                                or Shift_Left (Shift_Right (Instr, 12) and 1,
                                               9);
                           Imm := Sign_Extend (Imm, 10);
                           if Imm = 0 then
                              return ILLEGAL_INSTR;  --  Reserved
                           end if;
                           return I_Type (OPCODE_OP_IMM, 2, 2, FUNCT3_ADD_SUB,
                                          Imm);
                        end;
                     elsif Rd /= 0 then
                        --  C.LUI: lui rd, nzimm
                        declare
                           --  nzimm[17|16:12]
                           Imm : Word := 0;
                        begin
                           Imm := Shift_Left (Shift_Right (Instr, 2) and 16#1F#,
                                              12) or
                                  Shift_Left (Shift_Right (Instr, 12) and 1,
                                              17);
                           Imm := Sign_Extend (Imm, 18);
                           if Imm = 0 then
                              return ILLEGAL_INSTR;  --  Reserved
                           end if;
                           return U_Type (OPCODE_LUI, Rd, Imm);
                        end;
                     else
                        --  C.LUI rd=0 is a HINT, expand to lui x0, imm
                        declare
                           Imm : Word := 0;
                        begin
                           Imm := Shift_Left (Shift_Right (Instr, 2) and 16#1F#,
                                              12) or
                                  Shift_Left (Shift_Right (Instr, 12) and 1,
                                              17);
                           Imm := Sign_Extend (Imm, 18);
                           if Imm = 0 then
                              return ILLEGAL_INSTR;  --  Reserved (nzimm=0)
                           end if;
                           return U_Type (OPCODE_LUI, 0, Imm);
                        end;
                     end if;
                  end;

               --  C.ARITH: SRLI/SRAI/ANDI/SUB/XOR/OR/AND
               when C1_ARITH =>
                  declare
                     Rd_C  : constant Word := CReg (Shift_Right (Instr, 7));
                     Func2 : constant Word := Shift_Right (Instr, 10) and 3;
                     Shamt : constant Word := (Shift_Right (Instr, 2) and
                                               16#1F#) or
                                              Shift_Left (Shift_Right (Instr,
                                                                       12) and
                                                          1, 5);
                  begin
                     case Func2 is
                        when 2#00# =>  --  C.SRLI
                           return I_Type (OPCODE_OP_IMM, Rd_C, Rd_C,
                                          FUNCT3_SRL_SRA, Shamt);
                        when 2#01# =>  --  C.SRAI
                           return I_Type (OPCODE_OP_IMM, Rd_C, Rd_C,
                                          FUNCT3_SRL_SRA,
                                          Shamt or Shift_Left (16#20#, 5));
                        when 2#10# =>  --  C.ANDI
                           declare
                              Imm : Word := Shamt;
                           begin
                              Imm := Sign_Extend (Imm, 6);
                              return I_Type (OPCODE_OP_IMM, Rd_C, Rd_C,
                                             FUNCT3_AND, Imm);
                           end;
                        when 2#11# =>  --  SUB/XOR/OR/AND
                           declare
                              Rs2_C : constant Word :=
                                 CReg (Shift_Right (Instr, 2));
                              Func2_2 : constant Word :=
                                 Shift_Right (Instr, 5) and 3;
                              Bit12   : constant Word :=
                                 Shift_Right (Instr, 12) and 1;
                           begin
                              if Bit12 = 0 then
                                 case Func2_2 is
                                    when 2#00# =>  --  C.SUB
                                       return R_Type (OPCODE_OP, Rd_C, Rd_C,
                                                      Rs2_C, FUNCT3_ADD_SUB,
                                                      FUNCT7_ALT);
                                    when 2#01# =>  --  C.XOR
                                       return R_Type (OPCODE_OP, Rd_C, Rd_C,
                                                      Rs2_C, FUNCT3_XOR, 0);
                                    when 2#10# =>  --  C.OR
                                       return R_Type (OPCODE_OP, Rd_C, Rd_C,
                                                      Rs2_C, FUNCT3_OR, 0);
                                    when 2#11# =>  --  C.AND
                                       return R_Type (OPCODE_OP, Rd_C, Rd_C,
                                                      Rs2_C, FUNCT3_AND, 0);
                                    when others =>
                                       return ILLEGAL_INSTR;
                                 end case;
                              else
                                 return ILLEGAL_INSTR;  --  Reserved in RV32
                              end if;
                           end;
                        when others =>
                           return ILLEGAL_INSTR;
                     end case;
                  end;

               --  C.J: jal x0, offset (unconditional jump)
               when C1_J =>
                  declare
                     --  Same immediate format as C.JAL
                     Imm : Word := 0;
                  begin
                     Imm := Shift_Left (Shift_Right (Instr, 3) and 7, 1) or
                            Shift_Left (Shift_Right (Instr, 11) and 1, 4) or
                            Shift_Left (Shift_Right (Instr, 2) and 1, 5) or
                            Shift_Left (Shift_Right (Instr, 7) and 1, 6) or
                            Shift_Left (Shift_Right (Instr, 6) and 1, 7) or
                            Shift_Left (Shift_Right (Instr, 9) and 3, 8) or
                            Shift_Left (Shift_Right (Instr, 8) and 1, 10) or
                            Shift_Left (Shift_Right (Instr, 12) and 1, 11);
                     Imm := Sign_Extend (Imm, 12);
                     return J_Type (OPCODE_JAL, 0, Imm);  --  x0 = discard link
                  end;

               --  C.BEQZ: beq rs1', x0, offset
               when C1_BEQZ =>
                  declare
                     Rs1_C : constant Word := CReg (Shift_Right (Instr, 7));
                     --  imm[8|4:3|7:6|2:1|5]
                     Imm   : Word := 0;
                  begin
                     Imm := Shift_Left (Shift_Right (Instr, 3) and 3, 1) or
                            Shift_Left (Shift_Right (Instr, 10) and 3, 3) or
                            Shift_Left (Shift_Right (Instr, 2) and 1, 5) or
                            Shift_Left (Shift_Right (Instr, 5) and 3, 6) or
                            Shift_Left (Shift_Right (Instr, 12) and 1, 8);
                     Imm := Sign_Extend (Imm, 9);
                     return B_Type (OPCODE_BRANCH, Rs1_C, 0, FUNCT3_BEQ, Imm);
                  end;

               --  C.BNEZ: bne rs1', x0, offset
               when C1_BNEZ =>
                  declare
                     Rs1_C : constant Word := CReg (Shift_Right (Instr, 7));
                     Imm   : Word := 0;
                  begin
                     Imm := Shift_Left (Shift_Right (Instr, 3) and 3, 1) or
                            Shift_Left (Shift_Right (Instr, 10) and 3, 3) or
                            Shift_Left (Shift_Right (Instr, 2) and 1, 5) or
                            Shift_Left (Shift_Right (Instr, 5) and 3, 6) or
                            Shift_Left (Shift_Right (Instr, 12) and 1, 8);
                     Imm := Sign_Extend (Imm, 9);
                     return B_Type (OPCODE_BRANCH, Rs1_C, 0, FUNCT3_BNE, Imm);
                  end;

               when others =>
                  return ILLEGAL_INSTR;
            end case;

         --  ============================================================
         --  C2 Quadrant (bits [1:0] = 10)
         --  ============================================================
         when C_QUADRANT_2 =>
            case Funct3 is
               --  C.SLLI
               when C2_SLLI =>
                  declare
                     Rd    : constant Word := Shift_Right (Instr, 7) and
                                              16#1F#;
                     Shamt : constant Word := (Shift_Right (Instr, 2) and
                                               16#1F#) or
                                              Shift_Left (Shift_Right (Instr,
                                                                       12) and
                                                          1, 5);
                  begin
                     if Rd = 0 then
                        return ILLEGAL_INSTR;  --  Reserved (hints)
                     end if;
                     return I_Type (OPCODE_OP_IMM, Rd, Rd, FUNCT3_SLL, Shamt);
                  end;

               --  C.LWSP: lw rd, offset(x2)
               when C2_LWSP =>
                  declare
                     Rd   : constant Word := Shift_Right (Instr, 7) and 16#1F#;
                     --  uimm[5|4:2|7:6]
                     Uimm : Word := 0;
                  begin
                     if Rd = 0 then
                        return ILLEGAL_INSTR;  --  Reserved
                     end if;
                     Uimm := Shift_Left (Shift_Right (Instr, 4) and 7, 2) or
                             Shift_Left (Shift_Right (Instr, 12) and 1, 5) or
                             Shift_Left (Shift_Right (Instr, 2) and 3, 6);
                     return I_Type (OPCODE_LOAD, Rd, 2, FUNCT3_LW, Uimm);
                  end;

               --  C.JR / C.MV / C.EBREAK / C.JALR / C.ADD
               when C2_JR_MV_ADD =>
                  declare
                     Rd   : constant Word := Shift_Right (Instr, 7) and 16#1F#;
                     Rs2  : constant Word := Shift_Right (Instr, 2) and 16#1F#;
                     Bit12 : constant Word := Shift_Right (Instr, 12) and 1;
                  begin
                     if Bit12 = 0 then
                        if Rs2 = 0 then
                           --  C.JR: jalr x0, 0(rs1)
                           if Rd = 0 then
                              return ILLEGAL_INSTR;  --  Reserved
                           end if;
                           return I_Type (OPCODE_JALR, 0, Rd, 0, 0);
                        else
                           --  C.MV: add rd, x0, rs2 (rd=0 is HINT)
                           return R_Type (OPCODE_OP, Rd, 0, Rs2,
                                          FUNCT3_ADD_SUB, 0);
                        end if;
                     else
                        if Rs2 = 0 then
                           if Rd = 0 then
                              --  C.EBREAK
                              return OPCODE_SYSTEM or Shift_Left (1, 20);
                           else
                              --  C.JALR: jalr x1, 0(rs1)
                              return I_Type (OPCODE_JALR, 1, Rd, 0, 0);
                           end if;
                        else
                           --  C.ADD: add rd, rd, rs2 (rd=0 is HINT)
                           return R_Type (OPCODE_OP, Rd, Rd, Rs2,
                                          FUNCT3_ADD_SUB, 0);
                        end if;
                     end if;
                  end;

               --  C.SWSP: sw rs2, offset(x2)
               when C2_SWSP =>
                  declare
                     Rs2  : constant Word := Shift_Right (Instr, 2) and 16#1F#;
                     --  uimm[5:2|7:6]
                     Uimm : Word := 0;
                  begin
                     Uimm := Shift_Left (Shift_Right (Instr, 9) and 16#F#, 2) or
                             Shift_Left (Shift_Right (Instr, 7) and 3, 6);
                     return S_Type (OPCODE_STORE, 2, Rs2, FUNCT3_SW, Uimm);
                  end;

               --  C.FLWSP: flw fd, offset(x2)  (RV32FC; same offset as C.LWSP)
               when C2_FLWSP =>
                  declare
                     Rd   : constant Word := Shift_Right (Instr, 7) and 16#1F#;
                     Uimm : Word := 0;
                  begin
                     Uimm := Shift_Left (Shift_Right (Instr, 4) and 7, 2) or
                             Shift_Left (Shift_Right (Instr, 12) and 1, 5) or
                             Shift_Left (Shift_Right (Instr, 2) and 3, 6);
                     return I_Type (OPCODE_LOAD_FP, Rd, 2, FUNCT3_FLW, Uimm);
                  end;

               --  C.FSWSP: fsw fs2, offset(x2)  (RV32FC; same offset as C.SWSP)
               when C2_FSWSP =>
                  declare
                     Rs2  : constant Word := Shift_Right (Instr, 2) and 16#1F#;
                     Uimm : Word := 0;
                  begin
                     Uimm := Shift_Left (Shift_Right (Instr, 9) and 16#F#, 2) or
                             Shift_Left (Shift_Right (Instr, 7) and 3, 6);
                     return S_Type (OPCODE_STORE_FP, 2, Rs2, FUNCT3_FSW, Uimm);
                  end;

               --  C.FLDSP: fld fd, offset(x2)  (doubleword, like C.LDSP)
               when C2_FLDSP =>
                  declare
                     Rd   : constant Word := Shift_Right (Instr, 7) and 16#1F#;
                     Uimm : Word := 0;
                  begin
                     Uimm := Shift_Left (Shift_Right (Instr, 5) and 3, 3) or
                             Shift_Left (Shift_Right (Instr, 12) and 1, 5) or
                             Shift_Left (Shift_Right (Instr, 2) and 7, 6);
                     return I_Type (OPCODE_LOAD_FP, Rd, 2, FUNCT3_FLD, Uimm);
                  end;

               --  C.FSDSP: fsd fs2, offset(x2)  (doubleword, like C.SDSP)
               when C2_FSDSP =>
                  declare
                     Rs2  : constant Word := Shift_Right (Instr, 2) and 16#1F#;
                     Uimm : Word := 0;
                  begin
                     Uimm := Shift_Left (Shift_Right (Instr, 10) and 7, 3) or
                             Shift_Left (Shift_Right (Instr, 7) and 7, 6);
                     return S_Type (OPCODE_STORE_FP, 2, Rs2, FUNCT3_FSD, Uimm);
                  end;

               when others =>
                  return ILLEGAL_INSTR;
            end case;

         when others =>
            return ILLEGAL_INSTR;
      end case;
   end Expand;

end RISCV.Compressed;
