# C Library Reference

This document describes the bare-metal C library available for RISC-V programs.

## Overview

The emulator provides a minimal but functional C library suitable for embedded development:
- **Floating-point printf** - Full support for `%f`, `%e`, `%g` formats
- **String manipulation** - Complete `string.h` implementation (14 functions)
- **Standard library utilities** - Conversion, sorting, searching, random numbers
- **Memory allocation** - malloc, free, realloc, calloc
- **I/O functions** - printf, putchar, getchar, puts

All functions are implemented in `programs/` directory and automatically linked with your programs.

---

## Floating-Point Printf

### Supported Formats

| Format | Description | Example | Output |
|--------|-------------|---------|--------|
| `%f` | Fixed-point | `printf("%.2f", 3.14159)` | `3.14` |
| `%e` | Exponential | `printf("%e", 1234.5)` | `1.234500e+03` |
| `%g` | General (auto) | `printf("%g", 0.00001)` | `1.00000e-05` |

### Precision Control

```c
printf("%.2f", 3.14159);    // 3.14
printf("%.4f", 3.14159);    // 3.1416
printf("%.0f", 3.14159);    // 3

printf("%.2e", 123.456);    // 1.23e+02
printf("%.4e", 123.456);    // 1.2346e+02

printf("%.3g", 123.456);    // 123
printf("%.3g", 0.000123);   // 1.23e-04
```

### Default Precision

If precision is not specified, defaults are:
- `%f` -> 6 decimal places
- `%e` -> 6 decimal places
- `%g` -> 6 significant digits

```c
printf("%f", 3.14159);      // 3.141590
printf("%e", 3.14159);      // 3.141590e+00
printf("%g", 3.14159);      // 3.14159
```

### Special Values

```c
double inf = 1.0 / 0.0;
double neg_inf = -1.0 / 0.0;
double nan = 0.0 / 0.0;

printf("%f", inf);          // inf
printf("%f", neg_inf);      // -inf
printf("%f", nan);          // nan
```

### Complete Example

```c
int printf(const char *fmt, ...);

int main(void) {
    double pi = 3.14159265359;
    double e = 2.71828182846;

    // Fixed-point
    printf("Pi = %f\n", pi);              // Pi = 3.141593
    printf("Pi = %.2f\n", pi);            // Pi = 3.14
    printf("Pi = %.10f\n", pi);           // Pi = 3.1415926536

    // Exponential
    printf("Large: %e\n", 1234567.89);    // Large: 1.234568e+06
    printf("Small: %e\n", 0.0000123);     // Small: 1.230000e-05

    // General format (auto-selects best)
    printf("Auto: %g\n", 123.456);        // Auto: 123.456
    printf("Auto: %g\n", 0.0000001);      // Auto: 1.00000e-07

    // Mixed formats
    printf("Pi=%.2f, e=%.2f\n", pi, e);   // Pi=3.14, e=2.72

    // Scientific notation
    printf("Avogadro: %.3e\n", 6.022e23); // Avogadro: 6.022e+23

    return 0;
}
```

### Mandelbrot Example

The mandelbrot program now uses floating-point printf to display computation parameters:

```c
printf("=== Mandelbrot Set ===\n");
printf("Region: x=[%.1f, %.1f], y=[%.1f, %.1f]\n",
       x_min, x_max, y_min, y_max);
printf("Step: dx=%.6f, dy=%.6f\n", dx, dy);
```

Output:
```
=== Mandelbrot Set ===
Region: x=[-2.0, 1.0], y=[-1.0, 1.0]
Step: dx=0.037500, dy=0.050000
```

---

## String Functions

All functions from standard `string.h` are available by including `string.h` in your program.

### String Length

```c
#include "string.h"

size_t strlen(const char *s);
```

**Example:**
```c
int len = strlen("Hello");     // len = 5
int empty = strlen("");        // empty = 0
```

### String Copy

```c
char *strcpy(char *dst, const char *src);
char *strncpy(char *dst, const char *src, size_t n);
```

**Example:**
```c
char buf[20];

strcpy(buf, "Hello");          // buf = "Hello"
strncpy(buf, "World!", 3);     // buf = "Wor"
buf[3] = '\0';                 // Null-terminate
```

### String Comparison

```c
int strcmp(const char *s1, const char *s2);
int strncmp(const char *s1, const char *s2, size_t n);
```

**Returns:**
- `< 0` if s1 < s2
- `= 0` if s1 == s2
- `> 0` if s1 > s2

