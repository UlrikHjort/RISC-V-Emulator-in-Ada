/* **************************************************************************
 *         RISC-V Emulator - Ed25519 (RFC 8032) for RV32 bare-metal
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

/* ed25519.c -- Ed25519 (RFC 8032) for RV32 bare-metal
 *
 * Field arithmetic: 10-limb radix-2^25.5 representation (ref10/SUPERCOP style).
 * fe[i] stored as int32_t; 64-bit intermediates use int64_t.
 * No 64-bit division. -lgcc provides __muldi3 for 64-bit multiply.
 *
 * By Ulrik Hørlyk Hjort 2026
 */

#include "ed25519.h"
#include "sha512.h"
#include <stdint.h>

typedef int32_t  i32;
typedef int64_t  i64;
typedef uint8_t  u8;
typedef uint32_t u32;

/* Field element: 10 x int32_t limbs, alternating 26/25-bit bounds */
typedef i32 fe[10];

/* Extended coordinates: x=X/Z, y=Y/Z, xy=T/Z */
typedef struct { fe X; fe Y; fe Z; fe T; } ge_p3;
/* Projective */
typedef struct { fe X; fe Y; fe Z; } ge_p2;
/* Completed (p1p1): X=X1*T2, Y=Y1*Z2, Z=Z1*T2, T=X1*Y2 */
typedef struct { fe X; fe Y; fe Z; fe T; } ge_p1p1;
/* Cached (for mixed addition) */
typedef struct { fe YpX; fe YmX; fe Z; fe T2d; } ge_cached;

/* -- Helpers ---------------------------------------------------------------- */

static void fe_0(fe h) { int i; for(i=0;i<10;i++) h[i]=0; }
static void fe_1(fe h) { fe_0(h); h[0]=1; }

static void fe_copy(fe h, const fe f)
{ int i; for(i=0;i<10;i++) h[i]=f[i]; }

/* Constant-time conditional move: if b, h = f */
static void fe_cmov(fe h, const fe f, u32 b)
{
    i32 mask = -(i32)b;
    int i;
    for (i=0;i<10;i++) { i32 x = mask & (h[i]^f[i]); h[i] ^= x; }
}

static void fe_neg(fe h, const fe f)
{ int i; for(i=0;i<10;i++) h[i]=-f[i]; }

static void fe_add(fe h, const fe f, const fe g)
{ int i; for(i=0;i<10;i++) h[i]=f[i]+g[i]; }

static void fe_sub(fe h, const fe f, const fe g)
{ int i; for(i=0;i<10;i++) h[i]=f[i]-g[i]; }

/* -- Multiplication --------------------------------------------------------- */

static void fe_mul(fe h, const fe f, const fe g)
{
    i32 f0=f[0],f1=f[1],f2=f[2],f3=f[3],f4=f[4];
    i32 f5=f[5],f6=f[6],f7=f[7],f8=f[8],f9=f[9];
    i32 g0=g[0],g1=g[1],g2=g[2],g3=g[3],g4=g[4];
    i32 g5=g[5],g6=g[6],g7=g[7],g8=g[8],g9=g[9];
    i64 g1_19=(i64)19*g1, g2_19=(i64)19*g2, g3_19=(i64)19*g3, g4_19=(i64)19*g4;
    i64 g5_19=(i64)19*g5, g6_19=(i64)19*g6, g7_19=(i64)19*g7, g8_19=(i64)19*g8, g9_19=(i64)19*g9;
    i64 f1_2=(i64)2*f1, f3_2=(i64)2*f3, f5_2=(i64)2*f5, f7_2=(i64)2*f7, f9_2=(i64)2*f9;
    i64 h0,h1,h2,h3,h4,h5,h6,h7,h8,h9;
    i64 c0,c1,c2,c3,c4,c5,c6,c7,c8,c9;

    h0 = (i64)f0*g0   + (i64)f1_2*g9_19 + (i64)f2*g8_19   + (i64)f3_2*g7_19
       + (i64)f4*g6_19 + (i64)f5_2*g5_19 + (i64)f6*g4_19   + (i64)f7_2*g3_19
       + (i64)f8*g2_19 + (i64)f9_2*g1_19;
    h1 = (i64)f0*g1   + (i64)f1*g0      + (i64)f2*g9_19   + (i64)f3*g8_19
       + (i64)f4*g7_19 + (i64)f5*g6_19   + (i64)f6*g5_19   + (i64)f7*g4_19
       + (i64)f8*g3_19 + (i64)f9*g2_19;
    h2 = (i64)f0*g2   + (i64)f1_2*g1    + (i64)f2*g0      + (i64)f3_2*g9_19
       + (i64)f4*g8_19 + (i64)f5_2*g7_19 + (i64)f6*g6_19   + (i64)f7_2*g5_19
       + (i64)f8*g4_19 + (i64)f9_2*g3_19;
    h3 = (i64)f0*g3   + (i64)f1*g2      + (i64)f2*g1      + (i64)f3*g0
       + (i64)f4*g9_19 + (i64)f5*g8_19   + (i64)f6*g7_19   + (i64)f7*g6_19
       + (i64)f8*g5_19 + (i64)f9*g4_19;
    h4 = (i64)f0*g4   + (i64)f1_2*g3    + (i64)f2*g2      + (i64)f3_2*g1
       + (i64)f4*g0   + (i64)f5_2*g9_19  + (i64)f6*g8_19   + (i64)f7_2*g7_19
       + (i64)f8*g6_19 + (i64)f9_2*g5_19;
    h5 = (i64)f0*g5   + (i64)f1*g4      + (i64)f2*g3      + (i64)f3*g2
       + (i64)f4*g1   + (i64)f5*g0       + (i64)f6*g9_19   + (i64)f7*g8_19
       + (i64)f8*g7_19 + (i64)f9*g6_19;
    h6 = (i64)f0*g6   + (i64)f1_2*g5    + (i64)f2*g4      + (i64)f3_2*g3
       + (i64)f4*g2   + (i64)f5_2*g1     + (i64)f6*g0      + (i64)f7_2*g9_19
       + (i64)f8*g8_19 + (i64)f9_2*g7_19;
    h7 = (i64)f0*g7   + (i64)f1*g6      + (i64)f2*g5      + (i64)f3*g4
       + (i64)f4*g3   + (i64)f5*g2       + (i64)f6*g1      + (i64)f7*g0
       + (i64)f8*g9_19 + (i64)f9*g8_19;
    h8 = (i64)f0*g8   + (i64)f1_2*g7    + (i64)f2*g6      + (i64)f3_2*g5
       + (i64)f4*g4   + (i64)f5_2*g3     + (i64)f6*g2      + (i64)f7_2*g1
       + (i64)f8*g0   + (i64)f9_2*g9_19;
    h9 = (i64)f0*g9   + (i64)f1*g8      + (i64)f2*g7      + (i64)f3*g6
       + (i64)f4*g5   + (i64)f5*g4       + (i64)f6*g3      + (i64)f7*g2
       + (i64)f8*g1   + (i64)f9*g0;

    c0=(h0+(i64)(1<<25))>>26; h1+=c0; h0-=c0<<26;
    c4=(h4+(i64)(1<<25))>>26; h5+=c4; h4-=c4<<26;
    c1=(h1+(i64)(1<<24))>>25; h2+=c1; h1-=c1<<25;
    c5=(h5+(i64)(1<<24))>>25; h6+=c5; h5-=c5<<25;
    c2=(h2+(i64)(1<<25))>>26; h3+=c2; h2-=c2<<26;
    c6=(h6+(i64)(1<<25))>>26; h7+=c6; h6-=c6<<26;
    c3=(h3+(i64)(1<<24))>>25; h4+=c3; h3-=c3<<25;
    c7=(h7+(i64)(1<<24))>>25; h8+=c7; h7-=c7<<25;
    c4=(h4+(i64)(1<<25))>>26; h5+=c4; h4-=c4<<26;
    c8=(h8+(i64)(1<<25))>>26; h9+=c8; h8-=c8<<26;
    c9=(h9+(i64)(1<<24))>>25; h0+=c9*19; h9-=c9<<25;
    c0=(h0+(i64)(1<<25))>>26; h1+=c0; h0-=c0<<26;

    h[0]=(i32)h0; h[1]=(i32)h1; h[2]=(i32)h2; h[3]=(i32)h3; h[4]=(i32)h4;
    h[5]=(i32)h5; h[6]=(i32)h6; h[7]=(i32)h7; h[8]=(i32)h8; h[9]=(i32)h9;
}

