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

// deflate.c -- RFC 1951 deflate + RFC 1950 zlib decompressor
// By Ulrik Hørlyk Hjort 2026
//
// Implements:
//   - Stored blocks (BTYPE=00)
//   - Fixed Huffman (BTYPE=01, RFC 1951 Sec.3.2.6)
//   - Dynamic Huffman (BTYPE=10)
//   - zlib wrapper with Adler-32 verification
//
// Decoder uses the "canonical Huffman, one-bit-at-a-time" approach
// from the puff.c reference implementation.

#include "deflate.h"
#include <stddef.h>

// ---------------------------------------------------------------------------
// Huffman table
// ---------------------------------------------------------------------------

#define MAXBITS   15
#define MAXLCODES 288   // 286 literal/length codes + 2 padding
#define MAXDCODES 30
#define MAXCODES  (MAXLCODES + MAXDCODES)

typedef struct {
    int count[MAXBITS + 1];  // number of symbols with each code length
    int symbol[MAXCODES];    // symbols ordered by (length, canonical order)
} huffman_t;

// Build canonical Huffman table from array of code lengths.
// Returns 0 if complete, >0 if incomplete (unused codes), <0 if oversubscribed.
static int construct(huffman_t *h, const int *lengths, int n)
{
    int sym, len;
    int offs[MAXBITS + 1];

    for (len = 0; len <= MAXBITS; len++) h->count[len] = 0;
    for (sym = 0; sym < n; sym++) {
        if (lengths[sym] > 0 && lengths[sym] <= MAXBITS)
            h->count[lengths[sym]]++;
    }

    // check for oversubscription
    int left = 1;
    for (len = 1; len <= MAXBITS; len++) {
        left = (left << 1) - h->count[len];
        if (left < 0) return DEFLATE_ERR_OVERSUBSCRIBED;
    }

    // compute offsets into symbol[] for each length
    offs[1] = 0;
    for (len = 1; len < MAXBITS; len++)
        offs[len + 1] = offs[len] + h->count[len];

    // fill symbol[] sorted by (length, position in input)
    for (sym = 0; sym < n; sym++) {
        int l = lengths[sym];
        if (l > 0 && l <= MAXBITS)
            h->symbol[offs[l]++] = sym;
    }

    return left;  // 0 = complete, >0 = incomplete
}

// ---------------------------------------------------------------------------
// Bit-stream state
// ---------------------------------------------------------------------------

typedef struct {
    const uint8_t *in;
    size_t         in_pos;
    size_t         in_len;
    uint8_t       *out;
    size_t         out_pos;
    size_t         out_max;
    unsigned       bit_buf;
    int            bit_cnt;
    int            err;
} inf_t;

static int read_bit(inf_t *s)
{
    if (s->bit_cnt == 0) {
        if (s->in_pos >= s->in_len) { s->err = DEFLATE_ERR_TRUNC; return 0; }
        s->bit_buf = s->in[s->in_pos++];
        s->bit_cnt = 8;
    }
    int b = (int)(s->bit_buf & 1u);
    s->bit_buf >>= 1;
    s->bit_cnt--;
    return b;
}

// Read n bits (0-16), LSB first
static unsigned bits(inf_t *s, int n)
{
    unsigned val = 0;
    for (int i = 0; i < n; i++)
        val |= (unsigned)read_bit(s) << i;
    return val;
}

// Byte-align and read one byte
static unsigned read_byte(inf_t *s)
{
    s->bit_buf = 0;
    s->bit_cnt = 0;
    if (s->in_pos >= s->in_len) { s->err = DEFLATE_ERR_TRUNC; return 0; }
    return s->in[s->in_pos++];
}

// Emit one output byte
static void emit(inf_t *s, uint8_t b)
{
    if (s->out_pos >= s->out_max) { s->err = DEFLATE_ERR_OVERFLOW; return; }
    s->out[s->out_pos++] = b;
}

// ---------------------------------------------------------------------------
// Huffman decode
// ---------------------------------------------------------------------------

