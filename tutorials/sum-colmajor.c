/*
 * Tutorial 3 example -- cache-HOSTILE traversal.
 *
 * Identical to sum-rowmajor.c except the summation loop walks column-major:
 * [0][j],[1][j],... Each step jumps N*4 = 512 bytes, so almost every access
 * touches a fresh cache line and misses. Same answer, far more D-cache misses.
 */
#include <stdint.h>
#include "log.h"

#define N 128
static int32_t m[N][N];

int main(void) {
    log_init("sum-colmajor.log");

    for (int i = 0; i < N; i++)
        for (int j = 0; j < N; j++)
            m[i][j] = i * N + j;

    uint64_t sum = 0;
    for (int j = 0; j < N; j++)          /* column-major: [0][j],[1][j],... */
        for (int i = 0; i < N; i++)
            sum += m[i][j];

    log_write(NONE, "sum = %u\n", (unsigned) sum);
    log_close();
    return 0;
}
