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

-- Implements Zbkb, Zbkc, Zbkx, Zkne, Zknd, Zknh, Zksed, Zksh
package RISCV.Crypto is

   --  Zbkb: Bit manipulation for crypto
   function ANDN (Rs1, Rs2 : Word) return Word;
   function ORN (Rs1, Rs2 : Word) return Word;
   function XNOR_Op (Rs1, Rs2 : Word) return Word;
   function ROL (Rs1, Rs2 : Word) return Word;
   function ROR_Op (Rs1, Rs2 : Word) return Word;
   function RORI (Rs1 : Word; Shamt : Natural) return Word;
   function PACK (Rs1, Rs2 : Word) return Word;
   function PACKH (Rs1, Rs2 : Word) return Word;
   function REV8 (Rs1 : Word) return Word;
   function ZIP (Rs1 : Word) return Word;
   function UNZIP (Rs1 : Word) return Word;
   function BREV8 (Rs1 : Word) return Word;

   --  Zbkc: Carry-less multiplication
   function CLMUL (Rs1, Rs2 : Word) return Word;
   function CLMULH (Rs1, Rs2 : Word) return Word;

   --  Zbkx: Crossbar permutation
   function XPERM4 (Rs1, Rs2 : Word) return Word;
   function XPERM8 (Rs1, Rs2 : Word) return Word;

   --  Zkne: AES encryption
   function AES32ESI (Rs1, Rs2 : Word; BS : Natural) return Word;
   function AES32ESMI (Rs1, Rs2 : Word; BS : Natural) return Word;

   --  Zknd: AES decryption
   function AES32DSI (Rs1, Rs2 : Word; BS : Natural) return Word;
   function AES32DSMI (Rs1, Rs2 : Word; BS : Natural) return Word;

   --  Zknh: SHA-256
   function SHA256SIG0 (Rs1 : Word) return Word;
   function SHA256SIG1 (Rs1 : Word) return Word;
   function SHA256SUM0 (Rs1 : Word) return Word;
   function SHA256SUM1 (Rs1 : Word) return Word;

   --  Zknh: SHA-512 (RV32 paired)
   function SHA512SIG0H (Rs1, Rs2 : Word) return Word;
   function SHA512SIG0L (Rs1, Rs2 : Word) return Word;
   function SHA512SIG1H (Rs1, Rs2 : Word) return Word;
   function SHA512SIG1L (Rs1, Rs2 : Word) return Word;
   function SHA512SUM0R (Rs1, Rs2 : Word) return Word;
   function SHA512SUM1R (Rs1, Rs2 : Word) return Word;

   --  Zksed: SM4
   function SM4ED (Rs1, Rs2 : Word; BS : Natural) return Word;
   function SM4KS (Rs1, Rs2 : Word; BS : Natural) return Word;

   --  Zksh: SM3
   function SM3P0 (Rs1 : Word) return Word;
   function SM3P1 (Rs1 : Word) return Word;

   --  Zbb: basic bit manipulation (scalar)
   function CLZ    (Rs1 : Word) return Word;
   function CTZ    (Rs1 : Word) return Word;
   function CPOP   (Rs1 : Word) return Word;
   function SEXT_B (Rs1 : Word) return Word;
   function SEXT_H (Rs1 : Word) return Word;
   function ORC_B  (Rs1 : Word) return Word;
   function ZBB_MIN  (Rs1, Rs2 : Word) return Word;
   function ZBB_MAX  (Rs1, Rs2 : Word) return Word;
   function ZBB_MINU (Rs1, Rs2 : Word) return Word;
   function ZBB_MAXU (Rs1, Rs2 : Word) return Word;

   --  Zbs: single-bit manipulation
   function BSET (Rs1, Rs2 : Word) return Word;
   function BCLR (Rs1, Rs2 : Word) return Word;
   function BINV (Rs1, Rs2 : Word) return Word;
   function BEXT (Rs1, Rs2 : Word) return Word;

   --  Zbb: 64-bit variants (RV64 only)
   function CLZ64    (Rs1 : Double_Word) return Double_Word;
   function CTZ64    (Rs1 : Double_Word) return Double_Word;
   function CPOP64   (Rs1 : Double_Word) return Double_Word;
   function CLZW     (Rs1 : Double_Word) return Double_Word;
   function CTZW     (Rs1 : Double_Word) return Double_Word;
   function CPOPW    (Rs1 : Double_Word) return Double_Word;
   function REV8_64  (Rs1 : Double_Word) return Double_Word;
   function SEXT_B64 (Rs1 : Double_Word) return Double_Word;
   function SEXT_H64 (Rs1 : Double_Word) return Double_Word;
   function ZEXT_H64 (Rs1 : Double_Word) return Double_Word;
   function ROLW     (Rs1, Rs2 : Double_Word) return Double_Word;
   function RORW     (Rs1, Rs2 : Double_Word) return Double_Word;

   --  Zbb: 64-bit register-register logical / rotate / min-max (RV64 only)
   function ANDN64    (Rs1, Rs2 : Double_Word) return Double_Word;
   function ORN64     (Rs1, Rs2 : Double_Word) return Double_Word;
   function XNOR64    (Rs1, Rs2 : Double_Word) return Double_Word;
   function ROL64     (Rs1, Rs2 : Double_Word) return Double_Word;
   function ROR64     (Rs1, Rs2 : Double_Word) return Double_Word;
   function RORI64    (Rs1 : Double_Word; Shamt : Natural) return Double_Word;
   function ORC_B64   (Rs1 : Double_Word) return Double_Word;
   function ZBB_MIN64  (Rs1, Rs2 : Double_Word) return Double_Word;
   function ZBB_MAX64  (Rs1, Rs2 : Double_Word) return Double_Word;
   function ZBB_MINU64 (Rs1, Rs2 : Double_Word) return Double_Word;
   function ZBB_MAXU64 (Rs1, Rs2 : Double_Word) return Double_Word;

end RISCV.Crypto;
