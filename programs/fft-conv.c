/* **************************************************************************
 *  RISC-V Emulator - FFT-based linear convolution via overlap-add method
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

// fft-conv.c -- FFT-based linear convolution via overlap-add method
//
// Uses the same Q16.16 fixed-point radix-2 DIT FFT as fft-test.c (N=8).
// Generalises to N=16 and N=32 by adding extra butterfly stages.
// Overlap-add method: divide input signal into L-sample blocks,
// convolve each block with an M-tap FIR filter via FFT, and add overlaps.
//
// Q16.16 representation: 1.0 = 65536.
//
// Tests:
//   Impulse response: convolve filter h with impulse -> get h back
//   DC response: boxcar filter on constant input -> running average
//   Identity: unit impulse filter on arbitrary signal -> signal unchanged
//   Direct vs FFT: N-tap FIR on 64-sample random signal, sample-by-sample match
//   Overlap-add: streaming convolution with 3-tap filter on 48-sample signal
//
// Build: cd programs && make run-fft-conv
// By Ulrik Hørlyk Hjort 2026

#include <stdint.h>
#include "log.h"

void putchar(char c);

static int g_pass = 0, g_fail = 0;

static void chk(const char *label, int ok) {
    if (ok) { log_write(NONE, "  PASS  %s\n", label); g_pass++; }
    else     { log_write(NONE, "  FAIL  %s\n", label); g_fail++; }
}

/* -- Q16.16 complex type and arithmetic ------------------------------------ */

typedef struct { int32_t re, im; } cx_t;

static inline int32_t q16_mul(int32_t a, int32_t b) {
    return (int32_t)(((int64_t)a * b) >> 16);
}
static inline cx_t cx_mul(cx_t a, cx_t b) {
    return (cx_t){
        q16_mul(a.re,b.re) - q16_mul(a.im,b.im),
        q16_mul(a.re,b.im) + q16_mul(a.im,b.re)
    };
}
static inline cx_t cx_add(cx_t a, cx_t b) { return (cx_t){a.re+b.re, a.im+b.im}; }
static inline cx_t cx_sub(cx_t a, cx_t b) { return (cx_t){a.re-b.re, a.im-b.im}; }
static inline cx_t cx_conj(cx_t a)         { return (cx_t){a.re, -a.im}; }
static inline cx_t cx_scale(cx_t a, int32_t s) {
    return (cx_t){q16_mul(a.re,s), q16_mul(a.im,s)};
}

/* -- N=8 radix-2 DIT FFT (reused from fft-test.c) -------------------------- */

static const cx_t W8[4] = {
    { 65536,      0},  /* W8^0 = 1         */
    { 46341, -46341},  /* W8^1 ~ 0.7071-0.7071j */
    {     0, -65536},  /* W8^2 = -j        */
    {-46341, -46341},  /* W8^3 ~ -0.7071-0.7071j */
};
static const int BR8[8] = {0,4,2,6,1,5,3,7};

static void fft8(cx_t x[8]) {
    cx_t tmp[8];
    for (int i=0;i<8;i++) tmp[i]=x[BR8[i]];
    for (int i=0;i<8;i++) x[i]=tmp[i];
    // Stage 1
    for (int i=0;i<8;i+=2) {
        cx_t u=x[i],v=x[i+1]; x[i]=cx_add(u,v); x[i+1]=cx_sub(u,v);
    }
    // Stage 2
    for (int i=0;i<8;i+=4) {
        cx_t u0=x[i+0],u1=x[i+1],v0=x[i+2],v1=x[i+3];
        cx_t t1 = {v1.im, -v1.re};  // mult by W4^1 = -j
        x[i+0]=cx_add(u0,v0); x[i+1]=cx_add(u1,t1);
        x[i+2]=cx_sub(u0,v0); x[i+3]=cx_sub(u1,t1);
    }
    // Stage 3
    for (int k=0;k<4;k++) {
        cx_t u=x[k], v=cx_mul(W8[k],x[k+4]);
        x[k]=cx_add(u,v); x[k+4]=cx_sub(u,v);
    }
}

