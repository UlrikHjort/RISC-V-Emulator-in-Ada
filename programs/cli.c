/* **************************************************************************
 *     RISC-V Emulator - RISC-V Bare-Metal Command-Line Interface (CLI)
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

// By Ulrik Hørlyk Hjort 2026
/**
 * RISC-V Bare-Metal Command-Line Interface (CLI)
 * 
 * Interactive shell for testing and controlling peripherals.
 * Demonstrates UART interrupts, GPIO, SPI, and system features.
 */

#include "gpio.h"
#include "spi.h"
#include "i2c.h"
#include "timer.h"

#define NULL ((void*)0)
extern void printf(const char *fmt, ...);
extern int strcmp(const char *s1, const char *s2);
extern int strncmp(const char *s1, const char *s2, unsigned long n);
extern unsigned long strlen(const char *s);
extern char *strcpy(char *dst, const char *src);

/* UART registers for interrupt-driven I/O */
#define UART_BASE 0x10000000
#define UART_RBR  (*(volatile unsigned char *)(UART_BASE + 0))
#define UART_THR  (*(volatile unsigned char *)(UART_BASE + 0))
#define UART_IER  (*(volatile unsigned char *)(UART_BASE + 1))
#define UART_IIR  (*(volatile unsigned char *)(UART_BASE + 2))
#define UART_LSR  (*(volatile unsigned char *)(UART_BASE + 5))

#define IER_RDA   0x01
#define IIR_NO_INT 0x01
#define IIR_RDA    0x04
#define LSR_DR     0x01

/* Command buffer */
#define CMD_BUFFER_SIZE 256
static char cmd_buffer[CMD_BUFFER_SIZE];
static int cmd_length = 0;
static volatile int command_ready = 0;

/* Simple delay */
static void delay(unsigned int count) {
    for (volatile unsigned int i = 0; i < count; i++);
}

/* Simple atoi implementation */
static int cli_atoi(const char *str) {
    int result = 0;
    int sign = 1;
    
    if (*str == '-') {
        sign = -1;
        str++;
    } else if (*str == '+') {
        str++;
    }
    
    while (*str >= '0' && *str <= '9') {
        result = result * 10 + (*str - '0');
        str++;
    }
    
    return sign * result;
}

/* Parse hex string */
static unsigned int parse_hex(const char *str) {
    unsigned int result = 0;
    
    if (str[0] == '0' && (str[1] == 'x' || str[1] == 'X')) {
        str += 2;
    }
    
    while (*str) {
        result <<= 4;
        if (*str >= '0' && *str <= '9') {
            result |= (*str - '0');
        } else if (*str >= 'a' && *str <= 'f') {
            result |= (*str - 'a' + 10);
        } else if (*str >= 'A' && *str <= 'F') {
            result |= (*str - 'A' + 10);
        } else {
            break;
        }
        str++;
    }
    
    return result;
}

/* Tokenize command line */
#define MAX_ARGS 16
static int parse_args(char *line, char *argv[]) {
    int argc = 0;
    char *p = line;
    
    while (*p && argc < MAX_ARGS) {
        /* Skip whitespace */
        while (*p == ' ' || *p == '\t') p++;
        
        if (*p == '\0') break;
        
        /* Start of argument */
        argv[argc++] = p;
        
        /* Find end of argument */
        if (*p == '"') {
            /* Quoted string */
            p++;
            argv[argc-1] = p;
            while (*p && *p != '"') p++;
            if (*p) *p++ = '\0';
        } else {
            /* Regular token */
            while (*p && *p != ' ' && *p != '\t') p++;
            if (*p) *p++ = '\0';
        }
    }
    
    return argc;
}

/* Forward declarations */
static void cmd_help(int argc, char *argv[]);
static void cmd_status(int argc, char *argv[]);
static void cmd_version(int argc, char *argv[]);
static void cmd_clear(int argc, char *argv[]);
static void cmd_echo(int argc, char *argv[]);
static void cmd_gpio(int argc, char *argv[]);
static void cmd_spi(int argc, char *argv[]);
static void cmd_mem(int argc, char *argv[]);
static void cmd_uart(int argc, char *argv[]);
static void cmd_i2c(int argc, char *argv[]);
static void cmd_timer(int argc, char *argv[]);

/* Command table */
typedef struct {
    const char *name;
    void (*handler)(int argc, char *argv[]);
    const char *help;
} command_t;

