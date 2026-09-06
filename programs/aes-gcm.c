/* **************************************************************************
 * RISC-V Emulator - AES-128-GCM authenticated encryption (NIST SP 800-38D)
 *
 *           Copyright (C) 2026 By Ulrik Hørlyk Hjort
 *
 * Permission is hereby granted, free of charge, to any person obtaining
 * a copy of this software and associated documentation files (the
 * "Software"), to deal in the Software without restriction, including
 * without limitation the rights to use, copy, modify, merge, publish,
 * distribute, sublicense, and/or sell copies of the Software, and to
 * permit persons to whom the Software is furnished to do so, subject to
 * the following conditions:
 *
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 * NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
 * LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
 * OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
 * WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 * **************************************************************************/

// aes-gcm.c -- AES-128-GCM authenticated encryption (NIST SP 800-38D)
//
// GHASH operates in GF(2^128) with irreducible polynomial:
//   f(x) = 1 + x + x^2 + x^7 + x^128
// GCM uses 96-bit nonces (12 bytes). Counter starts at 2 for data encryption
// (counter 1 is used to encrypt the authentication tag).
//
// Test vectors: NIST SP 800-38D Appendix B
//   Test Case 1: empty PT/AAD -> tag only
//   Test Case 2: 16-byte PT, empty AAD
//   Test Case 3: 60-byte PT, empty AAD (non-trivial GHASH)
//   Test Case 4: 60-byte PT, 20-byte AAD (full AEAD)
//   Tamper detection, decrypt round-trip
//
// Build: cd programs && make run-aes-gcm
// By Ulrik Hørlyk Hjort 2026

#include <stdint.h>
#include "log.h"

void putchar(char c);

static int g_pass = 0, g_fail = 0;

static void chk(const char *label, int ok) {
    if (ok) { log_write(NONE, "  PASS  %s\n", label); g_pass++; }
    else     { log_write(NONE, "  FAIL  %s\n", label); g_fail++; }
}
static void chk_bytes(const char *label, const uint8_t *got, const uint8_t *exp, int n) {
    int ok = 1;
    for (int i=0;i<n;i++) if (got[i]!=exp[i]) { ok=0; break; }
    if (ok) { log_write(NONE, "  PASS  %s\n", label); g_pass++; }
    else {
        log_write(NONE, "  FAIL  %s\n", label);
        log_write(NONE, "    got:"); for(int i=0;i<n&&i<16;i++) log_write(NONE," %x",got[i]);
        if(n>16) log_write(NONE,"...");
        log_write(NONE, "\n    exp:"); for(int i=0;i<n&&i<16;i++) log_write(NONE," %x",exp[i]);
        if(n>16) log_write(NONE,"...");
        log_write(NONE, "\n");
        g_fail++;
    }
}

/* -- AES-128 --------------------------------------------------------------- */

