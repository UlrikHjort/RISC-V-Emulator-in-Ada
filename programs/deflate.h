/* **************************************************************************
 *     RISC-V Emulator - RFC 1951 deflate + RFC 1950 zlib decompressor
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

// deflate.h -- RFC 1951 deflate + RFC 1950 zlib decompressor
// By Ulrik Hørlyk Hjort 2026
#ifndef DEFLATE_H
#define DEFLATE_H

#include <stdint.h>
#include <stddef.h>

// Compute Adler-32 checksum (RFC 1950)
uint32_t adler32(const uint8_t *data, size_t len);

// Raw deflate decompression (RFC 1951, no header/trailer)
// Returns 0 on success, negative error code otherwise.
// *out_len is set to the number of bytes written to out.
int deflate_decompress(const uint8_t *in,  size_t in_len,
                       uint8_t       *out, size_t out_max,
                       size_t        *out_len);

// zlib decompression (RFC 1950): 2-byte header + deflate + 4-byte Adler-32
// Returns 0 on success, negative error code otherwise.
int zlib_decompress(const uint8_t *in,  size_t in_len,
                    uint8_t       *out, size_t out_max,
                    size_t        *out_len);

// Error codes
#define DEFLATE_OK           0
#define DEFLATE_ERR_TRUNC   -1   // input truncated
#define DEFLATE_ERR_OVERFLOW -2  // output buffer full
#define DEFLATE_ERR_BADCODE -3   // invalid Huffman code
#define DEFLATE_ERR_BADBLOCK -4  // bad block type or LEN/NLEN mismatch
#define DEFLATE_ERR_OVERSUBSCRIBED -5
#define DEFLATE_ERR_BACKREF -6   // back-reference before start of output
#define DEFLATE_ERR_ZLIB_HDR -7  // bad zlib header
#define DEFLATE_ERR_ZLIB_CHK -8  // Adler-32 mismatch

#endif
