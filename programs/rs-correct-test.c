/* **************************************************************************
 *       RISC-V Emulator - Reed-Solomon error correction over GF(2^8)
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

// rs-correct-test.c -- Reed-Solomon error correction over GF(2^8)
//
// Extends reed-solomon-test.c with full error correction:
//   Berlekamp-Massey  -> error locator polynomial Lambda(x)
//   Chien search      -> error locations (roots of Lambda)
//   Forney algorithm  -> error magnitudes
//
// Parameters:
//   GF(2^8) with AES polynomial p(x) = x^8 + x^4 + x^3 + x + 1 (0x11B)
//   Primitive element: alpha = 2 = 0x02
//   Code: RS(15, 9) -- 15-byte codeword, 9 data bytes, 6 parity bytes (t=3)
//   Can correct up to t=3 symbol errors.
//
//   RS(7, 3) -- 7-byte codeword, 3 data bytes, 4 parity bytes (t=2)
//   Can correct up to t=2 symbol errors.
//
// Algorithms:
//   Encoding: systematic polynomial long division (same as reed-solomon-test.c)
//   Syndrome: S[i] = received(alpha^(i+1)) for i=0..2t-1
//   BM: iterative linear recurrence solver for Lambda(x) from syndromes
//   Chien: evaluate Lambda(alpha^-j) for j=0..n-1, root -> error at position j
//   Forney: e[j] = -(X_j * Ohm(X_j^-1)) / Lambda'(X_j) where Ohm = syndrome poly mod Lambda
//
// Tests:
//   RS(7,3) t=2: 1-error and 2-error correction, 0-error passthrough
//   RS(15,9) t=3: 1,2,3-error correction
//   Error at first/last byte, multiple positions
//   Wrong magnitude detection (Forney gives right correction value)
//   Decoder returns error count; 0 means no errors detected
//   Uncorrectable: 3 errors on t=2 code -> detected but not corrected
//
// Build: cd programs && make run-rs-correct-test
// By Ulrik Hørlyk Hjort 2026

#include <stdint.h>
#include "log.h"

#define GF_POLY  0x11Du    /* x^8 + x^4 + x^3 + x^2 + 1 */
#define GF_SIZE  256

static int g_pass = 0, g_fail = 0;

/* -- GF(2^8) tables --------------------------------------------------------- */

static uint8_t gf_exp[512];  /* alpha^i, extended for negative indices */
static uint8_t gf_log[256];  /* discrete log: gf_log[alpha^i] = i */

static void gf_init(void)
{
    uint32_t x = 1u;
    for (int i = 0; i < 255; i++) {
        gf_exp[i] = (uint8_t)x;
        gf_log[x] = (uint8_t)i;
        x <<= 1;
        if (x & 0x100u) x ^= GF_POLY;
    }
    gf_exp[255] = gf_exp[0];  /* alpha^255 = alpha^0 = 1 */
    for (int i = 256; i < 512; i++)
        gf_exp[i] = gf_exp[i - 255];
    gf_log[0] = 0;  /* log(0) undefined; 0 by convention */
}

static uint8_t gf_mul(uint8_t a, uint8_t b)
{
    if (a == 0u || b == 0u) return 0u;
    return gf_exp[(int)gf_log[a] + (int)gf_log[b]];
}

static uint8_t gf_div(uint8_t a, uint8_t b)
{
    if (a == 0u) return 0u;
    /* a/b = alpha^(log(a) - log(b)) */
    return gf_exp[(255 + (int)gf_log[a] - (int)gf_log[b]) % 255];
}

static uint8_t gf_inv(uint8_t a)
{
    return gf_exp[255 - (int)gf_log[a]];  /* alpha^(-log(a)) = alpha^(255-log(a)) */
}

