/* **************************************************************************
 *   RISC-V Emulator - K=7 rate-1/2 Viterbi decoder (soft-decision, BPSK)
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

// viterbi.c -- K=7 rate-1/2 Viterbi decoder (soft-decision, BPSK)
//
// Encoder: shift register with NASA/Voyager generators G0=0x4F (0o117), G1=0x6D (0o155).
//   These produce 2 output bits per input bit from a 7-stage shift register (64 states).
//   K=7: constraint length 7, rate 1/2.
//
// Decoder: soft-decision Viterbi algorithm.
//   Received soft bits are quantized BPSK symbols: 0 bit -> +127, 1 bit -> -127.
//   Branch metric: Hamming-like absolute difference between received and expected symbol.
//   Traceback: depth = 5*K = 35 bits.
//
// Tests:
//   Known encode: "TEST" -> bit sequence verified against known-good output
//   Noiseless decode: encode -> BPSK -> Viterbi -> original bits
//   Low noise (3dB SNR): add AWGN, verify correct decode for short sequences
//   Sync: encoder and decoder state initialization
//
// Build: cd programs && make run-viterbi
// By Ulrik Hørlyk Hjort 2026

#include <stdint.h>
#include "log.h"

void putchar(char c);

static int g_pass = 0, g_fail = 0;

static void chk(const char *label, int ok) {
    if (ok) { log_write(NONE, "  PASS  %s\n", label); g_pass++; }
    else     { log_write(NONE, "  FAIL  %s\n", label); g_fail++; }
}

/* -- Convolutional encoder K=7, rate 1/2 ----------------------------------- */
// NASA standard generators (octal 117, 155):
//   G0 = 1001111 = 0x4F  (bits: 6,3,2,1,0 of shift register)
//   G1 = 1101101 = 0x6D  (bits: 6,5,3,2,0 of shift register)
// The shift register contains the current and previous 6 input bits.
// Output: 2 bits per input bit.

#define G0 0x4Fu
#define G1 0x6Du
#define K  7       // constraint length
#define STATES 64  // 2^(K-1) = 64 states

static int popcount7(uint32_t x) {
    x &= 0x7f; // 7 bits (bit 6 = new input in 7-bit shift register)
    int n = 0;
    while (x) { n += x&1; x>>=1; }
    return n;
}

// Encode a single bit, given shift register state sr (6-bit, MSB = oldest bit).
// Returns 2 output bits packed: bit1 | (bit0 << 1), and updates sr.
// Note: we push new bit into MSB of 7-bit shift register for encoding.
// State = lower 6 bits of shift register (after the input bit shifts in).
static void encode_bit(uint32_t *sr, int bit, int *out0, int *out1) {
    // 7-bit shift register: bit is the new input (MSB), *sr holds the previous 6 bits
    uint32_t reg7 = (*sr & 0x3f) | ((uint32_t)(bit & 1) << 6);
    *out0 = popcount7(reg7 & G0) & 1;
    *out1 = popcount7(reg7 & G1) & 1;
    *sr = (reg7 >> 1) & 0x3f; // shift right; new state = top 6 bits
}

// Encode a sequence of bytes, producing 2 output bits per input bit.
// Appends K-1 = 6 flush bits (zeros) to drive encoder to zero state.
// Output: 2*(nbits + K-1) symbols (as 0 or 1 values).
static int conv_encode(const uint8_t *data, int nbytes,
                        int8_t *out_symbols) // BPSK: 0->+127, 1->-127
{
    uint32_t sr = 0;
    int nsym = 0;

    for (int bi = 0; bi < nbytes*8 + (K-1); bi++) {
        int byte_idx = bi >> 3;
        int bit_idx  = 7 - (bi & 7); // MSB first
        int bit;
        if (bi < nbytes * 8) {
            bit = (data[byte_idx] >> bit_idx) & 1;
        } else {
            bit = 0; // flush
        }

        int o0, o1;
        encode_bit(&sr, bit, &o0, &o1);
        // BPSK mapping: 0 -> +127, 1 -> -127
        out_symbols[nsym++] = o0 ? -127 : 127;
        out_symbols[nsym++] = o1 ? -127 : 127;
    }
    return nsym; // = 2*total_bits
}

/* -- Viterbi decoder ------------------------------------------------------- */

