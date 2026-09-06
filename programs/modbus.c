/* **************************************************************************
 *                  RISC-V Emulator - Modbus RTU Protocol
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

#include "modbus.h"
#include <string.h>

/* ---- Slave state ---- */

uint8_t  mb_coils[MB_MAX_COILS / 8];
uint16_t mb_regs[MB_MAX_REGS];
uint8_t  mb_slave_addr = 1u;

/* ---- CRC-16/IBM (reflected 0x8005) ---- */

uint16_t modbus_crc16(const uint8_t *buf, int len)
{
    uint16_t crc = 0xFFFFu;
    int i, b;
    for (i = 0; i < len; i++) {
        crc ^= (uint16_t)buf[i];
        for (b = 0; b < 8; b++) {
            if (crc & 1u)
                crc = (crc >> 1) ^ 0xA001u;
            else
                crc >>= 1;
        }
    }
    return crc;
}

int mb_crc_ok(const mb_frame_t *f)
{
    uint16_t crc, frame_crc;
    if (f->len < 4) return 0;
    crc = modbus_crc16(f->buf, f->len - 2);
    frame_crc = (uint16_t)f->buf[f->len - 2] | ((uint16_t)f->buf[f->len - 1] << 8);
    return crc == frame_crc;
}

/* ---- Append CRC to frame ---- */

static void frame_append_crc(mb_frame_t *f)
{
    uint16_t crc = modbus_crc16(f->buf, f->len);
    f->buf[f->len]     = (uint8_t)(crc & 0xFFu);
    f->buf[f->len + 1] = (uint8_t)(crc >> 8);
    f->len += 2;
}

/* ---- Build request ---- */

int mb_build_request(mb_frame_t *f, uint8_t addr, uint8_t fc,
                     uint16_t reg, uint16_t count, const uint16_t *wdata)
{
    int i;
    f->len = 0;
    f->buf[f->len++] = addr;
    f->buf[f->len++] = fc;

    switch (fc) {
    case MB_FC_READ_COILS:
    case MB_FC_READ_HOLDING_REGS:
        f->buf[f->len++] = (uint8_t)(reg >> 8);
        f->buf[f->len++] = (uint8_t)(reg & 0xFFu);
        f->buf[f->len++] = (uint8_t)(count >> 8);
        f->buf[f->len++] = (uint8_t)(count & 0xFFu);
        break;

    case MB_FC_WRITE_SINGLE_REG:
        if (!wdata) return -1;
        f->buf[f->len++] = (uint8_t)(reg >> 8);
        f->buf[f->len++] = (uint8_t)(reg & 0xFFu);
        f->buf[f->len++] = (uint8_t)(wdata[0] >> 8);
        f->buf[f->len++] = (uint8_t)(wdata[0] & 0xFFu);
        break;

    case MB_FC_WRITE_MULTI_REGS:
        if (!wdata || count == 0 || count > 123u) return -1;
        f->buf[f->len++] = (uint8_t)(reg >> 8);
        f->buf[f->len++] = (uint8_t)(reg & 0xFFu);
        f->buf[f->len++] = (uint8_t)(count >> 8);
        f->buf[f->len++] = (uint8_t)(count & 0xFFu);
        f->buf[f->len++] = (uint8_t)(count * 2u);   /* byte count */
        for (i = 0; i < (int)count; i++) {
            f->buf[f->len++] = (uint8_t)(wdata[i] >> 8);
            f->buf[f->len++] = (uint8_t)(wdata[i] & 0xFFu);
        }
        break;

    default:
        return -1;
    }

    frame_append_crc(f);
    return f->len;
}

/* ---- Build exception response ---- */

static void build_exception(mb_frame_t *resp, uint8_t addr, uint8_t fc, uint8_t ex)
{
    resp->len = 0;
    resp->buf[resp->len++] = addr;
    resp->buf[resp->len++] = fc | 0x80u;
    resp->buf[resp->len++] = ex;
    frame_append_crc(resp);
}

/* ---- Slave processing ---- */

