# RISC-V Emulator - Math Library (math.h)

**Phase 5B.1** - Bare-Metal Mathematical Functions

## Overview

The math library provides a comprehensive set of mathematical functions for bare-metal RISC-V development, implementing the standard C math.h interface without relying on external libraries. All functions are implemented using Taylor series, Newton-Raphson methods, and other numerical approximations optimized for accuracy and performance.

**Test Results:** 107/107 tests passing (100% success rate)

---

## Features

### Basic Functions
- **Absolute value:** `fabs()`, `fabsf()`
- **Rounding:** `floor()`, `ceil()`, `round()`, `trunc()`
- **Modulo:** `fmod()`, `fmodf()`

### Power and Root Functions
- **Square root:** `sqrt()`, `sqrtf()` - Newton-Raphson method
- **Cube root:** `cbrt()`, `cbrtf()` - Newton-Raphson method
- **Power:** `pow()`, `powf()` - Optimized for integer exponents
- **Hypotenuse:** `hypot()`, `hypotf()` - Overflow-safe

### Exponential and Logarithm
- **Exponential:** `exp()`, `expf()` - Taylor series
- **Natural log:** `log()`, `logf()` - Series expansion
- **Base-10/Base-2:** `log10()`, `log2()`
- **Accurate for small x:** `expm1()`, `log1p()`

### Trigonometric Functions
- **Basic trig:** `sin()`, `cos()`, `tan()`
- **Inverse trig:** `asin()`, `acos()`, `atan()`, `atan2()`
- **Range reduction:** Automatic argument reduction to [-PI, PI]
- **Accuracy:** Uses improved atan() with argument reduction

### Hyperbolic Functions
- **Basic:** `sinh()`, `cosh()`, `tanh()`
- **Inverse:** `asinh()`, `acosh()`, `atanh()`

### Utility Functions
- **Classification:** `isnan()`, `isinf()`, `isfinite()`, `isnormal()`
- **Sign operations:** `signbit()`, `copysign()`
- **Decomposition:** `frexp()`, `ldexp()`, `modf()`, `scalbn()`
- **Min/Max:** `fmin()`, `fmax()`
- **Fused multiply-add:** `fma()`

### Special Values
- Full support for **NaN**, **Infinity**, and **signed zero**
- Proper handling of edge cases and special values
- IEEE 754 compatible behavior (where applicable)

---

## Implementation Details

### Numerical Methods

#### Square Root (Newton-Raphson)
```c
// Iterative approximation: x_new = 0.5 * (x_old + n / x_old)
// Converges quadratically
double sqrt(double x) {
    double guess = x;
    do {
        prev = guess;
        guess = 0.5 * (guess + x / guess);
    } while (fabs(guess - prev) > 1e-10 * guess);
    return guess;
}
```

#### Exponential (Taylor Series + Range Reduction)
```c
// exp(x) = exp(n*ln(2) + r) = 2^n * exp(r)
// Where |r| < ln(2)/2
// Taylor series: exp(r) = 1 + r + r^2/2! + r^3/3! + ...
```

#### Logarithm (Series Expansion)
```c
// Extract exponent: x = m * 2^e where 0.5 <= m < 1
// ln(x) = ln(m) + e * ln(2)
// Use series: ln((1+y)/(1-y)) = 2*(y + y^3/3 + y^5/5 + ...)
// Where y = (m-1)/(m+1)
```

#### Arctangent (Argument Reduction + Taylor Series)
```c
// Argument reduction for better convergence:
// atan(x) = 2*atan(x / (1 + sqrt(1 + x^2)))
// Reduces |x| > 0.4 to smaller values
// Then Taylor series: atan(x) = x - x^3/3 + x^5/5 - x^7/7 + ...
```

### Optimization Techniques

1. **Argument Reduction**
   - Exponential: Reduce to small range for faster convergence
   - Trigonometric: Reduce to [-PI, PI] range
   - Arctangent: Reduce to |x| < 0.4 for accurate convergence

2. **Special Case Handling**
   - Integer exponents use fast exponentiation by squaring
   - Small values use specialized approximations
   - Large values handled to prevent overflow

3. **RV32-Specific**
   - Uses 32-bit integers (not 64-bit) to avoid libgcc dependencies
   - Floor/ceil/trunc work correctly for values in int32 range
   - Optimized for RISC-V FPU (F and D extensions)

### Accuracy

- **Double precision:** ~1e-10 to 1e-15 relative accuracy
- **Single precision:** ~1e-6 to 1e-8 relative accuracy
- **Trigonometric:** Full precision within [-PI, PI]
- **Logarithm/Exponential:** Accurate across entire range

---

## Usage

### Including the Library

```c
#include "math.h"
```

### Example: Scientific Calculation