static const command_t commands[] = {
    {"help",    cmd_help,    "Show available commands"},
    {"status",  cmd_status,  "Display system status"},
    {"version", cmd_version, "Show version information"},
    {"clear",   cmd_clear,   "Clear screen"},
    {"echo",    cmd_echo,    "Echo arguments"},
    {"gpio",    cmd_gpio,    "GPIO control and status"},
    {"spi",     cmd_spi,     "SPI flash operations"},
    {"mem",     cmd_mem,     "Memory operations"},
    {"uart",    cmd_uart,    "UART configuration"},
    {"i2c",     cmd_i2c,     "I2C device operations"},
    {"timer",   cmd_timer,   "Timer and PWM control"},
    {NULL, NULL, NULL}
};

/* Help command */
static void cmd_help(int argc, char *argv[]) {
    if (argc > 1) {
        /* Help for specific command */
        for (int i = 0; commands[i].name; i++) {
            if (strcmp(argv[1], commands[i].name) == 0) {
                printf("Command: %s\n", commands[i].name);
                printf("Description: %s\n", commands[i].help);
                /* Add detailed help here */
                return;
            }
        }
        printf("Unknown command: %s\n", argv[1]);
    } else {
        /* General help */
        printf("\nAvailable commands:\n");
        for (int i = 0; commands[i].name; i++) {
            printf("  %-10s - %s\n", commands[i].name, commands[i].help);
        }
        printf("\nType 'help <command>' for detailed help\n");
    }
}

/* Status command */
static void cmd_status(int argc, char *argv[]) {
    printf("\n=== System Status ===\n");
    printf("CPU: RV32IMFD\n");
    printf("RAM: 128 MB @ 0x80000000\n");
    printf("\nPeripherals:\n");
    printf("  UART  @ 0x%08x [enabled]\n", UART_BASE);
    printf("  GPIO  @ 0x%08x [enabled]\n", GPIO_BASE);
    printf("  SPI   @ 0x%08x [enabled]\n", SPI_BASE);
    printf("  CLINT @ 0x02000000 [enabled]\n");
    printf("\n");
}

/* Version command */
static void cmd_version(int argc, char *argv[]) {
    printf("\nRISC-V Bare-Metal CLI v1.0\n");
    printf("Phase 5 - Practical Applications\n");
    printf("Built: %s %s\n", __DATE__, __TIME__);
    printf("\n");
}

/* Clear screen */
static void cmd_clear(int argc, char *argv[]) {
    printf("\033[2J\033[H");  /* ANSI clear screen and home cursor */
}

/* Echo command */
static void cmd_echo(int argc, char *argv[]) {
    for (int i = 1; i < argc; i++) {
        if (i > 1) printf(" ");
        printf("%s", argv[i]);
    }
    printf("\n");
}

/* GPIO command - implementation in next part */
static void cmd_gpio(int argc, char *argv[]);

/* SPI command - implementation in next part */
static void cmd_spi(int argc, char *argv[]);

/* Memory command - implementation in next part */
static void cmd_mem(int argc, char *argv[]);

/* UART command - implementation in next part */
static void cmd_uart(int argc, char *argv[]);

/* Execute command */
static void execute_command(char *cmd_line) {
    char *argv[MAX_ARGS];
    int argc;
    
    /* Skip empty lines */
    if (cmd_line[0] == '\0') {
        return;
    }
    
    /* Parse arguments */
    argc = parse_args(cmd_line, argv);
    if (argc == 0) return;
    
    /* Find and execute command */
    for (int i = 0; commands[i].name; i++) {
        if (strcmp(argv[0], commands[i].name) == 0) {
            commands[i].handler(argc, argv);
            return;
        }
    }
    
    printf("Error: Unknown command '%s'\n", argv[0]);
    printf("Type 'help' for available commands\n");
}

/* Process input character */
static void process_char(char c) {
    if (c == '\r' || c == '\n') {
        if (cmd_length > 0) {
            printf("\n");
            cmd_buffer[cmd_length] = '\0';
            command_ready = 1;
        } else {
            printf("\ncli> ");
        }
    } else if (c == 0x7F || c == 0x08) {
        /* Backspace */
        if (cmd_length > 0) {
            cmd_length--;
            printf("\b \b");
        }
    } else if (c == 0x03) {
        /* Ctrl-C: cancel current line */
        cmd_length = 0;
        printf("^C\ncli> ");
    } else if (c >= 32 && c < 127) {
        /* Printable character */
        if (cmd_length < CMD_BUFFER_SIZE - 1) {
            cmd_buffer[cmd_length++] = c;
            printf("%c", c);
        }
    }
}

/* Poll for UART input (simulates interrupt handler) */
static void poll_uart(void) {
    unsigned char lsr = UART_LSR;
    
    if (lsr & LSR_DR) {
        unsigned char c = UART_RBR;
        process_char(c);
    }
}