**Example:**
```c
if (strcmp("abc", "abc") == 0) {
    // Strings are equal
}

if (strncmp("Hello", "Help", 3) == 0) {
    // First 3 characters match
}

if (strcmp("abc", "xyz") < 0) {
    // "abc" comes before "xyz"
}
```

### String Concatenation

```c
char *strcat(char *dst, const char *src);
char *strncat(char *dst, const char *src, size_t n);
```

**Example:**
```c
char buf[50] = "Hello";

strcat(buf, " World");         // buf = "Hello World"
strncat(buf, "!!!", 2);        // buf = "Hello World!!"
```

### Memory Operations

```c
void *memcpy(void *dst, const void *src, size_t n);
void *memmove(void *dst, const void *src, size_t n);
void *memset(void *s, int c, size_t n);
int memcmp(const void *s1, const void *s2, size_t n);
```

**Example:**
```c
char src[10] = "ABCDEFGH";
char dst[10];

// Copy memory (non-overlapping)
memcpy(dst, src, 8);           // dst = "ABCDEFGH"

// Copy with overlap (use memmove)
memmove(src + 2, src, 5);      // src = "ABABCDE"

// Fill memory with value
memset(dst, 'X', 5);           // dst = "XXXXX..."

// Compare memory
if (memcmp(dst, src, 5) == 0) {
    // First 5 bytes are equal
}

// Copy array of integers
int nums[5] = {1, 2, 3, 4, 5};
int copy[5];
memcpy(copy, nums, sizeof(nums));
```

### Search Functions

```c
char *strchr(const char *s, int c);
char *strrchr(const char *s, int c);
char *strstr(const char *haystack, const char *needle);
```

**Example:**
```c
char *str = "Hello World";

// Find first 'o'
char *p = strchr(str, 'o');    // p points to "o World"

// Find last 'o'
p = strrchr(str, 'o');         // p points to "orld"

// Find substring
p = strstr(str, "World");      // p points to "World"

if (strchr(str, 'x') == NULL) {
    // 'x' not found
}
```

### Complete Example

```c
#include "string.h"

int printf(const char *fmt, ...);

int main(void) {
    char buffer[100];
    char name[50] = "Alice";

    // Build a string
    strcpy(buffer, "Hello, ");
    strcat(buffer, name);
    strcat(buffer, "!");
    printf("%s\n", buffer);        // "Hello, Alice!"

    // String length
    int len = strlen(buffer);
    printf("Length: %d\n", len);   // Length: 13

    // Search
    if (strstr(buffer, "Alice") != NULL) {
        printf("Found Alice!\n");
    }

    // Copy part of string
    char first_word[20];
    strncpy(first_word, buffer, 5);
    first_word[5] = '\0';
    printf("First word: %s\n", first_word);  // "Hello"

    // Compare
    if (strcmp(name, "Alice") == 0) {
        printf("Name is Alice\n");
    }

    // Memory operations
    int numbers[5] = {1, 2, 3, 4, 5};
    int backup[5];
    memcpy(backup, numbers, sizeof(numbers));

    return 0;
}
```

---

## Numeric Conversion Functions

### String to Integer

```c
int atoi(const char *str);
long atol(const char *str);
double atof(const char *str);
```

**Example:**
```c
int num = atoi("123");           // num = 123
int neg = atoi("-456");          // neg = -456
int partial = atoi("789abc");    // partial = 789

long big = atol("1234567");      // big = 1234567

double pi = atof("3.14159");     // pi = 3.14159
double neg_f = atof("-2.5");     // neg_f = -2.5
```

**Whitespace Handling:**
```c
int a = atoi("  42");            // a = 42 (leading spaces ignored)
int b = atoi("+100");            // b = 100 (plus sign allowed)
```

**Complete Example:**
```c
int printf(const char *fmt, ...);
extern int atoi(const char *str);
extern double atof(const char *str);

int main(void) {
    // Parse command-line-like input
    const char *port_str = "8080";
    const char *timeout_str = "30.5";

    int port = atoi(port_str);
    double timeout = atof(timeout_str);

    printf("Port: %d\n", port);        // Port: 8080
    printf("Timeout: %.1f\n", timeout); // Timeout: 30.5

    return 0;
}
```

---

## Sorting and Searching

### Quick Sort

```c
void qsort(void *base, size_t nmemb, size_t size,
           int (*compar)(const void *, const void *));
```

**Parameters:**
- `base` - Pointer to array
- `nmemb` - Number of elements
- `size` - Size of each element in bytes
- `compar` - Comparison function

