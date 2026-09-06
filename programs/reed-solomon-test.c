/* **************************************************************************
 *             RISC-V Emulator - Reed-Solomon ECC over GF(2^8)
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

// reed-solomon-test.c -- Reed-Solomon ECC over GF(2^8)
//
// Systematic RS(N,K) encoder and syndrome-based error detection.
// Field: GF(2^8) with AES polynomial 0x11B (same as AES MixColumns).
// Generator polynomial: g(x) = product of (x - alpha^i) for i=1..2t,
//   where alpha = 2 (the field generator), t = number of correctable errors.
//
// Parameters tested:
//   RS(7,3): N=7, K=3, 2t=4 parity symbols (corrects 2 errors)
//   RS(15,9): N=15, K=9, 2t=6 parity symbols (corrects 3 errors)
//
// Tests:
//   GF arithmetic:
//     - gf_add (XOR)
//     - gf_mul (shift-XOR with poly 0x11B)
//     - gf_pow (alpha^i)
//     - gf_inv (multiplicative inverse via a^254)
//   RS(7,3) encoding:
//     - Systematic encoding produces correct parity
//     - All-zero message -> all-zero codeword
//     - Known-good codeword passes syndrome check (all syndromes=0)
//   RS syndrome computation:
//     - Uncorrupted codeword -> syndromes all zero
//     - Single-symbol error -> non-zero syndromes
//
// Build: cd programs && make run-reed-solomon-test
// By Ulrik Hørlyk Hjort 2026

#include <stdint.h>
#include "log.h"

static int g_pass = 0, g_fail = 0;

static void chku(const char *lbl, uint32_t got, uint32_t exp)
{
    if (got == exp) {
        log_write(NONE, "  PASS  %s\n", lbl);
        g_pass++;
    } else {
        log_write(NONE, "  FAIL  %s: got 0x%x  exp 0x%x\n", lbl,
                  (unsigned)got, (unsigned)exp);
        g_fail++;
    }
}

static void chk_bool(const char *lbl, int ok)
{
    if (ok) { log_write(NONE, "  PASS  %s\n", lbl); g_pass++; }
    else    { log_write(NONE, "  FAIL  %s\n", lbl); g_fail++; }
}

/* ===========================================================================
 * GF(2^8) arithmetic -- AES polynomial 0x11B
 * =========================================================================== */

#define GF_POLY 0x11Bu

static uint8_t gf_add(uint8_t a, uint8_t b) { return a ^ b; }

static uint8_t gf_mul(uint8_t a, uint8_t b)
{
    uint8_t p = 0;
    for (int i = 0; i < 8; i++) {
        if (b & 1u) p ^= a;
        uint8_t hi = a & 0x80u;
        a <<= 1;
        if (hi) a ^= (uint8_t)(GF_POLY & 0xFF);
        b >>= 1;
    }
    return p;
}

/* alpha^n where alpha = 0x02 (primitive element) */
static uint8_t gf_pow(uint8_t base, uint8_t exp)
{
    uint8_t result = 1u;
    while (exp--) result = gf_mul(result, base);
    return result;
}

/* Multiplicative inverse: a^254 (Fermat in GF(2^8)) */
static uint8_t gf_inv(uint8_t a)
{
    if (a == 0u) return 0u;
    /* a^254 = a^(2^8-2) via square-and-multiply */
    uint8_t x   = a;
    uint8_t acc = 1u;
    int     e   = 254;
    while (e) {
        if (e & 1) acc = gf_mul(acc, x);
        x = gf_mul(x, x);
        e >>= 1;
    }
    return acc;
}

/* Evaluate polynomial p[0..deg] at point x (p[0] is highest degree) */
static uint8_t poly_eval(const uint8_t *p, int deg, uint8_t x)
{
    uint8_t r = 0u;
    for (int i = 0; i <= deg; i++)
        r = gf_add(gf_mul(r, x), p[i]);
    return r;
}

/* ===========================================================================
 * Reed-Solomon systematic encoder
 *
 * Systematic codeword: [message | parity]
 * Parity = remainder of (message * x^(2t)) divided by generator g(x).
 *
 * g(x) = (x + alpha^1)(x + alpha^2)...(x + alpha^(2t))
 *
 * We store generator as g[0..2t] with g[0]=1 (leading coefficient).
 * =========================================================================== */

