/* **************************************************************************
 *    RISC-V Emulator - Prime number finder using Sieve of Eratosthenes
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

// Prime number finder using Sieve of Eratosthenes
// Tests: arrays, loops, memory, bit operations
// By Ulrik Hørlyk Hjort 2026

int printf(const char *fmt, ...);

#define MAX_N 1000

char is_prime[MAX_N + 1];

void sieve_of_eratosthenes(int n) {
    // Initialize all as prime
    for (int i = 0; i <= n; i++) {
        is_prime[i] = 1;
    }

    is_prime[0] = is_prime[1] = 0;  // 0 and 1 are not prime

    // Sieve
    for (int i = 2; i * i <= n; i++) {
        if (is_prime[i]) {
            for (int j = i * i; j <= n; j += i) {
                is_prime[j] = 0;
            }
        }
    }
}

int main(void) {
    printf("=== Prime Number Finder ===\n\n");
    printf("Finding all primes up to %d...\n\n", MAX_N);

    sieve_of_eratosthenes(MAX_N);

    // Count and display primes
    int count = 0;
    for (int i = 2; i <= MAX_N; i++) {
        if (is_prime[i]) {
            count++;
            if (count % 10 == 1) {
                printf("\n");  // New line every 10 primes
            }
            printf("%d ", i);
        }
    }

    printf("\n\nFound %d primes up to %d\n", count, MAX_N);
    printf("Done!\n");

    while (1);
    return 0;
}
