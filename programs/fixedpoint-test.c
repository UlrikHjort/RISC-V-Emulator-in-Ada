/* **************************************************************************
 *      RISC-V Emulator - Q15 and Q16.16 fixed-point arithmetic tests
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

// fixedpoint-test.c -- Q15 and Q16.16 fixed-point arithmetic tests.
//
// Tests:
//   Q15  (s1.15): addition, subtraction, multiplication (with rounding),
//                 division, saturation, abs, conversion to/from int
//   Q16.16 (s15.16): same suite plus larger dynamic range
//   FIR   filter test using Q15 coefficients
//   CORDIC approximation of sine/cosine (integer only, no FPU)
//
// Build: cd programs && make run-fixedpoint-test
// By Ulrik Hørlyk Hjort 2026

#include <stdint.h>
#include <stddef.h>
#include "log.h"

void putchar(char c);
static void uart_puts(const char *s) {
    while (*s) { if (*s == '\n') putchar('\r'); putchar(*s++); }
}

static int g_pass = 0, g_fail = 0;

/* -- Helpers --------------------------------------------------------------- */

static void chk32(const char *lbl, int32_t got, int32_t exp) {
    if (got == exp) {
        log_write(NONE, "  PASS  %s\n", lbl);
        g_pass++;
    } else {
        log_write(NONE, "  FAIL  %s: got %d  exp %d\n", lbl, (int)got, (int)exp);
        g_fail++;
    }
}

static void chk32u(const char *lbl, uint32_t got, uint32_t exp) {
    if (got == exp) {
        log_write(NONE, "  PASS  %s\n", lbl);
        g_pass++;
    } else {
        log_write(NONE, "  FAIL  %s: got 0x%x  exp 0x%x\n", lbl, got, exp);
        g_fail++;
    }
}

/* -- Q15 (s1.15) arithmetic ------------------------------------------------ */
/*
 * One Q15 value occupies a 16-bit word with 15 fractional bits:
 *   range [-1.0, 1.0 - 2^-15]
 *   1.0  = 0x7FFF  (32767)
 *   -1.0 = 0x8000  (-32768)
 *   0.5  = 0x4000  (16384)
 */

#define Q15_ONE    ((int16_t)0x7FFF)
#define Q15_NEG1   ((int16_t)(int16_t)0x8000u)
#define Q15_HALF   ((int16_t)0x4000)
#define Q15_QRTR   ((int16_t)0x2000)

/* Saturating add */
static int16_t q15_add(int16_t a, int16_t b) {
    int32_t s = (int32_t)a + (int32_t)b;
    if (s >  0x7FFF) return  0x7FFF;
    if (s < -0x8000) return (int16_t)(int16_t)0x8000u;
    return (int16_t)s;
}

/* Saturating sub */
static int16_t q15_sub(int16_t a, int16_t b) {
    int32_t s = (int32_t)a - (int32_t)b;
    if (s >  0x7FFF) return  0x7FFF;
    if (s < -0x8000) return (int16_t)(int16_t)0x8000u;
    return (int16_t)s;
}

/* Multiply: result rounded to Q15 */
static int16_t q15_mul(int16_t a, int16_t b) {
    int32_t p = ((int32_t)a * (int32_t)b + 0x4000) >> 15;
    if (p >  0x7FFF) return  0x7FFF;
    if (p < -0x8000) return (int16_t)(int16_t)0x8000u;
    return (int16_t)p;
}

/* Negate (saturated -- handles MIN_INT) */
static int16_t q15_neg(int16_t a) {
    if (a == (int16_t)(int16_t)0x8000u) return 0x7FFF;
    return (int16_t)(-a);
}

/* Abs */
static int16_t q15_abs(int16_t a) {
    return (a < 0) ? q15_neg(a) : a;
}

/* Convert integer [-1,1] float-like fraction via integer arithmetic */
/* encode: val_times_32768 -> Q15 (clamped) */
static int16_t q15_from_frac(int32_t numerator, int32_t denominator) {
    int32_t v = (numerator * 32768) / denominator;
    if (v >  0x7FFF) v =  0x7FFF;
    if (v < -0x8000) v = -0x8000;
    return (int16_t)v;
}

