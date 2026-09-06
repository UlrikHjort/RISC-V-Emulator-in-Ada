/* **************************************************************************
 *           RISC-V Emulator - Automated regression test program
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

// Automated regression test program
// Tests: basic arithmetic, memory alignment, FPU, C library functions
// Returns 0 on success, 1 on failure
// By Ulrik Hørlyk Hjort 2026

int printf(const char *fmt, ...);
void putchar(char c);
void *malloc(unsigned long size);
void free(void *ptr);

// Test result tracking
static int tests_run = 0;
static int tests_passed = 0;
static int tests_failed = 0;

// Test macros
#define TEST(name) \
    do { \
        tests_run++; \
        printf("  Test: %s... ", name); \
    } while(0)

#define ASSERT(cond) \
    do { \
        if (cond) { \
            printf("PASS\n"); \
            tests_passed++; \
        } else { \
            printf("FAIL (line %d)\n", __LINE__); \
            tests_failed++; \
        } \
    } while(0)

#define ASSERT_EQ(a, b) \
    do { \
        if ((a) == (b)) { \
            printf("PASS\n"); \
            tests_passed++; \
        } else { \
            printf("FAIL (expected %d, got %d)\n", (int)(b), (int)(a)); \
            tests_failed++; \
        } \
    } while(0)

#define SECTION(name) \
    printf("\n=== %s ===\n", name)

// ============================================================================
// Arithmetic Tests
// ============================================================================

void test_arithmetic(void) {
    SECTION("Basic Arithmetic");

    TEST("Addition");
    ASSERT_EQ(5 + 3, 8);

    TEST("Subtraction");
    ASSERT_EQ(10 - 7, 3);

    TEST("Multiplication");
    ASSERT_EQ(6 * 7, 42);

    TEST("Division");
    ASSERT_EQ(100 / 4, 25);

    TEST("Modulo");
    ASSERT_EQ(17 % 5, 2);

    TEST("Negative numbers");
    ASSERT_EQ(-5 + 3, -2);

    TEST("Overflow wrap");
    unsigned int max = 0xFFFFFFFF;
    ASSERT_EQ(max + 1, 0);
}

// ============================================================================
// Bitwise Tests
// ============================================================================

void test_bitwise(void) {
    SECTION("Bitwise Operations");

    TEST("AND");
    ASSERT_EQ(0b1100 & 0b1010, 0b1000);

    TEST("OR");
    ASSERT_EQ(0b1100 | 0b1010, 0b1110);

    TEST("XOR");
    ASSERT_EQ(0b1100 ^ 0b1010, 0b0110);

    TEST("NOT");
    ASSERT_EQ(~0, -1);

    TEST("Left shift");
    ASSERT_EQ(1 << 10, 1024);

    TEST("Right shift");
    ASSERT_EQ(1024 >> 2, 256);

    TEST("Arithmetic right shift (signed)");
    int neg = -8;
    ASSERT_EQ(neg >> 1, -4);
}

// ============================================================================
// Memory Alignment Tests
// ============================================================================

void test_memory_alignment(void) {
    SECTION("Memory Alignment");

    // Test word-aligned access
    volatile unsigned int word_array[4] = {0x12345678, 0xAABBCCDD, 0x11223344, 0xDEADBEEF};

    TEST("Word load (aligned)");
    ASSERT_EQ(word_array[0], 0x12345678);

    TEST("Word load (offset)");
    ASSERT_EQ(word_array[2], 0x11223344);

    TEST("Word store (aligned)");
    word_array[1] = 0xCAFEBABE;
    ASSERT_EQ(word_array[1], 0xCAFEBABE);

    // Test halfword access
    volatile unsigned short half_array[4] = {0x1234, 0x5678, 0xABCD, 0xEF01};

    TEST("Halfword load");
    ASSERT_EQ(half_array[2], 0xABCD);

    TEST("Halfword store");
    half_array[0] = 0x9999;
    ASSERT_EQ(half_array[0], 0x9999);

    // Test byte access
    volatile unsigned char byte_array[8] = {1, 2, 3, 4, 5, 6, 7, 8};

    TEST("Byte load");
    ASSERT_EQ(byte_array[5], 6);

    TEST("Byte store");
    byte_array[3] = 42;
    ASSERT_EQ(byte_array[3], 42);

    // Test unaligned access (via byte array viewed as words)
    TEST("Unaligned word access");
    unsigned char data[8] = {0x78, 0x56, 0x34, 0x12, 0xDD, 0xCC, 0xBB, 0xAA};
    unsigned int *ptr = (unsigned int *)data;
    // On little-endian RISC-V: first word should be 0x12345678
    ASSERT_EQ(*ptr, 0x12345678);
}

// ============================================================================
// Control Flow Tests
// ============================================================================

void test_control_flow(void) {
    SECTION("Control Flow");

    TEST("If statement (true)");
    int x = 0;
    if (1) x = 5;
    ASSERT_EQ(x, 5);

    TEST("If statement (false)");
    x = 0;
    if (0) x = 5;
    ASSERT_EQ(x, 0);

    TEST("If-else (true branch)");
    x = (10 > 5) ? 1 : 2;
    ASSERT_EQ(x, 1);

    TEST("If-else (false branch)");
    x = (3 > 5) ? 1 : 2;
    ASSERT_EQ(x, 2);

    TEST("For loop");
    int sum = 0;
    for (int i = 1; i <= 10; i++) {
        sum += i;
    }
    ASSERT_EQ(sum, 55);

    TEST("While loop");
    int count = 0;
    int i = 0;
    while (i < 10) {
        count++;
        i++;
    }
    ASSERT_EQ(count, 10);

    TEST("Break in loop");
    sum = 0;
    for (i = 0; i < 100; i++) {
        if (i == 5) break;
        sum++;
    }
    ASSERT_EQ(sum, 5);

    TEST("Continue in loop");
    sum = 0;
    for (i = 0; i < 10; i++) {
        if (i % 2 == 0) continue;
        sum++;
    }
    ASSERT_EQ(sum, 5);  // Only odd numbers: 1,3,5,7,9
}

// ============================================================================
// Function Call Tests
// ============================================================================

int add_two_numbers(int a, int b) {
    return a + b;
}

int factorial(int n) {
    if (n <= 1) return 1;
    return n * factorial(n - 1);
}

void test_function_calls(void) {
    SECTION("Function Calls");

    TEST("Simple function call");
    ASSERT_EQ(add_two_numbers(3, 4), 7);

    TEST("Recursive function (factorial 5)");
    ASSERT_EQ(factorial(5), 120);

    TEST("Recursive function (factorial 10)");
    ASSERT_EQ(factorial(10), 3628800);
}

// ============================================================================
// Floating-Point Tests (if FPU available)
// ============================================================================

void test_floating_point(void) {
    SECTION("Floating-Point Operations");

    // Basic FP arithmetic
    TEST("FP addition");
    double a = 1.5;
    double b = 2.5;
    ASSERT((a + b) == 4.0);

    TEST("FP subtraction");
    ASSERT((b - a) == 1.0);

    TEST("FP multiplication");
    ASSERT((a * 2.0) == 3.0);

    TEST("FP division");
    ASSERT((b / 2.0) == 1.25);

    TEST("FP comparison (greater)");
    ASSERT(2.5 > 1.5);

    TEST("FP comparison (equal)");
    ASSERT(3.0 == 3.0);

    TEST("FP comparison (less)");
    ASSERT(1.0 < 2.0);

    // Test special values
    TEST("FP zero");
    double zero = 0.0;
    ASSERT(zero == 0.0);

    TEST("FP negative");
    double neg = -5.5;
    ASSERT(neg < 0.0);

    // Test conversions
    TEST("Int to float");
    double from_int = (double)42;
    ASSERT(from_int == 42.0);

    TEST("Float to int");
    int to_int = (int)3.7;
    ASSERT_EQ(to_int, 3);
}

// ============================================================================
// Memory Allocator Tests
// ============================================================================

void test_malloc(void) {
    SECTION("Memory Allocation");

    TEST("Malloc single int");
    int *p = malloc(sizeof(int));
    int success = (p != 0);
    if (success) {
        *p = 42;
        success = (*p == 42);
        free(p);
    }
    ASSERT(success);

    TEST("Malloc array");
    int *arr = malloc(10 * sizeof(int));
    success = (arr != 0);
    if (success) {
        for (int i = 0; i < 10; i++) {
            arr[i] = i * 2;
        }
        success = (arr[0] == 0 && arr[5] == 10 && arr[9] == 18);
        free(arr);
    }
    ASSERT(success);

    TEST("Malloc alignment");
    void *p1 = malloc(1);
    void *p2 = malloc(1);
    void *p3 = malloc(1);
    success = (((unsigned int)p1 % 8) == 0) &&
              (((unsigned int)p2 % 8) == 0) &&
              (((unsigned int)p3 % 8) == 0);
    if (p1) free(p1);
    if (p2) free(p2);
    if (p3) free(p3);
    ASSERT(success);

    TEST("Malloc large block");
    char *large = malloc(1024);
    success = (large != 0);
    if (success) {
        large[0] = 'A';
        large[1023] = 'Z';
        success = (large[0] == 'A' && large[1023] == 'Z');
        free(large);
    }
    ASSERT(success);
}

// ============================================================================
// Printf Tests
// ============================================================================

void test_printf(void) {
    SECTION("Printf Formatting");

    // Note: We can't easily validate printf output in automated tests,
    // so we just verify it doesn't crash
    TEST("Printf integer");
    printf("%d", 42);
    ASSERT(1);  // If we got here, it didn't crash

    TEST("Printf hex");
    printf("0x%x", 0xDEAD);
    ASSERT(1);

    TEST("Printf string");
    printf("%s", "test");
    ASSERT(1);

    TEST("Printf multiple args");
    printf("%d %s 0x%x", 123, "hello", 0xFF);
    ASSERT(1);

    printf("\n");  // Clean newline after tests
}

// ============================================================================
// Main Test Runner
// ============================================================================

int main(void) {
    printf("\n");
    printf("======================================\n");
    printf("   RISC-V Emulator Regression Tests\n");
    printf("======================================\n");

    // Run all test suites
    test_arithmetic();
    test_bitwise();
    test_memory_alignment();
    test_control_flow();
    test_function_calls();
    test_floating_point();
    test_malloc();
    test_printf();

    // Summary
    printf("\n");
    printf("======================================\n");
    printf("Test Summary\n");
    printf("======================================\n");
    printf("Total:  %d\n", tests_run);
    printf("Passed: %d\n", tests_passed);
    printf("Failed: %d\n", tests_failed);
    printf("\n");

    if (tests_failed == 0) {
        printf("SUCCESS: All tests passed!\n\n");
        return 0;
    } else {
        printf("FAILURE: %d test(s) failed!\n\n", tests_failed);
        return 1;
    }
}
