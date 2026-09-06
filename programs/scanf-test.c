/* **************************************************************************
 *   RISC-V Emulator - sprintf/snprintf/sscanf/strtol/strtoul/strtod test
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

// scanf-test.c -- sprintf/snprintf/sscanf/strtol/strtoul/strtod test
// By Ulrik Hørlyk Hjort 2026

#include <stdint.h>
#include "log.h"

void putchar(char c);

static int g_pass = 0, g_fail = 0;

static int streq(const char *a, const char *b) {
    while (*a && *b) if (*a++ != *b++) return 0;
    return *a == *b;
}

static void chk(const char *label, int ok) {
    if (ok) { log_write(NONE, "  PASS  %s\n", label); g_pass++; }
    else     { log_write(NONE, "  FAIL  %s\n", label); g_fail++; }
}
static void chk_str(const char *label, const char *got, const char *exp) {
    int ok = streq(got, exp);
    if (ok) { log_write(NONE, "  PASS  %s\n", label); g_pass++; }
    else {
        log_write(NONE, "  FAIL  %s\n", label);
        log_write(NONE, "    got: %s\n", got);
        log_write(NONE, "    exp: %s\n", exp);
        g_fail++;
    }
}

/* -- Declarations for the functions under test ---------------------------- */
int  sprintf(char *buf, const char *fmt, ...);
int  snprintf(char *buf, int size, const char *fmt, ...);
int  sscanf(const char *str, const char *fmt, ...);
long strtol(const char *str, char **endptr, int base);
unsigned long strtoul(const char *str, char **endptr, int base);
double strtod(const char *str, char **endptr);

/* ========================================================================== */

static void test_sprintf(void) {
    log_write(NONE, "\n=== sprintf ===\n");
    char buf[64];

    sprintf(buf, "%d", 42);         chk_str("%%d positive",          buf, "42");
    sprintf(buf, "%d", -99);        chk_str("%%d negative",          buf, "-99");
    sprintf(buf, "%05d", 7);        chk_str("%%05d zero-pad",        buf, "00007");
    sprintf(buf, "%5d", 7);         chk_str("%%5d space-pad",        buf, "    7");
    sprintf(buf, "%05d", -7);       chk_str("%%05d negative pad",    buf, "-0007");
    sprintf(buf, "%u", 4294967295u);chk_str("%%u UINT_MAX",         buf, "4294967295");
    sprintf(buf, "%x", 0xdeadbeefu);chk_str("%%x lowercase hex",    buf, "deadbeef");
    sprintf(buf, "%X", 0xCAFEu);    chk_str("%%X uppercase hex",     buf, "CAFE");
    sprintf(buf, "%08x", 0xABu);    chk_str("%%08x zero-pad hex",    buf, "000000ab");
    sprintf(buf, "%s", "hello");    chk_str("%%s string",            buf, "hello");
    sprintf(buf, "%c", 'Z');        chk_str("%%c char",              buf, "Z");
    sprintf(buf, "%%");             chk_str("%%%% literal",          buf, "%");
    sprintf(buf, "%d+%d=%d", 1,2,3);chk_str("mixed format",         buf, "1+2=3");
    sprintf(buf, "%.2f", 3.14159);  chk_str("%%.2f float",          buf, "3.14");
    sprintf(buf, "%.1f", -2.75);    chk_str("%%.1f neg float",       buf, "-2.8");
}

static void test_snprintf(void) {
    log_write(NONE, "\n=== snprintf ===\n");
    char buf[16];

    /* fits exactly */
    int r = snprintf(buf, 16, "hello %d", 42);
    chk_str("fits in buffer",         buf, "hello 42");
    chk("return = chars written",      r == 8);

    /* truncation: size=6, output would be "hello 42" (8 chars) */
    r = snprintf(buf, 6, "hello %d", 42);
    chk_str("truncated to 5 chars",   buf, "hello"); /* buf[5] = '\0' */
    chk("return = total chars (8)",   r == 8);

    /* size=1: nothing written, only NUL */
    snprintf(buf, 1, "abc");
    chk("size=1 -> empty string",      buf[0] == '\0');

    /* zero-pad in snprintf */
    snprintf(buf, 16, "%04x", 0xff);
    chk_str("%%04x in snprintf",      buf, "00ff");
}