static void test_q15(void) {
    log_write(NONE, "\n=== Q15 (s1.15) Fixed-Point ===\n");

    /* 0.5 + 0.25 = 0.75 */
    chk32("q15 0.5+0.25=0.75",    q15_add(Q15_HALF, Q15_QRTR), (int32_t)0x6000);

    /* 0.5 - 0.25 = 0.25 */
    chk32("q15 0.5-0.25=0.25",    q15_sub(Q15_HALF, Q15_QRTR), (int32_t)Q15_QRTR);

    /* Saturating add: 0.75 + 0.75 -> clamped to 1.0 */
    chk32("q15 sat add->1.0",      q15_add((int16_t)0x6000, (int16_t)0x6000), (int32_t)Q15_ONE);

    /* -0.5 + 0.5 = 0 */
    chk32("q15 -0.5+0.5=0",       q15_add((int16_t)-Q15_HALF, Q15_HALF), 0);

    /* 0.5 * 0.5 = 0.25 */
    chk32("q15 0.5*0.5=0.25",     q15_mul(Q15_HALF, Q15_HALF), (int32_t)Q15_QRTR);

    /* 0.5 * (-0.5) = -0.25 */
    chk32("q15 0.5*(-0.5)=-0.25", q15_mul(Q15_HALF, (int16_t)-Q15_HALF), -(int32_t)Q15_QRTR);

    /* 1.0 * 1.0: 0x7FFF*0x7FFF = 1073676289; +0x4000 >>15 = 32766 */
    chk32("q15 1.0*1.0~1.0",     q15_mul(Q15_ONE, Q15_ONE), (int32_t)(Q15_ONE - 1));

    /* q15_neg(0.5) = -0.5 */
    chk32("q15 neg(0.5)=-0.5",    q15_neg(Q15_HALF), -(int32_t)Q15_HALF);

    /* q15_neg(-1.0) = 1.0 (saturated, not -(-1.0)=+1.0 which overflows) */
    chk32("q15 neg(-1.0)=MAX",    q15_neg(Q15_NEG1), (int32_t)Q15_ONE);

    /* q15_abs(-0.25) = 0.25 */
    chk32("q15 abs(-0.25)=0.25",  q15_abs((int16_t)-Q15_QRTR), (int32_t)Q15_QRTR);

    /* Convert 3/4 -> should be 0x6000 = 0.75 */
    chk32("q15 from 3/4=0x6000",  q15_from_frac(3, 4), (int32_t)0x6000);

    /* from -1/2 = -0.5 = 0xC000 */
    chk32("q15 from -1/2=0xC000", q15_from_frac(-1, 2), (int32_t)(int16_t)0xC000u);
}

/* -- Q16.16 (s15.16) arithmetic -------------------------------------------- */
/*
 * 32-bit fixed-point with 16 fractional bits.
 *   range ~[-32768.0, 32767.99998]
 *   1.0   = 0x00010000
 *   0.5   = 0x00008000
 *   PI    ~ 0x0003243F  (3.14159...)
 *   E     ~ 0x0002B7E1  (2.71828...)
 */

#define Q16_ONE   ((int32_t)0x00010000)
#define Q16_HALF  ((int32_t)0x00008000)

/* No saturation needed here -- just use 64-bit for multiply */
static int32_t q16_add(int32_t a, int32_t b) { return a + b; }
static int32_t q16_sub(int32_t a, int32_t b) { return a - b; }
static int32_t q16_mul(int32_t a, int32_t b) {
    return (int32_t)(((int64_t)a * (int64_t)b) >> 16);
}
/* Integer part */
static int32_t q16_int(int32_t a)  { return a >> 16; }
/* Fractional part (upper 16 bits of fraction, i.e. x 10000 for display) */
static uint32_t q16_frac_u16(int32_t a) { return (uint32_t)(a & 0xFFFF); }