/* Startup banner */
static void print_banner(void) {
    printf("\033[2J\033[H");  /* Clear screen */
    printf("===========================================\n");
    printf("  RISC-V Bare-Metal CLI v1.0\n");
    printf("  Phase 5 - Practical Applications\n");
    printf("===========================================\n\n");
    printf("System Info:\n");
    printf("  CPU: RV32IMFD\n");
    printf("  RAM: 128 MB\n");
    printf("  Peripherals: UART, GPIO, SPI, CLINT\n\n");
    printf("Type 'help' for available commands\n");
    printf("Type 'status' for system information\n\n");
}

/* Main CLI loop */
int main(void) {
    /* Initialize peripherals */
    spi_init();
    
    /* Print banner */
    print_banner();
    
    /* Main loop */
    printf("cli> ");
    
    while (1) {
        /* Poll for input */
        poll_uart();
        
        /* Process command if ready */
        if (command_ready) {
            execute_command(cmd_buffer);
            cmd_length = 0;
            command_ready = 0;
            printf("cli> ");
        }
        
        /* Small delay to avoid busy-waiting */
        delay(1000);
    }
    
    return 0;
}

/* ========================================================================
 * GPIO Commands Implementation
 * ======================================================================== */

static void cmd_gpio(int argc, char *argv[]) {
    if (argc < 2) {
        printf("Usage: gpio <subcommand> [args]\n");
        printf("Subcommands:\n");
        printf("  dir <pin> <in|out>        - Set pin direction\n");
        printf("  set <pin> <0|1|low|high>  - Write to output pin\n");
        printf("  get <pin>                 - Read from pin\n");
        printf("  toggle <pin>              - Toggle output pin\n");
        printf("  pull <pin> <none|up|down> - Configure pull resistor\n");
        printf("  int <pin> <enable|disable> [level|edge] - Interrupt control\n");
        printf("  status                    - Show all pin states\n");
        return;
    }
    
    const char *subcmd = argv[1];
    
    if (strcmp(subcmd, "dir") == 0) {
        if (argc != 4) {
            printf("Usage: gpio dir <pin> <in|out>\n");
            return;
        }
        int pin = cli_atoi(argv[2]);
        if (pin < 0 || pin > 31) {
            printf("Error: Invalid pin number (0-31)\n");
            return;
        }
        
        int dir = -1;
        if (strcmp(argv[3], "in") == 0 || strcmp(argv[3], "input") == 0) {
            dir = GPIO_DIR_INPUT;
        } else if (strcmp(argv[3], "out") == 0 || strcmp(argv[3], "output") == 0) {
            dir = GPIO_DIR_OUTPUT;
        } else {
            printf("Error: Direction must be 'in' or 'out'\n");
            return;
        }
        
        gpio_set_direction(pin, dir);
        printf("Pin %d configured as %s\n", pin, dir ? "OUTPUT" : "INPUT");
        
    } else if (strcmp(subcmd, "set") == 0) {
        if (argc != 4) {
            printf("Usage: gpio set <pin> <0|1|low|high>\n");
            return;
        }
        int pin = cli_atoi(argv[2]);
        if (pin < 0 || pin > 31) {
            printf("Error: Invalid pin number (0-31)\n");
            return;
        }
        
        int value = -1;
        if (strcmp(argv[3], "0") == 0 || strcmp(argv[3], "low") == 0) {
            value = GPIO_LOW;
        } else if (strcmp(argv[3], "1") == 0 || strcmp(argv[3], "high") == 0) {
            value = GPIO_HIGH;
        } else {
            printf("Error: Value must be '0', '1', 'low', or 'high'\n");
            return;
        }
        
        gpio_write_pin(pin, value);
        printf("Pin %d set to %s\n", pin, value ? "HIGH" : "LOW");
        
    } else if (strcmp(subcmd, "get") == 0) {
        if (argc != 3) {
            printf("Usage: gpio get <pin>\n");
            return;
        }
        int pin = cli_atoi(argv[2]);
        if (pin < 0 || pin > 31) {
            printf("Error: Invalid pin number (0-31)\n");
            return;
        }
        
        unsigned int value = gpio_read_pin(pin);
        printf("Pin %d: %s (%d)\n", pin, value ? "HIGH" : "LOW", value);
        
    } else if (strcmp(subcmd, "toggle") == 0) {
        if (argc != 3) {
            printf("Usage: gpio toggle <pin>\n");
            return;
        }
        int pin = cli_atoi(argv[2]);
        if (pin < 0 || pin > 31) {
            printf("Error: Invalid pin number (0-31)\n");
            return;
        }
        
        gpio_toggle_pin(pin);
        printf("Pin %d toggled\n", pin);
        
    } else if (strcmp(subcmd, "pull") == 0) {
        if (argc != 4) {
            printf("Usage: gpio pull <pin> <none|up|down>\n");
            return;
        }
        int pin = cli_atoi(argv[2]);
        if (pin < 0 || pin > 31) {
            printf("Error: Invalid pin number (0-31)\n");
            return;
        }
        
        if (strcmp(argv[3], "none") == 0) {
            gpio_set_pull(pin, 0, GPIO_PULL_DOWN);
            printf("Pin %d pull resistor disabled\n", pin);
        } else if (strcmp(argv[3], "up") == 0) {
            gpio_set_pull(pin, 1, GPIO_PULL_UP);
            printf("Pin %d pull-up enabled\n", pin);
        } else if (strcmp(argv[3], "down") == 0) {
            gpio_set_pull(pin, 1, GPIO_PULL_DOWN);
            printf("Pin %d pull-down enabled\n", pin);
        } else {
            printf("Error: Pull type must be 'none', 'up', or 'down'\n");
            return;
        }
        
    } else if (strcmp(subcmd, "int") == 0) {
        if (argc < 4) {
            printf("Usage: gpio int <pin> <enable|disable> [level|edge]\n");
            return;
        }
        int pin = cli_atoi(argv[2]);
        if (pin < 0 || pin > 31) {
            printf("Error: Invalid pin number (0-31)\n");
            return;
        }
        
        if (strcmp(argv[3], "enable") == 0) {
            int type = GPIO_INT_EDGE;
            if (argc > 4) {
                if (strcmp(argv[4], "level") == 0) {
                    type = GPIO_INT_LEVEL;
                } else if (strcmp(argv[4], "edge") == 0) {
                    type = GPIO_INT_EDGE;
                } else {
                    printf("Error: Interrupt type must be 'level' or 'edge'\n");
                    return;
                }
            }
            gpio_enable_interrupt(pin, type);
            printf("Pin %d interrupt enabled (%s)\n", pin, type ? "edge" : "level");
        } else if (strcmp(argv[3], "disable") == 0) {
            gpio_disable_interrupt(pin);
            printf("Pin %d interrupt disabled\n", pin);
        } else {
            printf("Error: Must specify 'enable' or 'disable'\n");
            return;
        }
        
    } else if (strcmp(subcmd, "status") == 0) {
        printf("\nGPIO Status:\n");
        printf("Pin | Dir | Value | Int\n");
        printf("----+-----+-------+----\n");
        for (int i = 0; i < 8; i++) {
            unsigned int dir = (GPIO_DIRECTION >> i) & 1;
            unsigned int val = gpio_read_pin(i);
            unsigned int inten = gpio_interrupt_pending(i);
            printf(" %2d | %s | %s  | %s\n", i,
                   dir ? "OUT" : "IN ",
                   val ? "HIGH" : "LOW ",
                   inten ? "PND" : "---");
        }
        printf("... (showing pins 0-7, use 'gpio get <pin>' for others)\n");
        
    } else {
        printf("Error: Unknown subcommand '%s'\n", subcmd);
        printf("Type 'gpio' for usage\n");
    }
}