// Decode one symbol from the bit stream using table h.
// Reads bits one at a time, O(max_bits).
static int decode(inf_t *s, const huffman_t *h)
{
    int code = 0, first = 0, index = 0;
    for (int len = 1; len <= MAXBITS; len++) {
        code = (code << 1) | read_bit(s);
        int count = h->count[len];
        if (code - count < first) {
            // found: symbol is at index + (code - first)
            return h->symbol[index + (code - first)];
        }
        index += count;
        first  = (first + count) << 1;
    }
    s->err = DEFLATE_ERR_BADCODE;
    return -1;
}

// ---------------------------------------------------------------------------
// Length / distance tables (RFC 1951 Sec.3.2.5)
// ---------------------------------------------------------------------------

static const int lens[29] = {
    3,4,5,6,7,8,9,10, 11,13,15,17, 19,23,27,31,
    35,43,51,59, 67,83,99,115, 131,163,195,227, 258
};
static const int lext[29] = {
    0,0,0,0,0,0,0,0, 1,1,1,1, 2,2,2,2, 3,3,3,3, 4,4,4,4, 5,5,5,5, 0
};
static const int dists[30] = {
    1,2,3,4, 5,7, 9,13, 17,25, 33,49, 65,97, 129,193,
    257,385, 513,769, 1025,1537, 2049,3073, 4097,6145,
    8193,12289, 16385,24577
};
static const int dext[30] = {
    0,0,0,0, 1,1, 2,2, 3,3, 4,4, 5,5, 6,6, 7,7, 8,8, 9,9, 10,10, 11,11, 12,12, 13,13
};

// ---------------------------------------------------------------------------
// Block decoders
// ---------------------------------------------------------------------------

static void inflate_codes(inf_t *s, const huffman_t *lc, const huffman_t *dc)
{
    while (!s->err) {
        int sym = decode(s, lc);
        if (s->err) return;

        if (sym < 256) {
            emit(s, (uint8_t)sym);
        } else if (sym == 256) {
            return;  // end of block
        } else {
            // length/distance back-reference
            int li = sym - 257;
            if (li < 0 || li >= 29) { s->err = DEFLATE_ERR_BADCODE; return; }
            int len  = lens[li]  + (int)bits(s, lext[li]);
            int di   = decode(s, dc);
            if (s->err) return;
            if (di < 0 || di >= 30) { s->err = DEFLATE_ERR_BADCODE; return; }
            int dist = dists[di] + (int)bits(s, dext[di]);
            if ((int)s->out_pos < dist) { s->err = DEFLATE_ERR_BACKREF; return; }
            while (len-- > 0 && !s->err)
                emit(s, s->out[s->out_pos - dist]);
        }
    }
}

static void inflate_stored(inf_t *s)
{
    // discard partial byte, read LEN / NLEN
    unsigned len  = (unsigned)read_byte(s) | ((unsigned)read_byte(s) << 8);
    unsigned nlen = (unsigned)read_byte(s) | ((unsigned)read_byte(s) << 8);
    if (((len ^ nlen) & 0xFFFF) != 0xFFFF) { s->err = DEFLATE_ERR_BADBLOCK; return; }
    while (len-- > 0 && !s->err)
        emit(s, (uint8_t)read_byte(s));
}

static void inflate_fixed(inf_t *s)
{
    // Fixed Huffman code lengths per RFC 1951 Sec.3.2.6
    int lengths[MAXLCODES + MAXDCODES];
    int sym;
    huffman_t lc, dc;

    for (sym =   0; sym <= 143; sym++) lengths[sym] = 8;
    for (sym = 144; sym <= 255; sym++) lengths[sym] = 9;
    for (sym = 256; sym <= 279; sym++) lengths[sym] = 7;
    for (sym = 280; sym <= 287; sym++) lengths[sym] = 8;
    construct(&lc, lengths, MAXLCODES);

    for (sym = 0; sym < MAXDCODES; sym++) lengths[sym] = 5;
    construct(&dc, lengths, MAXDCODES);

    inflate_codes(s, &lc, &dc);
}