/* GF polynomial evaluation via Horner: p(x) = p[0] + p[1]*x + ... */
static uint8_t gf_poly_eval(const uint8_t *p, int deg, uint8_t x)
{
    uint8_t y = 0u;
    for (int i = deg; i >= 0; i--)
        y = gf_mul(y, x) ^ p[i];
    return y;
}

/* -- RS encoding ------------------------------------------------------------ */

/* Generator polynomial g(x) = product_{i=1}^{2t} (x + alpha^i)
 * Stored as coefficients g[0]..g[2t] with g[2t]=1. */
/* g[0]=1 is the leading (x^t2) coefficient; g[t2] is the constant term.
 * This matches the LFSR encoding convention: g[j] for j=1..t2 are the
 * lower-degree feedback coefficients. */
static void rs_build_generator(uint8_t *g, int t2)
{
    g[0] = 1u;
    for (int i = 1; i <= t2; i++) g[i] = 0u;
    for (int i = 1; i <= t2; i++) {
        uint8_t root = gf_exp[i];   /* alpha^i */
        for (int j = i; j >= 1; j--)
            g[j] ^= gf_mul(g[j - 1], root);
        /* g[0] = 1 throughout (monic) */
    }
}

static void rs_encode(const uint8_t *msg, int k, int t2,
                      const uint8_t *g, uint8_t *cw)
{
    for (int i = 0; i < k;  i++) cw[i]     = msg[i];
    for (int i = 0; i < t2; i++) cw[k + i] = 0u;
    for (int i = 0; i < k; i++) {
        uint8_t coef = cw[i];
        if (coef != 0u)
            for (int j = 1; j <= t2; j++)
                cw[i + j] ^= gf_mul(g[j], coef);
    }
    for (int i = 0; i < k; i++) cw[i] = msg[i];
}

/* -- Syndrome computation --------------------------------------------------- */

/* The codeword uses high-degree-first storage (cw[0] = x^(n-1) coefficient).
 * Syndrome S[i] = cw(alpha^(i+1)) using Horner's rule from highest to lowest. */
static void rs_syndromes(const uint8_t *cw, int n, int t2, uint8_t *S)
{
    for (int i = 0; i < t2; i++) {
        uint8_t root = gf_exp[i + 1], y = 0u;
        for (int j = 0; j < n; j++)
            y = gf_mul(y, root) ^ cw[j];
        S[i] = y;
    }
}

/* -- Berlekamp-Massey ------------------------------------------------------- */

/* Computes error locator polynomial Lambda from syndromes S[0..t2-1].
 * Lambda[0] = 1, degree = number of errors found.
 * Returns degree of Lambda (-1 if all syndromes zero). */
static int berlekamp_massey(const uint8_t *S, int t2, uint8_t *Lambda)
{
    uint8_t B[32] = {0};   /* previous Lambda before last L-update */
    int L = 0, m = 1;
    uint8_t b = 1u;

    Lambda[0] = 1u;
    B[0] = 1u;

    for (int n = 0; n < t2; n++) {
        /* Discrepancy: d = S[n] + sum_{i=1}^{L} Lambda[i]*S[n-i] */
        uint8_t d = S[n];
        for (int i = 1; i <= L; i++)
            d ^= gf_mul(Lambda[i], S[n - i]);

        if (d == 0u) {
            m++;
        } else if (2 * L <= n) {
            /* Save old Lambda, update Lambda in-place, then B = old Lambda */
            uint8_t T[32];
            for (int i = 0; i < 32; i++) T[i] = Lambda[i];
            uint8_t coef = gf_div(d, b);
            for (int i = 0; i < 32 - m; i++)
                Lambda[i + m] ^= gf_mul(coef, B[i]);
            L = n + 1 - L;
            b = d;
            for (int i = 0; i < 32; i++) B[i] = T[i];
            m = 1;
        } else {
            uint8_t coef = gf_div(d, b);
            for (int i = 0; i < 32 - m; i++)
                Lambda[i + m] ^= gf_mul(coef, B[i]);
            m++;
        }
    }

    return L;
}