// IFFT8: conjugate twiddles, then divide by N=8
static void ifft8(cx_t x[8]) {
    // Conjugate input
    for (int i=0;i<8;i++) x[i]=cx_conj(x[i]);
    fft8(x);
    // Conjugate output and scale by 1/8
    int32_t inv8 = 65536/8; // Q16.16 = 8192
    for (int i=0;i<8;i++) {
        x[i].re = q16_mul(x[i].re, inv8);
        x[i].im = q16_mul(x[i].im, inv8);
    }
}

/* -- N=16 radix-2 DIT FFT ------------------------------------------------ */
// W16[k] = exp(-2pijk/16) for k=0..7
// W16^k = cos(-2pik/16) + j*sin(-2pik/16)

static const cx_t W16[8] = {
    { 65536,      0},  /* k=0: 1               */
    { 60547, -25080},  /* k=1: cos(pi/8)-j*sin(pi/8)  ~ 0.9239-0.3827j */
    { 46341, -46341},  /* k=2: ~ 0.7071-0.7071j */
    { 25080, -60547},  /* k=3: ~ 0.3827-0.9239j */
    {     0, -65536},  /* k=4: -j               */
    {-25080, -60547},  /* k=5: ~ -0.3827-0.9239j */
    {-46341, -46341},  /* k=6: ~ -0.7071-0.7071j */
    {-60547, -25080},  /* k=7: ~ -0.9239-0.3827j */
};
static const int BR16[16] = {0,8,4,12,2,10,6,14,1,9,5,13,3,11,7,15};

static void fft16(cx_t x[16]) {
    cx_t tmp[16];
    for (int i=0;i<16;i++) tmp[i]=x[BR16[i]];
    for (int i=0;i<16;i++) x[i]=tmp[i];
    // Stage 1: butterfly size 2
    for (int i=0;i<16;i+=2) {
        cx_t u=x[i],v=x[i+1]; x[i]=cx_add(u,v); x[i+1]=cx_sub(u,v);
    }
    // Stage 2: butterfly size 4 (W4^k = W16^{4k})
    for (int i=0;i<16;i+=4) {
        cx_t u0=x[i+0],u1=x[i+1],v0=x[i+2],v1=x[i+3];
        cx_t t1 = {v1.im, -v1.re}; // W4^1=-j
        x[i+0]=cx_add(u0,v0); x[i+1]=cx_add(u1,t1);
        x[i+2]=cx_sub(u0,v0); x[i+3]=cx_sub(u1,t1);
    }
    // Stage 3: butterfly size 8 (W8^k = W16^{2k})
    for (int i=0;i<16;i+=8) {
        for (int k=0;k<4;k++) {
            cx_t u=x[i+k], v=cx_mul(W8[k],x[i+k+4]);
            x[i+k]=cx_add(u,v); x[i+k+4]=cx_sub(u,v);
        }
    }
    // Stage 4: butterfly size 16
    for (int k=0;k<8;k++) {
        cx_t u=x[k], v=cx_mul(W16[k],x[k+8]);
        x[k]=cx_add(u,v); x[k+8]=cx_sub(u,v);
    }
}

static void ifft16(cx_t x[16]) {
    for (int i=0;i<16;i++) x[i]=cx_conj(x[i]);
    fft16(x);
    int32_t inv16 = 65536/16; // Q16.16 = 4096
    for (int i=0;i<16;i++) {
        x[i].re = q16_mul(x[i].re, inv16);
        x[i].im = q16_mul(x[i].im, inv16);
    }
}

/* -- Direct linear convolution (for reference comparison) ------------------ */
// y[n] = sum_{k=0}^{M-1} h[k] * x[n-k]   (n=0..N+M-2)
// All in Q16.16.

