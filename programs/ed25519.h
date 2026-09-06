/* **************************************************************************
 *       RISC-V Emulator - Ed25519 Signatures (RFC 8032) - Interface
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

#ifndef ED25519_H
#define ED25519_H
#include <stdint.h>

#define ED25519_SEED_SIZE    32
#define ED25519_PUBLIC_SIZE  32
#define ED25519_PRIVATE_SIZE 64   /* seed || public key */
#define ED25519_SIG_SIZE     64

void ed25519_keypair(uint8_t public_key[32], uint8_t private_key[64],
                     const uint8_t seed[32]);
void ed25519_sign(uint8_t sig[64], const uint8_t *msg, uint32_t msg_len,
                  const uint8_t private_key[64]);
int  ed25519_verify(const uint8_t sig[64], const uint8_t *msg, uint32_t msg_len,
                    const uint8_t public_key[32]);

#endif /* ED25519_H */