static const uint8_t SBOX[256] = {
    0x63,0x7c,0x77,0x7b,0xf2,0x6b,0x6f,0xc5,0x30,0x01,0x67,0x2b,0xfe,0xd7,0xab,0x76,
    0xca,0x82,0xc9,0x7d,0xfa,0x59,0x47,0xf0,0xad,0xd4,0xa2,0xaf,0x9c,0xa4,0x72,0xc0,
    0xb7,0xfd,0x93,0x26,0x36,0x3f,0xf7,0xcc,0x34,0xa5,0xe5,0xf1,0x71,0xd8,0x31,0x15,
    0x04,0xc7,0x23,0xc3,0x18,0x96,0x05,0x9a,0x07,0x12,0x80,0xe2,0xeb,0x27,0xb2,0x75,
    0x09,0x83,0x2c,0x1a,0x1b,0x6e,0x5a,0xa0,0x52,0x3b,0xd6,0xb3,0x29,0xe3,0x2f,0x84,
    0x53,0xd1,0x00,0xed,0x20,0xfc,0xb1,0x5b,0x6a,0xcb,0xbe,0x39,0x4a,0x4c,0x58,0xcf,
    0xd0,0xef,0xaa,0xfb,0x43,0x4d,0x33,0x85,0x45,0xf9,0x02,0x7f,0x50,0x3c,0x9f,0xa8,
    0x51,0xa3,0x40,0x8f,0x92,0x9d,0x38,0xf5,0xbc,0xb6,0xda,0x21,0x10,0xff,0xf3,0xd2,
    0xcd,0x0c,0x13,0xec,0x5f,0x97,0x44,0x17,0xc4,0xa7,0x7e,0x3d,0x64,0x5d,0x19,0x73,
    0x60,0x81,0x4f,0xdc,0x22,0x2a,0x90,0x88,0x46,0xee,0xb8,0x14,0xde,0x5e,0x0b,0xdb,
    0xe0,0x32,0x3a,0x0a,0x49,0x06,0x24,0x5c,0xc2,0xd3,0xac,0x62,0x91,0x95,0xe4,0x79,
    0xe7,0xc8,0x37,0x6d,0x8d,0xd5,0x4e,0xa9,0x6c,0x56,0xf4,0xea,0x65,0x7a,0xae,0x08,
    0xba,0x78,0x25,0x2e,0x1c,0xa6,0xb4,0xc6,0xe8,0xdd,0x74,0x1f,0x4b,0xbd,0x8b,0x8a,
    0x70,0x3e,0xb5,0x66,0x48,0x03,0xf6,0x0e,0x61,0x35,0x57,0xb9,0x86,0xc1,0x1d,0x9e,
    0xe1,0xf8,0x98,0x11,0x69,0xd9,0x8e,0x94,0x9b,0x1e,0x87,0xe9,0xce,0x55,0x28,0xdf,
    0x8c,0xa1,0x89,0x0d,0xbf,0xe6,0x42,0x68,0x41,0x99,0x2d,0x0f,0xb0,0x54,0xbb,0x16,
};
static const uint8_t RCON[10] = {0x01,0x02,0x04,0x08,0x10,0x20,0x40,0x80,0x1b,0x36};

static uint8_t xtime(uint8_t x) { return (x<<1)^((x&0x80)?0x1b:0); }
static uint8_t gmul(uint8_t a, uint8_t b) {
    uint8_t r=0;
    while (b) { if(b&1) r^=a; a=xtime(a); b>>=1; }
    return r;
}

static void key_expand(const uint8_t key[16], uint8_t w[176]) {
    for (int i=0;i<16;i++) w[i]=key[i];
    for (int i=16;i<176;i+=4) {
        uint8_t t[4] = {w[i-4],w[i-3],w[i-2],w[i-1]};
        if (i%16==0) {
            uint8_t tmp=t[0];
            t[0]=SBOX[t[1]]^RCON[i/16-1];
            t[1]=SBOX[t[2]]; t[2]=SBOX[t[3]]; t[3]=SBOX[tmp];
        }
        w[i+0]=w[i-16]^t[0]; w[i+1]=w[i-15]^t[1];
        w[i+2]=w[i-14]^t[2]; w[i+3]=w[i-13]^t[3];
    }
}

static void aes128_encrypt(uint8_t blk[16], const uint8_t key[16]) {
    uint8_t w[176], s[16];
    key_expand(key, w);
    for (int i=0;i<16;i++) s[i]=blk[i];

    // AddRoundKey round 0
    for (int i=0;i<16;i++) s[i]^=w[i];

    for (int r=1;r<=9;r++) {
        // SubBytes
        for (int i=0;i<16;i++) s[i]=SBOX[s[i]];
        // ShiftRows (column-major: s[col*4+row])
        uint8_t t;
        t=s[1];s[1]=s[5];s[5]=s[9];s[9]=s[13];s[13]=t;
        t=s[2];s[2]=s[10];s[10]=t; t=s[6];s[6]=s[14];s[14]=t;
        t=s[3];s[3]=s[15];s[15]=s[11];s[11]=s[7];s[7]=t;
        // MixColumns
        for (int c=0;c<4;c++) {
            uint8_t *col=s+c*4;
            uint8_t a=col[0],b=col[1],cc=col[2],d=col[3];
            col[0]=gmul(2,a)^gmul(3,b)^cc^d;
            col[1]=a^gmul(2,b)^gmul(3,cc)^d;
            col[2]=a^b^gmul(2,cc)^gmul(3,d);
            col[3]=gmul(3,a)^b^cc^gmul(2,d);
        }
        // AddRoundKey
        for (int i=0;i<16;i++) s[i]^=w[r*16+i];
    }
    // Final round
    for (int i=0;i<16;i++) s[i]=SBOX[s[i]];
    uint8_t t;
    t=s[1];s[1]=s[5];s[5]=s[9];s[9]=s[13];s[13]=t;
    t=s[2];s[2]=s[10];s[10]=t; t=s[6];s[6]=s[14];s[14]=t;
    t=s[3];s[3]=s[15];s[15]=s[11];s[11]=s[7];s[7]=t;
    for (int i=0;i<16;i++) s[i]^=w[160+i];

    for (int i=0;i<16;i++) blk[i]=s[i];
}

