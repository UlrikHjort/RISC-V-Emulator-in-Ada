/* **************************************************************************
 *               RISC-V Emulator - I2C Sensor Monitoring Demo
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
 * I2C Sensor Monitoring Demo
 *
 * Demonstrates real-world peripheral integration:
 * - I2C: Read temperature sensor and accelerometer
 * - Timer: Control sampling rate (updates every second)
 * - UART: Display sensor data continuously
 * - GPIO: LED heartbeat indicator
 *
 * This simulates a typical embedded sensor monitoring application.
 */

extern void printf(const char *fmt, ...);

#include "i2c.h"
#include "timer.h"
#include "gpio.h"

/* Sampling configuration */
#define SAMPLE_INTERVAL  1000000  /* Timer ticks for ~1 second */
#define HEARTBEAT_PIN    0        /* GPIO pin for LED heartbeat */

/* Sensor readings */
typedef struct {
    int temp_celsius;     /* Temperature in 0.01degC units */
    short accel_x;
    short accel_y;
    short accel_z;
    unsigned int samples;
    unsigned int errors;
} sensor_data_t;

static sensor_data_t data = {0};

/**
 * Read temperature from TMP102 sensor
 * Returns temperature in 0.01degC units (e.g., 2534 = 25.34degC)
 */
static int read_temperature(void) {
    /* Start I2C transaction */
    if (!i2c_start(I2C_ADDR_TEMP << 1)) {
        return -27315;  /* Error: return absolute zero */
    }

    /* Select temperature register */
    i2c_write(0x00);

    /* Restart for read */
    i2c_restart((I2C_ADDR_TEMP << 1) | I2C_READ);

    /* Read 2 bytes */
    unsigned char msb = i2c_read_ack();
    unsigned char lsb = i2c_read_nack();
    i2c_stop();

    /* TMP102 format: 12-bit left-justified, 0.0625degC resolution */
    int temp_raw = (msb << 4) | (lsb >> 4);

    /* Sign extend if negative */
    if (temp_raw & 0x800) {
        temp_raw |= 0xF000;
    }

    /* Convert to 0.01degC units: temp_raw * 0.0625 * 100 = temp_raw * 6.25 */
    return (temp_raw * 625) / 100;
}

/**
 * Read accelerometer data from ADXL345
 */
static int read_accelerometer(short *x, short *y, short *z) {
    /* Start I2C transaction */
    if (!i2c_start(I2C_ADDR_ACCEL << 1)) {
        return 0;  /* Error */
    }

    /* Select DATAX0 register (0x32) */
    i2c_write(0x32);

    /* Restart for multi-byte read */
    i2c_restart((I2C_ADDR_ACCEL << 1) | I2C_READ);

    /* Read 6 bytes (X, Y, Z each 2 bytes) */
    unsigned char x0 = i2c_read_ack();
    unsigned char x1 = i2c_read_ack();
    unsigned char y0 = i2c_read_ack();
    unsigned char y1 = i2c_read_ack();
    unsigned char z0 = i2c_read_ack();
    unsigned char z1 = i2c_read_nack();
    i2c_stop();

    /* Combine bytes (little-endian) */
    *x = (short)((x1 << 8) | x0);
    *y = (short)((y1 << 8) | y0);
    *z = (short)((z1 << 8) | z0);

    return 1;  /* Success */
}

/**
 * Update sensor readings
 */
static void sample_sensors(void) {
    /* Read temperature */
    data.temp_celsius = read_temperature();

    /* Read accelerometer */
    if (!read_accelerometer(&data.accel_x, &data.accel_y, &data.accel_z)) {
        data.errors++;
    }

    data.samples++;
}

/**
 * Display sensor data in a nice format
 */