/* ========================================================================
 * SPI Commands Implementation
 * ======================================================================== */

static void cmd_spi(int argc, char *argv[]) {
    if (argc < 2) {
        printf("Usage: spi <subcommand> [args]\n");
        printf("Subcommands:\n");
        printf("  id                       - Read JEDEC ID\n");
        printf("  read <addr> <len> [hex|ascii] - Read from flash\n");
        printf("  write <addr> <data>      - Write to flash\n");
        printf("  status                   - Read flash status\n");
        return;
    }
    
    const char *subcmd = argv[1];
    
    if (strcmp(subcmd, "id") == 0) {
        unsigned char id[3];
        spi_flash_read_id(id);
        printf("JEDEC ID: %02X %02X %02X", id[0], id[1], id[2]);
        if (id[0] == 0xEF) {
            printf(" (Winbond)\n");
        } else {
            printf("\n");
        }
        
    } else if (strcmp(subcmd, "read") == 0) {
        if (argc < 4) {
            printf("Usage: spi read <address> <length> [hex|ascii]\n");
            return;
        }
        
        unsigned int addr = parse_hex(argv[2]);
        unsigned int len = cli_atoi(argv[3]);
        
        if (len > 256) {
            printf("Error: Maximum length is 256 bytes\n");
            return;
        }
        
        unsigned char buffer[256];
        spi_flash_read(addr, buffer, len);
        
        int show_ascii = 0;
        if (argc > 4 && strcmp(argv[4], "ascii") == 0) {
            show_ascii = 1;
        }
        
        printf("Read %d bytes from 0x%04X:\n", len, addr);
        
        for (unsigned int i = 0; i < len; i += 16) {
            printf("0x%04X: ", addr + i);
            
            /* Hex dump */
            for (unsigned int j = 0; j < 16 && i + j < len; j++) {
                printf("%02X ", buffer[i + j]);
            }
            
            /* ASCII dump */
            if (show_ascii) {
                /* Pad if less than 16 bytes */
                for (unsigned int j = len - i; j < 16 && i < len; j++) {
                    printf("   ");
                }
                printf(" | ");
                for (unsigned int j = 0; j < 16 && i + j < len; j++) {
                    char c = buffer[i + j];
                    printf("%c", (c >= 32 && c < 127) ? c : '.');
                }
            }
            printf("\n");
        }
        
    } else if (strcmp(subcmd, "write") == 0) {
        if (argc < 4) {
            printf("Usage: spi write <address> <data>\n");
            return;
        }
        
        unsigned int addr = parse_hex(argv[2]);
        const char *data = argv[3];
        unsigned int len = strlen(data);
        
        spi_flash_write_enable();
        spi_flash_write(addr, (const unsigned char *)data, len);
        printf("Wrote %d bytes to address 0x%04X\n", len, addr);
        
    } else if (strcmp(subcmd, "status") == 0) {
        unsigned char status = spi_flash_read_status();
        printf("Flash Status: 0x%02X\n", status);
        printf("  WEL (Write Enable):  %s\n", (status & 0x02) ? "Set" : "Clear");
        printf("  Busy:                %s\n", (status & 0x01) ? "Yes" : "No");
        
    } else {
        printf("Error: Unknown subcommand '%s'\n", subcmd);
        printf("Type 'spi' for usage\n");
    }
}