/* -- GF(2^128) multiply (GCM bit ordering) -------------------------------- */
// NIST SP 800-38D Sec.6.3 Algorithm 1 (right-shift GHASH multiplication)
// Irreducible poly: f(x) = 1 + x + x^2 + x^7 + x^128
// GCM bit order: MSB of byte 0 = bit 0 of GF element = coefficient of x^0

static void gf128_mul(const uint8_t X[16], const uint8_t Y[16], uint8_t Z[16]) {
    uint8_t V[16];
    for (int i=0;i<16;i++) { Z[i]=0; V[i]=X[i]; }

    for (int i=0;i<128;i++) {
        // y_i: bit i from the left in Y (bit 0 = MSB of byte 0)
        if (Y[i>>3] & (0x80u >> (i&7))) {
            for (int k=0;k<16;k++) Z[k]^=V[k];
        }
        int lsb = V[15] & 1; // bit 127 = LSB of byte 15
        // Right-shift V by 1 (shift window right: bit 0 becomes 0)
        for (int k=15;k>0;k--)
            V[k] = (uint8_t)((V[k]>>1) | ((V[k-1]&1)<<7));
        V[0] >>= 1;
        if (lsb) V[0] ^= 0xe1u; // R = 11100001 || 0^120
    }
}

/* -- GHASH ----------------------------------------------------------------- */
// Process a sequence of 16-byte blocks, accumulating in Y.

static void ghash_update(const uint8_t H[16], uint8_t Y[16],
                          const uint8_t *data, int len) {
    static const uint8_t zero[16] = {0};
    uint8_t tmp[16];
    // Complete blocks
    for (int pos=0; pos+16<=len; pos+=16) {
        for (int k=0;k<16;k++) tmp[k] = Y[k]^data[pos+k];
        gf128_mul(tmp, H, Y);
    }
    // Partial final block (zero-padded)
    int rem = len % 16;
    if (rem) {
        for (int k=0;k<16;k++) tmp[k] = Y[k]^(k<rem ? data[len-rem+k] : 0);
        gf128_mul(tmp, H, Y);
    }
    (void)zero;
}

/* -- AES-GCM seal/open ----------------------------------------------------- */

// Increment the 32-bit counter (big-endian) in the last 4 bytes of a 16-byte block
static void inc32(uint8_t ctr[16]) {
    for (int i=15;i>=12;i--) {
        if (++ctr[i]) break;
    }
}

static void store_be64(uint8_t *p, uint64_t v) {
    for (int i=7;i>=0;i--) { p[i]=(uint8_t)v; v>>=8; }
}

// Encrypt plaintext to ciphertext using AES-CTR starting at counter block J1
// J0 is the base counter (J1 = inc32(J0))
static void gctr(const uint8_t key[16], const uint8_t J0[16],
                 const uint8_t *pt, uint8_t *ct, int len)
{
    if (!len) return;
    uint8_t ctr[16], ks[16];
    for (int k=0;k<16;k++) ctr[k]=J0[k];
    inc32(ctr); // Start at J1

    for (int pos=0; pos<len; ) {
        for (int k=0;k<16;k++) ks[k]=ctr[k];
        aes128_encrypt(ks, key);
        int chunk = len-pos; if(chunk>16) chunk=16;
        for (int k=0;k<chunk;k++) ct[pos+k]=pt[pos+k]^ks[k];
        pos += chunk;
        inc32(ctr);
    }
}

