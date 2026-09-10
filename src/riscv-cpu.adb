-- ***************************************************************************
--                RISC-V Emulator - CPU Core
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
with RISCV.ALU;
with RISCV.Disasm;
with RISCV.Compressed;
with RISCV.Crypto;
with RISCV.CLINT;
with RISCV.UART;
with RISCV.Term_IO;

package body RISCV.CPU is

   --  Access_Result comparisons in the load/store paths below.
   use type Memory.Access_Result;

   function To_Word is new Ada.Unchecked_Conversion (Signed_Word, Word);
   function To_Signed is new Ada.Unchecked_Conversion (Word, Signed_Word);

   ----------------
   -- Initialize --
   ----------------

   procedure Initialize (CPU : out CPU_State; Start_PC : Word := 0) is
   begin
      CPU.Registers := (others => 0);
      FPU.Initialize (CPU.FP);
      Vector.Initialize (CPU.VU);
      CSR.Initialize (CPU.CSRs);
      CPU.PC             := Start_PC;
      CPU.Reset_Vector   := Start_PC;
      CPU.Halted         := False;
      CPU.Exception_Code := No_Exception;
      --  A Extension: initialize reservation as invalid
      CPU.Reserved_Addr     := 0;
      CPU.Reservation_Valid := False;
      CPU.Priv_Mode         := Machine;
      CPU.Hart_ID           := 0;
   end Initialize;

   -------------------
   -- Read_Register --
   -------------------

   function Read_Register (CPU : CPU_State;
                           Reg : Register_Index) return Word is
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

   procedure Write_Register (CPU   : in out CPU_State;
                             Reg   : Register_Index;
                             Value : Word) is
   begin
      if Reg /= 0 then
         CPU.Registers (Reg) := Value;
      end if;
   end Write_Register;

   --  Is the C (compressed) extension currently enabled (misa bit 2 = 1)?
   --  When disabled, IALIGN=32 and control-transfer targets must be 4-byte
   --  aligned, else an instruction-address-misaligned exception is raised.
   function C_Ext_Enabled (CPU : CPU_State) return Boolean is
   begin
      return (CSR.Read (CPU.CSRs, CSR.CSR_MISA) and 2#100#) /= 0;
   end C_Ext_Enabled;

   ----------
   -- Step --
   ----------

   procedure Step (CPU         : in out CPU_State;
                   Mem         : in out Memory.Memory_Unit;
                   Trace       : Boolean := False;
                   Trace_Cfg   : Trace_Config := (Enabled => False, others => <>)) is
      use Decoder;
      use ALU;

      Instruction   : Word;
      Decoded       : Decoded_Instruction;
      Rs1_Val       : Word;
      Rs2_Val       : Word;
      Result        : Word;
      Address       : Memory_Address;
      Next_PC       : Word;
      Branch        : Boolean;
      Old_Regs      : Register_File;
      Trace_Enabled : Boolean;

      function To_Hex (V : Word) return String;

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

      Is_Compressed : Boolean;
      Instr_Size    : Word;
      Extra_Cycles  : Natural := 0;   --  Extra mcycle cost beyond the base 1

   begin
      if CPU.Halted then
         return;
      end if;

      --  Fetch instruction: check for compressed (16-bit) first.
      --  The low half-word is fetched on its own so that a 16-bit
      --  instruction in the last half-word of a region does not fault on
      --  the two bytes past its end that a full word fetch would touch.
      Memory.Clear_Access_Fault (Mem);
      declare
         Lo   : Half_Word;
         Hi   : Half_Word;
         Both : Boolean;
      begin
         Memory.Read_Insn_Halves
            (Mem, Memory_Address (CPU.PC), Lo, Hi, Both);
         if Memory.Pending_Fault (Mem) /= Memory.OK then
            CPU.Exception_Code := Insn_Access_Fault;
            Trap_Entry (CPU, CSR.CAUSE_INSN_ACCESS_FAULT, CPU.PC);
            return;
         end if;

         if Compressed.Is_Compressed (Word (Lo)) then
            --  16-bit compressed instruction
            Is_Compressed := True;
            Instr_Size := 2;
            --  Expand compressed to 32-bit equivalent
            Instruction := Compressed.Expand (Lo);
            if Instruction = Compressed.ILLEGAL_INSTR then
               CPU.Exception_Code := Illegal_Instruction;
               Trap_Entry (CPU, CSR.CAUSE_ILLEGAL_INSN, Instruction);
               return;
            end if;
         else
            Is_Compressed := False;
            Instr_Size := 4;
            if not Both then
               Hi := Memory.Read_Half_Word
                        (Mem, Memory_Address (CPU.PC) + 2);
               if Memory.Pending_Fault (Mem) /= Memory.OK then
                  CPU.Exception_Code := Insn_Access_Fault;
                  Trap_Entry (CPU, CSR.CAUSE_INSN_ACCESS_FAULT, CPU.PC);
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
         Memory_Address (CPU.PC) >= Trace_Cfg.PC_Start and then
         Memory_Address (CPU.PC) <= Trace_Cfg.PC_End;

      --  Save old register state if register tracing enabled
      if Trace_Enabled and Trace_Cfg.Show_Regs then
         Old_Regs := CPU.Registers;
      end if;

      --  Print instruction trace
      if Trace_Enabled then
         if Is_Compressed then
            Put (To_Hex (CPU.PC) & ":      " &
                 To_Hex (Instruction) & "  [C] ");
         else
            Put (To_Hex (CPU.PC) & ":  " & To_Hex (Instruction) & "  ");
         end if;
         Put_Line (Disasm.Disassemble (Instruction, CPU.PC));
      end if;

      --  Read source registers
      Rs1_Val := Read_Register (CPU, Decoded.Rs1);
      Rs2_Val := Read_Register (CPU, Decoded.Rs2);

      --  Default: advance to next instruction
      Next_PC := CPU.PC + Instr_Size;
      Branch := False;

      --  Load-use hazard: +1 stall cycle if previous instruction was a LOAD
      --  and the current instruction reads the loaded register.
      if CPU.Last_Was_Load and CPU.Last_Load_Rd /= 0 then
         declare
            Op : constant Word := Instruction and 16#7F#;
         begin
            if Decoded.Rs1 = CPU.Last_Load_Rd or
               ((Op = OPCODE_OP or Op = OPCODE_STORE or
                 Op = OPCODE_BRANCH or Op = OPCODE_OP_32) and
                Decoded.Rs2 = CPU.Last_Load_Rd)
            then
               Extra_Cycles := Extra_Cycles + 1;
            end if;
         end;
      end if;
      CPU.Last_Was_Load := False;  --  Reset; set True below if this is a load

      case Decoded.Opcode is

         -----------------
         -- LUI (U-type)
         -----------------
         when OPCODE_LUI =>
            Write_Register (CPU, Decoded.Rd, Decoded.Imm_U);

         -------------------
         -- AUIPC (U-type)
         -------------------
         when OPCODE_AUIPC =>
            Write_Register (CPU, Decoded.Rd, CPU.PC + Decoded.Imm_U);

         -----------------
         -- JAL (J-type)
         -----------------
         when OPCODE_JAL =>
            Next_PC := To_Word (To_Signed (CPU.PC) + Decoded.Imm_J);
            --  With C disabled (IALIGN=32), a target that is not 4-byte
            --  aligned faults on the jump itself and rd is left unwritten.
            if (Next_PC and 2) /= 0 and then not C_Ext_Enabled (CPU) then
               CPU.Exception_Code := Misaligned_Fetch;
               Trap_Entry (CPU, CSR.CAUSE_INSN_MISALIGNED, Next_PC);
               return;
            end if;
            Write_Register (CPU, Decoded.Rd, CPU.PC + Instr_Size);
            Branch := True;

         ------------------
         -- JALR (I-type)
         ------------------
         when OPCODE_JALR =>
            Result := To_Word (To_Signed (Rs1_Val) + Decoded.Imm_I);
            Result := Result and 16#FFFFFFFE#;  -- Clear LSB
            Next_PC := Result;
            if (Next_PC and 2) /= 0 and then not C_Ext_Enabled (CPU) then
               CPU.Exception_Code := Misaligned_Fetch;
               Trap_Entry (CPU, CSR.CAUSE_INSN_MISALIGNED, Next_PC);
               return;
            end if;
            Write_Register (CPU, Decoded.Rd, CPU.PC + Instr_Size);
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
                  Branch := To_Signed (Rs1_Val) < To_Signed (Rs2_Val);
               when FUNCT3_BGE =>
                  Branch := To_Signed (Rs1_Val) >= To_Signed (Rs2_Val);
               when FUNCT3_BLTU =>
                  Branch := Rs1_Val < Rs2_Val;
               when FUNCT3_BGEU =>
                  Branch := Rs1_Val >= Rs2_Val;
               when others =>
                  CPU.Exception_Code := Illegal_Instruction;
                  Trap_Entry (CPU, CSR.CAUSE_ILLEGAL_INSN, Instruction);
                  return;
            end case;

            if Branch then
               Next_PC := To_Word (To_Signed (CPU.PC) + Decoded.Imm_B);
               if (Next_PC and 2) /= 0 and then not C_Ext_Enabled (CPU) then
                  CPU.Exception_Code := Misaligned_Fetch;
                  Trap_Entry (CPU, CSR.CAUSE_INSN_MISALIGNED, Next_PC);
                  return;
               end if;
            end if;

         -------------------
         -- Loads (I-type)
         -------------------
         when OPCODE_LOAD =>
            Address := Memory_Address (To_Word (To_Signed (Rs1_Val) + Decoded.Imm_I));
            Memory.Clear_Access_Fault (Mem);

            case Decoded.Funct3 is
               when FUNCT3_LB =>
                  Result := Word (Memory.Read_Byte (Mem, Address));
                  --  Sign extend from 8 bits
                  if (Result and 16#80#) /= 0 then
                     Result := Result or 16#FFFFFF00#;
                  end if;

               when FUNCT3_LH =>
                  --  Misaligned loads are emulated (byte-composed accessors).
                  Result := Word (Memory.Read_Half_Word (Mem, Address));
                  --  Sign extend from 16 bits
                  if (Result and 16#8000#) /= 0 then
                     Result := Result or 16#FFFF0000#;
                  end if;

               when FUNCT3_LW =>
                  Result := Memory.Read_Word (Mem, Address);

               when FUNCT3_LBU =>
                  Result := Word (Memory.Read_Byte (Mem, Address));

               when FUNCT3_LHU =>
                  Result := Word (Memory.Read_Half_Word (Mem, Address));

               when others =>
                  CPU.Exception_Code := Illegal_Instruction;
                  Trap_Entry (CPU, CSR.CAUSE_ILLEGAL_INSN, Instruction);
                  return;
            end case;

            --  An unmapped or unreadable byte anywhere in the access is a
            --  load access fault; rd must be left unwritten.
            if Memory.Pending_Fault (Mem) /= Memory.OK then
               CPU.Exception_Code := Load_Access_Fault;
               Trap_Entry (CPU, CSR.CAUSE_LOAD_ACCESS_FAULT,
                           Word (Memory.Pending_Fault_Address (Mem)));
               return;
            end if;

            Write_Register (CPU, Decoded.Rd, Result);

            --  Record load for load-use hazard detection
            CPU.Last_Was_Load := True;
            CPU.Last_Load_Rd  := Decoded.Rd;

         --------------------
         -- Stores (S-type)
         --------------------
         when OPCODE_STORE =>
            Address := Memory_Address (To_Word (To_Signed (Rs1_Val) + Decoded.Imm_S));
            Memory.Clear_Access_Fault (Mem);

            case Decoded.Funct3 is
               when FUNCT3_SB =>
                  Memory.Write_Byte (Mem, Address, Byte (Rs2_Val and 16#FF#));

               when FUNCT3_SH =>
                  --  Misaligned stores are emulated (byte-composed accessors).
                  Memory.Write_Half_Word (Mem, Address, Half_Word (Rs2_Val and 16#FFFF#));

               when FUNCT3_SW =>
                  Memory.Write_Word (Mem, Address, Rs2_Val);

               when others =>
                  CPU.Exception_Code := Illegal_Instruction;
                  Trap_Entry (CPU, CSR.CAUSE_ILLEGAL_INSN, Instruction);
                  return;
            end case;

            --  A store to unmapped memory, or to a read-only region, is a
            --  store access fault rather than a silent no-op.
            if Memory.Pending_Fault (Mem) /= Memory.OK then
               CPU.Exception_Code := Store_Access_Fault;
               Trap_Entry (CPU, CSR.CAUSE_STORE_ACCESS_FAULT,
                           Word (Memory.Pending_Fault_Address (Mem)));
               return;
            end if;

         ----------------------------
         -- OP-IMM (I-type ALU ops)
         ----------------------------
         when OPCODE_OP_IMM =>
            declare
               Imm   : constant Word := To_Word (Decoded.Imm_I);
               Shamt : constant Natural := Natural (Imm and 16#1F#);
               Bad   : Boolean := False;
            begin
               case Decoded.Funct3 is
                  when FUNCT3_ADD_SUB =>
                     Result := Add (Rs1_Val, Imm);
                  when FUNCT3_SLT =>
                     Result := Set_Less_Than (Rs1_Val, Imm);
                  when FUNCT3_SLTU =>
                     Result := Set_Less_Than_Unsigned (Rs1_Val, Imm);
                  when FUNCT3_XOR =>
                     Result := Op_Xor (Rs1_Val, Imm);
                  when FUNCT3_OR =>
                     Result := Op_Or (Rs1_Val, Imm);
                  when FUNCT3_AND =>
                     Result := Op_And (Rs1_Val, Imm);
                  when FUNCT3_SLL =>
                     --  Exact funct7 match. Anything not listed is reserved
                     --  and traps instead of running as SLLI -- including
                     --  instruction bit 25 set (shamt >= 32), which leaves
                     --  funct7 odd.
                     case Decoded.Funct7 is
                        when 2#0000000# =>
                           Result := Shift_Left_Logical (Rs1_Val, Shamt);
                        when 2#0110000# =>
                           --  Zbb unary ops, rs2 selects the operation
                           case Word (Decoded.Rs2) is
                              when ZBB_CLZ_RS2   => Result := Crypto.CLZ    (Rs1_Val);
                              when ZBB_CTZ_RS2   => Result := Crypto.CTZ    (Rs1_Val);
                              when ZBB_CPOP_RS2  => Result := Crypto.CPOP   (Rs1_Val);
                              when ZBB_SEXTB_RS2 => Result := Crypto.SEXT_B (Rs1_Val);
                              when ZBB_SEXTH_RS2 => Result := Crypto.SEXT_H (Rs1_Val);
                              when others        => Bad := True;
                           end case;
                        when 2#0010100# =>
                           --  bseti
                           Result := Crypto.BSET (Rs1_Val, Word (Shamt));
                        when 2#0100100# =>
                           --  bclri
                           Result := Crypto.BCLR (Rs1_Val, Word (Shamt));
                        when 2#0110100# =>
                           --  binvi
                           Result := Crypto.BINV (Rs1_Val, Word (Shamt));
                        when 2#0000100# =>
                           --  zip (Zbkb, RV32 only): rs2 = 01111
                           if Shamt = 15 then
                              Result := Crypto.ZIP (Rs1_Val);
                           else
                              Bad := True;
                           end if;
                        when 2#0001000# =>
                           --  SHA-256 / SM3 unary ops, rs2 selects
                           case Word (Decoded.Rs2) is
                              when SHA256_SUM0_RS2 => Result := Crypto.SHA256SUM0 (Rs1_Val);
                              when SHA256_SUM1_RS2 => Result := Crypto.SHA256SUM1 (Rs1_Val);
                              when SHA256_SIG0_RS2 => Result := Crypto.SHA256SIG0 (Rs1_Val);
                              when SHA256_SIG1_RS2 => Result := Crypto.SHA256SIG1 (Rs1_Val);
                              when SM3P0_RS2       => Result := Crypto.SM3P0 (Rs1_Val);
                              when SM3P1_RS2       => Result := Crypto.SM3P1 (Rs1_Val);
                              when others          => Bad := True;
                           end case;
                        when others =>
                           Bad := True;
                     end case;
                  when FUNCT3_SRL_SRA =>
                     case Decoded.Funct7 is
                        when 2#0000000# =>
                           Result := Shift_Right_Logical (Rs1_Val, Shamt);
                        when 2#0100000# =>
                           Result := Shift_Right_Arithmetic (Rs1_Val, Shamt);
                        when 2#0110000# =>
                           --  rori
                           Result := Crypto.RORI (Rs1_Val, Shamt);
                        when 2#0100100# =>
                           --  bexti
                           Result := Crypto.BEXT (Rs1_Val, Word (Shamt));
                        when 2#0010100# =>
                           --  orc.b: rs2 = 00111
                           if Word (Decoded.Rs2) = ZBB_ORCB_RS2 then
                              Result := Crypto.ORC_B (Rs1_Val);
                           else
                              Bad := True;
                           end if;
                        when 2#0110100# =>
                           --  rev8 (rs2 = 11000) and brev8 (rs2 = 00111)
                           if Word (Decoded.Rs2) = 16#18# then
                              Result := Crypto.REV8 (Rs1_Val);
                           elsif Word (Decoded.Rs2) = 7 then
                              Result := Crypto.BREV8 (Rs1_Val);
                           else
                              Bad := True;
                           end if;
                        when 2#0000100# =>
                           --  unzip (Zbkb, RV32 only): rs2 = 01111
                           if Shamt = 15 then
                              Result := Crypto.UNZIP (Rs1_Val);
                           else
                              Bad := True;
                           end if;
                        when others =>
                           Bad := True;
                     end case;
                  when others =>
                     Bad := True;
               end case;

               if Bad then
                  CPU.Exception_Code := Illegal_Instruction;
                  Trap_Entry (CPU, CSR.CAUSE_ILLEGAL_INSN, Instruction);
                  return;
               end if;
            end;

            Write_Register (CPU, Decoded.Rd, Result);

         -------------------------
         -- OP (R-type ALU ops)
         -------------------------
         when OPCODE_OP =>
            declare
               Shamt  : constant Natural := Natural (Rs2_Val and 16#1F#);
               Funct5 : constant Word :=
                  Shift_Right (Instruction, 25) and 16#1F#;
               BS     : constant Natural :=
                  Natural (Shift_Right (Instruction, 30));
               Bad    : Boolean := False;
            begin
               --  Dispatch on funct7 and then funct3. Every pair not listed
               --  is reserved and traps, rather than running as whichever
               --  base op shares its funct3.
               case Decoded.Funct7 is
                  when 2#0000000# =>
                     case Decoded.Funct3 is
                        when FUNCT3_ADD_SUB => Result := Add (Rs1_Val, Rs2_Val);
                        when FUNCT3_SLL     => Result := Shift_Left_Logical (Rs1_Val, Shamt);
                        when FUNCT3_SLT     => Result := Set_Less_Than (Rs1_Val, Rs2_Val);
                        when FUNCT3_SLTU    => Result := Set_Less_Than_Unsigned (Rs1_Val, Rs2_Val);
                        when FUNCT3_XOR     => Result := Op_Xor (Rs1_Val, Rs2_Val);
                        when FUNCT3_SRL_SRA => Result := Shift_Right_Logical (Rs1_Val, Shamt);
                        when FUNCT3_OR      => Result := Op_Or (Rs1_Val, Rs2_Val);
                        when FUNCT3_AND     => Result := Op_And (Rs1_Val, Rs2_Val);
                        when others         => Bad := True;
                     end case;
                  when 2#0100000# =>
                     --  sub, sra, and the Zbb/Zbkb inverted logic ops
                     case Decoded.Funct3 is
                        when FUNCT3_ADD_SUB => Result := Sub (Rs1_Val, Rs2_Val);
                        when FUNCT3_SRL_SRA => Result := Shift_Right_Arithmetic (Rs1_Val, Shamt);
                        when FUNCT3_XOR     => Result := Crypto.XNOR_Op (Rs1_Val, Rs2_Val);
                        when FUNCT3_OR      => Result := Crypto.ORN (Rs1_Val, Rs2_Val);
                        when FUNCT3_AND     => Result := Crypto.ANDN (Rs1_Val, Rs2_Val);
                        when others         => Bad := True;
                     end case;
                  when 2#0000001# =>
                     --  M extension
                     case Decoded.Funct3 is
                        when FUNCT3_MUL =>
                           Result := Mul (Rs1_Val, Rs2_Val);
                           Extra_Cycles := 2;   --  3 cycles total
                        when FUNCT3_MULH =>
                           Result := Mulh (Rs1_Val, Rs2_Val);
                           Extra_Cycles := 2;
                        when FUNCT3_MULHSU =>
                           Result := Mulhsu (Rs1_Val, Rs2_Val);
                           Extra_Cycles := 2;
                        when FUNCT3_MULHU =>
                           Result := Mulhu (Rs1_Val, Rs2_Val);
                           Extra_Cycles := 2;
                        when FUNCT3_DIV =>
                           Result := Div (Rs1_Val, Rs2_Val);
                           Extra_Cycles := 32;  --  33 cycles total
                        when FUNCT3_DIVU =>
                           Result := Divu (Rs1_Val, Rs2_Val);
                           Extra_Cycles := 32;
                        when FUNCT3_REM =>
                           Result := Op_Rem (Rs1_Val, Rs2_Val);
                           Extra_Cycles := 32;
                        when FUNCT3_REMU =>
                           Result := Remu (Rs1_Val, Rs2_Val);
                           Extra_Cycles := 32;
                        when others =>
                           Bad := True;
                     end case;
                  when 2#0010000# =>
                     --  Zba: sh1add / sh2add / sh3add
                     case Decoded.Funct3 is
                        when FUNCT3_SLT => Result := Add (Shift_Left_Logical (Rs1_Val, 1), Rs2_Val);
                        when FUNCT3_XOR => Result := Add (Shift_Left_Logical (Rs1_Val, 2), Rs2_Val);
                        when FUNCT3_OR  => Result := Add (Shift_Left_Logical (Rs1_Val, 3), Rs2_Val);
                        when others     => Bad := True;
                     end case;
                  when 2#0000101# =>
                     --  Zbc/Zbkc carry-less multiply, Zbb min/max
                     case Decoded.Funct3 is
                        when FUNCT3_SLL     => Result := Crypto.CLMUL (Rs1_Val, Rs2_Val);
                        when FUNCT3_SLT     => Result := Crypto.CLMULR (Rs1_Val, Rs2_Val);
                        when FUNCT3_SLTU    => Result := Crypto.CLMULH (Rs1_Val, Rs2_Val);
                        when FUNCT3_XOR     => Result := Crypto.ZBB_MIN (Rs1_Val, Rs2_Val);
                        when FUNCT3_SRL_SRA => Result := Crypto.ZBB_MINU (Rs1_Val, Rs2_Val);
                        when FUNCT3_OR      => Result := Crypto.ZBB_MAX (Rs1_Val, Rs2_Val);
                        when FUNCT3_AND     => Result := Crypto.ZBB_MAXU (Rs1_Val, Rs2_Val);
                        when others         => Bad := True;
                     end case;
                  when 2#0110000# =>
                     --  Zbb/Zbkb rotates
                     case Decoded.Funct3 is
                        when FUNCT3_SLL     => Result := Crypto.ROL (Rs1_Val, Rs2_Val);
                        when FUNCT3_SRL_SRA => Result := Crypto.ROR_Op (Rs1_Val, Rs2_Val);
                        when others         => Bad := True;
                     end case;
                  when 2#0000111# =>
                     --  Zicond
                     case Decoded.Funct3 is
                        when FUNCT3_SRL_SRA =>
                           --  czero.eqz: rd = (rs2 == 0) ? 0 : rs1
                           Result := (if Rs2_Val = 0 then 0 else Rs1_Val);
                        when FUNCT3_AND =>
                           --  czero.nez: rd = (rs2 != 0) ? 0 : rs1
                           Result := (if Rs2_Val /= 0 then 0 else Rs1_Val);
                        when others =>
                           Bad := True;
                     end case;
                  when 2#0010100# =>
                     --  Zbs bset, Zbkx xperm4 / xperm8
                     case Decoded.Funct3 is
                        when FUNCT3_SLL => Result := Crypto.BSET (Rs1_Val, Rs2_Val);
                        when FUNCT3_SLT => Result := Crypto.XPERM4 (Rs1_Val, Rs2_Val);
                        when FUNCT3_XOR => Result := Crypto.XPERM8 (Rs1_Val, Rs2_Val);
                        when others     => Bad := True;
                     end case;
                  when 2#0100100# =>
                     --  Zbs bclr / bext
                     case Decoded.Funct3 is
                        when FUNCT3_SLL     => Result := Crypto.BCLR (Rs1_Val, Rs2_Val);
                        when FUNCT3_SRL_SRA => Result := Crypto.BEXT (Rs1_Val, Rs2_Val);
                        when others         => Bad := True;
                     end case;
                  when 2#0110100# =>
                     --  Zbs binv
                     case Decoded.Funct3 is
                        when FUNCT3_SLL => Result := Crypto.BINV (Rs1_Val, Rs2_Val);
                        when others     => Bad := True;
                     end case;
                  when 2#0000100# =>
                     --  Zbkb pack (zext.h when rs2 = x0) / packh
                     case Decoded.Funct3 is
                        when FUNCT3_XOR => Result := Crypto.PACK (Rs1_Val, Rs2_Val);
                        when FUNCT3_AND => Result := Crypto.PACKH (Rs1_Val, Rs2_Val);
                        when others     => Bad := True;
                     end case;
                  when 2#0101110# | 2#0101010# | 2#0101111# |
                       2#0101011# | 2#0101000# | 2#0101001# =>
                     --  Zknh SHA-512 paired ops (RV32), funct3 = 000 only
                     if Decoded.Funct3 /= FUNCT3_ADD_SUB then
                        Bad := True;
                     else
                        case Decoded.Funct7 is
                           when 2#0101110# => Result := Crypto.SHA512SIG0H (Rs1_Val, Rs2_Val);
                           when 2#0101010# => Result := Crypto.SHA512SIG0L (Rs1_Val, Rs2_Val);
                           when 2#0101111# => Result := Crypto.SHA512SIG1H (Rs1_Val, Rs2_Val);
                           when 2#0101011# => Result := Crypto.SHA512SIG1L (Rs1_Val, Rs2_Val);
                           when 2#0101000# => Result := Crypto.SHA512SUM0R (Rs1_Val, Rs2_Val);
                           when 2#0101001# => Result := Crypto.SHA512SUM1R (Rs1_Val, Rs2_Val);
                           when others     => Bad := True;
                        end case;
                     end if;
                  when others =>
                     --  AES / SM4 (Zkne, Zknd, Zksed): funct3 = 000,
                     --  funct5 in [29:25], byte select in [31:30]. Their
                     --  funct7 values collide with none of the choices above.
                     if Decoded.Funct3 /= FUNCT3_ADD_SUB then
                        Bad := True;
                     else
                        case Funct5 is
                           when FUNCT5_AES32ESI  => Result := Crypto.AES32ESI (Rs1_Val, Rs2_Val, BS);
                           when FUNCT5_AES32ESMI => Result := Crypto.AES32ESMI (Rs1_Val, Rs2_Val, BS);
                           when FUNCT5_AES32DSI  => Result := Crypto.AES32DSI (Rs1_Val, Rs2_Val, BS);
                           when FUNCT5_AES32DSMI => Result := Crypto.AES32DSMI (Rs1_Val, Rs2_Val, BS);
                           when FUNCT5_SM4ED     => Result := Crypto.SM4ED (Rs1_Val, Rs2_Val, BS);
                           when FUNCT5_SM4KS     => Result := Crypto.SM4KS (Rs1_Val, Rs2_Val, BS);
                           when others           => Bad := True;
                        end case;
                     end if;
               end case;

               if Bad then
                  CPU.Exception_Code := Illegal_Instruction;
                  Trap_Entry (CPU, CSR.CAUSE_ILLEGAL_INSN, Instruction);
                  return;
               end if;
            end;

            Write_Register (CPU, Decoded.Rd, Result);

         ----------------------
         -- SYSTEM (I-type)
         ----------------------
         when OPCODE_SYSTEM =>
            if Decoded.Funct3 = FUNCT3_ECALL_EBREAK then
               if Instruction = 16#30200073# then
                  --  MRET: return from machine trap
                  --  Illegal if not in M-mode
                  if CPU.Priv_Mode /= Machine then
                     CPU.Exception_Code := Illegal_Instruction;
                     Trap_Entry (CPU, CSR.CAUSE_ILLEGAL_INSN, Instruction);
                     CSR.Increment_Instret (CPU.CSRs);
                     CSR.Increment_Mcycle (CPU.CSRs);
                     return;
                  end if;
                  Mret (CPU);
                  CSR.Increment_Instret (CPU.CSRs);
                  CSR.Increment_Mcycle (CPU.CSRs);
                  return;
               elsif Instruction = 16#10200073# then
                  --  SRET: return from supervisor trap
                  --  Illegal if in U-mode
                  if CPU.Priv_Mode = User then
                     CPU.Exception_Code := Illegal_Instruction;
                     Trap_Entry (CPU, CSR.CAUSE_ILLEGAL_INSN, Instruction);
                     CSR.Increment_Instret (CPU.CSRs);
                     CSR.Increment_Mcycle (CPU.CSRs);
                     return;
                  end if;
                  --  mstatus.TSR lets M-mode firmware intercept supervisor
                  --  trap returns; with it set, SRET from S-mode is illegal.
                  if CPU.Priv_Mode = Supervisor and then
                     (CSR.Read (CPU.CSRs, CSR.CSR_MSTATUS)
                      and CSR.MSTATUS_TSR) /= 0
                  then
                     CPU.Exception_Code := Illegal_Instruction;
                     Trap_Entry (CPU, CSR.CAUSE_ILLEGAL_INSN, Instruction);
                     CSR.Increment_Instret (CPU.CSRs);
                     CSR.Increment_Mcycle (CPU.CSRs);
                     return;
                  end if;
                  Sret (CPU);
                  CSR.Increment_Instret (CPU.CSRs);
                  CSR.Increment_Mcycle (CPU.CSRs);
                  return;
               elsif Instruction = 16#10500073# then
                  --  WFI: treat as NOP, but mstatus.TW makes it illegal
                  --  outside M-mode so firmware can police idling guests.
                  if CPU.Priv_Mode /= Machine and then
                     (CSR.Read (CPU.CSRs, CSR.CSR_MSTATUS)
                      and CSR.MSTATUS_TW) /= 0
                  then
                     CPU.Exception_Code := Illegal_Instruction;
                     Trap_Entry (CPU, CSR.CAUSE_ILLEGAL_INSN, Instruction);
                     CSR.Increment_Instret (CPU.CSRs);
                     CSR.Increment_Mcycle (CPU.CSRs);
                     return;
                  end if;
                  null;
               elsif (Instruction and 16#FE007FFF#) = 16#12000073# then
                  --  SFENCE.VMA: treat as NOP, but mstatus.TVM makes it
                  --  illegal in S-mode so a hypervisor can shadow the tables.
                  if CPU.Priv_Mode = Supervisor and then
                     (CSR.Read (CPU.CSRs, CSR.CSR_MSTATUS)
                      and CSR.MSTATUS_TVM) /= 0
                  then
                     CPU.Exception_Code := Illegal_Instruction;
                     Trap_Entry (CPU, CSR.CAUSE_ILLEGAL_INSN, Instruction);
                     CSR.Increment_Instret (CPU.CSRs);
                     CSR.Increment_Mcycle (CPU.CSRs);
                     return;
                  end if;
                  null;
               elsif Decoded.Imm_I = 0 then
                  --  ECALL: check for host logging syscalls first (a7 = number)
                  declare
                     use RISCV.Memory;  --  makes Log_File_Access visible for allocator
                     Syscall_Num  : constant Word := Read_Register (CPU, 17);
                     A0_Val       : constant Word := Read_Register (CPU, 10);
                     A1_Val       : constant Word := Read_Register (CPU, 11);
                     Is_Host_Call : Boolean := False;

                     function Img (N : Natural) return String is
                        S : constant String := Natural'Image (N);
                     begin
                        return S (S'First + 1 .. S'Last);
                     end Img;

                  begin
                     case Syscall_Num is

                        when 16#500# =>
                           --  HOST_LOG_OPEN: create log file on host
                           --  a0 = pointer to filename, a1 = filename length
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
                                 Write_Register (CPU, 10, Word'Last);
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
                                 Write_Register (CPU, 10, Word'Last);
                           end;
                           Is_Host_Call := True;

                        when 16#501# =>
                           --  HOST_LOG_WRITE: write bytes to log file
                           --  a0 = data pointer, a1 = byte count
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
                                 Write_Register (CPU, 10, Word (Len));
                              end;
                           else
                              Write_Register (CPU, 10, 0);
                           end if;
                           Is_Host_Call := True;

                        when 16#502# =>
                           --  HOST_LOG_CLOSE: close log file
                           if Mem.Log_File_Open then
                              Close (Mem.Log_File.all);
                              Mem.Log_File_Open := False;
                           end if;
                           Write_Register (CPU, 10, 0);
                           Is_Host_Call := True;

                        when 16#503# =>
                           --  HOST_LOG_REGS: dump integer registers to log
                           if Mem.Log_File_Open then
                              Put_Line (Mem.Log_File.all,
                                 "=== Register Dump (PC=0x" &
                                 To_Hex (CPU.PC) & ") ===");
                              for R in Register_Index loop
                                 Put_Line (Mem.Log_File.all,
                                    "  x" &
                                    (if R < 10 then "0" else "") &
                                    Img (Natural (R)) &
                                    " = 0x" &
                                    To_Hex (CPU.Registers (R)));
                              end loop;
                              Put_Line (Mem.Log_File.all, "");
                           end if;
                           Write_Register (CPU, 10, 0);
                           Is_Host_Call := True;

                        when 16#504# =>
                           --  HOST_GET_TIME_MS: return host wall-clock time
                           --  Returns milliseconds since midnight as a Word.
                           --  C code decomposes this into HH:MM:SS.mmm.
                           declare
                              T    : constant Ada.Calendar.Time :=
                                        Ada.Calendar.Clock;
                              Secs : constant Duration :=
                                        Ada.Calendar.Seconds (T);
                              Ms   : constant Word :=
                                        Word (Float (Secs) * 1000.0);
                           begin
                              Write_Register (CPU, 10, Ms);
                           end;
                           Is_Host_Call := True;

                        when 16#505# =>
                           --  HOST_FILE_OPEN: a0=path_ptr, a1=path_len, a2=mode
                           --  mode: 0=read 1=write 2=append -> handle(0-15) or -1
                           declare
                              use Ada.Streams.Stream_IO;
                              A2_Val   : constant Word :=
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
                                       Write_Register (CPU, 10, Word (Handle));
                                    exception
                                       when others =>
                                          Write_Register (CPU, 10, Word'Last);
                                    end;
                                 else
                                    Write_Register (CPU, 10, Word'Last);
                                 end if;
                              end;
                           end;
                           Is_Host_Call := True;

                        when 16#506# =>
                           --  HOST_FILE_READ: a0=handle, a1=buf_ptr, a2=count -> bytes_read
                           declare
                              use Ada.Streams;
                              use Ada.Streams.Stream_IO;
                              A2_Val      : constant Word :=
                                 Read_Register (CPU, 12);
                              H_Raw       : constant Word :=
                                 A0_Val;
                              Buf_Addr    : constant Memory_Address :=
                                 Memory_Address (A1_Val);
                              Total_Count : constant Natural :=
                                 Natural (A2_Val);
                              Total_Read  : Natural := 0;
                           begin
                              if H_Raw < Word (Memory.Max_SH_Files) and then
                                 Mem.SH_File_Open
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
                                 Write_Register (CPU, 10, Word (Total_Read));
                              else
                                 Write_Register (CPU, 10, Word'Last);
                              end if;
                           end;
                           Is_Host_Call := True;

                        when 16#507# =>
                           --  HOST_FILE_WRITE: a0=handle, a1=buf_ptr, a2=count -> bytes_written
                           declare
                              use Ada.Streams;
                              use Ada.Streams.Stream_IO;
                              A2_Val   : constant Word :=
                                 Read_Register (CPU, 12);
                              H_Raw    : constant Word :=
                                 A0_Val;
                              Buf_Addr : constant Memory_Address :=
                                 Memory_Address (A1_Val);
                              Count    : constant Natural := Natural (A2_Val);
                              Written  : Natural := 0;
                           begin
                              if H_Raw < Word (Memory.Max_SH_Files) and then
                                 Mem.SH_File_Open
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
                                      (CPU, 10, Word (Written));
                                 exception
                                    when others =>
                                       Write_Register
                                         (CPU, 10, Word'Last);
                                 end;
                              else
                                 Write_Register (CPU, 10, Word'Last);
                              end if;
                           end;
                           Is_Host_Call := True;

                        when 16#508# =>
                           --  HOST_FILE_CLOSE: a0=handle -> 0
                           declare
                              use Ada.Streams.Stream_IO;
                              H_Raw : constant Word := A0_Val;
                           begin
                              if H_Raw < Word (Memory.Max_SH_Files) and then
                                 Mem.SH_File_Open
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
                           --  HOST_FILE_SEEK: a0=handle, a1=offset(signed32), a2=whence -> 0/-1
                           declare
                              use Ada.Streams.Stream_IO;
                              A2_Val : constant Word :=
                                 Read_Register (CPU, 12);
                              H_Raw  : constant Word    := A0_Val;
                              Offset : constant Integer :=
                                 Integer (To_Signed (A1_Val));
                              Whence : constant Natural := Natural (A2_Val);
                           begin
                              if H_Raw < Word (Memory.Max_SH_Files) and then
                                 Mem.SH_File_Open
                                    (Memory.SH_File_Index (H_Raw))
                              then
                                 declare
                                    F : Ada.Streams.Stream_IO.File_Type
                                       renames Mem.SH_Files
                                          (Memory.SH_File_Index (H_Raw)).all;
                                    New_Pos : Long_Integer;
                                 begin
                                    case Whence is
                                       when 1 =>
                                          New_Pos :=
                                             Long_Integer (Index (F)) +
                                             Long_Integer (Offset);
                                       when 2 =>
                                          New_Pos :=
                                             Long_Integer (Size (F)) +
                                             Long_Integer (Offset) + 1;
                                       when others =>
                                          New_Pos :=
                                             Long_Integer (Offset) + 1;
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
                                       Write_Register (CPU, 10, Word'Last);
                                 end;
                              else
                                 Write_Register (CPU, 10, Word'Last);
                              end if;
                           end;
                           Is_Host_Call := True;

                        when 16#50A# =>
                           --  HOST_FILE_TELL: a0=handle -> 0-based position or -1
                           declare
                              use Ada.Streams.Stream_IO;
                              H_Raw : constant Word := A0_Val;
                           begin
                              if H_Raw < Word (Memory.Max_SH_Files) and then
                                 Mem.SH_File_Open
                                    (Memory.SH_File_Index (H_Raw))
                              then
                                 Write_Register
                                   (CPU, 10,
                                    Word (Index (Mem.SH_Files
                                       (Memory.SH_File_Index (H_Raw)).all))
                                    - 1);
                              else
                                 Write_Register (CPU, 10, Word'Last);
                              end if;
                           end;
                           Is_Host_Call := True;

                        when 16#50B# =>
                           --  HOST_FILE_SIZE: a0=handle -> size in bytes or -1
                           declare
                              use Ada.Streams.Stream_IO;
                              H_Raw : constant Word := A0_Val;
                           begin
                              if H_Raw < Word (Memory.Max_SH_Files) and then
                                 Mem.SH_File_Open
                                    (Memory.SH_File_Index (H_Raw))
                              then
                                 Write_Register
                                   (CPU, 10,
                                    Word (Size (Mem.SH_Files
                                       (Memory.SH_File_Index (H_Raw)).all)));
                              else
                                 Write_Register (CPU, 10, Word'Last);
                              end if;
                           end;
                           Is_Host_Call := True;

                        when 16#50C# =>
                           --  HOST_FB_DRAW: a0=buf_ptr (320x200 ARGB32), a1=frame_no
                           --  Writes doom_frame_NNNNNN.ppm to current directory
                           declare
                              use Ada.Streams;
                              use Ada.Streams.Stream_IO;
                              Frame_No : constant Word := A1_Val;
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

                              PPM  : Ada.Streams.Stream_IO.File_Type;
                              Hdr  : constant String :=
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
                                 Write_Register (CPU, 10, Word'Last);
                           end;
                           Is_Host_Call := True;

                        when 16#50D# =>
                           --  HOST_FB_TERM: a0=buf_ptr (320x200 ARGB32)
                           --  Renders the framebuffer to the terminal.
                           RISCV.Term_IO.Present_Frame
                             (Mem, Memory_Address (A0_Val));
                           Write_Register (CPU, 10, 0);
                           Is_Host_Call := True;

                        when 16#50E# =>
                           --  HOST_KEY_POLL: returns next stdin byte, 0 if none
                           Write_Register
                             (CPU, 10, Word (RISCV.Term_IO.Poll_Key));
                           Is_Host_Call := True;

                        when 93 =>
                           --  exit(status) - newlib/Linux ABI syscall 93.
                           --  In riscv-tests HTIF mode, a7=93 ECALL must trap
                           --  to the guest mtvec handler (which writes tohost)
                           --  instead of halting, so leave it to fall through.
                           if not Mem.HTIF_Enabled then
                              RISCV.Term_IO.End_Session;
                              CPU.Halted := True;
                              Is_Host_Call := True;
                           end if;

                        when others =>
                           null;  --  Not a host syscall; fall through

                     end case;

                     if Is_Host_Call then
                        CPU.PC := Next_PC;
                        CSR.Increment_Instret (CPU.CSRs);
                        CSR.Increment_Mcycle (CPU.CSRs);
                        return;
                     end if;

                     --  SBI shim: intercept all supervisor-mode ECALLs
                     --  (disabled under HTIF so riscv-tests si-mode ECALLs
                     --  trap normally to the guest handler, and by
                     --  Mem.SBI_Enabled for tests of raw trap routing).
                     if CPU.Priv_Mode = Supervisor
                       and then Mem.SBI_Enabled
                       and then not Mem.HTIF_Enabled
                     then
                        declare
                           EID     : constant Word := Syscall_Num;
                           FID     : constant Word :=
                              Read_Register (CPU, 16);
                           SBI_Err : Word := 0;
                           SBI_Val : Word := 0;
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
                                    Mip : constant Word :=
                                       CSR.Read (CPU.CSRs, CSR.CSR_MIP);
                                 begin
                                    if Mem.CLINT /= null then
                                       RISCV.CLINT.Set_Mtimecmp
                                         (Mem.CLINT.all, Val, CPU.Hart_ID);
                                    end if;
                                    CSR.Write (CPU.CSRs, CSR.CSR_MIP,
                                               Mip and not CSR.MIE_STIE);
                                 end;

                              when 1 =>
                                 --  Legacy sbi_console_putchar: a0 = char
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
                                 --  Legacy sbi_console_getchar: no input
                                 SBI_Err := Word'Last;

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
                                       SBI_Err := Word'Last;
                                 end case;

                              when 16#5449_4D45# =>
                                 --  TIMER extension: FID=0 same as set_timer
                                 if FID = 0 then
                                    declare
                                       Val : constant
                                         RISCV.CLINT.Timer_Value :=
                                          RISCV.CLINT.Timer_Value (A0_Val) or
                                          Shift_Left
                                            (RISCV.CLINT.Timer_Value (A1_Val),
                                             32);
                                       Mip : constant Word :=
                                          CSR.Read (CPU.CSRs, CSR.CSR_MIP);
                                    begin
                                       if Mem.CLINT /= null then
                                          RISCV.CLINT.Set_Mtimecmp
                                            (Mem.CLINT.all, Val, CPU.Hart_ID);
                                       end if;
                                       CSR.Write (CPU.CSRs, CSR.CSR_MIP,
                                                  Mip and not CSR.MIE_STIE);
                                    end;
                                 else
                                    SBI_Err := Word'Last;
                                 end if;

                              when others =>
                                 SBI_Err := Word'Last;

                           end case;

                           Write_Register (CPU, 10, SBI_Err);
                           Write_Register (CPU, 11, SBI_Val);
                           CPU.PC := Next_PC;
                           CSR.Increment_Instret (CPU.CSRs);
                           CSR.Increment_Mcycle (CPU.CSRs);
                           return;
                        end;
                     end if;
                  end;

                  --  Normal ECALL: route cause by privilege level
                  CPU.Exception_Code := Environment_Call;
                  declare
                     Cause : Word;
                  begin
                     case CPU.Priv_Mode is
                        when User       => Cause := CSR.CAUSE_ECALL_U;
                        when Supervisor => Cause := CSR.CAUSE_ECALL_S;
                        when Machine    => Cause := CSR.CAUSE_ECALL_M;
                        when Reserved   => Cause := CSR.CAUSE_ECALL_M;
                     end case;
                     Trap_Entry (CPU, Cause);
                  end;
                  CSR.Increment_Instret (CPU.CSRs);
                  CSR.Increment_Mcycle (CPU.CSRs);
                  return;
               elsif Decoded.Imm_I = 1 then
                  --  EBREAK
                  CPU.Exception_Code := Breakpoint;
                  Trap_Entry (CPU, CSR.CAUSE_BREAKPOINT, CPU.PC);
                  CSR.Increment_Instret (CPU.CSRs);
                  CSR.Increment_Mcycle (CPU.CSRs);
                  return;
               else
                  CPU.Exception_Code := Illegal_Instruction;
                  Trap_Entry (CPU, CSR.CAUSE_ILLEGAL_INSN, Instruction);
                  CSR.Increment_Instret (CPU.CSRs);
                  CSR.Increment_Mcycle (CPU.CSRs);
                  return;
               end if;
            else
               --  Zicsr: CSR instructions
               declare
                  CSR_Addr : constant CSR.CSR_Address :=
                     CSR.CSR_Address (Shift_Right (Instruction, 20) and
                                     16#FFF#);
                  Old_Val  : Word;
                  New_Val  : Word;
                  Zimm     : constant Word := Word (Decoded.Rs1);
                  Write_CSR : Boolean := True;
               begin
                  --  Check privilege level for CSR access
                  if not CSR.Can_Access_CSR (CSR_Addr, CPU.Priv_Mode) then
                     CPU.Exception_Code := Illegal_Instruction;
                     Trap_Entry (CPU, CSR.CAUSE_ILLEGAL_INSN, Instruction);
                     return;
                  end if;

                  --  mstatus.TVM traps satp as well as SFENCE.VMA, so a
                  --  hypervisor can shadow both the tables and the pointer
                  --  to them.
                  if CSR_Addr = CSR.CSR_SATP
                    and then CPU.Priv_Mode = Supervisor
                    and then (CSR.Read (CPU.CSRs, CSR.CSR_MSTATUS)
                              and CSR.MSTATUS_TVM) /= 0
                  then
                     CPU.Exception_Code := Illegal_Instruction;
                     Trap_Entry (CPU, CSR.CAUSE_ILLEGAL_INSN, Instruction);
                     return;
                  end if;

                  Extra_Cycles := 1;  --  CSR instructions cost 2 cycles

                  --  Read CSR (special handling for FP and vector CSRs)
                  case CSR_Addr is
                     when CSR.CSR_FFLAGS =>
                        Old_Val := FPU.Read_FFLAGS (CPU.FP);
                     when CSR.CSR_FRM =>
                        Old_Val := FPU.Read_FRM (CPU.FP);
                     when CSR.CSR_FCSR =>
                        Old_Val := FPU.Read_FCSR (CPU.FP);
                     --  Vector CSRs (read from vector state, not sparse map)
                     when CSR.CSR_VL =>
                        Old_Val := Vector.Read_VL (CPU.VU);
                     when CSR.CSR_VTYPE =>
                        Old_Val := Vector.Read_VType (CPU.VU);
                     when CSR.CSR_VLENB =>
                        Old_Val := Vector.Read_VLENB;
                     when CSR.CSR_VSTART =>
                        Old_Val := Vector.Read_VStart (CPU.VU);
                     when CSR.CSR_VXSAT =>
                        Old_Val := Vector.Read_VXSat (CPU.VU);
                     when CSR.CSR_VXRM =>
                        Old_Val := Vector.Read_VXRM (CPU.VU);
                     when others =>
                        Old_Val := CSR.Read (CPU.CSRs, CSR_Addr);
                  end case;

                  case Decoded.Funct3 is
                     when FUNCT3_CSRRW =>
                        --  CSRRW: rd = CSR; CSR = rs1
                        Write_Register (CPU, Decoded.Rd, Old_Val);
                        New_Val := Rs1_Val;

                     when FUNCT3_CSRRS =>
                        --  CSRRS: rd = CSR; CSR |= rs1
                        Write_Register (CPU, Decoded.Rd, Old_Val);
                        New_Val := Old_Val or Rs1_Val;
                        --  If rs1=x0, don't write (read-only op)
                        Write_CSR := Decoded.Rs1 /= 0;

                     when FUNCT3_CSRRC =>
                        --  CSRRC: rd = CSR; CSR &= ~rs1
                        Write_Register (CPU, Decoded.Rd, Old_Val);
                        New_Val := Old_Val and (not Rs1_Val);
                        Write_CSR := Decoded.Rs1 /= 0;

                     when FUNCT3_CSRRWI =>
                        --  CSRRWI: rd = CSR; CSR = zimm
                        Write_Register (CPU, Decoded.Rd, Old_Val);
                        New_Val := Zimm;

                     when FUNCT3_CSRRSI =>
                        --  CSRRSI: rd = CSR; CSR |= zimm
                        Write_Register (CPU, Decoded.Rd, Old_Val);
                        New_Val := Old_Val or Zimm;
                        Write_CSR := Zimm /= 0;

                     when FUNCT3_CSRRCI =>
                        --  CSRRCI: rd = CSR; CSR &= ~zimm
                        Write_Register (CPU, Decoded.Rd, Old_Val);
                        New_Val := Old_Val and (not Zimm);
                        Write_CSR := Zimm /= 0;

                     when others =>
                        CPU.Exception_Code := Illegal_Instruction;
                        Trap_Entry (CPU, CSR.CAUSE_ILLEGAL_INSN, Instruction);
                        return;
                  end case;

                  --  Write CSR if not a read-only operation
                  if Write_CSR then
                     if CSR.Is_Read_Only (CSR_Addr) then
                        CPU.Exception_Code := Illegal_Instruction;
                        Trap_Entry (CPU, CSR.CAUSE_ILLEGAL_INSN, Instruction);
                        return;
                     end if;
                     --  Special handling for FP and vector CSRs
                     case CSR_Addr is
                        when CSR.CSR_FFLAGS =>
                           FPU.Write_FFLAGS (CPU.FP, New_Val);
                        when CSR.CSR_FRM =>
                           FPU.Write_FRM (CPU.FP, New_Val);
                        when CSR.CSR_FCSR =>
                           FPU.Write_FCSR (CPU.FP, New_Val);
                        --  Writable vector CSRs
                        when CSR.CSR_VSTART =>
                           Vector.Write_VStart (CPU.VU, New_Val);
                        when CSR.CSR_VXSAT =>
                           Vector.Write_VXSat (CPU.VU, New_Val);
                        when CSR.CSR_VXRM =>
                           Vector.Write_VXRM (CPU.VU, New_Val);
                        when CSR.CSR_MISA =>
                           --  misa.C is WARL: refuse to clear C (set IALIGN=32)
                           --  when the next instruction fetch would then be
                           --  misaligned. Otherwise honour the write.
                           declare
                              Old_Misa : constant Word :=
                                 CSR.Read (CPU.CSRs, CSR.CSR_MISA);
                              Misa_Val : Word := New_Val;
                           begin
                              if (Old_Misa and 2#100#) /= 0 and then
                                 (Misa_Val and 2#100#) = 0 and then
                                 (Next_PC and 2) /= 0
                              then
                                 Misa_Val := Misa_Val or 2#100#;
                              end if;
                              CSR.Write (CPU.CSRs, CSR.CSR_MISA, Misa_Val);
                           end;
                        when others =>
                           CSR.Write (CPU.CSRs, CSR_Addr, New_Val);
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
               Trap_Entry (CPU, CSR.CAUSE_ILLEGAL_INSN, Instruction);
               CSR.Increment_Instret (CPU.CSRs);
               CSR.Increment_Mcycle (CPU.CSRs);
               return;
            end if;
            declare
               use FPU;
               FS1 : Word;
               FS2 : Word;
               FD1 : FP_Register;
               FD2 : FP_Register;
               RM  : constant Rounding_Mode :=
                 (if Decoded.Funct3 = 7 then DYN
                  elsif Decoded.Funct3 <= 4 then
                     Rounding_Mode'Val (Natural (Decoded.Funct3))
                  else DYN);
            begin
               --  Read the source operands in both widths.
               --
               --  The format field in Funct7 gives the DESTINATION format, so
               --  it cannot be used to pick the source width: FCVT.S.D reads a
               --  double while its format bit says single, and FCVT.D.S reads a
               --  single while its format bit says double. Selecting on that
               --  bit left the operand those two instructions actually use
               --  unassigned. Reading both is cheap and always correct -- each
               --  handler below then picks the operand its own encoding
               --  defines.
               FS1 := Read_Single (CPU.FP, Decoded.Rs1);
               FS2 := Read_Single (CPU.FP, Decoded.Rs2);
               FD1 := Read_Double (CPU.FP, Decoded.Rs1);
               FD2 := Read_Double (CPU.FP, Decoded.Rs2);

               case Decoded.Funct7 is
                  --  Single-precision operations
                  when FUNCT7_FADD_S =>
                     Write_Single (CPU.FP, Decoded.Rd,
                       FADD_S (CPU.FP, FS1, FS2, RM));
                     Extra_Cycles := 3;   --  4 cycles total

                  when FUNCT7_FSUB_S =>
                     Write_Single (CPU.FP, Decoded.Rd,
                       FSUB_S (CPU.FP, FS1, FS2, RM));
                     Extra_Cycles := 3;

                  when FUNCT7_FMUL_S =>
                     Write_Single (CPU.FP, Decoded.Rd,
                       FMUL_S (CPU.FP, FS1, FS2, RM));
                     Extra_Cycles := 3;

                  when FUNCT7_FDIV_S =>
                     Write_Single (CPU.FP, Decoded.Rd,
                       FDIV_S (CPU.FP, FS1, FS2, RM));
                     Extra_Cycles := 19;  --  20 cycles total

                  when FUNCT7_FSQRT_S =>
                     Write_Single (CPU.FP, Decoded.Rd,
                       FSQRT_S (CPU.FP, FS1, RM));
                     Extra_Cycles := 19;

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
                           Trap_Entry (CPU, CSR.CAUSE_ILLEGAL_INSN, Instruction);
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
                           Trap_Entry (CPU, CSR.CAUSE_ILLEGAL_INSN, Instruction);
                           return;
                     end case;

                  when FUNCT7_FCVT_W_S =>
                     --  FCVT.W.S or FCVT.WU.S (rs2 determines signed/unsigned)
                     if Decoded.Rs2 = 0 then
                        Write_Register (CPU, Decoded.Rd,
                          FCVT_W_S (CPU.FP, FS1, RM));
                     else
                        Write_Register (CPU, Decoded.Rd,
                          FCVT_WU_S (CPU.FP, FS1, RM));
                     end if;

                  when FUNCT7_FMV_X_W =>
                     --  FMV.X.W or FCLASS.S
                     if Decoded.Funct3 = 0 then
                        Write_Register (CPU, Decoded.Rd, FMV_X_W (FS1));
                     else  -- FCLASS.S
                        Write_Register (CPU, Decoded.Rd, FCLASS_S (FS1));
                     end if;

                  when FUNCT7_FCMP_S =>
                     case Decoded.Funct3 is
                        when FUNCT3_FEQ =>
                           Write_Register (CPU, Decoded.Rd,
                             FEQ_S (CPU.FP, FS1, FS2));
                        when FUNCT3_FLT =>
                           Write_Register (CPU, Decoded.Rd,
                             FLT_S (CPU.FP, FS1, FS2));
                        when FUNCT3_FLE =>
                           Write_Register (CPU, Decoded.Rd,
                             FLE_S (CPU.FP, FS1, FS2));
                        when others =>
                           CPU.Exception_Code := Illegal_Instruction;
                           Trap_Entry (CPU, CSR.CAUSE_ILLEGAL_INSN, Instruction);
                           return;
                     end case;

                  when FUNCT7_FCVT_S_W =>
                     --  FCVT.S.W or FCVT.S.WU
                     if Decoded.Rs2 = 0 then
                        Write_Single (CPU.FP, Decoded.Rd,
                          FCVT_S_W (CPU.FP, Rs1_Val, RM));
                     else
                        Write_Single (CPU.FP, Decoded.Rd,
                          FCVT_S_WU (CPU.FP, Rs1_Val, RM));
                     end if;

                  when FUNCT7_FMV_W_X =>
                     Write_Single (CPU.FP, Decoded.Rd, FMV_W_X (Rs1_Val));

                  --  Double-precision operations
                  when FUNCT7_FADD_D =>
                     Write_Double (CPU.FP, Decoded.Rd,
                       FADD_D (CPU.FP, FD1, FD2, RM));
                     Extra_Cycles := 3;   --  4 cycles total

                  when FUNCT7_FSUB_D =>
                     Write_Double (CPU.FP, Decoded.Rd,
                       FSUB_D (CPU.FP, FD1, FD2, RM));
                     Extra_Cycles := 3;

                  when FUNCT7_FMUL_D =>
                     Write_Double (CPU.FP, Decoded.Rd,
                       FMUL_D (CPU.FP, FD1, FD2, RM));
                     Extra_Cycles := 3;

                  when FUNCT7_FDIV_D =>
                     Write_Double (CPU.FP, Decoded.Rd,
                       FDIV_D (CPU.FP, FD1, FD2, RM));
                     Extra_Cycles := 19;  --  20 cycles total

                  when FUNCT7_FSQRT_D =>
                     Write_Double (CPU.FP, Decoded.Rd,
                       FSQRT_D (CPU.FP, FD1, RM));
                     Extra_Cycles := 19;

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
                           Trap_Entry (CPU, CSR.CAUSE_ILLEGAL_INSN, Instruction);
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
                           Trap_Entry (CPU, CSR.CAUSE_ILLEGAL_INSN, Instruction);
                           return;
                     end case;

                  when FUNCT7_FCVT_S_D =>
                     if Decoded.Rs2 = 2 then
                        --  FCVT.S.H: fp16 ->fp32
                        Write_Single (CPU.FP, Decoded.Rd,
                          FCVT_S_H (Read_Half (CPU.FP, Decoded.Rs1)));
                     else
                        Write_Single (CPU.FP, Decoded.Rd,
                          FCVT_S_D (CPU.FP, FD1, RM));
                     end if;

                  when FUNCT7_FCVT_D_S =>
                     Write_Double (CPU.FP, Decoded.Rd,
                       FCVT_D_S (CPU.FP, FS1, RM));

                  when FUNCT7_FCVT_W_D =>
                     if Decoded.Rs2 = 0 then
                        Write_Register (CPU, Decoded.Rd,
                          FCVT_W_D (CPU.FP, FD1, RM));
                     else
                        Write_Register (CPU, Decoded.Rd,
                          FCVT_WU_D (CPU.FP, FD1, RM));
                     end if;

                  when FUNCT7_FCMP_D =>
                     case Decoded.Funct3 is
                        when FUNCT3_FEQ =>
                           Write_Register (CPU, Decoded.Rd,
                             FEQ_D (CPU.FP, FD1, FD2));
                        when FUNCT3_FLT =>
                           Write_Register (CPU, Decoded.Rd,
                             FLT_D (CPU.FP, FD1, FD2));
                        when FUNCT3_FLE =>
                           Write_Register (CPU, Decoded.Rd,
                             FLE_D (CPU.FP, FD1, FD2));
                        when others =>
                           CPU.Exception_Code := Illegal_Instruction;
                           Trap_Entry (CPU, CSR.CAUSE_ILLEGAL_INSN, Instruction);
                           return;
                     end case;

                  when FUNCT7_FCLASS_D =>
                     Write_Register (CPU, Decoded.Rd, FCLASS_D (FD1));

                  when FUNCT7_FCVT_D_W =>
                     if Decoded.Rs2 = 0 then
                        Write_Double (CPU.FP, Decoded.Rd,
                          FCVT_D_W (CPU.FP, Rs1_Val, RM));
                     else
                        Write_Double (CPU.FP, Decoded.Rd,
                          FCVT_D_WU (CPU.FP, Rs1_Val, RM));
                     end if;

                  --  Half-precision (Zfh) operations
                  when FUNCT7_FADD_H =>
                     Write_Half (CPU.FP, Decoded.Rd,
                       FADD_H (CPU.FP, Read_Half (CPU.FP, Decoded.Rs1),
                               Read_Half (CPU.FP, Decoded.Rs2), RM));
                     Extra_Cycles := 3;

                  when FUNCT7_FSUB_H =>
                     Write_Half (CPU.FP, Decoded.Rd,
                       FSUB_H (CPU.FP, Read_Half (CPU.FP, Decoded.Rs1),
                               Read_Half (CPU.FP, Decoded.Rs2), RM));
                     Extra_Cycles := 3;

                  when FUNCT7_FMUL_H =>
                     Write_Half (CPU.FP, Decoded.Rd,
                       FMUL_H (CPU.FP, Read_Half (CPU.FP, Decoded.Rs1),
                               Read_Half (CPU.FP, Decoded.Rs2), RM));
                     Extra_Cycles := 3;

                  when FUNCT7_FDIV_H =>
                     Write_Half (CPU.FP, Decoded.Rd,
                       FDIV_H (CPU.FP, Read_Half (CPU.FP, Decoded.Rs1),
                               Read_Half (CPU.FP, Decoded.Rs2), RM));
                     Extra_Cycles := 19;

                  when FUNCT7_FSQRT_H =>
                     Write_Half (CPU.FP, Decoded.Rd,
                       FSQRT_H (CPU.FP, Read_Half (CPU.FP, Decoded.Rs1), RM));
                     Extra_Cycles := 19;

                  when FUNCT7_FSGNJ_H =>
                     declare
                        A : constant Word := Read_Half (CPU.FP, Decoded.Rs1);
                        B : constant Word := Read_Half (CPU.FP, Decoded.Rs2);
                     begin
                        case Decoded.Funct3 is
                           when FUNCT3_FSGNJ  =>
                              Write_Half (CPU.FP, Decoded.Rd, FSGNJ_H (A, B));
                           when FUNCT3_FSGNJN =>
                              Write_Half (CPU.FP, Decoded.Rd, FSGNJN_H (A, B));
                           when FUNCT3_FSGNJX =>
                              Write_Half (CPU.FP, Decoded.Rd, FSGNJX_H (A, B));
                           when others =>
                              CPU.Exception_Code := Illegal_Instruction;
                              Trap_Entry (CPU, CSR.CAUSE_ILLEGAL_INSN, Instruction);
                              return;
                        end case;
                     end;

                  when FUNCT7_FMINMAX_H =>
                     declare
                        A : constant Word := Read_Half (CPU.FP, Decoded.Rs1);
                        B : constant Word := Read_Half (CPU.FP, Decoded.Rs2);
                     begin
                        case Decoded.Funct3 is
                           when FUNCT3_FMIN =>
                              Write_Half (CPU.FP, Decoded.Rd, FMIN_H (CPU.FP, A, B));
                           when FUNCT3_FMAX =>
                              Write_Half (CPU.FP, Decoded.Rd, FMAX_H (CPU.FP, A, B));
                           when others =>
                              CPU.Exception_Code := Illegal_Instruction;
                              Trap_Entry (CPU, CSR.CAUSE_ILLEGAL_INSN, Instruction);
                              return;
                        end case;
                     end;

                  when FUNCT7_FCVT_W_H =>
                     if Decoded.Rs2 = 0 then
                        Write_Register (CPU, Decoded.Rd,
                          FCVT_W_H (CPU.FP, Read_Half (CPU.FP, Decoded.Rs1), RM));
                     else
                        Write_Register (CPU, Decoded.Rd,
                          FCVT_WU_H (CPU.FP, Read_Half (CPU.FP, Decoded.Rs1), RM));
                     end if;

                  when FUNCT7_FCVT_H_W =>
                     if Decoded.Rs2 = 0 then
                        Write_Half (CPU.FP, Decoded.Rd,
                          FCVT_H_W (CPU.FP, Rs1_Val, RM));
                     else
                        Write_Half (CPU.FP, Decoded.Rd,
                          FCVT_H_WU (CPU.FP, Rs1_Val, RM));
                     end if;

                  when FUNCT7_FMV_X_H =>
                     --  FMV.X.H (funct3=0) or FCLASS.H (funct3=1)
                     if Decoded.Funct3 = 0 then
                        Write_Register (CPU, Decoded.Rd,
                          Read_Half (CPU.FP, Decoded.Rs1));
                     else
                        Write_Register (CPU, Decoded.Rd,
                          FCLASS_H (Read_Half (CPU.FP, Decoded.Rs1)));
                     end if;

                  when FUNCT7_FMV_H_X =>
                     Write_Half (CPU.FP, Decoded.Rd, Rs1_Val and 16#FFFF#);

                  when FUNCT7_FCMP_H =>
                     declare
                        A : constant Word := Read_Half (CPU.FP, Decoded.Rs1);
                        B : constant Word := Read_Half (CPU.FP, Decoded.Rs2);
                     begin
                        case Decoded.Funct3 is
                           when FUNCT3_FEQ =>
                              Write_Register (CPU, Decoded.Rd, FEQ_H (CPU.FP, A, B));
                           when FUNCT3_FLT =>
                              Write_Register (CPU, Decoded.Rd, FLT_H (CPU.FP, A, B));
                           when FUNCT3_FLE =>
                              Write_Register (CPU, Decoded.Rd, FLE_H (CPU.FP, A, B));
                           when others =>
                              CPU.Exception_Code := Illegal_Instruction;
                              Trap_Entry (CPU, CSR.CAUSE_ILLEGAL_INSN, Instruction);
                              return;
                        end case;
                     end;

                  when FUNCT7_FCVT_H_SD =>
                     --  FCVT.H.S (rs2=0) or FCVT.H.D (rs2=1)
                     if Decoded.Rs2 = 0 then
                        Write_Half (CPU.FP, Decoded.Rd,
                          FCVT_H_S (CPU.FP, Read_Single (CPU.FP, Decoded.Rs1), RM));
                     else
                        CPU.Exception_Code := Illegal_Instruction;
                        Trap_Entry (CPU, CSR.CAUSE_ILLEGAL_INSN, Instruction);
                        return;
                     end if;

                  when others =>
                     CPU.Exception_Code := Illegal_Instruction;
                     Trap_Entry (CPU, CSR.CAUSE_ILLEGAL_INSN, Instruction);
                     return;
               end case;
            end;

         ----------------------
         -- Vector Extension
         ----------------------
         when OPCODE_VECTOR =>
            declare
               Funct6 : constant Word := Shift_Right (Instruction, 26);
               VM     : constant Boolean := (Instruction and 16#02000000#) /= 0;
               Vs1    : constant Register_Index := Decoded.Rs1;
               Vs2    : constant Register_Index := Decoded.Rs2;
               Vd     : constant Register_Index := Decoded.Rd;
               Simm5  : Signed_Word;
               Uimm5  : Natural;
            begin
               --  Sign-extend 5-bit immediate
               Simm5 := Signed_Word (Decoded.Rs1);
               if Simm5 >= 16 then
                  Simm5 := Simm5 - 32;
               end if;
               Uimm5 := Natural (Decoded.Rs1);

               case Decoded.Funct3 is
                  --  vsetvli, vsetivli, vsetvl (configuration)
                  when FUNCT3_OPCFG =>
                     declare
                        Zimm : Word;
                        AVL  : Word;
                        New_VL : Word;
                     begin
                        if (Instruction and 16#80000000#) = 0 then
                           --  vsetvli: rs1, rd, zimm[10:0]
                           Zimm := Shift_Right (Instruction, 20) and 16#7FF#;
                           if Decoded.Rs1 = 0 and Decoded.Rd = 0 then
                              --  Keep current VL
                              AVL := CPU.VU.VL;
                           elsif Decoded.Rs1 = 0 then
                              --  Set to VLMAX
                              AVL := 16#FFFFFFFF#;
                           else
                              AVL := Rs1_Val;
                           end if;
                           New_VL := Vector.Vsetvl (CPU.VU, AVL, Zimm);
                           Write_Register (CPU, Decoded.Rd, New_VL);
                        elsif (Instruction and 16#40000000#) /= 0 then
                           --  vsetivli: uimm[4:0], rd, zimm[9:0]
                           Zimm := Shift_Right (Instruction, 20) and 16#3FF#;
                           AVL := Word (Decoded.Rs1);  -- 5-bit immediate
                           New_VL := Vector.Vsetvl (CPU.VU, AVL, Zimm);
                           Write_Register (CPU, Decoded.Rd, New_VL);
                        else
                           --  vsetvl: rs1, rs2, rd
                           if Decoded.Rs1 = 0 and Decoded.Rd = 0 then
                              AVL := CPU.VU.VL;
                           elsif Decoded.Rs1 = 0 then
                              AVL := 16#FFFFFFFF#;
                           else
                              AVL := Rs1_Val;
                           end if;
                           New_VL := Vector.Vsetvl (CPU.VU, AVL, Rs2_Val);
                           Write_Register (CPU, Decoded.Rd, New_VL);
                        end if;
                     end;

                  --  OPIVV: Integer vector-vector
                  when FUNCT3_OPIVV =>
                     case Funct6 is
                        when VFUNCT6_VADD =>
                           Vector.VADD_VV (CPU.VU, Vd, Vs2, Vs1, VM);
                        when VFUNCT6_VSUB =>
                           Vector.VSUB_VV (CPU.VU, Vd, Vs2, Vs1, VM);
                        when VFUNCT6_VAND =>
                           Vector.VAND_VV (CPU.VU, Vd, Vs2, Vs1, VM);
                        when VFUNCT6_VOR =>
                           Vector.VOR_VV (CPU.VU, Vd, Vs2, Vs1, VM);
                        when VFUNCT6_VXOR =>
                           Vector.VXOR_VV (CPU.VU, Vd, Vs2, Vs1, VM);
                        when VFUNCT6_VMINU =>
                           Vector.VMINU_VV (CPU.VU, Vd, Vs2, Vs1, VM);
                        when VFUNCT6_VMIN =>
                           Vector.VMIN_VV (CPU.VU, Vd, Vs2, Vs1, VM);
                        when VFUNCT6_VMAXU =>
                           Vector.VMAXU_VV (CPU.VU, Vd, Vs2, Vs1, VM);
                        when VFUNCT6_VMAX =>
                           Vector.VMAX_VV (CPU.VU, Vd, Vs2, Vs1, VM);
                        when VFUNCT6_VSLL =>
                           Vector.VSLL_VV (CPU.VU, Vd, Vs2, Vs1, VM);
                        when VFUNCT6_VSRL =>
                           Vector.VSRL_VV (CPU.VU, Vd, Vs2, Vs1, VM);
                        when VFUNCT6_VSRA =>
                           Vector.VSRA_VV (CPU.VU, Vd, Vs2, Vs1, VM);
                        when VFUNCT6_VMSEQ =>
                           Vector.VMSEQ_VV (CPU.VU, Vd, Vs2, Vs1, VM);
                        when VFUNCT6_VMSNE =>
                           Vector.VMSNE_VV (CPU.VU, Vd, Vs2, Vs1, VM);
                        when VFUNCT6_VMSLTU =>
                           Vector.VMSLTU_VV (CPU.VU, Vd, Vs2, Vs1, VM);
                        when VFUNCT6_VMSLT =>
                           Vector.VMSLT_VV (CPU.VU, Vd, Vs2, Vs1, VM);
                        when VFUNCT6_VMSLEU =>
                           Vector.VMSLEU_VV (CPU.VU, Vd, Vs2, Vs1, VM);
                        when VFUNCT6_VMSLE =>
                           Vector.VMSLE_VV (CPU.VU, Vd, Vs2, Vs1, VM);
                        when VFUNCT6_VMERGE =>
                           if VM then
                              Vector.VMV_V_V (CPU.VU, Vd, Vs1);
                           else
                              Vector.VMERGE_VVM (CPU.VU, Vd, Vs2, Vs1);
                           end if;
                        when VFUNCT6_VRGATHER =>
                           Vector.VRGATHER_VV (CPU.VU, Vd, Vs2, Vs1, VM);
                        when VFUNCT6_VSLIDEUP =>
                           --  In OPIVV, funct6=001110 is vrgatherei16
                           Vector.VRGATHEREI16_VV
                             (CPU.VU, Vd, Vs2, Vs1, VM);
                        when VFUNCT6_VNSRL =>
                           Vector.VNSRL_WV (CPU.VU, Vd, Vs2, Vs1, VM);
                        when VFUNCT6_VNSRA =>
                           Vector.VNSRA_WV (CPU.VU, Vd, Vs2, Vs1, VM);
                        when VFUNCT6_VWADDU =>
                           Vector.VWADDU_VV (CPU.VU, Vd, Vs2, Vs1, VM);
                        when VFUNCT6_VWADD =>
                           Vector.VWADD_VV (CPU.VU, Vd, Vs2, Vs1, VM);
                        when VFUNCT6_VWSUBU =>
                           Vector.VWSUBU_VV (CPU.VU, Vd, Vs2, Vs1, VM);
                        when VFUNCT6_VWSUB =>
                           Vector.VWSUB_VV (CPU.VU, Vd, Vs2, Vs1, VM);
                        when VFUNCT6_VWADDUW =>
                           Vector.VWADDUW_VV (CPU.VU, Vd, Vs2, Vs1, VM);
                        when VFUNCT6_VWADDW =>
                           Vector.VWADDW_VV (CPU.VU, Vd, Vs2, Vs1, VM);
                        when VFUNCT6_VWSUBUW =>
                           Vector.VWSUBUW_VV (CPU.VU, Vd, Vs2, Vs1, VM);
                        when VFUNCT6_VWSUBW =>
                           Vector.VWSUBW_VV (CPU.VU, Vd, Vs2, Vs1, VM);
                        when VFUNCT6_VADC =>
                           Vector.VADC_VVM (CPU.VU, Vd, Vs2, Vs1);
                        when VFUNCT6_VMADC =>
                           Vector.VMADC_VVM (CPU.VU, Vd, Vs2, Vs1, VM);
                        when VFUNCT6_VSBC =>
                           Vector.VSBC_VVM (CPU.VU, Vd, Vs2, Vs1);
                        when VFUNCT6_VMSBC =>
                           Vector.VMSBC_VVM (CPU.VU, Vd, Vs2, Vs1, VM);
                        when VFUNCT6_VSADDU =>
                           Vector.VSADDU_VV (CPU.VU, Vd, Vs2, Vs1, VM);
                        when VFUNCT6_VSADD =>
                           Vector.VSADD_VV (CPU.VU, Vd, Vs2, Vs1, VM);
                        when VFUNCT6_VSSUBU =>
                           Vector.VSSUBU_VV (CPU.VU, Vd, Vs2, Vs1, VM);
                        when VFUNCT6_VSSUB =>
                           Vector.VSSUB_VV (CPU.VU, Vd, Vs2, Vs1, VM);
                        when VFUNCT6_VSSRL =>
                           Vector.VSSRL_VV (CPU.VU, Vd, Vs2, Vs1, VM);
                        when VFUNCT6_VSSRA =>
                           Vector.VSSRA_VV (CPU.VU, Vd, Vs2, Vs1, VM);
                        when VFUNCT6_VNCLIPU =>
                           Vector.VNCLIPU_WV (CPU.VU, Vd, Vs2, Vs1, VM);
                        when VFUNCT6_VNCLIP =>
                           Vector.VNCLIP_WV (CPU.VU, Vd, Vs2, Vs1, VM);
                        when VFUNCT6_VMV_REG =>
                           --  funct6=100111: vmv<n>r.v (vm=1) or vsmul.vv
                           if VM and then (Word (Vs1) in 0 | 1 | 3 | 7) then
                              declare
                                 NReg : Positive;
                              begin
                                 case Word (Vs1) is
                                    when 0 => NReg := 1;
                                    when 1 => NReg := 2;
                                    when 3 => NReg := 4;
                                    when 7 => NReg := 8;
                                    when others =>
                                       CPU.Exception_Code := Illegal_Instruction;
                                       Trap_Entry (CPU, CSR.CAUSE_ILLEGAL_INSN,
                                                   Instruction);
                                       return;
                                 end case;
                                 Vector.VMV_NR_V (CPU.VU, Vd, Vs2, NReg);
                              end;
                           else
                              Vector.VSMUL_VV (CPU.VU, Vd, Vs2, Vs1, VM);
                           end if;
                        when others =>
                           CPU.Exception_Code := Illegal_Instruction;
                           Trap_Entry (CPU, CSR.CAUSE_ILLEGAL_INSN, Instruction);
                           return;
                     end case;

                  --  OPIVX: Integer vector-scalar
                  when FUNCT3_OPIVX =>
                     case Funct6 is
                        when VFUNCT6_VADD =>
                           Vector.VADD_VX (CPU.VU, Vd, Vs2, Rs1_Val, VM);
                        when VFUNCT6_VSUB =>
                           Vector.VSUB_VX (CPU.VU, Vd, Vs2, Rs1_Val, VM);
                        when VFUNCT6_VRSUB =>
                           Vector.VRSUB_VX (CPU.VU, Vd, Vs2, Rs1_Val, VM);
                        when VFUNCT6_VAND =>
                           Vector.VAND_VX (CPU.VU, Vd, Vs2, Rs1_Val, VM);
                        when VFUNCT6_VOR =>
                           Vector.VOR_VX (CPU.VU, Vd, Vs2, Rs1_Val, VM);
                        when VFUNCT6_VXOR =>
                           Vector.VXOR_VX (CPU.VU, Vd, Vs2, Rs1_Val, VM);
                        when VFUNCT6_VMINU =>
                           Vector.VMINU_VX (CPU.VU, Vd, Vs2, Rs1_Val, VM);
                        when VFUNCT6_VMIN =>
                           Vector.VMIN_VX (CPU.VU, Vd, Vs2, Rs1_Val, VM);
                        when VFUNCT6_VMAXU =>
                           Vector.VMAXU_VX (CPU.VU, Vd, Vs2, Rs1_Val, VM);
                        when VFUNCT6_VMAX =>
                           Vector.VMAX_VX (CPU.VU, Vd, Vs2, Rs1_Val, VM);
                        when VFUNCT6_VSLL =>
                           Vector.VSLL_VX (CPU.VU, Vd, Vs2, Rs1_Val, VM);
                        when VFUNCT6_VSRL =>
                           Vector.VSRL_VX (CPU.VU, Vd, Vs2, Rs1_Val, VM);
                        when VFUNCT6_VSRA =>
                           Vector.VSRA_VX (CPU.VU, Vd, Vs2, Rs1_Val, VM);
                        when VFUNCT6_VMSEQ =>
                           Vector.VMSEQ_VX (CPU.VU, Vd, Vs2, Rs1_Val, VM);
                        when VFUNCT6_VMSNE =>
                           Vector.VMSNE_VX (CPU.VU, Vd, Vs2, Rs1_Val, VM);
                        when VFUNCT6_VMSLTU =>
                           Vector.VMSLTU_VX (CPU.VU, Vd, Vs2, Rs1_Val, VM);
                        when VFUNCT6_VMSLT =>
                           Vector.VMSLT_VX (CPU.VU, Vd, Vs2, Rs1_Val, VM);
                        when VFUNCT6_VMSLEU =>
                           Vector.VMSLEU_VX (CPU.VU, Vd, Vs2, Rs1_Val, VM);
                        when VFUNCT6_VMSLE =>
                           Vector.VMSLE_VX (CPU.VU, Vd, Vs2, Rs1_Val, VM);
                        when VFUNCT6_VMSGTU =>
                           Vector.VMSGTU_VX (CPU.VU, Vd, Vs2, Rs1_Val, VM);
                        when VFUNCT6_VMSGT =>
                           Vector.VMSGT_VX (CPU.VU, Vd, Vs2, Rs1_Val, VM);
                        when VFUNCT6_VRGATHER =>
                           Vector.VRGATHER_VX
                             (CPU.VU, Vd, Vs2, Rs1_Val, VM);
                        when VFUNCT6_VSLIDEUP =>
                           Vector.VSLIDEUP_VX
                             (CPU.VU, Vd, Vs2, Rs1_Val, VM);
                        when VFUNCT6_VSLIDEDN =>
                           Vector.VSLIDEDOWN_VX
                             (CPU.VU, Vd, Vs2, Rs1_Val, VM);
                        when VFUNCT6_VMERGE =>
                           if VM then
                              Vector.VMV_V_X (CPU.VU, Vd, Rs1_Val);
                           else
                              Vector.VMERGE_VXM (CPU.VU, Vd, Vs2, Rs1_Val);
                           end if;
                        when VFUNCT6_VNSRL =>
                           Vector.VNSRL_WX (CPU.VU, Vd, Vs2, Rs1_Val, VM);
                        when VFUNCT6_VNSRA =>
                           Vector.VNSRA_WX (CPU.VU, Vd, Vs2, Rs1_Val, VM);
                        when VFUNCT6_VWADDU =>
                           Vector.VWADDU_VX (CPU.VU, Vd, Vs2, Rs1_Val, VM);
                        when VFUNCT6_VWADD =>
                           Vector.VWADD_VX (CPU.VU, Vd, Vs2, Rs1_Val, VM);
                        when VFUNCT6_VWSUBU =>
                           Vector.VWSUBU_VX (CPU.VU, Vd, Vs2, Rs1_Val, VM);
                        when VFUNCT6_VWSUB =>
                           Vector.VWSUB_VX (CPU.VU, Vd, Vs2, Rs1_Val, VM);
                        when VFUNCT6_VWADDUW =>
                           Vector.VWADDUW_VX (CPU.VU, Vd, Vs2, Rs1_Val, VM);
                        when VFUNCT6_VWADDW =>
                           Vector.VWADDW_VX (CPU.VU, Vd, Vs2, Rs1_Val, VM);
                        when VFUNCT6_VWSUBUW =>
                           Vector.VWSUBUW_VX (CPU.VU, Vd, Vs2, Rs1_Val, VM);
                        when VFUNCT6_VWSUBW =>
                           Vector.VWSUBW_VX (CPU.VU, Vd, Vs2, Rs1_Val, VM);
                        when VFUNCT6_VADC =>
                           Vector.VADC_VXM (CPU.VU, Vd, Vs2, Rs1_Val);
                        when VFUNCT6_VMADC =>
                           Vector.VMADC_VXM (CPU.VU, Vd, Vs2, Rs1_Val, VM);
                        when VFUNCT6_VSBC =>
                           Vector.VSBC_VXM (CPU.VU, Vd, Vs2, Rs1_Val);
                        when VFUNCT6_VMSBC =>
                           Vector.VMSBC_VXM (CPU.VU, Vd, Vs2, Rs1_Val, VM);
                        when VFUNCT6_VSADDU =>
                           Vector.VSADDU_VX (CPU.VU, Vd, Vs2, Rs1_Val, VM);
                        when VFUNCT6_VSADD =>
                           Vector.VSADD_VX (CPU.VU, Vd, Vs2, Rs1_Val, VM);
                        when VFUNCT6_VSSUBU =>
                           Vector.VSSUBU_VX (CPU.VU, Vd, Vs2, Rs1_Val, VM);
                        when VFUNCT6_VSSUB =>
                           Vector.VSSUB_VX (CPU.VU, Vd, Vs2, Rs1_Val, VM);
                        when VFUNCT6_VSMUL =>
                           Vector.VSMUL_VX (CPU.VU, Vd, Vs2, Rs1_Val, VM);
                        when VFUNCT6_VSSRL =>
                           Vector.VSSRL_VX (CPU.VU, Vd, Vs2, Rs1_Val, VM);
                        when VFUNCT6_VSSRA =>
                           Vector.VSSRA_VX (CPU.VU, Vd, Vs2, Rs1_Val, VM);
                        when VFUNCT6_VNCLIPU =>
                           Vector.VNCLIPU_WX (CPU.VU, Vd, Vs2, Rs1_Val, VM);
                        when VFUNCT6_VNCLIP =>
                           Vector.VNCLIP_WX (CPU.VU, Vd, Vs2, Rs1_Val, VM);
                        when others =>
                           CPU.Exception_Code := Illegal_Instruction;
                           Trap_Entry (CPU, CSR.CAUSE_ILLEGAL_INSN, Instruction);
                           return;
                     end case;

                  --  OPIVI: Integer vector-immediate
                  when FUNCT3_OPIVI =>
                     case Funct6 is
                        when VFUNCT6_VADD =>
                           Vector.VADD_VI (CPU.VU, Vd, Vs2, Simm5, VM);
                        when VFUNCT6_VRSUB =>
                           Vector.VRSUB_VI (CPU.VU, Vd, Vs2, Simm5, VM);
                        when VFUNCT6_VAND =>
                           Vector.VAND_VI (CPU.VU, Vd, Vs2, Simm5, VM);
                        when VFUNCT6_VOR =>
                           Vector.VOR_VI (CPU.VU, Vd, Vs2, Simm5, VM);
                        when VFUNCT6_VXOR =>
                           Vector.VXOR_VI (CPU.VU, Vd, Vs2, Simm5, VM);
                        when VFUNCT6_VSLL =>
                           Vector.VSLL_VI (CPU.VU, Vd, Vs2, Uimm5, VM);
                        when VFUNCT6_VSRL =>
                           Vector.VSRL_VI (CPU.VU, Vd, Vs2, Uimm5, VM);
                        when VFUNCT6_VSRA =>
                           Vector.VSRA_VI (CPU.VU, Vd, Vs2, Uimm5, VM);
                        when VFUNCT6_VMSEQ =>
                           Vector.VMSEQ_VI (CPU.VU, Vd, Vs2, Simm5, VM);
                        when VFUNCT6_VMSNE =>
                           Vector.VMSNE_VI (CPU.VU, Vd, Vs2, Simm5, VM);
                        when VFUNCT6_VMSLEU =>
                           Vector.VMSLEU_VI (CPU.VU, Vd, Vs2, Simm5, VM);
                        when VFUNCT6_VMSLE =>
                           Vector.VMSLE_VI (CPU.VU, Vd, Vs2, Simm5, VM);
                        when VFUNCT6_VMSGTU =>
                           Vector.VMSGTU_VI (CPU.VU, Vd, Vs2, Simm5, VM);
                        when VFUNCT6_VMSGT =>
                           Vector.VMSGT_VI (CPU.VU, Vd, Vs2, Simm5, VM);
                        when VFUNCT6_VRGATHER =>
                           Vector.VRGATHER_VI (CPU.VU, Vd, Vs2, Uimm5, VM);
                        when VFUNCT6_VSLIDEUP =>
                           Vector.VSLIDEUP_VI (CPU.VU, Vd, Vs2, Uimm5, VM);
                        when VFUNCT6_VSLIDEDN =>
                           Vector.VSLIDEDOWN_VI
                             (CPU.VU, Vd, Vs2, Uimm5, VM);
                        when VFUNCT6_VMERGE =>
                           if VM then
                              Vector.VMV_V_I (CPU.VU, Vd, Simm5);
                           else
                              Vector.VMERGE_VIM (CPU.VU, Vd, Vs2, Simm5);
                           end if;
                        when VFUNCT6_VNSRL =>
                           Vector.VNSRL_WI (CPU.VU, Vd, Vs2, Uimm5, VM);
                        when VFUNCT6_VNSRA =>
                           Vector.VNSRA_WI (CPU.VU, Vd, Vs2, Uimm5, VM);
                        when VFUNCT6_VADC =>
                           Vector.VADC_VIM (CPU.VU, Vd, Vs2, Simm5);
                        when VFUNCT6_VMADC =>
                           Vector.VMADC_VIM (CPU.VU, Vd, Vs2, Simm5, VM);
                        when VFUNCT6_VSADDU =>
                           Vector.VSADDU_VI (CPU.VU, Vd, Vs2, Simm5, VM);
                        when VFUNCT6_VSADD =>
                           Vector.VSADD_VI (CPU.VU, Vd, Vs2, Simm5, VM);
                        when VFUNCT6_VSSRL =>
                           Vector.VSSRL_VI (CPU.VU, Vd, Vs2, Uimm5, VM);
                        when VFUNCT6_VSSRA =>
                           Vector.VSSRA_VI (CPU.VU, Vd, Vs2, Uimm5, VM);
                        when VFUNCT6_VNCLIPU =>
                           Vector.VNCLIPU_WI (CPU.VU, Vd, Vs2, Uimm5, VM);
                        when VFUNCT6_VNCLIP =>
                           Vector.VNCLIP_WI (CPU.VU, Vd, Vs2, Uimm5, VM);
                        when VFUNCT6_VMV_REG =>
                           --  vmv<n>r.v: copy N vector register groups
                           --  Encoded in OPIVI: vm=1, uimm5=nr-1 (0,1,3,7)
                           if VM and then (Uimm5 in 0 | 1 | 3 | 7) then
                              declare
                                 NReg : Positive;
                              begin
                                 case Uimm5 is
                                    when 0 => NReg := 1;
                                    when 1 => NReg := 2;
                                    when 3 => NReg := 4;
                                    when 7 => NReg := 8;
                                    when others =>
                                       CPU.Exception_Code := Illegal_Instruction;
                                       Trap_Entry (CPU, CSR.CAUSE_ILLEGAL_INSN,
                                                   Instruction);
                                       return;
                                 end case;
                                 Vector.VMV_NR_V (CPU.VU, Vd, Vs2, NReg);
                              end;
                           else
                              CPU.Exception_Code := Illegal_Instruction;
                              Trap_Entry (CPU, CSR.CAUSE_ILLEGAL_INSN, Instruction);
                              return;
                           end if;
                        when others =>
                           CPU.Exception_Code := Illegal_Instruction;
                           Trap_Entry (CPU, CSR.CAUSE_ILLEGAL_INSN, Instruction);
                           return;
                     end case;

                  --  OPMVV: Mask/reduction vector-vector
                  when FUNCT3_OPMVV =>
                     case Funct6 is
                        when VFUNCT6_VREDSUM =>
                           Vector.VMV_S_X (CPU.VU, Vd,
                             Vector.VREDSUM_VS (CPU.VU, Vs2, Vs1, VM));
                        when VFUNCT6_VREDAND =>
                           Vector.VMV_S_X (CPU.VU, Vd,
                             Vector.VREDAND_VS (CPU.VU, Vs2, Vs1, VM));
                        when VFUNCT6_VREDOR =>
                           Vector.VMV_S_X (CPU.VU, Vd,
                             Vector.VREDOR_VS (CPU.VU, Vs2, Vs1, VM));
                        when VFUNCT6_VREDXOR =>
                           Vector.VMV_S_X (CPU.VU, Vd,
                             Vector.VREDXOR_VS (CPU.VU, Vs2, Vs1, VM));
                        when VFUNCT6_VREDMINU =>
                           Vector.VMV_S_X (CPU.VU, Vd,
                             Vector.VREDMINU_VS (CPU.VU, Vs2, Vs1, VM));
                        when VFUNCT6_VREDMIN =>
                           Vector.VMV_S_X (CPU.VU, Vd,
                             Vector.VREDMIN_VS (CPU.VU, Vs2, Vs1, VM));
                        when VFUNCT6_VREDMAXU =>
                           Vector.VMV_S_X (CPU.VU, Vd,
                             Vector.VREDMAXU_VS (CPU.VU, Vs2, Vs1, VM));
                        when VFUNCT6_VREDMAX =>
                           Vector.VMV_S_X (CPU.VU, Vd,
                             Vector.VREDMAX_VS (CPU.VU, Vs2, Vs1, VM));
                        when VFUNCT6_VMV_X_S =>
                           --  funct6=010000: vmv.x.s / vcpop.m / vfirst.m
                           --  distinguished by vs1 field
                           case Vs1 is
                              when 0 =>
                                 --  vmv.x.s: Move scalar to x register
                                 Write_Register (CPU, Decoded.Rd,
                                   Vector.VMV_X_S (CPU.VU, Vs2));
                              when 16 =>
                                 --  vcpop.m: Count population of mask
                                 Write_Register (CPU, Decoded.Rd,
                                   Vector.VCPOP_M (CPU.VU, Vs2, VM));
                              when 17 =>
                                 --  vfirst.m: Find first set mask bit
                                 Write_Register (CPU, Decoded.Rd,
                                   To_Word (Vector.VFIRST_M (CPU.VU, Vs2, VM)));
                              when others =>
                                 CPU.Exception_Code := Illegal_Instruction;
                                 Trap_Entry (CPU, CSR.CAUSE_ILLEGAL_INSN,
                                             Instruction);
                                 return;
                           end case;
                        when VFUNCT6_VMANDNOT =>
                           Vector.VMANDNOT_MM (CPU.VU, Vd, Vs2, Vs1);
                        when VFUNCT6_VMAND =>
                           Vector.VMAND_MM (CPU.VU, Vd, Vs2, Vs1);
                        when VFUNCT6_VMXOR =>
                           Vector.VMXOR_MM (CPU.VU, Vd, Vs2, Vs1);
                        when VFUNCT6_VMOR =>
                           Vector.VMOR_MM (CPU.VU, Vd, Vs2, Vs1);
                        when VFUNCT6_VMORNOT =>
                           Vector.VMORNOT_MM (CPU.VU, Vd, Vs2, Vs1);
                        when VFUNCT6_VMNAND =>
                           Vector.VMNAND_MM (CPU.VU, Vd, Vs2, Vs1);
                        when VFUNCT6_VMNOR =>
                           Vector.VMNOR_MM (CPU.VU, Vd, Vs2, Vs1);
                        when VFUNCT6_VMXNOR =>
                           Vector.VMXNOR_MM (CPU.VU, Vd, Vs2, Vs1);
                        --  Special operations: viota, vid, vmsbf, etc. (funct6=010100)
                        when VFUNCT6_VID =>
                           --  Distinguish by rs1 value
                           case Vs1 is
                              when 16 =>  --  10000: viota.m
                                 Vector.VIOTA_M (CPU.VU, Vd, Vs2, VM);
                              when 17 =>  --  10001: vid.v
                                 Vector.VID_V (CPU.VU, Vd, VM);
                              when 1 =>   --  00001: vmsbf.m
                                 Vector.VMSBF_M (CPU.VU, Vd, Vs2, VM);
                              when 2 =>   --  00010: vmsof.m
                                 Vector.VMSOF_M (CPU.VU, Vd, Vs2, VM);
                              when 3 =>   --  00011: vmsif.m
                                 Vector.VMSIF_M (CPU.VU, Vd, Vs2, VM);
                              when others =>
                                 CPU.Exception_Code := Illegal_Instruction;
                                 Trap_Entry (CPU, CSR.CAUSE_ILLEGAL_INSN, Instruction);
                                 return;
                           end case;
                        --  Integer multiply/divide vector-vector
                        when VFUNCT6_VMULHU =>
                           Vector.VMULHU_VV (CPU.VU, Vd, Vs2, Vs1, VM);
                        when VFUNCT6_VMUL =>
                           Vector.VMUL_VV (CPU.VU, Vd, Vs2, Vs1, VM);
                        when VFUNCT6_VMULH =>
                           Vector.VMULH_VV (CPU.VU, Vd, Vs2, Vs1, VM);
                        when VFUNCT6_VDIVU =>
                           Vector.VDIVU_VV (CPU.VU, Vd, Vs2, Vs1, VM);
                        when VFUNCT6_VDIV =>
                           Vector.VDIV_VV (CPU.VU, Vd, Vs2, Vs1, VM);
                        when VFUNCT6_VREMU =>
                           Vector.VREMU_VV (CPU.VU, Vd, Vs2, Vs1, VM);
                        when VFUNCT6_VREM =>
                           Vector.VREM_VV (CPU.VU, Vd, Vs2, Vs1, VM);
                        when VFUNCT6_VWMULU =>
                           Vector.VWMULU_VV (CPU.VU, Vd, Vs2, Vs1, VM);
                        when VFUNCT6_VWMUL =>
                           Vector.VWMUL_VV (CPU.VU, Vd, Vs2, Vs1, VM);
                        when VFUNCT6_VWMULSU =>
                           Vector.VWMULSU_VV (CPU.VU, Vd, Vs2, Vs1, VM);
                        when VFUNCT6_VMACC =>
                           Vector.VMACC_VV (CPU.VU, Vd, Vs1, Vs2, VM);
                        when VFUNCT6_VNMSAC =>
                           Vector.VNMSAC_VV (CPU.VU, Vd, Vs1, Vs2, VM);
                        when VFUNCT6_VMADD =>
                           Vector.VMADD_VV (CPU.VU, Vd, Vs1, Vs2, VM);
                        when VFUNCT6_VNMSUB =>
                           Vector.VNMSUB_VV (CPU.VU, Vd, Vs1, Vs2, VM);
                        when VFUNCT6_VMULHSU =>
                           Vector.VMULHSU_VV (CPU.VU, Vd, Vs2, Vs1, VM);
                        when VFUNCT6_VWMACCU =>
                           Vector.VWMACCU_VV (CPU.VU, Vd, Vs1, Vs2, VM);
                        when VFUNCT6_VWMACC =>
                           Vector.VWMACC_VV (CPU.VU, Vd, Vs1, Vs2, VM);
                        when VFUNCT6_VWMACCSU =>
                           Vector.VWMACCSU_VV (CPU.VU, Vd, Vs1, Vs2, VM);
                        when VFUNCT6_VAADDU =>
                           Vector.VAADDU_VV (CPU.VU, Vd, Vs2, Vs1, VM);
                        when VFUNCT6_VAADD =>
                           Vector.VAADD_VV (CPU.VU, Vd, Vs2, Vs1, VM);
                        when VFUNCT6_VASUBU =>
                           Vector.VASUBU_VV (CPU.VU, Vd, Vs2, Vs1, VM);
                        when VFUNCT6_VASUB =>
                           Vector.VASUB_VV (CPU.VU, Vd, Vs2, Vs1, VM);
                        when VFUNCT6_VCOMPRESS =>
                           Vector.VCOMPRESS_VM (CPU.VU, Vd, Vs2, Vs1);
                        when VFUNCT6_VZEXT =>
                           --  vzext/vsext: distinguished by vs1 field
                           --  RVV spec VIWUNARY0 table:
                           --    vs1=00010(2)->vzext.vf8, 00011(3)->vsext.vf8
                           --    vs1=00100(4)->vzext.vf4, 00101(5)->vsext.vf4
                           --    vs1=00110(6)->vzext.vf2, 00111(7)->vsext.vf2
                           case Vs1 is
                              when 2 =>  -- vzext.vf8 (8x zero-extend)
                                 Vector.VZEXT_VF8 (CPU.VU, Vd, Vs2, VM);
                              when 3 =>  -- vsext.vf8 (8x sign-extend)
                                 Vector.VSEXT_VF8 (CPU.VU, Vd, Vs2, VM);
                              when 4 =>  -- vzext.vf4 (4x zero-extend)
                                 Vector.VZEXT_VF4 (CPU.VU, Vd, Vs2, VM);
                              when 5 =>  -- vsext.vf4 (4x sign-extend)
                                 Vector.VSEXT_VF4 (CPU.VU, Vd, Vs2, VM);
                              when 6 =>  -- vzext.vf2 (2x zero-extend)
                                 Vector.VZEXT_VF2 (CPU.VU, Vd, Vs2, VM);
                              when 7 =>  -- vsext.vf2 (2x sign-extend)
                                 Vector.VSEXT_VF2 (CPU.VU, Vd, Vs2, VM);
                              when others =>
                                 CPU.Exception_Code := Illegal_Instruction;
                                 Trap_Entry (CPU, CSR.CAUSE_ILLEGAL_INSN,
                                             Instruction);
                                 return;
                           end case;
                        when others =>
                           CPU.Exception_Code := Illegal_Instruction;
                           Trap_Entry (CPU, CSR.CAUSE_ILLEGAL_INSN, Instruction);
                           return;
                     end case;

                  --  OPMVX: Mask vector-scalar
                  when FUNCT3_OPMVX =>
                     case Funct6 is
                        when VFUNCT6_VMV_S_X =>
                           --  vmv.s.x: Move x register to vector element 0
                           Vector.VMV_S_X (CPU.VU, Vd, Rs1_Val);
                        when VFUNCT6_VMULHU =>
                           Vector.VMULHU_VX (CPU.VU, Vd, Vs2, Rs1_Val, VM);
                        when VFUNCT6_VMUL =>
                           Vector.VMUL_VX (CPU.VU, Vd, Vs2, Rs1_Val, VM);
                        when VFUNCT6_VMULH =>
                           Vector.VMULH_VX (CPU.VU, Vd, Vs2, Rs1_Val, VM);
                        when VFUNCT6_VDIVU =>
                           Vector.VDIVU_VX (CPU.VU, Vd, Vs2, Rs1_Val, VM);
                        when VFUNCT6_VDIV =>
                           Vector.VDIV_VX (CPU.VU, Vd, Vs2, Rs1_Val, VM);
                        when VFUNCT6_VREMU =>
                           Vector.VREMU_VX (CPU.VU, Vd, Vs2, Rs1_Val, VM);
                        when VFUNCT6_VREM =>
                           Vector.VREM_VX (CPU.VU, Vd, Vs2, Rs1_Val, VM);
                        when VFUNCT6_VWMULU =>
                           Vector.VWMULU_VX (CPU.VU, Vd, Vs2, Rs1_Val, VM);
                        when VFUNCT6_VWMUL =>
                           Vector.VWMUL_VX (CPU.VU, Vd, Vs2, Rs1_Val, VM);
                        when VFUNCT6_VWMULSU =>
                           Vector.VWMULSU_VX (CPU.VU, Vd, Vs2, Rs1_Val, VM);
                        when VFUNCT6_VMACC =>
                           Vector.VMACC_VX
                             (CPU.VU, Vd, Rs1_Val, Vs2, VM);
                        when VFUNCT6_VNMSAC =>
                           Vector.VNMSAC_VX
                             (CPU.VU, Vd, Rs1_Val, Vs2, VM);
                        when VFUNCT6_VMADD =>
                           Vector.VMADD_VX
                             (CPU.VU, Vd, Rs1_Val, Vs2, VM);
                        when VFUNCT6_VNMSUB =>
                           Vector.VNMSUB_VX
                             (CPU.VU, Vd, Rs1_Val, Vs2, VM);
                        when VFUNCT6_VSLIDE1UP =>
                           Vector.VSLIDE1UP_VX
                             (CPU.VU, Vd, Vs2, Rs1_Val, VM);
                        when VFUNCT6_VSLIDE1DN =>
                           Vector.VSLIDE1DOWN_VX
                             (CPU.VU, Vd, Vs2, Rs1_Val, VM);
                        when VFUNCT6_VMULHSU =>
                           Vector.VMULHSU_VX (CPU.VU, Vd, Vs2, Rs1_Val, VM);
                        when VFUNCT6_VWMACCU =>
                           Vector.VWMACCU_VX
                             (CPU.VU, Vd, Rs1_Val, Vs2, VM);
                        when VFUNCT6_VWMACC =>
                           Vector.VWMACC_VX
                             (CPU.VU, Vd, Rs1_Val, Vs2, VM);
                        when VFUNCT6_VWMACCSU =>
                           Vector.VWMACCSU_VX
                             (CPU.VU, Vd, Rs1_Val, Vs2, VM);
                        when VFUNCT6_VWMACCUS =>
                           Vector.VWMACCUS_VX
                             (CPU.VU, Vd, Rs1_Val, Vs2, VM);
                        when VFUNCT6_VAADDU =>
                           Vector.VAADDU_VX (CPU.VU, Vd, Vs2, Rs1_Val, VM);
                        when VFUNCT6_VAADD =>
                           Vector.VAADD_VX (CPU.VU, Vd, Vs2, Rs1_Val, VM);
                        when VFUNCT6_VASUBU =>
                           Vector.VASUBU_VX (CPU.VU, Vd, Vs2, Rs1_Val, VM);
                        when VFUNCT6_VASUB =>
                           Vector.VASUB_VX (CPU.VU, Vd, Vs2, Rs1_Val, VM);
                        when others =>
                           CPU.Exception_Code := Illegal_Instruction;
                           Trap_Entry (CPU, CSR.CAUSE_ILLEGAL_INSN, Instruction);
                           return;
                     end case;

                  --  OPFVV: FP vector-vector
                  when FUNCT3_OPFVV =>
                     declare
                        FP_Acc : constant Vector.FPU_Access :=
                           CPU.FP'Unchecked_Access;
                     begin
                        case Funct6 is
                           when VFUNCT6_VFADD =>
                              Vector.VFADD_VV (CPU.VU, FP_Acc, Vd, Vs2, Vs1, VM);
                           when VFUNCT6_VFSUB =>
                              Vector.VFSUB_VV (CPU.VU, FP_Acc, Vd, Vs2, Vs1, VM);
                           when VFUNCT6_VFMUL =>
                              Vector.VFMUL_VV (CPU.VU, FP_Acc, Vd, Vs2, Vs1, VM);
                           when VFUNCT6_VFDIV =>
                              Vector.VFDIV_VV (CPU.VU, FP_Acc, Vd, Vs2, Vs1, VM);
                           when VFUNCT6_VFMIN =>
                              Vector.VFMIN_VV (CPU.VU, FP_Acc, Vd, Vs2, Vs1, VM);
                           when VFUNCT6_VFMAX =>
                              Vector.VFMAX_VV (CPU.VU, FP_Acc, Vd, Vs2, Vs1, VM);
                           when VFUNCT6_VFMACC =>
                              Vector.VFMACC_VV (CPU.VU, FP_Acc, Vd, Vs1, Vs2, VM);
                           when VFUNCT6_VFNMACC =>
                              Vector.VFNMACC_VV (CPU.VU, FP_Acc, Vd, Vs1, Vs2, VM);
                           when VFUNCT6_VFMSAC =>
                              Vector.VFMSAC_VV (CPU.VU, FP_Acc, Vd, Vs1, Vs2, VM);
                           when VFUNCT6_VFNMSAC =>
                              Vector.VFNMSAC_VV (CPU.VU, FP_Acc, Vd, Vs1, Vs2, VM);
                           --  FP comparison
                           when VFUNCT6_VMFEQ =>
                              Vector.VMFEQ_VV (CPU.VU, FP_Acc, Vd, Vs2, Vs1, VM);
                           when VFUNCT6_VMFLE =>
                              Vector.VMFLE_VV (CPU.VU, FP_Acc, Vd, Vs2, Vs1, VM);
                           when VFUNCT6_VMFLT =>
                              Vector.VMFLT_VV (CPU.VU, FP_Acc, Vd, Vs2, Vs1, VM);
                           when VFUNCT6_VMFNE =>
                              Vector.VMFNE_VV (CPU.VU, FP_Acc, Vd, Vs2, Vs1, VM);
                           --  FP sign injection
                           when VFUNCT6_VFSGNJ =>
                              Vector.VFSGNJ_VV (CPU.VU, FP_Acc, Vd, Vs2, Vs1, VM);
                           when VFUNCT6_VFSGNJN =>
                              Vector.VFSGNJN_VV (CPU.VU, FP_Acc, Vd, Vs2, Vs1, VM);
                           when VFUNCT6_VFSGNJX =>
                              Vector.VFSGNJX_VV (CPU.VU, FP_Acc, Vd, Vs2, Vs1, VM);
                           --  FP reverse div/sub (OPFVF only for these)
                           when VFUNCT6_VFRDIV =>
                              --  funct6=100001 in OPFVV is undefined
                              CPU.Exception_Code := Illegal_Instruction;
                              Trap_Entry (CPU, CSR.CAUSE_ILLEGAL_INSN,
                                          Instruction);
                              return;
                           --  FP unary: sqrt/rsqrt7/rec7/class (funct6=010011)
                           when VFUNCT6_VFSQRT =>
                              case Vs1 is
                                 when 0 =>
                                    Vector.VFSQRT_V
                                      (CPU.VU, FP_Acc, Vd, Vs2, VM);
                                 when 4 =>
                                    Vector.VFRSQRT7_V
                                      (CPU.VU, FP_Acc, Vd, Vs2, VM);
                                 when 5 =>
                                    Vector.VFREC7_V
                                      (CPU.VU, FP_Acc, Vd, Vs2, VM);
                                 when 16 =>
                                    Vector.VFCLASS_V
                                      (CPU.VU, FP_Acc, Vd, Vs2, VM);
                                 when others =>
                                    CPU.Exception_Code := Illegal_Instruction;
                                    Trap_Entry (CPU, CSR.CAUSE_ILLEGAL_INSN,
                                                Instruction);
                                    return;
                              end case;
                           --  FP conversion unary (funct6=010010)
                           when VFUNCT6_VFUNARY =>
                              case Vs1 is
                                 when 0 =>
                                    Vector.VFCVT_XU_F_V
                                      (CPU.VU, FP_Acc, Vd, Vs2, VM);
                                 when 1 =>
                                    Vector.VFCVT_X_F_V
                                      (CPU.VU, FP_Acc, Vd, Vs2, VM);
                                 when 2 =>
                                    Vector.VFCVT_F_XU_V
                                      (CPU.VU, FP_Acc, Vd, Vs2, VM);
                                 when 3 =>
                                    Vector.VFCVT_F_X_V
                                      (CPU.VU, FP_Acc, Vd, Vs2, VM);
                                 when 6 =>
                                    Vector.VFCVT_RTZ_XU_F_V
                                      (CPU.VU, FP_Acc, Vd, Vs2, VM);
                                 when 7 =>
                                    Vector.VFCVT_RTZ_X_F_V
                                      (CPU.VU, FP_Acc, Vd, Vs2, VM);
                                 when 8 =>
                                    Vector.VFWCVT_XU_F_V
                                      (CPU.VU, FP_Acc, Vd, Vs2, VM);
                                 when 9 =>
                                    Vector.VFWCVT_X_F_V
                                      (CPU.VU, FP_Acc, Vd, Vs2, VM);
                                 when 10 =>
                                    Vector.VFWCVT_F_XU_V
                                      (CPU.VU, FP_Acc, Vd, Vs2, VM);
                                 when 11 =>
                                    Vector.VFWCVT_F_X_V
                                      (CPU.VU, FP_Acc, Vd, Vs2, VM);
                                 when 12 =>
                                    Vector.VFWCVT_F_F_V
                                      (CPU.VU, FP_Acc, Vd, Vs2, VM);
                                 when 14 =>
                                    Vector.VFWCVT_RTZ_XU_F_V
                                      (CPU.VU, FP_Acc, Vd, Vs2, VM);
                                 when 15 =>
                                    Vector.VFWCVT_RTZ_X_F_V
                                      (CPU.VU, FP_Acc, Vd, Vs2, VM);
                                 when 16 =>
                                    Vector.VFNCVT_XU_F_W
                                      (CPU.VU, FP_Acc, Vd, Vs2, VM);
                                 when 17 =>
                                    Vector.VFNCVT_X_F_W
                                      (CPU.VU, FP_Acc, Vd, Vs2, VM);
                                 when 18 =>
                                    Vector.VFNCVT_F_XU_W
                                      (CPU.VU, FP_Acc, Vd, Vs2, VM);
                                 when 19 =>
                                    Vector.VFNCVT_F_X_W
                                      (CPU.VU, FP_Acc, Vd, Vs2, VM);
                                 when 20 =>
                                    Vector.VFNCVT_F_F_W
                                      (CPU.VU, FP_Acc, Vd, Vs2, VM);
                                 when 21 =>
                                    Vector.VFNCVT_ROD_F_F_W
                                      (CPU.VU, FP_Acc, Vd, Vs2, VM);
                                 when 22 =>
                                    Vector.VFNCVT_RTZ_XU_F_W
                                      (CPU.VU, FP_Acc, Vd, Vs2, VM);
                                 when 23 =>
                                    Vector.VFNCVT_RTZ_X_F_W
                                      (CPU.VU, FP_Acc, Vd, Vs2, VM);
                                 when others =>
                                    CPU.Exception_Code := Illegal_Instruction;
                                    Trap_Entry (CPU, CSR.CAUSE_ILLEGAL_INSN,
                                                Instruction);
                                    return;
                              end case;
                           --  FP widening arithmetic
                           when VFUNCT6_VFWADD =>
                              Vector.VFWADD_VV (CPU.VU, FP_Acc, Vd, Vs2, Vs1, VM);
                           when VFUNCT6_VFWSUB =>
                              Vector.VFWSUB_VV (CPU.VU, FP_Acc, Vd, Vs2, Vs1, VM);
                           when VFUNCT6_VFWADDW =>
                              Vector.VFWADDW_VV (CPU.VU, FP_Acc, Vd, Vs2, Vs1, VM);
                           when VFUNCT6_VFWSUBW =>
                              Vector.VFWSUBW_VV (CPU.VU, FP_Acc, Vd, Vs2, Vs1, VM);
                           when VFUNCT6_VFWMUL =>
                              Vector.VFWMUL_VV (CPU.VU, FP_Acc, Vd, Vs2, Vs1, VM);
                           --  FP widening MAC
                           when VFUNCT6_VFWMACC =>
                              Vector.VFWMACC_VV (CPU.VU, FP_Acc, Vd, Vs1, Vs2, VM);
                           when VFUNCT6_VFWNMACC =>
                              Vector.VFWNMACC_VV (CPU.VU, FP_Acc, Vd, Vs1, Vs2, VM);
                           when VFUNCT6_VFWMSAC =>
                              Vector.VFWMSAC_VV (CPU.VU, FP_Acc, Vd, Vs1, Vs2, VM);
                           when VFUNCT6_VFWNMSAC =>
                              Vector.VFWNMSAC_VV (CPU.VU, FP_Acc, Vd, Vs1, Vs2, VM);
                           --  FP reduction
                           when VFUNCT6_VFREDOSUM =>
                              Vector.VFREDOSUM_VS
                                (CPU.VU, FP_Acc, Vd, Vs2, Vs1, VM);
                           when VFUNCT6_VFREDUSUM =>
                              Vector.VFREDUSUM_VS
                                (CPU.VU, FP_Acc, Vd, Vs2, Vs1, VM);
                           when VFUNCT6_VFREDMIN =>
                              Vector.VFREDMIN_VS
                                (CPU.VU, FP_Acc, Vd, Vs2, Vs1, VM);
                           when VFUNCT6_VFREDMAX =>
                              Vector.VFREDMAX_VS
                                (CPU.VU, FP_Acc, Vd, Vs2, Vs1, VM);
                           --  FP widening reduction
                           when VFUNCT6_VFWREDOSUM =>
                              Vector.VFWREDOSUM_VS
                                (CPU.VU, FP_Acc, Vd, Vs2, Vs1, VM);
                           when VFUNCT6_VFWREDUSUM =>
                              Vector.VFWREDUSUM_VS
                                (CPU.VU, FP_Acc, Vd, Vs2, Vs1, VM);
                           --  FP scalar move: vfmv.f.s (funct6=010000)
                           when VFUNCT6_VMV_X_S =>
                              FPU.Write_Single (CPU.FP, Decoded.Rd,
                                Vector.VFMV_F_S (CPU.VU, Vs2));
                           when others =>
                              CPU.Exception_Code := Illegal_Instruction;
                              Trap_Entry (CPU, CSR.CAUSE_ILLEGAL_INSN,
                                          Instruction);
                              return;
                        end case;
                     end;

                  --  OPFVF: FP vector-scalar
                  when FUNCT3_OPFVF =>
                     declare
                        FP_Acc : constant Vector.FPU_Access :=
                           CPU.FP'Unchecked_Access;
                        Fs1    : constant Word :=
                           FPU.Read_Single (CPU.FP, Decoded.Rs1);
                     begin
                        case Funct6 is
                           when VFUNCT6_VFADD =>
                              Vector.VFADD_VF (CPU.VU, FP_Acc, Vd, Vs2, Fs1, VM);
                           when VFUNCT6_VFSUB =>
                              Vector.VFSUB_VF (CPU.VU, FP_Acc, Vd, Vs2, Fs1, VM);
                           when VFUNCT6_VFMUL =>
                              Vector.VFMUL_VF (CPU.VU, FP_Acc, Vd, Vs2, Fs1, VM);
                           when VFUNCT6_VFDIV =>
                              Vector.VFDIV_VF (CPU.VU, FP_Acc, Vd, Vs2, Fs1, VM);
                           when VFUNCT6_VFMIN =>
                              Vector.VFMIN_VF (CPU.VU, FP_Acc, Vd, Vs2, Fs1, VM);
                           when VFUNCT6_VFMAX =>
                              Vector.VFMAX_VF (CPU.VU, FP_Acc, Vd, Vs2, Fs1, VM);
                           when VFUNCT6_VFMACC =>
                              Vector.VFMACC_VF (CPU.VU, FP_Acc, Vd, Fs1, Vs2, VM);
                           when VFUNCT6_VFNMACC =>
                              Vector.VFNMACC_VF (CPU.VU, FP_Acc, Vd, Fs1, Vs2, VM);
                           when VFUNCT6_VFMSAC =>
                              Vector.VFMSAC_VF (CPU.VU, FP_Acc, Vd, Fs1, Vs2, VM);
                           when VFUNCT6_VFNMSAC =>
                              Vector.VFNMSAC_VF (CPU.VU, FP_Acc, Vd, Fs1, Vs2, VM);
                           --  FP comparison
                           when VFUNCT6_VMFEQ =>
                              Vector.VMFEQ_VF (CPU.VU, FP_Acc, Vd, Vs2, Fs1, VM);
                           when VFUNCT6_VMFLE =>
                              Vector.VMFLE_VF (CPU.VU, FP_Acc, Vd, Vs2, Fs1, VM);
                           when VFUNCT6_VMFLT =>
                              Vector.VMFLT_VF (CPU.VU, FP_Acc, Vd, Vs2, Fs1, VM);
                           when VFUNCT6_VMFNE =>
                              Vector.VMFNE_VF (CPU.VU, FP_Acc, Vd, Vs2, Fs1, VM);
                           when VFUNCT6_VMFGT =>
                              Vector.VMFGT_VF (CPU.VU, FP_Acc, Vd, Vs2, Fs1, VM);
                           when VFUNCT6_VMFGE =>
                              Vector.VMFGE_VF (CPU.VU, FP_Acc, Vd, Vs2, Fs1, VM);
                           --  FP sign injection
                           when VFUNCT6_VFSGNJ =>
                              Vector.VFSGNJ_VF (CPU.VU, FP_Acc, Vd, Vs2, Fs1, VM);
                           when VFUNCT6_VFSGNJN =>
                              Vector.VFSGNJN_VF (CPU.VU, FP_Acc, Vd, Vs2, Fs1, VM);
                           when VFUNCT6_VFSGNJX =>
                              Vector.VFSGNJX_VF (CPU.VU, FP_Acc, Vd, Vs2, Fs1, VM);
                           --  FP reverse ops
                           when VFUNCT6_VFRDIV =>
                              Vector.VFRDIV_VF (CPU.VU, FP_Acc, Vd, Vs2, Fs1, VM);
                           when VFUNCT6_VFRSUB =>
                              Vector.VFRSUB_VF (CPU.VU, FP_Acc, Vd, Vs2, Fs1, VM);
                           --  FP merge/move
                           when VFUNCT6_VFMERGE =>
                              if VM then
                                 Vector.VFMV_V_F (CPU.VU, Vd, Fs1);
                              else
                                 Vector.VFMERGE_VF (CPU.VU, Vd, Vs2, Fs1);
                              end if;
                           --  FP scalar move: vfmv.s.f (funct6=010000)
                           when VFUNCT6_VMV_S_X =>
                              Vector.VFMV_S_F (CPU.VU, Vd, Fs1);
                           --  FP widening arithmetic
                           when VFUNCT6_VFWADD =>
                              Vector.VFWADD_VF (CPU.VU, FP_Acc, Vd, Vs2, Fs1, VM);
                           when VFUNCT6_VFWSUB =>
                              Vector.VFWSUB_VF (CPU.VU, FP_Acc, Vd, Vs2, Fs1, VM);
                           when VFUNCT6_VFWADDW =>
                              Vector.VFWADDW_VF (CPU.VU, FP_Acc, Vd, Vs2, Fs1, VM);
                           when VFUNCT6_VFWSUBW =>
                              Vector.VFWSUBW_VF (CPU.VU, FP_Acc, Vd, Vs2, Fs1, VM);
                           when VFUNCT6_VFWMUL =>
                              Vector.VFWMUL_VF (CPU.VU, FP_Acc, Vd, Vs2, Fs1, VM);
                           --  FP widening MAC
                           when VFUNCT6_VFWMACC =>
                              Vector.VFWMACC_VF (CPU.VU, FP_Acc, Vd, Fs1, Vs2, VM);
                           when VFUNCT6_VFWNMACC =>
                              Vector.VFWNMACC_VF (CPU.VU, FP_Acc, Vd, Fs1, Vs2, VM);
                           when VFUNCT6_VFWMSAC =>
                              Vector.VFWMSAC_VF (CPU.VU, FP_Acc, Vd, Fs1, Vs2, VM);
                           when VFUNCT6_VFWNMSAC =>
                              Vector.VFWNMSAC_VF (CPU.VU, FP_Acc, Vd, Fs1, Vs2, VM);
                           when others =>
                              CPU.Exception_Code := Illegal_Instruction;
                              Trap_Entry (CPU, CSR.CAUSE_ILLEGAL_INSN,
                                          Instruction);
                              return;
                        end case;
                     end;

                  when others =>
                     CPU.Exception_Code := Illegal_Instruction;
                     Trap_Entry (CPU, CSR.CAUSE_ILLEGAL_INSN, Instruction);
                     return;
               end case;
            end;

         --  Vector loads use LOAD_FP opcode with specific width encodings
         when OPCODE_LOAD_FP =>
            Address := Memory_Address
              (To_Word (To_Signed (Rs1_Val) + Decoded.Imm_I));
            Memory.Clear_Access_Fault (Mem);

            case Decoded.Funct3 is
               when FUNCT3_FLH =>
                  --  Load half-precision float (Zfh)
                  declare
                     HW : constant Half_Word :=
                       Memory.Read_Half_Word (Mem, Address);
                  begin
                     FPU.Write_Half (CPU.FP, Decoded.Rd, Word (HW));
                  end;

               when FUNCT3_FLW =>
                  --  Load single-precision float
                  Result := Memory.Read_Word (Mem, Address);
                  FPU.Write_Single (CPU.FP, Decoded.Rd, Result);

               when FUNCT3_FLD =>
                  --  Load double-precision float
                  declare
                     Lo : constant Word := Memory.Read_Word (Mem, Address);
                     Hi : constant Word := Memory.Read_Word (Mem, Address + 4);
                     Val : Unsigned_64;
                  begin
                     Val := Unsigned_64 (Lo) or
                            Shift_Left (Unsigned_64 (Hi), 32);
                     FPU.Write_Double (CPU.FP, Decoded.Rd, FPU.FP_Register (Val));
                  end;

               --  Vector loads
               when FUNCT3_VLE8 | FUNCT3_VLE16 | FUNCT3_VLE32 | FUNCT3_VLE64 =>
                  declare
                     Nf      : constant Natural := Natural (Shift_Right (Instruction, 29) and 7);
                     Mop     : constant Word := Shift_Right (Instruction, 26) and 3;
                     VM      : constant Boolean := (Instruction and 16#02000000#) /= 0;
                     Lumop   : constant Word := Shift_Right (Instruction, 20) and 16#1F#;
                     EEW     : Vector.SEW_Type;
                     Data_EEW : Vector.SEW_Type;
                  begin
                     case Decoded.Funct3 is
                        when FUNCT3_VLE8  => EEW := Vector.SEW_8;
                        when FUNCT3_VLE16 => EEW := Vector.SEW_16;
                        when FUNCT3_VLE32 => EEW := Vector.SEW_32;
                        when FUNCT3_VLE64 => EEW := Vector.SEW_64;
                        when others => EEW := Vector.SEW_32;
                     end case;

                     if Nf = 0 then
                        case Mop is
                           when VL_MOP_UNIT =>
                              if Lumop = VL_LUMOP_WHOLE then
                                 Vector.Vector_Load_Whole_Register
                                   (CPU.VU, Mem, Decoded.Rd, Rs1_Val, 1);
                              else
                                 Vector.Vector_Load_Unit_Stride
                                   (CPU.VU, Mem, Decoded.Rd, Rs1_Val, VM, EEW);
                              end if;
                           when VL_MOP_STRIDE =>
                              Vector.Vector_Load_Strided
                                (CPU.VU, Mem, Decoded.Rd, Rs1_Val, Rs2_Val, VM, EEW);
                           when VL_MOP_INDEX | VL_MOP_INDEXO =>
                              Data_EEW := CPU.VU.VType.VSEW;
                              Vector.Vector_Load_Indexed
                                (CPU.VU, Mem, Decoded.Rd, Rs1_Val,
                                 Decoded.Rs2, VM, Data_EEW, EEW);
                           when others =>
                              CPU.Exception_Code := Illegal_Instruction;
                              Trap_Entry (CPU, CSR.CAUSE_ILLEGAL_INSN, Instruction);
                              return;
                        end case;
                     else
                        --  Segment loads (nf > 0)
                        case Mop is
                           when VL_MOP_UNIT =>
                              if Lumop = VL_LUMOP_WHOLE then
                                 Vector.Vector_Load_Whole_Register
                                   (CPU.VU, Mem, Decoded.Rd, Rs1_Val, Nf + 1);
                              else
                                 Vector.Vector_Load_Segment_Unit
                                   (CPU.VU, Mem, Decoded.Rd, Rs1_Val, VM, EEW, Nf);
                              end if;
                           when VL_MOP_STRIDE =>
                              Vector.Vector_Load_Segment_Strided
                                (CPU.VU, Mem, Decoded.Rd, Rs1_Val, Rs2_Val,
                                 VM, EEW, Nf);
                           when VL_MOP_INDEX | VL_MOP_INDEXO =>
                              Data_EEW := CPU.VU.VType.VSEW;
                              Vector.Vector_Load_Segment_Indexed
                                (CPU.VU, Mem, Decoded.Rd, Rs1_Val,
                                 Decoded.Rs2, VM, Data_EEW, EEW, Nf);
                           when others =>
                              CPU.Exception_Code := Illegal_Instruction;
                              Trap_Entry (CPU, CSR.CAUSE_ILLEGAL_INSN, Instruction);
                              return;
                        end case;
                     end if;
                  end;

               when others =>
                  CPU.Exception_Code := Illegal_Instruction;
                  Trap_Entry (CPU, CSR.CAUSE_ILLEGAL_INSN, Instruction);
                  return;
            end case;

            --  Covers the vector loads too: they touch many bytes and the
            --  fault record keeps the first failing one.
            if Memory.Pending_Fault (Mem) /= Memory.OK then
               CPU.Exception_Code := Load_Access_Fault;
               Trap_Entry (CPU, CSR.CAUSE_LOAD_ACCESS_FAULT,
                           Word (Memory.Pending_Fault_Address (Mem)));
               return;
            end if;

         --  Vector stores use STORE_FP opcode
         when OPCODE_STORE_FP =>
            Address := Memory_Address
              (To_Word (To_Signed (Rs1_Val) + Decoded.Imm_S));
            Memory.Clear_Access_Fault (Mem);

            case Decoded.Funct3 is
               when FUNCT3_FSH =>
                  --  Store half-precision float (Zfh)
                  Memory.Write_Half_Word (Mem, Address,
                    Half_Word (FPU.Read_Half (CPU.FP, Decoded.Rs2) and 16#FFFF#));

               when FUNCT3_FSW =>
                  --  Store single-precision float
                  Result := FPU.Read_Single (CPU.FP, Decoded.Rs2);
                  Memory.Write_Word (Mem, Address, Result);

               when FUNCT3_FSD =>
                  --  Store double-precision float
                  declare
                     Val : constant Unsigned_64 := Unsigned_64
                       (FPU.Read_Double (CPU.FP, Decoded.Rs2));
                  begin
                     Memory.Write_Word (Mem, Address,
                       Word (Val and 16#FFFFFFFF#));
                     Memory.Write_Word (Mem, Address + 4,
                       Word (Shift_Right (Val, 32) and 16#FFFFFFFF#));
                  end;

               --  Vector stores
               when FUNCT3_VLE8 | FUNCT3_VLE16 | FUNCT3_VLE32 | FUNCT3_VLE64 =>
                  declare
                     Nf      : constant Natural := Natural (Shift_Right (Instruction, 29) and 7);
                     Mop     : constant Word := Shift_Right (Instruction, 26) and 3;
                     VM      : constant Boolean := (Instruction and 16#02000000#) /= 0;
                     Sumop   : constant Word := Shift_Right (Instruction, 20) and 16#1F#;
                     EEW     : Vector.SEW_Type;
                     Data_EEW : Vector.SEW_Type;
                  begin
                     case Decoded.Funct3 is
                        when FUNCT3_VLE8  => EEW := Vector.SEW_8;
                        when FUNCT3_VLE16 => EEW := Vector.SEW_16;
                        when FUNCT3_VLE32 => EEW := Vector.SEW_32;
                        when FUNCT3_VLE64 => EEW := Vector.SEW_64;
                        when others => EEW := Vector.SEW_32;
                     end case;

                     if Nf = 0 then
                        case Mop is
                           when VL_MOP_UNIT =>
                              if Sumop = VL_SUMOP_WHOLE then
                                 Vector.Vector_Store_Whole_Register
                                   (CPU.VU, Mem, Decoded.Rd, Rs1_Val, 1);
                              else
                                 Vector.Vector_Store_Unit_Stride
                                   (CPU.VU, Mem, Decoded.Rd, Rs1_Val, VM, EEW);
                              end if;
                           when VL_MOP_STRIDE =>
                              Vector.Vector_Store_Strided
                                (CPU.VU, Mem, Decoded.Rd, Rs1_Val, Rs2_Val, VM, EEW);
                           when VL_MOP_INDEX | VL_MOP_INDEXO =>
                              Data_EEW := CPU.VU.VType.VSEW;
                              Vector.Vector_Store_Indexed
                                (CPU.VU, Mem, Decoded.Rd, Rs1_Val,
                                 Decoded.Rs2, VM, Data_EEW, EEW);
                           when others =>
                              CPU.Exception_Code := Illegal_Instruction;
                              Trap_Entry (CPU, CSR.CAUSE_ILLEGAL_INSN, Instruction);
                              return;
                        end case;
                     else
                        --  Segment stores (nf > 0)
                        case Mop is
                           when VL_MOP_UNIT =>
                              if Sumop = VL_SUMOP_WHOLE then
                                 Vector.Vector_Store_Whole_Register
                                   (CPU.VU, Mem, Decoded.Rd, Rs1_Val, Nf + 1);
                              else
                                 Vector.Vector_Store_Segment_Unit
                                   (CPU.VU, Mem, Decoded.Rd, Rs1_Val, VM, EEW, Nf);
                              end if;
                           when VL_MOP_STRIDE =>
                              Vector.Vector_Store_Segment_Strided
                                (CPU.VU, Mem, Decoded.Rd, Rs1_Val, Rs2_Val,
                                 VM, EEW, Nf);
                           when VL_MOP_INDEX | VL_MOP_INDEXO =>
                              Data_EEW := CPU.VU.VType.VSEW;
                              Vector.Vector_Store_Segment_Indexed
                                (CPU.VU, Mem, Decoded.Rd, Rs1_Val,
                                 Decoded.Rs2, VM, Data_EEW, EEW, Nf);
                           when others =>
                              CPU.Exception_Code := Illegal_Instruction;
                              Trap_Entry (CPU, CSR.CAUSE_ILLEGAL_INSN, Instruction);
                              return;
                        end case;
                     end if;
                  end;

               when others =>
                  CPU.Exception_Code := Illegal_Instruction;
                  Trap_Entry (CPU, CSR.CAUSE_ILLEGAL_INSN, Instruction);
                  return;
            end case;

            --  Covers the vector stores too.
            if Memory.Pending_Fault (Mem) /= Memory.OK then
               CPU.Exception_Code := Store_Access_Fault;
               Trap_Entry (CPU, CSR.CAUSE_STORE_ACCESS_FAULT,
                           Word (Memory.Pending_Fault_Address (Mem)));
               return;
            end if;

         ----------------------------------
         -- A Extension (Atomic Memory Ops)
         ----------------------------------
         when OPCODE_AMO =>
            declare
               Funct5    : constant Word := Decoder.Get_Funct5 (Instruction);
               Mem_Val   : Word;
               New_Val   : Word;
            begin
               --  Only word-sized atomics in RV32A
               if Decoded.Funct3 /= FUNCT3_AMO_W then
                  CPU.Exception_Code := Illegal_Instruction;
                  Trap_Entry (CPU, CSR.CAUSE_ILLEGAL_INSN, Instruction);
                  return;
               end if;

               --  Address from rs1
               Address := Memory_Address (Rs1_Val);
               Memory.Clear_Access_Fault (Mem);

               case Funct5 is
                  --  LR.W: Load Reserved Word
                  when FUNCT5_LR =>
                     Mem_Val := Memory.Read_Word (Mem, Address);
                     Write_Register (CPU, Decoded.Rd, Mem_Val);
                     --  Set reservation
                     CPU.Reserved_Addr := Address;
                     CPU.Reservation_Valid := True;

                  --  SC.W: Store Conditional Word
                  when FUNCT5_SC =>
                     if CPU.Reservation_Valid and then
                        CPU.Reserved_Addr = Address
                     then
                        --  Reservation valid: store succeeds
                        Memory.Write_Word (Mem, Address, Rs2_Val);
                        Write_Register (CPU, Decoded.Rd, 0);  -- Success
                     else
                        --  Reservation invalid: store fails
                        Write_Register (CPU, Decoded.Rd, 1);  -- Failure
                     end if;
                     --  Clear reservation regardless of success
                     CPU.Reservation_Valid := False;

                  --  AMOSWAP.W: Atomic swap
                  when FUNCT5_AMOSWAP =>
                     Mem_Val := Memory.Read_Word (Mem, Address);
                     Memory.Write_Word (Mem, Address, Rs2_Val);
                     Write_Register (CPU, Decoded.Rd, Mem_Val);

                  --  AMOADD.W: Atomic add
                  when FUNCT5_AMOADD =>
                     Mem_Val := Memory.Read_Word (Mem, Address);
                     New_Val := Mem_Val + Rs2_Val;
                     Memory.Write_Word (Mem, Address, New_Val);
                     Write_Register (CPU, Decoded.Rd, Mem_Val);

                  --  AMOXOR.W: Atomic XOR
                  when FUNCT5_AMOXOR =>
                     Mem_Val := Memory.Read_Word (Mem, Address);
                     New_Val := Mem_Val xor Rs2_Val;
                     Memory.Write_Word (Mem, Address, New_Val);
                     Write_Register (CPU, Decoded.Rd, Mem_Val);

                  --  AMOAND.W: Atomic AND
                  when FUNCT5_AMOAND =>
                     Mem_Val := Memory.Read_Word (Mem, Address);
                     New_Val := Mem_Val and Rs2_Val;
                     Memory.Write_Word (Mem, Address, New_Val);
                     Write_Register (CPU, Decoded.Rd, Mem_Val);

                  --  AMOOR.W: Atomic OR
                  when FUNCT5_AMOOR =>
                     Mem_Val := Memory.Read_Word (Mem, Address);
                     New_Val := Mem_Val or Rs2_Val;
                     Memory.Write_Word (Mem, Address, New_Val);
                     Write_Register (CPU, Decoded.Rd, Mem_Val);

                  --  AMOMIN.W: Atomic signed min
                  when FUNCT5_AMOMIN =>
                     Mem_Val := Memory.Read_Word (Mem, Address);
                     if To_Signed (Rs2_Val) < To_Signed (Mem_Val) then
                        New_Val := Rs2_Val;
                     else
                        New_Val := Mem_Val;
                     end if;
                     Memory.Write_Word (Mem, Address, New_Val);
                     Write_Register (CPU, Decoded.Rd, Mem_Val);

                  --  AMOMAX.W: Atomic signed max
                  when FUNCT5_AMOMAX =>
                     Mem_Val := Memory.Read_Word (Mem, Address);
                     if To_Signed (Rs2_Val) > To_Signed (Mem_Val) then
                        New_Val := Rs2_Val;
                     else
                        New_Val := Mem_Val;
                     end if;
                     Memory.Write_Word (Mem, Address, New_Val);
                     Write_Register (CPU, Decoded.Rd, Mem_Val);

                  --  AMOMINU.W: Atomic unsigned min
                  when FUNCT5_AMOMINU =>
                     Mem_Val := Memory.Read_Word (Mem, Address);
                     if Rs2_Val < Mem_Val then
                        New_Val := Rs2_Val;
                     else
                        New_Val := Mem_Val;
                     end if;
                     Memory.Write_Word (Mem, Address, New_Val);
                     Write_Register (CPU, Decoded.Rd, Mem_Val);

                  --  AMOMAXU.W: Atomic unsigned max
                  when FUNCT5_AMOMAXU =>
                     Mem_Val := Memory.Read_Word (Mem, Address);
                     if Rs2_Val > Mem_Val then
                        New_Val := Rs2_Val;
                     else
                        New_Val := Mem_Val;
                     end if;
                     Memory.Write_Word (Mem, Address, New_Val);
                     Write_Register (CPU, Decoded.Rd, Mem_Val);

                  when others =>
                     CPU.Exception_Code := Illegal_Instruction;
                     Trap_Entry (CPU, CSR.CAUSE_ILLEGAL_INSN, Instruction);
                     return;
               end case;

               --  An atomic that could not reach memory faults as a store,
               --  which is what the ISA specifies for AMOs regardless of
               --  which half of the read-modify-write failed.
               if Memory.Pending_Fault (Mem) /= Memory.OK then
                  CPU.Exception_Code := Store_Access_Fault;
                  Trap_Entry (CPU, CSR.CAUSE_STORE_ACCESS_FAULT,
                              Word (Memory.Pending_Fault_Address (Mem)));
                  return;
               end if;
            end;

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
               Trap_Entry (CPU, CSR.CAUSE_ILLEGAL_INSN, Instruction);
               CSR.Increment_Instret (CPU.CSRs);
               CSR.Increment_Mcycle (CPU.CSRs);
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
                        Trap_Entry (CPU, CSR.CAUSE_ILLEGAL_INSN, Instruction);
                        return;
                  end case;
                  Extra_Cycles := 3;  --  FMA: 4 cycles total
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
                           Trap_Entry (CPU, CSR.CAUSE_ILLEGAL_INSN,
                                       Instruction);
                           return;
                     end case;
                  end;
                  Extra_Cycles := 3;  --  FMA: 4 cycles total
               else
                  CPU.Exception_Code := Illegal_Instruction;
                  Trap_Entry (CPU, CSR.CAUSE_ILLEGAL_INSN, Instruction);
                  return;
               end if;
            end;

         ---------------------------------
         -- FENCE / FENCE.I (MISC-MEM)
         ---------------------------------
         when OPCODE_MISC_MEM =>
            --  FENCE and FENCE.I are NOPs in a single-hart emulator
            null;

         when others =>
            CPU.Exception_Code := Illegal_Instruction;
            Trap_Entry (CPU, CSR.CAUSE_ILLEGAL_INSN, Instruction);
            return;
      end case;

      --  Post-execution trace output
      if Trace_Enabled then
         --  Log memory access if enabled
         if Trace_Cfg.Show_Memory and then Mem.Access_Occurred then
            Put_Line ("    MEM: " &
                     (if Mem.Last_Access_Write then "WRITE" else "READ ") &
                     " 0x" & To_Hex (Word (Mem.Last_Access_Addr)));
         end if;

         --  Log register changes if enabled
         if Trace_Cfg.Show_Regs then
            for I in Register_Index loop
               if CPU.Registers (I) /= Old_Regs (I) then
                  Put_Line ("    REG: x" & Register_Index'Image (I) &
                           " = 0x" & To_Hex (Old_Regs (I)) &
                           " -> 0x" & To_Hex (CPU.Registers (I)));
               end if;
            end loop;
         end if;
      end if;

      --  Branch/jump taken: +1 cycle (pipeline refill after non-sequential fetch)
      if (Decoded.Opcode = OPCODE_BRANCH and Next_PC /= CPU.PC + Instr_Size) or
         Decoded.Opcode = OPCODE_JAL or
         Decoded.Opcode = OPCODE_JALR
      then
         Extra_Cycles := Extra_Cycles + 1;
      end if;

      CPU.PC := Next_PC;

      --  Increment performance counters
      CSR.Increment_Instret (CPU.CSRs);
      CSR.Increment_Mcycle (CPU.CSRs, 1 + Extra_Cycles);

      --  HTIF tohost write (riscv-tests) terminates the run.
      if Mem.HTIF_Enabled and then Mem.Tohost_Written then
         CPU.Halted := True;
      end if;
   end Step;

   ---------
   -- Run --
   ---------

   procedure Run (CPU        : in out CPU_State;
                  Mem        : in out Memory.Memory_Unit;
                  Trace      : Boolean := False;
                  Trace_Cfg  : Trace_Config := (Enabled => False, others => <>);
                  Max_Cycles : Natural := Natural'Last) is
      Cycles : Natural := 0;
   begin
      while not CPU.Halted and Cycles < Max_Cycles loop
         --  Check for pending interrupts before each instruction
         declare
            Taken : Boolean;
         begin
            Taken := Check_Interrupts (CPU, Mem);
            pragma Unreferenced (Taken);
         end;
         Step (CPU, Mem, Trace, Trace_Cfg);
         Cycles := Cycles + 1;

         --  Update peripheral timers
         Memory.CLINT_Tick (Mem);
         Memory.Timer_Tick (Mem);

         --  Update watchdog and check for timeout
         if Memory.Watchdog_Tick (Mem) then
            --  Watchdog timeout! Reset the CPU
            Put_Line ("*** WATCHDOG TIMEOUT - System Reset ***");
            Initialize (CPU, CPU.Reset_Vector);  --  Reset CPU to entry point
            Cycles := 0;
         end if;

         --  Process DMA transfers (every 10 cycles for better performance)
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

   procedure Dump_State (CPU : CPU_State) is
      package Word_IO is new Ada.Text_IO.Modular_IO (Word);
      use Word_IO;
   begin
      Put_Line ("CPU State:");
      Put ("  PC = ");
      Put (CPU.PC, Width => 10, Base => 16);
      New_Line;

      Put_Line ("  Registers:");
      for I in Register_Index loop
         Put ("    x" & Register_Index'Image (I) & " = ");
         Put (CPU.Registers (I), Width => 10, Base => 16);
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

   procedure Trap_Entry (CPU   : in out CPU_State;
                         Cause : Word;
                         Tval  : Word := 0) is
      Is_Interrupt : constant Boolean := (Cause and 16#80000000#) /= 0;
      Cause_Code   : constant Word := Cause and 16#7FFFFFFF#;
      Delegate_To_S : Boolean := False;
   begin
      --  Check delegation: only delegate from U or S mode (never from M)
      if CPU.Priv_Mode /= Machine then
         if Is_Interrupt then
            Delegate_To_S :=
               (CSR.Read (CPU.CSRs, CSR.CSR_MIDELEG) and
                Shift_Left (1, Natural (Cause_Code))) /= 0;
         else
            Delegate_To_S :=
               (CSR.Read (CPU.CSRs, CSR.CSR_MEDELEG) and
                Shift_Left (1, Natural (Cause_Code))) /= 0;
         end if;
      end if;

      if Delegate_To_S then
         --  Trap to S-mode
         declare
            Stvec   : constant Word := CSR.Read (CPU.CSRs, CSR.CSR_STVEC);
            Mstatus : constant Word := CSR.Read (CPU.CSRs, CSR.CSR_MSTATUS);
            Mode    : constant Word := Stvec and 3;
            Base    : constant Word := Stvec and not 3;
            Target  : Word;
            New_Mstatus : Word := Mstatus;
         begin
            if Stvec = 0 then
               CPU.Halted := True;
               return;
            end if;

            CSR.Write (CPU.CSRs, CSR.CSR_SEPC, CPU.PC);
            CSR.Write (CPU.CSRs, CSR.CSR_SCAUSE, Cause);
            CSR.Write (CPU.CSRs, CSR.CSR_STVAL, Tval);

            --  SPIE = old SIE
            if (Mstatus and CSR.MSTATUS_SIE) /= 0 then
               New_Mstatus := New_Mstatus or CSR.MSTATUS_SPIE;
            else
               New_Mstatus := New_Mstatus and not CSR.MSTATUS_SPIE;
            end if;
            --  Clear SIE
            New_Mstatus := New_Mstatus and not CSR.MSTATUS_SIE;
            --  SPP = previous privilege (0=U, 1=S)
            if CPU.Priv_Mode = Supervisor then
               New_Mstatus := New_Mstatus or CSR.MSTATUS_SPP;
            else
               New_Mstatus := New_Mstatus and not CSR.MSTATUS_SPP;
            end if;
            CSR.Write (CPU.CSRs, CSR.CSR_MSTATUS, New_Mstatus);

            if Mode = 1 and then Is_Interrupt then
               Target := Base + Shift_Left (Cause_Code, 2);
            else
               Target := Base;
            end if;

            CPU.PC := Target;
            CPU.Priv_Mode := Supervisor;
            CPU.Exception_Code := No_Exception;
         end;
      else
         --  Trap to M-mode
         declare
            Mtvec   : constant Word := CSR.Read (CPU.CSRs, CSR.CSR_MTVEC);
            Mstatus : constant Word := CSR.Read (CPU.CSRs, CSR.CSR_MSTATUS);
            Mode    : constant Word := Mtvec and 3;
            Base    : constant Word := Mtvec and not 3;
            Target  : Word;
            New_Mstatus : Word := Mstatus;
            Priv_Bits   : Word;
         begin
            if Mtvec = 0 then
               CPU.Halted := True;
               return;
            end if;

            CSR.Write (CPU.CSRs, CSR.CSR_MEPC, CPU.PC);
            CSR.Write (CPU.CSRs, CSR.CSR_MCAUSE, Cause);
            CSR.Write (CPU.CSRs, CSR.CSR_MTVAL, Tval);

            --  MPIE = old MIE
            if (Mstatus and CSR.MSTATUS_MIE) /= 0 then
               New_Mstatus := New_Mstatus or CSR.MSTATUS_MPIE;
            else
               New_Mstatus := New_Mstatus and not CSR.MSTATUS_MPIE;
            end if;
            --  Clear MIE
            New_Mstatus := New_Mstatus and not CSR.MSTATUS_MIE;
            --  Set MPP = current privilege level
            New_Mstatus := New_Mstatus and not CSR.MSTATUS_MPP_MASK;
            Priv_Bits := Word (Privilege_Level'Pos (CPU.Priv_Mode));
            New_Mstatus := New_Mstatus or Shift_Left (Priv_Bits, 11);
            CSR.Write (CPU.CSRs, CSR.CSR_MSTATUS, New_Mstatus);

            if Mode = 1 and then Is_Interrupt then
               Target := Base + Shift_Left (Cause_Code, 2);
            else
               Target := Base;
            end if;

            CPU.PC := Target;
            CPU.Priv_Mode := Machine;
            CPU.Exception_Code := No_Exception;
         end;
      end if;
   end Trap_Entry;

   ----------
   -- Mret --
   ----------

   procedure Mret (CPU : in out CPU_State) is
      Mstatus : constant Word := CSR.Read (CPU.CSRs, CSR.CSR_MSTATUS);
      Mepc    : constant Word := CSR.Read (CPU.CSRs, CSR.CSR_MEPC);
      New_Mstatus : Word := Mstatus;
      MPP_Val : constant Word := Shift_Right (Mstatus and CSR.MSTATUS_MPP_MASK, 11);
   begin
      --  Restore MIE from MPIE
      if (Mstatus and CSR.MSTATUS_MPIE) /= 0 then
         New_Mstatus := New_Mstatus or CSR.MSTATUS_MIE;
      else
         New_Mstatus := New_Mstatus and not CSR.MSTATUS_MIE;
      end if;
      --  Set MPIE = 1
      New_Mstatus := New_Mstatus or CSR.MSTATUS_MPIE;
      --  Clear MPP to 0 (User)
      New_Mstatus := New_Mstatus and not CSR.MSTATUS_MPP_MASK;

      CSR.Write (CPU.CSRs, CSR.CSR_MSTATUS, New_Mstatus);

      --  Restore privilege from MPP
      case MPP_Val is
         when 0 => CPU.Priv_Mode := User;
         when 1 => CPU.Priv_Mode := Supervisor;
         when 3 => CPU.Priv_Mode := Machine;
         when others => CPU.Priv_Mode := User;
      end case;

      --  Jump back to saved PC. mepc[0] is always masked; with C disabled
      --  (IALIGN=32) mepc[1] is masked too.
      declare
         Target : Word := Mepc and 16#FFFFFFFE#;
      begin
         if not C_Ext_Enabled (CPU) then
            Target := Target and 16#FFFFFFFC#;
         end if;
         CPU.PC := Target;
      end;

      --  A trap return breaks any outstanding load reservation, so a later
      --  SC cannot succeed across a context switch that happened between
      --  the LR and the SC.
      CPU.Reservation_Valid := False;
   end Mret;

   ----------
   -- Sret --
   ----------

   procedure Sret (CPU : in out CPU_State) is
      Mstatus : constant Word := CSR.Read (CPU.CSRs, CSR.CSR_MSTATUS);
      Sepc    : constant Word := CSR.Read (CPU.CSRs, CSR.CSR_SEPC);
      New_Mstatus : Word := Mstatus;
   begin
      --  Restore SIE from SPIE
      if (Mstatus and CSR.MSTATUS_SPIE) /= 0 then
         New_Mstatus := New_Mstatus or CSR.MSTATUS_SIE;
      else
         New_Mstatus := New_Mstatus and not CSR.MSTATUS_SIE;
      end if;
      --  Set SPIE = 1
      New_Mstatus := New_Mstatus or CSR.MSTATUS_SPIE;
      --  Restore privilege from SPP (0=User, 1=Supervisor)
      if (Mstatus and CSR.MSTATUS_SPP) /= 0 then
         CPU.Priv_Mode := Supervisor;
      else
         CPU.Priv_Mode := User;
      end if;
      --  Clear SPP
      New_Mstatus := New_Mstatus and not CSR.MSTATUS_SPP;

      CSR.Write (CPU.CSRs, CSR.CSR_MSTATUS, New_Mstatus);

      --  Jump back to saved PC
      CPU.PC := Sepc;

      --  A trap return breaks any outstanding load reservation, so a later
      --  SC cannot succeed across a context switch that happened between
      --  the LR and the SC.
      CPU.Reservation_Valid := False;
   end Sret;

   ----------------------
   -- Check_Interrupts --
   ----------------------

   function Check_Interrupts (CPU : in out CPU_State;
                              Mem : Memory.Memory_Unit) return Boolean is
      Mstatus : constant Word := CSR.Read (CPU.CSRs, CSR.CSR_MSTATUS);
      Mie_Reg : constant Word := CSR.Read (CPU.CSRs, CSR.CSR_MIE);
      Mip_Reg : constant Word := CSR.Read (CPU.CSRs, CSR.CSR_MIP);
      M_Enabled : Boolean;
      S_Enabled : Boolean;
      Pending   : Word;

      Mideleg_Reg : constant Word := CSR.Read (CPU.CSRs, CSR.CSR_MIDELEG);

      --  Which enable applies to an interrupt depends on where it is
      --  delegated to, not on which level named the bit.  An S-level
      --  interrupt that mideleg does NOT delegate still targets M-mode, and
      --  must be taken there regardless of mstatus.SIE.
      function Enabled_For (Bit : Word) return Boolean is
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
                   or else (Mstatus and CSR.MSTATUS_MIE) /= 0;
      S_Enabled := CPU.Priv_Mode in User | Reserved
                   or else (CPU.Priv_Mode = Supervisor
                            and then (Mstatus and CSR.MSTATUS_SIE) /= 0);

      --  Update MIP from CLINT if available
      if Memory.CLINT_Enabled (Mem) then
         declare
            New_Mip : Word := Mip_Reg;
         begin
            if Memory.CLINT_Timer_Interrupt_Pending (Mem, CPU.Hart_ID) then
               New_Mip := New_Mip or CSR.MIE_MTIE;
            else
               New_Mip := New_Mip and not CSR.MIE_MTIE;
            end if;
            if Memory.CLINT_Software_Interrupt_Pending (Mem, CPU.Hart_ID) then
               New_Mip := New_Mip or CSR.MIE_MSIE;
            else
               New_Mip := New_Mip and not CSR.MIE_MSIE;
            end if;
            CSR.Write (CPU.CSRs, CSR.CSR_MIP, New_Mip);
         end;
      end if;

      --  Check for enabled & pending interrupts
      Pending := CSR.Read (CPU.CSRs, CSR.CSR_MIP) and Mie_Reg;

      if Pending = 0 then
         return False;
      end if;

      --  Priority: MEI > MSI > MTI > SEI > SSI > STI
      if (Pending and CSR.MIE_MEIE) /= 0
        and then Enabled_For (CSR.MIE_MEIE)
      then
         Trap_Entry (CPU, CSR.CAUSE_M_EXTERNAL_INT);
         return True;
      elsif (Pending and CSR.MIE_MSIE) /= 0
        and then Enabled_For (CSR.MIE_MSIE)
      then
         Trap_Entry (CPU, CSR.CAUSE_M_SOFTWARE_INT);
         return True;
      elsif (Pending and CSR.MIE_MTIE) /= 0
        and then Enabled_For (CSR.MIE_MTIE)
      then
         Trap_Entry (CPU, CSR.CAUSE_M_TIMER_INT);
         return True;
      elsif (Pending and CSR.MIE_SEIE) /= 0
        and then Enabled_For (CSR.MIE_SEIE)
      then
         Trap_Entry (CPU, CSR.CAUSE_S_EXTERNAL_INT);
         return True;
      elsif (Pending and CSR.MIE_SSIE) /= 0
        and then Enabled_For (CSR.MIE_SSIE)
      then
         Trap_Entry (CPU, CSR.CAUSE_S_SOFTWARE_INT);
         return True;
      elsif (Pending and CSR.MIE_STIE) /= 0
        and then Enabled_For (CSR.MIE_STIE)
      then
         Trap_Entry (CPU, CSR.CAUSE_S_TIMER_INT);
         return True;
      end if;

      return False;
   end Check_Interrupts;

   ----------------------
   -- Add_Cycle_Stalls --
   ----------------------

   procedure Add_Cycle_Stalls (CPU   : in out CPU_State;
                                Count : Natural) is
   begin
      --  CY bit (bit 0) of Mcountinhibit: if set, mcycle is frozen
      if (CPU.CSRs.Mcountinhibit and 1) = 0 then
         CPU.CSRs.Mcycle := CPU.CSRs.Mcycle + Unsigned_64 (Count);
      end if;
   end Add_Cycle_Stalls;

end RISCV.CPU;
