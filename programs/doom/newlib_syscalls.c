/*
 * newlib_syscalls.c -- bare-metal syscall stubs for Doom on RISC-V.
 *
 * Copyright (C) 2026 Ulrik Hørlyk Hjort
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * This file is linked with the GPLv2 DOOM engine in this directory and is
 * therefore GPLv2, unlike the MIT-licensed emulator. See ./README.md.
 *
 * Bridges newlib's FILE* machinery to our semihosting ECALLs:
 *   0x505  HOST_FILE_OPEN   a0=path_ptr a1=path_len a2=mode -> fd or -1
 *   0x506  HOST_FILE_READ   a0=fd a1=buf a2=n        -> bytes read
 *   0x507  HOST_FILE_WRITE  a0=fd a1=buf a2=n        -> bytes written
 *   0x508  HOST_FILE_CLOSE  a0=fd                    -> 0
 *   0x509  HOST_FILE_SEEK   a0=fd a1=offset a2=whence-> 0/-1
 *   0x50A  HOST_FILE_TELL   a0=fd                    -> position
 *   0x50B  HOST_FILE_SIZE   a0=fd                    -> size
 *
 * fd mapping: newlib fd = semihosting_handle + 3
 *   fd 0 = stdin  (no input)
 *   fd 1 = stdout (-> UART)
 *   fd 2 = stderr (-> UART)
 *   fd 3+ = semihosting handles 0..15
 */

#include <sys/stat.h>
#include <sys/types.h>
#include <sys/lock.h>
#include <errno.h>
#include <string.h>
#include <stdint.h>

/* -------------------------------------------------------------------------
 * Retargetable locking stubs (single-threaded bare-metal -- all no-ops)
 * -------------------------------------------------------------------------*/
struct __lock __lock___sfp_recursive_mutex;
struct __lock __lock___malloc_recursive_mutex;
struct __lock __lock___atexit_recursive_mutex;

void __retarget_lock_init(_LOCK_T l)              { (void)l; }
void __retarget_lock_init_recursive(_LOCK_T l)    { (void)l; }
void __retarget_lock_close(_LOCK_T l)             { (void)l; }
void __retarget_lock_close_recursive(_LOCK_T l)   { (void)l; }
void __retarget_lock_acquire(_LOCK_T l)           { (void)l; }
void __retarget_lock_acquire_recursive(_LOCK_T l) { (void)l; }
int  __retarget_lock_try_acquire(_LOCK_T l)           { (void)l; return 1; }
int  __retarget_lock_try_acquire_recursive(_LOCK_T l) { (void)l; return 1; }
void __retarget_lock_release(_LOCK_T l)           { (void)l; }
void __retarget_lock_release_recursive(_LOCK_T l) { (void)l; }

/* UART TX register for stdout/stderr */
#define UART_BASE 0x10000000UL

static inline void uart_putchar(char c) {
    volatile char *uart = (volatile char *)UART_BASE;
    *uart = c;
}

/* -------------------------------------------------------------------------
 * Heap (for malloc via newlib)
 * -------------------------------------------------------------------------*/
extern char _end;
static char *_heap_ptr = 0;

void *_sbrk(ptrdiff_t incr) {
    if (_heap_ptr == 0) _heap_ptr = &_end;
    char *prev = _heap_ptr;
    _heap_ptr += incr;
    return (void *)prev;
}

/* -------------------------------------------------------------------------
 * Exit
 * -------------------------------------------------------------------------*/
void __attribute__((noreturn)) _exit(int status) {
    register int a0 asm("a0") = status;
    register int a7 asm("a7") = 93;
    asm volatile("ecall" :: "r"(a0), "r"(a7));
    while (1) {}
}

/* -------------------------------------------------------------------------
 * stdout / stderr -> UART
 * -------------------------------------------------------------------------*/
static int _sh_open(const char *path, int path_len, int mode) {
    register uint32_t a0 asm("a0") = (uint32_t)(uintptr_t)path;
    register uint32_t a1 asm("a1") = (uint32_t)path_len;
    register uint32_t a2 asm("a2") = (uint32_t)mode;
    register uint32_t a7 asm("a7") = 0x505;
    asm volatile("ecall" : "+r"(a0) : "r"(a1), "r"(a2), "r"(a7) : "memory");
    return (int)a0;
}

static int _sh_read(int sh_fd, void *buf, unsigned int n) {
    register uint32_t a0 asm("a0") = (uint32_t)sh_fd;
    register uint32_t a1 asm("a1") = (uint32_t)(uintptr_t)buf;
    register uint32_t a2 asm("a2") = n;
    register uint32_t a7 asm("a7") = 0x506;
    asm volatile("ecall" : "+r"(a0) : "r"(a1), "r"(a2), "r"(a7) : "memory");
    return (int)a0;
}

