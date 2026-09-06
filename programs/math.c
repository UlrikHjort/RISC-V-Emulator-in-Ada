/* **************************************************************************
 *         RISC-V Emulator - Bare-metal math library implementation
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

// Bare-metal math library implementation
// Uses Taylor series and polynomial approximations
// Optimized for reasonable accuracy (not full IEEE 754 precision)
// By Ulrik Hørlyk Hjort 2026

#include "math.h"

// ============================================================================
// Utility Functions
// ============================================================================

// Check if value is NaN
int isnan(double x) {
    return x != x;
}

int isnanf(float x) {
    return x != x;
}

// Check if value is infinite
int isinf(double x) {
    return !isnan(x) && isnan(x - x);
}

int isinff(float x) {
    return !isnanf(x) && isnanf(x - x);
}

// Check if value is finite
int isfinite(double x) {
    return !isnan(x) && !isinf(x);
}

int isfinitef(float x) {
    return !isnanf(x) && !isinff(x);
}

// Classify floating-point value
int fpclassify(double x) {
    if (isnan(x)) return FP_NAN;
    if (isinf(x)) return FP_INFINITE;
    if (x == 0.0) return FP_ZERO;
    // Simplified: don't distinguish subnormal
    return FP_NORMAL;
}

int fpclassifyf(float x) {
    if (isnanf(x)) return FP_NAN;
    if (isinff(x)) return FP_INFINITE;
    if (x == 0.0f) return FP_ZERO;
    return FP_NORMAL;
}

// Check for normal value
int isnormal(double x) {
    return fpclassify(x) == FP_NORMAL;
}

int isnormalf(float x) {
    return fpclassifyf(x) == FP_NORMAL;
}

// Get sign bit (1 if negative, 0 if positive)
int signbit(double x) {
    // Use bit manipulation to check sign
    unsigned long long bits;
    __builtin_memcpy(&bits, &x, sizeof(x));
    return (bits >> 63) & 1;
}

int signbitf(float x) {
    unsigned int bits;
    __builtin_memcpy(&bits, &x, sizeof(x));
    return (bits >> 31) & 1;
}

// Copy sign from y to x
double copysign(double x, double y) {
    double result = fabs(x);
    return signbit(y) ? -result : result;
}

float copysignf(float x, float y) {
    float result = fabsf(x);
    return signbitf(y) ? -result : result;
}

// ============================================================================
// Basic Functions
// ============================================================================

// Absolute value
double fabs(double x) {
    return x < 0.0 ? -x : x;
}

float fabsf(float x) {
    return x < 0.0f ? -x : x;
}

// Floor (round down to integer)
double floor(double x) {
    if (isnan(x) || isinf(x)) return x;
    if (x >= 0.0) {
        return (double)(int)x;
    } else {
        int i = (int)x;
        double d = (double)i;
        // If x is negative and not an integer, subtract 1
        return (x == d) ? d : d - 1.0;
    }
}

float floorf(float x) {
    if (isnanf(x) || isinff(x)) return x;

    int i = (int)x;
    float f = (float)i;

    if (x < f) return f - 1.0f;
    return f;
}

// Ceiling (round up to integer)
double ceil(double x) {
    if (isnan(x) || isinf(x)) return x;
    if (x <= 0.0) {
        return (double)(int)x;
    } else {
        int i = (int)x;
        double d = (double)i;
        // If x is positive and not an integer, add 1
        return (x == d) ? d : d + 1.0;
    }
}

float ceilf(float x) {
    if (isnanf(x) || isinff(x)) return x;

    int i = (int)x;
    float f = (float)i;

    if (x > f) return f + 1.0f;
    return f;
}

// Round to nearest integer (ties round away from zero)
double round(double x) {
    if (isnan(x) || isinf(x)) return x;

    if (x >= 0.0) {
        return floor(x + 0.5);
    } else {
        return ceil(x - 0.5);
    }
}

float roundf(float x) {
    if (isnanf(x) || isinff(x)) return x;

    if (x >= 0.0f) {
        return floorf(x + 0.5f);
    } else {
        return ceilf(x - 0.5f);
    }
}

// Truncate to integer (round towards zero)
double trunc(double x) {
    if (isnan(x) || isinf(x)) return x;
    return (double)(int)x;
}

float truncf(float x) {
    if (isnanf(x) || isinff(x)) return x;
    return (float)(int)x;
}

// Floating-point remainder
double fmod(double x, double y) {
    if (isnan(x) || isnan(y) || isinf(x) || y == 0.0) return NAN;
    if (isinf(y)) return x;

    double result = x - trunc(x / y) * y;
    return result;
}

float fmodf(float x, float y) {
    if (isnanf(x) || isnanf(y) || isinff(x) || y == 0.0f) return NAN;
    if (isinff(y)) return x;

    float result = x - truncf(x / y) * y;
    return result;
}

// Decompose into mantissa and exponent: x = mantissa * 2^exp
double frexp(double x, int *exp) {
    if (x == 0.0 || !isfinite(x)) {
        *exp = 0;
        return x;
    }

    int e = 0;
    double m = x;

    // Normalize to [0.5, 1.0)
    if (fabs(m) >= 1.0) {
        while (fabs(m) >= 1.0) {
            m *= 0.5;
            e++;
        }
    } else {
        while (fabs(m) < 0.5) {
            m *= 2.0;
            e--;
        }
    }

    *exp = e;
    return m;
}

float frexpf(float x, int *exp) {
    if (x == 0.0f || !isfinitef(x)) {
        *exp = 0;
        return x;
    }

    int e = 0;
    float m = x;

    if (fabsf(m) >= 1.0f) {
        while (fabsf(m) >= 1.0f) {
            m *= 0.5f;
            e++;
        }
    } else {
        while (fabsf(m) < 0.5f) {
            m *= 2.0f;
            e--;
        }
    }

    *exp = e;
    return m;
}

// Multiply by power of 2: x * 2^exp
double ldexp(double x, int exp) {
    if (!isfinite(x) || x == 0.0) return x;

    double result = x;
    if (exp > 0) {
        while (exp-- > 0) result *= 2.0;
    } else {
        while (exp++ < 0) result *= 0.5;
    }
    return result;
}

float ldexpf(float x, int exp) {
    if (!isfinitef(x) || x == 0.0f) return x;

    float result = x;
    if (exp > 0) {
        while (exp-- > 0) result *= 2.0f;
    } else {
        while (exp++ < 0) result *= 0.5f;
    }
    return result;
}

// Same as ldexp for binary floating point
double scalbn(double x, int n) {
    return ldexp(x, n);
}

float scalbnf(float x, int n) {
    return ldexpf(x, n);
}

// Extract integer and fractional parts
double modf(double x, double *iptr) {
    *iptr = trunc(x);
    return x - *iptr;
}

float modff(float x, float *iptr) {
    *iptr = truncf(x);
    return x - *iptr;
}

// Min/Max
double fmin(double x, double y) {
    if (isnan(x)) return y;
    if (isnan(y)) return x;
    return x < y ? x : y;
}

float fminf(float x, float y) {
    if (isnanf(x)) return y;
    if (isnanf(y)) return x;
    return x < y ? x : y;
}

double fmax(double x, double y) {
    if (isnan(x)) return y;
    if (isnan(y)) return x;
    return x > y ? x : y;
}

float fmaxf(float x, float y) {
    if (isnanf(x)) return y;
    if (isnanf(y)) return x;
    return x > y ? x : y;
}

// Fused multiply-add: (x * y) + z
// Note: This won't have the precision of a true FMA, but it's functionally correct
double fma(double x, double y, double z) {
    return (x * y) + z;
}

float fmaf(float x, float y, float z) {
    return (x * y) + z;
}

// ============================================================================
// Square Root
// ============================================================================

// Square root using Newton-Raphson method
double sqrt(double x) {
    if (isnan(x) || x < 0.0) return NAN;
    if (isinf(x) || x == 0.0) return x;

    // Initial guess using bit manipulation for fast convergence
    double guess = x;
    double prev;

    // Newton-Raphson: x_new = 0.5 * (x_old + n / x_old)
    do {
        prev = guess;
        guess = 0.5 * (guess + x / guess);
    } while (fabs(guess - prev) > 1e-10 * guess);

    return guess;
}

float sqrtf(float x) {
    if (isnanf(x) || x < 0.0f) return NAN;
    if (isinff(x) || x == 0.0f) return x;

    float guess = x;
    float prev;

    do {
        prev = guess;
        guess = 0.5f * (guess + x / guess);
    } while (fabsf(guess - prev) > 1e-6f * guess);

    return guess;
}

// Cube root
double cbrt(double x) {
    if (!isfinite(x) || x == 0.0) return x;

    int sign = signbit(x) ? -1 : 1;
    x = fabs(x);

    // Newton-Raphson: x_new = (2*x_old + n/x_old^2) / 3
    double guess = x;
    double prev;

    do {
        prev = guess;
        guess = (2.0 * guess + x / (guess * guess)) / 3.0;
    } while (fabs(guess - prev) > 1e-10 * guess);

    return sign * guess;
}

float cbrtf(float x) {
    if (!isfinitef(x) || x == 0.0f) return x;

    int sign = signbitf(x) ? -1 : 1;
    x = fabsf(x);

    float guess = x;
    float prev;

    do {
        prev = guess;
        guess = (2.0f * guess + x / (guess * guess)) / 3.0f;
    } while (fabsf(guess - prev) > 1e-6f * guess);

    return sign * guess;
}

// Hypotenuse: sqrt(x^2 + y^2) avoiding overflow
double hypot(double x, double y) {
    x = fabs(x);
    y = fabs(y);

    if (x == 0.0) return y;
    if (y == 0.0) return x;

    // Scale to avoid overflow
    if (x > y) {
        double t = y / x;
        return x * sqrt(1.0 + t * t);
    } else {
        double t = x / y;
        return y * sqrt(1.0 + t * t);
    }
}

float hypotf(float x, float y) {
    x = fabsf(x);
    y = fabsf(y);

    if (x == 0.0f) return y;
    if (y == 0.0f) return x;

    if (x > y) {
        float t = y / x;
        return x * sqrtf(1.0f + t * t);
    } else {
        float t = x / y;
        return y * sqrtf(1.0f + t * t);
    }
}

// ============================================================================
// Exponential and Logarithm
// ============================================================================

// Natural exponential (e^x) using Taylor series
double exp(double x) {
    if (isnan(x)) return x;
    if (isinf(x)) return x > 0 ? x : 0.0;

    // Handle large values to avoid overflow
    if (x > 709.0) return INFINITY;
    if (x < -709.0) return 0.0;

    // exp(x) = exp(n*ln(2) + r) = 2^n * exp(r) where |r| < ln(2)/2
    int n = (int)round(x / M_LN2);
    double r = x - n * M_LN2;

    // Taylor series for exp(r): 1 + r + r^2/2! + r^3/3! + ...
    double sum = 1.0;
    double term = 1.0;

    for (int i = 1; i < 20; i++) {
        term *= r / i;
        sum += term;
        if (fabs(term) < 1e-15) break;
    }

    // Multiply by 2^n
    return ldexp(sum, n);
}

float expf(float x) {
    if (isnanf(x)) return x;
    if (isinff(x)) return x > 0 ? x : 0.0f;

    if (x > 88.0f) return INFINITY;
    if (x < -88.0f) return 0.0f;

    int n = (int)roundf(x / (float)M_LN2);
    float r = x - n * (float)M_LN2;

    float sum = 1.0f;
    float term = 1.0f;

    for (int i = 1; i < 15; i++) {
        term *= r / i;
        sum += term;
        if (fabsf(term) < 1e-7f) break;
    }

    return ldexpf(sum, n);
}

// Natural logarithm (ln(x))
double log(double x) {
    if (isnan(x) || x < 0.0) return NAN;
    if (x == 0.0) return -INFINITY;
    if (isinf(x)) return x;
    if (x == 1.0) return 0.0;

    // Extract exponent: x = m * 2^e where 0.5 <= m < 1
    int e;
    double m = frexp(x, &e);

    // Adjust to [1/sqrt(2), sqrt(2)] range
    if (m < M_SQRT1_2) {
        m *= 2.0;
        e--;
    }

    // ln(x) = ln(m * 2^e) = ln(m) + e * ln(2)
    // Use ln((1+y)/(1-y)) = 2*(y + y^3/3 + y^5/5 + ...)
    // where y = (m-1)/(m+1)
    double y = (m - 1.0) / (m + 1.0);
    double y2 = y * y;
    double sum = y;
    double term = y;

    for (int i = 1; i < 20; i++) {
        term *= y2;
        sum += term / (2 * i + 1);
        if (fabs(term / (2 * i + 1)) < 1e-15) break;
    }

    return 2.0 * sum + e * M_LN2;
}

float logf(float x) {
    if (isnanf(x) || x < 0.0f) return NAN;
    if (x == 0.0f) return -INFINITY;
    if (isinff(x)) return x;
    if (x == 1.0f) return 0.0f;

    int e;
    float m = frexpf(x, &e);

    if (m < (float)M_SQRT1_2) {
        m *= 2.0f;
        e--;
    }

    float y = (m - 1.0f) / (m + 1.0f);
    float y2 = y * y;
    float sum = y;
    float term = y;

    for (int i = 1; i < 15; i++) {
        term *= y2;
        sum += term / (2 * i + 1);
        if (fabsf(term / (2 * i + 1)) < 1e-7f) break;
    }

    return 2.0f * sum + e * (float)M_LN2;
}

// Base-10 logarithm
double log10(double x) {
    return log(x) * M_LOG10E;
}

float log10f(float x) {
    return logf(x) * (float)M_LOG10E;
}

// Base-2 logarithm
double log2(double x) {
    return log(x) * M_LOG2E;
}

float log2f(float x) {
    return logf(x) * (float)M_LOG2E;
}

// exp(x) - 1 (accurate for small x)
double expm1(double x) {
    if (fabs(x) < 1e-5) {
        // Use Taylor series for small x to avoid cancellation
        return x + x*x/2.0 + x*x*x/6.0;
    }
    return exp(x) - 1.0;
}

float expm1f(float x) {
    if (fabsf(x) < 1e-4f) {
        return x + x*x/2.0f + x*x*x/6.0f;
    }
    return expf(x) - 1.0f;
}

// log(1 + x) (accurate for small x)
double log1p(double x) {
    if (fabs(x) < 1e-5) {
        // Use Taylor series for small x
        return x - x*x/2.0 + x*x*x/3.0;
    }
    return log(1.0 + x);
}

float log1pf(float x) {
    if (fabsf(x) < 1e-4f) {
        return x - x*x/2.0f + x*x*x/3.0f;
    }
    return logf(1.0f + x);
}

// Power function: x^y
double pow(double x, double y) {
    // Special cases
    if (y == 0.0) return 1.0;
    if (x == 1.0) return 1.0;
    if (isnan(x) || isnan(y)) return NAN;

    if (x == 0.0) {
        if (y < 0.0) return INFINITY;
        return 0.0;
    }

    // For integer exponents, use repeated multiplication
    if (y == floor(y) && fabs(y) < 100.0) {
        int n = (int)y;
        double result = 1.0;
        double base = x;
        int neg = 0;

        if (n < 0) {
            n = -n;
            neg = 1;
        }

        while (n > 0) {
            if (n & 1) result *= base;
            base *= base;
            n >>= 1;
        }

        return neg ? 1.0 / result : result;
    }

    // General case: x^y = exp(y * ln(x))
    if (x < 0.0) return NAN;  // Negative base with non-integer exponent
    return exp(y * log(x));
}

float powf(float x, float y) {
    if (y == 0.0f) return 1.0f;
    if (x == 1.0f) return 1.0f;
    if (isnanf(x) || isnanf(y)) return NAN;

    if (x == 0.0f) {
        if (y < 0.0f) return INFINITY;
        return 0.0f;
    }

    if (y == floorf(y) && fabsf(y) < 100.0f) {
        int n = (int)y;
        float result = 1.0f;
        float base = x;
        int neg = 0;

        if (n < 0) {
            n = -n;
            neg = 1;
        }

        while (n > 0) {
            if (n & 1) result *= base;
            base *= base;
            n >>= 1;
        }

        return neg ? 1.0f / result : result;
    }

    if (x < 0.0f) return NAN;
    return expf(y * logf(x));
}

// ============================================================================
// Trigonometric Functions
// ============================================================================

// Reduce angle to [-pi, pi]
static double reduce_angle(double x) {
    // Reduce to [-2*pi, 2*pi]
    double periods = round(x / (2.0 * M_PI));
    x -= periods * 2.0 * M_PI;

    // Further reduce to [-pi, pi]
    if (x > M_PI) x -= 2.0 * M_PI;
    if (x < -M_PI) x += 2.0 * M_PI;

    return x;
}

static float reduce_anglef(float x) {
    float periods = roundf(x / (2.0f * (float)M_PI));
    x -= periods * 2.0f * (float)M_PI;

    if (x > (float)M_PI) x -= 2.0f * (float)M_PI;
    if (x < -(float)M_PI) x += 2.0f * (float)M_PI;

    return x;
}

// Sine using Taylor series
double sin(double x) {
    if (!isfinite(x)) return NAN;

    x = reduce_angle(x);

    // Taylor series: sin(x) = x - x^3/3! + x^5/5! - x^7/7! + ...
    double sum = x;
    double term = x;
    double x2 = x * x;

    for (int i = 1; i < 20; i++) {
        term *= -x2 / ((2 * i) * (2 * i + 1));
        sum += term;
        if (fabs(term) < 1e-15) break;
    }

    return sum;
}

float sinf(float x) {
    if (!isfinitef(x)) return NAN;

    x = reduce_anglef(x);

    float sum = x;
    float term = x;
    float x2 = x * x;

    for (int i = 1; i < 15; i++) {
        term *= -x2 / ((2 * i) * (2 * i + 1));
        sum += term;
        if (fabsf(term) < 1e-7f) break;
    }

    return sum;
}

// Cosine using Taylor series
double cos(double x) {
    if (!isfinite(x)) return NAN;

    x = reduce_angle(x);

    // Taylor series: cos(x) = 1 - x^2/2! + x^4/4! - x^6/6! + ...
    double sum = 1.0;
    double term = 1.0;
    double x2 = x * x;

    for (int i = 1; i < 20; i++) {
        term *= -x2 / ((2 * i - 1) * (2 * i));
        sum += term;
        if (fabs(term) < 1e-15) break;
    }

    return sum;
}

float cosf(float x) {
    if (!isfinitef(x)) return NAN;

    x = reduce_anglef(x);

    float sum = 1.0f;
    float term = 1.0f;
    float x2 = x * x;

    for (int i = 1; i < 15; i++) {
        term *= -x2 / ((2 * i - 1) * (2 * i));
        sum += term;
        if (fabsf(term) < 1e-7f) break;
    }

    return sum;
}

// Tangent
double tan(double x) {
    double c = cos(x);
    if (fabs(c) < 1e-15) return copysign(INFINITY, x);
    return sin(x) / c;
}

float tanf(float x) {
    float c = cosf(x);
    if (fabsf(c) < 1e-7f) return copysignf(INFINITY, x);
    return sinf(x) / c;
}

// Arcsine
double asin(double x) {
    if (x < -1.0 || x > 1.0) return NAN;
    if (x == -1.0) return -M_PI_2;
    if (x == 1.0) return M_PI_2;

    // Use atan2(x, sqrt(1 - x^2))
    return atan2(x, sqrt(1.0 - x * x));
}

float asinf(float x) {
    if (x < -1.0f || x > 1.0f) return NAN;
    if (x == -1.0f) return -(float)M_PI_2;
    if (x == 1.0f) return (float)M_PI_2;

    return atan2f(x, sqrtf(1.0f - x * x));
}

// Arccosine
double acos(double x) {
    if (x < -1.0 || x > 1.0) return NAN;
    return M_PI_2 - asin(x);
}

float acosf(float x) {
    if (x < -1.0f || x > 1.0f) return NAN;
    return (float)M_PI_2 - asinf(x);
}

// Arctangent
double atan(double x) {
    if (isnan(x)) return x;
    if (isinf(x)) return copysign(M_PI_2, x);

    // For better convergence, use argument reduction:
    // atan(x) = 2*atan(x / (1 + sqrt(1 + x^2)))
    // This transforms |x| > 0.4 to smaller values
    int reduce_count = 0;
    while (fabs(x) > 0.4 && reduce_count < 3) {
        x = x / (1.0 + sqrt(1.0 + x * x));
        reduce_count++;
    }

    // Taylor series: atan(x) = x - x^3/3 + x^5/5 - x^7/7 + ...
    // Converges well for |x| < 0.5
    double sum = x;
    double term = x;
    double x2 = x * x;

    for (int i = 1; i < 100; i++) {
        term *= -x2;
        double delta = term / (2 * i + 1);
        sum += delta;
        if (fabs(delta) < 1e-16) break;
    }

    // Undo the argument reduction: atan(x) was called reduce_count times
    // So result = 2^reduce_count * sum
    for (int i = 0; i < reduce_count; i++) {
        sum *= 2.0;
    }

    return sum;
}

float atanf(float x) {
    if (isnanf(x)) return x;
    if (isinff(x)) return copysignf((float)M_PI_2, x);

    // Argument reduction for better convergence
    int reduce_count = 0;
    while (fabsf(x) > 0.4f && reduce_count < 3) {
        x = x / (1.0f + sqrtf(1.0f + x * x));
        reduce_count++;
    }

    float sum = x;
    float term = x;
    float x2 = x * x;

    for (int i = 1; i < 50; i++) {
        term *= -x2;
        float delta = term / (2 * i + 1);
        sum += delta;
        if (fabsf(delta) < 1e-8f) break;
    }

    // Undo the argument reduction
    for (int i = 0; i < reduce_count; i++) {
        sum *= 2.0f;
    }

    return sum;
}

// Two-argument arctangent
double atan2(double y, double x) {
    if (isnan(x) || isnan(y)) return NAN;

    // Special cases
    if (x == 0.0) {
        if (y > 0.0) return M_PI_2;
        if (y < 0.0) return -M_PI_2;
        return 0.0;  // Both zero
    }

    double result = atan(y / x);

    // Adjust quadrant
    if (x < 0.0) {
        if (y >= 0.0)
            result += M_PI;
        else
            result -= M_PI;
    }

    return result;
}

float atan2f(float y, float x) {
    if (isnanf(x) || isnanf(y)) return NAN;

    if (x == 0.0f) {
        if (y > 0.0f) return (float)M_PI_2;
        if (y < 0.0f) return -(float)M_PI_2;
        return 0.0f;
    }

    float result = atanf(y / x);

    if (x < 0.0f) {
        if (y >= 0.0f)
            result += (float)M_PI;
        else
            result -= (float)M_PI;
    }

    return result;
}

// ============================================================================
// Hyperbolic Functions
// ============================================================================

// Hyperbolic sine
double sinh(double x) {
    if (!isfinite(x)) return x;

    // sinh(x) = (e^x - e^(-x)) / 2
    if (fabs(x) < 1.0) {
        // Use Taylor series for small x to avoid cancellation
        double x2 = x * x;
        double sum = x;
        double term = x;

        for (int i = 1; i < 20; i++) {
            term *= x2 / ((2 * i) * (2 * i + 1));
            sum += term;
            if (fabs(term) < 1e-15) break;
        }
        return sum;
    }

    double e_x = exp(x);
    return (e_x - 1.0 / e_x) * 0.5;
}

float sinhf(float x) {
    if (!isfinitef(x)) return x;

    if (fabsf(x) < 1.0f) {
        float x2 = x * x;
        float sum = x;
        float term = x;

        for (int i = 1; i < 15; i++) {
            term *= x2 / ((2 * i) * (2 * i + 1));
            sum += term;
            if (fabsf(term) < 1e-7f) break;
        }
        return sum;
    }

    float e_x = expf(x);
    return (e_x - 1.0f / e_x) * 0.5f;
}

// Hyperbolic cosine
double cosh(double x) {
    if (!isfinite(x)) return fabs(x);

    // cosh(x) = (e^x + e^(-x)) / 2
    double e_x = exp(fabs(x));  // cosh is even
    return (e_x + 1.0 / e_x) * 0.5;
}

float coshf(float x) {
    if (!isfinitef(x)) return fabsf(x);

    float e_x = expf(fabsf(x));
    return (e_x + 1.0f / e_x) * 0.5f;
}

// Hyperbolic tangent
double tanh(double x) {
    if (!isfinite(x)) return copysign(1.0, x);

    if (fabs(x) > 20.0) return copysign(1.0, x);

    // tanh(x) = sinh(x) / cosh(x) = (e^(2x) - 1) / (e^(2x) + 1)
    double e_2x = exp(2.0 * x);
    return (e_2x - 1.0) / (e_2x + 1.0);
}

float tanhf(float x) {
    if (!isfinitef(x)) return copysignf(1.0f, x);

    if (fabsf(x) > 15.0f) return copysignf(1.0f, x);

    float e_2x = expf(2.0f * x);
    return (e_2x - 1.0f) / (e_2x + 1.0f);
}

// Inverse hyperbolic sine
double asinh(double x) {
    if (!isfinite(x)) return x;
    // asinh(x) = ln(x + sqrt(x^2 + 1))
    return log(x + sqrt(x * x + 1.0));
}

float asinhf(float x) {
    if (!isfinitef(x)) return x;
    return logf(x + sqrtf(x * x + 1.0f));
}

// Inverse hyperbolic cosine
double acosh(double x) {
    if (x < 1.0) return NAN;
    // acosh(x) = ln(x + sqrt(x^2 - 1))
    return log(x + sqrt(x * x - 1.0));
}

float acoshf(float x) {
    if (x < 1.0f) return NAN;
    return logf(x + sqrtf(x * x - 1.0f));
}

// Inverse hyperbolic tangent
double atanh(double x) {
    if (x <= -1.0 || x >= 1.0) return NAN;
    // atanh(x) = 0.5 * ln((1+x)/(1-x))
    return 0.5 * log((1.0 + x) / (1.0 - x));
}

float atanhf(float x) {
    if (x <= -1.0f || x >= 1.0f) return NAN;
    return 0.5f * logf((1.0f + x) / (1.0f - x));
}
