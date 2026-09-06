/* **************************************************************************
 *RISC-V Emulator - Bare-metal time library implementation using CLINT timer
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

// Bare-metal time library implementation using CLINT timer
// Provides standard C time.h functions for RISC-V
// By Ulrik Hørlyk Hjort 2026

#include "time.h"

// ============================================================================
// CLINT Timer Access
// ============================================================================

// CLINT (Core Local Interruptor) base address
#define CLINT_BASE    0x02000000UL
#define MTIME_OFFSET  0xBFF8
#define MTIME_ADDR    (CLINT_BASE + MTIME_OFFSET)

// Timer frequency (10 MHz for QEMU virt machine)
#define TIMER_FREQ 10000000ULL

// Read 64-bit mtime register
static inline unsigned long long read_mtime(void) {
    volatile unsigned long long *mtime = (volatile unsigned long long *)MTIME_ADDR;
    return *mtime;
}

// Read mcycle CSR (per-hart CPU cycle counter, includes pipeline stalls)
// Uses the standard 32-bit split to get the full 64-bit value without __udivdi3.
// Re-reads the high word to guard against a rollover between the two reads.
static inline unsigned long long read_cycle(void) {
    unsigned long hi1, hi2, lo;
    do {
        __asm__ volatile ("rdcycleh %0" : "=r"(hi1));
        __asm__ volatile ("rdcycle  %0" : "=r"(lo));
        __asm__ volatile ("rdcycleh %0" : "=r"(hi2));
    } while (hi1 != hi2);
    return ((unsigned long long)hi1 << 32) | lo;
}

// ============================================================================
// Global State
// ============================================================================

// Epoch offset: time at which time_init() was called
// If not set, time() returns seconds since boot
static time_t epoch_offset = 0;
static unsigned long long boot_ticks = 0;
static int time_initialized = 0;

// Static buffer for time string conversions
static char time_string_buffer[64];
static struct tm time_tm_buffer;

// ============================================================================
// Initialization
// ============================================================================

void time_init(time_t initial_time) {
    boot_ticks = read_mtime();
    epoch_offset = initial_time;
    time_initialized = 1;
}

// ============================================================================
// Time Access Functions
// ============================================================================

// Get raw mtime value
unsigned long long time_get_mtime(void) {
    return read_mtime();
}

// Get ticks since boot
unsigned long long time_get_ticks(void) {
    if (!time_initialized) {
        boot_ticks = read_mtime();
        time_initialized = 1;
    }
    return read_mtime() - boot_ticks;
}

// Get current time in seconds since epoch
time_t time(time_t *timer) {
    unsigned long long ticks = time_get_ticks();

    // Avoid 64-bit division by splitting into high and low parts
    // ticks / TIMER_FREQ = ticks / 10000000
    unsigned long high = (unsigned long)(ticks >> 32);
    unsigned long low = (unsigned long)ticks;

    // Compute seconds using 32-bit arithmetic
    // We know TIMER_FREQ = 10000000 < 2^32, so we can do this safely
    unsigned long seconds_high = high * (4294967296UL / TIMER_FREQ);
    unsigned long seconds_low = low / TIMER_FREQ;
    time_t seconds = (time_t)(seconds_high + seconds_low);

    // Add epoch offset if set
    seconds += epoch_offset;

    if (timer != 0) {
        *timer = seconds;
    }

    return seconds;
}

// Get processor time (clock ticks since start)
clock_t clock(void) {
    return (clock_t)time_get_ticks();
}

// Calculate difference between two times
double difftime(time_t time1, time_t time0) {
    return (double)(time1 - time0);
}

// ============================================================================
// Delay Functions
// ============================================================================

void delay_ms(unsigned int ms) {
    // Avoid 64-bit division: TIMER_FREQ / 1000 = ticks per millisecond
    unsigned long ticks_per_ms = TIMER_FREQ / 1000;
    unsigned long long ticks = (unsigned long long)ms * ticks_per_ms;
    unsigned long long start = read_mtime();
    while ((read_mtime() - start) < ticks);
}

void delay_us(unsigned int us) {
    // Avoid 64-bit division: TIMER_FREQ / 1000000 = ticks per microsecond
    unsigned long ticks_per_us = TIMER_FREQ / 1000000;
    unsigned long long ticks = (unsigned long long)us * ticks_per_us;
    unsigned long long start = read_mtime();
    while ((read_mtime() - start) < ticks);
}

// ============================================================================
// Calendar Calculations
// ============================================================================

// Days in each month (non-leap year)
static const int days_in_month[12] = {
    31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31
};

// Check if year is a leap year
static int is_leap_year(int year) {
    // Year is in "years since 1900" format, so actual year is year + 1900
    int actual_year = year + 1900;

    if (actual_year % 4 != 0) return 0;
    if (actual_year % 100 != 0) return 1;
    if (actual_year % 400 != 0) return 0;
    return 1;
}

// Get days in month
static int get_days_in_month(int month, int year) {
    if (month == 1 && is_leap_year(year)) {  // February in leap year
        return 29;
    }
    return days_in_month[month];
}

// Note: Day of week calculation is done differently in gmtime()
// using a simpler algorithm based on epoch (1970-01-01 = Thursday)

// ============================================================================
// Time Conversion Functions
// ============================================================================

// Convert time_t to struct tm (UTC)
struct tm *gmtime(const time_t *timer) {
    if (timer == 0) return 0;

    time_t t = *timer;
    struct tm *result = &time_tm_buffer;

    // Calculate seconds, minutes, hours
    result->tm_sec = t % 60;
    t /= 60;
    result->tm_min = t % 60;
    t /= 60;
    result->tm_hour = t % 24;
    t /= 24;  // Now t is days since epoch

    // Calculate day of week (1970-01-01 was a Thursday = 4)
    result->tm_wday = (t + 4) % 7;

    // Calculate year
    int year = 1970;
    int days_remaining = (int)t;

    while (1) {
        int days_in_year = (year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)) ? 366 : 365;

        if (days_remaining < days_in_year) {
            break;
        }

        days_remaining -= days_in_year;
        year++;
    }

    result->tm_year = year - 1900;  // Years since 1900
    result->tm_yday = days_remaining;

    // Calculate month and day
    int month = 0;
    while (month < 12) {
        int days = get_days_in_month(month, result->tm_year);

        if (days_remaining < days) {
            break;
        }

        days_remaining -= days;
        month++;
    }

    result->tm_mon = month;
    result->tm_mday = days_remaining + 1;  // Day of month is 1-based
    result->tm_isdst = 0;  // No DST in bare-metal

    return result;
}

// Convert time_t to struct tm (local time = UTC for bare-metal)
struct tm *localtime(const time_t *timer) {
    return gmtime(timer);
}

// Convert struct tm to time_t
time_t mktime(struct tm *timeptr) {
    if (timeptr == 0) return -1;

    // Calculate days since epoch
    int year = timeptr->tm_year + 1900;
    int days = 0;

    // Add days for complete years since 1970
    for (int y = 1970; y < year; y++) {
        if (y % 4 == 0 && (y % 100 != 0 || y % 400 == 0)) {
            days += 366;  // Leap year
        } else {
            days += 365;
        }
    }

    // Add days for complete months in current year
    for (int m = 0; m < timeptr->tm_mon; m++) {
        days += get_days_in_month(m, timeptr->tm_year);
    }

    // Add remaining days
    days += timeptr->tm_mday - 1;  // tm_mday is 1-based

    // Calculate total seconds
    time_t result = (time_t)days * 86400;
    result += timeptr->tm_hour * 3600;
    result += timeptr->tm_min * 60;
    result += timeptr->tm_sec;

    // Update tm_wday and tm_yday
    timeptr->tm_wday = (days + 4) % 7;  // 1970-01-01 was Thursday

    // Calculate day of year
    int yday = 0;
    for (int m = 0; m < timeptr->tm_mon; m++) {
        yday += get_days_in_month(m, timeptr->tm_year);
    }
    yday += timeptr->tm_mday - 1;
    timeptr->tm_yday = yday;

    return result;
}

// ============================================================================
// Time String Functions
// ============================================================================

// Month names
static const char *month_names[] = {
    "Jan", "Feb", "Mar", "Apr", "May", "Jun",
    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
};

// Day names
static const char *day_names[] = {
    "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"
};

// Simple string copy
static void strcpy_local(char *dest, const char *src) {
    while (*src) {
        *dest++ = *src++;
    }
    *dest = '\0';
}

// Simple number to string (2 digits with leading zero)
static void int_to_str_2d(char *str, int val) {
    str[0] = '0' + (val / 10);
    str[1] = '0' + (val % 10);
    str[2] = '\0';
}

// Number to string (4 digits)
static void int_to_str_4d(char *str, int val) {
    str[0] = '0' + (val / 1000);
    str[1] = '0' + ((val / 100) % 10);
    str[2] = '0' + ((val / 10) % 10);
    str[3] = '0' + (val % 10);
    str[4] = '\0';
}

// Convert struct tm to string: "Wed Jun 30 21:49:08 1993\n"
char *asctime(const struct tm *timeptr) {
    if (timeptr == 0) return 0;

    char *buf = time_string_buffer;
    char tmp[8];

    // Day name
    strcpy_local(buf, day_names[timeptr->tm_wday]);
    buf += 3;
    *buf++ = ' ';

    // Month name
    strcpy_local(buf, month_names[timeptr->tm_mon]);
    buf += 3;
    *buf++ = ' ';

    // Day of month (space-padded)
    if (timeptr->tm_mday < 10) {
        *buf++ = ' ';
        *buf++ = '0' + timeptr->tm_mday;
    } else {
        int_to_str_2d(tmp, timeptr->tm_mday);
        *buf++ = tmp[0];
        *buf++ = tmp[1];
    }
    *buf++ = ' ';

    // Hour
    int_to_str_2d(tmp, timeptr->tm_hour);
    *buf++ = tmp[0];
    *buf++ = tmp[1];
    *buf++ = ':';

    // Minute
    int_to_str_2d(tmp, timeptr->tm_min);
    *buf++ = tmp[0];
    *buf++ = tmp[1];
    *buf++ = ':';

    // Second
    int_to_str_2d(tmp, timeptr->tm_sec);
    *buf++ = tmp[0];
    *buf++ = tmp[1];
    *buf++ = ' ';

    // Year
    int_to_str_4d(tmp, timeptr->tm_year + 1900);
    *buf++ = tmp[0];
    *buf++ = tmp[1];
    *buf++ = tmp[2];
    *buf++ = tmp[3];
    *buf++ = '\n';
    *buf = '\0';

    return time_string_buffer;
}

// Convert time_t to string
char *ctime(const time_t *timer) {
    return asctime(localtime(timer));
}

// Simplified strftime - supports basic format specifiers
unsigned long strftime(char *str, unsigned long maxsize,
                       const char *format, const struct tm *timeptr) {
    if (str == 0 || format == 0 || timeptr == 0 || maxsize == 0) {
        return 0;
    }

    char *dest = str;
    const char *src = format;
    unsigned long count = 0;
    char tmp[8];

    while (*src && count < maxsize - 1) {
        if (*src == '%') {
            src++;
            switch (*src) {
                case 'a':  // Abbreviated weekday name
                    strcpy_local(dest, day_names[timeptr->tm_wday]);
                    dest += 3;
                    count += 3;
                    break;

                case 'b':  // Abbreviated month name
                    strcpy_local(dest, month_names[timeptr->tm_mon]);
                    dest += 3;
                    count += 3;
                    break;

                case 'd':  // Day of month (01-31)
                    int_to_str_2d(tmp, timeptr->tm_mday);
                    *dest++ = tmp[0];
                    *dest++ = tmp[1];
                    count += 2;
                    break;

                case 'H':  // Hour (00-23)
                    int_to_str_2d(tmp, timeptr->tm_hour);
                    *dest++ = tmp[0];
                    *dest++ = tmp[1];
                    count += 2;
                    break;

                case 'M':  // Minute (00-59)
                    int_to_str_2d(tmp, timeptr->tm_min);
                    *dest++ = tmp[0];
                    *dest++ = tmp[1];
                    count += 2;
                    break;

                case 'S':  // Second (00-59)
                    int_to_str_2d(tmp, timeptr->tm_sec);
                    *dest++ = tmp[0];
                    *dest++ = tmp[1];
                    count += 2;
                    break;

                case 'Y':  // Year (4 digits)
                    int_to_str_4d(tmp, timeptr->tm_year + 1900);
                    *dest++ = tmp[0];
                    *dest++ = tmp[1];
                    *dest++ = tmp[2];
                    *dest++ = tmp[3];
                    count += 4;
                    break;

                case 'm':  // Month (01-12)
                    int_to_str_2d(tmp, timeptr->tm_mon + 1);
                    *dest++ = tmp[0];
                    *dest++ = tmp[1];
                    count += 2;
                    break;

                case '%':  // Literal %
                    *dest++ = '%';
                    count++;
                    break;

                default:  // Unknown specifier, copy as-is
                    *dest++ = '%';
                    *dest++ = *src;
                    count += 2;
                    break;
            }
            src++;
        } else {
            *dest++ = *src++;
            count++;
        }
    }

    *dest = '\0';
    return count;
}

// ============================================================================
// POSIX clock_gettime / gettimeofday
// ============================================================================

int clock_gettime(int clk_id, struct timespec *tp) {
    if (!tp) return -1;

    unsigned long long ticks;
    if (clk_id == CLOCK_THREAD_CPUTIME_ID) {
        /* Per-hart CPU cycle counter -- reads mcycle CSR via rdcycle.
         * Includes pipeline stall cycles (MUL/DIV/FP/cache misses).
         * Scaled at the same 10 MHz nominal rate as CLOCK_MONOTONIC so
         * the two clocks agree on instruction count when there are no stalls,
         * but THREAD_CPUTIME grows faster once cache/FP stalls are present. */
        ticks = read_cycle();
    } else if (clk_id == CLOCK_MONOTONIC ||
               clk_id == CLOCK_PROCESS_CPUTIME_ID) {
        ticks = time_get_ticks();
    } else {
        /* CLOCK_REALTIME: raw mtime */
        ticks = read_mtime();
    }

    /* Timer is 10 MHz (TIMER_FREQ = 10000000).
     * tv_sec  = ticks / 10000000
     * tv_nsec = (ticks % 10000000) * 100
     *
     * Avoid 64-bit division (__udivdi3 absent in -nostdlib):
     * Split ticks into 32-bit hi/lo words and use 32-bit arithmetic.
     * For uptime < 429 s the hi word is zero; the approximation below
     * gives exact results for any hi value representable in 32 bits.
     */
    unsigned long lo = (unsigned long)(ticks & 0xFFFFFFFFUL);
    unsigned long hi = (unsigned long)(ticks >> 32);

    /* Each 2^32 ticks ~ 429 seconds at 10 MHz.
     * Exact: 4294967296 / 10000000 = 429 remainder 4967296.
     * We use the integer quotient 429 for the hi contribution; the
     * fractional remainder causes at most 1 second of error per 429 s,
     * which is acceptable for a bare-metal approximation.
     */
    unsigned long sec_hi  = hi * 429UL;
    unsigned long sec_lo  = lo / 10000000UL;
    tp->tv_sec = (time_t)(sec_hi + sec_lo);

    /* Sub-second nanoseconds from the low word remainder.
     * lo % TIMER_FREQ gives ticks in [0, 9999999];
     * multiply by 100 to convert to nanoseconds (100 ns resolution). */
    unsigned long rem = lo % 10000000UL;
    tp->tv_nsec = (long)(rem * 100UL);

    if (clk_id == CLOCK_REALTIME) {
        tp->tv_sec += epoch_offset;
    }
    return 0;
}

int gettimeofday(struct timeval *tv, void *tz) {
    (void)tz;
    if (!tv) return -1;

    unsigned long long ticks = time_get_ticks();
    unsigned long lo = (unsigned long)(ticks & 0xFFFFFFFFUL);
    unsigned long hi = (unsigned long)(ticks >> 32);

    tv->tv_sec  = (long)(hi * 429UL + lo / 10000000UL);
    /* 1 microsecond = 10 ticks at 10 MHz */
    tv->tv_usec = (long)((lo % 10000000UL) / 10UL);
    return 0;
}
