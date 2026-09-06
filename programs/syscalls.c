/* **************************************************************************
 *       RISC-V Emulator - Minimal Newlib Syscall Stubs and C Library
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

// Minimal newlib syscall stubs + C library for bare-metal RISC-V
// Provides: heap allocation (malloc/free), strtol/strtoul, sscanf
// By Ulrik Hørlyk Hjort 2026

#include <stdarg.h>
void putchar(char c);
char getchar(void);

// Heap management
extern char _end;  // Defined by linker script
static char *heap_ptr = 0;

void *_sbrk(int incr) {
    // Initialize heap on first call
    if (heap_ptr == 0) {
        // Align heap to 8-byte boundary
        unsigned long end_addr = (unsigned long)&_end;
        heap_ptr = (char *)((end_addr + 7) & ~7UL);
    }

    char *prev_heap_ptr = heap_ptr;
    heap_ptr += incr;
    return (void *)prev_heap_ptr;
}

// I/O stubs (we use UART directly)
int _write(int file, char *ptr, int len) {
    int i;
    for (i = 0; i < len; i++) {
        putchar(ptr[i]);
    }
    return len;
}

int _read(int file, char *ptr, int len) {
    int i;
    for (i = 0; i < len; i++) {
        ptr[i] = getchar();
        if (ptr[i] == '\r' || ptr[i] == '\n') {
            i++;
            break;
        }
    }
    return i;
}

// File operation stubs (not implemented)
int _close(int file) {
    return -1;
}

int _lseek(int file, int ptr, int dir) {
    return 0;
}

int _fstat(int file, void *st) {
    return 0;
}

int _isatty(int file) {
    return 1;
}

// Exit handler - infinite loop
void _exit(int status) {
    while (1);
}

// Simple integer printing (used by Forth's dot word)
void put_int(int val) {
    char buf[12];  // Enough for 32-bit int plus sign
    int i = 0;
    int is_negative = 0;

    if (val < 0) {
        is_negative = 1;
        val = -val;
    }

    // Build string in reverse
    do {
        buf[i++] = '0' + (val % 10);
        val /= 10;
    } while (val > 0);

    // Add sign
    if (is_negative) {
        buf[i++] = '-';
    }

    // Print in correct order
    while (i > 0) {
        putchar(buf[--i]);
    }
}

// Simple string printing
void put_string(const char *s) {
    while (*s) {
        putchar(*s++);
    }
}

// Simple memory management (bump allocator)
// Note: This implementation does not support free() or realloc() properly

#define ALIGNMENT 8
#define ALIGN(size) (((size) + (ALIGNMENT-1)) & ~(ALIGNMENT-1))

void *malloc(unsigned long size) {
    if (size == 0) return 0;

    size = ALIGN(size);
    void *ptr = _sbrk(size);

    if (ptr == (void *)-1) {
        return 0;  // Out of memory
    }

    return ptr;
}

void *calloc(unsigned long nmemb, unsigned long size) {
    unsigned long total = nmemb * size;
    void *ptr = malloc(total);

    if (ptr) {
        // Zero the memory
        char *p = (char *)ptr;
        for (unsigned long i = 0; i < total; i++) {
            p[i] = 0;
        }
    }

    return ptr;
}

void *realloc(void *ptr, unsigned long size) {
    // Simple implementation: allocate new block and copy
    // This is inefficient but works for a simple allocator

    if (ptr == 0) {
        return malloc(size);
    }

    if (size == 0) {
        // Note: we don't actually free the old block in this simple allocator
        return 0;
    }

    void *new_ptr = malloc(size);
    if (new_ptr == 0) {
        return 0;
    }

    // Copy data (we don't know the old size, so we just copy 'size' bytes)
    // This assumes the new size is not larger than the old size
    char *src = (char *)ptr;
    char *dst = (char *)new_ptr;
    for (unsigned long i = 0; i < size; i++) {
        dst[i] = src[i];
    }

    return new_ptr;
}

void free(void *ptr) {
    // Bump allocator doesn't support free
    // Just ignore it
    (void)ptr;
}

// ============================================================================
// Numeric Conversion Functions
// ============================================================================

// Convert string to integer
int atoi(const char *str) {
    int result = 0;
    int sign = 1;

    // Skip leading whitespace
    while (*str == ' ' || *str == '\t' || *str == '\n') {
        str++;
    }

    // Handle sign
    if (*str == '-') {
        sign = -1;
        str++;
    } else if (*str == '+') {
        str++;
    }

    // Convert digits
    while (*str >= '0' && *str <= '9') {
        result = result * 10 + (*str - '0');
        str++;
    }

    return sign * result;
}

// Convert string to long
long atol(const char *str) {
    long result = 0;
    int sign = 1;

    // Skip leading whitespace
    while (*str == ' ' || *str == '\t' || *str == '\n') {
        str++;
    }

    // Handle sign
    if (*str == '-') {
        sign = -1;
        str++;
    } else if (*str == '+') {
        str++;
    }

    // Convert digits
    while (*str >= '0' && *str <= '9') {
        result = result * 10 + (*str - '0');
        str++;
    }

    return sign * result;
}

// Note: atof() is in atof.c (requires FPU, so it's separate)

// ============================================================================
// Sorting and Searching Functions
// ============================================================================

// Binary search in sorted array
// Returns pointer to matching element, or NULL if not found
void *bsearch(const void *key, const void *base, unsigned long nmemb,
              unsigned long size, int (*compar)(const void *, const void *)) {
    const unsigned char *base_ptr = (const unsigned char *)base;
    unsigned long low = 0;
    unsigned long high = nmemb;

    while (low < high) {
        unsigned long mid = low + (high - low) / 2;
        const void *mid_ptr = base_ptr + mid * size;
        int cmp = compar(key, mid_ptr);

        if (cmp < 0) {
            high = mid;
        } else if (cmp > 0) {
            low = mid + 1;
        } else {
            return (void *)mid_ptr;  // Found
        }
    }

    return (void *)0;  // Not found
}

// Helper function for qsort: swap two elements
static void swap_elements(unsigned char *a, unsigned char *b, unsigned long size) {
    while (size--) {
        unsigned char tmp = *a;
        *a++ = *b;
        *b++ = tmp;
    }
}

// Helper function for qsort: partition array
static unsigned long partition(unsigned char *base, unsigned long low, unsigned long high,
                               unsigned long size, int (*compar)(const void *, const void *)) {
    unsigned char *pivot = base + high * size;
    unsigned long i = low;

    for (unsigned long j = low; j < high; j++) {
        unsigned char *elem = base + j * size;
        if (compar(elem, pivot) < 0) {
            swap_elements(base + i * size, elem, size);
            i++;
        }
    }

    swap_elements(base + i * size, pivot, size);
    return i;
}

// Helper function for qsort: recursive quicksort
static void quicksort(unsigned char *base, unsigned long low, unsigned long high,
                      unsigned long size, int (*compar)(const void *, const void *)) {
    if (low < high) {
        unsigned long pi = partition(base, low, high, size, compar);

        // Recursively sort elements before and after partition
        if (pi > 0) {
            quicksort(base, low, pi - 1, size, compar);
        }
        quicksort(base, pi + 1, high, size, compar);
    }
}

// Sort array using quicksort algorithm
void qsort(void *base, unsigned long nmemb, unsigned long size,
           int (*compar)(const void *, const void *)) {
    if (nmemb <= 1) return;
    quicksort((unsigned char *)base, 0, nmemb - 1, size, compar);
}

// ============================================================================
// Random Number Generator (Linear Congruential Generator)
// ============================================================================

static unsigned long rand_seed = 1;

// Generate pseudo-random number (0 to RAND_MAX)
// Uses simple LCG: X(n+1) = (a * X(n) + c) mod m
// Parameters from POSIX rand_r()
int rand(void) {
    rand_seed = rand_seed * 1103515245 + 12345;
    return (int)((rand_seed >> 16) & 0x7FFF);  // Return 15-bit value
}

// Set random number seed
void srand(unsigned int seed) {
    rand_seed = seed;
}

// RAND_MAX constant (maximum value returned by rand())
#define RAND_MAX 32767

// ============================================================================
// String-to-Number: strtol, strtoul
// ============================================================================

long strtol(const char *str, char **endptr, int base) {
    const char *s = str;
    while (*s == ' ' || *s == '\t' || *s == '\n') s++;

    int neg = 0;
    if (*s == '-') { neg = 1; s++; }
    else if (*s == '+') s++;

    if (base == 0) {
        if (s[0] == '0' && (s[1] == 'x' || s[1] == 'X')) { base = 16; s += 2; }
        else if (s[0] == '0') { base = 8; s++; }
        else base = 10;
    } else if (base == 16 && s[0] == '0' && (s[1] == 'x' || s[1] == 'X')) {
        s += 2;
    }

    long result = 0;
    while (1) {
        int digit;
        char c = *s;
        if (c >= '0' && c <= '9') digit = c - '0';
        else if (c >= 'a' && c <= 'z') digit = c - 'a' + 10;
        else if (c >= 'A' && c <= 'Z') digit = c - 'A' + 10;
        else break;
        if (digit >= base) break;
        result = result * base + digit;
        s++;
    }
    if (endptr) *endptr = (char *)s;
    return neg ? -result : result;
}

unsigned long strtoul(const char *str, char **endptr, int base) {
    const char *s = str;
    while (*s == ' ' || *s == '\t' || *s == '\n') s++;
    if (*s == '+') s++;

    if (base == 0) {
        if (s[0] == '0' && (s[1] == 'x' || s[1] == 'X')) { base = 16; s += 2; }
        else if (s[0] == '0') { base = 8; s++; }
        else base = 10;
    } else if (base == 16 && s[0] == '0' && (s[1] == 'x' || s[1] == 'X')) {
        s += 2;
    }

    unsigned long result = 0;
    while (1) {
        int digit;
        char c = *s;
        if (c >= '0' && c <= '9') digit = c - '0';
        else if (c >= 'a' && c <= 'z') digit = c - 'a' + 10;
        else if (c >= 'A' && c <= 'Z') digit = c - 'A' + 10;
        else break;
        if (digit >= base) break;
        result = result * base + digit;
        s++;
    }
    if (endptr) *endptr = (char *)s;
    return result;
}

// ============================================================================
// sscanf -- basic: %d %i %u %x %X %s %c, whitespace matching, literal chars
// ============================================================================

int sscanf(const char *str, const char *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    const char *s = str;
    int count = 0;

    while (*fmt) {
        if (*fmt == ' ' || *fmt == '\t' || *fmt == '\n') {
            while (*s == ' ' || *s == '\t' || *s == '\n') s++;
            fmt++;
            continue;
        }
        if (*fmt != '%') {
            if (*s != *fmt) break;
            s++; fmt++;
            continue;
        }
        fmt++; /* skip '%' */

        /* optional width (parsed but not fully enforced for simplicity) */
        int width = 0;
        while (*fmt >= '0' && *fmt <= '9') { width = width * 10 + (*fmt++ - '0'); }
        (void)width;

        char spec = *fmt++;

        /* skip leading whitespace for all but %c */
        if (spec != 'c') {
            while (*s == ' ' || *s == '\t' || *s == '\n') s++;
        }

        switch (spec) {
        case 'd': {
            char *end;
            long val = strtol(s, &end, 10);
            if (end == s) goto done;
            *va_arg(args, int *) = (int)val;
            s = end; count++;
            break;
        }
        case 'i': {
            char *end;
            long val = strtol(s, &end, 0); /* auto-detect base */
            if (end == s) goto done;
            *va_arg(args, int *) = (int)val;
            s = end; count++;
            break;
        }
        case 'u': {
            char *end;
            unsigned long val = strtoul(s, &end, 10);
            if (end == s) goto done;
            *va_arg(args, unsigned int *) = (unsigned int)val;
            s = end; count++;
            break;
        }
        case 'x': case 'X': {
            char *end;
            unsigned long val = strtoul(s, &end, 16);
            if (end == s) goto done;
            *va_arg(args, unsigned int *) = (unsigned int)val;
            s = end; count++;
            break;
        }
        case 's': {
            char *out = va_arg(args, char *);
            int n = 0;
            while (*s && *s != ' ' && *s != '\t' && *s != '\n') out[n++] = *s++;
            if (n == 0) goto done;
            out[n] = '\0';
            count++;
            break;
        }
        case 'c': {
            if (!*s) goto done;
            *va_arg(args, char *) = *s++;
            count++;
            break;
        }
        case '%':
            if (*s == '%') s++; else goto done;
            break;
        default:
            goto done;
        }
    }
done:
    va_end(args);
    return count;
}