static void test_sscanf(void) {
    log_write(NONE, "\n=== sscanf ===\n");
    int n; unsigned int u; char s[32]; char c;

    /* %d */
    int r = sscanf("42", "%d", &n);
    chk("%%d positive: count=1",   r == 1);
    chk("%%d positive: val=42",    n == 42);

    r = sscanf("-99", "%d", &n);
    chk("%%d negative: count=1",   r == 1);
    chk("%%d negative: val=-99",   n == -99);

    /* %u */
    r = sscanf("4000000000", "%u", &u);
    chk("%%u large: count=1",      r == 1);
    chk("%%u large: val correct",  u == 4000000000u);

    /* %x */
    r = sscanf("deadbeef", "%x", &u);
    chk("%%x hex: count=1",        r == 1);
    chk("%%x hex: val correct",    u == 0xdeadbeefu);

    r = sscanf("0xCAFE", "%x", &u);
    chk("%%x with 0x prefix",      u == 0xCAFEu);

    /* %s */
    r = sscanf("  hello world", "%s", s);
    chk("%%s first word: count=1", r == 1);
    chk("%%s first word: correct", streq(s, "hello"));

    /* %c */
    r = sscanf("A", "%c", &c);
    chk("%%c: count=1",            r == 1);
    chk("%%c: val='A'",            c == 'A');

    /* multiple fields */
    r = sscanf("10 hello ff", "%d %s %x", &n, s, &u);
    chk("multi-field: count=3",    r == 3);
    chk("multi-field: n=10",       n == 10);
    chk("multi-field: s=hello",    streq(s, "hello"));
    chk("multi-field: u=0xff",     u == 0xff);

    /* %i auto-detect base */
    r = sscanf("0x1A", "%i", &n);
    chk("%%i hex auto: val=26",    n == 26);
    r = sscanf("010", "%i", &n);
    chk("%%i octal auto: val=8",   n == 8);

    /* literal char matching */
    r = sscanf("3:14", "%d:%d", &n, &u);
    chk("literal ':' match",       r == 2 && n == 3 && u == 14);

    /* partial match -> returns count so far */
    r = sscanf("42 xyz", "%d %d", &n, &u);
    chk("partial match returns 1", r == 1);
}

static void test_strtol(void) {
    log_write(NONE, "\n=== strtol ===\n");
    char *end;

    chk("base10 +",    strtol("123",    &end, 10) == 123);
    chk("base10 -",    strtol("-456",   &end, 10) == -456);
    chk("base16 0x",   strtol("0xff",   &end, 16) == 255);
    chk("base16 no0x", strtol("1A",     &end, 16) == 26);
    chk("base8",       strtol("17",     &end, 8)  == 15);
    chk("auto dec",    strtol("100",    &end, 0)  == 100);
    chk("auto hex",    strtol("0x10",   &end, 0)  == 16);
    chk("auto oct",    strtol("010",    &end, 0)  == 8);

    /* endptr points past consumed chars */
    strtol("42abc", &end, 10);
    chk("endptr after digits",     streq(end, "abc"));

    /* whitespace skip */
    chk("leading spaces",  strtol("  7",  &end, 10) == 7);
}

static void test_strtoul(void) {
    log_write(NONE, "\n=== strtoul ===\n");
    char *end;

    chk("strtoul dec",     strtoul("4294967295", &end, 10) == 4294967295ul);
    chk("strtoul hex 0x",  strtoul("0xDEAD",     &end, 16) == 0xDEADu);
    chk("strtoul auto hex",strtoul("0xff",        &end, 0)  == 255u);
    chk("strtoul auto oct",strtoul("077",         &end, 0)  == 63u);
    chk("strtoul 0",       strtoul("0",           &end, 10) == 0u);
}

static void test_strtod(void) {
    log_write(NONE, "\n=== strtod ===\n");
    char *end;
    double v;

    v = strtod("42",    &end); chk("integer",      (int)v == 42);
    v = strtod("-7",    &end); chk("negative int",  (int)v == -7);
    v = strtod("3.5",   &end); chk("3.5 -> *2=7",   (int)(v*2) == 7);
    v = strtod("1e3",   &end); chk("1e3 = 1000",    (int)v == 1000);
    v = strtod("1.5e2", &end); chk("1.5e2 = 150",   (int)v == 150);
    v = strtod("2.5e-1",&end); chk("2.5e-1 = 0.25", (int)(v*4) == 1);
    v = strtod("  3.0", &end); chk("leading space",  (int)v == 3);

    /* endptr */
    strtod("1.5xyz", &end);
    chk("endptr after number",  streq(end, "xyz"));
}

/* ========================================================================== */
int main(void) {
    log_init("scanf-test.log");
    log_write(NONE, "sprintf/snprintf/sscanf/strtol/strtoul/strtod Test\n");

    test_sprintf();
    test_snprintf();
    test_sscanf();
    test_strtol();
    test_strtoul();
    test_strtod();

    log_write(NONE, "\n%d PASS  %d FAIL\n", g_pass, g_fail);
    log_close();
    return g_fail ? 1 : 0;
}