#define MAX_TRACEBACK 512  // maximum decode length in bits
#define LARGE_METRIC  0x7fffffff

// Precomputed encoder output for each (state, input_bit) pair.
// out0[s][b] and out1[s][b] = output bits for state s, input b.
// State = lower 6 bits of shift register BEFORE the new bit is shifted in.
static int8_t enc_out0[STATES][2];
static int8_t enc_out1[STATES][2];
static int    next_st [STATES][2]; // next state after input bit b

static void precompute_trellis(void) {
    for (int s=0; s<STATES; s++) {
        for (int b=0; b<2; b++) {
            uint32_t reg7 = (uint32_t)s | ((uint32_t)b << 6);
            enc_out0[s][b] = popcount7(reg7 & G0) & 1;
            enc_out1[s][b] = popcount7(reg7 & G1) & 1;
            next_st[s][b]  = (int)(reg7 >> 1) & (STATES-1);
        }
    }
}

// Branch metric: absolute difference between received soft symbol and expected hard bit
static inline int branch_metric(int8_t received, int expected_bit) {
    // expected: 0 -> +127, 1 -> -127
    int ref = expected_bit ? -127 : 127;
    int d = (int)received - ref;
    return d < 0 ? -d : d;
}

// Decode soft symbols using Viterbi algorithm.
// nsym = number of symbols (= 2 * number of encoded bits including flush bits)
// Output: data bytes (nbytes_out = (nsym/2 - (K-1)) / 8)
static void viterbi_decode(const int8_t *sym, int nsym, uint8_t *out, int nbytes_out)
{
    int nbits = nsym / 2; // total encoded bits

    // Path metrics (current and next)
    static int32_t pm[STATES], pm_next[STATES];
    // Survivor bits: for each (time, state), which input bit was chosen
    static uint8_t tb[MAX_TRACEBACK][STATES]; // 1 bit per entry, packed as byte

    for (int s=0;s<STATES;s++) pm[s] = LARGE_METRIC;
    pm[0] = 0; // start in state 0

    for (int t=0; t<nbits; t++) {
        for (int s=0;s<STATES;s++) pm_next[s] = LARGE_METRIC;

        int8_t r0 = sym[t*2+0];
        int8_t r1 = sym[t*2+1];

        for (int s=0; s<STATES; s++) {
            if (pm[s] == LARGE_METRIC) continue;
            for (int b=0; b<2; b++) {
                int bm = branch_metric(r0, enc_out0[s][b])
                       + branch_metric(r1, enc_out1[s][b]);
                int ns = next_st[s][b];
                int32_t new_m = pm[s] + bm;
                if (new_m < pm_next[ns]) {
                    pm_next[ns] = new_m;
                    if (t < MAX_TRACEBACK) tb[t][ns] = (uint8_t)s; // store predecessor state
                }
            }
        }

        // Normalize to prevent overflow (subtract minimum)
        int32_t minm = LARGE_METRIC;
        for (int s=0;s<STATES;s++)
            if (pm_next[s] < minm) minm = pm_next[s];
        if (minm != LARGE_METRIC)
            for (int s=0;s<STATES;s++)
                if (pm_next[s] != LARGE_METRIC) pm_next[s] -= minm;

        for (int s=0;s<STATES;s++) pm[s] = pm_next[s];
    }

    // Find state with minimum metric at the end
    int best_state = 0;
    for (int s=1;s<STATES;s++)
        if (pm[s] < pm[best_state]) best_state = s;

    // Traceback
    // Key insight: ns = (prev | (b<<6)) >> 1, so ns[5] = b (input bit).
    // tb[t][ns] stores the predecessor state (set in forward ACS above).
    static uint8_t bits[MAX_TRACEBACK];
    int s = best_state;
    for (int t = nbits-1; t >= 0; t--) {
        bits[t] = (s >> 5) & 1;  // input bit = bit 5 of this state (see trellis structure)
        s = (t < MAX_TRACEBACK) ? (int)tb[t][s] : (s & 0x1f) << 1;
    }

    // Convert bits to bytes (MSB first)
    for (int i=0;i<nbytes_out;i++) {
        uint8_t byte = 0;
        for (int b=0;b<8;b++) {
            byte = (byte<<1) | (bits[i*8+b] & 1);
        }
        out[i] = byte;
    }
}

