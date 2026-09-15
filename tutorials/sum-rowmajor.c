/*
 * Tutorial 3 example -- cache-FRIENDLY traversal.
 *
 * Sums a 128x128 int32 matrix (64 KB, larger than the 16 KB L1 D-cache) in
 * row-major order: element [i][j] then [i][j+1], i.e. sequential in memory.
 * Each cache line brings in the next elements you need, so misses are rare.
 * sum-colmajor.c computes the identical sum the cache-hostile way.
 */
#include <stdint.h>
#include "log.h"

#define N 128
static int32_t m[N][N];

int main(void)
{
    log_init("sum-rowmajor.log");

    for (int i = 0; i < N; i++)
        for (int j = 0; j < N; j++)
            m[i][j] = i * N + j;

    uint64_t sum = 0;
    for (int i = 0; i < N; i++)          /* row-major: [i][0],[i][1],... */
        for (int j = 0; j < N; j++)
            sum += m[i][j];

    log_write(NONE, "sum = %u\n", (unsigned) sum);
    log_close();
    return 0;
}
