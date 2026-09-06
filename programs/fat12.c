/* **************************************************************************
 *            RISC-V Emulator - FAT12 Filesystem over SPI Flash
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

#include "fat12.h"
#include "spi.h"
#include "log.h"
#include <string.h>

/* ---- Sector I/O ---- */

static void read_sector(int sec, uint8_t *buf)
{
    spi_flash_read((unsigned int)sec * FAT12_SECTOR_SIZE, buf, FAT12_SECTOR_SIZE);
}

static void write_sector(int sec, const uint8_t *buf)
{
    spi_flash_write_enable();
    spi_flash_write((unsigned int)sec * FAT12_SECTOR_SIZE, buf, FAT12_SECTOR_SIZE);
}

/* ---- FAT12 cache (one sector = one FAT copy) ---- */

static uint8_t g_fat_buf[FAT12_SECTOR_SIZE];
static int     g_fat_loaded;
static int     g_fat_dirty;

static void fat_load(void)
{
    if (!g_fat_loaded) {
        read_sector(FAT12_RESERVED, g_fat_buf);
        g_fat_loaded = 1;
        g_fat_dirty  = 0;
    }
}

static void fat_flush(void)
{
    int i;
    if (g_fat_dirty) {
        write_sector(FAT12_RESERVED, g_fat_buf);
        /* Write second FAT copy */
        write_sector(FAT12_RESERVED + FAT12_FAT_SECTORS, g_fat_buf);
        g_fat_dirty = 0;
    }
    /* suppress unused var warning when FAT_SECTORS=1 */
    (void)i;
}

/* FAT12: 12 bits per entry, packed 2 entries per 3 bytes */
static uint16_t fat_get(uint16_t cluster)
{
    uint32_t  off = (uint32_t)cluster * 3u / 2u;
    uint16_t  val;
    fat_load();
    val = (uint16_t)g_fat_buf[off] | ((uint16_t)g_fat_buf[off + 1u] << 8);
    if (cluster & 1u)
        val >>= 4;
    else
        val &= 0x0FFFu;
    return val;
}

static void fat_set(uint16_t cluster, uint16_t value)
{
    uint32_t off = (uint32_t)cluster * 3u / 2u;
    fat_load();
    if (cluster & 1u) {
        g_fat_buf[off]     = (g_fat_buf[off] & 0x0Fu) | (uint8_t)((value & 0x0Fu) << 4);
        g_fat_buf[off + 1u] = (uint8_t)(value >> 4);
    } else {
        g_fat_buf[off]      = (uint8_t)(value & 0xFFu);
        g_fat_buf[off + 1u] = (g_fat_buf[off + 1u] & 0xF0u) | (uint8_t)((value >> 8) & 0x0Fu);
    }
    g_fat_dirty = 1;
}

/* Find a free cluster, mark it EOC, return cluster number (0 = disk full) */
static uint16_t fat_alloc(void)
{
    uint16_t i;
    fat_load();
    for (i = 2u; i < (uint16_t)(FAT12_TOTAL_CLUSTERS + 2u); i++) {
        if (fat_get(i) == FAT12_FREE_CLUSTER) {
            fat_set(i, (uint16_t)FAT12_EOC);
            return i;
        }
    }
    return 0;
}

static void fat_free_chain(uint16_t cluster)
{
    while (cluster >= 2u && cluster < (uint16_t)FAT12_BAD_CLUSTER) {
        uint16_t next = fat_get(cluster);
        fat_set(cluster, (uint16_t)FAT12_FREE_CLUSTER);
        cluster = next;
    }
}

/* ---- Cluster <-> sector ---- */

static int cluster_to_sector(uint16_t cluster)
{
    return FAT12_FIRST_DATA_SEC + (int)(cluster - 2u);
}

/* ---- Directory helpers ---- */

#define ROOT_SEC(s) (FAT12_RESERVED + FAT12_NUM_FATS * FAT12_FAT_SECTORS + (s))

/* Convert "HELLO.TXT" to 8.3 padded uppercase */
static void name_to_83(const char *name, uint8_t *out)
{
    int i, j;
    const char *dot = name;
    while (*dot && *dot != '.') dot++;

    memset(out, ' ', 11);

    for (i = 0; i < 8 && name[i] && (name + i) != dot; i++) {
        char c = name[i];
        if (c >= 'a' && c <= 'z') c = (char)(c - 32);
        out[i] = (uint8_t)c;
    }
    if (*dot == '.') {
        dot++;
        for (j = 0; j < 3 && dot[j]; j++) {
            char c = dot[j];
            if (c >= 'a' && c <= 'z') c = (char)(c - 32);
            out[8 + j] = (uint8_t)c;
        }
    }
}

static int name_match(const uint8_t *a, const uint8_t *b)
{
    int i;
    for (i = 0; i < 11; i++) {
        if (a[i] != b[i]) return 0;
    }
    return 1;
}

/* Find a directory entry by 8.3 name.
 * Returns 0 on found, -1 on not found.
 * out_sec and out_idx are the absolute flash sector and entry-within-sector. */
