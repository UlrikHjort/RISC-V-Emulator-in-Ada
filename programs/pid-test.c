/* **************************************************************************
 *   RISC-V Emulator - Discrete-time PID controller in Q16.16 fixed-point
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

// pid-test.c -- Discrete-time PID controller in Q16.16 fixed-point.
//
// Implements a standard discrete PID:
//   error[k] = setpoint - measurement[k]
//   P[k] = Kp * error[k]
//   I[k] = I[k-1] + Ki * error[k] * dt
//   D[k] = Kd * (error[k] - error[k-1]) / dt
//   output[k] = clamp(P[k] + I[k] + D[k], out_min, out_max)
// With anti-windup: integrator is clamped to [i_min, i_max].
//
// All arithmetic in Q16.16 (int32_t with 16 fractional bits).
// dt = 1 time unit (simplifies D term to Kd * delta_e).
//
// Tests:
//   - P-only: output = Kp * error
//   - I-only: output accumulates over multiple steps
//   - D-only: output = Kd * (error - prev_error)
//   - Combined PID: known step-response values
//   - Anti-windup: integrator clamp stops runaway
//   - Setpoint tracking: output converges to setpoint on simple plant
//
// Build: cd programs && make run-pid-test
// By Ulrik Hørlyk Hjort 2026

#include <stdint.h>
#include "log.h"

void putchar(char c);
static void uart_puts(const char *s) {
    while (*s) { if (*s == '\n') putchar('\r'); putchar(*s++); }
}

static int g_pass = 0, g_fail = 0;

/* -- Q16.16 arithmetic ----------------------------------------------------- */

#define Q16_ONE    ((int32_t)0x00010000)  /* 1.0 */
#define Q16_HALF   ((int32_t)0x00008000)  /* 0.5 */

static inline int32_t q16_mul(int32_t a, int32_t b) {
    return (int32_t)(((int64_t)a * (int64_t)b) >> 16);
}

static inline int32_t q16_from_int(int32_t n) {
    return n * Q16_ONE;
}

static inline int32_t q16_int_part(int32_t a) {
    return a >> 16;
}

/* -- PID state ------------------------------------------------------------- */

typedef struct {
    int32_t Kp, Ki, Kd;       /* gains in Q16.16 */
    int32_t out_min, out_max;  /* output clamp Q16.16 */
    int32_t i_min, i_max;     /* integrator clamp Q16.16 */
    int32_t integrator;        /* running sum Q16.16 */
    int32_t prev_error;        /* for D term Q16.16 */
} pid_t;

static void pid_init(pid_t *pid,
                     int32_t Kp, int32_t Ki, int32_t Kd,
                     int32_t out_min, int32_t out_max,
                     int32_t i_min, int32_t i_max)
{
    pid->Kp = Kp; pid->Ki = Ki; pid->Kd = Kd;
    pid->out_min = out_min; pid->out_max = out_max;
    pid->i_min = i_min;     pid->i_max = i_max;
    pid->integrator = 0;
    pid->prev_error = 0;
}

static int32_t pid_update(pid_t *pid, int32_t setpoint, int32_t measurement) {
    int32_t error = setpoint - measurement;

    /* P term */
    int32_t p_term = q16_mul(pid->Kp, error);

    /* I term with anti-windup clamp */
    pid->integrator += q16_mul(pid->Ki, error);
    if (pid->integrator > pid->i_max) pid->integrator = pid->i_max;
    if (pid->integrator < pid->i_min) pid->integrator = pid->i_min;

    /* D term: Kd * (error - prev_error) */
    int32_t d_term = q16_mul(pid->Kd, error - pid->prev_error);
    pid->prev_error = error;

    /* Sum and clamp output */
    int32_t output = p_term + pid->integrator + d_term;
    if (output > pid->out_max) output = pid->out_max;
    if (output < pid->out_min) output = pid->out_min;
    return output;
}

/* -- Helper macros --------------------------------------------------------- */

static void chk_q16(const char *lbl, int32_t got, int32_t exp, int32_t tol) {
    int32_t diff = got - exp;
    if (diff < 0) diff = -diff;
    if (diff <= tol) {
        log_write(NONE, "  PASS  %s (got %d exp %d)\n", lbl,
                  (int)q16_int_part(got), (int)q16_int_part(exp));
        g_pass++;
    } else {
        log_write(NONE, "  FAIL  %s: got 0x%x (%d) exp 0x%x (%d) tol %d\n",
                  lbl, (uint32_t)got, (int)q16_int_part(got),
                  (uint32_t)exp, (int)q16_int_part(exp), (int)tol);
        g_fail++;
    }
}

