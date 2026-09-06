# Instruction Set Architecture

The emulator supports **RV32IMFDV** - the 32-bit RISC-V base ISA with standard extensions.

## RV32I - Base Integer ISA (40 instructions)

### Arithmetic

| Instruction | Format | Description |
|-------------|--------|-------------|
| `ADD rd, rs1, rs2` | R | rd = rs1 + rs2 |
| `SUB rd, rs1, rs2` | R | rd = rs1 - rs2 |
| `ADDI rd, rs1, imm` | I | rd = rs1 + imm (sign-extended) |
| `SLT rd, rs1, rs2` | R | rd = (rs1 < rs2) ? 1 : 0 (signed) |
| `SLTU rd, rs1, rs2` | R | rd = (rs1 < rs2) ? 1 : 0 (unsigned) |
| `SLTI rd, rs1, imm` | I | rd = (rs1 < imm) ? 1 : 0 (signed) |
| `SLTIU rd, rs1, imm` | I | rd = (rs1 < imm) ? 1 : 0 (unsigned) |

### Logical

| Instruction | Format | Description |
|-------------|--------|-------------|
| `AND rd, rs1, rs2` | R | rd = rs1 & rs2 |
| `OR rd, rs1, rs2` | R | rd = rs1 \| rs2 |
| `XOR rd, rs1, rs2` | R | rd = rs1 ^ rs2 |
| `ANDI rd, rs1, imm` | I | rd = rs1 & imm |
| `ORI rd, rs1, imm` | I | rd = rs1 \| imm |
| `XORI rd, rs1, imm` | I | rd = rs1 ^ imm |

### Shifts

| Instruction | Format | Description |
|-------------|--------|-------------|
| `SLL rd, rs1, rs2` | R | rd = rs1 << rs2[4:0] |
| `SRL rd, rs1, rs2` | R | rd = rs1 >> rs2[4:0] (logical) |
| `SRA rd, rs1, rs2` | R | rd = rs1 >> rs2[4:0] (arithmetic) |
| `SLLI rd, rs1, shamt` | I | rd = rs1 << shamt |
| `SRLI rd, rs1, shamt` | I | rd = rs1 >> shamt (logical) |
| `SRAI rd, rs1, shamt` | I | rd = rs1 >> shamt (arithmetic) |

### Loads

| Instruction | Format | Description |
|-------------|--------|-------------|
| `LB rd, offset(rs1)` | I | rd = sign_extend(mem[rs1+offset][7:0]) |
| `LH rd, offset(rs1)` | I | rd = sign_extend(mem[rs1+offset][15:0]) |
| `LW rd, offset(rs1)` | I | rd = mem[rs1+offset][31:0] |
| `LBU rd, offset(rs1)` | I | rd = zero_extend(mem[rs1+offset][7:0]) |
| `LHU rd, offset(rs1)` | I | rd = zero_extend(mem[rs1+offset][15:0]) |

### Stores

| Instruction | Format | Description |
|-------------|--------|-------------|
| `SB rs2, offset(rs1)` | S | mem[rs1+offset][7:0] = rs2[7:0] |
| `SH rs2, offset(rs1)` | S | mem[rs1+offset][15:0] = rs2[15:0] |
| `SW rs2, offset(rs1)` | S | mem[rs1+offset][31:0] = rs2 |

### Branches

| Instruction | Format | Description |
|-------------|--------|-------------|
| `BEQ rs1, rs2, offset` | B | if (rs1 == rs2) PC += offset |
| `BNE rs1, rs2, offset` | B | if (rs1 != rs2) PC += offset |
| `BLT rs1, rs2, offset` | B | if (rs1 < rs2) PC += offset (signed) |
| `BGE rs1, rs2, offset` | B | if (rs1 >= rs2) PC += offset (signed) |
| `BLTU rs1, rs2, offset` | B | if (rs1 < rs2) PC += offset (unsigned) |
| `BGEU rs1, rs2, offset` | B | if (rs1 >= rs2) PC += offset (unsigned) |

### Jumps

| Instruction | Format | Description |
|-------------|--------|-------------|
| `JAL rd, offset` | J | rd = PC+4; PC += offset |
| `JALR rd, rs1, offset` | I | rd = PC+4; PC = (rs1+offset) & ~1 |

### Upper Immediate

| Instruction | Format | Description |
|-------------|--------|-------------|
| `LUI rd, imm` | U | rd = imm << 12 |
| `AUIPC rd, imm` | U | rd = PC + (imm << 12) |

### System

| Instruction | Format | Description |
|-------------|--------|-------------|
| `ECALL` | I | Environment call (syscall) |
| `EBREAK` | I | Breakpoint |