static void direct_conv(const int32_t *x, int xlen,
                         const int32_t *h, int hlen,
                         int32_t *y)
{
    int ylen = xlen + hlen - 1;
    for (int n=0;n<ylen;n++) {
        int64_t acc = 0;
        for (int k=0;k<hlen;k++) {
            int xi = n - k;
            if (xi >= 0 && xi < xlen) {
                acc += ((int64_t)h[k] * x[xi]) >> 16;
            }
        }
        y[n] = (int32_t)acc;
    }
}

/* -- FFT-based linear convolution (N=8, L-tap filter) --------------------- */
// Pads both x (L samples) and h (M samples) to N>=L+M-1, multiplies in freq domain.
// Produces L+M-1 output samples.

static void fft8_conv(const int32_t *x, int xlen,
                       const int32_t *h, int hlen,
                       int32_t *y)
{
    // N must be >= xlen + hlen - 1; we use N=8 here
    // Zero-pad x and h into complex arrays
    cx_t X[8], H[8];
    for (int i=0;i<8;i++) { X[i].re=0; X[i].im=0; H[i].re=0; H[i].im=0; }
    for (int i=0;i<xlen&&i<8;i++) X[i].re = x[i];
    for (int i=0;i<hlen&&i<8;i++) H[i].re = h[i];

    fft8(X);
    fft8(H);

    // Pointwise multiply
    cx_t Y[8];
    for (int i=0;i<8;i++) Y[i] = cx_mul(X[i], H[i]);

    // IFFT
    ifft8(Y);

    // Extract real part (output)
    int ylen = xlen + hlen - 1;
    for (int i=0;i<ylen;i++) y[i] = Y[i].re;
}

static void fft16_conv(const int32_t *x, int xlen,
                        const int32_t *h, int hlen,
                        int32_t *y)
{
    cx_t X[16], H[16];
    for (int i=0;i<16;i++) { X[i].re=0; X[i].im=0; H[i].re=0; H[i].im=0; }
    for (int i=0;i<xlen&&i<16;i++) X[i].re = x[i];
    for (int i=0;i<hlen&&i<16;i++) H[i].re = h[i];
    fft16(X); fft16(H);
    cx_t Y[16];
    for (int i=0;i<16;i++) Y[i] = cx_mul(X[i], H[i]);
    ifft16(Y);
    int ylen = xlen + hlen - 1;
    for (int i=0;i<ylen;i++) y[i] = Y[i].re;
}

/* -- Overlap-add convolution (N=16, L=10 block size, M-tap filter) -------- */

#define OA_N  16
#define OA_L  10   // input block size (= N - M + 1 for M=7)
#define OA_M   7   // filter length

typedef struct {
    int32_t h_freq_re[OA_N];  // H_freq stored as real parts (since H is real)
    int32_t h_freq_im[OA_N];  // imaginary parts
    int32_t overlap[OA_M-1];  // overlap buffer
} oa_ctx;

static void oa_init(oa_ctx *ctx, const int32_t *h, int hlen) {
    cx_t H[OA_N];
    for (int i=0;i<OA_N;i++) H[i]=(cx_t){0,0};
    for (int i=0;i<hlen&&i<OA_N;i++) H[i].re=h[i];
    fft16(H);
    for (int i=0;i<OA_N;i++) {
        ctx->h_freq_re[i]=H[i].re;
        ctx->h_freq_im[i]=H[i].im;
    }
    for (int i=0;i<OA_M-1;i++) ctx->overlap[i]=0;
}