void gcm_seal(const uint8_t key[16], const uint8_t nonce[12],
              const uint8_t *aad, int aad_len,
              const uint8_t *pt,  int pt_len,
              uint8_t *ct, uint8_t tag[16])
{
    // H = AES_K(0^128)
    uint8_t H[16] = {0};
    aes128_encrypt(H, key);

    // J0 = nonce || 0x00000001 (for 96-bit nonce)
    uint8_t J0[16] = {0};
    for (int k=0;k<12;k++) J0[k]=nonce[k];
    J0[15] = 0x01;

    // Encrypt: GCTR(K, inc32(J0), PT)
    gctr(key, J0, pt, ct, pt_len);

    // GHASH(H, AAD || pad || CT || pad || [len(A)]_64 || [len(C)]_64)
    uint8_t ghash[16] = {0};
    ghash_update(H, ghash, aad, aad_len);
    ghash_update(H, ghash, ct,  pt_len);

    uint8_t lens[16];
    store_be64(lens+0, (uint64_t)aad_len * 8); // lengths in bits
    store_be64(lens+8, (uint64_t)pt_len  * 8);
    ghash_update(H, ghash, lens, 16);

    // Tag = E_K(J0) XOR GHASH
    uint8_t ej0[16];
    for (int k=0;k<16;k++) ej0[k]=J0[k];
    aes128_encrypt(ej0, key);
    for (int k=0;k<16;k++) tag[k]=ej0[k]^ghash[k];
}

int gcm_open(const uint8_t key[16], const uint8_t nonce[12],
             const uint8_t *aad, int aad_len,
             const uint8_t *ct, int ct_len,
             const uint8_t *expected_tag, uint8_t *pt)
{
    // Verify tag first
    uint8_t H[16] = {0};
    aes128_encrypt(H, key);

    uint8_t J0[16] = {0};
    for (int k=0;k<12;k++) J0[k]=nonce[k];
    J0[15] = 0x01;

    uint8_t ghash[16] = {0};
    ghash_update(H, ghash, aad, aad_len);
    ghash_update(H, ghash, ct,  ct_len);

    uint8_t lens[16];
    store_be64(lens+0, (uint64_t)aad_len * 8);
    store_be64(lens+8, (uint64_t)ct_len  * 8);
    ghash_update(H, ghash, lens, 16);

    uint8_t ej0[16];
    for (int k=0;k<16;k++) ej0[k]=J0[k];
    aes128_encrypt(ej0, key);

    int diff = 0;
    for (int k=0;k<16;k++) diff |= (ej0[k]^ghash[k]) ^ expected_tag[k];
    if (diff) return 0;

    gctr(key, J0, ct, pt, ct_len);
    return 1;
}

/* ========================================================================== */
/*                               T E S T S                                   */
/* ========================================================================== */

// NIST SP 800-38D, Appendix B, Test Case 1
// Key=00..0, IV=00..0, PT=empty, AAD=empty -> CT=empty, Tag=58e2fccefa7e3061367f1d57a4e7455a
static void test_case1(void) {
    log_write(NONE, "\n=== NIST GCM Test Case 1 (empty PT/AAD) ===\n");
    static const uint8_t key[16] = {0};
    static const uint8_t nonce[12] = {0};
    static const uint8_t exp_tag[16] = {
        0x58,0xe2,0xfc,0xce, 0xfa,0x7e,0x30,0x61,
        0x36,0x7f,0x1d,0x57, 0xa4,0xe7,0x45,0x5a
    };
    uint8_t tag[16];
    gcm_seal(key, nonce, (uint8_t*)"", 0, (uint8_t*)"", 0, (uint8_t*)"", tag);
    chk_bytes("TC1 tag matches NIST", tag, exp_tag, 16);
}

