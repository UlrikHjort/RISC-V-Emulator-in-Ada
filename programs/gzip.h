/* **************************************************************************
 *        RISC-V Emulator - Gzip Compression (RFC 1952) - Interface
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

#ifndef GZIP_H
#define GZIP_H
#include <stdint.h>

/* Compress src into dst in gzip format (RFC 1952).
 * Uses deflate stored blocks -- output is always valid gzip but uncompressed.
 * dst must be large enough: src_len + 18 + ceil(src_len/65535)*5 bytes is safe.
 * Returns number of bytes written to dst, or 0 on error. */
uint32_t gzip_compress(const uint8_t *src, uint32_t src_len,
                       uint8_t *dst, uint32_t dst_cap);

/* Decompress gzip-format src into dst.
 * Verifies magic bytes, CM, CRC-32, and ISIZE trailer fields.
 * Returns number of bytes written to dst, or 0 on error. */
uint32_t gzip_decompress(const uint8_t *src, uint32_t src_len,
                         uint8_t *dst, uint32_t dst_cap);

#endif /* GZIP_H */
