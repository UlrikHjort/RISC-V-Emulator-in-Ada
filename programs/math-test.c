/* **************************************************************************
 *      RISC-V Emulator - Comprehensive test program for math library
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

// Comprehensive test program for math library
// Tests all mathematical functions with known values
// By Ulrik Hørlyk Hjort 2026

#include "uart.h"
#include "printf.h"
#include "math.h"

// Test counter
static int tests_run = 0;
static int tests_passed = 0;
static int tests_failed = 0;

// Tolerance for floating-point comparison
#define TOLERANCE 1e-6
#define TOLERANCE_F 1e-5f

// Compare doubles with tolerance
static int approx_equal(double a, double b, double tol) {
    if (isnan(a) && isnan(b)) return 1;
    if (isinf(a) && isinf(b) && signbit(a) == signbit(b)) return 1;
    return fabs(a - b) <= tol;
}

// Compare floats with tolerance
static int approx_equalf(float a, float b, float tol) {
    if (isnanf(a) && isnanf(b)) return 1;
    if (isinff(a) && isinff(b) && signbitf(a) == signbitf(b)) return 1;
    return fabsf(a - b) <= tol;
}

// Test macro for double values
#define TEST_DOUBLE(name, expr, expected) do { \
    tests_run++; \
    double result = (expr); \
    if (approx_equal(result, expected, TOLERANCE)) { \
        tests_passed++; \
        printf("  PASS: %s\n", name); \
    } else { \
        tests_failed++; \
        printf("  FAIL: %s - got %f, expected %f\n", name, result, expected); \
    } \
} while(0)

// Test macro for float values
#define TEST_FLOAT(name, expr, expected) do { \
    tests_run++; \
    float result = (expr); \
    if (approx_equalf(result, expected, TOLERANCE_F)) { \
        tests_passed++; \
        printf("  PASS: %s\n", name); \
    } else { \
        tests_failed++; \
        printf("  FAIL: %s - got %f, expected %f\n", name, result, expected); \
    } \
} while(0)

// Test macro for boolean conditions
#define TEST_BOOL(name, expr) do { \
    tests_run++; \
    if (expr) { \
        tests_passed++; \
        printf("  PASS: %s\n", name); \
    } else { \
        tests_failed++; \
        printf("  FAIL: %s\n", name); \
    } \
} while(0)

void test_basic_functions(void) {
    printf("\n=== Testing Basic Functions ===\n");

    TEST_DOUBLE("fabs(3.5)", fabs(3.5), 3.5);
    TEST_DOUBLE("fabs(-3.5)", fabs(-3.5), 3.5);

    TEST_DOUBLE("floor(3.7)", floor(3.7), 3.0);
    TEST_DOUBLE("floor(-3.7)", floor(-3.7), -4.0);

    TEST_DOUBLE("ceil(3.2)", ceil(3.2), 4.0);
    TEST_DOUBLE("ceil(-3.2)", ceil(-3.2), -3.0);

    TEST_DOUBLE("round(3.5)", round(3.5), 4.0);
    TEST_DOUBLE("round(3.4)", round(3.4), 3.0);
    TEST_DOUBLE("round(-3.5)", round(-3.5), -4.0);

    TEST_DOUBLE("trunc(3.9)", trunc(3.9), 3.0);
    TEST_DOUBLE("trunc(-3.9)", trunc(-3.9), -3.0);

    TEST_DOUBLE("fmod(7.5, 2.0)", fmod(7.5, 2.0), 1.5);
    TEST_DOUBLE("fmod(-7.5, 2.0)", fmod(-7.5, 2.0), -1.5);
}

void test_sqrt_and_roots(void) {
    printf("\n=== Testing Square and Cube Roots ===\n");

    TEST_DOUBLE("sqrt(4.0)", sqrt(4.0), 2.0);
    TEST_DOUBLE("sqrt(9.0)", sqrt(9.0), 3.0);
    TEST_DOUBLE("sqrt(2.0)", sqrt(2.0), M_SQRT2);
    TEST_DOUBLE("sqrt(0.5)", sqrt(0.5), M_SQRT1_2);

    TEST_DOUBLE("cbrt(8.0)", cbrt(8.0), 2.0);
    TEST_DOUBLE("cbrt(27.0)", cbrt(27.0), 3.0);
    TEST_DOUBLE("cbrt(-8.0)", cbrt(-8.0), -2.0);

    TEST_DOUBLE("hypot(3.0, 4.0)", hypot(3.0, 4.0), 5.0);
    TEST_DOUBLE("hypot(5.0, 12.0)", hypot(5.0, 12.0), 13.0);
}

void test_exponential_and_log(void) {
    printf("\n=== Testing Exponential and Logarithm ===\n");

    TEST_DOUBLE("exp(0.0)", exp(0.0), 1.0);
    TEST_DOUBLE("exp(1.0)", exp(1.0), M_E);
    TEST_DOUBLE("exp(2.0)", exp(2.0), M_E * M_E);

    TEST_DOUBLE("log(1.0)", log(1.0), 0.0);
    TEST_DOUBLE("log(M_E)", log(M_E), 1.0);
    TEST_DOUBLE("log(10.0)", log(10.0), M_LN10);
    TEST_DOUBLE("log(2.0)", log(2.0), M_LN2);

    TEST_DOUBLE("log10(1.0)", log10(1.0), 0.0);
    TEST_DOUBLE("log10(10.0)", log10(10.0), 1.0);
    TEST_DOUBLE("log10(100.0)", log10(100.0), 2.0);

    TEST_DOUBLE("log2(1.0)", log2(1.0), 0.0);
    TEST_DOUBLE("log2(2.0)", log2(2.0), 1.0);
    TEST_DOUBLE("log2(8.0)", log2(8.0), 3.0);

    TEST_DOUBLE("expm1(0.0)", expm1(0.0), 0.0);
    TEST_DOUBLE("log1p(0.0)", log1p(0.0), 0.0);
}

void test_power_functions(void) {
    printf("\n=== Testing Power Functions ===\n");

    TEST_DOUBLE("pow(2.0, 3.0)", pow(2.0, 3.0), 8.0);
    TEST_DOUBLE("pow(3.0, 2.0)", pow(3.0, 2.0), 9.0);
    TEST_DOUBLE("pow(10.0, 0.0)", pow(10.0, 0.0), 1.0);
    TEST_DOUBLE("pow(2.0, -1.0)", pow(2.0, -1.0), 0.5);
    TEST_DOUBLE("pow(4.0, 0.5)", pow(4.0, 0.5), 2.0);
    TEST_DOUBLE("pow(M_E, 2.0)", pow(M_E, 2.0), M_E * M_E);
}

void test_trigonometric(void) {
    printf("\n=== Testing Trigonometric Functions ===\n");

    TEST_DOUBLE("sin(0.0)", sin(0.0), 0.0);
    TEST_DOUBLE("sin(M_PI_2)", sin(M_PI_2), 1.0);
    TEST_DOUBLE("sin(M_PI)", sin(M_PI), 0.0);
    TEST_DOUBLE("sin(-M_PI_2)", sin(-M_PI_2), -1.0);

    TEST_DOUBLE("cos(0.0)", cos(0.0), 1.0);
    TEST_DOUBLE("cos(M_PI_2)", cos(M_PI_2), 0.0);
    TEST_DOUBLE("cos(M_PI)", cos(M_PI), -1.0);

    TEST_DOUBLE("tan(0.0)", tan(0.0), 0.0);
    TEST_DOUBLE("tan(M_PI_4)", tan(M_PI_4), 1.0);

    // Test inverse trig functions
    TEST_DOUBLE("asin(0.0)", asin(0.0), 0.0);
    TEST_DOUBLE("asin(1.0)", asin(1.0), M_PI_2);
    TEST_DOUBLE("asin(-1.0)", asin(-1.0), -M_PI_2);

    TEST_DOUBLE("acos(1.0)", acos(1.0), 0.0);
    TEST_DOUBLE("acos(0.0)", acos(0.0), M_PI_2);

    TEST_DOUBLE("atan(0.0)", atan(0.0), 0.0);
    TEST_DOUBLE("atan(1.0)", atan(1.0), M_PI_4);
    TEST_DOUBLE("atan(-1.0)", atan(-1.0), -M_PI_4);

    TEST_DOUBLE("atan2(1.0, 1.0)", atan2(1.0, 1.0), M_PI_4);
    TEST_DOUBLE("atan2(1.0, 0.0)", atan2(1.0, 0.0), M_PI_2);
    TEST_DOUBLE("atan2(0.0, 1.0)", atan2(0.0, 1.0), 0.0);
}

void test_hyperbolic(void) {
    printf("\n=== Testing Hyperbolic Functions ===\n");

    TEST_DOUBLE("sinh(0.0)", sinh(0.0), 0.0);
    TEST_DOUBLE("sinh(1.0)", sinh(1.0), (M_E - 1.0/M_E) / 2.0);

    TEST_DOUBLE("cosh(0.0)", cosh(0.0), 1.0);
    TEST_DOUBLE("cosh(1.0)", cosh(1.0), (M_E + 1.0/M_E) / 2.0);

    TEST_DOUBLE("tanh(0.0)", tanh(0.0), 0.0);

    TEST_DOUBLE("asinh(0.0)", asinh(0.0), 0.0);
    TEST_DOUBLE("acosh(1.0)", acosh(1.0), 0.0);
    TEST_DOUBLE("atanh(0.0)", atanh(0.0), 0.0);
}

void test_special_values(void) {
    printf("\n=== Testing Special Values ===\n");

    // NaN tests
    TEST_BOOL("isnan(NAN)", isnan(NAN));
    TEST_BOOL("!isnan(1.0)", !isnan(1.0));
    TEST_BOOL("isnan(sqrt(-1.0))", isnan(sqrt(-1.0)));

    // Infinity tests
    TEST_BOOL("isinf(INFINITY)", isinf(INFINITY));
    TEST_BOOL("isinf(-INFINITY)", isinf(-INFINITY));
    TEST_BOOL("!isinf(1.0)", !isinf(1.0));
    TEST_BOOL("isinf(exp(1000.0))", isinf(exp(1000.0)));

    // Finite tests
    TEST_BOOL("isfinite(1.0)", isfinite(1.0));
    TEST_BOOL("!isfinite(INFINITY)", !isfinite(INFINITY));
    TEST_BOOL("!isfinite(NAN)", !isfinite(NAN));

    // Sign tests
    TEST_BOOL("!signbit(1.0)", !signbit(1.0));
    TEST_BOOL("signbit(-1.0)", signbit(-1.0));

    // Copysign tests
    TEST_DOUBLE("copysign(3.0, -1.0)", copysign(3.0, -1.0), -3.0);
    TEST_DOUBLE("copysign(-3.0, 1.0)", copysign(-3.0, 1.0), 3.0);
}

void test_float_variants(void) {
    printf("\n=== Testing Float Variants ===\n");

    TEST_FLOAT("sqrtf(4.0f)", sqrtf(4.0f), 2.0f);
    TEST_FLOAT("sinf(0.0f)", sinf(0.0f), 0.0f);
    TEST_FLOAT("cosf(0.0f)", cosf(0.0f), 1.0f);
    TEST_FLOAT("expf(0.0f)", expf(0.0f), 1.0f);
    TEST_FLOAT("logf(1.0f)", logf(1.0f), 0.0f);
    TEST_FLOAT("powf(2.0f, 3.0f)", powf(2.0f, 3.0f), 8.0f);
}

void test_utility_functions(void) {
    printf("\n=== Testing Utility Functions ===\n");

    int exp;
    double mant;

    mant = frexp(8.0, &exp);
    TEST_DOUBLE("frexp(8.0) mantissa", mant, 0.5);
    TEST_BOOL("frexp(8.0) exponent", exp == 4);

    TEST_DOUBLE("ldexp(0.5, 4)", ldexp(0.5, 4), 8.0);
    TEST_DOUBLE("ldexp(1.0, 10)", ldexp(1.0, 10), 1024.0);

    double ipart;
    double fpart = modf(3.75, &ipart);
    TEST_DOUBLE("modf(3.75) integer", ipart, 3.0);
    TEST_DOUBLE("modf(3.75) fraction", fpart, 0.75);

    TEST_DOUBLE("fmin(2.0, 3.0)", fmin(2.0, 3.0), 2.0);
    TEST_DOUBLE("fmax(2.0, 3.0)", fmax(2.0, 3.0), 3.0);

    TEST_DOUBLE("fma(2.0, 3.0, 4.0)", fma(2.0, 3.0, 4.0), 10.0);
}

void test_edge_cases(void) {
    printf("\n=== Testing Edge Cases ===\n");

    // Very small values
    TEST_DOUBLE("sin(1e-10)", sin(1e-10), 1e-10);
    TEST_DOUBLE("exp(0.0)", exp(0.0), 1.0);
    TEST_DOUBLE("log(1.0)", log(1.0), 0.0);

    // Pythagorean identity: sin^2 + cos^2 = 1
    double angle = 0.5;
    double s = sin(angle);
    double c = cos(angle);
    TEST_DOUBLE("sin^2 + cos^2", s*s + c*c, 1.0);

    // exp(log(x)) = x
    TEST_DOUBLE("exp(log(5.0))", exp(log(5.0)), 5.0);

    // log(exp(x)) = x
    TEST_DOUBLE("log(exp(2.0))", log(exp(2.0)), 2.0);

    // sqrt(x^2) = |x|
    TEST_DOUBLE("sqrt(3.0^2)", sqrt(pow(3.0, 2.0)), 3.0);
}

int main(void) {
    uart_init();

    printf("\n");
    printf("========================================\n");
    printf("  RISC-V Math Library Test Suite\n");
    printf("========================================\n");

    test_basic_functions();
    test_sqrt_and_roots();
    test_exponential_and_log();
    test_power_functions();
    test_trigonometric();
    test_hyperbolic();
    test_special_values();
    test_float_variants();
    test_utility_functions();
    test_edge_cases();

    printf("\n");
    printf("========================================\n");
    printf("  Test Summary\n");
    printf("========================================\n");
    printf("Total tests run:    %d\n", tests_run);
    printf("Tests passed:       %d\n", tests_passed);
    printf("Tests failed:       %d\n", tests_failed);
    printf("\n");

    if (tests_failed == 0) {
        printf("SUCCESS: All tests passed!\n");
    } else {
        printf("FAILURE: %d test(s) failed\n", tests_failed);
    }

    printf("========================================\n");
    printf("\n");

    return tests_failed == 0 ? 0 : 1;
}