int mb_slave_process(const mb_frame_t *req, mb_frame_t *resp)
{
    uint8_t  addr, fc;
    uint16_t start, count;
    int      i;

    if (!mb_crc_ok(req)) return -1;

    addr = req->buf[0];
    fc   = req->buf[1];

    /* Ignore frames not addressed to us */
    if (addr != mb_slave_addr) {
        resp->len = 0;
        return 0;
    }

    switch (fc) {

    /* ---- FC01: Read Coils ---- */
    case MB_FC_READ_COILS:
        if (req->len < 8) {
            build_exception(resp, addr, fc, MB_EX_ILLEGAL_VALUE);
            return 0;
        }
        start = ((uint16_t)req->buf[2] << 8) | req->buf[3];
        count = ((uint16_t)req->buf[4] << 8) | req->buf[5];

        if (count == 0u || start + count > (uint16_t)MB_MAX_COILS) {
            build_exception(resp, addr, fc, MB_EX_ILLEGAL_ADDR);
            return 0;
        }
        {
            int nbytes = ((int)count + 7) / 8;
            resp->len = 0;
            resp->buf[resp->len++] = addr;
            resp->buf[resp->len++] = fc;
            resp->buf[resp->len++] = (uint8_t)nbytes;
            for (i = 0; i < nbytes; i++) {
                /* Collect 8 coil bits */
                uint8_t byte = 0u;
                int     b;
                for (b = 0; b < 8; b++) {
                    int coil = (int)start + i * 8 + b;
                    if (coil < (int)(start + count) && coil < MB_MAX_COILS) {
                        if (mb_coils[coil / 8] & (uint8_t)(1u << (coil % 8)))
                            byte |= (uint8_t)(1u << b);
                    }
                }
                resp->buf[resp->len++] = byte;
            }
            frame_append_crc(resp);
        }
        break;

    /* ---- FC03: Read Holding Registers ---- */
    case MB_FC_READ_HOLDING_REGS:
        if (req->len < 8) {
            build_exception(resp, addr, fc, MB_EX_ILLEGAL_VALUE);
            return 0;
        }
        start = ((uint16_t)req->buf[2] << 8) | req->buf[3];
        count = ((uint16_t)req->buf[4] << 8) | req->buf[5];

        if (count == 0u || start + count > (uint16_t)MB_MAX_REGS) {
            build_exception(resp, addr, fc, MB_EX_ILLEGAL_ADDR);
            return 0;
        }
        resp->len = 0;
        resp->buf[resp->len++] = addr;
        resp->buf[resp->len++] = fc;
        resp->buf[resp->len++] = (uint8_t)(count * 2u);
        for (i = 0; i < (int)count; i++) {
            resp->buf[resp->len++] = (uint8_t)(mb_regs[start + i] >> 8);
            resp->buf[resp->len++] = (uint8_t)(mb_regs[start + i] & 0xFFu);
        }
        frame_append_crc(resp);
        break;

    /* ---- FC06: Write Single Register ---- */
    case MB_FC_WRITE_SINGLE_REG:
        if (req->len < 8) {
            build_exception(resp, addr, fc, MB_EX_ILLEGAL_VALUE);
            return 0;
        }
        start = ((uint16_t)req->buf[2] << 8) | req->buf[3];
        if (start >= (uint16_t)MB_MAX_REGS) {
            build_exception(resp, addr, fc, MB_EX_ILLEGAL_ADDR);
            return 0;
        }
        mb_regs[start] = ((uint16_t)req->buf[4] << 8) | req->buf[5];
        /* Echo request as response */
        memcpy(resp->buf, req->buf, (unsigned int)req->len);
        resp->len = req->len;
        break;

    /* ---- FC16: Write Multiple Registers ---- */
    case MB_FC_WRITE_MULTI_REGS:
        if (req->len < 9) {
            build_exception(resp, addr, fc, MB_EX_ILLEGAL_VALUE);
            return 0;
        }
        start = ((uint16_t)req->buf[2] << 8) | req->buf[3];
        count = ((uint16_t)req->buf[4] << 8) | req->buf[5];

        if (count == 0u || start + count > (uint16_t)MB_MAX_REGS) {
            build_exception(resp, addr, fc, MB_EX_ILLEGAL_ADDR);
            return 0;
        }
        for (i = 0; i < (int)count; i++) {
            mb_regs[start + i] =
                ((uint16_t)req->buf[7 + i * 2] << 8) | req->buf[8 + i * 2];
        }
        resp->len = 0;
        resp->buf[resp->len++] = addr;
        resp->buf[resp->len++] = fc;
        resp->buf[resp->len++] = (uint8_t)(start >> 8);
        resp->buf[resp->len++] = (uint8_t)(start & 0xFFu);
        resp->buf[resp->len++] = (uint8_t)(count >> 8);
        resp->buf[resp->len++] = (uint8_t)(count & 0xFFu);
        frame_append_crc(resp);
        break;

    default:
        build_exception(resp, addr, fc, MB_EX_ILLEGAL_FC);
        break;
    }

    return 0;
}

/* ---- Response parsers ---- */

int mb_parse_read_regs(const mb_frame_t *resp, uint16_t *vals, int count)
{
    int byte_count, n, i;
    if (!mb_crc_ok(resp)) return -1;
    if (resp->len < 5)    return -1;
    if (resp->buf[1] != MB_FC_READ_HOLDING_REGS) return -1;

    byte_count = resp->buf[2];
    n = byte_count / 2;
    if (n > count) n = count;

    for (i = 0; i < n; i++) {
        vals[i] = ((uint16_t)resp->buf[3 + i * 2] << 8) | resp->buf[4 + i * 2];
    }
    return n;
}

int mb_parse_read_coils(const mb_frame_t *resp, uint8_t *bits, int count)
{
    int byte_count, i, b, idx;
    if (!mb_crc_ok(resp)) return -1;
    if (resp->len < 4)    return -1;
    if (resp->buf[1] != MB_FC_READ_COILS) return -1;

    byte_count = resp->buf[2];
    idx = 0;
    for (i = 0; i < byte_count && idx < count; i++) {
        for (b = 0; b < 8 && idx < count; b++, idx++) {
            bits[idx] = (resp->buf[3 + i] >> b) & 1u;
        }
    }
    return idx;
}

uint8_t mb_is_exception(const mb_frame_t *resp)
{
    if (resp->len < 5) return 0u;
    if (resp->buf[1] & 0x80u) return resp->buf[2];
    return 0u;
}