static void fe_sq(fe h, const fe f)
{
    i32 f0=f[0],f1=f[1],f2=f[2],f3=f[3],f4=f[4];
    i32 f5=f[5],f6=f[6],f7=f[7],f8=f[8],f9=f[9];
    i64 f0_2=(i64)2*f0, f1_2=(i64)2*f1, f2_2=(i64)2*f2, f3_2=(i64)2*f3, f4_2=(i64)2*f4;
    i64 f5_2=(i64)2*f5, f6_2=(i64)2*f6, f7_2=(i64)2*f7;
    i64 f5_38=(i64)38*f5, f6_19=(i64)19*f6, f7_38=(i64)38*f7, f8_19=(i64)19*f8, f9_38=(i64)38*f9;
    i64 h0,h1,h2,h3,h4,h5,h6,h7,h8,h9;
    i64 c0,c1,c2,c3,c4,c5,c6,c7,c8,c9;

    h0 = (i64)f0*f0      + (i64)f1_2*f9_38 + (i64)f2_2*f8_19
       + (i64)f3_2*f7_38 + (i64)f4_2*f6_19  + (i64)f5*f5_38;
    h1 = (i64)f0_2*f1    + (i64)f2*f9_38   + (i64)f3_2*f8_19
       + (i64)f4*f7_38   + (i64)f5_2*f6_19;
    h2 = (i64)f0_2*f2    + (i64)f1_2*f1    + (i64)f3_2*f9_38
       + (i64)f4_2*f8_19 + (i64)f5_2*f7_38  + (i64)f6*f6_19;
    h3 = (i64)f0_2*f3    + (i64)f1_2*f2    + (i64)f4*f9_38
       + (i64)f5_2*f8_19 + (i64)f6*f7_38;
    h4 = (i64)f0_2*f4    + (i64)f1_2*f3_2  + (i64)f2*f2
       + (i64)f5_2*f9_38 + (i64)f6_2*f8_19  + (i64)f7*f7_38;
    h5 = (i64)f0_2*f5    + (i64)f1_2*f4    + (i64)f2_2*f3
       + (i64)f6*f9_38   + (i64)f7_2*f8_19;
    h6 = (i64)f0_2*f6    + (i64)f1_2*f5_2  + (i64)f2_2*f4
       + (i64)f3_2*f3    + (i64)f7_2*f9_38  + (i64)f8*f8_19;
    h7 = (i64)f0_2*f7    + (i64)f1_2*f6    + (i64)f2_2*f5
       + (i64)f3_2*f4    + (i64)f8*f9_38;
    h8 = (i64)f0_2*f8    + (i64)f1_2*f7_2  + (i64)f2_2*f6
       + (i64)f3_2*f5_2  + (i64)f4*f4       + (i64)f9*f9_38;
    h9 = (i64)f0_2*f9    + (i64)f1_2*f8    + (i64)f2_2*f7
       + (i64)f3_2*f6    + (i64)f4_2*f5;

    c0=(h0+(i64)(1<<25))>>26; h1+=c0; h0-=c0<<26;
    c4=(h4+(i64)(1<<25))>>26; h5+=c4; h4-=c4<<26;
    c1=(h1+(i64)(1<<24))>>25; h2+=c1; h1-=c1<<25;
    c5=(h5+(i64)(1<<24))>>25; h6+=c5; h5-=c5<<25;
    c2=(h2+(i64)(1<<25))>>26; h3+=c2; h2-=c2<<26;
    c6=(h6+(i64)(1<<25))>>26; h7+=c6; h6-=c6<<26;
    c3=(h3+(i64)(1<<24))>>25; h4+=c3; h3-=c3<<25;
    c7=(h7+(i64)(1<<24))>>25; h8+=c7; h7-=c7<<25;
    c4=(h4+(i64)(1<<25))>>26; h5+=c4; h4-=c4<<26;
    c8=(h8+(i64)(1<<25))>>26; h9+=c8; h8-=c8<<26;
    c9=(h9+(i64)(1<<24))>>25; h0+=c9*19; h9-=c9<<25;
    c0=(h0+(i64)(1<<25))>>26; h1+=c0; h0-=c0<<26;

    h[0]=(i32)h0; h[1]=(i32)h1; h[2]=(i32)h2; h[3]=(i32)h3; h[4]=(i32)h4;
    h[5]=(i32)h5; h[6]=(i32)h6; h[7]=(i32)h7; h[8]=(i32)h8; h[9]=(i32)h9;
}

/* fe_sq2: h = 2*f^2 */
static void fe_sq2(fe h, const fe f)
{
    fe_sq(h, f);
    int i; for(i=0;i<10;i++) h[i]*=2;
}

/* -- Exponentiation helpers ------------------------------------------------- */

/* h = f^(2^252 - 3) -- used in sqrt */
static void fe_pow22523(fe out, const fe z)
{
    fe t0, t1, t2;
    int i;
    fe_sq(t0, z);
    fe_sq(t1, t0); fe_sq(t1, t1); fe_mul(t1, t1, z);
    fe_mul(t0, t0, t1);
    fe_sq(t0, t0); fe_mul(t0, t0, t1);
    fe_sq(t1, t0);
    for (i=1;i<5;i++) fe_sq(t1, t1);
    fe_mul(t0, t1, t0);
    fe_sq(t1, t0);
    for (i=1;i<10;i++) fe_sq(t1, t1);
    fe_mul(t1, t1, t0);
    fe_sq(t2, t1);
    for (i=1;i<20;i++) fe_sq(t2, t2);
    fe_mul(t1, t2, t1);
    fe_sq(t1, t1);
    for (i=1;i<10;i++) fe_sq(t1, t1);
    fe_mul(t0, t1, t0);
    fe_sq(t1, t0);
    for (i=1;i<50;i++) fe_sq(t1, t1);
    fe_mul(t1, t1, t0);
    fe_sq(t2, t1);
    for (i=1;i<100;i++) fe_sq(t2, t2);
    fe_mul(t1, t2, t1);
    fe_sq(t1, t1);
    for (i=1;i<50;i++) fe_sq(t1, t1);
    fe_mul(t0, t1, t0);
    fe_sq(t0, t0); fe_sq(t0, t0);
    fe_mul(out, t0, z);
}

/* h = 1/f mod p */
static void fe_invert(fe h, const fe f)
{
    fe t0, t1, t2, t3;
    int i;
    fe_sq(t0, f);
    fe_sq(t1, t0); fe_sq(t1, t1); fe_mul(t1, t1, f);
    fe_mul(t0, t0, t1);
    fe_sq(t2, t0); fe_mul(t1, t2, t1);
    fe_sq(t2, t1);
    for (i=1;i<5;i++) fe_sq(t2, t2);
    fe_mul(t1, t2, t1);
    fe_sq(t2, t1);
    for (i=1;i<10;i++) fe_sq(t2, t2);
    fe_mul(t2, t2, t1);
    fe_sq(t3, t2);
    for (i=1;i<20;i++) fe_sq(t3, t3);
    fe_mul(t2, t3, t2);
    fe_sq(t2, t2);
    for (i=1;i<10;i++) fe_sq(t2, t2);
    fe_mul(t1, t2, t1);
    fe_sq(t2, t1);
    for (i=1;i<50;i++) fe_sq(t2, t2);
    fe_mul(t2, t2, t1);
    fe_sq(t3, t2);
    for (i=1;i<100;i++) fe_sq(t3, t3);
    fe_mul(t2, t3, t2);
    fe_sq(t2, t2);
    for (i=1;i<50;i++) fe_sq(t2, t2);
    fe_mul(t1, t2, t1);
    fe_sq(t1, t1); for (i=1;i<5;i++) fe_sq(t1, t1);
    fe_mul(h, t1, t0);
}

/* -- Encoding / Decoding ---------------------------------------------------- */

static void fe_tobytes(u8 s[32], const fe h)
{
    i32 t[10];
    i32 q;
    i32 carry[10];
    int i;
    for (i=0;i<10;i++) t[i]=h[i];

    /* Full reduction: conditional subtraction of p */
    q = (19*t[9] + (1<<24)) >> 25;
    q = (t[0] + q) >> 26;
    q = (t[1] + q) >> 25;
    q = (t[2] + q) >> 26;
    q = (t[3] + q) >> 25;
    q = (t[4] + q) >> 26;
    q = (t[5] + q) >> 25;
    q = (t[6] + q) >> 26;
    q = (t[7] + q) >> 25;
    q = (t[8] + q) >> 26;
    q = (t[9] + q) >> 25;

    t[0] += 19*q;
    carry[0]=(t[0])>>26; t[1]+=carry[0]; t[0]-=carry[0]<<26;
    carry[1]=(t[1])>>25; t[2]+=carry[1]; t[1]-=carry[1]<<25;
    carry[2]=(t[2])>>26; t[3]+=carry[2]; t[2]-=carry[2]<<26;
    carry[3]=(t[3])>>25; t[4]+=carry[3]; t[3]-=carry[3]<<25;
    carry[4]=(t[4])>>26; t[5]+=carry[4]; t[4]-=carry[4]<<26;
    carry[5]=(t[5])>>25; t[6]+=carry[5]; t[5]-=carry[5]<<25;
    carry[6]=(t[6])>>26; t[7]+=carry[6]; t[6]-=carry[6]<<26;
    carry[7]=(t[7])>>25; t[8]+=carry[7]; t[7]-=carry[7]<<25;
    carry[8]=(t[8])>>26; t[9]+=carry[8]; t[8]-=carry[8]<<26;
    carry[9]=(t[9])>>25;                 t[9]-=carry[9]<<25;
    (void)i;

    s[ 0] = (u8)(t[0] >> 0);
    s[ 1] = (u8)(t[0] >> 8);
    s[ 2] = (u8)(t[0] >> 16);
    s[ 3] = (u8)((t[0] >> 24) | (t[1] << 2));
    s[ 4] = (u8)(t[1] >> 6);
    s[ 5] = (u8)(t[1] >> 14);
    s[ 6] = (u8)((t[1] >> 22) | (t[2] << 3));
    s[ 7] = (u8)(t[2] >> 5);
    s[ 8] = (u8)(t[2] >> 13);
    s[ 9] = (u8)((t[2] >> 21) | (t[3] << 5));
    s[10] = (u8)(t[3] >> 3);
    s[11] = (u8)(t[3] >> 11);
    s[12] = (u8)((t[3] >> 19) | (t[4] << 6));
    s[13] = (u8)(t[4] >> 2);
    s[14] = (u8)(t[4] >> 10);
    s[15] = (u8)(t[4] >> 18);
    s[16] = (u8)(t[5] >> 0);
    s[17] = (u8)(t[5] >> 8);
    s[18] = (u8)(t[5] >> 16);
    s[19] = (u8)((t[5] >> 24) | (t[6] << 1));
    s[20] = (u8)(t[6] >> 7);
    s[21] = (u8)(t[6] >> 15);
    s[22] = (u8)((t[6] >> 23) | (t[7] << 3));
    s[23] = (u8)(t[7] >> 5);
    s[24] = (u8)(t[7] >> 13);
    s[25] = (u8)((t[7] >> 21) | (t[8] << 4));
    s[26] = (u8)(t[8] >> 4);
    s[27] = (u8)(t[8] >> 12);
    s[28] = (u8)((t[8] >> 20) | (t[9] << 6));
    s[29] = (u8)(t[9] >> 2);
    s[30] = (u8)(t[9] >> 10);
    s[31] = (u8)(t[9] >> 18);
}

