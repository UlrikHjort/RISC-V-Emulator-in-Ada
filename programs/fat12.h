/* **************************************************************************
 *              RISC-V Emulator - FAT12 Filesystem - Interface
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

#ifndef FAT12_H
#define FAT12_H

#include <stdint.h>

/* Flash geometry (64KB, 512-byte sectors) */
#define FAT12_SECTOR_SIZE     512
#define FAT12_TOTAL_SECTORS   128

/* Layout */
#define FAT12_RESERVED        1     /* sector 0: BPB */
#define FAT12_NUM_FATS        2
#define FAT12_FAT_SECTORS     1     /* 1 sector per FAT copy */
#define FAT12_ROOT_ENTRIES    64
#define FAT12_ROOT_SECTORS    4     /* 64 x 32B / 512 */
#define FAT12_FIRST_DATA_SEC  7     /* 1 + 2 + 4 */
#define FAT12_TOTAL_CLUSTERS  121   /* 128 - 7 */

/* FAT12 cluster values */
#define FAT12_FREE_CLUSTER    0x000u
#define FAT12_BAD_CLUSTER     0xFF7u
#define FAT12_EOC             0xFFFu

/* Directory entry attributes */
#define FAT12_ATTR_READONLY   0x01
#define FAT12_ATTR_HIDDEN     0x02
#define FAT12_ATTR_SYSTEM     0x04
#define FAT12_ATTR_VOLUME_ID  0x08
#define FAT12_ATTR_DIRECTORY  0x10
#define FAT12_ATTR_ARCHIVE    0x20

/* ---- On-disk structures ---- */

typedef struct __attribute__((packed)) {
    uint8_t  jmp[3];
    uint8_t  oem[8];
    uint16_t bytes_per_sector;
    uint8_t  sectors_per_cluster;
    uint16_t reserved_sectors;
    uint8_t  num_fats;
    uint16_t root_entries;
    uint16_t total_sectors;
    uint8_t  media;
    uint16_t fat_sectors;
    uint16_t sectors_per_track;
    uint16_t num_heads;
    uint32_t hidden_sectors;
    uint32_t total_sectors32;
    uint8_t  drive_number;
    uint8_t  reserved1;
    uint8_t  boot_sig;
    uint32_t volume_id;
    uint8_t  volume_label[11];
    uint8_t  fs_type[8];
} bpb_t;

typedef struct __attribute__((packed)) {
    uint8_t  name[8];
    uint8_t  ext[3];
    uint8_t  attr;
    uint8_t  reserved[10];
    uint16_t time;
    uint16_t date;
    uint16_t first_cluster;
    uint32_t file_size;
} dir_entry_t;

/* ---- In-memory file handle ---- */

typedef struct {
    uint16_t first_cluster;
    uint16_t cur_cluster;
    uint32_t file_size;
    uint32_t pos;
    int      dir_sector;
    int      dir_index;
    int      writable;
} fat12_file_t;

/* ---- API ---- */

/* Write a fresh FAT12 filesystem to flash */
int  fat12_format(void);

/* Mount: read BPB and verify; returns 0 on success, -1 if not formatted */
int  fat12_init(void);

/* Open existing file for reading; returns 0 on success, -1 if not found */
int  fat12_open(const char *name, fat12_file_t *f);

/* Create new file for writing; returns 0 on success, -1 on error */
int  fat12_create(const char *name, fat12_file_t *f);

/* Read up to len bytes; returns bytes read */
int  fat12_read(fat12_file_t *f, void *buf, int len);

/* Write len bytes; returns bytes written */
int  fat12_write(fat12_file_t *f, const void *buf, int len);

/* Flush and update directory entry */
int  fat12_close(fat12_file_t *f);

/* Delete a file; returns 0 on success, -1 if not found */
int  fat12_delete(const char *name);

/* Read directory entry at index 0..63
 * Returns 0=valid, 1=deleted (entry->name[0]=0xE5), -1=end/out-of-range */
int  fat12_readdir(int index, dir_entry_t *entry);

#endif /* FAT12_H */
