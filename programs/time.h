/* **************************************************************************
 *               RISC-V Emulator - Time Functions - Interface
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

#ifndef TIME_H
#define TIME_H

// Time types
typedef long time_t;           // Seconds since epoch (1970-01-01 00:00:00 UTC)
typedef unsigned long clock_t; // CPU clock ticks

// Clock ticks per second
#define CLOCKS_PER_SEC 10000000  // 10 MHz (CLINT default frequency)

// Broken-down time structure
struct tm {
    int tm_sec;    // Seconds [0-60] (60 allows for leap seconds)
    int tm_min;    // Minutes [0-59]
    int tm_hour;   // Hours [0-23]
    int tm_mday;   // Day of month [1-31]
    int tm_mon;    // Month [0-11] (0 = January)
    int tm_year;   // Years since 1900
    int tm_wday;   // Day of week [0-6] (0 = Sunday)
    int tm_yday;   // Day of year [0-365]
    int tm_isdst;  // Daylight saving time flag (>0, 0, <0)
};

// ============================================================================
// Time Manipulation Functions
// ============================================================================

// Get current calendar time (seconds since epoch)
time_t time(time_t *timer);

// Get processor clock time (ticks since program start)
clock_t clock(void);

// Calculate difference between two times in seconds
double difftime(time_t time1, time_t time0);

// Convert struct tm to time_t
time_t mktime(struct tm *timeptr);

// ============================================================================
// Time Conversion Functions
// ============================================================================

// Convert time_t to struct tm (UTC)
struct tm *gmtime(const time_t *timer);

// Convert time_t to struct tm (local time, same as gmtime for bare-metal)
struct tm *localtime(const time_t *timer);

// Convert struct tm to string: "Wed Jun 30 21:49:08 1993\n"
char *asctime(const struct tm *timeptr);

// Convert time_t to string (combines localtime and asctime)
char *ctime(const time_t *timer);

// Format time string
// Simplified version - supports basic format specifiers
unsigned long strftime(char *str, unsigned long maxsize,
                       const char *format, const struct tm *timeptr);

// ============================================================================
// Bare-Metal Specific Functions
// ============================================================================

// Initialize time system with epoch offset (seconds since 1970-01-01 00:00:00)
// Call this at startup if you know the current time
void time_init(time_t initial_time);

// Get raw CLINT mtime value (64-bit counter)
unsigned long long time_get_mtime(void);

// Get ticks since boot
unsigned long long time_get_ticks(void);

// Delay for specified milliseconds
void delay_ms(unsigned int ms);

// Delay for specified microseconds
void delay_us(unsigned int us);

// ============================================================================
// POSIX Extensions
// ============================================================================

// Clock IDs for clock_gettime
#define CLOCK_REALTIME           0
#define CLOCK_MONOTONIC          1
#define CLOCK_PROCESS_CPUTIME_ID 2
#define CLOCK_THREAD_CPUTIME_ID  3

// Timespec: nanosecond-precision timestamp
struct timespec {
    time_t tv_sec;   // Seconds
    long   tv_nsec;  // Nanoseconds [0, 999999999]
};

// Timeval: microsecond-precision timestamp (used by gettimeofday)
struct timeval {
    long tv_sec;   // Seconds
    long tv_usec;  // Microseconds [0, 999999]
};

// POSIX clock_gettime
//   CLOCK_REALTIME / CLOCK_MONOTONIC / CLOCK_PROCESS_CPUTIME_ID -- CLINT mtime
//   CLOCK_THREAD_CPUTIME_ID -- per-hart mcycle CSR (rdcycle), includes stalls
int clock_gettime(int clk_id, struct timespec *tp);

// BSD/POSIX gettimeofday -- reads CLINT mtime, converts to sec+usec
int gettimeofday(struct timeval *tv, void *tz);

#endif // TIME_H
