/* **************************************************************************
 *                 RISC-V Emulator - FAT12 Filesystem Tests
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

#include "fat12.h"
#include "log.h"
#include "uart.h"
#include <string.h>

static int g_pass, g_fail;

#define PASS(msg) do { \
    log_write(NONE, "PASS: " msg "\n"); \
    g_pass++; \
} while (0)

#define FAIL(msg) do { \
    log_write(NONE, "FAIL: " msg "\n"); \
    g_fail++; \
} while (0)

#define CHECK(cond, msg) do { \
    if (cond) PASS(msg); else FAIL(msg); \
} while (0)

/* Build a repeating-pattern buffer for large-write tests */
static void fill_pattern(uint8_t *buf, int len, uint8_t start)
{
    int i;
    for (i = 0; i < len; i++)
        buf[i] = (uint8_t)((start + i) & 0xFFu);
}

static int verify_pattern(const uint8_t *buf, int len, uint8_t start)
{
    int i;
    for (i = 0; i < len; i++) {
        if (buf[i] != (uint8_t)((start + i) & 0xFFu)) return 0;
    }
    return 1;
}

static int str_eq(const char *a, const char *b)
{
    while (*a && *b) { if (*a != *b) return 0; a++; b++; }
    return *a == *b;
}

int main(void)
{
    uart_init();
    log_init("fat12-test.log");
    log_write(NONE, "=== FAT12 Test ===\n");

    g_pass = 0; g_fail = 0;

    /* ---- Test 1: Format ---- */
    {
        int r = fat12_format();
        CHECK(r == 0, "format returns 0");
    }

    /* ---- Test 2: Init (mount) ---- */
    {
        int r = fat12_init();
        CHECK(r == 0, "init after format succeeds");
    }

    /* ---- Test 3-7: Create and write a small file ---- */
    {
        fat12_file_t f;
        const char  *msg = "Hello, FAT12!";
        int          msglen = 13;
        int r;

        r = fat12_create("TEST.TXT", &f);
        CHECK(r == 0, "create TEST.TXT");

        r = fat12_write(&f, msg, msglen);
        CHECK(r == msglen, "write 13 bytes");

        CHECK(f.file_size == (uint32_t)msglen, "file_size == 13 after write");
        CHECK(f.first_cluster >= 2u, "cluster allocated");

        r = fat12_close(&f);
        CHECK(r == 0, "close TEST.TXT");
    }

    /* ---- Test 8-12: Open and read back ---- */
    {
        fat12_file_t f;
        char         rbuf[32];
        int          r;

        r = fat12_open("TEST.TXT", &f);
        CHECK(r == 0, "open TEST.TXT");
        CHECK(f.file_size == 13u, "file_size == 13 on open");

        memset(rbuf, 0, sizeof rbuf);
        r = fat12_read(&f, rbuf, 32);
        CHECK(r == 13, "read returns 13");
        CHECK(str_eq(rbuf, "Hello, FAT12!"), "content matches");
    }

    /* ---- Test 13: Open non-existent file ---- */
    {
        fat12_file_t f;
        int r = fat12_open("NO.FILE", &f);
        CHECK(r == -1, "open missing file returns -1");
    }

    /* ---- Test 14-17: Multi-cluster write (600 bytes, spans 2 clusters) ---- */
    {
        fat12_file_t f;
        uint8_t      wbuf[600];
        uint8_t      rbuf[600];
        int          r;

        fill_pattern(wbuf, 600, 0xA5u);

        r = fat12_create("BIG.BIN", &f);
        CHECK(r == 0, "create BIG.BIN");

        r = fat12_write(&f, wbuf, 600);
        CHECK(r == 600, "write 600 bytes (multi-cluster)");

        CHECK(f.file_size == 600u, "file_size == 600");

        r = fat12_close(&f);
        CHECK(r == 0, "close BIG.BIN");

        /* Read back */
        r = fat12_open("BIG.BIN", &f);
        CHECK(r == 0, "re-open BIG.BIN");

        memset(rbuf, 0, sizeof rbuf);
        r = fat12_read(&f, rbuf, 600);
        CHECK(r == 600, "read back 600 bytes");
        CHECK(verify_pattern(rbuf, 600, 0xA5u), "multi-cluster content correct");
    }

    /* ---- Test 19-21: Create a third file ---- */
    {
        fat12_file_t f;
        const char  *data = "Third";
        int          r;

        r = fat12_create("THIRD.DAT", &f);
        CHECK(r == 0, "create THIRD.DAT");
        fat12_write(&f, data, 5);
        fat12_close(&f);

        r = fat12_open("THIRD.DAT", &f);
        CHECK(r == 0, "open THIRD.DAT");

        char rbuf[8] = {0};
        fat12_read(&f, rbuf, 8);
        CHECK(str_eq(rbuf, "Third"), "THIRD.DAT content");
    }

    /* ---- Test 22-24: Directory listing ---- */
    {
        dir_entry_t e;
        int r;

        r = fat12_readdir(0, &e);
        CHECK(r == 0, "readdir[0] valid");
        /* name should be "TEST    " (first 8 chars) */
        CHECK(e.name[0] == 'T' && e.name[1] == 'E' && e.name[2] == 'S' && e.name[3] == 'T',
              "readdir[0] is TEST");

        r = fat12_readdir(1, &e);
        CHECK(r == 0, "readdir[1] valid");
        CHECK(e.name[0] == 'B' && e.name[1] == 'I' && e.name[2] == 'G',
              "readdir[1] is BIG");

        r = fat12_readdir(2, &e);
        CHECK(r == 0, "readdir[2] valid (THIRD)");
    }

    /* ---- Test 25-28: Delete file ---- */
    {
        fat12_file_t f;
        dir_entry_t  e;
        int r;

        r = fat12_delete("TEST.TXT");
        CHECK(r == 0, "delete TEST.TXT");

        r = fat12_open("TEST.TXT", &f);
        CHECK(r == -1, "open after delete returns -1");

        r = fat12_readdir(0, &e);
        CHECK(r == 1, "readdir[0] shows deleted slot");
        CHECK(e.name[0] == 0xE5u, "deleted marker 0xE5");
    }

    /* ---- Test 29: Reuse deleted slot ---- */
    {
        fat12_file_t f;
        int r;

        r = fat12_create("TEST.TXT", &f);
        CHECK(r == 0, "recreate TEST.TXT reuses slot");
        fat12_write(&f, "New", 3);
        fat12_close(&f);
    }

    /* ---- Test 30: Exact 512-byte (1-cluster) boundary ---- */
    {
        fat12_file_t f;
        uint8_t      wbuf[512];
        uint8_t      rbuf[512];
        int          r;

        fill_pattern(wbuf, 512, 0x55u);
        fat12_create("EXACT.BIN", &f);
        r = fat12_write(&f, wbuf, 512);
        CHECK(r == 512, "write exactly 512 bytes");
        fat12_close(&f);

        fat12_open("EXACT.BIN", &f);
        r = fat12_read(&f, rbuf, 512);
        CHECK(r == 512, "read exactly 512 bytes");
        CHECK(verify_pattern(rbuf, 512, 0x55u), "exact-boundary content correct");
    }

    /* ---- Test 33: Delete on non-existent file ---- */
    {
        int r = fat12_delete("GHOST.TXT");
        CHECK(r == -1, "delete non-existent returns -1");
    }

    /* ---- Test 34: Second format clears files ---- */
    {
        fat12_file_t f;
        int r;

        fat12_format();
        fat12_init();
        r = fat12_open("BIG.BIN", &f);
        CHECK(r == -1, "file gone after re-format");
    }

    /* Print summary */
    log_write(NONE, "\n");
    log_write(NONE, "=== Results ===\n");
    log_write(NONE, "PASS: ");
    {
        /* simple decimal print */
        char s[8]; int n = g_pass; int i = 7;
        s[i] = '\0';
        if (n == 0) { s[--i] = '0'; }
        else { while (n) { s[--i] = (char)('0' + n%10); n /= 10; } }
        log_write(NONE, s + i);
    }
    log_write(NONE, "\nFAIL: ");
    {
        char s[8]; int n = g_fail; int i = 7;
        s[i] = '\0';
        if (n == 0) { s[--i] = '0'; }
        else { while (n) { s[--i] = (char)('0' + n%10); n /= 10; } }
        log_write(NONE, s + i);
    }
    log_write(NONE, "\n");

    if (g_fail == 0)
        log_write(NONE, "ALL PASSED\n");

    log_close();
    return g_fail;
}