/* Convert integer n and fraction f/65536 to Q16.16 */
static int32_t q16_from_parts(int32_t n, int32_t frac) {
    return (n << 16) | (uint16_t)frac;
}

static void test_q16(void) {
    log_write(NONE, "\n=== Q16.16 (s15.16) Fixed-Point ===\n");

    /* 1.0 + 0.5 = 1.5 */
    int32_t r;
    r = q16_add(Q16_ONE, Q16_HALF);
    chk32("q16 1.0+0.5=1.5",       r, Q16_ONE + Q16_HALF);

    /* 1.5 - 0.5 = 1.0 */
    r = q16_sub(Q16_ONE + Q16_HALF, Q16_HALF);
    chk32("q16 1.5-0.5=1.0",       r, Q16_ONE);

    /* 1.0 * 1.0 = 1.0 */
    r = q16_mul(Q16_ONE, Q16_ONE);
    chk32("q16 1.0*1.0=1.0",       r, Q16_ONE);

    /* 0.5 * 0.5 = 0.25 */
    r = q16_mul(Q16_HALF, Q16_HALF);
    chk32("q16 0.5*0.5=0.25",      r, Q16_HALF / 2);

    /* 2.0 * 3.0 = 6.0 */
    r = q16_mul(2 * Q16_ONE, 3 * Q16_ONE);
    chk32("q16 2.0*3.0=6.0",       r, 6 * Q16_ONE);

    /* Integer part of 3.14159 */
    int32_t pi_q16 = q16_from_parts(3, 9279);   /* 3 + 9279/65536 ~ 3.1416 */
    chk32("q16 int(pi)=3",         q16_int(pi_q16), 3);
    chk32u("q16 frac(pi)~9279",   q16_frac_u16(pi_q16), 9279u);

    /* Negative: -1.5 */
    int32_t neg1p5 = -(Q16_ONE + Q16_HALF);
    chk32("q16 int(-1.5)=-2",      q16_int(neg1p5), -2); /* arithmetic right-shift */

    /* (-1.0) * 2.0 = -2.0 */
    r = q16_mul(-Q16_ONE, 2 * Q16_ONE);
    chk32("q16 -1*2=-2",           r, -2 * Q16_ONE);

    /* chain: (0.5 + 0.5) * 4.0 = 4.0 */
    r = q16_mul(q16_add(Q16_HALF, Q16_HALF), 4 * Q16_ONE);
    chk32("q16 (0.5+0.5)*4=4",    r, 4 * Q16_ONE);
}

/* -- Q15 FIR filter -------------------------------------------------------- */
/*
 * 5-tap low-pass FIR with Hann-windowed coefficients (sum ~ 1.0):
 *   h = [0.0625, 0.25, 0.375, 0.25, 0.0625] in Q15
 *   Pass a step function through it; output should converge to 1.0.
 */

#define FIR_TAPS 5
static const int16_t fir_h[FIR_TAPS] = {
    2048,    /* 0.0625 * 32768 */
    8192,    /* 0.25   * 32768 */
    12288,   /* 0.375  * 32768 */
    8192,
    2048,
};

static int16_t fir_filter(const int16_t *h, int16_t *buf, int16_t x) {
    /* Shift buffer: buf[0]=oldest */
    for (int i = 0; i < FIR_TAPS - 1; i++)
        buf[i] = buf[i + 1];
    buf[FIR_TAPS - 1] = x;

    int32_t acc = 0;
    for (int i = 0; i < FIR_TAPS; i++)
        acc += (int32_t)h[i] * (int32_t)buf[i];
    /* acc is Q30; shift to Q15 */
    return (int16_t)(acc >> 15);
}

