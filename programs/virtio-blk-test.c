/* **************************************************************************
 *        RISC-V Emulator - VirtIO Block Device Test
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
 * **************************************************************************
 * Tests the VirtIO MMIO block device (transport v2) at 0x10001000:
 *   - Device enumeration (magic, version, device ID)
 *   - Status negotiation sequence
 *   - Virtqueue setup (descriptor table, available ring, used ring)
 *   - Block write (VIRTIO_BLK_T_OUT) -- write pattern to sector
 *   - Block read  (VIRTIO_BLK_T_IN)  -- read back and verify
 *   - Multi-sector read/write
 *   - Out-of-range sector (IOERR)
 *   - Device reset
 */

#include <stdint.h>
#include "log.h"

static void *my_memset(void *s, int c, unsigned n)
{
    unsigned char *p = (unsigned char *)s;
    while (n--) *p++ = (unsigned char)c;
    return s;
}
#define memset my_memset

static int g_pass = 0, g_fail = 0;

static void chk(const char *label, int ok)
{
    if (ok) { log_write(NONE, "PASS %s\n", label); g_pass++; }
    else     { log_write(NONE, "FAIL %s\n", label); g_fail++; }
}

/* ---- VirtIO MMIO base ---- */
#define VIRTIO_BASE  0x10001000UL

#define VREG(off)   (*(volatile uint32_t *)(VIRTIO_BASE + (off)))

#define REG_MAGIC           0x000
#define REG_VERSION         0x004
#define REG_DEVICE_ID       0x008
#define REG_VENDOR_ID       0x00C
#define REG_DEVICE_FEATURES 0x010
#define REG_DEV_FEAT_SEL    0x014
#define REG_DRV_FEATURES    0x020
#define REG_DRV_FEAT_SEL    0x024
#define REG_QUEUE_SEL       0x030
#define REG_QUEUE_NUM_MAX   0x034
#define REG_QUEUE_NUM       0x038
#define REG_QUEUE_READY     0x044
#define REG_QUEUE_NOTIFY    0x050
#define REG_INT_STATUS      0x060
#define REG_INT_ACK         0x064
#define REG_STATUS          0x070
#define REG_QUEUE_DESC_LO   0x080
#define REG_QUEUE_DESC_HI   0x084
#define REG_QUEUE_DRV_LO    0x090
#define REG_QUEUE_DRV_HI    0x094
#define REG_QUEUE_DEV_LO    0x0A0
#define REG_QUEUE_DEV_HI    0x0A4
#define REG_CFG_GEN         0x0FC
#define REG_CFG_BASE        0x100

/* VirtIO status bits */
#define VIRTIO_STATUS_ACKNOWLEDGE  1
#define VIRTIO_STATUS_DRIVER       2
#define VIRTIO_STATUS_DRIVER_OK    4
#define VIRTIO_STATUS_FEATURES_OK  8

/* Block request types */
#define VIRTIO_BLK_T_IN   0
#define VIRTIO_BLK_T_OUT  1

/* Descriptor flags */
#define VIRTQ_DESC_F_NEXT   1
#define VIRTQ_DESC_F_WRITE  2

/* ---- Virtqueue structures ---- */
#define QUEUE_SIZE  16
#define SECTOR_SIZE 512

typedef struct {
    uint64_t addr;
    uint32_t len;
    uint16_t flags;
    uint16_t next;
} __attribute__((packed)) VirtqDesc;

typedef struct {
    uint16_t flags;
    uint16_t idx;
    uint16_t ring[QUEUE_SIZE];
} __attribute__((packed)) VirtqAvail;

typedef struct {
    uint32_t id;
    uint32_t len;
} __attribute__((packed)) VirtqUsedElem;

typedef struct {
    uint16_t flags;
    uint16_t idx;
    VirtqUsedElem ring[QUEUE_SIZE];
} __attribute__((packed)) VirtqUsed;

typedef struct {
    uint32_t type;
    uint32_t reserved;
    uint64_t sector;
} __attribute__((packed)) VirtioBlkReq;

