-- ***************************************************************************
--                RISC-V Emulator - 64-bit CPU Core (RV64)
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

with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Text_IO; use Ada.Text_IO;
with Ada.Calendar;
with Ada.Directories;
with Ada.Unchecked_Conversion;
with RISCV.Decoder;
with RISCV.ALU64;
with RISCV.Crypto;
with RISCV.Disasm;
with RISCV.Compressed;
with RISCV.CSR;
with RISCV.CLINT;
with RISCV.UART;

package body RISCV.CPU64 is

   --  Access_Result comparisons in the load/store paths below.
   use type Memory.Access_Result;

   package Crypto renames RISCV.Crypto;

   function To_Signed64 is new Ada.Unchecked_Conversion (Double_Word, Signed_DWord);
   function To_Double   is new Ada.Unchecked_Conversion (Signed_DWord, Double_Word);
   function To_Signed   is new Ada.Unchecked_Conversion (Word, Signed_Word);
   function To_Word     is new Ada.Unchecked_Conversion (Signed_Word, Word);

   --  Sign-extend a Signed_Word immediate to Double_Word
   function SE (SW : Signed_Word) return Double_Word is
   begin
      return To_Double (Signed_DWord (Integer_64 (SW)));
   end SE;

   --  Sign-extend a 32-bit value to 64 bits
   function SE32 (W : Word) return Double_Word is
   begin
      return To_Double (Signed_DWord (Integer_64 (To_Signed (W))));
   end SE32;

   --  Read a 64-bit double-word from memory (two 32-bit reads)
   function Read_DWord_Mem (Mem  : in out Memory.Memory_Unit;
                             Addr : Memory_Address_64) return Double_Word is
      Lo : constant Word := Memory.Read_Word (Mem, Memory_Address (Addr));
      Hi : constant Word := Memory.Read_Word (Mem, Memory_Address (Addr + 4));
   begin
      return Double_Word (Lo) or Shift_Left (Double_Word (Hi), 32);
   end Read_DWord_Mem;

   --  Write a 64-bit double-word to memory (two 32-bit writes)
   procedure Write_DWord_Mem (Mem   : in out Memory.Memory_Unit;
                               Addr  : Memory_Address_64;
                               Value : Double_Word) is
   begin
      Memory.Write_Word (Mem, Memory_Address (Addr),
                         Word (Value and 16#FFFF_FFFF#));
      Memory.Write_Word (Mem, Memory_Address (Addr + 4),
                         Word (Shift_Right (Value, 32)));
   end Write_DWord_Mem;

   --  Is the C (compressed) extension currently enabled (misa bit 2 = 1)?
   --  When disabled, IALIGN=32 and every instruction fetch / control-transfer
   --  target must be 4-byte aligned, else an instruction-address-misaligned
   --  exception is raised.
   function C_Ext_Enabled (CPU : CPU64_State) return Boolean is
   begin
      return (CSR64.Read (CPU.CSRs, CSR64.CSR_MISA) and 2#100#) /= 0;
   end C_Ext_Enabled;

   ----------------
   -- Initialize --
   ----------------

   procedure Initialize (CPU      : out CPU64_State;
                         Start_PC : Double_Word := 0) is
   begin
      CPU.Registers         := (others => 0);
      CPU.PC                := Memory_Address_64 (Start_PC);
      CPU.Reset_Vector      := Memory_Address_64 (Start_PC);
      CPU.Halted            := False;
      CPU.Exception_Code    := No_Exception;
      CPU.Reservation_Valid := False;
      CPU.Reserved_Addr     := 0;
      CPU.Priv_Mode         := Machine;
      FPU.Initialize (CPU.FP);
      Vector.Initialize (CPU.VU);
      CSR64.Initialize (CPU.CSRs);
   end Initialize;

   -------------------
   -- Read_Register --
   -------------------

   function Read_Register (CPU : CPU64_State;
                            Reg : Register_Index) return Double_Word is
   begin
      if Reg = 0 then
         return 0;
      else
         return CPU.Registers (Reg);
      end if;
   end Read_Register;

   --------------------
   -- Write_Register --
   --------------------

   procedure Write_Register (CPU   : in out CPU64_State;
                              Reg   : Register_Index;
                              Value : Double_Word) is
   begin
      if Reg /= 0 then
         CPU.Registers (Reg) := Value;
      end if;
   end Write_Register;

   ----------
   -- Step --
   ----------

   procedure Step (CPU       : in out CPU64_State;
                   Mem       : in out Memory.Memory_Unit;
                   Trace     : Boolean := False;
                   Trace_Cfg : Trace_Config := (Enabled => False, others => <>)) is
      use Decoder;
      use ALU64;

      Instruction   : Word;
      Decoded       : Decoded_Instruction;
      Rs1_Val       : Double_Word;
      Rs2_Val       : Double_Word;
      Result        : Double_Word;
      Address       : Memory_Address_64;
      Next_PC       : Memory_Address_64;
      Branch        : Boolean;
      Old_Regs      : Register_File_64;
      Trace_Enabled : Boolean;
      Is_Compressed : Boolean;
      Instr_Size    : Memory_Address_64;

      --  Local hex formatter for 64-bit values
      function To_Hex64 (V : Double_Word) return String is
         Hex_Chars : constant String := "0123456789abcdef";
         Res       : String (1 .. 16);
         Val       : Double_Word := V;
      begin
         for I in reverse Res'Range loop
            Res (I) := Hex_Chars (Natural (Val and 16#F#) + 1);
            Val := Shift_Right (Val, 4);
         end loop;
         return Res;
      end To_Hex64;

      --  Local hex formatter for 32-bit values
      function To_Hex (V : Word) return String is
         Hex_Chars : constant String := "0123456789abcdef";
         Res       : String (1 .. 8);
         Val       : Word := V;
      begin
         for I in reverse Res'Range loop
            Res (I) := Hex_Chars (Natural (Val and 16#F#) + 1);
            Val := Shift_Right (Val, 4);
         end loop;
         return Res;
      end To_Hex;

      --  RV64C expansion: handles RV64-specific recodings over the base RV32C
      function Expand64 (CI : Half_Word) return Word is
         Instr   : constant Word := Word (CI);
         Op      : constant Word := Instr and 2#11#;
         Funct3  : constant Word := Shift_Right (Instr, 13) and 2#111#;

         --  Compressed register (3-bit, maps to x8-x15)
         function CReg (Bits : Word) return Word is
         begin
            return (Bits and 7) + 8;
         end CReg;

         --  Encode I-type instruction
         function I_Type (Opcode : Word; Rd, Rs1 : Word;
                          Funct3_Val : Word; Imm : Word) return Word is
         begin
            return Opcode or Shift_Left (Rd, 7) or Shift_Left (Funct3_Val, 12) or
                   Shift_Left (Rs1, 15) or Shift_Left (Imm and 16#FFF#, 20);
         end I_Type;

         --  Encode S-type instruction
         function S_Type (Opcode : Word; Rs1, Rs2 : Word;
                          Funct3_Val : Word; Imm : Word) return Word is
            Imm_4_0  : constant Word := Imm and 16#1F#;
            Imm_11_5 : constant Word := Shift_Right (Imm, 5) and 16#7F#;
         begin
            return Opcode or Shift_Left (Imm_4_0, 7) or Shift_Left (Funct3_Val, 12) or
                   Shift_Left (Rs1, 15) or Shift_Left (Rs2, 20) or
                   Shift_Left (Imm_11_5, 25);
         end S_Type;

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

         --  C0 quadrant constants
         C_QUADRANT_0 : constant Word := 0;
         C_QUADRANT_1 : constant Word := 1;
         C_QUADRANT_2 : constant Word := 2;

         --  C0 funct3
         C0_LD  : constant Word := 2#011#;
         C0_SD  : constant Word := 2#111#;

         --  C1 funct3
         C1_ADDIW : constant Word := 2#001#;  -- RV64: was C.JAL in RV32
         C1_ARITH : constant Word := 2#100#;  -- SRLI/SRAI/ANDI/SUB/../SUBW/ADDW

         --  C2 funct3
         C2_LDSP  : constant Word := 2#011#;
         C2_SDSP  : constant Word := 2#111#;

      begin
         case Op is
            --  ============================================================
            --  C0 Quadrant
            --  ============================================================
            when C_QUADRANT_0 =>
               if Funct3 = C0_LD then
                  --  C.LD: ld rd', offset(rs1')
                  --  offset = {uimm[5:3], uimm[7:6]} (zero-extended, *8)
                  declare
                     Rd_C  : constant Word := CReg (Shift_Right (Instr, 2));
                     Rs1_C : constant Word := CReg (Shift_Right (Instr, 7));
                     Uimm  : Word := 0;
                  begin
                     Uimm := Shift_Left (Shift_Right (Instr, 10) and 7, 3) or
                             Shift_Left (Shift_Right (Instr, 5) and 3, 6);
                     return I_Type (OPCODE_LOAD, Rd_C, Rs1_C, FUNCT3_LD, Uimm);
                  end;
               elsif Funct3 = C0_SD then
                  --  C.SD: sd rs2', offset(rs1')
                  --  same offset encoding as C.LD
                  declare
                     Rs2_C : constant Word := CReg (Shift_Right (Instr, 2));
                     Rs1_C : constant Word := CReg (Shift_Right (Instr, 7));
                     Uimm  : Word := 0;
                  begin
                     Uimm := Shift_Left (Shift_Right (Instr, 10) and 7, 3) or
                             Shift_Left (Shift_Right (Instr, 5) and 3, 6);
                     return S_Type (OPCODE_STORE, Rs1_C, Rs2_C, FUNCT3_SD, Uimm);
                  end;
               else
                  --  All other C0 instructions are identical to RV32C
                  return Compressed.Expand (CI);
               end if;

            --  ============================================================
            --  C1 Quadrant
            --  ============================================================
            when C_QUADRANT_1 =>
               if Funct3 = C1_ADDIW then
                  --  C.ADDIW: addiw rd, rd, imm  (RV64 replacement for C.JAL)
                  declare
                     Rd  : constant Word := Shift_Right (Instr, 7) and 16#1F#;
                     Imm : Word := (Shift_Right (Instr, 2) and 16#1F#) or
                                   Shift_Left (Shift_Right (Instr, 12) and 1, 5);
                  begin
                     if Rd = 0 then
                        return Compressed.ILLEGAL_INSTR;  --  Reserved
                     end if;
                     Imm := Sign_Extend (Imm, 6);
                     return I_Type (OPCODE_OP_IMM_32, Rd, Rd, FUNCT3_ADD_SUB, Imm);
                  end;
               elsif Funct3 = C1_ARITH and then
                     (Shift_Right (Instr, 10) and 3) = 2#11# and then
                     (Shift_Right (Instr, 12) and 1) = 1
               then
                  --  C.SUBW / C.ADDW: CA-format with bit12=1 (reserved in RV32,
                  --  RV64-only). funct2 (bits 6:5): 00 = SUBW, 01 = ADDW.
                  declare
                     Rd_C  : constant Word := CReg (Shift_Right (Instr, 7));
                     Rs2_C : constant Word := CReg (Shift_Right (Instr, 2));
                     F7    : Word;
                  begin
                     case Shift_Right (Instr, 5) and 3 is
                        when 2#00# => F7 := FUNCT7_ALT;  --  C.SUBW
                        when 2#01# => F7 := 0;           --  C.ADDW
                        when others => return Compressed.ILLEGAL_INSTR;
                     end case;
                     return OPCODE_OP_32 or Shift_Left (Rd_C, 7) or
                            Shift_Left (FUNCT3_ADD_SUB, 12) or
                            Shift_Left (Rd_C, 15) or Shift_Left (Rs2_C, 20) or
                            Shift_Left (F7, 25);
                  end;
               else
                  --  All other C1 instructions are identical to RV32C
                  return Compressed.Expand (CI);
               end if;

            --  ============================================================
            --  C2 Quadrant
            --  ============================================================
            when C_QUADRANT_2 =>
               if Funct3 = C2_LDSP then
                  --  C.LDSP: ld rd, offset(sp)
                  --  offset[5]=bit12, offset[4:3]=bits6:5, offset[8:6]=bits4:2
                  declare
                     Rd   : constant Word := Shift_Right (Instr, 7) and 16#1F#;
                     Uimm : Word := 0;
                  begin
                     if Rd = 0 then
                        return Compressed.ILLEGAL_INSTR;  --  Reserved
                     end if;
                     Uimm := Shift_Left (Shift_Right (Instr, 5) and 3, 3) or
                             Shift_Left (Shift_Right (Instr, 12) and 1, 5) or
                             Shift_Left (Shift_Right (Instr, 2) and 7, 6);
                     return I_Type (OPCODE_LOAD, Rd, 2, FUNCT3_LD, Uimm);
                  end;
               elsif Funct3 = C2_SDSP then
                  --  C.SDSP: sd rs2, offset(sp)
                  --  offset[5:3]=bits12:10, offset[8:6]=bits9:7 (zero-ext, *8)
                  declare
                     Rs2  : constant Word := Shift_Right (Instr, 2) and 16#1F#;
                     Uimm : Word := 0;
                  begin
                     Uimm := Shift_Left (Shift_Right (Instr, 10) and 7, 3) or
                             Shift_Left (Shift_Right (Instr, 7) and 7, 6);
                     return S_Type (OPCODE_STORE, 2, Rs2, FUNCT3_SD, Uimm);
                  end;
               else
                  --  All other C2 instructions are identical to RV32C
                  return Compressed.Expand (CI);
               end if;

            when others =>
               return Compressed.ILLEGAL_INSTR;
         end case;
      end Expand64;

      --  Translate a virtual address to a physical address via Sv39 MMU.
      --  Returns True on success; on page fault, triggers trap and returns False.
      function Translate_Address (VA  : Memory_Address_64;
                                  Acc : MMU.Access_Type;
                                  PA  : out Memory_Address_64)
         return Boolean
      is
         SATP_Val : constant Double_Word :=
            CSR64.Read (CPU.CSRs, CSR64.CSR_SATP);
         Mst      : constant Double_Word :=
            CSR64.Read (CPU.CSRs, CSR64.CSR_MSTATUS);
         Cause    : Double_Word;
         Tval     : Double_Word;
      begin
         if not MMU.Translate (CPU.MMU, VA, Acc, CPU.Priv_Mode,
                               SATP_Val, Mst, Mem, PA, Cause, Tval)
         then
            case Acc is
               when MMU.Execute => CPU.Exception_Code := Insn_Page_Fault;
               when MMU.Load    => CPU.Exception_Code := Load_Page_Fault;
               when MMU.Store   => CPU.Exception_Code := Store_Page_Fault;
            end case;
            Trap_Entry (CPU, Cause, Double_Word (VA));
            return False;
         end if;
         return True;
      end Translate_Address;

   begin
      if CPU.Halted then
         return;
      end if;

      --  Fetch instruction (with MMU translation). The low half-word is
      --  fetched on its own so that a 16-bit instruction in the last
      --  half-word of a region does not fault on the two bytes past its end
      --  that a full word fetch would touch.
      declare
         Phys_PC : Memory_Address_64;
         Lo      : Half_Word;
         Hi      : Half_Word;
         Both    : Boolean;
      begin
         if not Translate_Address (CPU.PC, MMU.Execute, Phys_PC) then
            return;
         end if;
         Memory.Clear_Access_Fault (Mem);
         Memory.Read_Insn_Halves
            (Mem, Memory_Address (Phys_PC), Lo, Hi, Both);
         if Memory.Pending_Fault (Mem) /= Memory.OK then
            CPU.Exception_Code := Insn_Access_Fault;
            Trap_Entry (CPU,
                        Double_Word (CSR.CAUSE_INSN_ACCESS_FAULT),
                        Double_Word (CPU.PC));
            return;
         end if;

         if Compressed.Is_Compressed (Word (Lo)) then
            --  16-bit compressed instruction
            Is_Compressed := True;
            Instr_Size := 2;
            --  Expand using RV64C rules
            Instruction := Expand64 (Lo);
            if Instruction = Compressed.ILLEGAL_INSTR then
               CPU.Exception_Code := Illegal_Instruction;
               Trap_Entry (CPU,
                           Double_Word (CSR.CAUSE_ILLEGAL_INSN),
                           Double_Word (Instruction));
               return;
            end if;
         else
            Is_Compressed := False;
            Instr_Size := 4;
            if not Both then
               Hi := Memory.Read_Half_Word
                        (Mem, Memory_Address (Phys_PC) + 2);
               if Memory.Pending_Fault (Mem) /= Memory.OK then
                  CPU.Exception_Code := Insn_Access_Fault;
                  Trap_Entry (CPU,
                              Double_Word (CSR.CAUSE_INSN_ACCESS_FAULT),
                              Double_Word (CPU.PC));
                  return;
               end if;
            end if;
            Instruction := Word (Lo) or Shift_Left (Word (Hi), 16);
         end if;
      end;

      Decoded := Decode (Instruction);

      --  Check if tracing is enabled for this PC
      Trace_Enabled :=
         (Trace or Trace_Cfg.Enabled) and then
         CPU.PC >= Trace_Cfg.PC_Start and then
         CPU.PC <= Trace_Cfg.PC_End;

      --  Save old register state if register tracing enabled
      if Trace_Enabled and Trace_Cfg.Show_Regs then
         Old_Regs := CPU.Registers;
      end if;

      --  Print instruction trace
      if Trace_Enabled then
         if Is_Compressed then
            Put (To_Hex64 (Double_Word (CPU.PC)) & ":      " &
                 To_Hex (Instruction) & "  [C] ");
         else
            Put (To_Hex64 (Double_Word (CPU.PC)) & ":  " &
                 To_Hex (Instruction) & "  ");
         end if;
         Put_Line (Disasm.Disassemble (Instruction, Word (CPU.PC)));
      end if;

      --  Read source registers
      Rs1_Val := Read_Register (CPU, Decoded.Rs1);
      Rs2_Val := Read_Register (CPU, Decoded.Rs2);

      --  Default: advance to next instruction
      Next_PC := CPU.PC + Instr_Size;
      Branch  := False;

      --  RV64E: trap if any register operand is >= 16 for R-type instructions.
      --  Only OPCODE_OP and OPCODE_OP_32 (R-type) are checked: those three
      --  fields (Rs1/Rs2/Rd) are all architectural registers with no aliasing
      --  to immediates. OPCODE_OP_IMM, OPCODE_LOAD, OPCODE_STORE, OPCODE_BRANCH
      --  are NOT checked because log64.c/semihosting (a7=x17) and compiler-
      --  generated prologues freely use x16-x31 in those encodings.
      if CPU.Rv32e and then
         (Decoded.Opcode = OPCODE_OP or else Decoded.Opcode = OPCODE_OP_32)
      then
         if Word (Decoded.Rs1) >= 16 or else
            Word (Decoded.Rs2) >= 16 or else
            Word (Decoded.Rd)  >= 16
         then
            CPU.Exception_Code := Illegal_Instruction;
            Trap_Entry (CPU, Double_Word (CSR.CAUSE_ILLEGAL_INSN),
                        Double_Word (Instruction));
            return;
         end if;
      end if;

      case Decoded.Opcode is

         -----------------
         -- LUI (U-type)
         -----------------
         when OPCODE_LUI =>
            --  Sign-extend the 32-bit U-type immediate (already shifted to [31:12])
            Write_Register (CPU, Decoded.Rd, SE32 (Decoded.Imm_U));

         -------------------
         -- AUIPC (U-type)
         -------------------
         when OPCODE_AUIPC =>
            Write_Register (CPU, Decoded.Rd,
                            Double_Word (CPU.PC) + SE32 (Decoded.Imm_U));

         -----------------
         -- JAL (J-type)
         -----------------
         when OPCODE_JAL =>
            Next_PC := Memory_Address_64
              (Double_Word (CPU.PC) + SE (Decoded.Imm_J));
            --  With C disabled (IALIGN=32), a target that is not 4-byte
            --  aligned faults on the jump itself and rd is left unwritten.
            if (Double_Word (Next_PC) and 2) /= 0 and then
               not C_Ext_Enabled (CPU)
            then
               CPU.Exception_Code := Misaligned_Fetch;
               Trap_Entry (CPU, Double_Word (CSR.CAUSE_INSN_MISALIGNED),
                           Double_Word (Next_PC));
               return;
            end if;
            Write_Register (CPU, Decoded.Rd,
                            Double_Word (CPU.PC) + Double_Word (Instr_Size));
            Branch := True;

         ------------------
         -- JALR (I-type)
         ------------------
         when OPCODE_JALR =>
            Result := (Rs1_Val + SE (Decoded.Imm_I)) and
                      (not Double_Word (1));  --  Clear LSB
            Next_PC := Memory_Address_64 (Result);
            if (Double_Word (Next_PC) and 2) /= 0 and then
               not C_Ext_Enabled (CPU)
            then
               CPU.Exception_Code := Misaligned_Fetch;
               Trap_Entry (CPU, Double_Word (CSR.CAUSE_INSN_MISALIGNED),
                           Double_Word (Next_PC));
               return;
            end if;
            Write_Register (CPU, Decoded.Rd,
                            Double_Word (CPU.PC) + Double_Word (Instr_Size));
            Branch := True;

         ----------------------
         -- Branches (B-type)
         ----------------------
         when OPCODE_BRANCH =>
            case Decoded.Funct3 is
               when FUNCT3_BEQ =>
                  Branch := Rs1_Val = Rs2_Val;
               when FUNCT3_BNE =>
                  Branch := Rs1_Val /= Rs2_Val;
               when FUNCT3_BLT =>
                  Branch := To_Signed64 (Rs1_Val) < To_Signed64 (Rs2_Val);
               when FUNCT3_BGE =>
                  Branch := To_Signed64 (Rs1_Val) >= To_Signed64 (Rs2_Val);
               when FUNCT3_BLTU =>
                  Branch := Rs1_Val < Rs2_Val;
               when FUNCT3_BGEU =>
                  Branch := Rs1_Val >= Rs2_Val;
               when others =>
                  CPU.Exception_Code := Illegal_Instruction;
                  Trap_Entry (CPU,
                              Double_Word (CSR.CAUSE_ILLEGAL_INSN),
                              Double_Word (Instruction));
                  return;
            end case;

            if Branch then
               Next_PC := Memory_Address_64
                 (Double_Word (CPU.PC) + SE (Decoded.Imm_B));
               if (Double_Word (Next_PC) and 2) /= 0 and then
                  not C_Ext_Enabled (CPU)
               then
                  CPU.Exception_Code := Misaligned_Fetch;
                  Trap_Entry (CPU, Double_Word (CSR.CAUSE_INSN_MISALIGNED),
                              Double_Word (Next_PC));
                  return;
               end if;
            end if;

         -------------------
         -- Loads (I-type)
         -------------------
         when OPCODE_LOAD =>
            Address := Memory_Address_64 (Rs1_Val + SE (Decoded.Imm_I));

            declare
               Phys_Addr : Memory_Address_64;
            begin
               if not Translate_Address (Address, MMU.Load, Phys_Addr) then
                  return;
               end if;
               Address := Phys_Addr;
            end;
            Memory.Clear_Access_Fault (Mem);

            case Decoded.Funct3 is
               when FUNCT3_LB =>
                  Result := Double_Word (Memory.Read_Byte (Mem, Memory_Address (Address)));
                  --  Sign extend from 8 bits
                  if (Result and 16#80#) /= 0 then
                     Result := Result or 16#FFFFFFFFFFFFFF00#;
                  end if;

               when FUNCT3_LH =>
                  --  Misaligned loads are emulated (byte-composed accessors).
                  Result := Double_Word (Memory.Read_Half_Word (Mem, Memory_Address (Address)));
                  --  Sign extend from 16 bits
                  if (Result and 16#8000#) /= 0 then
                     Result := Result or 16#FFFFFFFFFFFF0000#;
                  end if;

               when FUNCT3_LW =>
                  --  LW in RV64: sign-extends to 64 bits
                  Result := SE32 (Memory.Read_Word (Mem, Memory_Address (Address)));

               when FUNCT3_LWU =>
                  --  LWU: load word unsigned (zero-extend to 64 bits)
                  Result := Double_Word (Memory.Read_Word (Mem, Memory_Address (Address)));

               when FUNCT3_LD =>
                  --  LD: load 8 bytes
                  Result := Read_DWord_Mem (Mem, Address);

               when FUNCT3_LBU =>
                  Result := Double_Word (Memory.Read_Byte (Mem, Memory_Address (Address)));

               when FUNCT3_LHU =>
                  Result := Double_Word (Memory.Read_Half_Word (Mem, Memory_Address (Address)));

               when others =>
                  CPU.Exception_Code := Illegal_Instruction;
                  Trap_Entry (CPU,
                              Double_Word (CSR.CAUSE_ILLEGAL_INSN),
                              Double_Word (Instruction));
                  return;
            end case;

            --  An unmapped or unreadable byte anywhere in the access is a
            --  load access fault; rd must be left unwritten.
            if Memory.Pending_Fault (Mem) /= Memory.OK then
               CPU.Exception_Code := Load_Access_Fault;
               Trap_Entry (CPU,
                           Double_Word (CSR.CAUSE_LOAD_ACCESS_FAULT),
                           Double_Word (Memory.Pending_Fault_Address (Mem)));
               return;
            end if;

            Write_Register (CPU, Decoded.Rd, Result);

         --------------------
         -- Stores (S-type)
         --------------------
         when OPCODE_STORE =>
            Address := Memory_Address_64 (Rs1_Val + SE (Decoded.Imm_S));

            declare
               Phys_Addr : Memory_Address_64;
            begin
               if not Translate_Address (Address, MMU.Store, Phys_Addr) then
                  return;
               end if;
               Address := Phys_Addr;
            end;
            Memory.Clear_Access_Fault (Mem);

            case Decoded.Funct3 is
               when FUNCT3_SB =>
                  Memory.Write_Byte (Mem, Memory_Address (Address),
                                     Byte (Rs2_Val and 16#FF#));

               when FUNCT3_SH =>
                  --  Misaligned stores are emulated (byte-composed accessors).
                  Memory.Write_Half_Word (Mem, Memory_Address (Address),
                                         Half_Word (Rs2_Val and 16#FFFF#));

               when FUNCT3_SW =>
                  Memory.Write_Word (Mem, Memory_Address (Address),
                                     Word (Rs2_Val and 16#FFFF_FFFF#));

               when FUNCT3_SD =>
                  --  SD: store 8 bytes
                  Write_DWord_Mem (Mem, Address, Rs2_Val);

               when others =>
                  CPU.Exception_Code := Illegal_Instruction;
                  Trap_Entry (CPU,
                              Double_Word (CSR.CAUSE_ILLEGAL_INSN),
                              Double_Word (Instruction));
                  return;
            end case;

            --  A store to unmapped memory, or to a read-only region, is a
            --  store access fault rather than a silent no-op.
            if Memory.Pending_Fault (Mem) /= Memory.OK then
               CPU.Exception_Code := Store_Access_Fault;
               Trap_Entry (CPU,
                           Double_Word (CSR.CAUSE_STORE_ACCESS_FAULT),
                           Double_Word (Memory.Pending_Fault_Address (Mem)));
               return;
            end if;

         ----------------------------
         -- OP-IMM (I-type ALU ops)
         ----------------------------
         when OPCODE_OP_IMM =>
            declare
               --  For shifts: 6-bit shamt in bits [25:20] of instruction
               --  which corresponds to lower 6 bits of the 12-bit imm field
               Shamt : constant Natural :=
                  Natural (To_Word (Decoded.Imm_I) and 16#3F#);
               Imm64 : constant Double_Word := SE (Decoded.Imm_I);
            begin
               case Decoded.Funct3 is
                  when FUNCT3_ADD_SUB =>
                     Result := Add (Rs1_Val, Imm64);
                  when FUNCT3_SLT =>
                     Result := Set_Less_Than (Rs1_Val, Imm64);
                  when FUNCT3_SLTU =>
                     Result := Set_Less_Than_Unsigned (Rs1_Val, Imm64);
                  when FUNCT3_XOR =>
                     Result := Op_Xor (Rs1_Val, Imm64);
                  when FUNCT3_OR =>
                     Result := Op_Or (Rs1_Val, Imm64);
                  when FUNCT3_AND =>
                     Result := Op_And (Rs1_Val, Imm64);
                  when FUNCT3_SLL =>
                     --  Zbb unary ops share funct3=001, funct7=FUNCT7_ROL
                     if Decoded.Funct7 = FUNCT7_ROL then
                        case Word (Decoded.Rs2) is
                           when ZBB_CLZ_RS2   => Result := Crypto.CLZ64    (Rs1_Val);
                           when ZBB_CTZ_RS2   => Result := Crypto.CTZ64    (Rs1_Val);
                           when ZBB_CPOP_RS2  => Result := Crypto.CPOP64   (Rs1_Val);
                           when ZBB_SEXTB_RS2 => Result := Crypto.SEXT_B64 (Rs1_Val);
                           when ZBB_SEXTH_RS2 => Result := Crypto.SEXT_H64 (Rs1_Val);
                           when others        => Result := Shift_Left_Logical (Rs1_Val, Shamt);
                        end case;
                     else
                        --  SLLI: shift amount in lower 6 bits of imm
                        Result := Shift_Left_Logical (Rs1_Val, Shamt);
                     end if;
                  when FUNCT3_SRL_SRA =>
                     --  REV8 (RV64): funct7=0110101, rs2=11000
                     if Decoded.Funct7 = FUNCT7_REV8_64 and
                           Word (Decoded.Rs2) = 16#18#
                     then
                        Result := Crypto.REV8_64 (Rs1_Val);
                     --  ORC.B: funct7=0010100, rs2=00111
                     elsif Decoded.Funct7 = FUNCT7_ORC_B and
                           Word (Decoded.Rs2) = ZBB_ORCB_RS2
                     then
                        Result := Crypto.ORC_B64 (Rs1_Val);
                     --  RORI: 6-bit shamt, funct6=011000 (low funct7 bit is
                     --  shamt[5], so mask it off before comparing)
                     elsif (Decoded.Funct7 and 2#1111110#) = FUNCT7_ROR then
                        Result := Crypto.RORI64 (Rs1_Val, Shamt);
                     --  Check bit 30 of instruction to distinguish SRLI vs SRAI
                     elsif (Instruction and Shift_Left (1, 30)) /= 0 then
                        Result := Shift_Right_Arithmetic (Rs1_Val, Shamt);
                     else
                        Result := Shift_Right_Logical (Rs1_Val, Shamt);
                     end if;
                  when others =>
                     CPU.Exception_Code := Illegal_Instruction;
                     Trap_Entry (CPU,
                                 Double_Word (CSR.CAUSE_ILLEGAL_INSN),
                                 Double_Word (Instruction));
                     return;
               end case;
            end;

            Write_Register (CPU, Decoded.Rd, Result);

         ----------------------------------------
         -- OP-IMM-32 (I-type W ops, RV64 only)
         ----------------------------------------
         when OPCODE_OP_IMM_32 =>
            declare
               --  5-bit shamt for W-suffix shift operations
               Shamt5 : constant Natural :=
                  Natural (To_Word (Decoded.Imm_I) and 16#1F#);
            begin
               case Decoded.Funct3 is
                  when FUNCT3_ADD_SUB =>
                     --  ADDIW: rd = sign_extend32(rs1[31:0] + imm)
                     Result := SE32 (Word (Rs1_Val and 16#FFFF_FFFF#) +
                                     Word (SE (Decoded.Imm_I) and 16#FFFF_FFFF#));
                  when FUNCT3_SLL =>
                     --  Zbb W-variants: CLZW/CTZW/CPOPW use funct7=FUNCT7_ROL.
                     --  Zba SLLI.UW uses funct6=000010 (funct7 & ~1 = FUNCT7_PACK)
                     --  and a 6-bit shamt (result is full 64-bit, NOT truncated).
                     if (Decoded.Funct7 and 2#1111110#) = FUNCT7_PACK then
                        --  SLLI.UW: rd = zero_extend32(rs1[31:0]) << shamt6
                        Result := Shift_Left_Logical
                           (Rs1_Val and 16#FFFF_FFFF#,
                            Natural (To_Word (Decoded.Imm_I) and 16#3F#));
                     elsif Decoded.Funct7 = FUNCT7_ROL then
                        case Word (Decoded.Rs2) is
                           when ZBB_CLZ_RS2  => Result := Crypto.CLZW  (Rs1_Val);
                           when ZBB_CTZ_RS2  => Result := Crypto.CTZW  (Rs1_Val);
                           when ZBB_CPOP_RS2 => Result := Crypto.CPOPW (Rs1_Val);
                           when others       => Result := Sllw (Rs1_Val, Shamt5);
                        end case;
                     else
                        --  SLLIW: rd = sign_extend32(rs1[31:0] << shamt5)
                        Result := Sllw (Rs1_Val, Shamt5);
                     end if;
                  when FUNCT3_SRL_SRA =>
                     if Decoded.Funct7 = FUNCT7_ROR then
                        --  RORIW: rotate-right of lower 32 bits, sign-extended
                        Result := Crypto.RORW (Rs1_Val, Double_Word (Shamt5));
                     elsif (Instruction and Shift_Left (1, 30)) /= 0 then
                        --  SRAIW: arithmetic right shift of lower 32 bits
                        Result := Sraw (Rs1_Val, Shamt5);
                     else
                        --  SRLIW: logical right shift of lower 32 bits
                        Result := Srlw (Rs1_Val, Shamt5);
                     end if;
                  when others =>
                     CPU.Exception_Code := Illegal_Instruction;
                     Trap_Entry (CPU,
                                 Double_Word (CSR.CAUSE_ILLEGAL_INSN),
                                 Double_Word (Instruction));
                     return;
               end case;
            end;

            Write_Register (CPU, Decoded.Rd, Result);

         -------------------------
         -- OP (R-type ALU ops)
         -------------------------
         when OPCODE_OP =>
            declare
               --  6-bit shamt in RV64 register-register shifts
               Shamt6 : constant Natural :=
                  Natural (Rs2_Val and 16#3F#);
            begin
               if Decoded.Funct7 = FUNCT7_MULDIV then
                  --  M extension (64-bit)
                  case Decoded.Funct3 is
                     when FUNCT3_MUL =>
                        Result := Mul (Rs1_Val, Rs2_Val);
                     when FUNCT3_MULH =>
                        Result := Mulh (Rs1_Val, Rs2_Val);
                     when FUNCT3_MULHSU =>
                        Result := Mulhsu (Rs1_Val, Rs2_Val);
                     when FUNCT3_MULHU =>
                        Result := Mulhu (Rs1_Val, Rs2_Val);
                     when FUNCT3_DIV =>
                        Result := Div (Rs1_Val, Rs2_Val);
                     when FUNCT3_DIVU =>
                        Result := Divu (Rs1_Val, Rs2_Val);
                     when FUNCT3_REM =>
                        Result := Op_Rem (Rs1_Val, Rs2_Val);
                     when FUNCT3_REMU =>
                        Result := Remu (Rs1_Val, Rs2_Val);
                     when others =>
                        CPU.Exception_Code := Illegal_Instruction;
                        Trap_Entry (CPU,
                                    Double_Word (CSR.CAUSE_ILLEGAL_INSN),
                                    Double_Word (Instruction));
                        return;
                  end case;
               elsif Decoded.Funct7 = FUNCT7_ZBA then
                  --  Zba: sh1add / sh2add / sh3add (64-bit)
                  case Decoded.Funct3 is
                     when FUNCT3_SLT =>
                        --  sh1add rd, rs1, rs2: rd = rs2 + (rs1 << 1)
                        Result := Add (Shift_Left_Logical (Rs1_Val, 1), Rs2_Val);
                     when FUNCT3_XOR =>
                        --  sh2add rd, rs1, rs2: rd = rs2 + (rs1 << 2)
                        Result := Add (Shift_Left_Logical (Rs1_Val, 2), Rs2_Val);
                     when FUNCT3_OR =>
                        --  sh3add rd, rs1, rs2: rd = rs2 + (rs1 << 3)
                        Result := Add (Shift_Left_Logical (Rs1_Val, 3), Rs2_Val);
                     when others =>
                        CPU.Exception_Code := Illegal_Instruction;
                        Trap_Entry (CPU,
                                    Double_Word (CSR.CAUSE_ILLEGAL_INSN),
                                    Double_Word (Instruction));
                        return;
                  end case;
               else
                  --  Base RV64I (with Zbb register-register ops interleaved:
                  --  they share funct3 values with base ops and are selected
                  --  by funct7 -- FUNCT7_ANDN/ORN=0x20, FUNCT7_MINMAX=0x05,
                  --  FUNCT7_ROL/ROR=0x30).
                  case Decoded.Funct3 is
                     when FUNCT3_ADD_SUB =>
                        if Decoded.Funct7 = FUNCT7_ALT then
                           Result := Sub (Rs1_Val, Rs2_Val);
                        else
                           Result := Add (Rs1_Val, Rs2_Val);
                        end if;
                     when FUNCT3_SLL =>
                        if Decoded.Funct7 = FUNCT7_ROL then
                           Result := Crypto.ROL64 (Rs1_Val, Rs2_Val);
                        else
                           Result := Shift_Left_Logical (Rs1_Val, Shamt6);
                        end if;
                     when FUNCT3_SLT =>
                        Result := Set_Less_Than (Rs1_Val, Rs2_Val);
                     when FUNCT3_SLTU =>
                        Result := Set_Less_Than_Unsigned (Rs1_Val, Rs2_Val);
                     when FUNCT3_XOR =>
                        if Decoded.Funct7 = FUNCT7_ANDN then
                           Result := Crypto.XNOR64 (Rs1_Val, Rs2_Val);
                        elsif Decoded.Funct7 = FUNCT7_MINMAX then
                           Result := Crypto.ZBB_MIN64 (Rs1_Val, Rs2_Val);
                        else
                           Result := Op_Xor (Rs1_Val, Rs2_Val);
                        end if;
                     when FUNCT3_SRL_SRA =>
                        if Decoded.Funct7 = FUNCT7_ZICOND then
                           --  czero.eqz: rd = (rs2 == 0) ? 0 : rs1
                           Result :=
                              (if Rs2_Val = 0 then 0 else Rs1_Val);
                        elsif Decoded.Funct7 = FUNCT7_ROR then
                           Result := Crypto.ROR64 (Rs1_Val, Rs2_Val);
                        elsif Decoded.Funct7 = FUNCT7_MINMAX then
                           Result := Crypto.ZBB_MINU64 (Rs1_Val, Rs2_Val);
                        elsif Decoded.Funct7 = FUNCT7_ALT then
                           Result := Shift_Right_Arithmetic (Rs1_Val, Shamt6);
                        else
                           Result := Shift_Right_Logical (Rs1_Val, Shamt6);
                        end if;
                     when FUNCT3_OR =>
                        if Decoded.Funct7 = FUNCT7_ORN then
                           Result := Crypto.ORN64 (Rs1_Val, Rs2_Val);
                        elsif Decoded.Funct7 = FUNCT7_MINMAX then
                           Result := Crypto.ZBB_MAX64 (Rs1_Val, Rs2_Val);
                        else
                           Result := Op_Or (Rs1_Val, Rs2_Val);
                        end if;
                     when FUNCT3_AND =>
                        if Decoded.Funct7 = FUNCT7_ZICOND then
                           --  czero.nez: rd = (rs2 != 0) ? 0 : rs1
                           Result :=
                              (if Rs2_Val /= 0 then 0 else Rs1_Val);
                        elsif Decoded.Funct7 = FUNCT7_ANDN then
                           Result := Crypto.ANDN64 (Rs1_Val, Rs2_Val);
                        elsif Decoded.Funct7 = FUNCT7_MINMAX then
                           Result := Crypto.ZBB_MAXU64 (Rs1_Val, Rs2_Val);
                        else
                           Result := Op_And (Rs1_Val, Rs2_Val);
                        end if;
                     when others =>
                        CPU.Exception_Code := Illegal_Instruction;
                        Trap_Entry (CPU,
                                    Double_Word (CSR.CAUSE_ILLEGAL_INSN),
                                    Double_Word (Instruction));
                        return;
                  end case;
               end if;
            end;

            Write_Register (CPU, Decoded.Rd, Result);

         ----------------------------------
         -- OP-32 (R-type W ops, RV64 only)
         ----------------------------------
         when OPCODE_OP_32 =>
            declare
               Shamt5 : constant Natural := Natural (Rs2_Val and 16#1F#);
            begin
               if Decoded.Funct7 = FUNCT7_MULDIV then
                  --  RV64M W-suffix multiply/divide
                  case Decoded.Funct3 is
                     when FUNCT3_MUL =>
                        Result := Mulw (Rs1_Val, Rs2_Val);
                     when FUNCT3_DIV =>
                        Result := Divw (Rs1_Val, Rs2_Val);
                     when FUNCT3_DIVU =>
                        Result := Divuw (Rs1_Val, Rs2_Val);
                     when FUNCT3_REM =>
                        Result := Remw (Rs1_Val, Rs2_Val);
                     when FUNCT3_REMU =>
                        Result := Remuw (Rs1_Val, Rs2_Val);
                     when others =>
                        CPU.Exception_Code := Illegal_Instruction;
                        Trap_Entry (CPU,
                                    Double_Word (CSR.CAUSE_ILLEGAL_INSN),
                                    Double_Word (Instruction));
                        return;
                  end case;
               elsif Decoded.Funct7 = FUNCT7_ROL then
                  --  Zbb W-rotates: ROLW (funct3=001) / RORW (funct3=101)
                  case Decoded.Funct3 is
                     when FUNCT3_SLL =>
                        Result := Crypto.ROLW (Rs1_Val, Rs2_Val);
                     when FUNCT3_SRL_SRA =>
                        Result := Crypto.RORW (Rs1_Val, Rs2_Val);
                     when others =>
                        CPU.Exception_Code := Illegal_Instruction;
                        Trap_Entry (CPU,
                                    Double_Word (CSR.CAUSE_ILLEGAL_INSN),
                                    Double_Word (Instruction));
                        return;
                  end case;
               elsif Decoded.Funct7 = FUNCT7_PACK and
                     Word (Decoded.Rs2) = 0 and
                     Decoded.Funct3 = FUNCT3_XOR
               then
                  --  ZEXT.H (RV64): OP-32, funct7=FUNCT7_PACK, funct3=100, rs2=0
                  Result := Crypto.ZEXT_H64 (Rs1_Val);
               elsif Decoded.Funct7 = FUNCT7_PACK and
                     Decoded.Funct3 = FUNCT3_ADD_SUB
               then
                  --  add.uw: rd = rs2 + zero_extend(rs1[31:0])
                  Result := Add (Rs1_Val and 16#FFFF_FFFF#, Rs2_Val);
               elsif Decoded.Funct7 = FUNCT7_ZBA then
                  --  Zba .UW variants: zero-extend lower 32 bits of rs1
                  declare
                     Rs1_Zext : constant Double_Word :=
                        Rs1_Val and 16#FFFF_FFFF#;
                  begin
                     case Decoded.Funct3 is
                        when FUNCT3_SLT =>
                           --  sh1add.uw: rd = rs2 + (zext(rs1[31:0]) << 1)
                           Result :=
                              Add (Shift_Left_Logical (Rs1_Zext, 1), Rs2_Val);
                        when FUNCT3_XOR =>
                           --  sh2add.uw: rd = rs2 + (zext(rs1[31:0]) << 2)
                           Result :=
                              Add (Shift_Left_Logical (Rs1_Zext, 2), Rs2_Val);
                        when FUNCT3_OR =>
                           --  sh3add.uw: rd = rs2 + (zext(rs1[31:0]) << 3)
                           Result :=
                              Add (Shift_Left_Logical (Rs1_Zext, 3), Rs2_Val);
                        when others =>
                           CPU.Exception_Code := Illegal_Instruction;
                           Trap_Entry (CPU,
                                       Double_Word (CSR.CAUSE_ILLEGAL_INSN),
                                       Double_Word (Instruction));
                           return;
                     end case;
                  end;
               elsif Decoded.Funct7 = FUNCT7_ALT then
                  --  SUBW / SRAW
                  case Decoded.Funct3 is
                     when FUNCT3_ADD_SUB =>
                        Result := Subw (Rs1_Val, Rs2_Val);
                     when FUNCT3_SRL_SRA =>
                        Result := Sraw (Rs1_Val, Shamt5);
                     when others =>
                        CPU.Exception_Code := Illegal_Instruction;
                        Trap_Entry (CPU,
                                    Double_Word (CSR.CAUSE_ILLEGAL_INSN),
                                    Double_Word (Instruction));
                        return;
                  end case;
               else
                  --  ADDW / SLLW / SRLW (funct7=0)
                  case Decoded.Funct3 is
                     when FUNCT3_ADD_SUB =>
                        Result := Addw (Rs1_Val, Rs2_Val);
                     when FUNCT3_SLL =>
                        Result := Sllw (Rs1_Val, Shamt5);
                     when FUNCT3_SRL_SRA =>
                        Result := Srlw (Rs1_Val, Shamt5);
                     when others =>
                        CPU.Exception_Code := Illegal_Instruction;
                        Trap_Entry (CPU,
                                    Double_Word (CSR.CAUSE_ILLEGAL_INSN),
                                    Double_Word (Instruction));
                        return;
                  end case;
               end if;
            end;

            Write_Register (CPU, Decoded.Rd, Result);

         ----------------------
         -- SYSTEM (I-type)
         ----------------------
         when OPCODE_SYSTEM =>
            if Decoded.Funct3 = FUNCT3_ECALL_EBREAK then
               if Instruction = 16#30200073# then
                  --  MRET
                  if CPU.Priv_Mode /= Machine then
                     CPU.Exception_Code := Illegal_Instruction;
                     Trap_Entry (CPU,
                                 Double_Word (CSR.CAUSE_ILLEGAL_INSN),
                                 Double_Word (Instruction));
                     CSR64.Increment_Instret (CPU.CSRs);
                     CSR64.Increment_Mcycle (CPU.CSRs);
                     return;
                  end if;
                  Mret (CPU);
                  CSR64.Increment_Instret (CPU.CSRs);
                  CSR64.Increment_Mcycle (CPU.CSRs);
                  return;
               elsif Instruction = 16#10200073# then
                  --  SRET
                  if CPU.Priv_Mode = User then
                     CPU.Exception_Code := Illegal_Instruction;
                     Trap_Entry (CPU,
                                 Double_Word (CSR.CAUSE_ILLEGAL_INSN),
                                 Double_Word (Instruction));
                     CSR64.Increment_Instret (CPU.CSRs);
                     CSR64.Increment_Mcycle (CPU.CSRs);
                     return;
                  end if;
                  --  mstatus.TSR lets M-mode firmware intercept supervisor
                  --  trap returns; with it set, SRET from S-mode is illegal.
                  if CPU.Priv_Mode = Supervisor and then
                     (CSR64.Read (CPU.CSRs, CSR.CSR_MSTATUS)
                      and CSR64.MSTATUS_TSR) /= 0
                  then
                     CPU.Exception_Code := Illegal_Instruction;
                     Trap_Entry (CPU,
                                 Double_Word (CSR.CAUSE_ILLEGAL_INSN),
                                 Double_Word (Instruction));
                     CSR64.Increment_Instret (CPU.CSRs);
                     CSR64.Increment_Mcycle (CPU.CSRs);
                     return;
                  end if;
                  Sret (CPU);
                  CSR64.Increment_Instret (CPU.CSRs);
                  CSR64.Increment_Mcycle (CPU.CSRs);
                  return;
               elsif Instruction = 16#10500073# then
                  --  WFI: treat as NOP, but mstatus.TW makes it illegal
                  --  outside M-mode so firmware can police idling guests.
                  if CPU.Priv_Mode /= Machine and then
                     (CSR64.Read (CPU.CSRs, CSR.CSR_MSTATUS)
                      and CSR64.MSTATUS_TW) /= 0
                  then
                     CPU.Exception_Code := Illegal_Instruction;
                     Trap_Entry (CPU,
                                 Double_Word (CSR.CAUSE_ILLEGAL_INSN),
                                 Double_Word (Instruction));
                     CSR64.Increment_Instret (CPU.CSRs);
                     CSR64.Increment_Mcycle (CPU.CSRs);
                     return;
                  end if;
                  null;
               elsif (Instruction and 16#FE007FFF#) = 16#12000073# then
                  --  SFENCE.VMA: flush TLB, unless mstatus.TVM traps it so a
                  --  hypervisor can shadow the guest's page tables.
                  if CPU.Priv_Mode = Supervisor and then
                     (CSR64.Read (CPU.CSRs, CSR.CSR_MSTATUS)
                      and CSR64.MSTATUS_TVM) /= 0
                  then
                     CPU.Exception_Code := Illegal_Instruction;
                     Trap_Entry (CPU,
                                 Double_Word (CSR.CAUSE_ILLEGAL_INSN),
                                 Double_Word (Instruction));
                     CSR64.Increment_Instret (CPU.CSRs);
                     CSR64.Increment_Mcycle (CPU.CSRs);
                     return;
                  end if;
                  MMU.Flush_TLB (CPU.MMU);
               elsif Decoded.Imm_I = 0 then
                  --  ECALL
                  declare
                     use RISCV.Memory;
                     Syscall_Num  : constant Double_Word := Read_Register (CPU, 17);
                     A0_Val       : constant Double_Word := Read_Register (CPU, 10);
                     A1_Val       : constant Double_Word := Read_Register (CPU, 11);
                     Is_Host_Call : Boolean := False;

                     function Img (N : Natural) return String is
                        S : constant String := Natural'Image (N);
                     begin
                        return S (S'First + 1 .. S'Last);
                     end Img;

                  begin
                     case Syscall_Num is

                        when 16#500# =>
                           --  HOST_LOG_OPEN
                           declare
                              Len  : constant Natural :=
                                 (if A1_Val > 255 then 255
                                  else Natural (A1_Val));
                              Name : String (1 .. Len);
                           begin
                              for I in 1 .. Len loop
                                 Name (I) := Character'Val
                                    (Memory.Read_Byte
                                       (Mem,
                                        Memory_Address (A0_Val) +
                                        Memory_Address (I - 1)));
                              end loop;
                              --  The log name comes from the guest, so it
                              --  is confined like any other host path:
                              --  relative, and with no ".." escape.
                              if Mem.Host_IO = Memory.Off
                                or else not Memory.Valid_Host_Name (Name)
                              then
                                 Write_Register (CPU, 10, Double_Word'Last);
                              else
                                 if Mem.Log_File_Open then
                                    Close (Mem.Log_File.all);
                                    Mem.Log_File_Open := False;
                                 end if;
                                 if Mem.Log_File = null then
                                    Mem.Log_File :=
                                       new Ada.Text_IO.File_Type;
                                 end if;
                                 if Mem.Log_Dir_Len > 0 then
                                    declare
                                       Dir  : constant String :=
                                          Mem.Log_Dir (1 .. Mem.Log_Dir_Len);
                                       Path : constant String :=
                                          Dir & "/" & Name;
                                    begin
                                       if not Ada.Directories.Exists (Dir) then
                                          Ada.Directories.Create_Path (Dir);
                                       end if;
                                       Create (Mem.Log_File.all,
                                               Out_File, Path);
                                    end;
                                 else
                                    Create (Mem.Log_File.all, Out_File, Name);
                                 end if;
                                 Mem.Log_File_Open := True;
                                 Write_Register (CPU, 10, 0);
                              end if;
                           exception
                              when others =>
                                 Mem.Log_File_Open := False;
                                 Write_Register (CPU, 10, Double_Word'Last);
                           end;
                           Is_Host_Call := True;

                        when 16#501# =>
                           --  HOST_LOG_WRITE
                           if Mem.Log_File_Open then
                              declare
                                 --  a1 is guest-controlled.  Cap it so a
                                 --  bad value cannot hang the emulator in a
                                 --  billion-iteration loop, nor overflow the
                                 --  conversion to Natural.
                                 Max_Log_Write : constant := 16#10_0000#;
                                 Len : constant Natural :=
                                    (if A1_Val > Max_Log_Write
                                     then Max_Log_Write
                                     else Natural (A1_Val));
                              begin
                                 for I in 0 .. Len - 1 loop
                                    Put (Mem.Log_File.all,
                                         Character'Val
                                           (Memory.Read_Byte
                                              (Mem,
                                               Memory_Address (A0_Val) +
                                               Memory_Address (I))));
                                 end loop;
                                 --  Report what was actually written.
                                 Write_Register (CPU, 10, Double_Word (Len));
                              end;
                           else
                              Write_Register (CPU, 10, 0);
                           end if;
                           Is_Host_Call := True;

                        when 16#502# =>
                           --  HOST_LOG_CLOSE
                           if Mem.Log_File_Open then
                              Close (Mem.Log_File.all);
                              Mem.Log_File_Open := False;
                           end if;
                           Write_Register (CPU, 10, 0);
                           Is_Host_Call := True;

                        when 16#503# =>
                           --  HOST_LOG_REGS
                           if Mem.Log_File_Open then
                              Put_Line (Mem.Log_File.all,
                                 "=== Register Dump (PC=0x" &
                                 To_Hex64 (Double_Word (CPU.PC)) & ") ===");
                              for R in Register_Index loop
                                 Put_Line (Mem.Log_File.all,
                                    "  x" &
                                    (if R < 10 then "0" else "") &
                                    Img (Natural (R)) &
                                    " = 0x" &
                                    To_Hex64 (CPU.Registers (R)));
                              end loop;
                              Put_Line (Mem.Log_File.all, "");
                           end if;
                           Write_Register (CPU, 10, 0);
                           Is_Host_Call := True;

                        when 16#504# =>
                           --  HOST_GET_TIME_MS
                           declare
                              T    : constant Ada.Calendar.Time :=
                                        Ada.Calendar.Clock;
                              Secs : constant Duration :=
                                        Ada.Calendar.Seconds (T);
                              Ms   : constant Double_Word :=
                                        Double_Word (Float (Secs) * 1000.0);
                           begin
                              Write_Register (CPU, 10, Ms);
                           end;
                           Is_Host_Call := True;

                        when 16#505# =>
                           --  HOST_FILE_OPEN: a0=path_ptr, a1=path_len, a2=mode -> handle or -1
                           declare
                              use Ada.Streams.Stream_IO;
                              A2_Val   : constant Double_Word :=
                                 Read_Register (CPU, 12);
                              Path_Len : constant Natural :=
                                 (if A1_Val > 511 then 511
                                  else Natural (A1_Val));
                              Path   : String (1 .. Path_Len);
                              Handle : Integer := -1;
                           begin
                              for I in 1 .. Path_Len loop
                                 Path (I) := Character'Val
                                    (Memory.Read_Byte
                                       (Mem,
                                        Memory_Address (A0_Val) +
                                        Memory_Address (I - 1)));
                              end loop;
                              for H in Memory.SH_File_Index loop
                                 if not Mem.SH_File_Open (H) then
                                    Handle := Integer (H);
                                    exit;
                                 end if;
                              end loop;
                              --  Confine the guest-supplied path to the
                              --  host I/O root before touching the host
                              --  filesystem, and honour the access mode.
                              declare
                                 Host_Path : String
                                    (1 .. Memory.Max_Host_Path +
                                          Memory.Max_Host_Root + 1);
                                 Host_Len  : Natural;
                                 Permitted : Boolean;
                              begin
                                 Memory.Resolve_Host_Path
                                   (Mem, Path,
                                    Writing  => A2_Val = 1 or A2_Val = 2,
                                    Full     => Host_Path,
                                    Full_Len => Host_Len,
                                    Allowed  => Permitted);
                                 if not Permitted then
                                    Handle := -1;
                                 end if;

                                 if Handle >= 0 then
                                    declare
                                       H : constant Memory.SH_File_Index :=
                                          Memory.SH_File_Index (Handle);
                                       P : constant String :=
                                          Host_Path (1 .. Host_Len);
                                    begin
                                       if Mem.SH_Files (H) = null then
                                          Mem.SH_Files (H) :=
                                             new Ada.Streams.Stream_IO
                                                    .File_Type;
                                       end if;
                                       case A2_Val is
                                          when 1 =>
                                             Create (Mem.SH_Files (H).all,
                                                     Out_File, P);
                                          when 2 =>
                                             Open (Mem.SH_Files (H).all,
                                                   Append_File, P);
                                          when others =>
                                             Open (Mem.SH_Files (H).all,
                                                   In_File, P);
                                       end case;
                                       Mem.SH_File_Open (H) := True;
                                       Write_Register
                                         (CPU, 10, Double_Word (Handle));
                                    exception
                                       when others =>
                                          Write_Register
                                            (CPU, 10, Double_Word'Last);
                                    end;
                                 else
                                    Write_Register (CPU, 10, Double_Word'Last);
                                 end if;
                              end;
                           end;
                           Is_Host_Call := True;

                        when 16#506# =>
                           --  HOST_FILE_READ: a0=handle, a1=buf_ptr, a2=count -> bytes_read
                           declare
                              use Ada.Streams;
                              use Ada.Streams.Stream_IO;
                              A2_Val      : constant Double_Word :=
                                 Read_Register (CPU, 12);
                              H_Raw       : constant Double_Word := A0_Val;
                              Buf_Addr    : constant Memory_Address :=
                                 Memory_Address (A1_Val);
                              Total_Count : constant Natural :=
                                 Natural (A2_Val);
                              Total_Read  : Natural := 0;
                           begin
                              if H_Raw < Double_Word (Memory.Max_SH_Files)
                                 and then Mem.SH_File_Open
                                    (Memory.SH_File_Index (H_Raw))
                              then
                                 declare
                                    F : Ada.Streams.Stream_IO.File_Type
                                       renames Mem.SH_Files
                                          (Memory.SH_File_Index (H_Raw)).all;
                                    Chunk  : Stream_Element_Array (1 .. 4096);
                                    Last   : Stream_Element_Offset;
                                    Remain : Natural := Total_Count;
                                 begin
                                    while Remain > 0 loop
                                       declare
                                          This : constant Stream_Element_Offset
                                             := Stream_Element_Offset
                                                (Natural'Min (Remain, 4096));
                                       begin
                                          Read (F, Chunk (1 .. This), Last);
                                          for I in 1 .. Last loop
                                             Memory.Write_Byte
                                                (Mem,
                                                 Buf_Addr +
                                                 Memory_Address (Total_Read),
                                                 Byte (Chunk (I)));
                                             Total_Read := Total_Read + 1;
                                          end loop;
                                          Remain := Remain - Natural (Last);
                                          if Last < This then exit; end if;
                                       exception
                                          when Ada.Streams.Stream_IO.End_Error =>
                                             exit;
                                       end;
                                    end loop;
                                 end;
                                 Write_Register
                                   (CPU, 10, Double_Word (Total_Read));
                              else
                                 Write_Register (CPU, 10, Double_Word'Last);
                              end if;
                           end;
                           Is_Host_Call := True;

                        when 16#507# =>
                           --  HOST_FILE_WRITE: a0=handle, a1=buf_ptr, a2=count -> bytes_written
                           declare
                              use Ada.Streams;
                              use Ada.Streams.Stream_IO;
                              A2_Val   : constant Double_Word :=
                                 Read_Register (CPU, 12);
                              H_Raw    : constant Double_Word := A0_Val;
                              Buf_Addr : constant Memory_Address :=
                                 Memory_Address (A1_Val);
                              Count    : constant Natural := Natural (A2_Val);
                              Written  : Natural := 0;
                           begin
                              if H_Raw < Double_Word (Memory.Max_SH_Files)
                                 and then Mem.SH_File_Open
                                    (Memory.SH_File_Index (H_Raw))
                              then
                                 declare
                                    F : Ada.Streams.Stream_IO.File_Type
                                       renames Mem.SH_Files
                                          (Memory.SH_File_Index (H_Raw)).all;
                                    Chunk  : Stream_Element_Array (1 .. 4096);
                                    Remain : Natural := Count;
                                 begin
                                    while Remain > 0 loop
                                       declare
                                          This : constant Natural :=
                                             Natural'Min (Remain, 4096);
                                       begin
                                          for I in 1 .. This loop
                                             Chunk (Stream_Element_Offset (I))
                                                := Stream_Element
                                                   (Memory.Read_Byte
                                                      (Mem,
                                                       Buf_Addr +
                                                       Memory_Address
                                                          (Written + I - 1)));
                                          end loop;
                                          Write (F, Chunk
                                             (1 .. Stream_Element_Offset
                                                      (This)));
                                          Written := Written + This;
                                          Remain  := Remain - This;
                                       end;
                                    end loop;
                                    Write_Register
                                      (CPU, 10, Double_Word (Written));
                                 exception
                                    when others =>
                                       Write_Register
                                         (CPU, 10, Double_Word'Last);
                                 end;
                              else
                                 Write_Register (CPU, 10, Double_Word'Last);
                              end if;
                           end;
                           Is_Host_Call := True;

                        when 16#508# =>
                           --  HOST_FILE_CLOSE: a0=handle -> 0
                           declare
                              use Ada.Streams.Stream_IO;
                              H_Raw : constant Double_Word := A0_Val;
                           begin
                              if H_Raw < Double_Word (Memory.Max_SH_Files)
                                 and then Mem.SH_File_Open
                                    (Memory.SH_File_Index (H_Raw))
                              then
                                 Close (Mem.SH_Files
                                    (Memory.SH_File_Index (H_Raw)).all);
                                 Mem.SH_File_Open
                                    (Memory.SH_File_Index (H_Raw)) := False;
                              end if;
                              Write_Register (CPU, 10, 0);
                           end;
                           Is_Host_Call := True;

                        when 16#509# =>
                           --  HOST_FILE_SEEK: a0=handle, a1=offset(signed), a2=whence -> 0/-1
                           declare
                              use Ada.Streams.Stream_IO;
                              function To_S64 is new Ada.Unchecked_Conversion
                                 (Double_Word, Long_Long_Integer);
                              A2_Val : constant Double_Word :=
                                 Read_Register (CPU, 12);
                              H_Raw  : constant Double_Word  := A0_Val;
                              Offset : constant Long_Long_Integer :=
                                 To_S64 (A1_Val);
                              Whence : constant Natural := Natural (A2_Val);
                           begin
                              if H_Raw < Double_Word (Memory.Max_SH_Files)
                                 and then Mem.SH_File_Open
                                    (Memory.SH_File_Index (H_Raw))
                              then
                                 declare
                                    F : Ada.Streams.Stream_IO.File_Type
                                       renames Mem.SH_Files
                                          (Memory.SH_File_Index (H_Raw)).all;
                                    New_Pos : Long_Long_Integer;
                                 begin
                                    case Whence is
                                       when 1 =>
                                          New_Pos :=
                                             Long_Long_Integer (Index (F)) +
                                             Offset;
                                       when 2 =>
                                          New_Pos :=
                                             Long_Long_Integer (Size (F)) +
                                             Offset + 1;
                                       when others =>
                                          New_Pos := Offset + 1;
                                    end case;
                                    if New_Pos < 1 then
                                       New_Pos := 1;
                                    end if;
                                    Set_Index (F,
                                       Ada.Streams.Stream_IO.Positive_Count
                                          (New_Pos));
                                    Write_Register (CPU, 10, 0);
                                 exception
                                    when others =>
                                       Write_Register
                                         (CPU, 10, Double_Word'Last);
                                 end;
                              else
                                 Write_Register (CPU, 10, Double_Word'Last);
                              end if;
                           end;
                           Is_Host_Call := True;

                        when 16#50A# =>
                           --  HOST_FILE_TELL: a0=handle -> 0-based position or -1
                           declare
                              use Ada.Streams.Stream_IO;
                              H_Raw : constant Double_Word := A0_Val;
                           begin
                              if H_Raw < Double_Word (Memory.Max_SH_Files)
                                 and then Mem.SH_File_Open
                                    (Memory.SH_File_Index (H_Raw))
                              then
                                 Write_Register
                                   (CPU, 10,
                                    Double_Word (Index (Mem.SH_Files
                                       (Memory.SH_File_Index (H_Raw)).all))
                                    - 1);
                              else
                                 Write_Register (CPU, 10, Double_Word'Last);
                              end if;
                           end;
                           Is_Host_Call := True;

                        when 16#50B# =>
                           --  HOST_FILE_SIZE: a0=handle -> size or -1
                           declare
                              use Ada.Streams.Stream_IO;
                              H_Raw : constant Double_Word := A0_Val;
                           begin
                              if H_Raw < Double_Word (Memory.Max_SH_Files)
                                 and then Mem.SH_File_Open
                                    (Memory.SH_File_Index (H_Raw))
                              then
                                 Write_Register
                                   (CPU, 10,
                                    Double_Word (Size (Mem.SH_Files
                                       (Memory.SH_File_Index (H_Raw)).all)));
                              else
                                 Write_Register (CPU, 10, Double_Word'Last);
                              end if;
                           end;
                           Is_Host_Call := True;

                        when 16#50C# =>
                           --  HOST_FB_DRAW: a0=buf_ptr (320x200 ARGB32), a1=frame_no
                           declare
                              use Ada.Streams;
                              use Ada.Streams.Stream_IO;
                              Frame_No : constant Double_Word := A1_Val;
                              FB_Addr  : constant Memory_Address :=
                                 Memory_Address (A0_Val);

                              function Frame_Name return String is
                                 N   : Natural :=
                                    Natural (Frame_No mod 1_000_000);
                                 Dig : String (1 .. 6);
                              begin
                                 for I in reverse 1 .. 6 loop
                                    Dig (I) := Character'Val
                                       (Character'Pos ('0') + N mod 10);
                                    N := N / 10;
                                 end loop;
                                 return "doom_frame_" & Dig & ".ppm";
                              end Frame_Name;

                              PPM : Ada.Streams.Stream_IO.File_Type;
                              Hdr : constant String :=
                                 "P6" & ASCII.LF &
                                 "320 200" & ASCII.LF &
                                 "255" & ASCII.LF;
                           begin
                              Create (PPM, Out_File, Frame_Name);
                              declare
                                 H_Bytes : Stream_Element_Array
                                    (1 .. Stream_Element_Offset (Hdr'Length));
                              begin
                                 for I in Hdr'Range loop
                                    H_Bytes (Stream_Element_Offset
                                       (I - Hdr'First + 1)) :=
                                          Stream_Element
                                             (Character'Pos (Hdr (I)));
                                 end loop;
                                 Write (PPM, H_Bytes);
                              end;
                              for Chunk in 0 .. 499 loop
                                 declare
                                    RGB  : Stream_Element_Array (1 .. 384);
                                    Base : Stream_Element_Offset;
                                    P    : Word;
                                 begin
                                    for J in 0 .. 127 loop
                                       P := Memory.Read_Word
                                          (Mem,
                                           FB_Addr + Memory_Address
                                              ((Chunk * 128 + J) * 4));
                                       Base := Stream_Element_Offset
                                          (J * 3 + 1);
                                       RGB (Base)     := Stream_Element
                                          ((P / 16#10000#) and 16#FF#);
                                       RGB (Base + 1) := Stream_Element
                                          ((P / 16#100#) and 16#FF#);
                                       RGB (Base + 2) := Stream_Element
                                          (P and 16#FF#);
                                    end loop;
                                    Write (PPM, RGB);
                                 end;
                              end loop;
                              Close (PPM);
                              Write_Register (CPU, 10, 0);
                           exception
                              when others =>
                                 Write_Register (CPU, 10, Double_Word'Last);
                           end;
                           Is_Host_Call := True;

                        when 93 =>
                           --  exit(status). Under HTIF, let a7=93 ECALL trap
                           --  to the guest mtvec handler (writes tohost).
                           if not Mem.HTIF_Enabled then
                              CPU.Halted := True;
                              Is_Host_Call := True;
                           end if;

                        when others =>
                           null;

                     end case;

                     if Is_Host_Call then
                        CPU.PC := Next_PC;
                        CSR64.Increment_Instret (CPU.CSRs);
                        CSR64.Increment_Mcycle (CPU.CSRs);
                        return;
                     end if;

                     --  SBI shim: intercept supervisor-mode ECALLs
                     --  (disabled under HTIF for riscv-tests, and by
                     --  Mem.SBI_Enabled for tests of raw trap routing).
                     if CPU.Priv_Mode = Supervisor
                       and then Mem.SBI_Enabled
                       and then not Mem.HTIF_Enabled
                     then
                        declare
                           EID     : constant Double_Word := Syscall_Num;
                           FID     : constant Double_Word :=
                              Read_Register (CPU, 16);
                           SBI_Err : Double_Word := 0;
                           SBI_Val : Double_Word := 0;
                        begin
                           case EID is

                              when 0 =>
                                 --  Legacy sbi_set_timer: a0=lo, a1=hi
                                 declare
                                    Val : constant RISCV.CLINT.Timer_Value :=
                                       RISCV.CLINT.Timer_Value (A0_Val) or
                                       Shift_Left
                                         (RISCV.CLINT.Timer_Value (A1_Val),
                                          32);
                                    Mip : constant Double_Word :=
                                       CSR64.Read (CPU.CSRs, CSR64.CSR_MIP);
                                 begin
                                    if Mem.CLINT /= null then
                                       RISCV.CLINT.Set_Mtimecmp
                                         (Mem.CLINT.all, Val);
                                    end if;
                                    CSR64.Write (CPU.CSRs, CSR64.CSR_MIP,
                                                 Mip and not CSR64.MIE_STIE);
                                 end;

                              when 1 =>
                                 --  Legacy sbi_console_putchar
                                 if Mem.UART /= null then
                                    RISCV.UART.Write
                                      (Mem.UART.all,
                                       Mem.UART.Base_Address,
                                       Byte (A0_Val and 16#FF#));
                                 else
                                    Put (Character'Val
                                           (Integer (A0_Val) mod 128));
                                 end if;

                              when 2 =>
                                 --  Legacy sbi_console_getchar
                                 SBI_Err := Double_Word'Last;

                              when 8 =>
                                 --  Legacy sbi_shutdown
                                 CPU.Halted := True;

                              when 16#10# =>
                                 --  SBI Base extension
                                 case FID is
                                    when 0 =>
                                       SBI_Val := 16#0200_0000#;
                                    when 1 =>
                                       SBI_Val := 3;
                                    when 2 =>
                                       SBI_Val := 1;
                                    when 3 =>
                                       case A0_Val is
                                          when 0 | 1 | 2 | 8
                                             | 16#10#
                                             | 16#5449_4D45# =>
                                             SBI_Val := 1;
                                          when others =>
                                             SBI_Val := 0;
                                       end case;
                                    when 4 | 5 | 6 =>
                                       SBI_Val := 0;
                                    when others =>
                                       SBI_Err := Double_Word'Last;
                                 end case;

                              when 16#5449_4D45# =>
                                 --  TIMER extension
                                 if FID = 0 then
                                    declare
                                       Val : constant RISCV.CLINT.Timer_Value :=
                                          RISCV.CLINT.Timer_Value (A0_Val) or
                                          Shift_Left
                                            (RISCV.CLINT.Timer_Value (A1_Val),
                                             32);
                                       Mip : constant Double_Word :=
                                          CSR64.Read (CPU.CSRs, CSR64.CSR_MIP);
                                    begin
                                       if Mem.CLINT /= null then
                                          RISCV.CLINT.Set_Mtimecmp
                                            (Mem.CLINT.all, Val);
                                       end if;
                                       CSR64.Write (CPU.CSRs, CSR64.CSR_MIP,
                                                    Mip and not CSR64.MIE_STIE);
                                    end;
                                 else
                                    SBI_Err := Double_Word'Last;
                                 end if;

                              when others =>
                                 SBI_Err := Double_Word'Last;

                           end case;

                           Write_Register (CPU, 10, SBI_Err);
                           Write_Register (CPU, 11, SBI_Val);
                           CPU.PC := Next_PC;
                           CSR64.Increment_Instret (CPU.CSRs);
                           CSR64.Increment_Mcycle (CPU.CSRs);
                           return;
                        end;
                     end if;
                  end;

                  --  Normal ECALL
                  CPU.Exception_Code := Environment_Call;
                  declare
                     Cause : Double_Word;
                  begin
                     case CPU.Priv_Mode is
                        when User       => Cause := Double_Word (CSR.CAUSE_ECALL_U);
                        when Supervisor => Cause := Double_Word (CSR.CAUSE_ECALL_S);
                        when Machine    => Cause := Double_Word (CSR.CAUSE_ECALL_M);
                        when Reserved   => Cause := Double_Word (CSR.CAUSE_ECALL_M);
                     end case;
                     Trap_Entry (CPU, Cause);
                  end;
                  CSR64.Increment_Instret (CPU.CSRs);
                  CSR64.Increment_Mcycle (CPU.CSRs);
                  return;
               elsif Decoded.Imm_I = 1 then
                  --  EBREAK
                  CPU.Exception_Code := Breakpoint;
                  Trap_Entry (CPU,
                              Double_Word (CSR.CAUSE_BREAKPOINT),
                              Double_Word (CPU.PC));
                  CSR64.Increment_Instret (CPU.CSRs);
                  CSR64.Increment_Mcycle (CPU.CSRs);
                  return;
               else
                  CPU.Exception_Code := Illegal_Instruction;
                  Trap_Entry (CPU,
                              Double_Word (CSR.CAUSE_ILLEGAL_INSN),
                              Double_Word (Instruction));
                  CSR64.Increment_Instret (CPU.CSRs);
                  CSR64.Increment_Mcycle (CPU.CSRs);
                  return;
               end if;
            else
               --  Zicsr: CSR instructions
               declare
                  CSR_Addr  : constant CSR64.CSR_Address :=
                     CSR64.CSR_Address (Shift_Right (Instruction, 20) and 16#FFF#);
                  Old_Val   : Double_Word;
                  New_Val   : Double_Word;
                  Zimm      : constant Double_Word := Double_Word (Decoded.Rs1);
                  Write_CSR : Boolean := True;
               begin
                  --  Check privilege level for CSR access
                  if not CSR.Can_Access_CSR (CSR_Addr, CPU.Priv_Mode) then
                     CPU.Exception_Code := Illegal_Instruction;
                     Trap_Entry (CPU,
                                 Double_Word (CSR.CAUSE_ILLEGAL_INSN),
                                 Double_Word (Instruction));
                     return;
                  end if;

                  --  mstatus.TVM traps satp as well as SFENCE.VMA, so a
                  --  hypervisor can shadow both the tables and the pointer
                  --  to them.
                  if CSR_Addr = CSR64.CSR_SATP
                    and then CPU.Priv_Mode = Supervisor
                    and then (CSR64.Read (CPU.CSRs, CSR.CSR_MSTATUS)
                              and CSR64.MSTATUS_TVM) /= 0
                  then
                     CPU.Exception_Code := Illegal_Instruction;
                     Trap_Entry (CPU,
                                 Double_Word (CSR.CAUSE_ILLEGAL_INSN),
                                 Double_Word (Instruction));
                     return;
                  end if;

                  --  Read CSR (special handling for FP and vector CSRs)
                  case CSR_Addr is
                     when CSR64.CSR_FFLAGS =>
                        Old_Val := Double_Word (FPU.Read_FFLAGS (CPU.FP));
                     when CSR64.CSR_FRM =>
                        Old_Val := Double_Word (FPU.Read_FRM (CPU.FP));
                     when CSR64.CSR_FCSR =>
                        Old_Val := Double_Word (FPU.Read_FCSR (CPU.FP));
                     when CSR64.CSR_VL =>
                        Old_Val := Double_Word (Vector.Read_VL (CPU.VU));
                     when CSR64.CSR_VTYPE =>
                        Old_Val := Double_Word (Vector.Read_VType (CPU.VU));
                     when CSR64.CSR_VLENB =>
                        Old_Val := Double_Word (Vector.Read_VLENB);
                     when CSR64.CSR_VSTART =>
                        Old_Val := Double_Word (Vector.Read_VStart (CPU.VU));
                     when CSR64.CSR_VXSAT =>
                        Old_Val := Double_Word (Vector.Read_VXSat (CPU.VU));
                     when CSR64.CSR_VXRM =>
                        Old_Val := Double_Word (Vector.Read_VXRM (CPU.VU));
                     when others =>
                        Old_Val := CSR64.Read (CPU.CSRs, CSR_Addr);
                  end case;

                  case Decoded.Funct3 is
                     when FUNCT3_CSRRW =>
                        Write_Register (CPU, Decoded.Rd, Old_Val);
                        New_Val := Rs1_Val;

                     when FUNCT3_CSRRS =>
                        Write_Register (CPU, Decoded.Rd, Old_Val);
                        New_Val := Old_Val or Rs1_Val;
                        Write_CSR := Decoded.Rs1 /= 0;

                     when FUNCT3_CSRRC =>
                        Write_Register (CPU, Decoded.Rd, Old_Val);
                        New_Val := Old_Val and (not Rs1_Val);
                        Write_CSR := Decoded.Rs1 /= 0;

                     when FUNCT3_CSRRWI =>
                        Write_Register (CPU, Decoded.Rd, Old_Val);
                        New_Val := Zimm;

                     when FUNCT3_CSRRSI =>
                        Write_Register (CPU, Decoded.Rd, Old_Val);
                        New_Val := Old_Val or Zimm;
                        Write_CSR := Zimm /= 0;

                     when FUNCT3_CSRRCI =>
                        Write_Register (CPU, Decoded.Rd, Old_Val);
                        New_Val := Old_Val and (not Zimm);
                        Write_CSR := Zimm /= 0;

                     when others =>
                        CPU.Exception_Code := Illegal_Instruction;
                        Trap_Entry (CPU,
                                    Double_Word (CSR.CAUSE_ILLEGAL_INSN),
                                    Double_Word (Instruction));
                        return;
                  end case;

                  if Write_CSR then
                     if CSR64.Is_Read_Only (CSR_Addr) then
                        CPU.Exception_Code := Illegal_Instruction;
                        Trap_Entry (CPU,
                                    Double_Word (CSR.CAUSE_ILLEGAL_INSN),
                                    Double_Word (Instruction));
                        return;
                     end if;
                     case CSR_Addr is
                        when CSR64.CSR_FFLAGS =>
                           FPU.Write_FFLAGS (CPU.FP, Word (New_Val and 16#1F#));
                        when CSR64.CSR_FRM =>
                           FPU.Write_FRM (CPU.FP, Word (New_Val and 7));
                        when CSR64.CSR_FCSR =>
                           FPU.Write_FCSR (CPU.FP, Word (New_Val and 16#FF#));
                        when CSR64.CSR_VSTART =>
                           Vector.Write_VStart (CPU.VU, Word (New_Val));
                        when CSR64.CSR_VXSAT =>
                           Vector.Write_VXSat (CPU.VU, Word (New_Val));
                        when CSR64.CSR_VXRM =>
                           Vector.Write_VXRM (CPU.VU, Word (New_Val));
                        when CSR64.CSR_MISA =>
                           --  misa.C is WARL: refuse to clear C (set IALIGN=32)
                           --  when the next instruction fetch would then be
                           --  misaligned. Otherwise honour the write.
                           declare
                              Old_Misa : constant Double_Word :=
                                 CSR64.Read (CPU.CSRs, CSR64.CSR_MISA);
                              Misa_Val : Double_Word := New_Val;
                           begin
                              if (Old_Misa and 2#100#) /= 0 and then
                                 (Misa_Val and 2#100#) = 0 and then
                                 (Double_Word (Next_PC) and 2) /= 0
                              then
                                 Misa_Val := Misa_Val or 2#100#;
                              end if;
                              CSR64.Write (CPU.CSRs, CSR64.CSR_MISA, Misa_Val);
                           end;
                        when others =>
                           CSR64.Write (CPU.CSRs, CSR_Addr, New_Val);
                     end case;
                  end if;
               end;
            end if;

         ----------------------
         -- FP Operations
         ----------------------
         when OPCODE_OP_FP =>
            --  funct3 = 5 and 6 are reserved rounding-mode encodings.  The F
            --  extension requires a static RM of 101 or 110 to raise an
            --  illegal instruction, not to fall back to dynamic rounding.
            if Decoded.Funct3 = 5 or else Decoded.Funct3 = 6 then
               CPU.Exception_Code := Illegal_Instruction;
               Trap_Entry (CPU,
                           Double_Word (CSR.CAUSE_ILLEGAL_INSN),
                           Double_Word (Instruction));
               CSR64.Increment_Instret (CPU.CSRs);
               CSR64.Increment_Mcycle (CPU.CSRs);
               return;
            end if;
            declare
               use FPU;
               FS1 : Word;
               FS2 : Word;
               FD1 : FP_Register;
               FD2 : FP_Register;
               FH1 : Word := 0;
               FH2 : Word := 0;
               RM  : constant Rounding_Mode :=
                 (if Decoded.Funct3 = 7 then DYN
                  elsif Decoded.Funct3 <= 4 then
                     Rounding_Mode'Val (Natural (Decoded.Funct3))
                  else DYN);
            begin
               --  Read FP source operands (all formats - used selectively per opcode)
               FS1 := Read_Single (CPU.FP, Decoded.Rs1);
               FS2 := Read_Single (CPU.FP, Decoded.Rs2);
               FD1 := Read_Double (CPU.FP, Decoded.Rs1);
               FD2 := Read_Double (CPU.FP, Decoded.Rs2);
               FH1 := Read_Half (CPU.FP, Decoded.Rs1);
               FH2 := Read_Half (CPU.FP, Decoded.Rs2);

               case Decoded.Funct7 is
                  when FUNCT7_FADD_S =>
                     Write_Single (CPU.FP, Decoded.Rd,
                       FADD_S (CPU.FP, FS1, FS2, RM));

                  when FUNCT7_FSUB_S =>
                     Write_Single (CPU.FP, Decoded.Rd,
                       FSUB_S (CPU.FP, FS1, FS2, RM));

                  when FUNCT7_FMUL_S =>
                     Write_Single (CPU.FP, Decoded.Rd,
                       FMUL_S (CPU.FP, FS1, FS2, RM));

                  when FUNCT7_FDIV_S =>
                     Write_Single (CPU.FP, Decoded.Rd,
                       FDIV_S (CPU.FP, FS1, FS2, RM));

                  when FUNCT7_FSQRT_S =>
                     Write_Single (CPU.FP, Decoded.Rd,
                       FSQRT_S (CPU.FP, FS1, RM));

                  when FUNCT7_FSGNJ_S =>
                     case Decoded.Funct3 is
                        when FUNCT3_FSGNJ =>
                           Write_Single (CPU.FP, Decoded.Rd, FSGNJ_S (FS1, FS2));
                        when FUNCT3_FSGNJN =>
                           Write_Single (CPU.FP, Decoded.Rd, FSGNJN_S (FS1, FS2));
                        when FUNCT3_FSGNJX =>
                           Write_Single (CPU.FP, Decoded.Rd, FSGNJX_S (FS1, FS2));
                        when others =>
                           CPU.Exception_Code := Illegal_Instruction;
                           Trap_Entry (CPU,
                                       Double_Word (CSR.CAUSE_ILLEGAL_INSN),
                                       Double_Word (Instruction));
                           return;
                     end case;

                  when FUNCT7_FMINMAX_S =>
                     case Decoded.Funct3 is
                        when FUNCT3_FMIN =>
                           Write_Single (CPU.FP, Decoded.Rd,
                             FMIN_S (CPU.FP, FS1, FS2));
                        when FUNCT3_FMAX =>
                           Write_Single (CPU.FP, Decoded.Rd,
                             FMAX_S (CPU.FP, FS1, FS2));
                        when others =>
                           CPU.Exception_Code := Illegal_Instruction;
                           Trap_Entry (CPU,
                                       Double_Word (CSR.CAUSE_ILLEGAL_INSN),
                                       Double_Word (Instruction));
                           return;
                     end case;

                  when FUNCT7_FCVT_W_S =>
                     case Decoded.Rs2 is
                        when 0 =>   --  FCVT.W.S: float ->int32, sign-extend
                           Write_Register (CPU, Decoded.Rd,
                             SE32 (FCVT_W_S (CPU.FP, FS1, RM)));
                        when 1 =>   --  FCVT.WU.S: float ->uint32, sign-extend
                           Write_Register (CPU, Decoded.Rd,
                             SE32 (FCVT_WU_S (CPU.FP, FS1, RM)));
                        when 2 =>   --  FCVT.L.S: float ->int64 (RV64)
                           Write_Register (CPU, Decoded.Rd,
                             Double_Word (FCVT_L_S (CPU.FP, FS1, RM)));
                        when 3 =>   --  FCVT.LU.S: float ->uint64 (RV64)
                           Write_Register (CPU, Decoded.Rd,
                             Double_Word (FCVT_LU_S (CPU.FP, FS1, RM)));
                        when others =>
                           CPU.Exception_Code := Illegal_Instruction;
                           Trap_Entry (CPU,
                                       Double_Word (CSR.CAUSE_ILLEGAL_INSN),
                                       Double_Word (Instruction));
                           return;
                     end case;

                  when FUNCT7_FMV_X_W =>
                     if Decoded.Funct3 = 0 then
                        --  FMV.X.W: move the raw low 32 bits of the register
                        --  (sign-extended), with no NaN-box interpretation.
                        Write_Register (CPU, Decoded.Rd,
                          SE32 (Word (Unsigned_64
                            (Read_Register (CPU.FP, Decoded.Rs1))
                            and 16#FFFF_FFFF#)));
                     else  --  FCLASS.S
                        Write_Register (CPU, Decoded.Rd,
                          Double_Word (FCLASS_S (FS1)));
                     end if;

                  when FUNCT7_FCMP_S =>
                     case Decoded.Funct3 is
                        when FUNCT3_FEQ =>
                           Write_Register (CPU, Decoded.Rd,
                             Double_Word (FEQ_S (CPU.FP, FS1, FS2)));
                        when FUNCT3_FLT =>
                           Write_Register (CPU, Decoded.Rd,
                             Double_Word (FLT_S (CPU.FP, FS1, FS2)));
                        when FUNCT3_FLE =>
                           Write_Register (CPU, Decoded.Rd,
                             Double_Word (FLE_S (CPU.FP, FS1, FS2)));
                        when others =>
                           CPU.Exception_Code := Illegal_Instruction;
                           Trap_Entry (CPU,
                                       Double_Word (CSR.CAUSE_ILLEGAL_INSN),
                                       Double_Word (Instruction));
                           return;
                     end case;

                  when FUNCT7_FCVT_S_W =>
                     case Decoded.Rs2 is
                        when 0 =>   --  FCVT.S.W: int32 ->float
                           Write_Single (CPU.FP, Decoded.Rd,
                             FCVT_S_W (CPU.FP,
                                       Word (Rs1_Val and 16#FFFF_FFFF#), RM));
                        when 1 =>   --  FCVT.S.WU: uint32 ->float
                           Write_Single (CPU.FP, Decoded.Rd,
                             FCVT_S_WU (CPU.FP,
                                        Word (Rs1_Val and 16#FFFF_FFFF#), RM));
                        when 2 =>   --  FCVT.S.L: int64 ->float (RV64)
                           Write_Single (CPU.FP, Decoded.Rd,
                             FCVT_S_L (CPU.FP, FP_Register (Rs1_Val), RM));
                        when 3 =>   --  FCVT.S.LU: uint64 ->float (RV64)
                           Write_Single (CPU.FP, Decoded.Rd,
                             FCVT_S_LU (CPU.FP, FP_Register (Rs1_Val), RM));
                        when others =>
                           CPU.Exception_Code := Illegal_Instruction;
                           Trap_Entry (CPU,
                                       Double_Word (CSR.CAUSE_ILLEGAL_INSN),
                                       Double_Word (Instruction));
                           return;
                     end case;

                  when FUNCT7_FMV_W_X =>
                     --  FMV.W.X: move lower 32 bits of int reg to float
                     Write_Single (CPU.FP, Decoded.Rd,
                       FMV_W_X (Word (Rs1_Val and 16#FFFF_FFFF#)));

                  when FUNCT7_FADD_D =>
                     Write_Double (CPU.FP, Decoded.Rd,
                       FADD_D (CPU.FP, FD1, FD2, RM));

                  when FUNCT7_FSUB_D =>
                     Write_Double (CPU.FP, Decoded.Rd,
                       FSUB_D (CPU.FP, FD1, FD2, RM));

                  when FUNCT7_FMUL_D =>
                     Write_Double (CPU.FP, Decoded.Rd,
                       FMUL_D (CPU.FP, FD1, FD2, RM));

                  when FUNCT7_FDIV_D =>
                     Write_Double (CPU.FP, Decoded.Rd,
                       FDIV_D (CPU.FP, FD1, FD2, RM));

                  when FUNCT7_FSQRT_D =>
                     Write_Double (CPU.FP, Decoded.Rd,
                       FSQRT_D (CPU.FP, FD1, RM));

                  when FUNCT7_FSGNJ_D =>
                     case Decoded.Funct3 is
                        when FUNCT3_FSGNJ =>
                           Write_Double (CPU.FP, Decoded.Rd, FSGNJ_D (FD1, FD2));
                        when FUNCT3_FSGNJN =>
                           Write_Double (CPU.FP, Decoded.Rd, FSGNJN_D (FD1, FD2));
                        when FUNCT3_FSGNJX =>
                           Write_Double (CPU.FP, Decoded.Rd, FSGNJX_D (FD1, FD2));
                        when others =>
                           CPU.Exception_Code := Illegal_Instruction;
                           Trap_Entry (CPU,
                                       Double_Word (CSR.CAUSE_ILLEGAL_INSN),
                                       Double_Word (Instruction));
                           return;
                     end case;

                  when FUNCT7_FMINMAX_D =>
                     case Decoded.Funct3 is
                        when FUNCT3_FMIN =>
                           Write_Double (CPU.FP, Decoded.Rd,
                             FMIN_D (CPU.FP, FD1, FD2));
                        when FUNCT3_FMAX =>
                           Write_Double (CPU.FP, Decoded.Rd,
                             FMAX_D (CPU.FP, FD1, FD2));
                        when others =>
                           CPU.Exception_Code := Illegal_Instruction;
                           Trap_Entry (CPU,
                                       Double_Word (CSR.CAUSE_ILLEGAL_INSN),
                                       Double_Word (Instruction));
                           return;
                     end case;

                  when FUNCT7_FCVT_S_D =>
                     if Decoded.Rs2 = 1 then
                        Write_Single (CPU.FP, Decoded.Rd,
                          FCVT_S_D (CPU.FP, FD1, RM));
                     elsif Decoded.Rs2 = 2 then
                        Write_Single (CPU.FP, Decoded.Rd, FCVT_S_H (FH1));
                     else
                        CPU.Exception_Code := Illegal_Instruction;
                        Trap_Entry (CPU,
                                    Double_Word (CSR.CAUSE_ILLEGAL_INSN),
                                    Double_Word (Instruction));
                        return;
                     end if;

                  when FUNCT7_FCVT_D_S =>
                     if Decoded.Rs2 = 0 then
                        Write_Double (CPU.FP, Decoded.Rd,
                          FCVT_D_S (CPU.FP, FS1, RM));
                     elsif Decoded.Rs2 = 2 then
                        Write_Double (CPU.FP, Decoded.Rd, FCVT_D_H (FH1));
                     else
                        CPU.Exception_Code := Illegal_Instruction;
                        Trap_Entry (CPU,
                                    Double_Word (CSR.CAUSE_ILLEGAL_INSN),
                                    Double_Word (Instruction));
                        return;
                     end if;

                  when FUNCT7_FCVT_W_D =>
                     case Decoded.Rs2 is
                        when 0 =>   --  FCVT.W.D: double ->int32, sign-extend
                           Write_Register (CPU, Decoded.Rd,
                             SE32 (FCVT_W_D (CPU.FP, FD1, RM)));
                        when 1 =>   --  FCVT.WU.D: double ->uint32, sign-extend
                           Write_Register (CPU, Decoded.Rd,
                             SE32 (FCVT_WU_D (CPU.FP, FD1, RM)));
                        when 2 =>   --  FCVT.L.D: double ->int64 (RV64)
                           Write_Register (CPU, Decoded.Rd,
                             Double_Word (FCVT_L_D (CPU.FP, FD1, RM)));
                        when 3 =>   --  FCVT.LU.D: double ->uint64 (RV64)
                           Write_Register (CPU, Decoded.Rd,
                             Double_Word (FCVT_LU_D (CPU.FP, FD1, RM)));
                        when others =>
                           CPU.Exception_Code := Illegal_Instruction;
                           Trap_Entry (CPU,
                                       Double_Word (CSR.CAUSE_ILLEGAL_INSN),
                                       Double_Word (Instruction));
                           return;
                     end case;

                  when FUNCT7_FCMP_D =>
                     case Decoded.Funct3 is
                        when FUNCT3_FEQ =>
                           Write_Register (CPU, Decoded.Rd,
                             Double_Word (FEQ_D (CPU.FP, FD1, FD2)));
                        when FUNCT3_FLT =>
                           Write_Register (CPU, Decoded.Rd,
                             Double_Word (FLT_D (CPU.FP, FD1, FD2)));
                        when FUNCT3_FLE =>
                           Write_Register (CPU, Decoded.Rd,
                             Double_Word (FLE_D (CPU.FP, FD1, FD2)));
                        when others =>
                           CPU.Exception_Code := Illegal_Instruction;
                           Trap_Entry (CPU,
                                       Double_Word (CSR.CAUSE_ILLEGAL_INSN),
                                       Double_Word (Instruction));
                           return;
                     end case;

                  when FUNCT7_FCLASS_D =>
                     --  funct7=0x71 encodes both FMV.X.D (funct3=0) and FCLASS.D (funct3=1)
                     if Decoded.Funct3 = 0 then
                        --  FMV.X.D: move double bits to 64-bit integer register
                        Write_Register (CPU, Decoded.Rd,
                          Double_Word (FD1));
                     else
                        Write_Register (CPU, Decoded.Rd,
                          Double_Word (FCLASS_D (FD1)));
                     end if;

                  when FUNCT7_FCVT_D_W =>
                     case Decoded.Rs2 is
                        when 0 =>   --  FCVT.D.W: int32 ->double
                           Write_Double (CPU.FP, Decoded.Rd,
                             FCVT_D_W (CPU.FP,
                                       Word (Rs1_Val and 16#FFFF_FFFF#), RM));
                        when 1 =>   --  FCVT.D.WU: uint32 ->double
                           Write_Double (CPU.FP, Decoded.Rd,
                             FCVT_D_WU (CPU.FP,
                                        Word (Rs1_Val and 16#FFFF_FFFF#), RM));
                        when 2 =>   --  FCVT.D.L: int64 ->double (RV64)
                           Write_Double (CPU.FP, Decoded.Rd,
                             FCVT_D_L (CPU.FP, FP_Register (Rs1_Val), RM));
                        when 3 =>   --  FCVT.D.LU: uint64 ->double (RV64)
                           Write_Double (CPU.FP, Decoded.Rd,
                             FCVT_D_LU (CPU.FP, FP_Register (Rs1_Val), RM));
                        when others =>
                           CPU.Exception_Code := Illegal_Instruction;
                           Trap_Entry (CPU,
                                       Double_Word (CSR.CAUSE_ILLEGAL_INSN),
                                       Double_Word (Instruction));
                           return;
                     end case;

                  when FUNCT7_FMV_D_X =>
                     --  FMV.D.X: move 64-bit integer register bits to double (RV64)
                     Write_Double (CPU.FP, Decoded.Rd, FP_Register (Rs1_Val));

                  --  Half-precision arithmetic (Zfh)
                  when FUNCT7_FADD_H =>
                     Write_Half (CPU.FP, Decoded.Rd, FADD_H (CPU.FP, FH1, FH2, RM));
                  when FUNCT7_FSUB_H =>
                     Write_Half (CPU.FP, Decoded.Rd, FSUB_H (CPU.FP, FH1, FH2, RM));
                  when FUNCT7_FMUL_H =>
                     Write_Half (CPU.FP, Decoded.Rd, FMUL_H (CPU.FP, FH1, FH2, RM));
                  when FUNCT7_FDIV_H =>
                     Write_Half (CPU.FP, Decoded.Rd, FDIV_H (CPU.FP, FH1, FH2, RM));
                  when FUNCT7_FSQRT_H =>
                     Write_Half (CPU.FP, Decoded.Rd, FSQRT_H (CPU.FP, FH1, RM));
                  when FUNCT7_FSGNJ_H =>
                     case Decoded.Funct3 is
                        when FUNCT3_FSGNJ =>
                           Write_Half (CPU.FP, Decoded.Rd, FSGNJ_H (FH1, FH2));
                        when FUNCT3_FSGNJN =>
                           Write_Half (CPU.FP, Decoded.Rd, FSGNJN_H (FH1, FH2));
                        when FUNCT3_FSGNJX =>
                           Write_Half (CPU.FP, Decoded.Rd, FSGNJX_H (FH1, FH2));
                        when others =>
                           CPU.Exception_Code := Illegal_Instruction;
                           Trap_Entry (CPU,
                                       Double_Word (CSR.CAUSE_ILLEGAL_INSN),
                                       Double_Word (Instruction));
                           return;
                     end case;
                  when FUNCT7_FMINMAX_H =>
                     case Decoded.Funct3 is
                        when FUNCT3_FMIN =>
                           Write_Half (CPU.FP, Decoded.Rd, FMIN_H (CPU.FP, FH1, FH2));
                        when FUNCT3_FMAX =>
                           Write_Half (CPU.FP, Decoded.Rd, FMAX_H (CPU.FP, FH1, FH2));
                        when others =>
                           CPU.Exception_Code := Illegal_Instruction;
                           Trap_Entry (CPU,
                                       Double_Word (CSR.CAUSE_ILLEGAL_INSN),
                                       Double_Word (Instruction));
                           return;
                     end case;
                  when FUNCT7_FCVT_W_H =>
                     if Decoded.Rs2 = 0 then
                        Write_Register (CPU, Decoded.Rd,
                          SE32 (FCVT_W_H (CPU.FP, FH1, RM)));
                     else
                        --  FCVT.WU.H sign-extends its 32-bit result to XLEN.
                        Write_Register (CPU, Decoded.Rd,
                          SE32 (FCVT_WU_H (CPU.FP, FH1, RM)));
                     end if;
                  when FUNCT7_FCVT_H_W =>
                     if Decoded.Rs2 = 0 then
                        Write_Half (CPU.FP, Decoded.Rd,
                          FCVT_H_W (CPU.FP, Word (Rs1_Val and 16#FFFF_FFFF#), RM));
                     else
                        Write_Half (CPU.FP, Decoded.Rd,
                          FCVT_H_WU (CPU.FP, Word (Rs1_Val and 16#FFFF_FFFF#), RM));
                     end if;
                  when FUNCT7_FMV_X_H =>
                     if Decoded.Funct3 = 0 then
                        Write_Register (CPU, Decoded.Rd,
                          SE32 (FH1 and 16#FFFF#));  --  FMV.X.H
                     else
                        Write_Register (CPU, Decoded.Rd,
                          Double_Word (FCLASS_H (FH1)));  --  FCLASS.H
                     end if;
                  when FUNCT7_FMV_H_X =>
                     Write_Half (CPU.FP, Decoded.Rd,
                       Word (Rs1_Val and 16#FFFF#));  --  FMV.H.X
                  when FUNCT7_FCMP_H =>
                     case Decoded.Funct3 is
                        when FUNCT3_FEQ =>
                           Write_Register (CPU, Decoded.Rd,
                             Double_Word (FEQ_H (CPU.FP, FH1, FH2)));
                        when FUNCT3_FLT =>
                           Write_Register (CPU, Decoded.Rd,
                             Double_Word (FLT_H (CPU.FP, FH1, FH2)));
                        when FUNCT3_FLE =>
                           Write_Register (CPU, Decoded.Rd,
                             Double_Word (FLE_H (CPU.FP, FH1, FH2)));
                        when others =>
                           CPU.Exception_Code := Illegal_Instruction;
                           Trap_Entry (CPU,
                                       Double_Word (CSR.CAUSE_ILLEGAL_INSN),
                                       Double_Word (Instruction));
                           return;
                     end case;
                  when FUNCT7_FCVT_H_SD =>
                     if Decoded.Rs2 = 0 then
                        Write_Half (CPU.FP, Decoded.Rd,
                          FCVT_H_S (CPU.FP, FS1, RM));
                     elsif Decoded.Rs2 = 1 then
                        Write_Half (CPU.FP, Decoded.Rd,
                          FCVT_H_D (CPU.FP, FD1, RM));
                     else
                        CPU.Exception_Code := Illegal_Instruction;
                        Trap_Entry (CPU,
                                    Double_Word (CSR.CAUSE_ILLEGAL_INSN),
                                    Double_Word (Instruction));
                        return;
                     end if;

                  when others =>
                     CPU.Exception_Code := Illegal_Instruction;
                     Trap_Entry (CPU,
                                 Double_Word (CSR.CAUSE_ILLEGAL_INSN),
                                 Double_Word (Instruction));
                     return;
               end case;
            end;

         ----------------------------------
         -- A Extension (Atomic Memory Ops)
         ----------------------------------
         when OPCODE_AMO =>
            Memory.Clear_Access_Fault (Mem);
            declare
               Funct5 : constant Word := Decoder.Get_Funct5 (Instruction);
            begin
               if Decoded.Funct3 = FUNCT3_AMO_W then
                  --  32-bit atomics
                  declare
                     Mem_Val32 : Word;
                     New_Val32 : Word;
                  begin
                     Address := Memory_Address_64 (Rs1_Val);

                     declare
                        Phys_Addr : Memory_Address_64;
                     begin
                        if not Translate_Address (Address, MMU.Load,
                                                  Phys_Addr)
                        then
                           return;
                        end if;
                        Address := Phys_Addr;
                     end;

                     case Funct5 is
                        when FUNCT5_LR =>
                           Mem_Val32 := Memory.Read_Word
                             (Mem, Memory_Address (Address));
                           Write_Register (CPU, Decoded.Rd,
                                           SE32 (Mem_Val32));
                           CPU.Reserved_Addr := Address;
                           CPU.Reservation_Valid := True;

                        when FUNCT5_SC =>
                           if CPU.Reservation_Valid and then
                              CPU.Reserved_Addr = Address
                           then
                              Memory.Write_Word (Mem, Memory_Address (Address),
                                                 Word (Rs2_Val and 16#FFFF_FFFF#));
                              Write_Register (CPU, Decoded.Rd, 0);
                           else
                              Write_Register (CPU, Decoded.Rd, 1);
                           end if;
                           CPU.Reservation_Valid := False;

                        when FUNCT5_AMOSWAP =>
                           Mem_Val32 := Memory.Read_Word
                             (Mem, Memory_Address (Address));
                           Memory.Write_Word (Mem, Memory_Address (Address),
                                              Word (Rs2_Val and 16#FFFF_FFFF#));
                           Write_Register (CPU, Decoded.Rd, SE32 (Mem_Val32));

                        when FUNCT5_AMOADD =>
                           Mem_Val32 := Memory.Read_Word
                             (Mem, Memory_Address (Address));
                           New_Val32 := Mem_Val32 +
                                        Word (Rs2_Val and 16#FFFF_FFFF#);
                           Memory.Write_Word (Mem, Memory_Address (Address),
                                              New_Val32);
                           Write_Register (CPU, Decoded.Rd, SE32 (Mem_Val32));

                        when FUNCT5_AMOXOR =>
                           Mem_Val32 := Memory.Read_Word
                             (Mem, Memory_Address (Address));
                           New_Val32 := Mem_Val32 xor
                                        Word (Rs2_Val and 16#FFFF_FFFF#);
                           Memory.Write_Word (Mem, Memory_Address (Address),
                                              New_Val32);
                           Write_Register (CPU, Decoded.Rd, SE32 (Mem_Val32));

                        when FUNCT5_AMOAND =>
                           Mem_Val32 := Memory.Read_Word
                             (Mem, Memory_Address (Address));
                           New_Val32 := Mem_Val32 and
                                        Word (Rs2_Val and 16#FFFF_FFFF#);
                           Memory.Write_Word (Mem, Memory_Address (Address),
                                              New_Val32);
                           Write_Register (CPU, Decoded.Rd, SE32 (Mem_Val32));

                        when FUNCT5_AMOOR =>
                           Mem_Val32 := Memory.Read_Word
                             (Mem, Memory_Address (Address));
                           New_Val32 := Mem_Val32 or
                                        Word (Rs2_Val and 16#FFFF_FFFF#);
                           Memory.Write_Word (Mem, Memory_Address (Address),
                                              New_Val32);
                           Write_Register (CPU, Decoded.Rd, SE32 (Mem_Val32));

                        when FUNCT5_AMOMIN =>
                           Mem_Val32 := Memory.Read_Word
                             (Mem, Memory_Address (Address));
                           if To_Signed (Word (Rs2_Val and 16#FFFF_FFFF#)) <
                              To_Signed (Mem_Val32)
                           then
                              New_Val32 := Word (Rs2_Val and 16#FFFF_FFFF#);
                           else
                              New_Val32 := Mem_Val32;
                           end if;
                           Memory.Write_Word (Mem, Memory_Address (Address),
                                              New_Val32);
                           Write_Register (CPU, Decoded.Rd, SE32 (Mem_Val32));

                        when FUNCT5_AMOMAX =>
                           Mem_Val32 := Memory.Read_Word
                             (Mem, Memory_Address (Address));
                           if To_Signed (Word (Rs2_Val and 16#FFFF_FFFF#)) >
                              To_Signed (Mem_Val32)
                           then
                              New_Val32 := Word (Rs2_Val and 16#FFFF_FFFF#);
                           else
                              New_Val32 := Mem_Val32;
                           end if;
                           Memory.Write_Word (Mem, Memory_Address (Address),
                                              New_Val32);
                           Write_Register (CPU, Decoded.Rd, SE32 (Mem_Val32));

                        when FUNCT5_AMOMINU =>
                           Mem_Val32 := Memory.Read_Word
                             (Mem, Memory_Address (Address));
                           if Word (Rs2_Val and 16#FFFF_FFFF#) < Mem_Val32 then
                              New_Val32 := Word (Rs2_Val and 16#FFFF_FFFF#);
                           else
                              New_Val32 := Mem_Val32;
                           end if;
                           Memory.Write_Word (Mem, Memory_Address (Address),
                                              New_Val32);
                           Write_Register (CPU, Decoded.Rd, SE32 (Mem_Val32));

                        when FUNCT5_AMOMAXU =>
                           Mem_Val32 := Memory.Read_Word
                             (Mem, Memory_Address (Address));
                           if Word (Rs2_Val and 16#FFFF_FFFF#) > Mem_Val32 then
                              New_Val32 := Word (Rs2_Val and 16#FFFF_FFFF#);
                           else
                              New_Val32 := Mem_Val32;
                           end if;
                           Memory.Write_Word (Mem, Memory_Address (Address),
                                              New_Val32);
                           Write_Register (CPU, Decoded.Rd, SE32 (Mem_Val32));

                        when others =>
                           CPU.Exception_Code := Illegal_Instruction;
                           Trap_Entry (CPU,
                                       Double_Word (CSR.CAUSE_ILLEGAL_INSN),
                                       Double_Word (Instruction));
                           return;
                     end case;
                  end;

               elsif Decoded.Funct3 = FUNCT3_AMO_D then
                  --  64-bit atomics
                  declare
                     Mem_Val64 : Double_Word;
                     New_Val64 : Double_Word;
                  begin
                     Address := Memory_Address_64 (Rs1_Val);

                     declare
                        Phys_Addr : Memory_Address_64;
                     begin
                        if not Translate_Address (Address, MMU.Load,
                                                  Phys_Addr)
                        then
                           return;
                        end if;
                        Address := Phys_Addr;
                     end;

                     case Funct5 is
                        when FUNCT5_LR =>
                           Mem_Val64 := Read_DWord_Mem (Mem, Address);
                           Write_Register (CPU, Decoded.Rd, Mem_Val64);
                           CPU.Reserved_Addr := Address;
                           CPU.Reservation_Valid := True;

                        when FUNCT5_SC =>
                           if CPU.Reservation_Valid and then
                              CPU.Reserved_Addr = Address
                           then
                              Write_DWord_Mem (Mem, Address, Rs2_Val);
                              Write_Register (CPU, Decoded.Rd, 0);
                           else
                              Write_Register (CPU, Decoded.Rd, 1);
                           end if;
                           CPU.Reservation_Valid := False;

                        when FUNCT5_AMOSWAP =>
                           Mem_Val64 := Read_DWord_Mem (Mem, Address);
                           Write_DWord_Mem (Mem, Address, Rs2_Val);
                           Write_Register (CPU, Decoded.Rd, Mem_Val64);

                        when FUNCT5_AMOADD =>
                           Mem_Val64 := Read_DWord_Mem (Mem, Address);
                           New_Val64 := Mem_Val64 + Rs2_Val;
                           Write_DWord_Mem (Mem, Address, New_Val64);
                           Write_Register (CPU, Decoded.Rd, Mem_Val64);

                        when FUNCT5_AMOXOR =>
                           Mem_Val64 := Read_DWord_Mem (Mem, Address);
                           New_Val64 := Mem_Val64 xor Rs2_Val;
                           Write_DWord_Mem (Mem, Address, New_Val64);
                           Write_Register (CPU, Decoded.Rd, Mem_Val64);

                        when FUNCT5_AMOAND =>
                           Mem_Val64 := Read_DWord_Mem (Mem, Address);
                           New_Val64 := Mem_Val64 and Rs2_Val;
                           Write_DWord_Mem (Mem, Address, New_Val64);
                           Write_Register (CPU, Decoded.Rd, Mem_Val64);

                        when FUNCT5_AMOOR =>
                           Mem_Val64 := Read_DWord_Mem (Mem, Address);
                           New_Val64 := Mem_Val64 or Rs2_Val;
                           Write_DWord_Mem (Mem, Address, New_Val64);
                           Write_Register (CPU, Decoded.Rd, Mem_Val64);

                        when FUNCT5_AMOMIN =>
                           Mem_Val64 := Read_DWord_Mem (Mem, Address);
                           if To_Signed64 (Rs2_Val) < To_Signed64 (Mem_Val64) then
                              New_Val64 := Rs2_Val;
                           else
                              New_Val64 := Mem_Val64;
                           end if;
                           Write_DWord_Mem (Mem, Address, New_Val64);
                           Write_Register (CPU, Decoded.Rd, Mem_Val64);

                        when FUNCT5_AMOMAX =>
                           Mem_Val64 := Read_DWord_Mem (Mem, Address);
                           if To_Signed64 (Rs2_Val) > To_Signed64 (Mem_Val64) then
                              New_Val64 := Rs2_Val;
                           else
                              New_Val64 := Mem_Val64;
                           end if;
                           Write_DWord_Mem (Mem, Address, New_Val64);
                           Write_Register (CPU, Decoded.Rd, Mem_Val64);

                        when FUNCT5_AMOMINU =>
                           Mem_Val64 := Read_DWord_Mem (Mem, Address);
                           if Rs2_Val < Mem_Val64 then
                              New_Val64 := Rs2_Val;
                           else
                              New_Val64 := Mem_Val64;
                           end if;
                           Write_DWord_Mem (Mem, Address, New_Val64);
                           Write_Register (CPU, Decoded.Rd, Mem_Val64);

                        when FUNCT5_AMOMAXU =>
                           Mem_Val64 := Read_DWord_Mem (Mem, Address);
                           if Rs2_Val > Mem_Val64 then
                              New_Val64 := Rs2_Val;
                           else
                              New_Val64 := Mem_Val64;
                           end if;
                           Write_DWord_Mem (Mem, Address, New_Val64);
                           Write_Register (CPU, Decoded.Rd, Mem_Val64);

                        when others =>
                           CPU.Exception_Code := Illegal_Instruction;
                           Trap_Entry (CPU,
                                       Double_Word (CSR.CAUSE_ILLEGAL_INSN),
                                       Double_Word (Instruction));
                           return;
                     end case;
                  end;

               else
                  CPU.Exception_Code := Illegal_Instruction;
                  Trap_Entry (CPU,
                              Double_Word (CSR.CAUSE_ILLEGAL_INSN),
                              Double_Word (Instruction));
                  return;
               end if;

               --  An atomic that could not reach memory faults as a store,
               --  whichever half of the read-modify-write failed.
               if Memory.Pending_Fault (Mem) /= Memory.OK then
                  CPU.Exception_Code := Store_Access_Fault;
                  Trap_Entry
                    (CPU,
                     Double_Word (CSR.CAUSE_STORE_ACCESS_FAULT),
                     Double_Word (Memory.Pending_Fault_Address (Mem)));
                  return;
               end if;
            end;

         -----------------------------------------------
         -- FP Loads (LOAD-FP opcode)
         -----------------------------------------------
         when OPCODE_LOAD_FP =>
            Address := Memory_Address_64 (Rs1_Val + SE (Decoded.Imm_I));

            declare
               Phys_Addr : Memory_Address_64;
            begin
               if not Translate_Address (Address, MMU.Load, Phys_Addr) then
                  return;
               end if;
               Address := Phys_Addr;
            end;
            Memory.Clear_Access_Fault (Mem);

            case Decoded.Funct3 is
               when FUNCT3_FLW =>
                  FPU.Write_Single (CPU.FP, Decoded.Rd,
                    Memory.Read_Word (Mem, Memory_Address (Address)));

               when FUNCT3_FLD =>
                  declare
                     Lo  : constant Word := Memory.Read_Word
                       (Mem, Memory_Address (Address));
                     Hi  : constant Word := Memory.Read_Word
                       (Mem, Memory_Address (Address + 4));
                     Val : constant Unsigned_64 :=
                        Unsigned_64 (Lo) or
                        Shift_Left (Unsigned_64 (Hi), 32);
                  begin
                     FPU.Write_Double (CPU.FP, Decoded.Rd,
                                       FPU.FP_Register (Val));
                  end;

               when FUNCT3_FLH =>
                  --  Load half-precision float (Zfh)
                  FPU.Write_Half (CPU.FP, Decoded.Rd,
                    Word (Memory.Read_Half_Word (Mem, Memory_Address (Address))));

               when others =>
                  CPU.Exception_Code := Illegal_Instruction;
                  Trap_Entry (CPU,
                              Double_Word (CSR.CAUSE_ILLEGAL_INSN),
                              Double_Word (Instruction));
                  return;
            end case;

            if Memory.Pending_Fault (Mem) /= Memory.OK then
               CPU.Exception_Code := Load_Access_Fault;
               Trap_Entry (CPU,
                           Double_Word (CSR.CAUSE_LOAD_ACCESS_FAULT),
                           Double_Word (Memory.Pending_Fault_Address (Mem)));
               return;
            end if;

         -----------------------------------------------
         -- FP Stores (STORE-FP opcode)
         -----------------------------------------------
         when OPCODE_STORE_FP =>
            Address := Memory_Address_64 (Rs1_Val + SE (Decoded.Imm_S));

            declare
               Phys_Addr : Memory_Address_64;
            begin
               if not Translate_Address (Address, MMU.Store, Phys_Addr) then
                  return;
               end if;
               Address := Phys_Addr;
            end;
            Memory.Clear_Access_Fault (Mem);

            case Decoded.Funct3 is
               when FUNCT3_FSW =>
                  --  FSW stores the raw low 32 bits of the register (no
                  --  NaN-box interpretation) -- a preceding FLD may have left
                  --  a full double there whose low word must be stored as-is.
                  Memory.Write_Word (Mem, Memory_Address (Address),
                    Word (Unsigned_64 (FPU.Read_Register (CPU.FP, Decoded.Rs2))
                          and 16#FFFF_FFFF#));

               when FUNCT3_FSD =>
                  declare
                     Val : constant Unsigned_64 :=
                        Unsigned_64 (FPU.Read_Double (CPU.FP, Decoded.Rs2));
                  begin
                     Memory.Write_Word (Mem, Memory_Address (Address),
                       Word (Val and 16#FFFF_FFFF#));
                     Memory.Write_Word (Mem, Memory_Address (Address + 4),
                       Word (Shift_Right (Val, 32) and 16#FFFF_FFFF#));
                  end;

               when FUNCT3_FSH =>
                  --  Store half-precision float (Zfh)
                  Memory.Write_Half_Word (Mem, Memory_Address (Address),
                    Half_Word (FPU.Read_Half (CPU.FP, Decoded.Rs2) and 16#FFFF#));

               when others =>
                  CPU.Exception_Code := Illegal_Instruction;
                  Trap_Entry (CPU,
                              Double_Word (CSR.CAUSE_ILLEGAL_INSN),
                              Double_Word (Instruction));
                  return;
            end case;

            if Memory.Pending_Fault (Mem) /= Memory.OK then
               CPU.Exception_Code := Store_Access_Fault;
               Trap_Entry (CPU,
                           Double_Word (CSR.CAUSE_STORE_ACCESS_FAULT),
                           Double_Word (Memory.Pending_Fault_Address (Mem)));
               return;
            end if;

         -------------------------------------------
         -- FMADD / FMSUB / FNMADD / FNMSUB (R4)
         -------------------------------------------
         when OPCODE_FMADD | OPCODE_FMSUB |
              OPCODE_FNMSUB | OPCODE_FNMADD =>
            --  funct3 = 5 and 6 are reserved rounding-mode encodings.  The F
            --  extension requires a static RM of 101 or 110 to raise an
            --  illegal instruction, not to fall back to dynamic rounding.
            if Decoded.Funct3 = 5 or else Decoded.Funct3 = 6 then
               CPU.Exception_Code := Illegal_Instruction;
               Trap_Entry (CPU,
                           Double_Word (CSR.CAUSE_ILLEGAL_INSN),
                           Double_Word (Instruction));
               CSR64.Increment_Instret (CPU.CSRs);
               CSR64.Increment_Mcycle (CPU.CSRs);
               return;
            end if;
            declare
               use FPU;
               Fmt : constant Word := Shift_Right (Instruction, 25) and 3;
               Rs3 : constant Register_Index :=
                  Register_Index (Shift_Right (Instruction, 27) and 16#1F#);
               FS1 : constant Word := Read_Single (CPU.FP, Decoded.Rs1);
               FS2 : constant Word := Read_Single (CPU.FP, Decoded.Rs2);
               FS3 : constant Word := Read_Single (CPU.FP, Rs3);
               RM  : constant Rounding_Mode :=
                 (if Decoded.Funct3 = 7 then DYN
                  elsif Decoded.Funct3 <= 4 then
                     Rounding_Mode'Val (Natural (Decoded.Funct3))
                  else DYN);
            begin
               if Fmt = 0 then  --  Single precision
                  case Decoded.Opcode is
                     when OPCODE_FMADD =>
                        Write_Single (CPU.FP, Decoded.Rd,
                          FMADD_S (CPU.FP, FS1, FS2, FS3, RM));
                     when OPCODE_FMSUB =>
                        Write_Single (CPU.FP, Decoded.Rd,
                          FMSUB_S (CPU.FP, FS1, FS2, FS3, RM));
                     when OPCODE_FNMSUB =>
                        Write_Single (CPU.FP, Decoded.Rd,
                          FNMSUB_S (CPU.FP, FS1, FS2, FS3, RM));
                     when OPCODE_FNMADD =>
                        Write_Single (CPU.FP, Decoded.Rd,
                          FNMADD_S (CPU.FP, FS1, FS2, FS3, RM));
                     when others =>
                        CPU.Exception_Code := Illegal_Instruction;
                        Trap_Entry (CPU,
                                    Double_Word (CSR.CAUSE_ILLEGAL_INSN),
                                    Double_Word (Instruction));
                        return;
                  end case;
               elsif Fmt = 1 then  --  Double precision
                  declare
                     FD1 : constant FP_Register :=
                        Read_Double (CPU.FP, Decoded.Rs1);
                     FD2 : constant FP_Register :=
                        Read_Double (CPU.FP, Decoded.Rs2);
                     FD3 : constant FP_Register :=
                        Read_Double (CPU.FP, Rs3);
                  begin
                     case Decoded.Opcode is
                        when OPCODE_FMADD =>
                           Write_Double (CPU.FP, Decoded.Rd,
                             FMADD_D (CPU.FP, FD1, FD2, FD3, RM));
                        when OPCODE_FMSUB =>
                           Write_Double (CPU.FP, Decoded.Rd,
                             FMSUB_D (CPU.FP, FD1, FD2, FD3, RM));
                        when OPCODE_FNMSUB =>
                           Write_Double (CPU.FP, Decoded.Rd,
                             FNMSUB_D (CPU.FP, FD1, FD2, FD3, RM));
                        when OPCODE_FNMADD =>
                           Write_Double (CPU.FP, Decoded.Rd,
                             FNMADD_D (CPU.FP, FD1, FD2, FD3, RM));
                        when others =>
                           CPU.Exception_Code := Illegal_Instruction;
                           Trap_Entry (CPU,
                                       Double_Word (CSR.CAUSE_ILLEGAL_INSN),
                                       Double_Word (Instruction));
                           return;
                     end case;
                  end;
               elsif Fmt = 2 then  --  Half precision (Zfh)
                  declare
                     FH1 : constant Word := Read_Half (CPU.FP, Decoded.Rs1);
                     FH2 : constant Word := Read_Half (CPU.FP, Decoded.Rs2);
                     FH3 : constant Word := Read_Half (CPU.FP, Rs3);
                  begin
                     case Decoded.Opcode is
                        when OPCODE_FMADD =>
                           Write_Half (CPU.FP, Decoded.Rd,
                             FMADD_H (CPU.FP, FH1, FH2, FH3, RM));
                        when OPCODE_FMSUB =>
                           Write_Half (CPU.FP, Decoded.Rd,
                             FMSUB_H (CPU.FP, FH1, FH2, FH3, RM));
                        when OPCODE_FNMSUB =>
                           Write_Half (CPU.FP, Decoded.Rd,
                             FNMSUB_H (CPU.FP, FH1, FH2, FH3, RM));
                        when OPCODE_FNMADD =>
                           Write_Half (CPU.FP, Decoded.Rd,
                             FNMADD_H (CPU.FP, FH1, FH2, FH3, RM));
                        when others =>
                           CPU.Exception_Code := Illegal_Instruction;
                           Trap_Entry (CPU,
                                       Double_Word (CSR.CAUSE_ILLEGAL_INSN),
                                       Double_Word (Instruction));
                           return;
                     end case;
                  end;
               else
                  CPU.Exception_Code := Illegal_Instruction;
                  Trap_Entry (CPU,
                              Double_Word (CSR.CAUSE_ILLEGAL_INSN),
                              Double_Word (Instruction));
                  return;
               end if;
            end;

         ---------------------------------
         -- FENCE / FENCE.I (MISC-MEM)
         ---------------------------------
         when OPCODE_MISC_MEM =>
            --  NOPs in a single-hart emulator
            null;

         when others =>
            CPU.Exception_Code := Illegal_Instruction;
            Trap_Entry (CPU,
                        Double_Word (CSR.CAUSE_ILLEGAL_INSN),
                        Double_Word (Instruction));
            return;
      end case;

      --  Post-execution trace output
      if Trace_Enabled then
         if Trace_Cfg.Show_Memory and then Mem.Access_Occurred then
            Put_Line ("    MEM: " &
                      (if Mem.Last_Access_Write then "WRITE" else "READ ") &
                      " 0x" & To_Hex (Word (Mem.Last_Access_Addr)));
         end if;

         if Trace_Cfg.Show_Regs then
            for I in Register_Index loop
               if CPU.Registers (I) /= Old_Regs (I) then
                  Put_Line ("    REG: x" & Register_Index'Image (I) &
                           " = 0x" & To_Hex64 (Old_Regs (I)) &
                           " -> 0x" & To_Hex64 (CPU.Registers (I)));
               end if;
            end loop;
         end if;
      end if;

      CPU.PC := Next_PC;

      CSR64.Increment_Instret (CPU.CSRs);
      declare
         Cycles : Positive := 1;
      begin
         case Decoded.Opcode is
            when OPCODE_LOAD | OPCODE_LOAD_FP =>
               Cycles := 2;
            when OPCODE_JAL | OPCODE_JALR =>
               Cycles := 2;
            when OPCODE_BRANCH =>
               Cycles := (if Branch then 3 else 1);
            when OPCODE_OP =>
               if Decoded.Funct7 = FUNCT7_MULDIV then
                  case Decoded.Funct3 is
                     when FUNCT3_MUL    => Cycles := 3;
                     when FUNCT3_MULH | FUNCT3_MULHSU | FUNCT3_MULHU =>
                        Cycles := 5;
                     when others        => Cycles := 33;
                  end case;
               end if;
            when OPCODE_OP_FP =>
               case Decoded.Funct7 is
                  when FUNCT7_FADD_S | FUNCT7_FSUB_S |
                       FUNCT7_FADD_D | FUNCT7_FSUB_D |
                       FUNCT7_FADD_H | FUNCT7_FSUB_H => Cycles := 4;
                  when FUNCT7_FMUL_S | FUNCT7_FMUL_H => Cycles := 5;
                  when FUNCT7_FMUL_D                  => Cycles := 8;
                  when FUNCT7_FDIV_H                  => Cycles := 15;
                  when FUNCT7_FDIV_S                  => Cycles := 20;
                  when FUNCT7_FSQRT_H                 => Cycles := 20;
                  when FUNCT7_FDIV_D                  => Cycles := 30;
                  when FUNCT7_FSQRT_S                 => Cycles := 25;
                  when FUNCT7_FSQRT_D                 => Cycles := 35;
                  when others                         => Cycles := 3;
               end case;
            when OPCODE_FMADD | OPCODE_FMSUB |
                 OPCODE_FNMADD | OPCODE_FNMSUB =>
               Cycles := (if (Decoded.Funct7 and 3) = 1 then 8 else 5);
            when OPCODE_SYSTEM =>
               Cycles := 2;
            when others =>
               null;
         end case;
         CSR64.Increment_Mcycle (CPU.CSRs, Cycles);
      end;

      --  HTIF tohost write (riscv-tests) terminates the run.
      if Mem.HTIF_Enabled and then Mem.Tohost_Written then
         CPU.Halted := True;
      end if;
   end Step;

   ---------
   -- Run --
   ---------

   procedure Run (CPU        : in out CPU64_State;
                  Mem        : in out Memory.Memory_Unit;
                  Trace      : Boolean := False;
                  Trace_Cfg  : Trace_Config := (Enabled => False, others => <>);
                  Max_Cycles : Natural := Natural'Last) is
      Cycles : Natural := 0;
   begin
      while not CPU.Halted and Cycles < Max_Cycles loop
         declare
            Taken : Boolean;
         begin
            Taken := Check_Interrupts (CPU, Mem);
            pragma Unreferenced (Taken);
         end;
         Step (CPU, Mem, Trace, Trace_Cfg);
         Cycles := Cycles + 1;

         Memory.CLINT_Tick (Mem);
         Memory.Timer_Tick (Mem);

         if Memory.Watchdog_Tick (Mem) then
            Put_Line ("*** WATCHDOG TIMEOUT - System Reset ***");
            Initialize (CPU, Double_Word (CPU.Reset_Vector));
            Cycles := 0;
         end if;

         if Cycles mod 10 = 0 then
            declare
               DMA_Complete : Boolean;
            begin
               DMA_Complete := Memory.DMA_Process (Mem);
               pragma Unreferenced (DMA_Complete);
            end;
         end if;
      end loop;
   end Run;

   ----------------
   -- Dump_State --
   ----------------

   procedure Dump_State (CPU : CPU64_State) is
      package DW_IO is new Ada.Text_IO.Modular_IO (Double_Word);
      use DW_IO;
   begin
      Put_Line ("CPU64 State:");
      Put ("  PC = ");
      Put (Double_Word (CPU.PC), Width => 18, Base => 16);
      New_Line;

      Put_Line ("  Registers:");
      for I in Register_Index loop
         Put ("    x" & Register_Index'Image (I) & " = ");
         Put (CPU.Registers (I), Width => 18, Base => 16);
         if I mod 4 = 3 then
            New_Line;
         end if;
      end loop;
      New_Line;

      Put_Line ("  Halted: " & Boolean'Image (CPU.Halted));
      Put_Line ("  Exception: " & Exception_Code'Image (CPU.Exception_Code));
   end Dump_State;

   ----------------
   -- Trap_Entry --
   ----------------

   procedure Trap_Entry (CPU   : in out CPU64_State;
                         Cause : Double_Word;
                         Tval  : Double_Word := 0) is
      Is_Interrupt  : constant Boolean :=
         (Cause and CSR64.CAUSE_INTERRUPT_BIT) /= 0;
      Cause_Code    : constant Double_Word :=
         Cause and (not CSR64.CAUSE_INTERRUPT_BIT);
      Delegate_To_S : Boolean := False;
   begin
      --  Check delegation: only delegate from U or S mode (never from M)
      if CPU.Priv_Mode /= Machine then
         if Is_Interrupt then
            Delegate_To_S :=
               (CSR64.Read (CPU.CSRs, CSR64.CSR_MIDELEG) and
                Shift_Left (Double_Word (1), Natural (Cause_Code))) /= 0;
         else
            Delegate_To_S :=
               (CSR64.Read (CPU.CSRs, CSR64.CSR_MEDELEG) and
                Shift_Left (Double_Word (1), Natural (Cause_Code))) /= 0;
         end if;
      end if;

      if Delegate_To_S then
         --  Trap to S-mode
         declare
            Stvec   : constant Double_Word :=
               CSR64.Read (CPU.CSRs, CSR64.CSR_STVEC);
            Mstatus : constant Double_Word :=
               CSR64.Read (CPU.CSRs, CSR64.CSR_MSTATUS);
            Mode    : constant Double_Word := Stvec and 3;
            Base    : constant Double_Word := Stvec and (not Double_Word (3));
            Target  : Double_Word;
            New_Mstatus : Double_Word := Mstatus;
         begin
            if Stvec = 0 then
               CPU.Halted := True;
               return;
            end if;

            CSR64.Write (CPU.CSRs, CSR64.CSR_SEPC, Double_Word (CPU.PC));
            CSR64.Write (CPU.CSRs, CSR64.CSR_SCAUSE, Cause);
            CSR64.Write (CPU.CSRs, CSR64.CSR_STVAL, Tval);

            --  SPIE = old SIE
            if (Mstatus and CSR64.MSTATUS_SIE) /= 0 then
               New_Mstatus := New_Mstatus or CSR64.MSTATUS_SPIE;
            else
               New_Mstatus := New_Mstatus and (not CSR64.MSTATUS_SPIE);
            end if;
            New_Mstatus := New_Mstatus and (not CSR64.MSTATUS_SIE);
            if CPU.Priv_Mode = Supervisor then
               New_Mstatus := New_Mstatus or CSR64.MSTATUS_SPP;
            else
               New_Mstatus := New_Mstatus and (not CSR64.MSTATUS_SPP);
            end if;
            CSR64.Write (CPU.CSRs, CSR64.CSR_MSTATUS, New_Mstatus);

            if Mode = 1 and then Is_Interrupt then
               Target := Base + Shift_Left (Cause_Code, 2);
            else
               Target := Base;
            end if;

            CPU.PC := Memory_Address_64 (Target);
            CPU.Priv_Mode := Supervisor;
            CPU.Exception_Code := No_Exception;
         end;
      else
         --  Trap to M-mode
         declare
            Mtvec   : constant Double_Word :=
               CSR64.Read (CPU.CSRs, CSR64.CSR_MTVEC);
            Mstatus : constant Double_Word :=
               CSR64.Read (CPU.CSRs, CSR64.CSR_MSTATUS);
            Mode    : constant Double_Word := Mtvec and 3;
            Base    : constant Double_Word := Mtvec and (not Double_Word (3));
            Target  : Double_Word;
            New_Mstatus : Double_Word := Mstatus;
            Priv_Bits   : Double_Word;
         begin
            if Mtvec = 0 then
               CPU.Halted := True;
               return;
            end if;

            CSR64.Write (CPU.CSRs, CSR64.CSR_MEPC, Double_Word (CPU.PC));
            CSR64.Write (CPU.CSRs, CSR64.CSR_MCAUSE, Cause);
            CSR64.Write (CPU.CSRs, CSR64.CSR_MTVAL, Tval);

            --  MPIE = old MIE
            if (Mstatus and CSR64.MSTATUS_MIE) /= 0 then
               New_Mstatus := New_Mstatus or CSR64.MSTATUS_MPIE;
            else
               New_Mstatus := New_Mstatus and (not CSR64.MSTATUS_MPIE);
            end if;
            New_Mstatus := New_Mstatus and (not CSR64.MSTATUS_MIE);
            New_Mstatus := New_Mstatus and (not CSR64.MSTATUS_MPP_MASK);
            Priv_Bits := Double_Word (Privilege_Level'Pos (CPU.Priv_Mode));
            New_Mstatus := New_Mstatus or Shift_Left (Priv_Bits, 11);
            CSR64.Write (CPU.CSRs, CSR64.CSR_MSTATUS, New_Mstatus);

            if Mode = 1 and then Is_Interrupt then
               Target := Base + Shift_Left (Cause_Code, 2);
            else
               Target := Base;
            end if;

            CPU.PC := Memory_Address_64 (Target);
            CPU.Priv_Mode := Machine;
            CPU.Exception_Code := No_Exception;
         end;
      end if;
   end Trap_Entry;

   ----------
   -- Mret --
   ----------

   procedure Mret (CPU : in out CPU64_State) is
      Mstatus : constant Double_Word :=
         CSR64.Read (CPU.CSRs, CSR64.CSR_MSTATUS);
      Mepc    : constant Double_Word :=
         CSR64.Read (CPU.CSRs, CSR64.CSR_MEPC);
      New_Mstatus : Double_Word := Mstatus;
      MPP_Val     : constant Double_Word :=
         Shift_Right (Mstatus and CSR64.MSTATUS_MPP_MASK, 11);
   begin
      --  Restore MIE from MPIE
      if (Mstatus and CSR64.MSTATUS_MPIE) /= 0 then
         New_Mstatus := New_Mstatus or CSR64.MSTATUS_MIE;
      else
         New_Mstatus := New_Mstatus and (not CSR64.MSTATUS_MIE);
      end if;
      --  Set MPIE = 1
      New_Mstatus := New_Mstatus or CSR64.MSTATUS_MPIE;
      --  Clear MPP to 0 (User)
      New_Mstatus := New_Mstatus and (not CSR64.MSTATUS_MPP_MASK);

      CSR64.Write (CPU.CSRs, CSR64.CSR_MSTATUS, New_Mstatus);

      case MPP_Val is
         when 0 => CPU.Priv_Mode := User;
         when 1 => CPU.Priv_Mode := Supervisor;
         when 3 => CPU.Priv_Mode := Machine;
         when others => CPU.Priv_Mode := User;
      end case;

      --  mepc[0] is always masked; with C disabled (IALIGN=32) mepc[1] too.
      declare
         Target : Double_Word := Mepc and (not Double_Word (1));
      begin
         if not C_Ext_Enabled (CPU) then
            Target := Target and (not Double_Word (2));
         end if;
         CPU.PC := Memory_Address_64 (Target);
      end;

      --  A trap return breaks any outstanding load reservation, so a later
      --  SC cannot succeed across a context switch that happened between
      --  the LR and the SC.
      CPU.Reservation_Valid := False;
   end Mret;

   ----------
   -- Sret --
   ----------

   procedure Sret (CPU : in out CPU64_State) is
      Mstatus : constant Double_Word :=
         CSR64.Read (CPU.CSRs, CSR64.CSR_MSTATUS);
      Sepc    : constant Double_Word :=
         CSR64.Read (CPU.CSRs, CSR64.CSR_SEPC);
      New_Mstatus : Double_Word := Mstatus;
   begin
      --  Restore SIE from SPIE
      if (Mstatus and CSR64.MSTATUS_SPIE) /= 0 then
         New_Mstatus := New_Mstatus or CSR64.MSTATUS_SIE;
      else
         New_Mstatus := New_Mstatus and (not CSR64.MSTATUS_SIE);
      end if;
      --  Set SPIE = 1
      New_Mstatus := New_Mstatus or CSR64.MSTATUS_SPIE;
      --  Restore privilege from SPP
      if (Mstatus and CSR64.MSTATUS_SPP) /= 0 then
         CPU.Priv_Mode := Supervisor;
      else
         CPU.Priv_Mode := User;
      end if;
      --  Clear SPP
      New_Mstatus := New_Mstatus and (not CSR64.MSTATUS_SPP);

      CSR64.Write (CPU.CSRs, CSR64.CSR_MSTATUS, New_Mstatus);

      CPU.PC := Memory_Address_64 (Sepc);

      --  A trap return breaks any outstanding load reservation, so a later
      --  SC cannot succeed across a context switch that happened between
      --  the LR and the SC.
      CPU.Reservation_Valid := False;
   end Sret;

   ----------------------
   -- Check_Interrupts --
   ----------------------

   function Check_Interrupts (CPU : in out CPU64_State;
                               Mem : in out Memory.Memory_Unit) return Boolean is
      Mstatus   : constant Double_Word :=
         CSR64.Read (CPU.CSRs, CSR64.CSR_MSTATUS);
      Mie_Reg   : constant Double_Word :=
         CSR64.Read (CPU.CSRs, CSR64.CSR_MIE);
      Mip_Reg   : constant Double_Word :=
         CSR64.Read (CPU.CSRs, CSR64.CSR_MIP);
      M_Enabled : Boolean;
      S_Enabled : Boolean;
      Pending   : Double_Word;

      --  RV64 interrupt cause values (bit 63 set = interrupt)
      CAUSE_M_EXT  : constant Double_Word :=
         CSR64.CAUSE_INTERRUPT_BIT or 11;
      CAUSE_M_SOFT : constant Double_Word :=
         CSR64.CAUSE_INTERRUPT_BIT or 3;
      CAUSE_M_TIMER : constant Double_Word :=
         CSR64.CAUSE_INTERRUPT_BIT or 7;
      CAUSE_S_EXT  : constant Double_Word :=
         CSR64.CAUSE_INTERRUPT_BIT or 9;
      CAUSE_S_SOFT : constant Double_Word :=
         CSR64.CAUSE_INTERRUPT_BIT or 1;
      CAUSE_S_TIMER : constant Double_Word :=
         CSR64.CAUSE_INTERRUPT_BIT or 5;

      Mideleg_Reg : constant Double_Word :=
         CSR64.Read (CPU.CSRs, CSR64.CSR_MIDELEG);

      --  Which enable applies to an interrupt depends on where it is
      --  delegated to, not on which level named the bit.  An S-level
      --  interrupt that mideleg does NOT delegate still targets M-mode, and
      --  must be taken there regardless of mstatus.SIE.
      function Enabled_For (Bit : Double_Word) return Boolean is
      begin
         if (Mideleg_Reg and Bit) /= 0 then
            return S_Enabled;
         else
            return M_Enabled;
         end if;
      end Enabled_For;
   begin
      --  An interrupt targeting M-mode is taken whenever the hart runs below
      --  M, or in M with mstatus.MIE set.  One targeting S-mode is taken
      --  whenever the hart runs below S, or in S with mstatus.SIE set;
      --  M-mode never takes an S-targeted interrupt.
      M_Enabled := CPU.Priv_Mode /= Machine
                   or else (Mstatus and CSR64.MSTATUS_MIE) /= 0;
      S_Enabled := CPU.Priv_Mode in User | Reserved
                   or else (CPU.Priv_Mode = Supervisor
                            and then (Mstatus and CSR64.MSTATUS_SIE) /= 0);

      --  Update MIP from CLINT and PLIC
      declare
         New_Mip : Double_Word := Mip_Reg;
         Lo32    : Word;
      begin
         if Memory.CLINT_Enabled (Mem) then
            if Memory.CLINT_Timer_Interrupt_Pending (Mem) then
               New_Mip := New_Mip or CSR64.MIE_MTIE;
            else
               New_Mip := New_Mip and (not CSR64.MIE_MTIE);
            end if;
            if Memory.CLINT_Software_Interrupt_Pending (Mem) then
               New_Mip := New_Mip or CSR64.MIE_MSIE;
            else
               New_Mip := New_Mip and (not CSR64.MIE_MSIE);
            end if;
         end if;
         if Memory.PLIC_Enabled (Mem) then
            --  MEIP/SEIP are in the lower 32 bits of MIP
            Lo32 := Memory.PLIC_Update_Mip (Mem, Word (New_Mip and 16#FFFF_FFFF#));
            New_Mip := (New_Mip and 16#FFFF_FFFF_0000_0000#) or Double_Word (Lo32);
         end if;
         CSR64.Write (CPU.CSRs, CSR64.CSR_MIP, New_Mip);
      end;

      Pending := CSR64.Read (CPU.CSRs, CSR64.CSR_MIP) and Mie_Reg;

      if Pending = 0 then
         return False;
      end if;

      --  Priority: MEI > MSI > MTI > SEI > SSI > STI
      if (Pending and CSR64.MIE_MEIE) /= 0
        and then Enabled_For (CSR64.MIE_MEIE)
      then
         Trap_Entry (CPU, CAUSE_M_EXT);
         return True;
      elsif (Pending and CSR64.MIE_MSIE) /= 0
        and then Enabled_For (CSR64.MIE_MSIE)
      then
         Trap_Entry (CPU, CAUSE_M_SOFT);
         return True;
      elsif (Pending and CSR64.MIE_MTIE) /= 0
        and then Enabled_For (CSR64.MIE_MTIE)
      then
         Trap_Entry (CPU, CAUSE_M_TIMER);
         return True;
      elsif (Pending and CSR64.MIE_SEIE) /= 0
        and then Enabled_For (CSR64.MIE_SEIE)
      then
         Trap_Entry (CPU, CAUSE_S_EXT);
         return True;
      elsif (Pending and CSR64.MIE_SSIE) /= 0
        and then Enabled_For (CSR64.MIE_SSIE)
      then
         Trap_Entry (CPU, CAUSE_S_SOFT);
         return True;
      elsif (Pending and CSR64.MIE_STIE) /= 0
        and then Enabled_For (CSR64.MIE_STIE)
      then
         Trap_Entry (CPU, CAUSE_S_TIMER);
         return True;
      end if;

      return False;
   end Check_Interrupts;

   ----------------------
   -- Add_Cycle_Stalls --
   ----------------------

   procedure Add_Cycle_Stalls (CPU   : in out CPU64_State;
                                Count : Natural) is
   begin
      --  CY bit (bit 0) of Mcountinhibit: if set, mcycle is frozen
      if (CPU.CSRs.Mcountinhibit and 1) = 0 then
         CPU.CSRs.Mcycle := CPU.CSRs.Mcycle + Unsigned_64 (Count);
      end if;
   end Add_Cycle_Stalls;

end RISCV.CPU64;
