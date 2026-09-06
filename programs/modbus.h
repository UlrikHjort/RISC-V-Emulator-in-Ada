/* **************************************************************************
 *            RISC-V Emulator - Modbus RTU Protocol - Interface
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

#ifndef MODBUS_H
#define MODBUS_H

#include <stdint.h>

/* ---- Function Codes ---- */
#define MB_FC_READ_COILS        0x01u
#define MB_FC_READ_HOLDING_REGS 0x03u
#define MB_FC_WRITE_SINGLE_REG  0x06u
#define MB_FC_WRITE_MULTI_REGS  0x10u

/* ---- Exception Codes ---- */
#define MB_EX_ILLEGAL_FC        0x01u
#define MB_EX_ILLEGAL_ADDR      0x02u
#define MB_EX_ILLEGAL_VALUE     0x03u

/* ---- Slave limits ---- */
#define MB_MAX_COILS   64
#define MB_MAX_REGS    64
#define MB_MAX_FRAME   256

/* ---- Frame buffer ---- */
typedef struct {
    uint8_t buf[MB_MAX_FRAME];
    int     len;
} mb_frame_t;

/* ---- Slave state (accessible to tests for pre-loading / verification) ---- */
extern uint8_t  mb_coils[MB_MAX_COILS / 8];   /* bit-packed, LSB first */
extern uint16_t mb_regs[MB_MAX_REGS];
extern uint8_t  mb_slave_addr;

/* ---- API ---- */

/* CRC-16/IBM (MODBUS): polynomial 0xA001, init 0xFFFF */
uint16_t modbus_crc16(const uint8_t *buf, int len);

/* Verify frame CRC; returns 1 if valid, 0 if bad */
int mb_crc_ok(const mb_frame_t *f);

/* Build a request frame.
 * fc = MB_FC_READ_COILS / MB_FC_READ_HOLDING_REGS:  reg=start, count=count, wdata=NULL
 * fc = MB_FC_WRITE_SINGLE_REG:                       reg=reg,   count=1,    wdata=&val
 * fc = MB_FC_WRITE_MULTI_REGS:                       reg=start, count=n,    wdata=vals[]
 * Returns frame length on success, -1 on error.
 */
int mb_build_request(mb_frame_t *f, uint8_t addr, uint8_t fc,
                     uint16_t reg, uint16_t count, const uint16_t *wdata);

/* Process a request frame and populate a response frame.
 * Returns 0 on success (even if an exception response was generated), -1 on bad CRC. */
int mb_slave_process(const mb_frame_t *req, mb_frame_t *resp);

/* Parse a FC03/FC01 response into vals[]; returns number of registers/bytes read, -1 on error */
int mb_parse_read_regs(const mb_frame_t *resp, uint16_t *vals, int count);
int mb_parse_read_coils(const mb_frame_t *resp, uint8_t *bits, int count);

/* Check if a response is an exception; returns exception code or 0 */
uint8_t mb_is_exception(const mb_frame_t *resp);

#endif /* MODBUS_H */