/* Static queue buffers (aligned as required by spec) */
static VirtqDesc  desc[QUEUE_SIZE] __attribute__((aligned(16)));
static VirtqAvail avail            __attribute__((aligned(2)));
static VirtqUsed  used             __attribute__((aligned(4)));

/* ---- Globals ---- */
static uint16_t next_desc = 0;   /* next free descriptor */
static uint16_t avail_head = 0;  /* avail ring head (num entries added) */
static uint16_t used_tail  = 0;  /* last used ring entry we consumed */

/* ---- virtqueue helpers ---- */
static void vq_reset(void)
{
    memset(desc,  0, sizeof(desc));
    memset(&avail, 0, sizeof(avail));
    memset(&used,  0, sizeof(used));
    next_desc  = 0;
    avail_head = 0;
    used_tail  = 0;
}

/* Allocate n consecutive descriptors.
   Since we wait synchronously after every submit, we always reuse slots
   starting at next_desc, which we reset to 0 after each vq_wait. */
static uint16_t alloc_descs(int n)
{
    uint16_t first = next_desc;
    next_desc = (uint16_t)(next_desc + (uint16_t)n);
    return first;
}

/* Submit head to avail ring, then kick (write QueueNotify) */
static void vq_submit(uint16_t head)
{
    avail.ring[avail_head % QUEUE_SIZE] = head;
    avail_head++;
    /* Memory barrier (compiler barrier sufficient in single-threaded env) */
    __asm__ volatile ("" ::: "memory");
    avail.idx = avail_head;
    __asm__ volatile ("" ::: "memory");
    VREG(REG_QUEUE_NOTIFY) = 0;
}

/* Wait for and consume one used ring entry, return len */
static uint32_t vq_wait(uint16_t *id_out)
{
    /* In polling mode the emulator processes synchronously on QueueNotify */
    uint16_t new_idx = used.idx;
    if (new_idx == used_tail)
        return 0;  /* nothing yet */
    *id_out = (uint16_t)used.ring[used_tail % QUEUE_SIZE].id;
    uint32_t len = used.ring[used_tail % QUEUE_SIZE].len;
    used_tail++;
    /* Acknowledge interrupt */
    VREG(REG_INT_ACK) = VREG(REG_INT_STATUS);
    /* Reset descriptor allocation: previous descs are free again */
    next_desc = 0;
    return len;
}

/* ---- Device initialization ---- */
static int virtio_init(void)
{
    /* Reset */
    VREG(REG_STATUS) = 0;

    /* ACKNOWLEDGE + DRIVER */
    uint32_t status = VIRTIO_STATUS_ACKNOWLEDGE | VIRTIO_STATUS_DRIVER;
    VREG(REG_STATUS) = status;

    /* Negotiate features (we accept none) */
    VREG(REG_DRV_FEAT_SEL) = 0;
    VREG(REG_DRV_FEATURES) = 0;

    /* FEATURES_OK */
    status |= VIRTIO_STATUS_FEATURES_OK;
    VREG(REG_STATUS) = status;

    if (!(VREG(REG_STATUS) & VIRTIO_STATUS_FEATURES_OK))
        return -1;  /* device rejected features */

    /* Setup queue 0 */
    VREG(REG_QUEUE_SEL) = 0;
    uint32_t qmax = VREG(REG_QUEUE_NUM_MAX);
    if (qmax == 0)
        return -1;
    uint32_t qnum = qmax < QUEUE_SIZE ? qmax : QUEUE_SIZE;
    VREG(REG_QUEUE_NUM)    = qnum;
    VREG(REG_QUEUE_DESC_LO) = (uint32_t)(uintptr_t)desc;
    VREG(REG_QUEUE_DESC_HI) = 0;
    VREG(REG_QUEUE_DRV_LO)  = (uint32_t)(uintptr_t)&avail;
    VREG(REG_QUEUE_DRV_HI)  = 0;
    VREG(REG_QUEUE_DEV_LO)  = (uint32_t)(uintptr_t)&used;
    VREG(REG_QUEUE_DEV_HI)  = 0;
    VREG(REG_QUEUE_READY)   = 1;

    /* DRIVER_OK */
    status |= VIRTIO_STATUS_DRIVER_OK;
    VREG(REG_STATUS) = status;
    return 0;
}

