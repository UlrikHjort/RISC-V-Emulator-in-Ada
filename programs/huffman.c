/* **************************************************************************
 *         RISC-V Emulator - Huffman encode/decode round-trip test
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

// huffman.c -- Huffman encode/decode round-trip test.
//
// Tests:
//   - Build Huffman tree from frequency table
//   - Generate canonical codes from tree
//   - Bit-level encode/decode round-trip
//   - Multiple test messages with known properties
//
// Implementation uses a simple priority queue (min-heap) built from
// a fixed-size node pool allocated on the stack (no malloc needed).
//
// Build: cd programs && make run-huffman
// By Ulrik Hørlyk Hjort 2026

#include <stdint.h>
#include "log.h"

void putchar(char c);
static void uart_puts(const char *s) {
    while (*s) { if (*s == '\n') putchar('\r'); putchar(*s++); }
}

static int g_pass = 0, g_fail = 0;

static void checkb(const char *label, int got, int expected) {
    if (got == expected) {
        log_write(NONE, "  PASS  %s\n", label); g_pass++;
    } else {
        log_write(NONE, "  FAIL  %s: got %d  exp %d\n", label, got, expected);
        g_fail++;
    }
}

// -- Huffman implementation ------------------------------------------------

#define MAX_SYMBOLS  256
#define MAX_NODES    (MAX_SYMBOLS * 2)
#define MAX_CODELEN  32    // max bits per code
#define MAX_BITS     4096  // max encoded bits

typedef struct {
    uint32_t freq;
    int      left, right;  // -1 = leaf; otherwise index into nodes[]
    int      symbol;       // valid only for leaves
} HNode;

typedef struct {
    HNode nodes[MAX_NODES];
    int   n;          // number of nodes in use
    int   heap[MAX_NODES];  // min-heap of node indices, ordered by freq
    int   heap_size;
} HTree;

// Heap operations (min-heap by nodes[].freq)
static void heap_push(HTree *t, int idx) {
    int i = t->heap_size++;
    t->heap[i] = idx;
    while (i > 0) {
        int parent = (i - 1) / 2;
        if (t->nodes[t->heap[parent]].freq <= t->nodes[t->heap[i]].freq) break;
        int tmp = t->heap[parent]; t->heap[parent] = t->heap[i]; t->heap[i] = tmp;
        i = parent;
    }
}

static int heap_pop(HTree *t) {
    int ret = t->heap[0];
    t->heap[0] = t->heap[--t->heap_size];
    int i = 0;
    while (1) {
        int l = 2*i+1, r = 2*i+2, m = i;
        if (l < t->heap_size && t->nodes[t->heap[l]].freq < t->nodes[t->heap[m]].freq) m = l;
        if (r < t->heap_size && t->nodes[t->heap[r]].freq < t->nodes[t->heap[m]].freq) m = r;
        if (m == i) break;
        int tmp = t->heap[i]; t->heap[i] = t->heap[m]; t->heap[m] = tmp;
        i = m;
    }
    return ret;
}

// Code table entry
typedef struct {
    uint32_t bits;    // code bits (LSB-first)
    int      length;  // code length in bits (0 = unused symbol)
} HCode;

// Build Huffman tree and populate code table.
// freq[s] = frequency of symbol s (0 means unused).
// Returns root node index, or -1 if no symbols.
static int build_tree(HTree *t, const uint32_t freq[MAX_SYMBOLS]) {
    t->n = 0;
    t->heap_size = 0;

    // Create leaf nodes for all symbols with freq > 0
    for (int s = 0; s < MAX_SYMBOLS; s++) {
        if (freq[s] > 0) {
            t->nodes[t->n] = (HNode){freq[s], -1, -1, s};
            heap_push(t, t->n++);
        }
    }
    if (t->heap_size == 0) return -1;

    // Build tree by merging two lowest-frequency nodes
    while (t->heap_size > 1) {
        int a = heap_pop(t);
        int b = heap_pop(t);
        t->nodes[t->n] = (HNode){
            t->nodes[a].freq + t->nodes[b].freq,
            a, b, -1
        };
        heap_push(t, t->n++);
    }
    return heap_pop(t);
}

// Recursively assign codes (DFS traversal)
static void assign_codes(const HTree *t, int node, uint32_t bits, int depth,
                          HCode codes[MAX_SYMBOLS]) {
    if (t->nodes[node].left == -1) {
        // Leaf -- single-symbol tree (depth==0) gets 1-bit code '0'
        codes[t->nodes[node].symbol].bits   = bits;
        codes[t->nodes[node].symbol].length = depth > 0 ? depth : 1;
    } else {
        assign_codes(t, t->nodes[node].left,  bits,           depth + 1, codes);
        assign_codes(t, t->nodes[node].right, bits | (1u << depth), depth + 1, codes);
    }
}

// Encode src[0..n-1] into bits[]. Returns total bit count, or -1 on overflow.
static int encode(const HCode codes[MAX_SYMBOLS],
                  const uint8_t *src, int n,
                  uint8_t bits[MAX_BITS/8]) {
    int bit_pos = 0;
    for (int i = 0; i < n; i++) {
        const HCode *c = &codes[(uint8_t)src[i]];
        if (c->length == 0) return -1;  // unused symbol
        for (int b = 0; b < c->length; b++) {
            if (bit_pos >= MAX_BITS) return -1;
            if ((c->bits >> b) & 1)
                bits[bit_pos / 8] |= (1u << (bit_pos % 8));
            else
                bits[bit_pos / 8] &= ~(1u << (bit_pos % 8));
            bit_pos++;
        }
    }
    return bit_pos;
}

// Decode n_bits bits from bits[] using the tree rooted at root.
// Output to dst[]. Returns number of decoded symbols, or -1 on error.
static int decode(const HTree *t, int root,
                  const uint8_t *bits, int n_bits,
                  uint8_t *dst, int max_out) {
    int node = root;
    int bit_pos = 0;
    int out = 0;
    // Single-symbol tree: root is a leaf; one bit encodes one symbol
    if (t->nodes[root].left == -1) {
        while (bit_pos < n_bits && out < max_out) {
            dst[out++] = (uint8_t)t->nodes[root].symbol;
            bit_pos++;
        }
        return out;
    }
    while (bit_pos < n_bits) {
        if (t->nodes[node].left == -1) {
            // Leaf: emit symbol
            if (out >= max_out) return -1;
            dst[out++] = (uint8_t)t->nodes[node].symbol;
            node = root;
        }
        int b = (bits[bit_pos / 8] >> (bit_pos % 8)) & 1;
        node = b ? t->nodes[node].right : t->nodes[node].left;
        bit_pos++;
    }
    // Flush last symbol if we ended on a leaf
    if (t->nodes[node].left == -1) {
        if (out >= max_out) return -1;
        dst[out++] = (uint8_t)t->nodes[node].symbol;
    }
    return out;
}

// -- Tests -----------------------------------------------------------------

static HTree g_tree;

// Round-trip test for a given message
static void roundtrip(const char *label, const uint8_t *msg, int n) {
    uint32_t freq[MAX_SYMBOLS] = {0};
    for (int i = 0; i < n; i++) freq[msg[i]]++;

    int root = build_tree(&g_tree, freq);
    if (root < 0) {
        log_write(NONE, "  FAIL  %s: build_tree failed\n", label);
        g_fail++;
        return;
    }

    HCode codes[MAX_SYMBOLS] = {{0, 0}};
    assign_codes(&g_tree, root, 0, 0, codes);

    uint8_t bitbuf[MAX_BITS/8] = {0};
    int bit_count = encode(codes, msg, n, bitbuf);
    if (bit_count < 0) {
        log_write(NONE, "  FAIL  %s: encode failed\n", label);
        g_fail++;
        return;
    }

    uint8_t dec[512] = {0};
    int dec_n = decode(&g_tree, root, bitbuf, bit_count, dec, 512);
    if (dec_n != n) {
        log_write(NONE, "  FAIL  %s: decode gave %d bytes, expected %d\n",
                  label, dec_n, n);
        g_fail++;
        return;
    }
    for (int i = 0; i < n; i++) {
        if (dec[i] != msg[i]) {
            log_write(NONE, "  FAIL  %s: mismatch at byte %d\n", label, i);
            g_fail++;
            return;
        }
    }
    log_write(NONE, "  PASS  %s (n=%d bits=%d)\n", label, n, bit_count);
    g_pass++;
}

static void test_roundtrips(void) {
    log_write(NONE, "\n=== Huffman round-trip ===\n");

    // Simple repeated byte (1 symbol -> degenerate tree)
    static const uint8_t aaa[] = {0x41, 0x41, 0x41, 0x41, 0x41};
    roundtrip("'AAAAA' (1 symbol)", aaa, 5);

    // Two symbols, equal frequency
    static const uint8_t ab[] = {0x41, 0x42, 0x41, 0x42, 0x41, 0x42};
    roundtrip("'ABABAB' (2 symbols)", ab, 6);

    // ASCII text
    static const uint8_t hello[] = "Hello, World!";
    roundtrip("'Hello, World!'", hello, 13);

    // Text with Zipfian distribution (many repeated chars)
    static const uint8_t text[] =
        "the quick brown fox jumps over the lazy dog "
        "the fox the fox the fox";
    roundtrip("pangram with repeats", text, 68);

    // All-distinct bytes (worst case for compression)
    static const uint8_t distinct[] = {
        0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07
    };
    roundtrip("8 distinct bytes", distinct, 8);

    // Binary data with skewed distribution
    static const uint8_t binary[64] = {
        0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
        0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
        0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01,
        0x02,0x02,0x02,0x02,0x03,0x03,0x04,0x05,
        0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,
        0xFE,0xFE,0xFE,0xFE,0xFD,0xFD,0xFC,0xFB,
        0x10,0x20,0x30,0x40,0x50,0x60,0x70,0x80,
        0x11,0x22,0x33,0x44,0x55,0x66,0x77,0x88
    };
    roundtrip("64-byte skewed binary", binary, 64);
}

static void test_code_properties(void) {
    log_write(NONE, "\n=== Code properties ===\n");

    // Symmetric input: 2 symbols with frequencies 1:2
    uint32_t freq[MAX_SYMBOLS] = {0};
    freq['A'] = 1;
    freq['B'] = 2;
    int root = build_tree(&g_tree, freq);
    HCode codes[MAX_SYMBOLS] = {{0, 0}};
    assign_codes(&g_tree, root, 0, 0, codes);

    // Both symbols must have length 1 or 2
    checkb("2-symbol: A has code", codes['A'].length > 0, 1);
    checkb("2-symbol: B has code", codes['B'].length > 0, 1);
    // B (higher freq) should have shorter code
    checkb("2-symbol: B code <= A code length",
           codes['B'].length <= codes['A'].length, 1);

    // Single symbol: must be coded
    freq['A'] = 0; freq['B'] = 0;
    freq['X'] = 5;
    root = build_tree(&g_tree, freq);
    HCode codes2[MAX_SYMBOLS] = {{0, 0}};
    assign_codes(&g_tree, root, 0, 0, codes2);
    checkb("1-symbol: X has code", codes2['X'].length > 0, 1);
    checkb("1-symbol: X code length=1", codes2['X'].length, 1);
    // Single-symbol tree uses a 1-bit code ('0') for the only symbol
}

// -- Main ------------------------------------------------------------------

int main(void) {
    uart_puts("=== Huffman Test ===\n");
    if (log_init("huffman.log") != 0) {
        uart_puts("ERROR: log_init failed\n"); return 1;
    }

    log_write(NONE, "=== Huffman Encode/Decode Test ===\n");

    test_roundtrips();
    test_code_properties();

    log_write(NONE, "\n=== Summary ===\n");
    log_write(NONE, "  PASS: %d\n", g_pass);
    log_write(NONE, "  FAIL: %d\n", g_fail);
    log_write(NONE, "  %s\n", g_fail == 0 ? "ALL TESTS PASSED" : "SOME TESTS FAILED");

    log_close();
    uart_puts(g_fail == 0 ? "ALL PASSED\n" : "SOME FAILED\n");
    return g_fail;
}
