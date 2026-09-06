/* **************************************************************************
 *RISC-V Emulator - String and memory function test for the RISC-V emulator
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

// string-ops.c -- String and memory function test for the RISC-V emulator.
//
// Exercises byte/halfword load-store paths via string.c functions:
//   1. memset / memcpy / memmove / memcmp
//   2. strlen / strcpy / strncpy
//   3. strcmp / strncmp
//   4. strcat / strncat
//   5. strchr / strrchr / strstr
//   Edge cases: empty strings, overlapping buffers, unaligned pointers
//
// Build: cd programs && make run-string-ops
// By Ulrik Hørlyk Hjort 2026

#include "log.h"
#include "string.h"
#include <stdint.h>

void putchar(char c);

static void uart_puts(const char *s) {
    while (*s) { if (*s == '\n') putchar('\r'); putchar(*s++); }
}

static int g_pass = 0, g_fail = 0;

static void check_i(const char *label, int got, int expected) {
    if (got == expected) {
        log_write(NONE, "  PASS  %s\n", label); g_pass++;
    } else {
        log_write(NONE, "  FAIL  %s: got %d  exp %d\n", label, got, expected); g_fail++;
    }
}

static void check_str(const char *label, const char *got, const char *expected) {
    if (strcmp(got, expected) == 0) {
        log_write(NONE, "  PASS  %s\n", label); g_pass++;
    } else {
        log_write(NONE, "  FAIL  %s: got \"%s\"  exp \"%s\"\n", label, got, expected); g_fail++;
    }
}

static void check_ptr(const char *label, const void *got, const void *expected) {
    if (got == expected) {
        log_write(NONE, "  PASS  %s\n", label); g_pass++;
    } else {
        log_write(NONE, "  FAIL  %s: ptr mismatch\n", label); g_fail++;
    }
}

// --- 1. memset ----------------------------------------------------------------

static void test_memset(void) {
    log_write(NONE, "\n=== memset ===\n");

    uint8_t buf[32];

    memset(buf, 0xAB, 32);
    int all_ab = 1;
    for (int i = 0; i < 32; i++) if (buf[i] != 0xAB) { all_ab = 0; break; }
    check_i("memset 32 bytes = 0xAB", all_ab, 1);

    memset(buf, 0, 32);
    int all_zero = 1;
    for (int i = 0; i < 32; i++) if (buf[i] != 0) { all_zero = 0; break; }
    check_i("memset 32 bytes = 0", all_zero, 1);

    // Partial fill: only middle 10 bytes
    memset(buf, 0xFF, 32);
    memset(buf + 5, 0x00, 10);
    check_i("partial memset: buf[4]=0xFF",  buf[4],  0xFF);
    check_i("partial memset: buf[5]=0x00",  buf[5],  0x00);
    check_i("partial memset: buf[14]=0x00", buf[14], 0x00);
    check_i("partial memset: buf[15]=0xFF", buf[15], 0xFF);

    // Zero-length memset -- must not crash
    memset(buf, 0x55, 0);
    check_i("memset len=0: buf[0] unchanged", buf[0], 0xFF);
}

// --- 2. memcpy ----------------------------------------------------------------

static void test_memcpy(void) {
    log_write(NONE, "\n=== memcpy ===\n");

    static const uint8_t src[16] = {0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15};
    uint8_t dst[20];

    memset(dst, 0xFF, sizeof(dst));
    memcpy(dst, src, 16);
    int ok = 1;
    for (int i = 0; i < 16; i++) if (dst[i] != i) { ok = 0; break; }
    check_i("memcpy 16 bytes", ok, 1);
    check_i("memcpy doesn't overwrite beyond", dst[16], 0xFF);

    // Unaligned src (src+1)
    memset(dst, 0, 16);
    memcpy(dst, src + 1, 8);
    check_i("memcpy unaligned src: dst[0]=1", dst[0], 1);
    check_i("memcpy unaligned src: dst[7]=8", dst[7], 8);

    // Unaligned dst (dst+1)
    memset(dst, 0, 16);
    memcpy(dst + 1, src, 8);
    check_i("memcpy unaligned dst: dst[1]=0", dst[1], 0);
    check_i("memcpy unaligned dst: dst[8]=7", dst[8], 7);

    // Zero-length
    memset(dst, 0xAA, 4);
    memcpy(dst, src, 0);
    check_i("memcpy len=0: dst[0] unchanged", dst[0], 0xAA);
}

// --- 3. memmove (overlapping) -------------------------------------------------

static void test_memmove(void) {
    log_write(NONE, "\n=== memmove (overlapping) ===\n");

    uint8_t buf[20];

    // Forward overlap: src < dst, overlapping
    for (int i = 0; i < 20; i++) buf[i] = (uint8_t)i;
    memmove(buf + 4, buf, 10);   // copy buf[0..9] -> buf[4..13]
    check_i("memmove fwd: buf[4]=0",   buf[4],  0);
    check_i("memmove fwd: buf[5]=1",   buf[5],  1);
    check_i("memmove fwd: buf[13]=9",  buf[13], 9);
    check_i("memmove fwd: buf[3] unchanged=3", buf[3], 3);

    // Backward overlap: dst < src, overlapping
    for (int i = 0; i < 20; i++) buf[i] = (uint8_t)i;
    memmove(buf, buf + 4, 10);   // copy buf[4..13] -> buf[0..9]
    check_i("memmove bwd: buf[0]=4",   buf[0], 4);
    check_i("memmove bwd: buf[1]=5",   buf[1], 5);
    check_i("memmove bwd: buf[9]=13",  buf[9], 13);
    check_i("memmove bwd: buf[10] unchanged=10", buf[10], 10);
}

// --- 4. memcmp ----------------------------------------------------------------

static void test_memcmp(void) {
    log_write(NONE, "\n=== memcmp ===\n");

    static const uint8_t a[] = {1, 2, 3, 4, 5};
    static const uint8_t b[] = {1, 2, 3, 4, 5};
    static const uint8_t c[] = {1, 2, 3, 4, 6};
    static const uint8_t d[] = {1, 2, 3, 4, 4};

    check_i("memcmp equal -> 0",   memcmp(a, b, 5), 0);
    check_i("memcmp a<c -> <0",    (memcmp(a, c, 5) < 0), 1);
    check_i("memcmp a>d -> >0",    (memcmp(a, d, 5) > 0), 1);
    check_i("memcmp len=0 -> 0",   memcmp(a, c, 0), 0);
    check_i("memcmp partial: first 4 equal -> 0", memcmp(a, c, 4), 0);
}

// --- 5. strlen ----------------------------------------------------------------

static void test_strlen(void) {
    log_write(NONE, "\n=== strlen ===\n");

    check_i("strlen \"\"   = 0",         (int)strlen(""),         0);
    check_i("strlen \"a\"  = 1",         (int)strlen("a"),        1);
    check_i("strlen \"hello\" = 5",      (int)strlen("hello"),    5);
    check_i("strlen \"hello world\" = 11", (int)strlen("hello world"), 11);

    char buf[8] = {'a','b','c','\0','x','y','z','\0'};
    check_i("strlen stops at first \\0 = 3", (int)strlen(buf), 3);
}

// --- 6. strcpy / strncpy ------------------------------------------------------

static void test_strcpy(void) {
    log_write(NONE, "\n=== strcpy / strncpy ===\n");

    char dst[32];

    // strcpy
    memset(dst, 0xFF, sizeof(dst));
    strcpy(dst, "hello");
    check_str("strcpy \"hello\"", dst, "hello");
    check_i("strcpy nul-terminates", dst[5], 0);

    strcpy(dst, "");
    check_str("strcpy empty", dst, "");
    check_i("strcpy empty: dst[0]=0", dst[0], 0);

    // strncpy: copies exactly n bytes; pads with NUL if src is shorter
    memset(dst, 0xFF, sizeof(dst));
    strncpy(dst, "hi", 8);
    check_str("strncpy \"hi\" n=8", dst, "hi");
    check_i("strncpy pads: dst[2]=0", dst[2], 0);
    check_i("strncpy pads: dst[7]=0", dst[7], 0);
    check_i("strncpy no overwrite: dst[8]=0xFF", (uint8_t)dst[8], 0xFF);

    // strncpy with n < strlen(src): no NUL added
    memset(dst, 0xFF, sizeof(dst));
    strncpy(dst, "hello", 3);
    check_i("strncpy n=3: dst[0]='h'", dst[0], 'h');
    check_i("strncpy n=3: dst[2]='l'", dst[2], 'l');
    // dst[3] is NOT set to NUL by strncpy when src >= n
}

// --- 7. strcmp / strncmp ------------------------------------------------------

static void test_strcmp(void) {
    log_write(NONE, "\n=== strcmp / strncmp ===\n");

    check_i("strcmp equal -> 0",        strcmp("abc", "abc"), 0);
    check_i("strcmp \"abc\"<\"abd\" -> <0", (strcmp("abc","abd") < 0), 1);
    check_i("strcmp \"abd\">\"abc\" -> >0", (strcmp("abd","abc") > 0), 1);
    check_i("strcmp empty eq -> 0",     strcmp("", ""), 0);
    check_i("strcmp \"a\">\"\" -> >0",  (strcmp("a", "") > 0), 1);
    check_i("strcmp \"\"<\"a\" -> <0",  (strcmp("", "a") < 0), 1);

    check_i("strncmp equal prefix",     strncmp("abcX", "abcY", 3), 0);
    check_i("strncmp differ at 4th",    (strncmp("abcX","abcY",4) != 0), 1);
    check_i("strncmp n=0 -> 0",         strncmp("abc","xyz",0), 0);
}

// --- 8. strcat / strncat ------------------------------------------------------

static void test_strcat(void) {
    log_write(NONE, "\n=== strcat / strncat ===\n");

    char dst[32];

    strcpy(dst, "hello");
    strcat(dst, " world");
    check_str("strcat basic", dst, "hello world");

    strcpy(dst, "");
    strcat(dst, "abc");
    check_str("strcat to empty", dst, "abc");

    strcat(dst, "");
    check_str("strcat empty src", dst, "abc");

    // strncat
    strcpy(dst, "hello");
    strncat(dst, " world", 3);
    check_str("strncat n=3", dst, "hello wo");   // ' ','w','o' (3 chars)

    strcpy(dst, "hi");
    strncat(dst, "xyz", 10);   // copies all 3 since n > len
    check_str("strncat n>len", dst, "hixyz");
}

// --- 9. strchr / strrchr / strstr --------------------------------------------

static void test_search(void) {
    log_write(NONE, "\n=== strchr / strrchr / strstr ===\n");

    const char *s = "hello world";

    check_ptr("strchr finds 'o'", strchr(s, 'o'), s + 4);
    check_ptr("strrchr finds last 'o'", strrchr(s, 'o'), s + 7);
    check_ptr("strchr 'h' = s[0]", strchr(s, 'h'), s);
    check_ptr("strchr '\\0' = s+11", strchr(s, '\0'), s + 11);
    check_ptr("strchr missing = NULL", strchr(s, 'z'), (char*)0);

    check_ptr("strstr finds \"world\"", strstr(s, "world"), s + 6);
    check_ptr("strstr finds \"hello\"", strstr(s, "hello"), s);
    check_ptr("strstr missing = NULL", strstr(s, "xyz"), (char*)0);
    check_ptr("strstr empty needle = s", strstr(s, ""), s);
}

// --- Main ---------------------------------------------------------------------

int main(void) {
    uart_puts("=== String Ops Test ===\n");
    if (log_init("string-ops.log") != 0) {
        uart_puts("ERROR: log_init failed\n");
        return 1;
    }

    log_write(NONE, "=== String Operations Test (RV32IMC) ===\n");

    test_memset();
    test_memcpy();
    test_memmove();
    test_memcmp();
    test_strlen();
    test_strcpy();
    test_strcmp();
    test_strcat();
    test_search();

    log_write(NONE, "\n=== Summary ===\n");
    log_write(NONE, "  PASS: %d\n", g_pass);
    log_write(NONE, "  FAIL: %d\n", g_fail);
    log_write(NONE, "  %s\n", g_fail == 0 ? "ALL TESTS PASSED" : "SOME TESTS FAILED");

    log_close();
    uart_puts(g_fail == 0 ? "ALL PASSED\n" : "SOME FAILED\n");
    return g_fail;
}