/* ---- Block I/O ---- */

/* Sector data buffers */
static uint8_t wbuf[SECTOR_SIZE];
static uint8_t rbuf[SECTOR_SIZE];

/* Issue a 1-sector read or write request.
   3-descriptor chain: [header | data | status]
   Returns status byte (0 = OK). */
static uint8_t blk_op(uint32_t type, uint64_t sector,
                       uint8_t *buf, uint32_t buf_len)
{
    static VirtioBlkReq hdr;
    static uint8_t      status_byte;

    hdr.type     = type;
    hdr.reserved = 0;
    hdr.sector   = sector;
    status_byte  = 0xFF;  /* sentinel */

    uint16_t d0 = alloc_descs(3);
    uint16_t d1 = (uint16_t)(d0 + 1);
    uint16_t d2 = (uint16_t)(d0 + 2);

    /* Header: read-only, chained */
    desc[d0].addr  = (uint64_t)(uintptr_t)&hdr;
    desc[d0].len   = sizeof(hdr);
    desc[d0].flags = VIRTQ_DESC_F_NEXT;
    desc[d0].next  = d1;

    /* Data: chained; for reads (IN) device writes -> WRITE flag */
    desc[d1].addr  = (uint64_t)(uintptr_t)buf;
    desc[d1].len   = buf_len;
    desc[d1].flags = VIRTQ_DESC_F_NEXT |
                     (type == VIRTIO_BLK_T_IN ? VIRTQ_DESC_F_WRITE : 0);
    desc[d1].next  = d2;

    /* Status: device writes -> WRITE, no chaining */
    desc[d2].addr  = (uint64_t)(uintptr_t)&status_byte;
    desc[d2].len   = 1;
    desc[d2].flags = VIRTQ_DESC_F_WRITE;
    desc[d2].next  = 0;

    vq_submit(d0);

    /* Collect result */
    uint16_t id;
    vq_wait(&id);
    return status_byte;
}

/* ---- Test helpers ---- */
static int buf_equal(const uint8_t *a, const uint8_t *b, uint32_t len)
{
    for (uint32_t i = 0; i < len; i++)
        if (a[i] != b[i])
            return 0;
    return 1;
}

static int buf_all(const uint8_t *b, uint8_t val, uint32_t len)
{
    for (uint32_t i = 0; i < len; i++)
        if (b[i] != val)
            return 0;
    return 1;
}