**Example:**
```c
// Comparison function for integers
int compare_ints(const void *a, const void *b) {
    int arg1 = *(const int *)a;
    int arg2 = *(const int *)b;

    if (arg1 < arg2) return -1;
    if (arg1 > arg2) return 1;
    return 0;
}

int main(void) {
    int numbers[] = {5, 2, 8, 1, 9, 3};
    int count = 6;

    // Sort array
    qsort(numbers, count, sizeof(int), compare_ints);

    // Now: numbers = {1, 2, 3, 5, 8, 9}

    return 0;
}
```

**Sorting Strings:**
```c
int compare_strings(const void *a, const void *b) {
    const char *str1 = *(const char **)a;
    const char *str2 = *(const char **)b;
    return strcmp(str1, str2);
}

int main(void) {
    const char *names[] = {"Charlie", "Alice", "Bob"};

    qsort(names, 3, sizeof(char *), compare_strings);

    // Now: {"Alice", "Bob", "Charlie"}

    return 0;
}
```

### Binary Search

```c
void *bsearch(const void *key, const void *base, size_t nmemb,
              size_t size, int (*compar)(const void *, const void *));
```

**Returns:** Pointer to matching element, or NULL if not found

**Example:**
```c
int main(void) {
    int sorted[] = {1, 3, 5, 7, 9, 11, 13, 15};
    int count = 8;
    int key = 7;

    int *result = (int *)bsearch(&key, sorted, count,
                                  sizeof(int), compare_ints);

    if (result != NULL) {
        printf("Found: %d\n", *result);  // Found: 7
    } else {
        printf("Not found\n");
    }

    // Search for non-existent value
    key = 4;
    result = (int *)bsearch(&key, sorted, count,
                            sizeof(int), compare_ints);
    if (result == NULL) {
        printf("4 not found\n");
    }

    return 0;
}
```

**Complete Example - Sort and Search:**
```c
extern void qsort(void *base, size_t n, size_t size,
                  int (*cmp)(const void *, const void *));
extern void *bsearch(const void *key, const void *base, size_t n,
                     size_t size, int (*cmp)(const void *, const void *));

int compare_ints(const void *a, const void *b) {
    return (*(int *)a - *(int *)b);
}

int main(void) {
    int data[] = {42, 17, 93, 8, 55, 31, 66};
    int count = 7;

    printf("Original: ");
    for (int i = 0; i < count; i++) {
        printf("%d ", data[i]);
    }
    printf("\n");

    // Sort
    qsort(data, count, sizeof(int), compare_ints);

    printf("Sorted: ");
    for (int i = 0; i < count; i++) {
        printf("%d ", data[i]);
    }
    printf("\n");

    // Search
    int search_val = 55;
    int *found = bsearch(&search_val, data, count,
                         sizeof(int), compare_ints);

    if (found) {
        printf("Found %d at position %d\n",
               *found, (int)(found - data));
    }

    return 0;
}
```

---

## Random Number Generation

```c
int rand(void);
void srand(unsigned int seed);
```

**Range:** 0 to 32767 (RAND_MAX)

### Basic Usage

```c
extern int rand(void);
extern void srand(unsigned int seed);

int main(void) {
    // Generate random numbers
    int r1 = rand();
    int r2 = rand();
    int r3 = rand();

    printf("Random: %d %d %d\n", r1, r2, r3);

    return 0;
}
```

### Seeding for Reproducibility

```c
int main(void) {
    // Same seed = same sequence
    srand(42);
    int a1 = rand();
    int a2 = rand();

    srand(42);  // Reset to same seed
    int b1 = rand();
    int b2 = rand();

    // a1 == b1, a2 == b2 (reproducible)

    return 0;
}
```

### Generating Ranges

```c
// Random number in range [0, n)
int rand_range(int n) {
    return rand() % n;
}

// Random number in range [min, max]
int rand_between(int min, int max) {
    return min + rand() % (max - min + 1);
}

int main(void) {
    srand(12345);  // Seed with known value

    // Dice roll (1-6)
    int dice = rand_between(1, 6);

    // Random index (0-9)
    int index = rand_range(10);

    // Coin flip (0 or 1)
    int coin = rand() % 2;

    printf("Dice: %d, Index: %d, Coin: %d\n",
           dice, index, coin);

    return 0;
}
```

### Monte Carlo Example

```c
int main(void) {
    srand(42);

    // Estimate pi using Monte Carlo
    int inside = 0;
    int total = 10000;

    for (int i = 0; i < total; i++) {
        double x = (double)rand() / 32767.0;
        double y = (double)rand() / 32767.0;

        if (x*x + y*y <= 1.0) {
            inside++;
        }
    }

    double pi_estimate = 4.0 * inside / total;
    printf("Pi estimate: %.4f\n", pi_estimate);

    return 0;
}
```

