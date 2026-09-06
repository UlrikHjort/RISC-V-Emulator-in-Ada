/* **************************************************************************
 * RISC-V Emulator - Standard string.h implementation for bare-metal RISC-V
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

// Standard string.h implementation for bare-metal RISC-V
// By Ulrik Hørlyk Hjort 2026

#include "string.h"

// ============================================================================
// Basic String Functions
// ============================================================================

// Return length of string (excluding null terminator)
size_t strlen(const char *s) {
    size_t len = 0;
    while (*s++) {
        len++;
    }
    return len;
}

// Copy string from src to dst (including null terminator)
// Returns dst
char *strcpy(char *dst, const char *src) {
    char *orig_dst = dst;
    while ((*dst++ = *src++));
    return orig_dst;
}

// Copy at most n bytes from src to dst
// If src is shorter than n, pad with null bytes
// Returns dst
char *strncpy(char *dst, const char *src, size_t n) {
    char *orig_dst = dst;
    size_t i;

    // Copy bytes from src
    for (i = 0; i < n && src[i] != '\0'; i++) {
        dst[i] = src[i];
    }

    // Pad with null bytes if src is shorter than n
    for (; i < n; i++) {
        dst[i] = '\0';
    }

    return orig_dst;
}

// Compare two strings
// Returns: <0 if s1 < s2, 0 if equal, >0 if s1 > s2
int strcmp(const char *s1, const char *s2) {
    while (*s1 && (*s1 == *s2)) {
        s1++;
        s2++;
    }
    return *(unsigned char *)s1 - *(unsigned char *)s2;
}

// Compare at most n bytes of two strings
int strncmp(const char *s1, const char *s2, size_t n) {
    if (n == 0) return 0;

    while (n > 0 && *s1 && (*s1 == *s2)) {
        s1++;
        s2++;
        n--;
    }

    if (n == 0) return 0;
    return *(unsigned char *)s1 - *(unsigned char *)s2;
}

// Concatenate src to end of dst
// Returns dst
char *strcat(char *dst, const char *src) {
    char *orig_dst = dst;

    // Find end of dst
    while (*dst) {
        dst++;
    }

    // Copy src to end of dst
    while ((*dst++ = *src++));

    return orig_dst;
}

// Concatenate at most n bytes of src to dst
// Returns dst
char *strncat(char *dst, const char *src, size_t n) {
    char *orig_dst = dst;

    // Find end of dst
    while (*dst) {
        dst++;
    }

    // Copy at most n bytes from src
    size_t i;
    for (i = 0; i < n && src[i] != '\0'; i++) {
        dst[i] = src[i];
    }
    dst[i] = '\0';

    return orig_dst;
}

// ============================================================================
// Memory Functions
// ============================================================================

// Copy n bytes from src to dst (non-overlapping regions)
// Returns dst
void *memcpy(void *dst, const void *src, size_t n) {
    unsigned char *d = (unsigned char *)dst;
    const unsigned char *s = (const unsigned char *)src;

    while (n--) {
        *d++ = *s++;
    }

    return dst;
}

// Copy n bytes from src to dst (handles overlapping regions)
// Returns dst
void *memmove(void *dst, const void *src, size_t n) {
    unsigned char *d = (unsigned char *)dst;
    const unsigned char *s = (const unsigned char *)src;

    if (d < s) {
        // Copy forward
        while (n--) {
            *d++ = *s++;
        }
    } else if (d > s) {
        // Copy backward to handle overlap
        d += n;
        s += n;
        while (n--) {
            *--d = *--s;
        }
    }

    return dst;
}

// Set n bytes of s to value c
// Returns s
void *memset(void *s, int c, size_t n) {
    unsigned char *p = (unsigned char *)s;
    unsigned char value = (unsigned char)c;

    while (n--) {
        *p++ = value;
    }

    return s;
}

// Compare n bytes of s1 and s2
// Returns: <0 if s1 < s2, 0 if equal, >0 if s1 > s2
int memcmp(const void *s1, const void *s2, size_t n) {
    const unsigned char *p1 = (const unsigned char *)s1;
    const unsigned char *p2 = (const unsigned char *)s2;

    while (n--) {
        if (*p1 != *p2) {
            return *p1 - *p2;
        }
        p1++;
        p2++;
    }

    return 0;
}

// ============================================================================
// Search Functions
// ============================================================================

// Find first occurrence of character c in string s
// Returns pointer to character, or NULL if not found
char *strchr(const char *s, int c) {
    while (*s) {
        if (*s == (char)c) {
            return (char *)s;
        }
        s++;
    }

    // Check if c is null terminator
    if ((char)c == '\0') {
        return (char *)s;
    }

    return (char *)0;  // NULL
}

// Find last occurrence of character c in string s
// Returns pointer to character, or NULL if not found
char *strrchr(const char *s, int c) {
    const char *last = (char *)0;  // NULL

    while (*s) {
        if (*s == (char)c) {
            last = s;
        }
        s++;
    }

    // Check if c is null terminator
    if ((char)c == '\0') {
        return (char *)s;
    }

    return (char *)last;
}

// Find first occurrence of substring needle in string haystack
// Returns pointer to first character of substring, or NULL if not found
char *strstr(const char *haystack, const char *needle) {
    // Empty needle matches at beginning
    if (!*needle) {
        return (char *)haystack;
    }

    // Search for needle in haystack
    while (*haystack) {
        const char *h = haystack;
        const char *n = needle;

        // Try to match needle starting at current position
        while (*h && *n && (*h == *n)) {
            h++;
            n++;
        }

        // If we reached end of needle, we found a match
        if (!*n) {
            return (char *)haystack;
        }

        haystack++;
    }

    return (char *)0;  // NULL
}

// ============================================================================
// Advanced String Parsing Functions
// ============================================================================

// Static variable for strtok to maintain state between calls
static char *strtok_saveptr = (char *)0;

// Extract tokens from string
// First call: strtok(str, delim) where str is the string to tokenize
// Subsequent calls: strtok(NULL, delim) to get next token
// Returns NULL when no more tokens
char *strtok(char *str, const char *delim) {
    // Use saved pointer if str is NULL
    if (str == (char *)0) {
        str = strtok_saveptr;
    }

    // If no string, return NULL
    if (str == (char *)0) {
        return (char *)0;
    }

    // Skip leading delimiters
    while (*str != '\0') {
        const char *d = delim;
        int is_delim = 0;

        while (*d != '\0') {
            if (*str == *d) {
                is_delim = 1;
                break;
            }
            d++;
        }

        if (!is_delim) {
            break;  // Found start of token
        }
        str++;
    }

    // If we reached end of string, no token
    if (*str == '\0') {
        strtok_saveptr = (char *)0;
        return (char *)0;
    }

    // Start of token
    char *token = str;

    // Find end of token
    while (*str != '\0') {
        const char *d = delim;

        while (*d != '\0') {
            if (*str == *d) {
                // Found delimiter, terminate token and save position
                *str = '\0';
                strtok_saveptr = str + 1;
                return token;
            }
            d++;
        }
        str++;
    }

    // Reached end of string, this is the last token
    strtok_saveptr = (char *)0;
    return token;
}

// Find first occurrence of any character from accept in s
char *strpbrk(const char *s, const char *accept) {
    if (s == (const char *)0 || accept == (const char *)0) {
        return (char *)0;
    }

    while (*s != '\0') {
        const char *a = accept;

        while (*a != '\0') {
            if (*s == *a) {
                return (char *)s;  // Found match
            }
            a++;
        }
        s++;
    }

    return (char *)0;  // No match found
}

// Get length of prefix substring consisting only of characters in accept
size_t strspn(const char *s, const char *accept) {
    if (s == (const char *)0 || accept == (const char *)0) {
        return 0;
    }

    size_t count = 0;

    while (*s != '\0') {
        const char *a = accept;
        int found = 0;

        while (*a != '\0') {
            if (*s == *a) {
                found = 1;
                break;
            }
            a++;
        }

        if (!found) {
            break;  // Character not in accept set
        }

        count++;
        s++;
    }

    return count;
}

// Get length of prefix substring consisting only of characters NOT in reject
size_t strcspn(const char *s, const char *reject) {
    if (s == (const char *)0 || reject == (const char *)0) {
        return 0;
    }

    size_t count = 0;

    while (*s != '\0') {
        const char *r = reject;

        while (*r != '\0') {
            if (*s == *r) {
                return count;  // Found character in reject set
            }
            r++;
        }

        count++;
        s++;
    }

    return count;
}

// Duplicate string (allocates memory with malloc)
// Note: Requires malloc() from syscalls.c
char *strdup(const char *s) {
    if (s == (const char *)0) {
        return (char *)0;
    }

    size_t len = strlen(s) + 1;  // +1 for null terminator

    // Declare malloc with proper signature
    extern void *malloc(unsigned long size);

    char *dup = (char *)malloc(len);
    if (dup == (char *)0) {
        return (char *)0;  // Allocation failed
    }

    // Copy string
    char *dest = dup;
    while (*s != '\0') {
        *dest++ = *s++;
    }
    *dest = '\0';

    return dup;
}