/* -- Chien search ----------------------------------------------------------- */

/* Find error positions in codeword (high-degree-first storage).
 * cw[j] holds x^(n-1-j); error locator X_k = alpha^(n-1-j).
 * Lambda(X_k^-1) = 0 <-> X_k^-1 = alpha^(j+1-n) = alpha^((256-n+j)%255).
 * error_pos[k] = codeword array index j of the k-th error.
 * Returns number of roots found. */
static int chien_search(const uint8_t *Lambda, int L, int n,
                        uint8_t *error_pos)
{
    int cnt = 0;
    for (int j = 0; j < n; j++) {
        uint8_t x = gf_exp[(256 - n + j) % 255];
        uint8_t val = 0u;
        uint8_t xpow = 1u;
        for (int i = 0; i <= L; i++) {
            val ^= gf_mul(Lambda[i], xpow);
            xpow = gf_mul(xpow, x);
        }
        if (val == 0u) {
            error_pos[cnt++] = (uint8_t)j;
        }
    }
    return cnt;
}

/* -- Forney algorithm ------------------------------------------------------- */

/* Compute error magnitudes using Forney's formula.
 * Omega(x) = S(x) * Lambda(x) mod x^(2t)  [error evaluator polynomial]
 * e_j = X_j * Omega(X_j^-1) / Lambda'(X_j)
 * where X_j = alpha^(error_pos[j]) and Lambda' is formal derivative.
 * Writes corrections to errata[error_pos[k]]. */
static void forney(const uint8_t *S, int t2,
                   const uint8_t *Lambda, int L,
                   const uint8_t *error_pos, int num_errors, int n,
                   uint8_t *errata)
{
    /* Compute Omega = S * Lambda mod x^(2t) */
    uint8_t Omega[32] = {0};
    for (int i = 0; i < t2; i++) {
        for (int j = 0; j <= L && i + j < t2; j++)
            Omega[i + j] ^= gf_mul(S[i], Lambda[j]);
    }

    /* Formal derivative of Lambda (in GF(2)): odd-indexed terms survive. */
    uint8_t Lambda_prime[32] = {0};
    for (int i = 0; i < L; i++) {
        if ((i + 1) & 1)
            Lambda_prime[i] = Lambda[i + 1];
    }

    for (int k = 0; k < num_errors; k++) {
        int pos = (int)error_pos[k];
        /* High-degree-first: cw[pos] is x^(n-1-pos); X_k = alpha^(n-1-pos) */
        uint8_t Xk     = gf_exp[n - 1 - pos];
        uint8_t Xk_inv = gf_inv(Xk);

        uint8_t omega_val  = gf_poly_eval(Omega, t2 - 1, Xk_inv);
        uint8_t lprime_val = gf_poly_eval(Lambda_prime, L - 1, Xk_inv);

        if (lprime_val == 0u) continue;

        /* Forney: e_k = Omega(Xk^-1) / Lambda'(Xk^-1)
         * (no extra Xk factor since syndromes start at alpha^1, b=1) */
        errata[pos] = gf_div(omega_val, lprime_val);
    }
}

/* -- Full decoder ----------------------------------------------------------- */

/* Decode in-place. Returns number of errors corrected, or -1 if uncorrectable. */
static int rs_decode(uint8_t *cw, int n, int t2)
{
    uint8_t S[16] = {0};
    rs_syndromes(cw, n, t2, S);

    /* Check if all syndromes zero -> no errors */
    int all_zero = 1;
    for (int i = 0; i < t2; i++) if (S[i] != 0u) { all_zero = 0; break; }
    if (all_zero) return 0;

    /* Berlekamp-Massey: find error locator */
    uint8_t Lambda[32] = {0};
    int L = berlekamp_massey(S, t2, Lambda);

    if (L > t2 / 2 || L <= 0) return -1;  /* too many errors */

    /* Chien search: find error positions */
    uint8_t error_pos[16] = {0};
    int n_errs = chien_search(Lambda, L, n, error_pos);

    if (n_errs != L) return -1;  /* number of roots != degree -> uncorrectable */

    /* Forney: compute error magnitudes and correct */
    uint8_t errata[32] = {0};
    forney(S, t2, Lambda, L, error_pos, n_errs, n, errata);

    for (int k = 0; k < n_errs; k++)
        cw[error_pos[k]] ^= errata[error_pos[k]];

    return n_errs;
}