/* ========================================================================
 * Memory Commands Implementation
 * ======================================================================== */

static void cmd_mem(int argc, char *argv[]) {
    if (argc < 2) {
        printf("Usage: mem <subcommand> [args]\n");
        printf("Subcommands:\n");
        printf("  read <addr> <len>         - Read and dump memory\n");
        printf("  write <addr> <value>      - Write word to memory\n");
        printf("  fill <addr> <len> <value> - Fill memory region\n");
        return;
    }
    
    const char *subcmd = argv[1];
    
    if (strcmp(subcmd, "read") == 0) {
        if (argc < 4) {
            printf("Usage: mem read <address> <length>\n");
            return;
        }
        
        unsigned int addr = parse_hex(argv[2]);
        unsigned int len = cli_atoi(argv[3]);
        
        if (len > 256) {
            printf("Error: Maximum length is 256 bytes\n");
            return;
        }
        
        printf("Memory dump from 0x%08X:\n", addr);
        
        volatile unsigned char *ptr = (volatile unsigned char *)addr;
        for (unsigned int i = 0; i < len; i += 16) {
            printf("%08X: ", addr + i);
            
            /* Hex dump */
            for (unsigned int j = 0; j < 16 && i + j < len; j++) {
                printf("%02X ", ptr[i + j]);
            }
            
            /* ASCII dump */
            for (unsigned int j = len - i; j < 16 && i < len; j++) {
                printf("   ");
            }
            printf(" | ");
            for (unsigned int j = 0; j < 16 && i + j < len; j++) {
                char c = ptr[i + j];
                printf("%c", (c >= 32 && c < 127) ? c : '.');
            }
            printf("\n");
        }
        
    } else if (strcmp(subcmd, "write") == 0) {
        if (argc < 4) {
            printf("Usage: mem write <address> <value>\n");
            return;
        }
        
        unsigned int addr = parse_hex(argv[2]);
        unsigned int value = parse_hex(argv[3]);
        
        volatile unsigned int *ptr = (volatile unsigned int *)addr;
        *ptr = value;
        printf("Wrote 0x%08X to address 0x%08X\n", value, addr);
        
    } else if (strcmp(subcmd, "fill") == 0) {
        if (argc < 5) {
            printf("Usage: mem fill <address> <length> <value>\n");
            return;
        }
        
        unsigned int addr = parse_hex(argv[2]);
        unsigned int len = cli_atoi(argv[3]);
        unsigned char value = (unsigned char)parse_hex(argv[4]);
        
        volatile unsigned char *ptr = (volatile unsigned char *)addr;
        for (unsigned int i = 0; i < len; i++) {
            ptr[i] = value;
        }
        printf("Filled %d bytes at 0x%08X with 0x%02X\n", len, addr, value);
        
    } else {
        printf("Error: Unknown subcommand '%s'\n", subcmd);
        printf("Type 'mem' for usage\n");
    }
}

/* ========================================================================
 * UART Commands Implementation
 * ======================================================================== */

