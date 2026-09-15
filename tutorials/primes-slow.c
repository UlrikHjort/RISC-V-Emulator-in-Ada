/*
 * Tutorial 1 example -- the SLOW version.
 *
 * Counts the primes below LIMIT using a deliberately naive primality test
 * that trial-divides by every integer up to n-1. The profiler will show
 * almost all cycles inside is_prime(); primes-fast.c is the optimized
 * counterpart used in the "after" measurement.
 */
#include <stdint.h>
#include "log.h"

#define LIMIT 4000

static int __attribute__((noinline)) is_prime(uint32_t n) {
    if (n < 2) return 0;
    for (uint32_t d = 2; d < n; d++)      /* trial-divide by everything */
        if (n % d == 0) return 0;
    return 1;
}

static uint32_t __attribute__((noinline)) count_primes(uint32_t limit) {
    uint32_t count = 0;
    for (uint32_t n = 2; n < limit; n++)
        if (is_prime(n)) count++;
    return count;
}

int main(void) {
    log_init("primes-slow.log");
    uint32_t c = count_primes(LIMIT);
    log_write(NONE, "primes below %u: %u\n", (unsigned) LIMIT, (unsigned) c);
    log_close();
    return 0;
}