static void test_fir(void) {
    log_write(NONE, "\n=== Q15 FIR Low-Pass Filter ===\n");
    int16_t buf[FIR_TAPS] = {0};
    int16_t y;

    /* Feed zeros -- output stays 0 */
    y = fir_filter(fir_h, buf, 0);
    chk32("fir zeros->0",           y, 0);

    /* Step input: feed 1.0 (=0x7FFF) five times */
    fir_filter(fir_h, buf, Q15_ONE);
    fir_filter(fir_h, buf, Q15_ONE);
    fir_filter(fir_h, buf, Q15_ONE);
    fir_filter(fir_h, buf, Q15_ONE);
    y = fir_filter(fir_h, buf, Q15_ONE);
    /* After 5 samples the sum is h[0]+...+h[4] * 0x7FFF ~ 0x7FFF (+/-rounding) */
    /* Tolerance: +/-2 LSB */
    int ok = (y >= Q15_ONE - 2 && y <= Q15_ONE);
    if (ok) {
        log_write(NONE, "  PASS  fir step->~1.0 (%d)\n", (int)y);
        g_pass++;
    } else {
        log_write(NONE, "  FAIL  fir step->~1.0: got %d exp ~%d\n", (int)y, (int)Q15_ONE);
        g_fail++;
    }

    /* Feed a zero -- output should start dropping */
    y = fir_filter(fir_h, buf, 0);
    /* 0.25+0.375+0.25+0.0625 ~ 0.9375 -> 0x7800 = 30720 */
    int16_t exp_drop = (int16_t)((8192 + 12288 + 8192 + 2048) * (int32_t)Q15_ONE >> 15);
    ok = (y >= exp_drop - 2 && y <= exp_drop + 2);
    if (ok) {
        log_write(NONE, "  PASS  fir drop step (%d)\n", (int)y);
        g_pass++;
    } else {
        log_write(NONE, "  FAIL  fir drop step: got %d exp ~%d\n", (int)y, (int)exp_drop);
        g_fail++;
    }
}

/* -- CORDIC (integer sine/cosine) ------------------------------------------ */
/*
 * 16-iteration CORDIC in rotation mode, Q16.16 representation.
 * Returns sin and cos for angle in Q16.16 radians.
 * Pre-computed atan table: atan(2^-i) in Q16.16.
 */

static const int32_t cordic_atan[16] = {
    /* atan(2^-i) in Q16.16 = atan * 65536 */
    51472,  /* atan(1)       = 0.7854 rad */
    30386,  /* atan(0.5)     = 0.4636 rad */
    16055,  /* atan(0.25)    = 0.2450 rad */
     8150,  /* atan(0.125)   = 0.1244 rad */
     4091,  /* atan(0.0625)  = 0.0624 rad */
     2047,
     1024,
      512,
      256,
      128,
       64,
       32,
       16,
        8,
        4,
        2,
};

/* CORDIC gain: product(1/sqrt(1+2^(-2i))) ~ 0.60726; in Q16.16 */
#define CORDIC_GAIN  39797   /* 0.60726 * 65536 */

static void cordic_rotate(int32_t angle, int32_t *cos_out, int32_t *sin_out) {
    /* Reduce angle to [-pi/2, pi/2] */
    int32_t pi_q16   = 205887;   /* pi   * 65536 */
    int32_t pi_2_q16 = 102944;   /* pi/2 * 65536 */
    int quadrant = 0;
    if (angle > pi_2_q16) {
        angle -= pi_q16;
        quadrant = 1;
    } else if (angle < -pi_2_q16) {
        angle += pi_q16;
        quadrant = 2;
    }

    int32_t x = CORDIC_GAIN;
    int32_t y = 0;
    int32_t z = angle;

    for (int i = 0; i < 16; i++) {
        int32_t xn, yn;
        if (z >= 0) {
            xn = x - (y >> i);
            yn = y + (x >> i);
            z -= cordic_atan[i];
        } else {
            xn = x + (y >> i);
            yn = y - (x >> i);
            z += cordic_atan[i];
        }
        x = xn; y = yn;
    }

    if (quadrant == 1) { *cos_out = -x; *sin_out = -y; }
    else if (quadrant == 2) { *cos_out = -x; *sin_out = -y; }
    else { *cos_out = x; *sin_out = y; }
}

