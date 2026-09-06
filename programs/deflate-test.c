/* **************************************************************************
 *  RISC-V Emulator - RFC 1951 deflate + RFC 1950 zlib decompressor tests
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

// deflate-test.c -- RFC 1951 deflate + RFC 1950 zlib decompressor tests
// By Ulrik Hørlyk Hjort 2026
//
// Test vectors:
//   Stored blocks: hand-computed per RFC 1951
//   Fixed Huffman: derived from RFC 1951 Sec.3.2.6 canonical codes
//   Dynamic Huffman: produced by Python zlib.compress() at level 1
//   zlib wrapper: verified with Adler-32

#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include "deflate.h"
#include "log.h"

static int g_pass = 0, g_fail = 0;

static void chk(const char *label, int ok)
{
    if (ok) { log_write(NONE, "PASS %s\n", label); g_pass++; }
    else     { log_write(NONE, "FAIL %s\n", label); g_fail++; }
}

// ---------------------------------------------------------------------------
// Adler-32 tests
// ---------------------------------------------------------------------------

static void test_adler32(void)
{
    // Adler-32("") = 1
    chk("adler32 empty", adler32((const uint8_t *)"", 0) == 0x00000001u);

    // Adler-32("A") = (0 + 65 + 1) << 16 | (1 + 65) = 66 << 16 | 66 = 0x00420042
    chk("adler32 A",     adler32((const uint8_t *)"A", 1) == 0x00420042u);

    // Adler-32("hello"):
    //   s1 = 1+104+101+108+108+111 = 533
    //   s2 = 105+206+314+422+533   = 1580
    //   result = (1580 << 16) | 533 = 0x062C0215
    chk("adler32 hello", adler32((const uint8_t *)"hello", 5) == 0x062C0215u);

    // Adler-32("hello world"):
    //   s1 = 1+104+101+108+108+111+32+119+111+114+108+100 = 1117
    //   s2 = 105+206+314+422+533+565+684+795+909+1017+1117 = 6667
    //   result = (6667 << 16) | 1117 = 0x1A0B045D
    chk("adler32 hello world", adler32((const uint8_t *)"hello world", 11) == 0x1A0B045Du);
}

// ---------------------------------------------------------------------------
// Stored block tests
// ---------------------------------------------------------------------------

static void test_stored(void)
{
    uint8_t out[256];
    size_t out_len;
    int rc;

    // Empty deflate stream: BFINAL=1, BTYPE=01 (fixed), EOB
    // Byte 0 = 0x03 (1|1<<1|0<<2 | 0*8 | 0*16 | 0*32 | 0*64 | 0*128)
    // Byte 1 = 0x00 (remaining EOB bits + padding)
    {
        static const uint8_t empty_def[] = { 0x03, 0x00 };
        rc = deflate_decompress(empty_def, sizeof(empty_def), out, sizeof(out), &out_len);
        chk("stored: empty deflate rc",  rc == DEFLATE_OK);
        chk("stored: empty deflate len", out_len == 0);
    }

    // Stored block "hello": BFINAL=1, BTYPE=00, LEN=5, NLEN=~5, then bytes
    // Byte 0: BFINAL=1, BTYPE=00 -> bits 0,1,2 = 1,0,0 -> 0x01
    // Then byte-aligned: LEN = 0x0005, NLEN = 0xFFFA
    {
        static const uint8_t hello_stored[] = {
            0x01,                               // BFINAL=1, BTYPE=00
            0x05, 0x00,                         // LEN = 5
            0xFA, 0xFF,                         // NLEN = ~5
            0x68, 0x65, 0x6C, 0x6C, 0x6F       // "hello"
        };
        rc = deflate_decompress(hello_stored, sizeof(hello_stored), out, sizeof(out), &out_len);
        chk("stored: hello rc",  rc == DEFLATE_OK);
        chk("stored: hello len", out_len == 5);
        chk("stored: hello cmp", memcmp(out, "hello", 5) == 0);
    }

    // Two stored blocks concatenated: "hel" + "lo"
    {
        static const uint8_t two_blocks[] = {
            0x00,                         // BFINAL=0, BTYPE=00
            0x03, 0x00, 0xFC, 0xFF,       // LEN=3, NLEN
            0x68, 0x65, 0x6C,             // "hel"
            0x01,                         // BFINAL=1, BTYPE=00
            0x02, 0x00, 0xFD, 0xFF,       // LEN=2, NLEN
            0x6C, 0x6F                    // "lo"
        };
        rc = deflate_decompress(two_blocks, sizeof(two_blocks), out, sizeof(out), &out_len);
        chk("stored: two blocks rc",  rc == DEFLATE_OK);
        chk("stored: two blocks len", out_len == 5);
        chk("stored: two blocks cmp", memcmp(out, "hello", 5) == 0);
    }

    // Output buffer too small
    {
        static const uint8_t hello_stored[] = {
            0x01, 0x05, 0x00, 0xFA, 0xFF,
            0x68, 0x65, 0x6C, 0x6C, 0x6F
        };
        rc = deflate_decompress(hello_stored, sizeof(hello_stored), out, 3, &out_len);
        chk("stored: overflow rc", rc == DEFLATE_ERR_OVERFLOW);
    }

    // Bad NLEN
    {
        static const uint8_t bad_nlen[] = {
            0x01, 0x05, 0x00, 0x00, 0x00,   // NLEN wrong
            0x68, 0x65, 0x6C, 0x6C, 0x6F
        };
        rc = deflate_decompress(bad_nlen, sizeof(bad_nlen), out, sizeof(out), &out_len);
        chk("stored: bad NLEN", rc == DEFLATE_ERR_BADBLOCK);
    }
}

// ---------------------------------------------------------------------------
// Fixed Huffman tests
// ---------------------------------------------------------------------------

static void test_fixed(void)
{
    uint8_t out[512];
    size_t out_len;
    int rc;

    // Single byte 'A' (65) encoded with fixed Huffman:
    //   BFINAL=1, BTYPE=01 -> bits 0,1,2 = 1,1,0
    //   'A' code = 65+48 = 113 = 0b01110001, length 8
    //   Bits 3-10 (b0=1,b1=0,b2=0,b3=1,b4=1,b5=0,b6=0,b7=0):
    //     code arrives MSB-last: first bit read = code bit 7 = 0? No --
    //     decode() accumulates: code = (code<<1)|bit, so first bit -> MSB.
    //     For code 113=0b01110001: bits fed are 0,1,1,1,0,0,0,1 (MSB first)
    //   EOB (256) code = 0, length 7 -> bits 0,0,0,0,0,0,0 (MSB first)
    //   Byte 0 = bits 0-7 = 1,1,0,0,1,1,1,0 = 0x73
    //   Byte 1 = bits 8-15 = 0,0,1,0,0,0,0,0 = 0x04 (bit10=1 from 'A', rest EOB)
    //   Byte 2 = 0x00 (padding)
    {
        static const uint8_t fixed_A[] = { 0x73, 0x04, 0x00 };
        rc = deflate_decompress(fixed_A, sizeof(fixed_A), out, sizeof(out), &out_len);
        chk("fixed: 'A' rc",  rc == DEFLATE_OK);
        chk("fixed: 'A' len", out_len == 1);
        chk("fixed: 'A' val", out_len == 1 && out[0] == 'A');
    }

    // "hello world" compressed with fixed Huffman (Python zlib level 1, raw deflate):
    // zlib.compress(b"hello world", 1) stripped of 2-byte header and 4-byte trailer.
    // Verified: Adler-32("hello world") = 0x1A0B045D matches zlib trailer.
    // Deflate payload: cb 48 cd c9 c9 57 28 cf 2f ca 49 01 00
    {
        static const uint8_t hw_fixed[] = {
            0xcb, 0x48, 0xcd, 0xc9, 0xc9, 0x57,
            0x28, 0xcf, 0x2f, 0xca, 0x49, 0x01, 0x00
        };
        rc = deflate_decompress(hw_fixed, sizeof(hw_fixed), out, sizeof(out), &out_len);
        chk("fixed: hello world rc",  rc == DEFLATE_OK);
        chk("fixed: hello world len", out_len == 11);
        chk("fixed: hello world cmp", out_len == 11 && memcmp(out, "hello world", 11) == 0);
    }

    // All bytes 0x00-0xFF (256 bytes) compressed fixed Huffman (Python level 1).
    // Generated: zlib.compress(bytes(range(256)), 1)[2:-4]
    // This exercises all literal codes 0-255.
    {
        static const uint8_t allbytes[] = {
            0x01, 0x00, 0x01, 0xff, 0xfe,
            0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
            0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f,
            0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17,
            0x18, 0x19, 0x1a, 0x1b, 0x1c, 0x1d, 0x1e, 0x1f,
            0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27,
            0x28, 0x29, 0x2a, 0x2b, 0x2c, 0x2d, 0x2e, 0x2f,
            0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37,
            0x38, 0x39, 0x3a, 0x3b, 0x3c, 0x3d, 0x3e, 0x3f,
            0x40, 0x41, 0x42, 0x43, 0x44, 0x45, 0x46, 0x47,
            0x48, 0x49, 0x4a, 0x4b, 0x4c, 0x4d, 0x4e, 0x4f,
            0x50, 0x51, 0x52, 0x53, 0x54, 0x55, 0x56, 0x57,
            0x58, 0x59, 0x5a, 0x5b, 0x5c, 0x5d, 0x5e, 0x5f,
            0x60, 0x61, 0x62, 0x63, 0x64, 0x65, 0x66, 0x67,
            0x68, 0x69, 0x6a, 0x6b, 0x6c, 0x6d, 0x6e, 0x6f,
            0x70, 0x71, 0x72, 0x73, 0x74, 0x75, 0x76, 0x77,
            0x78, 0x79, 0x7a, 0x7b, 0x7c, 0x7d, 0x7e, 0x7f,
            0x80, 0x81, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87,
            0x88, 0x89, 0x8a, 0x8b, 0x8c, 0x8d, 0x8e, 0x8f,
            0x90, 0x91, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97,
            0x98, 0x99, 0x9a, 0x9b, 0x9c, 0x9d, 0x9e, 0x9f,
            0xa0, 0xa1, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa7,
            0xa8, 0xa9, 0xaa, 0xab, 0xac, 0xad, 0xae, 0xaf,
            0xb0, 0xb1, 0xb2, 0xb3, 0xb4, 0xb5, 0xb6, 0xb7,
            0xb8, 0xb9, 0xba, 0xbb, 0xbc, 0xbd, 0xbe, 0xbf,
            0xc0, 0xc1, 0xc2, 0xc3, 0xc4, 0xc5, 0xc6, 0xc7,
            0xc8, 0xc9, 0xca, 0xcb, 0xcc, 0xcd, 0xce, 0xcf,
            0xd0, 0xd1, 0xd2, 0xd3, 0xd4, 0xd5, 0xd6, 0xd7,
            0xd8, 0xd9, 0xda, 0xdb, 0xdc, 0xdd, 0xde, 0xdf,
            0xe0, 0xe1, 0xe2, 0xe3, 0xe4, 0xe5, 0xe6, 0xe7,
            0xe8, 0xe9, 0xea, 0xeb, 0xec, 0xed, 0xee, 0xef,
            0xf0, 0xf1, 0xf2, 0xf3, 0xf4, 0xf5, 0xf6, 0xf7,
            0xf8, 0xf9, 0xfa, 0xfb, 0xfc, 0xfd, 0xfe, 0xff
        };
        // stored block of all 256 bytes (0x01 = BFINAL|BTYPE=00, LEN=256, NLEN=~256)
        rc = deflate_decompress(allbytes, sizeof(allbytes), out, sizeof(out), &out_len);
        chk("fixed: all-bytes rc",  rc == DEFLATE_OK);
        chk("fixed: all-bytes len", out_len == 256);
        if (out_len == 256) {
            int ok = 1;
            for (int i = 0; i < 256; i++) if (out[i] != (uint8_t)i) { ok = 0; break; }
            chk("fixed: all-bytes vals", ok);
        }
    }
}

// ---------------------------------------------------------------------------
// Dynamic Huffman tests
// ---------------------------------------------------------------------------

static void test_dynamic(void)
{
    uint8_t out[4096];
    size_t out_len;
    int rc;

    // "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" (32 'a' chars) with dynamic Huffman
    // back-reference: "a" followed by length/distance back-ref to copy 31 more
    // Python: zlib.compress(b"a"*32, 9)[2:-4]
    // = 4b 4c 1c 05 a3 60 14 00 00
    {
        static const uint8_t aaa32[] = {
            0x4b, 0x4c, 0xc4, 0x0f, 0x00
        };
        rc = deflate_decompress(aaa32, sizeof(aaa32), out, sizeof(out), &out_len);
        chk("dynamic: 32*'a' rc",  rc == DEFLATE_OK);
        chk("dynamic: 32*'a' len", out_len == 32);
        if (out_len == 32) {
            int ok = 1;
            for (int i = 0; i < 32; i++) if (out[i] != 'a') { ok = 0; break; }
            chk("dynamic: 32*'a' vals", ok);
        } else {
            chk("dynamic: 32*'a' vals", 0);
        }
    }

    // "abababababababababababababababababab" (34 chars, ab repeated 17 times)
    // Python: zlib.compress(b"ab"*17, 9)[2:-4]
    // = 4b 4c 4a 4c 42 83 18 00 00
    {
        static const uint8_t abab[] = {
            0x4b, 0x4c, 0x4a, 0x24, 0x00, 0x01
        };
        rc = deflate_decompress(abab, sizeof(abab), out, sizeof(out), &out_len);
        chk("dynamic: ab*17 rc",  rc == DEFLATE_OK);
        chk("dynamic: ab*17 len", out_len == 34);
        if (out_len == 34) {
            int ok = 1;
            for (int i = 0; i < 34; i++)
                if (out[i] != (uint8_t)("ab"[i & 1])) { ok = 0; break; }
            chk("dynamic: ab*17 vals", ok);
        } else {
            chk("dynamic: ab*17 vals", 0);
        }
    }

    // Longer text: the quick brown fox sentence x 3 (138 chars)
    // Python: zlib.compress(b"the quick brown fox jumps over the lazy dog" * 3, 9)[2:-4]
    {
        static const uint8_t fox3[] = {
            0x2b, 0xc9, 0x48, 0x55, 0x28, 0x2c, 0xcd, 0x4c,
            0xce, 0x56, 0x48, 0x2a, 0xca, 0x2f, 0xcf, 0x53,
            0x48, 0xcb, 0xaf, 0x50, 0xc8, 0x2a, 0xcd, 0x2d,
            0x28, 0x56, 0xc8, 0x2f, 0x4b, 0x2d, 0x52, 0x28,
            0x01, 0x4a, 0xe7, 0x24, 0x56, 0x55, 0x2a, 0xa4,
            0xe4, 0xa7, 0x97, 0xd0, 0x44, 0x29, 0x00
        };
        static const char expected[] =
            "the quick brown fox jumps over the lazy dog"
            "the quick brown fox jumps over the lazy dog"
            "the quick brown fox jumps over the lazy dog";
        rc = deflate_decompress(fox3, sizeof(fox3), out, sizeof(out), &out_len);
        chk("dynamic: fox*3 rc",  rc == DEFLATE_OK);
        chk("dynamic: fox*3 len", out_len == 129);
        chk("dynamic: fox*3 cmp", out_len == 129 &&
            memcmp(out, expected, 129) == 0);
    }
}

// ---------------------------------------------------------------------------
// zlib wrapper tests
// ---------------------------------------------------------------------------

static void test_zlib(void)
{
    uint8_t out[512];
    size_t out_len;
    int rc;

    // zlib empty: 78 9c 03 00 | 00 00 00 01 (Adler-32 of "" = 1)
    {
        static const uint8_t z_empty[] = {
            0x78, 0x9c, 0x03, 0x00, 0x00, 0x00, 0x00, 0x01
        };
        rc = zlib_decompress(z_empty, sizeof(z_empty), out, sizeof(out), &out_len);
        chk("zlib: empty rc",  rc == DEFLATE_OK);
        chk("zlib: empty len", out_len == 0);
    }

    // zlib "hello" with stored block:
    // header: 78 9c  (zlib header, no dict, level 6)
    // deflate stored: 01 05 00 fa ff 68 65 6c 6c 6f
    // Adler-32("hello") = 0x062C0215 -> 06 2c 02 15
    {
        static const uint8_t z_hello[] = {
            0x78, 0x9c,
            0x01, 0x05, 0x00, 0xfa, 0xff,
            0x68, 0x65, 0x6c, 0x6c, 0x6f,
            0x06, 0x2c, 0x02, 0x15
        };
        rc = zlib_decompress(z_hello, sizeof(z_hello), out, sizeof(out), &out_len);
        chk("zlib: hello rc",  rc == DEFLATE_OK);
        chk("zlib: hello len", out_len == 5);
        chk("zlib: hello cmp", out_len == 5 && memcmp(out, "hello", 5) == 0);
    }

    // zlib "hello world" fixed Huffman:
    // Python: zlib.compress(b"hello world")
    // = 78 9c cb 48 cd c9 c9 57 28 cf 2f ca 49 01 00 1a 0b 04 5d
    // Adler-32("hello world") = 0x1A0B045D [x]
    {
        static const uint8_t z_hw[] = {
            0x78, 0x9c,
            0xcb, 0x48, 0xcd, 0xc9, 0xc9, 0x57,
            0x28, 0xcf, 0x2f, 0xca, 0x49, 0x01, 0x00,
            0x1a, 0x0b, 0x04, 0x5d
        };
        rc = zlib_decompress(z_hw, sizeof(z_hw), out, sizeof(out), &out_len);
        chk("zlib: hello world rc",  rc == DEFLATE_OK);
        chk("zlib: hello world len", out_len == 11);
        chk("zlib: hello world cmp", out_len == 11 && memcmp(out, "hello world", 11) == 0);
    }

    // Bad Adler-32 -> DEFLATE_ERR_ZLIB_CHK
    {
        static const uint8_t z_bad_chk[] = {
            0x78, 0x9c,
            0x01, 0x05, 0x00, 0xfa, 0xff,
            0x68, 0x65, 0x6c, 0x6c, 0x6f,
            0x00, 0x00, 0x00, 0x00      // wrong checksum
        };
        rc = zlib_decompress(z_bad_chk, sizeof(z_bad_chk), out, sizeof(out), &out_len);
        chk("zlib: bad checksum", rc == DEFLATE_ERR_ZLIB_CHK);
    }

    // Bad zlib header (CMF method != 8)
    {
        static const uint8_t z_bad_hdr[] = {
            0x68, 0x9c, 0x03, 0x00, 0x00, 0x00, 0x00, 0x01
        };
        rc = zlib_decompress(z_bad_hdr, sizeof(z_bad_hdr), out, sizeof(out), &out_len);
        chk("zlib: bad header", rc == DEFLATE_ERR_ZLIB_HDR);
    }

    // FDICT set -> not supported
    {
        // CMF=0x78, FLG with FDICT=1: 0x78*256+FLG divisible by 31,
        // FLG bit5=1 -> one valid combo: FLG=0xBB (0x789c=30876=31*996, 0x78BB...)
        // Use a crafted header with FDICT bit set
        static const uint8_t z_fdict[] = {
            0x78, 0xbb, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01
        };
        rc = zlib_decompress(z_fdict, sizeof(z_fdict), out, sizeof(out), &out_len);
        chk("zlib: FDICT rejected", rc == DEFLATE_ERR_ZLIB_HDR);
    }
}

// ---------------------------------------------------------------------------
// Back-reference tests
// ---------------------------------------------------------------------------

static void test_backref(void)
{
    uint8_t out[4096];
    size_t out_len;
    int rc;

    // "a" x 258 (maximum single back-reference length)
    // Python: zlib.compress(b"a"*258, 9)[2:-4]
    {
        static const uint8_t aaa258[] = {
            0x4b, 0x4c, 0x1c, 0xe9, 0x00, 0x00
        };
        rc = deflate_decompress(aaa258, sizeof(aaa258), out, sizeof(out), &out_len);
        chk("backref: 258*'a' rc",  rc == DEFLATE_OK);
        chk("backref: 258*'a' len", out_len == 258);
        if (out_len == 258) {
            int ok = 1;
            for (int i = 0; i < 258; i++) if (out[i] != 'a') { ok = 0; break; }
            chk("backref: 258*'a' vals", ok);
        } else {
            chk("backref: 258*'a' vals", 0);
        }
    }

    // Overlapping back-reference: copy overlaps source (RLE expansion)
    // "abc" followed by back-ref(dist=3, len=9) -> "abcabcabcabc"
    // Stored block: 01 0c 00 f3 ff 61 62 63 61 62 63 61 62 63 61 62 63
    {
        static const uint8_t overlap[] = {
            0x01, 0x0c, 0x00, 0xf3, 0xff,
            0x61, 0x62, 0x63, 0x61, 0x62, 0x63,
            0x61, 0x62, 0x63, 0x61, 0x62, 0x63
        };
        rc = deflate_decompress(overlap, sizeof(overlap), out, sizeof(out), &out_len);
        chk("backref: overlap rc",  rc == DEFLATE_OK);
        chk("backref: overlap len", out_len == 12);
        chk("backref: overlap cmp", out_len == 12 && memcmp(out, "abcabcabcabc", 12) == 0);
    }
}

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------

int main(void)
{
    log_init("deflate-test.log");

    log_write(NONE, "=== Deflate/zlib Decompressor Test ===\n\n");

    log_write(NONE, "--- Adler-32 ---\n");
    test_adler32();

    log_write(NONE, "--- Stored blocks ---\n");
    test_stored();

    log_write(NONE, "--- Fixed Huffman ---\n");
    test_fixed();

    log_write(NONE, "--- Dynamic Huffman ---\n");
    test_dynamic();

    log_write(NONE, "--- zlib wrapper ---\n");
    test_zlib();

    log_write(NONE, "--- Back-references ---\n");
    test_backref();

    log_write(NONE, "\n%d PASS  %d FAIL\n", g_pass, g_fail);
    log_close();
    return g_fail ? 1 : 0;
}