static int dir_find(const uint8_t *name83, int *out_sec, int *out_idx, dir_entry_t *out_ent)
{
    uint8_t buf[FAT12_SECTOR_SIZE];
    int s, j;

    for (s = 0; s < FAT12_ROOT_SECTORS; s++) {
        read_sector(ROOT_SEC(s), buf);
        for (j = 0; j < 16; j++) {
            dir_entry_t *e = (dir_entry_t *)(void *)(buf + j * 32);
            if (e->name[0] == 0x00u) return -1;   /* end of directory */
            if (e->name[0] == 0xE5u) continue;     /* deleted */
            if (name_match(e->name, name83)) {
                if (out_sec) *out_sec = ROOT_SEC(s);
                if (out_idx) *out_idx = j;
                if (out_ent) *out_ent = *e;
                return 0;
            }
        }
    }
    return -1;
}

/* ---- Public API ---- */

int fat12_format(void)
{
    uint8_t buf[FAT12_SECTOR_SIZE];
    bpb_t  *bpb = (bpb_t *)(void *)buf;
    int     i;

    /* --- Boot sector / BPB --- */
    memset(buf, 0, sizeof buf);
    bpb->jmp[0] = 0xEBu; bpb->jmp[1] = 0x3Cu; bpb->jmp[2] = 0x90u;
    memcpy(bpb->oem, "RISCVFAT", 8);
    bpb->bytes_per_sector    = FAT12_SECTOR_SIZE;
    bpb->sectors_per_cluster = 1u;
    bpb->reserved_sectors    = FAT12_RESERVED;
    bpb->num_fats            = FAT12_NUM_FATS;
    bpb->root_entries        = FAT12_ROOT_ENTRIES;
    bpb->total_sectors       = FAT12_TOTAL_SECTORS;
    bpb->media               = 0xF8u;
    bpb->fat_sectors         = FAT12_FAT_SECTORS;
    bpb->sectors_per_track   = 1u;
    bpb->num_heads           = 1u;
    bpb->boot_sig            = 0x29u;
    bpb->volume_id           = 0x12345678uL;
    memcpy(bpb->volume_label, "RISCV      ", 11);
    memcpy(bpb->fs_type,      "FAT12   ",  8);
    buf[510] = 0x55u; buf[511] = 0xAAu;
    write_sector(0, buf);

    /* --- FAT1 and FAT2: media byte + reserved entries 0 and 1 --- */
    memset(buf, 0, sizeof buf);
    buf[0] = 0xF8u; buf[1] = 0xFFu; buf[2] = 0xFFu;
    write_sector(FAT12_RESERVED, buf);
    write_sector(FAT12_RESERVED + FAT12_FAT_SECTORS, buf);

    /* --- Root directory: all zeroes --- */
    memset(buf, 0, sizeof buf);
    for (i = 0; i < FAT12_ROOT_SECTORS; i++) {
        write_sector(ROOT_SEC(i), buf);
    }

    g_fat_loaded = 0;
    g_fat_dirty  = 0;
    fat_load();
    return 0;
}

int fat12_init(void)
{
    uint8_t buf[FAT12_SECTOR_SIZE];
    bpb_t  *bpb = (bpb_t *)(void *)buf;

    spi_init();
    g_fat_loaded = 0;
    g_fat_dirty  = 0;

    read_sector(0, buf);
    if (buf[510] != 0x55u || buf[511] != 0xAAu) return -1;
    if (bpb->bytes_per_sector != FAT12_SECTOR_SIZE)  return -1;
    if (bpb->num_fats         != FAT12_NUM_FATS)     return -1;
    return 0;
}

int fat12_open(const char *name, fat12_file_t *f)
{
    uint8_t    name83[11];
    dir_entry_t ent;
    int         sec, idx;

    name_to_83(name, name83);
    if (dir_find(name83, &sec, &idx, &ent) != 0) return -1;

    f->first_cluster = ent.first_cluster;
    f->cur_cluster   = ent.first_cluster;
    f->file_size     = ent.file_size;
    f->pos           = 0u;
    f->dir_sector    = sec;
    f->dir_index     = idx;
    f->writable      = 0;
    return 0;
}

int fat12_create(const char *name, fat12_file_t *f)
{
    uint8_t buf[FAT12_SECTOR_SIZE];
    uint8_t name83[11];
    int     s, j;

    name_to_83(name, name83);
    if (dir_find(name83, NULL, NULL, NULL) == 0) return -1;  /* already exists */

    for (s = 0; s < FAT12_ROOT_SECTORS; s++) {
        int sec = ROOT_SEC(s);
        read_sector(sec, buf);
        for (j = 0; j < 16; j++) {
            dir_entry_t *e = (dir_entry_t *)(void *)(buf + j * 32);
            if (e->name[0] == 0x00u || e->name[0] == 0xE5u) {
                memset(e, 0, 32);
                memcpy(e->name, name83, 11);
                e->attr          = FAT12_ATTR_ARCHIVE;
                e->first_cluster = 0u;
                e->file_size     = 0u;
                write_sector(sec, buf);

                f->first_cluster = 0u;
                f->cur_cluster   = 0u;
                f->file_size     = 0u;
                f->pos           = 0u;
                f->dir_sector    = sec;
                f->dir_index     = j;
                f->writable      = 1;
                return 0;
            }
        }
    }
    return -1;  /* directory full */
}