/* Build generator polynomial: g(x) = prod_{i=1}^{2t} (x + alpha^i)
 * g[] has 2t+1 coefficients; g[0]=1 (highest degree). */
static void rs_gen_poly(uint8_t *g, int t2)  /* t2 = 2*t */
{
    g[0] = 1u;
    for (int i = 0; i <= t2; i++) g[i+1] = 0u;  /* zero out */
    for (int i = 1; i <= t2; i++) {
        /* multiply g by (x + alpha^i): shift and XOR */
        uint8_t root = gf_pow(2u, (uint8_t)i);
        for (int j = i; j >= 1; j--)
            g[j] = gf_add(g[j], gf_mul(g[j-1], root));
        g[0] = g[0];  /* leading coefficient stays 1 */
    }
}

/* Systematic encode: codeword[0..N-1] = [msg[0..K-1] | parity[0..2t-1]]
 * codeword must be N = K + 2t bytes. */
static void rs_encode(const uint8_t *msg, int K, int t2,
                      const uint8_t *g, uint8_t *cw)
{
    int N = K + t2;

    /* Copy message into high part */
    for (int i = 0; i < K;  i++) cw[i]   = msg[i];
    for (int i = 0; i < t2; i++) cw[K+i] = 0u;    /* parity area */

    /* Polynomial long division: divide msg*x^t2 by g, keep remainder */
    for (int i = 0; i < K; i++) {
        uint8_t coef = cw[i];
        if (coef != 0u) {
            for (int j = 1; j <= t2; j++)
                cw[i + j] ^= gf_mul(g[j], coef);
        }
    }

    /* Restore message bytes (they get modified by the division loop) */
    for (int i = 0; i < K; i++) cw[i] = msg[i];
    (void)N;
}

/* Compute 2t syndromes S[i] = cw(alpha^(i+1)) for i=0..2t-1 */
static void rs_syndromes(const uint8_t *cw, int N, int t2, uint8_t *S)
{
    for (int i = 0; i < t2; i++) {
        uint8_t root = gf_pow(2u, (uint8_t)(i+1));
        S[i] = poly_eval(cw, N-1, root);
    }
}

/* ===========================================================================
 * Tests
 * =========================================================================== */

static void test_gf_basic(void)
{
    log_write(NONE, "\n-- GF(2^8) basic arithmetic --\n");

    /* add = XOR */
    chku("gf_add(0x53,0xCA) = 0x99", gf_add(0x53u, 0xCAu), 0x99u);
    chku("gf_add(0x00,0xFF) = 0xFF", gf_add(0x00u, 0xFFu), 0xFFu);
    chku("gf_add(0xAB,0xAB) = 0x00", gf_add(0xABu, 0xABu), 0x00u);

    /* mul: FIPS 197 Sec.4.2 example: {57} * {83} = {C1} */
    chku("gf_mul(0x57,0x83) = 0xC1", gf_mul(0x57u, 0x83u), 0xC1u);
    chku("gf_mul(0x02,0x80) = 0x1B", gf_mul(0x02u, 0x80u), 0x1Bu); /* xtime(0x80) */
    chku("gf_mul(0x00,0xFF) = 0x00", gf_mul(0x00u, 0xFFu), 0x00u);
    chku("gf_mul(0x01,0x42) = 0x42", gf_mul(0x01u, 0x42u), 0x42u);
    chku("gf_mul commutativity",     gf_mul(0x53u, 0xCAu), gf_mul(0xCAu, 0x53u));

    /* pow: alpha^0=1, alpha^1=2, alpha^7=? */
    chku("gf_pow(2,0) = 1", gf_pow(2u, 0u), 1u);
    chku("gf_pow(2,1) = 2", gf_pow(2u, 1u), 2u);
    chku("gf_pow(2,8) = 0x1B", gf_pow(2u, 8u), 0x1Bu);  /* 2^8 mod 0x11B = 0x1B */
    /* alpha has order 255: alpha^255 = 1 */
    chku("gf_pow(2,255) = 1", gf_pow(2u, 255u), 1u);

    /* inv: a * inv(a) = 1 */
    chku("gf_mul(0x53,inv(0x53)) = 1",
         gf_mul(0x53u, gf_inv(0x53u)), 1u);
    chku("gf_mul(0xCAu,inv(0xCA)) = 1",
         gf_mul(0xCAu, gf_inv(0xCAu)), 1u);
    chku("gf_inv(0x01) = 0x01",  gf_inv(0x01u), 0x01u);
    chku("gf_inv(0x00) = 0x00",  gf_inv(0x00u), 0x00u); /* by convention */
}