static void chk32(const char *lbl, int32_t got, int32_t exp) {
    if (got == exp) {
        log_write(NONE, "  PASS  %s\n", lbl);
        g_pass++;
    } else {
        log_write(NONE, "  FAIL  %s: got %d  exp %d\n", lbl, (int)got, (int)exp);
        g_fail++;
    }
}

/* -- Test: P-only controller ----------------------------------------------- */

static void test_p_only(void) {
    log_write(NONE, "\n=== P-only (Ki=0, Kd=0) ===\n");
    pid_t pid;
    int32_t out;

    /* Kp=1.0, error=10 -> output=10 */
    pid_init(&pid, Q16_ONE, 0, 0,
             q16_from_int(-1000), q16_from_int(1000),
             q16_from_int(-1000), q16_from_int(1000));
    out = pid_update(&pid, q16_from_int(10), q16_from_int(0));
    chk_q16("P: Kp=1, e=10 -> out=10",    out, q16_from_int(10), 0);

    /* Kp=2.0, error=5 -> output=10 */
    pid_init(&pid, 2 * Q16_ONE, 0, 0,
             q16_from_int(-1000), q16_from_int(1000),
             q16_from_int(-1000), q16_from_int(1000));
    out = pid_update(&pid, q16_from_int(5), q16_from_int(0));
    chk_q16("P: Kp=2, e=5 -> out=10",     out, q16_from_int(10), 0);

    /* Kp=0.5, error=8 -> output=4 */
    pid_init(&pid, Q16_HALF, 0, 0,
             q16_from_int(-1000), q16_from_int(1000),
             q16_from_int(-1000), q16_from_int(1000));
    out = pid_update(&pid, q16_from_int(8), q16_from_int(0));
    chk_q16("P: Kp=0.5, e=8 -> out=4",    out, q16_from_int(4), 0);

    /* Negative error: Kp=1, sp=5, meas=10 -> e=-5, out=-5 */
    pid_init(&pid, Q16_ONE, 0, 0,
             q16_from_int(-1000), q16_from_int(1000),
             q16_from_int(-1000), q16_from_int(1000));
    out = pid_update(&pid, q16_from_int(5), q16_from_int(10));
    chk_q16("P: Kp=1, e=-5 -> out=-5",    out, q16_from_int(-5), 0);

    /* Output clamping: Kp=1, e=500, out_max=100 -> clamped to 100 */
    pid_init(&pid, Q16_ONE, 0, 0,
             q16_from_int(-100), q16_from_int(100),
             q16_from_int(-100), q16_from_int(100));
    out = pid_update(&pid, q16_from_int(500), q16_from_int(0));
    chk_q16("P: output clamped to 100",   out, q16_from_int(100), 0);
}

/* -- Test: I-only controller ----------------------------------------------- */

static void test_i_only(void) {
    log_write(NONE, "\n=== I-only (Kp=0, Kd=0) ===\n");
    pid_t pid;
    int32_t out;

    /* Ki=1.0, 3 steps with e=4 each -> I accumulates: 4, 8, 12 */
    pid_init(&pid, 0, Q16_ONE, 0,
             q16_from_int(-1000), q16_from_int(1000),
             q16_from_int(-1000), q16_from_int(1000));
    pid_update(&pid, q16_from_int(4), q16_from_int(0));  /* I=4 */
    pid_update(&pid, q16_from_int(4), q16_from_int(0));  /* I=8 */
    out = pid_update(&pid, q16_from_int(4), q16_from_int(0));  /* I=12 */
    chk_q16("I: Ki=1, 3*e=4 -> out=12",   out, q16_from_int(12), 0);

    /* Anti-windup: Ki=1, e=500, i_max=50 -> integrator clamps to 50 */
    pid_init(&pid, 0, Q16_ONE, 0,
             q16_from_int(-1000), q16_from_int(1000),
             q16_from_int(-50), q16_from_int(50));
    pid_update(&pid, q16_from_int(500), q16_from_int(0));
    pid_update(&pid, q16_from_int(500), q16_from_int(0));
    out = pid_update(&pid, q16_from_int(500), q16_from_int(0));
    chk_q16("I: anti-windup i_max=50",    out, q16_from_int(50), 0);

    /* Integrator accumulates with small steps */
    pid_init(&pid, 0, Q16_HALF, 0,    /* Ki=0.5 */
             q16_from_int(-1000), q16_from_int(1000),
             q16_from_int(-1000), q16_from_int(1000));
    pid_update(&pid, q16_from_int(2), q16_from_int(0));  /* I += 0.5*2 = 1 */
    pid_update(&pid, q16_from_int(4), q16_from_int(0));  /* I += 0.5*4 = 2 -> I=3 */
    out = pid_update(&pid, q16_from_int(6), q16_from_int(0));  /* I += 0.5*6 = 3 -> I=6 */
    chk_q16("I: Ki=0.5, steps 2+4+6 -> 6", out, q16_from_int(6), 0);
}