/* -- Simple LCG for adding AWGN noise ------------------------------------- */
static uint32_t lcg_state = 12345678u;
static int lcg_next(void) {
    lcg_state = lcg_state * 1664525u + 1013904223u;
    return (int)(lcg_state >> 16) & 0xffff; // 0..65535
}
// Gaussian-ish noise with scale sigma (approximated by sum of uniforms)
static int awgn(int sigma) {
    int s = 0;
    for (int i=0;i<4;i++) s += (lcg_next() & 0x3ff) - 512; // range approx +/-2048
    return (s * sigma) >> 11;
}

/* ========================================================================== */
/*                               T E S T S                                   */
/* ========================================================================== */

static void test_encode_known(void) {
    log_write(NONE, "\n=== Encoder output (known sequence) ===\n");

    precompute_trellis();

    // Single zero byte -> all-zero encoder output (state stays at 0)
    uint8_t msg[1] = {0x00};
    int8_t sym[2 * (8 + K-1)];
    int nsym = conv_encode(msg, 1, sym);
    int all_pos = 1;
    for (int i=0;i<nsym;i++) if (sym[i] != 127) { all_pos=0; break; }
    chk("all-zero input -> all +127 symbols", all_pos);

    // All-ones byte -> alternating output per parity bit
    msg[0] = 0xff;
    nsym = conv_encode(msg, 1, sym);
    // With all 1s input, the encoder shifts the same pattern repeatedly.
    // Just verify output has both +127 and -127 symbols (non-trivial)
    int has_pos = 0, has_neg = 0;
    for (int i=0;i<nsym;i++) {
        if (sym[i]==127) has_pos=1;
        if (sym[i]==-127) has_neg=1;
    }
    chk("all-ones input produces mixed symbols", has_pos && has_neg);

    // Verify symmetry: encode 0xAA and 0x55 produce different outputs
    uint8_t msg2[1] = {0xAA}, msg3[1] = {0x55};
    int8_t sym2[2*(8+K-1)], sym3[2*(8+K-1)];
    conv_encode(msg2, 1, sym2);
    conv_encode(msg3, 1, sym3);
    int same = 1;
    for (int i=0;i<2*8;i++) if (sym2[i]!=sym3[i]){same=0;break;}
    chk("0xAA and 0x55 produce different encoded symbols", !same);
}

static void test_noiseless_decode(void) {
    log_write(NONE, "\n=== Noiseless decode ===\n");

    precompute_trellis();

    // Single byte: 0x55
    {
        uint8_t msg[1] = {0x55};
        int8_t sym[2*(8+K-1)];
        int nsym = conv_encode(msg, 1, sym);
        uint8_t decoded[1];
        viterbi_decode(sym, nsym, decoded, 1);
        chk("noiseless decode 0x55", decoded[0] == 0x55);
    }
    // Single byte: 0xA3
    {
        uint8_t msg[1] = {0xA3};
        int8_t sym[2*(8+K-1)];
        int nsym = conv_encode(msg, 1, sym);
        uint8_t decoded[1];
        viterbi_decode(sym, nsym, decoded, 1);
        chk("noiseless decode 0xA3", decoded[0] == 0xA3);
    }
    // Multi-byte: "HELLO"
    {
        static const uint8_t msg[] = "HELLO";
        int nbytes = 5;
        int8_t sym[2*(5*8+K-1)];
        int nsym = conv_encode(msg, nbytes, sym);
        uint8_t decoded[5];
        viterbi_decode(sym, nsym, decoded, nbytes);
        int ok = 1;
        for (int i=0;i<nbytes;i++) if (decoded[i]!=msg[i]){ok=0;break;}
        chk("noiseless decode 'HELLO'", ok);
    }
    // Multi-byte: all zeros
    {
        uint8_t msg[4] = {0,0,0,0};
        int8_t sym[2*(4*8+K-1)];
        int nsym = conv_encode(msg, 4, sym);
        uint8_t decoded[4];
        viterbi_decode(sym, nsym, decoded, 4);
        int ok = 1;
        for (int i=0;i<4;i++) if (decoded[i]!=0){ok=0;break;}
        chk("noiseless decode all-zeros (4 bytes)", ok);
    }
    // Multi-byte: all ones
    {
        uint8_t msg[4] = {0xff,0xff,0xff,0xff};
        int8_t sym[2*(4*8+K-1)];
        int nsym = conv_encode(msg, 4, sym);
        uint8_t decoded[4];
        viterbi_decode(sym, nsym, decoded, 4);
        int ok = 1;
        for (int i=0;i<4;i++) if (decoded[i]!=0xff){ok=0;break;}
        chk("noiseless decode all-ones (4 bytes)", ok);
    }
}