static int _sh_write(int sh_fd, const void *buf, unsigned int n) {
    register uint32_t a0 asm("a0") = (uint32_t)sh_fd;
    register uint32_t a1 asm("a1") = (uint32_t)(uintptr_t)buf;
    register uint32_t a2 asm("a2") = n;
    register uint32_t a7 asm("a7") = 0x507;
    asm volatile("ecall" : "+r"(a0) : "r"(a1), "r"(a2), "r"(a7) : "memory");
    return (int)a0;
}

static int _sh_close(int sh_fd) {
    register uint32_t a0 asm("a0") = (uint32_t)sh_fd;
    register uint32_t a7 asm("a7") = 0x508;
    asm volatile("ecall" : "+r"(a0) : "r"(a7));
    return 0;
}

static int _sh_seek(int sh_fd, int offset, int whence) {
    register uint32_t a0 asm("a0") = (uint32_t)sh_fd;
    register uint32_t a1 asm("a1") = (uint32_t)offset;
    register uint32_t a2 asm("a2") = (uint32_t)whence;
    register uint32_t a7 asm("a7") = 0x509;
    asm volatile("ecall" : "+r"(a0) : "r"(a1), "r"(a2), "r"(a7) : "memory");
    return (int)a0;
}

static int _sh_tell(int sh_fd) {
    register uint32_t a0 asm("a0") = (uint32_t)sh_fd;
    register uint32_t a7 asm("a7") = 0x50A;
    asm volatile("ecall" : "+r"(a0) : "r"(a7));
    return (int)a0;
}

/* -------------------------------------------------------------------------
 * newlib required syscalls
 * -------------------------------------------------------------------------*/

int _open(const char *path, int flags, int mode) {
    (void)mode;
    int sh_mode = 0;  /* default: read */
    if (flags & 1)       sh_mode = 1;  /* O_WRONLY -> write */
    else if (flags & 2)  sh_mode = 1;  /* O_RDWR  -> write (simplification) */
    if (flags & 0x200)   sh_mode = 1;  /* O_CREAT -> write */
    int handle = _sh_open(path, (int)strlen(path), sh_mode);
    if (handle < 0 || (unsigned int)handle == 0xFFFFFFFFu) {
        errno = ENOENT;
        return -1;
    }
    return handle + 3;
}

int _close(int fd) {
    if (fd < 3) return 0;
    return _sh_close(fd - 3);
}

int _read(int fd, void *buf, unsigned int count) {
    if (fd == 0) { errno = EAGAIN; return -1; }
    if (fd < 3)  return 0;
    int n = _sh_read(fd - 3, buf, count);
    if (n == 0) return 0;  /* EOF */
    return n;
}

int _write(int fd, const void *buf, unsigned int count) {
    if (fd == 1 || fd == 2) {
        const char *p = (const char *)buf;
        for (unsigned int i = 0; i < count; i++) uart_putchar(p[i]);
        return (int)count;
    }
    if (fd < 3) return 0;
    return _sh_write(fd - 3, buf, count);
}

off_t _lseek(int fd, off_t offset, int whence) {
    if (fd < 3) return 0;
    if (_sh_seek(fd - 3, (int)offset, whence) < 0) return (off_t)-1;
    return (off_t)_sh_tell(fd - 3);
}

int _fstat(int fd, struct stat *st) {
    (void)fd;
    st->st_mode = S_IFREG | 0644;
    st->st_size = 0;
    return 0;
}

int _isatty(int fd) {
    return (fd < 3) ? 1 : 0;
}

int _kill(int pid, int sig) { (void)pid; (void)sig; errno = EINVAL; return -1; }
int _getpid(void) { return 1; }

/* Low-level syscall stubs -- newlib calls these with _prefix */
int _mkdir(const char *path, int mode) { (void)path; (void)mode; return 0; }
int _rmdir(const char *path) { (void)path; return 0; }
int _unlink(const char *path) { (void)path; return 0; }
int _rename(const char *old, const char *newp) { (void)old; (void)newp; return 0; }
int _stat(const char *path, struct stat *st) {
    (void)path;
    st->st_mode = S_IFREG | 0644;
    st->st_size = 0;
    return 0;
}
int _access(const char *path, int mode) { (void)path; (void)mode; return 0; }

/* Also provide POSIX-level wrappers that Doom calls directly */
int access(const char *path, int mode) { return _access(path, mode); }
int unlink(const char *path) { return _unlink(path); }
int mkdir(const char *path, mode_t mode) { (void)path; (void)mode; return 0; }

/* getenv -- return NULL for all environment variables */
char *getenv(const char *name) { (void)name; return 0; }

/* atexit -- stub */
int atexit(void (*fn)(void)) { (void)fn; return 0; }