static void test_cordic(void) {
    log_write(NONE, "\n=== CORDIC Sine/Cosine (Q16.16) ===\n");
    int32_t s, c;

    /* cos(0) = 1.0, sin(0) = 0.0 */
    cordic_rotate(0, &c, &s);
    /* Tolerance: +/-200 ulp (about +/-0.003) */
    int ok;
    ok = (c >= Q16_ONE - 200 && c <= Q16_ONE + 200);
    if (ok) { log_write(NONE, "  PASS  cos(0)~1.0 (%d)\n", c); g_pass++; }
    else     { log_write(NONE, "  FAIL  cos(0): got %d exp %d\n", c, Q16_ONE); g_fail++; }
    ok = (s >= -200 && s <= 200);
    if (ok) { log_write(NONE, "  PASS  sin(0)~0.0 (%d)\n", s); g_pass++; }
    else     { log_write(NONE, "  FAIL  sin(0): got %d exp 0\n", s); g_fail++; }

    /* cos(pi/6) ~ 0.866 = 0xDDB3 in Q16.16 */
    /* sin(pi/6) ~ 0.5   = 0x8000 */
    int32_t pi6_q16 = 34315;   /* pi/6 * 65536 */
    cordic_rotate(pi6_q16, &c, &s);
    ok = (c >= 56667 - 400 && c <= 56667 + 400);  /* 0.866*65536=56754 */
    if (ok) { log_write(NONE, "  PASS  cos(pi/6)~0.866 (%d)\n", c); g_pass++; }
    else     { log_write(NONE, "  FAIL  cos(pi/6): got %d exp ~56754\n", c); g_fail++; }
    ok = (s >= Q16_HALF - 400 && s <= Q16_HALF + 400);
    if (ok) { log_write(NONE, "  PASS  sin(pi/6)~0.5 (%d)\n", s); g_pass++; }
    else     { log_write(NONE, "  FAIL  sin(pi/6): got %d exp ~%d\n", s, Q16_HALF); g_fail++; }

    /* cos(pi/4) = sin(pi/4) ~ 0.7071 = 46341 in Q16.16 */
    int32_t pi4_q16 = 51472;   /* pi/4 * 65536 */
    cordic_rotate(pi4_q16, &c, &s);
    ok = (c >= 46341 - 400 && c <= 46341 + 400);
    if (ok) { log_write(NONE, "  PASS  cos(pi/4)~0.7071 (%d)\n", c); g_pass++; }
    else     { log_write(NONE, "  FAIL  cos(pi/4): got %d exp ~46341\n", c); g_fail++; }
    ok = (s >= 46341 - 400 && s <= 46341 + 400);
    if (ok) { log_write(NONE, "  PASS  sin(pi/4)~0.7071 (%d)\n", s); g_pass++; }
    else     { log_write(NONE, "  FAIL  sin(pi/4): got %d exp ~46341\n", s); g_fail++; }

    /* sin^2 + cos^2 ~ 1 -- Pythagorean identity */
    /* Use pi/3: cos=0.5, sin=sqrt(3)/2 */
    int32_t pi3_q16 = 68629;
    cordic_rotate(pi3_q16, &c, &s);
    /* s^2 + c^2 should be ~Q16_ONE^2 in Q16.32; shift back */
    int64_t pyth = ((int64_t)s * s + (int64_t)c * c) >> 16;
    ok = (pyth >= Q16_ONE - 600 && pyth <= Q16_ONE + 600);
    if (ok) { log_write(NONE, "  PASS  sin^2+cos^2~1 at pi/3 (%d)\n", (int)pyth); g_pass++; }
    else     { log_write(NONE, "  FAIL  sin^2+cos^2 at pi/3: %d exp %d\n", (int)pyth, Q16_ONE); g_fail++; }
}

/* -- Integer square root (Newton's method) ------------------------------- */
/*
 * isqrt(n): integer square root of n (floor).
 * Exercises integer division and loop -- no FPU.
 */
