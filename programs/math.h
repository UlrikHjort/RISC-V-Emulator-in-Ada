/* **************************************************************************
 *          RISC-V Emulator - Mathematical Constants and Functions
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

#ifndef MATH_H
#define MATH_H

// Mathematical constants
#define M_E        2.71828182845904523536   // e
#define M_LOG2E    1.44269504088896340736   // log2(e)
#define M_LOG10E   0.43429448190325182765   // log10(e)
#define M_LN2      0.69314718055994530942   // ln(2)
#define M_LN10     2.30258509299404568402   // ln(10)
#define M_PI       3.14159265358979323846   // pi
#define M_PI_2     1.57079632679489661923   // pi/2
#define M_PI_4     0.78539816339744830962   // pi/4
#define M_1_PI     0.31830988618379067154   // 1/pi
#define M_2_PI     0.63661977236758134308   // 2/pi
#define M_2_SQRTPI 1.12837916709551257390   // 2/sqrt(pi)
#define M_SQRT2    1.41421356237309504880   // sqrt(2)
#define M_SQRT1_2  0.70710678118654752440   // 1/sqrt(2)

// Special values
#define INFINITY   (1.0/0.0)
#define NAN        (0.0/0.0)
#define HUGE_VAL   INFINITY

// Classification macros
#define FP_INFINITE  1
#define FP_NAN       2
#define FP_NORMAL    3
#define FP_SUBNORMAL 4
#define FP_ZERO      5

// ============================================================================
// Basic Functions
// ============================================================================

// Absolute value
double fabs(double x);
float fabsf(float x);

// Modulo (floating-point remainder)
double fmod(double x, double y);
float fmodf(float x, float y);

// Floor, ceiling, and rounding
double floor(double x);
float floorf(float x);

double ceil(double x);
float ceilf(float x);

double round(double x);
float roundf(float x);

double trunc(double x);
float truncf(float x);

// ============================================================================
// Power and Root Functions
// ============================================================================

// Square root
double sqrt(double x);
float sqrtf(float x);

// Cube root
double cbrt(double x);
float cbrtf(float x);

// Power function (x^y)
double pow(double x, double y);
float powf(float x, float y);

// Hypotenuse (sqrt(x^2 + y^2) without overflow)
double hypot(double x, double y);
float hypotf(float x, float y);

// ============================================================================
// Exponential and Logarithm Functions
// ============================================================================

// Exponential (e^x)
double exp(double x);
float expf(float x);

// Natural logarithm (ln(x))
double log(double x);
float logf(float x);

// Base-10 logarithm
double log10(double x);
float log10f(float x);

// Base-2 logarithm
double log2(double x);
float log2f(float x);

// exp(x) - 1 (accurate for small x)
double expm1(double x);
float expm1f(float x);

// log(1 + x) (accurate for small x)
double log1p(double x);
float log1pf(float x);

// ============================================================================
// Trigonometric Functions
// ============================================================================

// Sine, cosine, tangent
double sin(double x);
float sinf(float x);

double cos(double x);
float cosf(float x);

double tan(double x);
float tanf(float x);

// Inverse trigonometric functions
double asin(double x);
float asinf(float x);

double acos(double x);
float acosf(float x);

double atan(double x);
float atanf(float x);

double atan2(double y, double x);
float atan2f(float y, float x);

// ============================================================================
// Hyperbolic Functions
// ============================================================================

double sinh(double x);
float sinhf(float x);

double cosh(double x);
float coshf(float x);

double tanh(double x);
float tanhf(float x);

double asinh(double x);
float asinhf(float x);

double acosh(double x);
float acoshf(float x);

double atanh(double x);
float atanhf(float x);

// ============================================================================
// Utility Functions
// ============================================================================

// Classify floating-point value
int fpclassify(double x);
int fpclassifyf(float x);

// Check for NaN
int isnan(double x);
int isnanf(float x);

// Check for infinity
int isinf(double x);
int isinff(float x);

// Check for finite value
int isfinite(double x);
int isfinitef(float x);

// Check for normal value
int isnormal(double x);
int isnormalf(float x);

// Sign bit
int signbit(double x);
int signbitf(float x);

// Copy sign
double copysign(double x, double y);
float copysignf(float x, float y);

// Decompose floating-point number
double frexp(double x, int *exp);
float frexpf(float x, int *exp);

// Multiply by power of 2
double ldexp(double x, int exp);
float ldexpf(float x, int exp);

// Extract mantissa and exponent
double modf(double x, double *iptr);
float modff(float x, float *iptr);

// Scale by FLT_RADIX to the power of n
double scalbn(double x, int n);
float scalbnf(float x, int n);

// ============================================================================
// Min/Max Functions
// ============================================================================

double fmin(double x, double y);
float fminf(float x, float y);

double fmax(double x, double y);
float fmaxf(float x, float y);

// Fused multiply-add: (x * y) + z
double fma(double x, double y, double z);
float fmaf(float x, float y, float z);

#endif // MATH_H