static void fe_frombytes(fe h, const u8 s[32])
{
    i64 h0 = (u32)s[ 0]        | ((u32)s[ 1]<< 8) | ((u32)s[ 2]<<16) | ((u32)(s[ 3]&0x03)<<24);
    i64 h1 = ((u32)s[ 3]>> 2)  | ((u32)s[ 4]<< 6) | ((u32)s[ 5]<<14) | ((u32)(s[ 6]&0x07)<<22);
    i64 h2 = ((u32)s[ 6]>> 3)  | ((u32)s[ 7]<< 5) | ((u32)s[ 8]<<13) | ((u32)(s[ 9]&0x1f)<<21);
    i64 h3 = ((u32)s[ 9]>> 5)  | ((u32)s[10]<< 3) | ((u32)s[11]<<11) | ((u32)(s[12]&0x3f)<<19);
    i64 h4 = ((u32)s[12]>> 6)  | ((u32)s[13]<< 2) | ((u32)s[14]<<10) | ((u32)s[15]<<18);
    i64 h5 = (u32)s[16]        | ((u32)s[17]<< 8) | ((u32)s[18]<<16) | ((u32)(s[19]&0x01)<<24);
    i64 h6 = ((u32)s[19]>> 1)  | ((u32)s[20]<< 7) | ((u32)s[21]<<15) | ((u32)(s[22]&0x07)<<23);
    i64 h7 = ((u32)s[22]>> 3)  | ((u32)s[23]<< 5) | ((u32)s[24]<<13) | ((u32)(s[25]&0x0f)<<21);
    i64 h8 = ((u32)s[25]>> 4)  | ((u32)s[26]<< 4) | ((u32)s[27]<<12) | ((u32)(s[28]&0x3f)<<20);
    i64 h9 = ((u32)s[28]>> 6)  | ((u32)s[29]<< 2) | ((u32)s[30]<<10) | ((u32)(s[31]&0x7f)<<18);
    i32 c;
    c=(i32)((h0+(i64)(1<<25))>>26); h1+=c; h0-=(i64)c<<26;
    c=(i32)((h1+(i64)(1<<24))>>25); h2+=c; h1-=(i64)c<<25;
    c=(i32)((h2+(i64)(1<<25))>>26); h3+=c; h2-=(i64)c<<26;
    c=(i32)((h3+(i64)(1<<24))>>25); h4+=c; h3-=(i64)c<<25;
    c=(i32)((h4+(i64)(1<<25))>>26); h5+=c; h4-=(i64)c<<26;
    c=(i32)((h5+(i64)(1<<24))>>25); h6+=c; h5-=(i64)c<<25;
    c=(i32)((h6+(i64)(1<<25))>>26); h7+=c; h6-=(i64)c<<26;
    c=(i32)((h7+(i64)(1<<24))>>25); h8+=c; h7-=(i64)c<<25;
    c=(i32)((h8+(i64)(1<<25))>>26); h9+=c; h8-=(i64)c<<26;
    c=(i32)((h9+(i64)(1<<24))>>25); h0+=(i64)c*19; h9-=(i64)c<<25;
    h[0]=(i32)h0; h[1]=(i32)h1; h[2]=(i32)h2; h[3]=(i32)h3; h[4]=(i32)h4;
    h[5]=(i32)h5; h[6]=(i32)h6; h[7]=(i32)h7; h[8]=(i32)h8; h[9]=(i32)h9;
}

static int fe_iszero(const fe f)
{
    u8 s[32]; fe_tobytes(s, f);
    u32 x=0; int i; for(i=0;i<32;i++) x|=s[i]; return x==0;
}

static int fe_isneg(const fe f)
{ u8 s[32]; fe_tobytes(s, f); return s[0]&1; }

/* -- Curve constants (ref10/SUPERCOP values) ------------------------------- */

/* d = -121665/121666 mod p */
static const i32 d_c[10] = {
    -10913610, 13857413, -15372611, 6949391,   114729,
     -8787816, -6275908,  -3247719, -18696448, -12055116
};
/* 2*d */
static const i32 d2_c[10] = {
    -21827239, -5839606, -30745221, 13898782, 229458,
     15978800, -12551817, -6495438, 29715968,  9444199
};
/* sqrt(-1) mod p */
static const i32 sqrtm1_c[10] = {
    -32595792, -7943725,  9377950, 3500415, 12389472,
       -272473, -25146209, -2005654, 326686, 11406482
};

/* Base point G encoded per RFC 8032:
 * 32-byte little-endian encoding with sign of x in top bit of last byte.
 * This is the compressed y-coordinate of the Ed25519 base point.
 * y = 4/5 mod p, x is positive (bit 0 of x = 0, so top bit = 0). */
static const u8 G_bytes[32] = {
    0x58,0x66,0x66,0x66,0x66,0x66,0x66,0x66,
    0x66,0x66,0x66,0x66,0x66,0x66,0x66,0x66,
    0x66,0x66,0x66,0x66,0x66,0x66,0x66,0x66,
    0x66,0x66,0x66,0x66,0x66,0x66,0x66,0x66
};

/* -- Extended coordinates --------------------------------------------------- */

static void ge_p3_0(ge_p3 *h)
{ fe_0(h->X); fe_1(h->Y); fe_1(h->Z); fe_0(h->T); }

static void ge_p3_to_p2(ge_p2 *r, const ge_p3 *p)
{ fe_copy(r->X,p->X); fe_copy(r->Y,p->Y); fe_copy(r->Z,p->Z); }

static void ge_p3_to_cached(ge_cached *r, const ge_p3 *p)
{
    fe d2; int i; for(i=0;i<10;i++) d2[i]=d2_c[i];
    fe_add(r->YpX, p->Y, p->X);
    fe_sub(r->YmX, p->Y, p->X);
    fe_copy(r->Z, p->Z);
    fe_mul(r->T2d, p->T, d2);
}

/* p1p1 -> p3 conversion */
static void ge_p1p1_to_p3(ge_p3 *r, const ge_p1p1 *p)
{
    fe_mul(r->X, p->X, p->T);
    fe_mul(r->Y, p->Y, p->Z);
    fe_mul(r->Z, p->Z, p->T);
    fe_mul(r->T, p->X, p->Y);
}

/* p2 doubling -> p1p1 */
static void ge_p2_dbl(ge_p1p1 *r, const ge_p2 *p)
{
    fe t0;
    fe_sq(r->X, p->X);
    fe_sq(r->Z, p->Y);
    fe_sq2(r->T, p->Z);
    fe_add(r->Y, p->X, p->Y);
    fe_sq(t0, r->Y);
    fe_add(r->Y, r->Z, r->X);
    fe_sub(r->Z, r->Z, r->X);
    fe_sub(r->X, t0, r->Y);
    fe_sub(r->T, r->T, r->Z);
}

static void ge_p3_dbl(ge_p3 *r, const ge_p3 *p)
{
    ge_p2 p2; ge_p1p1 tmp;
    ge_p3_to_p2(&p2, p);
    ge_p2_dbl(&tmp, &p2);
    ge_p1p1_to_p3(r, &tmp);
}

/* p3 + cached -> p1p1 */
static void ge_add_r(ge_p1p1 *r, const ge_p3 *p, const ge_cached *q)
{
    fe t0;
    fe_add(r->X, p->Y, p->X);
    fe_sub(r->Y, p->Y, p->X);
    fe_mul(r->Z, r->X, q->YpX);
    fe_mul(r->Y, r->Y, q->YmX);
    fe_mul(r->T, q->T2d, p->T);
    fe_mul(r->X, p->Z, q->Z);
    fe_add(t0, r->X, r->X);
    fe_sub(r->X, r->Z, r->Y);
    fe_add(r->Y, r->Z, r->Y);
    fe_add(r->Z, t0, r->T);
    fe_sub(r->T, t0, r->T);
}

/* p3 + cached -> p3 */
static void ge_add(ge_p3 *r, const ge_p3 *p, const ge_cached *q)
{
    ge_p1p1 tmp;
    ge_add_r(&tmp, p, q);
    ge_p1p1_to_p3(r, &tmp);
}

/* Encode p3 -> 32 bytes */
static void ge_p3_tobytes(u8 s[32], const ge_p3 *h)
{
    fe recip, x, y;
    fe_invert(recip, h->Z);
    fe_mul(x, h->X, recip);
    fe_mul(y, h->Y, recip);
    fe_tobytes(s, y);
    s[31] ^= (u8)(fe_isneg(x)<<7);
}