// NIST SP 800-38D Test Case 2
// Key=00..0, IV=00..0, PT=00..0 (16 bytes), AAD=empty
// CT=0388dace60b6a392f328c2b971b2fe78
// Tag=ab6e47d42cec13bdf53a67b21257bddf
static void test_case2(void) {
    log_write(NONE, "\n=== NIST GCM Test Case 2 (16-byte PT, empty AAD) ===\n");
    static const uint8_t key[16] = {0};
    static const uint8_t nonce[12] = {0};
    static const uint8_t pt[16] = {0};
    static const uint8_t exp_ct[16] = {
        0x03,0x88,0xda,0xce, 0x60,0xb6,0xa3,0x92,
        0xf3,0x28,0xc2,0xb9, 0x71,0xb2,0xfe,0x78
    };
    static const uint8_t exp_tag[16] = {
        0xab,0x6e,0x47,0xd4, 0x2c,0xec,0x13,0xbd,
        0xf5,0x3a,0x67,0xb2, 0x12,0x57,0xbd,0xdf
    };
    uint8_t ct[16], tag[16];
    gcm_seal(key, nonce, (uint8_t*)"", 0, pt, 16, ct, tag);
    chk_bytes("TC2 ciphertext matches NIST", ct, exp_ct, 16);
    chk_bytes("TC2 tag matches NIST",       tag, exp_tag, 16);
}

// NIST SP 800-38D Test Case 3
// Key=feffe9928665731c6d6a8f9467308308
// IV=cafebabefacedbaddecaf888
// PT=d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a721c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b391aafd255
// AAD=empty
// CT=42831ec2217774244b7221b784d0d49ce3aa212f2c02a4e035c17e2329aca12e21d514b25466931c7d8f6a5aac84aa051ba30b396a0aac973d58e091473f5985
// Tag=4d5c2af327cd64a62cf35abd2ba6fab4
static void test_case3(void) {
    log_write(NONE, "\n=== NIST GCM Test Case 3 (60-byte PT, empty AAD) ===\n");
    static const uint8_t key[16] = {
        0xfe,0xff,0xe9,0x92, 0x86,0x65,0x73,0x1c,
        0x6d,0x6a,0x8f,0x94, 0x67,0x30,0x83,0x08
    };
    static const uint8_t nonce[12] = {
        0xca,0xfe,0xba,0xbe, 0xfa,0xce,0xdb,0xad,
        0xde,0xca,0xf8,0x88
    };
    static const uint8_t pt[64] = {
        0xd9,0x31,0x32,0x25, 0xf8,0x84,0x06,0xe5,
        0xa5,0x59,0x09,0xc5, 0xaf,0xf5,0x26,0x9a,
        0x86,0xa7,0xa9,0x53, 0x15,0x34,0xf7,0xda,
        0x2e,0x4c,0x30,0x3d, 0x8a,0x31,0x8a,0x72,
        0x1c,0x3c,0x0c,0x95, 0x95,0x68,0x09,0x53,
        0x2f,0xcf,0x0e,0x24, 0x49,0xa6,0xb5,0x25,
        0xb1,0x6a,0xed,0xf5, 0xaa,0x0d,0xe6,0x57,
        0xba,0x63,0x7b,0x39, 0x1a,0xaf,0xd2,0x55
    };
    static const uint8_t exp_ct[64] = {
        0x42,0x83,0x1e,0xc2, 0x21,0x77,0x74,0x24,
        0x4b,0x72,0x21,0xb7, 0x84,0xd0,0xd4,0x9c,
        0xe3,0xaa,0x21,0x2f, 0x2c,0x02,0xa4,0xe0,
        0x35,0xc1,0x7e,0x23, 0x29,0xac,0xa1,0x2e,
        0x21,0xd5,0x14,0xb2, 0x54,0x66,0x93,0x1c,
        0x7d,0x8f,0x6a,0x5a, 0xac,0x84,0xaa,0x05,
        0x1b,0xa3,0x0b,0x39, 0x6a,0x0a,0xac,0x97,
        0x3d,0x58,0xe0,0x91, 0x47,0x3f,0x59,0x85
    };
    static const uint8_t exp_tag[16] = {
        0x4d,0x5c,0x2a,0xf3, 0x27,0xcd,0x64,0xa6,
        0x2c,0xf3,0x5a,0xbd, 0x2b,0xa6,0xfa,0xb4
    };
    uint8_t ct[64], tag[16];
    gcm_seal(key, nonce, (uint8_t*)"", 0, pt, 64, ct, tag);
    chk_bytes("TC3 ciphertext matches NIST", ct, exp_ct, 64);
    chk_bytes("TC3 tag matches NIST",       tag, exp_tag, 16);
}