static void cmd_uart(int argc, char *argv[]) {
    if (argc < 2) {
        printf("Usage: uart <subcommand> [args]\n");
        printf("Subcommands:\n");
        printf("  regs                     - Show UART registers\n");
        printf("  int <rda|thre|both|none> - Configure interrupts\n");
        return;
    }
    
    const char *subcmd = argv[1];
    
    if (strcmp(subcmd, "regs") == 0) {
        unsigned char ier = UART_IER;
        unsigned char iir = UART_IIR;
        unsigned char lsr = UART_LSR;
        
        printf("\nUART Registers:\n");
        printf("  IER (Interrupt Enable):  0x%02X\n", ier);
        printf("    RDA (Received Data):   %s\n", (ier & 0x01) ? "Enabled" : "Disabled");
        printf("    THRE (THR Empty):      %s\n", (ier & 0x02) ? "Enabled" : "Disabled");
        
        printf("  IIR (Interrupt ID):      0x%02X\n", iir);
        if (iir & 0x01) {
            printf("    Status:                No interrupt\n");
        } else {
            printf("    Status:                Interrupt pending\n");
            printf("    Type:                  0x%02X\n", iir & 0x0E);
        }
        
        printf("  LSR (Line Status):       0x%02X\n", lsr);
        printf("    DR (Data Ready):       %s\n", (lsr & 0x01) ? "Yes" : "No");
        printf("    THRE (THR Empty):      %s\n", (lsr & 0x20) ? "Yes" : "No");
        printf("\n");
        
    } else if (strcmp(subcmd, "int") == 0) {
        if (argc < 3) {
            printf("Usage: uart int <rda|thre|both|none>\n");
            return;
        }
        
        unsigned char ier = 0;
        if (strcmp(argv[2], "rda") == 0) {
            ier = 0x01;
            printf("UART RDA interrupt enabled\n");
        } else if (strcmp(argv[2], "thre") == 0) {
            ier = 0x02;
            printf("UART THRE interrupt enabled\n");
        } else if (strcmp(argv[2], "both") == 0) {
            ier = 0x03;
            printf("UART RDA and THRE interrupts enabled\n");
        } else if (strcmp(argv[2], "none") == 0) {
            ier = 0x00;
            printf("UART interrupts disabled\n");
        } else {
            printf("Error: Invalid interrupt type\n");
            return;
        }
        
        UART_IER = ier;
        
    } else {
        printf("Error: Unknown subcommand '%s'\n", subcmd);
        printf("Type 'uart' for usage\n");
    }
}