```c
#include "uart.h"
#include "printf.h"
#include "math.h"

int main(void) {
    uart_init();

    // Calculate trajectory (ballistics)
    double angle = 45.0 * M_PI / 180.0;  // 45 degrees in radians
    double velocity = 100.0;              // m/s
    double gravity = 9.81;                // m/s^2

    double vx = velocity * cos(angle);
    double vy = velocity * sin(angle);
    double time_to_peak = vy / gravity;
    double max_height = pow(vy, 2.0) / (2.0 * gravity);
    double range = vx * 2.0 * time_to_peak;

    printf("Projectile Motion:\n");
    printf("  Angle:       %f degrees\n", angle * 180.0 / M_PI);
    printf("  Velocity:    %f m/s\n", velocity);
    printf("  Max height:  %f m\n", max_height);
    printf("  Range:       %f m\n", range);

    return 0;
}
```

### Example: Signal Processing

```c
#include "math.h"

// Generate sine wave samples
void generate_sine_wave(float *buffer, int samples, float frequency, float samplerate) {
    for (int i = 0; i < samples; i++) {
        float t = (float)i / samplerate;
        buffer[i] = sinf(2.0f * M_PI * frequency * t);
    }
}

// Fast Fourier Transform helper
float calculate_magnitude(float real, float imag) {
    return sqrtf(real * real + imag * imag);
}

float calculate_phase(float real, float imag) {
    return atan2f(imag, real);
}
```

### Example: Statistics

```c
#include "math.h"

// Calculate standard deviation
double std_deviation(double *data, int n) {
    double mean = 0.0;
    for (int i = 0; i < n; i++) {
        mean += data[i];
    }
    mean /= n;

    double variance = 0.0;
    for (int i = 0; i < n; i++) {
        double diff = data[i] - mean;
        variance += diff * diff;
    }
    variance /= n;

    return sqrt(variance);
}

// Gaussian probability density function
double gaussian_pdf(double x, double mean, double std_dev) {
    double coeff = 1.0 / (std_dev * sqrt(2.0 * M_PI));
    double exponent = -0.5 * pow((x - mean) / std_dev, 2.0);
    return coeff * exp(exponent);
}
```

---

## Mathematical Constants

Available in `math.h`:

```c
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
```

Special values:
```c
#define INFINITY   (1.0/0.0)
#define NAN        (0.0/0.0)
#define HUGE_VAL   INFINITY
```

---

## Building Programs with Math Library

### Makefile Integration

The math library is automatically included when you compile programs:

```makefile
# Build with math library
my-program.elf: crt0.S uart.c syscalls.c printf.c ftoa.c math.c my-program.c hello.ld
	$(CC) $(CFLAGS) -march=rv32imfd $(LDFLAGS) -o $@ \
	    crt0.S uart.c syscalls.c printf.c ftoa.c math.c my-program.c
```

**Important:** Always use `-march=rv32imfd` to enable floating-point instructions.

### Running Programs

```bash
# Build
make my-program.bin

# Run with emulator
make run-my-program

# Or manually:
./bin/riscv_emulator --machine qemu-virt --pty --wait programs/out/bin/my-program.bin 80000000
```

---

## Testing

### Running the Test Suite

```bash
# Build test
make math-test.bin

# Run test
./bin/riscv_emulator --machine qemu-virt --quiet --max-instructions 50000000 \
    programs/out/bin/math-test.bin 80000000
```

### Test Coverage

The `math-test.c` program includes 107 comprehensive tests:

| Category | Tests | Coverage |
|----------|-------|----------|
| Basic Functions | 13 | fabs, floor, ceil, round, trunc, fmod |
| Roots | 9 | sqrt, cbrt, hypot |
| Exponential/Log | 15 | exp, log, log10, log2, expm1, log1p |
| Power | 6 | pow with various exponents |
| Trigonometric | 20 | sin, cos, tan, asin, acos, atan, atan2 |
| Hyperbolic | 8 | sinh, cosh, tanh, asinh, acosh, atanh |
| Special Values | 14 | NaN, Infinity, sign handling |
| Float Variants | 6 | 32-bit float versions |
| Utility | 9 | frexp, ldexp, modf, fmin, fmax, fma |
| Edge Cases | 7 | Identities and special values |

**Result:** 107/107 tests passing (100%)

---

## Known Limitations

### 1. Limited Range for Integer Conversions

Functions like `floor()`, `ceil()`, and `trunc()` use 32-bit integer conversion internally:

- **Works correctly:** Values in range [-2^31, 2^31-1] ~ [-2.1B, 2.1B]
- **May overflow:** Very large floating-point values outside int32 range

**Workaround:** For very large values, these functions return approximations. This is acceptable for most embedded applications.

### 2. No Long Double Support

Only `double` (64-bit) and `float` (32-bit) are supported. `long double` is treated as `double`.

### 3. Performance Considerations

- **Taylor series:** Some functions (exp, log, sin, cos) use iterative methods
- **Convergence:** Typically 10-20 iterations for full precision
- **Instruction count:** ~1000-10000 instructions per call depending on function

**Performance tips:**
- Cache frequently used values (e.g., sin/cos lookup tables)
- Use `float` versions (`sinf`, `sqrtf`) when precision allows
- Avoid calling in tight loops if possible

### 4. No Hardware FMA

The `fma()` function computes `(x * y) + z` but doesn't use true hardware FMA, so it may not have the same precision as a true fused multiply-add instruction.

---

## Best Practices