static void test_rs_7_3(void)
{
    log_write(NONE, "\n-- RS(7,3): K=3 message, 2t=4 parity, N=7 --\n");
    /* Generator: g(x) = (x+a)(x+a^2)(x+a^3)(x+a^4)
     * where a = alpha = 2 */
    uint8_t g[5]; /* degree 4, 5 coefficients */
    rs_gen_poly(g, 4);

    /* Known generator for this RS code:
     * (x+2)(x+4)(x+8)(x+16):
     * (x+2)(x+4) = x^2 + 6x + 8
     * (x+8)(x+16)= x^2 + 24x + 128
     * (x^2+6x+8)(x^2+24x+128):
     *   x^4 + 24x^3 + 128x^2
     *      + 6x^3  + 144x^2 + 768x
     *              + 8x^2   + 192x + 1024
     * But we need GF arithmetic, so let me just verify structure. */

    /* All-zero message -> all-zero codeword */
    uint8_t msg0[3] = {0, 0, 0};
    uint8_t cw0[7];
    rs_encode(msg0, 3, 4, g, cw0);
    int all_zero = 1;
    for (int i = 0; i < 7; i++) if (cw0[i] != 0) all_zero = 0;
    chk_bool("RS(7,3) zero message -> zero codeword", all_zero);

    /* Encode known message {1, 0, 0} and verify syndromes = 0 */
    uint8_t msg1[3] = {1, 0, 0};
    uint8_t cw1[7];
    rs_encode(msg1, 3, 4, g, cw1);
    uint8_t S[4];
    rs_syndromes(cw1, 7, 4, S);
    int syn_ok = (S[0]==0 && S[1]==0 && S[2]==0 && S[3]==0);
    chk_bool("RS(7,3) encode {1,0,0}: syndromes all zero", syn_ok);

    /* Encode {0, 1, 0} */
    uint8_t msg2[3] = {0, 1, 0};
    uint8_t cw2[7];
    rs_encode(msg2, 3, 4, g, cw2);
    rs_syndromes(cw2, 7, 4, S);
    syn_ok = (S[0]==0 && S[1]==0 && S[2]==0 && S[3]==0);
    chk_bool("RS(7,3) encode {0,1,0}: syndromes all zero", syn_ok);

    /* Encode {0x12, 0x34, 0x56} */
    uint8_t msg3[3] = {0x12, 0x34, 0x56};
    uint8_t cw3[7];
    rs_encode(msg3, 3, 4, g, cw3);
    rs_syndromes(cw3, 7, 4, S);
    syn_ok = (S[0]==0 && S[1]==0 && S[2]==0 && S[3]==0);
    chk_bool("RS(7,3) encode {0x12,0x34,0x56}: syndromes all zero", syn_ok);

    /* Corrupt one byte -> at least one syndrome != 0 */
    uint8_t cw3_bad[7];
    for (int i = 0; i < 7; i++) cw3_bad[i] = cw3[i];
    cw3_bad[2] ^= 0x01u;  /* flip bit in position 2 */
    rs_syndromes(cw3_bad, 7, 4, S);
    int any_nonzero = (S[0]!=0 || S[1]!=0 || S[2]!=0 || S[3]!=0);
    chk_bool("RS(7,3) single error -> non-zero syndrome", any_nonzero);

    /* Corrupt in parity area */
    uint8_t cw3_bad2[7];
    for (int i = 0; i < 7; i++) cw3_bad2[i] = cw3[i];
    cw3_bad2[5] ^= 0x80u;
    rs_syndromes(cw3_bad2, 7, 4, S);
    any_nonzero = (S[0]!=0 || S[1]!=0 || S[2]!=0 || S[3]!=0);
    chk_bool("RS(7,3) parity error -> non-zero syndrome", any_nonzero);

    /* Verify message is preserved in systematic form */
    chku("RS(7,3) cw[0] = msg[0]", cw3[0], 0x12u);
    chku("RS(7,3) cw[1] = msg[1]", cw3[1], 0x34u);
    chku("RS(7,3) cw[2] = msg[2]", cw3[2], 0x56u);
}

