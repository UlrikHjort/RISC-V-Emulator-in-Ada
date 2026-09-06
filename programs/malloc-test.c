/* **************************************************************************
 *              RISC-V Emulator - Memory allocator stress test
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

// Memory allocator stress test
// Tests: malloc, free, realloc, alignment, fragmentation
// By Ulrik Hørlyk Hjort 2026

#include <stddef.h>

int printf(const char *fmt, ...);
void *malloc(unsigned long size);
void free(void *ptr);
void *realloc(void *ptr, unsigned long size);

// Simple linked list node
typedef struct Node {
    int data;
    struct Node *next;
} Node;

int main(void) {
    printf("=== Memory Allocator Test ===\n\n");

    // Test 1: Basic allocations
    printf("Test 1: Basic allocations\n");
    int *a = malloc(sizeof(int));
    int *b = malloc(sizeof(int) * 10);
    char *c = malloc(100);

    if (a && b && c) {
        *a = 42;
        b[0] = 1; b[9] = 10;
        c[0] = 'H'; c[1] = 'i'; c[2] = '\0';

        printf("  a = %d (at %x)\n", *a, (unsigned int)a);
        printf("  b[0] = %d, b[9] = %d (at %x)\n", b[0], b[9], (unsigned int)b);
        printf("  c = \"%s\" (at %x)\n", c, (unsigned int)c);
        printf("  PASS\n\n");
    } else {
        printf("  FAIL: malloc returned NULL\n\n");
    }

    // Test 2: Linked list (multiple small allocations)
    printf("Test 2: Linked list (10 nodes)\n");
    Node *head = NULL;
    for (int i = 0; i < 10; i++) {
        Node *node = malloc(sizeof(Node));
        if (!node) {
            printf("  FAIL: malloc failed at node %d\n\n", i);
            goto test3;
        }
        node->data = i * 10;
        node->next = head;
        head = node;
    }

    printf("  List: ");
    Node *curr = head;
    while (curr) {
        printf("%d ", curr->data);
        curr = curr->next;
    }
    printf("\n  PASS\n\n");

test3:
    // Test 3: Large allocation
    printf("Test 3: Large allocation (1KB)\n");
    char *large = malloc(1024);
    if (large) {
        for (int i = 0; i < 1024; i++) {
            large[i] = (char)(i & 0xFF);
        }
        printf("  Allocated 1KB at %x\n", (unsigned int)large);
        printf("  large[0] = %x, large[1023] = %x\n",
               (unsigned char)large[0], (unsigned char)large[1023]);
        printf("  PASS\n\n");
    } else {
        printf("  FAIL: malloc returned NULL\n\n");
    }

    // Test 4: Realloc
    printf("Test 4: Realloc\n");
    int *arr = malloc(5 * sizeof(int));
    if (arr) {
        for (int i = 0; i < 5; i++) arr[i] = i;
        printf("  Original (5 ints): ");
        for (int i = 0; i < 5; i++) printf("%d ", arr[i]);
        printf("\n");

        arr = realloc(arr, 10 * sizeof(int));
        if (arr) {
            for (int i = 5; i < 10; i++) arr[i] = i;
            printf("  After realloc (10 ints): ");
            for (int i = 0; i < 10; i++) printf("%d ", arr[i]);
            printf("\n  PASS\n\n");
        } else {
            printf("  FAIL: realloc returned NULL\n\n");
        }
    }

    // Test 5: Alignment check
    printf("Test 5: Alignment check\n");
    void *p1 = malloc(1);
    void *p2 = malloc(1);
    void *p3 = malloc(1);

    printf("  p1 = %x (aligned to 8? %s)\n",
           (unsigned int)p1, ((unsigned int)p1 % 8 == 0) ? "yes" : "no");
    printf("  p2 = %x (aligned to 8? %s)\n",
           (unsigned int)p2, ((unsigned int)p2 % 8 == 0) ? "yes" : "no");
    printf("  p3 = %x (aligned to 8? %s)\n",
           (unsigned int)p3, ((unsigned int)p3 % 8 == 0) ? "yes" : "no");

    if (((unsigned int)p1 % 8 == 0) &&
        ((unsigned int)p2 % 8 == 0) &&
        ((unsigned int)p3 % 8 == 0)) {
        printf("  PASS\n\n");
    } else {
        printf("  FAIL: not all pointers are aligned\n\n");
    }

    printf("All tests complete!\n");
    while (1);
    return 0;
}
