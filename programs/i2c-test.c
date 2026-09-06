/* **************************************************************************
 *             RISC-V Emulator - I2C Test Program - Simplified
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
 * I2C Test Program - Simplified
 */

extern void printf(const char *fmt, ...);

#include "i2c.h"

void print_test(const char *name, int passed) {
    printf("%s: %s\n", name, passed ? "PASS" : "FAIL");
}

int main(void) {
    printf("\n=== I2C Controller Test Program ===\n\n");

    /* Test 1: Init */
    printf("=== Test 1: I2C Initialization ===\n");
    i2c_init();
    print_test("I2C initialized", 1);

    /* Test 2: Scan */
    printf("\n=== Test 2: I2C Bus Scan ===\n");
    int found = 0;
    for (unsigned char addr = 1; addr < 128; addr++) {
        if (i2c_start(addr << 1)) {
            printf("Found device at 0x%x\n", addr);
            found++;
        }
        i2c_stop();
    }
    printf("Found %d devices\n", found);
    print_test("Found 3 devices", found == 3);

    /* Test 3: Temperature sensor */
    printf("\n=== Test 3: Temperature Sensor ===\n");
    i2c_start(I2C_ADDR_TEMP << 1);
    i2c_write(0x00);
    i2c_restart((I2C_ADDR_TEMP << 1) | I2C_READ);
    unsigned char msb = i2c_read_ack();
    unsigned char lsb = i2c_read_nack();
    i2c_stop();
    printf("Temperature raw: MSB=0x%x LSB=0x%x\n", msb, lsb);
    print_test("Temperature read", msb == 0x01 && lsb == 0x90);

    /* Test 4: EEPROM write/read */
    printf("\n=== Test 4: EEPROM Write/Read ===\n");
    i2c_start(I2C_ADDR_EEPROM << 1);
    i2c_write(0x10);  /* Address */
    i2c_write(0xAB);  /* Data */
    i2c_stop();

    i2c_start(I2C_ADDR_EEPROM << 1);
    i2c_write(0x10);
    i2c_restart((I2C_ADDR_EEPROM << 1) | I2C_READ);
    unsigned char data = i2c_read_nack();
    i2c_stop();
    printf("Wrote 0xAB, read 0x%x\n", data);
    print_test("EEPROM write/read", data == 0xAB);

    printf("\n=== I2C Tests Complete ===\n");
    return 0;
}
