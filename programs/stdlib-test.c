/* **************************************************************************
 *        RISC-V Emulator - Standard library utility functions test
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

// Standard library utility functions test
// Tests: atoi, atol, atof, bsearch, qsort, rand, srand
// By Ulrik Hørlyk Hjort 2026

int printf(const char *fmt, ...);

// Stdlib functions
extern int atoi(const char *str);
extern long atol(const char *str);
extern double atof(const char *str);
extern void *bsearch(const void *key, const void *base, unsigned long nmemb,
                     unsigned long size, int (*compar)(const void *, const void *));
extern void qsort(void *base, unsigned long nmemb, unsigned long size,
                  int (*compar)(const void *, const void *));
extern int rand(void);
extern void srand(unsigned int seed);

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

// ============================================================================
// Numeric Conversion Tests
// ============================================================================

void test_atoi(void) {
    printf("\n=== atoi Tests ===\n");

    TEST("Positive number");
    ASSERT(atoi("123") == 123, "expected 123");

    TEST("Negative number");
    ASSERT(atoi("-456") == -456, "expected -456");

    TEST("With leading whitespace");
    ASSERT(atoi("  789") == 789, "expected 789");

    TEST("With plus sign");
    ASSERT(atoi("+42") == 42, "expected 42");

    TEST("Zero");
    ASSERT(atoi("0") == 0, "expected 0");

    TEST("Stops at non-digit");
    ASSERT(atoi("123abc") == 123, "expected 123");
}

void test_atol(void) {
    printf("\n=== atol Tests ===\n");

    TEST("Small positive");
    ASSERT(atol("1234567") == 1234567L, "expected 1234567");

    TEST("Small negative");
    ASSERT(atol("-9876543") == -9876543L, "expected -9876543");

    TEST("With whitespace");
    ASSERT(atol(" 42") == 42L, "expected 42");

    TEST("Zero");
    ASSERT(atol("0") == 0L, "expected 0");
}

void test_atof(void) {
    printf("\n=== atof Tests ===\n");

    TEST("Integer part only");
    double val1 = atof("123");
    ASSERT(val1 > 122.9 && val1 < 123.1, "expected 123.0");

    TEST("With decimal");
    double val2 = atof("3.14");
    ASSERT(val2 > 3.13 && val2 < 3.15, "expected 3.14");

    TEST("Negative");
    double val3 = atof("-2.5");
    ASSERT(val3 > -2.51 && val3 < -2.49, "expected -2.5");

    TEST("Leading zero");
    double val4 = atof("0.5");
    ASSERT(val4 > 0.49 && val4 < 0.51, "expected 0.5");

    TEST("With whitespace");
    double val5 = atof("  1.5");
    ASSERT(val5 > 1.49 && val5 < 1.51, "expected 1.5");

    TEST("Zero");
    double val6 = atof("0.0");
    ASSERT(val6 > -0.01 && val6 < 0.01, "expected 0.0");
}

// ============================================================================
// Sorting and Searching Tests
// ============================================================================

// Comparison function for integers
int int_compare(const void *a, const void *b) {
    int arg1 = *(const int *)a;
    int arg2 = *(const int *)b;

    if (arg1 < arg2) return -1;
    if (arg1 > arg2) return 1;
    return 0;
}

void test_qsort(void) {
    printf("\n=== qsort Tests ===\n");

    TEST("Sort ascending");
    int arr1[] = {5, 2, 8, 1, 9, 3};
    qsort(arr1, 6, sizeof(int), int_compare);
    int sorted1 = (arr1[0] == 1 && arr1[1] == 2 && arr1[2] == 3 &&
                   arr1[3] == 5 && arr1[4] == 8 && arr1[5] == 9);
    ASSERT(sorted1, "expected sorted array");

    TEST("Already sorted");
    int arr2[] = {1, 2, 3, 4, 5};
    qsort(arr2, 5, sizeof(int), int_compare);
    int sorted2 = (arr2[0] == 1 && arr2[4] == 5);
    ASSERT(sorted2, "expected sorted array");

    TEST("Reverse sorted");
    int arr3[] = {9, 7, 5, 3, 1};
    qsort(arr3, 5, sizeof(int), int_compare);
    int sorted3 = (arr3[0] == 1 && arr3[1] == 3 && arr3[4] == 9);
    ASSERT(sorted3, "expected sorted array");

    TEST("Duplicates");
    int arr4[] = {3, 1, 2, 3, 2, 1};
    qsort(arr4, 6, sizeof(int), int_compare);
    int sorted4 = (arr4[0] == 1 && arr4[2] == 2 && arr4[4] == 3);
    ASSERT(sorted4, "expected sorted array with duplicates");

    TEST("Single element");
    int arr5[] = {42};
    qsort(arr5, 1, sizeof(int), int_compare);
    ASSERT(arr5[0] == 42, "expected unchanged");

    TEST("Two elements");
    int arr6[] = {2, 1};
    qsort(arr6, 2, sizeof(int), int_compare);
    ASSERT(arr6[0] == 1 && arr6[1] == 2, "expected swapped");
}

void test_bsearch(void) {
    printf("\n=== bsearch Tests ===\n");

    int arr[] = {1, 3, 5, 7, 9, 11, 13, 15};
    int size = 8;

    TEST("Find first element");
    int key1 = 1;
    int *result1 = (int *)bsearch(&key1, arr, size, sizeof(int), int_compare);
    ASSERT(result1 != (int *)0 && *result1 == 1, "expected to find 1");

    TEST("Find last element");
    int key2 = 15;
    int *result2 = (int *)bsearch(&key2, arr, size, sizeof(int), int_compare);
    ASSERT(result2 != (int *)0 && *result2 == 15, "expected to find 15");

    TEST("Find middle element");
    int key3 = 7;
    int *result3 = (int *)bsearch(&key3, arr, size, sizeof(int), int_compare);
    ASSERT(result3 != (int *)0 && *result3 == 7, "expected to find 7");

    TEST("Not found (too small)");
    int key4 = 0;
    int *result4 = (int *)bsearch(&key4, arr, size, sizeof(int), int_compare);
    ASSERT(result4 == (int *)0, "expected NULL");

    TEST("Not found (too large)");
    int key5 = 20;
    int *result5 = (int *)bsearch(&key5, arr, size, sizeof(int), int_compare);
    ASSERT(result5 == (int *)0, "expected NULL");

    TEST("Not found (gap)");
    int key6 = 4;
    int *result6 = (int *)bsearch(&key6, arr, size, sizeof(int), int_compare);
    ASSERT(result6 == (int *)0, "expected NULL");
}

// ============================================================================
// Random Number Generator Tests
// ============================================================================

void test_rand(void) {
    printf("\n=== rand/srand Tests ===\n");

    TEST("Generate random numbers");
    int r1 = rand();
    int r2 = rand();
    int r3 = rand();
    ASSERT(r1 >= 0 && r2 >= 0 && r3 >= 0, "expected non-negative");

    TEST("Numbers are different");
    int different = (r1 != r2) || (r2 != r3);
    ASSERT(different, "expected some variation");

    TEST("Seed produces consistent sequence");
    srand(42);
    int s1 = rand();
    int s2 = rand();
    srand(42);  // Reset to same seed
    int s3 = rand();
    int s4 = rand();
    ASSERT(s1 == s3 && s2 == s4, "expected same sequence");

    TEST("Different seeds produce different values");
    srand(100);
    int d1 = rand();
    srand(200);
    int d2 = rand();
    ASSERT(d1 != d2, "expected different values");

    TEST("Range check");
    srand(12345);
    int in_range = 1;
    for (int i = 0; i < 100; i++) {
        int r = rand();
        if (r < 0 || r > 32767) {
            in_range = 0;
            break;
        }
    }
    ASSERT(in_range, "expected all values in [0, RAND_MAX]");
}

// ============================================================================
// Integration Tests
// ============================================================================

void test_integration(void) {
    printf("\n=== Integration Tests ===\n");

    TEST("atoi + qsort");
    int nums[5];
    nums[0] = atoi("42");
    nums[1] = atoi("7");
    nums[2] = atoi("100");
    nums[3] = atoi("3");
    nums[4] = atoi("56");
    qsort(nums, 5, sizeof(int), int_compare);
    ASSERT(nums[0] == 3 && nums[4] == 100, "expected sorted");

    TEST("atoi + bsearch");
    int sorted_nums[] = {10, 20, 30, 40, 50};
    int search_key = atoi("30");
    int *found = (int *)bsearch(&search_key, sorted_nums, 5, sizeof(int), int_compare);
    ASSERT(found != (int *)0 && *found == 30, "expected to find 30");

    TEST("rand + qsort");
    srand(999);
    int random_nums[10];
    for (int i = 0; i < 10; i++) {
        random_nums[i] = rand() % 100;
    }
    qsort(random_nums, 10, sizeof(int), int_compare);
    // Check if sorted
    int is_sorted = 1;
    for (int i = 1; i < 10; i++) {
        if (random_nums[i] < random_nums[i-1]) {
            is_sorted = 0;
            break;
        }
    }
    ASSERT(is_sorted, "expected sorted random numbers");
}

// ============================================================================
// Main Test Runner
// ============================================================================

int main(void) {
    printf("\n======================================\n");
    printf("   Standard Library Utilities Tests\n");
    printf("======================================\n");

    test_atoi();
    test_atol();
    test_atof();
    test_qsort();
    test_bsearch();
    test_rand();
    test_integration();

    printf("\n======================================\n");
    printf("Test Summary\n");
    printf("======================================\n");
    printf("Total:  %d\n", tests_run);
    printf("Passed: %d\n", tests_passed);
    printf("Failed: %d\n", tests_failed);
    printf("\n");

    if (tests_failed == 0) {
        printf("SUCCESS: All stdlib tests passed!\n\n");
        return 0;
    } else {
        printf("FAILURE: %d test(s) failed!\n\n", tests_failed);
        return 1;
    }
}
