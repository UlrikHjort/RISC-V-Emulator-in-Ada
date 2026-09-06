/* **************************************************************************
 *              RISC-V Emulator - Sorting algorithm benchmark
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

// sort-bench.c -- Sorting algorithm benchmark
//
// Implements four classic algorithms and compares their correctness and
// cycle cost on three data scenarios:
//
//   random      -- 64 values from xorshift32(seed=12345), mod 10000
//   sorted      -- already in ascending order
//   reverse     -- in descending order
//
// All four algorithms must produce the same output; insertion sort is the
// ground-truth reference.  Cycle counts are logged so you can compare
// algorithm efficiency on each scenario.
//
// Algorithms:
//   1. Insertion sort  O(n^2)      -- simple, stable, fast on nearly-sorted data
//   2. Heap sort       O(n log n) -- in-place, no extra memory
//   3. Quicksort       O(n log n) -- median-of-three pivot, good average case
//   4. Merge sort      O(n log n) -- stable, uses O(n) temporary buffer
//
// Build: cd programs && make run-sort-bench
// By Ulrik Hørlyk Hjort 2026

#include "log.h"
#include <stdint.h>

void putchar(char c);
static void uart_puts(const char *s) {
    while (*s) { if (*s == '\n') putchar('\r'); putchar(*s++); }
}

#define N 64

// -- PRNG --------------------------------------------------------------------

static uint32_t xorshift32(uint32_t *s) {
    uint32_t x = *s;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    return *s = x;
}

// -- Utility -----------------------------------------------------------------

static void copy(int32_t *dst, const int32_t *src, int n) {
    for (int i = 0; i < n; i++) dst[i] = src[i];
}

static int equal(const int32_t *a, const int32_t *b, int n) {
    for (int i = 0; i < n; i++) if (a[i] != b[i]) return 0;
    return 1;
}

static int is_sorted(const int32_t *a, int n) {
    for (int i = 1; i < n; i++) if (a[i] < a[i-1]) return 0;
    return 1;
}

static void swap(int32_t *a, int32_t *b) {
    int32_t t = *a; *a = *b; *b = t;
}

// -- Insertion sort -----------------------------------------------------------

static void insertion_sort(int32_t *a, int n) {
    for (int i = 1; i < n; i++) {
        int32_t key = a[i];
        int j = i - 1;
        while (j >= 0 && a[j] > key) { a[j+1] = a[j]; j--; }
        a[j+1] = key;
    }
}

// -- Heap sort ----------------------------------------------------------------

static void sift_down(int32_t *a, int n, int i) {
    while (1) {
        int largest = i, l = 2*i+1, r = 2*i+2;
        if (l < n && a[l] > a[largest]) largest = l;
        if (r < n && a[r] > a[largest]) largest = r;
        if (largest == i) break;
        swap(&a[i], &a[largest]);
        i = largest;
    }
}

static void heap_sort(int32_t *a, int n) {
    for (int i = n/2 - 1; i >= 0; i--) sift_down(a, n, i);
    for (int i = n - 1; i > 0; i--) {
        swap(&a[0], &a[i]);
        sift_down(a, i, 0);
    }
}

// -- Quicksort (median-of-three pivot) ----------------------------------------

static int32_t median3(int32_t a, int32_t b, int32_t c) {
    // Sort a,b,c and return the median
    if (a > b) { int32_t t = a; a = b; b = t; }
    if (b > c) { int32_t t = b; b = c; c = t; }
    if (a > b) b = a;
    return b;
}

static void quicksort(int32_t *a, int lo, int hi) {
    if (hi - lo < 2) return;
    if (hi - lo == 2) {
        if (a[lo] > a[lo+1]) swap(&a[lo], &a[lo+1]);
        return;
    }
    int mid = lo + (hi - lo) / 2;
    int32_t pivot = median3(a[lo], a[mid], a[hi-1]);
    // Place median at a[hi-1] to use as pivot sentinel
    // (find it and swap to hi-1)
    if (a[lo] == pivot)        swap(&a[lo],  &a[hi-1]);
    else if (a[mid] == pivot)  swap(&a[mid], &a[hi-1]);

    int i = lo, j = hi - 2;
    while (i <= j) {
        while (i <= j && a[i] < pivot) i++;
        while (i <= j && a[j] > pivot) j--;
        if (i < j) { swap(&a[i], &a[j]); i++; j--; }
        else if (i == j) { i++; break; }
    }
    // Put pivot back
    swap(&a[i], &a[hi-1]);
    quicksort(a, lo, i);
    quicksort(a, i + 1, hi);
}

// -- Merge sort ---------------------------------------------------------------

static int32_t merge_tmp[N];  // static scratch buffer

static void merge_halves(int32_t *a, int lo, int mid, int hi) {
    for (int i = lo; i < hi; i++) merge_tmp[i - lo] = a[i];
    int i = 0, j = mid - lo, k = lo;
    int left_end = mid - lo, right_end = hi - lo;
    while (i < left_end && j < right_end)
        a[k++] = (merge_tmp[i] <= merge_tmp[j]) ? merge_tmp[i++] : merge_tmp[j++];
    while (i < left_end)  a[k++] = merge_tmp[i++];
    while (j < right_end) a[k++] = merge_tmp[j++];
}

static void merge_sort(int32_t *a, int lo, int hi) {
    if (hi - lo < 2) return;
    int mid = lo + (hi - lo) / 2;
    merge_sort(a, lo, mid);
    merge_sort(a, mid, hi);
    merge_halves(a, lo, mid, hi);
}

// -- Test infrastructure ------------------------------------------------------

static int g_pass = 0, g_fail = 0;

static void check_label(const char *label, int ok) {
    if (ok) { log_write(NONE, "  PASS  %s\n", label); g_pass++; }
    else    { log_write(NONE, "  FAIL  %s\n", label); g_fail++; }
}

static void log_array_short(const char *label, const int32_t *a, int n) {
    log_write(NONE, "  %s: [", label);
    for (int i = 0; i < n; i++) {
        if (i) log_write(NONE, ",");
        log_write(NONE, "%d", a[i]);
    }
    log_write(NONE, "]\n");
}

// -- Run one scenario ---------------------------------------------------------

static int32_t ref[N];   // insertion sort result (ground truth)
static int32_t buf[N];   // working copy

static void run_scenario(const char *name, const int32_t *data) {
    log_write(NONE, "\n--- Scenario: %s ---\n", name);
    log_array_short("input[0..7]", data, 8);

    // Ground truth: insertion sort
    copy(ref, data, N);
    log_write(CYCLES, "insertion_sort start\n");
    insertion_sort(ref, N);
    log_write(CYCLES, "insertion_sort done\n");
    check_label("insertion_sort: output is sorted", is_sorted(ref, N));

    // Heap sort
    copy(buf, data, N);
    log_write(CYCLES, "heap_sort start\n");
    heap_sort(buf, N);
    log_write(CYCLES, "heap_sort done\n");
    check_label("heap_sort: output is sorted",    is_sorted(buf, N));
    check_label("heap_sort: matches reference",   equal(buf, ref, N));

    // Quicksort
    copy(buf, data, N);
    log_write(CYCLES, "quicksort start\n");
    quicksort(buf, 0, N);
    log_write(CYCLES, "quicksort done\n");
    check_label("quicksort:  output is sorted",   is_sorted(buf, N));
    check_label("quicksort:  matches reference",  equal(buf, ref, N));

    // Merge sort
    copy(buf, data, N);
    log_write(CYCLES, "merge_sort start\n");
    merge_sort(buf, 0, N);
    log_write(CYCLES, "merge_sort done\n");
    check_label("merge_sort: output is sorted",   is_sorted(buf, N));
    check_label("merge_sort: matches reference",  equal(buf, ref, N));

    log_array_short("sorted[0..7]", ref, 8);
}

// -- Main ---------------------------------------------------------------------

int main(void) {
    uart_puts("=== Sort Benchmark ===\n");

    if (log_init("sort-bench.log") != 0) {
        uart_puts("ERROR: log_init failed\n");
        return 1;
    }

    log_write(NONE, "=== Sorting Algorithm Benchmark (N=%d) ===\n", N);
    log_write(NONE, "Algorithms: insertion | heap | quick (median-of-3) | merge\n");
    log_write(NONE, "Cycle counts: subtract consecutive [XXXXXXXX] timestamps\n");

    // -- Scenario 1: random data ----------------------------------------------
    int32_t random_data[N];
    {
        uint32_t seed = 12345;
        for (int i = 0; i < N; i++)
            random_data[i] = (int32_t)(xorshift32(&seed) % 10000);
    }
    run_scenario("random (xorshift32 seed=12345)", random_data);

    // -- Scenario 2: already sorted -------------------------------------------
    int32_t sorted_data[N];
    for (int i = 0; i < N; i++) sorted_data[i] = i * 3;
    run_scenario("already sorted (0, 3, 6, ... )", sorted_data);

    // -- Scenario 3: reverse sorted -------------------------------------------
    int32_t reverse_data[N];
    for (int i = 0; i < N; i++) reverse_data[i] = (N - 1 - i) * 3;
    run_scenario("reverse sorted (189, 186, ... , 0)", reverse_data);

    // -- Scenario 4: all same value (edge case) -------------------------------
    int32_t equal_data[N];
    for (int i = 0; i < N; i++) equal_data[i] = 42;
    run_scenario("all equal (42)", equal_data);

    log_write(NONE, "\n=== Summary ===\n");
    log_write(NONE, "  PASS: %d\n", g_pass);
    log_write(NONE, "  FAIL: %d\n", g_fail);
    log_write(NONE, "  %s\n", g_fail == 0 ? "ALL TESTS PASSED" : "SOME TESTS FAILED");

    log_close();
    uart_puts(g_fail == 0 ? "ALL PASSED\n" : "SOME FAILED\n");
    return g_fail;
}
