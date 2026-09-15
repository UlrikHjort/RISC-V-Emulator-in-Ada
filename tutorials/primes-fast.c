/*
 * Tutorial 1 example -- the FAST version.
 *
 * Same result as primes-slow.c, but is_prime() stops at sqrt(n) and skips
 * even divisors. The profiler shows the same shape (is_prime dominates) but
 * a fraction of the cycles -- the point of the walkthrough.
 */
#include <stdint.h>
#include "log.h"

#define LIMIT 4000

static int __attribute__((noinline)) is_prime(uint32_t n)
{
    if (n < 2)      return 0;
    if (n % 2 == 0) return n == 2;
    for (uint32_t d = 3; d * d <= n; d += 2)   /* odd divisors up to sqrt(n) */
        if (n % d == 0) return 0;
    return 1;
}

static uint32_t __attribute__((noinline)) count_primes(uint32_t limit)
{
    uint32_t count = 0;
    for (uint32_t n = 2; n < limit; n++)
        if (is_prime(n)) count++;
    return count;
}

int main(void)
{
    log_init("primes-fast.log");
    uint32_t c = count_primes(LIMIT);
    log_write(NONE, "primes below %u: %u\n", (unsigned) LIMIT, (unsigned) c);
    log_close();
    return 0;
}