static uint32_t isqrt(uint32_t n) {
    if (n < 2) return n;
    uint32_t x = n >> 1;          /* initial guess: avoids overflow of (n+1)/2 */
    uint32_t y = (x + n / x) / 2;
    while (y < x) {
        x = y;
        y = (x + n / x) / 2;
    }
    return x;
}

static void test_isqrt(void) {
    log_write(NONE, "\n=== Integer Square Root ===\n");
    struct { uint32_t n; uint32_t exp; } cases[] = {
        {0, 0}, {1, 1}, {4, 2}, {9, 3}, {16, 4}, {25, 5},
        {100, 10}, {1024, 32}, {65536, 256}, {1000000, 1000},
        {0xFFFFFFFFu, 65535u},  /* floor(sqrt(2^32-1)) = 65535 */
    };
    for (size_t i = 0; i < sizeof cases / sizeof cases[0]; i++) {
        uint32_t got = isqrt(cases[i].n);
        if (got == cases[i].exp) {
            log_write(NONE, "  PASS  isqrt(%d)=%d\n", (int)cases[i].n, (int)cases[i].exp);
            g_pass++;
        } else {
            log_write(NONE, "  FAIL  isqrt(%d): got %d  exp %d\n",
                      (int)cases[i].n, (int)got, (int)cases[i].exp);
            g_fail++;
        }
    }
}

/* -- Saturating 32-bit arithmetic ---------------------------------------- */
static int32_t sat_add32(int32_t a, int32_t b) {
    int64_t s = (int64_t)a + (int64_t)b;
    if (s >  0x7FFFFFFF) return  0x7FFFFFFF;
    if (s < -(int64_t)0x80000000) return (int32_t)(uint32_t)0x80000000u;
    return (int32_t)s;
}
static int32_t sat_sub32(int32_t a, int32_t b) {
    int64_t s = (int64_t)a - (int64_t)b;
    if (s >  0x7FFFFFFF) return  0x7FFFFFFF;
    if (s < -(int64_t)0x80000000) return (int32_t)(uint32_t)0x80000000u;
    return (int32_t)s;
}

static void test_saturation(void) {
    log_write(NONE, "\n=== Saturating 32-bit Arithmetic ===\n");
    chk32("sat_add(MAX,1)=MAX",     sat_add32(0x7FFFFFFF,  1),     0x7FFFFFFF);
    chk32("sat_add(MIN,-1)=MIN",    sat_add32((int32_t)0x80000000u, -1), (int32_t)0x80000000u);
    chk32("sat_add(0,0)=0",         sat_add32(0, 0), 0);
    chk32("sat_add(100,200)=300",   sat_add32(100, 200), 300);
    chk32("sat_sub(MIN,1)=MIN",     sat_sub32((int32_t)0x80000000u, 1), (int32_t)0x80000000u);
    chk32("sat_sub(MAX,-1)=MAX",    sat_sub32(0x7FFFFFFF, -1), 0x7FFFFFFF);
    chk32("sat_sub(5,3)=2",         sat_sub32(5, 3), 2);
}

/* -- Main ------------------------------------------------------------------- */

int main(void) {
    uart_puts("=== Fixed-Point Arithmetic Test ===\n");
    if (log_init("fixedpoint-test.log") != 0) {
        uart_puts("ERROR: log_init failed\n"); return 1;
    }
    log_write(NONE, "=== Fixed-Point Arithmetic Test (Q15, Q16.16, FIR, CORDIC) ===\n");

    test_q15();
    test_q16();
    test_fir();
    test_cordic();
    test_isqrt();
    test_saturation();

    log_write(NONE, "\n=== Summary ===\n");
    log_write(NONE, "  PASS: %d\n", g_pass);
    log_write(NONE, "  FAIL: %d\n", g_fail);
    log_write(NONE, "  %s\n", g_fail == 0 ? "ALL TESTS PASSED" : "SOME TESTS FAILED");
    log_close();

    uart_puts(g_fail == 0 ? "ALL PASSED\n" : "SOME FAILED\n");
    return g_fail;
}
