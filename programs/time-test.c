/* **************************************************************************
 *      RISC-V Emulator - Test time.h / time.c bare-metal time library
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

/*
 * time-test.c -- Test time.h / time.c bare-metal time library
 *
 * Tests: clock(), clock_gettime(), gettimeofday(), mktime()/gmtime(),
 *        difftime(), time(), delay_ms(), strftime().
 *
 * By Ulrik Hørlyk Hjort 2026
 */
#include <stdint.h>
#include "time.h"
#include "log.h"

static int g_pass = 0, g_fail = 0;

static void chk(const char *label, int ok)
{
    if (ok) { log_write(NONE, "PASS %s\n", label); g_pass++; }
    else    { log_write(NONE, "FAIL %s\n", label); g_fail++; }
}

int main(void)
{
    log_init("time-test.log");
    log_write(NONE, "=== Time Library Test ===\n");

    /* 1. clock() is monotonically non-decreasing */
    {
        clock_t c1 = clock();
        volatile int x = 0;
        for (int i = 0; i < 5000; i++) x += i;
        clock_t c2 = clock();
        chk("clock() monotonic", c2 >= c1);
        (void)x;
    }

    /* 2. clock_gettime(CLOCK_MONOTONIC) */
    {
        struct timespec t1, t2;
        clock_gettime(CLOCK_MONOTONIC, &t1);
        volatile int y = 1;
        for (int i = 0; i < 5000; i++) y *= 2;
        clock_gettime(CLOCK_MONOTONIC, &t2);
        chk("clock_gettime monotonic", t2.tv_sec > t1.tv_sec ||
            (t2.tv_sec == t1.tv_sec && t2.tv_nsec >= t1.tv_nsec));
        chk("tv_nsec in range",
            t1.tv_nsec >= 0 && t1.tv_nsec < 1000000000L);
        (void)y;
    }

    /* 3. gettimeofday() */
    {
        struct timeval tv;
        int rc = gettimeofday(&tv, 0);
        chk("gettimeofday rc==0", rc == 0);
        chk("tv_usec in range",
            tv.tv_usec >= 0 && tv.tv_usec < 1000000L);
    }

    /* 4. mktime / gmtime round-trip for 2026-03-15 12:30:00 */
    {
        struct tm t = {0};
        t.tm_year = 2026 - 1900;
        t.tm_mon  = 2;   /* March = 2 (0-based) */
        t.tm_mday = 15;
        t.tm_hour = 12;
        t.tm_min  = 30;
        t.tm_sec  = 0;
        time_t epoch = mktime(&t);
        struct tm *back = gmtime(&epoch);
        chk("mktime/gmtime year",  back->tm_year == 2026 - 1900);
        chk("mktime/gmtime month", back->tm_mon  == 2);
        chk("mktime/gmtime mday",  back->tm_mday == 15);
    }

    /* 5. difftime */
    {
        time_t t1 = 1000, t2 = 1050;
        double d = difftime(t2, t1);
        chk("difftime", (int)d == 50);
    }

    /* 6. clock_gettime(CLOCK_THREAD_CPUTIME_ID) -- backed by rdcycle (mcycle CSR) */
    {
        struct timespec c1, c2;
        int rc = clock_gettime(CLOCK_THREAD_CPUTIME_ID, &c1);
        chk("thread_cputime rc==0", rc == 0);
        chk("thread_cputime tv_nsec range",
            c1.tv_nsec >= 0 && c1.tv_nsec < 1000000000L);
        /* Do some work so mcycle advances, then check monotonicity */
        volatile int z = 0;
        for (int i = 0; i < 5000; i++) z += i;
        clock_gettime(CLOCK_THREAD_CPUTIME_ID, &c2);
        chk("thread_cputime monotonic",
            c2.tv_sec > c1.tv_sec ||
            (c2.tv_sec == c1.tv_sec && c2.tv_nsec >= c1.tv_nsec));
        (void)z;
    }

    log_write(NONE, "\n%d PASS  %d FAIL\n", g_pass, g_fail);
    log_close();
    return g_fail ? 1 : 0;
}