static void test_rs_15_9(void)
{
    log_write(NONE, "\n-- RS(15,9): K=9 message, 2t=6 parity, N=15 --\n");
    uint8_t g[7];  /* degree 6, 7 coefficients */
    rs_gen_poly(g, 6);

    /* All-zero -> all-zero */
    uint8_t msg0[9] = {0};
    uint8_t cw0[15];
    rs_encode(msg0, 9, 6, g, cw0);
    int all_zero = 1;
    for (int i = 0; i < 15; i++) if (cw0[i]) all_zero = 0;
    chk_bool("RS(15,9) zero message -> zero codeword", all_zero);

    /* Encode and check syndromes */
    uint8_t msg1[9] = {0xAA,0xBB,0xCC,0xDD,0xEE,0xFF,0x11,0x22,0x33};
    uint8_t cw1[15];
    rs_encode(msg1, 9, 6, g, cw1);
    uint8_t S[6];
    rs_syndromes(cw1, 15, 6, S);
    int syn_ok = 1;
    for (int i = 0; i < 6; i++) if (S[i]) syn_ok = 0;
    chk_bool("RS(15,9) encode: syndromes all zero", syn_ok);

    /* Message preserved */
    int msg_ok = 1;
    for (int i = 0; i < 9; i++) if (cw1[i] != msg1[i]) msg_ok = 0;
    chk_bool("RS(15,9) message bytes preserved", msg_ok);

    /* Two errors -> syndromes non-zero */
    cw1[3] ^= 0x07u;
    cw1[11] ^= 0xE0u;
    rs_syndromes(cw1, 15, 6, S);
    int any_nz = 0;
    for (int i = 0; i < 6; i++) if (S[i]) any_nz = 1;
    chk_bool("RS(15,9) two errors -> non-zero syndromes", any_nz);

    /* Linearity: encode(a XOR b) = encode(a) XOR encode(b) */
    uint8_t msg2[9] = {0x01,0x02,0x03,0x04,0x05,0x06,0x07,0x08,0x09};
    uint8_t msg3[9] = {0x10,0x20,0x30,0x40,0x50,0x60,0x70,0x80,0x90};
    uint8_t msgx[9];
    for (int i = 0; i < 9; i++) msgx[i] = msg2[i] ^ msg3[i];

    uint8_t cw2[15], cw3[15], cwx[15];
    rs_encode(msg2, 9, 6, g, cw2);
    rs_encode(msg3, 9, 6, g, cw3);
    rs_encode(msgx, 9, 6, g, cwx);

    int lin_ok = 1;
    for (int i = 0; i < 15; i++)
        if (cwx[i] != (cw2[i] ^ cw3[i])) lin_ok = 0;
    chk_bool("RS(15,9) linearity: encode(a^b) == encode(a)^encode(b)", lin_ok);
}

static void test_poly_eval(void)
{
    log_write(NONE, "\n-- Polynomial evaluation in GF(2^8) --\n");
    /* p(x) = x^2 + x + 1 evaluated at alpha: p[0]=1, p[1]=1, p[2]=1 */
    uint8_t p3[3] = {1, 1, 1};  /* coefficients high-to-low */
    /* p(2) = 4 + 2 + 1 = 7 (in GF, + is XOR: 4^2^1 = 7) */
    chku("p(x)=x^2+x+1 at x=2: 4^2^1 = 7", poly_eval(p3, 2, 2u), 7u);
    /* p(0) = 0 + 0 + 1 = 1 */
    chku("p(x)=x^2+x+1 at x=0: = 1",        poly_eval(p3, 2, 0u), 1u);
    /* p(1) = 1 + 1 + 1 = 1 (in GF, 1^1^1=1) */
    chku("p(x)=x^2+x+1 at x=1: 1^1^1 = 1",  poly_eval(p3, 2, 1u), 1u);
    /* Constant polynomial p(x) = 5 */
    uint8_t pc[1] = {5};
    chku("p(x)=5 at x=42: = 5",              poly_eval(pc, 0, 42u), 5u);
}

/* -- main ------------------------------------------------------------------- */
int main(void)
{
    log_init("reed-solomon-test.log");
    log_write(NONE, "=== Reed-Solomon ECC Test (GF(2^8)) ===\n");

    test_gf_basic();
    test_poly_eval();
    test_rs_7_3();
    test_rs_15_9();

    log_write(NONE, "\n=== Result: %d PASS  %d FAIL ===\n", g_pass, g_fail);
    log_close();
    return g_fail;
}