---

## M Extension - Integer Multiply/Divide (8 instructions)

| Instruction | Format | Description |
|-------------|--------|-------------|
| `MUL rd, rs1, rs2` | R | rd = (rs1 * rs2)[31:0] |
| `MULH rd, rs1, rs2` | R | rd = (rs1 * rs2)[63:32] (signed*signed) |
| `MULHSU rd, rs1, rs2` | R | rd = (rs1 * rs2)[63:32] (signed*unsigned) |
| `MULHU rd, rs1, rs2` | R | rd = (rs1 * rs2)[63:32] (unsigned*unsigned) |
| `DIV rd, rs1, rs2` | R | rd = rs1 / rs2 (signed) |
| `DIVU rd, rs1, rs2` | R | rd = rs1 / rs2 (unsigned) |
| `REM rd, rs1, rs2` | R | rd = rs1 % rs2 (signed) |
| `REMU rd, rs1, rs2` | R | rd = rs1 % rs2 (unsigned) |

**Note:** Division by zero returns -1 (DIV) or UINT_MAX (DIVU).

---

## F Extension - Single-Precision Floating-Point

### Arithmetic

| Instruction | Description |
|-------------|-------------|
| `FADD.S rd, rs1, rs2` | rd = rs1 + rs2 |
| `FSUB.S rd, rs1, rs2` | rd = rs1 - rs2 |
| `FMUL.S rd, rs1, rs2` | rd = rs1 * rs2 |
| `FDIV.S rd, rs1, rs2` | rd = rs1 / rs2 |
| `FSQRT.S rd, rs1` | rd = sqrt(rs1) |
| `FMIN.S rd, rs1, rs2` | rd = min(rs1, rs2) |
| `FMAX.S rd, rs1, rs2` | rd = max(rs1, rs2) |

### Sign Manipulation

| Instruction | Description |
|-------------|-------------|
| `FSGNJ.S rd, rs1, rs2` | rd = rs1 with sign of rs2 |
| `FSGNJN.S rd, rs1, rs2` | rd = rs1 with negated sign of rs2 |
| `FSGNJX.S rd, rs1, rs2` | rd = rs1 with sign = rs1.sign XOR rs2.sign |

### Comparisons

| Instruction | Description |
|-------------|-------------|
| `FEQ.S rd, rs1, rs2` | rd = (rs1 == rs2) ? 1 : 0 |
| `FLT.S rd, rs1, rs2` | rd = (rs1 < rs2) ? 1 : 0 |
| `FLE.S rd, rs1, rs2` | rd = (rs1 <= rs2) ? 1 : 0 |

### Conversions

| Instruction | Description |
|-------------|-------------|
| `FCVT.W.S rd, rs1` | rd = int32(rs1) |
| `FCVT.WU.S rd, rs1` | rd = uint32(rs1) |
| `FCVT.S.W rd, rs1` | rd = float(int32(rs1)) |
| `FCVT.S.WU rd, rs1` | rd = float(uint32(rs1)) |

### Classification

| Instruction | Description |
|-------------|-------------|
| `FCLASS.S rd, rs1` | rd = classification bits |

Classification bits: NegInf, NegNorm, NegSubnorm, NegZero, PosZero, PosSubnorm, PosNorm, PosInf, SNaN, QNaN

### Move (bit-level)

| Instruction | Description |
|-------------|-------------|
| `FMV.X.W rd, rs1` | rd = bitcast(rs1) (FP to int) |
| `FMV.W.X rd, rs1` | rd = bitcast(rs1) (int to FP) |

### Load/Store

| Instruction | Description |
|-------------|-------------|
| `FLW rd, offset(rs1)` | rd = mem[rs1+offset] (32-bit) |
| `FSW rs2, offset(rs1)` | mem[rs1+offset] = rs2 (32-bit) |

---

## D Extension - Double-Precision Floating-Point

Same operations as F extension with `.D` suffix:
- `FADD.D`, `FSUB.D`, `FMUL.D`, `FDIV.D`, `FSQRT.D`
- `FMIN.D`, `FMAX.D`
- `FCVT.W.D`, `FCVT.WU.D`, `FCVT.D.W`, `FCVT.D.WU`
- `FCVT.S.D`, `FCVT.D.S` (single<->double conversion)
- `FLD`, `FSD` (64-bit load/store)
- `FCLASS.D`, comparisons, sign manipulation

**NaN Boxing:** Single-precision values in 64-bit registers are NaN-boxed (upper 32 bits = 0xFFFFFFFF).

---

## V Extension - Vector (RVV 1.0)

### Configuration