int fat12_read(fat12_file_t *f, void *buf, int len)
{
    uint8_t *dst   = (uint8_t *)buf;
    int      nread = 0;

    while (len > 0 && f->pos < f->file_size) {
        int      sec_off = (int)(f->pos % (uint32_t)FAT12_SECTOR_SIZE);
        int      avail   = FAT12_SECTOR_SIZE - sec_off;
        int      remain  = (int)(f->file_size - f->pos);
        int      n;
        uint8_t  sec_buf[FAT12_SECTOR_SIZE];
        uint16_t next;

        if (f->cur_cluster < 2u) break;

        if (avail > remain) avail = remain;
        if (avail > len)    avail = len;
        n = avail;

        read_sector(cluster_to_sector(f->cur_cluster), sec_buf);
        memcpy(dst, sec_buf + sec_off, (unsigned int)n);

        dst     += n;
        f->pos  += (uint32_t)n;
        len     -= n;
        nread   += n;

        /* Advance to next cluster at sector boundary */
        if (f->pos % (uint32_t)FAT12_SECTOR_SIZE == 0u) {
            next = fat_get(f->cur_cluster);
            if (next >= (uint16_t)FAT12_EOC || next < 2u) break;
            f->cur_cluster = next;
        }
    }
    return nread;
}

int fat12_write(fat12_file_t *f, const void *buf, int len)
{
    const uint8_t *src      = (const uint8_t *)buf;
    int            nwritten = 0;

    while (len > 0) {
        int     sec_off = (int)(f->pos % (uint32_t)FAT12_SECTOR_SIZE);
        int     n       = FAT12_SECTOR_SIZE - sec_off;
        uint8_t sec_buf[FAT12_SECTOR_SIZE];
        int     sec;

        if (n > len) n = len;

        /* Allocate first cluster for a new/empty file */
        if (f->cur_cluster < 2u) {
            uint16_t c = fat_alloc();
            if (c == 0u) break;
            f->first_cluster = c;
            f->cur_cluster   = c;
        }

        sec = cluster_to_sector(f->cur_cluster);

        /* Read-modify-write for partial sector */
        read_sector(sec, sec_buf);
        memcpy(sec_buf + sec_off, src, (unsigned int)n);
        write_sector(sec, sec_buf);

        src      += n;
        f->pos   += (uint32_t)n;
        if (f->pos > f->file_size) f->file_size = f->pos;
        len      -= n;
        nwritten += n;

        /* At a cluster boundary with more data: allocate next cluster */
        if (f->pos % (uint32_t)FAT12_SECTOR_SIZE == 0u && len > 0) {
            uint16_t c = fat_alloc();
            if (c == 0u) break;
            fat_set(f->cur_cluster, c);
            f->cur_cluster = c;
        }
    }
    return nwritten;
}

int fat12_close(fat12_file_t *f)
{
    if (f->writable) {
        uint8_t      buf[FAT12_SECTOR_SIZE];
        dir_entry_t *e;

        fat_flush();
        read_sector(f->dir_sector, buf);
        e = (dir_entry_t *)(void *)(buf + f->dir_index * 32);
        e->first_cluster = f->first_cluster;
        e->file_size     = f->file_size;
        write_sector(f->dir_sector, buf);
        f->writable = 0;
    }
    return 0;
}

int fat12_delete(const char *name)
{
    uint8_t     name83[11];
    dir_entry_t ent;
    int         sec, idx;
    uint8_t     buf[FAT12_SECTOR_SIZE];
    dir_entry_t *e;

    name_to_83(name, name83);
    if (dir_find(name83, &sec, &idx, &ent) != 0) return -1;

    fat_load();
    fat_free_chain(ent.first_cluster);
    fat_flush();

    read_sector(sec, buf);
    e = (dir_entry_t *)(void *)(buf + idx * 32);
    e->name[0] = 0xE5u;
    write_sector(sec, buf);
    return 0;
}

int fat12_readdir(int index, dir_entry_t *entry)
{
    uint8_t     buf[FAT12_SECTOR_SIZE];
    int         s = index / 16;
    int         j = index % 16;
    dir_entry_t *e;

    if (s >= FAT12_ROOT_SECTORS) return -1;
    read_sector(ROOT_SEC(s), buf);
    e = (dir_entry_t *)(void *)(buf + j * 32);

    if (e->name[0] == 0x00u) return -1;   /* end of directory */
    if (entry) *entry = *e;
    if (e->name[0] == 0xE5u) return 1;    /* deleted slot */
    return 0;
}