int main(void)
{
    log_init("virtio-blk-test.log");
    log_write(NONE, "VirtIO Block Device Test\n\n");

    /* ---- Enumerate device ---- */
    log_write(NONE, "--- Enumerate ---\n");
    chk("magic value",    VREG(REG_MAGIC) == 0x74726976u);
    chk("version = 2",    VREG(REG_VERSION) == 2);
    chk("device id = 2",  VREG(REG_DEVICE_ID) == 2);
    chk("vendor id ok",   VREG(REG_VENDOR_ID) != 0);

    /* Capacity from device config */
    uint32_t cap_lo = VREG(REG_CFG_BASE);
    uint32_t cap_hi = VREG(REG_CFG_BASE + 4);
    chk("capacity lo = 1024", cap_lo == 1024);
    chk("capacity hi = 0",    cap_hi == 0);

    chk("queue num max >= 1", VREG(REG_QUEUE_NUM_MAX) >= 1);

    /* ---- Initialize ---- */
    log_write(NONE, "--- Init ---\n");
    vq_reset();
    int rc = virtio_init();
    chk("init ok",          rc == 0);
    chk("status driver_ok", VREG(REG_STATUS) == (VIRTIO_STATUS_ACKNOWLEDGE |
                                                   VIRTIO_STATUS_DRIVER      |
                                                   VIRTIO_STATUS_FEATURES_OK |
                                                   VIRTIO_STATUS_DRIVER_OK));
    chk("queue ready",      VREG(REG_QUEUE_READY) == 1);

    /* ---- Write sector 0 ---- */
    log_write(NONE, "--- Write sector 0 ---\n");
    for (int i = 0; i < SECTOR_SIZE; i++)
        wbuf[i] = (uint8_t)(i & 0xFF);

    uint8_t st = blk_op(VIRTIO_BLK_T_OUT, 0, wbuf, SECTOR_SIZE);
    chk("write status ok",       st == 0);
    chk("interrupt status set",  VREG(REG_INT_STATUS) == 0);  /* cleared by vq_wait */

    /* ---- Read sector 0 back ---- */
    log_write(NONE, "--- Read sector 0 ---\n");
    memset(rbuf, 0, sizeof(rbuf));
    st = blk_op(VIRTIO_BLK_T_IN, 0, rbuf, SECTOR_SIZE);
    chk("read status ok",   st == 0);
    chk("read data match",  buf_equal(wbuf, rbuf, SECTOR_SIZE));

    /* ---- Write sector 5 with 0xAB pattern ---- */
    log_write(NONE, "--- Write sector 5 ---\n");
    memset(wbuf, 0xAB, SECTOR_SIZE);
    st = blk_op(VIRTIO_BLK_T_OUT, 5, wbuf, SECTOR_SIZE);
    chk("write sect5 ok", st == 0);

    memset(rbuf, 0, SECTOR_SIZE);
    st = blk_op(VIRTIO_BLK_T_IN, 5, rbuf, SECTOR_SIZE);
    chk("read sect5 ok",   st == 0);
    chk("sect5 data 0xAB", buf_all(rbuf, 0xAB, SECTOR_SIZE));

    /* ---- Sector 0 still intact? ---- */
    log_write(NONE, "--- Verify sector 0 unchanged ---\n");
    for (int i = 0; i < SECTOR_SIZE; i++)
        wbuf[i] = (uint8_t)(i & 0xFF);
    memset(rbuf, 0, SECTOR_SIZE);
    st = blk_op(VIRTIO_BLK_T_IN, 0, rbuf, SECTOR_SIZE);
    chk("re-read sect0 ok",     st == 0);
    chk("sect0 pattern intact", buf_equal(wbuf, rbuf, SECTOR_SIZE));

    /* ---- Write last valid sector (1023) ---- */
    log_write(NONE, "--- Last sector (1023) ---\n");
    memset(wbuf, 0xCD, SECTOR_SIZE);
    st = blk_op(VIRTIO_BLK_T_OUT, 1023, wbuf, SECTOR_SIZE);
    chk("write sect1023 ok", st == 0);

    memset(rbuf, 0, SECTOR_SIZE);
    st = blk_op(VIRTIO_BLK_T_IN, 1023, rbuf, SECTOR_SIZE);
    chk("read sect1023 ok",   st == 0);
    chk("sect1023 data 0xCD", buf_all(rbuf, 0xCD, SECTOR_SIZE));

    /* ---- Out-of-range sector (1024) -> IOERR ---- */
    log_write(NONE, "--- Out-of-range sector ---\n");
    memset(rbuf, 0, SECTOR_SIZE);
    st = blk_op(VIRTIO_BLK_T_IN, 1024, rbuf, SECTOR_SIZE);
    chk("oob read = IOERR", st == 1);

    memset(wbuf, 0x99, SECTOR_SIZE);
    st = blk_op(VIRTIO_BLK_T_OUT, 1024, wbuf, SECTOR_SIZE);
    chk("oob write = IOERR", st == 1);

    /* ---- Device reset ---- */
    log_write(NONE, "--- Device reset ---\n");
    VREG(REG_STATUS) = 0;
    chk("status = 0 after reset", VREG(REG_STATUS) == 0);
    chk("queue not ready",        VREG(REG_QUEUE_READY) == 0);

    /* Re-init and verify disk still holds data */
    vq_reset();
    rc = virtio_init();
    chk("re-init ok", rc == 0);
    memset(rbuf, 0, SECTOR_SIZE);
    st = blk_op(VIRTIO_BLK_T_IN, 5, rbuf, SECTOR_SIZE);
    chk("post-reset read ok",   st == 0);
    chk("data survives reset",  buf_all(rbuf, 0xAB, SECTOR_SIZE));

    log_write(NONE, "\n%d PASS  %d FAIL\n", g_pass, g_fail);
    log_close();
    return g_fail;
}