/* I2C command handler */
static void cmd_i2c(int argc, char *argv[]) {
    if (argc < 2) {
        printf("I2C Commands:\n");
        printf("  i2c init              - Initialize I2C controller\n");
        printf("  i2c scan              - Scan for I2C devices\n");
        printf("  i2c read <addr> <reg> - Read from device register\n");
        printf("  i2c write <addr> <reg> <data> - Write to device\n");
        printf("  i2c temp              - Read temperature sensor\n");
        printf("  i2c accel             - Read accelerometer\n");
        printf("  i2c eeprom <addr> [data] - EEPROM read/write\n");
        return;
    }

    const char *subcmd = argv[1];

    if (strcmp(subcmd, "init") == 0) {
        i2c_init();
        printf("I2C controller initialized\n");
        printf("  Prescale: %d (100 kHz standard mode)\n", I2C_PRESCALE);

    } else if (strcmp(subcmd, "scan") == 0) {
        printf("Scanning I2C bus (7-bit addresses)...\n");
        int found = 0;

        for (unsigned char addr = 1; addr < 128; addr++) {
            if (i2c_start(addr << 1)) {
                printf("  0x%02X: Device found\n", addr);
                found++;
            }
            i2c_stop();
        }

        printf("Scan complete. Found %d device(s)\n", found);

    } else if (strcmp(subcmd, "read") == 0) {
        if (argc < 4) {
            printf("Usage: i2c read <addr> <reg>\n");
            return;
        }

        unsigned char addr = parse_hex(argv[2]);
        unsigned char reg = parse_hex(argv[3]);

        if (!i2c_start(addr << 1)) {
            printf("Error: Device 0x%02X not responding\n", addr);
            i2c_stop();
            return;
        }

        i2c_write(reg);
        i2c_restart((addr << 1) | I2C_READ);
        unsigned char data = i2c_read_nack();
        i2c_stop();

        printf("Read from 0x%02X reg 0x%02X: 0x%02X\n", addr, reg, data);

    } else if (strcmp(subcmd, "write") == 0) {
        if (argc < 5) {
            printf("Usage: i2c write <addr> <reg> <data>\n");
            return;
        }

        unsigned char addr = parse_hex(argv[2]);
        unsigned char reg = parse_hex(argv[3]);
        unsigned char data = parse_hex(argv[4]);

        if (!i2c_start(addr << 1)) {
            printf("Error: Device 0x%02X not responding\n", addr);
            i2c_stop();
            return;
        }

        i2c_write(reg);
        i2c_write(data);
        i2c_stop();

        printf("Wrote 0x%02X to device 0x%02X reg 0x%02X\n", data, addr, reg);

    } else if (strcmp(subcmd, "temp") == 0) {
        printf("Reading temperature sensor (0x48)...\n");

        if (!i2c_start(I2C_ADDR_TEMP << 1)) {
            printf("Error: Temperature sensor not found\n");
            i2c_stop();
            return;
        }

        i2c_write(0x00);  /* Temperature register */
        i2c_restart((I2C_ADDR_TEMP << 1) | I2C_READ);
        unsigned char msb = i2c_read_ack();
        unsigned char lsb = i2c_read_nack();
        i2c_stop();

        /* TMP102 format: 12-bit left-justified */
        int temp_raw = (msb << 4) | (lsb >> 4);
        if (temp_raw & 0x800) {
            temp_raw |= 0xF000;  /* Sign extend */
        }
        int temp_c = (temp_raw * 625) / 100;  /* 0.0625degC per LSB */

        printf("Temperature: %d.%02ddegC (raw: 0x%03X)\n",
               temp_c / 100, temp_c % 100, temp_raw & 0xFFF);

    } else if (strcmp(subcmd, "accel") == 0) {
        printf("Reading accelerometer (0x1D)...\n");

        if (!i2c_start(I2C_ADDR_ACCEL << 1)) {
            printf("Error: Accelerometer not found\n");
            i2c_stop();
            return;
        }

        /* Read device ID */
        i2c_write(0x00);
        i2c_restart((I2C_ADDR_ACCEL << 1) | I2C_READ);
        unsigned char devid = i2c_read_nack();
        i2c_stop();

        printf("Device ID: 0x%02X ", devid);
        printf(devid == 0xE5 ? "(OK)\n" : "(Error)\n");

        /* Read acceleration data */
        i2c_start(I2C_ADDR_ACCEL << 1);
        i2c_write(0x32);  /* DATAX0 */
        i2c_restart((I2C_ADDR_ACCEL << 1) | I2C_READ);

        unsigned char x0 = i2c_read_ack();
        unsigned char x1 = i2c_read_ack();
        unsigned char y0 = i2c_read_ack();
        unsigned char y1 = i2c_read_ack();
        unsigned char z0 = i2c_read_ack();
        unsigned char z1 = i2c_read_nack();
        i2c_stop();

        short x = (x1 << 8) | x0;
        short y = (y1 << 8) | y0;
        short z = (z1 << 8) | z0;

        printf("Acceleration: X=%d Y=%d Z=%d\n", x, y, z);

    } else if (strcmp(subcmd, "eeprom") == 0) {
        if (argc < 3) {
            printf("Usage: i2c eeprom <addr> [data]\n");
            return;
        }

        unsigned char mem_addr = parse_hex(argv[2]);

        if (argc >= 4) {
            /* Write */
            unsigned char data = parse_hex(argv[3]);

            i2c_start(I2C_ADDR_EEPROM << 1);
            i2c_write(mem_addr);
            i2c_write(data);
            i2c_stop();

            printf("Wrote 0x%02X to EEPROM address 0x%02X\n", data, mem_addr);
        } else {
            /* Read */
            i2c_start(I2C_ADDR_EEPROM << 1);
            i2c_write(mem_addr);
            i2c_restart((I2C_ADDR_EEPROM << 1) | I2C_READ);
            unsigned char data = i2c_read_nack();
            i2c_stop();

            printf("Read from EEPROM address 0x%02X: 0x%02X\n", mem_addr, data);
        }

    } else {
        printf("Error: Unknown subcommand '%s'\n", subcmd);
        printf("Type 'i2c' for usage\n");
    }
}