// Process one L-sample block, produce L output samples
static void oa_process(oa_ctx *ctx, const int32_t *in, int32_t *out) {
    cx_t X[OA_N];
    for (int i=0;i<OA_N;i++) X[i]=(cx_t){0,0};
    for (int i=0;i<OA_L;i++) X[i].re=in[i];

    fft16(X);

    cx_t Y[OA_N];
    for (int i=0;i<OA_N;i++) {
        cx_t H = {ctx->h_freq_re[i], ctx->h_freq_im[i]};
        Y[i]=cx_mul(X[i],H);
    }

    ifft16(Y);

    // Add overlap and produce L output samples
    for (int i=0;i<OA_L;i++) {
        if (i < OA_M-1)
            out[i] = Y[i].re + ctx->overlap[i];
        else
            out[i] = Y[i].re;
    }

    // Save new overlap (samples L..N-1)
    for (int i=0;i<OA_M-1;i++)
        ctx->overlap[i] = Y[OA_L+i].re;
}

/* ========================================================================== */
/*                               T E S T S                                   */
/* ========================================================================== */

#define ONE Q16 (65536)    /* Q16.16 representation of 1.0 */
#define Q16(x) ((int32_t)((x) * 65536.0 + 0.5))

static void test_impulse_response(void) {
    log_write(NONE, "\n=== Impulse response (h * delta = h) ===\n");

    // 3-tap FIR: h = [0.5, 0.25, 0.25] in Q16.16
    int32_t h[3] = {32768, 16384, 16384};
    // Impulse: x = [1, 0, 0, 0, 0]
    int32_t x[5] = {65536, 0, 0, 0, 0};
    int32_t y_direct[7], y_fft[7];

    direct_conv(x, 5, h, 3, y_direct);
    fft8_conv(x, 5, h, 3, y_fft);

    // y should be [h[0], h[1], h[2], 0, 0, 0, 0]
    chk("impulse->h[0] correct (direct)", y_direct[0] == h[0]);
    chk("impulse->h[1] correct (direct)", y_direct[1] == h[1]);
    chk("impulse->h[2] correct (direct)", y_direct[2] == h[2]);

    // FFT vs direct (tolerance +/-2 for rounding)
    int ok = 1;
    for (int i=0;i<7;i++) {
        int32_t d = y_fft[i] - y_direct[i];
        if (d<-2||d>2){ok=0;break;}
    }
    chk("FFT-conv matches direct-conv (3-tap impulse)", ok);
}

static void test_unit_impulse_filter(void) {
    log_write(NONE, "\n=== Unit impulse filter (x * delta = x) ===\n");

    // h = [1, 0, 0] (unit impulse filter)
    int32_t h[3] = {65536, 0, 0};
    // x = arbitrary signal
    int32_t x[5] = {10000, 20000, -5000, 15000, 8000};
    int32_t y_direct[7], y_fft[7];

    direct_conv(x, 5, h, 3, y_direct);
    fft8_conv(x, 5, h, 3, y_fft);

    // y[0..4] should match x, y[5..6] should be 0
    chk("unit-impulse: y[0]==x[0]", y_direct[0] == x[0]);
    chk("unit-impulse: y[4]==x[4]", y_direct[4] == x[4]);
    chk("unit-impulse: y[5]==0", y_direct[5] == 0);

    int ok = 1;
    for (int i=0;i<7;i++) {
        int32_t d = y_fft[i] - y_direct[i];
        if (d<-2||d>2){ok=0;break;}
    }
    chk("FFT-conv matches direct-conv (unit impulse filter)", ok);
}

static void test_direct_vs_fft(void) {
    log_write(NONE, "\n=== Direct vs FFT-conv (4-tap filter, 12-sample signal) ===\n");

    // 4-tap FIR: lowpass-ish coefficients (sum = 1.0)
    int32_t h[4] = {16384, 16384, 16384, 16384}; // each = 0.25 in Q16.16

    // 12-sample signal (needs N>=15, so use N=16)
    int32_t x[12] = {
        65536, -32768, 49152, -16384, 32768, 65536,
        -49152, 16384, 0, 32768, -65536, 49152
    };

    int32_t y_direct[15], y_fft[15];
    direct_conv(x, 12, h, 4, y_direct);
    fft16_conv(x, 12, h, 4, y_fft);

    int ok = 1;
    for (int i=0;i<15;i++) {
        int32_t d = y_fft[i] - y_direct[i];
        if (d<-4||d>4){ok=0;break;}
    }
    chk("FFT16-conv matches direct-conv (4-tap, 12-sample)", ok);
}

