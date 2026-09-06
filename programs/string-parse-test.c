/* **************************************************************************
 *   RISC-V Emulator - Test program for advanced string parsing functions
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

// Test program for advanced string parsing functions
// Tests strtok, strpbrk, strspn, strcspn, strdup
// By Ulrik Hørlyk Hjort 2026

#include "uart.h"
#include "printf.h"
#include "string.h"

// Test counter
static int tests_run = 0;
static int tests_passed = 0;
static int tests_failed = 0;

// Test macro
#define TEST(name, condition) do { \
    tests_run++; \
    if (condition) { \
        tests_passed++; \
        printf("  PASS: %s\n", name); \
    } else { \
        tests_failed++; \
        printf("  FAIL: %s\n", name); \
    } \
} while(0)

void test_strtok(void) {
    printf("\n=== Testing strtok() ===\n");

    // Test 1: Basic tokenization with space delimiter
    char str1[] = "Hello world from RISC-V";
    char *token;

    token = strtok(str1, " ");
    TEST("strtok first token", token != 0 && strcmp(token, "Hello") == 0);

    token = strtok(0, " ");
    TEST("strtok second token", token != 0 && strcmp(token, "world") == 0);

    token = strtok(0, " ");
    TEST("strtok third token", token != 0 && strcmp(token, "from") == 0);

    token = strtok(0, " ");
    TEST("strtok fourth token", token != 0 && strcmp(token, "RISC-V") == 0);

    token = strtok(0, " ");
    TEST("strtok no more tokens", token == 0);

    // Test 2: Multiple delimiters
    char str2[] = "one,two;three:four";
    token = strtok(str2, ",;:");
    TEST("strtok multi-delim 1st", token != 0 && strcmp(token, "one") == 0);

    token = strtok(0, ",;:");
    TEST("strtok multi-delim 2nd", token != 0 && strcmp(token, "two") == 0);

    token = strtok(0, ",;:");
    TEST("strtok multi-delim 3rd", token != 0 && strcmp(token, "three") == 0);

    token = strtok(0, ",;:");
    TEST("strtok multi-delim 4th", token != 0 && strcmp(token, "four") == 0);

    // Test 3: Leading/trailing delimiters
    char str3[] = "  leading and trailing  ";
    token = strtok(str3, " ");
    TEST("strtok skips leading", token != 0 && strcmp(token, "leading") == 0);

    token = strtok(0, " ");
    TEST("strtok middle token", token != 0 && strcmp(token, "and") == 0);

    token = strtok(0, " ");
    TEST("strtok before trailing", token != 0 && strcmp(token, "trailing") == 0);

    // Test 4: Empty string
    char str4[] = "";
    token = strtok(str4, " ");
    TEST("strtok empty string", token == 0);

    // Test 5: Only delimiters
    char str5[] = "   ";
    token = strtok(str5, " ");
    TEST("strtok only delimiters", token == 0);
}

void test_strpbrk(void) {
    printf("\n=== Testing strpbrk() ===\n");

    const char *str = "Hello, World!";

    // Test 1: Find comma
    char *result = strpbrk(str, ",");
    TEST("strpbrk finds comma", result != 0 && *result == ',');

    // Test 2: Find any vowel
    result = strpbrk(str, "aeiou");
    TEST("strpbrk finds first vowel", result != 0 && *result == 'e');

    // Test 3: Find punctuation
    result = strpbrk(str, "!?.");
    TEST("strpbrk finds exclamation", result != 0 && *result == '!');

    // Test 4: No match
    result = strpbrk(str, "xyz");
    TEST("strpbrk no match", result == 0);

    // Test 5: Find uppercase
    result = strpbrk(str, "ABCDEFGHIJKLMNOPQRSTUVWXYZ");
    TEST("strpbrk finds uppercase", result != 0 && *result == 'H');

    // Test 6: Empty accept string
    result = strpbrk(str, "");
    TEST("strpbrk empty accept", result == 0);

    // Test 7: Multiple characters in accept
    result = strpbrk("test123", "0123456789");
    TEST("strpbrk finds digit", result != 0 && *result == '1');
}

void test_strspn(void) {
    printf("\n=== Testing strspn() ===\n");

    // Test 1: Count leading digits
    const char *str1 = "123abc";
    size_t len = strspn(str1, "0123456789");
    TEST("strspn counts digits", len == 3);

    // Test 2: Count leading whitespace
    const char *str2 = "   hello";
    len = strspn(str2, " \t\n");
    TEST("strspn counts whitespace", len == 3);

    // Test 3: No matching characters
    const char *str3 = "hello";
    len = strspn(str3, "xyz");
    TEST("strspn no match", len == 0);

    // Test 4: All characters match
    const char *str4 = "aaabbbccc";
    len = strspn(str4, "abc");
    TEST("strspn all match", len == 9);

    // Test 5: Leading lowercase letters
    const char *str5 = "helloWORLD";
    len = strspn(str5, "abcdefghijklmnopqrstuvwxyz");
    TEST("strspn lowercase", len == 5);

    // Test 6: Empty string
    const char *str6 = "";
    len = strspn(str6, "abc");
    TEST("strspn empty string", len == 0);

    // Test 7: Hex digits
    const char *str7 = "1A2Fghi";
    len = strspn(str7, "0123456789ABCDEFabcdef");
    TEST("strspn hex digits", len == 4);
}

void test_strcspn(void) {
    printf("\n=== Testing strcspn() ===\n");

    // Test 1: Find first non-digit
    const char *str1 = "123abc";
    size_t len = strcspn(str1, "abcdefghijklmnopqrstuvwxyz");
    TEST("strcspn to first letter", len == 3);

    // Test 2: Find first whitespace
    const char *str2 = "hello world";
    len = strcspn(str2, " \t\n");
    TEST("strcspn to whitespace", len == 5);

    // Test 3: No matching reject characters
    const char *str3 = "hello";
    len = strcspn(str3, "xyz");
    TEST("strcspn no reject match", len == 5);

    // Test 4: First character matches reject
    const char *str4 = "hello";
    len = strcspn(str4, "h");
    TEST("strcspn immediate match", len == 0);

    // Test 5: Find punctuation
    const char *str5 = "hello, world";
    len = strcspn(str5, ",.!?");
    TEST("strcspn to punctuation", len == 5);

    // Test 6: Empty reject string
    const char *str6 = "test";
    len = strcspn(str6, "");
    TEST("strcspn empty reject", len == 4);

    // Test 7: Find end of line
    const char *str7 = "line one\nline two";
    len = strcspn(str7, "\n\r");
    TEST("strcspn to newline", len == 8);
}

void test_strdup(void) {
    printf("\n=== Testing strdup() ===\n");

    // Test 1: Duplicate simple string
    const char *original = "Hello";
    char *copy = strdup(original);

    TEST("strdup returns non-null", copy != 0);
    TEST("strdup copies correctly", copy != 0 && strcmp(copy, original) == 0);
    TEST("strdup creates different pointer", copy != original);

    // Modify copy to verify it's independent
    if (copy != 0) {
        copy[0] = 'h';
        TEST("strdup creates independent copy",
             copy[0] == 'h' && original[0] == 'H');
    }

    // Test 2: Duplicate empty string
    const char *empty = "";
    char *empty_copy = strdup(empty);
    TEST("strdup empty string", empty_copy != 0 && strcmp(empty_copy, "") == 0);

    // Test 3: Duplicate long string
    const char *long_str = "This is a longer string for testing";
    char *long_copy = strdup(long_str);
    TEST("strdup long string", long_copy != 0 && strcmp(long_copy, long_str) == 0);
}

void test_combined_usage(void) {
    printf("\n=== Testing Combined Usage ===\n");

    // Example: Parse CSV line
    char csv[] = "name,age,city";
    char *token = strtok(csv, ",");
    int field_count = 0;

    while (token != 0) {
        field_count++;
        token = strtok(0, ",");
    }
    TEST("CSV parsing counts fields", field_count == 3);

    // Example: Validate identifier (letters and underscores)
    const char *identifier = "valid_name_123";
    size_t valid_len = strspn(identifier, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_");
    TEST("Identifier validation", valid_len == strlen(identifier));

    const char *invalid = "invalid name!";
    size_t invalid_len = strspn(invalid, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_");
    TEST("Invalid identifier detected", invalid_len < strlen(invalid));

    // Example: Find filename in path
    const char *path = "/usr/local/bin/program";
    char *slash = strrchr(path, '/');
    TEST("Path parsing finds last slash", slash != 0);
    if (slash) {
        TEST("Path parsing extracts filename", strcmp(slash + 1, "program") == 0);
    }

    // Example: Trim whitespace
    const char *text = "   trimmed   ";
    size_t leading = strspn(text, " \t");
    const char *trimmed_start = text + leading;

    // Find end of non-whitespace
    size_t content_len = strcspn(trimmed_start, " \t");
    TEST("Whitespace trimming", content_len == 7);  // "trimmed" length
}

int main(void) {
    uart_init();

    printf("\n");
    printf("========================================\n");
    printf("  String Parsing Functions Test Suite\n");
    printf("========================================\n");

    test_strtok();
    test_strpbrk();
    test_strspn();
    test_strcspn();
    test_strdup();
    test_combined_usage();

    printf("\n");
    printf("========================================\n");
    printf("  Test Summary\n");
    printf("========================================\n");
    printf("Total tests run:    %d\n", tests_run);
    printf("Tests passed:       %d\n", tests_passed);
    printf("Tests failed:       %d\n", tests_failed);
    printf("\n");

    if (tests_failed == 0) {
        printf("SUCCESS: All tests passed!\n");
    } else {
        printf("FAILURE: %d test(s) failed\n", tests_failed);
    }

    printf("========================================\n");
    printf("\n");

    return tests_failed == 0 ? 0 : 1;
}