/* Decode 32 bytes -> p3; return 0 on success, -1 on failure */
static int ge_frombytes_vartime(ge_p3 *h, const u8 s[32])
{
    fe u, v, v3, vxx, check;
    fe sqm1, d;
    int i;
    for(i=0;i<10;i++) { sqm1[i]=sqrtm1_c[i]; d[i]=d_c[i]; }

    fe_frombytes(h->Y, s);
    fe_1(h->Z);
    fe_sq(u, h->Y);             /* u = y^2 */
    fe_mul(v, u, d);            /* v = d*y^2 */
    fe_sub(u, u, h->Z);         /* u = y^2 - 1 */
    fe_add(v, v, h->Z);         /* v = d*y^2 + 1 */

    /* x = sqrt(u/v) = u*v^3*(u*v^7)^((p-5)/8) */
    fe_sq(v3, v);
    fe_mul(v3, v3, v);          /* v3 = v^3 */
    fe_sq(h->X, v3);
    fe_mul(h->X, h->X, v);      /* v^7 */
    fe_mul(h->X, h->X, u);      /* u*v^7 */
    fe_pow22523(h->X, h->X);    /* (u*v^7)^((p-5)/8) */
    fe_mul(h->X, h->X, v3);
    fe_mul(h->X, h->X, u);      /* u * v^3 * ... */

    fe_sq(vxx, h->X);
    fe_mul(vxx, vxx, v);
    fe_sub(check, vxx, u);

    if (!fe_iszero(check)) {
        fe_add(check, vxx, u);
        if (!fe_iszero(check)) return -1;
        fe_mul(h->X, h->X, sqm1);
    }

    if (fe_isneg(h->X) != ((s[31]>>7)&1))
        fe_neg(h->X, h->X);

    fe_mul(h->T, h->X, h->Y);
    return 0;
}

/* -- Scalar multiplication ------------------------------------------------- */

static void ge_scalarmult_base(ge_p3 *h, const u8 *scalar)
{
    ge_p3 A, tmp;
    ge_cached Ac;
    int i, bit;

    /* Decode base point from canonical encoding */
    if (ge_frombytes_vartime(&A, G_bytes) != 0) {
        fe_0(h->X); fe_1(h->Y); fe_1(h->Z); fe_0(h->T);
        return;
    }

    ge_p3_0(h);

    for (i=254; i>=0; i--) {
        bit = (scalar[i>>3] >> (i&7)) & 1;
        ge_p3_dbl(&tmp, h);
        fe_copy(h->X,tmp.X); fe_copy(h->Y,tmp.Y);
        fe_copy(h->Z,tmp.Z); fe_copy(h->T,tmp.T);
        ge_p3_to_cached(&Ac, &A);
        ge_add(&tmp, h, &Ac);
        fe_cmov(h->X, tmp.X, (u32)bit);
        fe_cmov(h->Y, tmp.Y, (u32)bit);
        fe_cmov(h->Z, tmp.Z, (u32)bit);
        fe_cmov(h->T, tmp.T, (u32)bit);
    }
}

static void ge_scalarmult(ge_p3 *h, const u8 *scalar, const ge_p3 *A)
{
    ge_p3 tmp;
    ge_cached Ac;
    int i, bit;

    ge_p3_0(h);

    for (i=254; i>=0; i--) {
        bit = (scalar[i>>3] >> (i&7)) & 1;
        ge_p3_dbl(&tmp, h);
        fe_copy(h->X,tmp.X); fe_copy(h->Y,tmp.Y);
        fe_copy(h->Z,tmp.Z); fe_copy(h->T,tmp.T);
        ge_p3_to_cached(&Ac, A);
        ge_add(&tmp, h, &Ac);
        fe_cmov(h->X, tmp.X, (u32)bit);
        fe_cmov(h->Y, tmp.Y, (u32)bit);
        fe_cmov(h->Z, tmp.Z, (u32)bit);
        fe_cmov(h->T, tmp.T, (u32)bit);
    }
}

/* -- Scalar mod L ----------------------------------------------------------- */

