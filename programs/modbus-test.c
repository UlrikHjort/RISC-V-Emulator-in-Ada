/* **************************************************************************
 *                    RISC-V Emulator - Modbus RTU Tests
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
#include "log.h"
#include "uart.h"
#include <string.h>

static int g_pass, g_fail;

#define PASS(msg) do { log_write(NONE, "PASS: " msg "\n"); g_pass++; } while (0)
#define FAIL(msg) do { log_write(NONE, "FAIL: " msg "\n"); g_fail++; } while (0)
#define CHECK(cond, msg) do { if (cond) PASS(msg); else FAIL(msg); } while (0)

/* Round-trip helper: build request -> slave -> response */
static int transact(uint8_t addr, uint8_t fc,
                    uint16_t reg, uint16_t count, const uint16_t *wdata,
                    mb_frame_t *resp)
{
    mb_frame_t req;
    int r;
    r = mb_build_request(&req, addr, fc, reg, count, wdata);
    if (r < 0) return -1;
    return mb_slave_process(&req, resp);
}

int main(void)
{
    uart_init();
    log_init("modbus-test.log");
    log_write(NONE, "=== MODBUS RTU Test ===\n");

    g_pass = 0; g_fail = 0;

    /* Reset slave state */
    memset(mb_coils, 0, sizeof mb_coils);
    memset(mb_regs,  0, sizeof mb_regs);
    mb_slave_addr = 1u;

    /* ---- CRC-16 Tests ---- */

    /* Known vector: [01 03 00 00 00 0A] -> CRC = 0xCDC5 (lo=C5, hi=CD in frame) */
    {
        uint8_t msg[] = {0x01u, 0x03u, 0x00u, 0x00u, 0x00u, 0x0Au};
        uint16_t crc = modbus_crc16(msg, 6);
        CHECK(crc == 0xCDC5u, "CRC-16 vector [01 03 00 00 00 0A] == 0xCDC5");
    }

    /* Known vector: [01 06 00 01 00 03] -> CRC = 0x0B98 (lo=98, hi=0B in frame) */
    {
        uint8_t msg[] = {0x01u, 0x06u, 0x00u, 0x01u, 0x00u, 0x03u};
        uint16_t crc = modbus_crc16(msg, 6);
        CHECK(crc == 0x0B98u, "CRC-16 vector [01 06 00 01 00 03] == 0x0B98");
    }

    /* Whole-frame CRC check: verify mb_crc_ok works for a valid frame.
     * For [01 03 00 00 00 0A], CRC=0xCDC5 -> lo=0xC5, hi=0xCD in frame. */
    {
        mb_frame_t f;
        f.len = 0;
        f.buf[f.len++] = 0x01u;
        f.buf[f.len++] = 0x03u;
        f.buf[f.len++] = 0x00u;
        f.buf[f.len++] = 0x00u;
        f.buf[f.len++] = 0x00u;
        f.buf[f.len++] = 0x0Au;
        f.buf[f.len++] = 0xC5u;  /* CRC lo */
        f.buf[f.len++] = 0xCDu;  /* CRC hi */
        CHECK(mb_crc_ok(&f) == 1, "mb_crc_ok accepts valid frame");
    }

    /* Bad CRC rejected */
    {
        mb_frame_t f;
        f.len = 0;
        f.buf[f.len++] = 0x01u;
        f.buf[f.len++] = 0x03u;
        f.buf[f.len++] = 0x00u;
        f.buf[f.len++] = 0x00u;
        f.buf[f.len++] = 0x00u;
        f.buf[f.len++] = 0x0Au;
        f.buf[f.len++] = 0xFFu;  /* wrong CRC */
        f.buf[f.len++] = 0xFFu;
        CHECK(mb_crc_ok(&f) == 0, "mb_crc_ok rejects bad CRC");
    }

    /* ---- FC06: Write Single Register ---- */

    {
        mb_frame_t resp;
        uint16_t   val = 0x1234u;
        int r;

        r = transact(1u, MB_FC_WRITE_SINGLE_REG, 5u, 1u, &val, &resp);
        CHECK(r == 0,          "FC06 transact ok");
        CHECK(mb_crc_ok(&resp), "FC06 response CRC ok");
        CHECK(mb_is_exception(&resp) == 0u, "FC06 no exception");
        CHECK(mb_regs[5] == 0x1234u, "FC06 reg[5] == 0x1234");
        /* Echo: response bytes 2-5 match request */
        CHECK(resp.buf[2] == 0x00u && resp.buf[3] == 0x05u, "FC06 echo reg addr");
        CHECK(resp.buf[4] == 0x12u && resp.buf[5] == 0x34u, "FC06 echo value");
    }

    /* ---- FC03: Read Holding Registers ---- */

    {
        mb_frame_t resp;
        uint16_t   vals[4];
        int r, n;

        /* Pre-load registers */
        mb_regs[0] = 0x0001u;
        mb_regs[1] = 0x0002u;
        mb_regs[2] = 0xABCDu;
        mb_regs[3] = 0xFFFFu;

        r = transact(1u, MB_FC_READ_HOLDING_REGS, 0u, 4u, 0, &resp);
        CHECK(r == 0,           "FC03 transact ok");
        CHECK(mb_crc_ok(&resp), "FC03 response CRC ok");
        CHECK(mb_is_exception(&resp) == 0u, "FC03 no exception");

        n = mb_parse_read_regs(&resp, vals, 4);
        CHECK(n == 4,                "FC03 parsed 4 registers");
        CHECK(vals[0] == 0x0001u,    "FC03 reg[0] == 0x0001");
        CHECK(vals[1] == 0x0002u,    "FC03 reg[1] == 0x0002");
        CHECK(vals[2] == 0xABCDu,    "FC03 reg[2] == 0xABCD");
        CHECK(vals[3] == 0xFFFFu,    "FC03 reg[3] == 0xFFFF");
        CHECK(resp.buf[2] == 8u,     "FC03 byte count == 8");
    }

    /* ---- FC16: Write Multiple Registers ---- */

    {
        mb_frame_t resp;
        uint16_t   wvals[3] = {0x1111u, 0x2222u, 0x3333u};
        uint16_t   rvals[3];
        int r, n;

        r = transact(1u, MB_FC_WRITE_MULTI_REGS, 10u, 3u, wvals, &resp);
        CHECK(r == 0,           "FC16 transact ok");
        CHECK(mb_crc_ok(&resp), "FC16 response CRC ok");
        CHECK(mb_is_exception(&resp) == 0u, "FC16 no exception");

        /* Response: [addr][0x10][start_hi][start_lo][count_hi][count_lo][crcx2] */
        CHECK(resp.buf[1] == 0x10u, "FC16 response FC");
        CHECK(resp.buf[3] == 0x0Au, "FC16 start_lo == 10");
        CHECK(resp.buf[5] == 0x03u, "FC16 count_lo == 3");

        /* Verify registers were actually written */
        CHECK(mb_regs[10] == 0x1111u, "FC16 reg[10] == 0x1111");
        CHECK(mb_regs[11] == 0x2222u, "FC16 reg[11] == 0x2222");
        CHECK(mb_regs[12] == 0x3333u, "FC16 reg[12] == 0x3333");

        /* Read them back with FC03 */
        transact(1u, MB_FC_READ_HOLDING_REGS, 10u, 3u, 0, &resp);
        n = mb_parse_read_regs(&resp, rvals, 3);
        CHECK(n == 3 && rvals[0] == 0x1111u &&
              rvals[1] == 0x2222u && rvals[2] == 0x3333u,
              "FC03 read-back after FC16 correct");
    }

    /* ---- FC01: Read Coils ---- */

    {
        mb_frame_t resp;
        uint8_t    bits[8];
        int r, n;

        /* Set coils: coil 0=1, 1=0, 2=1, 3=1, 4=0, 5=0, 6=1, 7=0 -> byte=0x4D */
        mb_coils[0] = 0x4Du;

        r = transact(1u, MB_FC_READ_COILS, 0u, 8u, 0, &resp);
        CHECK(r == 0,           "FC01 transact ok");
        CHECK(mb_crc_ok(&resp), "FC01 response CRC ok");

        n = mb_parse_read_coils(&resp, bits, 8);
        CHECK(n == 8, "FC01 parsed 8 coils");
        CHECK(bits[0] == 1u && bits[1] == 0u &&
              bits[2] == 1u && bits[3] == 1u, "FC01 bits[0-3] correct");
        CHECK(bits[4] == 0u && bits[5] == 0u &&
              bits[6] == 1u && bits[7] == 0u, "FC01 bits[4-7] correct");
    }

    /* ---- Error / Exception Tests ---- */

    /* Wrong slave address -> no response (len=0) */
    {
        mb_frame_t req, resp;
        mb_build_request(&req, 2u, MB_FC_READ_HOLDING_REGS, 0u, 1u, 0);
        mb_slave_process(&req, &resp);
        CHECK(resp.len == 0, "wrong slave addr -> no response");
    }

    /* FC03 out-of-range address -> exception 0x02 */
    {
        mb_frame_t resp;
        transact(1u, MB_FC_READ_HOLDING_REGS, 60u, 10u, 0, &resp);
        CHECK(mb_is_exception(&resp) == MB_EX_ILLEGAL_ADDR,
              "FC03 OOB -> exception ILLEGAL_ADDR");
    }

    /* FC06 write to invalid register -> exception 0x02 */
    {
        mb_frame_t resp;
        uint16_t   v = 0xFFFFu;
        transact(1u, MB_FC_WRITE_SINGLE_REG, 100u, 1u, &v, &resp);
        CHECK(mb_is_exception(&resp) == MB_EX_ILLEGAL_ADDR,
              "FC06 OOB -> exception ILLEGAL_ADDR");
    }

    /* FC16 zero-count -> exception (handled as ILLEGAL_ADDR: count=0 fails check) */
    {
        mb_frame_t resp;
        uint16_t   v = 0u;
        transact(1u, MB_FC_WRITE_MULTI_REGS, 0u, 0u, &v, &resp);
        CHECK(mb_is_exception(&resp) != 0u, "FC16 count=0 -> exception");
    }

    /* Unknown FC -> exception 0x01 */
    {
        mb_frame_t req, resp;
        req.len = 0;
        req.buf[req.len++] = 1u;   /* addr */
        req.buf[req.len++] = 0x42u; /* unknown FC */
        req.buf[req.len++] = 0u;
        req.buf[req.len++] = 0u;
        {
            uint16_t crc = modbus_crc16(req.buf, req.len);
            req.buf[req.len++] = (uint8_t)(crc & 0xFFu);
            req.buf[req.len++] = (uint8_t)(crc >> 8);
        }
        mb_slave_process(&req, &resp);
        CHECK(mb_is_exception(&resp) == MB_EX_ILLEGAL_FC,
              "unknown FC -> exception ILLEGAL_FC");
    }

    /* Bad CRC in request -> slave rejects (-1) */
    {
        mb_frame_t req, resp;
        mb_build_request(&req, 1u, MB_FC_READ_HOLDING_REGS, 0u, 1u, 0);
        req.buf[req.len - 1] ^= 0xFFu;   /* corrupt CRC */
        int r = mb_slave_process(&req, &resp);
        CHECK(r == -1, "bad request CRC -> slave returns -1");
    }

    /* ---- FC06 + FC03 round-trip stress: 10 registers ---- */
    {
        uint16_t wv[10], rv[10];
        mb_frame_t resp;
        int i, ok = 1;

        for (i = 0; i < 10; i++) wv[i] = (uint16_t)(i * 0x100u + i);

        transact(1u, MB_FC_WRITE_MULTI_REGS, 20u, 10u, wv, &resp);
        CHECK(mb_is_exception(&resp) == 0u, "FC16 stress write ok");

        transact(1u, MB_FC_READ_HOLDING_REGS, 20u, 10u, 0, &resp);
        mb_parse_read_regs(&resp, rv, 10);
        for (i = 0; i < 10; i++) {
            if (rv[i] != wv[i]) { ok = 0; break; }
        }
        CHECK(ok, "FC03/FC16 10-register round-trip");
    }

    /* Print summary */
    log_write(NONE, "\n");
    log_write(NONE, "=== Results ===\n");
    {
        char s[16]; int n; int i;
        log_write(NONE, "PASS: ");
        n = g_pass; i = 15; s[i] = '\0';
        if (!n) { s[--i] = '0'; }
        else { while (n) { s[--i] = (char)('0' + n%10); n /= 10; } }
        log_write(NONE, s + i);
        log_write(NONE, "\nFAIL: ");
        n = g_fail; i = 15; s[i] = '\0';
        if (!n) { s[--i] = '0'; }
        else { while (n) { s[--i] = (char)('0' + n%10); n /= 10; } }
        log_write(NONE, s + i);
        log_write(NONE, "\n");
    }
    if (g_fail == 0)
        log_write(NONE, "ALL PASSED\n");

    log_close();
    return g_fail;
}
