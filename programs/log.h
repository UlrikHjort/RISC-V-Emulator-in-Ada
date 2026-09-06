/* **************************************************************************
 *            RISC-V Emulator - Host Logging Module - Interface
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

#ifndef LOG_H
#define LOG_H

// Host logging module for the RISC-V emulator.
//
// Allows programs running inside the emulator to create and write to log
// files on the *host* filesystem.  The emulator intercepts five custom
// ECALL syscall numbers before they reach the normal trap handler:
//
//   a7 = 0x500  HOST_LOG_OPEN      a0=filename ptr, a1=filename len  -> 0 / -1
//   a7 = 0x501  HOST_LOG_WRITE     a0=data ptr,     a1=data len      -> bytes written
//   a7 = 0x502  HOST_LOG_CLOSE     (no args)                         -> 0
//   a7 = 0x503  HOST_LOG_REGS      (no args)  emulator dumps regs    -> 0
//   a7 = 0x504  HOST_GET_TIME_MS   (no args)  ms since midnight       -> Word
//
// Files are created relative to the directory the emulator is launched from.
//
// Usage example:
//
//   #include "log.h"
//
//   int main(void) {
//       log_init("run.log");
//       log_write(NONE,       "Raw message: %d\n", 42);
//       log_write(TIME_STAMP, "Timestamped: %s\n", "hello");
//       log_write(CYCLES,     "After %u instructions\n", 0);
//       log_regs();
//       log_close();
//       return 0;
//   }

// Timestamp prefix mode for log_write().
typedef enum {
    NONE       = 0,  // no prefix        -- "message"
    TIME_STAMP = 1,  // host wall-clock  -- "[HH:MM:SS.mmm] message"
    CYCLES     = 2,  // CPU cycle count  -- "[00abcdef] message"
} log_mode_t;

// Open (create/truncate) a log file on the host filesystem.
// filename: null-terminated path string visible to the host OS.
// Returns 0 on success, -1 on failure.
int log_init(const char *filename);

// Write a formatted string to the log file (printf-style).
// mode    -- NONE, TIME_STAMP, or CYCLES
// format  -- format string; supports %d %u %x %X %s %c %%
// Returns the number of bytes written, or 0 if the log is not open.
int log_write(log_mode_t mode, const char *format, ...);

// Ask the emulator to append a register dump to the log file.
// Output format:  x00 = 0xNNNNNNNN  (one register per line, x0-x31 + PC)
void log_regs(void);

// Flush and close the log file.
void log_close(void);

#endif // LOG_H