/* sc_reduce: reduce 64-byte s mod L, put result in s[0..31], zero s[32..63] */
void sc_reduce(u8 s[64])
{
    i64 s0,s1,s2,s3,s4,s5,s6,s7,s8,s9,s10,s11,
        s12,s13,s14,s15,s16,s17,s18,s19,s20,s21,s22,s23;
    i64 c0,c1,c2,c3,c4,c5,c6,c7,c8,c9,c10,c11,c12,c13,c14,c15,c16;

    /* Unpack 512-bit input into 24 x 21-bit limbs.
     * Limb n starts at bit n*21. start_byte=n*21/8, bit_in_byte=n*21%8.
     * Use load_4 when bit_in_byte >= 4 (limb spans 4 bytes), else load_3. */
    s0  = 2097151LL & (               (i64)s[ 0] | ((i64)s[ 1]<< 8) | ((i64)s[ 2]<<16));
    s1  = 2097151LL & (((i64)s[ 2]>>5)| ((i64)s[ 3]<< 3) | ((i64)s[ 4]<<11) | ((i64)s[ 5]<<19));
    s2  = 2097151LL & (((i64)s[ 5]>>2)| ((i64)s[ 6]<< 6) | ((i64)s[ 7]<<14));
    s3  = 2097151LL & (((i64)s[ 7]>>7)| ((i64)s[ 8]<< 1) | ((i64)s[ 9]<< 9) | ((i64)s[10]<<17));
    s4  = 2097151LL & (((i64)s[10]>>4)| ((i64)s[11]<< 4) | ((i64)s[12]<<12) | ((i64)s[13]<<20));
    s5  = 2097151LL & (((i64)s[13]>>1)| ((i64)s[14]<< 7) | ((i64)s[15]<<15));
    s6  = 2097151LL & (((i64)s[15]>>6)| ((i64)s[16]<< 2) | ((i64)s[17]<<10) | ((i64)s[18]<<18));
    s7  = 2097151LL & (((i64)s[18]>>3)| ((i64)s[19]<< 5) | ((i64)s[20]<<13));
    s8  = 2097151LL & (               (i64)s[21] | ((i64)s[22]<< 8) | ((i64)s[23]<<16));
    s9  = 2097151LL & (((i64)s[23]>>5)| ((i64)s[24]<< 3) | ((i64)s[25]<<11) | ((i64)s[26]<<19));
    s10 = 2097151LL & (((i64)s[26]>>2)| ((i64)s[27]<< 6) | ((i64)s[28]<<14));
    s11 = 2097151LL & (((i64)s[28]>>7)| ((i64)s[29]<< 1) | ((i64)s[30]<< 9) | ((i64)s[31]<<17));
    s12 = 2097151LL & (((i64)s[31]>>4)| ((i64)s[32]<< 4) | ((i64)s[33]<<12) | ((i64)s[34]<<20));
    s13 = 2097151LL & (((i64)s[34]>>1)| ((i64)s[35]<< 7) | ((i64)s[36]<<15));
    s14 = 2097151LL & (((i64)s[36]>>6)| ((i64)s[37]<< 2) | ((i64)s[38]<<10) | ((i64)s[39]<<18));
    s15 = 2097151LL & (((i64)s[39]>>3)| ((i64)s[40]<< 5) | ((i64)s[41]<<13));
    s16 = 2097151LL & (               (i64)s[42] | ((i64)s[43]<< 8) | ((i64)s[44]<<16));
    s17 = 2097151LL & (((i64)s[44]>>5)| ((i64)s[45]<< 3) | ((i64)s[46]<<11) | ((i64)s[47]<<19));
    s18 = 2097151LL & (((i64)s[47]>>2)| ((i64)s[48]<< 6) | ((i64)s[49]<<14));
    s19 = 2097151LL & (((i64)s[49]>>7)| ((i64)s[50]<< 1) | ((i64)s[51]<< 9) | ((i64)s[52]<<17));
    s20 = 2097151LL & (((i64)s[52]>>4)| ((i64)s[53]<< 4) | ((i64)s[54]<<12) | ((i64)s[55]<<20));
    s21 = 2097151LL & (((i64)s[55]>>1)| ((i64)s[56]<< 7) | ((i64)s[57]<<15));
    s22 = 2097151LL & (((i64)s[57]>>6)| ((i64)s[58]<< 2) | ((i64)s[59]<<10) | ((i64)s[60]<<18));
    s23 =             (((i64)s[60]>>3)| ((i64)s[61]<< 5) | ((i64)s[62]<<13) | ((i64)s[63]<<21));

    s11 += s23*666643LL; s12 += s23*470296LL; s13 += s23*654183LL;
    s14 -= s23*997805LL; s15 += s23*136657LL; s16 -= s23*683901LL; s23=0;
    s10 += s22*666643LL; s11 += s22*470296LL; s12 += s22*654183LL;
    s13 -= s22*997805LL; s14 += s22*136657LL; s15 -= s22*683901LL; s22=0;
    s9  += s21*666643LL; s10 += s21*470296LL; s11 += s21*654183LL;
    s12 -= s21*997805LL; s13 += s21*136657LL; s14 -= s21*683901LL; s21=0;
    s8  += s20*666643LL; s9  += s20*470296LL; s10 += s20*654183LL;
    s11 -= s20*997805LL; s12 += s20*136657LL; s13 -= s20*683901LL; s20=0;
    s7  += s19*666643LL; s8  += s19*470296LL; s9  += s19*654183LL;
    s10 -= s19*997805LL; s11 += s19*136657LL; s12 -= s19*683901LL; s19=0;
    s6  += s18*666643LL; s7  += s18*470296LL; s8  += s18*654183LL;
    s9  -= s18*997805LL; s10 += s18*136657LL; s11 -= s18*683901LL; s18=0;

    /* Butterfly carry: even slots first, then odd -- reduces s12..s17 before second fold */
    c6 =(s6 +(i64)(1<<20))>>21; s7 +=c6;  s6 -=c6 *((i64)1<<21);
    c8 =(s8 +(i64)(1<<20))>>21; s9 +=c8;  s8 -=c8 *((i64)1<<21);
    c10=(s10+(i64)(1<<20))>>21; s11+=c10; s10-=c10*((i64)1<<21);
    c12=(s12+(i64)(1<<20))>>21; s13+=c12; s12-=c12*((i64)1<<21);
    c14=(s14+(i64)(1<<20))>>21; s15+=c14; s14-=c14*((i64)1<<21);
    c16=(s16+(i64)(1<<20))>>21; s17+=c16; s16-=c16*((i64)1<<21);
    c7 =(s7 +(i64)(1<<20))>>21; s8 +=c7;  s7 -=c7 *((i64)1<<21);
    c9 =(s9 +(i64)(1<<20))>>21; s10+=c9;  s9 -=c9 *((i64)1<<21);
    c11=(s11+(i64)(1<<20))>>21; s12+=c11; s11-=c11*((i64)1<<21);
    c13=(s13+(i64)(1<<20))>>21; s14+=c13; s13-=c13*((i64)1<<21);
    c15=(s15+(i64)(1<<20))>>21; s16+=c15; s15-=c15*((i64)1<<21);

    s5  += s17*666643LL; s6  += s17*470296LL; s7  += s17*654183LL;
    s8  -= s17*997805LL; s9  += s17*136657LL; s10 -= s17*683901LL; s17=0;
    s4  += s16*666643LL; s5  += s16*470296LL; s6  += s16*654183LL;
    s7  -= s16*997805LL; s8  += s16*136657LL; s9  -= s16*683901LL; s16=0;
    s3  += s15*666643LL; s4  += s15*470296LL; s5  += s15*654183LL;
    s6  -= s15*997805LL; s7  += s15*136657LL; s8  -= s15*683901LL; s15=0;
    s2  += s14*666643LL; s3  += s14*470296LL; s4  += s14*654183LL;
    s5  -= s14*997805LL; s6  += s14*136657LL; s7  -= s14*683901LL; s14=0;
    s1  += s13*666643LL; s2  += s13*470296LL; s3  += s13*654183LL;
    s4  -= s13*997805LL; s5  += s13*136657LL; s6  -= s13*683901LL; s13=0;
    s0  += s12*666643LL; s1  += s12*470296LL; s2  += s12*654183LL;
    s3  -= s12*997805LL; s4  += s12*136657LL; s5  -= s12*683901LL; s12=0;

    c0=(s0+(i64)(1<<20))>>21; s1+=c0;  s0-=c0*((i64)1<<21);
    c1=(s1+(i64)(1<<20))>>21; s2+=c1;  s1-=c1*((i64)1<<21);
    c2=(s2+(i64)(1<<20))>>21; s3+=c2;  s2-=c2*((i64)1<<21);
    c3=(s3+(i64)(1<<20))>>21; s4+=c3;  s3-=c3*((i64)1<<21);
    c4=(s4+(i64)(1<<20))>>21; s5+=c4;  s4-=c4*((i64)1<<21);
    c5=(s5+(i64)(1<<20))>>21; s6+=c5;  s5-=c5*((i64)1<<21);
    c6=(s6+(i64)(1<<20))>>21; s7+=c6;  s6-=c6*((i64)1<<21);
    c7=(s7+(i64)(1<<20))>>21; s8+=c7;  s7-=c7*((i64)1<<21);
    c8=(s8+(i64)(1<<20))>>21; s9+=c8;  s8-=c8*((i64)1<<21);
    c9=(s9+(i64)(1<<20))>>21; s10+=c9; s9-=c9*((i64)1<<21);
    c10=(s10+(i64)(1<<20))>>21; s11+=c10; s10-=c10*((i64)1<<21);
    c11=(s11+(i64)(1<<20))>>21; s12+=c11; s11-=c11*((i64)1<<21);

    s0  += s12*666643LL; s1  += s12*470296LL; s2  += s12*654183LL;
    s3  -= s12*997805LL; s4  += s12*136657LL; s5  -= s12*683901LL; s12=0;

    c0=(s0+(i64)(1<<20))>>21; s1+=c0;  s0-=c0*((i64)1<<21);
    c1=(s1+(i64)(1<<20))>>21; s2+=c1;  s1-=c1*((i64)1<<21);
    c2=(s2+(i64)(1<<20))>>21; s3+=c2;  s2-=c2*((i64)1<<21);
    c3=(s3+(i64)(1<<20))>>21; s4+=c3;  s3-=c3*((i64)1<<21);
    c4=(s4+(i64)(1<<20))>>21; s5+=c4;  s4-=c4*((i64)1<<21);
    c5=(s5+(i64)(1<<20))>>21; s6+=c5;  s5-=c5*((i64)1<<21);
    c6=(s6+(i64)(1<<20))>>21; s7+=c6;  s6-=c6*((i64)1<<21);
    c7=(s7+(i64)(1<<20))>>21; s8+=c7;  s7-=c7*((i64)1<<21);
    c8=(s8+(i64)(1<<20))>>21; s9+=c8;  s8-=c8*((i64)1<<21);
    c9=(s9+(i64)(1<<20))>>21; s10+=c9; s9-=c9*((i64)1<<21);
    c10=(s10+(i64)(1<<20))>>21; s11+=c10; s10-=c10*((i64)1<<21);

    /* If the carry-reduced value is negative (s11<0), add L to get canonical rep. */
    if (s11 < 0) {
        i64 ci;
        s0 += 1430509LL; s1 += 1626855LL; s2 += 1442968LL;
        s3 +=  997804LL; s4 += 1960495LL; s5 +=  683900LL;
        if(s0>=(i64)1<<21){s0-=(i64)1<<21;ci=1;}else if(s0<0){s0+=(i64)1<<21;ci=-1;}else ci=0; s1+=ci;
        if(s1>=(i64)1<<21){s1-=(i64)1<<21;ci=1;}else if(s1<0){s1+=(i64)1<<21;ci=-1;}else ci=0; s2+=ci;
        if(s2>=(i64)1<<21){s2-=(i64)1<<21;ci=1;}else if(s2<0){s2+=(i64)1<<21;ci=-1;}else ci=0; s3+=ci;
        if(s3>=(i64)1<<21){s3-=(i64)1<<21;ci=1;}else if(s3<0){s3+=(i64)1<<21;ci=-1;}else ci=0; s4+=ci;
        if(s4>=(i64)1<<21){s4-=(i64)1<<21;ci=1;}else if(s4<0){s4+=(i64)1<<21;ci=-1;}else ci=0; s5+=ci;
        if(s5>=(i64)1<<21){s5-=(i64)1<<21;ci=1;}else if(s5<0){s5+=(i64)1<<21;ci=-1;}else ci=0; s6+=ci;
        if(s6>=(i64)1<<21){s6-=(i64)1<<21;ci=1;}else if(s6<0){s6+=(i64)1<<21;ci=-1;}else ci=0; s7+=ci;
        if(s7>=(i64)1<<21){s7-=(i64)1<<21;ci=1;}else if(s7<0){s7+=(i64)1<<21;ci=-1;}else ci=0; s8+=ci;
        if(s8>=(i64)1<<21){s8-=(i64)1<<21;ci=1;}else if(s8<0){s8+=(i64)1<<21;ci=-1;}else ci=0; s9+=ci;
        if(s9>=(i64)1<<21){s9-=(i64)1<<21;ci=1;}else if(s9<0){s9+=(i64)1<<21;ci=-1;}else ci=0; s10+=ci;
        if(s10>=(i64)1<<21){s10-=(i64)1<<21;ci=1;}else if(s10<0){s10+=(i64)1<<21;ci=-1;}else ci=0; s11+=ci;
        if(s11 < 0) s11 += (i64)1<<21;
    }
    /* Borrow-normalize: ensure all limbs in [0,2^21) before packing.
     * After centered carries, limbs may be in [-2^20,2^20); arithmetic
     * right-shift by 21 gives -1 for negative limbs, 0 for non-negative. */
    c0 =s0 >>21; s1 +=c0;  s0 -=c0 *((i64)1<<21);
    c1 =s1 >>21; s2 +=c1;  s1 -=c1 *((i64)1<<21);
    c2 =s2 >>21; s3 +=c2;  s2 -=c2 *((i64)1<<21);
    c3 =s3 >>21; s4 +=c3;  s3 -=c3 *((i64)1<<21);
    c4 =s4 >>21; s5 +=c4;  s4 -=c4 *((i64)1<<21);
    c5 =s5 >>21; s6 +=c5;  s5 -=c5 *((i64)1<<21);
    c6 =s6 >>21; s7 +=c6;  s6 -=c6 *((i64)1<<21);
    c7 =s7 >>21; s8 +=c7;  s7 -=c7 *((i64)1<<21);
    c8 =s8 >>21; s9 +=c8;  s8 -=c8 *((i64)1<<21);
    c9 =s9 >>21; s10+=c9;  s9 -=c9 *((i64)1<<21);
    c10=s10>>21; s11+=c10; s10-=c10*((i64)1<<21);

    s[ 0]=(u8)(s0>> 0); s[ 1]=(u8)(s0>> 8); s[ 2]=(u8)((s0>>16)|(s1<<5));
    s[ 3]=(u8)(s1>> 3); s[ 4]=(u8)(s1>>11); s[ 5]=(u8)((s1>>19)|(s2<<2));
    s[ 6]=(u8)(s2>> 6); s[ 7]=(u8)((s2>>14)|(s3<<7));
    s[ 8]=(u8)(s3>> 1); s[ 9]=(u8)(s3>> 9); s[10]=(u8)((s3>>17)|(s4<<4));
    s[11]=(u8)(s4>> 4); s[12]=(u8)(s4>>12); s[13]=(u8)((s4>>20)|(s5<<1));
    s[14]=(u8)(s5>> 7); s[15]=(u8)((s5>>15)|(s6<<6));
    s[16]=(u8)(s6>> 2); s[17]=(u8)(s6>>10); s[18]=(u8)((s6>>18)|(s7<<3));
    s[19]=(u8)(s7>> 5); s[20]=(u8)(s7>>13);
    s[21]=(u8)(s8>> 0); s[22]=(u8)(s8>> 8); s[23]=(u8)((s8>>16)|(s9<<5));
    s[24]=(u8)(s9>> 3); s[25]=(u8)(s9>>11); s[26]=(u8)((s9>>19)|(s10<<2));
    s[27]=(u8)(s10>>6); s[28]=(u8)((s10>>14)|(s11<<7));
    s[29]=(u8)(s11>>1); s[30]=(u8)(s11>>9); s[31]=(u8)(s11>>17);
    { int j; for(j=32;j<64;j++) s[j]=0; }
}