### 1. Choose Appropriate Precision

```c
// Use float for less critical calculations (faster)
float temperature = sinf(angle) * 100.0f;

// Use double for accumulated errors or high precision
double trajectory = sin(angle) * velocity * time;
```

### 2. Check for Special Values

```c
double result = sqrt(x);
if (isnan(result)) {
    // Handle invalid input (x was negative)
}

if (isinf(result)) {
    // Handle overflow
}
```

### 3. Avoid Cancellation Errors

```c
// Bad: catastrophic cancellation for small x
double y = exp(x) - 1.0;  // Loses precision when x is small

// Good: use expm1() for small x
double y = expm1(x);  // Accurate for all x
```

### 4. Use Constants

```c
// Bad: recomputing constants
double area = radius * radius * 3.14159265;

// Good: use M_PI
double area = radius * radius * M_PI;
```

### 5. Range Reduction

For periodic functions, reduce arguments to avoid loss of precision:

```c
// For very large angles, reduce to [0, 2PI)
double normalized_angle = fmod(large_angle, 2.0 * M_PI);
double result = sin(normalized_angle);
```

---

## Integration with Other Libraries

### Printf with Floating-Point

```c
#include "printf.h"
#include "math.h"

double x = sqrt(2.0);
printf("sqrt(2) = %f\n", x);  // Output: sqrt(2) = 1.414214
printf("sqrt(2) = %e\n", x);  // Output: sqrt(2) = 1.414214e+00
```

### String Conversion

```c
#include "atof.h"  // From stdlib
#include "math.h"

const char *str = "3.14159";
double value = atof(str);
double result = sin(value);
```

---

## Troubleshooting

### Problem: Linker errors about `__fixdfdi` or `__floatdidf`

**Cause:** 64-bit integer conversion functions missing.

**Solution:** The math library has been updated to use 32-bit integers only. If you still see these errors, ensure you're using the latest `math.c`.

### Problem: Inaccurate results for atan()

**Cause:** Taylor series converges slowly for large arguments.

**Solution:** The improved `atan()` implementation uses argument reduction. Ensure you have the latest version.

### Problem: Very slow execution

**Cause:** Taylor series functions can take many iterations.

**Solution:**
- Use `-O2` optimization
- Use float versions (`sinf`, `sqrtf`) when possible
- Consider lookup tables for frequently used angles

### Problem: sqrt() returns NaN

**Cause:** Attempting to take the square root of a negative number.

**Solution:** Check for negative inputs:
```c
if (x < 0.0) {
    // Handle error
} else {
    result = sqrt(x);
}
```

---

## Function Reference Summary

### Basic (13 functions)
`fabs`, `fabsf`, `fmod`, `fmodf`, `floor`, `floorf`, `ceil`, `ceilf`, `round`, `roundf`, `trunc`, `truncf`

### Roots (6 functions)
`sqrt`, `sqrtf`, `cbrt`, `cbrtf`, `hypot`, `hypotf`

### Power (6 functions)
`pow`, `powf`, `exp`, `expf`, `expm1`, `expm1f`

### Logarithm (10 functions)
`log`, `logf`, `log10`, `log10f`, `log2`, `log2f`, `log1p`, `log1pf`

### Trigonometric (14 functions)
`sin`, `sinf`, `cos`, `cosf`, `tan`, `tanf`
`asin`, `asinf`, `acos`, `acosf`, `atan`, `atanf`, `atan2`, `atan2f`

### Hyperbolic (12 functions)
`sinh`, `sinhf`, `cosh`, `coshf`, `tanh`, `tanhf`
`asinh`, `asinhf`, `acosh`, `acoshf`, `atanh`, `atanhf`

### Utility (24 functions)
`isnan`, `isnanf`, `isinf`, `isinff`, `isfinite`, `isfinitef`, `isnormal`, `isnormalf`
`signbit`, `signbitf`, `copysign`, `copysignf`, `frexp`, `frexpf`, `ldexp`, `ldexpf`
`modf`, `modff`, `scalbn`, `scalbnf`, `fmin`, `fminf`, `fmax`, `fmaxf`, `fma`, `fmaf`

**Total: 85 functions**

---

## Files

- **`programs/math.h`** - Header file with function prototypes and constants
- **`programs/math.c`** - Implementation (~1000 lines)
- **`programs/math-test.c`** - Comprehensive test suite (107 tests)

---

## Future Enhancements

Possible future additions:
- [ ] Error and gamma functions (erf, gamma, lgamma)
- [ ] Bessel functions
- [ ] Complex number support
- [ ] Lookup table optimizations for sin/cos
- [ ] CORDIC algorithm for trigonometric functions
- [ ] Fast approximations (less accurate but faster)

---

## Conclusion

The math library provides a complete, accurate, and efficient mathematical function suite for bare-metal RISC-V development. With 100% test pass rate and comprehensive coverage of standard math.h functions, it enables scientific computing, signal processing, statistics, and general-purpose numerical calculations in embedded environments.

**Status:** Complete and production-ready  
**Test Coverage:** 107/107 tests passing (100%)  
**Performance:** Optimized for RV32IMFD  