/* -- test helpers ----------------------------------------------------------- */

static void chk_int(const char *lbl, int got, int exp)
{
    if (got == exp) {
        log_write(NONE, "  PASS  %s\n", lbl);
        g_pass++;
    } else {
        log_write(NONE, "  FAIL  %s: got %d  exp %d\n", lbl, got, exp);
        g_fail++;
    }
}

static void chk_bool(const char *lbl, int ok)
{
    if (ok) { log_write(NONE, "  PASS  %s\n", lbl); g_pass++; }
    else    { log_write(NONE, "  FAIL  %s\n", lbl); g_fail++; }
}

/* -- RS(7,3) tests: n=7, k=3, t2=4, t=2 ------------------------------------ */

#define N7  7
#define K3  3
#define T2_4 4

static void test_rs73(void)
{
    log_write(NONE, "\n-- RS(7,3) t=2: up to 2 symbol errors correctable --\n");

    uint8_t g4[8] = {0};
    rs_build_generator(g4, T2_4);

    uint8_t msg[K3]  = {0xAB, 0xCD, 0xEF};
    uint8_t cw[N7];
    rs_encode(msg, K3, T2_4, g4, cw);

    /* Verify encode: syndromes = 0 */
    uint8_t S[T2_4];
    rs_syndromes(cw, N7, T2_4, S);
    int clean = 1;
    for (int i = 0; i < T2_4; i++) if (S[i] != 0u) { clean = 0; break; }
    chk_bool("RS(7,3) encode: syndromes=0", clean);

    /* No error: decode returns 0 */
    uint8_t rx[N7];
    for (int i = 0; i < N7; i++) rx[i] = cw[i];
    chk_int("RS(7,3) no-error: decode returns 0", rs_decode(rx, N7, T2_4), 0);
    chk_bool("RS(7,3) no-error: codeword unchanged",
             rx[0]==cw[0] && rx[1]==cw[1] && rx[2]==cw[2]);

    /* 1 error in data byte 0 */
    for (int i = 0; i < N7; i++) rx[i] = cw[i];
    rx[0] ^= 0x42u;
    int nerr = rs_decode(rx, N7, T2_4);
    chk_int("RS(7,3) 1 error: decode returns 1", nerr, 1);
    chk_bool("RS(7,3) 1 error: data restored",
             rx[0]==cw[0] && rx[1]==cw[1] && rx[2]==cw[2]);

    /* 1 error in last parity byte (position 6) */
    for (int i = 0; i < N7; i++) rx[i] = cw[i];
    rx[6] ^= 0x99u;
    nerr = rs_decode(rx, N7, T2_4);
    chk_int("RS(7,3) 1 error in parity: returns 1", nerr, 1);
    chk_bool("RS(7,3) 1 error in parity: corrected", rx[6] == cw[6]);

    /* 2 errors at positions 0 and 2 */
    for (int i = 0; i < N7; i++) rx[i] = cw[i];
    rx[0] ^= 0x11u;
    rx[2] ^= 0x22u;
    nerr = rs_decode(rx, N7, T2_4);
    chk_int("RS(7,3) 2 errors: decode returns 2", nerr, 2);
    chk_bool("RS(7,3) 2 errors: data[0] restored", rx[0] == cw[0]);
    chk_bool("RS(7,3) 2 errors: data[2] restored", rx[2] == cw[2]);

    /* 2 errors in parity at positions 3 and 5 */
    for (int i = 0; i < N7; i++) rx[i] = cw[i];
    rx[3] ^= 0xAAu;
    rx[5] ^= 0xBBu;
    nerr = rs_decode(rx, N7, T2_4);
    chk_int("RS(7,3) 2 parity errors: returns 2", nerr, 2);
    chk_bool("RS(7,3) 2 parity: codeword restored",
             rx[3]==cw[3] && rx[5]==cw[5]);

    /* 3 errors -> uncorrectable (t=2 can only fix 2) */
    for (int i = 0; i < N7; i++) rx[i] = cw[i];
    rx[0] ^= 0x01u;
    rx[1] ^= 0x02u;
    rx[2] ^= 0x03u;
    nerr = rs_decode(rx, N7, T2_4);
    chk_int("RS(7,3) 3 errors: uncorrectable (returns -1)", nerr, -1);
}

