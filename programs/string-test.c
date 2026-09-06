/* **************************************************************************
 *              RISC-V Emulator - String library test program
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

// String library test program
// Tests all functions in string.h/string.c
// By Ulrik Hørlyk Hjort 2026

#include "string.h"

int printf(const char *fmt, ...);

// Test result tracking
static int tests_run = 0;
static int tests_passed = 0;
static int tests_failed = 0;

#define TEST(name) \
    do { \
        tests_run++; \
        printf("  %s... ", name); \
    } while(0)

#define PASS() \
    do { \
        printf("PASS\n"); \
        tests_passed++; \
    } while(0)

#define FAIL(msg) \
    do { \
        printf("FAIL: %s\n", msg); \
        tests_failed++; \
    } while(0)

#define ASSERT(cond, msg) \
    do { \
        if (cond) { \
            PASS(); \
        } else { \
            FAIL(msg); \
        } \
    } while(0)

void test_strlen(void) {
    printf("\n=== strlen Tests ===\n");

    TEST("Empty string");
    ASSERT(strlen("") == 0, "expected 0");

    TEST("Single char");
    ASSERT(strlen("a") == 1, "expected 1");

    TEST("Normal string");
    ASSERT(strlen("Hello") == 5, "expected 5");

    TEST("Long string");
    ASSERT(strlen("The quick brown fox jumps over the lazy dog") == 43, "expected 43");
}

void test_strcpy(void) {
    printf("\n=== strcpy Tests ===\n");
    char buf[50];

    TEST("Copy empty string");
    strcpy(buf, "");
    ASSERT(strlen(buf) == 0, "expected empty");

    TEST("Copy simple string");
    strcpy(buf, "Hello");
    ASSERT(strcmp(buf, "Hello") == 0, "expected Hello");

    TEST("Copy overwrites");
    strcpy(buf, "Hi");
    ASSERT(strcmp(buf, "Hi") == 0, "expected Hi");
}

void test_strncpy(void) {
    printf("\n=== strncpy Tests ===\n");
    char buf[10];

    TEST("Copy full string");
    memset(buf, 'X', sizeof(buf));
    strncpy(buf, "Hello", 10);
    ASSERT(strcmp(buf, "Hello") == 0, "expected Hello");

    TEST("Copy partial string");
    memset(buf, 'X', sizeof(buf));
    strncpy(buf, "Hello", 3);
    buf[3] = '\0';
    ASSERT(strcmp(buf, "Hel") == 0, "expected Hel");

    TEST("Padding with nulls");
    memset(buf, 'X', sizeof(buf));
    strncpy(buf, "Hi", 5);
    ASSERT(buf[0] == 'H' && buf[1] == 'i' && buf[2] == '\0' && buf[3] == '\0', "expected padding");
}

void test_strcmp(void) {
    printf("\n=== strcmp Tests ===\n");

    TEST("Equal strings");
    ASSERT(strcmp("Hello", "Hello") == 0, "expected equal");

    TEST("Different strings (<)");
    ASSERT(strcmp("ABC", "XYZ") < 0, "expected ABC < XYZ");

    TEST("Different strings (>)");
    ASSERT(strcmp("XYZ", "ABC") > 0, "expected XYZ > ABC");

    TEST("Prefix match");
    ASSERT(strcmp("Hello", "Hello World") < 0, "expected shorter < longer");

    TEST("Empty strings");
    ASSERT(strcmp("", "") == 0, "expected equal");
}

void test_strncmp(void) {
    printf("\n=== strncmp Tests ===\n");

    TEST("Equal (full)");
    ASSERT(strncmp("Hello", "Hello", 5) == 0, "expected equal");

    TEST("Equal (partial)");
    ASSERT(strncmp("Hello", "Help", 3) == 0, "expected first 3 equal");

    TEST("Different (partial)");
    ASSERT(strncmp("Hello", "Help", 4) != 0, "expected different at 4");

    TEST("Zero length");
    ASSERT(strncmp("ABC", "XYZ", 0) == 0, "expected equal with n=0");
}

void test_strcat(void) {
    printf("\n=== strcat Tests ===\n");
    char buf[50];

    TEST("Concatenate to empty");
    buf[0] = '\0';
    strcat(buf, "Hello");
    ASSERT(strcmp(buf, "Hello") == 0, "expected Hello");

    TEST("Concatenate strings");
    strcpy(buf, "Hello");
    strcat(buf, " World");
    ASSERT(strcmp(buf, "Hello World") == 0, "expected Hello World");

    TEST("Multiple concatenations");
    strcpy(buf, "A");
    strcat(buf, "B");
    strcat(buf, "C");
    ASSERT(strcmp(buf, "ABC") == 0, "expected ABC");
}

void test_strncat(void) {
    printf("\n=== strncat Tests ===\n");
    char buf[50];

    TEST("Concatenate with limit");
    strcpy(buf, "Hello");
    strncat(buf, " World!", 3);
    ASSERT(strcmp(buf, "Hello Wo") == 0, "expected Hello Wo");

    TEST("Limit exceeds source");
    strcpy(buf, "Hi");
    strncat(buf, " there", 100);
    ASSERT(strcmp(buf, "Hi there") == 0, "expected Hi there");
}

void test_memcpy(void) {
    printf("\n=== memcpy Tests ===\n");
    char buf[20];
    const char *src = "Hello World";

    TEST("Copy bytes");
    memcpy(buf, src, 5);
    buf[5] = '\0';
    ASSERT(strcmp(buf, "Hello") == 0, "expected Hello");

    TEST("Copy full string");
    memcpy(buf, src, 12);
    ASSERT(strcmp(buf, "Hello World") == 0, "expected Hello World");

    TEST("Copy integers");
    int nums[] = {1, 2, 3, 4, 5};
    int dest[5];
    memcpy(dest, nums, sizeof(nums));
    ASSERT(dest[0] == 1 && dest[4] == 5, "expected correct copy");
}

void test_memmove(void) {
    printf("\n=== memmove Tests ===\n");
    char buf[20];

    TEST("Non-overlapping");
    strcpy(buf, "Hello World");
    memmove(buf, buf + 6, 5);
    buf[5] = '\0';
    ASSERT(strcmp(buf, "World") == 0, "expected World");

    TEST("Overlapping forward");
    strcpy(buf, "ABCDEFGH");
    memmove(buf + 2, buf, 5);
    buf[7] = '\0';
    ASSERT(strcmp(buf, "ABABCDE") == 0, "expected ABABCDE");

    TEST("Overlapping backward");
    strcpy(buf, "ABCDEFGH");
    memmove(buf, buf + 2, 5);
    buf[5] = '\0';
    ASSERT(strcmp(buf, "CDEFG") == 0, "expected CDEFG");
}

void test_memset(void) {
    printf("\n=== memset Tests ===\n");
    char buf[20];

    TEST("Set to zero");
    memset(buf, 0, 10);
    int all_zero = 1;
    for (int i = 0; i < 10; i++) {
        if (buf[i] != 0) all_zero = 0;
    }
    ASSERT(all_zero, "expected all zeros");

    TEST("Set to character");
    memset(buf, 'A', 5);
    buf[5] = '\0';
    ASSERT(strcmp(buf, "AAAAA") == 0, "expected AAAAA");

    TEST("Set to pattern");
    memset(buf, 0x42, 4);
    ASSERT(buf[0] == 0x42 && buf[3] == 0x42, "expected 0x42");
}

void test_memcmp(void) {
    printf("\n=== memcmp Tests ===\n");
    char a[] = "Hello";
    char b[] = "Hello";
    char c[] = "World";

    TEST("Equal arrays");
    ASSERT(memcmp(a, b, 5) == 0, "expected equal");

    TEST("Different arrays");
    ASSERT(memcmp(a, c, 5) != 0, "expected different");

    TEST("Partial compare (equal)");
    ASSERT(memcmp("Hello World", "Hello There", 5) == 0, "expected first 5 equal");

    TEST("Binary data");
    unsigned char d1[] = {0x01, 0x02, 0x03};
    unsigned char d2[] = {0x01, 0x02, 0x03};
    ASSERT(memcmp(d1, d2, 3) == 0, "expected equal binary");
}

void test_strchr(void) {
    printf("\n=== strchr Tests ===\n");
    const char *str = "Hello World";

    TEST("Find existing char");
    ASSERT(strchr(str, 'W') == str + 6, "expected position 6");

    TEST("Find first occurrence");
    ASSERT(strchr(str, 'l') == str + 2, "expected position 2");

    TEST("Find non-existent char");
    ASSERT(strchr(str, 'X') == (char *)0, "expected NULL");

    TEST("Find null terminator");
    ASSERT(strchr(str, '\0') == str + 11, "expected end of string");
}

void test_strrchr(void) {
    printf("\n=== strrchr Tests ===\n");
    const char *str = "Hello World";

    TEST("Find last occurrence");
    ASSERT(strrchr(str, 'l') == str + 9, "expected position 9");

    TEST("Find single occurrence");
    ASSERT(strrchr(str, 'W') == str + 6, "expected position 6");

    TEST("Find non-existent char");
    ASSERT(strrchr(str, 'X') == (char *)0, "expected NULL");

    TEST("Find null terminator");
    ASSERT(strrchr(str, '\0') == str + 11, "expected end of string");
}

void test_strstr(void) {
    printf("\n=== strstr Tests ===\n");
    const char *str = "Hello World Hello";

    TEST("Find substring");
    ASSERT(strstr(str, "World") == str + 6, "expected position 6");

    TEST("Find first occurrence");
    ASSERT(strstr(str, "Hello") == str, "expected position 0");

    TEST("Find non-existent");
    ASSERT(strstr(str, "Goodbye") == (char *)0, "expected NULL");

    TEST("Find empty string");
    ASSERT(strstr(str, "") == str, "expected position 0");

    TEST("Find at end");
    ASSERT(strstr("ABC", "C") == "ABC" + 2, "expected position 2");
}

int main(void) {
    printf("\n======================================\n");
    printf("   String Library Tests\n");
    printf("======================================\n");

    test_strlen();
    test_strcpy();
    test_strncpy();
    test_strcmp();
    test_strncmp();
    test_strcat();
    test_strncat();
    test_memcpy();
    test_memmove();
    test_memset();
    test_memcmp();
    test_strchr();
    test_strrchr();
    test_strstr();

    printf("\n======================================\n");
    printf("Test Summary\n");
    printf("======================================\n");
    printf("Total:  %d\n", tests_run);
    printf("Passed: %d\n", tests_passed);
    printf("Failed: %d\n", tests_failed);
    printf("\n");

    if (tests_failed == 0) {
        printf("SUCCESS: All string tests passed!\n\n");
        return 0;
    } else {
        printf("FAILURE: %d test(s) failed!\n\n", tests_failed);
        return 1;
    }
}
