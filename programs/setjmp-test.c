/* **************************************************************************
 *              RISC-V Emulator - setjmp / longjmp test suite
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
 * setjmp / longjmp test suite
 *
 * Tests: basic return value, val=0->1, deep-nested jump, stack-pointer
 * restoration, nested try/catch pattern, multiple longjmps to same buf.
 */

#include <stdint.h>
#include "log.h"
#include "setjmp.h"

static int g_pass = 0, g_fail = 0;

static void chk(const char *label, int ok)
{
    if (ok) { log_write(NONE, "PASS %s\n", label); g_pass++; }
    else     { log_write(NONE, "FAIL %s\n", label); g_fail++; }
}

/* ------------------------------------------------------------------ */
/* Shared jmp_buf for simple tests                                     */
/* ------------------------------------------------------------------ */
static jmp_buf g_env;

/* ---- test 2: basic longjmp delivers value ------------------------- */
static void __attribute__((noinline)) thrower(int val)
{
    longjmp(g_env, val);
}

static int test_basic(void)
{
    int r = setjmp(g_env);
    if (r == 0)
        thrower(42);
    return r;   /* should be 42 */
}

/* ---- test 3: val=0 becomes 1 -------------------------------------- */
static int test_zero_becomes_one(void)
{
    int r = setjmp(g_env);
    if (r == 0)
        longjmp(g_env, 0);
    return r;   /* should be 1 */
}

/* ---- test 4: longjmp from depth-3 call stack ---------------------- */
static void __attribute__((noinline)) deep3(void) { longjmp(g_env, 99); }
static void __attribute__((noinline)) deep2(void) { deep3(); }
static void __attribute__((noinline)) deep1(void) { deep2(); }

static int test_deep(void)
{
    int r = setjmp(g_env);
    if (r == 0)
        deep1();
    return r;   /* should be 99 */
}

/* ---- test 6: nested try/catch with two independent jmp_bufs ------- */
static jmp_buf g_outer, g_inner;

static void throw_inner(void) { longjmp(g_inner, 10); }
static void throw_outer(void) { longjmp(g_outer, 20); }

/* ------------------------------------------------------------------ */
int main(void)
{
    log_init("setjmp-test.log");
    log_write(NONE, "=== setjmp/longjmp Test ===\n");

    /* 1. setjmp returns 0 on first call */
    {
        jmp_buf b;
        chk("setjmp returns 0 initially", setjmp(b) == 0);
    }

    /* 2. longjmp delivers the specified value */
    chk("longjmp delivers value 42", test_basic() == 42);

    /* 3. longjmp(env, 0) yields 1 */
    chk("longjmp(env,0) returns 1", test_zero_becomes_one() == 1);

    /* 4. longjmp from depth-3 call stack */
    chk("longjmp from depth-3 stack", test_deep() == 99);

    /* 5. multiple longjmps to the same buf accumulate correctly */
    {
        int r = setjmp(g_env);
        if (r == 0) longjmp(g_env, 1);
        if (r == 1) longjmp(g_env, 2);
        if (r == 2) longjmp(g_env, 3);
        chk("multiple longjmps to same buf", r == 3);
    }

    /* 6. stack pointer is restored after longjmp */
    {
        volatile uint32_t sp_before = 0, sp_after = 0;
        asm volatile ("mv %0, sp" : "=r"(sp_before));
        int r = setjmp(g_env);
        if (r == 0) {
            /* grow the stack inside the if-branch, then jump out */
            volatile char tmp[64];
            (void)tmp;
            longjmp(g_env, 7);
        }
        asm volatile ("mv %0, sp" : "=r"(sp_after));
        chk("sp restored after longjmp",
            r == 7 && sp_before == sp_after);
    }

    /* 7. nested try/catch -- inner catches then rethrows to outer */
    {
        volatile int inner_caught = 0, outer_caught = 0;
        if (setjmp(g_outer) == 0) {
            if (setjmp(g_inner) == 0) {
                throw_inner();          /* longjmp to g_inner */
            } else {
                inner_caught = 1;
                throw_outer();          /* longjmp to g_outer */
            }
        } else {
            outer_caught = 1;
        }
        chk("try/catch: inner caught",                 inner_caught == 1);
        chk("try/catch: outer caught after rethrow",   outer_caught == 1);
    }

    /* 8. callee-saved registers are preserved across longjmp */
    {
        /* Force s1 to a known value, longjmp out, verify it is unchanged */
        volatile int s1_expected = 0xABCD;
        register int s1_saved asm("s1") = s1_expected;
        (void)s1_saved;                 /* prevent optimisation */
        int r = setjmp(g_env);
        if (r == 0) {
            /* scribble caller-saved regs, then jump */
            volatile int x = 0; (void)x;
            longjmp(g_env, 5);
        }
        register int s1_after asm("s1");
        chk("s1 preserved across longjmp", s1_after == s1_expected);
    }

    /* 9-12. longjmp with several values round-trips correctly */
    {
        static const int vals[] = { 1, 13, 77, 255 };
        for (int i = 0; i < 4; i++) {
            int r = setjmp(g_env);
            if (r == 0) longjmp(g_env, vals[i]);
            chk("longjmp value round-trip", r == vals[i]);
        }
    }

    log_write(NONE, "\n%d PASS  %d FAIL\n", g_pass, g_fail);
    log_close();
    return g_fail ? 1 : 0;
}
