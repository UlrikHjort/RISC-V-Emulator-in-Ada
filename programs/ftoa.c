/* **************************************************************************
 *RISC-V Emulator - Floating-point to ASCII conversion for bare-metal printf
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

// Floating-point to ASCII conversion for bare-metal printf
// Implements %f, %e, %g format specifiers

// Helper: check if double is NaN
// By Ulrik Hørlyk Hjort 2026
static int is_nan(double x) {
    return x != x;
}

// Helper: check if double is infinite
static int is_inf(double x) {
    return (x == x) && ((x - x) != 0.0);
}

// Helper: get sign and absolute value
static double get_abs(double x, int *sign) {
    if (x < 0.0) {
        *sign = 1;
        return -x;
    }
    *sign = 0;
    return x;
}

// Helper: reverse a string in place
static void reverse_str(char *str, int len) {
    int i = 0;
    int j = len - 1;
    while (i < j) {
        char tmp = str[i];
        str[i] = str[j];
        str[j] = tmp;
        i++;
        j--;
    }
}

// Helper: unsigned integer to string (for integer parts)
static int uint_to_str(unsigned long val, char *buf) {
    int i = 0;

    if (val == 0) {
        buf[i++] = '0';
    } else {
        while (val > 0) {
            buf[i++] = '0' + (val % 10);
            val /= 10;
        }
    }

    reverse_str(buf, i);
    buf[i] = '\0';
    return i;
}

// Convert double to fixed-point string (for %f format)
// Format: [-]ddd.ddd
void ftoa_fixed(double val, char *buf, int precision) {
    int sign;
    int pos = 0;

    // Handle special values
    if (is_nan(val)) {
        buf[0] = 'n'; buf[1] = 'a'; buf[2] = 'n'; buf[3] = '\0';
        return;
    }

    if (is_inf(val)) {
        if (val < 0) buf[pos++] = '-';
        buf[pos++] = 'i'; buf[pos++] = 'n'; buf[pos++] = 'f';
        buf[pos] = '\0';
        return;
    }

    // Get absolute value and sign
    val = get_abs(val, &sign);

    // Add sign
    if (sign) {
        buf[pos++] = '-';
    }

    // Compute pow10 for the requested precision
    unsigned long pow10_prec = 1;
    for (int i = 0; i < precision; i++) pow10_prec *= 10;

    // Scale fractional part to integer and round.
    // Use double arithmetic + unsigned long cast (32-bit, safe via FPU fcvt).
    // Example: val=2.75, precision=1 -> frac=0.75*10+0.5=8.0 -> frac_int=8, int_part=2 -> "2.8"
    unsigned long int_part = (unsigned long)val;
    double frac_scaled = (val - (double)int_part);
    for (int i = 0; i < precision; i++) frac_scaled *= 10.0;
    frac_scaled += 0.5;
    unsigned long frac_int = (unsigned long)frac_scaled;
    // Propagate carry from rounding (e.g. 9.999 -> frac rounds up to 10)
    if (precision > 0 && frac_int >= pow10_prec) {
        int_part++;
        frac_int -= pow10_prec;
    }

    // Convert integer part
    char temp[32];
    int len = uint_to_str(int_part, temp);
    for (int i = 0; i < len; i++) {
        buf[pos++] = temp[i];
    }

    // Add decimal point and fractional digits (with leading zeros)
    if (precision > 0) {
        buf[pos++] = '.';
        char frac_buf[16];
        int fi = 0;
        for (int i = 0; i < precision; i++) {
            frac_buf[fi++] = '0' + (int)(frac_int % 10);
            frac_int /= 10;
        }
        for (int i = fi - 1; i >= 0; i--) buf[pos++] = frac_buf[i];
    }

    buf[pos] = '\0';
}

// Convert double to exponential string (for %e format)
// Format: [-]d.ddde+/-dd
void ftoa_exp(double val, char *buf, int precision) {
    int sign;
    int pos = 0;

    // Handle special values
    if (is_nan(val)) {
        buf[0] = 'n'; buf[1] = 'a'; buf[2] = 'n'; buf[3] = '\0';
        return;
    }

    if (is_inf(val)) {
        if (val < 0) buf[pos++] = '-';
        buf[pos++] = 'i'; buf[pos++] = 'n'; buf[pos++] = 'f';
        buf[pos] = '\0';
        return;
    }

    // Handle zero
    if (val == 0.0 || val == -0.0) {
        buf[pos++] = '0';
        if (precision > 0) {
            buf[pos++] = '.';
            for (int i = 0; i < precision; i++) {
                buf[pos++] = '0';
            }
        }
        buf[pos++] = 'e'; buf[pos++] = '+'; buf[pos++] = '0'; buf[pos++] = '0';
        buf[pos] = '\0';
        return;
    }

    // Get absolute value and sign
    val = get_abs(val, &sign);

    // Add sign
    if (sign) {
        buf[pos++] = '-';
    }

    // Calculate exponent
    int exponent = 0;
    if (val >= 10.0) {
        while (val >= 10.0) {
            val /= 10.0;
            exponent++;
        }
    } else if (val < 1.0) {
        while (val < 1.0) {
            val *= 10.0;
            exponent--;
        }
    }

    // Round to precision
    double rounding = 0.5;
    for (int i = 0; i < precision; i++) {
        rounding /= 10.0;
    }
    val += rounding;

    // Check if rounding carried over
    if (val >= 10.0) {
        val /= 10.0;
        exponent++;
    }

    // Format mantissa
    int int_part = (int)val;
    double frac_part = val - (double)int_part;

    buf[pos++] = '0' + int_part;

    if (precision > 0) {
        buf[pos++] = '.';
        for (int i = 0; i < precision; i++) {
            frac_part *= 10.0;
            int digit = (int)frac_part;
            buf[pos++] = '0' + digit;
            frac_part -= (double)digit;
        }
    }

    // Add exponent
    buf[pos++] = 'e';
    buf[pos++] = (exponent >= 0) ? '+' : '-';

    int exp_val = (exponent >= 0) ? exponent : -exponent;
    if (exp_val < 10) {
        buf[pos++] = '0';
        buf[pos++] = '0' + exp_val;
    } else {
        buf[pos++] = '0' + (exp_val / 10);
        buf[pos++] = '0' + (exp_val % 10);
    }

    buf[pos] = '\0';
}

// Convert double to general format (for %g format)
// Uses exponential for very large/small numbers, fixed otherwise
void ftoa_general(double val, char *buf, int precision) {
    int sign;

    // Handle special values
    if (is_nan(val)) {
        buf[0] = 'n'; buf[1] = 'a'; buf[2] = 'n'; buf[3] = '\0';
        return;
    }

    if (is_inf(val)) {
        int pos = 0;
        if (val < 0) buf[pos++] = '-';
        buf[pos++] = 'i'; buf[pos++] = 'n'; buf[pos++] = 'f';
        buf[pos] = '\0';
        return;
    }

    // Get absolute value
    double abs_val = get_abs(val, &sign);

    // Default precision for %g is 6 if not specified
    if (precision == 0) precision = 6;

    // Calculate exponent
    int exponent = 0;
    if (abs_val != 0.0) {
        if (abs_val >= 10.0) {
            while (abs_val >= 10.0) {
                abs_val /= 10.0;
                exponent++;
            }
        } else if (abs_val < 1.0) {
            while (abs_val < 1.0) {
                abs_val *= 10.0;
                exponent--;
            }
        }
    }

    // Use exponential if exponent < -4 or >= precision
    if (exponent < -4 || exponent >= precision) {
        ftoa_exp(val, buf, precision - 1);
    } else {
        // Use fixed-point format
        int frac_digits = precision - exponent - 1;
        if (frac_digits < 0) frac_digits = 0;
        ftoa_fixed(val, buf, frac_digits);
    }
}