static void inflate_dynamic(inf_t *s)
{
    int nlen  = (int)bits(s, 5) + 257;  // # literal/length code lengths
    int ndist = (int)bits(s, 5) + 1;    // # distance code lengths
    int ncode = (int)bits(s, 4) + 4;    // # code-length-alphabet lengths

    // Code-length alphabet order (RFC 1951 Sec.3.2.7)
    static const int order[19] = {
        16,17,18, 0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15
    };

    int cl_lengths[19];
    int i;
    for (i = 0; i < 19; i++) cl_lengths[i] = 0;
    for (i = 0; i < ncode; i++) cl_lengths[order[i]] = (int)bits(s, 3);

    huffman_t cl;
    construct(&cl, cl_lengths, 19);

    // Decode literal/length + distance code lengths
    int all_lengths[MAXLCODES + MAXDCODES];
    int total = nlen + ndist;
    i = 0;
    while (i < total && !s->err) {
        int sym = decode(s, &cl);
        if (s->err) return;
        if (sym < 16) {
            all_lengths[i++] = sym;
        } else if (sym == 16) {
            if (i == 0) { s->err = DEFLATE_ERR_BADCODE; return; }
            int rep = (int)bits(s, 2) + 3;
            int prev = all_lengths[i - 1];
            while (rep-- > 0 && i < total) all_lengths[i++] = prev;
        } else if (sym == 17) {
            int rep = (int)bits(s, 3) + 3;
            while (rep-- > 0 && i < total) all_lengths[i++] = 0;
        } else {  // sym == 18
            int rep = (int)bits(s, 7) + 11;
            while (rep-- > 0 && i < total) all_lengths[i++] = 0;
        }
    }

    huffman_t lc, dc;
    construct(&lc, all_lengths,        nlen);
    construct(&dc, all_lengths + nlen, ndist);
    inflate_codes(s, &lc, &dc);
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

int deflate_decompress(const uint8_t *in,  size_t in_len,
                       uint8_t       *out, size_t out_max,
                       size_t        *out_len)
{
    inf_t s;
    s.in      = in;
    s.in_pos  = 0;
    s.in_len  = in_len;
    s.out     = out;
    s.out_pos = 0;
    s.out_max = out_max;
    s.bit_buf = 0;
    s.bit_cnt = 0;
    s.err     = 0;

    int last;
    do {
        last = (int)bits(&s, 1);
        int type = (int)bits(&s, 2);
        if (s.err) return s.err;

        if      (type == 0) inflate_stored(&s);
        else if (type == 1) inflate_fixed(&s);
        else if (type == 2) inflate_dynamic(&s);
        else    { s.err = DEFLATE_ERR_BADBLOCK; }

        if (s.err) return s.err;
    } while (!last);

    if (out_len) *out_len = s.out_pos;
    return DEFLATE_OK;
}

uint32_t adler32(const uint8_t *data, size_t len)
{
    uint32_t s1 = 1, s2 = 0;
    for (size_t i = 0; i < len; i++) {
        s1 = (s1 + data[i]) % 65521u;
        s2 = (s2 + s1)      % 65521u;
    }
    return (s2 << 16) | s1;
}

int zlib_decompress(const uint8_t *in,  size_t in_len,
                    uint8_t       *out, size_t out_max,
                    size_t        *out_len)
{
    // Need at least 2-byte header + 4-byte trailer
    if (in_len < 6) return DEFLATE_ERR_ZLIB_HDR;

    // CMF / FLG check: (CMF*256 + FLG) % 31 == 0, FDICT must be 0
    uint8_t cmf = in[0], flg = in[1];
    if ((cmf & 0x0F) != 8)           return DEFLATE_ERR_ZLIB_HDR;  // not deflate
    if ((((unsigned)cmf << 8) + flg) % 31 != 0) return DEFLATE_ERR_ZLIB_HDR;
    if (flg & 0x20)                  return DEFLATE_ERR_ZLIB_HDR;  // FDICT not supported

    int rc = deflate_decompress(in + 2, in_len - 6, out, out_max, out_len);
    if (rc != DEFLATE_OK) return rc;

    // Verify Adler-32 (big-endian, last 4 bytes)
    size_t n = in_len;
    uint32_t expected = ((uint32_t)in[n-4] << 24) | ((uint32_t)in[n-3] << 16) |
                        ((uint32_t)in[n-2] <<  8) |  (uint32_t)in[n-1];
    uint32_t actual   = adler32(out, *out_len);
    if (actual != expected) return DEFLATE_ERR_ZLIB_CHK;

    return DEFLATE_OK;
}
