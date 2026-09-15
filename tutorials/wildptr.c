/*
 * Tutorial 2 example -- a wild-pointer bug.
 *
 * slot_for() returns NULL when the key is not found, and main() forgets to
 * check for it before writing through the pointer. On real hardware this
 * might silently corrupt memory; under the emulator it traps as a store
 * access fault, and mtval hands you the offending address.
 *
 * The key is read from a volatile so the compiler cannot fold the missing
 * lookup (and the undefined NULL store) away at compile time -- we want the
 * bug to actually execute, the way it would with a runtime input.
 */
#include <stdint.h>
#include "log.h"

static int *__attribute__((noinline)) slot_for(int *table, int n, int key)
{
    for (int i = 0; i < n; i++)
        if (table[i * 2] == key)
            return &table[i * 2 + 1];
    return 0;                     /* not found */
}

int main(void)
{
    int table[8] = { 1, 10, 2, 20, 3, 30, 4, 40 };
    volatile int lookup_key = 99;      /* pretend this came from input */

    log_init("wildptr.log");
    log_write(NONE, "looking up key %d...\n", lookup_key);

    int *v = slot_for(table, 4, lookup_key);   /* 99 is absent -> NULL */
    *v = 123;                                  /* BUG: no NULL check   */

    log_write(NONE, "stored %d (this line is never reached)\n", *v);
    log_close();
    return 0;
}