---

## Memory Allocation

### Malloc and Free

```c
void *malloc(size_t size);
void free(void *ptr);
void *calloc(size_t nmemb, size_t size);
void *realloc(void *ptr, size_t size);
```

**Example:**
```c
void *malloc(unsigned long size);
void free(void *ptr);

int main(void) {
    // Allocate single integer
    int *num = malloc(sizeof(int));
    if (num != NULL) {
        *num = 42;
        printf("Value: %d\n", *num);
        free(num);
    }

    // Allocate array
    int *array = malloc(10 * sizeof(int));
    if (array != NULL) {
        for (int i = 0; i < 10; i++) {
            array[i] = i * 2;
        }
        free(array);
    }

    return 0;
}
```

### Memory Alignment

All allocations are 8-byte aligned:

```c
void *p1 = malloc(1);   // Aligned to 8-byte boundary
void *p2 = malloc(1);   // Also 8-byte aligned
void *p3 = malloc(100); // Also 8-byte aligned
```

### Complete Example - Dynamic Linked List

```c
typedef struct Node {
    int data;
    struct Node *next;
} Node;

int main(void) {
    Node *head = NULL;

    // Create list: 10 -> 20 -> 30
    for (int i = 1; i <= 3; i++) {
        Node *node = malloc(sizeof(Node));
        if (node) {
            node->data = i * 10;
            node->next = head;
            head = node;
        }
    }

    // Print list
    Node *current = head;
    while (current) {
        printf("%d -> ", current->data);
        current = current->next;
    }
    printf("NULL\n");

    // Free list
    while (head) {
        Node *temp = head;
        head = head->next;
        free(temp);
    }

    return 0;
}
```

---

## Complete Program Examples

### Example 1: Data Processing

```c
#include "string.h"

int printf(const char *fmt, ...);
extern int atoi(const char *str);
extern void qsort(void *base, size_t n, size_t size,
                  int (*cmp)(const void *, const void *));

int compare(const void *a, const void *b) {
    return (*(int *)a - *(int *)b);
}

int main(void) {
    // Parse and sort data
    const char *data[] = {"25", "10", "50", "5", "30"};
    int numbers[5];

    // Convert strings to integers
    for (int i = 0; i < 5; i++) {
        numbers[i] = atoi(data[i]);
    }

    // Sort
    qsort(numbers, 5, sizeof(int), compare);

    // Display
    printf("Sorted data:\n");
    for (int i = 0; i < 5; i++) {
        printf("  %d\n", numbers[i]);
    }

    return 0;
}
```

### Example 2: Scientific Computation

```c
int printf(const char *fmt, ...);
extern int rand(void);
extern void srand(unsigned int seed);

double calculate_mean(double *data, int n) {
    double sum = 0.0;
    for (int i = 0; i < n; i++) {
        sum += data[i];
    }
    return sum / n;
}

int main(void) {
    srand(123);

    // Generate random data
    double measurements[100];
    for (int i = 0; i < 100; i++) {
        measurements[i] = (double)rand() / 32767.0 * 100.0;
    }

    // Calculate statistics
    double mean = calculate_mean(measurements, 100);

    printf("Generated 100 measurements\n");
    printf("Mean: %.2f\n", mean);
    printf("First 10: ");
    for (int i = 0; i < 10; i++) {
        printf("%.1f ", measurements[i]);
    }
    printf("\n");

    return 0;
}
```

### Example 3: String Processing

```c
#include "string.h"

int printf(const char *fmt, ...);

void process_command(const char *cmd) {
    if (strcmp(cmd, "start") == 0) {
        printf("Starting...\n");
    } else if (strcmp(cmd, "stop") == 0) {
        printf("Stopping...\n");
    } else if (strstr(cmd, "set") != NULL) {
        printf("Setting parameter\n");
    } else {
        printf("Unknown command\n");
    }
}

int main(void) {
    char buffer[100];

    // Simulate commands
    strcpy(buffer, "start");
    process_command(buffer);

    strcpy(buffer, "set temp 25");
    process_command(buffer);

    strcpy(buffer, "stop");
    process_command(buffer);

    return 0;
}
```

---

## Building Programs with C Library

All C library functions are automatically available. Just include the appropriate headers:

```c
#include "string.h"   // For string functions

int printf(const char *fmt, ...);  // Always available
extern int atoi(const char *str);  // Declare as needed
```

### Build Example

```bash
cd programs
make fibonacci.bin      # Automatically includes printf.c, ftoa.c
make string-test.bin    # Includes string.c
make stdlib-test.bin    # Includes all stdlib functions
```

### Testing Your Program

```bash
# Run with emulator
./bin/riscv_emulator --machine qemu-virt myprogram.bin 80000000

# With PTY for interactive I/O
./bin/riscv_emulator --machine qemu-virt --pty --wait myprogram.bin 80000000
# Then connect with: minicom -D /dev/pts/X
```

---

## Reference Summary

### Available Functions

| Category | Functions | Count |
|----------|-----------|-------|
| Printf | printf (with %d, %u, %x, %s, %c, %f, %e, %g) | 1 |
| String | strlen, strcpy, strncpy, strcmp, strncmp, strcat, strncat | 7 |
| Memory | memcpy, memmove, memset, memcmp | 4 |
| Search | strchr, strrchr, strstr | 3 |
| Convert | atoi, atol, atof | 3 |
| Sort/Search | qsort, bsearch | 2 |
| Random | rand, srand | 2 |
| Malloc | malloc, free, calloc, realloc | 4 |
| I/O | putchar, getchar, puts | 3 |
| **Total** | | **29 functions** |

### Format Specifiers

| Specifier | Type | Example |
|-----------|------|---------|
| %d | Signed int | printf("%d", -42) |
| %u | Unsigned int | printf("%u", 42) |
| %x | Hex int | printf("%x", 0xFF) |
| %s | String | printf("%s", "text") |
| %c | Char | printf("%c", 'A') |
| %f | Float (fixed) | printf("%.2f", 3.14) |
| %e | Float (exp) | printf("%e", 1.23e4) |
| %g | Float (auto) | printf("%g", 0.001) |
| %% | Literal % | printf("100%%") |

---

## Notes and Limitations

### Precision

- Floating-point uses software emulation (accurate but slower than hardware)
- `atof()` has limited precision for very large/small numbers
- Random numbers use simple LCG (not cryptographically secure)

### Memory

- Heap allocation uses simple bump allocator
- `free()` doesn't actually reclaim memory (no fragmentation but no reuse)
- All allocations are 8-byte aligned
- Heap grows from _end symbol upward

### Platform

- All functions are bare-metal (no OS dependencies)
- Thread-safe (single-threaded environment)
- No errno support
- No locale support

---

## time.h - POSIX Time API

`programs/time.h` + `programs/time.c` provide `clock_gettime` and `gettimeofday` backed by the CLINT mtime counter (10 MHz tick rate).

### Clock IDs

| Constant | Value | Description |
|----------|-------|-------------|
| `CLOCK_REALTIME` | 0 | Wall-clock time (same as MONOTONIC in bare-metal) |
| `CLOCK_MONOTONIC` | 1 | Monotonically increasing from boot |
| `CLOCK_PROCESS_CPUTIME_ID` | 2 | Same as MONOTONIC |
| `CLOCK_THREAD_CPUTIME_ID` | 3 | Same as MONOTONIC |

### Functions

```c
#include "time.h"

// Get time into timespec (seconds + nanoseconds)
int clock_gettime(int clk_id, struct timespec *tp);

// Get time into timeval (seconds + microseconds)
int gettimeofday(struct timeval *tv, void *tz);
```

### Example

```c
#include "time.h"

struct timespec t1, t2;
clock_gettime(CLOCK_MONOTONIC, &t1);
// ... work ...
clock_gettime(CLOCK_MONOTONIC, &t2);

long elapsed_ns = (t2.tv_sec - t1.tv_sec) * 1000000000L
                + (t2.tv_nsec - t1.tv_nsec);
```

### Linking

```makefile
$(CC) $(CFLAGS) $(LDFLAGS) -o $@ crt0.S uart.c log.c time.c my-test.c
```

### Notes

- 10 MHz tick -> 100 ns resolution; `tv_nsec` is a multiple of 100
- Uses 32-bit split arithmetic to avoid `__udivdi3` (no `-nostdlib` 64-bit division)
- `mktime`/`gmtime`/`difftime` stubs are also provided

---

## See Also

- `STATUS.md` - Full test inventory with per-test assertion counts
- `programs/printf-float-test.c` - Comprehensive printf examples
- `programs/string-test.c` - String function test cases
- `programs/stdlib-test.c` - Stdlib function examples
- `doc/TESTING.md` - How to run and test programs