// NIST SP 800-38D Test Case 4 (60-byte PT, 20-byte AAD)
// Key=feffe9928665731c6d6a8f9467308308
// IV=cafebabefacedbaddecaf888
// PT=d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a721c3c0c95956809532fcf0e2449a6b525b
// AAD=feedfacedeadbeeffeedfacedeadbeefabaddad2
// CT=42831ec2217774244b7221b784d0d49ce3aa212f2c02a4e035c17e2329aca12e21d514b25466931c7d8f6a5aac84aa051ba30b396a0aac973d58e091
// Tag=5bc94fbc3221a5db94fae95ae7121a47
static void test_case4(void) {
    log_write(NONE, "\n=== NIST GCM Test Case 4 (60-byte PT, 20-byte AAD) ===\n");
    static const uint8_t key[16] = {
        0xfe,0xff,0xe9,0x92, 0x86,0x65,0x73,0x1c,
        0x6d,0x6a,0x8f,0x94, 0x67,0x30,0x83,0x08
    };
    static const uint8_t nonce[12] = {
        0xca,0xfe,0xba,0xbe, 0xfa,0xce,0xdb,0xad,
        0xde,0xca,0xf8,0x88
    };
    static const uint8_t aad[20] = {
        0xfe,0xed,0xfa,0xce, 0xde,0xad,0xbe,0xef,
        0xfe,0xed,0xfa,0xce, 0xde,0xad,0xbe,0xef,
        0xab,0xad,0xda,0xd2
    };
    static const uint8_t pt[60] = {
        0xd9,0x31,0x32,0x25, 0xf8,0x84,0x06,0xe5,
        0xa5,0x59,0x09,0xc5, 0xaf,0xf5,0x26,0x9a,
        0x86,0xa7,0xa9,0x53, 0x15,0x34,0xf7,0xda,
        0x2e,0x4c,0x30,0x3d, 0x8a,0x31,0x8a,0x72,
        0x1c,0x3c,0x0c,0x95, 0x95,0x68,0x09,0x53,
        0x2f,0xcf,0x0e,0x24, 0x49,0xa6,0xb5,0x25,
        0xb1,0x6a,0xed,0xf5, 0xaa,0x0d,0xe6,0x57,
        0xba,0x63,0x7b,0x39
    };
    static const uint8_t exp_ct[60] = {
        0x42,0x83,0x1e,0xc2, 0x21,0x77,0x74,0x24,
        0x4b,0x72,0x21,0xb7, 0x84,0xd0,0xd4,0x9c,
        0xe3,0xaa,0x21,0x2f, 0x2c,0x02,0xa4,0xe0,
        0x35,0xc1,0x7e,0x23, 0x29,0xac,0xa1,0x2e,
        0x21,0xd5,0x14,0xb2, 0x54,0x66,0x93,0x1c,
        0x7d,0x8f,0x6a,0x5a, 0xac,0x84,0xaa,0x05,
        0x1b,0xa3,0x0b,0x39, 0x6a,0x0a,0xac,0x97,
        0x3d,0x58,0xe0,0x91
    };
    static const uint8_t exp_tag[16] = {
        0x5b,0xc9,0x4f,0xbc, 0x32,0x21,0xa5,0xdb,
        0x94,0xfa,0xe9,0x5a, 0xe7,0x12,0x1a,0x47
    };
    uint8_t ct[60], tag[16];
    gcm_seal(key, nonce, aad, 20, pt, 60, ct, tag);
    chk_bytes("TC4 ciphertext matches NIST", ct, exp_ct, 60);
    chk_bytes("TC4 tag matches NIST",       tag, exp_tag, 16);
}