/* -- Test: D-only controller ----------------------------------------------- */

static void test_d_only(void) {
    log_write(NONE, "\n=== D-only (Kp=0, Ki=0) ===\n");
    pid_t pid;
    int32_t out;

    /* Kd=1, step from e=0 to e=5 (prev=0): D = 1*(5-0) = 5 */
    pid_init(&pid, 0, 0, Q16_ONE,
             q16_from_int(-1000), q16_from_int(1000),
             q16_from_int(-1000), q16_from_int(1000));
    out = pid_update(&pid, q16_from_int(5), q16_from_int(0));
    chk_q16("D: Kd=1, e=5 (prev=0) -> 5", out, q16_from_int(5), 0);

    /* Second step with same error: e=5 again, prev=5 -> D = 0 */
    out = pid_update(&pid, q16_from_int(5), q16_from_int(0));
    chk_q16("D: Kd=1, e=5 (prev=5) -> 0", out, q16_from_int(0), 0);

    /* Error decreasing: e goes from 10 to 3 -> D = 1*(3-10) = -7 */
    pid_init(&pid, 0, 0, Q16_ONE,
             q16_from_int(-1000), q16_from_int(1000),
             q16_from_int(-1000), q16_from_int(1000));
    pid_update(&pid, q16_from_int(10), q16_from_int(0));  /* sets prev_error=10 */
    out = pid_update(&pid, q16_from_int(3), q16_from_int(0));
    chk_q16("D: Kd=1, e: 10->3 -> -7",     out, q16_from_int(-7), 0);

    /* Kd=2, delta=6: D = 2*6 = 12 */
    pid_init(&pid, 0, 0, 2 * Q16_ONE,
             q16_from_int(-1000), q16_from_int(1000),
             q16_from_int(-1000), q16_from_int(1000));
    pid_update(&pid, q16_from_int(0), q16_from_int(0));   /* prev_error=0 */
    out = pid_update(&pid, q16_from_int(6), q16_from_int(0));
    chk_q16("D: Kd=2, e: 0->6 -> 12",      out, q16_from_int(12), 0);
}

/* -- Test: Combined PID ---------------------------------------------------- */

static void test_combined(void) {
    log_write(NONE, "\n=== Combined PID ===\n");
    pid_t pid;
    int32_t out;

    /* Kp=1, Ki=0.5, Kd=1; sp=10, meas=0
     * Step 1: e=10, P=10, I=0+0.5*10=5, D=1*(10-0)=10  -> out=25
     * Step 2: e=10, P=10, I=5+5=10,     D=1*(10-10)=0  -> out=20
     * Step 3: e=10, P=10, I=10+5=15,    D=0             -> out=25
     */
    pid_init(&pid, Q16_ONE, Q16_HALF, Q16_ONE,
             q16_from_int(-1000), q16_from_int(1000),
             q16_from_int(-1000), q16_from_int(1000));

    out = pid_update(&pid, q16_from_int(10), q16_from_int(0));
    chk_q16("PID step1: P=10,I=5,D=10->25", out, q16_from_int(25), 0);

    out = pid_update(&pid, q16_from_int(10), q16_from_int(0));
    chk_q16("PID step2: P=10,I=10,D=0->20", out, q16_from_int(20), 0);

    out = pid_update(&pid, q16_from_int(10), q16_from_int(0));
    chk_q16("PID step3: P=10,I=15,D=0->25", out, q16_from_int(25), 0);
}

/* -- Test: Step response on simple plant ------------------------------------ */
/*
 * Plant model: integrator  measurement[k+1] = measurement[k] + output[k] * Kplant
 * With Kplant = 0.1, setpoint = 100.
 * P-only control (Kp=0.5) converges (with steady-state error).
 * PI control (Kp=0.5, Ki=0.05) converges to exact setpoint.
 */