| Instruction | Description |
|-------------|-------------|
| `vsetvli rd, rs1, vtypei` | Set VL and VTYPE from immediate |
| `vsetivli rd, uimm, vtypei` | Set VL from immediate |
| `vsetvl rd, rs1, rs2` | Set VL and VTYPE from registers |

**VTYPE fields:** vsew (element width), vlmul (grouping), vta, vma

### Load/Store (Unit-Stride)

| Instruction | Description |
|-------------|-------------|
| `vle8.v vd, (rs1)` | Load bytes |
| `vle16.v vd, (rs1)` | Load halfwords |
| `vle32.v vd, (rs1)` | Load words |
| `vle64.v vd, (rs1)` | Load doublewords |
| `vse8.v vs3, (rs1)` | Store bytes |
| `vse16.v vs3, (rs1)` | Store halfwords |
| `vse32.v vs3, (rs1)` | Store words |
| `vse64.v vs3, (rs1)` | Store doublewords |

### Integer Arithmetic

| Instruction | Variants | Description |
|-------------|----------|-------------|
| `vadd` | .vv, .vx, .vi | Vector add |
| `vsub` | .vv, .vx | Vector subtract |
| `vrsub` | .vx, .vi | Reverse subtract |
| `vmul` | .vv, .vx | Multiply |
| `vmulh` | .vv, .vx | Multiply high (signed) |
| `vmulhu` | .vv, .vx | Multiply high (unsigned) |
| `vmulhsu` | .vv, .vx | Multiply high (signed*unsigned) |
| `vdiv` | .vv, .vx | Divide (signed) |
| `vdivu` | .vv, .vx | Divide (unsigned) |
| `vrem` | .vv, .vx | Remainder (signed) |
| `vremu` | .vv, .vx | Remainder (unsigned) |

### Logical

| Instruction | Variants | Description |
|-------------|----------|-------------|
| `vand` | .vv, .vx, .vi | AND |
| `vor` | .vv, .vx, .vi | OR |
| `vxor` | .vv, .vx, .vi | XOR |

### Shifts

| Instruction | Variants | Description |
|-------------|----------|-------------|
| `vsll` | .vv, .vx, .vi | Shift left logical |
| `vsrl` | .vv, .vx, .vi | Shift right logical |
| `vsra` | .vv, .vx, .vi | Shift right arithmetic |

### Min/Max

| Instruction | Description |
|-------------|-------------|
| `vminu.vv/vx` | Unsigned minimum |
| `vmin.vv/vx` | Signed minimum |
| `vmaxu.vv/vx` | Unsigned maximum |
| `vmax.vv/vx` | Signed maximum |

### Comparisons (produce mask)

| Instruction | Description |
|-------------|-------------|
| `vmseq.vv/vx/vi` | Set mask if equal |
| `vmsne.vv/vx/vi` | Set mask if not equal |
| `vmslt.vv/vx` | Set mask if less than (signed) |
| `vmsltu.vv/vx` | Set mask if less than (unsigned) |
| `vmsle.vv/vx/vi` | Set mask if less or equal (signed) |
| `vmsleu.vv/vx/vi` | Set mask if less or equal (unsigned) |
| `vmsgt.vx/vi` | Set mask if greater than (signed) |
| `vmsgtu.vx/vi` | Set mask if greater than (unsigned) |

### Reductions

| Instruction | Description |
|-------------|-------------|
| `vredsum.vs` | Sum reduction |
| `vredand.vs` | AND reduction |
| `vredor.vs` | OR reduction |
| `vredxor.vs` | XOR reduction |
| `vredmin.vs` | Min reduction (signed) |
| `vredminu.vs` | Min reduction (unsigned) |
| `vredmax.vs` | Max reduction (signed) |
| `vredmaxu.vs` | Max reduction (unsigned) |

### Mask Operations

| Instruction | Description |
|-------------|-------------|
| `vmand.mm` | Mask AND |
| `vmnand.mm` | Mask NAND |
| `vmor.mm` | Mask OR |
| `vmnor.mm` | Mask NOR |
| `vmxor.mm` | Mask XOR |
| `vmxnor.mm` | Mask XNOR |
| `vcpop.m` | Count population (mask) |
| `vfirst.m` | Find first set bit |
| `vmsbf.m` | Set before first |
| `vmsof.m` | Set only first |
| `vmsif.m` | Set including first |
| `viota.m` | Iota (prefix count) |
| `vid.v` | Vector ID (element index) |

### Permutation

| Instruction | Description |
|-------------|-------------|
| `vmv.v.v` | Vector move |
| `vmv.v.x` | Scalar to vector |
| `vmv.v.i` | Immediate to vector |
| `vmv.x.s` | Vector element to scalar |
| `vmv.s.x` | Scalar to vector element |
| `vmerge.vvm/vxm/vim` | Conditional merge |