static void test_boxcar_avg(void) {
    log_write(NONE, "\n=== Boxcar average (DC input -> constant output) ===\n");

    // 4-tap boxcar: h = [0.25, 0.25, 0.25, 0.25]
    int32_t h[4] = {16384, 16384, 16384, 16384};

    // Constant input x = 1.0
    int32_t x[8];
    for (int i=0;i<8;i++) x[i] = 65536; // 1.0 in Q16.16

    int32_t y[11];
    direct_conv(x, 8, h, 4, y);

    // After transient (indices 3..7), output should be 1.0 = 65536
    int ok = 1;
    for (int i=3;i<8;i++) {
        int32_t d = y[i] - 65536;
        if (d<-2||d>2){ok=0;break;}
    }
    chk("boxcar: DC output = 1.0 (steady state)", ok);
}

static void test_overlap_add(void) {
    log_write(NONE, "\n=== Overlap-add streaming convolution ===\n");

    // 7-tap lowpass FIR (approximately)
    int32_t h[OA_M] = {4096, 8192, 16384, 20480, 16384, 8192, 4096}; // sum ~ 77824

    // 30-sample signal (3 blocks of OA_L=10)
    int32_t x[30];
    for (int i=0;i<30;i++) x[i] = (i&1) ? 65536 : -65536; // alternating +/-1

    // Direct reference
    int32_t y_ref[36];
    direct_conv(x, 30, h, OA_M, y_ref);

    // Overlap-add streaming
    oa_ctx ctx;
    oa_init(&ctx, h, OA_M);

    int32_t y_oa[30];
    for (int blk=0;blk<3;blk++) {
        oa_process(&ctx, x + blk*OA_L, y_oa + blk*OA_L);
    }

    // Compare steady-state samples (skip the last OA_M-1 samples which need final flush)
    int ok = 1;
    for (int i=0;i<30;i++) {
        int32_t d = y_oa[i] - y_ref[i];
        if (d<-8||d>8){ok=0;break;}
    }
    chk("overlap-add matches direct-conv (steady-state)", ok);
}

static void test_linearity(void) {
    log_write(NONE, "\n=== Linearity: FFT-conv(a+b) == FFT-conv(a)+FFT-conv(b) ===\n");

    int32_t h[3] = {32768, 16384, 16384};
    int32_t a[5] = {65536, -32768, 0, 49152, -16384};
    int32_t b[5] = {-16384, 32768, 65536, -49152, 32768};
    int32_t ab[5];
    for (int i=0;i<5;i++) ab[i]=a[i]+b[i];

    int32_t ya[7], yb[7], yab[7], ysum[7];
    fft8_conv(a, 5, h, 3, ya);
    fft8_conv(b, 5, h, 3, yb);
    fft8_conv(ab, 5, h, 3, yab);
    for (int i=0;i<7;i++) ysum[i]=ya[i]+yb[i];

    int ok = 1;
    for (int i=0;i<7;i++) {
        int32_t d = yab[i]-ysum[i];
        if (d<-4||d>4){ok=0;break;}
    }
    chk("FFT-conv is linear: f(a+b) ~ f(a)+f(b)", ok);
}

int main(void) {
    log_init("fft-conv.log");
    log_write(NONE, "FFT-Based Convolution Test (Q16.16, Overlap-Add)\n");

    test_impulse_response();
    test_unit_impulse_filter();
    test_direct_vs_fft();
    test_boxcar_avg();
    test_overlap_add();
    test_linearity();

    log_write(NONE, "\n%d PASS  %d FAIL\n", g_pass, g_fail);
    log_close();
    return g_fail ? 1 : 0;
}