/* sc_muladd: s = (a*b + c) mod L */
void sc_muladd(u8 s[32], const u8 a[32], const u8 b[32], const u8 c[32])
{
    i64 a0,a1,a2,a3,a4,a5,a6,a7,a8,a9,a10,a11;
    i64 b0,b1,b2,b3,b4,b5,b6,b7,b8,b9,b10,b11;
    i64 c0,c1,c2,c3,c4,c5,c6,c7,c8,c9,c10,c11;
    i64 s0,s1,s2,s3,s4,s5,s6,s7,s8,s9,s10,s11,
        s12,s13,s14,s15,s16,s17,s18,s19,s20,s21,s22,s23;
    i64 carry0,carry1,carry2,carry3,carry4,carry5,
        carry6,carry7,carry8,carry9,carry10,carry11,
        carry12,carry13,carry14,carry15,carry16,carry17,
        carry18,carry19,carry20,carry21,carry22;

    a0  = 2097151LL & ((i64)a[ 0]|((i64)a[ 1]<<8)|((i64)a[ 2]<<16));
    a1  = 2097151LL & (((i64)a[ 2]>>5)|((i64)a[ 3]<<3)|((i64)a[ 4]<<11)|((i64)a[ 5]<<19));
    a2  = 2097151LL & (((i64)a[ 5]>>2)|((i64)a[ 6]<<6)|((i64)a[ 7]<<14));
    a3  = 2097151LL & (((i64)a[ 7]>>7)|((i64)a[ 8]<<1)|((i64)a[ 9]<<9)|((i64)a[10]<<17));
    a4  = 2097151LL & (((i64)a[10]>>4)|((i64)a[11]<<4)|((i64)a[12]<<12)|((i64)a[13]<<20));
    a5  = 2097151LL & (((i64)a[13]>>1)|((i64)a[14]<<7)|((i64)a[15]<<15));
    a6  = 2097151LL & (((i64)a[15]>>6)|((i64)a[16]<<2)|((i64)a[17]<<10)|((i64)a[18]<<18));
    a7  = 2097151LL & (((i64)a[18]>>3)|((i64)a[19]<<5)|((i64)a[20]<<13));
    a8  = 2097151LL & ((i64)a[21]|((i64)a[22]<<8)|((i64)a[23]<<16));
    a9  = 2097151LL & (((i64)a[23]>>5)|((i64)a[24]<<3)|((i64)a[25]<<11)|((i64)a[26]<<19));
    a10 = 2097151LL & (((i64)a[26]>>2)|((i64)a[27]<<6)|((i64)a[28]<<14));
    a11 =              (((i64)a[28]>>7)|((i64)a[29]<<1)|((i64)a[30]<<9)|((i64)a[31]<<17));

    b0  = 2097151LL & ((i64)b[ 0]|((i64)b[ 1]<<8)|((i64)b[ 2]<<16));
    b1  = 2097151LL & (((i64)b[ 2]>>5)|((i64)b[ 3]<<3)|((i64)b[ 4]<<11)|((i64)b[ 5]<<19));
    b2  = 2097151LL & (((i64)b[ 5]>>2)|((i64)b[ 6]<<6)|((i64)b[ 7]<<14));
    b3  = 2097151LL & (((i64)b[ 7]>>7)|((i64)b[ 8]<<1)|((i64)b[ 9]<<9)|((i64)b[10]<<17));
    b4  = 2097151LL & (((i64)b[10]>>4)|((i64)b[11]<<4)|((i64)b[12]<<12)|((i64)b[13]<<20));
    b5  = 2097151LL & (((i64)b[13]>>1)|((i64)b[14]<<7)|((i64)b[15]<<15));
    b6  = 2097151LL & (((i64)b[15]>>6)|((i64)b[16]<<2)|((i64)b[17]<<10)|((i64)b[18]<<18));
    b7  = 2097151LL & (((i64)b[18]>>3)|((i64)b[19]<<5)|((i64)b[20]<<13));
    b8  = 2097151LL & ((i64)b[21]|((i64)b[22]<<8)|((i64)b[23]<<16));
    b9  = 2097151LL & (((i64)b[23]>>5)|((i64)b[24]<<3)|((i64)b[25]<<11)|((i64)b[26]<<19));
    b10 = 2097151LL & (((i64)b[26]>>2)|((i64)b[27]<<6)|((i64)b[28]<<14));
    b11 =              (((i64)b[28]>>7)|((i64)b[29]<<1)|((i64)b[30]<<9)|((i64)b[31]<<17));

    c0  = 2097151LL & ((i64)c[ 0]|((i64)c[ 1]<<8)|((i64)c[ 2]<<16));
    c1  = 2097151LL & (((i64)c[ 2]>>5)|((i64)c[ 3]<<3)|((i64)c[ 4]<<11)|((i64)c[ 5]<<19));
    c2  = 2097151LL & (((i64)c[ 5]>>2)|((i64)c[ 6]<<6)|((i64)c[ 7]<<14));
    c3  = 2097151LL & (((i64)c[ 7]>>7)|((i64)c[ 8]<<1)|((i64)c[ 9]<<9)|((i64)c[10]<<17));
    c4  = 2097151LL & (((i64)c[10]>>4)|((i64)c[11]<<4)|((i64)c[12]<<12)|((i64)c[13]<<20));
    c5  = 2097151LL & (((i64)c[13]>>1)|((i64)c[14]<<7)|((i64)c[15]<<15));
    c6  = 2097151LL & (((i64)c[15]>>6)|((i64)c[16]<<2)|((i64)c[17]<<10)|((i64)c[18]<<18));
    c7  = 2097151LL & (((i64)c[18]>>3)|((i64)c[19]<<5)|((i64)c[20]<<13));
    c8  = 2097151LL & ((i64)c[21]|((i64)c[22]<<8)|((i64)c[23]<<16));
    c9  = 2097151LL & (((i64)c[23]>>5)|((i64)c[24]<<3)|((i64)c[25]<<11)|((i64)c[26]<<19));
    c10 = 2097151LL & (((i64)c[26]>>2)|((i64)c[27]<<6)|((i64)c[28]<<14));
    c11 =              (((i64)c[28]>>7)|((i64)c[29]<<1)|((i64)c[30]<<9)|((i64)c[31]<<17));

    s0  = c0 +a0*b0;
    s1  = c1 +a0*b1 +a1*b0;
    s2  = c2 +a0*b2 +a1*b1 +a2*b0;
    s3  = c3 +a0*b3 +a1*b2 +a2*b1 +a3*b0;
    s4  = c4 +a0*b4 +a1*b3 +a2*b2 +a3*b1 +a4*b0;
    s5  = c5 +a0*b5 +a1*b4 +a2*b3 +a3*b2 +a4*b1 +a5*b0;
    s6  = c6 +a0*b6 +a1*b5 +a2*b4 +a3*b3 +a4*b2 +a5*b1 +a6*b0;
    s7  = c7 +a0*b7 +a1*b6 +a2*b5 +a3*b4 +a4*b3 +a5*b2 +a6*b1 +a7*b0;
    s8  = c8 +a0*b8 +a1*b7 +a2*b6 +a3*b5 +a4*b4 +a5*b3 +a6*b2 +a7*b1 +a8*b0;
    s9  = c9 +a0*b9 +a1*b8 +a2*b7 +a3*b6 +a4*b5 +a5*b4 +a6*b3 +a7*b2 +a8*b1 +a9*b0;
    s10 = c10+a0*b10+a1*b9 +a2*b8 +a3*b7 +a4*b6 +a5*b5 +a6*b4 +a7*b3 +a8*b2 +a9*b1+a10*b0;
    s11 = c11+a0*b11+a1*b10+a2*b9 +a3*b8 +a4*b7 +a5*b6 +a6*b5 +a7*b4 +a8*b3 +a9*b2+a10*b1+a11*b0;
    s12 =     a1*b11+a2*b10+a3*b9 +a4*b8 +a5*b7 +a6*b6 +a7*b5 +a8*b4 +a9*b3+a10*b2+a11*b1;
    s13 =     a2*b11+a3*b10+a4*b9 +a5*b8 +a6*b7 +a7*b6 +a8*b5 +a9*b4+a10*b3+a11*b2;
    s14 =     a3*b11+a4*b10+a5*b9 +a6*b8 +a7*b7 +a8*b6 +a9*b5+a10*b4+a11*b3;
    s15 =     a4*b11+a5*b10+a6*b9 +a7*b8 +a8*b7 +a9*b6+a10*b5+a11*b4;
    s16 =     a5*b11+a6*b10+a7*b9 +a8*b8 +a9*b7+a10*b6+a11*b5;
    s17 =     a6*b11+a7*b10+a8*b9 +a9*b8+a10*b7+a11*b6;
    s18 =     a7*b11+a8*b10+a9*b9+a10*b8+a11*b7;
    s19 =     a8*b11+a9*b10+a10*b9+a11*b8;
    s20 =     a9*b11+a10*b10+a11*b9;
    s21 =     a10*b11+a11*b10;
    s22 =     a11*b11;
    s23 = 0;

    carry0=(s0 +(i64)(1<<20))>>21; s1 +=carry0; s0 -=carry0*((i64)1<<21);
    carry0=(s1 +(i64)(1<<20))>>21; s2 +=carry0; s1 -=carry0*((i64)1<<21);
    carry0=(s2 +(i64)(1<<20))>>21; s3 +=carry0; s2 -=carry0*((i64)1<<21);
    carry0=(s3 +(i64)(1<<20))>>21; s4 +=carry0; s3 -=carry0*((i64)1<<21);
    carry0=(s4 +(i64)(1<<20))>>21; s5 +=carry0; s4 -=carry0*((i64)1<<21);
    carry0=(s5 +(i64)(1<<20))>>21; s6 +=carry0; s5 -=carry0*((i64)1<<21);
    carry0=(s6 +(i64)(1<<20))>>21; s7 +=carry0; s6 -=carry0*((i64)1<<21);
    carry0=(s7 +(i64)(1<<20))>>21; s8 +=carry0; s7 -=carry0*((i64)1<<21);
    carry0=(s8 +(i64)(1<<20))>>21; s9 +=carry0; s8 -=carry0*((i64)1<<21);
    carry0=(s9 +(i64)(1<<20))>>21; s10+=carry0; s9 -=carry0*((i64)1<<21);
    carry0=(s10+(i64)(1<<20))>>21; s11+=carry0; s10-=carry0*((i64)1<<21);
    carry0=(s11+(i64)(1<<20))>>21; s12+=carry0; s11-=carry0*((i64)1<<21);
    carry0=(s12+(i64)(1<<20))>>21; s13+=carry0; s12-=carry0*((i64)1<<21);
    carry0=(s13+(i64)(1<<20))>>21; s14+=carry0; s13-=carry0*((i64)1<<21);
    carry0=(s14+(i64)(1<<20))>>21; s15+=carry0; s14-=carry0*((i64)1<<21);
    carry0=(s15+(i64)(1<<20))>>21; s16+=carry0; s15-=carry0*((i64)1<<21);
    carry0=(s16+(i64)(1<<20))>>21; s17+=carry0; s16-=carry0*((i64)1<<21);
    carry0=(s17+(i64)(1<<20))>>21; s18+=carry0; s17-=carry0*((i64)1<<21);
    carry0=(s18+(i64)(1<<20))>>21; s19+=carry0; s18-=carry0*((i64)1<<21);
    carry0=(s19+(i64)(1<<20))>>21; s20+=carry0; s19-=carry0*((i64)1<<21);
    carry0=(s20+(i64)(1<<20))>>21; s21+=carry0; s20-=carry0*((i64)1<<21);
    carry0=(s21+(i64)(1<<20))>>21; s22+=carry0; s21-=carry0*((i64)1<<21);
    carry0=(s22+(i64)(1<<20))>>21; s23+=carry0; s22-=carry0*((i64)1<<21);

    s11+=s23*666643LL; s12+=s23*470296LL; s13+=s23*654183LL;
    s14-=s23*997805LL; s15+=s23*136657LL; s16-=s23*683901LL; s23=0;
    s10+=s22*666643LL; s11+=s22*470296LL; s12+=s22*654183LL;
    s13-=s22*997805LL; s14+=s22*136657LL; s15-=s22*683901LL; s22=0;
    s9 +=s21*666643LL; s10+=s21*470296LL; s11+=s21*654183LL;
    s12-=s21*997805LL; s13+=s21*136657LL; s14-=s21*683901LL; s21=0;
    s8 +=s20*666643LL; s9 +=s20*470296LL; s10+=s20*654183LL;
    s11-=s20*997805LL; s12+=s20*136657LL; s13-=s20*683901LL; s20=0;
    s7 +=s19*666643LL; s8 +=s19*470296LL; s9 +=s19*654183LL;
    s10-=s19*997805LL; s11+=s19*136657LL; s12-=s19*683901LL; s19=0;
    s6 +=s18*666643LL; s7 +=s18*470296LL; s8 +=s18*654183LL;
    s9 -=s18*997805LL; s10+=s18*136657LL; s11-=s18*683901LL; s18=0;
    s5 +=s17*666643LL; s6 +=s17*470296LL; s7 +=s17*654183LL;
    s8 -=s17*997805LL; s9 +=s17*136657LL; s10-=s17*683901LL; s17=0;
    s4 +=s16*666643LL; s5 +=s16*470296LL; s6 +=s16*654183LL;
    s7 -=s16*997805LL; s8 +=s16*136657LL; s9 -=s16*683901LL; s16=0;
    s3 +=s15*666643LL; s4 +=s15*470296LL; s5 +=s15*654183LL;
    s6 -=s15*997805LL; s7 +=s15*136657LL; s8 -=s15*683901LL; s15=0;
    s2 +=s14*666643LL; s3 +=s14*470296LL; s4 +=s14*654183LL;
    s5 -=s14*997805LL; s6 +=s14*136657LL; s7 -=s14*683901LL; s14=0;
    s1 +=s13*666643LL; s2 +=s13*470296LL; s3 +=s13*654183LL;
    s4 -=s13*997805LL; s5 +=s13*136657LL; s6 -=s13*683901LL; s13=0;
    s0 +=s12*666643LL; s1 +=s12*470296LL; s2 +=s12*654183LL;
    s3 -=s12*997805LL; s4 +=s12*136657LL; s5 -=s12*683901LL; s12=0;

    carry0 =(s0 +(i64)(1<<20))>>21; s1 +=carry0;  s0 -=carry0 *((i64)1<<21);
    carry1 =(s1 +(i64)(1<<20))>>21; s2 +=carry1;  s1 -=carry1 *((i64)1<<21);
    carry2 =(s2 +(i64)(1<<20))>>21; s3 +=carry2;  s2 -=carry2 *((i64)1<<21);
    carry3 =(s3 +(i64)(1<<20))>>21; s4 +=carry3;  s3 -=carry3 *((i64)1<<21);
    carry4 =(s4 +(i64)(1<<20))>>21; s5 +=carry4;  s4 -=carry4 *((i64)1<<21);
    carry5 =(s5 +(i64)(1<<20))>>21; s6 +=carry5;  s5 -=carry5 *((i64)1<<21);
    carry6 =(s6 +(i64)(1<<20))>>21; s7 +=carry6;  s6 -=carry6 *((i64)1<<21);
    carry7 =(s7 +(i64)(1<<20))>>21; s8 +=carry7;  s7 -=carry7 *((i64)1<<21);
    carry8 =(s8 +(i64)(1<<20))>>21; s9 +=carry8;  s8 -=carry8 *((i64)1<<21);
    carry9 =(s9 +(i64)(1<<20))>>21; s10+=carry9;  s9 -=carry9 *((i64)1<<21);
    carry10=(s10+(i64)(1<<20))>>21; s11+=carry10; s10-=carry10*((i64)1<<21);
    carry11=(s11+(i64)(1<<20))>>21; s12+=carry11; s11-=carry11*((i64)1<<21);

    s0 +=s12*666643LL; s1 +=s12*470296LL; s2 +=s12*654183LL;
    s3 -=s12*997805LL; s4 +=s12*136657LL; s5 -=s12*683901LL; s12=0;

    carry0 =(s0 +(i64)(1<<20))>>21; s1 +=carry0;  s0 -=carry0 *((i64)1<<21);
    carry1 =(s1 +(i64)(1<<20))>>21; s2 +=carry1;  s1 -=carry1 *((i64)1<<21);
    carry2 =(s2 +(i64)(1<<20))>>21; s3 +=carry2;  s2 -=carry2 *((i64)1<<21);
    carry3 =(s3 +(i64)(1<<20))>>21; s4 +=carry3;  s3 -=carry3 *((i64)1<<21);
    carry4 =(s4 +(i64)(1<<20))>>21; s5 +=carry4;  s4 -=carry4 *((i64)1<<21);
    carry5 =(s5 +(i64)(1<<20))>>21; s6 +=carry5;  s5 -=carry5 *((i64)1<<21);
    carry6 =(s6 +(i64)(1<<20))>>21; s7 +=carry6;  s6 -=carry6 *((i64)1<<21);
    carry7 =(s7 +(i64)(1<<20))>>21; s8 +=carry7;  s7 -=carry7 *((i64)1<<21);
    carry8 =(s8 +(i64)(1<<20))>>21; s9 +=carry8;  s8 -=carry8 *((i64)1<<21);
    carry9 =(s9 +(i64)(1<<20))>>21; s10+=carry9;  s9 -=carry9 *((i64)1<<21);
    carry10=(s10+(i64)(1<<20))>>21; s11+=carry10; s10-=carry10*((i64)1<<21);

    /* If the carry-reduced value is negative (s11<0), add L to get canonical rep. */
    if (s11 < 0) {
        i64 ci;
        s0 += 1430509LL; s1 += 1626855LL; s2 += 1442968LL;
        s3 +=  997804LL; s4 += 1960495LL; s5 +=  683900LL;
        if(s0>=(i64)1<<21){s0-=(i64)1<<21;ci=1;}else if(s0<0){s0+=(i64)1<<21;ci=-1;}else ci=0; s1+=ci;
        if(s1>=(i64)1<<21){s1-=(i64)1<<21;ci=1;}else if(s1<0){s1+=(i64)1<<21;ci=-1;}else ci=0; s2+=ci;
        if(s2>=(i64)1<<21){s2-=(i64)1<<21;ci=1;}else if(s2<0){s2+=(i64)1<<21;ci=-1;}else ci=0; s3+=ci;
        if(s3>=(i64)1<<21){s3-=(i64)1<<21;ci=1;}else if(s3<0){s3+=(i64)1<<21;ci=-1;}else ci=0; s4+=ci;
        if(s4>=(i64)1<<21){s4-=(i64)1<<21;ci=1;}else if(s4<0){s4+=(i64)1<<21;ci=-1;}else ci=0; s5+=ci;
        if(s5>=(i64)1<<21){s5-=(i64)1<<21;ci=1;}else if(s5<0){s5+=(i64)1<<21;ci=-1;}else ci=0; s6+=ci;
        if(s6>=(i64)1<<21){s6-=(i64)1<<21;ci=1;}else if(s6<0){s6+=(i64)1<<21;ci=-1;}else ci=0; s7+=ci;
        if(s7>=(i64)1<<21){s7-=(i64)1<<21;ci=1;}else if(s7<0){s7+=(i64)1<<21;ci=-1;}else ci=0; s8+=ci;
        if(s8>=(i64)1<<21){s8-=(i64)1<<21;ci=1;}else if(s8<0){s8+=(i64)1<<21;ci=-1;}else ci=0; s9+=ci;
        if(s9>=(i64)1<<21){s9-=(i64)1<<21;ci=1;}else if(s9<0){s9+=(i64)1<<21;ci=-1;}else ci=0; s10+=ci;
        if(s10>=(i64)1<<21){s10-=(i64)1<<21;ci=1;}else if(s10<0){s10+=(i64)1<<21;ci=-1;}else ci=0; s11+=ci;
        if(s11 < 0) s11 += (i64)1<<21;
    }
    /* Borrow-normalize: ensure all limbs in [0,2^21) before packing. */
    carry0 =s0 >>21; s1 +=carry0;  s0 -=carry0 *((i64)1<<21);
    carry1 =s1 >>21; s2 +=carry1;  s1 -=carry1 *((i64)1<<21);
    carry2 =s2 >>21; s3 +=carry2;  s2 -=carry2 *((i64)1<<21);
    carry3 =s3 >>21; s4 +=carry3;  s3 -=carry3 *((i64)1<<21);
    carry4 =s4 >>21; s5 +=carry4;  s4 -=carry4 *((i64)1<<21);
    carry5 =s5 >>21; s6 +=carry5;  s5 -=carry5 *((i64)1<<21);
    carry6 =s6 >>21; s7 +=carry6;  s6 -=carry6 *((i64)1<<21);
    carry7 =s7 >>21; s8 +=carry7;  s7 -=carry7 *((i64)1<<21);
    carry8 =s8 >>21; s9 +=carry8;  s8 -=carry8 *((i64)1<<21);
    carry9 =s9 >>21; s10+=carry9;  s9 -=carry9 *((i64)1<<21);
    carry10=s10>>21; s11+=carry10; s10-=carry10*((i64)1<<21);

    s[ 0]=(u8)(s0>> 0); s[ 1]=(u8)(s0>> 8); s[ 2]=(u8)((s0>>16)|(s1<<5));
    s[ 3]=(u8)(s1>> 3); s[ 4]=(u8)(s1>>11); s[ 5]=(u8)((s1>>19)|(s2<<2));
    s[ 6]=(u8)(s2>> 6); s[ 7]=(u8)((s2>>14)|(s3<<7));
    s[ 8]=(u8)(s3>> 1); s[ 9]=(u8)(s3>> 9); s[10]=(u8)((s3>>17)|(s4<<4));
    s[11]=(u8)(s4>> 4); s[12]=(u8)(s4>>12); s[13]=(u8)((s4>>20)|(s5<<1));
    s[14]=(u8)(s5>> 7); s[15]=(u8)((s5>>15)|(s6<<6));
    s[16]=(u8)(s6>> 2); s[17]=(u8)(s6>>10); s[18]=(u8)((s6>>18)|(s7<<3));
    s[19]=(u8)(s7>> 5); s[20]=(u8)(s7>>13);
    s[21]=(u8)(s8>> 0); s[22]=(u8)(s8>> 8); s[23]=(u8)((s8>>16)|(s9<<5));
    s[24]=(u8)(s9>> 3); s[25]=(u8)(s9>>11); s[26]=(u8)((s9>>19)|(s10<<2));
    s[27]=(u8)(s10>>6); s[28]=(u8)((s10>>14)|(s11<<7));
    s[29]=(u8)(s11>>1); s[30]=(u8)(s11>>9); s[31]=(u8)(s11>>17);
}