---

## A Extension - Atomics

LR.W/SC.W, AMOSWAP.W, AMOADD.W, AMOAND.W, AMOOR.W, AMOXOR.W, AMOMIN.W, AMOMAX.W, AMOMINU.W, AMOMAXU.W.
64-bit variants (LR.D/SC.D + AMO.D) available in RV64 mode.

---

## C Extension - Compressed 16-bit Instructions

Full RVC 1.0: ~40 compressed instructions (CR/CI/CSS/CIW/CL/CS/CB/CJ formats).
RV64C overrides: C.ADDIW, C.LD/SD, C.LDSP/SDSP.

---

## Zicsr - CSR Instructions

CSRRW, CSRRS, CSRRC, CSRRWI, CSRRSI, CSRRCI.

---

## Zbb / Zbs / Zba - Bit-Manipulation

- **Zbb**: CLZ, CTZ, CPOP, SEXT.B/H, ORC.B, REV8, MIN/MAX/MINU/MAXU, ROL, ROR, RORI, ANDN, ORN, XNOR
- **Zbs**: BSET, BCLR, BINV, BEXT (and immediate variants)
- **Zba**: SH1ADD, SH2ADD, SH3ADD; RV64: ADD.UW, SH1ADD.UW, SH2ADD.UW, SH3ADD.UW

---

## Zbkc / Zbkx - Crypto Bit-Manipulation

- **Zbkc**: CLMUL, CLMULH, CLMULR
- **Zbkx**: XPERM4, XPERM8

---

## Zicond - Conditional Zero

- `czero.eqz rd, rs1, rs2` - rd = (rs2 == 0) ? 0 : rs1
- `czero.nez rd, rs1, rs2` - rd = (rs2 != 0) ? 0 : rs1
- cmov pattern: `czero_eqz(a, cond) | czero_nez(b, cond)` selects a if cond!=0, else b

---

## Zfh - Half-Precision Float (fp16)

- Arithmetic: FADD.H, FSUB.H, FMUL.H, FDIV.H, FSQRT.H
- FMA: FMADD.H, FMSUB.H, FNMADD.H, FNMSUB.H
- Convert: FCVT.S.H, FCVT.H.S, FCVT.D.H, FCVT.H.D
- Compare/classify: FEQ.H, FLT.H, FLE.H, FCLASS.H
- Move: FMV.X.H, FMV.H.X, FMIN.H, FMAX.H
- Load/store: FLH (funct3=1), FSH (funct3=1)
- NaN-boxing: fp16 values are NaN-boxed in the upper 48 bits of the 64-bit FP register
- Build flag: `-march=rv32imafdc_zfh -mabi=ilp32f`

---

## RV32E - Embedded 16-Register Subset

- Enabled via `--rv32e` CLI flag
- MISA.E (bit 4) set; MISA.I (bit 8) and MISA.V (bit 21) cleared; MXL=1
- Register file limited to x0-x15; accesses to x16-x31 in OP/OP-IMM/LOAD/STORE/BRANCH/JALR opcodes raise an illegal instruction exception
- `Rv32e : Boolean` field in `CPU_State`

---

## RV64IMAFD - 64-bit ISA

Auto-detected from ELF class byte (ELF64 -> RV64 mode). Uses separate `RISCV.CPU64` package.

- 64-bit ALU: all RV32I ops sign-extended to 64 bits
- New: LD, SD, LWU; ADDIW, ADDW, SUBW, SLLW, SRLW, SRAW (and immediate variants)
- 64-bit FPU: FCVT.L.D, FCVT.LU.D, FCVT.D.L, FCVT.D.LU, FMV.X.D, FMV.D.X
- 64-bit atomics: LR.D, SC.D, all AMO.D variants
- MCAUSE interrupt bit at bit 63
- Sv39 MMU: 3-level page table, 64-entry TLB, 1GB/2MB/4KB superpages, page faults

---

## Privileged ISA

- **M-mode**: mstatus, mtvec, mepc, mcause, mscratch, mideleg, medeleg, mhartid, MRET
- **S-mode**: sstatus, stvec, sepc, scause, sscratch, sip, sie, satp, SRET, SBI shim
- **U-mode**: ecall from U-mode delegates to S-mode trap handler
- **CSR extensions**: mcountinhibit (0x320), mcounteren (0x306), scounteren (0x106), HPM stubs (0xB03-0xB1F)
- **Multi-hart**: `--harts N`; mhartid CSR returns hart index; each hart has independent register file and CSR state