static void test_decrypt_roundtrip(void) {
    log_write(NONE, "\n=== Decrypt round-trip ===\n");
    static const uint8_t key[16] = {
        0xfe,0xff,0xe9,0x92, 0x86,0x65,0x73,0x1c,
        0x6d,0x6a,0x8f,0x94, 0x67,0x30,0x83,0x08
    };
    static const uint8_t nonce[12] = {
        0xca,0xfe,0xba,0xbe, 0xfa,0xce,0xdb,0xad,
        0xde,0xca,0xf8,0x88
    };
    static const uint8_t aad[20] = {
        0xfe,0xed,0xfa,0xce, 0xde,0xad,0xbe,0xef,
        0xfe,0xed,0xfa,0xce, 0xde,0xad,0xbe,0xef,
        0xab,0xad,0xda,0xd2
    };
    static const uint8_t ct[60] = {
        0x42,0x83,0x1e,0xc2, 0x21,0x77,0x74,0x24,
        0x4b,0x72,0x21,0xb7, 0x84,0xd0,0xd4,0x9c,
        0xe3,0xaa,0x21,0x2f, 0x2c,0x02,0xa4,0xe0,
        0x35,0xc1,0x7e,0x23, 0x29,0xac,0xa1,0x2e,
        0x21,0xd5,0x14,0xb2, 0x54,0x66,0x93,0x1c,
        0x7d,0x8f,0x6a,0x5a, 0xac,0x84,0xaa,0x05,
        0x1b,0xa3,0x0b,0x39, 0x6a,0x0a,0xac,0x97,
        0x3d,0x58,0xe0,0x91
    };
    static const uint8_t tag[16] = {
        0x5b,0xc9,0x4f,0xbc, 0x32,0x21,0xa5,0xdb,
        0x94,0xfa,0xe9,0x5a, 0xe7,0x12,0x1a,0x47
    };
    static const uint8_t exp_pt[60] = {
        0xd9,0x31,0x32,0x25, 0xf8,0x84,0x06,0xe5,
        0xa5,0x59,0x09,0xc5, 0xaf,0xf5,0x26,0x9a,
        0x86,0xa7,0xa9,0x53, 0x15,0x34,0xf7,0xda,
        0x2e,0x4c,0x30,0x3d, 0x8a,0x31,0x8a,0x72,
        0x1c,0x3c,0x0c,0x95, 0x95,0x68,0x09,0x53,
        0x2f,0xcf,0x0e,0x24, 0x49,0xa6,0xb5,0x25,
        0xb1,0x6a,0xed,0xf5, 0xaa,0x0d,0xe6,0x57,
        0xba,0x63,0x7b,0x39
    };
    uint8_t pt[60];
    int ok = gcm_open(key, nonce, aad, 20, ct, 60, tag, pt);
    chk("decrypt TC4 tag accepted", ok);
    chk_bytes("decrypt TC4 plaintext matches", pt, exp_pt, 60);

    // Tamper
    uint8_t bad_ct[60];
    for (int i=0;i<60;i++) bad_ct[i]=ct[i];
    bad_ct[0] ^= 0x01;
    chk("tampered CT rejected", !gcm_open(key,nonce,aad,20,bad_ct,60,tag,pt));

    uint8_t bad_tag[16];
    for (int i=0;i<16;i++) bad_tag[i]=tag[i];
    bad_tag[0] ^= 0x01;
    chk("tampered tag rejected", !gcm_open(key,nonce,aad,20,ct,60,bad_tag,pt));
}

int main(void) {
    log_init("aes-gcm.log");
    log_write(NONE, "AES-128-GCM Test (NIST SP 800-38D)\n");

    test_case1();
    test_case2();
    test_case3();
    test_case4();
    test_decrypt_roundtrip();

    log_write(NONE, "\n%d PASS  %d FAIL\n", g_pass, g_fail);
    log_close();
    return g_fail ? 1 : 0;
}