static void display_data(void) {
    /* Clear screen and move cursor to top */
    printf("\033[2J\033[H");

    /* Header */
    printf("====================================\n");
    printf("   I2C Sensor Monitoring Demo\n");
    printf("====================================\n\n");

    /* Temperature */
    printf("Temperature Sensor (TMP102):\n");
    printf("  Address: 0x%02X\n", I2C_ADDR_TEMP);
    printf("  Value:   %d.%02d degC\n",
           data.temp_celsius / 100,
           data.temp_celsius % 100);
    printf("\n");

    /* Accelerometer */
    printf("Accelerometer (ADXL345):\n");
    printf("  Address: 0x%02X\n", I2C_ADDR_ACCEL);
    printf("  X-axis:  %6d\n", data.accel_x);
    printf("  Y-axis:  %6d\n", data.accel_y);
    printf("  Z-axis:  %6d\n", data.accel_z);
    printf("\n");

    /* Statistics */
    printf("Statistics:\n");
    printf("  Samples: %u\n", data.samples);
    printf("  Errors:  %u\n", data.errors);
    printf("  Uptime:  %u seconds\n", data.samples);
    printf("\n");

    /* Timer status */
    unsigned int counter = timer_get_counter(0);
    unsigned int compare = timer_get_compare(0);
    unsigned int progress = (counter * 100) / compare;

    printf("Next sample in: %u%%\n", 100 - progress);
    printf("====================================\n");
}

/**
 * Initialize all peripherals
 */
static void init_peripherals(void) {
    printf("Initializing peripherals...\n");

    /* Initialize I2C */
    i2c_init();
    printf("  I2C: OK (100 kHz standard mode)\n");

    /* Initialize GPIO for heartbeat LED */
    gpio_set_direction(HEARTBEAT_PIN, GPIO_DIR_OUTPUT);
    gpio_write_pin(HEARTBEAT_PIN, GPIO_LOW);
    printf("  GPIO: OK (pin %d output)\n", HEARTBEAT_PIN);

    /* Initialize timer for 1-second sampling */
    timer_init();
    timer_set_prescale(100);  /* Slow down timer */
    timer_set_counter(0, 0);
    timer_set_compare(0, SAMPLE_INTERVAL);
    timer_set_auto_reload(0, 1);
    timer_enable_interrupt(0, 1);
    timer_enable_channel(0, 1);
    printf("  Timer: OK (channel 0, %u ticks)\n", SAMPLE_INTERVAL);

    /* Verify I2C devices */
    printf("\nScanning I2C bus...\n");
    int temp_ok = i2c_start(I2C_ADDR_TEMP << 1);
    i2c_stop();
    printf("  Temperature sensor (0x%02X): %s\n",
           I2C_ADDR_TEMP, temp_ok ? "FOUND" : "NOT FOUND");

    int accel_ok = i2c_start(I2C_ADDR_ACCEL << 1);
    i2c_stop();
    printf("  Accelerometer (0x%02X):      %s\n",
           I2C_ADDR_ACCEL, accel_ok ? "FOUND" : "NOT FOUND");

    if (!temp_ok || !accel_ok) {
        printf("\nWarning: Some sensors not responding!\n");
    }

    printf("\nStarting continuous monitoring...\n");
    printf("Press Ctrl+C to stop\n\n");

    /* Small delay before starting */
    for (volatile int i = 0; i < 1000000; i++);
}

/**
 * Main monitoring loop
 */
int main(void) {
    printf("\n");
    printf("====================================\n");
    printf("  I2C Sensor Monitoring Demo\n");
    printf("====================================\n\n");

    /* Initialize all peripherals */
    init_peripherals();

    /* Initial sample */
    sample_sensors();
    display_data();

    /* Main monitoring loop */
    while (1) {
        /* Check if timer has elapsed */
        if (timer_get_interrupt(0)) {
            /* Clear interrupt */
            timer_clear_interrupt(0);

            /* Toggle heartbeat LED */
            gpio_toggle_pin(HEARTBEAT_PIN);

            /* Sample sensors */
            sample_sensors();

            /* Display updated data */
            display_data();
        }

        /* Small delay to avoid busy-wait consuming all CPU */
        for (volatile int i = 0; i < 1000; i++);
    }

    return 0;
}