/* Timer command handler */
static void cmd_timer(int argc, char *argv[]) {
    if (argc < 2) {
        printf("Timer Commands:\n");
        printf("  timer init               - Initialize timer controller\n");
        printf("  timer set <ch> <val>     - Set compare value\n");
        printf("  timer start <ch>         - Enable channel\n");
        printf("  timer stop <ch>          - Disable channel\n");
        printf("  timer pwm <ch> <duty>    - Set PWM duty (0-255)\n");
        printf("  timer status [ch]        - Show timer status\n");
        printf("  timer prescale <val>     - Set prescaler (1-255)\n");
        return;
    }

    const char *subcmd = argv[1];

    if (strcmp(subcmd, "init") == 0) {
        timer_init();
        printf("Timer controller initialized\n");
        printf("  4 channels available (0-3)\n");
        printf("  Prescale: %d\n", timer_get_prescale());

    } else if (strcmp(subcmd, "set") == 0) {
        if (argc < 4) {
            printf("Usage: timer set <channel> <value>\n");
            return;
        }

        int ch = cli_atoi(argv[2]);
        unsigned int val = parse_hex(argv[3]);

        if (ch < 0 || ch > 3) {
            printf("Error: Channel must be 0-3\n");
            return;
        }

        timer_set_compare(ch, val);
        printf("Channel %d compare value set to %u (0x%08X)\n", ch, val, val);

    } else if (strcmp(subcmd, "start") == 0) {
        if (argc < 3) {
            printf("Usage: timer start <channel>\n");
            return;
        }

        int ch = cli_atoi(argv[2]);
        if (ch < 0 || ch > 3) {
            printf("Error: Channel must be 0-3\n");
            return;
        }

        timer_enable_channel(ch, 1);
        timer_set_auto_reload(ch, 1);
        printf("Channel %d started (auto-reload enabled)\n", ch);

    } else if (strcmp(subcmd, "stop") == 0) {
        if (argc < 3) {
            printf("Usage: timer stop <channel>\n");
            return;
        }

        int ch = cli_atoi(argv[2]);
        if (ch < 0 || ch > 3) {
            printf("Error: Channel must be 0-3\n");
            return;
        }

        timer_enable_channel(ch, 0);
        printf("Channel %d stopped\n", ch);

    } else if (strcmp(subcmd, "pwm") == 0) {
        if (argc < 4) {
            printf("Usage: timer pwm <channel> <duty>\n");
            printf("  duty: 0-255 (0=0%%, 128=50%%, 255=100%%)\n");
            return;
        }

        int ch = cli_atoi(argv[2]);
        int duty = cli_atoi(argv[3]);

        if (ch < 0 || ch > 3) {
            printf("Error: Channel must be 0-3\n");
            return;
        }
        if (duty < 0 || duty > 255) {
            printf("Error: Duty must be 0-255\n");
            return;
        }

        timer_set_pwm_mode(ch, 1);
        timer_set_compare(ch, 255);
        timer_set_output(ch, duty);
        timer_set_auto_reload(ch, 1);
        timer_enable_channel(ch, 1);

        printf("Channel %d PWM: %d/255 (%d%%)\n", ch, duty, (duty * 100) / 255);

    } else if (strcmp(subcmd, "status") == 0) {
        int ch = -1;
        if (argc >= 3) {
            ch = cli_atoi(argv[2]);
            if (ch < 0 || ch > 3) {
                printf("Error: Channel must be 0-3\n");
                return;
            }
        }

        printf("Timer Status:\n");
        printf("  Prescale: %d\n", timer_get_prescale());
        printf("  Interrupt Status: 0x%02X\n", TIMER_INT_STATUS);
        printf("  Interrupt Enable: 0x%02X\n", TIMER_INT_ENABLE);
        printf("\n");

        int start = (ch >= 0) ? ch : 0;
        int end = (ch >= 0) ? ch : 3;

        for (int i = start; i <= end; i++) {
            unsigned char ctrl = TIMER_CH_CTRL(i);
            unsigned int counter = timer_get_counter(i);
            unsigned int compare = timer_get_compare(i);
            unsigned char output = timer_get_output(i);

            printf("Channel %d:\n", i);
            printf("  CTRL:    0x%02X ", ctrl);
            if (ctrl & TIMER_CTRL_ENABLE) printf("[EN] ");
            if (ctrl & TIMER_CTRL_PWM_MODE) printf("[PWM] ");
            if (ctrl & TIMER_CTRL_AUTO_RELOAD) printf("[AUTO] ");
            if (ctrl & TIMER_CTRL_INT_ENABLE) printf("[INT] ");
            printf("\n");
            printf("  Counter: %u (0x%08X)\n", counter, counter);
            printf("  Compare: %u (0x%08X)\n", compare, compare);
            printf("  Output:  %u (%d%%)\n", output, (output * 100) / 255);
            printf("\n");
        }

    } else if (strcmp(subcmd, "prescale") == 0) {
        if (argc < 3) {
            printf("Current prescale: %d\n", timer_get_prescale());
            return;
        }

        int val = cli_atoi(argv[2]);
        if (val < 1 || val > 255) {
            printf("Error: Prescale must be 1-255\n");
            return;
        }

        timer_set_prescale(val);
        printf("Prescale set to %d\n", val);

    } else {
        printf("Error: Unknown subcommand '%s'\n", subcmd);
        printf("Type 'timer' for usage\n");
    }
}