/* -- RS(15,9) tests: n=15, k=9, t2=6, t=3 ---------------------------------- */

#define N15  15
#define K9   9
#define T2_6 6

static void test_rs159(void)
{
    log_write(NONE, "\n-- RS(15,9) t=3: up to 3 symbol errors correctable --\n");

    uint8_t g6[8] = {0};
    rs_build_generator(g6, T2_6);

    uint8_t msg[K9] = {0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09};
    uint8_t cw[N15];
    rs_encode(msg, K9, T2_6, g6, cw);

    /* No error */
    uint8_t rx[N15];
    for (int i = 0; i < N15; i++) rx[i] = cw[i];
    chk_int("RS(15,9) no error: returns 0", rs_decode(rx, N15, T2_6), 0);

    /* 1 error at position 0 (data) */
    for (int i = 0; i < N15; i++) rx[i] = cw[i];
    rx[0] ^= 0x7Fu;
    chk_int("RS(15,9) 1 error at pos 0: returns 1",
            rs_decode(rx, N15, T2_6), 1);
    chk_bool("RS(15,9) 1 error: corrected", rx[0] == cw[0]);

    /* 1 error at last position (parity) */
    for (int i = 0; i < N15; i++) rx[i] = cw[i];
    rx[14] ^= 0x55u;
    chk_int("RS(15,9) 1 error at pos 14: returns 1",
            rs_decode(rx, N15, T2_6), 1);
    chk_bool("RS(15,9) 1 error at 14: corrected", rx[14] == cw[14]);

    /* 2 errors */
    for (int i = 0; i < N15; i++) rx[i] = cw[i];
    rx[3] ^= 0x3Cu;
    rx[8] ^= 0xF0u;
    int nerr = rs_decode(rx, N15, T2_6);
    chk_int("RS(15,9) 2 errors: returns 2", nerr, 2);
    chk_bool("RS(15,9) 2 errors: corrected", rx[3]==cw[3] && rx[8]==cw[8]);

    /* 3 errors at data positions 0, 4, 7 */
    for (int i = 0; i < N15; i++) rx[i] = cw[i];
    rx[0] ^= 0xFEu;
    rx[4] ^= 0x10u;
    rx[7] ^= 0x80u;
    nerr = rs_decode(rx, N15, T2_6);
    chk_int("RS(15,9) 3 errors: returns 3", nerr, 3);
    chk_bool("RS(15,9) 3 errors: all corrected",
             rx[0]==cw[0] && rx[4]==cw[4] && rx[7]==cw[7]);

    /* 3 errors in parity region */
    for (int i = 0; i < N15; i++) rx[i] = cw[i];
    rx[9]  ^= 0xAAu;
    rx[11] ^= 0xBBu;
    rx[13] ^= 0xCCu;
    nerr = rs_decode(rx, N15, T2_6);
    chk_int("RS(15,9) 3 parity errors: returns 3", nerr, 3);
    chk_bool("RS(15,9) 3 parity: corrected",
             rx[9]==cw[9] && rx[11]==cw[11] && rx[13]==cw[13]);

    /* 4 errors -> uncorrectable */
    for (int i = 0; i < N15; i++) rx[i] = cw[i];
    rx[0] ^= 0x01u;
    rx[3] ^= 0x02u;
    rx[6] ^= 0x04u;
    rx[9] ^= 0x08u;
    nerr = rs_decode(rx, N15, T2_6);
    chk_int("RS(15,9) 4 errors: uncorrectable", nerr, -1);
}