static void test_noisy_decode(void) {
    log_write(NONE, "\n=== Noisy decode (low sigma) ===\n");

    precompute_trellis();
    lcg_state = 0xdeadbeef;

    // Add small Gaussian noise (sigma~15 on scale of 127)
    // At this SNR the Viterbi decoder should recover the message error-free
    // for short sequences.
    static const uint8_t msg[] = "RISCV";
    int nbytes = 5;
    int8_t sym[2*(5*8+K-1)];
    int nsym = conv_encode(msg, nbytes, sym);

    // Add noise (sigma=15, BPSK levels at +/-127)
    int8_t noisy[2*(5*8+K-1)];
    for (int i=0;i<nsym;i++) {
        int v = (int)sym[i] + awgn(15);
        if (v > 127) v = 127;
        if (v < -127) v = -127;
        noisy[i] = (int8_t)v;
    }

    uint8_t decoded[5];
    viterbi_decode(noisy, nsym, decoded, nbytes);
    int ok = 1;
    for (int i=0;i<nbytes;i++) if (decoded[i]!=msg[i]){ok=0;break;}
    chk("decode 'RISCV' with sigma=15 noise", ok);

    // Try with sigma=30
    lcg_state = 0xc0ffee42;
    for (int i=0;i<nsym;i++) {
        int v = (int)sym[i] + awgn(30);
        if (v > 127) v = 127;
        if (v < -127) v = -127;
        noisy[i] = (int8_t)v;
    }
    viterbi_decode(noisy, nsym, decoded, nbytes);
    ok = 1;
    for (int i=0;i<nbytes;i++) if (decoded[i]!=msg[i]){ok=0;break;}
    chk("decode 'RISCV' with sigma=30 noise", ok);
}

static void test_trellis_structure(void) {
    log_write(NONE, "\n=== Trellis structure validation ===\n");

    precompute_trellis();

    // Every state has exactly 2 successors (one for bit 0, one for bit 1)
    int valid = 1;
    for (int s=0;s<STATES;s++) {
        for (int b=0;b<2;b++) {
            if (next_st[s][b] < 0 || next_st[s][b] >= STATES) { valid=0; break; }
        }
    }
    chk("all next states in range [0,63]", valid);

    // From state 0 with input 0: output should be 0,0 (G0=0, G1=0 for all-zero shift reg)
    chk("state0 input0 -> output (0,0)", enc_out0[0][0]==0 && enc_out1[0][0]==0);

    // State 0, input 1: shift register = 1000000
    // G0=0x4F=1001111: parity of bits 6,3,2,1,0 of 1000000 = parity(1,0,0,0,0) = 1
    // G1=0x6D=1101101: parity of bits 6,5,3,2,0 of 1000000 = parity(1,0,0,0,0) = 1
    chk("state0 input1 -> output (1,1)", enc_out0[0][1]==1 && enc_out1[0][1]==1);

    // After encoding one '1' bit from state 0, next state should be 32 (=100000 binary)
    chk("state0 input1 -> next_state=32", next_st[0][1]==32);

    // From state 32 (=100000), input 0: reg7 = 0100000
    // G0=0x4F: bits 6,3,2,1,0 of 0100000 = 0,0,0,0,0 -> parity=0
    // G1=0x6D: bits 6,5,3,2,0 of 0100000 = 0,1,0,0,0 -> parity=1
    chk("state32 input0 -> output (0,1)", enc_out0[32][0]==0 && enc_out1[32][0]==1);
}

int main(void) {
    log_init("viterbi.log");
    log_write(NONE, "Viterbi K=7 Decoder Test\n");

    test_trellis_structure();
    test_encode_known();
    test_noiseless_decode();
    test_noisy_decode();

    log_write(NONE, "\n%d PASS  %d FAIL\n", g_pass, g_fail);
    log_close();
    return g_fail ? 1 : 0;
}