/* -- Helpers ---------------------------------------------------------------- */

static void ed_memcpy(u8 *dst, const u8 *src, u32 n)
{ u32 i; for(i=0;i<n;i++) dst[i]=src[i]; }

/* -- Public API ------------------------------------------------------------- */

void ed25519_keypair(u8 public_key[32], u8 private_key[64], const u8 seed[32])
{
    u8 h[64];
    ge_p3 A;
    sha512(seed, 32, h);
    h[0]  &= 248;
    h[31] &= 127;
    h[31] |= 64;
    ge_scalarmult_base(&A, h);
    ge_p3_tobytes(public_key, &A);
    ed_memcpy(private_key,      seed,       32);
    ed_memcpy(private_key + 32, public_key, 32);
}

void ed25519_sign(u8 sig[64], const u8 *msg, u32 msg_len,
                  const u8 private_key[64])
{
    sha512_ctx ctx;
    u8 h[64], nonce[64], k_hash[64], R_bytes[32], S[32];
    ge_p3 R;
    const u8 *public_key = private_key + 32;

    /* Expand seed */
    sha512(private_key, 32, h);
    h[0] &= 248; h[31] &= 127; h[31] |= 64;

    /* r = SHA-512(h[32..63] || msg) mod L */
    sha512_init(&ctx);
    sha512_update(&ctx, h+32, 32);
    sha512_update(&ctx, msg, msg_len);
    sha512_final(&ctx, nonce);
    sc_reduce(nonce);

    /* R = r*B */
    ge_scalarmult_base(&R, nonce);
    ge_p3_tobytes(R_bytes, &R);

    /* k = SHA-512(R || A || msg) mod L */
    sha512_init(&ctx);
    sha512_update(&ctx, R_bytes, 32);
    sha512_update(&ctx, public_key, 32);
    sha512_update(&ctx, msg, msg_len);
    sha512_final(&ctx, k_hash);
    ed_memcpy(sig, k_hash, 64);
    sc_reduce(sig);  /* sig[0..31] = k */

    /* S = (r + k*a) mod L */
    sc_muladd(S, sig, h, nonce);

    ed_memcpy(sig,      R_bytes, 32);
    ed_memcpy(sig + 32, S,       32);
}