/* -- Additional correctness checks ------------------------------------------ */

static void test_gf(void)
{
    log_write(NONE, "\n-- GF(2^8) table sanity --\n");
    /* alpha^255 = 1 */
    chk_bool("alpha^255 = 1", gf_exp[255] == 1u);
    /* gf_log[gf_exp[i]] = i for i=0..254 */
    int ok = 1;
    for (int i = 0; i < 255; i++)
        if (gf_log[gf_exp[i]] != (uint8_t)i) { ok = 0; break; }
    chk_bool("gf_log[gf_exp[i]] = i for i=0..254", ok);
    /* gf_exp[gf_log[a]] = a for a=1..255 */
    int ok2 = 1;
    for (int a = 1; a < 256; a++)
        if (gf_exp[gf_log[a]] != (uint8_t)a) { ok2 = 0; break; }
    chk_bool("gf_exp[gf_log[a]] = a for a=1..255", ok2);
    /* Known: gf_mul(0x02, 0x80) = 0x1D (reduction by 0x11D) */
    chk_bool("gf_mul(0x02,0x80)=0x1D", gf_mul(0x02u, 0x80u) == 0x1Du);
    /* Known: gf_mul(0x57,0x83) = 0x31 (poly 0x11D) */
    chk_bool("gf_mul(0x57,0x83)=0x31", gf_mul(0x57u, 0x83u) == 0x31u);
    /* gf_inv(gf_mul(a,b)) = gf_mul(gf_inv(b), gf_inv(a)) */
    chk_bool("gf_inv: a * inv(a) = 1", gf_mul(0x1Bu, gf_inv(0x1Bu)) == 1u);
}

static void test_different_messages(void)
{
    log_write(NONE, "\n-- RS(15,9) multiple messages with t=3 correction --\n");

    uint8_t g6[8] = {0};
    rs_build_generator(g6, T2_6);

    /* Test several different messages */
    static const uint8_t msgs[3][K9] = {
        {0xFF, 0x00, 0xFF, 0x00, 0xAA, 0x55, 0xA5, 0x5A, 0x0F},
        {0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF, 0x00},
        {0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01}
    };

    for (int m = 0; m < 3; m++) {
        uint8_t cw[N15], rx[N15];
        rs_encode(msgs[m], K9, T2_6, g6, cw);

        /* Inject 3 errors */
        for (int i = 0; i < N15; i++) rx[i] = cw[i];
        rx[m]     ^= 0x77u;
        rx[m + 3] ^= 0x88u;
        rx[m + 6] ^= 0x99u;

        int nerr = rs_decode(rx, N15, T2_6);
        int ok = (nerr == 3);
        for (int i = 0; i < K9; i++)
            if (rx[i] != cw[i]) ok = 0;

        if (ok) { log_write(NONE, "  PASS  msg[%d] 3-error correction\n", m); g_pass++; }
        else    { log_write(NONE, "  FAIL  msg[%d] 3-error correction\n", m); g_fail++; }
    }
}

/* -- main ------------------------------------------------------------------- */
int main(void)
{
    gf_init();

    log_init("rs-correct-test.log");
    log_write(NONE, "=== Reed-Solomon Error Correction (GF(2^8), BM+Chien+Forney) ===\n");

    test_gf();
    test_rs73();
    test_rs159();
    test_different_messages();

    log_write(NONE, "\n=== Result: %d PASS  %d FAIL ===\n", g_pass, g_fail);
    log_close();
    return g_fail;
}