static void test_step_response(void) {
    log_write(NONE, "\n=== Step Response (PI controller, integrator plant) ===\n");
    pid_t pid;

    int32_t Kplant   = Q16_ONE / 10;  /* 0.1 */
    int32_t setpoint = q16_from_int(100);
    int32_t meas     = q16_from_int(0);
    int32_t output;

    pid_init(&pid,
             Q16_HALF,            /* Kp = 0.5 */
             Q16_ONE / 20,        /* Ki = 0.05 */
             0,                   /* Kd = 0 */
             q16_from_int(-500), q16_from_int(500),
             q16_from_int(-200), q16_from_int(200));

    /* Run 100 steps */
    for (int k = 0; k < 100; k++) {
        output = pid_update(&pid, setpoint, meas);
        meas += q16_mul(output, Kplant);
    }

    /* After 100 steps the PI should have driven meas close to 100 */
    int32_t error = setpoint - meas;
    if (error < 0) error = -error;
    int ok = (q16_int_part(error) <= 5);   /* within 5 units */
    if (ok) {
        log_write(NONE, "  PASS  PI converged: meas~%d (err=%d)\n",
                  (int)q16_int_part(meas), (int)q16_int_part(error));
        g_pass++;
    } else {
        log_write(NONE, "  FAIL  PI didn't converge: meas=%d err=%d\n",
                  (int)q16_int_part(meas), (int)q16_int_part(error));
        g_fail++;
    }
}

/* -- Test: Anti-windup during output saturation ----------------------------- */

static void test_antiwindup(void) {
    log_write(NONE, "\n=== Anti-Windup ===\n");
    pid_t pid;

    /* Large constant error, small output limit -> integrator would runaway
     * without anti-windup. With i_max=10 it must stay bounded. */
    pid_init(&pid,
             Q16_ONE,           /* Kp=1 */
             Q16_ONE,           /* Ki=1 */
             0,                 /* Kd=0 */
             q16_from_int(-20), q16_from_int(20),
             q16_from_int(-10), q16_from_int(10));

    int32_t out = 0;
    for (int k = 0; k < 20; k++)
        out = pid_update(&pid, q16_from_int(100), q16_from_int(0));

    /* Integrator should be clamped to i_max=10; P=100 clamped -> out=out_max=20 */
    chk_q16("antiwindup: output clamped", out, q16_from_int(20), 0);

    /* Verify integrator didn't blow up (its contribution should be exactly 10) */
    /* We can't read integrator directly, but after removing the large P contribution:
     * If we set e=0 (meas=setpoint), P=0, D=Kd*(0-100)=0, so out = just integrator */
    int32_t int_only = pid_update(&pid, q16_from_int(100), q16_from_int(100));
    /* e=0: P=0, D=0, I unchanged -> out = integrator (clamped to 10) + clamp */
    /* Since I was at 10 (i_max) and e=0, I stays at 10, so out = 0+10+0 = 10 */
    chk_q16("antiwindup: integrator=i_max", int_only, q16_from_int(10), 0);
}

/* -- Test: Reset and zero state --------------------------------------------- */

static void test_reset(void) {
    log_write(NONE, "\n=== Reset / Zero State ===\n");
    pid_t pid;

    /* Fresh PID with e=0 -> output=0 */
    pid_init(&pid, Q16_ONE, Q16_ONE, Q16_ONE,
             q16_from_int(-100), q16_from_int(100),
             q16_from_int(-100), q16_from_int(100));
    int32_t out = pid_update(&pid, q16_from_int(0), q16_from_int(0));
    chk32("zero error -> zero output", q16_int_part(out), 0);

    /* After several non-zero steps, re-init should reset */
    pid_update(&pid, q16_from_int(10), q16_from_int(0));
    pid_update(&pid, q16_from_int(10), q16_from_int(0));

    pid_init(&pid, Q16_ONE, Q16_ONE, Q16_ONE,
             q16_from_int(-100), q16_from_int(100),
             q16_from_int(-100), q16_from_int(100));
    out = pid_update(&pid, q16_from_int(5), q16_from_int(0));
    /* Fresh: P=5, I=5, D=5*(5-0)=5 -> out=15 */
    chk_q16("after reinit: P+I+D=15", out, q16_from_int(15), 0);
}

/* -- Main ------------------------------------------------------------------- */

int main(void) {
    uart_puts("=== PID Controller Test ===\n");
    if (log_init("pid-test.log") != 0) {
        uart_puts("ERROR: log_init failed\n"); return 1;
    }
    log_write(NONE, "=== Discrete PID Controller (Q16.16 Fixed-Point) ===\n");

    test_p_only();
    test_i_only();
    test_d_only();
    test_combined();
    test_step_response();
    test_antiwindup();
    test_reset();

    log_write(NONE, "\n=== Summary ===\n");
    log_write(NONE, "  PASS: %d\n", g_pass);
    log_write(NONE, "  FAIL: %d\n", g_fail);
    log_write(NONE, "  %s\n", g_fail == 0 ? "ALL TESTS PASSED" : "SOME TESTS FAILED");
    log_close();

    uart_puts(g_fail == 0 ? "ALL PASSED\n" : "SOME FAILED\n");
    return g_fail;
}