int ed25519_verify(const u8 sig[64], const u8 *msg, u32 msg_len,
                   const u8 public_key[32])
{
    sha512_ctx ctx;
    u8 k_hash[64], k[64], check_bytes[32];
    ge_p3 A, R_check, kA;
    ge_cached kAc;
    int i;
    const u8 *R_bytes = sig;
    const u8 *S_bytes = sig + 32;

    if (S_bytes[31] & 0xe0) return 0;

    if (ge_frombytes_vartime(&A, public_key) != 0) return 0;

    /* k = SHA-512(R || A || msg) mod L */
    sha512_init(&ctx);
    sha512_update(&ctx, R_bytes, 32);
    sha512_update(&ctx, public_key, 32);
    sha512_update(&ctx, msg, msg_len);
    sha512_final(&ctx, k_hash);
    ed_memcpy(k, k_hash, 64);
    sc_reduce(k);

    /* Negate A for: [S]*B - [k]*A */
    fe_neg(A.X, A.X);
    fe_neg(A.T, A.T);

    /* R_check = [S]*B */
    ge_scalarmult_base(&R_check, S_bytes);

    /* Add [k]*(-A) */
    ge_scalarmult(&kA, k, &A);
    ge_p3_to_cached(&kAc, &kA);
    ge_add(&R_check, &R_check, &kAc);

    ge_p3_tobytes(check_bytes, &R_check);

    { u32 diff=0; for(i=0;i<32;i++) diff|=(u32)(check_bytes[i]^R_bytes[i]);
      return (diff==0)?1:0; }
}


